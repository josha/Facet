--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local themes = Facet.themes

local function make(options: { [string]: any }?): (any, any, any)
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local config: { [string]: any } = { types = engine.types, guiService = gui, services = { GuiService = gui } }
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	return engine, runtime, Facet.controls(runtime, config :: any)
end

local function build(options: { [string]: any }?, body: (any, any) -> any): (any, any, () -> ())
	local engine, runtime, UI = make(options)
	local root: any
	runtime.mount(function()
		root = body(UI, runtime.constructors)
		return root
	end, engine.new("ScreenGui"))
	return root, engine, function()
		runtime:dispose()
	end
end

local function child(node: any, className: string): any
	return node:FindFirstChildWhichIsA(className)
end

local function wide(): any
	return assert(themes.define({
		identity = { id = "wide-spacing" },
		metrics = { space = { xs = 6, s = 12, m = 20, l = 30, xl = 48 } },
	} :: any))
end

local function refusal(body: (any, any) -> any): string?
	local engine, runtime, UI = make()
	local ok, message = pcall(function()
		runtime.mount(function()
			return body(UI, runtime.constructors)
		end, engine.new("ScreenGui"))
	end)
	runtime:dispose()
	return if ok then nil else tostring(message)
end

local function mentions(message: string?, fragment: string): boolean
	return message ~= nil and string.find(message, fragment, 1, true) ~= nil
end

