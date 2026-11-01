--!strict
type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Live = {
	Facet: FacetModule,
	settle: (number) -> (),
	check: (string, boolean, unknown?) -> (),
	device: ({ device: string, input: Enum.PreferredInput?, orientation: Enum.ScreenOrientation? }) -> (),
}

return {
	{
		id = "imperative-toasts-use-their-edge-stack",
		contracts = {},
		run = function(t: Live)
			local gui = game:GetService("GuiService")
			local devices: { { device: string, input: Enum.PreferredInput?, orientation: Enum.ScreenOrientation? } } = {
				{ device = "hd_1080", input = Enum.PreferredInput.KeyboardAndMouse },
				{
					device = "iphone_14",
					input = Enum.PreferredInput.Touch,
					orientation = Enum.ScreenOrientation.Portrait,
				},
				{
					device = "iphone_14",
					input = Enum.PreferredInput.Touch,
					orientation = Enum.ScreenOrientation.LandscapeLeft,
				},
				{ device = "hd_1080", input = Enum.PreferredInput.Gamepad },
			}
			for _, device in devices do
				t.device(device)
				local app = t.Facet.app({ name = "ToastPlacement", motionLevel = "normal" })
				local button: GuiButton? = nil
				app.mount(function()
					button = app.UI.Button "Continue" { label = "Continue", Position = UDim2.fromScale(0.5, 0.5) }
					return assert(button)
				end)
				t.settle(30)
				gui.SelectedObject = button
				t.settle(4)
				local selected = gui.SelectedObject
				local live = 0
				for _, edge in { "top", "bottom" } :: { "top" | "bottom" } do
					for index = 1, 2 do
						app.presentToast(function(UI: Controls): Instance
							live += 1
							t.Facet.Compose.cleanup(function()
								live -= 1
							end)
							return UI.Text(`{edge}{index}`)({ text = `{edge} result {index}`, AutoLocalize = false })
						end, { position = edge :: "top" | "bottom", width = "hug", duration = 60 })
					end
				end
				t.settle(60)
				local layer =
					game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("ToastPlacementToasts") :: ScreenGui
				t.check("each body mounts once", live == 4, live)
				t.check("passive toasts preserve focus", gui.SelectedObject == selected)
				for _, edge in { "top", "bottom" } do
					local previous: GuiObject? = nil
					for index = 1, 2 do
						local label = assert(layer:FindFirstChild(`{edge}{index}`, true)) :: TextLabel
						local slot = assert(label:FindFirstAncestor("ToastSlot")) :: GuiObject
						local stack = slot.Parent
						t.check(
							edge .. " slot belongs to its stack",
							stack ~= nil and stack.Name == "ToastStack",
							stack
						)
						local row = assert(label:FindFirstAncestor("ToastRow")) :: GuiObject
						local midpoint = row.AbsolutePosition.Y + row.AbsoluteSize.Y / 2
						local middle = layer.AbsolutePosition.Y + layer.AbsoluteSize.Y / 2
						t.check(
							edge .. " is on the requested edge",
							if edge == "top" then midpoint < middle else midpoint > middle,
							midpoint
						)
						t.check(edge .. " text fits", label.TextFits)
						t.check(
							edge .. " stays inside the screen",
							row.AbsolutePosition.X >= layer.AbsolutePosition.X
								and row.AbsolutePosition.X + row.AbsoluteSize.X
									<= layer.AbsolutePosition.X + layer.AbsoluteSize.X
						)
						if previous then
							t.check(
								edge .. " rows do not overlap",
								row.AbsolutePosition.Y >= previous.AbsolutePosition.Y + previous.AbsoluteSize.Y
									or previous.AbsolutePosition.Y >= row.AbsolutePosition.Y + row.AbsoluteSize.Y,
								{ previous.AbsolutePosition, row.AbsolutePosition }
							)
						end
						previous = row
					end
				end
				app.dispose()
				t.settle(4)
				t.check("all bodies are released", live == 0, live)
				t.check("toast layer is released", layer.Parent == nil)
			end
		end,
	},
}
