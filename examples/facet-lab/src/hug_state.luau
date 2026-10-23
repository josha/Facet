--!strict
local CatalogTypes = require("./catalog_types")

return function(rows: { unknown }, none: unknown): CatalogTypes.Builder
	return function(c: CatalogTypes.Context): CatalogTypes.Properties
		return {
			from = c.cell("three", { rows[1], rows[2], rows[3] }),
			mode = "all",
			hug = true,
			columns = none,
			minColumnWidth = 120,
			Size = none,
		}
	end
end
