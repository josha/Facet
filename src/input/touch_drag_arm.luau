--!strict
--[[ WHOSE GESTURE IS THIS FINGER'S? — the touch arbitration between a DRAG and
	the scroll or swipe underneath it.

	THE DEFECT THIS EXISTS FOR, measured live on a phone (the Studio device
	emulator's `iphone_16`, portrait, real `UserInputType.Touch`): the Discover feed could not
	be scrolled AT ALL. A 230 px upward drag starting on a grid card left the
	scroller's `CanvasPosition` at exactly `0, 0`. Disabling the three
	`UIDragDetector`s the cards carry and repeating the identical gesture scrolled
	it to `0, 249.2`. So the detector CLAIMS the touch on press, and everything
	underneath — the scroller, and a swipeable row's own recogniser — is starved
	of a gesture the player never meant as a drag.

	A MOUSE CAN AFFORD TO DECIDE BY TRAVEL; A FINGER CANNOT. `interaction_tokens`
	already gates press→drag promotion on distance (6 px pointer, 14 px touch),
	and that gate is the right one once the drag is under way — but it is asked
	too late. By the time a finger has travelled 14 px the engine's detector has
	owned the touch for several frames and the scroller has already lost it. And
	distance cannot separate the two intentions in the first place: a scroll and a
	drag both begin as a finger moving across a card. The only thing that
	distinguishes them at the moment of the press is that a player who means to
	DRAG holds still first. That is the platform convention on both phone
	platforms (press-and-hold to pick up, swipe to scroll), so it is also what a
	player already expects.

	So: a touch arms a drag by TIME, and disarms itself by TRAVEL.

	  · finger down          -> pending: nothing is claimed, the scroller is free
	  · moves past the slop  -> released for good; this gesture can never become a
	                            drag, and the scroll or swipe underneath keeps it
	  · held past the hold   -> armed; the drag acquisition may take it
	  · lifts while pending  -> a tap, which was never in doubt

	ONE GESTURE, ONE OUTCOME. `state` never returns to `pending` once it has left
	it, so a gesture that scrolled cannot also drag and a gesture that armed cannot
	also scroll. Re-arming needs a fresh `press`.

	A MOUSE IS NOT ARBITRATED. A mouse press arms immediately: nothing is
	contended for it (a scroller takes the wheel, not the button) and asking a
	player to hold a mouse still for a third of a second before a drag would be a
	regression on every desk. `press` arms at once for any non-touch pointer, so
	the caller never needs two code paths.

	PURE, AND THAT IS THE POINT. The live half of this — WHO drives an armed
	finger, given that the engine will not hand a `UIDragDetector` a touch that
	was already down when it was switched on — is an engine fact, measured
	separately and recorded in `client/screen_target`'s `setDragDetector`. What is
	testable is the policy, and the policy is here, with no clock, no instance and
	no engine: `press`, `move` and `tick` are given their own numbers by whoever
	owns them, and `session` below sequences the effects without naming one.
]]

local interaction_tokens = require("./interaction_tokens")

local touch_drag_arm = {}

export type State = "idle" | "pending" | "armed" | "released"

export type Arm = {
	-- the gesture's current verdict; `released` means "this one belongs to
	-- whatever is underneath" and is terminal until the next `press`
	state: (self: Arm) -> State,
	-- a pointer went down. `pointerType` is the adapter's own string ("touch",
	-- "mouse", "pen", nil); anything that is not touch arms immediately
	press: (self: Arm, pointerType: string?, x: number, y: number, nowMs: number) -> State,
	-- the pointer moved while the press is live
	move: (self: Arm, x: number, y: number, nowMs: number) -> State,
	-- time passed with the pointer still down (a frame, a timer, a test)
	tick: (self: Arm, nowMs: number) -> State,
	-- the pointer came up, or the gesture was cancelled
	release: (self: Arm) -> (),
}

export type Tuning = {
	holdMs: number?,
	slopPx: number?,
}

