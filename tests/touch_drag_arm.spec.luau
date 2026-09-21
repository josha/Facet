--!strict
--[[ ONE FINGER, ONE OUTCOME.

	The live defect these cases stand for: on a phone the Discover feed could not
	be scrolled at all, because the cards' drag acquisition claimed the touch from
	the press. Measured in the Studio device emulator's `iphone_16` (portrait, real
	`UserInputType.Touch`): a 230 px upward flick starting on a card left the
	scroller's `CanvasPosition` at `0, 0`; the identical flick with the three
	`UIDragDetector`s disabled scrolled it to `0, 249.2`.

	`touch_drag_arm` is the policy that decides whether the drag may have the
	finger. What it can be asked here is everything except the engine's half:
	whether a `UIDragDetector` enabled mid-press still picks up the in-flight touch
	is an engine fact, measured live and recorded where it is relied on
	(`client/screen_target.setDragDetector`). A spec that faked it would be
	asserting our own mock.
]]
local t = require("./lib/testkit")
local touchDragArm = require("../src/input/touch_drag_arm")
local tokens = require("../src/input/interaction_tokens")

local HOLD = tokens.touchDragArm.holdMs
local SLOP = tokens.touchDragArm.slopPx

t.describe("touch drag arm", function()
	t.it("gives a moving finger to whatever is underneath it", function()
		local arm = touchDragArm.new()
		t.expect(arm:press("touch", 100, 500, 0)).toBe("pending")
		-- the flick that could not scroll the feed: it travels immediately
		t.expect(arm:move(100, 500 - (SLOP + 1), 16)).toBe("released")
		-- ...and holding still AFTERWARDS does not win it back
		t.expect(arm:tick(HOLD * 3)).toBe("released")
	end)

	t.it("releases before the press could ever have promoted to a drag", function()
		-- the slop must be the SMALLER gate, or a gesture would promote into a
		-- drag on the way to being released and both would run
		t.expect(`slop {SLOP} < touch promotion {tokens.dragPromotionPx.touch}`)
			.toBe(`slop {SLOP} < touch promotion {tokens.dragPromotionPx.touch}`)
		t.expect(`slop is the smaller gate: {SLOP < tokens.dragPromotionPx.touch}`)
			.toBe("slop is the smaller gate: true")
	end)

	t.it("arms a finger that holds still, and keeps it armed once it moves", function()
		local arm = touchDragArm.new()
		arm:press("touch", 100, 500, 0)
		t.expect(arm:tick(HOLD - 1)).toBe("pending") -- not yet
		t.expect(arm:tick(HOLD)).toBe("armed")
		-- the drag proper: travel after the arm is the drag, not a release
		t.expect(arm:move(100, 200, HOLD + 100)).toBe("armed")
	end)

	t.it("counts the hold on a finger that only trembles", function()
		-- a host that reports motion but never ticks must still arm: the jitter
		-- inside the slop is a held finger, and the player feels the hold land
		local arm = touchDragArm.new()
		arm:press("touch", 100, 500, 0)
		t.expect(arm:move(102, 501, HOLD - 10)).toBe("pending")
		t.expect(arm:move(101, 499, HOLD + 10)).toBe("armed")
	end)

	t.it("does not arbitrate a mouse or a pen", function()
		for _, pointerType in { "mouse", "pen", "pointer" } do
			local arm = touchDragArm.new()
			t.expect(`{pointerType}: {arm:press(pointerType, 10, 10, 0)}`).toBe(`{pointerType}: armed`)
			-- and travel never takes it away again
			t.expect(`{pointerType} after travel: {arm:move(400, 400, 8)}`).toBe(`{pointerType} after travel: armed`)
		end
		-- an adapter that reports no pointer type at all is the headless fake's
		-- mouse, and is treated as one
		local arm = touchDragArm.new()
		t.expect(arm:press(nil, 10, 10, 0)).toBe("armed")
	end)

	t.it("needs a fresh press to arm again", function()
		local arm = touchDragArm.new()
		arm:press("touch", 100, 500, 0)
		arm:move(100, 600, 16)
		t.expect(arm:state()).toBe("released")
		arm:release()
		t.expect(arm:state()).toBe("idle")
		arm:press("touch", 100, 500, 1000)
		t.expect(arm:tick(1000 + HOLD)).toBe("armed")
	end)

	t.it("takes a caller's own tuning over the tokens", function()
		local arm = touchDragArm.new({ holdMs = 10, slopPx = 100 })
		arm:press("touch", 0, 0, 0)
		t.expect(arm:move(50, 0, 5)).toBe("pending") -- inside the wider slop
		t.expect(arm:tick(10)).toBe("armed") -- past the shorter hold
	end)
end)

--[[ THE WIRING IS THE PART THE PHONE FOUND BROKEN. The verdict above was right
	the whole time; what was wrong was what the acquisition path DID with it — a
	hold armed the engine's detector and nothing else, so the page went on panning
	under the card and the registry still asked the player for 14 px of travel it
	had just asked them not to make. `touch_drag_arm.session` is that sequencing,
	with the engine injected as four effects, so it can be asked here instead of
	only on a device. ]]
