--!strict

local overlay = {}

function overlay.bind(
	Facet: any,
	runtime: any,
	UI: any,
	Host: any,
	parent: Instance,
	panels: any,
	model: any,
	options: any
): any
	local Compose = Facet.Compose
	local types = options.types or { Vector2 = Vector2, UDim2 = UDim2, Enum = Enum }
	local gui = options.guiService or game:GetService("GuiService")
	local inset = Compose.cell({ near = types.Vector2.zero, far = types.Vector2.zero })
	local function measure()
		local screen = if parent:IsA("ScreenGui") then parent else parent:FindFirstAncestorWhichIsA("ScreenGui")
		local near, far = types.Vector2.zero, types.Vector2.zero
		if screen and not screen.IgnoreGuiInset and screen.ScreenInsets == types.Enum.ScreenInsets.CoreUISafeInsets then
			near, far = gui:GetGuiInset()
		end
		inset:set({ near = near, far = far })
	end
	local changed = gui:GetPropertyChangedSignal("TopbarInset"):Connect(measure)
	Compose.cleanup(function()
		changed:Disconnect()
	end)
	measure()
	local scrim = Host.Frame "ModalScrim" {
		Position = function(use)
			local value: any = use(inset)
			return types.UDim2.fromOffset(-value.near.X, -value.near.Y)
		end,
		Size = function(use)
			local value: any = use(inset)
			return types.UDim2.new(1, value.near.X + value.far.X, 1, value.near.Y + value.far.Y)
		end,
		BackgroundColor3 = (options.types or { Color3 = Color3 }).Color3.fromRGB(24, 34, 54),
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 3900,
		Visible = function(use)
			local state = use(model)
			return state.menuTitle ~= "" or state.dataTitle ~= "" or state.transferTitle ~= ""
		end,
	}
	local focus = Compose.keyed({
		from = function(use)
			local state = use(model)
			local panel = if state.transferTitle ~= ""
				then panels.transfer
				elseif state.galleryTitle ~= "" then panels.gallery
				elseif state.dataTitle ~= "" then panels.data
				elseif state.menuTitle ~= "" then panels.menu
				else nil
			return if panel then { panel } else {}
		end,
		key = function(panel)
			return panel.Name
		end,
		render = function(current)
			local panel = current:peek()
			UI.focusSection(panel, { focusOnAppear = true, returnFocus = true })
			return Host.Folder "EditorFocus" {}
		end,
	})
	return { scrim = scrim, focus = focus }
end

return overlay
