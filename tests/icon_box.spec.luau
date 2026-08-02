--!strict
-- THE ICON'S BOX (director report, 2026-07-28).
--
-- Three of the four defects in that report were ONE defect: a semantic icon is
-- PAINTED at the theme's `iconSizes` rung and was MEASURED as the ASCII glyph
-- string the control draws underneath it. A ">" is 6px wide; Fantasy Ornate's
-- `medium` rung is 32. The picture was therefore 13px wider than its own node on
-- EVERY side, and it painted straight through the frame beside it and the label
-- after it.
--
-- Measured live before the fix, across all nine reference configurations:
--
--     studio-neutral    box 8x22   icon 20x20   6.0px overhang per side
--     classic-desktop   box 6x15   icon 20x20   7.0px
--     compact-pointer   box 6x17   no art       0
--     fantasy-ornate    box 6x23   icon 32x32   13.0px
--     fantasy-parchment box 6x23   icon 20x20   7.0px
--     glossy-mobile     box 8x24   icon 20x20   6.0px
--     glossy-touch      box 8x23   no art       0
--     pixel-quest       box 7x20   icon 32x32   12.5px
--     scifi-hud         box 7x21   icon 20x20   6.5px
--
-- So this was never a Fantasy Ornate bug. It was every package that paints an
-- icon at all, and the two that looked clean were clean only because they draw
-- no picture — which is exactly why the second half of this file matters as much
-- as the first: THE PACKAGES THAT DRAW NO ART MUST NOT MOVE BY A PIXEL. A
-- reservation that fires unconditionally would fix seven packages by breaking
-- the geometry of the two that were already right.
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local LuauUI = require("../src") :: any
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local chrome_slots = require("../src/tokens/chrome_slots")
local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local fake_target = require("./lib/fake_target")

local PACKAGES = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local function packageOf(name: string): any
	return (require)(`../examples/themes/{name}`).build(LuauUI.themes)
end

-- every configuration the library ships, INCLUDING the flat neutral one: the
-- live measurement above proved Studio Neutral overhangs by 6px, so a sweep that
-- skipped it would have called the defect theme-specific
local function configurations(): { { name: string, pkg: any } }
	local out = { { name = "studio-neutral", pkg = snapshot.neutralPackage() } }
	for _, name in PACKAGES do
		table.insert(out, { name = name, pkg = packageOf(name) })
	end
	return out
end

-- does this package actually PAINT a picture for this name, or does it fall all
-- the way through to the ASCII character? That is the whole condition — the
-- reservation exists to hold a picture, so a name with no picture reserves
-- nothing.
local function paintsArt(pkg: any, name: string): boolean
	local resolved = themes.resolveIcon(pkg, name)
	return type(resolved) == "table" and resolved.source == "asset"
end

-- mount ONE icon-hinted text node the way `disclosure_group` builds its caret --
-- the glyph as the node's own text, the semantic name on the hint beside it --
-- and report the rect the solver reserved for it.
local function caretRect(pkg: any, iconName: string, iconSize: string?): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 400 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	env:set("themeMetrics", snapshot.resolve(pkg, nil, {}))
	local adapter = fake_target.new()
	local caret = chrome_slots.attachHint(
		UI.Text({ id = "Caret", text = themes.iconGlyph(iconName) or ">", textSize = "control" }),
		{ icon = iconName, iconSize = iconSize }
	)
	local root = mountLib.mount(core, UI.Screen({ id = "S", padding = 0, children = { caret } }))
	local controller = rendererLib.attach(core, root, env, adapter, {})
	controller.initialRender()
	local rect = adapter.node("/S/Caret").rect
	local out = { w = rect.w, h = rect.h }
	controller.dispose()
	root.dispose()
	return out
end

