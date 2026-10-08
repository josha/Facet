--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")

	local function build(body: (any, any) -> any): (any, any, () -> ())
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local UI =
			Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } } :: any)
		local root: any
		runtime.mount(function()
			root = body(UI, runtime.constructors)
			return root
		end, engine.new("ScreenGui"))
		return root, engine, function()
			runtime:dispose()
		end
	end

	local function list(root: any): any
		return root:FindFirstChildWhichIsA("UIListLayout")
	end

	local function sized(engine: any, node: any, width: number, height: number)
		node.AbsoluteSize = engine.types.Vector2.new(width, height)
	end

	verifyHarness:suite("adaptive layout", function()
		verifyHarness:suite("AdaptiveStack that fits", function()
			local function toolbar(align: ("center" | "end" | "start" | "stretch")?): (any, any, () -> ())
				local root, engine, stop = build(function(UI: FacetControls, Host: RobloxHost)
					return UI.AdaptiveStack {
						gap = 20,
						align = align,
						Host.Frame { Name = "A" } :: unknown,
						Host.Frame { Name = "B" },
						Host.Frame { Name = "C" },
					}
				end)
				for _, name in { "A", "B", "C" } do
					sized(engine, root:FindFirstChild(name), 100, 40)
				end
				return root, engine, stop
			end

			verifyHarness:case("fills the width, stays a row while the row fits and stacks when it does not", {
				id = "native_adaptive_layout::AdaptiveStack that fits::fills the width, stays a row while the row fits and stacks when it does not",
				run = function()
					local root, engine, stop = toolbar()
					local E, V2 = engine.types.Enum, engine.types.Vector2
					local layout = list(root)
					Verify.expect(root.Size):toBe(engine.types.UDim2.fromScale(1, 0))
					sized(engine, root, 400, 40)
					layout.AbsoluteContentSize = V2.new(340, 40)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Horizontal)
					sized(engine, root, 300, 40)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
					layout.AbsoluteContentSize = V2.new(100, 160)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
					sized(engine, root, 340, 160)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Horizontal)
					stop()
				end,
			})

			verifyHarness:case("returns to a row when a child narrows while stacked", {
				id = "native_adaptive_layout::AdaptiveStack that fits::returns to a row when a child narrows while stacked",
				run = function()
					local root, engine, stop = toolbar()
					local E, V2 = engine.types.Enum, engine.types.Vector2
					local layout = list(root)
					sized(engine, root, 300, 40)
					layout.AbsoluteContentSize = V2.new(340, 40)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
					sized(engine, root:FindFirstChild("C"), 60, 40)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Horizontal)
					stop()
				end,
			})

			verifyHarness:case("keeps the row width it measured when stretched children fill the column", {
				id = "native_adaptive_layout::AdaptiveStack that fits::keeps the row width it measured when stretched children fill the column",
				run = function()
					local root, engine, stop = toolbar("stretch")
					local E, V2 = engine.types.Enum, engine.types.Vector2
					local layout = list(root)
					sized(engine, root, 300, 40)
					layout.AbsoluteContentSize = V2.new(340, 40)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
					for _, name in { "A", "B", "C" } do
						sized(engine, root:FindFirstChild(name), 300, 40)
					end
					layout.AbsoluteContentSize = V2.new(300, 160)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
					sized(engine, root, 340, 160)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Horizontal)
					stop()
				end,
			})

			verifyHarness:case("measures the row again when a stretched column loses a child", {
				id = "native_adaptive_layout::AdaptiveStack that fits::measures the row again when a stretched column loses a child",
				run = function()
					local root, engine, stop = toolbar("stretch")
					local E, V2 = engine.types.Enum, engine.types.Vector2
					local layout = list(root)
					sized(engine, root, 300, 40)
					layout.AbsoluteContentSize = V2.new(340, 40)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
					root:FindFirstChild("C").Parent = nil
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Horizontal)
					stop()
				end,
			})

			verifyHarness:case(
				"counts no width for a Divider or a filling child and retries a refused row only after a change",
				{
					id = "native_adaptive_layout::AdaptiveStack that fits::counts no width for a Divider or a filling child and retries a refused row only after a change",
					run = function()
						local root, engine, stop = build(function(UI: FacetControls, Host: RobloxHost)
							return UI.AdaptiveStack {
								gap = 20,
								Host.Frame { Name = "A" } :: unknown,
								UI.Divider "Line" {},
								Host.Frame { Name = "B", UI.fill() },
								Host.Frame { Name = "C" },
							}
						end)
						local E, V2 = engine.types.Enum, engine.types.Vector2
						local layout = list(root)
						for _, name in { "A", "B", "C" } do
							sized(engine, root:FindFirstChild(name), 100, 40)
						end
						sized(engine, root:FindFirstChild("Line"), 1, 40)
						sized(engine, root, 300, 40)
						layout.AbsoluteContentSize = V2.new(400, 40)
						Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
						sized(engine, root:FindFirstChild("Line"), 300, 1)
						layout.AbsoluteContentSize = V2.new(300, 200)
						Verify.expect(layout.FillDirection):toBe(E.FillDirection.Horizontal)
						layout.AbsoluteContentSize = V2.new(330, 40)
						Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
						layout.AbsoluteContentSize = V2.new(300, 200)
						Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
						sized(engine, root, 340, 200)
						Verify.expect(layout.FillDirection):toBe(E.FillDirection.Horizontal)
						stop()
					end,
				}
			)

			verifyHarness:case("measures against the width inside its padding", {
				id = "native_adaptive_layout::AdaptiveStack that fits::measures against the width inside its padding",
				run = function()
					local root, engine, stop = build(function(UI: FacetControls, Host: RobloxHost)
						return UI.AdaptiveStack { padding = 10, Host.Frame { Name = "A" } }
					end)
					local E = engine.types.Enum
					local layout = list(root)
					sized(engine, root:FindFirstChild("A"), 100, 40)
					sized(engine, root, 115, 40)
					layout.AbsoluteContentSize = engine.types.Vector2.new(100, 40)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
					sized(engine, root, 120, 60)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Horizontal)
					stop()
				end,
			})

			verifyHarness:case("stays a row along a horizontal scroll axis, where the width is unbounded", {
				id = "native_adaptive_layout::AdaptiveStack that fits::stays a row along a horizontal scroll axis, where the width is unbounded",
				run = function()
					local root, engine, stop = build(function(UI: FacetControls)
						return UI.ScrollView { axis = "x" :: "x", UI.AdaptiveStack "Row" {} }
					end)
					local row = root:FindFirstChild("Row")
					sized(engine, row, 100, 40)
					list(row).AbsoluteContentSize = engine.types.Vector2.new(500, 40)
					Verify.expect(list(row).FillDirection):toBe(engine.types.Enum.FillDirection.Horizontal)
					stop()
				end,
			})
		end)
	end)
end
