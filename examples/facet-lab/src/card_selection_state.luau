--!strict
local CatalogTypes = require("./catalog_types")

type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Row = { name: string }

return function(art: string): CatalogTypes.Builder
	return function(c: CatalogTypes.Context): CatalogTypes.Properties
		local initial: { [string]: boolean } = { ["1"] = true }
		local selection = c.cell("cardSelection", initial)
		return {
			columns = 2,
			itemSize = 160,
			selection = selection,
			onSelectionChange = function(keys: { [string]: boolean })
				selection:set(keys)
				c.log("onSelectionChange")()
			end,
			render = function(current: Readable<Row>): GuiObject
				return c.UI.Card({
					image = art,
					imageAspectRatio = 2,
					title = function(use: Use): string
						return use(current).name
					end,
				})
			end,
		}
	end
end
