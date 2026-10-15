--!strict

local Kit = require(script.Parent.Kit)
local function button(parent: Instance, text: string, action: () -> ()): TextButton
	local control = Kit.button(text)
	control.Parent = parent
	control.Activated:Connect(function()
		action()
	end)
	return control
end
local function label(parent: Instance, text: string): TextLabel
	local control = Kit.label(text)
	control.Parent = parent
	return control
end
local function panel(playerGui: PlayerGui, title: string): (Kit.Modal, ScrollingFrame, TextButton)
	local screen = Kit.screen(playerGui, title)
	local modal = Kit.modal(screen, title, title)
	local scroll = Kit.scroller()
	scroll.Parent = modal.body
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = scroll
	local opener = button(Kit.hud(screen), title, function()
		modal.setOpen(true)
	end)
	return modal, scroll, opener
end
return { button = button, label = label, panel = panel }
