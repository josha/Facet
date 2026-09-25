--!strict
local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, {
		id = id,
		contracts = contracts,
		run = function(t)
			local present = false
			t.mount(function(UI, Host)
				present = UI.VStack ~= nil
				return Host.Frame({})
			end)
			t.cleanup()
			t.check("this build has the layout constructors", present)
			if present then
				run(t)
			end
		end,
	})
end

local function box(Host: any, name: string, w: number, h: number, extra: { [string]: any }?): Frame
	local props: { [string]: any } = { Name = name, Size = UDim2.fromOffset(w, h) }
	for key, value in extra or {} do
		props[key] = value
	end
	return Host.Frame(props)
end

add("screen-padding-and-gap", { "themes-P3-24", "mech2-36" }, function(t)
	local stage = t.mount(function(UI, Host)
		return UI.Screen "Screen" { padding = "m", gap = "s", box(Host, "A", 10, 10), box(Host, "B", 10, 10) }
	end, { size = Vector2.new(400, 300) })
	local screen, a, b = t.find(stage, "Screen"), t.find(stage, "A"), t.find(stage, "B")
	t.near("A is inset by 16", a.AbsolutePosition.X - screen.AbsolutePosition.X, 16, 0.5)
	t.near("B follows A by 10 + 8", b.AbsolutePosition.Y - a.AbsolutePosition.Y, 18, 0.5)
	t.near("the screen fills its parent width", screen.AbsoluteSize.X, 400, 0.5)
	t.cleanup()
	stage = t.mount(function(UI, Host)
		return UI.VStack "Stack" { gap = "s", padding = "m", box(Host, "A", 20, 20), box(Host, "B", 20, 20) }
	end, { size = Vector2.new(400, 300) })
	t.near("stack height is children plus gap plus padding", t.find(stage, "Stack").AbsoluteSize.Y, 80, 0.5)
end)

add("grid-cells-and-gaps", { "mech2-41", "mech2-40", "mech2-42" }, function(t)
	local stage = t.mount(function(UI, Host)
		return UI.Grid "Grid" {
			columns = 2,
			gap = 4,
			cellHeight = 30,
			box(Host, "A", 0, 30),
			box(Host, "B", 0, 30),
			box(Host, "C", 0, 30),
		}
	end, { size = Vector2.new(200, 200) })
	local a, b, c = t.find(stage, "A"), t.find(stage, "B"), t.find(stage, "C")
	t.near("A and B share a row", a.AbsolutePosition.Y, b.AbsolutePosition.Y, 0.5)
	t.check(
		"B is right of A",
		b.AbsolutePosition.X > a.AbsolutePosition.X,
		{ a.AbsolutePosition.X, b.AbsolutePosition.X }
	)
	t.check("C starts the second row", c.AbsolutePosition.Y > a.AbsolutePosition.Y, c.AbsolutePosition.Y)
	t.near("C is in the first column", c.AbsolutePosition.X, a.AbsolutePosition.X, 0.5)
	t.cleanup()
	stage = t.mount(function(UI, Host)
		local cells = {}
		for index = 1, 4 do
			table.insert(cells, box(Host, "Cell" .. index, 0, 30))
		end
		return UI.Grid "Grid" {
			columns = 3,
			gap = 6,
			cellHeight = 30,
			Size = UDim2.fromOffset(210, 0),
			table.unpack(cells),
		}
	end, { size = Vector2.new(400, 300) })
	local grid = t.find(stage, "Grid")
	local c2, c4, c1 = t.find(stage, "Cell2"), t.find(stage, "Cell4"), t.find(stage, "Cell1")
	t.near("cell 2 at x 72", c2.AbsolutePosition.X - grid.AbsolutePosition.X, 72, 1)
	t.near("cell 4 at x 0", c4.AbsolutePosition.X - grid.AbsolutePosition.X, 0, 1)
	t.near("row pitch is cell height plus gap", c4.AbsolutePosition.Y - c1.AbsolutePosition.Y, 36, 1)
	t.cleanup()
	stage = t.mount(function(UI, Host)
		local cells = {}
		for index = 1, 6 do
			table.insert(cells, box(Host, "Cell" .. index, 0, 30))
		end
		return UI.Grid "Grid" {
			columns = 3,
			rowGap = "m",
			padding = { left = "xs" },
			aspectRatio = 1.5,
			Size = UDim2.fromOffset(300, 0),
			table.unpack(cells),
		}
	end, { size = Vector2.new(400, 400) })
	grid = t.find(stage, "Grid")
	c1, c4 = t.find(stage, "Cell1"), t.find(stage, "Cell4")
	t.near("left padding insets the first cell by 4", c1.AbsolutePosition.X - grid.AbsolutePosition.X, 4, 1)
	t.near("rowGap m opens rows by 16", c4.AbsolutePosition.Y - (c1.AbsolutePosition.Y + c1.AbsoluteSize.Y), 16, 1)
	t.near("aspect ratio 1.5 cell", c1.AbsoluteSize.X / math.max(1, c1.AbsoluteSize.Y), 1.5, 0.05)
end)

