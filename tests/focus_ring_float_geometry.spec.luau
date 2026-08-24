--!strict
-- THE FLOAT FOCUS RING'S GEOMETRY (device bug fix round, director 2026-08-23,
-- "Screen-anchored HUD" toggle screenshot). Two defects, one fixture: a
-- gamepad/keyboard focus on a control inside a SCROLLED/clipped host (the
-- showcase demo picker's row list) draws a `FocusRingFloat` — the manually
-- positioned Frame+UIStroke `adapter.setFocusVisual` builds because an
-- outward-drawing ring under a clipping ScrollingFrame gets cut.
--
-- `src/client/screen_target.luau` reaches engine globals at load time and
-- cannot run headlessly (docs/lessons/the-200k-source-cap-is-on-writing-or-
-- loading.md's sibling problem), so — same instrument
-- `theme_layer_application.spec.luau` uses — this reads the live adapter as
-- TEXT and pins the two defects' fixes structurally. Reverting either edit
-- turns exactly one case below red.
--
-- (a) THE LIFT ORDERING. `style.extra.tenFootFocusScale` lifts a strongly-
-- focused control via a top-left-anchored UIScale (`FocusScale`), applied
-- AFTER the float used to be sized — so the float was always sized from the
-- PRE-lift rect while the button visually grew past it on the right/bottom
-- (the two edges a top-left anchor grows into). Measured live (demo picker,
-- console-ten-foot, a scrolled row): button 146x69 base -> 153x72 lifted;
-- float stuck at 138x61. Fixed by computing `lift`/`liftScale` BEFORE the
-- float's own Size line and multiplying it in.
--
-- (b) THE NATIVE PHANTOM CORNER. Under native paint (B-15's default) a
-- rounded control's `::UICorner` is a StyleSheet pseudo-element the ENGINE
-- materializes at render time and never a real child instance
-- (`native_style.luau`'s own note: "a real modifier instance here would
-- silently defeat those rules") — so `host:FindFirstChildOfClass("UICorner")`
-- always answered nil on a native-styled host, and the float shipped with a
-- sharp corner over a control the player sees painted round. Fixed with a
-- fallback that resolves the SAME role -> radius mapping `applySurface`'s
-- bespoke `corner()` already uses (`screen_paint.luau`), applied to the
-- float's own (unstyled, framework-owned) instance.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local adapter_source = require("./lib/adapter_source")

local source = fs.readFile("src/client/screen_target.luau")
local FN = adapter_source.bodyOf(source, "function adapter.setFocusVisual(")

local function at(needle: string): number
	local i = string.find(FN, needle, 1, true)
	expect(i ~= nil).toBe(true)
	return i :: number
end

describe("screen_target.setFocusVisual: the float ring's geometry (device fix round)", function()
	it("found the function body (the anchor still names a real member)", function()
		expect(#FN > 0).toBe(true)
	end)

	it("(a) computes the lift scale before the float is sized, not after", function()
		local liftScaleAt = at("local liftScale = if strong and lift then")
		local floatSizeAt = at("rect.w * liftScale - 2 * thickness")
		expect(liftScaleAt < floatSizeAt).toBe(true)
	end)

	it("(a) the float's Size is the rect scaled by the lift factor on both axes", function()
		expect(string.find(FN, "rect.w * liftScale - 2 * thickness", 1, true) ~= nil).toBe(true)
		expect(string.find(FN, "rect.h * liftScale - 2 * thickness", 1, true) ~= nil).toBe(true)
	end)

	it("(a) the float's Position stays UNSCALED (the lift anchors top-left)", function()
		-- the position line reads the plain rect, never `* liftScale` — a scaled
		-- position would mean the anchor moved, which the lift never does
		local posLineStart = at("f.Position = UDim2.fromOffset(rect.x - origin.x + thickness")
		local posLineEnd = string.find(FN, ")\n", posLineStart, true) or (posLineStart + 120)
		local posLine = string.sub(FN, posLineStart, posLineEnd)
		expect(string.find(posLine, "liftScale", 1, true)).toBe(nil)
	end)

	it("(b) falls back to a resolved radius when no literal UICorner clone exists", function()
		local cloneAt = at("corner:Clone().Parent = float")
		local fallbackAt = at("local surfaceRole = handle.nativeSurface or handle.declaredSurface")
		expect(cloneAt < fallbackAt).toBe(true)
	end)

	it("(b) the fallback mirrors applySurface's bespoke role -> radius mapping", function()
		expect(string.find(FN, 'surfaceRole == "raised"', 1, true) ~= nil).toBe(true)
		expect(string.find(FN, "style.radii.panel", 1, true) ~= nil).toBe(true)
		expect(string.find(FN, 'surfaceRole == "control" or surfaceRole == "chip"', 1, true) ~= nil).toBe(true)
		expect(string.find(FN, "style.radii.control", 1, true) ~= nil).toBe(true)
		expect(string.find(FN, 'handle.shape == "circle"', 1, true) ~= nil).toBe(true)
		expect(string.find(FN, "UDim.new(0.5, 0)", 1, true) ~= nil).toBe(true)
	end)

	it("(b) the fallback corner is parented on the float, not on the styled host", function()
		local fallbackCornerAt = at('local fallbackCorner = Instance.new("UICorner")')
		local parentAt = string.find(FN, "fallbackCorner.Parent = float", fallbackCornerAt, true)
		expect(parentAt ~= nil).toBe(true)
	end)
end)
