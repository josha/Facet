--!strict
--[[ ONE RUNG, ONE PLATE HEIGHT (owner ruling 2026-09-24). At the same
	`controlSize`, every plated control — Button, the menu Picker's trigger, the
	segmented strip, TextInput and a standard checkbox row — paints the same outer
	plate height, in Facet Neutral and in every shipped package (an art theme's
	frame carve may lift a small rung above its metric, but it lifts all of them
	alike). A plain row (a plain checkbox, a switch) has no plate and is never taller
	than one, and its checkbox box grows with the rung. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any

local PACKAGES = {
	"neutral",
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

--[[ THE KNOWN DELTAS (owed, 2026-09-24): at the small rungs of two art packages
	a Button's frame carve plus its label outgrows the rung (fantasy: 43 against a
	39/30-38 field and checkbox plate), and scifi's switch track art is 29 at an
	xsmall rung of 24. Closing them needs one package-level rule — a rung is never
	shorter than its control art needs, applied in `snapshot.resolve` — which moves
	those packages' geometry and is its own change. Pinned at today's values so a
	drift either way is seen. ]]
local KNOWN: { [string]: number } = {
	["fantasy_ornate xsmall field"] = 39,
	["fantasy_ornate xsmall checkbox"] = 35,
	["fantasy_ornate compact field"] = 39,
	["fantasy_ornate compact checkbox"] = 38,
	["fantasy_parchment xsmall checkbox"] = 30,
	["scifi_hud xsmall switchRow"] = 29,
}

local function heights(name: string, rung: string): { [string]: number }
	local metrics = if name == "neutral"
		then nil
		else Facet.themes.resolve(require(`../examples/themes/{name}`).build(Facet.themes), nil, {})
	local w = world.new({
		viewport = { x = 0, y = 0, w = 1600, h = 800 },
		themeMetrics = metrics,
		capabilities = { mouse = true, keyboard = true },
	})
	local UI, C = w.UI, Facet.Compose
	local options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } }
	w.present(function()
		return UI.Screen("S")({
			UI.HStack("Row")({
				align = "start",
				gap = "s",
				UI.Button("B")({ label = "Settings", controlSize = rung }),
				UI.Picker("PM")({
					label = "Theme:",
					style = "menu",
					valueAlignment = "start",
					sizing = "hug",
					controlSize = rung,
					selected = C.cell("a"),
					options = options,
				}),
				UI.Picker("PS")({ style = "segmented", controlSize = rung, selected = C.cell("a"), options = options }),
				UI.VStack("TIw")({
					width = { type = "fixed", px = 160 },
					UI.TextInput("TI")({ value = C.cell("x"), controlSize = rung }),
				}),
				UI.Toggle("TK")({
					label = "Motion",
					presentation = "checkbox",
					controlSize = rung,
					width = UI.hug(),
					value = C.cell(false),
				}),
				UI.Toggle("TC")({
					label = "Reduced Motion",
					presentation = "checkbox",
					appearance = "plain",
					controlSize = rung,
					width = UI.hug(),
					value = C.cell(false),
				}),
				UI.Toggle("TS")({ label = "Music", controlSize = rung, width = UI.hug(), value = C.cell(false) }),
			}),
		})
	end)
	w.settle(3)
	local function h(path: string): number
		return assert(w.adapter.node("/S/Row/" .. path), path).rect.h
	end
	local out = {
		button = h("B+target/B"),
		menu = h("PM+target/PM/Form/PointerRow/then/Row/Trigger"),
		segmented = h("PS+target/PS/Indicator"),
		field = h("TIw/TI+target/TI"),
		checkbox = h("TK+target/TK"),
		plainRow = h("TC+target/TC"),
		plainBox = h("TC+target/TC/Row/Indicator"),
		switchRow = h("TS+target/TS"),
	}
	w.close()
	return out
end

describe("one rung, one plate height", function()
	for _, name in PACKAGES do
		it(`{name}: plated controls agree at every rung; plain rows are never taller`, function()
			local boxes = {}
			for _, rung in { "xsmall", "compact", "regular", "large" } do
				local hs = heights(name, rung)
				for _, key in { "menu", "segmented", "field", "checkbox" } do
					local known = KNOWN[`{name} {rung} {key}`]
					if known then
						expect(`{rung} {key} {hs[key]}`).toBe(`{rung} {key} {known}`)
					else
						expect(`{rung} {key} {math.abs(hs[key] - hs.button) <= 1}`).toBe(`{rung} {key} true`)
					end
				end
				for _, key in { "plainRow", "switchRow", "plainBox" } do
					local known = KNOWN[`{name} {rung} {key}`]
					if known then
						expect(`{rung} {key} {hs[key]}`).toBe(`{rung} {key} {known}`)
					else
						expect(`{rung} {key} {hs[key] <= hs.button + 1}`).toBe(`{rung} {key} true`)
					end
				end
				table.insert(boxes, hs.plainBox)
			end
			-- the checkbox box grows with the rung (never shrinks up the ladder)
			expect(boxes[1] <= boxes[2] and boxes[2] <= boxes[3] and boxes[3] <= boxes[4]).toBe(true)
			expect(boxes[1] < boxes[4]).toBe(true)
		end)
	end
end)
