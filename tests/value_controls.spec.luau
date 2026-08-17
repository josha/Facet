--!strict
-- Milestone B — the value-control family (docs/plans/swiftui-parity-next.md
-- investment 4; acceptance rows B-VAL1 and B-VAL3).
--
-- B-VAL1 is the SHARED model: Slider and Stepper are different affordances over
-- one piece of arithmetic, so they cannot disagree at the edges.
-- B-VAL3 is reach: every input class must arrive at that same arithmetic through
-- a real path (adapter.tap / system.deviceKey), never a direct callback.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local valueModel = require("../src/controls/value_model")
local fake_target = require("../tests/lib/fake_target")
local adapter_source = require("./lib/adapter_source")

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
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	local value = core:signal(5)
	local spec: any = { id = "Volume", label = "Volume", value = value, min = 0, max = 10, step = 1 }
	for k, v in (specOverrides or {}) :: any do
		spec[k] = v
	end
	local control = LuauUI.newStepper(LuauUI, core, spec)
	pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
	pres.refresh()
	return core, adapter, system, pres, value, control
end

describe("B-VAL3: Stepper reaches the same arithmetic from every input class", function()
	it("pointer: tapping plus and minus steps the owner's value", function()
		local _, adapter, _, pres, value = mountStepper()
		adapter.tap("/S/Volume/Inc")
		pres.refresh()
		expect(value:get()).toBe(6)
		adapter.tap("/S/Volume/Dec")
		adapter.tap("/S/Volume/Dec")
		pres.refresh()
		expect(value:get()).toBe(4)
	end)

	it("touch: a finger tap on + steps it identically", function()
		local _, adapter, _, pres, value = mountStepper()
		adapter.pointerDown("/S/Volume/Inc", 0, 0, "touch")
		adapter.tap("/S/Volume/Inc", { pointer = "touch" })
		pres.refresh()
		expect(value:get()).toBe(6)
	end)

	it("keyboard: Adjust on the focused control steps without touching a button", function()
		local _, _, system, pres, value = mountStepper()
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("Period", true)
		system.deviceKey("Period", false)
		pres.refresh()
		expect(value:get()).toBe(6)
		system.deviceKey("Comma", true)
		system.deviceKey("Comma", false)
		pres.refresh()
		expect(value:get()).toBe(5)
	end)

	it("gamepad: ButtonA on the focused + activates, and the bumpers Adjust", function()
		local _, _, system, pres, value = mountStepper()
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("ButtonR1", true)
		system.deviceKey("ButtonR1", false)
		pres.refresh()
		expect(value:get()).toBe(6)
		system.deviceKey("ButtonL1", true)
		system.deviceKey("ButtonL1", false)
		pres.refresh()
		expect(value:get()).toBe(5)
	end)

	it("no Adjust key is bound while focus sits outside the Stepper (no gameplay bumper shadow)", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local value = core:signal(5)
		local control = LuauUI.newStepper(LuauUI, core, {
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
		expect(value:get()).toBe(5)
	end)
end)

describe("B-VAL3: Stepper bounds, formatting, disabled and lifecycle", function()
	it("stops at both bounds instead of running past them", function()
		local _, adapter, _, pres, value = mountStepper({ value = nil })
		for _ = 1, 20 do
			adapter.tap("/S/Volume/Inc")
		end
		pres.refresh()
		expect(value:get()).toBe(10)
		for _ = 1, 30 do
			adapter.tap("/S/Volume/Dec")
		end
		pres.refresh()
		expect(value:get()).toBe(0)
	end)

	it("the affordance at a bound is DISABLED, not silently inert", function()
		local _, adapter, _, pres, value = mountStepper()
		for _ = 1, 10 do
			adapter.tap("/S/Volume/Inc")
		end
		pres.refresh()
		expect(value:get()).toBe(10)
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
		expect(value:get()).toBe(5)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		system.deviceKey("Period", true)
		system.deviceKey("Period", false)
		pres.refresh()
		expect(value:get()).toBe(5)
	end)

	it("rejects a non-settable value instead of silently owning one", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			return LuauUI.newStepper(
				LuauUI,
				core,
				{ id = "X", value = core:memo(function()
					return 1
				end), min = 0, max = 2 }
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "SETTABLE Signal", 1, true) ~= nil).toBe(true)
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
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local value = core:signal(5)
		local baseline = core:counters()
		local control = LuauUI.newStepper(LuauUI, core, {
			id = "V",
			label = "V",
			value = value,
			min = 0,
			max = 10,
			step = 1,
		})
		control.dispose()
		local after = core:counters()
		expect(after.scopes).toBe(baseline.scopes)
		expect(after.observers).toBe(baseline.observers)
	end)
end)

-- ===== Slider (B-VAL2 / B-VAL3) ============================================

local function mountSlider(specOverrides: any?, fakeOpts: any?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new()
	if fakeOpts ~= nil and (fakeOpts :: any).noDragDetector then
		(adapter :: any).noDragDetector = true
	end
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	local value = core:signal(50)
	local spec: any = { id = "Vol", label = "Vol", value = value, min = 0, max = 100 }
	for k, v in (specOverrides or {}) :: any do
		spec[k] = v
	end
	local control = LuauUI.newSlider(LuauUI, core, spec)
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
		expect(value:get()).toBe(50) -- geometry moved; the value did not
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
		expect(value:get()).toBe(100)
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
		expect(value:get()).toBe(25)
		adapter.pointerMove(track.x + track.w, track.y)
		pres.refresh()
		expect(value:get()).toBe(100)
		adapter.pointerUp(track.x + track.w, track.y)
	end)

	it("pointer: tap-to-position jumps to the tapped fraction", function()
		local _, adapter, _, pres, value = mountSlider()
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x + track.w // 2, track.y)
		pres.refresh()
		expect(value:get()).toBe(50)
		adapter.pointerUp(track.x + track.w // 2, track.y)
	end)

	it("tap-to-position can be switched off", function()
		local _, adapter, _, pres, value = mountSlider({ tapToPosition = false })
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x, track.y)
		pres.refresh()
		expect(value:get()).toBe(50) -- unchanged until the drag moves
		adapter.pointerUp(track.x, track.y)
	end)

	it("touch: a touch-typed drag drives it identically", function()
		local _, adapter, _, pres, value = mountSlider(nil, { noDragDetector = true })
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x, track.y, "touch")
		pres.refresh()
		expect(value:get()).toBe(0)
		adapter.pointerMove(track.x + track.w // 2, track.y)
		pres.refresh()
		expect(value:get()).toBe(50)
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
		expect(value:get()).toBe(60)
		system.deviceKey("Comma", true)
		system.deviceKey("Comma", false)
		pres.refresh()
		expect(value:get()).toBe(50)
	end)

	it("gamepad: the bumpers Adjust the focused slider", function()
		local _, _, system, pres, value = mountSlider({ step = 10 })
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("ButtonR1", true)
		system.deviceKey("ButtonR1", false)
		pres.refresh()
		expect(value:get()).toBe(60)
	end)

	it("stays inside its bounds from every route", function()
		local _, adapter, system, pres, value = mountSlider({ step = 10 })
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x - 500, track.y)
		pres.refresh()
		expect(value:get()).toBe(0)
		adapter.pointerUp(track.x, track.y)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		for _ = 1, 5 do
			system.deviceKey("Comma", true)
			system.deviceKey("Comma", false)
		end
		pres.refresh()
		expect(value:get()).toBe(0)
	end)

	it("Slider hot-switch: losing the pointer class mid-drag CANCELS back to the snapshot", function()
		local _, adapter, _, pres, value, control = mountSlider()
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x, track.y)
		pres.refresh()
		expect(value:get()).toBe(0)
		expect(control.dump().dragging).toBe(true)
		control.onInteractionClassLost("pointer")
		pres.refresh()
		-- the half-finished drag must not commit a value the player did not choose
		expect(value:get()).toBe(50)
		expect(control.dump().dragging).toBe(false)
	end)

	it("a cancelled capture also reverts (the adapter's own cancel path)", function()
		local _, adapter, _, pres, value = mountSlider(nil, { noDragDetector = true })
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x, track.y)
		pres.refresh()
		expect(value:get()).toBe(0)
		-- the engine cancels a capture when its zone dies mid-drag; the fake mirrors
		-- that through _cancelIfCaptured, the same path the renderer's removal uses
		adapter._cancelIfCaptured(adapter.node("/S/Vol/TrackHost/Track"), "interrupted")
		pres.refresh()
		expect(value:get()).toBe(50)
	end)

	it("a disabled Slider refuses drag AND Adjust", function()
		local _, adapter, system, pres, value = mountSlider({ enabled = false, step = 10 })
		local track = adapter.node("/S/Vol/TrackHost/Track").rect
		adapter.pointerDown("/S/Vol/TrackHost/Track", track.x + track.w, track.y)
		pres.refresh()
		expect(value:get()).toBe(50)
		adapter.pointerUp(track.x, track.y)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		system.deviceKey("Period", true)
		system.deviceKey("Period", false)
		pres.refresh()
		expect(value:get()).toBe(50)
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
		local baseline = core:counters()
		local value2 = core:signal(1)
		local second = LuauUI.newSlider(LuauUI, core, { id = "S2", value = value2, min = 0, max = 2 })
		second.dispose()
		local after = core:counters()
		expect(after.scopes).toBe(baseline.scopes)
		expect(after.observers).toBe(baseline.observers)
	end)
