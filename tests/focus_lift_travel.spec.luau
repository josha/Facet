--!strict
--[[ THE TEN-FOOT LIFT NOW TRAVELS — and three things had to follow it there
	(transitions round fix wave, task 7 items 4, 7 and 10).

	Tier 1 item 1D turned the 1.05x `FocusScale` from an instant write into a
	`style.motion.normal` tween (`aimFocusScale`). A value that used to be
	SETTLED on the frame it changed is now IN FLIGHT for 0.2 s, and everything
	that reads or ends it had been written against the instant version:

	  (4) `adapter.park` cancels the in-flight tween so it cannot land on the
	      next control to take this identity — but `Cancel` stops a tween where
	      it STANDS. The blur that made the node park-eligible had started the
	      1.05 → 1 travel, so a row recycled inside 0.2 s kept a scale of
	      1.01-1.05 forever: `adopt` never touches `focusScale`, and the next
	      focus re-aims from wherever it finds it.

	  (7) the FLOAT focus ring (the sibling Frame+UIStroke drawn for a control
	      inside a clipping host) is sized at `rect * liftScale` INSTANTLY, which
	      was correct when the lift was instant too. Against a tweening lift the
	      ring hangs ~5 % outside the control for the whole enter, and snaps back
	      to the unlifted size before the control has finished shrinking on blur.
	      The float's own Size travels on the SAME TweenInfo now.

	  (10) the Toggle's knob tween was fire-and-forget while its track tween was
	      held and cancelled — so a knob mid-travel through a recycle or a
	      teardown wrote onto whatever instance took its place.

	`src/client/*` reaches engine globals at load time and cannot run headlessly
	(`tests/lib/adapter_source.luau`'s own header), and a `UIScale.Scale` is
	invisible to the fake adapter in any case — so, like every other pin in this
	adapter family, these read the live source as TEXT and anchor on the exact
	lines that carry each ruling. Reverting any one edit turns exactly one case
	below red. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local adapter_source = require("./lib/adapter_source")

local targetSrc = fs.readFile("src/client/screen_target.luau")

describe("screen_target.park: a cancelled lift is also RESET, not left where it stood (item 4)", function()
	local FN = adapter_source.bodyOf(targetSrc, "function adapter.park(")

	it("found the function", function()
		expect(#FN > 0).toBe(true)
	end)

	it("writes the scale back to 1, and does it AFTER the cancel", function()
		local cancelAt = string.find(FN, "handle.focusScaleTween:Cancel()", 1, true)
		local resetAt = string.find(FN, "handle.focusScale.Scale = 1", 1, true)
		expect(cancelAt ~= nil).toBe(true)
		expect(resetAt ~= nil).toBe(true)
		-- order matters: a reset BEFORE the cancel is overwritten by the tween's
		-- next step, which is the same bug with an extra line in it
		expect((resetAt :: number) > (cancelAt :: number)).toBe(true)
	end)

	it("guards on the UIScale existing — a near display never creates one", function()
		expect(string.find(FN, "if handle.focusScale ~= nil then", 1, true) ~= nil).toBe(true)
	end)

	it("the pre-lift comment states the park reset rather than only the blur", function()
		-- the `setFocusVisual` comment this fix makes true again: it claimed
		-- "FocusScale is 1 whenever this branch runs", which the recycling path
		-- had quietly falsified
		local VISUAL = adapter_source.bodyOf(targetSrc, "function adapter.setFocusVisual(")
		local at = string.find(VISUAL, "Measured pre-lift: FocusScale is 1", 1, true)
		expect(at ~= nil).toBe(true)
		local window = string.sub(VISUAL, at :: number, (at :: number) + 400)
		expect(string.find(window, "adapter.park", 1, true) ~= nil).toBe(true)
	end)
end)
