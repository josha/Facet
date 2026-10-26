--!strict
local CatalogTypes = require("./catalog_types")
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)

local function make(UI: Controls, _p: CatalogTypes.Properties, c: CatalogTypes.Context): Instance
	return require("./reward_sequence_demo")(UI, c.Host, c.Compose, true)
end

local countUp: CatalogTypes.PageDefinition = {
	family = "media",
	purpose = "Show a changing total.",
	alternatives = "Use Text for a fixed number.",
	snippet = "local number = UI.countUp(total)",
	axes = {},
	states = {},
	make = make,
}

local follow: CatalogTypes.PageDefinition = {
	family = "media",
	purpose = "Move a bar or color toward a changing value with a theme spring.",
	alternatives = "Use countUp for a number that a player reads.",
	snippet = 'value = UI.follow(charge, "move")',
	axes = {},
	states = {},
	make = make,
}

local toward: CatalogTypes.PageDefinition = {
	family = "media",
	purpose = "Fill a meter during one step of a sequence.",
	alternatives = "Use a sample function for a custom curve.",
	snippet = '{ duration = "glide", sample = UI.toward(charge, 1) }',
	axes = {},
	states = {},
	make = make,
}

return { countUp = countUp, follow = follow, toward = toward }
