--!strict
local CatalogTypes = require("./catalog_types")

return function(c: CatalogTypes.Context): CatalogTypes.Properties
	local visible = c.cell("headerVisible", true)
	local actions: { CatalogTypes.OverlayAction } = {
		{
			id = "Done",
			label = "Done",
			onActivate = function()
				c.cell("open", false):set(false)
			end,
		},
	}
	return {
		placement = "center",
		headerVisible = visible,
		content = function()
			local toggle: CatalogTypes.ToggleCellProps = { label = "Show header", value = visible }
			local body: CatalogTypes.StackProps = {
				width = "fill",
				gap = "s",
				c.UI.Toggle(toggle),
				c.UI.TextInput { value = c.cell("draft", ""), placeholder = "Draft" },
			}
			return c.UI.VStack(body)
		end,
		actions = actions,
	}
end
