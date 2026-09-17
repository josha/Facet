--!strict
-- A component is a deferred description. Only mount supplies an owner and core.
local blueprint = require("./blueprint")
local contract = require("./core/contract")
local tracking = require("./core/tracking")
local guard = require("./spec_guard")
local motionTypes = require("./motion/motion")
local normalizeChildren = require("./blueprint_children")
local authoring = {}
export type AnimationSpec = blueprint.AnimationSpec
export type Animated = { animation: AnimationSpec? }
export type Children = { [number]: blueprint.Blueprint, children: { blueprint.Blueprint }? }
export type Read<T> = () -> T
export type Write<T> = (T | ((T) -> T)) -> ()
export type Context = {
	state: <T>(initial: T) -> (Read<T>, Write<T>),
	read: <T>(source: contract.Readable<T>) -> Read<T>,
	memo: <T>(compute: Read<T>) -> Read<T>,
	animate: (source: Read<number>, preset: string, opts: motionTypes.ValueOpts?) -> Read<number>,
	withAnimation: (preset: string, run: () -> ()) -> (),
	watch: <T>(source: Read<T>, callback: (T) -> (), opts: { immediate: boolean? }?) -> () -> (),
	effect: (run: () -> (() -> ())?) -> () -> (),
	own: <T>(resource: T) -> T,
	batch: (run: () -> ()) -> (),
	untrack: <T>(read: Read<T>) -> T,
	env: (key: string) -> Read<any>,
}
local function getter(source: any): any
	local read = function()
		return source._read(tracking.current())
	end
	tracking.sources[read] = source
	return read
end
local function result(ok: boolean, value: any): any
	if not ok then
		error(value, 0)
	end
	return value
end
local bind = tracking.bind
function authoring.context(core: any, scope: any, services: any): Context
	local ui: any = {}
	local function active()
		assert(not scope:isDisposed(), "Facet: this component has unmounted")
	end
	local function own(value)
		active()
		return scope:own(value)
	end
	ui.own = own
	ui.read = getter
	ui.state = function(initial)
		active()
		local signal = own(core:signal(initial))
		return getter(signal),
			function(value)
				signal:set(if type(value) == "function" then value(signal:get()) else value)
			end
	end
	ui.memo = function(compute)
		active()
		return getter(own(core:memo(function()
			return compute(tracking.current())
		end)))
	end
	ui.animate = function(read, preset, opts)
		active()
		assert(services and services.presenter, "Facet: ui.animate requires a presenter")
		local motion = own(services.presenter.motionClock:animate(bind(core, scope, read), preset, opts))
		return getter(motion)
	end
	ui.withAnimation = function(preset, run)
		active()
		assert(services and services.presenter, "Facet: ui.withAnimation requires a presenter")
		services.presenter.withAnimation(preset, run)
	end
	ui.batch = function(run)
		core:transaction(run)
	end
	ui.untrack = function(read)
		return result(tracking.run(nil, read))
	end
	ui.env = function(key)
		assert(services and services.env, "Facet: ui.env requires an environment at mount")
		return getter(services.env:get(key))
	end
	ui.watch = function(read, callback, opts)
		guard.assertKnownKeys("ui.watch", opts, { immediate = true }, "opts")
		local owned = scope:child("watch")
		local source = bind(core, owned, read)
		owned:own(core:observe(source, function(value)
			result(tracking.run(nil, callback, value))
		end))
		if opts and opts.immediate then
			result(tracking.run(nil, callback, source:get()))
		end
		return function()
			if not owned:isDisposed() then
				owned:dispose()
			end
		end
	end
	ui.effect = function(run)
		active()
		local cleanup, disposed = nil, false
		local function clean()
			local previous = cleanup
			cleanup = nil
			if previous then
				result(tracking.run(nil, previous))
			end
		end
		local stop = core:effect(function()
			local cleanOk, cleanError = pcall(clean :: any)
			local returned = run(tracking.current())
			assert(
				returned == nil or type(returned) == "function",
				"Facet: an effect may return only a cleanup function"
			)
			cleanup = returned
			if disposed or scope:isDisposed() then
				clean()
			end
			if not cleanOk then
				error(cleanError, 0)
			end
		end)
		return own(function()
			if disposed then
				return
			end
			disposed = true
			stop()
			clean()
		end)
	end
	return table.freeze(ui)
