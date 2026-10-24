--!strict
local CatalogTypes = require("./catalog_types")

return function(c: CatalogTypes.Context): CatalogTypes.Properties
	local function ring(): GuiObject
		return c.UI.Path "NativeGlyph" {
			points = c.Facet.pathShapes.ring({ radius = 0.75 }),
			thickness = 2,
			closed = true,
		}
	end
	return { glyph = ring }
end
