--!strict
local harness = require("./lib/harness")
-- Milestone B — the value-control family (docs/plans/parity-next.md
-- investment 4; acceptance rows B-VAL1 and B-VAL3).
--
-- B-VAL1 is the SHARED model: Slider and Stepper are different affordances over
-- one piece of arithmetic, so they cannot disagree at the edges.
-- B-VAL3 is reach: every input class must arrive at that same arithmetic through
-- a real path (adapter.tap / system.deviceKey), never a direct callback.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = harness.coreFactory
local Facet = require("../src") :: any
local UI = harness.UI
local environment = require("../src/env/environment")
local presenterLib = harness.presenterLib
local actionsLib = require("../src/input/actions")
local valueModel = require("../src/controls/value_model")
local fake_target = require("../tests/lib/fake_target")
local adapter_source = require("./lib/adapter_source")
local Compose = require("../src/vendor/compose/core")

describe("B-VAL1: the shared value model", function()
	it("clamps to its bounds", function()
		local m = valueModel.new({ min = 0, max = 10 })
		expect(m.clamp(-5)).toBe(0)
		expect(m.clamp(99)).toBe(10)
		expect(m.clamp(4)).toBe(4)
	end)

	it("quantizes onto a grid measured FROM min, so the bounds are reachable", function()
		local m = valueModel.new({ min = 5, max = 25, step = 5 })
		expect(m.quantize(5)).toBe(5)
		expect(m.quantize(7)).toBe(5)
		expect(m.quantize(8)).toBe(10)
		expect(m.quantize(25)).toBe(25)
		expect(m.quantize(1000)).toBe(25)
	end)

	it("a non-integer grid still lands exactly on the bounds", function()
		local m = valueModel.new({ min = 0, max = 1, step = 0.25 })
		expect(m.quantize(0.3)).toBe(0.25)
		expect(m.quantize(0.99)).toBe(1)
		expect(m.atMax(1)).toBe(true)
	end)

	it("stepping always makes progress and never leaves the range", function()
		local m = valueModel.new({ min = 0, max = 3, step = 1 })
		expect(m.stepped(0, 1)).toBe(1)
		expect(m.stepped(3, 1)).toBe(3) -- already at max
		expect(m.stepped(0, -1)).toBe(0) -- already at min
		-- a mid-grid value must not quantize back onto itself and no-op
		local mid = valueModel.new({ min = 0, max = 10, step = 2 })
		expect(mid.stepped(5, 1) > 5).toBe(true)
		expect(mid.stepped(5, -1) < 5).toBe(true)
	end)

	it("a continuous model steps by a fraction of the range", function()
		local m = valueModel.new({ min = 0, max = 100 })
		expect(m.stepped(50, 1)).toBe(51)
		expect(m.stepped(50, -1)).toBe(49)
	end)

	it("fraction and fromFraction round-trip through the grid", function()
		local m = valueModel.new({ min = 0, max = 10, step = 1 })
		expect(m.fraction(5)).toBe(0.5)
		expect(m.fromFraction(0.5)).toBe(5)
		expect(m.fromFraction(-1)).toBe(0)
		expect(m.fromFraction(2)).toBe(10)
	end)

	it("formats without noise and never prints negative zero", function()
		local m = valueModel.new({ min = -5, max = 5 })
		expect(m.format(3)).toBe("3")
		expect(m.format(2.5)).toBe("2.5")
		expect(m.format(0)).toBe("0")
		expect(m.format(-0.0)).toBe("0")
	end)

	it("a custom formatter is honoured everywhere the value is shown", function()
		local m = valueModel.new({
			min = 0,
			max = 1,
			format = function(v)
				return string.format("%d%%", math.floor(v * 100 + 0.5))
			end,
		})
		expect(m.format(0.5)).toBe("50%")
		expect(string.find(m.semanticText(0.5), "50%", 1, true) ~= nil).toBe(true)
	end)

	-- F-38. `spec.format` was the one user callback in this area running raw, and
	-- it runs from the RENDER path of Slider and Stepper — a throwing formatter
	-- unwound a whole solve. The core quarantines its equivalent (`eq`) for
	-- exactly this reason. Containment here is the lowest-risk shape: fall back
	-- to the default formatting of the clamped value, never unwind.
	it("a throwing formatter falls back to the default format instead of unwinding a solve", function()
		local calls = 0
		local m = valueModel.new({
			min = 0,
			max = 10,
			step = 1,
			format = function(v)
				calls += 1
				error(`no formatter for {v}`)
			end,
		})
		expect(m.format(4)).toBe("4")
		expect(m.semanticText(4)).toBe("4 of 0 to 10")
		expect(calls > 0).toBe(true) -- the formatter really was attempted
		-- and the fallback is of the CLAMPED value, like the healthy path
		expect(m.format(99)).toBe("10")
		expect(m.format(-99)).toBe("0")
	end)

	it("a formatter that throws for ONE value still formats the others", function()
		local m = valueModel.new({
			min = 0,
			max = 10,
			step = 1,
			format = function(v)
				if v == 4 then
					error("boom")
				end
				return `<{v}>`
			end,
		})
		expect(m.format(4)).toBe("4") -- fallback for the bad one only
		expect(m.format(5)).toBe("<5>")
		expect(m.semanticText(4)).toBe("4 of <0> to <10>")
	end)

	it("semantic value text states the value IN ITS RANGE", function()
		local m = valueModel.new({ min = 0, max = 10, step = 1 })
		expect(m.semanticText(4)).toBe("4 of 0 to 10")
	end)

	it("a NaN or infinite value resolves to the low bound instead of propagating", function()
		local m = valueModel.new({ min = 2, max = 8 })
		expect(m.clamp(0 / 0)).toBe(2)
		expect(m.clamp(math.huge)).toBe(2)
		expect(m.fraction(0 / 0)).toBe(0)
	end)

	it("an impossible range or step is a build error, not a silent degradation", function()
		expect(pcall(function()
			return valueModel.new({ min = 10, max = 10 })
		end)).toBe(false)
		expect(pcall(function()
			return valueModel.new({ min = 0, max = 1, step = 0 })
		end)).toBe(false)
		expect(pcall(function()
			return valueModel.new({ min = 0, max = 1, step = -2 })
		end)).toBe(false)
		expect(pcall(function()
			return valueModel.new({ min = 0 / 0, max = 1 })
		end)).toBe(false)
	end)
end)

-- ===== Stepper =============================================================

local function mountStepper(specOverrides: any?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new({ ops = true })
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	local value = Compose.cell(5)
	local spec: any = { id = "Volume", label = "Volume", value = value, min = 0, max = 10, step = 1 }
	for k, v in (specOverrides or {}) :: any do
		spec[k] = v
	end
	local control = harness.Controls.Stepper(core, spec)
	pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
	pres.refresh()
	return core, adapter, system, pres, value, control
end

describe("B-VAL3: Stepper reaches the same arithmetic from every input class", function()
	it("pointer: tapping plus and minus steps the owner's value", function()
		local _, adapter, _, pres, value = mountStepper()
		adapter.tap("/S/Volume/Inc")
		pres.refresh()
		expect(value:peek()).toBe(6)
		adapter.tap("/S/Volume/Dec")
		adapter.tap("/S/Volume/Dec")
		pres.refresh()
		expect(value:peek()).toBe(4)
	end)

	it("touch: a finger tap on + steps it identically", function()
		local _, adapter, _, pres, value = mountStepper()
		adapter.pointerDown("/S/Volume/Inc", 0, 0, "touch")
		adapter.tap("/S/Volume/Inc", { pointer = "touch" })
		pres.refresh()
		expect(value:peek()).toBe(6)
	end)

	it("keyboard: Adjust on the focused control steps without touching a button", function()
		local _, _, system, pres, value = mountStepper()
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("Period", true)
		system.deviceKey("Period", false)
		pres.refresh()
		expect(value:peek()).toBe(6)
		system.deviceKey("Comma", true)
		system.deviceKey("Comma", false)
		pres.refresh()
		expect(value:peek()).toBe(5)
	end)

	it("gamepad: ButtonA on the focused + activates, and the bumpers Adjust", function()
		local _, _, system, pres, value = mountStepper()
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("ButtonR1", true)
		system.deviceKey("ButtonR1", false)
		pres.refresh()
		expect(value:peek()).toBe(6)
		system.deviceKey("ButtonL1", true)
		system.deviceKey("ButtonL1", false)
		pres.refresh()
		expect(value:peek()).toBe(5)
	end)

	it("no Adjust key is bound while focus sits outside the Stepper (no gameplay bumper shadow)", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new({ ops = true })
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local value = Compose.cell(5)
		local control = harness.Controls.Stepper(core, {
			id = "Volume",
			label = "Volume",
			value = value,
			min = 0,
			max = 10,
			step = 1,
		})
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "Elsewhere", label = "elsewhere", height = { type = "fixed", px = 44 } }),
				control.blueprint,
			},
		}))
		pres.refresh()
		-- focus is on the first focusable, which is OUTSIDE the stepper
		system.deviceKey("ButtonR1", true)
		system.deviceKey("ButtonR1", false)
		pres.refresh()
		expect(value:peek()).toBe(5)
	end)
