--!strict
local CatalogTypes = require("./catalog_types")

return function(c: CatalogTypes.Context): CatalogTypes.Properties
	local fill = c.cell("fillBody", false)
	local detents: { CatalogTypes.SheetDetent } = { "hug", { id = "window", fraction = 0.9 } }
	return {
		placement = "center",
		detents = detents,
		detent = function(use: CatalogTypes.Use)
			return if use(fill) then "window" else "hug"
		end,
		content = function()
			local toggle: CatalogTypes.ToggleCellProps = { label = "Fill available height", value = fill }
			local body: CatalogTypes.StackProps = {
				width = "fill",
				height = function(use: CatalogTypes.Use)
					return if use(fill) then "fill" else "hug"
				end,
				gap = "s",
				c.UI.Toggle(toggle),
				c.UI.TextInput { value = c.cell("draft", ""), placeholder = "Draft" },
				c.UI.Button {
					label = "Done",
					onActivate = function()
						c.cell("open", false):set(false)
					end,
				},
			}
			return c.UI.VStack(body)
		end,
	}
end
