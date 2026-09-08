--!strict
-- Caller-owned route state, one keyed current page, and branch-owned content.
-- navBar owns chrome; the presenter owns Cancel ordering, focus and transitions.
-- Pages are rebuilt on return. Keep durable form/data state in the caller's model.
local guard = require("../spec_guard")
local contribution = require("../input/contribution")
local coreContract = require("../core/contract")
local blueprintLib = require("../blueprint")
local environment = require("../env/environment")
local navigation = {}
export type Entry = { id: string, value: any? }
export type Destination = {
	title: blueprintLib.Bound<string>?,
	content: (scope: coreContract.Scope, entry: Entry?) -> blueprintLib.Blueprint,
}
export type Spec = {
	id: string?,
	path: coreContract.Signal<{ Entry }>,
	root: Destination,
	destinations: { [string]: Destination },
	backLabel: string,
	env: environment.Env?,
	transition: blueprintLib.TransitionSpec?,
}
local KEYS = guard.keySet({ "id", "path", "root", "destinations", "backLabel", "env", "transition" })
local PAGE_KEYS = guard.keySet({ "title", "content" })
local ENTRY_KEYS = guard.keySet({ "id", "value" })
local function fail(message: string)
	error("Facet Controls.NavigationStack: " .. message, 0)
end
local function prefix(root: string?, path: string?): boolean
	return root ~= nil and path ~= nil and (path == root or path:sub(1, #root + 1) == root .. "/")
end
function navigation.build(Facet: any, core: any, spec: Spec)
	guard.assertKnownKeys("Controls.NavigationStack", spec, KEYS, "spec")
	if type(spec) ~= "table" then
		fail("spec must be a table")
	end
	local UI = Facet.UI
	local id = spec.id or "NavigationStack"
	if type(id) ~= "string" or id == "" then
		fail("id must be a non-empty string")
	end
	if
		type(spec.path) ~= "table"
		or spec.path.kind ~= "signal"
		or type(spec.path.set) ~= "function"
		or type(spec.path.get) ~= "function"
	then
		fail("path must be a caller-owned settable Signal<array<Entry>>")
	end
	if type(spec.backLabel) ~= "string" or spec.backLabel == "" then
		fail("backLabel must be a non-empty localized string")
	end
	if spec.env ~= nil and (type(spec.env) ~= "table" or type(spec.env.get) ~= "function") then
		fail("env must be a Facet environment")
	end
	local function page(value: any, where: string): Destination
		if type(value) ~= "table" then
			fail(where .. " must be a destination spec")
		end
		guard.assertKnownKeys("Controls.NavigationStack." .. where, value, PAGE_KEYS, "spec")
		if type(value.content) ~= "function" then
			fail(where .. ".content must be a function(scope, entry)")
		end
		if value.title ~= nil and type(value.title) ~= "string" and not UI.isReadable(value.title) then
			fail(where .. ".title must be a string or Readable<string>")
		end
		if UI.isReadable(value.title) and type(value.title:get()) ~= "string" then
			fail(where .. ".title must read a string")
		end
		return table.freeze({ title = value.title, content = value.content })
	end
	local root = page(spec.root, "root")
	if type(spec.destinations) ~= "table" then
		fail("destinations must be a route-id map")
	end
	local destinations = {}
	for route, definition in spec.destinations do
		if type(route) ~= "string" or route == "" then
			fail("destination ids must be non-empty strings")
		end
		destinations[route] = page(definition, "destinations." .. route)
	end
	local function entry(value: any): Entry
		if type(value) ~= "table" then
			fail("each path entry must be {id, value?}")
		end
		guard.assertKnownKeys("Controls.NavigationStack entry", value, ENTRY_KEYS, "spec")
		if type(value.id) ~= "string" or destinations[value.id] == nil then
			fail("unknown destination id '" .. tostring(value.id) .. "'")
		end
		return table.freeze({ id = value.id, value = value.value })
	end
	local function path(value: any): { Entry }
		if type(value) ~= "table" then
			fail("path must contain an array of route entries")
		end
		local count = 0
		for key in value do
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #value then
				fail("path must be a dense array without extra keys")
			end
			count += 1
		end
		if count ~= #value then
			fail("path must be a dense array")
		end
		local copy = {}
		for _, route in value do
			table.insert(copy, entry(route))
		end
		return table.freeze(copy)
	end
	local accepted = path(spec.path:get())
	-- Validate the transition through its owning public constructor before scope allocation.
	if spec.transition ~= nil then
		if UI.isReadable(spec.transition) then
			fail("transition must be a static specification")
		end
		UI.ForEach({
			items = spec.path,
			key = function()
				return "validate"
			end,
			row = function()
				return UI.Box({})
			end,
			transition = spec.transition,
		})
	end
	local scope = core:scope("navigation-" .. id)
	-- A pure horizontal slide is navigation: both pages travel together, and
	-- Back reverses that travel. Other authored forms keep their own policy.
	local authored = spec.transition
	local forward = if authored then authored.enter else nil
	local horizontal = authored ~= nil
		and authored.fade ~= true
		and (forward == "slide-left" or forward == "slide-right")
		and (authored.exit == nil or authored.exit == (if forward == "slide-left" then "slide-right" else "slide-left"))
	local stackWidth = nil
	local transition = authored
	local pageTransition = nil
	if horizontal then
		local initial = table.clone(authored)
		initial.enter = "instant"
		initial.exit = forward
		pageTransition = scope:own(core:signal(initial))
		transition = pageTransition
	end
	local disposed, lastError, quarantined = false, nil, false
	local revision = 0
	local rootFrame = { key = "Page0", entry = nil, definition = root, depth = 0 }
	local frames = { rootFrame }
	local function frame(route: Entry, depth: number): any
		revision += 1
		return { key = "Page" .. revision, entry = route, definition = destinations[route.id], depth = depth }
	end
	for i, route in accepted do
		table.insert(frames, frame(route, i))
	end
	local current = frames[#frames]
	local items = scope:own(core:signal({ current }))
	local graph, pending = nil, nil
	local offFocus, offTick, inputScope = nil, nil, nil
	scope:own(function()
		if offFocus then
			offFocus()
		end
		if offTick then
			offTick()
		end
	end)
	local activeScopes = {}
	local livePages = 0
	local function capture()
		if graph then
			local focused = graph.focused:get()
			if prefix(current.path, focused) then
				current.focus = focused
			end
		end
	end
	local function restore()
		if disposed or graph == nil or pending == nil or pending ~= current or not current.appeared then
			return
		end
		-- onAppear precedes the presenter's map refresh. Wait for that map to contain
		-- this page; its focused signal changes when the old page's focus is removed.
		local map = graph.focusMap()
		if not map then
			return
		end
		local first = nil
		local existing = graph.focused:get()
		local existingLegal = false
		local existingAnywhere = false
		for _, item in map.traversal do
			existingAnywhere = existingAnywhere or (item.eligible and item.path == existing)
			if item.eligible and prefix(current.path, item.path) then
				first = first or item.path
				existingLegal = existingLegal or item.path == existing
			end
		end
		if first == nil then
			return
		end
		local target = current.focus
		pending = nil -- focusOn notifies synchronously; a retry cannot recurse.
		-- Respect presenter initialFocus and focus established by a nested control.
		if target == nil and (existingLegal or (current.depth == 0 and existingAnywhere)) then
			return
		end
		if target == nil or not graph.focusOn(target) then
			graph.focusOn(first)
		end
	end
	local function accept(nextPath: { Entry })
		capture()
		local common = 0
		for i, route in nextPath do
			local old = accepted[i]
			if old == nil or old.id ~= route.id or old.value ~= route.value then
				break
			end
			common = i
		end
		for i = #frames, common + 2, -1 do
			frames[i] = nil
		end
		for i = common + 1, #nextPath do
			table.insert(frames, frame(nextPath[i], i))
		end
		local backward = #nextPath < #accepted and common == #nextPath
		accepted = nextPath
		local nextFrame = frames[#frames]
		if nextFrame ~= current then
			current = nextFrame
			pending = current
			if pageTransition ~= nil then
				local travel = if backward
					then (if forward == "slide-left" then "slide-right" else "slide-left")
					else forward
				pageTransition:set({
					enter = if stackWidth == nil then "instant" else travel,
					exit = travel,
					class = authored.class,
					distance = authored.distance or stackWidth,
				})
			end
			items:set({ current })
		end
		quarantined = false
	end
	scope:own(core:observe(spec.path, function(value)
		if disposed then
			return
		end
		local ok, result = pcall(path, value)
		if not ok then
			lastError = tostring(result)
			quarantined = true
			return
		end
		accept(result)
	end))
	-- During a core transaction the observer has not published accepted yet.
	-- Compose verbs on the caller's current write; invalid external writes still
	-- fall back to the last validated path rather than poisoning an API action.
	local function mutationPath(): { Entry }
		local ok, result = pcall(path, spec.path:get())
		return if ok then result else accepted
	end
	local api = {}
	function api.push(value: Entry): boolean
		if disposed then
			return false
		end
		local valid = entry(value)
		local nextPath = table.clone(mutationPath())
		table.insert(nextPath, valid)
		spec.path:set(nextPath)
		return true
	end
	function api.pop(): boolean
		if disposed then
			return false
		end
		local nextPath = table.clone(mutationPath())
		if #nextPath == 0 then
			return false
		end
		table.remove(nextPath)
		spec.path:set(nextPath)
		return true
	end
	function api.popToRoot(): boolean
		if disposed or #mutationPath() == 0 then
			return false
		end
		spec.path:set({})
		return true
	end
	api.back = api.pop
	local spacing, titleSize = "m", "title"
	if spec.env ~= nil then
		spacing = scope:own(core:memo(function(use)
			return if use(spec.env:get("sizeClass")) == "compact" then "s" else "m"
		end))
		titleSize = scope:own(core:memo(function(use)
			return if use(spec.env:get("sizeClass")) == "compact" then "body" else "title"
		end))
	end
	local function row(item: any, itemScope: any): any
		livePages += 1
		itemScope:own(function()
			livePages -= 1
			item.appeared = false
		end)
		local contentScope = itemScope:child("navigation-content-" .. item.key)
		activeScopes[contentScope] = true
		contentScope:own(function()
			activeScopes[contentScope] = nil
		end)
		local function quarantine(err: any): any
			lastError = tostring(err)
			quarantined = true
			if not contentScope:isDisposed() then
				contentScope:dispose()
			end
			return UI.Box({ id = "Unavailable", width = UI.fill() })
		end
		local content = UI.ErrorBoundary({
			id = "Content",
			view = function()
				local bp = item.definition.content(contentScope, item.entry)
				if
					type(bp) ~= "table"
					or type(bp.class) ~= "string"
					or type(UI[bp.class]) ~= "function"
					or type(bp.props) ~= "table"
				then
					fail("content must return a UI blueprint")
				end
				return bp
			end,
			fallback = quarantine,
		})
		-- An untitled root is an existing shell: preserve its full content box.
		-- Destinations always have Back, even when their title is omitted.
		local hasChrome = item.depth > 0 or item.definition.title ~= nil
		local pageChildren = {}
		if hasChrome then
			table.insert(
				pageChildren,
				Facet.navBar({
					id = "NavBar",
					title = item.definition.title,
					titleSize = titleSize,
					titleWidth = UI.fill(),
					backLabel = spec.backLabel,
					onBack = if item.depth > 0
						then function()
							api.pop()
						end
						else nil,
				})
			)
		end
		table.insert(
			pageChildren,
			UI.VStack({ id = "BodyHost", width = UI.fill(), height = UI.fill(), children = { content } })
		)
		local pageBlueprint = UI.VStack({
			id = "Page",
			surface = if item.depth > 0 or horizontal then "base" else nil,
			width = UI.fill(),
			height = UI.fill(),
			gap = if hasChrome then spacing else 0,
			padding = if hasChrome then spacing else 0,
			onAppear = function(mountedPath: string)
				item.path = mountedPath
				item.appeared = true
				if item == current then
					pending = item
					restore()
				end
			end,
			children = pageChildren,
		})
		-- The shared transition authority requires one declared CanvasGroup for
		-- fading forms. Opt-in transitions compose the complete page through it.
		return if spec.transition ~= nil
			then UI.ZStack({
				id = "PageMotion",
				zIndex = item.depth,
				canvasGroup = true,
				width = UI.fill(),
				height = UI.fill(),
				children = { pageBlueprint },
			})
			else pageBlueprint
	end
	local blueprint = contribution.attach(
		UI.ZStack({
			id = id,
			clipChildren = true,
			width = UI.fill(),
			height = UI.fill(),
			children = {
				UI.ForEach({
					id = "Pages",
					items = items,
					key = function(item)
						return item.key
					end,
					row = row,
					transition = transition,
				}),
			},
		}),
		{
			syncGeometry = function(rectOf: any, node: any)
				local rect = if node then rectOf(node.path) else nil
				if rect and rect.w > 0 then
					stackWidth = rect.w
				end
			end,
			bindInputScope = function(delivery: any)
				if disposed or inputScope == delivery then
					return
				end
				if offTick then
					offTick()
				end
				inputScope = delivery
				-- A path write can leave focus on surviving shell chrome. In that
				-- case the map refresh changes no focused signal; retry on the
				-- presenter's existing tick, after the page has appeared.
				offTick = delivery.onTick(function()
					if pending then
						restore()
					end
				end)
				delivery.onDispose(function()
					if inputScope == delivery then
						if offTick then
							offTick()
						end
						offTick, inputScope = nil, nil
					end
				end)
			end,
			bindFocusGraph = function(focusGraph: any)
				if disposed then
					return
				end
				if graph ~= focusGraph then
					if offFocus then
						offFocus()
					end
					graph = focusGraph
					offFocus = core:observe(graph.focused, function()
						restore()
					end)
				end
				restore()
			end,
			handleCancel = function()
				return api.back()
			end,
		}
	)
	local function dump()
		return {
			schema = "facet-navigation-stack-dump/1",
			id = id,
			path = table.freeze(table.clone(accepted)),
			depth = #accepted,
			current = {
				id = if current.entry then current.entry.id else nil,
				key = current.key,
				value = if current.entry then current.entry.value else nil,
				path = current.path,
			},
			canGoBack = not disposed and #accepted > 0,
			livePages = livePages,
			disposed = disposed,
			quarantined = quarantined,
			lastError = lastError,
		}
	end
	local function dispose()
		if disposed then
			return
		end
		disposed = true
		pending = nil
		items:set({})
		for owned in activeScopes do
			if not owned:isDisposed() then
				owned:dispose()
			end
		end
		scope:dispose()
		graph = nil
	end
	return { blueprint = blueprint, api = table.freeze(api), dump = dump, dispose = dispose }
end
return navigation