end)

describe("B-VAL3: Stepper bounds, formatting, disabled and lifecycle", function()
	it("stops at both bounds instead of running past them", function()
		local _, adapter, _, pres, value = mountStepper({ value = nil })
		for _ = 1, 20 do
			adapter.tap("/S/Volume/Inc")
		end
		pres.refresh()
		expect(value:peek()).toBe(10)
		for _ = 1, 30 do
			adapter.tap("/S/Volume/Dec")
		end
		pres.refresh()
		expect(value:peek()).toBe(0)
	end)

	it("the affordance at a bound is DISABLED, not silently inert", function()
		local _, adapter, _, pres, value = mountStepper()
		for _ = 1, 10 do
			adapter.tap("/S/Volume/Inc")
		end
		pres.refresh()
		expect(value:peek()).toBe(10)
		expect(adapter.node("/S/Volume/Inc").props.enabled).toBe(false)
		expect(adapter.node("/S/Volume/Dec").props.enabled).toBe(true)
	end)

	it("the readout follows the value with no factory rerun", function()
		local _, adapter, _, pres, _, control = mountStepper()
		expect(adapter.node("/S/Volume/Value").props.text).toBe("5")
		adapter.tap("/S/Volume/Inc")
		pres.refresh()
		expect(adapter.node("/S/Volume/Value").props.text).toBe("6")
		expect(control.dump().semanticText).toBe("6 of 0 to 10")
	end)

	it("a custom format reaches the visible readout", function()
		local _, adapter = mountStepper({
			format = function(v: number)
				return string.format("%d dB", v)
			end,
		})
		expect(adapter.node("/S/Volume/Value").props.text).toBe("5 dB")
	end)

	it("an explicitly disabled Stepper refuses every input class", function()
		local _, adapter, system, pres, value = mountStepper({ enabled = false })
		adapter.tap("/S/Volume/Inc")
		pres.refresh()
		expect(value:peek()).toBe(5)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		system.deviceKey("Period", true)
		system.deviceKey("Period", false)
		pres.refresh()
		expect(value:peek()).toBe(5)
	end)

	it("rejects a non-settable value instead of silently owning one", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			return harness.Controls.Stepper(
				core,
				{ id = "X", value = Compose.formula(function()
					return 1
				end), min = 0, max = 2 }
			)
		end)
		expect(ok).toBe(false)
		expect(
			string.find(tostring(err), "must be a writable Compose cell holding a number, owned by the caller", 1, true)
				~= nil
		).toBe(true)
	end)

	it("dump is deterministic", function()
		local _, _, _, _, _, control = mountStepper()
		local serde = require("@lune/serde")
		expect(serde.encode("json", control.dump(), true)).toBe(serde.encode("json", control.dump(), true))
	end)

	it("build/interact/dispose returns the registry to its baseline", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local adapter = fake_target.new({ ops = true })
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local value = Compose.cell(5)
		local baseline = core.owner.size()
		local control = harness.Controls.Stepper(core, {
			id = "V",
			label = "V",
			value = value,
			min = 0,
			max = 10,
			step = 1,
		})
		control.dispose()
		local after = core.owner.size()
		expect(after).toBe(baseline)
		expect(after).toBe(baseline)
	end)
end)

-- ===== Slider (B-VAL2 / B-VAL3) ============================================

