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
		verifyHarness:case("mounts every authored page at the smoke viewports", {
			id = "facet_home::Facet Home visual source::mounts every authored page at the smoke viewports",
			run = function()
				local Facet = require("../src")
				local engines = require("./lib/native_engine")
				local session = require("../tools/designer/modules/session")
				local render = require("../tools/designer/modules/design_render")
				for _, name in { "Home", "Furnish", "Activities", "People", "Settings", "Wall" } do
					local value = source.parse(fs.readFile(`examples/facet_home/designs/{name}.luau`), name)
					for _, size in { { 389, 762 }, { 430, 932 }, { 1280, 720 } } do
						local engine = engines.new()
						local mounted = session.mount(Facet, engine.new("ScreenGui"), {
							name = name,
							render = function(ctx)
								return render.build(value, ctx)
							end,
						}, {
							engine = engine,
							types = engine.types,
							config = {
								width = size[1],
								height = size[2],
								input = "Touch",
								display = "Small",
								distance = "near",
								palette = "Dark",
								textSize = "Medium",
								motionLevel = "none",
							},
						})
						Verify.expect(mounted.root.Size.X.Offset):toBe(size[1])
						Verify.expect(mounted.root.Size.Y.Offset):toBe(size[2])
						Verify.expect(#mounted.content:GetChildren() > 0):toBe(true)
						mounted.dispose()
					end
				end
			end,
		})
	end)
end
