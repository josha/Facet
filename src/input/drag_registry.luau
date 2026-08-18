--!strict
-- The per-surface drag REGISTRY (ADR-0022 Decision 5, rows SF-D1/D2/D4/D5).
-- One object owns every live `UI.draggable` / `UI.dropTarget` on a surface and
-- runs the single acquisition→session→terminal code path all four input classes
-- share. The pure policy still lives in `drag_session` (legality, exactly-once
-- enter/leave, predicted verdict, inertness); this module is what connects that
-- policy to real mounted geometry, real pointer events, real motion and the
-- semantic feedback seam.
--
-- ONE PROMOTION PATH, THREE ACQUISITIONS. `UIDragDetector` (when the adapter
-- has it), the ADR-0008 pointer capture (when it does not), and the non-pointer
-- arm→navigate→commit verbs all funnel into `beginSession` / `updateAt` /
-- `release`. There is deliberately no second legality path for gamepads: a
-- "gamepad mode" that re-implemented `accepts` would drift from the pointer one
-- the first time a game changed a rule.
--
-- LIVE RECTS, NEVER CAPTURED ONES. Targets are resolved through the renderer's
-- `rectOf` at every hit-test, and `refreshTargets()` re-runs the hover against
-- the last pointer position. That is what makes a drop verdict correct while
-- the list under the pointer scrolls (autoscroll re-resolves EVERY frame, in
-- the same frame as the scroll write) or re-sorts mid-drag.
--
-- PAINT ORDER IS THE TIE-BREAK. Overlapping targets resolve to the topmost drawn
-- one, and "topmost" is the renderer's own z-walk index (`zOf`) — the same walk
-- that decides what the player actually sees, including any `zIndex` override.
-- Without it the answer would be registration order, which is mount order,
-- which is not what is on screen.
--
-- WHY THE VERDICT CARRIES MORE THAN THE SESSION'S HOVER. `drag_session` skips
-- illegal targets entirely (no enter fires for them, by contract), so the
-- session alone cannot say "you are over row 7 and it is refusing you because
-- FULL". The registry hit-tests targets GEOMETRICALLY as well, and publishes
-- `{ targetId, overId, legal, reason }` — the session still owns every
-- enter/leave and the drop, and the extra read is what lets a row paint its
-- refusal with the game's own reason code.
--
-- COLLABORATORS ARE INJECTED, and every one of them is optional. The registry
-- is fully exercisable with none of them attached (that is how the headless
-- suite drives it): no `motionClock` means terminals resolve instantly instead
-- of flying, no `proxy` means nothing is painted, no `feedback` means the
-- semantic events are dropped on the floor. A missing collaborator degrades one
-- behaviour; it never changes a verdict.

local drag_session = require("./drag_session")
local drag_velocity = require("./drag_velocity")
local tokens = require("./interaction_tokens")
local specGuard = require("../spec_guard")

local drag_registry = {}

export type Feedback = {
	emit: (event: string, info: any) -> (),
}

-- the presenter's drag-proxy layer (above toasts, below modals). `show` may
-- answer nil (a host with no layer), which turns the whole proxy story off
-- without any caller branching on it.
export type ProxyHost = {
	show: (info: any) -> any?,
	transform: (handle: any, t: { x: number, y: number, scale: number? }) -> (),
	hide: (handle: any) -> (),
}

export type Opts = {
	core: any,
	rectOf: (path: string) -> any,
	-- paint-order index for a mounted path (renderer z-walk); absent = mount order
	zOf: ((path: string) -> number?)?,
	now: (() -> number)?,
	feedback: Feedback?,
	proxy: ProxyHost?,
	motionClock: any?,
	promotionPx: { [string]: number }?,
	-- THE HOST'S TWO LIVE PREDICATES (api-architecture-consistency F-29). Both are
	-- read below and neither was declared. `isPathLive`: a retiring subtree paints
	-- its exit but is not a drag surface, answered per path at RESOLUTION time
	-- (ARCH-F2). `isSourceEnabled`: whether a source is currently enabled, a live
	-- prop read (P2-3). Absent = always live / always enabled, which is what a
	-- standalone registry wants.
	isPathLive: ((path: string) -> boolean)?,
	isSourceEnabled: ((path: string) -> boolean)?,
}

export type Verdict = {
	targetId: string?, -- the LEGAL target the session is hovering (nil = none)
	overId: string?, -- the target geometrically under the pointer, legal or not
	legal: boolean,
	reason: string?, -- the game's refusal code for `overId`
	mode: string, -- "pointer" | "armed"
}

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function centerOf(rect: any): (number?, number?)
	if type(rect) ~= "table" or not isFinite(rect.x) or not isFinite(rect.y) then
		return nil, nil
	end
	return rect.x + (rect.w or 0) / 2, rect.y + (rect.h or 0) / 2
end

-- CLOSED OPTS (constitution §4; ARCH-1). Two of these ARE live predicates whose
-- absence means "always legal" (`isPathLive`, `isSourceEnabled`), so a typo here
-- silently widens what a surface will accept — the worst direction to fail in.
local DRAG_REGISTRY_OPTS_KEYS = specGuard.keySet({
	"core",
	"feedback",
	"isPathLive",
	"isSourceEnabled",
	"motionClock",
	"now",
	"promotionPx",
	"proxy",
	"rectOf",
	"zOf",
})

