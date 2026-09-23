--!strict
-- Facet control implementations construct directly into the Compose UI host.
-- This is a domain-constructor vocabulary, not a second state or mount runtime.
local Compose = require("../vendor/compose/core")
local blueprint = require("../blueprint")
local button = require("../controls/button")
local progress = require("../controls/progress_view")
local toggle = require("../controls/toggle")
local textInput = require("../controls/text_input")
local specGuard = require("../spec_guard")
local controls = {}

function controls.new(runtime: any, core: any, presenter: any, surfaces: any?)
	local UI = table.clone(blueprint) :: any
	for name in blueprint.schema.all() do
		local constructor = runtime.create(name)
		UI[name] = function(spec)
			local props = table.clone(spec or {})
			local label = props.id
			props.id = nil
			if props.children then
				for _, child in props.children do
					table.insert(props, child)
				end
				props.children = nil
			end
			return if label then constructor(label)(props) else constructor(props)
		end
	end
	local scrollPrimitive = UI.ScrollView
	UI.ScrollView = function(spec)
		local props = table.clone(spec)
		local config = props.navigation
		props.navigation = nil
		local navigation = require("../controls/scroll_navigation")
		if config then
			navigation.validate(config)
		end
		local node = scrollPrimitive(props)
		if config then
			local owner = Compose.currentOwner()
			local saved = table.clone(config)
			saved.targets = table.freeze(table.clone(config.targets or {}))
			node.meta = table.freeze({ scrollNavigation = table.freeze(saved) })
			node = navigation.attach(owner, node)
		end
		return node
	end
	UI.isReadable = Compose.isReadable
	-- A region's disclosure shows a copy of its richest form on a surface the
	-- region opens for itself, mounted through the application where there is one.
	local regionPrimitive = UI.Region
	local function mountSurface(component: any, present: any, options: any)
		local target = runtime.target()
		local stop = runtime.mount(component, target)
		local ok, handle = pcall(present, runtime.root(target, stop), options)
		if not ok then
			stop()
			error(handle, 0)
		end
		return handle
	end
	local regionNative = {
		make = function(built)
			return regionPrimitive(built)
		end,
		clone = function(form)
			return if type(form) == "table" then runtime.clone(form) else form
		end,
		contribution = function(bundle)
			local native = table.clone(bundle)
			native.bindPresent = function(presentModal, dismiss, presentAnchored)
				bundle.bindPresent(
					function(component, options)
						if surfaces and surfaces.modal then
							return surfaces.modal(component, options)
						end
						return mountSurface(component, presentModal, options)
					end,
					dismiss,
					function(component, options)
						if surfaces and surfaces.anchored then
							return surfaces.anchored(component, options)
						end
						return presentAnchored(component, options, function(build, presentOptions, presentSurface)
							return mountSurface(function()
								return build(UI)
							end, presentSurface, presentOptions)
						end)
					end
				)
			end
			return native
		end,
	}
	UI.Region = function(spec)
		return blueprint.regionWith(UI, spec, regionNative)
	end
	-- A composition is ruled on where it is written: its regions are all present.
	local compositionPrimitive = UI.Composition
	UI.Composition = function(spec)
		return runtime.validate(compositionPrimitive(spec))
	end
	local regionTransitions = require("./region_transitions")
	-- An ANONYMOUS region is legal. Compose's constructor takes either a name or
	-- the props table, and `ctor(nil)` is neither: it refuses with
	-- "expects a props table", which names the wrong mistake.
	local function named(ctor: any, id: any): any
		return if id ~= nil then ctor(id) else ctor
	end
	UI.When = function(spec)
		local region = runtime.create("When")
		if spec.transition ~= nil then
			return regionTransitions.when(region, spec)
		end
		return named(region, spec.id)({
			Compose.show(
				spec.condition,
				function()
					return region("then")({ spec.thenView() })
				end,
				if spec.elseView
					then function()
						return region("else")({ spec.elseView() })
					end
					else nil
			),
		})
	end

	UI.ErrorBoundary = function(spec)
		local region = runtime.create("ErrorBoundary")
		return named(region, spec.id)({ Compose.boundary(spec.view, spec.fallback) })
	end
	UI.ForEach = function(spec)
		-- Compose owns row identity and lifetime. A path segment distinguishes
		-- rows without adding a layout node for each collection slot.
		local region = runtime.create("ForEach")
		-- `key` is a function or the name of the field that holds the identity;
		-- both paths below want the function.
		local keyOf = specGuard.keyFunction("UI.ForEach", spec.key)
		if keyOf ~= spec.key then
			spec = table.clone(spec)
			spec.key = keyOf
		end
		if spec.transition ~= nil then
			return regionTransitions.forEach(region, spec)
		end
		return named(region, spec.id)({
			Compose.keyed({
				from = spec.items,
				key = keyOf,
				render = function(item, _, key)
					local node = spec.row(item:peek(), nil, item)
					node.collectionKey = `[{key}]`
					return node
				end,
			}),
		})
	end

	local modifiers = {
		"containerRelativeFrame",
		"frame",
		"padding",
		"offset",
		"aspectRatio",
		"alignment",
		"corners",
		"shadow",
		"gradient",
		"stroke",
	}
	for _, name in modifiers do
		UI[name] = function(node, ...)
			-- Normalize only the modifier's writes. Even an equal-value write must
			-- replace a previous binding on that property. The node's meta rides
			-- along: a chrome-slot hint decides what a gradient may paint.
			local normalized = blueprint[name]({ class = node.class, props = {}, meta = node.meta }, ...)
			runtime.decorate(node, normalized.props)
			return node
		end
	end
	-- Drag declarations ride the node's meta, where the renderer reads them.
	for _, name in { "draggable", "dropTarget" } do
		UI[name] = function(node, spec)
			assert(node.parent == nil, `Facet {name}: declare drag behaviour before mounting the node`)
			node.meta = blueprint[name]({ class = node.class, meta = node.meta }, spec).meta
			return node
		end
	end
	-- Sensory declarations ride the node's meta, where the scene reads them.
	UI.sensoryFeedback = function(node, spec)
		assert(
			type(node) ~= "table" or node.parent == nil,
			"Facet sensoryFeedback: declare feedback before mounting the node"
		)
		node.meta = blueprint.sensoryFeedback(
			if type(node) == "table" then { class = node.class, meta = node.meta } else node,
			spec
		).meta
		return node
	end
	-- An activation gate rides the node's meta, where the presenter's one
	-- Activate dispatch reads it — so all four input sources honour it.
	UI.activationGate = function(node, spec)
		assert(node.parent == nil, "Facet activationGate: declare the gate before mounting the node")
		node.meta = blueprint.activationGate({ class = node.class, meta = node.meta }, spec).meta
		return node
	end
	-- A focus section rides the node's meta too, where the focus map reads it.
	UI.focusSection = function(node, spec)
		assert(node.parent == nil, "Facet focusSection: declare the section before mounting the node")
		node.meta = blueprint.focusSection({ class = node.class, meta = node.meta }, spec).meta
		return node
	end
	-- One modifier set, normalized once per node and written to each of them.
	UI.styleGroup = function(spec, nodes, style)
		assert(type(nodes) == "table", "Facet UI.styleGroup: expected a list of nodes second")
		local shells = {}
		for index, node in nodes do
			shells[index] = { class = node.class, props = {}, meta = node.meta }
		end
		for index, normalized in blueprint.styleGroup(spec, shells, style) do
			runtime.decorate(nodes[index], normalized.props)
		end
		return nodes
	end
	for _, name in { "background", "overlay" } do
		UI[name] = function(base, content, align)
			assert(base.parent == nil and content.parent == nil, `Facet {name}: layer nodes before mounting them`)
			if name == "background" then
				local fill = { type = "fill", weight = 1 }
				local dimensions = {}
				if content.props.width == nil then
					dimensions.width = fill
				end
				if content.props.height == nil then
					dimensions.height = fill
				end
				runtime.decorate(content, dimensions)
			end
			local wrapper = UI.ZStack({
				id = base.id .. "+" .. name,
				width = base.props.width,
				height = base.props.height,
				alignH = align,
				if name == "background" then content else base,
				if name == "background" then base else content,
			})
			-- The wrapper follows the base's dimensions, including future bound
			-- writes. An explicit dimension on the wrapper overrides that axis.
			wrapper.dimensionSource = base
			wrapper.inheritedDimensions = { width = true, height = true }
			base.dimensionFollowers = base.dimensionFollowers or {}
			base.dimensionFollowers[wrapper] = true
			return wrapper
		end
	end
	local library: any = { UI = UI, Controls = {}, surfaces = surfaces, runtime = runtime, presenter = presenter }
	library.Controls.ProgressView = function(controlCore, spec)
		return progress.build(library, controlCore, spec)
	end
	local api = setmetatable({}, { __index = runtime.constructors })
	library.nativeControls = api
	for _, name in modifiers do
		api[name] = UI[name]
	end
	api.background = UI.background
	api.overlay = UI.overlay
	--[[ `UI.ForEach`/`UI.When` dispatch on `spec.transition` (Compose.keyed/
		Compose.show underneath, `../render/region_transitions.luau` when a
		transition is declared) but that dispatch lives only on the INTERNAL
		`UI` a native control's `build(library, core, spec)` receives —
		`app.controls.ForEach`/`.When` fell through the `runtime.constructors`
		metatable to the bare structural-node constructor instead, which does
		nothing with `items`/`condition`/`transition` at all. An app that hand-
		rolls its OWN `Compose.keyed`/`Compose.show` (every reference app's own
		`forEach`/`when` helper, passing the built node as an ordinary child)
		never touches this and keeps working unchanged; only a caller that
		passes the SCHEMA shape (`items`/`condition`) — the one shape a
		hand-rolled child can never accidentally produce — opts into the same
		dispatch a native control gets, so a declared `transition` finally
		reaches the coordinator from app code too.

		THE NAME IS NOT PART OF THE SHAPE. A region may be anonymous, so the two
		forms are told apart by the SPEC KEY alone and an anonymous schema-shaped
		spec dispatches exactly like a named one. A key that belongs to NEITHER
		form — not a numeric child, not a declared prop of the region class — is a
		typo, and it says so rather than building a structural node that quietly
		does nothing with it. ]]
	local REGION_SHAPES = {
		ForEach = "{ items = <cell or formula>, key = <function or field name>, row = <function> }",
		When = "{ condition = <cell or formula>, thenView = <function>, elseView = <function>? }",
	}
	for _, name in { "ForEach", "When" } do
		local raw = runtime.constructors[name]
		local domain = UI[name]
		local schemaKey = if name == "ForEach" then "items" else "condition"
		local shape = REGION_SHAPES[name]
		-- the raw form still carries the class's own props (`transition`, and
		-- `id` when the caller spells it in the table rather than in the name)
		local declared = blueprint.schema.forClass(name).props
		local function dispatch(props: any, id: string?): any
			if type(props) ~= "table" then
				error(`Facet UI.{name}: expected {shape}, or a table of numeric children (got {typeof(props)}).`, 0)
			end
			if props[schemaKey] ~= nil then
				local spec = table.clone(props)
				spec.id = id or spec.id
				return domain(spec)
			end
			for key in props do
				if type(key) ~= "number" and key ~= "id" and declared[key] == nil then
					error(
						`Facet UI.{name}: \`{tostring(key)}\` is neither a numeric child nor a declared prop. `
							.. `Pass {shape} — or numeric children plus the class's own props, for a region you `
							.. `drive with your own Compose.show/Compose.keyed.`,
						0
					)
				end
			end
			return if id ~= nil then raw(id)(props) else raw(props)
		end
		api[name] = function(first: any)
			if type(first) == "string" then
				return function(props: any)
					return dispatch(props, first)
				end
			end
			return dispatch(first, nil)
		end
	end
	for _, name in { "fill", "hug", "cornersData", "shadowData", "gradientData", "strokeData", "sortedEntries" } do
		api[name] = blueprint[name]
	end
	-- A focus section rides the container's metadata, where the focus map reads it.
	api.focusSection = UI.focusSection
	-- "this subtree takes one activation to become active", for every source.
	api.activationGate = UI.activationGate
	-- Drag declarations ride the node's metadata, where the renderer reads them.
	api.draggable = UI.draggable
	api.dropTarget = UI.dropTarget
	api.sensoryFeedback = UI.sensoryFeedback
	-- A surface's top bar: a Back verb, a one-line title, then trailing nodes.
	api.navBar = function(spec)
		return require("../present/nav_bar").build(spec, UI)
	end
	api.styleGroup = UI.styleGroup
	-- A region's children are its forms, richest first; a composition's are its
	-- regions. Both are ruled on as declarations, so they are built whole.
	for _, kind in { "Region", "Composition" } do
		api[kind] = function(name)
			assert(type(name) == "string", `Facet UI.{kind} needs a name: UI.{kind}("Name")(\{ ... })`)
			return function(props)
				assert(type(props) == "table", `Facet {kind}: expected a property table`)
				local spec, kids = {}, {}
				for key, value in props do
					if type(key) == "number" then
						kids[key] = value
					else
						spec[key] = value
					end
				end
				assert(spec.id == nil and spec.children == nil, "use one constructor name and numeric children")
				spec.id = name
				spec.children = kids
				return UI[kind](spec)
			end
		end
	end
	api.ScrollView = function(spec)
		if type(spec) == "string" then
			return function(props)
				local named = table.clone(props)
				assert(named.id == nil, "use one constructor name")
				named.id = spec
				return UI.ScrollView(named)
			end
		end
		return UI.ScrollView(spec)
	end
	api.Stage = require("./compose_stage").new(runtime.create("Stage"))
	local serial = 0
	local function composite(name: string, build: (any, any, any) -> any)
		local function construct(spec, label)
			assert(type(spec) == "table", `Facet {name}: expected a property table`)
			serial += 1
			local supplied = table.clone(spec)
			assert(label == nil or supplied.id == nil, "use one constructor name")
			supplied.id = label or supplied.id or `{name}#{serial}`
			if #supplied > 0 then
				assert(supplied.children == nil, "use numeric children, not both child spellings")
				supplied.children = table.move(supplied, 1, #supplied, 1, {})
				for i = 1, #supplied do
					supplied[i] = nil
				end
			end
			-- `ref` receives the control's `{ api, dump }` when the control is built.
			-- A control that publishes its verbs on its own record (the virtual
			-- list and grid) is its own `api`.
			local ref = supplied.ref
			supplied.ref = nil
			assert(ref == nil or type(ref) == "function", `Facet {name}: ref must be a function`)
			local built = build(library, core, supplied)
			if built.dispose then
				Compose.cleanup(built.dispose)
			end
			if ref then
				local api = built.api
				if api == nil then
					-- A flat record is its own verb set. Construction products stay
					-- private: the blueprint is mounted and `dispose` belongs to the
					-- owner above.
					api = {}
					for key, value in built do
						if key ~= "blueprint" and key ~= "dispose" then
							api[key] = value
						end
					end
					table.freeze(api)
				end
				ref(table.freeze({ api = api, dump = built.dump }))
			end
			return built.blueprint
		end
		return function(spec)
			if type(spec) == "string" then
				return function(props)
					return construct(props, spec)
				end
			end
			return construct(spec, nil)
		end
	end
	api.VirtualList = composite("VirtualList", require("../controls/virtual_list").build)
	api.VirtualGrid = composite("VirtualGrid", require("../controls/virtual_grid").build)
	api.Button = composite("Button", button.build)
	api.ShortcutHint = composite("ShortcutHint", require("../controls/shortcut_hint").build)
	api.Label = composite("Label", require("../controls/label").build)
	api.Stepper = composite("Stepper", require("../controls/stepper").build)
	api.Slider = composite("Slider", require("../controls/slider").build)
	api.Rating = composite("Rating", require("../controls/rating").build)
	api.LevelPicker = composite("LevelPicker", require("../controls/level_picker").build)
	api.Picker = composite("Picker", require("../controls/picker").build)
	api.DisclosureGroup = composite("DisclosureGroup", require("../controls/disclosure_group").build)
	api.CollapsibleView = composite("CollapsibleView", require("../controls/collapsible_view").build)
	api.Menu = composite("Menu", require("../controls/menu").build)
	api.PopupButton = composite("PopupButton", require("../controls/picker_menu").build)
	api.SplitButton = composite("SplitButton", require("../controls/split_button").build)
	api.RadialMenu = composite("RadialMenu", require("../controls/radial_menu").build)
	api.Alert = composite("Alert", require("../controls/alert").build)
	api.Callout = composite("Callout", require("../controls/callout").build)
	api.Popover = composite("Popover", require("../controls/popover").build)
	api.Dialog = composite("Dialog", require("../controls/dialog").build)
	api.Notice = composite("Notice", require("../controls/notice").build)
	api.Card = composite("Card", require("../controls/card").build)
	api.Pagination = composite("Pagination", require("../controls/pagination").build)
	api.StepIndicator = composite("StepIndicator", require("../controls/step_indicator").build)
	api.Snackbar = composite("Snackbar", require("../controls/snackbar").build)
	api.NavBar = composite("NavBar", require("../present/nav_bar").buildControl)
	api.Sheet = composite("Sheet", require("../controls/sheet").build)
	api.NavigationStack = composite("NavigationStack", require("../controls/navigation_stack").build)
	api.AsyncImage = composite("AsyncImage", require("../controls/async_image").build)
	api.ComboBox = composite("ComboBox", require("../controls/combo_box").build)
	api.PageView = composite("PageView", require("../controls/page_view").build)
	api.RowActions = composite("RowActions", require("../controls/row_actions").build)
	api.Table = composite("Table", require("../controls/table").build)
	api.TabView = composite("TabView", require("../controls/tab_view").build)
	api.Badge = composite("Badge", require("../controls/badge").build)
	api.StatusIndicator = composite("StatusIndicator", require("../controls/status_indicator").build)
	api.Skeleton = composite("Skeleton", require("../controls/skeleton").build)
	api.Avatar = composite("Avatar", require("../controls/avatar").build)
	api.AvatarGroup = composite("AvatarGroup", require("../controls/avatar_group").build)
	api.Chip = composite("Chip", require("../controls/chip").build)
	api.Toggle = composite("Toggle", toggle.build)
	api.TextInput = composite("TextInput", textInput.build)
	api.NumberInput = composite("NumberInput", textInput.buildNumber)
	api.ProgressView = composite("ProgressView", progress.build)
	return api, UI, library
end
return controls
