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
	local player = assert(game:GetService("Players").LocalPlayer)
	local playerGui = player:WaitForChild("PlayerGui")
	assert(playerGui:IsA("PlayerGui"))
	local ring: Frame = UI.focusRing(playerGui)
	UI.focusSection(list)
	local responder = UI.responder(list, { passive = true, gameplayGuard = false, traversalWrap = false })
	responder.engage()
	local drag: Facet.DraggableSpec = { payload = "card", armOnTap = true, statusLabels = false }
	UI.draggable(list, drag)
	local drop: Facet.DropTargetSpec = {
		onDrop = function(payload: unknown, info: Facet.DropInfo)
			print(payload, info.mode)
		end,
	}
	UI.dropTarget(list, drop)
	local dial: Facet.AdjustableOptions = {
		onAdjust = function(direction: number)
			print(direction)
		end,
		axis = "vertical",
		repeats = true,
	}
	UI.adjustable(list, dial)
	local kind: Facet.HapticKind = "success"
	UI.feedback(kind)
	return UI.Screen("Environment")({
		ring,
		UI.Text({
			text = function(use: Facet.Use): string
				return `{use(env.sizeClass)} {moved} {shown} {use(anchor.anchor) ~= nil} {use(responder.state)}`
			end,
		}),
	})
end
app.mount(Screen)
return nil
