--!strict
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")

-- A modal with owner-held detents, a draggable header, and focus-based sizing.
local guard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local chromeSlots = require("../tokens/chrome_slots")
local overlayParts = require("./overlay_parts")
local alert = require("./alert")
local sheetRelease = require("./sheet_release")
local dragVelocity = require("../input/drag_velocity")
local interactionTokens = require("../input/interaction_tokens")
local sheet = {}
local specTypes = require("../spec_types/sheet")
type StringCell = specTypes.StringCell
type BooleanCell = specTypes.BooleanCell
export type Spec<V = StringCell, P = BooleanCell> = specTypes.Spec<V, P>
local KEYS = guard.keySet({
	"id",
	"title",
	"content",
	"detent",
	"detents",
	"env",
	"presenter",
	"isPresented",
	"interactiveDismissDisabled",
	"dragIndicator",
	"placement",
	"edge",
	"width",
	"closeButton",
	"header",
	"hero",
	"actions",
	"actionLayout",
	"contentInset",
	"scrollPolicy",
})
local PLACEMENTS = { automatic = true, bottom = true, side = true, center = true }
-- `request(reason) -> boolean` is the private close-request seam: asked BEFORE
-- the Close button, Cancel, a dismissing drag or an outside tap tears the sheet
-- down ("close" | "cancel" | "drag" | "outside"); false keeps the surface, its
-- focus and the accepted detent. Absent, every route closes as it always has.
local function build(Facet: any, core: any, spec: Spec, owner: any, request: ((string) -> boolean)?)
	guard.assertKnownKeys("UI.Sheet", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Sheet"
	assert(type(id) == "string" and id ~= "", "UI.Sheet.id must be a nonempty string")
	assert(
		type(spec.title) == "string" or type(spec.title) == "function" or UI.isReadable(spec.title),
		"UI.Sheet.title must be text, a readable or a function"
	)
	assert(
		(type(spec.content) == "table" and type(spec.content.class) == "string") or type(spec.content) == "function",
		"UI.Sheet.content must be a content builder or UI node"
	)
	assert(
		require("../selection_model").isWritable(spec.detent),
		"UI.Sheet.detent must be a writable Compose cell the caller owns"
	)
	assert(
		spec.isPresented == nil or (require("../selection_model").isWritable(spec.isPresented)),
		"UI.Sheet.isPresented must be a writable Compose cell"
	)
	assert(
		spec.isPresented == nil or spec.presenter ~= nil or Facet.surfaces ~= nil,
		"UI.Sheet.isPresented requires presenter"
	)
	assert(
		spec.interactiveDismissDisabled == nil or type(spec.interactiveDismissDisabled) == "boolean",
		"UI.Sheet.interactiveDismissDisabled must be boolean"
	)
	local indicator = spec.dragIndicator or "automatic"
	assert(
		indicator == "automatic" or indicator == "visible" or indicator == "hidden",
		"UI.Sheet.dragIndicator must be automatic | visible | hidden"
	)
	local placement = spec.placement or "automatic"
	assert(PLACEMENTS[placement] == true, "UI.Sheet.placement must be automatic | bottom | side | center")
	assert(
		spec.edge == nil or (placement == "side" and (spec.edge == "left" or spec.edge == "right")),
		"UI.Sheet.edge is left | right, and only with placement = side"
	)
	local edge = spec.edge or "right"
	assert(
		spec.width == nil or overlayParts.WIDTHS[spec.width] ~= nil,
		"UI.Sheet.width must be automatic | narrow | wide"
	)
	assert(spec.closeButton == nil or type(spec.closeButton) == "boolean", "UI.Sheet.closeButton must be boolean")
	assert(
		spec.header == nil
			or spec.header == false
			or (type(spec.header) == "table" and type(spec.header.class) == "string"),
		"UI.Sheet.header is a blueprint or false"
	)
	assert(
		spec.contentInset == nil or spec.contentInset == "standard" or spec.contentInset == "none",
		"UI.Sheet.contentInset must be standard | none"
	)
	assert(
		spec.actionLayout == nil
			or spec.actionLayout == "automatic"
			or spec.actionLayout == "row"
			or spec.actionLayout == "stacked",
		"UI.Sheet.actionLayout must be automatic | row | stacked"
	)
	local scrollPolicy = spec.scrollPolicy or "always"
	assert(
		scrollPolicy == "always" or scrollPolicy == "atLargestDetent",
		"UI.Sheet.scrollPolicy must be always | atLargestDetent"
	)
	local where = `UI.Sheet('{id}')`
	overlayParts.checkHero(where, spec.hero)
	local hero: any = spec.hero
	local sticky = hero ~= nil and hero.sticky == true
	local overHero = spec.header == false and hero ~= nil
	local sizePath = if overHero then "/Layer/Panel/Stage/Header/Size" else "/Layer/Panel/Header/Size"
	local actions: { any } = spec.actions or {}
	overlayParts.checkActions(where, spec.actions, math.huge)
	local cancelAction, defaults = nil, 0
	for _, action in actions do
		assert(not string.find(action.id, "/", 1, true), `{where}: action ids may not contain '/'`)
		if action.role == "default" then
			defaults += 1
		elseif action.role == "cancel" then
			assert(cancelAction == nil, `{where}: only one action may take role = "cancel"`)
			cancelAction = action
		end
	end
	assert(defaults <= 1, `{where}: only one action may take role = "default"`)
	local utilityHeight = Compose.cell(nil)
	local measureHug: (any, any) -> ()
	local detents, byId = {}, {}
	assert(spec.detents == nil or type(spec.detents) == "table", "UI.Sheet.detents must be an array")
	local entries = spec.detents or { "medium", "large" }
	for index, entry in entries do
		assert(
			type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #entries,
			"UI.Sheet.detents must be a dense array"
		)
		local d
		if type(entry) == "string" then
			assert(
				entry == "medium" or entry == "large" or entry == "hug",
				"UI.Sheet.detents accepts medium, large, hug, or {id, fraction|height}"
			)
			d = if entry == "hug"
				then { id = "hug", hug = true }
				else { id = entry, fraction = if entry == "medium" then 0.5 else 1 }
		else
			guard.assertKnownKeys("UI.Sheet.detents", entry, guard.keySet({ "id", "fraction", "height" }), "detent")
			assert(
				type(entry) == "table" and type(entry.id) == "string" and entry.id ~= "",
				"UI.Sheet detent requires a nonempty id"
			)
			assert(
				(entry.fraction ~= nil) ~= (entry.height ~= nil),
				"UI.Sheet detent requires exactly one of fraction or height"
			)
			local n = entry.fraction or entry.height
			assert(
				type(n) == "number" and n > 0 and n < math.huge and (entry.fraction == nil or n <= 1),
				"UI.Sheet detent fraction must be in (0,1], height must be finite and positive"
			)
			d = table.clone(entry)
		end
		assert(not byId[d.id], "UI.Sheet detent IDs must be unique")
		byId[d.id] = d
		d.index = index
		table.insert(detents, d)
	end
	assert(#detents > 0, "UI.Sheet.detents must not be empty")
	assert(byId[spec.detent:peek()] ~= nil, "UI.Sheet.detent must name a declared detent")
	local env = surfaceEnv.resolve("Sheet", id, core, spec.env, "sheet sizing requires an environment")
	local dragHeight = Compose.cell(nil)
	local dragging = Compose.cell(false)
	local presenter = spec.presenter or Facet.presenter
	local handle, disposed, syncing = nil, false, false
	local vp = env:get("viewportRect")
	local chrome = env:get("platformChrome")
	local distance = env:get("distanceProfile")
	local classes = env:get("interactionClasses")
	local metrics = env:get("themeMetrics")
	local keyboard = env:get("keyboardOcclusionRect")
	-- the room the keyboard covers above the safe bottom edge
	local function keyboardBelow(use): number
		local v, c, occ = use(vp), use(chrome), use(keyboard)
		if type(occ) ~= "table" or type(occ.y) ~= "number" then
			return 0
		end
		return math.max(0, v.y + v.h - c.insets.bottom - occ.y)
	end
	-- the hug detent's measured height: natural body plus pinned regions, fed
	-- back from geometry; nil until measured (the floor stands in)
	local hugHeight = Compose.cell(nil)
	-- ONE safe rectangle: the viewport less the platform insets and the keyboard
	local function available(use)
		local v, c = use(vp), use(chrome)
		return math.max(1, v.h - c.insets.top - c.insets.bottom - keyboardBelow(use))
	end
	local function read(v)
		return v:peek()
	end
	local function heightOf(d, use)
		local h = available(use)
		local m = use(metrics)
		local minimum = (themeSnapshot.resolveNumber(m, "targetSizes.minimum") or 44) * 4
			+ (themeSnapshot.resolveNumber(m, "m") or 16) * 2
		local want = if d.hug then use(hugHeight) or minimum elseif d.fraction then h * d.fraction else d.height
		return math.min(h, math.max(minimum, want))
	end
	-- by height; equal heights keep their authored order
	local function ordered()
		local out = table.clone(detents)
		table.sort(out, function(a, b)
			local ha, hb = heightOf(a, read), heightOf(b, read)
			if ha ~= hb then
				return ha < hb
			end
			return a.index < b.index
		end)
		return out
	end
	local function select(key)
		assert(byId[key] ~= nil, "UI.Sheet.detent must name a declared detent")
		spec.detent:set(key)
		dragHeight:set(nil)
	end
	local function adjust(direction, wrap)
		local sorted = ordered()
		local index = table.find(sorted, byId[spec.detent:peek()]) or 1
		local nextIndex = if wrap then index % #sorted + 1 else math.clamp(index + direction, 1, #sorted)
		if nextIndex == index then
			return false
		end
		select(sorted[nextIndex].id)
		return true
	end
	local cancelDrag: (boolean?) -> ()
	local function dismiss()
		cancelDrag()
		if spec.isPresented then
			syncing = true
			spec.isPresented:set(false)
			syncing = false
		end
		if handle then
			local old = handle
			handle = nil
			presenter.dismiss(old)
		end
	end
	owner.own(function()
		disposed = true
		dismiss()
	end)
	local function allowed(reason: string): boolean
		return request == nil or request(reason) ~= false
	end
	local function interactiveClose()
		if not spec.interactiveDismissDisabled and allowed("cancel") then
			dismiss()
		end
		return true
	end
	local function usable(action: any): boolean
		local selection = require("../selection_model")
		return action ~= nil and selection.read(action.enabled) ~= false and selection.read(action.busy) ~= true
	end
	-- actions never close the sheet; the caller does, through its own cells
	local function press(action: any)
		if usable(action) then
			action.onActivate()
		end
	end
	--[[ THE DRAG SESSION. One at a time, whichever source starts it: the Grip
		handle (framework capture, acquires at once), the panel's native drag
		detector, or the engine's touch-pan stream on the panel or (scrollPolicy =
		atLargestDetent) the body. Detector and pan sessions stay tentative until
		the direct-input slop for their class. The session is tied to the class
		that started it: losing that class cancels, back to the grabbed detent;
		any other class change carries. An outside detent write wins outright. ]]
	local paintedHeight: any
	local session: any = nil
	local tracker = dragVelocity.new()
	local motionClock: any, nowFn: (() -> number)? = nil, nil
	local spring: any = nil
	local bodyTaken = Compose.cell(false) -- the body yields its scroll to a drag
	local function now(): number
		return if nowFn ~= nil then nowFn() else 0
	end
	local function stops(): { any }
		local out = {}
		for _, d in ordered() do
			table.insert(out, { id = d.id, height = heightOf(d, read), index = d.index })
		end
		return out
	end
	local function canDismiss(): boolean
		return not spec.interactiveDismissDisabled
	end
	local function ensureSpring()
		if spring ~= nil or motionClock == nil then
			return
		end
		spring = motionClock:spring(paintedHeight:peek(), "object")
		local mine = spring
		owner.own(function()
			mine:dispose()
		end)
		owner.watchStatic(mine, function()
			if spring == mine and not dragging:peek() then
				paintedHeight:set(mine:peek())
			end
		end)
	end
	-- the spring starts where the panel IS, at the speed it was given
	local function seed(velocity: number)
		ensureSpring()
		if spring ~= nil then
			spring:snap(paintedHeight:peek())
			spring:setVelocity(velocity)
		end
	end
	local function endSession()
		session = nil
		tracker:reset()
		bodyTaken:set(false)
	end
	-- restore = false when an outside write already decided the detent
	function cancelDrag(restore: boolean?)
		local s = session
		endSession()
		if s ~= nil and s.acquired then
			seed(0)
		end
		dragging:set(false)
		dragHeight:set(nil)
		if s ~= nil and restore ~= false and s.acquired and byId[s.detent] ~= nil then
			spec.detent:set(s.detent)
		end
	end
	local function grab(source: string, class: string?, anchor: number, acquired: boolean): boolean
		if session ~= nil then
			return false -- one session: a second source cannot take it over
		end
		local c = classes:peek()
		session = {
			source = source,
			class = class,
			known = class ~= nil and c[class] == true,
			anchor = anchor,
			start = paintedHeight:peek(),
			detent = spec.detent:peek(),
			acquired = false,
		}
		if acquired then
			session.acquired = true
			dragging:set(true)
			dragHeight:set(session.start)
			tracker:push(0, session.start, now())
		end
		return true
	end
	local function move(y: number)
		local s = session
		if s == nil then
			return
		end
		if not s.acquired then
			if math.abs(y - s.anchor) < interactionTokens.promotionPx(s.class) then
				return
			end
			-- acquired AT the slop point, so the panel never jumps
			local slop = interactionTokens.promotionPx(s.class)
			s.acquired = true
			s.anchor += if y > s.anchor then slop else -slop
			if s.source == "body" then
				bodyTaken:set(true)
			end
			dragging:set(true)
			dragHeight:set(s.start)
			tracker:push(0, s.start, now())
		end
		local sorted = stops()
		local limit = themeSnapshot.resolveNumber(metrics:peek(), "targetSizes.minimum") or 44
		local h = sheetRelease.resist(
			s.start + s.anchor - y,
			sorted[1].height,
			sorted[#sorted].height,
			available(read),
			canDismiss(),
			limit
		)
		dragHeight:set(h)
		tracker:push(0, h, now())
	end
	local function release()
		local s = session
		if s == nil then
			return
		end
		if not s.acquired then
			endSession()
			return
		end
		-- the terminal sample: a hold after motion reads as no speed
		local h = dragHeight:peek() or s.start
		tracker:push(0, h, now())
		local _, velocity = tracker:velocity()
		endSession()
		local choice = sheetRelease.choose(stops(), h, velocity, spec.detent:peek(), canDismiss())
		seed(velocity)
		dragging:set(false)
		if choice == "dismiss" then
			if allowed("drag") then
				dismiss()
			else
				-- refused: back to the detent the caller still holds
				select(spec.detent:peek())
			end
			return
		end
		select(choice)
	end
	local function classOf(pointerType: string?): string
		return interactionTokens.classForPointerType(pointerType)
	end
	-- the detector reports positions only; its class is the one direct class
	-- present, or unknown (then only losing both direct classes cancels)
	local function detectorClass(): string?
		local c = classes:peek()
		if c.pointer and not c.touch then
			return "pointer"
		elseif c.touch and not c.pointer then
			return "touch"
		end
		return nil
	end
	owner.watchStatic(classes, function(c)
		local s = session
		if s == nil then
			return
		end
		local lost = if s.known then c[s.class] ~= true else not c.pointer and not c.touch
		if lost then
			cancelDrag()
		end
	end)
	-- the room changing under a drag makes its geometry stale
	owner.watchStatic(
		Compose.formula(function(use)
			return available(use)
		end),
		function()
			if session ~= nil then
				cancelDrag()
			end
		end
	)
	-- a late id the sheet does not declare is refused (the error boundary sees
	-- it) and geometry stays on the last valid one until a valid id arrives
	local lastValid = spec.detent:peek()
	owner.watchStatic(spec.detent, function(key)
		if session ~= nil then
			cancelDrag(false)
		end
		assert(byId[key] ~= nil, "UI.Sheet.detent must name a declared detent")
		lastValid = key
	end)
	local height = Compose.formula(function(use)
		local d = byId[use(spec.detent)] or byId[lastValid]
		return math.min(available(use), use(dragHeight) or heightOf(d, use))
	end)
	-- ONE painted-height authority: the drag writes it directly, the clock's
	-- spring settles it, and with reduced motion or no clock it snaps
	paintedHeight = Compose.cell(height:peek())
	owner.watch(function(use)
		local h = use(height)
		if use(dragging) or use(env:get("motionPolicy")) == "reduced" or motionClock == nil then
			if spring ~= nil then
				spring:snap(h)
			end
			paintedHeight:set(h)
			return
		end
		ensureSpring()
		spring:setTarget(h)
	end)
	local function bindMotion(clock: any, nowSource: (() -> number)?)
		if clock == motionClock then
			nowFn = nowSource or nowFn
			return
		end
		if spring ~= nil then
			spring:dispose()
			spring = nil
		end
		motionClock, nowFn = clock, nowSource
	end
	local tallest = Compose.formula(function(use)
		local d = byId[use(spec.detent)] or byId[lastValid]
		local mine = heightOf(d, use)
		for _, other in detents do
			if heightOf(other, use) > mine then
				return false
			end
		end
		return true
	end)
	local sizeLabel = Compose.formula(function(use)
		return "Size: " .. use(spec.detent)
	end)
	local direct = Compose.formula(function(use)
		local c = use(classes)
		return indicator ~= "hidden" and (indicator == "visible" or c.pointer or c.touch)
	end)
	-- automatic stays the distance default: ten-foot centred, otherwise bottom
	local function placed(use): string
		if placement ~= "automatic" then
			return placement
		end
		return if use(distance) == "ten-foot" then "center" else "bottom"
	end
	local function transition()
		if placement == "side" then
			local toward = if edge == "left" then "slide-left" else "slide-right"
			local from = if edge == "left" then "slide-right" else "slide-left"
			return { enter = from, exit = toward, distance = vp:peek().w }
		end
		return { enter = "slide-up", exit = "slide-down", distance = vp:peek().h }
	end
	local function actionWidth(use): number
		local v, c, m = use(vp), use(chrome), use(metrics)
		local cap = themeSnapshot.resolveNumber(m, overlayParts.WIDTHS[spec.width or "automatic"]) or math.huge
		local room = v.w - (c.insets.left or 0) - (c.insets.right or 0)
		return math.max(0, math.min(cap, room) - 2 * (themeSnapshot.resolveNumber(m, "m") or 16))
	end
	-- the utility controls: Size, and Close unless closeButton = false. Laid over
	-- a hero (header = false) they hug the top-right corner.
	local function utilities(over: boolean)
		return UI.HStack({
			id = "Header",
			width = if over then UI.hug() else UI.fill(),
			alignH = if over then "end" else nil,
			alignV = if over then "start" else nil,
			gap = "s",
			children = {
				UI.Button({
					id = "Size",
					label = sizeLabel,
					disclose = true,
					enabled = #detents > 1,
					width = if over then nil else UI.fill(),
					height = { type = "minMax", min = "targetSizes.minimum" },
					onActivate = function()
						adjust(1, true)
					end,
				}),
				if spec.closeButton == false
					then nil
					else UI.Button({
						id = "Close",
						disclose = true,
						label = "Close",
						compactLabel = { icon = "chevron.down", prefer = true },
						width = { type = "fixed", px = "targetSizes.minimum" },
						height = { type = "minMax", min = "targetSizes.minimum" },
						onActivate = function()
							if allowed("close") then
								dismiss()
							end
						end,
					}) :: any,
			},
		})
	end
	--[[ NATIVE ACQUISITION on the mounted panel: the engine's UIDragDetector
		(pointer; on a touch engine it arms by hold) and its touch-pan stream,
		which observes without sinking, so interactive descendants keep their first
		press. atLargestDetent also observes the body's pan. Re-attached per
		mounted surface; released with it and with the owner. ]]
	local findBody: (any) -> any
	local controller: any = nil
	local attachedRoot: string? = nil
	local detachers: { () -> () } = {}
	local function detachInput()
		for _, off in detachers do
			pcall(off)
		end
		table.clear(detachers)
		attachedRoot = nil
	end
	owner.own(detachInput)
	local function onPan(source: string, bodyPath: string?, g: any)
		if g.kind ~= "pan" then
			return
		end
		local ty = if type(g.totalTranslation) == "table" then g.totalTranslation.y or 0 else 0
		local fingers = if type(g.positions) == "table" then #g.positions else 1
		local s = session
		if g.state == "began" then
			if fingers > 1 then
				return
			end
			if source == "body" and tallest:peek() then
				-- at the tallest detent a body pan is the scroller's, unless it
				-- starts at the top and goes down
				local pos = if bodyPath ~= nil then controller.scrollPosition(bodyPath) else nil
				if pos ~= nil and pos.y > 0.5 then
					return
				end
				if grab(source, "touch", 0, false) then
					session.downOnly = true
				end
				return
			end
			grab(source, "touch", 0, false)
		elseif g.state == "changed" then
			if s == nil or s.source ~= source or fingers > 1 then
				return
			end
			if s.downOnly and not s.acquired and ty < 0 then
				endSession() -- upward from the top: the scroller's gesture
				return
			end
			move(ty)
		elseif s ~= nil and s.source == source then
			if g.state == "ended" then
				move(ty)
				release()
			else
				cancelDrag()
			end
		end
	end
	local function attachInput(root: any)
		if controller == nil or attachedRoot == root.path then
			return
		end
		detachInput()
		attachedRoot = root.path
		local panelPath = root.path .. "/Layer/Panel"
		local function keep(off: any)
			if off ~= nil then
				table.insert(detachers, off)
			end
		end
		if controller.attachDragDetector ~= nil then
			keep(controller.attachDragDetector(panelPath, {
				onStart = function(pos: any)
					if pos ~= nil then
						grab("detector", detectorClass(), pos.y, false)
					end
				end,
				onContinue = function(pos: any)
					if pos ~= nil and session ~= nil and session.source == "detector" then
						move(pos.y)
					end
				end,
				onEnd = function()
					if session ~= nil and session.source == "detector" then
						release()
					end
				end,
			}))
		end
		if controller.attachContextGestures ~= nil then
			keep(controller.attachContextGestures(panelPath, {
				onGesture = function(g: any)
					onPan("panel", nil, g)
				end,
			}))
			local body = if scrollPolicy == "atLargestDetent" then findBody(root) else nil
			if body ~= nil then
				local bodyPath = body.path
				keep(controller.attachContextGestures(bodyPath, {
					onGesture = function(g: any)
						onPan("body", bodyPath, g)
					end,
				}))
			end
		end
	end
	-- hug = the body's natural content height (its children's extent plus its
	-- own padding) plus everything pinned around the body viewport, counted once
	function findBody(node: any): any
		if node.id == "Body" and node.class == "ScrollView" then
			return node
		end
		for _, child in node.children or {} do
			local found = findBody(child)
			if found ~= nil then
				return found
			end
		end
		return nil
	end
	function measureHug(rectOf: any, root: any)
		local body = findBody(root)
		local panelRect = rectOf(root.path .. "/Layer/Panel")
		local bodyRect = if body ~= nil then rectOf(body.path) else nil
		if type(panelRect) ~= "table" or type(bodyRect) ~= "table" then
			return
		end
		local top, bottom = math.huge, -math.huge
		for _, child in body.children or {} do
			local r = rectOf(child.path)
			if type(r) == "table" then
				top, bottom = math.min(top, r.y), math.max(bottom, r.y + r.h)
			end
		end
		if top == math.huge then
			return
		end
		local pad = if hero ~= nil and not sticky or spec.contentInset == "none"
			then 0
			else themeSnapshot.resolveNumber(metrics:peek(), "s") or 8
		local want = (bottom - top) + 2 * pad + (panelRect.h - bodyRect.h)
		local was = hugHeight:peek()
		if was == nil or math.abs(was - want) > 0.5 then
			hugHeight:set(want)
		end
	end
	local function buildScreen()
		local content = if type(spec.content) == "function" then spec.content() else spec.content
		local pad = if spec.contentInset == "none" then 0 else "s"
		-- the band authored hero content keeps clear for the controls over it
		local strip = if overHero and hero.content ~= nil
			then Compose.formula(function(use)
				return { type = "fixed", px = use(utilityHeight) or "targetSizes.minimum" }
			end)
			else nil
		local bodyChildren = { content }
		if hero ~= nil and not sticky then
			bodyChildren = {
				overlayParts.hero(UI, hero, strip),
				UI.VStack({ id = "Inset", width = UI.fill(), padding = pad, children = { content } }),
			}
		end
		local body = UI.ScrollView({
			id = "Body",
			axis = "y",
			-- atLargestDetent: below the tallest detent the body's pan is the
			-- sheet's; a drag that took the body freezes it (never two scrollers)
			scrollEnabled = Compose.formula(function(use)
				if use(bodyTaken) then
					return false
				end
				return scrollPolicy == "always" or use(tallest)
			end),
			width = UI.fill(),
			height = UI.fill(),
			padding = if hero ~= nil and not sticky then nil else pad,
			children = bodyChildren,
		})
		local children: { any } = {
			UI.ZStack({
				id = "Drag",
				hidden = Compose.formula(function(use)
					return not use(direct)
				end),
				width = UI.fill(),
				height = { type = "fixed", px = "targetSizes.minimum" },
				children = {
					UI.corners(
						UI.Box({
							id = "Indicator",
							width = { type = "fixed", px = "targetSizes.minimum" },
							height = { type = "fixed", px = "space.xs" },
							tint = { role = "contentSecondary", blend = 1 },
							alignH = "center",
							alignV = "center",
						}),
						"pill"
					),
					UI.Grip({
						id = "Handle",
						width = UI.fill(),
						height = UI.fill(),
						-- the handle is the grab target itself: it acquires at once
						onPointerDown = function(_, pos)
							return grab("grip", classOf(pos.pointerType), pos.y, true)
						end,
						onPointerMove = function(_, pos)
							if session ~= nil and session.source == "grip" then
								move(pos.y)
							end
						end,
						onPointerUp = function()
							if session ~= nil and session.source == "grip" then
								release()
							end
						end,
						onPointerCancel = function()
							if session ~= nil and session.source == "grip" then
								cancelDrag()
							end
						end,
					}),
				},
			}),
		}
		if overHero then
			-- no header strip: the utilities lie over the hero, pinned to the panel
			-- top whether the hero is pinned or scrolls with the body
			local column = if sticky
				then UI.VStack({
					id = "Column",
					width = UI.fill(),
					height = UI.fill(),
					gap = "s",
					children = { overlayParts.hero(UI, hero, strip), body },
				})
				else body
			table.insert(
				children,
				UI.ZStack({
					id = "Stage",
					width = UI.fill(),
					height = UI.fill(),
					children = { column, utilities(true) },
				})
			)
		else
			if sticky then
				table.insert(children, overlayParts.hero(UI, hero))
			end
			if spec.header == nil then
				table.insert(children, UI.Text({ id = "Title", text = spec.title, disclose = true }))
			elseif spec.header ~= false then
				table.insert(children, spec.header)
			end
			table.insert(children, utilities(false))
			table.insert(children, body)
		end
		if #actions > 0 then
			table.insert(
				children,
				alert.actionGroup(
					Facet,
					Compose.currentOwner() or owner,
					env,
					actions,
					spec.actionLayout or "automatic",
					actionWidth,
					press
				)
			)
		end
		local panel = chromeSlots.attachHint(
			UI.VStack({
				id = "Panel",
				width = { type = "minMax", max = overlayParts.WIDTHS[spec.width or "automatic"] },
				height = Compose.formula(function(use)
					return { type = "fixed", px = use(paintedHeight) }
				end),
				alignH = if placement ~= "side" then "center" elseif edge == "left" then "start" else "end",
				alignV = Compose.formula(function(use)
					return if placed(use) == "center" then "center" else "end"
				end),
				surface = "raised",
				padding = "m",
				gap = "s",
				children = children,
			}),
			{ slot = "panel" }
		)
		local utilityPath = if overHero then "/Layer/Panel/Stage/Header" else nil
		local blueprint = require("../input/contribution").attach(
			UI.Screen({
				id = id,
				children = {
					UI.ZStack({
						id = "Layer",
						width = UI.fill(),
						height = UI.fill(),
						-- the keyboard takes the room below its top edge
						padding = Compose.formula(function(use)
							return { top = 0, left = 0, right = 0, bottom = keyboardBelow(use) }
						end),
						children = { panel },
					}),
				},
			}),
			{
				handleCancel = function(): boolean
					-- a sheet that refuses interactive dismissal refuses its implicit
					-- Cancel too; the caller's own buttons still work
					if spec.interactiveDismissDisabled then
						return true
					end
					if usable(cancelAction) then
						press(cancelAction)
						return true
					end
					return interactiveClose()
				end,
				requestDismiss = function(): boolean
					return allowed("outside")
				end,
				bindController = function(c: any)
					if c ~= controller then
						detachInput()
						controller = c
					end
				end,
				bindMotion = bindMotion,
				syncGeometry = function(rectOf: any, node: any?)
					if node == nil then
						return
					end
					attachInput(node)
					if utilityPath ~= nil then
						local r = rectOf(node.path .. utilityPath)
						if type(r) == "table" and r.h > 0 and r.h ~= utilityHeight:peek() then
							utilityHeight:set(r.h)
						end
					end
					if byId.hug ~= nil and byId.hug.hug then
						measureHug(rectOf, node)
					end
				end,
				adjustAxis = "horizontal",
				adjustTargets = function(root)
					return { [root.path .. sizePath] = true }
				end,
				handleAdjust = function(path, direction)
					if path ~= "/" .. id .. sizePath then
						return false
					end
					return adjust(direction, false)
				end,
			}
		)
		return blueprint
	end
	local blueprint = UI.ZStack({ id = id .. "Anchor" })
	local function present(target)
		assert(not disposed, "UI.Sheet is disposed")
		if handle then
			return handle
		end
		presenter = target or presenter
		assert(presenter and type(presenter.presentModal) == "function", "UI.Sheet.present requires a presenter")
		local presentModal = if Facet.surfaces then Facet.surfaces.modal else presenter.presentModal
		handle = presentModal(if Facet.surfaces then buildScreen else blueprint, {
			outsideTapCancel = not spec.interactiveDismissDisabled,
			cancelPolicy = "none",
			transition = (function()
				local motion: any = transition()
				motion.class = "dismiss"
				motion.exitClass = "dismiss"
				return motion
			end)(),
		})
		local opened = handle
		opened.scope.own(function()
			if handle == opened then
				handle = nil
				if spec.isPresented then
					syncing = true
					spec.isPresented:set(false)
					syncing = false
				end
			end
		end)
		if spec.isPresented then
			syncing = true
			spec.isPresented:set(true)
			syncing = false
		end
		return handle
	end
	if spec.isPresented then
		owner.watchStatic(spec.isPresented, function(want)
			if not syncing and not disposed then
				if want then
					present()
				else
					dismiss()
				end
			end
		end)
		if spec.isPresented:peek() then
			present()
		end
	end
	local function dump()
		return {
			schema = "facet-sheet-dump/1",
			id = id,
			detent = spec.detent:peek(),
			height = height:peek(),
			presented = handle ~= nil,
			dragging = dragging:peek(),
			placement = placed(read),
			edge = if placement == "side" then edge else nil,
			transition = (function()
				local motion = transition()
				return { enter = motion.enter, exit = motion.exit }
			end)(),
		}
	end
	return table.freeze({
		blueprint = blueprint,
		present = present,
		dismiss = dismiss,
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	})
end
function sheet.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end
-- the same sheet with the private close-request seam (see `build`); not a
-- public constructor — the Popover's compact form presents through it
function sheet.buildRequesting(Facet: any, core: any, spec: Spec, request: (string) -> boolean)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner, request)
	end)
end
return sheet