local function mountSlider(specOverrides: any?, fakeOpts: any?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new({ ops = true })
	if fakeOpts ~= nil and (fakeOpts :: any).noDragDetector then
		(adapter :: any).noDragDetector = true
	end
	local system = actionsLib.newSystem(core)
	-- Tab is a presenter option: a case that drives Tab asks for it
	local pres = presenterLib.new(
		core,
		env,
		adapter,
		system,
		if fakeOpts ~= nil and (fakeOpts :: any).keyboardNavigation then { keyboardNavigation = true } else nil
	)
	local value = Compose.cell(50)
	local spec: any = { id = "Vol", label = "Vol", value = value, min = 0, max = 100 }
	for k, v in (specOverrides or {}) :: any do
		spec[k] = v
	end
	local control = harness.Controls.Slider(core, spec)
	pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
	pres.refresh()
	return core, adapter, system, pres, value, control, env
end

-- Director review 2026-07-24 (live capture): the row read fine only because the
-- text measurer over-reserved every label, so the SLACK IN THE BOX was doing the
-- spacing. Exact text measurement removed that slack and the thumb — a circle
-- that sits at the track's left edge at value 0 — landed against the final "s"
-- of "Brightness". The row now declares its own clearance, and this pins it: a
-- future tightening has to fail here rather than in a screenshot.
-- Director review 2026-07-24 (live capture): AT REST the Brightness slider drew
-- no accent fill and parked its thumb at offset 0 while the value was 40 — the
-- control only looked right after something else changed the value. `fillWidth`
-- and `thumbOffset` are memos over the SOLVED track rect, but that rect arrived
-- through a plain upvalue rather than a signal, so the memos never re-ran when
-- the geometry landed. A reactive framework cannot have a control that reads
-- geometry non-reactively: it renders a value it is not showing.
describe("slider: the fill and thumb show the value AT REST (director review 2026-07-24)", function()
	it("paints the fill and positions the thumb on the first solve, with no interaction", function()
		local _, adapter = mountSlider() -- value 50 of 0..100
		local track = adapter.node("/S/Vol/TrackHost").rect
		local fill = adapter.node("/S/Vol/TrackHost/Groove/Fill").rect
		local thumb = adapter.node("/S/Vol/TrackHost/Groove/Thumb").rect
		expect(track.w > 0).toBe(true)
		-- half the value is half the track, and the thumb rides with it
		expect(fill.w).toBe(math.floor(track.w * 0.5 + 0.5))
		expect(thumb.x - track.x).toBe(math.floor((track.w - 20) * 0.5 + 0.5))
	end)

	it("an idle slider is idle: re-feeding the same track geometry writes nothing", function()
		local _, adapter, _, pres = mountSlider()
		pres.refresh() -- settle
		-- syncGeometry re-feeds the track rect on EVERY refresh, and the fill and
		-- thumb are now memos over it. An unchanged rect therefore has to be a
		-- no-op end to end, or an at-rest slider re-solves its surface every
		-- frame. (This passes with either equality today, because rectOf hands
		-- back a stable table; it is here so that stops being load-bearing.)
		adapter.takeOps()
		pres.refresh()
		pres.refresh()
		expect(#adapter.takeOps()).toBe(0)
	end)

	it("follows the track when a resize changes it, without the value moving", function()
		local _, adapter, _, pres, value, _, env = mountSlider()
		local before = adapter.node("/S/Vol/TrackHost").rect.w
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		pres.refresh()
		local after = adapter.node("/S/Vol/TrackHost").rect
		expect(after.w > before).toBe(true)
		expect(value:peek()).toBe(50) -- geometry moved; the value did not
		-- ONE FRAME of lag by construction, and it is the honest answer rather
		-- than a bug: the solved rect is fed back AFTER the solve that produced
		-- it, so a visual derived from geometry converges on the next frame. The
		-- old defect was that it never converged at all.
		pres.refresh()
		expect(adapter.node("/S/Vol/TrackHost/Groove/Fill").rect.w).toBe(math.floor(after.w * 0.5 + 0.5))
		expect(adapter.node("/S/Vol/TrackHost/Groove/Thumb").rect.x - after.x).toBe(
			math.floor((after.w - 20) * 0.5 + 0.5)
		)
	end)
end)

describe("slider: the label clears the thumb (director review 2026-07-24)", function()
	it("leaves real space between the label's glyphs and the circle that can sit at the track's left edge", function()
		local _, adapter = mountSlider()
		local label = adapter.node("/S/Vol/Label").rect
		local track = adapter.node("/S/Vol/TrackHost").rect
		local gap = track.x - (label.x + label.w)
		-- the thumb is round and reaches the track's leading edge, so a straight
		-- 8px step reads as touching. 16 is the declared clearance.
		expect(gap).toBeGreaterThanOrEqual(16)
	end)

	it("the clearance survives a label whose measured box is exactly its glyphs", function()
		-- the estimator's slack is what used to hide this, so prove it with an
		-- EXACT measurement in place: the gap must come from the layout, not from
		-- a fat box
		local text_metrics = require("../src/layout/text_metrics")
		text_metrics.resetMeasured()
		text_metrics.setMeasured("BuilderSans", 16, "Vol", 21)
		local _, adapter = mountSlider()
		local label = adapter.node("/S/Vol/Label").rect
		local track = adapter.node("/S/Vol/TrackHost").rect
		expect(label.w).toBe(21)
		expect(track.x - (label.x + label.w)).toBeGreaterThanOrEqual(16)
		text_metrics.resetMeasured()
	end)
end)

describe("B-VAL2: the Slider's live drag is the NATIVE detector, with a proven fallback", function()
	it("attaches a UIDragDetector to the track through the controller seam", function()
		local _, _, _, _, _, control = mountSlider()
		expect(control.dump().nativeDetector).toBe(true)
	end)

	it("a native drag moves the value and commits on end", function()
		local committed: number? = nil
		local _, adapter, _, pres, value = mountSlider({
			onCommit = function(v: number)
				committed = v
			end,
		})
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.driveDragStart("/S/Vol/TrackHost/Track", { x = track.x, y = track.y })
		pres.refresh()
		adapter.driveDragContinue("/S/Vol/TrackHost/Track", { x = track.x + track.w, y = track.y }, nil)
		pres.refresh()
		expect(value:peek()).toBe(100)
		adapter.driveDragEnd("/S/Vol/TrackHost/Track", { x = track.x + track.w, y = track.y })
		expect(committed).toBe(100)
	end)

	it("FALLBACK: with no detector, the Grip capture path drives the SAME arithmetic", function()
		-- stepped so the assertion is about the ROUTE, not about float rounding on a
		-- 314px track
		local _, adapter, _, pres, value, control = mountSlider({ step = 5 }, { noDragDetector = true })
		expect(control.dump().nativeDetector).toBe(false)
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x + track.w // 4, track.y)
		pres.refresh()
		expect(value:peek()).toBe(25)
		adapter.pointerMove(track.x + track.w, track.y)
		pres.refresh()
		expect(value:peek()).toBe(100)
		adapter.pointerUp(track.x + track.w, track.y)
	end)

	it("pointer: tap-to-position jumps to the tapped fraction", function()
		local _, adapter, _, pres, value = mountSlider()
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x + track.w // 2, track.y)
		pres.refresh()
		expect(value:peek()).toBe(50)
		adapter.pointerUp(track.x + track.w // 2, track.y)
	end)

	it("tap-to-position can be switched off", function()
		local _, adapter, _, pres, value = mountSlider({ tapToPosition = false })
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x, track.y)
		pres.refresh()
		expect(value:peek()).toBe(50) -- unchanged until the drag moves
		adapter.pointerUp(track.x, track.y)
	end)

	it("touch: a touch-typed drag drives it identically", function()
		local _, adapter, _, pres, value = mountSlider(nil, { noDragDetector = true })
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x, track.y, "touch")
		pres.refresh()
		expect(value:peek()).toBe(0)
		adapter.pointerMove(track.x + track.w // 2, track.y)
		pres.refresh()
		expect(value:peek()).toBe(50)
		adapter.pointerUp(track.x + track.w // 2, track.y)
	end)

	it("the track meets the effective-target floor", function()
		local _, adapter = mountSlider()
		expect(adapter.node("/S/Vol/TrackHost/Track").rect.h >= 44).toBe(true)
	end)
end)

describe("B-VAL3: Slider keyboard, gamepad, bounds and hot-switch", function()
	it("keyboard: Adjust steps predictably rather than requiring a drag", function()
		local _, _, system, pres, value = mountSlider({ step = 10 })
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("Period", true)
		system.deviceKey("Period", false)
		pres.refresh()
		expect(value:peek()).toBe(60)
		system.deviceKey("Comma", true)
		system.deviceKey("Comma", false)
		pres.refresh()
		expect(value:peek()).toBe(50)
	end)

	it("gamepad: the bumpers Adjust the focused slider", function()
		local _, _, system, pres, value = mountSlider({ step = 10 })
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("ButtonR1", true)
		system.deviceKey("ButtonR1", false)
		pres.refresh()
		expect(value:peek()).toBe(60)
	end)

	it("stays inside its bounds from every route", function()
		local _, adapter, system, pres, value = mountSlider({ step = 10 })
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x - 500, track.y)
		pres.refresh()
		expect(value:peek()).toBe(0)
		adapter.pointerUp(track.x, track.y)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		for _ = 1, 5 do
			system.deviceKey("Comma", true)
			system.deviceKey("Comma", false)
		end
		pres.refresh()
		expect(value:peek()).toBe(0)
	end)

	it("Slider hot-switch: losing the pointer class mid-drag CANCELS back to the snapshot", function()
		local _, adapter, _, pres, value, control = mountSlider()
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x, track.y)
		pres.refresh()
		expect(value:peek()).toBe(0)
		expect(control.dump().dragging).toBe(true)
		control.onInteractionClassLost("pointer")
		pres.refresh()
		-- the half-finished drag must not commit a value the player did not choose
		expect(value:peek()).toBe(50)
		expect(control.dump().dragging).toBe(false)
	end)

	it("a cancelled capture also reverts (the adapter's own cancel path)", function()
		local _, adapter, _, pres, value = mountSlider(nil, { noDragDetector = true })
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x, track.y)
		pres.refresh()
		expect(value:peek()).toBe(0)
		-- the engine cancels a capture when its zone dies mid-drag; the fake mirrors
		-- that through _cancelIfCaptured, the same path the renderer's removal uses
		adapter._cancelIfCaptured(adapter.node("/S/Vol/TrackHost/Track"), "interrupted")
		pres.refresh()
		expect(value:peek()).toBe(50)
	end)

	it("a disabled Slider refuses drag AND Adjust", function()
		local _, adapter, system, pres, value = mountSlider({ enabled = false, step = 10 })
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x + track.w, track.y)
		pres.refresh()
		expect(value:peek()).toBe(50)
		adapter.pointerUp(track.x, track.y)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		system.deviceKey("Period", true)
		system.deviceKey("Period", false)
		pres.refresh()
		expect(value:peek()).toBe(50)
	end)

	it("shares the value model with Stepper: identical bounds arithmetic", function()
		local _, _, _, _, _, sliderControl = mountSlider({ min = 5, max = 25, step = 5 })
		local _, _, _, _, _, stepperControl = mountStepper({ min = 5, max = 25, step = 5 })
		expect(sliderControl.model.quantize(7)).toBe(stepperControl.model.quantize(7))
		expect(sliderControl.model.stepped(5, -1)).toBe(stepperControl.model.stepped(5, -1))
		expect(sliderControl.model.semanticText(10)).toBe(stepperControl.model.semanticText(10))
	end)

	it("dump is deterministic and build/dispose is registry-neutral", function()
		local serde = require("@lune/serde")
		local core, _, _, _, _, control = mountSlider()
		expect(serde.encode("json", control.dump(), true)).toBe(serde.encode("json", control.dump(), true))
		local baseline = core.owner.size()
		local value2 = Compose.cell(1)
		local second = harness.Controls.Slider(core, { id = "S2", value = value2, min = 0, max = 2 })
		second.dispose()
		local after = core.owner.size()
		expect(after).toBe(baseline)
		expect(after).toBe(baseline)
	end)
end)

-- ===== verifier finding V13 ==================================================

describe("verifier V13: a disabled Slider leaves focus order", function()
	it("navigation skips a disabled Slider's track instead of only refusing the verb", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new({ ops = true })
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local enabled = Compose.cell(false)
		local control = harness.Controls.Slider(core, {
			id = "Vol",
			label = "Vol",
			value = Compose.cell(50),
			min = 0,
			max = 100,
			enabled = enabled,
		})
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "Above", label = "a", height = { type = "fixed", px = 44 } }),
				control.blueprint,
				UI.Button({ id = "Below", label = "b", height = { type = "fixed", px = 44 } }),
			},
		}))
		pres.refresh()
		local function reachable(): string
			local seen = ""
			for _ = 1, 5 do
				system.deviceKey("DPadDown", true)
				system.deviceKey("DPadDown", false)
				pres.refresh()
				local f = pres.focus.focused:peek()
				if f ~= nil then
					seen ..= f .. ","
				end
			end
			return seen
		end
		local whileDisabled = reachable()
		expect(string.find(whileDisabled, "Below", 1, true) ~= nil).toBe(true)
		expect(string.find(whileDisabled, "Vol/TrackHost/Track", 1, true)).toBe(nil)
		-- ...and enabling puts it back, with no remount
		local liveBefore = adapter.liveCount()
		enabled:set(true)
		pres.refresh()
		expect(string.find(reachable(), "Vol/TrackHost/Track", 1, true) ~= nil).toBe(true)
		expect(adapter.liveCount()).toBe(liveBefore)
	end)
end)

-- ===== verifier finding V11 ==================================================

