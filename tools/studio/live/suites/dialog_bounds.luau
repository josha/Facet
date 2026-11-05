--!strict
type FacetModule = typeof(require("@repo/src"))
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ThemePackage = typeof(require("@repo/tools/typecheck/aliases").ReadOnlyThemePackage)
type NavigationPath = { { id: string, value: unknown? } }
type Live = {
	Facet: FacetModule,
	mount: (
		(FacetControls, RobloxHost) -> Frame,
		{ size: Vector2, theme: ThemePackage, environment: { viewingDistance: string }, frames: number }
	) -> Frame,
	settle: (number?) -> (),
	check: (string, boolean, unknown?) -> (),
	near: (string, number, number, number?) -> (),
	stable: (GuiObject, number?, number?) -> number,
	cleanup: () -> (),
}

return {
	{
		id = "canonical-navigable-dialog-keeps-insets-and-logical-density",
		contracts = { "Dialog.bodyHeight", "Dialog.presentation", "themes.forResolution" },
		run = function(t: Live)
			local Facet = t.Facet
			local Design = (
				require :: (ModuleScript) -> typeof(require("@repo/examples/blocks/navigable_dialog_design"))
			)(game:GetService("ReplicatedStorage"):WaitForChild("FacetDialogDesign") :: ModuleScript)
			local base = Facet.themes.neutralPackage()
			for _, device in
				{
					{ width = 390, height = 844, distance = "near" },
					{ width = 844, height = 390, distance = "near" },
					{ width = 1024, height = 768, distance = "near" },
					{ width = 1920, height = 1080, distance = "near" },
					{ width = 3840, height = 2160, distance = "near" },
					{ width = 1920, height = 1080, distance = "ten-foot" },
				}
			do
				local label = `{device.width}x{device.height} {device.distance}`
				local open = Facet.Compose.cell(true)
				local path = Facet.Compose.cell<<NavigationPath>>({})
				local package = Facet.themes.forResolution(base, device.width, device.height)
				local stage = t.mount(function(UI, Host)
					return Host.Frame {
						Size = UDim2.fromScale(1, 1),
						Design(UI, {
							open = open,
							path = path,
							music = Facet.Compose.cell(true),
							volume = Facet.Compose.cell(50),
							onPresentedChange = function(value: boolean)
								open:set(value)
							end,
							onDetails = function()
								path:set({ { id = "details" } })
							end,
						}),
					}
				end, {
					size = Vector2.new(device.width, device.height),
					theme = package,
					environment = { viewingDistance = device.distance },
					frames = 45,
				})
				local panel = stage:FindFirstChild("Panel", true)
				local body = stage:FindFirstChild("Body", true)
				local stack = stage:FindFirstChild("PreferencesNavigation", true)
				local form = stage:FindFirstChild("PreferencesForm", true)
				assert(panel and panel:IsA("GuiObject") and body and body:IsA("GuiObject"))
				assert(stack and stack:IsA("GuiObject") and form and form:IsA("ScrollingFrame"))
				t.stable(panel)
				local at = panel.AbsolutePosition - stage.AbsolutePosition
				local ending = at + panel.AbsoluteSize
				t.check(
					label .. " leaves an inset on every edge",
					at.X > 0 and at.Y > 0 and ending.X < device.width and ending.Y < device.height,
					{ at, panel.AbsoluteSize }
				)
				t.check(
					label .. " has a finite useful body",
					body.AbsoluteSize.Y > 44 and body.AbsoluteSize.Y < device.height,
					body.AbsoluteSize
				)
				t.near(label .. " navigation fills the offered body", stack.AbsoluteSize.Y, body.AbsoluteSize.Y, 1)
				t.near(label .. " form fills the navigation root", form.AbsoluteSize.Y, stack.AbsoluteSize.Y, 1)
				local scale = Facet.adaptive.resolutionScale(device.width, device.height)
					* (if device.distance == "ten-foot" then Facet.adaptive.TEN_FOOT_SCALE else 1)
				if device.height >= 768 then
					t.near(label .. " keeps the authored logical body height", body.AbsoluteSize.Y, 420 * scale, 1)
				end
				if device.width == 844 then
					t.check(
						label .. " scrolls overflow inside the form",
						form.AbsoluteCanvasSize.Y > form.AbsoluteWindowSize.Y,
						{ form.AbsoluteCanvasSize, form.AbsoluteWindowSize }
					)
					form.CanvasPosition = Vector2.new(0, 10000)
					t.settle(6)
					t.check(label .. " reaches the bottom of the form", form.CanvasPosition.Y > 0, form.CanvasPosition)
				end
				path:set({ { id = "details" } })
				t.settle(30)
				local back = stage:FindFirstChild("Back", true)
				t.check(label .. " exposes native navigation Back", back ~= nil)
				t.near(label .. " keeps panel height during navigation", panel.AbsoluteSize.Y, ending.Y - at.Y, 1)
				path:set({})
				t.settle(30)
				t.check(label .. " root has no Back", stage:FindFirstChild("Back", true) == nil)
				open:set(false)
				t.settle(30)
				t.check(label .. " dismisses the modal", stage:FindFirstChild("DialogModal", true) == nil)
				t.cleanup()
			end
		end,
	},
}
