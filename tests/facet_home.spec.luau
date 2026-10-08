--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local fs, serde = require("@lune/fs"), require("@lune/serde")
	local source = require("../tools/designer/modules/source")

	verifyHarness:suite("Facet Home dock geometry", function()
		verifyHarness:case("contains its controls and stays above the viewport edge", {
			id = "facet_home::Facet Home dock geometry::contains its controls and stays above the viewport edge",
			run = function()
				local Facet = require("../src")
				local engine = require("./lib/native_engine").new()
				local runtime = Facet.Roblox.createRuntime(engine)
				local UI = Facet.controls(runtime, { types = engine.types })
				local dock = require("../examples/facet_home/dock")
				local stop, panel: any = runtime.mount(function()
					return dock(runtime, engine.types.UDim2, {
						UI.Button({ label = "Open Home", Size = engine.types.UDim2.fromOffset(118, 44) }),
						UI.Text({
							text = "Status",
							Size = engine.types.UDim2.fromOffset(180, 48),
							AutomaticSize = engine.types.Enum.AutomaticSize.None,
						}),
					})
				end, engine.new("ScreenGui"))
				local padding = Facet.themes.neutralPackage().metrics.space.m
				for _, child in panel:GetChildren() do
					if child:IsA("GuiObject") then
						Verify.expect(padding + child.Size.Y.Offset + padding <= panel.Size.Y.Offset):toBe(true)
					end
				end
				for _, height in { 390, 759, 844 } do
					local top = height * panel.Position.Y.Scale + panel.Position.Y.Offset
					Verify.expect(top >= 0 and top + panel.Size.Y.Offset <= height):toBe(true)
				end
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("Facet Home visual source", function()
		for _, name in { "Home", "Furnish", "Activities", "People", "Settings", "Wall" } do
		end
	end)
end
