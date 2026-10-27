--!strict
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)

local CatalogTypes = require("./catalog_types")

return function(handoff: boolean, zoom: boolean?): CatalogTypes.Builder
	return function(c: CatalogTypes.Context): CatalogTypes.Properties
		local UI = c.UI
		local column = c.cell("column", "sidebar")
		local back = c.cell("compactBack", false)
		local props: CatalogTypes.Properties = {
			preferredCompactColumn = column,
			detailLabel = false,
			sidebar = function(): Instance
				return UI.Button {
					label = "Files (opens detail)",
					onActivate = function()
						column:set("detail")
					end,
				}
			end,
		}
		if zoom then
			props.transition = { scale = true }
		end
		if handoff then
			props.compactBack = back
			props.detail = function(): Instance
				local body: StackProps = {
					width = "fill",
					UI.NavBar { title = "Linked files", backLabel = "Files", onBack = back },
				}
				body[#body + 1] = UI.Button { label = "Linked files" }
				return UI.VStack(body)
			end
		end
		return props
	end
end