add("zstack-alignment", { "mech2-40" }, function(t)
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Pair" {
			Size = UDim2.fromOffset(200, 100),
			BackgroundTransparency = 1,
			UI.ZStack "End" { width = 200, height = 100, alignH = "end", alignV = "start", box(Host, "E", 20, 20) },
			UI.ZStack "Mid" { width = 200, height = 100, alignH = "center", alignV = "center", box(Host, "M", 50, 30) },
		}
	end, { size = Vector2.new(400, 300) })
	local z, e, m = t.find(stage, "End"), t.find(stage, "E"), t.find(stage, "M")
	t.near("end child at x 180", e.AbsolutePosition.X - z.AbsolutePosition.X, 180, 0.5)
	t.near("end child at y 0", e.AbsolutePosition.Y - z.AbsolutePosition.Y, 0, 0.5)
	t.near("centre child at x 75", m.AbsolutePosition.X - z.AbsolutePosition.X, 75, 0.5)
	t.near("centre child at y 35", m.AbsolutePosition.Y - z.AbsolutePosition.Y, 35, 0.5)
end)

add("stack-distribution", { "mech3-47" }, function(t)
	local expected = { spaceBetween = { 0, 250, 500 }, spaceEvenly = { 75, 250, 425 } }
	for mode, xs in expected do
		local stage = t.mount(function(UI, Host)
			return UI.HStack "Row" {
				width = 600,
				distribute = mode,
				box(Host, "A", 100, 20),
				box(Host, "B", 100, 20),
				box(Host, "C", 100, 20),
			}
		end, { size = Vector2.new(700, 200) })
		local row = t.find(stage, "Row")
		for index, name in { "A", "B", "C" } do
			t.near(`{mode} {name} x`, t.find(stage, name).AbsolutePosition.X - row.AbsolutePosition.X, xs[index], 1)
		end
		t.cleanup()
	end
	local stage = t.mount(function(UI, Host)
		return UI.VStack "Column" { height = 300, distribute = "end", box(Host, "A", 20, 20), box(Host, "B", 20, 20) }
	end, { size = Vector2.new(300, 400) })
	local column, b = t.find(stage, "Column"), t.find(stage, "B")
	t.near(
		"end distribution puts the last child at the bottom",
		b.AbsolutePosition.Y + b.AbsoluteSize.Y,
		column.AbsolutePosition.Y + column.AbsoluteSize.Y,
		1
	)
end)

add("fill-and-extents", { "mech2-36", "mech1-100" }, function(t)
	local stage = t.mount(function(UI, Host)
		return UI.HStack "Row" {
			width = 600,
			box(Host, "Fixed", 100, 20),
			box(Host, "One", 0, 20, { UI.fill() }),
			box(Host, "Two", 0, 20, { UI.fill(2) }),
		}
	end, { size = Vector2.new(700, 200) })
	local one, two = t.find(stage, "One"), t.find(stage, "Two")
	t.near("fill(2) takes twice fill()", two.AbsoluteSize.X / math.max(1, one.AbsoluteSize.X), 2, 0.05)
	t.near("fills share the leftover width", one.AbsoluteSize.X + two.AbsoluteSize.X, 500, 1)
	t.cleanup()
	for _, case in { { width = "fill", expected = 400 }, { width = 120, expected = 120 } } do
		stage = t.mount(function(UI, Host)
			return Host.Frame "Parent" {
				Size = UDim2.fromOffset(400, 200),
				UI.VStack "Stack" { width = case.width, box(Host, "A", 50, 20) },
			}
		end, { size = Vector2.new(500, 300) })
		t.near(`width {case.width}`, t.find(stage, "Stack").AbsoluteSize.X, case.expected, 0.5)
		t.cleanup()
	end
	stage = t.mount(function(UI, Host)
		return Host.Frame "Parent" {
			Size = UDim2.fromOffset(400, 200),
			UI.VStack "Stack" { width = "hug", box(Host, "A", 50, 20) },
		}
	end, { size = Vector2.new(500, 300) })
	t.near("width hug", t.find(stage, "Stack").AbsoluteSize.X, 50, 0.5)
end)

add("scroll-view-canvas-and-stretch", { "mech2-36" }, function(t)
	local stage = t.mount(function(UI, Host)
		local children = {}
		for index = 1, 12 do
			table.insert(
				children,
				UI.Text({ Name = "Line" .. index, text = string.rep("Wrapped text ", 6), TextWrapped = true })
			)
		end
		return UI.ScrollView "Scroll" { width = 240, height = 200, align = "stretch", table.unpack(children) }
	end, { size = Vector2.new(400, 400) })
	local scroll, line = t.find(stage, "Scroll"), t.find(stage, "Line1")
	t.check("content is taller than the window", scroll.AbsoluteCanvasSize.Y > scroll.AbsoluteWindowSize.Y, {
		canvas = scroll.AbsoluteCanvasSize,
		window = scroll.AbsoluteWindowSize,
	})
	t.near("a stretched child is as wide as the window", line.AbsoluteSize.X, scroll.AbsoluteWindowSize.X, 1)
	t.check("the stretched label wraps", line.TextBounds.Y > line.TextSize * 1.5, line.TextBounds)
end)

return cases
