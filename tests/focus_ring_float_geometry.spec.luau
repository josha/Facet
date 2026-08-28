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
--
-- (c) TWO MORE DEFECTS, fixed together (task THEME2, director item: "the
-- selection ring is rounded vs matching the theme", i1.png — Pixel Quest's
-- hard-cornered plaque wrapped in a smooth rounded ring):
--
--   (c1) THE CORNER WAS ONLY EVER BUILT `if float == nil` — at first
--   creation, never again. `refreshFocusVisuals` re-enters `setFocusVisual`
--   for every STILL-FOCUSED handle on a live theme swap specifically so it can
--   "repaint whatever is showing one right now" (`setActiveTheme`'s own
--   documented job) — but the corner was invisible to that repaint, so a
--   control that stayed focused across a swap kept the OUTGOING theme's ring
--   shape forever. Fixed by moving the corner sync OUT of the `if float ==
--   nil` guard so it re-runs, idempotently, on every call.
--
--   (c2) THE FALLBACK READ `style.radii`, A CONSTRUCTION-TIME SNAPSHOT THAT IS
--   NEVER REASSIGNED (`screen_paint.luau`'s own contract: "style, nativeMode,
--   palette — construction-time facts, by value"). A live package install/
--   swap instead reassigns `activeThemeSnapshot` (`setThemePackage`'s whole
--   job), so the fallback answered "what radius did this target boot with"
--   forever, on the FIRST focus after a swap too, not only one that survived
--   it. Fixed by preferring `activeThemeSnapshot.radii` (the SAME
--   `themeSnapshot`-shaped table `style.radii` is) when a package is
--   installed, falling back to `style.radii` exactly as before when it is not.

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
		local cloneAt = at("floatCorner = realCorner:Clone()")
		local fallbackAt = at("local surfaceRole = handle.nativeSurface or handle.declaredSurface")
		expect(cloneAt < fallbackAt).toBe(true)
	end)

	it("(b) the fallback mirrors applySurface's bespoke role -> radius mapping", function()
		expect(string.find(FN, 'surfaceRole == "raised"', 1, true) ~= nil).toBe(true)
		expect(string.find(FN, "liveRadii.panel", 1, true) ~= nil).toBe(true)
		expect(string.find(FN, 'surfaceRole == "control" or surfaceRole == "chip"', 1, true) ~= nil).toBe(true)
		expect(string.find(FN, "liveRadii.control", 1, true) ~= nil).toBe(true)
		expect(string.find(FN, 'handle.shape == "circle"', 1, true) ~= nil).toBe(true)
		expect(string.find(FN, "UDim.new(0.5, 0)", 1, true) ~= nil).toBe(true)
	end)

	it("(b) the fallback corner is parented on the float, not on the styled host", function()
		local fallbackCornerAt = at('floatCorner = Instance.new("UICorner")')
		local parentAt = string.find(FN, "floatCorner.Parent = float", fallbackCornerAt, true)
		expect(parentAt ~= nil).toBe(true)
	end)

	it("(c1) the corner sync runs after float creation, and only once per call", function()
		-- the creation guard assigns `handle.focusRingFloat` exactly once, before
		-- the corner lookup — a mutation that moved the lookup back INTO the `if
		-- float == nil` guard (the pre-fix shape) would put it BEFORE this line
		-- instead of after
		local createdAt = at("handle.focusRingFloat = float")
		local syncAt = at('local realCorner = host:FindFirstChildOfClass("UICorner")')
		expect(createdAt < syncAt).toBe(true)
		-- and the lookup is not itself repeated (a copy inside the guard would
		-- make the fix a no-op for a float that already existed)
		local _, occurrences = string.gsub(FN, 'host:FindFirstChildOfClass%("UICorner"%)', "")
		expect(occurrences).toBe(1)
	end)

	it("(c1) an existing float's corner is UPDATED in place, never duplicated", function()
		-- both branches (real-corner clone, native fallback) reuse `floatCorner`
		-- when one is already there — a `floatCorner == nil` guard around each
		-- `Instance.new`/`:Clone()`, and a plain `.CornerRadius =` write on the
		-- else side of each — which is what makes re-running this block on
		-- every call idempotent rather than a leak of one UICorner per swap
		expect(string.find(FN, 'local floatCorner = float:FindFirstChildOfClass("UICorner")', 1, true) ~= nil):toBe(
			true
		)
		expect(string.find(FN, "(floatCorner :: UICorner).CornerRadius = realCorner.CornerRadius", 1, true) ~= nil):toBe(
			true
		)
		expect(string.find(FN, "(floatCorner :: UICorner).CornerRadius = radius", 1, true) ~= nil):toBe(true)
	end)

	it("(c2) the live package's radii win over the frozen construction-time style", function()
		-- `activeThemeSnapshot` (reassigned by every `setThemePackage` swap) is
		-- read FIRST; `style.radii` (never reassigned — the construction-time
		-- fact `screen_paint.luau`'s own header names) is the fallback, never
		-- the answer, whenever a package is installed
		local liveRadiiAt = at('local liveRadii = if type(activeThemeSnapshot) == "table"')
		expect(string.find(FN, "then (activeThemeSnapshot :: any).radii", liveRadiiAt, true) ~= nil):toBe(true)
		local elseAt = string.find(FN, "else style.radii", liveRadiiAt, true)
		expect(elseAt ~= nil).toBe(true)
		-- and the mapping below reads `liveRadii`, never `style.radii`, directly
		expect(string.find(FN, "radius = UDim.new(0, style.radii", 1, true)).toBe(nil)
	end)
end)