describe("verifier V11: the hit expander is re-based by its clip host", function()
	it("a sub-floor control inside a ScrollView gets an expander in HOST space, not window space", function()
		-- the expander used to be positioned with the raw window-space rect while
		-- every other instance is re-based by its clip host, so inside a ScrollView
		-- the invisible activation surface landed off by the host origin
		-- the WHOLE adapter: `applyHitExpander` — the shared placement helper this
		-- pin's second half anchors on — moved to `screen_presentation` with the
		-- presentation channel when screen_target crossed the 200_000-char Source
		-- cap, and the claim is about the adapter rather than about one of its files
		local source = adapter_source.live()
		-- (window widened 1800→2400 when the expander's Activated started building
		-- the SAME activate meta a press on the control itself carries — redteam
		-- item 2, 2026-08-13; then 2400→3000 when the expander began MIRRORING its
		-- host's declared sensory verb and disabled state at birth — release-
		-- candidate review F1, 2026-08-18; then a THIRD time, silently, when task
		-- CONN round 2 (`1a01521`) grew setHitRect's body by +519 chars replacing
		-- the inline hitExpanderPointerConn guard with a reconnectOnChange block,
		-- pushing this call 113 chars past the 3000-char edge with no test change
		-- to match — a red pin nobody noticed until the forensic attribution in
		-- .superpowers/sdd/framework-gaps-phase2-followups/value-controls-red-
		-- attribution.md. The invariant asserted below was unchanged all three
		-- times; only the text it lives in kept growing. Retiring the fixed-window
		-- idiom for good: this now anchors via adapter_source.bodyOf
		-- (find-until-next-sibling-declaration), which is immune to the function
		-- body growing, instead of guessing another width.
		local body = adapter_source.bodyOf(source, "function adapter.setHitRect(")
		expect(#body > 0).toBe(true)
		-- the seam still re-bases — through the shared placement helper the control's
		-- own re-base uses (RS-A16-D1b), which is what also fixes the origin arriving
		-- LATE. The property is unchanged; only its single home moved.
		expect(string.find(body, "applyHitExpander(handle)", 1, true) ~= nil).toBe(true)
		local atHelper = string.find(source, "local function applyHitExpander", 1, true)
		expect(atHelper ~= nil).toBe(true)
		local helper = string.sub(source, atHelper :: number, (atHelper :: number) + 700)
		-- the origin read moved one level further in (Plan C, C1): `hostOriginOf` is
		-- the one place that decides what a Position is relative to, and it answers 0
		-- under a COORDINATE-SPACE host, whose children's rects are already relative
		expect(string.find(helper, "hostOriginOf(handle)", 1, true) ~= nil).toBe(true)
		expect(string.find(helper, "rect.x - ox", 1, true) ~= nil).toBe(true)
		expect(string.find(helper, "rect.y - oy", 1, true) ~= nil).toBe(true)
	end)

	it("the framework still asks for the expansion in solver space", function()
		-- the RENDERER keeps reporting window-space rects; only the adapter re-bases,
		-- so the seam contract is unchanged for a target with no clip hosts
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = harness.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "List",
						height = { type = "fixed", px = 120 },
						children = {
							UI.Button({
								id = "Tiny",
								label = "x",
								width = { type = "fixed", px = 22 },
								height = { type = "fixed", px = 22 },
							}),
						},
					}),
				},
			})
		)
		local adapter = fake_target.new({ ops = true })
		local controller =
			require("../src/render/renderer").attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local node = adapter.node("/S/List/Tiny")
		local hit = adapter.hitRectOf("/S/List/Tiny") :: any
		expect(hit ~= nil).toBe(true)
		expect(hit.w).toBe(44)
		-- centred on the control in the SAME space the renderer reports rects
		expect(hit.x).toBe(node.rect.x - 11)
		expect(hit.y).toBe(node.rect.y - 11)
	end)
end)

describe("stepper: target geometry (director review 2026-07-24)", function()
	it("the -/+ buttons carry the 44px floor on BOTH axes, not just height", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local value = Compose.cell(6)
		local stepper = harness.Controls.Stepper(core, {
			id = "Vol",
			label = "Volume",
			value = value,
			min = 0,
			max = 10,
			step = 1,
		})
		local root = harness.mount(core, UI.Screen({ id = "S", children = { stepper.blueprint } }))
		local adapter = fake_target.new({ ops = true })
		local controller =
			require("../src/render/renderer").attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		for _, id in { "Dec", "Inc" } do
			local rect = adapter.node("/S/Vol/" .. id).rect
			-- a target the finger has to hit is a target on both axes; a 36x46
			-- sliver reads as a mistake even when its hit area is padded out
			expect(rect.w >= 44).toBe(true)
			expect(rect.h >= 44).toBe(true)
		end
		stepper.dispose()
		controller.dispose()
		root.dispose()
	end)

	it("the readout is centred and keeps a stable width, so the buttons never shift", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local value = Compose.cell(9)
		local stepper = harness.Controls.Stepper(core, {
			id = "Vol",
			label = "Volume",
			value = value,
			min = 0,
			max = 100,
			step = 1,
		})
		local root = harness.mount(core, UI.Screen({ id = "S", children = { stepper.blueprint } }))
		local adapter = fake_target.new({ ops = true })
		local controller =
			require("../src/render/renderer").attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/Vol/Value").props.textAlign).toBe("center")
		local incX = adapter.node("/S/Vol/Inc").rect.x
		local valueW = adapter.node("/S/Vol/Value").rect.w
		-- stepping to a WIDER number must not move the button under the finger
		value:set(10)
		controller.refresh()
		expect(adapter.node("/S/Vol/Value").rect.w).toBe(valueW)
		expect(adapter.node("/S/Vol/Inc").rect.x).toBe(incX)
		stepper.dispose()
		controller.dispose()
		root.dispose()
	end)
end)

-- ===== the customization ladder on a Slider (director fix round 2026-07-25) ==
--
-- RUNG 1 is the theme: a package's sliderTrack/sliderThumb recipes skin every
-- slider in the game. RUNG 2 is this — one view saying "not that one, THIS
-- picture", modifier-style, which opts that node out of theme changes.

describe("Slider: the decoration slot hint and the per-view override", function()
	local chrome_slots = require("../src/tokens/chrome_slots")

	-- find a node by trailing id in the mounted blueprint
	local function nodeById(node: any, id: string): any
		if node.id == id then
			return node
		end
		for _, child in node.children or {} do
			local found = nodeById(child, id)
			if found ~= nil then
				return found
			end
		end
		return nil
	end

	it("declares its rail and thumb slots on the INTERNAL meta channel", function()
		-- nothing generic can infer "this Box is a slider rail": `surface =
		-- "control"` would have given it the BUTTON skin, a button plate
		-- stretched into a groove
		local control = harness.Controls.Slider(customFactory.new(), {
			id = "Vol",
			value = Compose.cell(50),
			min = 0,
			max = 100,
		})
		local rail = nodeById(control.blueprint, "Rail")
		local thumb = nodeById(control.blueprint, "Thumb")
		expect(chrome_slots.readHint(rail).slot).toBe("sliderTrack")
		expect(chrome_slots.readHint(thumb).slot).toBe("sliderThumb")
		-- ...and the accent FILL declares that it is not a decoration surface at
		-- all, or an ornate package paints a button plate over the filled bar
		expect(chrome_slots.readHint(nodeById(control.blueprint, "Fill")).slot).toBe(chrome_slots.NO_SLOT)
		-- and NOT through the public prop bag: the hint is invisible to the schema
		expect((rail.props :: any).slot).toBeNil()
		expect((rail.props :: any).decoration).toBeNil()
		-- NEITHER node carries a public `surface` any more. Borrowing one was the
		-- whole bug: `surface = "raised"` on the thumb subscribed it to the panel
		-- treatment, and Glossy Mobile's panel gradient carries alpha, so the fill
		-- behind the thumb read straight through it.
		expect(rail.props.surface).toBeNil()
		expect(thumb.props.surface).toBeNil()
	end)

	it("a per-view thumbImage/trackImage rides the same channel", function()
		local core = customFactory.new()
		local control = harness.Controls.Slider(core, {
			id = "Vol",
			value = Compose.cell(50),
			min = 0,
			max = 100,
			thumbImage = "rbxassetid://4242",
			trackImage = "rbxassetid://2424",
		})
		expect(chrome_slots.readHint(nodeById(control.blueprint, "Thumb")).image).toBe("rbxassetid://4242")
		expect(chrome_slots.readHint(nodeById(control.blueprint, "Rail")).image).toBe("rbxassetid://2424")
		expect(control.dump().skinRung).toBe("view")
		expect(control.dump().thumbImage).toBe("rbxassetid://4242")
	end)

	it("without an override the control stays on the theme's rung", function()
		local _, _, _, _, _, control = mountSlider()
		expect(control.dump().skinRung).toBe("theme")
		expect(control.dump().thumbImage).toBeNil()
		expect(chrome_slots.readHint(nodeById(control.blueprint, "Thumb")).image).toBeNil()
	end)

	it("the override still works, and still mounts, on a flat theme", function()
		-- rung 2 is independent of the installed package: a game with no theme
		-- package at all can still hand ONE slider a picture
		local _, adapter, _, _, value, control = mountSlider({ thumbImage = "rbxassetid://99" })
		expect(adapter.node("/S/Vol/TrackHost/Groove/Thumb") ~= nil).toBe(true)
		expect(value:peek()).toBe(50)
		expect(control.dump().skinRung).toBe("view")
	end)
end)

