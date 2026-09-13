--!strict
--[[ A BADGE'S NUMBER SITS IN THE MIDDLE OF ITS SEAL, AND THE PROOF IS TWO RECTS.

	WHAT WAS REPORTED (owner, 2026-09-12, Compact Pointer): the "3" on the Inbox
	tab sits off-centre in its white circle.

	THE PLATE IS BIGGER THAN THE GLYPH, by two rules that both mean to be:
	`render/layout_node.luau` gives `surface = "badge"` an intrinsic MINIMUM on
	both axes (`controls.badge.minimum`, 20px in Facet Neutral) and the row recipe
	spends an `xs` a side. So something has to decide where the number sits in the
	slack — and while the plate and the glyph were ONE `UI.Text`, nothing in Facet
	did. The horizontal answer came from `src/client/screen_target.luau`'s create
	default for a text node, `TextXAlignment.Left`; the vertical one from its
	`TextYAlignment.Center`. One of those two is wrong, and neither of them is the
	control's.

	WHY THIS FILE IS A REWRITE. Its first version derived the glyph's rect by
	arithmetic — the node's rect, less its padding, plus a measured text box,
	placed by the declared alignment — and then asserted that the result was
	centred. That is a tautology on the horizontal axis the moment `textAlign` is
	`"center"`, and on the vertical axis it asserted nothing at all: both deltas
	were zero by construction, for every theme, forever. It pinned a declaration.

	SO THE SEAL IS A PLATE WITH A GLYPH INSIDE IT, and this file reads the two
	SOLVED rects the layout actually produced. The numbers below are what the
	stack does when it is left to place the child itself, measured before the fix:

	    Facet Neutral    20x20 plate, 8x15 glyph at +6,+0   dy -2.5
	    Compact Pointer  20x20 plate, 11x14 glyph at +2,+0  dx -2.5  dy -3
	    Pixel Quest      20x20 plate, 12x15 glyph at +4,+0  dy -2.5
	    Glossy Touch     25x20 plate, 13x17 glyph at +6,+0  dy -1.5

	`alignH`/`alignV` are what put it in the middle, as the control's own decision
	on both axes, in a form this target can see.

	WHAT IS PINNED, over Facet Neutral and every theme of every shipped example
	package, at the default text preference and at two raised ones (the preference
	is what grows the glyph past the badge minimum and changes which term decides
	the plate's size on each axis):

	  1. The seal really does mount a glyph of its own, and the glyph really is
	     smaller than the plate — otherwise "centred" is vacuous.
	  2. Both centre deltas are within a pixel, measured rect against rect.
	  3. The skinned half already agreed (`chrome_slots.CENTRED_LIFT_SLOTS`), which
	     is the rule the unskinned half is now keeping too.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local chrome_slots = require("../src/tokens/chrome_slots")

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

-- the player's text preference, which is what decides whether the badge MINIMUM
-- or the glyph's own line box sizes the plate — a different arithmetic on each
-- axis, and therefore a different way to be off-centre
local OFFSETS = { 0, 4, 14 }

local BADGE_TEXT = "3"

type Rect = { x: number, y: number, w: number, h: number }

-- the plate and the glyph inside it, as the LAYOUT solved them. Nothing here is
-- derived: both rects are read off the target.
local function sealOf(metrics: any?, offset: number): (Rect, Rect)
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = 900, h = 720 },
		safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		themeMetrics = metrics,
		env = { preferredTextOffset = offset },
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
	local platePath: string? = nil
	for _, path in w.adapter.paths() do
		if string.sub(path, -#"/Badge") == "/Badge" then
			platePath = path
		end
	end
	assert(platePath ~= nil, "the badged option mounted no seal")
	local plate = w.adapter.node(platePath :: string)
	local glyph = w.adapter.node((platePath :: string) .. "/Count")
	assert(glyph ~= nil, `the seal at {platePath} mounts no glyph node — nothing to measure it against`)
	return plate.rect, glyph.rect
end

local function deltas(plate: Rect, glyph: Rect): (number, number)
	return (glyph.x + glyph.w / 2) - (plate.x + plate.w / 2), (glyph.y + glyph.h / 2) - (plate.y + plate.h / 2)
end

describe("badge centering: the seal is bigger than the glyph, on purpose", function()
	it("the plate takes the theme's badge minimum, so there is slack to be off-centre in", function()
		local plate, glyph = sealOf(nil, 0)
		expect(`plate {plate.w}x{plate.h} glyph {glyph.w}x{glyph.h}`).toBe("plate 20x20 glyph 8x15")
		expect(plate.w > glyph.w and plate.h > glyph.h).toBe(true)
	end)

	it("the skinned half already centres, which is the rule the unskinned half has to match", function()
		expect(chrome_slots.centresLiftedText("badge")).toBe(true)
		-- ...and it is specific to the badge, not a blanket lift rule
		expect(chrome_slots.centresLiftedText("control")).toBe(false)
	end)
end)

describe("badge centering: the glyph is concentric with its plate, measured", function()
	it("Facet Neutral, at the default preference and at two raised ones", function()
		for _, offset in OFFSETS do
			local plate, glyph = sealOf(nil, offset)
			local dx, dy = deltas(plate, glyph)
			assert(
				math.abs(dx) <= 1 and math.abs(dy) <= 1,
				`Facet Neutral +{offset}: the glyph is off-centre by {dx}, {dy} in a {plate.w}x{plate.h} seal`
			)
		end
	end)

	it("...and every theme of every shipped example package", function()
		local checked = 0
		for _, entry in PACKAGES do
			local package, report = entry.module.build(Facet.themes)
			assert(package ~= nil, `{entry.name} failed its own package gate: {report and report.errors[1]}`)
			for _, theme in package.style.themes do
				local metrics = Facet.themes.resolve(package, theme.name, {})
				for _, offset in OFFSETS do
					local plate, glyph = sealOf(metrics, offset)
					local dx, dy = deltas(plate, glyph)
					checked += 1
					assert(
						math.abs(dx) <= 1 and math.abs(dy) <= 1,
						`{entry.name}/{theme.name} +{offset}: the glyph is off-centre by {dx}, {dy} `
							.. `in a {plate.w}x{plate.h} seal`
					)
				end
			end
		end
		expect(checked > 24).toBe(true)
	end)
end)
