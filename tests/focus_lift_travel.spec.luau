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

	it("it is cancelled beside the track's, through the one helper that ends a flip", function()
		local HELPER = adapter_source.bodyOf(paintSrc, "local function stopToggleTweens(")
		expect(string.find(HELPER, "handle.toggleTrackTween:Cancel()", 1, true) ~= nil).toBe(true)
		expect(string.find(HELPER, "handle.toggleKnobTween:Cancel()", 1, true) ~= nil).toBe(true)
		-- ...and each field is cleared with its cancel, so a later flip does not
		-- re-cancel a finished tween
		expect(string.find(HELPER, "handle.toggleKnobTween = nil", 1, true) ~= nil).toBe(true)
		-- the cancel comes BEFORE either tween is re-created, or a flip would
		-- cancel the tween it had just started
		local cancelAt = string.find(FN, "stopToggleTweens(handle)", 1, true)
		local createAt = string.find(FN, "TweenService:Create(track,", 1, true)
		expect(cancelAt ~= nil and createAt ~= nil).toBe(true)
		expect((cancelAt :: number) < (createAt :: number)).toBe(true)
		-- no bare cancel survives outside the helper
		local _, bare = string.gsub(paintSrc, "handle%.toggleKnobTween:Cancel%(%)", "")
		expect(bare).toBe(1)
	end)

	it("the instant arm PLACES the knob, because the cancel above it can strand one", function()
		--[[ REVIEW N1. The retheme arm deliberately skipped `knob.Position` — a
			retheme is not a state change, so moving the knob was a no-op. Once
			the cancel moved above the branch that stopped being true: `Cancel`
			stops a tween where it STANDS, and the Back overshoot means "where it
			stands" can be PAST the end of the track, so a theme swap landing
			inside the 0.2 s travel stranded the knob mid-track until the next
			flip — and the knob IS the value readout. Under `retheme` the caller
			passes `handle.toggleOn`, so `knobPos` is the CURRENT state's place:
			the write is the same no-op it always was on every path except the one
			that was broken. ]]
		local cancelAt = string.find(FN, "stopToggleTweens(handle)", 1, true)
		local instantAt = string.find(FN, "if retheme == true or isReducedMotion() then", 1, true)
		expect(instantAt ~= nil).toBe(true)
		expect((cancelAt :: number) < (instantAt :: number)).toBe(true)
		-- the placement is UNCONDITIONAL inside that arm: no `retheme` guard left
		local arm = string.sub(FN, instantAt :: number, string.find(FN, "\n\t\telse\n", instantAt :: number, true))
		expect(string.find(arm, "knob.Position = knobPos", 1, true) ~= nil).toBe(true)
		expect(string.find(arm, "if retheme ~= true then", 1, true)).toBe(nil)
		-- ...and the refresh a theme swap drives really does pass `retheme = true`
		-- with the CURRENT value, which is what makes the write a placement
		-- rather than a state change
		local REFRESH = adapter_source.bodyOf(paintSrc, "local function refreshToggleVisuals(")
		expect(string.find(REFRESH, "applyToggleValue(handle, handle.toggleOn == true, true)", 1, true) ~= nil).toBe(
			true
		)
	end)

	it("the placement is the TEARDOWN'S to ask for, never inferred from a flag", function()
		--[[ THE REGRESSION THIS PINS. Review D7 wanted the knob put where its
			value says after an interrupted tween, and the first shape inferred
			that from "was a tween running?". That is true on the FLIP path too —
			`applyToggleValue` writes the new `handle.toggleOn` BEFORE it calls
			the helper — so the knob was placed at the DESTINATION and the tween
			that followed ran from there to the same place: zero visible motion,
			on every flip. Only the three TEARDOWN sites want a placement, and
			they are the ones that ask for it. ]]
		local HELPER = adapter_source.bodyOf(paintSrc, "local function stopToggleTweens(")
		expect(string.find(HELPER, "stopToggleTweens(handle: any, place: boolean?)", 1, true) ~= nil).toBe(true)
		-- the placement is gated on the ARGUMENT, not on a "was it tweening" read
		expect(string.find(HELPER, "if place == true and handle.knob ~= nil then", 1, true) ~= nil).toBe(true)
		expect(string.find(HELPER, "knobWasTweening", 1, true)).toBeNil()
		-- the position still comes from the VALUE
		expect(
			string.find(HELPER, "if handle.toggleOn == true then TOGGLE_KNOB_ON else TOGGLE_KNOB_OFF", 1, true) ~= nil
		).toBe(true)
		-- ...and the FLIP path asks for no placement, so its tween has somewhere
		-- to travel from
		local FN2 = adapter_source.bodyOf(paintSrc, "local function applyToggleValue(")
		expect(string.find(FN2, "stopToggleTweens(handle)", 1, true) ~= nil).toBe(true)
		expect(string.find(FN2, "stopToggleTweens(handle, true)", 1, true)).toBeNil()
	end)

	it("each tween field means IN FLIGHT — cleared when the tween lands, not only when cancelled", function()
		--[[ both fields were assigned at creation and cleared only by
			`stopToggleTweens`, so from the SECOND flip on they read as "running"
			forever. With the placement inferred from that flag, every flip
			teleported; on its own it still means a genuine mid-flight reversal is
			treated as one more stale-field case. `Completed:Once` is the idiom the
			press-dip tween beside them already uses. ]]
		local FN2 = adapter_source.bodyOf(paintSrc, "local function applyToggleValue(")
		-- each of the two tweens this function creates is followed by its own
		-- completion hook, within its own block
		for _, pair in
			{
				{ create = "TweenService:Create(track,", field = "handle.toggleTrackTween == tween" },
				{ create = "TweenService:Create(knob, overshootInfo", field = "handle.toggleKnobTween == knobTween" },
			}
		do
			local at = string.find(FN2, pair.create, 1, true)
			expect(`{pair.create} found: {at ~= nil}`).toBe(`{pair.create} found: true`)
			local block = string.sub(FN2, at :: number, (at :: number) + 420)
			expect(string.find(block, "Completed:Once", 1, true) ~= nil).toBe(true)
			-- `Completed` fires for a CANCELLED tween too, so the state is
			-- checked...
			expect(string.find(block, "state == Enum.PlaybackState.Completed", 1, true) ~= nil).toBe(true)
			-- ...and so is identity, or a late callback would clear the tween that
			-- REPLACED the one it belongs to
			expect(string.find(block, pair.field, 1, true) ~= nil).toBe(true)
		end
	end)

	it("the adapter's three teardown paths end the toggle's tweens too (item 10's root cause)", function()
		--[[ item 10 named a recycled toggle as the risk and then fixed only the
			flip-to-flip case; a Toggle handle IS park-eligible, so the tween
			outliving the identity was never closed. `park`, `destroy` and
			`destroyRoot` all call the same helper now — the same three that end
			the focus lift's pair. ]]
		for _, anchor in { "function adapter.park(", "function adapter.destroyRoot(" } do
			local BODY = adapter_source.bodyOf(targetSrc, anchor)
			expect(#BODY > 0).toBe(true)
			expect(string.find(BODY, "stopToggleTweens(handle", 1, true) ~= nil).toBe(true)
		end
		-- the per-node removal path is the third; it is where the float ring and
		-- the focus-scale tween are already ended
		local removeAt = string.find(targetSrc, "handle.focusRingFloat:Destroy()", 1, true)
		expect(removeAt ~= nil).toBe(true)
		local window = string.sub(targetSrc, removeAt :: number, (removeAt :: number) + 700)
		expect(string.find(window, "stopToggleTweens(handle)", 1, true) ~= nil).toBe(true)
		--[[ ...and EXACTLY ONE of the three asks for the knob placement: `park`,
			the only teardown that keeps the instance. The other two destroy it
			within a few lines, so a placement there is a write onto an object
			that is about to stop existing — dead, and the kind of dead write a
			count like this one is for. ]]
		local _, placements = string.gsub(targetSrc, "stopToggleTweens%(handle, true%)", "")
		expect(placements).toBe(1)
		local PARK = adapter_source.bodyOf(targetSrc, "function adapter.park(")
		expect(string.find(PARK, "stopToggleTweens(handle, true)", 1, true) ~= nil).toBe(true)
	end)
end)

describe("screen_target: the float ring's geometry dies with the float (review N8)", function()
	it("every site that drops `focusRingFloat` drops `focusFloatGeom` with it", function()
		--[[ `focusFloatGeom` is what `aimFocusScale` computes the float's travel
			from. Left behind when a float is destroyed, a LATER float on the same
			handle would travel from the rect of the one that died — the stale-fact
			shape this adapter's own history is full of. The count is the claim:
			as many geometry drops as float drops. ]]
		local unpaired: { number } = {}
		local at = 1
		local drops = 0
		while true do
			local found = string.find(targetSrc, "handle.focusRingFloat = nil", at, true)
			if found == nil then
				break
			end
			drops += 1
			-- the geometry drop rides the same block (a few lines, allowing for a
			-- comment between them)
			local window = string.sub(targetSrc, found, found + 500)
			if string.find(window, "handle.focusFloatGeom = nil", 1, true) == nil then
				table.insert(unpaired, drops)
			end
			at = found + 1
		end
		expect(drops).toBe(3) -- setFocusVisual's reparented-away check, its teardown, and `destroy`
		expect(`unpaired float drops: {table.concat(unpaired, ", ")}`).toBe("unpaired float drops: ")
		-- `destroyRoot` is the fourth site: it never drops an individual float
		-- (the whole ScreenGui goes), so it clears the geometry beside the rest of
		-- the handle's motion state instead
		local ROOT = adapter_source.bodyOf(targetSrc, "function adapter.destroyRoot(")
		expect(string.find(ROOT, "handle.focusFloatGeom = nil", 1, true) ~= nil).toBe(true)
	end)
end)
