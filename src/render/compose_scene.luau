--!strict
-- Facet's domain host for Compose. The host owns UI validation, identity,
-- inherited styling and renderer invalidation. Compose owns the node lifetime,
-- bindings and structural operations. No second reactive graph or tree builder.
local Compose = require("../vendor/compose/core")
local blueprint = require("../blueprint")
local schema = require("../blueprint_schema")
local primitiveProperties = require("../primitive_properties")
local richText = require("../layout/rich_text")
local inheritance = require("./inheritance")
local validateButton = require("../button_properties")
local feedback = require("../present/feedback")
local observeChange = require("../core/on_change")
local motionClock = require("../motion/clock")
local scene = {}
local roots: any = setmetatable({}, { __mode = "k" })
function scene.isRoot(value: any): boolean
	return roots[value] == true
end
local STRUCTURAL = { ForEach = true, When = true, ErrorBoundary = true }
local STACK = { VStack = true, HStack = true, ScrollView = true }

function scene.new(frames: any?)
	local nextId = 0
	local targets: any = setmetatable({}, { __mode = "k" })
	local function mark(node: any, class: string, prop: string?)
		local journal = node.journal
		if not journal or not node.path then
			return
		end
		journal.sequence += 1
		table.insert(journal.pending, {
			path = node.path,
			class = class,
			prop = prop,
			-- WHOSE WRITE THIS IS (`motion/clock.isCommitting`): a motion's own commit
			-- is already an animation, and the declarative layout session must not
			-- wrap it in a second one.
			origin = if motionClock.isCommitting() then "motion" else nil,
		})
	end
	local function cascade(node: any, inherited: inheritance.Inherit?)
		local outgoing, disabled, tint, same = inheritance.apply(node, inherited)
		if disabled then
			mark(node, "paint", "enabled")
			mark(node, "semantics", "enabled")
			mark(node, "navigation", "enabled")
		end
		if tint then
			mark(node, "paint", "tint")
		end
		if not same then
			for _, child in node.children do
				cascade(child, outgoing)
			end
		end
	end
	-- Change-form sensory declarations observe their trigger only while the
	-- surface has somewhere to report, and stop with the node.
	local function listen(node: any, declarations: any)
		local journal = node.journal
		if node.feedbackStops or not journal or not journal.feedback then
			return
		end
		local stops = {}
		node.feedbackStops = stops
		for _, declaration in declarations do
			if declaration.trigger ~= nil then
				table.insert(
					stops,
					journal.observe(declaration.trigger, function()
						local sink = node.journal and node.journal.feedback
						if sink then
							-- a fresh event each time: the surface stamps itself onto it
							sink({ type = declaration.event, path = node.path })
						end
					end)
				)
			end
		end
	end
	local function attach(node: any, parent: any)
		node.parent = parent
		-- Build detached subtrees without walking their descendants at each
		-- nesting level. Mounting into a surface assigns paths and inheritance once.
		if not parent.journal and not node.journal then
			return
		end
		if node.journal ~= parent.journal then
			if node.journal then
				node.journal.mounted -= 1
			end
			if parent.journal then
				parent.journal.mounted += 1
				parent.journal.created += 1
			end
		end
		node.journal = parent.journal
		local prefix = if node.collectionKey then node.collectionKey .. "/" else ""
		node.path = (parent.path or "") .. "/" .. prefix .. node.id
		-- A row is a ForEach item root spliced into a stack. Regions thread the
		-- fact down to it; no other stack child carries it.
		local region = STRUCTURAL[parent.class]
		if STRUCTURAL[node.class] then
			node.inStack = STACK[parent.class] or (region and parent.inStack) or nil
			node.rowRegion = (node.inStack and node.class == "ForEach") or (region and parent.rowRegion) or nil
		else
			node.inStack = (region and parent.rowRegion) or nil
		end
		inheritance.apply(node, parent.inheritOut)
		-- An activation sensation is heard by everything beneath its declaration.
		local declarations = if node.meta ~= nil then feedback.readDeclarations(node) else nil
		node.activationFeedback = feedback.activationIn(declarations) or parent.activationFeedback
		if declarations then
			listen(node, declarations)
		end
		for _, child in node.children do
			attach(child, node)
		end
	end
	-- Names the node in a property error: its mounted path, else its authored name.
	local function where(node: any): string
		if node.path then
			return ` (at {node.path})`
		end
		return if node.named then ` (at '{node.id}')` else ""
	end
	local function changed(parent: any)
		parent.childrenVersion += 1
		mark(parent, "structure", nil)
	end
	local function property(node: any, key: string, value: any, inherited: boolean?, clearing: boolean?)
		local definition = node.schema.props[key]
		if not definition then
			-- A capability the class declines is named as refused, with the spelling that works.
			local refusal = schema.refusal(node.class, key)
			if refusal ~= nil then
				error(
					`Facet UI.{node.class}: '{key}' is REFUSED on UI.{node.class}, not missing. {refusal}{where(node)}`,
					0
				)
			end
			local message = `Facet UI.{node.class}: unknown property '{key}'.`
			local suggestions = schema.suggest(node.class, key)
			if #suggestions > 0 then
				message ..= ` Did you mean '{table.concat(suggestions, "', '")}'?`
			end
			error(`{message} Valid properties: {table.concat(schema.propNames(node.class), ", ")}.{where(node)}`, 0)
		end
		if definition.deprecated then
			error(`Facet {node.class}.{key} is not supported; use {definition.deprecated.replacement}{where(node)}`, 0)
		end
		local valid, detail = true, nil
		if
			(
				primitiveProperties.direct[node.class]
				or node.class == "ScrollView"
				or node.validated
				or type(blueprint[node.class]) ~= "function"
			)
			and not clearing
			and (value ~= nil or definition.required)
		then
			valid, detail = schema.checkValue(definition, value)
		end
		if not valid then
			error(`Facet {node.class}.{key}: {detail or "invalid value"}{where(node)}`, 0)
		end
		if not inherited and node.inheritedDimensions then
			node.inheritedDimensions[key] = nil
		end
		if node.dynamicProps and node.dynamicProps[key] ~= nil then
			primitiveProperties.assertBoundValue(node.class, key, definition, value)
		end
		if node.validated and key == "text" and node.props.rich == true and type(value) == "string" then
			value = richText.normalizeFontSizes(value)
		end
		local old = node.props[key]
		node.props[key] = value
		if old == value then
			return
		end
		if (key == "width" or key == "height") and node.dimensionFollowers then
			for follower in node.dimensionFollowers do
				if not follower.destroyed and follower.inheritedDimensions[key] then
					property(follower, key, value, true)
				end
			end
		end
		if node.journal then
			local baseline = key == "lineAlign"
				and (
					old == "firstTextBaseline"
					or old == "lastTextBaseline"
					or value == "firstTextBaseline"
					or value == "lastTextBaseline"
				)
			for _, class in ipairs(blueprint.PROP_DIRTY[node.class][key] or { "paint" }) do
				mark(node, if baseline and class == "arrange" then "measure" else class, key)
			end
		end
		if key == "enabled" or key == "tint" then
			cascade(node, node.parent and node.parent.inheritOut)
		end
	end
	local function validate(node: any)
		if STRUCTURAL[node.class] then
			return
		end
		if node.prevalidated then
			node.prevalidated = nil
			return
		end
		local definition = assert(node.schema, `Facet: '{node.class}' has no property schema`)
		-- The UI vocabulary owns cross-property rules and normalization (for
		-- example clipping and button content). Run it once after Compose has
		-- assigned initial properties; binding updates use the property schema.
		local constructor = blueprint[node.class]
		if primitiveProperties.direct[node.class] then
			primitiveProperties.normalize(node.class, node.props, definition.props, node.dynamicProps)
			if node.class == "Button" then
				validateButton(node.props, node.children)
			end
		elseif type(constructor) == "function" then
			local spec = table.clone(node.props)
			spec.id = node.id
			if definition.container then
				spec.children = node.children
			end
			local normalized = constructor(spec)
			node.props = table.clone(normalized.props)
		else
			for name, prop in definition.props do
				if prop.required and node.props[name] == nil then
					error(`Facet {node.class}.{name} is required{where(node)}`, 0)
				end
			end
		end
		node.validated = true
	end

	local render = {
		createNode = function(kind: string)
			local definition = schema.forClass(kind)
			if not STRUCTURAL[kind] and not definition then
				error(`Facet: unknown UI node '{kind}'`, 0)
			end
			nextId += 1
			return {
				class = kind,
				schema = definition,
				id = `{kind}#{nextId}`,
				props = {},
				children = {},
				childrenVersion = 0,
				factoryRuns = 1,
			}
		end,
		setProperty = property,
		clearProperty = function(node: any, key: string)
			property(node, key, nil, false, true)
		end,
		insertChild = function(parent: any, child: any, index: number?)
			if not targets[parent] and not STRUCTURAL[parent.class] and not parent.schema.container then
				error(`Facet {parent.class}: a leaf cannot contain children`, 0)
			end
			validate(child)
			for _, sibling in parent.children do
				if sibling.id == child.id and sibling.collectionKey == child.collectionKey then
					error(`Facet: duplicate child name '{child.id}'`, 0)
				end
			end
			table.insert(parent.children, index or (#parent.children + 1), child)
			attach(child, parent)
			changed(parent)
		end,
		moveChild = function(parent: any, child: any, index: number)
			local previous = assert(table.find(parent.children, child), "Facet: moving an unattached child")
			table.remove(parent.children, previous)
			table.insert(parent.children, index, child)
			changed(parent)
		end,
		removeChild = function(parent: any, child: any)
			local index = table.find(parent.children, child)
			if index then
				table.remove(parent.children, index)
				changed(parent)
			end
			child.parent = nil
		end,
		destroyNode = function(node: any)
			if node.destroyed then
				return
			end
			node.destroyed = true
			if node.feedbackStops then
				for _, stop in node.feedbackStops do
					stop()
				end
				node.feedbackStops = nil
			end
			if node.dimensionSource then
				if node.dimensionSource.dimensionFollowers then
					node.dimensionSource.dimensionFollowers[node] = nil
				end
				node.dimensionSource = nil
			end
			node.dimensionFollowers = nil
			if node.journal then
				node.journal.mounted -= 1
			end
			node.parent = nil
			node.journal = nil
		end,
	}
	local runtime = Compose.createRuntime({
		name = "Facet UI",
		render = render,
		frames = frames,
		naming = {
			setName = function(node: any, name: string)
				assert(type(name) == "string" and name ~= "", "Facet: a node name cannot be empty")
				assert(node.parent == nil, "Facet: name a node before attaching it")
				node.id = name
				node.named = true
			end,
		},
		events = {
			classifyKey = function(node: any, key: string)
				local definition = node.schema.props[key]
				return if definition
						and not definition.reactive
						and string.sub(key, 1, 2) == "on"
					then "event"
					else "property"
			end,
			connectEvent = function(node: any, key: string, handler: any)
				property(node, key, handler)
				return function()
					if node.props[key] == handler then
						node.props[key] = nil
					end
				end
			end,
		},
	})
	-- A property the schema marks `reactive = false` is read once. Compose
	-- would bind a readable there silently, so the constructor refuses it.
	local createNode = runtime.create
	local function refuseBound(kind: string, definition: any, props: any)
		if type(props) ~= "table" then
			return
		end
		for key, value in props do
			-- Children ride numeric keys; property functions and readables both bind.
			local prop = if type(key) == "string" then definition.props[key] else nil
			if
				prop
				and prop.reactive == false
				and (
					Compose.isReadable(value) or (type(value) == "function" and not table.find(prop.types, "function"))
				)
			then
				error(
					`Facet UI.{kind}.{key} does not accept a Compose cell or formula, or a property function (it is read once at mount). `
						.. `Pass a plain value, or rebuild the subtree through UI.When/UI.ForEach.`,
					0
				)
			end
		end
	end
	-- A bound property is a fact the renderer reads when it creates the node: a
	-- container with a bound placement is a coordinate space.
	local function noteBound(node: any, definition: any, props: any): any
		if type(props) == "table" then
			for key, value in props do
				-- children ride the numeric keys; only a bindable value can be bound
				local kind = type(value)
				if type(key) == "string" and (kind == "function" or kind == "table") then
					local prop = definition.props[key]
					if prop and prop.reactive == true and (kind == "function" or Compose.isReadable(value)) then
						local bound = node.dynamicProps
						if bound == nil then
							bound = {}
							node.dynamicProps = bound
						end
						bound[key] = value
					end
				end
			end
		end
		return node
	end
	-- A node's recipe is the props table it was built from; its class is its kind.
	local NO_PROPS = table.freeze({})
	local function create(kind: string)
		local constructor = createNode(kind)
		local definition = schema.forClass(kind)
		if not definition then
			return function(first: any)
				if type(first) == "string" then
					local named = constructor(first)
					return function(props: any)
						local node = named(props)
						node.recipe = props or NO_PROPS
						return node
					end
				end
				local node = constructor(first)
				node.recipe = first or NO_PROPS
				return node
			end
		end
		-- A CROSS-PROPERTY REFUSAL IS A CONSTRUCTION ERROR, and this is the first
		-- moment it can be asked: Compose assigns one property at a time, so the
		-- PAIR only exists once the node is built. `assertCombinations` writes
		-- nothing (see `primitive_properties`), so `validate` asking it again at
		-- mount changes nothing.
		local function finish(node: any, props: any): any
			node.recipe = props or NO_PROPS
			for key in node.dynamicProps or {} do
				primitiveProperties.assertBoundValue(kind, key, definition.props[key], node.props[key])
			end
			primitiveProperties.assertCombinations(kind, node.props, node.dynamicProps)
			return node
		end
		return function(first: any)
			if type(first) == "string" then
				local named = constructor(first)
				return function(props: any)
					refuseBound(kind, definition, props)
					return finish(noteBound(named(props), definition, props), props)
				end
			end
			refuseBound(kind, definition, first)
			return finish(noteBound(constructor(first), definition, first), first)
		end
	end
	runtime.create = create
	-- A node remembers what built it, so a second surface can show a copy of a
	-- live subtree: same name, properties, bindings, handlers and metadata,
	-- rebuilt under the calling owner. Structural children rebuild themselves.
	local decorateNode = runtime.decorate
	runtime.decorate = function(node: any, props: any)
		if node.recipe then
			node.recipeDecor = node.recipeDecor or {}
			table.insert(node.recipeDecor, props)
		end
		return decorateNode(node, props)
	end
	local function clone(node: any, copies: any): any
		local recipe = assert(node.recipe, `Facet: '{node.id}' cannot be copied onto a second surface`)
		local props = {}
		for key, value in recipe do
			if type(key) == "number" and type(value) == "table" and value.recipe then
				props[key] = clone(value, copies)
			else
				props[key] = value
			end
		end
		local copy = create(node.class)(props)
		copy.id = node.id
		copy.named = node.named
		for _, extra in node.recipeDecor or {} do
			runtime.decorate(copy, extra)
		end
		copy.meta = node.meta
		copy.collectionKey = node.collectionKey
		copies[node] = copy
		local source = node.dimensionSource and copies[node.dimensionSource]
		if source then
			copy.dimensionSource = source
			copy.inheritedDimensions = table.clone(node.inheritedDimensions)
			source.dimensionFollowers = source.dimensionFollowers or {}
			source.dimensionFollowers[copy] = true
		end
		return copy
	end
	-- Rules a finished declaration at the call site instead of at insertion.
	runtime.validate = function(node: any)
		validate(node)
		node.prevalidated = true
		return node
	end
	runtime.clone = function(node: any)
		return clone(node, {})
	end
	runtime.constructors = setmetatable({}, {
		__index = function(self: any, kind: string)
			local constructor = create(kind)
			rawset(self, kind, constructor)
			return constructor
		end,
	})
	local watcher
	local function observeDefault(source: any, onChanged: () -> ()): () -> ()
		watcher = watcher or Compose.createOwner(runtime.reactor)
		return observeChange(watcher, source, onChanged)
	end
	local function target()
		local journal: any = { pending = {}, sequence = 0, mounted = 0, created = 0 }
		local container = { children = {}, childrenVersion = 0, journal = journal }
		targets[container] = true
		return container
	end
	local function root(container: any, dispose: () -> ())
		assert(targets[container] and #container.children == 1, "Facet: a surface needs exactly one root")
		local journal = container.journal
		local mounted = {
			node = container.children[1],
			dispose = dispose,
			takeDirty = function()
				local pending = journal.pending
				journal.pending = {}
				return pending
			end,
			dirtySeq = function()
				return journal.sequence
			end,
			dirtySince = function(sequence: number)
				local count = journal.sequence - sequence
				return if count >= 0 and count <= #journal.pending
					then table.move(journal.pending, #journal.pending - count + 1, #journal.pending, 1, {})
					else nil
			end,
			counters = function()
				return { mounted = journal.mounted, factoryRuns = journal.created }
			end,
			-- Where this surface's sensory declarations report. `observe` watches a
			-- trigger for a change and answers its stop.
			setFeedback = function(sink: (event: any) -> (), observe: any?)
				journal.feedback = sink
				journal.observe = observe or observeDefault
				local function walk(node: any)
					local declarations = if node.meta ~= nil then feedback.readDeclarations(node) else nil
					if declarations then
						listen(node, declarations)
					end
					for _, child in node.children do
						walk(child)
					end
				end
				walk(container.children[1])
			end,
		}
		roots[mounted] = true
		return mounted
	end
	-- A control that opens a surface of its own mounts it through these.
	runtime.target = target
	runtime.root = root
	return { runtime = runtime, target = target, root = root }
end
return scene
