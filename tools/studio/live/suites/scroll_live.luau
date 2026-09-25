--!strict
local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function cell(Host: any, name: string, size: UDim2): any
	return Host.Frame(name)({ Size = size, BackgroundTransparency = 0.5 })
end

add("scroll-view-canvas-covers-rows-and-gaps", { "apps-224" }, function(t: any)
	local stage = t.mount(function(UI, Host)
		return UI.ScrollView "List" {
			gap = 10,
			Size = UDim2.fromOffset(300, 100),
			cell(Host, "A", UDim2.fromOffset(300, 40)),
			cell(Host, "B", UDim2.fromOffset(300, 40)),
			cell(Host, "C", UDim2.fromOffset(300, 40)),
		}
	end, { size = Vector2.new(400, 400) })
	t.settle(10)
	local list = t.find(stage, "List")
	local a, c = t.find(list, "A"), t.find(list, "C")
	local padding = list:FindFirstChildWhichIsA("UIPadding")
	local vertical = if padding
		then padding:GetStyled("PaddingTop").Offset + padding:GetStyled("PaddingBottom").Offset
		else 0
	t.near("the canvas holds three rows and two gaps", list.AbsoluteCanvasSize.Y, 140 + vertical, 1)
	t.near("rows advance by their height plus the gap", c.AbsolutePosition.Y - a.AbsolutePosition.Y, 100, 1)
	t.check("the overflowing list scrolls", list.AbsoluteCanvasSize.Y > list.AbsoluteWindowSize.Y)
end)

add("horizontal-scroll-view-steps-along-x", { "apps-226" }, function(t: any)
	local stage = t.mount(function(UI, Host)
		local cells = {}
		for index = 1, 5 do
			table.insert(cells, cell(Host, "Cell" .. index, UDim2.new(0, 60, 1, 0)))
		end
		return UI.ScrollView "Rail" {
			axis = "x",
			gap = 10,
			Size = UDim2.fromOffset(200, 120),
			table.unpack(cells),
		}
	end, { size = Vector2.new(400, 400) })
	t.settle(10)
	local rail = t.find(stage, "Rail")
	local first, second = t.find(rail, "Cell1"), t.find(rail, "Cell2")
	local padding = rail:FindFirstChildWhichIsA("UIPadding")
	local horizontal = if padding
		then padding:GetStyled("PaddingLeft").Offset + padding:GetStyled("PaddingRight").Offset
		else 0
	t.near("cells advance along x by width plus gap", second.AbsolutePosition.X - first.AbsolutePosition.X, 70, 1)
	t.near("the canvas extent is horizontal", rail.AbsoluteCanvasSize.X, 340 + horizontal, 1)
	t.near("a full-height cell fills the window height", first.AbsoluteSize.Y, rail.AbsoluteWindowSize.Y, 1)
	t.check("the rail scrolls sideways, not down", rail.AbsoluteCanvasSize.Y <= rail.AbsoluteWindowSize.Y + 1, {
		canvas = rail.AbsoluteCanvasSize,
		window = rail.AbsoluteWindowSize,
	})
end)

return cases