-- ===== the hint has to REACH the adapter, not merely be declared =============
--
-- Live regression 2026-07-25 (glossy, native mode): the slider's rail and thumb
-- rendered INVISIBLE. The `Slot — sliderThumb` rules existed in the sheet and
-- every headless spec was green, because every one of them asserted EMISSION —
-- that the package compiles the rule — and none asserted APPLICATION: that the
-- live node ends up carrying the class tag those rules select on.
--
-- Two links in that chain are testable headlessly, and both are asserted here.

describe("Slider: the decoration hint reaches the render target", function()
	local chrome_slots = require("../src/tokens/chrome_slots")

	it("the adapter receives each hinted node's slot through create()", function()
		local _, adapter = mountSlider()
		-- blueprint -> mount (meta copied) -> renderer (readHint) -> adapter arg
		local thumb = adapter.node("/S/Vol/TrackHost/Groove/Thumb")
		local rail = adapter.node("/S/Vol/TrackHost/Groove/Rail")
		expect(thumb ~= nil and rail ~= nil).toBe(true)
		expect(thumb.decorationHint ~= nil).toBe(true)
		expect(thumb.decorationHint.slot).toBe("sliderThumb")
		expect(rail.decorationHint.slot).toBe("sliderTrack")
		-- the accent fill declares that it is NOT a decoration surface
		expect(adapter.node("/S/Vol/TrackHost/Groove/Fill").decorationHint.slot).toBe(chrome_slots.NO_SLOT)
		-- and a node that never declared one carries nothing at all
		expect(adapter.node("/S/Vol/Label").decorationHint).toBeNil()
	end)

	it("a per-view override rides the same argument", function()
		local _, adapter = mountSlider({ thumbImage = "rbxassetid://4242" })
		expect(adapter.node("/S/Vol/TrackHost/Groove/Thumb").decorationHint.image).toBe("rbxassetid://4242")
	end)

	it("the hint yields the tag the sheet's rules actually select on", function()
		-- the second link: given the slot the adapter received, the DESIRED tag
		-- set (sheet_model.classifyTags — the one and only builder syncTags
		-- diffs against) contains the tag `Slot — sliderThumb` keys on
		local sheet_model = require("../src/tokens/sheet_model")
		local _, adapter = mountSlider()
		for _, case in
			{
				{ path = "/S/Vol/TrackHost/Groove/Thumb", tag = "facet-slot-sliderThumb" },
				{ path = "/S/Vol/TrackHost/Groove/Rail", tag = "facet-slot-sliderTrack" },
			}
		do
			local node = adapter.node(case.path)
			local desired = sheet_model.classifyTags({
				surface = node.props.surface, -- nil: a hinted node borrows no surface
				slotHint = node.decorationHint.slot,
			})
			expect(desired[case.tag]).toBe(true)
			-- and it is the ONLY tag it earns: no surface treatment leaks in
			local count = 0
			for _ in desired do
				count += 1
			end
			expect(count).toBe(1)
		end
	end)
end)
-- ===== P3b: axis, rotation, range, thumb modes, custom knob ================
--
-- Every case below asks the SCREEN what happened — a solved rect, a hit rect, a
-- mounted path, the owner's own Signal — never the control's dump. The dump is
-- read in exactly one place (the fixture's report), and a control that agreed
-- with its own dump while painting something else is the defect these rows are
-- written against.

local function mountRange(specOverrides: any?, worldOverrides: any?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	for k, v in (worldOverrides or {}) :: any do
		env:set(k, v)
	end
	local adapter = fake_target.new({ ops = true })
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system, { keyboardNavigation = true })
	local value = Compose.cell({ lower = 20, upper = 60 })
	local spec: any = { id = "Gap", label = "Gap", value = value, min = 0, max = 100, range = true, step = 5 }
	for k, v in (specOverrides or {}) :: any do
		spec[k] = v
	end
	local control = harness.Controls.Slider(core, spec)
	pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
	pres.refresh()
	return core, adapter, system, pres, value, control, env
end

local RANGE_LOWER = "/S/Gap/TrackHost/Handles/HandleLower"
local RANGE_UPPER = "/S/Gap/TrackHost/Handles/HandleUpper"
local RANGE_TRACK = "/S/Gap/TrackHost/Track"

describe("Slider axis: a vertical track runs bottom to top", function()
	it("the fill grows from the BOTTOM edge and the thumb climbs as the value rises", function()
		local _, adapter, _, pres, value = mountSlider({ axis = "y", step = 10 }, nil)
		local track = adapter.node("/S/Vol/TrackHost").rect
		local fill = adapter.node("/S/Vol/TrackHost/Groove/Fill").rect
		-- a vertical track is TALL and thin: the value axis is its height
		expect(track.h > track.w).toBe(true)
		-- at 50 of 0..100 the fill is half the track and its BOTTOM edge is the
		-- track's bottom edge — a fill that grew downward would share the TOP one
		expect(fill.h).toBe(math.floor(track.h * 0.5 + 0.5))
		expect(fill.y + fill.h).toBe(track.y + track.h)
		local before = adapter.node("/S/Vol/TrackHost/Groove/Thumb").rect.y
		value:set(90)
		pres.refresh()
		pres.refresh()
		expect(adapter.node("/S/Vol/TrackHost/Groove/Thumb").rect.y < before).toBe(true)
	end)

	it("Up/Down adjust it and Left/Right do not, because the AXIS is what was authored", function()
		--[[ FOCUSED WITH TAB, DELIBERATELY. A vertical slider declares the VERTICAL
			adjust axis, which is the axis a flat screen also navigates on — the
			trade `contribution.Bundle` documents for this key — so arriving on
			DPadDown spends that press on navigation and the first arrow after it is
			absorbed by the same held-direction edge. Tab is the way in that does not
			share an axis with the value. ]]
		local _, _, system, pres, value = mountSlider({ axis = "y", step = 10 }, { keyboardNavigation = true })
		system.deviceKey("Tab", true)
		system.deviceKey("Tab", false)
		pres.refresh()
		-- Up increases a bottom-to-top track; the presenter's vertical adjust axis
		-- is what makes these arrows reach the control at all
		system.deviceKey("Up", true)
		system.deviceKey("Up", false)
		pres.refresh()
		expect(value:peek()).toBe(60)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		pres.refresh()
		expect(value:peek()).toBe(50)
		-- the other axis keeps navigating: it never reaches the value
		system.deviceKey("Right", true)
		system.deviceKey("Right", false)
		pres.refresh()
		expect(value:peek()).toBe(50)
	end)
end)

describe("Slider axis: the press that lands focus is not a value step", function()
	it("Up onto a vertical slider moves the ring only; the next Up steps it", function()
		for _, key in { "Up", "DPadUp" } do
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			local adapter = fake_target.new({ ops = true })
			local system = actionsLib.newSystem(core)
			local pres = presenterLib.new(core, env, adapter, system, { keyboardNavigation = true })
			local rear, boost = Compose.cell(50), Compose.cell(50)
			local vertical = harness.Controls.Slider(
				core,
				{ id = "Rear", label = "Rear", value = rear, min = 0, max = 100, step = 10, axis = "y" }
			)
			local horizontal = harness.Controls.Slider(
				core,
				{ id = "Boost", label = "Boost", value = boost, min = 0, max = 100, step = 10 }
			)
			pres.present(UI.Screen({ id = "S", children = { vertical.blueprint, horizontal.blueprint } }))
			pres.refresh()
			local function tap(code: string)
				system.deviceKey(code, true)
				pres.refresh()
				system.deviceKey(code, false)
				pres.refresh()
			end
			-- the engine hands a key HELD when its binding is made to that binding
			-- (one Up moved the ring AND stepped Rear); the headless model
			-- does not, so the engine's delivery is replayed as a second down
			pres.focus.focusOn("/S/Boost/TrackHost/Track")
			pres.refresh()
			system.deviceKey(key, true)
			pres.refresh()
			system.deviceKey(key, true)
			pres.refresh()
			system.deviceKey(key, false)
			pres.refresh()
			local ring = tostring(pres.focus.focused:peek())
			expect(`{key} landed {string.find(ring, "/S/Rear", 1, true) ~= nil} {rear:peek()}`).toBe(
				`{key} landed true 50`
			)
			tap(key)
			expect(`{key} next {rear:peek()}`).toBe(`{key} next 60`)
		end
	end)
end)

describe("Slider rotation: the painted angle and the pointer share one conversion", function()
	--[[ `rotation` is PAINT-ONLY about the node's centre, so the solver hands back
		the unrotated rect and the renderer can answer nothing about where the
		player pressed. The control therefore un-rotates the pointer itself — and
		THAT is what these cases drive: a press placed where the player's finger
		really lands on the turned track must produce the fraction the upright
		track would have produced at the same point along it. ]]
	local function pressAtFraction(adapter: any, pres: any, degrees: number, f: number, root: string?, painted: any?)
		local at = (root or "/S/Vol") .. "/TrackHost"
		local track = painted or adapter.node(at).rect
		local cx, cy = track.x + track.w / 2, track.y + track.h / 2
		-- the point ON the upright track at fraction f, then turned by the same
		-- angle the paint is turned by (screen y runs DOWN, so positive is clockwise)
		local ux, uy = track.x + track.w * f, cy
		local a = math.rad(degrees)
		local dx, dy = ux - cx, uy - cy
		local px = cx + dx * math.cos(a) - dy * math.sin(a)
		local py = cy + dx * math.sin(a) + dy * math.cos(a)
		adapter.pointerDown(at .. "/Track", px, py)
		pres.refresh()
		adapter.pointerUp(px, py)
	end

	it("every eighth of a turn reads the same value the upright track would", function()
		for _, degrees in { 45, 90, 135, 180, 225, 270, 315 } do
			local _, adapter, _, pres, value = mountSlider({ rotation = degrees, step = 25 })
			pressAtFraction(adapter, pres, degrees, 0.75)
			expect(`{degrees}deg -> {value:peek()}`).toBe(`{degrees}deg -> 75`)
		end
	end)

	it("a press on a SCROLLED track reads the painted position, not the layout one", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new({ ops = true })
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local value = Compose.cell(0)
		local control = harness.Controls.Slider(core, {
			id = "Vol",
			label = "Vol",
			value = value,
			min = 0,
			max = 100,
			step = 25,
			rotation = 90,
		})
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Scroll",
					axis = "y",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Box({ id = "Spacer", width = UI.fill(), height = { type = "fixed", px = 400 } }),
						control.blueprint,
						UI.Box({ id = "After", width = UI.fill(), height = { type = "fixed", px = 400 } }),
					},
				}),
			},
		}))
		pres.refresh()
		-- really scroll before the press: the painted track moves, its layout rect does not
		handle.controller.scrollTo("/S/Scroll", { x = 0, y = 300 })
		pres.refresh()
		local painted = handle.controller.screenRectOf("/S/Scroll/Vol/TrackHost")
		expect(painted.y ~= adapter.node("/S/Scroll/Vol/TrackHost").rect.y).toBe(true)
		pressAtFraction(adapter, pres, 90, 0.25, "/S/Scroll/Vol", painted)
		expect(value:peek()).toBe(25)
	end)

	it("an upright slider takes the untouched path: zero degrees costs no conversion", function()
		local _, adapter, _, pres, value = mountSlider({ rotation = 0, step = 25 })
		local track = adapter.node("/S/Vol/TrackHost").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x + track.w, track.y + track.h / 2)
		pres.refresh()
		adapter.pointerUp(track.x + track.w, track.y)
		expect(value:peek()).toBe(100)
	end)
