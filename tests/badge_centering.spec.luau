--!strict
--[[ A BADGE'S NUMBER SITS IN THE MIDDLE OF ITS SEAL.

	WHAT WAS REPORTED (owner, 2026-09-12, Compact Pointer): the "3" on the Inbox
	tab sits off-centre in its white circle.

	WHAT IT ACTUALLY WAS, and it is not a text-bounds boot-window read or a hug
	that failed. A count seal is a `UI.Text` carrying `surface = "badge"`, and two
	independent rules make its plate bigger than its glyph: `render/layout_node
	.luau` gives a badge an intrinsic MINIMUM on both axes (`controls.badge
	.minimum`, 20px in Facet Neutral) and the row recipe spends an `xs` of padding
	a side. So the plate is 20px wide around an 8px glyph — and the glyph was
	drawn LEFT, because `screen_target` defaults a text node to
	`TextXAlignment.Left` and this one declared no `textAlign`. Measured in Facet
	Neutral: a 20x20 seal whose text rect is centred at x+5 of its own 10, two
	pixels off on a twenty-pixel circle.

	THE TWO HALVES DISAGREED, which is what makes it a defect rather than a taste
	call. `chrome_slots.CENTRED_LIFT_SLOTS` is `{ badge = true }` and its comment
	states the rule out loud — "A badge's number belongs in the middle of its
	seal" — so a badge wearing a package's SKIN has its lifted label centred on
	both axes. An unskinned badge, which is every badge under every flat theme
	including Facet Neutral, kept the class default. One surface, two answers.

	`menu_recipe` is also the file that already writes `textAlign = "center"`
	twice, on the two glyphs of a selection indicator ten lines up. The badge is
	the odd one out in its own recipe.

	WHAT IS PINNED HERE. The text rect a badge's glyph actually lands in, derived
	the way the adapter derives it — the node's rect, less its own resolved
	padding, with the glyph measured through `Facet.text.measure` and placed by
	the declared `textAlign` horizontally and `TextYAlignment.Center` vertically
	(adapter-owned, `screen_target`'s create branch) — is concentric with the
	plate to within a pixel. Run over Facet Neutral and every theme of every
	shipped example package, because the plate minimum, the padding step and the
	type ramp are all the theme's and a badge that centres in one has to centre in
	all of them.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local chrome_slots = require("../src/tokens/chrome_slots")
local text_metrics = require("../src/layout/text_metrics")

local UI = Facet.UI

local PACKAGES: { { name: string, module: any } } = {
	{ name = "classic_desktop", module = require("../examples/themes/classic_desktop") },
	{ name = "compact_pointer", module = require("../examples/themes/compact_pointer") },
	{ name = "fantasy_ornate", module = require("../examples/themes/fantasy_ornate") },
	{ name = "fantasy_parchment", module = require("../examples/themes/fantasy_parchment") },
	{ name = "glossy_mobile", module = require("../examples/themes/glossy_mobile") },
	{ name = "glossy_touch", module = require("../examples/themes/glossy_touch") },
	{ name = "pixel_quest", module = require("../examples/themes/pixel_quest") },
	{ name = "scifi_hud", module = require("../examples/themes/scifi_hud") },
}

local BADGE_TEXT = "3"

local function badgeWorld(metrics: any?)
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = 900, h = 720 },
		safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		themeMetrics = metrics,
	})
	local picker = Facet.Controls.Picker(w.core, {
		id = "View",
		selected = w.core:signal("a"),
		options = {
			{ value = "a", label = "Pages" },
			{ value = "b", label = "Inbox", badge = BADGE_TEXT },
			{ value = "c", label = "Notes" },
		},
		env = w.env,
		presentation = "segmented",
	})
	w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
	for _, path in w.adapter.paths() do
		if string.sub(path, -#"/Badge") == "/Badge" then
			return w.adapter.node(path)
		end
	end
	error("the badged option did not mount a seal")
end

type Rect = { x: number, y: number, w: number, h: number }

--[[ WHERE THE GLYPH ACTUALLY LANDS, derived the way the live adapter derives it.
	A `UIPadding` insets a TextLabel's text area, so the box is the node's rect
	less its own resolved padding; the horizontal place is the declared
	`textAlign` (`start` when none is declared — `screen_target` writes
	`TextXAlignment.Left` at create); the vertical place is always Center, which
	is adapter-owned and deliberately so (the headless measurer over-reserves and
	centring splits that error evenly). ]]
local function textRectOf(node: any): Rect
	local pad: any = node.props.padding or {}
	local function px(value: any): number
		return if type(value) == "number" then value else 0
	end
	local left, right, top, bottom = px(pad.left), px(pad.right), px(pad.top), px(pad.bottom)
	local box: Rect = {
		x = node.rect.x + left,
		y = node.rect.y + top,
		w = node.rect.w - left - right,
		h = node.rect.h - top - bottom,
	}
	local font = node.props.textFont
	assert(type(font) == "table" and type(font.family) == "string", "the seal carries no resolved font")
	assert(type(node.props.textSize) == "number", "the seal carries no resolved text size")
	-- a generous width: a one-glyph count never wraps, and a width clamped to the
	-- box would measure the box rather than the glyph
	local measured =
		text_metrics.measure({ text = node.props.text, font = font.family, size = node.props.textSize, width = 4096 })
	local align = node.props.textAlign or "start"
	local x = if align == "center"
		then box.x + (box.w - measured.width) / 2
		elseif align == "end" then box.x + box.w - measured.width
		else box.x
	return { x = x, y = box.y + (box.h - measured.height) / 2, w = measured.width, h = measured.height }
end

local function offCentre(node: any): (number, number)
	local text = textRectOf(node)
	local dx = (text.x + text.w / 2) - (node.rect.x + node.rect.w / 2)
	local dy = (text.y + text.h / 2) - (node.rect.y + node.rect.h / 2)
	return dx, dy
end

describe("badge centering: the seal is bigger than the glyph, on purpose", function()
	it("the plate takes the theme's badge minimum, so there is slack to be off-centre in", function()
		local node = badgeWorld()
		local measured =
			text_metrics.measure({ text = BADGE_TEXT, font = "BuilderSans", size = node.props.textSize, width = 4096 })
		expect(node.rect.w > measured.width).toBe(true)
		expect(node.rect.h > measured.height).toBe(true)
	end)

	it("the skinned half already centres, which is the rule the unskinned half has to match", function()
		expect(chrome_slots.centresLiftedText("badge")).toBe(true)
		-- ...and it is specific to the badge, not a blanket lift rule
		expect(chrome_slots.centresLiftedText("control")).toBe(false)
	end)
end)

describe("badge centering: the glyph is concentric with its plate in every theme", function()
	it("Facet Neutral", function()
		local dx, dy = offCentre(badgeWorld())
		expect(`dx {math.abs(dx) <= 1} dy {math.abs(dy) <= 1}`).toBe("dx true dy true")
	end)

	it("...and every theme of every shipped example package", function()
		local checked = 0
		for _, entry in PACKAGES do
			local package, report = entry.module.build(Facet.themes)
			assert(package ~= nil, `{entry.name} failed its own package gate: {report and report.errors[1]}`)
			for _, theme in package.style.themes do
				local metrics = Facet.themes.resolve(package, theme.name, {})
				local node = badgeWorld(metrics)
				local dx, dy = offCentre(node)
				checked += 1
				assert(
					math.abs(dx) <= 1 and math.abs(dy) <= 1,
					`{entry.name}/{theme.name}: the glyph is off-centre by {dx}, {dy} in a `
						.. `{node.rect.w}x{node.rect.h} seal`
				)
			end
		end
		expect(checked > 8).toBe(true)
	end)
end)