end
local function deferred(id: string?, build: any, component: boolean?): blueprint.Blueprint
	return table.freeze({
		class = "Component",
		id = id,
		props = table.freeze({}),
		meta = table.freeze({ build = build, component = component }),
	}) :: any
end
function authoring.component<P>(setup: (Context, P) -> blueprint.Blueprint): (P) -> blueprint.Blueprint
	assert(type(setup) == "function", "Facet.component expects a setup function")
	return function(props: P): blueprint.Blueprint
		if type(props) == "table" then
			local normalized = table.clone(normalizeChildren(props))
			if normalized.children then
				normalized.children = table.freeze(table.clone(normalized.children))
			end
			props = table.freeze(normalized) :: any
		end
		return deferred(nil, function(core, scope, services)
			local ui = authoring.context(core, scope, services)
			local view = setup(ui, props)
			assert(
				type(view) == "table" and type(view.class) == "string" and type(view.props) == "table",
				"Facet: a component must return a blueprint"
			)
			return view
		end, true)
	end
end

-- Explicit property vocabulary: callbacks (including factories and formatters)
-- are never classified by arity, nor treated as reactive just because callable.
local REACTIVE = guard.keySet({
	"label",
	"subtitle",
	"text",
	"title",
	"message",
	"enabled",
	"disabled",
	"busy",
	"selected",
	"value",
	"mixed",
	"options",
	"items",
	"width",
	"height",
	"role",
	"icon",
	"description",
	"progress",
	"isPresented",
	"query",
	"invalid",
	"placeholder",
	"transition",
	"rows",
	"columns",
	"gap",
	"rowGap",
	"expanded",
	"selection",
	"detent",
	"textSize",
	"sidebarPreference",
	"shoulderNavigation",
	"dimmed",
	"image",
	"viewportExtent",
	"viewportHeight",
	"estimatedItemExtent",
	"valueAlignment",
	"sizing",
	"sizeClass",
	"axis",
	"interactionClasses",
	"clearance",
	"ringWidth",
})
local ENV = guard.keySet({
	"Picker",
	"ComboBox",
	"SplitButton",
	"Alert",
	"Sheet",
	"TabView",
	"VirtualList",
	"VirtualGrid",
	"NavigationStack",
	"RadialMenu",
	"RowActions",
	"LevelPicker",
	"Rating",
	"TextInput",
	"Menu",
	"CollapsibleView",
	"Table",
})
local WRITABLE = {
	Toggle = { value = "onChange", mixed = "onMixedChange" },
	Slider = { value = "onChange" },
	Stepper = { value = "onChange" },
	Rating = { value = "onChange" },
	LevelPicker = { value = "onChange" },
	TextInput = { value = "onChange" },
	Chip = { selected = "onToggle" },
	Picker = { selected = "onChange", query = "onQueryChange" },
	ComboBox = { value = "onChange", text = "onTextChange" },
	Alert = { isPresented = "onPresentedChange" },
	DisclosureGroup = { expanded = "onChange" },
	CollapsibleView = { expanded = "onChange" },
	PageView = { selection = "onChange" },
	TabView = { selection = "onChange" },
	Sheet = { detent = "onDetentChange", isPresented = "onPresentedChange" },
}
local function controlSpec(core: any, scope: any, name: string, spec: any, legacy: boolean?): any
	local normalized = table.clone(normalizeChildren(spec))
	for key, value in normalized do
		if
			REACTIVE[key :: string]
			and type(value) == "function"
			and not (legacy and name == "Alert" and (key == "title" or key == "message"))
		then
			local source = bind(core, scope, value)
			local change = WRITABLE[name] and WRITABLE[name][key]
			if change then
				local callback = normalized[change]
				assert(type(callback) == "function", `Facet View.{name}: a {key} getter requires {change}`)
				local proxy: any = table.clone(source)
				proxy.kind = "signal"
				proxy.set = function(_, nextValue)
					callback(nextValue)
				end
				proxy.dispose = function() end
				normalized[key] = proxy
				normalized[change] = nil
			else
				normalized[key] = source
			end
		end
	end
	return normalized