t.describe("native layout primitives", function()
	t.describe("VStack and HStack", function()
		t.it("build a plain Frame with a list layout and number the children in declaration order", function()
			local root, engine, stop = build(nil, function(UI)
				return UI.VStack {
					UI.Text { text = "One" },
					UI.Text { text = "Two" },
					UI.Button { label = "Three", onActivate = function() end },
				}
			end)
			local E = engine.types.Enum
			t.expect(root.ClassName).toBe("Frame")
			t.expect(root.BackgroundTransparency).toBe(1)
			t.expect(root.BorderSizePixel).toBe(0)
			t.expect(root.Size).toBe(engine.types.UDim2.new(0, 0, 0, 0))
			t.expect(root.AutomaticSize).toBe(E.AutomaticSize.XY)
			local layout = child(root, "UIListLayout")
			t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
			t.expect(layout.SortOrder).toBe(E.SortOrder.LayoutOrder)
			t.expect(layout.Padding).toBe(engine.types.UDim.new(0, 0))
			t.expect(child(root, "UIPadding")).toBeNil()
			local orders = {}
			for _, node in root:GetChildren() do
				if node:IsA("GuiObject") then
					orders[node.Text] = node.LayoutOrder
				end
			end
			t.expect(orders).toEqual({ One = 1, Two = 2, Three = 3 })
			stop()
		end)

		t.it("lays an HStack out horizontally and accepts a constructor name", function()
			local root, engine, stop = build(nil, function(UI)
				return UI.HStack "Toolbar" { gap = 4, UI.Text { text = "A" } }
			end)
			t.expect(root.Name).toBe("Toolbar")
			t.expect(child(root, "UIListLayout").FillDirection).toBe(engine.types.Enum.FillDirection.Horizontal)
			t.expect(child(root, "UIListLayout").Padding).toBe(engine.types.UDim.new(0, 4))
			stop()
		end)

		t.it("resolves gap and padding spacing steps from the theme package", function()
			local root, engine, stop = build(nil, function(UI)
				return UI.VStack { gap = "s", padding = "m", UI.Text { text = "A" } }
			end)
			local space = themes.neutralPackage().metrics.space
			local padding = child(root, "UIPadding")
			t.expect(child(root, "UIListLayout").Padding).toBe(engine.types.UDim.new(0, space.s))
			for _, side in { "PaddingTop", "PaddingRight", "PaddingBottom", "PaddingLeft" } do
				t.expect(padding[side]).toBe(engine.types.UDim.new(0, space.m))
			end
			stop()
		end)

		t.it("pads each side on its own and keeps literal pixel values", function()
			local root, engine, stop = build(nil, function(UI)
				return UI.VStack { gap = 7, padding = { left = "xs", top = 3 } }
			end)
			local padding = child(root, "UIPadding")
			local D = engine.types.UDim
			t.expect(child(root, "UIListLayout").Padding).toBe(D.new(0, 7))
			t.expect(padding.PaddingLeft).toBe(D.new(0, themes.neutralPackage().metrics.space.xs))
			t.expect(padding.PaddingTop).toBe(D.new(0, 3))
			t.expect(padding.PaddingRight).toBe(D.new(0, 0))
			t.expect(padding.PaddingBottom).toBe(D.new(0, 0))
			stop()
		end)

		t.it("moves gap and padding when the theme package changes", function()
			local theme = Compose.cell(themes.neutralPackage())
			local root, engine, stop = build({ theme = theme }, function(UI)
				return UI.VStack { gap = "s", padding = { left = "m" }, UI.Text { text = "A" } }
			end)
			local D = engine.types.UDim
			local layout, padding = child(root, "UIListLayout"), child(root, "UIPadding")
			t.expect(layout.Padding).toBe(D.new(0, 8))
			t.expect(padding.PaddingLeft).toBe(D.new(0, 16))
			theme:set(wide())
			t.expect(child(root, "UIListLayout")).toBe(layout)
			t.expect(layout.Padding).toBe(D.new(0, 12))
			t.expect(padding.PaddingLeft).toBe(D.new(0, 20))
			stop()
		end)

		t.it("maps align and distribute to the native list alignment and flex", function()
			local align = Compose.cell("center")
			local root, engine, stop = build(nil, function(UI)
				return UI.HStack { align = align, distribute = "spaceBetween", UI.Text { text = "A" } }
			end)
			local E = engine.types.Enum
			local layout = child(root, "UIListLayout")
			t.expect(layout.VerticalAlignment).toBe(E.VerticalAlignment.Center)
			t.expect(layout.ItemLineAlignment).toBe(E.ItemLineAlignment.Automatic)
			t.expect(layout.HorizontalFlex).toBe(E.UIFlexAlignment.SpaceBetween)
			t.expect(layout.HorizontalAlignment).toBe(E.HorizontalAlignment.Left)
			t.expect(layout.VerticalFlex).toBe(E.UIFlexAlignment.None)
			align:set("stretch")
			t.expect(layout.ItemLineAlignment).toBe(E.ItemLineAlignment.Stretch)
			t.expect(layout.VerticalFlex).toBe(E.UIFlexAlignment.Fill)
			t.expect(layout.HorizontalFlex).toBe(E.UIFlexAlignment.SpaceBetween)
			t.expect(layout.VerticalAlignment).toBe(E.VerticalAlignment.Top)
			align:set("end")
			t.expect(layout.VerticalAlignment).toBe(E.VerticalAlignment.Bottom)
			t.expect(layout.VerticalFlex).toBe(E.UIFlexAlignment.None)
			stop()
			local column = build(nil, function(UI)
				return UI.VStack { align = "end", distribute = "center" }
			end)
			local list = child(column, "UIListLayout")
			t.expect(list.HorizontalAlignment).toBe(E.HorizontalAlignment.Right)
			t.expect(list.VerticalAlignment).toBe(E.VerticalAlignment.Center)
			t.expect(list.VerticalFlex).toBe(E.UIFlexAlignment.None)
		end)

		t.it("spreads the leftover space with every native flex distribution", function()
			local E = engineLib.new().types.Enum
			for name, flex in
				{
					spaceBetween = E.UIFlexAlignment.SpaceBetween,
					spaceAround = E.UIFlexAlignment.SpaceAround,
					spaceEvenly = E.UIFlexAlignment.SpaceEvenly,
				}
			do
				local row, _, stopRow = build(nil, function(UI)
					return UI.HStack { distribute = name }
				end)
				t.expect(child(row, "UIListLayout").HorizontalFlex).toBe(flex)
				stopRow()
				local column, _, stopColumn = build(nil, function(UI)
					return UI.VStack { distribute = name }
				end)
				t.expect(child(column, "UIListLayout").VerticalFlex).toBe(flex)
				stopColumn()
			end
			local screen, _, stopScreen = build(nil, function(UI)
				return UI.Screen { distribute = "end" }
			end)
			t.expect(child(screen, "UIListLayout").VerticalAlignment).toBe(E.VerticalAlignment.Bottom)
			stopScreen()
		end)

		t.it("accepts distribute only on the list containers", function()
			t.expect(mentions(
				refusal(function(UI)
					return UI.ZStack { distribute = "center" }
				end),
				"distribute"
			)).toBe(true)
			t.expect(mentions(
				refusal(function(UI)
					return UI.Grid { columns = 2, distribute = "center" }
				end),
				"distribute"
			)).toBe(true)
			t.expect(refusal(function(UI)
				return UI.ScrollView { distribute = "center" }
			end)).toBeNil()
		end)

		t.it("writes no alignment property that the author did not ask for", function()
			local root, engine, stop = build(nil, function(UI)
				return UI.VStack {}
			end)
			local E = engine.types.Enum
			local layout = child(root, "UIListLayout")
			local native = engine.new("UIListLayout")
			t.expect(layout.HorizontalAlignment).toBe(native.HorizontalAlignment)
			t.expect(layout.VerticalAlignment).toBe(native.VerticalAlignment)
			t.expect(layout.ItemLineAlignment).toBe(native.ItemLineAlignment)
			t.expect(layout.HorizontalFlex).toBe(E.UIFlexAlignment.None)
			t.expect(layout.Wraps).toBe(false)
			stop()
		end)

		t.it("sizes by fill, hug and pixels on each axis", function()
			local width = Compose.cell("fill" :: any)
			local root, engine, stop = build(nil, function(UI)
				return UI.VStack { width = width, height = 40 }
			end)
			local E, D2 = engine.types.Enum, engine.types.UDim2
			t.expect(root.Size).toBe(D2.new(1, 0, 0, 40))
			t.expect(root.AutomaticSize).toBe(E.AutomaticSize.None)
			width:set(120)
			t.expect(root.Size).toBe(D2.new(0, 120, 0, 40))
			width:set("hug")
			t.expect(root.AutomaticSize).toBe(E.AutomaticSize.X)
			stop()
		end)

		t.it("passes native properties through and lets them win over the defaults", function()
			local D2 = engineLib.new().types.UDim2
			local root, engine, stop = build(nil, function(UI)
				return UI.VStack { BackgroundTransparency = 0.25, Size = D2.fromOffset(10, 10) }
			end)
			t.expect(root.BackgroundTransparency).toBe(0.25)
			t.expect(root.Size).toBe(engine.types.UDim2.fromOffset(10, 10))
			stop()
		end)

		t.it("numbers the nodes that a Compose directive child adds later", function()
			local shown = Compose.cell(false)
			local root, _, stop = build(nil, function(UI)
				return UI.VStack {
					UI.Text { text = "First" },
					Compose.show(shown, function()
						return UI.Text { text = "Middle" }
					end),
					UI.Text { text = "Last" },
				}
			end)
			shown:set(true)
			local orders = {}
			for _, node in root:GetChildren() do
				if node:IsA("GuiObject") then
					orders[node.Text] = node.LayoutOrder
				end
			end
			t.expect(orders).toEqual({ First = 1, Middle = 2, Last = 3 })
			stop()
		end)

		t.it("refuses an unknown spacing step, alignment or option and names the vocabulary", function()
			local engine, runtime, UI = make()
			local function refused(body: () -> any, fragment: string)
				local ok, message = pcall(function()
					runtime.mount(body, engine.new("ScreenGui"))
				end)
				t.expect(ok).toBe(false)
				t.expect(string.find(tostring(message), fragment, 1, true) ~= nil).toBe(true)
			end
			refused(function()
				return UI.VStack { gap = "enormous" }
			end, "xs, s, m, l, xl")
			refused(function()
				return UI.VStack { padding = "enormous" }
			end, "enormous")
			refused(function()
				return UI.VStack { padding = { left = "enormous" } }
			end, "enormous")
			refused(function()
				return UI.HStack { align = "middle" }
			end, "start, center, end or stretch")
			refused(function()
				return UI.VStack { distribute = "around" }
			end, "spaceBetween")
			refused(function()
				return UI.VStack { width = "stretch" }
			end, "fill, hug")
			refused(function()
				return UI.VStack { gpa = "s" }
			end, "gpa")
			runtime:dispose()
		end)
	end)

	t.describe("fill", function()
		t.it("refuses a weight that is not a positive number", function()
			t.expect(mentions(
				refusal(function(UI)
					return UI.HStack { UI.Text { text = "A", UI.fill(0) } }
				end),
				"positive"
			)).toBe(true)
			t.expect(mentions(
				refusal(function(UI)
					return UI.HStack { UI.Text { text = "A", UI.fill(-1) } }
				end),
				"positive"
			)).toBe(true)
		end)

		t.it("makes a native flex item that fills the main axis, by weight when given", function()
			local root, engine, stop = build(nil, function(UI)
				return UI.HStack {
					UI.Text { text = "A", UI.fill() },
					UI.Text { text = "B", UI.fill(2) },
				}
			end)
			local E = engine.types.Enum
			local items = {}
			for _, node in root:GetChildren() do
				if node:IsA("GuiObject") then
					items[node.Text] = child(node, "UIFlexItem")
				end
			end
			t.expect(items.A.FlexMode).toBe(E.UIFlexMode.Fill)
			t.expect(items.B.FlexMode).toBe(E.UIFlexMode.Custom)
			t.expect(items.B.GrowRatio).toBe(2)
			t.expect(items.B.ShrinkRatio).toBe(2)
			stop()
		end)
	end)

	t.describe("Screen", function()
		t.it("fills its parent, pads the content by the m step and stacks vertically", function()
			local root, engine, stop = build(nil, function(UI)
				return UI.Screen "Home" { gap = "s", UI.Text { text = "A" } }
			end)
			local E = engine.types.Enum
			t.expect(root.Name).toBe("Home")
			t.expect(root.Size).toBe(engine.types.UDim2.fromScale(1, 1))
			t.expect(root.AutomaticSize).toBe(E.AutomaticSize.None)
			t.expect(root.BackgroundTransparency).toBe(1)
			t.expect(child(root, "UIPadding").PaddingTop).toBe(engine.types.UDim.new(0, 16))
			t.expect(child(root, "UIListLayout").FillDirection).toBe(E.FillDirection.Vertical)
			t.expect(child(root, "UIListLayout").Padding).toBe(engine.types.UDim.new(0, 8))
			stop()
			local bare = build(nil, function(UI)
				return UI.Screen { padding = 0 }
			end)
			t.expect(child(bare, "UIPadding").PaddingLeft).toBe(engine.types.UDim.new(0, 0))
		end)
	end)

	t.describe("ZStack", function()
		t.it("layers later children above earlier ones and keeps an authored ZIndex", function()
			local root, _, stop = build(nil, function(UI, Host)
				return UI.ZStack {
					Host.Frame { Name = "Back" },
					Host.Frame { Name = "Front" },
					Host.Frame { Name = "Pinned", ZIndex = 9 },
				}
			end)
			t.expect(root:FindFirstChild("Back").ZIndex).toBe(1)
			t.expect(root:FindFirstChild("Front").ZIndex).toBe(2)
			t.expect(root:FindFirstChild("Pinned").ZIndex).toBe(9)
			t.expect(child(root, "UIListLayout")).toBeNil()
			stop()
		end)

		t.it("refuses an alignment outside start, center and end", function()
			t.expect(mentions(
				refusal(function(UI, Host)
					return UI.ZStack { alignH = "stretch", Host.Frame {} }
				end),
				"start, center or end"
			)).toBe(true)
		end)

		t.it("aligns every child by anchor point and scale position", function()
			local horizontal = Compose.cell("center")
			local root, engine, stop = build(nil, function(UI, Host)
				return UI.ZStack {
					width = "fill",
					height = "fill",
					alignH = horizontal,
					alignV = "end",
					Host.Frame { Name = "Badge" },
				}
			end)
			local badge = root:FindFirstChild("Badge")
			t.expect(badge.AnchorPoint).toBe(engine.types.Vector2.new(0.5, 1))
			t.expect(badge.Position).toBe(engine.types.UDim2.fromScale(0.5, 1))
			horizontal:set("end")
			t.expect(badge.AnchorPoint).toBe(engine.types.Vector2.new(1, 1))
			t.expect(badge.Position).toBe(engine.types.UDim2.fromScale(1, 1))
			stop()
		end)

		t.it("aligns children by offset along a hugging axis", function()
			local root, engine, stop = build(nil, function(UI, Host)
				return UI.ZStack {
					width = 60,
					alignH = "end",
					alignV = "end",
					Host.Frame { Name = "Card" },
					Host.Frame { Name = "Dot" },
				}
			end)
			local V2, D2 = engine.types.Vector2, engine.types.UDim2
			local card, dot = root:FindFirstChild("Card"), root:FindFirstChild("Dot")
			card.AbsoluteSize = V2.new(60, 40)
			dot.AbsoluteSize = V2.new(16, 16)
			t.expect(dot.AnchorPoint).toBe(V2.new(1, 0))
			t.expect(dot.Position).toBe(D2.new(1, 0, 0, 24))
			t.expect(card.Position).toBe(D2.new(1, 0, 0, 0))
			dot.AbsoluteSize = V2.new(16, 50)
			t.expect(card.Position).toBe(D2.new(1, 0, 0, 10))
			t.expect(dot.Position).toBe(D2.new(1, 0, 0, 0))
			stop()
		end)
	end)

	t.describe("ScrollView", function()
		t.it("sizes vertical content to the scroll window with a list layout and automatic canvas", function()
			local root, engine, stop = build(nil, function(UI)
				return UI.ScrollView "Page" { gap = "s", padding = "m", UI.Text { text = "A" }, UI.Text { text = "B" } }
			end)
			local E, D2 = engine.types.Enum, engine.types.UDim2
			t.expect(root.ClassName).toBe("ScrollingFrame")
			t.expect(root.Name).toBe("Page")
			t.expect(root.Size).toBe(D2.fromScale(1, 1))
			t.expect(root.CanvasSize).toBe(D2.new())
			t.expect(root.AutomaticCanvasSize).toBe(E.AutomaticSize.Y)
			t.expect(root.ScrollingDirection).toBe(E.ScrollingDirection.Y)
			t.expect(root.VerticalScrollBarInset).toBe(E.ScrollBarInset.ScrollBar)
			t.expect(root.BackgroundTransparency).toBe(1)
			local layout = child(root, "UIListLayout")
			t.expect(layout.FillDirection).toBe(E.FillDirection.Vertical)
			t.expect(layout.Padding).toBe(engine.types.UDim.new(0, 8))
			t.expect(child(root, "UIPadding").PaddingTop).toBe(engine.types.UDim.new(0, 16))
			local orders = {}
			for _, node in root:GetChildren() do
				if node:IsA("GuiObject") then
					orders[node.Text] = node.LayoutOrder
				end
			end
			t.expect(orders).toEqual({ A = 1, B = 2 })
			stop()
		end)

		t.it("stretches the children across the scroll window when align is stretch", function()
			local root, engine, stop = build(nil, function(UI)
				return UI.ScrollView { align = "stretch", UI.Text { text = "A" } }
			end)
			local layout = child(root, "UIListLayout")
			t.expect(layout.ItemLineAlignment).toBe(engine.types.Enum.ItemLineAlignment.Stretch)
			t.expect(layout.HorizontalFlex).toBe(engine.types.Enum.UIFlexAlignment.Fill)
			stop()
		end)

		t.it("runs a horizontal axis as a horizontal list with a horizontal canvas", function()
			local root, engine, stop = build(nil, function(UI)
				return UI.ScrollView { axis = "x" }
			end)
			local E = engine.types.Enum
			t.expect(child(root, "UIListLayout").FillDirection).toBe(E.FillDirection.Horizontal)
			t.expect(root.AutomaticCanvasSize).toBe(E.AutomaticSize.X)
			t.expect(root.ScrollingDirection).toBe(E.ScrollingDirection.X)
			t.expect(root.HorizontalScrollBarInset).toBe(E.ScrollBarInset.ScrollBar)
			stop()
			local both = build(nil, function(UI)
				return UI.ScrollView { axis = "xy" }
			end)
			t.expect(both.AutomaticCanvasSize).toBe(E.AutomaticSize.XY)
			t.expect(both.ScrollingDirection).toBe(E.ScrollingDirection.XY)
		end)
	end)

	t.describe("Grid", function()
		t.it("divides the width into columns with a native grid layout", function()
			local root, engine, stop = build(nil, function(UI, Host)
				return UI.Grid "Tiles" {
					columns = 3,
					gap = "s",
					Host.Frame { Name = "A" },
					Host.Frame { Name = "B" },
					Host.Frame { Name = "C" },
					Host.Frame { Name = "D" },
				}
			end)
			local E, D2 = engine.types.Enum, engine.types.UDim2
			local grid = child(root, "UIGridLayout")
			t.expect(root.Size).toBe(D2.new(1, 0, 0, 0))
			t.expect(root.AutomaticSize).toBe(E.AutomaticSize.Y)
			t.expect(grid.SortOrder).toBe(E.SortOrder.LayoutOrder)
			t.expect(grid.FillDirection).toBe(E.FillDirection.Horizontal)
			t.expect(grid.FillDirectionMaxCells).toBe(3)
			t.expect(grid.CellPadding).toBe(D2.fromOffset(8, 8))
			local height = themes.neutralPackage().metrics.controlSizes.regular.height
			t.expect(grid.CellSize.X.Scale).toBeCloseTo(1 / 3)
			t.expect(grid.CellSize.X.Offset).toBe(-6)
			for width = 60, 900 do
				local row = 3 * (grid.CellSize.X.Scale * width + grid.CellSize.X.Offset) + 2 * grid.CellPadding.X.Offset
				t.expect(row <= width).toBe(true)
			end
			t.expect(grid.CellSize.Y.Offset).toBe(height)
			t.expect(root:FindFirstChild("D").LayoutOrder).toBe(4)
			stop()
		end)

		t.it("takes a separate row gap, a cell height and an aspect ratio", function()
			local columns = Compose.cell(2)
			local root, engine, stop = build(nil, function(UI)
				return UI.Grid { columns = columns, gap = 4, rowGap = "m", cellHeight = 60, aspectRatio = 1.5 }
			end)
			local grid = child(root, "UIGridLayout")
			t.expect(grid.CellPadding).toBe(engine.types.UDim2.fromOffset(4, 16))
			t.expect(grid.CellSize.Y.Offset).toBe(60)
			t.expect(child(grid, "UIAspectRatioConstraint").AspectRatio).toBe(1.5)
			columns:set(4)
			t.expect(grid.FillDirectionMaxCells).toBe(4)
			t.expect(grid.CellSize.X.Scale).toBeCloseTo(0.25)
			t.expect(grid.CellSize.X.Offset).toBe(-3)
			stop()
		end)

		t.it("moves the row gap with the theme and keeps the column count", function()
			local theme = Compose.cell(themes.neutralPackage())
			local root, engine, stop = build({ theme = theme }, function(UI)
				return UI.Grid { columns = 3, gap = 4, rowGap = "s" }
			end)
			local grid = child(root, "UIGridLayout")
			t.expect(grid.CellPadding).toBe(engine.types.UDim2.fromOffset(4, 8))
			theme:set(wide())
			t.expect(grid.CellPadding).toBe(engine.types.UDim2.fromOffset(4, 12))
			t.expect(grid.FillDirectionMaxCells).toBe(3)
			stop()
		end)

		t.it("refuses a column count that is not a whole number", function()
			local engine, runtime, UI = make()
			local ok, message = pcall(function()
				runtime.mount(function()
					return UI.Grid { columns = 1.5 }
				end, engine.new("ScreenGui"))
			end)
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(message), "whole number", 1, true) ~= nil).toBe(true)
			runtime:dispose()
		end)
	end)

	t.describe("theme spacing steps", function()
		t.it("validates the spacing scale of a theme package", function()
			local package, report =
				themes.define({ identity = { id = "bad-space" }, metrics = { space = { s = -2 } } } :: any)
			t.expect(package).toBeNil()
			t.expect(report.errors[1].field).toBe("metrics.space.s")
			local good = wide()
			t.expect(good.metrics.space.s).toBe(12)
		end)
	end)
end)