function drag_registry.new(opts: Opts)
	specGuard.assertKnownKeys("newDragRegistry", opts, DRAG_REGISTRY_OPTS_KEYS, "opts")
	assert(type(opts) == "table" and type(opts.core) == "table", "Facet drag registry: `core` is required")
	assert(type(opts.rectOf) == "function", "Facet drag registry: `rectOf` is required (the renderer's live rects)")
	local core = opts.core
	local rectOf = opts.rectOf
	local zOf = opts.zOf
	-- ARCH-F2: a retiring subtree paints its exit but is NOT a drag surface. The
	-- host answers liveness per path at RESOLUTION time — no registration churn,
	-- so a re-entry mid-exit is eligible again the same frame.
	local isPathLive: ((string) -> boolean)? = opts.isPathLive
	local function pathLive(path: string): boolean
		return isPathLive == nil or isPathLive(path)
	end
	-- P2-3: the host answers whether a SOURCE is currently enabled (live prop
	-- read); absent = always enabled (standalone registry use)
	local isSourceEnabled: ((string) -> boolean)? = opts.isSourceEnabled
	local function sourceEnabled(path: string): boolean
		return isSourceEnabled == nil or isSourceEnabled(path)
	end
	local now = opts.now or os.clock
	local feedback = opts.feedback
	local proxyHost = opts.proxy
	local motionClock = opts.motionClock
	local promotionOverrides = opts.promotionPx

	local sources: { [string]: any } = {}
	local targets: { [string]: any } = {}
	local targetOrder: { string } = {} -- registration order; z refines it
	-- a target being unregistered, kept reachable for exactly the retarget that
	-- drops it. Without this the exactly-once `leave` a removed hover owes
	-- (finding F5) would be swallowed: the declaration is already gone by the
	-- time the session notices its target vanished, and a highlight nobody was
	-- told to tear down stays lit on a row that no longer exists.
	local retiring: { [string]: any } = {}
	local disposed = false

	-- the predicted verdict, published as a plain signal so any consumer binds it
	local verdict = core:signal(nil :: Verdict?)
	-- THE HELD SOURCE (director round five): the path a live session is carrying,
	-- for the whole of "the slot sits empty until it lands or returns" — set at
	-- acquisition, cleared when the drop LANDS or the return flight ARRIVES (not
	-- at the release frame, which is earlier). The renderer binds this to the
	-- `luau-drag-held` state every theme's sheet empties.
	local heldSource = core:signal(nil :: string?)

	-- pre-promotion press (a press that has not travelled far enough to be a drag)
	local pending: any = nil
	-- the live session and everything hanging off it
	local live: any = nil
	-- forward declaration: `beginSession` runs the first hover through the SAME
	-- function every later move does, so there is one hover code path
	local updateAtInternal: (x: number, y: number) -> ()

	local function emit(event: string, info: any)
		if feedback ~= nil then
			feedback.emit(event, info)
		end
	end

	-- ===== target resolution ==============================================
	-- ordered bottom-to-top: `drag_session` takes the LAST array match, so the
	-- array must run in paint order for "the topmost target wins" to be true.
	local function orderedTargetPaths(): { string }
		local paths: { string } = {}
		for _, path in targetOrder do
			if targets[path] ~= nil and pathLive(path) then
				table.insert(paths, path)
			end
		end
		if zOf == nil then
			return paths
		end
		local rank: { [string]: number } = {}
		for index, path in paths do
			local z = (zOf :: any)(path)
			rank[path] = if isFinite(z) then z :: number else index
		end
		table.sort(paths, function(a, b)
			if rank[a] == rank[b] then
				return a < b
			end
			return rank[a] < rank[b]
		end)
		return paths
	end

	-- session targets from LIVE solver rects. A target whose node has no solved
	-- rect (its row scrolled out of the window and unmounted) simply is not in
	-- the array this frame — the hit-test is over VISIBLE targets only, which is
	-- exactly why edge autoscroll exists: it is how an off-screen row becomes
	-- reachable rather than a special case that lets you drop on one you cannot see.
	local function buildTargets(): ({ any }, { [string]: string? })
		local out: { any } = {}
		local reasons: { [string]: string? } = {}
		for _, path in orderedTargetPaths() do
			local rect = rectOf(path)
			if type(rect) == "table" and isFinite(rect.x) and isFinite(rect.w) then
				local decl = targets[path]
				local accepts = decl.accepts
				table.insert(out, {
					id = path,
					rect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h },
					accepts = if accepts == nil
						then nil
						else function(p: any): boolean
							local ok, reason = accepts(p)
							reasons[path] = if ok then nil else reason
							return ok == true
						end,
				})
			end
		end
		return out, reasons
	end

	-- topmost target under a point REGARDLESS of legality (the "what am I over"
	-- half of the verdict; the session owns the "what is legal" half)
	local function overTargetAt(x: number, y: number, list: { any }): string?
		local found: string? = nil
		for _, entry in list do
			local rect = entry.rect
			if x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h then
				found = entry.id
			end
		end
		return found
	end

	-- "the session moved" subscribers. A drop-line indicator and an autoscroll
	-- host both need the pointer's new position on the frame it changed, and
	-- neither of them owns the acquisition, so the registry publishes the moment
	-- rather than making every host poll.
	local watchers: { (state: any) -> () } = {}
	local function notifyWatchers()
		if #watchers == 0 then
			return
		end
		local state = if live == nil
			then { active = false }
			else {
				active = true,
				mode = live.mode,
				source = live.sourcePath,
				payload = live.payload,
				hovered = live.session:state().hovered,
				over = live.overId,
				x = live.lastX,
				y = live.lastY,
			}
		for _, watcher in table.clone(watchers) do
			watcher(state)
		end
	end

	local function publishVerdict()
		if live == nil then
			verdict:set(nil)
			return
		end
		local hovered = live.session:state().hovered
		local over = live.overId
		verdict:set({
			targetId = hovered,
			overId = over,
			legal = hovered ~= nil,
			reason = if over ~= nil and hovered == nil then live.reasons[over] else nil,
			mode = live.mode,
		})
	end

	-- ===== proxy presentation =============================================
	-- Proxy writes take a RECORD, not the `live` upvalue: a terminal detaches
	-- the session immediately (the gesture is over, the registry is inert, a new
	-- gesture may begin) while the record lives on as a DETACHED FLIGHT the
	-- motion clock finishes visually — the legacy-ratified split between "the
	-- drag ended" and "the ghost is still flying home". Found by integration:
	-- with a presenter-wired clock, a live-until-arrival session made every
	-- terminal linger and double-fire (suite rows SF-D1/D5).
	local detachedFlights: { [any]: boolean } = {}
	local function writeProxyFor(record: any)
		if record.proxyHandle == nil or proxyHost == nil then
			return
		end
		proxyHost.transform(record.proxyHandle, {
			x = record.proxyX,
			y = record.proxyY,
			scale = record.proxyScale,
		})
	end
	local function writeProxy()
		if live ~= nil then
			writeProxyFor(live)
		end
	end

	local function moveProxyTo(x: number, y: number)
		if live == nil then
			return
		end
		-- HARD 1:1 with the pointer. There is never a spring between the finger
		-- and the ghost: lag on the thing you are holding reads as a dropped frame,
		-- not as polish. Springs run on the pickup scale and the return flight only.
		live.proxyX = x - live.grabDX
		live.proxyY = y - live.grabDY
		writeProxy()
	end

	local function hideProxyFor(record: any)
		-- the CHASE dies first (ARCH-F1): its judge closure holds the shared
		-- presenter clock, so a flight whose springs were disposed but whose
		-- chase survived would step the clock forever without ever settling
		if record.chaseHandle ~= nil then
			record.chaseHandle.cancel()
			record.chaseHandle = nil
		end
		if record.motionScope ~= nil then
			for _, disposeOne in record.motionScope do
				disposeOne()
			end
			record.motionScope = nil
		end
		if record.proxyHandle ~= nil and proxyHost ~= nil then
			proxyHost.hide(record.proxyHandle)
		end
		record.proxyHandle = nil
		detachedFlights[record] = nil
	end
	local function hideProxy()
		if live ~= nil then
			hideProxyFor(live)
		end
	end

	-- ===== terminal motion ================================================
	-- A return flight (reject or cancel) and a commit flight are the SAME
	-- mechanism aimed at different live targets, which is why they share one
	-- function: the only differences are the seed velocity and what happens on
	-- arrival. `readTarget` returning nil (its row unmounted mid-flight) resolves
	-- the chase by settle with `targetLost`, which is finding F5's ruling.
	local function flyTo(
		record: any,
		readTarget: () -> (number?, number?),
		seedVx: number,
		seedVy: number,
		onDone: (info: any) -> ()
	)
		if record.proxyHandle == nil or motionClock == nil then
			hideProxyFor(record)
			onDone({ how = "instant", targetLost = false })
			return
		end
		-- the record is DETACHED by the time a flight starts: the session upvalue
		-- is already nil, a new gesture may begin, and this closure set is the
		-- only thing keeping the ghost moving until arrival (or dispose)
		detachedFlights[record] = true
		local className = record.decl.dragMotion or "object"
		local x = motionClock:spring(record.proxyX, className)
		local y = motionClock:spring(record.proxyY, className)
		x:setVelocity(seedVx)
		y:setVelocity(seedVy)
		local function pull()
			if record.flightDone then
				return
			end
			record.proxyX = x:get()
			record.proxyY = y:get()
			writeProxyFor(record)
		end
		local unX = core:observe(x, pull)
		local unY = core:observe(y, pull)
		record.motionScope = {
			function()
				unX()
				unY()
				x:dispose()
				y:dispose()
			end,
		}
		record.chaseHandle = motionClock:chase({
			x = x,
			y = y,
			target = readTarget,
			onArrive = function(info: any)
				if record.flightDone then
					return
				end
				record.flightDone = true
				hideProxyFor(record)
				onDone(info)
			end,
		})
	end

	-- Flights aim the GHOST'S CENTER at the target rect's CENTER (director fix
	-- round): the flight springs drive the proxy's top-left, so the aim subtracts
	-- half the ghost. Top-left aiming made a card dropped mid-row slide visibly
	-- LEFT to the row's corner; center aiming lands it onto the thing itself.
	local function centerAim(session: any, rect: any): (number?, number?)
		if type(rect) ~= "table" or not isFinite(rect.x) then
			return nil, nil
		end
		return rect.x + rect.w / 2 - (session.proxyW or 0) / 2, rect.y + rect.h / 2 - (session.proxyH or 0) / 2
	end

	local function sourceAnchor(session: any): () -> (number?, number?)
		return function()
			return centerAim(session, rectOf(session.sourcePath))
		end
	end

	-- the RETURN flight's arrival, announced (director round five): "the slot
	-- sits empty until it lands or returns" needs the RETURN half to be a real
	-- event. `arrive` is the taxonomy's motion verb — any chase reaching its
	-- live target — and the fly-home is exactly that.
	local function flyHome(session: any, vx: number, vy: number)
		flyTo(session, sourceAnchor(session), vx, vy, function(arrival: any)
			heldSource:set(nil)
			emit("arrive", {
				source = session.sourcePath,
				payload = session.payload,
				returned = true,
				how = arrival.how,
				targetLost = arrival.targetLost,
			})
		end)
	end

	-- ===== session lifecycle ==============================================
	local function endSession()
		live = nil
		pending = nil
		verdict:set(nil)
		notifyWatchers()
	end

	local function beginSession(sourcePath: string, mode: string, x: number, y: number, pointerType: string?)
		local decl = sources[sourcePath]
		if decl == nil or not pathLive(sourcePath) then
			-- a retiring source cannot begin a gesture (ARCH-F2): it is painting
			-- its exit and about to be disposed
			return false
		end
		if not sourceEnabled(sourcePath) then
			-- a DISABLED source acquires nothing (P2-3) — the same gate the tap
			-- path honors, read live at acquisition time
			return false
		end
		local payload = decl.payload
		if type(payload) == "function" then
			payload = payload(sourcePath)
		end
		local sourceRect = rectOf(sourcePath)
		-- GRAB ANCHOR (director fix round, RR parity): the ratified feel carries the
		-- card CENTERED under the pointer — RascalRally's ghost is AnchorPoint
		-- (0.5,0.5) at the raw pointer (SponsorGesture gate round 11, finding 6).
		-- `grabAnchor = "preserve"` keeps the grab-point offset for large surfaces
		-- where a snap-to-center would visibly jump.
		local grabDX, grabDY = 0, 0
		local proxyW, proxyH = 44, 44
		if type(sourceRect) == "table" and isFinite(sourceRect.x) then
			proxyW, proxyH = sourceRect.w, sourceRect.h
			if decl.grabAnchor == "preserve" then
				grabDX, grabDY = x - sourceRect.x, y - sourceRect.y
			else
				grabDX, grabDY = sourceRect.w / 2, sourceRect.h / 2
			end
		end
		local session: any = {
			sourcePath = sourcePath,
			decl = decl,
			payload = payload,
			mode = mode,
			pointerType = pointerType,
			reasons = {} :: { [string]: string? },
			overId = nil :: string?,
			velocity = drag_velocity.new(),
			grabDX = grabDX,
			grabDY = grabDY,
			proxyW = proxyW,
			proxyH = proxyH,
			proxyX = if type(sourceRect) == "table" then sourceRect.x else x,
			proxyY = if type(sourceRect) == "table" then sourceRect.y else y,
			proxyScale = 1,
			proxyHandle = nil :: any,
			scaleValue = nil :: any,
			motionScope = nil :: any,
		}
		local list, reasons = buildTargets()
		session.reasons = reasons
		session.session = drag_session.new({
			payload = payload,
			source = sourcePath,
			targets = list,
			onEnter = function(targetId: string)
				local target = targets[targetId]
				if target ~= nil and target.onEnter ~= nil then
					target.onEnter(payload)
				end
			end,
			onLeave = function(targetId: string)
				local target = targets[targetId] or retiring[targetId]
				if target ~= nil and target.onLeave ~= nil then
					target.onLeave(payload)
				end
			end,
			onPredict = function()
				-- the verdict is published AFTER the session settled its hover, so a
				-- consumer reading it inside enter/leave sees a consistent pair
			end,
		})
		session.targetList = list
		live = session
		heldSource:set(sourcePath)

		if proxyHost ~= nil then
			session.proxyHandle = proxyHost.show({
				sourcePath = sourcePath,
				payload = payload,
				blueprint = if decl.proxy ~= nil then decl.proxy() else nil,
				rect = sourceRect,
				mode = mode,
			})
		end
		-- PICKUP SCALE is a persistent spring RETARGETED, never recreated: a rapid
		-- grab-release-grab reverses smoothly through the same physics instead of
		-- restarting from 1.0 mid-flight.
		if motionClock ~= nil and session.proxyHandle ~= nil then
			local scale = motionClock:spring(1, decl.dragMotion or "object")
			session.scaleValue = scale
			local unsub = core:observe(scale, function()
				if live == session then
					session.proxyScale = scale:get()
					writeProxy()
				end
			end)
			session.disposeScale = function()
				unsub()
				scale:dispose()
			end
			scale:setTarget(1.15)
		else
			session.proxyScale = 1.15
		end
		moveProxyTo(x, y)
		session.velocity:push(x, y, now())
		-- the initial aim FIRST, the announcement LAST (director virtual-controller
		-- round): a `select` consumer that aims the fresh session (the §5.5 arm
		-- presentation aiming the first eligible row) must not have its aim
		-- stomped by this session's own opening hit-test
		updateAtInternal(x, y)
		emit("select", { source = sourcePath, payload = payload, mode = mode })
		return true
	end

	function updateAtInternal(x: number, y: number)
		if live == nil then
			return
		end
		live.lastX, live.lastY = x, y
		live.overId = overTargetAt(x, y, live.targetList)
		live.session:update(x, y)
		publishVerdict()
		notifyWatchers()
	end

	local function disposeSessionMotion()
		if live ~= nil and live.disposeScale ~= nil then
			live.disposeScale()
			live.disposeScale = nil
		end
		if live ~= nil and live.disposeHop ~= nil then
			-- the armed hop springs die with the session: a terminal flight owns
			-- the proxy from here (same ARCH-F1 rule as the chase handle)
			live.disposeHop()
			live.disposeHop = nil
			live.hopX = nil
			live.hopY = nil
		end
	end

	-- ===== terminals ======================================================
	local function resolveDrop(x: number, y: number, gestural: boolean)
		if live == nil then
			return { kind = "rejected" }
		end
		local session = live
		-- READ THE VELOCITY BEFORE ANY STATE RESET (SF-D2): the buffer that
		-- describes the gesture is the first thing a reset would throw away.
		local vx, vy = 0, 0
		if gestural then
			session.velocity:push(x, y, now())
			vx, vy = session.velocity:velocity()
		end
		session.overId = overTargetAt(x, y, session.targetList)
		local result = session.session:drop(x, y)
		disposeSessionMotion()
		-- ONE CANCEL SHAPE (ui-designer I-7; P5-F4). Releasing over the drag's OWN
		-- source is the put-it-back gesture, not a commit: same verb, same flight,
		-- same trace as every other cancel affordance.
		if result.kind == "dropped" and (result :: any).targetId == session.sourcePath then
			emit("cancel", {
				source = session.sourcePath,
				payload = session.payload,
				mode = session.mode,
				how = "overSource",
			})
			endSession()
			flyHome(session, vx, vy)
			return { kind = "cancelled", reason = "overSource" }
		end
		if result.kind == "dropped" then
			local targetPath = (result :: any).targetId
			local decl = targets[targetPath]
			local info = {
				targetId = targetPath,
				source = session.sourcePath,
				mode = session.mode,
				velocity = { x = vx, y = vy },
				-- the release POINT, not just the target identity: "which half of
				-- the row" is a question one target id cannot answer, and an
				-- insertion line needs it
				pointerX = x,
				pointerY = y,
			}
			emit("commit", { source = session.sourcePath, targetId = targetPath, payload = session.payload })
			if decl ~= nil then
				decl.onDrop(session.payload, info)
			end
			if session.decl.onCommitProxy == "flyToTarget" then
				-- TERMINAL FIRST, FLIGHT DETACHED: the session ends on the release
				-- frame (inert registry, clean verdict, a new gesture is legal) and
				-- the record flies on alone; `land` still fires on the ARRIVAL frame
				-- (the causal moment), which is the ratified split.
				endSession()
				flyTo(
					session,
					function()
						return centerAim(session, rectOf(targetPath))
					end,
					vx,
					vy,
					function(arrival: any)
						heldSource:set(nil)
						emit("land", {
							source = session.sourcePath,
							targetId = targetPath,
							payload = session.payload,
							how = arrival.how,
							targetLost = arrival.targetLost,
						})
					end
				)
				return result
			end
			hideProxy()
			heldSource:set(nil)
			emit(
				"land",
				{ source = session.sourcePath, targetId = targetPath, payload = session.payload, how = "instant" }
			)
			endSession()
			return result
		end
		-- The payload goes home under the motion contract either way, carrying the
		-- release velocity when the gesture had one and zero when it did not — the
		-- SAME path, so a keyboard cancel and a thrown card cannot drift. The VERB
		-- differs (I-7): a release over NOTHING is the free-area cancel gesture;
		-- `reject` is reserved for a refusal WITH a target (and its reason code),
		-- so a game's "why was this refused" handler never sees a reason-less
		-- event that was really a player putting the card away.
		if session.overId == nil then
			emit("cancel", {
				source = session.sourcePath,
				payload = session.payload,
				mode = session.mode,
				how = "freeRelease",
			})
		else
			emit("reject", {
				source = session.sourcePath,
				payload = session.payload,
				targetId = session.overId,
				reason = session.reasons[session.overId],
				mode = session.mode,
			})
		end
		-- terminal first, flight detached (same rule as the commit flight above)
		endSession()
		flyHome(session, vx, vy)
		return result
	end

	local registry = {}

	registry.verdict = verdict

	-- ===== registration ===================================================
	--[[ A SOURCE THAT VANISHES ENDS ITS DRAG — unless it declared itself RECYCLED.

		The symmetric half of finding F5, which handled a TARGET vanishing under a
		live drag. The source side had nothing, and the consequence is worse,
		because the ghost is not parented to the source: the drag proxy is its own
		screen on the presenter's scope, destroyed only when the registry is
		disposed. So a surface that dropped its sources mid-drag left the ghost
		painted over whatever was underneath, while the stale session refused every
		new pickup (`arm` and the tap-to-arm path both bail while one exists) and
		stayed committable onto anything that remounted beneath it.

		`recycled` is what separates "windowed out of a live list" from "torn down"
		— see its header in `drag_contract`. Liveness cannot: a minimised director
		table still has a live HUD root above it.

		`cancel` is the whole fix: it flies the ghost home, clears `heldSource` and
		the verdict, and emits the same `cancel` event every other cancel affordance
		does, so no consumer needs new vocabulary. ]]
	function registry.registerSource(path: string, decl: any): () -> ()
		sources[path] = decl
		return function()
			if sources[path] == decl then
				sources[path] = nil
			end
			if pending ~= nil and pending.path == path then
				pending = nil
			end
			if live ~= nil and live.sourcePath == path and decl.recycled ~= true then
				registry.cancel("sourceUnmounted")
			end
		end
	end

	-- REMOVING AN ARMED/HOVERED TARGET MID-SESSION (finding F5): the rebuild
	-- drops it from the array and `session:retarget` re-evaluates hover at the
	-- last position, which fires exactly one `leave` and clears the verdict. The
	-- session stays live with no hovered target; an in-flight return flight
	-- whose anchor vanished resolves by settle with `targetLost`.
	function registry.registerTarget(path: string, decl: any): () -> ()
		if targets[path] == nil then
			table.insert(targetOrder, path)
		end
		targets[path] = decl
		registry.refreshTargets()
		return function()
			if targets[path] ~= decl then
				return
			end
			targets[path] = nil
			local index = table.find(targetOrder, path)
			if index ~= nil then
				table.remove(targetOrder, index)
			end
			retiring[path] = decl
			registry.refreshTargets()
			retiring[path] = nil
		end
	end

	-- re-resolve every target rect and re-run the hover at the last pointer
	-- position. Called after a scroll write (in the SAME frame), after a reflow,
	-- and whenever the target set changes.
	function registry.refreshTargets()
		if live == nil then
			return
		end
		local list, reasons = buildTargets()
		live.targetList = list
		live.reasons = reasons
		live.session:retarget(list)
		if live.lastX ~= nil then
			live.overId = overTargetAt(live.lastX, live.lastY, list)
		end
		publishVerdict()
	end

	-- ===== pointer acquisition (detector and capture share this) ==========
	function registry.pointerDown(path: string, pos: any): boolean?
		if disposed or sources[path] == nil then
			return nil
		end
		local decl = sources[path]
		local pointerType = if type(pos) == "table" then pos.pointerType else nil
		if decl.declineTouch == true and tokens.classForPointerType(pointerType) == "touch" then
			-- DECLINE so the native scroll host under this node keeps the pan.
			-- Touch reorder rides a grip that does not decline (Table precedent).
			return false
		end
		pending = { path = path, startX = pos.x, startY = pos.y, pointerType = pointerType }
		return nil
	end

	function registry.pointerMove(path: string, pos: any)
		if disposed then
			return
		end
		if live ~= nil and live.mode == "pointer" then
			live.velocity:push(pos.x, pos.y, now())
			moveProxyTo(pos.x, pos.y)
			updateAtInternal(pos.x, pos.y)
			return
		end
		local press = pending
		if press == nil or press.path ~= path then
			return
		end
		-- ONE promotion test, from ONE token table, for every acquisition path
		if
			not tokens.promoted(
				pos.x - press.startX,
				pos.y - press.startY,
				press.pointerType,
				sources[path] and sources[path].promotionPx or promotionOverrides
			)
		then
			return
		end
		pending = nil
		beginSession(path, "pointer", pos.x, pos.y, press.pointerType)
	end

	-- returns "tap" for a release under the promotion threshold. On the raw
	-- capture path the native Activate fires on its own and the caller ignores
	-- this; on the LIVE UIDragDetector path the detector CONSUMES the click
	-- (measured 2026-07-27: a detector on a GuiButton suppresses `.Activated` —
	-- the fake mirror preserved it, which is why headless stayed green), so the
	-- caller must dispatch the tap itself. Taps are never eaten, on every
	-- acquisition path — that is SF-D3's live half.
	function registry.pointerUp(path: string, pos: any): string?
		if disposed then
			return nil
		end
		if live ~= nil and live.mode == "pointer" then
			resolveDrop(pos.x, pos.y, true)
			return nil
		end
		if pending ~= nil and pending.path == path then
			pending = nil
			return "tap"
		end
		return nil
	end

	function registry.pointerCancel(path: string, reason: string?): boolean?
		if disposed then
			return nil
		end
		if pending ~= nil and pending.path == path then
			pending = nil
		end
		if live ~= nil and live.mode == "pointer" then
			registry.cancel(reason or "pointerCancel")
			-- the origin node unmounting mid-drag must NOT kill the capture (ADR-0008)
			return true
		end
		return nil
	end

	-- UIDragDetector form of the same three moments. The engine's own threshold
	-- decides when it starts telling us about the drag; the framework's token
	-- still decides when that becomes a session, so the promotion rule is one
	-- rule on every adapter.
	function registry.detectorHandlers(path: string)
		return {
			onStart = function(pos: any)
				registry.pointerDown(path, pos)
			end,
			onContinue = function(pos: any)
				registry.pointerMove(path, pos)
			end,
			-- the "tap" outcome is RETURNED so the wiring that owns the node-tap
			-- dispatch (the renderer) can fire it — the live detector consumed
			-- the click, so nobody else will (see pointerUp)
			onEnd = function(pos: any): string?
				return registry.pointerUp(path, pos)
			end,
		}
	end

	-- the armed ghost's hop: ONE persistent spring pair per session, retargeted
	-- (never recreated) so rapid steps reverse smoothly instead of restarting.
	-- No clock = instant placement, the same rule the flights follow.
	local function springProxyTo(px: number, py: number)
		if motionClock ~= nil and live.proxyHandle ~= nil then
			if live.hopX == nil then
				local className = live.decl.dragMotion or "object"
				local session = live
				local hx = motionClock:spring(session.proxyX, className)
				local hy = motionClock:spring(session.proxyY, className)
				local function ride()
					if live ~= session then
						return
					end
					session.proxyX = hx:get()
					session.proxyY = hy:get()
					writeProxy()
				end
				local unX = core:observe(hx, ride)
				local unY = core:observe(hy, ride)
				session.hopX = hx
				session.hopY = hy
				session.disposeHop = function()
					unX()
					unY()
					hx:dispose()
					hy:dispose()
				end
			end
			live.hopX:setTarget(px)
			live.hopY:setTarget(py)
		else
			live.proxyX = px
			live.proxyY = py
			writeProxyFor(live)
		end
	end

	-- ===== non-pointer paradigm: arm → navigate → commit (SF-D4) ==========
	function registry.arm(sourcePath: string): boolean
		if disposed or live ~= nil or sources[sourcePath] == nil then
			return false
		end
		local rect = rectOf(sourcePath)
		local x, y = centerOf(rect)
		if x == nil then
			return false
		end
		local began = beginSession(sourcePath, "armed", x :: number, y :: number, nil)
		-- a parked ghost travels on the PICKUP, not on the first aim (row
		-- SF-D14): the card leaving the dock is what says "you are holding it",
		-- and waiting for a focus move would leave a tap-armed card sitting in
		-- its own slot looking un-picked-up.
		if began and live ~= nil and live.decl.armStaging ~= nil then
			local at = live.decl.armStaging()
			if type(at) == "table" and type(at.x) == "number" and type(at.y) == "number" then
				springProxyTo(at.x, at.y)
			end
		end
		return began
	end

	-- move the predicted target to a mounted target node. The SAME session and
	-- the SAME hit-test run: the armed paradigm aims at the target's centre, so
	-- legality, enter/leave and the verdict are literally the pointer code path.
	function registry.armTo(targetPath: string): boolean
		if live == nil or live.mode ~= "armed" then
			return false
		end
		if not pathLive(targetPath) then
			-- a RETIRING target is not aimable (ARCH-F2): the armed paradigm must
			-- skip it exactly as resolution excludes it
			return false
		end
		local x, y = centerOf(rectOf(targetPath))
		if x == nil then
			return false
		end
		-- THE GHOST RIDES THE AIM (director virtual-controller round; RR
		-- SponsorGesture §3 "the ghost springs from its dock slot to the focused
		-- row"): a picked-up card that never moves is indistinguishable from a
		-- card that was never picked up. Aiming is logical and instant
		-- (updateAtInternal below); the ghost SPRINGS after it.
		--
		-- ...UNLESS THE SOURCE PARKED IT (row SF-D14; RascalRally §11 D-2, the
		-- ratified "one fixed staging spot above the dock"). The aim, the verdict
		-- and the commit flight are unchanged — only where the ghost WAITS moves,
		-- so the row carries the aim and the card never sits on the name it is
		-- about to be played on. The spot was taken at the pickup and does not
		-- move with the aim, so this branch simply leaves the ghost alone.
		if live.decl.armStaging == nil then
			springProxyTo((x :: number) - live.grabDX, (y :: number) - live.grabDY)
		end
		updateAtInternal(x :: number, y :: number)
		return true
	end

	function registry.commit(): any
		if live == nil then
			return { kind = "rejected" }
		end
		local x, y = live.lastX, live.lastY
		if x == nil then
			x, y = centerOf(rectOf(live.sourcePath))
		end
		if x == nil then
			return registry.cancel("noTarget")
		end
		-- non-gestural commit: zero seed through the same consumer path
		return resolveDrop(x :: number, y :: number, live.mode == "pointer")
	end

	function registry.cancel(reason: string?): any
		if live == nil then
			pending = nil
			return { kind = "cancelled", reason = reason }
		end
		local session = live
		local result = session.session:cancel(reason)
		disposeSessionMotion()
		-- the third cancel affordance (Cancel action, modal presentation, an API
		-- cancel) — same `cancel` verb as the gestural forms (I-7); `dismiss`
		-- belongs to surfaces and toasts, never to a drag
		emit("cancel", {
			source = session.sourcePath,
			payload = session.payload,
			reason = reason,
			mode = session.mode,
			how = "action",
		})
		-- terminal first, flight detached; and CANCEL IS ALWAYS ZERO-SEED,
		-- whatever the finger was doing: a cancel is not a throw, and inheriting
		-- the gesture's momentum would read as the drag still being obeyed.
		endSession()
		flyHome(session, 0, 0)
		return result
	end

	-- FINDING F7: a modal presenting mid-drag cancels the session. A focus trap
	-- and a drag proxy cannot coexist — the player would be holding something
	-- they can no longer aim. The presenter calls this on every surface it puts
	-- up; only trapping surfaces cancel.
	function registry.surfacePresented(kind: string?)
		if live ~= nil and (kind == "modal" or kind == "sheet" or kind == "alert") then
			registry.cancel("modalPresented")
		end
	end

	-- ===== reads ==========================================================
	-- subscribe to "the session moved / began / ended". Fires on every hover
	-- update and on every terminal, with `{ active = false }` when the session
	-- is gone. Returns an unsubscribe.
	function registry.onUpdate(fn: (state: any) -> ()): () -> ()
		table.insert(watchers, fn)
		return function()
			local index = table.find(watchers, fn)
			if index ~= nil then
				table.remove(watchers, index)
			end
		end
	end

	-- collaborators may arrive AFTER the registry exists: the presentation layer
	-- (the feedback bus, the drag-proxy layer, the motion clock) is built around
	-- a presented surface, so a registry that could only be configured at
	-- construction would force every host to guess the mount order. Each is read
	-- live, so a swap takes effect on the next gesture.
	-- `false` CLEARS a collaborator (nil cannot: it does not survive table
	-- iteration). The presenter wires every surface automatically, so `false`
	-- is how a degraded host — or a test isolating one collaborator — opts a
	-- pre-wired one back out.
	local function collaboratorValue(value: any): any
		return if value == false then nil else value
	end
	function registry.setCollaborators(collaborators: { [string]: any })
		if collaborators.now ~= nil then
			now = collaboratorValue(collaborators.now) or now
		end
		if collaborators.feedback ~= nil then
			feedback = collaboratorValue(collaborators.feedback)
		end
		if collaborators.proxy ~= nil then
			proxyHost = collaboratorValue(collaborators.proxy)
		end
		if collaborators.motionClock ~= nil then
			motionClock = collaboratorValue(collaborators.motionClock)
		end
		if collaborators.promotionPx ~= nil then
			promotionOverrides = collaboratorValue(collaborators.promotionPx)
		end
	end

	function registry.isActive(): boolean
		return live ~= nil
	end

	function registry.session(): any
		return if live ~= nil then live.session else nil
	end

	function registry.payload(): any
		return if live ~= nil then live.payload else nil
	end

	function registry.mode(): string?
		return if live ~= nil then live.mode else nil
	end

	function registry.sourcePath(): string?
		return if live ~= nil then live.sourcePath else nil
	end

	-- the pointer point the autoscroll host feeds its band test (nil when no
	-- gesture is live), in the same space as the solver rects
	function registry.pointerPosition(): { x: number, y: number }?
		if live == nil or live.lastX == nil then
			return nil
		end
		return { x = live.lastX, y = live.lastY }
	end

	-- the target the live interaction is on. The focus graph's active-interaction
	-- exemption reads this: a row that is being dropped onto never loses its
	-- focusability mid-gesture just because its own predicate flipped.
	function registry.interactionTarget(): string?
		if live == nil then
			return nil
		end
		return live.session:state().hovered or live.overId
	end

	function registry.dump()
		local targetPaths = orderedTargetPaths()
		local sourcePaths: { string } = {}
		for path in sources do
			table.insert(sourcePaths, path)
		end
		table.sort(sourcePaths)
		return {
			schema = "facet-drag-registry-dump/1",
			sources = sourcePaths,
			targets = targetPaths,
			active = live ~= nil,
			mode = if live ~= nil then live.mode else nil,
			source = if live ~= nil then live.sourcePath else nil,
			verdict = verdict:get(),
		}
	end

	-- the held-source Readable (the renderer binds it to the `luau-drag-held`
	-- state; any consumer may read it the same way it reads the verdict)
	registry.heldSource = heldSource

	function registry.dispose()
		heldSource:set(nil)
		if disposed then
			return
		end
		if live ~= nil then
			disposeSessionMotion()
			hideProxy()
			live.session:cancel("dispose")
		end
		-- detached flights die with the registry: their springs and ghost handles
		-- must not outlive the surface (registry-neutral teardown, SF-C1)
		for record in detachedFlights do
			record.flightDone = true
			hideProxyFor(record)
		end
		disposed = true
		endSession()
		table.clear(sources)
		table.clear(targets)
		table.clear(targetOrder)
		table.clear(watchers)
		-- the verdict and held-source signals are the registry's core resources; a
		-- surface torn down and rebuilt must return the core's counters to baseline
		if type((verdict :: any).dispose) == "function" then
			(verdict :: any):dispose()
		end
		if type((heldSource :: any).dispose) == "function" then
			(heldSource :: any):dispose()
		end
	end

	return registry
end

return drag_registry