end
-- The lower-level handle API accepts the same Bound property vocabulary.
-- Ordinary specs keep their allocation-free forwarding path; a recipe owns
-- only the bindings it adds and disposes them with the existing control handle.
function authoring.control<T>(name: string, build: (any, any, any) -> T, Facet: any, core: any, spec: any): T
	local recipes = false
	for key, value in spec do
		if
			REACTIVE[key]
			and type(value) == "function"
			and not (name == "Alert" and (key == "title" or key == "message"))
		then
			recipes = true
			break
		end
	end
	if not recipes then
		return build(Facet, core, spec)
	end
	local scope = core:scope("control-recipes")
	local ok, result = pcall(function()
		local normalized = controlSpec(core, scope, name, spec, true)
		local control: any = build(Facet, core, normalized)
		if name == "AsyncImage" then
			-- AsyncImage attaches its resource lease and memos to the supplied
			-- owner and returns a readback, not a disposable control handle.
			normalized.scope:own(scope)
			return control
		end
		scope:own(control)
		local owned = table.clone(control)
		owned.dispose = function()
			scope:dispose()
		end
		return owned
	end)
	if not ok then
		scope:dispose()
		error(result, 0)
	end
	return result :: any
end

local function collectionKey(key: any): any
	if type(key) == "string" then
		assert(key ~= "", "Facet: collection key field cannot be empty")
		return function(item)
			return item[key]
		end
	end
	assert(type(key) == "function", "Facet: collection key must be a field name or function")
	return key
