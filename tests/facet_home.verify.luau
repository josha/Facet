--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local fs = require("@std/fs")

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
					return dock(Facet.host(runtime), engine.types.UDim2, {
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
		verifyHarness:case("mounts every authored page at the smoke viewports", {
			id = "facet_home::Facet Home visual source::mounts every authored page at the smoke viewports",
			run = function()
				local Facet = require("../src")
				local engines = require("./lib/native_engine")
				local Design = Facet.design().Design
				for _, name in { "Home", "Furnish", "Activities", "People", "Settings", "Wall" } do
					local code = fs.readFileToString(`examples/facet_home/designs/{name}.luau`)
					for _, size in { { 389, 762 }, { 430, 932 }, { 1280, 720 } } do
						local engine = engines.new()
						local runtime = Facet.Roblox.createRuntime(engine)
						local types = engine.types
						local UI = Facet.controls(runtime, {
							types = types,
							motionLevel = "none",
							environment = { viewportSize = types.Vector2.new(size[1], size[2]) },
						})
						local library = Facet.design().library({
							UI = UI,
							rgb = types.Color3.fromRGB,
							udim2 = types.UDim2.new,
							offset = types.UDim2.fromOffset,
						})
						local value = Design.parse(code, library)
						Verify.expect(Design.emit(value, library, { name = name })):toBe(code)
						local root: Instance? = nil
						local stop = runtime.mount(function()
							local built = Design.render(value, library)
							if typeof(built) == "Instance" then
								root = built
							end
							return built
						end, engine.new("ScreenGui"))
						Verify.expect(#assert(root):GetChildren() > 0):toBe(true)
						stop()
						runtime:dispose()
					end
				end
			end,
		})
	end)
end
