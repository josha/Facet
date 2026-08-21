--!strict
--[[ SCROLL SNAPPING — where a scrolling collection is allowed to come to REST
	(director ruling 2026-08-18).

	WHAT WAS MISSING. The adapt audit parked the shipped card rail mid-card (x=77
	on a 140px pitch), let it settle for thirty frames, and read x=77 back: nothing
	in `src/` snapped, and no author could make it. The compact "one card per
	swipe" paradigm — the director's own worked example — could not be BUILT, let
	alone defaulted (`artifacts/release-candidate-review/adapt-audit/matrix.md`,
	B-7, "MISSING — no route at all, not even authored").

	WHAT THIS IS. Two halves, and the split is the same one `input/autoscroll.luau`
	makes: `resolve` is PURE ARITHMETIC over an extent index — given where the
	scroll came to rest, where the travel started, and how fast it went, which
	offset should it hold? — and `new` is the small state machine that decides WHEN
	to ask and animates the answer. Neither half owns a scroll driver: the host
	control writes, through the same `controller.scrollTo` seam its keep-visible
	already uses (native §4, "the framework's ONE programmatic scroll write").

	THE ENGINE HAS NO SNAP AND NO RELEASE EVENT, which is what shapes everything
	below. A Roblox `ScrollingFrame` owns the pan and the momentum; the framework
	sees only `CanvasPosition` changes arriving through `observeScroll`. So:

	  · "the gesture released" is not observable — what IS observable is that the
	    offset STOPPED CHANGING. The settle detector is therefore a quiet window
	    (`QUIET_S`) re-armed by every sample, and its expiry is the release;
	  · "release velocity" is not observable either. The peak SPEED across the
	    travel is, from the samples themselves, and it separates a flick (which
	    must advance) from a nudge (which must fall back) exactly as well. It is
	    timed by the QUIET RAMP ITSELF — a linear 0->1 glide over `QUIET_S`, so
	    the seconds between two samples are `ramp * QUIET_S` — rather than by a
	    second time source. One clock drives the detector, the timing and the
	    travel, which is why a scripted `pres.tick(dt)` replays a flick exactly;
	  · nothing here listens to raw input. There is no second scroll driver and no
	    pointer listener — the input inventory's authority rules
	    (`artifacts/release-candidate-review/input/ias-authority.md`) leave the
	    gesture with the engine and this module downstream of the mirror.

	ONE EXTENT SOURCE, NEVER A SECOND ARITHMETIC. The boundaries a settle may land
	on are `index.offsetOf(i)` — the SAME `src/virtual_extents.luau` index the
	windowing already divides by, handed in by the host. A variable-extent list
	therefore snaps to its measured boundaries with no extra code, and there is no
	parallel pitch calculation that could drift from the one the window uses.

	THE END OF THE LIST IS A REST OF ITS OWN. `maxScroll` is a legal landing place
	even though no item starts there: the last page shows the tail flush. Without
	that rule a rail whose final boundary lies past `maxScroll` snaps to a clamped
	target, reads back a different offset, and snaps again — the overscroll
	oscillation the anchor discipline warns about, arriving through the fix
	for something else. Every candidate is clamped and the terminal is in the
	candidate set, so a settle at the end resolves to the end and stops.

	AN ITEM LONGER THAN THE VIEWPORT DISABLES SNAP FOR THAT SETTLE. Alignment would
	mean the player cannot stop anywhere inside a tall row and read the rest of it.
	Content access beats alignment — the same ruling the localization rule makes
	when copy expands past its box (§15.3), applied to the scroll axis.

	REDUCED MOTION COSTS NOTHING EXTRA. The travel is a `clock:spring` value of the
	DEFAULT `decorative` kind, so `setTarget` under reduced motion places the
	offset at the terminus instantly and announces the same arrival on the same
	frame (`src/motion/motion.luau`, I-4). The instant placement is the motion
	authority's, not a second policy here.

	IT COSTS NOTHING WHILE IDLE. Both motion values are built on the FIRST sample
	of an enabled scroller and both are `settled` at rest, and a settled value has
	left the clock (`motion.luau`: "a fresh glide starts settled and costs the
	clock nothing until something aims it"). A snapping list that nobody is
	touching runs zero per-frame work — asserted in `tests/scroll_snap.spec.luau`
	against `clock:activeCount()` and the clock's own write counter.

	WITHOUT A MOTION CLOCK THERE IS NO SNAP, deliberately. The clock is the one
	sanctioned frame source in this framework (`presenter.onTick`), a control
	reaches it only through the contribution's `bindMotion`, and settle detection
	is a question about frames. A standalone mount that never meets a presenter
	keeps exactly today's behaviour rather than getting a worse imitation of this
	one.

	Public interface: `scroll_snap.MODES`, `scroll_snap.resolve(req) -> px?`,
	`scroll_snap.keepVisible(...) -> px?`, `scroll_snap.new(ctx) -> Snap`.
	Depends on `src/num.luau` only.
]]

local num = require("../num")

local scroll_snap = {}

-- the public vocabulary of the `snap` key, in one place so a control's refusal
-- message and this module's own guard cannot disagree
scroll_snap.MODES = table.freeze({ none = true, item = true })
scroll_snap.DEFAULT_MODE = "none"

--[[ THE FOUR NUMBERS, and where each comes from.

	QUIET_S — how long the offset must hold still before a settle is called. It is
	a compromise between two real costs measured on touch scrollers everywhere: too
	short and a finger that pauses mid-drag has the content snapped out from under
	it; too long and the alignment arrives after the player has looked away. 0.12 s
	is ~7 frames at 60 Hz — longer than any gap in the engine's own momentum
	stream, short enough to read as part of the release. It is the one number here
	a real thumb can disagree with, so it is on the batched device pass.

	FLICK_PX_S — the speed above which a travel is a FLICK, and a flick must
	advance. Below it the settle rounds to whichever boundary is nearest, so a slow
	drag that did not clear an item's midpoint falls back where it started.

	MIN_TRAVEL_PX — a snap smaller than this is not a snap, it is the engine's own
	rounding, and writing it back would fight the engine forever (the sub-pixel
	rule the scroll anchor already keeps).

	TAKEOVER_PX — how far a sample may sit from what this module last wrote before
	it is read as the PLAYER, not as the echo of our own write. A finger landing on
	a rail mid-flight must win immediately; the engine's own clamp and rounding
	must not. ]]
scroll_snap.QUIET_S = 0.12
scroll_snap.FLICK_PX_S = 240
scroll_snap.MIN_TRAVEL_PX = 0.5
scroll_snap.TAKEOVER_PX = 2
-- the travel's feel: the built-in critically damped class every other
-- object-scale movement in this framework already uses (`src/motion/classes.luau`
-- — dampingRatio 1.0, response 0.28). A snap that overshot would look like the
-- list disagreeing with itself.
scroll_snap.TRAVEL_CLASS = "object"

local EPS = 1e-6
local isFinite = num.isFinite

--[[ modeReader(control, declared, fallback?) -> (use?) -> mode

	THE `snap` KEY, READ THE SAME WAY BY EVERY COLLECTION THAT HAS ONE. Both
	scrolling collections accept a string or a Readable of one, refuse anything
	outside the vocabulary by name, and fall back to a DEFAULT that the control may
	derive from something of its own (`newVirtualList`'s card arrangement: a rail
	resolved to one card per view is a pager, and pages snap). Two copies of that
	would be two places for the refusal message and the precedence to drift, which
	is the shape `native_scroll_binding.luau` already refuses for the mirror.

	A READABLE IS CHECKED AT READ TIME, not at construction: its value is only
	knowable then, and an unusable one is refused rather than quietly treated as
	off — a silent "off" is indistinguishable from the feature not existing, which
	is what this whole wave was about. ]]
function scroll_snap.modeReader(
	control: string,
	declared: any,
	fallback: ((use: any?) -> string)?
): (use: any?) -> string
	local isLive = type(declared) == "table" and type((declared :: any).get) == "function"
	local function check(value: any): string
		if type(value) ~= "string" or scroll_snap.MODES[value] == nil then
			error(
				`Facet {control}.snap must be "none" (the default — the collection rests wherever the engine's `
					.. `momentum left it) or "item" (it settles onto an item boundary on its scroll axis), or a `
					.. `Readable of one of those. Got '{tostring(value)}'.`,
				0
			)
		end
		return value
	end
	if declared ~= nil and not isLive then
		check(declared)
	end
	return function(use: any?): string
		if declared ~= nil then
			return check(if isLive then (if use ~= nil then use(declared) else (declared :: any):get()) else declared)
		end
		if fallback ~= nil then
			return (fallback :: any)(use)
		end
		return scroll_snap.DEFAULT_MODE
	end
end

-- ===== the pure half =======================================================

export type Request = {
	-- a `src/virtual_extents.luau` Index: the host's OWN window arithmetic
	index: any,
	-- the scroller's extent along its scroll axis
	viewport: number,
	-- where the offset came to rest (raw, straight off the mirror)
	offset: number,
	-- where this travel started: the last position the collection RESTED at
	origin: number,
	-- the peak speed seen during the travel, px/s, unsigned
	peak: number,
	flickPxPerS: number?,
}

-- the 1-based item whose LEADING EDGE is nearest `offset`. `slotAt` answers "how
-- many item midpoints has this offset passed", which is that question already —
-- and asking the index rather than re-deriving it is what keeps the uniform and
-- variable forms agreeing.
local function nearestIndex(ix: any, offset: number): number
	if ix.count <= 0 then
		return 1
	end
	return math.clamp(ix.slotAt(offset) + 1, 1, ix.count)
end

-- the largest item index whose leading edge is at or before `v` (the slot the
-- offset is INSIDE). `nearestIndex` is within one of it by construction, because
-- the midpoint partition it uses lies inside the slot.
local function floorIndex(ix: any, v: number): number
	local i = nearestIndex(ix, v)
	if ix.offsetOf(i) > v + EPS then
		i -= 1
	end
	return math.clamp(i, 1, math.max(1, ix.count))
end

-- ...and the smallest whose leading edge is at or after `v`
local function ceilIndex(ix: any, v: number): number
	local i = nearestIndex(ix, v)
	if ix.offsetOf(i) < v - EPS then
		i += 1
	end
	return math.clamp(i, 1, math.max(1, ix.count))
end

local function usable(ix: any, viewport: number): boolean
	return type(ix) == "table"
		and type(ix.count) == "number"
		and ix.count > 0
		and isFinite(viewport)
		and viewport > 0
		and isFinite(ix.content)
end

--[[ resolve(req) -> px? — WHERE THIS SETTLE SHOULD LAND, or nil for "leave it".

	nil is returned, and it is a full answer rather than a failure, when: nothing
	can scroll; the item under the offset or the one it would land on is taller
	than the viewport; or the answer is where the offset already is. ]]
function scroll_snap.resolve(req: Request): number?
	local ix = req.index
	if not usable(ix, req.viewport) or not isFinite(req.offset) then
		return nil
	end
	local maxScroll = math.max(0, ix.content - req.viewport)
	if maxScroll <= 0 then
		return nil -- the content fits: there is one resting place and it is here
	end
	local offset = math.clamp(req.offset, 0, maxScroll)
	local origin = math.clamp(if isFinite(req.origin) then req.origin else offset, 0, maxScroll)
	local landing = nearestIndex(ix, offset)

	--[[ A FLICK ADVANCES, AT LEAST ONE. Rounding to the nearest boundary alone
		makes a quick, SHORT flick undo itself: the engine's momentum dies inside the
		item the gesture started in, the nearest boundary is the one it left, and the
		rail springs back — the classic paging defect. So a travel whose peak speed
		cleared `FLICK_PX_S` may not land short of the next boundary in the direction
		it went; a hard fling that crossed several is untouched, because the nearest
		boundary is already further on. A slow drag is not a flick and keeps the
		round-to-nearest, which is what lets a player back out of a half-swipe. ]]
	local flickAt = if isFinite(req.flickPxPerS) then req.flickPxPerS :: number else scroll_snap.FLICK_PX_S
	local travel = offset - origin
	if isFinite(req.peak) and req.peak >= flickAt and math.abs(travel) > EPS then
		local direction = if travel > 0 then 1 else -1
		local least = math.clamp(nearestIndex(ix, origin) + direction, 1, ix.count)
		landing = if direction > 0 then math.max(landing, least) else math.min(landing, least)
	end

	--[[ CONTENT ACCESS BEATS ALIGNMENT. Both ends are asked: the item the player
		is currently INSIDE (snapping away from it would hide the part they are
		reading) and the item this settle would land on. Either one taller than the
		viewport and this settle simply does not snap. ]]
	if ix.extentOf(landing) > req.viewport + EPS or ix.extentOf(floorIndex(ix, offset)) > req.viewport + EPS then
		return nil
	end

	--[[ THE CANDIDATE SET IS THE BOUNDARIES *AND THE END*, and the end is a real
		member of it rather than a clamp artefact. A rail whose last item does not
		start at `maxScroll` — any rail whose viewport is not a whole number of
		pitches, which is most of them, and every one-up rail with a peek — has a
		final page that no boundary can express. Without the terminal in the set, a
		settle 5px short of the end is pulled 95px BACK to the last reachable
		boundary, and the player can never rest looking at the last card.

		NEARER WINS, and only near the end can the terminal be nearer at all: mid-list
		`maxScroll` is hundreds of pixels away and the comparison is never close. A
		flick needs no exemption from it, and was given one and then had it taken
		back: to be pulled BACK to the end a flick would have to leave it at speed
		and travel less than half a card, which is not a gesture a hand can make,
		and a rule for a case nobody can reach is a rule nothing can check. ]]
	local target = math.clamp(ix.offsetOf(landing), 0, maxScroll)
	if math.abs(maxScroll - offset) < math.abs(target - offset) then
		target = maxScroll
	end
	if math.abs(target - offset) < scroll_snap.MIN_TRAVEL_PX then
		return nil
	end
	return target
end

--[[ keepVisible(index, viewport, current, itemIndex, plain) -> px?

	KEEP-VISIBLE LANDS *ON* A BOUNDARY, NOT NEAR ONE. Focus traversal already
	brings an item into view through the shared minimal-scroll clamp
	(`solver.keepVisibleOffset`); under `snap = "item"` the position it computes is
	usually not a resting place, so the focused item would sit mid-page and the
	next settle would move it again.

	This rounds that answer OUTWARD in the direction the scroll is already going —
	the smallest boundary that still satisfies a forward scroll, the largest that
	satisfies a backward one — so the item stays fully visible AND the scroller
	rests where it is allowed to. `plain = nil` (already in band) stays nil: a
	visible item is not a reason to move the page.

	An item taller than the viewport keeps the plain answer, for `resolve`'s
	reason: no boundary can show all of it, so the minimal scroll is the honest
	one. ]]
function scroll_snap.keepVisible(ix: any, viewport: number, current: number, itemIndex: number, plain: number?): number?
	if plain == nil or not usable(ix, viewport) or not isFinite(plain) then
		return plain
	end
	local maxScroll = math.max(0, ix.content - viewport)
	if maxScroll <= 0 then
		return plain
	end
	local index = math.clamp(itemIndex, 1, ix.count)
	if ix.extentOf(index) > viewport + EPS then
		return plain
	end
	local wanted = math.clamp(plain :: number, 0, maxScroll)
	local forward = wanted > current
	local aligned = if forward
		then math.clamp(ix.offsetOf(ceilIndex(ix, wanted)), 0, maxScroll)
		else math.clamp(ix.offsetOf(floorIndex(ix, wanted)), 0, maxScroll)
	--[[ THE END AGAIN. Rounding a forward scroll UP can ask for a boundary past
		the terminal; the clamp above lands it on the terminal, which is a legal
		rest and still shows the item. Rounding a backward scroll DOWN can never
		leave the item short, because `plain` for a backward scroll IS the item's
		own leading edge and that is a boundary. ]]
	return aligned
end

-- ===== the state machine ===================================================

export type Ctx = {
	core: any,
	-- the control's own scope: every motion value built here is owned by it, so a
	-- disposed control leaves nothing registered on the presenter's clock
	scope: any,
	-- the live extent index and viewport, read at settle time (never cached: a
	-- rotation or a text-size change moves both between one sample and the next)
	index: () -> any,
	viewport: () -> number,
	-- "none" | "item", read live so an adaptive default can flip with the facts
	mode: () -> string,
	-- the host's own programmatic scroll write, already clamped and already
	-- routed through its bound controller
	write: (offset: number) -> (),
	quietS: number?,
	flickPxPerS: number?,
}

export type Snap = {
	-- a `CanvasPosition` sample, straight from the mirror
	sample: (offset: number) -> (),
	-- the FRAMEWORK moved the scroll (keep-visible, a programmatic scrollTo, the
	-- variable-extent anchor correction). It is a new resting place, not a travel:
	-- announcing it stops the echo being read as a gesture the player never made.
	rest: (offset: number) -> (),
	bindMotion: (clock: any) -> (),
	dispose: () -> (),
	-- for tests and `dump()`: never for behaviour
	debug: () -> { [string]: any },
}

function scroll_snap.new(ctx: Ctx): Snap
	local quietS = if isFinite(ctx.quietS) then ctx.quietS :: number else scroll_snap.QUIET_S
	local clock: any = nil
	-- the quiet window, as a 0->1 ramp whose ARRIVAL is the signal. Its number is
	-- read by nobody; what it publishes is "the offset has held still for one
	-- window". `informational`, because under reduced motion a settle detector
	-- that placed itself instantly would fire on the first sample of a gesture
	-- and snap the content out from under a live finger.
	local quiet: any = nil
	local quietRelease: (() -> ())? = nil
	-- the travel itself
	local flight: any = nil
	local flightTarget: number? = nil
	local flightActive = false
	local lastWrite: number? = nil

	local origin = 0
	local peak = 0
	local lastOffset = 0
	-- whether `lastOffset` describes a sample of the CURRENT travel (a speed needs
	-- two samples, and the first one after a rest has no predecessor)
	local hasPrevious = false
	local disposed = false

	local function enabled(): boolean
		return ctx.mode() == "item"
	end

	local function markRest(at: number)
		origin = at
		lastOffset = at
		hasPrevious = false
		peak = 0
		flightActive = false
		flightTarget = nil
	end

	local function cancelFlight()
		if flight ~= nil and flightActive then
			flight:stop()
		end
		flightActive = false
		flightTarget = nil
	end

	--[[ THE FLIGHT'S WRITES, and why arrival is detected HERE rather than on the
		value's own `onSettle`. Under reduced motion `setTarget` PLACES the value and
		announces the arrival in the same call, so a settle handler that cleared the
		flight could run before the observer that writes it. Watching the value
		itself — write every step, and call it arrived when the step IS the terminus
		— gives one code path for the animated and the instant case, in whichever
		order the flush delivers them. ]]
	local function onFlightValue(v: number)
		if disposed or not flightActive or flightTarget == nil then
			return
		end
		local target = flightTarget :: number
		--[[ THE LAST WRITE IS THE TARGET ITSELF, EXACTLY. A spring is settled by an
			epsilon, not by equality, so the frame it arrives on is a fraction of a
			pixel short — and a snap that stops 0.4px off a boundary is a snap that
			did not happen, because the next settle reads that offset back and has
			nothing left to do about it. Arrival closes the gap in the same write. ]]
		local arrived = math.abs(v - target) < scroll_snap.MIN_TRAVEL_PX
		local value = if arrived then target else v
		lastWrite = value
		ctx.write(value)
		if arrived then
			markRest(target)
		end
	end

	local function beginFlight(from: number, to: number)
		if flight == nil or math.abs(to - from) < scroll_snap.MIN_TRAVEL_PX then
			markRest(from)
			return
		end
		-- start from where the ENGINE actually is, never from the last terminus:
		-- the player has been driving this offset since the previous flight
		flight:snap(from)
		flightTarget = to
		flightActive = true
		lastWrite = from
		flight:setTarget(to)
	end

	local function attemptSnap()
		if disposed or flightActive or not enabled() then
			peak = 0
			return
		end
		local offset = lastOffset
		local target = scroll_snap.resolve({
			index = ctx.index(),
			viewport = ctx.viewport(),
			offset = offset,
			origin = origin,
			peak = peak,
			flickPxPerS = ctx.flickPxPerS,
		})
		if target == nil then
			markRest(offset)
			return
		end
		beginFlight(offset, target)
	end

	--[[ BUILT ON THE FIRST SAMPLE OF AN ENABLED SCROLLER, never at construction.
		A list whose `snap` is "none" — every list that ships today — allocates
		nothing here and registers nothing with the clock, so this feature is
		invisible in both the instance census and the clock's stats until somebody
		asks for it. It is also why an adaptive default that flips ON at a rotation
		works with no re-mount: the next sample builds what it needs. ]]
	local function ensureValues(): boolean
		if disposed or clock == nil then
			return false
		end
		if quiet ~= nil then
			return true
		end
		--[[ `quantum` is set explicitly because this ramp is also the CLOCK the
			speed estimate reads. An `informational` value under reduced motion
			writes only every `quantum` seconds by default (0.1 s — coarser sweep,
			same terminus), and a sample reading a ramp that stale would price a
			flick at up to eight times its real speed. A per-frame quantum costs one
			number write per frame while a finger is on the rail and nothing at all
			at rest. ]]
		quiet = ctx.scope:own(clock:glide(0, { duration = quietS, kind = "informational", quantum = 1 / 240 }))
		quietRelease = quiet:onSettle(attemptSnap)
		ctx.scope:own(function()
			if quietRelease ~= nil then
				quietRelease()
				quietRelease = nil
			end
		end)
		flight = ctx.scope:own(clock:spring(0, scroll_snap.TRAVEL_CLASS))
		ctx.scope:own(ctx.core:observe(flight, onFlightValue))
		return true
	end

	local self: Snap = {} :: any

	function self.sample(offset: number)
		if disposed or not isFinite(offset) then
			return
		end
		if not enabled() then
			-- keep the resting place current so a mode that flips ON later starts
			-- its first travel from where the player actually left the scroller
			cancelFlight()
			markRest(offset)
			return
		end
		if flightActive then
			if lastWrite ~= nil and math.abs(offset - (lastWrite :: number)) <= scroll_snap.TAKEOVER_PX then
				return -- the echo of our own write
			end
			-- A HAND ON A MOVING RAIL WINS. The flight is abandoned where it stands
			-- and this sample opens a fresh travel from the player's own position.
			cancelFlight()
			markRest(offset)
		end
		if not ensureValues() then
			return -- no clock: no frames, no settle detection, today's behaviour
		end
		--[[ HOW FAST, IN SECONDS, WITH NO SECOND CLOCK. The quiet ramp was set to 0
			at the previous sample and rises linearly to 1 over `quietS`, so its value
			right now IS the fraction of a window that has passed since then. Two
			samples in one frame read 0 and are skipped rather than dividing by it. ]]
		if hasPrevious then
			local sinceS = math.max(0, math.min(1, quiet:get())) * quietS
			if sinceS > 0 then
				peak = math.max(peak, math.abs(offset - lastOffset) / sinceS)
			end
		end
		lastOffset = offset
		hasPrevious = true
		-- re-arm: the ramp restarts at 0 and its arrival at 1 is one whole quiet
		-- window with no sample in it (`snap` announces nothing — the placement
		-- rule `progress_view`'s indeterminate cycle relies on for the same reason)
		quiet:snap(0)
		quiet:setTarget(1)
	end

	function self.rest(offset: number)
		if disposed or not isFinite(offset) then
			return
		end
		cancelFlight()
		if quiet ~= nil then
			quiet:stop() -- abandoned, not arrived: no settle event
		end
		markRest(offset)
		lastWrite = offset
	end

	function self.bindMotion(motionClock: any)
		if disposed or motionClock == nil or clock ~= nil then
			-- a second clock would give this scroller two frame sources; the first
			-- one delivered is the presenter's and it is the one that stays
			return
		end
		clock = motionClock
	end

	function self.dispose()
		disposed = true
		cancelFlight()
		-- the values and the observer are owned by the control's scope, which is
		-- what disposes them; nothing is registered anywhere else
	end

	function self.debug(): { [string]: any }
		return {
			mode = ctx.mode(),
			armed = quiet ~= nil,
			flying = flightActive,
			origin = origin,
			peak = peak,
			lastOffset = lastOffset,
			target = flightTarget,
		}
	end

	return self
end

return scroll_snap
