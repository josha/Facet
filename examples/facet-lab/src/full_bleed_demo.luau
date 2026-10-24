--!strict
local CatalogTypes = require("./catalog_types")

return function(c: CatalogTypes.Context): Instance
	local UI = c.UI
	local stop: (() -> ())? = nil
	local function close()
		local release = stop
		stop = nil
		if release then
			release()
		end
	end
	c.Compose.cleanup(close)
	return UI.Button "OpenFullBleed" {
		label = "Open a full-bleed garage page",
		onActivate = function()
			close()
			local release, screen = c.app.mount(function()
				return UI.Screen "FullBleed" {
					surface = "surface",
					Active = true,
					UI.NavBar {
						title = "Garage",
						trailing = UI.Button { label = "Close", appearance = "utility", onActivate = close },
					},
					UI.Text {
						text = "The plate reaches the glass. Text and Close stay in the safe area.",
						wrap = true,
					},
				}
			end)
			screen.DisplayOrder = 1000
			stop = release
		end,
	}
end