function touch_drag_arm.new(tuning: Tuning?): Arm
	local tokens = interaction_tokens.touchDragArm
	local holdMs = if tuning ~= nil and tuning.holdMs ~= nil then tuning.holdMs else tokens.holdMs
	local slopPx = if tuning ~= nil and tuning.slopPx ~= nil then tuning.slopPx else tokens.slopPx
	local slopSq = slopPx * slopPx

	local state: State = "idle"
	local startX, startY, startMs = 0, 0, 0

	local self = {}

	function self:state(): State
		return state
	end

	function self:press(pointerType: string?, x: number, y: number, nowMs: number): State
		startX, startY, startMs = x, y, nowMs
		--[[ A NON-TOUCH PRESS IS NOT CONTENDED (see the header). `classForPointerType`
			is the same mapping the promotion gate uses, so "what counts as a finger"
			is answered in exactly one place — a pen arms at once, like the mouse it
			behaves as. ]]
		if interaction_tokens.classForPointerType(pointerType) ~= "touch" then
			state = "armed"
		else
			state = "pending"
		end
		return state
	end

	function self:move(x: number, y: number, nowMs: number): State
		if state ~= "pending" then
			return state -- armed drags and released gestures are both decided
		end
		local dx, dy = x - startX, y - startY
		if (dx * dx + dy * dy) >= slopSq then
			state = "released"
			return state
		end
		--[[ TIME PASSES ON A MOVE TOO. A finger that trembles inside the slop for
			half a second has still been held, and a player who feels the hold land
			expects the drag whether or not a `tick` happened to arrive first. Without
			this, a gesture could sit in `pending` indefinitely on a host that only
			reports motion. ]]
		return self:tick(nowMs)
	end

	function self:tick(nowMs: number): State
		if state == "pending" and (nowMs - startMs) >= holdMs then
			state = "armed"
		end
		return state
	end

	function self:release()
		state = "idle"
	end

	return (self :: any) :: Arm
end