end)

-- ===== verifier finding V13 ==================================================

describe("verifier V13: a disabled Slider leaves focus order", function()
	it("navigation skips a disabled Slider's track instead of only refusing the verb", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local enabled = core:signal(false)
		local control = LuauUI.newSlider(LuauUI, core, {
			id = "Vol",
			label = "Vol",
			value = core:signal(50),
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
				local f = pres.focus.focused:get()
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
		local at = string.find(source, "function adapter.setHitRect", 1, true)
		expect(at ~= nil).toBe(true)
		-- (window widened 1800→2400 when the expander's Activated started building
		-- the SAME activate meta a press on the control itself carries — redteam
		-- item 2, 2026-08-13. The invariant asserted below is unchanged; the text
		-- it lives in grew by three comment lines and a typed parameter.)
		local body = string.sub(source, at :: number, (at :: number) + 2400)
		-- the seam still re-bases — through the shared placement helper the control's
		-- own re-base uses (RS-A16-D1b), which is what also fixes the origin arriving
		-- LATE. The property is unchanged; only its single home moved.
		expect(string.find(body, "applyHitExpander(handle)", 1, true) ~= nil).toBe(true)
		local atHelper = string.find(source, "local function applyHitExpander", 1, true)
		expect(atHelper ~= nil).toBe(true)
		local helper = string.sub(source, atHelper :: number, (atHelper :: number) + 700)
		expect(string.find(helper, "handle.instanceHost", 1, true) ~= nil).toBe(true)
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
		local root = require("../src/mount").mount(
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
		local adapter = fake_target.new()
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
		local value = core:signal(6)
		local stepper = LuauUI.newStepper(LuauUI, core, {
			id = "Vol",
			label = "Volume",
			value = value,
			min = 0,
			max = 10,
			step = 1,
		})
		local root = require("../src/mount").mount(core, UI.Screen({ id = "S", children = { stepper.blueprint } }))
		local adapter = fake_target.new()
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
		local value = core:signal(9)
		local stepper = LuauUI.newStepper(LuauUI, core, {
			id = "Vol",
			label = "Volume",
			value = value,
			min = 0,
			max = 100,
			step = 1,
		})
		local root = require("../src/mount").mount(core, UI.Screen({ id = "S", children = { stepper.blueprint } }))
		local adapter = fake_target.new()
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
-- picture", SwiftUI-style, which opts that node out of theme changes.

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
		local control = LuauUI.newSlider(LuauUI, customFactory.new(), {
			id = "Vol",
			value = customFactory.new():signal(50),
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
		local control = LuauUI.newSlider(LuauUI, core, {
			id = "Vol",
			value = core:signal(50),
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
		expect(value:get()).toBe(50)
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
				{ path = "/S/Vol/TrackHost/Groove/Thumb", tag = "luau-slot-sliderThumb" },
				{ path = "/S/Vol/TrackHost/Groove/Rail", tag = "luau-slot-sliderTrack" },
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
