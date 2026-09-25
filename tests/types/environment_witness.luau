--!strict
local Facet = require("../../src")
local app: Facet.App = Facet.app()
local UI = app.UI
local function Screen(): Frame
	local env: Facet.Environment = UI.environment()
	local anchor: Facet.WorldAnchor = UI.worldAnchor({ target = workspace })
	local options: Facet.ScrollOptions = { animated = false }
	local list = Instance.new("ScrollingFrame")
	local moved: boolean = UI.scrollTo(list, "top", options)
	local shown: boolean = UI.scrollToVisible(list, nil, options)
	return UI.Screen({
		UI.Text({
			text = function(use: Facet.Use): string
				return `{use(env.sizeClass)} {moved} {shown} {use(anchor.anchor) ~= nil}`
			end,
		}),
	})
end
app.mount(Screen)
return nil