--[[ THE ARM'S WIRING, WHICH IS ALSO POLICY. `new` above answers "whose gesture
	is this finger's"; a caller still has to decide WHEN to switch the engine's
	detector on, what to do to the scroller underneath while an armed drag runs,
	and when to put both back. That sequencing was written once inside
	`client/screen_target`, where nothing headless could reach it — and the part a
	real phone found broken was the sequencing, not the verdict.

	So the sequence lives here, with the engine injected as four effects:

	  * `now()` -> milliseconds (the caller's clock, never `os.clock` here)
	  * `setArmed(on, touch)` — take or release the acquisition. `touch` says
	    WHICH acquisition: a non-touch pointer arms the engine's own detector, a
	    finger is driven by the framework (the engine will not hand a detector a
	    touch that was already down — measured, see `client/screen_target`).
	  * `setScrollSuppressed(on)` — the ancestor scroller's `ScrollingEnabled`,
	    inverted. Optional: a node with no scrolling ancestor omits it.
	  * `schedule(seconds, fn) -> cancel` — a timer, because a finger held
	    PERFECTLY still produces no motion events at all and the hold still has to
	    expire.

	THE SCROLLER IS STOPPED ONLY FOR AN ARMED FINGER, and only for the rest of
	that gesture. A mouse never suppresses it (a scroller takes the wheel, not the
	button), and a touch that travelled out to `released` never suppresses it
	either — by then the scroller is the one that owns the gesture. Precedent for
	the suppression itself is `client/screen_pointer`'s paging capture, which
	turns `ScrollingEnabled` off for exactly as long as it is driving the canvas.

	RESTORING IS A TWO-KEYED LOCK. A finger lifting (`release`) does NOT restore
	while the engine is still running a drag — `UIDragDetector` keeps streaming
	`DragContinue` past the lift on some hosts — so the detector goes back to
	sleep on `dragEnded`, and whichever of the two arrives last is the one that
	hands the scroller back. `dispose` is the unconditional third key, for a node
	that unmounts mid-gesture. ]]
export type SessionEffects = {
	now: () -> number,
	setArmed: (on: boolean, touch: boolean) -> (),
	setScrollSuppressed: ((on: boolean) -> ())?,
	schedule: (seconds: number, fn: () -> ()) -> (() -> ())?,
}

export type SessionOptions = {
	-- the declaration's `declineTouch`: a finger may never arm this source
	declinesTouch: boolean?,
	tuning: Tuning?,
}

export type Session = {
	-- a pointer went down on the node. `pointerType` is the adapter's string.
	press: (self: Session, pointerType: string?, x: number, y: number) -> (),
	-- the pointer moved while down (touch only — a mouse is already decided)
	move: (self: Session, x: number, y: number) -> (),
	-- the pointer came up
	release: (self: Session) -> (),
	-- the engine told us a drag actually started / ended
	dragStarted: (self: Session) -> (),
	dragEnded: (self: Session) -> (),
	-- TRUE while the live gesture is a FINGER that armed by holding. The
	-- acquisition path tags its positions with this so the registry can begin the
	-- session at the arm instead of asking for another 14 px of travel — the hold
	-- already spent the promotion.
	armedTouch: (self: Session) -> boolean,
	dispose: (self: Session) -> (),
}

function touch_drag_arm.session(effects: SessionEffects, options: SessionOptions?): Session
	local declinesTouch = options ~= nil and options.declinesTouch == true
	local holdMs = interaction_tokens.touchDragArm.holdMs
	if options ~= nil and options.tuning ~= nil and options.tuning.holdMs ~= nil then
		holdMs = options.tuning.holdMs
	end
	local arm = touch_drag_arm.new(if options ~= nil then options.tuning else nil)

	local cancelTimer: (() -> ())? = nil
	local enabled = false
	local suppressed = false
	local dragging = false
	local armedByFinger = false
	local pressIsTouch = false

	local self = {}

	local function clearTimer()
		if cancelTimer ~= nil then
			local cancel = cancelTimer
			cancelTimer = nil
			cancel()
		end
	end

	local function suppressScroll(on: boolean)
		if suppressed == on or effects.setScrollSuppressed == nil then
			return
		end
		suppressed = on
		effects.setScrollSuppressed(on)
	end

	local function setArmed(on: boolean)
		if enabled == on then
			return
		end
		enabled = on
		effects.setArmed(on, pressIsTouch)
	end

	local function applyArm()
		if arm:state() ~= "armed" then
			return
		end
		clearTimer()
		if pressIsTouch then
			armedByFinger = true
			suppressScroll(true)
		end
		setArmed(true)
	end

	local function rest()
		if dragging then
			return
		end
		setArmed(false)
		suppressScroll(false)
		armedByFinger = false
		pressIsTouch = false
	end

	function self:press(pointerType: string?, x: number, y: number)
		local touch = interaction_tokens.classForPointerType(pointerType) == "touch"
		if touch and declinesTouch then
			return -- the declaration's own answer, kept on the engine's path too
		end
		pressIsTouch = touch
		clearTimer()
		arm:press(pointerType, x, y, effects.now())
		applyArm()
		if arm:state() == "pending" then
			cancelTimer = effects.schedule(holdMs / 1000, function()
				cancelTimer = nil
				arm:tick(effects.now())
				applyArm()
			end)
		end
	end

	function self:move(x: number, y: number)
		if arm:state() ~= "pending" then
			return
		end
		arm:move(x, y, effects.now())
		if arm:state() == "released" then
			clearTimer()
			return -- the scroller (or the row's swipe) owns this gesture now
		end
		applyArm()
	end

	function self:release()
		clearTimer()
		arm:release()
		rest()
	end

	function self:dragStarted()
		dragging = true
	end

	function self:dragEnded()
		dragging = false
		rest()
	end

	function self:armedTouch(): boolean
		return armedByFinger
	end

	function self:dispose()
		clearTimer()
		arm:release()
		dragging = false
		rest()
	end

	return (self :: any) :: Session
end

return touch_drag_arm
