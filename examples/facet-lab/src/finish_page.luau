--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Use = <T>(ReadOnlyValue<T>) -> T

local CatalogTypes = require("./catalog_types")
type Context = CatalogTypes.Context
type Properties = CatalogTypes.Properties

local PLATE = "row"
local DRINKS = {
	{ id = "TaroMilk", name = "Taro Milk", note = "Sweet and purple", price = 40, glyph = "star" },
	{ id = "MangoPop", name = "Mango Pop", note = "Bright and fizzy", price = 55, glyph = "heart" },
	{ id = "MatchaCloud", name = "Matcha Cloud", note = "Calm and creamy", price = 70, glyph = "gift" },
}

local page: CatalogTypes.PageDefinition = {
	facet = true,
	title = "Theme finish",
	surface = "Facet.themes.define (finish)",
	family = "facet",
	cellWidth = 460,
	alias = "Theme finish (look, named plate, control shadow)",
	purpose = "The edge and the depth that the theme gives a panel, a second kind of panel and the controls. "
		.. "Choose a Look theme in Settings to compare flat, raised, glow and hard.",
	note = "The rows take the plate named row when the theme names it. Foundation and Neutral name no plate, "
		.. "so their rows have the panel finish.",
	alternatives = "Art in chrome for a drawn material.",
	snippet = 'finish = { look = "hard", plates = { row = { edge = { width = 2 } } } }; UI.Card { layout = "row", plate = "row" }',
	base = function()
		return {}
	end,
	axes = { { key = "rows", values = { "cards", "stacks" } } },
	states = {},
	make = function(UI: FacetControls, p: Properties, c: Context): Instance
		local theme = if c.ctx then c.ctx.theme else nil
		local named = c.Compose.formula(function(use: Use): string
			local package = if theme then use(theme) else nil
			local chrome = if package then package.chrome else nil
			return if chrome and chrome["plate-" .. PLATE] ~= nil then "named" else "plain"
		end)
		local function row(drink: typeof(DRINKS[1]), plate: string?): Instance
			local buy = c.log("buy " .. drink.name)
			if p.rows == "stacks" then
				return UI.HStack(drink.id) {
					surface = "panel",
					plate = plate,
					padding = "s",
					gap = "m",
					width = "fill",
					align = "center",
					UI.Label { title = drink.name, icon = drink.glyph },
					UI.Spacer {},
					UI.Button { label = "Buy " .. drink.price, appearance = "emphasis", onActivate = buy },
				}
			end
			return UI.Card(drink.id) {
				title = drink.name,
				caption = drink.note,
				glyph = drink.glyph,
				layout = "row",
				reveal = "always",
				plate = plate,
				primaryAction = { label = "Buy " .. drink.price, onActivate = buy },
			}
		end
		local function panel(plate: string?): Instance
			local rows: { Instance } = {}
			for _, drink in DRINKS do
				table.insert(rows, row(drink, plate))
			end
			return UI.VStack "Finish" {
				surface = "panel",
				width = "fill",
				padding = "m",
				gap = "m",
				UI.Text { text = "Boba Stand", textRole = "heading" },
				UI.Text {
					text = if plate
						then "The rows take the plate named " .. plate .. "."
						else "This theme names no plate. The rows have the panel finish.",
					textRole = "caption",
					wrap = true,
				},
				UI.VStack "Rows" { width = "fill", gap = "s", table.unpack(rows) },
				UI.HStack "Actions" {
					gap = "s",
					wrap = true,
					UI.Button { label = "Open", appearance = "emphasis", onActivate = c.log("open") },
					UI.Button { label = "Later", onActivate = c.log("later") },
					UI.Button { label = "Sold out", enabled = false, onActivate = c.log("sold") },
				},
			}
		end
		return UI.VStack "FinishHost" {
			width = "fill",
			c.Compose.switch(named, {
				named = function()
					return panel(PLATE)
				end,
				plain = function()
					return panel(nil)
				end,
			}),
		}
	end,
}

return page