end
function authoring.views(Facet: any): any
	local View = table.clone(blueprint)
	for name, constructor in Facet.Controls do
		View[name] = function(spec)
			assert(type(spec) == "table", `Facet View.{name} expects a spec table`)
			local snapshot = table.freeze(table.clone(normalizeChildren(spec)))
			return deferred(spec.id, function(core, scope, services)
				local normalized = controlSpec(core, scope, name, snapshot)
				local animation = normalized.animation
				normalized.animation = nil
				assert(
					animation == nil or (name ~= "Alert" and name ~= "Sheet"),
					`Facet View.{name}: animate the modal content; the presentation binding owns its transition`
				)
				if name == "AsyncImage" or name == "ProgressView" then
					normalized.scope = normalized.scope or scope
				end
				if name == "ProgressView" and services and services.presenter then
					normalized.motionClock = normalized.motionClock or services.presenter.motionClock
				end
				if name == "VirtualList" or name == "VirtualGrid" then
					assert(normalized.cell == nil, "Facet View collections use row, not cell")
					normalized.key = collectionKey(normalized.key)
					local row = normalized.row
					assert(type(row) == "function", "Facet View collections require row(itemGetter)")
					normalized.row = nil
					if name == "VirtualList" then
						assert(normalized.rows == nil, "Facet View.VirtualList uses items, not rows")
						normalized.rows, normalized.items = normalized.items, nil
					end
					normalized.viewportExtent = normalized.viewportExtent or "auto"
					normalized.cell = function(_, ctx)
						return row(function()
							return ctx.current(function(source)
								return source._read(tracking.current())
							end)
						end)
					end
				end
				if normalized.env == nil and services then
					-- Only constructors declaring env receive it.
					if ENV[name] then
						normalized.env = services.env
					end
				end
				if name == "Button" and normalized.confirm then
					assert(services and services.presenter, "Facet: Button.confirm requires a presenter")
					local confirm = normalized.confirm
					guard.assertKnownKeys(
						"View.Button.confirm",
						confirm,
						{ title = true, message = true, acceptLabel = true, cancelLabel = true, destructive = true },
						"spec"
					)
					local activate = normalized.onActivate
					normalized.confirm = nil
					local original
					local alert = scope:own(Facet.Controls.Alert(core, {
						title = if type(confirm.title) == "function"
							then bind(core, scope, confirm.title)
							else confirm.title,
						message = if type(confirm.message) == "function"
							then bind(core, scope, confirm.message)
							else confirm.message,
						env = services.env,
						actions = {
							{ id = "Cancel", label = confirm.cancelLabel or "Cancel", role = "cancel" },
							{
								id = "Confirm",
								label = confirm.acceptLabel or "Confirm",
								role = if confirm.destructive then "destructive" else "default",
								onActivate = function()
									activate(original)
								end,
							},
						},
					}))
					normalized.onActivate = function(meta)
						if not alert.dump().presented then
							original = meta
							alert.present(services.presenter)
						end
					end
				end
				if (name == "Alert" or name == "Sheet") and services then
					normalized.presenter = normalized.presenter or services.presenter
				end
				local control = constructor(core, normalized)
				if name ~= "AsyncImage" then
					scope:own(control)
				end
				if name == "Alert" or name == "Sheet" then
					assert(
						normalized.isPresented ~= nil
							or (name == "Alert" and (normalized.item ~= nil or normalized.error ~= nil)),
						`Facet View.{name} requires a presentation binding`
					)
					-- The control owns its modal. An empty structural region contributes
					-- no layout box or gap in the declaring component.
					return blueprint.ForEach({
						id = spec.id,
						items = scope:own(core:signal({})),
						key = function(item)
							return item
						end,
						row = function()
							error("empty modal region")
						end,
					})
				end
				if animation then
					local bp = table.clone(control.blueprint)
					local props = table.clone(bp.props)
					local classSpec = blueprint.schema.forClass(bp.class)
					assert(classSpec)
					local valid, why = blueprint.schema.checkValue(classSpec.props.animation, animation)
					assert(valid, `Facet View.{name}.animation: {why or "invalid policy"}`)
					for key in animation do
						assert(key == "layout" or classSpec.props[key], `Facet View.{name} cannot animate {key}`)
					end
					props.animation = table.freeze(table.clone(animation))
					bp.props = table.freeze(props)
					return table.freeze(bp)
				end
				return control.blueprint
			end)
		end
	end
	View.When = function(spec: any)
		spec = table.clone(normalizeChildren(spec))
		if spec.children then
			assert(spec.thenView == nil, "Facet View.When: use children or thenView, not both")
			assert(#spec.children == 1, "Facet View.When requires one child; group multiple children in a layout")
			local child = spec.children[1]
			spec.children = nil
			spec.thenView = function()
				return child
			end
		end
		return deferred(spec.id, function(core, scope)
			local props = table.clone(spec)
			if type(props.condition) == "function" then
				props.condition = bind(core, scope, props.condition)
			end
			return blueprint.When(props)
		end)
	end
	View.ForEach = function(spec)
		return deferred(spec.id, function(core, scope)
			local props = table.clone(spec)
			props.key = collectionKey(props.key)
			if type(props.items) == "function" then
				props.items = bind(core, scope, props.items)
			end
			local row = props.row
			props.row = function(item)
				return row(getter(item))
			end
			local bp = table.clone(blueprint.ForEach(props))
			bp.meta = { currentItem = true }
			return table.freeze(bp)
		end)
	end
	-- A modifier targets the eventual root, retaining its original validation.
	for _, name in
		{
			"shadow",
			"gradient",
			"corners",
			"stroke",
			"focusSection",
			"draggable",
			"dropTarget",
			"sensoryFeedback",
			"frame",
			"padding",
			"offset",
			"containerRelativeFrame",
			"aspectRatio",
			"alignment",
			"overlay",
			"background",
		}
	do
		local modify = blueprint[name]
		View[name] = function(bp, ...)
			local args = table.pack(...)
			local enabledRecipe = name == "draggable"
				and type(args[1]) == "table"
				and type(args[1].enabled) == "function"
			if not (bp.meta and bp.meta.build) and not enabledRecipe then
				return modify(bp, ...)
			end
			if enabledRecipe then
				args[1] = table.freeze(table.clone(args[1]))
			end
			return deferred(bp.id, function(core, scope, services)
				local resolved = bp
				while resolved.meta and resolved.meta.build do
					resolved = resolved.meta.build(core, scope, services)
				end
				if enabledRecipe then
					local spec = table.clone(args[1])
					spec.enabled = bind(core, scope, spec.enabled)
					return modify(resolved, spec)
				end
				return modify(resolved, table.unpack(args, 1, args.n))
			end)
		end
	end
	View.styleGroup = function(spec, blueprints, style)
		blueprint.styleGroup(spec, {}, style)
		local styled = {}
		for index, bp in blueprints do
			styled[index] = if bp.meta and bp.meta.build
				then deferred(bp.id, function(core, scope, services)
					local resolved = bp
					while resolved.meta and resolved.meta.build do
						resolved = resolved.meta.build(core, scope, services)
					end
					return blueprint.styleGroup(spec, { resolved }, style)[1]
				end)
				else blueprint.styleGroup(spec, { bp }, style)[1]
		end
		return styled
	end
	return table.freeze(View)
end
return authoring
