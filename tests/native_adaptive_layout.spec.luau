--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

local function build(body: (any, any) -> any): (any, any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
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
	local runtime = Facet.Roblox.createRuntime(engine)
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

t.describe("adaptive layout", function()
	t.describe("AdaptiveStack with a bound axis", function()
		t.it("flips the list direction in place and keeps every child", function()
			local axis = Compose.cell("x")
			local root, engine, stop = build(function(UI, Host)
				return UI.AdaptiveStack { axis = axis, gap = 8, Host.Frame { Name = "A" }, Host.Frame { Name = "B" } }
			end)
			local E = engine.types.Enum
			local layout, a = list(root), root:FindFirstChild("A")
			t.expect(layout.FillDirection).toBe(E.FillDirection.Horizontal)
			axis:set("y")
			t.expect(list(root)).toBe(layout)
			t.expect(root:FindFirstChild("A")).toBe(a)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
			t.expect(layout.Padding).toBe(engine.types.UDim.new(0, 8))
			stop()
		end)

		t.it("moves align to the cross axis and distribute to the main axis when it flips", function()
			local axis = Compose.cell("x")
			local root, engine, stop = build(function(UI)
				return UI.AdaptiveStack { axis = axis, align = "center", distribute = "end" }
			end)
			local E = engine.types.Enum
			local layout = list(root)
			t.expect(layout.VerticalAlignment).toBe(E.VerticalAlignment.Center)
			t.expect(layout.HorizontalAlignment).toBe(E.HorizontalAlignment.Right)
			axis:set("y")
			t.expect(layout.HorizontalAlignment).toBe(E.HorizontalAlignment.Center)
			t.expect(layout.VerticalAlignment).toBe(E.VerticalAlignment.Bottom)
			stop()
		end)

		t.it("refuses an axis other than x or y", function()
			t.expect(string.find(
				refusal(function(UI)
					return UI.AdaptiveStack { axis = "xy" }
				end),
				"AdaptiveStack axis must be x or y",
				1,
				true
			))
				.never()
				.toBeNil()
		end)
	end)

	t.describe("AdaptiveStack that fits", function()
		local function toolbar(align: string?): (any, any, () -> ())
			local root, engine, stop = build(function(UI, Host)
				return UI.AdaptiveStack {
					gap = 20,
					align = align,
					Host.Frame { Name = "A" },
					Host.Frame { Name = "B" },
					Host.Frame { Name = "C" },
				}
			end)
			for _, name in { "A", "B", "C" } do
				sized(engine, root:FindFirstChild(name), 100, 40)
			end
			return root, engine, stop
		end

		t.it("fills the width, stays a row while the row fits and stacks when it does not", function()
			local root, engine, stop = toolbar()
			local E, V2 = engine.types.Enum, engine.types.Vector2
			local layout = list(root)
			t.expect(root.Size).toBe(engine.types.UDim2.fromScale(1, 0))
			sized(engine, root, 400, 40)
			layout.AbsoluteContentSize = V2.new(340, 40)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Horizontal)
			sized(engine, root, 300, 40)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
			layout.AbsoluteContentSize = V2.new(100, 160)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
			sized(engine, root, 340, 160)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Horizontal)
			stop()
		end)

		t.it("returns to a row when a child narrows while stacked", function()
			local root, engine, stop = toolbar()
			local E, V2 = engine.types.Enum, engine.types.Vector2
			local layout = list(root)
			sized(engine, root, 300, 40)
			layout.AbsoluteContentSize = V2.new(340, 40)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
			sized(engine, root:FindFirstChild("C"), 60, 40)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Horizontal)
			stop()
		end)

		t.it("keeps the row width it measured when stretched children fill the column", function()
			local root, engine, stop = toolbar("stretch")
			local E, V2 = engine.types.Enum, engine.types.Vector2
			local layout = list(root)
			sized(engine, root, 300, 40)
			layout.AbsoluteContentSize = V2.new(340, 40)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
			for _, name in { "A", "B", "C" } do
				sized(engine, root:FindFirstChild(name), 300, 40)
			end
			layout.AbsoluteContentSize = V2.new(300, 160)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
			sized(engine, root, 340, 160)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Horizontal)
			stop()
		end)

		t.it("measures the row again when a stretched column loses a child", function()
			local root, engine, stop = toolbar("stretch")
			local E, V2 = engine.types.Enum, engine.types.Vector2
			local layout = list(root)
			sized(engine, root, 300, 40)
			layout.AbsoluteContentSize = V2.new(340, 40)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
			root:FindFirstChild("C").Parent = nil
			t.expect(layout.FillDirection).toBe(E.FillDirection.Horizontal)
			stop()
		end)

		t.it(
			"counts no width for a Divider or a filling child and retries a refused row only after a change",
			function()
				local root, engine, stop = build(function(UI, Host)
					return UI.AdaptiveStack {
						gap = 20,
						Host.Frame { Name = "A" },
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
				t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
				sized(engine, root:FindFirstChild("Line"), 300, 1)
				layout.AbsoluteContentSize = V2.new(300, 200)
				t.expect(layout.FillDirection).toBe(E.FillDirection.Horizontal)
				layout.AbsoluteContentSize = V2.new(330, 40)
				t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
				layout.AbsoluteContentSize = V2.new(300, 200)
				t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
				sized(engine, root, 340, 200)
				t.expect(layout.FillDirection).toBe(E.FillDirection.Horizontal)
				stop()
			end
		)

		t.it("measures against the width inside its padding", function()
			local root, engine, stop = build(function(UI, Host)
				return UI.AdaptiveStack { padding = 10, Host.Frame { Name = "A" } }
			end)
			local E = engine.types.Enum
			local layout = list(root)
			sized(engine, root:FindFirstChild("A"), 100, 40)
			sized(engine, root, 115, 40)
			layout.AbsoluteContentSize = engine.types.Vector2.new(100, 40)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
			sized(engine, root, 120, 60)
			t.expect(layout.FillDirection).toBe(E.FillDirection.Horizontal)
			stop()
		end)

		t.it("stays a row along a horizontal scroll axis, where the width is unbounded", function()
			local root, engine, stop = build(function(UI)
				return UI.ScrollView { axis = "x", UI.AdaptiveStack "Row" {} }
			end)
			local row = root:FindFirstChild("Row")
			sized(engine, row, 100, 40)
			list(row).AbsoluteContentSize = engine.types.Vector2.new(500, 40)
			t.expect(list(row).FillDirection).toBe(engine.types.Enum.FillDirection.Horizontal)
			stop()
		end)
	end)

	t.describe("ViewThatFits", function()
		local function actions(): (any, any, () -> ())
			return build(function(UI, Host)
				return UI.ViewThatFits {
					Host.Frame { Name = "Row" },
					Host.Frame { Name = "Column" },
				}
			end)
		end

		t.it("shows the first candidate whose width fits and hides the others", function()
			local root, engine, stop = actions()
			local row, column = root:FindFirstChild("Row"), root:FindFirstChild("Column")
			sized(engine, row, 300, 40)
			sized(engine, column, 120, 100)
			sized(engine, root, 320, 0)
			t.expect(row.Visible).toBe(true)
			t.expect(column.Visible).toBe(false)
			sized(engine, root, 200, 0)
			t.expect(row.Visible).toBe(false)
			t.expect(column.Visible).toBe(true)
			t.expect(root:FindFirstChild("Row")).toBe(row)
			stop()
		end)

		t.it("shows the last candidate when none fits", function()
			local root, engine, stop = actions()
			sized(engine, root:FindFirstChild("Row"), 300, 40)
			sized(engine, root:FindFirstChild("Column"), 120, 100)
			sized(engine, root, 80, 0)
			t.expect(root:FindFirstChild("Row").Visible).toBe(false)
			t.expect(root:FindFirstChild("Column").Visible).toBe(true)
			stop()
		end)

		t.it("fills the width, hugs the height and ignores height while it hugs", function()
			local root, engine, stop = actions()
			t.expect(root.Size).toBe(engine.types.UDim2.fromScale(1, 0))
			t.expect(root.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.Y)
			t.expect(list(root).FillDirection).toBe(engine.types.Enum.FillDirection.Vertical)
			sized(engine, root:FindFirstChild("Row"), 300, 400)
			sized(engine, root, 320, 40)
			t.expect(root:FindFirstChild("Row").Visible).toBe(true)
			stop()
		end)

		t.it("tests the height too when the height is bounded", function()
			local root, engine, stop = build(function(UI, Host)
				return UI.ViewThatFits { height = "fill", Host.Frame { Name = "Tall" }, Host.Frame { Name = "Short" } }
			end)
			sized(engine, root:FindFirstChild("Tall"), 100, 300)
			sized(engine, root:FindFirstChild("Short"), 100, 50)
			sized(engine, root, 320, 200)
			t.expect(root:FindFirstChild("Tall").Visible).toBe(false)
			t.expect(root:FindFirstChild("Short").Visible).toBe(true)
			stop()
		end)

		t.it("picks the first candidate along a horizontal scroll axis", function()
			local root, engine, stop = build(function(UI, Host)
				return UI.ScrollView {
					axis = "x",
					UI.ViewThatFits "Fits" { Host.Frame { Name = "Wide" }, Host.Frame { Name = "Narrow" } },
				}
			end)
			local fits = root:FindFirstChild("Fits")
			sized(engine, fits:FindFirstChild("Wide"), 900, 40)
			sized(engine, fits, 300, 40)
			t.expect(fits:FindFirstChild("Wide").Visible).toBe(true)
			t.expect(fits:FindFirstChild("Narrow").Visible).toBe(false)
			stop()
		end)

		t.it("refuses a ViewThatFits without candidates", function()
			t.expect(string.find(
				refusal(function(UI)
					return UI.ViewThatFits {}
				end),
				"ViewThatFits needs at least one candidate",
				1,
				true
			))
				.never()
				.toBeNil()
		end)
	end)
end)
