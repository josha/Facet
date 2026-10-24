--!strict
local CatalogTypes = require("./catalog_types")

type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)

local LABELS = { "All", "Motors", "Boosts", "Wheels", "Cosmetics" }

local function categories(count: number): { PickerOption }
	local options: { PickerOption } = {}
	for index = 1, count do
		local label = LABELS[index]
		table.insert(options, { value = string.lower(label), label = label })
	end
	return options
end

return function(none: unknown): { scrolls: CatalogTypes.Builder, fallback: CatalogTypes.Builder }
	return {
		scrolls = function(c: CatalogTypes.Context): CatalogTypes.Properties
			return {
				label = none,
				style = "segmented",
				selected = c.cell("category", "cosmetics"),
				options = categories(5),
			}
		end,
		fallback = function(c: CatalogTypes.Context): CatalogTypes.Properties
			local selected = c.cell("category", "all")
			return {
				c.UI.Picker({ Name = "Strip", style = "segmented", selected = selected, options = categories(4) }),
				c.UI.Picker({ Name = "Menu", style = "menu", selected = selected, options = categories(4) }),
			}
		end,
	}
end