describe("the icon's box: a picture is reserved for, not painted over", function()
	it("an icon-hinted node is never smaller than the picture drawn on it", function()
		-- THE DEFECT, stated as an invariant. The picture is centred on the node,
		-- so a node narrower than the picture overhangs by half the difference on
		-- each side -- which is what reached the frame and the label.
		for _, config in configurations() do
			local snap = snapshot.resolve(config.pkg, nil, {})
			if paintsArt(config.pkg, "chevron.trailing") then
				local rect = caretRect(config.pkg, "chevron.trailing")
				local px = snap.iconSizes.medium
				expect(`{config.name}: w {rect.w} >= icon {px}`).toBe(`{config.name}: w {rect.w} >= icon {px}`)
				expect(rect.w >= px).toBe(true)
				expect(rect.h >= px).toBe(true)
			end
		end
	end)

	it("...at whichever `iconSizes` rung the hint names", function()
		-- the reservation reads the SAME role the adapter paints at, or the two
		-- seams disagree again in the other direction
		local pkg = packageOf("fantasy_ornate")
		local snap = snapshot.resolve(pkg, nil, {})
		for _, role in { "small", "medium", "large" } do
			local rect = caretRect(pkg, "chevron.trailing", role)
			expect(rect.w >= snap.iconSizes[role]).toBe(true)
			expect(rect.h >= snap.iconSizes[role]).toBe(true)
		end
	end)

	it("a package that draws NO art reserves nothing extra — flat geometry is untouched", function()
		-- glossy-touch and compact-pointer decline the framework rung on purpose
		-- (a controlled ASCII comparison against the ornate packages). They drew
		-- the caret correctly BEFORE this change and must draw it identically
		-- after: an unconditional reservation would fix seven packages by
		-- breaking the two that were already right.
		local checked = 0
		for _, config in configurations() do
			if not paintsArt(config.pkg, "chevron.trailing") then
				local snap = snapshot.resolve(config.pkg, nil, {})
				local rect = caretRect(config.pkg, "chevron.trailing")
				-- the glyph is one narrow character; the icon rung is 20px+. If the
				-- reservation had fired here, the box would BE the rung.
				expect(rect.w < snap.iconSizes.medium).toBe(true)
				checked += 1
			end
		end
		-- the sweep must actually have exercised the negative case, or this test
		-- passes by finding nothing (the shape a package rename would produce)
		expect(checked > 0).toBe(true)
	end)

	it("a node with an EXPLICIT size keeps it — the author still wins", function()
		-- the floor only applies to an axis the solver derives from content. A
		-- fixed box is an instruction, and the paint-side clamp (screen_chrome)
		-- is what keeps the picture inside it.
		local pkg = packageOf("fantasy_ornate")
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("themeMetrics", snapshot.resolve(pkg, nil, {}))
		local adapter = fake_target.new()
		local caret = chrome_slots.attachHint(
			UI.Text({ id = "Caret", text = ">", textSize = "control", width = { type = "fixed", px = 12 } }),
			{ icon = "chevron.trailing" }
		)
		local root = mountLib.mount(core, UI.Screen({ id = "S", padding = 0, children = { caret } }))
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/Caret").rect.w).toBe(12)
		controller.dispose()
		root.dispose()
	end)

	it("the snapshot publishes WHICH names resolve to art, derived not authored", function()
		-- the solver cannot ask the package (it holds the snapshot), and the
		-- condition above is load-bearing, so the answer rides the snapshot the
		-- same way `chromeBleed` and `iconRunGap` do: derived on resolve, nothing
		-- new for a package to author, no content stamp moved.
		for _, config in configurations() do
			local snap = snapshot.resolve(config.pkg, nil, {})
			expect(type(snap.iconArt)).toBe("table")
			for _, name in { "chevron.trailing", "chevron.down", "edit" } do
				expect(`{config.name}/{name}={tostring(snap.iconArt[name] == true)}`).toBe(
					`{config.name}/{name}={tostring(paintsArt(config.pkg, name))}`
				)
			end
		end
	end)
end)

describe("the icon's box: the paint seam clamps to what it was given", function()
	it("a picture never draws wider than the node's content box", function()
		-- the report's defect 1, in numbers: `CmpIcon` solved to 52x67 under
		-- Fantasy Ornate with 12px of padding a side, so the content box is 28 --
		-- and the package's `medium` rung is 32. The picture drew 32 and spilled
		-- past the frame both sides.
		expect(chrome_slots.iconBoxPx(32, 52, 67, 24, 0)).toBe(28)
		-- the height can be the binding axis just as easily
		expect(chrome_slots.iconBoxPx(32, 200, 18, 0, 0)).toBe(18)
	end)

	it("a node with room draws the theme's rung untouched", function()
		-- the clamp is a ceiling, never a resize: a node the renderer already grew
		-- to hold the picture must paint it at full size or the measure half was
		-- pointless.
		expect(chrome_slots.iconBoxPx(32, 44, 55, 0, 0)).toBe(32)
		expect(chrome_slots.iconBoxPx(20, 20, 20, 0, 0)).toBe(20)
	end)

	it("no rect yet means no constraint — the re-fit happens when it lands", function()
		-- on the create path a handle can carry a picture before its first
		-- `setRect`. Guessing a box there would draw a 1px icon and cache it.
		expect(chrome_slots.iconBoxPx(32, nil, nil, 0, 0)).toBe(32)
	end)

	it("never zero — a tight picture beats an invisible one", function()
		-- a node squeezed to nothing is a different defect (the chrome-inset
		-- collapse). Rendering a 0px image would hide the evidence of it.
		expect(chrome_slots.iconBoxPx(32, 10, 10, 40, 40)).toBe(1)
	end)

	it("the clamp is applied where the picture is sized", function()
		-- the measure half cannot help a node whose size the author fixed -- the
		-- compact-label button in the report is `width = 52` under a package whose
		-- own frame leaves 28. So the adapter caps the drawn px to the box it
		-- actually has, and this pins that the cap exists at the sizing line
		-- rather than leaving the suite green with a picture painting outside its
		-- node again.
		local fs = require("@lune/fs")
		local source = fs.readFile("src/client/screen_chrome.luau")
		local sizingLine = string.find(source, "child.Size = UDim2.fromOffset(", 1, true)
		expect(sizingLine ~= nil).toBe(true)
		-- `iconBoxPx` is the clamp: it must be computed BEFORE the size is written
		local clamp = string.find(source, "iconBoxPx", 1, true)
		expect(clamp ~= nil).toBe(true)
		expect((clamp :: number) < (sizingLine :: number)).toBe(true)
	end)
end)