t.describe("touch drag arm: the acquisition sequence", function()
	-- a scripted engine: a clock the case advances by hand, a detector and a
	-- scroller that just record, and a timer the case fires when it chooses
	local function rig(options: any?)
		local r: any = {
			ms = 0,
			enabled = false,
			suppressed = false,
			timers = 0,
			log = {} :: { string },
		}
		local fire: (() -> ())? = nil
		r.session = touchDragArm.session({
			now = function(): number
				return r.ms
			end,
			setArmed = function(on: boolean, touch: boolean)
				r.enabled = on
				r.lastTouch = touch
				table.insert(r.log, `{if on then "armed" else "released"} {if touch then "finger" else "pointer"}`)
			end,
			setScrollSuppressed = function(on: boolean)
				r.suppressed = on
				table.insert(r.log, if on then "scroll stopped" else "scroll restored")
			end,
			schedule = function(seconds: number, fn: () -> ()): (() -> ())?
				r.timers += 1
				fire = fn
				return function()
					r.timers -= 1
					fire = nil
				end
			end,
		}, options)
		-- what a real host's timer does: time has passed, the finger is still down
		function r.hold(ms: number)
			r.ms += ms
			if fire ~= nil then
				local f = fire
				fire = nil
				r.timers -= 1
				f()
			end
		end
		return r
	end

	t.it("a held finger arms the drag AND stops the page under it", function()
		local r = rig()
		r.session:press("touch", 100, 500)
		-- nothing is claimed while the verdict is still open: the scroller is
		-- free, which is the whole reason the feed scrolls again
		t.expect(`during the hold: {r.enabled} {r.suppressed}`).toBe("during the hold: false false")
		r.hold(HOLD)
		t.expect(table.concat(r.log, ", ")).toBe("scroll stopped, armed finger")
		t.expect(r.session:armedTouch()).toBe(true)
	end)

	t.it("a finger that travels first never arms and never stops the page", function()
		local r = rig()
		r.session:press("touch", 100, 500)
		r.ms += 16
		r.session:move(100, 500 - (SLOP + 1))
		r.hold(HOLD * 3) -- the timer is cancelled; more time changes nothing
		t.expect(`{#r.log} effects, armed={r.session:armedTouch()}`).toBe("0 effects, armed=false")
		t.expect(r.timers).toBe(0)
	end)

	t.it("a hold that is released without moving leaves nothing behind", function()
		local r = rig()
		r.session:press("touch", 100, 500)
		r.hold(HOLD)
		r.session:release()
		t.expect(table.concat(r.log, ", ")).toBe("scroll stopped, armed finger, released finger, scroll restored")
		t.expect(r.session:armedTouch()).toBe(false)
	end)

	t.it("the page stays stopped for the whole drag, past the lift", function()
		local r = rig()
		r.session:press("touch", 100, 500)
		r.hold(HOLD)
		r.session:dragStarted()
		r.session:release() -- the finger is up; the engine is still dragging
		t.expect(`after the lift: {r.enabled} {r.suppressed}`).toBe("after the lift: true true")
		r.session:dragEnded()
		t.expect(`after the drag: {r.enabled} {r.suppressed}`).toBe("after the drag: false false")
	end)

	t.it("a mouse arms at once and never touches the scroller", function()
		local r = rig()
		r.session:press("mouse", 100, 500)
		-- `touch = false` is what tells the adapter to use the ENGINE's detector;
		-- a finger is driven by the framework instead (the engine will not adopt
		-- a touch that was already down)
		t.expect(table.concat(r.log, ", ")).toBe("armed pointer")
		-- an armed MOUSE is not an armed finger: it still promotes by travel, so
		-- a click that never moves stays a click
		t.expect(r.session:armedTouch()).toBe(false)
		t.expect(r.timers).toBe(0)
	end)

	t.it("a declining source is never armed by a finger, and never scheduled", function()
		local r = rig({ declinesTouch = true })
		r.session:press("touch", 100, 500)
		r.hold(HOLD * 3)
		t.expect(`{#r.log} effects, {r.timers} timers`).toBe("0 effects, 0 timers")
		-- ...and the same node still acquires on a mouse
		r.session:press("mouse", 100, 500)
		t.expect(r.enabled).toBe(true)
	end)

	t.it("a node unmounting mid-gesture hands the scroller back", function()
		local r = rig()
		r.session:press("touch", 100, 500)
		r.hold(HOLD)
		r.session:dragStarted()
		r.session:dispose()
		t.expect(`{r.enabled} {r.suppressed} {r.timers}`).toBe("false false 0")
	end)

	t.it("a node with no scrolling ancestor simply has no scroller effect", function()
		local r: any = { ms = 0, enabled = false }
		local session = touchDragArm.session({
			now = function(): number
				return r.ms
			end,
			setArmed = function(on: boolean, _touch: boolean)
				r.enabled = on
			end,
			schedule = function(_seconds: number, fn: () -> ()): (() -> ())?
				r.fire = fn
				return function()
					r.fire = nil
				end
			end,
		})
		session:press("touch", 10, 10)
		r.ms = HOLD
		r.fire()
		t.expect(r.enabled).toBe(true)
		session:release()
		t.expect(r.enabled).toBe(false)
	end)
end)
