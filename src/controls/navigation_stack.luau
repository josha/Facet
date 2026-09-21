--!strict
-- Caller-owned route state, one keyed current page, and branch-owned content.
-- navBar owns chrome; the presenter owns Cancel ordering, focus and transitions.
-- Pages are rebuilt on return. Keep durable form/data state in the caller's model.
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local selection = require("../selection_model")
local guard = require("../spec_guard")
local contribution = require("../input/contribution")
local blueprintLib = require("../blueprint")
local transitionsLib = require("../render/transitions")
local regionTransitions = require("../render/region_transitions")
local motionClasses = require("../motion/classes")
local surfaceEnv = require("../env/surface_env")
local schema = require("../blueprint_schema")
local navigation = {}
local specTypes = require("../spec_types/navigation_stack")
export type Entry = specTypes.Entry
export type Destination = specTypes.Destination
export type Spec = specTypes.Spec
local KEYS = guard.keySet({ "id", "path", "root", "destinations", "backLabel", "env", "transition" })
local PAGE_KEYS = guard.keySet({ "title", "content" })
local ENTRY_KEYS = guard.keySet({ "id", "value" })
local function fail(message: string)
	error("Facet UI.NavigationStack: " .. message, 0)
end
-- Where a form travels, in screen space. An enter arrives against its travel;
-- an exit leaves along it. Forms without travel fade or swap in place.
local TRAVEL = {
	["slide-up"] = { x = 0, y = -1 },
	["slide-down"] = { x = 0, y = 1 },
	["slide-left"] = { x = -1, y = 0 },
	["slide-right"] = { x = 1, y = 0 },
}
local NUDGE = 24
local COORDINATED = { materialize = true, transform = true, reveal = true }
local REST = table.freeze({ x = 0, y = 0 })
local function prefix(root: string?, path: string?): boolean
	return root ~= nil and path ~= nil and (path == root or path:sub(1, #root + 1) == root .. "/")
end
local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.NavigationStack", spec, KEYS, "spec")
	if type(spec) ~= "table" then
		fail("spec must be a table")
	end
	local UI = Facet.UI
	local id = spec.id or "NavigationStack"
	if type(id) ~= "string" or id == "" then
		fail("id must be a non-empty string")
	end
	if not selection.isWritable(spec.path) then
		fail("path must be a writable Compose cell containing route entries")
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
		guard.assertKnownKeys("UI.NavigationStack." .. where, value, PAGE_KEYS, "spec")
		if type(value.content) ~= "function" then
			fail(where .. ".content must be a function(owner, entry)")
		end
		if value.title ~= nil and type(value.title) ~= "string" and not UI.isReadable(value.title) then
			fail(where .. ".title must be a string or Readable<string>")
		end
		if UI.isReadable(value.title) and type(value.title:peek()) ~= "string" then
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
		guard.assertKnownKeys("UI.NavigationStack entry", value, ENTRY_KEYS, "spec")
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
	local accepted = path(spec.path:peek())
	-- Validate the transition through its owning public constructor before scope allocation.
	if spec.transition ~= nil then
		if UI.isReadable(spec.transition) then
			fail("transition must be a static specification")
		end
		blueprintLib.ForEach({
			items = spec.path,
			key = function()
				return "validate"
			end,
			row = function()
				return blueprintLib.Box({})
			end,
			transition = spec.transition,
		})
	end
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
	-- A paired slide uses the same motion class for both pages. Otherwise
	-- the default exit class finishes sooner than the entering page.
	local pageClass = authored and (authored.class or transitionsLib.DEFAULT_CLASS)
	if horizontal then
		local initial = table.clone(authored)
		initial.enter = "instant"
		initial.exit = forward
		initial.class = pageClass
		initial.exitClass = authored.exitClass or pageClass
		pageTransition = Compose.cell(initial)
		transition = pageTransition
	end
	-- Native motion: each mounted page owns one place in [-1, 1]. 0 is rest,
	-- a positive place is the side it enters from, a negative one the side it
	-- leaves to. One retargeted tween per page keeps a reversal continuous.
	local motion = nil
	if authored ~= nil then
		local enter = authored.enter
		local exit = if horizontal then forward else authored.exit or schema.TRANSITION_MIRROR[enter]
		local fades = authored.fade == true
			or schema.TRANSITION_FADES[enter] == true
			or schema.TRANSITION_FADES[exit] == true
		local from, to = TRAVEL[enter], TRAVEL[exit]
		if COORDINATED[enter] or COORDINATED[exit] then
			-- These forms scale or clip the page, which the surface's transition
			-- coordinator writes.
			local declared = table.clone(authored)
			declared.exit = exit
			motion = {
				region = regionTransitions.motion(declared),
				declared = declared,
				fades = fades,
				clips = declared.enter == "reveal" or declared.exit == "reveal",
				enters = true,
				exits = true,
			}
		elseif fades or from ~= nil or to ~= nil then
			motion = {
				fades = fades,
				from = from,
				to = to,
				enters = fades or from ~= nil,
				exits = fades or to ~= nil,
				enterSeconds = motionClasses.resolve(pageClass).response,
				exitSeconds = motionClasses.resolve(
					authored.exitClass or (if horizontal then pageClass else transitionsLib.DEFAULT_EXIT_CLASS)
				).response,
				distance = Compose.cell(authored.distance or NUDGE),
				env = surfaceEnv.forSpec(core, spec.env),
			}
		end
	end
	local disposed, lastError, quarantined = false, nil, false
	local revision = 0
	local rootFrame = { key = "Page0", entry = nil, definition = root, depth = 0, done = Compose.cell(false) }
	local frames = { rootFrame }
	local function frame(route: Entry, depth: number): any
		revision += 1
		return {
			key = "Page" .. revision,
			entry = route,
			definition = destinations[route.id],
			depth = depth,
			done = Compose.cell(false),
		}
	end
	for i, route in accepted do
		table.insert(frames, frame(route, i))
	end
	local current = frames[#frames]
	-- With native motion the collection holds the current page plus every page
	-- still leaving; a finished exit prunes its entry.
	local mounted = { current }
	local top = Compose.cell(current)
	local items = Compose.cell(if motion == nil then table.clone(frames) else { current })
	local graph, pending = nil, nil
	local offFocus, offTick, inputScope = nil, nil, nil
	owner.own(function()
		if offFocus then
			offFocus()
		end
		if offTick then
			offTick()
		end
	end)
	local activeScopes = {}
	-- Counts every mounted page, including one still playing its exit.
	local livePages = 0
	local function capture()
		if graph then
			local focused = graph.focused:peek()
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
		local existing = graph.focused:peek()
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
			local leaving = current
			current = nextFrame
			pending = current
			if motion ~= nil then
				-- Back reverses a paired slide; every other form keeps its sides.
				local side = if horizontal and backward then -1 else 1
				local travels = motion.enters
				if horizontal then
					local distance = authored.distance or stackWidth
					travels = distance ~= nil
					motion.distance:set(distance or NUDGE)
				end
				if motion.region ~= nil then
					-- the leaving slot starts its own exit when `top` moves
					if not leaving.slotted then
						leaving.done:set(true)
					end
				elseif leaving.goal == nil or not motion.exits or (horizontal and not travels) then
					leaving.done:set(true)
				else
					leaving.goal:set(-side)
				end
				current.start = if travels then side else 0
				current.done:set(false)
				if current.goal ~= nil then
					current.goal:set(0)
				end
				if table.find(mounted, current) == nil then
					table.insert(mounted, current)
					table.sort(mounted, function(a, b)
						return a.depth < b.depth
					end)
				end
				top:set(current)
				items:set(table.clone(mounted))
			elseif pageTransition ~= nil then
				local travel = if backward
					then (if forward == "slide-left" then "slide-right" else "slide-left")
					else forward
				local page = table.clone(authored)
				page.enter = if stackWidth == nil then "instant" else travel
				page.exit = travel
				page.class = pageClass
				page.exitClass = authored.exitClass or pageClass
				page.distance = authored.distance or stackWidth
				pageTransition:set(page)
			end
			if motion == nil then
				items:set(table.clone(frames))
			end
		end
		quarantined = false
	end
	owner.watchStatic(spec.path, function(value)
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
	end)
	-- During a core transaction the observer has not published accepted yet.
	-- Compose verbs on the caller's current write; invalid external writes still
	-- fall back to the last validated path rather than poisoning an API action.
	local function mutationPath(): { Entry }
		local ok, result = pcall(path, spec.path:peek())
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
		spacing = Compose.formula(function(use)
			return if use(spec.env:get("sizeClass")) == "compact" then "s" else "m"
		end)
		titleSize = Compose.formula(function(use)
			return if use(spec.env:get("sizeClass")) == "compact" then "body" else "title"
		end)
	end
	local function row(item: any): any
		local rowOwner = Compose.currentOwner()
		livePages += 1
		rowOwner.own(function()
			livePages -= 1
			item.appeared = false
		end)
		local contentScope = rowOwner.createChild()
		activeScopes[contentScope] = true
		contentScope.own(function()
			activeScopes[contentScope] = nil
		end)
		local function quarantine(err: any): any
			lastError = tostring(err)
			quarantined = true
			if not contentScope.isDisposed() then
				contentScope.dispose()
			end
			return UI.Box({ id = "Unavailable", width = UI.fill() })
		end
		local content = UI.ErrorBoundary({
			id = "Content",
			view = function()
				local bp = Compose.withOwner(contentScope, function()
					return item.definition.content(contentScope, item.entry)
				end)
				if
					type(bp) ~= "table"
					or type(bp.class) ~= "string"
					or not (type(UI[bp.class]) == "function" or (bp.class == "Component" and bp.meta and type(
						bp.meta.build
					) == "function"))
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
				require("../present/nav_bar").build({
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
				}, UI)
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
		if motion ~= nil then
			return pageBlueprint
		end
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
	-- One keyed slot per mounted page. The slot carries the paint-only motion;
	-- presence owns the page, holds it through its exit and reclaims it when
	-- the route returns before that exit finishes.
	-- A page whose form the coordinator writes. The slot is the transition's
	-- node: it enters when its page becomes the top, exits when another does,
	-- and a route that returns mid-exit reverses the same motion.
	local function coordinatedSlot(item: any, key: string): any
		local m = motion :: any
		local slotOwner = Compose.currentOwner()
		local node = UI.ZStack({
			id = "PageMotion",
			zIndex = item.depth,
			canvasGroup = m.fades or nil,
			clipChildren = m.clips or nil,
			width = UI.fill(),
			height = UI.fill(),
			enabled = function(use)
				return use(top) == item
			end,
			Compose.presence(function(use)
				return use(top) == item
			end, function()
				return row(item)
			end, {
				exit = function()
					return { completed = item.done }
				end,
			}),
		})
		node.collectionKey = `[{key}]`
		node.transition = m.declared
		item.slotted = true
		local leaving = false
		slotOwner.own(function()
			item.slotted = nil
			m.region.release(node)
		end)
		local arrives = (item.start or 0) ~= 0
		slotOwner.watch(function(use)
			if use(top) == item then
				if leaving then
					leaving = false
					m.region.cancelExit(node)
					m.region.enter(node)
				elseif arrives then
					arrives = false
					m.region.enter(node)
				end
			elseif not leaving then
				leaving = true
				local function finish()
					item.done:set(true)
				end
				if not m.region.exit(node, finish) then
					finish()
				end
			end
		end)
		return node
	end
	local function slot(item: any, key: string): any
		local m = motion :: any
		if m.region ~= nil then
			return coordinatedSlot(item, key)
		end
		local goal = Compose.cell(item.start or 0)
		item.goal = goal
		local place = Facet.runtime.tween(function(use)
			return use(goal)
		end, {
			seconds = function()
				return if goal:peek() == 0 then m.enterSeconds else m.exitSeconds
			end,
			ease = Compose.easing.outCubic,
		})
		local function reduced(use)
			return m.env ~= nil and use(m.env:get("motionPolicy")) == "reduced"
		end
		local slotOwner = Compose.currentOwner()
		slotOwner.own(function()
			if item.goal == goal then
				item.goal = nil
			end
		end)
		slotOwner.watch(function(use)
			if use(top) ~= item and (reduced(use) or math.abs(use(place)) >= 1) then
				item.done:set(true)
			end
		end)
		if item == current then
			goal:set(0)
		else
			item.done:set(true)
		end
		local node = UI.ZStack({
			id = "PageMotion",
			zIndex = item.depth,
			canvasGroup = true,
			width = UI.fill(),
			height = UI.fill(),
			enabled = function(use)
				return use(top) == item
			end,
			offset = function(use)
				local at = use(place)
				local travel = if at > 0 then m.from else m.to
				if at == 0 or travel == nil or reduced(use) then
					return REST
				end
				-- An enter arrives against its travel; an exit leaves along it.
				local reach = -at * use(m.distance)
				return { x = travel.x * reach, y = travel.y * reach }
			end,
			opacity = if m.fades
				then function(use)
					return if reduced(use) then 1 else 1 - math.min(1, math.abs(use(place)))
				end
				else nil,
			Compose.presence(function(use)
				return use(top) == item
			end, function()
				return row(item)
			end, {
				exit = function()
					return { completed = item.done }
				end,
			}),
		})
		node.collectionKey = `[{key}]`
		return node
	end
	local pages
	if motion ~= nil then
		owner.watch(function(use)
			local kept = nil
			for _, item in use(items) do
				if item ~= current and use(item.done) then
					kept = kept or table.clone(mounted)
					table.remove(kept, table.find(kept, item))
				end
			end
			if kept ~= nil then
				mounted = kept
				items:set(table.clone(kept))
			end
		end)
		pages = UI.ZStack({
			id = "Pages",
			width = UI.fill(),
			height = UI.fill(),
			Compose.keyed({
				from = items,
				key = function(item)
					return item.key
				end,
				render = function(value, _, key)
					return slot(value:peek(), key)
				end,
			}),
		})
		if motion.region ~= nil then
			pages.drainTransitions = motion.region.drain
		end
	else
		pages = UI.ZStack({
			id = "Pages",
			width = UI.fill(),
			height = UI.fill(),
			Compose.LayerStack({
				from = items,
				key = function(item)
					return item.key
				end,
				retention = "top",
				render = function(value, _, key)
					local node = row(value:peek())
					node.collectionKey = `[{key}]`
					return node
				end,
			}),
		})
	end
	local blueprint = contribution.attach(
		UI.ZStack({
			id = id,
			clipChildren = true,
			width = UI.fill(),
			height = UI.fill(),
			children = { pages },
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
					offFocus = owner.watchStatic(graph.focused, function()
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
			if not owned.isDisposed() then
				owned.dispose()
			end
		end
		owner.dispose()
		graph = nil
	end
	return { blueprint = blueprint, api = table.freeze(api), dump = dump, dispose = dispose }
end
function navigation.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end
return navigation
