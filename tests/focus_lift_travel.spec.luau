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
local paintSrc = fs.readFile("src/client/screen_paint.luau")

describe("screen_target.park: a cancelled lift is also RESET, not left where it stood (item 4)", function()
	local FN = adapter_source.bodyOf(targetSrc, "function adapter.park(")

	it("found the function", function()
		expect(#FN > 0).toBe(true)
	end)

	it("writes the scale back to 1, and does it AFTER the cancel", function()
		-- the cancel is `stopFocusScaleTweens` since item 7 gave the lift a second
		-- tween (the float ring's Size) — one helper, four call sites
		local cancelAt = string.find(FN, "stopFocusScaleTweens(handle)", 1, true)
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

describe("screen_target.aimFocusScale: the float ring travels with the lift (item 7)", function()
	local FN = adapter_source.bodyOf(targetSrc, "local function aimFocusScale(")
	local VISUAL = adapter_source.bodyOf(targetSrc, "function adapter.setFocusVisual(")

	it("found the function", function()
		expect(#FN > 0).toBe(true)
	end)

	it("the float's Size is written at the CURRENT scale, not at the lift's destination", function()
		local at = string.find(VISUAL, "handle.focusFloatGeom = {", 1, true)
		expect(at ~= nil).toBe(true)
		local window = string.sub(VISUAL, at :: number, (at :: number) + 400)
		-- the starting scale is READ off the live UIScale...
		expect(string.find(window, "handle.focusScale.Scale else 1", 1, true) ~= nil).toBe(true)
		-- ...and the destination expression is gone from the instant write
		expect(string.find(VISUAL, "rect.w * liftScale", 1, true)).toBe(nil)
	end)

	it("aims with `liftScale` itself, so the two halves cannot use two expressions", function()
		expect(string.find(VISUAL, "aimFocusScale(handle, liftScale)", 1, true) ~= nil).toBe(true)
		expect(string.find(VISUAL, "aimFocusScale(handle, style.extra.tenFootFocusScale)", 1, true)).toBe(nil)
	end)

	it("the float tween rides the SAME TweenInfo as the UIScale, built once", function()
		local infoAt = string.find(FN, "local info = TweenInfo.new(style.motion.normal", 1, true)
		expect(infoAt ~= nil).toBe(true)
		-- one TweenInfo, two Create calls: a second `TweenInfo.new` here would be
		-- two durations that agree until somebody changes one
		local _, infos = string.gsub(FN, "TweenInfo%.new", "")
		expect(infos).toBe(1)
		expect(string.find(FN, "TweenService:Create(float, info, { Size = size })", 1, true) ~= nil).toBe(true)
		expect(string.find(FN, "TweenService:Create(focusScale, info, { Scale = target })", 1, true) ~= nil).toBe(true)
	end)

	it("the target size is the same expression the instant write used", function()
		expect(
			string.find(FN, "UDim2.fromOffset(geom.w * target - 2 * geom.t, geom.h * target - 2 * geom.t)", 1, true)
				~= nil
		).toBe(true)
	end)

	it("reduced motion places both instead of tweening either", function()
		expect(string.find(FN, "local instant = isReducedMotion()", 1, true) ~= nil).toBe(true)
		-- the float's own branch reads the same flag, not a second call
		expect(string.find(FN, "if instant or float.Size == size then", 1, true) ~= nil).toBe(true)
		expect(string.find(FN, "if instant or focusScale.Scale == target then", 1, true) ~= nil).toBe(true)
		local _, reads = string.gsub(FN, "isReducedMotion%(%)", "")
		expect(reads).toBe(1)
	end)

	it("both tweens end through ONE cancel, and every lift-ending site calls it", function()
		--[[ four sites end a lift without finishing it: a re-aim, `park`,
			`destroy` and `destroyRoot`. Each used to carry its own hand-copied
			two-line cancel of `focusScaleTween`; with a SECOND tween in flight
			that shape is four chances to forget the other half. The count is the
			claim: no bare `focusScaleTween:Cancel()` survives outside the one
			helper. ]]
		local _, helpers = string.gsub(targetSrc, "stopFocusScaleTweens%(handle%)", "")
		expect(helpers >= 4).toBe(true)
		local _, cancels = string.gsub(targetSrc, "handle%.focusScaleTween:Cancel%(%)", "")
		expect(cancels).toBe(1) -- inside `stopFocusScaleTweens` and nowhere else
		local HELPER = adapter_source.bodyOf(targetSrc, "local function stopFocusScaleTweens(")
		expect(string.find(HELPER, "handle.focusFloatTween:Cancel()", 1, true) ~= nil).toBe(true)
	end)
end)

describe("screen_paint.applyToggleValue: the knob tween is HELD, like the track's (item 10)", function()
	local FN = adapter_source.bodyOf(paintSrc, "local function applyToggleValue(")

	it("found the function", function()
		expect(#FN > 0).toBe(true)
	end)

	it("the knob's Position tween is stored on the handle, not fired and forgotten", function()
		--[[ the track's colour tween was held in `handle.toggleTrackTween` and
			cancelled on the next flip; the knob's Position tween — the one Tier 1
			item 1E added, with a Back overshoot over `motion.normal` — was
			created inline and played. A flip-flip inside 0.2 s therefore left the
			first knob tween running, and a recycled toggle (a Toggle handle is
			park-eligible: `parkEligible` refuses motion scales, canvas groups,
			hit expanders, floats, glows and focus, not a track/knob pair) took
			the leftover writes to its own knob. ]]
		expect(string.find(FN, "handle.toggleKnobTween = knobTween", 1, true) ~= nil).toBe(true)
		expect(string.find(FN, "TweenService:Create(knob, overshootInfo(style.motion.normal)", 1, true) ~= nil).toBe(
			true
		)
	end)

	it("it is cancelled beside the track's, in the one place that ends a flip", function()
		local trackCancelAt = string.find(FN, "handle.toggleTrackTween:Cancel()", 1, true)
		local knobCancelAt = string.find(FN, "handle.toggleKnobTween:Cancel()", 1, true)
		expect(trackCancelAt ~= nil and knobCancelAt ~= nil).toBe(true)
		-- both cancels come BEFORE either tween is re-created, or a flip would
		-- cancel the tween it had just started
		local createAt = string.find(FN, "TweenService:Create(track,", 1, true)
		expect(createAt ~= nil).toBe(true)
		expect((trackCancelAt :: number) < (createAt :: number)).toBe(true)
		expect((knobCancelAt :: number) < (createAt :: number)).toBe(true)
		-- ...and the field is cleared with the cancel, so a later flip does not
		-- re-cancel a finished tween
		expect(string.find(FN, "handle.toggleKnobTween = nil", 1, true) ~= nil).toBe(true)
	end)

	it("the instant paths (retheme, reduced motion) leave no tween behind either", function()
		-- they still run the SAME cancel above before writing, which is what makes
		-- a reduce-motion flip mid-travel land where it should
		local cancelAt = string.find(FN, "handle.toggleKnobTween:Cancel()", 1, true)
		local instantAt = string.find(FN, "if retheme == true or isReducedMotion() then", 1, true)
		expect(instantAt ~= nil).toBe(true)
		expect((cancelAt :: number) < (instantAt :: number)).toBe(true)
	end)
end)
