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
	local ring: Frame = UI.focusRing(game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui)
	UI.focusSection(list)
	local responder = UI.responder(list, { passive = true, gameplayGuard = false, traversalWrap = false })
	responder.engage()
	local drag: Facet.DraggableSpec = { payload = "card", armOnTap = true }
	UI.draggable(list, drag)
	local drop: Facet.DropTargetSpec = {
		onDrop = function(payload: any, info: Facet.DropInfo)
			print(payload, info.mode)
		end,
	}
	UI.dropTarget(list, drop)
	return UI.Screen({
		ring :: any,
		UI.Text({
			text = function(use: Facet.Use): string
				return `{use(env.sizeClass)} {moved} {shown} {use(anchor.anchor) ~= nil} {use(responder.state)}`
			end,
		}),
	})
end
app.mount(Screen)
return nil