end)

describe("Slider range: two thumbs, one track, and they never cross", function()
	it("both handles are targets that meet the touch floor, and the fill spans between them", function()
		local _, adapter = mountRange()
		local lower = adapter.hitRectOf(RANGE_LOWER)
		local upper = adapter.hitRectOf(RANGE_UPPER)
		expect(lower.w >= 44 and lower.h >= 44).toBe(true)
		expect(upper.w >= 44 and upper.h >= 44).toBe(true)
		-- the paint between them IS the selected band: it starts at the lower thumb
		-- and ends at the upper, rather than at the track's own edge
		local track = adapter.node("/S/Gap/TrackHost").rect
		local fill = adapter.node("/S/Gap/TrackHost/Groove/Fill").rect
		expect(fill.x - track.x).toBe(math.floor(track.w * 0.2 + 0.5))
		expect(fill.w).toBe(math.floor(track.w * 0.6 + 0.5) - math.floor(track.w * 0.2 + 0.5))
	end)

	it("a thumb stops at the other one, and `minGap` holds them apart", function()
		local _, adapter, _, pres, value = mountRange({ minGap = 10 })
		local track = adapter.node(RANGE_TRACK).rect
		-- drag the LOWER thumb all the way right: it must stop a whole gap short
		adapter.pointerDown(RANGE_LOWER, track.x + math.floor(track.w * 0.2), track.y + track.h / 2)
		pres.refresh()
		adapter.pointerMove(track.x + track.w, track.y + track.h / 2)
		pres.refresh()
		adapter.pointerUp(track.x + track.w, track.y + track.h / 2)
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("50/60")
	end)

	it("an arrow a thumb cannot use against its partner keeps the ring on that thumb", function()
		local _, _, system, pres, value = mountRange({ minGap = 10 })
		value:set({ lower = 50, upper = 60 })
		pres.refresh()
		expect(pres.focus.focused:peek()).toBe(RANGE_LOWER)
		system.deviceKey("Right", true)
		system.deviceKey("Right", false)
		pres.refresh()
		expect(`{pres.focus.focused:peek()} {value:peek().lower}`).toBe(`{RANGE_LOWER} 50`)
	end)

	it("a press LEFT of a coincident pair takes the lower thumb, and a press right takes the upper", function()
		for _, case in
			{
				{ at = 0.2, moves = "lower" },
				{ at = 0.8, moves = "upper" },
			}
		do
			local _, adapter, _, pres, value = mountRange({ step = 1 })
			value:set({ lower = 50, upper = 50 })
			pres.refresh()
			local track = adapter.node(RANGE_TRACK).rect
			local x = track.x + track.w * case.at
			adapter.pointerDown(RANGE_TRACK, x, track.y + track.h / 2)
			pres.refresh()
			adapter.pointerUp(x, track.y + track.h / 2)
			local pair = value:peek()
			local moved = if pair.lower ~= 50 then "lower" else "upper"
			expect(`at {case.at} -> {moved}`).toBe(`at {case.at} -> {case.moves}`)
		end
	end)

	it("a drag keeps the thumb it started with, even dragged past the other one", function()
		local _, adapter, _, pres, value = mountRange({ minGap = 0 })
		local track = adapter.node(RANGE_TRACK).rect
		-- grab the UPPER thumb and drag it all the way to the left edge: it must
		-- pile up on the lower thumb, never hand the gesture over to it
		adapter.pointerDown(RANGE_UPPER, track.x + math.floor(track.w * 0.6), track.y + track.h / 2)
		pres.refresh()
		adapter.pointerMove(track.x, track.y + track.h / 2)
		pres.refresh()
		adapter.pointerUp(track.x, track.y + track.h / 2)
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("20/20")
	end)

	it("ONE commit per completed gesture, and it names the thumb that moved", function()
		local commits = {}
		local _, adapter, _, pres = mountRange({
			onCommit = function(range: any, info: any)
				table.insert(commits, `{info.thumb}:{range.lower}-{range.upper}`)
			end,
		})
		local track = adapter.node(RANGE_TRACK).rect
		adapter.pointerDown(RANGE_UPPER, track.x + math.floor(track.w * 0.6), track.y + track.h / 2)
		pres.refresh()
		for _, f in { 0.7, 0.8, 0.9 } do
			adapter.pointerMove(track.x + track.w * f, track.y + track.h / 2)
			pres.refresh()
		end
		adapter.pointerUp(track.x + track.w * 0.9, track.y + track.h / 2)
		expect(#commits).toBe(1)
		expect(commits[1]).toBe("upper:20-90")
	end)

	it("keyboard: each thumb is its own Tab stop, and the arrows adjust the one holding the ring", function()
		local _, _, system, pres, value = mountRange()
		local function tab()
			system.deviceKey("Tab", true)
			system.deviceKey("Tab", false)
			pres.refresh()
		end
		local function right()
			system.deviceKey("Right", true)
			system.deviceKey("Right", false)
			pres.refresh()
		end
		-- the ring enters on the LOWER thumb (the group's own entry), and the arrow
		-- moves THAT number
		expect(pres.focus.focused:peek()).toBe(RANGE_LOWER)
		right()
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("25/60")
		-- ...and Tab is a second stop, not a way past the pair
		tab()
		expect(pres.focus.focused:peek()).toBe(RANGE_UPPER)
		right()
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("25/65")
		-- a third Tab LEAVES the control rather than bouncing between the thumbs
		-- forever: with nothing else on this screen it wraps back to the entry
		tab()
		expect(pres.focus.focused:peek()).toBe(RANGE_LOWER)
	end)

	it("gamepad: Left/Right reach the other thumb until Activate engages, and Cancel gives them back", function()
		local _, _, system, pres, value = mountRange(nil, {
			capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
		})
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		expect(pres.focus.focused:peek()).toBe(RANGE_LOWER)
		-- NOT engaged: the arrow is navigation, so the ring moves and nothing changes
		system.deviceKey("DPadRight", true)
		system.deviceKey("DPadRight", false)
		pres.refresh()
		expect(pres.focus.focused:peek()).toBe(RANGE_UPPER)
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("20/60")
		-- engaged: the same arrow is the value
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		pres.refresh()
		system.deviceKey("DPadRight", true)
		system.deviceKey("DPadRight", false)
		pres.refresh()
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("20/65")
		expect(pres.focus.focused:peek()).toBe(RANGE_UPPER)
		-- ...AND IT IS LEAVEABLE. Cancel drops the mode and the arrow navigates again
		system.deviceKey("ButtonB", true)
		system.deviceKey("ButtonB", false)
		pres.refresh()
		system.deviceKey("DPadLeft", true)
		system.deviceKey("DPadLeft", false)
		pres.refresh()
		expect(pres.focus.focused:peek()).toBe(RANGE_LOWER)
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("20/65")
	end)

	it("losing the pointer class mid-drag restores BOTH numbers, not just the one that moved", function()
		local _, adapter, _, pres, value, control = mountRange()
		local track = adapter.node(RANGE_TRACK).rect
		adapter.pointerDown(RANGE_LOWER, track.x + math.floor(track.w * 0.2), track.y + track.h / 2)
		pres.refresh()
		adapter.pointerMove(track.x, track.y + track.h / 2)
		pres.refresh()
		expect(value:peek().lower).toBe(0)
		control.onInteractionClassLost("pointer")
		pres.refresh()
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("20/60")
	end)

	it("a REAL capability loss mid-drag restores the pair, and the later move and release commit nothing", function()
		local commits = 0
		local _, adapter, _, pres, value, _, env = mountRange({
			onCommit = function()
				commits += 1
			end,
		}, { capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false } })
		local track = adapter.node(RANGE_TRACK).rect
		adapter.pointerDown(RANGE_LOWER, track.x + math.floor(track.w * 0.2), track.y + track.h / 2)
		pres.refresh()
		adapter.pointerMove(track.x, track.y + track.h / 2)
		pres.refresh()
		expect(value:peek().lower).toBe(0)
		-- the device's pointer and touch go away: the environment's live class set moves
		env:set("capabilities", { keyboard = false, mouse = false, touch = false, gamepad = true })
		pres.refresh()
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("20/60")
		adapter.pointerMove(track.x + track.w * 0.4, track.y + track.h / 2)
		adapter.pointerUp(track.x + track.w * 0.4, track.y + track.h / 2)
		pres.refresh()
		expect(`{value:peek().lower}/{value:peek().upper} commits={commits}`).toBe("20/60 commits=0")
	end)

	it("an authored pair the wrong way round is a spec error, not a silent swap", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			harness.Controls.Slider(core, {
				id = "Bad",
				value = Compose.cell({ lower = 80, upper = 20 }),
				min = 0,
				max = 100,
				range = true,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "is above", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Slider thumb modes and the custom knob", function()
	it('`thumb = "none"` paints no handle and leaves every route open', function()
		local _, adapter, system, pres, value = mountSlider({ thumb = "none", step = 10 })
		-- the handle is not painted...
		expect(adapter.visibleOf("/S/Vol/TrackHost/Groove/Thumb")).toBe(false)
		-- ...and the readout still says the value
		expect(adapter.node("/S/Vol/Value").props.text).toBe("50")
		-- pointer and touch still reach it
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x + track.w, track.y, "touch")
		pres.refresh()
		adapter.pointerUp(track.x + track.w, track.y)
		expect(value:peek()).toBe(100)
		-- and so do keyboard and gamepad
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("Comma", true)
		system.deviceKey("Comma", false)
		pres.refresh()
		system.deviceKey("ButtonL1", true)
		system.deviceKey("ButtonL1", false)
		pres.refresh()
		expect(value:peek()).toBe(80)
	end)

	it('`thumb = "auto"` keeps the handle out at rest and brings it back on focus', function()
		local _, adapter, system, pres = mountSlider({ thumb = "auto" })
		expect(adapter.visibleOf("/S/Vol/TrackHost/Groove/Thumb")).toBe(false)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		expect(adapter.visibleOf("/S/Vol/TrackHost/Groove/Thumb")).toBe(true)
	end)

	it('`thumb = "auto"` on a TOUCH-primary surface keeps a handle to grab', function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		local adapter = fake_target.new({ ops = true })
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local control = harness.Controls.Slider(core, {
			id = "Vol",
			label = "Vol",
			value = Compose.cell(50),
			min = 0,
			max = 100,
			thumb = "auto",
		})
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		expect(adapter.visibleOf("/S/Vol/TrackHost/Groove/Thumb")).toBe(true)
	end)

	it("a custom knob is built once per thumb and solves at the control's own footprint", function()
		local builds = 0
		local seen: { any } = {}
		local _, adapter, _, pres, value = mountSlider({
			step = 10,
			thumbContent = function(info: any)
				builds += 1
				table.insert(seen, info.thumb)
				return UI.Text({ id = "Pip", text = "x", textSize = "caption" })
			end,
		})
		expect(builds).toBe(1)
		expect(seen[1]).toBe("value")
		local knob = adapter.node("/S/Vol/TrackHost/Groove/Thumb").rect
		local mark = adapter.node("/S/Vol/TrackHost/Groove/Thumb/Pip").rect
		-- the handle is the CONTROL's, floored at the theme's own thumb metric, and
		-- the caller's mark is centred inside it rather than deciding its size
		expect(knob.w >= mark.w and knob.h >= mark.h).toBe(true)
		expect(knob.w).toBe(20)
		-- ...and the mark never paints outside the handle that carries it
		expect(mark.x >= knob.x and mark.x + mark.w <= knob.x + knob.w).toBe(true)
		-- and it rides the value without being rebuilt
		value:set(100)
		pres.refresh()
		pres.refresh()
		expect(builds).toBe(1)
		expect(adapter.node("/S/Vol/TrackHost/Groove/Thumb").rect.x > knob.x).toBe(true)
	end)

	it("a custom knob drops the theme's own slot, so no package paints a circle behind it", function()
		local _, adapter = mountSlider({
			thumbContent = function()
				return UI.Text({ id = "Pip", text = "x", textSize = "caption" })
			end,
		})
		-- the handle node keeps its id and loses the chrome hint with the box that
		-- named it: a package's `Slot — sliderThumb` rule has nothing to select
		expect(adapter.node("/S/Vol/TrackHost/Groove/Thumb").decorationHint).toBeNil()
		-- ...and it grows rather than clipping when the content outgrows the metric
		local big = select(
			2,
			mountSlider({
				thumbContent = function()
					return UI.Box({
						id = "Wide",
						width = { type = "fixed", px = 40 },
						height = { type = "fixed", px = 40 },
					})
				end,
			})
		)
		expect(big.node("/S/Vol/TrackHost/Groove/Thumb").rect.w).toBe(40)
	end)
end)

describe("Slider controlSize: the plate shrinks and the target does not", function()
	it("a named rung paints a thinner track inside a whole reserved target", function()
		local _, adapter = mountSlider({ controlSize = "compact" })
		local floor = adapter.node("/S/Vol/TrackHost+target").rect
		local plate = adapter.node("/S/Vol/TrackHost+target/TrackHost").rect
		expect(plate.h < floor.h).toBe(true)
		expect(floor.h >= 44).toBe(true)
		-- and the hit surface still answers for a whole finger
		local hit = adapter.hitRectOf("/S/Vol/TrackHost+target/TrackHost/Track")
		expect(hit.h >= 44).toBe(true)
	end)
end)

-- ===== P3b fix round 1 =====================================================

describe('Slider `thumb = "auto"`: the hover route is wired, not just declared', function()
	it("the handle appears under the pointer and goes again when it leaves", function()
		--[[ The attach used to live inside `bindController` behind
			`trackPath ~= nil` — never true there, because the presenter binds the
			controller BEFORE the first geometry feed and the track path is only
			learned by that feed. So the one writer of `hovered` never ran and the
			handle that `auto` promises under the pointer never came. This drives the
			engine's own hover stream, which is the seam that was dead. ]]
		local _, adapter, _, pres = mountSlider({ thumb = "auto" })
		local TRACK = "/S/Vol/TrackHost/Track"
		local THUMB = "/S/Vol/TrackHost/Groove/Thumb"
		expect(adapter.visibleOf(THUMB)).toBe(false)
		adapter.hover(TRACK)
		pres.refresh()
		expect(adapter.visibleOf(THUMB)).toBe(true)
		adapter.unhover(TRACK)
		pres.refresh()
		expect(adapter.visibleOf(THUMB)).toBe(false)
	end)
end)

describe("Slider `controlSize` on a vertical track", function()
	it("a rung thins the track and the column keeps its travel", function()
		--[[ `reserveTarget` floors the axis it is given, and flooring the VALUE axis
			of a vertical slider is the content-sizing collapse this file names: a
			`fill` track inside a hugging parent resolves to one touch target and the
			travel goes with it. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new({ ops = true })
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local control = harness.Controls.Slider(core, {
			id = "Vol",
			label = "Vol",
			value = Compose.cell(50),
			min = 0,
			max = 100,
			step = 5,
			axis = "y",
			controlSize = "compact",
		})
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ZStack({
					id = "Stage",
					width = { type = "fixed", px = 120 },
					height = { type = "fixed", px = 260 },
					children = { control.blueprint },
				}),
			},
		}))
		pres.refresh()
		local floor = adapter.node("/S/Stage/Vol/TrackHost+target").rect
		local plate = adapter.node("/S/Stage/Vol/TrackHost+target/TrackHost").rect
		-- the track still has a column to run down...
		expect(plate.h > 150).toBe(true)
		-- ...its paint is thinner than a whole target ACROSS...
		expect(plate.w < 44).toBe(true)
		-- ...and the reserved footprint is still a finger wide
		expect(floor.w >= 44).toBe(true)
	end)
end)

describe("Slider range: an illegal pair arriving at RUNTIME is quarantined, never fatal", function()
	local function drive(next_: any, reason: string, overrides: any?)
		local _, adapter, _, pres, value, control = mountRange(overrides)
		local before = adapter.node("/S/Gap/TrackHost/Groove/Fill").rect
		value:set(next_)
		pres.refresh()
		pres.refresh()
		local after = adapter.node("/S/Gap/TrackHost/Groove/Fill").rect
		-- the screen holds the last legal band rather than painting nonsense...
		expect(`{reason}: {after.x},{after.w}`).toBe(`{reason}: {before.x},{before.w}`)
		-- ...the refusal is SAID rather than swallowed...
		expect(`{reason}: said`).toBe(`{reason}: {if #control.diagnostics() > 0 then "said" else "silent"}`)
		-- ...and nothing was quarantined inside the solve
		return control
	end

	it("a reversed pair, a scalar, a nil and a pair narrower than its own gap all keep the last legal band", function()
		drive({ lower = 80, upper = 20 }, "reversed")
		drive(50, "scalar")
		drive(nil, "nil")
		drive({ lower = 40, upper = 41 }, "under the gap", { minGap = 10 })
	end)

	it("and the control is still DRIVEABLE afterwards, from the pointer", function()
		local _, adapter, _, pres, value = mountRange({ minGap = 10 })
		value:set({ lower = 90, upper = 10 })
		pres.refresh()
		local track = adapter.node(RANGE_TRACK).rect
		adapter.pointerDown(RANGE_LOWER, track.x, track.y + track.h / 2)
		pres.refresh()
		adapter.pointerUp(track.x, track.y + track.h / 2)
		-- the press moved the LAST LEGAL pair's lower thumb to the floor
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("0/60")
	end)

	it("an authored pair narrower than its own gap is a build error", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			harness.Controls.Slider(core, {
				id = "Bad",
				value = Compose.cell({ lower = 40, upper = 41 }),
				min = 0,
				max = 100,
				range = true,
				minGap = 10,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "narrower than", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Slider: the words that decide what it IS are refused when bound", function()
	it("a bound axis names itself rather than freezing on its first reading", function()
		local core = customFactory.new()
		for _, key in { "axis", "range", "thumb", "minGap" } do
			local spec: any = { id = "B", value = Compose.cell(0.5), min = 0, max = 1 }
			spec[key] = function()
				return if key == "minGap" then 0 else "x"
			end
			local ok, err = pcall(function()
				harness.Controls.Slider(core, spec)
			end)
			expect(`{key}: {ok}`).toBe(`{key}: false`)
			expect(`{key}: {string.find(tostring(err), "construction-only", 1, true) ~= nil}`).toBe(`{key}: true`)
		end
	end)
end)

describe("Slider range: each handle's travel is priced off its OWN art", function()
	it("two different-sized knobs both stop at the track's end", function()
		local _, adapter, _, pres, value = mountRange({
			minGap = 0,
			thumbContent = function(info: any)
				local px = if info.thumb == "upper" then 40 else 12
				return UI.Box({
					id = "Art",
					width = { type = "fixed", px = px },
					height = { type = "fixed", px = px },
				})
			end,
		})
		value:set({ lower = 0, upper = 100 })
		pres.refresh()
		pres.refresh()
		local track = adapter.node("/S/Gap/TrackHost").rect
		local lower = adapter.node("/S/Gap/TrackHost/Handles/ThumbLower").rect
		local upper = adapter.node("/S/Gap/TrackHost/Handles/ThumbUpper").rect
		-- the two handles really are different sizes...
		expect(upper.w > lower.w).toBe(true)
		-- ...the lower one sits at the track's start...
		expect(lower.x).toBe(track.x)
		-- ...and the BIGGER one still stops exactly at its end, rather than hanging
		-- past it by the size difference
		expect(upper.x + upper.w).toBe(track.x + track.w)
	end)
end)

describe("Slider: two answers to one question are refused", function()
	it("a thumbImage beside a thumbContent names the collision", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			harness.Controls.Slider(core, {
				id = "B",
				value = Compose.cell(0.5),
				min = 0,
				max = 1,
				thumbImage = "rbxassetid://1",
				thumbContent = function()
					return UI.Box({ id = "Art" })
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "both paint the handle", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Slider range adjust mode: only a pad may enter it", function()
	it("a keyboard Return on a handle does not latch a mode a keyboard never needs", function()
		local _, _, system, pres, value, control = mountRange()
		expect(pres.focus.focused:peek()).toBe(RANGE_LOWER)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		pres.refresh()
		expect(control.dump().engaged).toBe(false)
		-- ...and the arrows still adjust, which is the keyboard's whole story
		system.deviceKey("Right", true)
		system.deviceKey("Right", false)
		pres.refresh()
		expect(`{value:peek().lower}/{value:peek().upper}`).toBe("25/60")
	end)
end)

describe("Slider range: legality at build, and lifetimes", function()
	it("an initial NaN, a bad type and a bad gap are build errors, never a seeded fallback", function()
		for _, bad in { { lower = 0 / 0, upper = 10 }, { lower = "1", upper = 10 }, { lower = 1, upper = math.huge } } do
			local core = customFactory.new()
			local ok = pcall(function()
				harness.Controls.Slider(core, { id = "B", value = Compose.cell(bad), min = 0, max = 100, range = true })
			end)
			expect(ok).toBe(false)
		end
	end)

	it("a runtime NaN keeps the last legal band, and a legal pair afterwards paints and drives again", function()
		local _, adapter, _, pres, value, control = mountRange()
		value:set({ lower = 0 / 0, upper = 50 })
		pres.refresh()
		expect(#control.diagnostics()).toBe(1)
		value:set({ lower = 30, upper = 70 })
		pres.refresh()
		pres.refresh()
		local track = adapter.node("/S/Gap/TrackHost").rect
		local fill = adapter.node("/S/Gap/TrackHost/Groove/Fill").rect
		expect(fill.x - track.x).toBe(math.floor(track.w * 0.3 + 0.5))
		-- a repeat of the same refusal is recorded once; a legal read resets that
		value:set({ lower = 0 / 0, upper = 50 })
		pres.refresh()
		expect(#control.diagnostics()).toBe(2)
	end)

	it("a knob is told its own thumb, and building, driving and disposing leaves the owner as it was", function()
		local core = customFactory.new()
		local baseline = core.owner.size()
		local seen: { string } = {}
		local control = harness.Controls.Slider(core, {
			id = "L",
			value = Compose.cell({ lower = 10, upper = 90 }),
			min = 0,
			max = 100,
			range = true,
			thumb = "auto",
			thumbContent = function(info: any)
				table.insert(seen, info.thumb)
				return UI.Box({ id = "Art" })
			end,
		})
		expect(table.concat(seen, " ")).toBe("lower upper")
		control.dispose()
		expect(core.owner.size()).toBe(baseline)
	end)
end)
