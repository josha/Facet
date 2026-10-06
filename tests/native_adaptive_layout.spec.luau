--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

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

	local function refusal(body: (any, any) -> any): string
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types } :: any)
		local ok, message = pcall(function()
			runtime.mount(function()
				return body(UI, runtime.constructors)
			end, engine.new("ScreenGui"))
		end)
		runtime:dispose()
		return if ok then "" else tostring(message)
	end

	local function list(root: any): any
		return root:FindFirstChildWhichIsA("UIListLayout")
	end

	local function sized(engine: any, node: any, width: number, height: number)
		node.AbsoluteSize = engine.types.Vector2.new(width, height)
	end

	verifyHarness:suite("adaptive layout", function()
		verifyHarness:suite("AdaptiveStack with a bound axis", function()
			verifyHarness:case("flips the list direction in place and keeps every child", {
				id = "native_adaptive_layout::AdaptiveStack with a bound axis::flips the list direction in place and keeps every child",
				run = function()
					local axis = Compose.cell("x" :: "x" | "y")
					local root, engine, stop = build(function(UI: FacetControls, Host: RobloxHost)
						return UI.AdaptiveStack {
							axis = axis,
							gap = 8,
							Host.Frame { Name = "A" } :: unknown,
							Host.Frame { Name = "B" },
						}
					end)
					local E = engine.types.Enum
					local layout, a = list(root), root:FindFirstChild("A")
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Horizontal)
					axis:set("y")
					Verify.expect((list(root))):toBe(layout)
					Verify.expect((root:FindFirstChild("A"))):toBe(a)
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
					Verify.expect(layout.Padding):toBe(engine.types.UDim.new(0, 8))
					stop()
				end,
			})

			verifyHarness:case("moves align to the cross axis and distribute to the main axis when it flips", {
				id = "native_adaptive_layout::AdaptiveStack with a bound axis::moves align to the cross axis and distribute to the main axis when it flips",
				run = function()
					local axis = Compose.cell("x" :: "x" | "y")
					local root, engine, stop = build(function(UI: FacetControls)
						return UI.AdaptiveStack { axis = axis, align = "center" :: "center", distribute = "end" :: "end" }
					end)
					local E = engine.types.Enum
					local layout = list(root)
					Verify.expect(layout.VerticalAlignment):toBe(E.VerticalAlignment.Center)
					Verify.expect(layout.HorizontalAlignment):toBe(E.HorizontalAlignment.Right)
					axis:set("y")
					Verify.expect(layout.HorizontalAlignment):toBe(E.HorizontalAlignment.Center)
					Verify.expect(layout.VerticalAlignment):toBe(E.VerticalAlignment.Bottom)
					stop()
				end,
			})

			verifyHarness:case("refuses an axis other than x or y", {
				id = "native_adaptive_layout::AdaptiveStack with a bound axis::refuses an axis other than x or y",
				run = function()
					Verify.expect((string.find(
						refusal(function(UI: FacetControls)
							return UI.AdaptiveStack { axis = "xy" :: any }
						end),
						"AdaptiveStack axis must be x or y",
						1,
						true
					))).never
						:toBeNil()
				end,
			})
		end)

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

		verifyHarness:suite("ViewThatFits", function()
			local function actions(): (any, any, () -> ())
				return build(function(UI: FacetControls, Host: RobloxHost)
					return UI.ViewThatFits {
						Host.Frame { Name = "Row" } :: unknown,
						Host.Frame { Name = "Column" },
					}
				end)
			end

			verifyHarness:case("shows the first candidate whose width fits and hides the others", {
				id = "native_adaptive_layout::ViewThatFits::shows the first candidate whose width fits and hides the others",
				run = function()
					local root, engine, stop = actions()
					local row, column = root:FindFirstChild("Row"), root:FindFirstChild("Column")
					sized(engine, row, 300, 40)
					sized(engine, column, 120, 100)
					sized(engine, root, 320, 0)
					Verify.expect(row.Visible):toBe(true)
					Verify.expect(column.Visible):toBe(false)
					sized(engine, root, 200, 0)
					Verify.expect(row.Visible):toBe(false)
					Verify.expect(column.Visible):toBe(true)
					Verify.expect((root:FindFirstChild("Row"))):toBe(row)
					stop()
				end,
			})

			verifyHarness:case("shows the last candidate when none fits", {
				id = "native_adaptive_layout::ViewThatFits::shows the last candidate when none fits",
				run = function()
					local root, engine, stop = actions()
					sized(engine, root:FindFirstChild("Row"), 300, 40)
					sized(engine, root:FindFirstChild("Column"), 120, 100)
					sized(engine, root, 80, 0)
					Verify.expect(root:FindFirstChild("Row").Visible):toBe(false)
					Verify.expect(root:FindFirstChild("Column").Visible):toBe(true)
					stop()
				end,
			})

			verifyHarness:case("fills the width, hugs the height and ignores height while it hugs", {
				id = "native_adaptive_layout::ViewThatFits::fills the width, hugs the height and ignores height while it hugs",
				run = function()
					local root, engine, stop = actions()
					Verify.expect(root.Size):toBe(engine.types.UDim2.fromScale(1, 0))
					Verify.expect(root.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
					Verify.expect(list(root).FillDirection):toBe(engine.types.Enum.FillDirection.Vertical)
					sized(engine, root:FindFirstChild("Row"), 300, 400)
					sized(engine, root, 320, 40)
					Verify.expect(root:FindFirstChild("Row").Visible):toBe(true)
					stop()
				end,
			})

			verifyHarness:case("tests the height too when the height is bounded", {
				id = "native_adaptive_layout::ViewThatFits::tests the height too when the height is bounded",
				run = function()
					local root, engine, stop = build(function(UI: FacetControls, Host: RobloxHost)
						return UI.ViewThatFits {
							height = "fill" :: "fill",
							Host.Frame { Name = "Tall" } :: unknown,
							Host.Frame { Name = "Short" },
						}
					end)
					sized(engine, root:FindFirstChild("Tall"), 100, 300)
					sized(engine, root:FindFirstChild("Short"), 100, 50)
					sized(engine, root, 320, 200)
					Verify.expect(root:FindFirstChild("Tall").Visible):toBe(false)
					Verify.expect(root:FindFirstChild("Short").Visible):toBe(true)
					stop()
				end,
			})

			verifyHarness:case("picks the first candidate along a horizontal scroll axis", {
				id = "native_adaptive_layout::ViewThatFits::picks the first candidate along a horizontal scroll axis",
				run = function()
					local root, engine, stop = build(function(UI: FacetControls, Host: RobloxHost)
						return UI.ScrollView {
							axis = "x" :: "x",
							UI.ViewThatFits "Fits" {
								Host.Frame { Name = "Wide" } :: unknown,
								Host.Frame { Name = "Narrow" },
							},
						}
					end)
					local fits = root:FindFirstChild("Fits")
					sized(engine, fits:FindFirstChild("Wide"), 900, 40)
					sized(engine, fits, 300, 40)
					Verify.expect(fits:FindFirstChild("Wide").Visible):toBe(true)
					Verify.expect(fits:FindFirstChild("Narrow").Visible):toBe(false)
					stop()
				end,
			})

			verifyHarness:case("refuses a ViewThatFits without candidates", {
				id = "native_adaptive_layout::ViewThatFits::refuses a ViewThatFits without candidates",
				run = function()
					Verify.expect((string.find(
						refusal(function(UI: FacetControls)
							return UI.ViewThatFits {}
						end),
						"ViewThatFits needs at least one candidate",
						1,
						true
					))).never
						:toBeNil()
				end,
			})
		end)
	end)
end
