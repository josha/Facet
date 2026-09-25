--!strict
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local cases: { any } = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function interactive(
	id: string,
	contracts: { string },
	plan: string,
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () }
)
	table.insert(cases, { id = id, contracts = contracts, plan = plan, setup = setup, steps = steps })
end

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function within(node: any, root: any): boolean
	return node ~= nil and root ~= nil and (node == root or node:IsDescendantOf(root))
end

local function visibleNamed(t: any, root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

local function buttonNamed(root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("TextButton") then
			return node
		end
	end
	return nil
end

local function overlap(a: any, b: any): boolean
	local w = math.min(a.r, b.r) - math.max(a.x, b.x)
	local h = math.min(a.b, b.b) - math.max(a.y, b.y)
	return w > 0.5 and h > 0.5
end

local function crossings(named: { any }): { string }
	local out = {}
	for i = 1, #named do
		for j = i + 1, #named do
			if overlap(named[i].rect, named[j].rect) then
				table.insert(out, `{named[i].name} x {named[j].name}`)
			end
		end
	end
	return out
end

local function centre(rect: any): Vector2
	return Vector2.new(rect.x + rect.w / 2, rect.y + rect.h / 2)
end

local function screenPoint(x: number, y: number): { number }
	return { math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function windowRect(frame: any): any
	local at, size = frame.AbsolutePosition, frame.AbsoluteWindowSize
	return { x = at.X, y = at.Y, w = size.X, h = size.Y, r = at.X + size.X, b = at.Y + size.Y }
end

local function scenario(t: any, name: string, options: { [string]: any }?): (any, any)
	local config: { [string]: any } = options or {}
	local built: any
	local stage = t.mount(function(UI: any, Host: any, Compose: any, env: any)
		built = t.scenario(name).build(t.context(UI, Host, Compose, env))
		return if type(built) == "function" then built() else built.screen()
	end, { size = config.size, reducedMotion = config.reducedMotion, frames = config.frames or 20 })
	return stage, built
end

local function paginationItems(root: any): { any }
	local row = root and root:FindFirstChild("Row")
	local items = {}
	if not row then
		return items
	end
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			table.insert(items, child)
		end
	end
	table.sort(items, function(a: any, b: any): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	return items
end

local function paginationText(root: any): string
	local out = {}
	for _, item in paginationItems(root) do
		local page = string.match(item.Name, "^Slot%-(%d+)$")
		if page then
			table.insert(out, page)
		elseif string.match(item.Name, "^gap%-") then
			table.insert(out, "…")
		elseif item.Name == "Label" then
			table.insert(out, item.ContentText)
		else
			table.insert(out, string.lower(item.Name))
		end
	end
	return table.concat(out, " ")
end

local function settledText(t: any, root: any): string
	local last = ""
	for index = 1, 12 do
		t.settle(1)
		local now = paginationText(root)
		if index >= 3 and now == last then
			return now
		end
		last = now
	end
	return last
end

local function hasPage(text: string, page: string): boolean
	return string.find(" " .. text .. " ", " " .. page .. " ", 1, true) ~= nil
end

local ARROWS = { First = true, Previous = true, Next = true, Last = true }

add("pagination-fit-narrows-in-order", { "post-pagination-08" }, function(t)
	local width: any
	local stage = t.mount(function(UI: any, Host: any, Compose: any)
		width = Compose.cell(800)
		local page = Compose.cell(5000)
		return Host.Frame "Holder" {
			BackgroundTransparency = 1,
			Size = function(use)
				return UDim2.fromOffset(use(width), 60)
			end,
			UI.Pagination "Results" {
				page = page,
				pageCount = 9999,
				onChange = function(nextPage: number)
					page:set(nextPage)
				end,
			},
		}
	end, { size = Vector2.new(1280, 720), frames = 12 })
	local root = t.find(stage, "Results")
	t.check("the Results pagination mounts", root ~= nil)
	if not root then
		return
	end
	local states, widths = {}, {}
	local narrowest, narrowArrow = math.huge, math.huge
	local overflow = {}
	for w = 800, 100, -5 do
		width:set(w)
		local text = settledText(t, root)
		table.insert(states, text)
		table.insert(widths, w)
		local label = string.find(text, "Page ", 1, true) ~= nil
		for _, item in paginationItems(root) do
			if string.match(item.Name, "^Slot%-") then
				narrowest = math.min(narrowest, item.AbsoluteSize.X)
			elseif ARROWS[item.Name] then
				narrowArrow = math.min(narrowArrow, item.AbsoluteSize.X)
			end
		end
		local row = root:FindFirstChild("Row")
		if row and not label and row.AbsoluteCanvasSize.X > w + 1 then
			table.insert(overflow, { w, row.AbsoluteCanvasSize.X })
		end
	end
	local distinct, previous = {}, nil
	for index, text in states do
		if text ~= previous then
			table.insert(distinct, `{widths[index]}: {text}`)
			previous = text
		end
	end
	t.note("states as the width narrows", distinct)
	local function firstMissing(page: string): number
		for index, text in states do
			if string.find(text, "Page ", 1, true) == nil and not hasPage(text, page) then
				return index
			end
		end
		return math.huge
	end
	local labelAt = math.huge
	for index, text in states do
		if string.find(text, "Page 5000 of 9999", 1, true) then
			labelAt = index
			break
		end
	end
	local order = {
		firstMissing("9999"),
		firstMissing("1"),
		firstMissing("5001"),
		firstMissing("4999"),
		labelAt,
	}
	t.note("first width index without 9999, 1, 5001, 4999, and with the label", order)
	t.check(
		"at 800 px the row shows 1 … 4999 5000 5001 … 9999",
		states[1] == "previous 1 … 4999 5000 5001 … 9999 next",
		states[1]
	)
	t.check("9999 drops first", order[1] < order[2], order)
	t.check("then 1", order[2] < order[3], order)
	t.check("then 5001", order[3] < order[4], order)
	t.check("then 4999", order[4] < order[5], order)
	t.check("the label Page 5000 of 9999 shows last", order[5] < math.huge, states[#states])
	t.check("no page slot is narrower than 44 px", narrowest >= 43.5, narrowest)
	t.check("no arrow is narrower than 44 px", narrowArrow >= 43.5, narrowArrow)
	t.check("every numbers row fits its offered width", #overflow == 0, overflow)
end)

local PAGINATIONS = { "Results", "Feed", "Label", "Rtl" }

local function findSection(stage: any): any
	for _, node in stage:GetDescendants() do
		if node.Name == "Paging" and node:IsA("Frame") and node:FindFirstChild("Results") then
			return node
		end
	end
	return nil
end

local function sectionPaginations(stage: any): (any, { [string]: any })
	local section = findSection(stage)
	local found = {}
	if section then
		for _, name in PAGINATIONS do
			found[name] = section:FindFirstChild(name)
		end
	end
	return section, found
end

add("pagination-hug-matches-fill", { "post-pagination-09" }, function(t)
	local stage = scenario(t, "paging", { size = Vector2.new(1280, 720) })
	local section, found = sectionPaginations(stage)
	t.check("the Paging section and its four paginations mount", section ~= nil and found.Rtl ~= nil)
	if not section then
		return
	end
	local before = {}
	for _, name in PAGINATIONS do
		local root = found[name]
		before[name] = { text = settledText(t, root), width = root.AbsoluteSize.X }
	end
	section.AutomaticSize = Enum.AutomaticSize.XY
	t.settle(10)
	for _, name in PAGINATIONS do
		local root = found[name]
		local text = settledText(t, root)
		t.check(`{name} shows the same window in a hugging section`, text == before[name].text, {
			fill = before[name].text,
			hug = text,
		})
		t.check(`{name} keeps a width above zero in a hugging section`, root.AbsoluteSize.X > 44, root.AbsoluteSize)
		t.near(`{name} keeps its width in a hugging section`, root.AbsoluteSize.X, before[name].width, 1)
	end
	t.cleanup()
	local roots = {}
	t.mount(function(UI: any, Host: any, Compose: any)
		local children = {
			Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
		}
		for index, w in { 360, 330, 240, 190 } do
			for _, kind in { "Fill", "Hug" } do
				local page = Compose.cell(5000)
				local pagination = UI.Pagination({
					Name = `{kind}{w}`,
					page = page,
					pageCount = 9999,
					onChange = function(nextPage: number)
						page:set(nextPage)
					end,
				})
				roots[`{kind}{w}`] = pagination
				table.insert(
					children,
					Host.Frame({
						Name = `{kind}Holder{w}`,
						LayoutOrder = index * 2 + (if kind == "Hug" then 1 else 0),
						BackgroundTransparency = 1,
						Size = if kind == "Fill" then UDim2.fromOffset(w, 44) else UDim2.fromOffset(w, 0),
						AutomaticSize = if kind == "Fill" then Enum.AutomaticSize.None else Enum.AutomaticSize.XY,
						pagination,
					})
				)
			end
		end
		local zero = Compose.cell(5000)
		local hugZero = UI.Pagination({
			Name = "HugZero",
			page = zero,
			pageCount = 9999,
			onChange = function(nextPage: number)
				zero:set(nextPage)
			end,
		})
		roots.HugZero = hugZero
		table.insert(
			children,
			Host.Frame({
				Name = "HugZeroHolder",
				LayoutOrder = 100,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				hugZero,
			})
		)
		local props: { [any]: any } = { Name = "Column", BackgroundTransparency = 1, Size = UDim2.fromOffset(600, 700) }
		for _, child in children do
			table.insert(props, child)
		end
		return Host.Frame(props)
	end, { size = Vector2.new(1280, 720), frames = 12 })
	for _, w in { 360, 330, 240, 190 } do
		local fill, hug = roots[`Fill{w}`], roots[`Hug{w}`]
		local a, b = settledText(t, fill), settledText(t, hug)
		t.check(`{w} px: a hugging parent shows the filling window`, a == b and a ~= "", { fill = a, hug = b })
		t.near(`{w} px: the hugged pagination keeps the offered width`, hug.AbsoluteSize.X, w, 1)
	end
	t.note("a zero-offset hugging parent gives the pagination this width", roots.HugZero.AbsoluteSize.X)
end)

interactive(
	"pagination-neighbours-arrive-and-land",
	{ "post-pagination-11", "post-pagination-16" },
	"afterDown: with the Refuse toggle selected, press Down once",
	function(t)
		local value = {}
		local alive: any, count: any
		local fixture = t.mount(function(UI: any, Host: any, Compose: any)
			alive = Compose.cell(true)
			count = Compose.cell(3)
			local page = Compose.cell(2)
			return Host.Frame "ZeroHost" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Compose.show(alive, function()
					return Host.Frame "ZeroCase" {
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(700, 40),
						Size = UDim2.fromOffset(500, 300),
						Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
						UI.Button({ Name = "Before", label = "Before", LayoutOrder = 1 }),
						UI.Pagination({
							Name = "Zero",
							LayoutOrder = 2,
							page = page,
							pageCount = count,
							onChange = function(nextPage: number)
								page:set(nextPage)
							end,
						}),
						UI.Button({ Name = "After", label = "After", LayoutOrder = 3 }),
					}
				end),
			}
		end, { size = Vector2.new(1280, 720), frames = 12 })
		local zero = t.find(fixture, "Zero")
		local target = zero and t.find(zero, "Page-3")
		t.check("the zero-count fixture shows Page-3", target ~= nil)
		if zero and target then
			GuiService.SelectedObject = target
			t.settle(2)
			count:set(0)
			t.settle(12)
			local selected = GuiService.SelectedObject
			t.note("selection after the count drops to zero", selectedName())
			t.check("the row shows No pages", paginationText(zero) == "No pages", paginationText(zero))
			local buttons = 0
			for _, node in zero:GetDescendants() do
				if node:IsA("GuiButton") then
					buttons += 1
				end
			end
			t.check("no stop is left inside the row", buttons == 0, buttons)
			t.check(
				"the selection lands on a live neighbour",
				selected ~= nil
					and not within(selected, zero)
					and (selected.Name == "Before" or selected.Name == "After")
					and t.visible(selected),
				selectedName()
			)
		end
		GuiService.SelectedObject = nil
		alive:set(false)
		t.settle(4)
		local stage = scenario(t, "paging", { size = Vector2.new(1280, 720) })
		local section, found = sectionPaginations(stage)
		value.results = found.Results
		value.refuse = section and section:FindFirstChild("Refuse")
		t.check("the Refuse toggle and the Results row are found", value.refuse ~= nil and value.results ~= nil)
		GuiService.SelectedObject = value.refuse
		t.check("the Refuse toggle holds the selection", selectedName() == "Refuse", selectedName())
		t.note("gamepad", "D-pad Down moves the same native selection as the Down arrow key")
		return value
	end,
	{
		afterDown = function(t, value)
			local selected = GuiService.SelectedObject
			t.note("selection after Down", selected and selected:GetFullName())
			t.check("Down from Refuse lands inside the Results row", within(selected, value.results), selectedName())
			GuiService.SelectedObject = nil
		end,
	}
)

local function targetsOf(t: any, root: any, where: string, named: { any })
	for _, item in paginationItems(root) do
		if string.match(item.Name, "^Slot%-") then
			local slot = t.rect(item)
			table.insert(named, { name = `{root.Name}/{item.Name}`, rect = slot })
			t.check(`{where} {root.Name} {item.Name} is at least 44 px`, slot.w >= 43.5 and slot.h >= 43.5, {
				slot.w,
				slot.h,
			})
			local plate = item:FindFirstChildWhichIsA("TextButton")
			if plate then
				local box = t.rect(plate)
				local a, b = centre(box), centre(slot)
				t.check(
					`{where} {root.Name} {item.Name} plate is centred in its slot`,
					math.abs(a.X - b.X) <= 0.75 and math.abs(a.Y - b.Y) <= 0.75,
					{ plate = { box.x, box.y, box.w, box.h }, slot = { slot.x, slot.y, slot.w, slot.h } }
				)
				t.inside(`{where} {root.Name} {item.Name} plate inside its slot`, box, slot, 0.5)
			else
				t.check(`{where} {root.Name} {item.Name} has a plate`, false)
			end
		elseif ARROWS[item.Name] then
			local arrow = t.rect(item)
			table.insert(named, { name = `{root.Name}/{item.Name}`, rect = arrow })
			t.check(`{where} {root.Name} {item.Name} arrow is at least 44 px`, arrow.w >= 43.5 and arrow.h >= 43.5, {
				arrow.w,
				arrow.h,
			})
		end
	end
end

add("pagination-targets-separate-and-centred", { "post-pagination-13", "post-pagination-14" }, function(t)
	for _, size in { Vector2.new(1280, 720), Vector2.new(390, 844) } do
		local where = `{size.X}x{size.Y}`
		local stage = scenario(t, "paging", { size = size })
		local _, found = sectionPaginations(stage)
		for _, name in PAGINATIONS do
			local root = found[name]
			t.check(`{where} {name} found`, root ~= nil)
			if root then
				settledText(t, root)
				local named = {}
				targetsOf(t, root, where, named)
				t.note(`{where} {name} row`, paginationText(root))
				local crossed = crossings(named)
				t.check(`{where} {name} targets do not overlap`, #crossed == 0, crossed)
			end
		end
		t.cleanup()
	end
end)

add("pagination-arrows-hold-still", { "post-pagination-15" }, function(t)
	local specs: { any } = {
		{ name = "KnownLtr", extra = { pageCount = 12, form = "label" }, from = 9, to = 10 },
		{ name = "KnownRtl", extra = { pageCount = 12, form = "label", direction = "rtl" }, from = 9, to = 10 },
		{ name = "UnknownLtr", extra = { hasNext = true, hasPrevious = true }, from = 9, to = 10 },
		{ name = "UnknownRtl", extra = { hasNext = true, hasPrevious = true, direction = "rtl" }, from = 99, to = 100 },
	}
	local pages = {}
	local stage = t.mount(function(UI: any, Host: any, Compose: any)
		local props: { [any]: any } = {
			Name = "Column",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(600, 400),
			Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
		}
		for index, entry in specs do
			local page = Compose.cell(entry.from)
			pages[entry.name] = page
			local spec: { [string]: any } = {
				Name = entry.name,
				LayoutOrder = index,
				page = page,
				onChange = function(nextPage: number)
					page:set(nextPage)
				end,
			}
			for key, item in entry.extra do
				spec[key] = item
			end
			table.insert(props, UI.Pagination(spec))
		end
		return Host.Frame(props)
	end, { size = Vector2.new(1280, 720), frames = 12 })
	for _, entry in specs do
		local root = t.find(stage, entry.name)
		t.check(`{entry.name} mounts`, root ~= nil)
		if root then
			settledText(t, root)
			local row = root:FindFirstChild("Row")
			local nextArrow, previousArrow = row and row:FindFirstChild("Next"), row and row:FindFirstChild("Previous")
			t.check(`{entry.name} has Next and Previous`, nextArrow ~= nil and previousArrow ~= nil)
			if nextArrow and previousArrow then
				local beforeText = paginationText(root)
				local a, b = nextArrow.AbsolutePosition.X, previousArrow.AbsolutePosition.X
				pages[entry.name]:set(entry.to)
				local afterText = settledText(t, root)
				t.note(`{entry.name} label`, { beforeText, afterText })
				t.near(
					`{entry.name} Next holds still from {entry.from} to {entry.to}`,
					nextArrow.AbsolutePosition.X,
					a,
					0.5
				)
				t.near(
					`{entry.name} Previous holds still from {entry.from} to {entry.to}`,
					previousArrow.AbsolutePosition.X,
					b,
					0.5
				)
				local label = row:FindFirstChild("Label")
				if label then
					t.check(`{entry.name} label text fits its reservation`, label.TextFits == true, {
						label.ContentText,
						label.TextBounds,
						label.AbsoluteSize,
					})
				end
			end
		end
	end
end)

local STEP_IDS = { "cart", "ship", "pay", "review" }

local function stepCells(t: any, indicator: any): { [string]: any }
	local out = {}
	for _, id in STEP_IDS do
		out[id] = t.find(indicator, "Step-" .. id)
	end
	return out
end

local function underlineCheck(t: any, where: string, indicator: any, id: string)
	local cells = stepCells(t, indicator)
	local cell, line, strip = cells[id], t.find(indicator, "Underline"), t.find(indicator, "Strip")
	t.check(`{where} {id} cell and underline found`, cell ~= nil and line ~= nil and strip ~= nil)
	if not (cell and line and strip) then
		return
	end
	local c, u, s = t.rect(cell), t.rect(line), t.rect(strip)
	t.check(`{where} the underline shows`, line.Visible == true)
	t.near(`{where} the underline starts under {id}`, u.x, c.x, 1)
	t.near(`{where} the underline spans {id}`, u.w, c.w, 1)
	t.near(`{where} the underline sits on the strip's bottom line under {id}`, u.b, s.b, 1)
	t.check(`{where} the underline sits inside {id}'s column`, u.y >= c.y - 0.5 and u.b <= c.b + 1, {
		underline = { u.x, u.y, u.w, u.h },
		cell = { c.x, c.y, c.w, c.h },
	})
end

add("steps-underline-follows-and-springs", { "post-step-02", "post-step-03", "post-step-07" }, function(t)
	local stage, built = scenario(t, "steps", { size = Vector2.new(1280, 720), reducedMotion = false })
	local indicator = t.find(stage, "Checkout")
	t.check("the Checkout indicator mounts", indicator ~= nil)
	if not indicator then
		return
	end
	t.check(
		"Checkout shows the row at 1280 px",
		indicator:GetAttribute("FacetForm") == "row",
		indicator:GetAttribute("FacetForm")
	)
	local cells = stepCells(t, indicator)
	local first = cells.cart and t.rect(cells.cart)
	for _, id in STEP_IDS do
		local cell = cells[id]
		t.check(`{id} cell found`, cell ~= nil)
		if cell and first then
			local r = t.rect(cell)
			t.near(`{id} shares the row's top edge`, r.y, first.y, 0.5)
			t.near(`{id} shares the row's height`, r.h, first.h, 0.5)
		end
	end
	for _, id in STEP_IDS do
		built.steps.select(id)
		t.settle(45)
		underlineCheck(t, "motion on", indicator, id)
	end
	local line = t.find(indicator, "Underline")
	if GuiService.ReducedMotionEnabled then
		t.note("not checked", "the spring: GuiService.ReducedMotionEnabled is on in this session")
	elseif line and cells.cart and cells.review then
		local start, finish = line.AbsolutePosition.X, cells.cart.AbsolutePosition.X
		built.steps.select("cart")
		local between = {}
		for _ = 1, 40 do
			t.settle(1)
			local x = line.AbsolutePosition.X
			if math.abs(x - start) > 1 and math.abs(x - finish) > 1 then
				between[math.floor(x + 0.5)] = true
			end
		end
		local count = 0
		for _ in between do
			count += 1
		end
		t.note("underline positions between review and cart", count)
		t.check("the underline passes through several positions on its way to Cart", count >= 3, count)
		t.settle(20)
		underlineCheck(t, "after the spring", indicator, "cart")
	end
	t.cleanup()
	local reducedStage, reducedBuilt = scenario(t, "steps", { size = Vector2.new(1280, 720) })
	local reduced = t.find(reducedStage, "Checkout")
	local reducedLine = reduced and t.find(reduced, "Underline")
	local reducedCells = reduced and stepCells(t, reduced)
	t.check("the reduced-motion copy mounts", reducedLine ~= nil and reducedCells ~= nil)
	if reducedLine and reducedCells and reducedCells.pay then
		reducedBuilt.steps.select("pay")
		t.settle(3)
		t.near(
			"under reduced motion the underline lands under Payment at once",
			reducedLine.AbsolutePosition.X,
			reducedCells.pay.AbsolutePosition.X,
			1
		)
		t.near(
			"under reduced motion the underline takes Payment's width at once",
			reducedLine.AbsoluteSize.X,
			reducedCells.pay.AbsoluteSize.X,
			1
		)
		reducedBuilt.steps.refuse()
		local x = reducedLine.AbsolutePosition.X
		reducedBuilt.steps.select("cart")
		t.settle(6)
		t.near("a refused selection leaves the underline where it was", reducedLine.AbsolutePosition.X, x, 0.5)
	end
end)

add("steps-number-marker-is-a-circle", { "post-step-05" }, function(t)
	local stage = scenario(t, "steps", { size = Vector2.new(1280, 720) })
	local indicator = t.find(stage, "Checkout")
	t.check("the Checkout indicator mounts", indicator ~= nil)
	if not indicator then
		return
	end
	t.note("preferred text size", t.environment.preferredTextSize)
	if t.environment.preferredTextSize ~= "Enum.PreferredTextSize.Largest" then
		t.note(
			"not checked",
			"the largest preferred text size: scripts cannot set it; this run checks the circle at the current size"
		)
	end
	local circles = 0
	for _, id in STEP_IDS do
		local cell = t.find(indicator, "Step-" .. id)
		local cue = cell and t.find(cell, "Cue")
		t.check(`{id} marker found`, cue ~= nil)
		if cue then
			local side = cue.AbsoluteSize
			t.note(`{id} marker size`, side)
			t.near(`{id} marker is square`, side.X, side.Y, 0.5)
			local circle = cue:FindFirstChild("Circle")
			local number = circle and circle:FindFirstChild("Number")
			if circle and circle.Visible and number then
				circles += 1
				t.near(`{id} circle is round`, circle.AbsoluteSize.X, circle.AbsoluteSize.Y, 0.5)
				local bounds = number.TextBounds
				t.note(`{id} cue declared`, {
					size = tostring(cue.Size),
					textSize = number.TextSize,
					styled = number:GetStyled("TextSize"),
					bounds = bounds,
					circle = circle.AbsoluteSize,
					parent = cue.Parent and cue.Parent.AbsoluteSize,
				})
				t.check(`{id} circle holds its number with room`, side.X >= math.max(bounds.X, bounds.Y) + 7.5, {
					side = side,
					bounds = bounds,
				})
			end
		end
	end
	t.check("at least one numbered circle shows", circles >= 1, circles)
end)

local function checkoutSteps(): { any }
	return {
		{ id = "cart", label = "Cart", state = "complete", navigable = true },
		{ id = "ship", label = "Shipping", description = "Address and speed", navigable = true },
		{ id = "pay", label = "Payment", description = "Card declined", state = "error", navigable = true },
		{ id = "review", label = "Review" },
	}
end

add("steps-form-fits-the-offer", { "post-step-10", "post-step-11" }, function(t)
	for _, entry in
		{ { size = Vector2.new(1280, 720), form = "row" }, { size = Vector2.new(390, 844), form = "summary" } }
	do
		local where = `{entry.size.X}x{entry.size.Y}`
		local stage = scenario(t, "steps", { size = entry.size })
		local checkout, compact = t.find(stage, "Checkout"), t.find(stage, "Compact")
		t.check(`{where} Checkout and Compact mount`, checkout ~= nil and compact ~= nil)
		if checkout and compact then
			local form = checkout:GetAttribute("FacetForm")
			t.note(`{where} Checkout form`, form)
			if entry.form == "row" then
				t.check(`{where} Checkout shows the row`, form == "row", form)
			end
			local strip, summary = t.find(checkout, "Strip"), t.find(checkout, "SummaryRow")
			if form == "row" then
				t.check(
					`{where} the row shows and the summary hides`,
					strip and strip.Visible and summary and not summary.Visible
				)
				for _, id in STEP_IDS do
					local cell = t.find(checkout, "Step-" .. id)
					local label = cell and t.find(cell, "Label")
					t.check(
						`{where} the row shows {id}'s label whole`,
						label ~= nil and label.TextFits == true,
						label
							and {
								label.ContentText,
								label.TextBounds,
								label.AbsoluteSize,
							}
					)
				end
			else
				t.check(
					`{where} the summary shows and the row hides`,
					strip and not strip.Visible and summary and summary.Visible
				)
			end
			t.note(`{where} Narrow copy form`, compact:GetAttribute("FacetForm"))
			if entry.form == "summary" then
				t.check("the Narrow copy shows the summary", compact:GetAttribute("FacetForm") == "summary")
				local menu = t.find(compact, "ShowSteps")
				t.check("the Narrow copy shows its Steps menu", menu ~= nil and t.visible(menu))
			end
			local section = checkout.Parent
			local forms = { checkout:GetAttribute("FacetForm"), compact:GetAttribute("FacetForm") }
			section.AutomaticSize = Enum.AutomaticSize.XY
			t.settle(12)
			t.check(
				`{where} a hugging section shows the same Checkout form`,
				checkout:GetAttribute("FacetForm") == forms[1],
				{
					forms[1],
					checkout:GetAttribute("FacetForm"),
				}
			)
			t.check(
				`{where} a hugging section shows the same Narrow form`,
				compact:GetAttribute("FacetForm") == forms[2],
				{
					forms[2],
					compact:GetAttribute("FacetForm"),
				}
			)
		end
		t.cleanup()
	end
	local width: any, probe: any
	local stage = t.mount(function(UI: any, Host: any, Compose: any)
		width = Compose.cell(900)
		probe = Compose.cell(900)
		local current = Compose.cell("ship")
		local children = {
			Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
		}
		for index, kind in { "Fill", "Hug" } do
			table.insert(
				children,
				Host.Frame({
					Name = kind .. "Holder",
					LayoutOrder = index,
					BackgroundTransparency = 1,
					Size = function(use)
						return UDim2.fromOffset(use(width), if kind == "Fill" then 120 else 0)
					end,
					AutomaticSize = if kind == "Fill" then Enum.AutomaticSize.None else Enum.AutomaticSize.XY,
					UI.StepIndicator({
						Name = kind,
						steps = checkoutSteps(),
						current = current,
						onSelect = function(id: string)
							current:set(id)
						end,
					}),
				})
			)
		end
		table.insert(
			children,
			Host.Frame({
				Name = "SizedHolder",
				LayoutOrder = 3,
				BackgroundTransparency = 1,
				Size = function(use)
					return UDim2.fromOffset(use(width), 120)
				end,
				UI.StepIndicator({
					Name = "Sized",
					sizing = "hug",
					steps = checkoutSteps(),
					current = current,
					onSelect = function(id: string)
						current:set(id)
					end,
				}),
			})
		)
		table.insert(
			children,
			Host.Frame({
				Name = "ProbeHolder",
				LayoutOrder = 4,
				BackgroundTransparency = 1,
				Size = function(use)
					return UDim2.fromOffset(use(probe), 120)
				end,
				UI.StepIndicator({
					Name = "Probe",
					steps = checkoutSteps(),
					current = current,
					onSelect = function(id: string)
						current:set(id)
					end,
				}),
			})
		)
		local props: { [any]: any } =
			{ Name = "Column", BackgroundTransparency = 1, Size = UDim2.fromOffset(1000, 700) }
		for _, child in children do
			table.insert(props, child)
		end
		return Host.Frame(props)
	end, { size = Vector2.new(1280, 720), frames = 12 })
	local fill, hug, sized, probed =
		t.find(stage, "Fill"), t.find(stage, "Hug"), t.find(stage, "Sized"), t.find(stage, "Probe")
	t.check("the fixture indicators mount", fill ~= nil and hug ~= nil and sized ~= nil and probed ~= nil)
	if not (fill and hug and sized and probed) then
		return
	end
	local seen = {}
	for _, w in { 900, 250, 900 } do
		width:set(w)
		t.settle(12)
		local settled = hug.Parent.AbsoluteSize.X
		probe:set(settled)
		t.settle(12)
		t.note(`{w} px forms`, {
			fill = fill:GetAttribute("FacetForm"),
			hug = hug:GetAttribute("FacetForm"),
			hugWidth = settled,
		})
		t.check(
			`{w} px: a hugging parent shows the form a filling one shows at the hug's settled width`,
			probed:GetAttribute("FacetForm") == hug:GetAttribute("FacetForm"),
			{ probe = probed:GetAttribute("FacetForm"), hug = hug:GetAttribute("FacetForm"), width = settled }
		)
		table.insert(seen, sized:GetAttribute("FacetForm"))
	end
	t.check(
		"hug sizing narrows to the summary and widens back to the row",
		seen[1] == "row" and seen[2] == "summary" and seen[3] == "row",
		seen
	)
end)

local function voteParts(t: any, stage: any): any
	local votes = t.find(stage, "Votes")
	if not votes then
		return nil
	end
	local track, past = votes:FindFirstChild("TrackVote"), votes:FindFirstChild("PastVote")
	return {
		votes = votes,
		track = track,
		trackUp = track and t.find(track, "Opt1"),
		trackDown = track and t.find(track, "Opt2"),
		pastUp = past and t.find(past, "Opt1"),
		pastDown = past and t.find(past, "Opt2"),
		chip = votes:FindFirstChild("VoteTag"),
	}
end

interactive(
	"vote-pad-reaches-and-proposes",
	{ "post-vote-03" },
	"afterRight: with the TrackVote Upvote side selected, press Right once; afterReturn: press Return once",
	function(t)
		local value = {}
		local stage, built = scenario(t, "selection_controls", { size = Vector2.new(1280, 720) })
		value.built = built
		value.parts = voteParts(t, stage)
		local parts = value.parts
		t.check("the TrackVote sides are found", parts ~= nil and parts.trackUp ~= nil and parts.trackDown ~= nil)
		if parts and parts.trackUp then
			GuiService.SelectedObject = parts.trackUp
		end
		t.check(
			"the Upvote side holds the selection",
			parts ~= nil and GuiService.SelectedObject == parts.trackUp,
			selectedName()
		)
		t.check("the vote starts at none", built.report().vote == "none", built.report().vote)
		t.note("gamepad", "D-pad Right moves the same native selection as the Right arrow key")
		t.note(
			"not checked",
			"ButtonA: the input tools send it as a keyboard key; Return runs the same native activation of the selected side"
		)
		return value
	end,
	{
		afterRight = function(t, value)
			t.check(
				"Right reaches the Downvote side",
				GuiService.SelectedObject == value.parts.trackDown,
				selectedName()
			)
		end,
		afterReturn = function(t, value)
			t.check(
				"one activation on Downvote proposes down once",
				value.built.report().vote == "down",
				value.built.report().vote
			)
			GuiService.SelectedObject = nil
		end,
	}
)

add("vote-targets-separate", { "post-vote-08" }, function(t)
	for _, size in { Vector2.new(1280, 720), Vector2.new(390, 844) } do
		local where = `{size.X}x{size.Y}`
		local stage = scenario(t, "selection_controls", { size = size })
		local parts = voteParts(t, stage)
		t.check(
			`{where} the vote row parts are found`,
			parts ~= nil
				and parts.trackUp ~= nil
				and parts.trackDown ~= nil
				and parts.pastUp ~= nil
				and parts.pastDown ~= nil
				and parts.chip ~= nil
		)
		if parts and parts.trackUp and parts.trackDown and parts.pastUp and parts.pastDown and parts.chip then
			local named = {
				{ name = "TrackVote up", rect = t.rect(parts.trackUp) },
				{ name = "TrackVote down", rect = t.rect(parts.trackDown) },
				{ name = "PastVote up", rect = t.rect(parts.pastUp) },
				{ name = "PastVote down", rect = t.rect(parts.pastDown) },
				{ name = "Rally chip", rect = t.rect(parts.chip) },
			}
			local crossed = crossings(named)
			t.check(`{where} no two vote targets overlap`, #crossed == 0, crossed)
			for index = 1, 2 do
				local r = named[index].rect
				t.check(`{where} {named[index].name} is at least 44 px`, r.w >= 43.5 and r.h >= 43.5, { r.w, r.h })
			end
			local summary = parts.track and parts.track:FindFirstChild("Summary")
			t.check(
				`{where} the TrackVote summary shows`,
				summary ~= nil and summary.Visible and summary.ContentText ~= ""
			)
			if summary then
				t.note(`{where} summary fits`, { summary.TextFits, summary.ContentText })
			end
			local found = t.offenders(parts.votes, stage)
			t.note(`{where} vote row lateral offenders`, found.lateral)
		end
		t.cleanup()
	end
end)

local function cardsMount(t: any, reducedMotion: boolean?): (any, any, any)
	local stage, built =
		scenario(t, "cards", { size = Vector2.new(1280, 720), reducedMotion = reducedMotion, frames = 30 })
	local games = t.find(stage, "Games")
	if games then
		t.stable(games)
		t.settle(10)
	end
	return stage, built, games
end

local function cardIn(t: any, games: any, key: string): any
	local cell = games and games:FindFirstChild("Items") and t.find(games:FindFirstChild("Items"), key)
	if not cell then
		return nil
	end
	local card = t.find(cell, "Card")
	local more = card and t.find(card, "More")
	return {
		cell = cell,
		card = card,
		hit = t.find(cell, "RowHit"),
		body = card and card:FindFirstChild("Body"),
		reveal = card and card:FindFirstChild("Reveal"),
		primary = card and t.find(card, "Primary"),
		more = more and t.find(more, "Trigger"),
	}
end

local function sameRect(a: any, b: any): boolean
	return math.abs(a.x - b.x) <= 0.5
		and math.abs(a.y - b.y) <= 0.5
		and math.abs(a.w - b.w) <= 0.5
		and math.abs(a.h - b.h) <= 0.5
end

interactive(
	"card-hover-reveals-inside-the-envelope",
	{ "post-card-07", "post-card-08", "post-card-17" },
	"afterHover: move the mouse without clicking to the point noted as 'hover point'",
	function(t)
		local value = {}
		local _, built, games = cardsMount(t)
		t.check("the Games grid mounts", games ~= nil)
		if not games then
			return value
		end
		value.built = built
		value.parts = {}
		value.rects = {}
		for _, key in { "g1", "g2", "g3", "g6" } do
			local parts = cardIn(t, games, key)
			value.parts[key] = parts
			t.check(`{key} card found`, parts ~= nil and parts.card ~= nil)
			if parts and parts.card then
				value.rects[key] = t.rect(parts.card)
			end
		end
		local target = value.parts.g2
		if target and target.card then
			t.check(
				"g2 is not revealed at rest",
				target.card:GetAttribute("FacetRevealed") == false,
				target.card:GetAttribute("FacetRevealed")
			)
			local controls = built.controls.g2
			local extent = controls and controls.revealExtent and controls.revealExtent:peek()
			t.check("g2 has a revealExtent", extent ~= nil)
			if extent then
				t.near("revealExtent.body equals the card height at rest", extent.body, target.card.AbsoluteSize.Y, 0.5)
			end
			local body = t.rect(target.body)
			local point = screenPoint(body.x + body.w / 2, body.y + body.h / 3)
			t.note("hover point", point)
		end
		t.note(
			"motion",
			"reduced motion is on in this fixture, so the lift scale stays 1 and rectangles compare exactly"
		)
		t.note("not checked", "the envelope at the largest text size: scripts cannot set the preferred text size")
		return value
	end,
	{
		afterHover = function(t, value)
			local target = value.parts and value.parts.g2
			if not (target and target.card) then
				t.check("g2 card found", false)
				return
			end
			t.settle(10)
			t.check("the hovered card reports hover", target.card:GetAttribute("FacetHovered") == true)
			t.check("the hovered card reveals", target.card:GetAttribute("FacetRevealed") == true)
			t.check(
				"the plate paints",
				target.reveal ~= nil and target.reveal.GroupTransparency < 0.01,
				target.reveal and target.reveal.GroupTransparency
			)
			local card, body = t.rect(target.card), t.rect(target.body)
			for _, pair in { { "Play", target.primary }, { "More", target.more } } do
				local node = pair[2]
				t.check(`{pair[1]} found`, node ~= nil)
				if node then
					local r = t.rect(node)
					t.inside(`{pair[1]} sits inside the card`, r, card, 0.5)
					t.check(`{pair[1]} sits below the body`, r.y >= body.b - 0.5, { action = r.y, body = body.b })
				end
			end
			for key, before in value.rects do
				local parts = value.parts[key]
				t.check(`{key} did not move or resize`, sameRect(t.rect(parts.card), before), {
					before = { before.x, before.y, before.w, before.h },
					after = t.rect(parts.card),
				})
			end
			local extent = value.built.controls.g2.revealExtent:peek()
			t.near("revealExtent.body still equals the card height", extent.body, target.card.AbsoluteSize.Y, 0.5)
		end,
	}
)

interactive(
	"card-keys-enter-and-stay-inside",
	{ "post-card-11", "post-card-23" },
	"afterReturn: with the g1 cell selected, press Return once; afterRight: press Right once; afterRightAgain: press Right once; afterDown: press Down once",
	function(t)
		local value = {}
		local _, built, games = cardsMount(t)
		value.built = built
		value.parts = games and cardIn(t, games, "g1")
		local parts = value.parts
		t.check(
			"the g1 cell, Play and More are found",
			parts ~= nil and parts.hit ~= nil and parts.primary ~= nil and parts.more ~= nil
		)
		if parts and parts.hit then
			GuiService.SelectedObject = parts.hit
		end
		t.check("the g1 cell holds the selection", selectedName() == "RowHit", selectedName())
		t.note("gamepad", "D-pad Right and Down move the same native selection as the arrow keys")
		t.note(
			"not checked",
			"ButtonA, ButtonB and ButtonY: the input tools cannot send them; Return is the same native activation as A, and leaveActions is the function that B runs"
		)
		return value
	end,
	{
		afterReturn = function(t, value)
			local parts = value.parts
			t.check("Return on the cell enters Play", GuiService.SelectedObject == parts.primary, selectedName())
			t.check("the card reports entered", parts.card:GetAttribute("FacetEntered") == true)
		end,
		afterRight = function(t, value)
			t.check("Right moves to More", GuiService.SelectedObject == value.parts.more, selectedName())
		end,
		afterRightAgain = function(t, value)
			t.check("Right again stays on More", GuiService.SelectedObject == value.parts.more, selectedName())
		end,
		afterDown = function(t, value)
			local parts = value.parts
			t.check("Down stays inside the card", within(GuiService.SelectedObject, parts.card), selectedName())
			local controls = value.built.controls.g1
			if controls and controls.leaveActions then
				controls.leaveActions()
				t.settle(6)
				t.check(
					"leaving the actions returns to the cell",
					GuiService.SelectedObject == parts.hit,
					selectedName()
				)
				t.check("the cell stays revealed", parts.card:GetAttribute("FacetRevealed") == true)
			end
			GuiService.SelectedObject = nil
		end,
	}
)

add("card-grid-lines-and-corners", { "post-card-27", "post-card-28" }, function(t)
	local _, _, games = cardsMount(t, false)
	t.check("the Games grid mounts", games ~= nil)
	if not games then
		return
	end
	local items = games:FindFirstChild("Items")
	local lines = 0
	if items then
		for _, cell in items:GetDescendants() do
			if cell:IsA("GuiObject") and string.match(cell.Name, "^g%d+$") and cell:FindFirstChild("Content") then
				local card = t.find(cell, "Card")
				local plate = card and card:FindFirstChild("Reveal")
				if card and plate then
					lines += 1
					t.inside(`{cell.Name} card inside its cell`, card, cell, 0.5)
					t.inside(`{cell.Name} plate inside its cell`, plate, cell, 0.5)
				end
			end
		end
	end
	t.check("mounted cells were checked", lines >= 4, lines)
	if GuiService.ReducedMotionEnabled then
		t.note("motion", "GuiService.ReducedMotionEnabled is on, so the lift stays at scale 1")
	end
	local function corner(key: string)
		local parts = cardIn(t, games, key)
		t.check(`{key} cell found`, parts ~= nil and parts.hit ~= nil and parts.card ~= nil)
		if not (parts and parts.hit and parts.card) then
			return
		end
		GuiService.SelectedObject = parts.hit
		t.settle(40)
		local clip = windowRect(games)
		local hit, card = t.rect(parts.hit), t.rect(parts.card)
		t.note(`{key} lift scale`, parts.card.AbsoluteSize.X / math.max(1, parts.cell.AbsoluteSize.X))
		t.check(`{key} selected card is engaged`, parts.card:GetAttribute("FacetEngaged") == true)
		t.inside(`{key} lifted card inside the grid clip`, card, clip, 0.5)
		t.inside(`{key} selected cell ring box inside the grid clip`, hit, clip, 0.5)
		t.note(`{key} margins to the clip`, {
			left = math.min(hit.x, card.x) - clip.x,
			top = math.min(hit.y, card.y) - clip.y,
			right = clip.r - math.max(hit.r, card.r),
			bottom = clip.b - math.max(hit.b, card.b),
		})
		GuiService.SelectedObject = nil
		t.settle(20)
	end
	corner("g1")
	corner("g4")
	local passes = 0
	for pass = 1, 30 do
		passes = pass
		local target = math.max(0, games.AbsoluteCanvasSize.Y - games.AbsoluteWindowSize.Y)
		games.CanvasPosition = Vector2.new(0, target)
		t.settle(8)
		local last = cardIn(t, games, "g60")
		if
			last
			and last.card
			and math.abs(games.CanvasPosition.Y - (games.AbsoluteCanvasSize.Y - games.AbsoluteWindowSize.Y)) <= 1
		then
			break
		end
	end
	t.settle(20)
	t.note("canvas at the end", { position = games.CanvasPosition, canvas = games.AbsoluteCanvasSize, passes = passes })
	corner("g57")
	corner("g60")
	t.note(
		"ring",
		"the engine draws the selection ring around RowHit; its outset is not readable, so the margins are noted"
	)
end)

local function menuItems(count: number, prefix: string): { any }
	local list = {}
	for index = 1, count do
		table.insert(list, { id = `{prefix}{index}`, label = `Row {index}`, onSelect = function() end })
	end
	return list
end

local PLACEMENTS = {
	{ name = "Trailing", edge = "trailing", x = 200, y = 300, expect = "trailing" },
	{ name = "Top", edge = "top", x = 600, y = 400, expect = "top" },
	{ name = "TrailingFlip", edge = "trailing", x = 1170, y = 300, expect = "leading" },
	{ name = "TopFlip", edge = "top", x = 600, y = 12, expect = "bottom" },
}

add("menu-edge-and-align-place-the-panel", { "post-menu-02" }, function(t)
	local cells = {}
	local stage = t.mount(function(UI: any, Host: any, Compose: any)
		local props: { [any]: any } = { Name = "Board", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }
		for _, entry in PLACEMENTS do
			local open = Compose.cell(false)
			cells[entry.name] = open
			table.insert(
				props,
				UI.Menu({
					Name = entry.name,
					label = entry.name,
					items = menuItems(3, entry.name),
					edge = entry.edge,
					align = "center",
					isPresented = open,
					Position = UDim2.fromOffset(entry.x, entry.y),
				})
			)
		end
		return Host.Frame(props)
	end, { size = Vector2.new(1280, 720), frames = 12 })
	for _, entry in PLACEMENTS do
		local menu = t.find(stage, entry.name)
		local trigger = menu and menu:FindFirstChild("Trigger")
		t.check(`{entry.name} trigger found`, trigger ~= nil)
		if trigger then
			cells[entry.name]:set(true)
			t.settle(20)
			local panel = visibleNamed(t, stage, "MenuPanel")
			t.check(`{entry.name} panel opens`, panel ~= nil)
			if panel then
				t.stable(panel)
				local p, g = t.rect(panel), t.rect(trigger)
				local pc, gc = centre(p), centre(g)
				t.note(`{entry.name} rects`, { panel = { p.x, p.y, p.w, p.h }, trigger = { g.x, g.y, g.w, g.h } })
				if entry.expect == "trailing" then
					t.near(`{entry.name} opens beside the trigger's trailing edge`, p.x, g.r + 4, 1.5)
					t.near(`{entry.name} is vertically centred on the trigger`, pc.Y, gc.Y, 1.5)
				elseif entry.expect == "leading" then
					t.near(`{entry.name} flips to the leading side near the screen edge`, p.r, g.x - 4, 1.5)
					t.near(`{entry.name} stays vertically centred on the trigger`, pc.Y, gc.Y, 1.5)
				elseif entry.expect == "top" then
					t.near(`{entry.name} opens above the trigger`, p.b, g.y - 4, 1.5)
					t.near(`{entry.name} is horizontally centred on the trigger`, pc.X, gc.X, 1.5)
				else
					t.near(`{entry.name} flips below the trigger near the top edge`, p.y, g.b + 4, 1.5)
					t.near(`{entry.name} stays horizontally centred on the trigger`, pc.X, gc.X, 1.5)
				end
				t.inside(`{entry.name} panel inside the screen`, p, stage, 1)
			end
			cells[entry.name]:set(false)
			t.settle(20)
		end
	end
	GuiService.SelectedObject = nil
end)

add("menu-rows-floor-and-lead", { "post-menu-05" }, function(t)
	local open: any
	local stage = t.mount(function(UI: any, Host: any, Compose: any)
		open = Compose.cell(false)
		local list: { any } = {
			{ id = "all", label = "All tracks", badge = 3, onSelect = function() end },
			{ id = "fav", label = "Favourites", shortcutLabel = "Ctrl+F", onSelect = function() end },
			{ id = "recent", label = "Recent", meta = "12 tracks", onSelect = function() end },
		}
		for index = 1, 4 do
			table.insert(list, { id = `p{index}`, label = `Track {index}`, onSelect = function() end })
		end
		return Host.Frame "Board" {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			UI.Menu({
				Name = "Bounded",
				label = "Tracks",
				items = list,
				maxHeight = 260,
				isPresented = open,
				Position = UDim2.fromOffset(200, 100),
			}),
		}
	end, { size = Vector2.new(1280, 720), frames = 12 })
	open:set(true)
	t.settle(20)
	local panel = visibleNamed(t, stage, "MenuPanel")
	t.check("the bounded menu opens", panel ~= nil)
	if not panel then
		return
	end
	t.stable(panel)
	t.check("the panel honours maxHeight", panel.AbsoluteSize.Y <= 260.5, panel.AbsoluteSize.Y)
	local named, lead = {}, nil
	for _, id in { "all", "fav", "recent", "p1", "p2", "p3", "p4" } do
		local row = buttonNamed(panel, id)
		t.check(`{id} row found`, row ~= nil)
		if row then
			local r = t.rect(row)
			table.insert(named, { name = id, rect = r })
			t.check(`{id} row is at least 44 px tall`, r.h >= 43.5, r.h)
			local title = t.find(row, "Title")
			if title then
				local x = title.AbsolutePosition.X - row.AbsolutePosition.X
				lead = lead or x
				t.near(`{id} label starts where the badge row's label starts`, x, lead, 0.5)
			else
				t.check(`{id} has a Title label`, false)
			end
		end
	end
	local crossed = crossings(named)
	t.check("no two rows overlap", #crossed == 0, crossed)
	open:set(false)
	t.settle(10)
	GuiService.SelectedObject = nil
end)

interactive(
	"menu-lands-on-selected-and-walks-bounded",
	{ "post-menu-07", "post-menu-08" },
	"afterDown: with the first row of the bounded menu selected, press Down 11 times",
	function(t)
		local value = {}
		local yearOpen: any, boundedOpen: any
		local stage = t.mount(function(UI: any, Host: any, Compose: any)
			yearOpen, boundedOpen = Compose.cell(false), Compose.cell(false)
			local year = Compose.cell(2026)
			local years = {}
			for item = 1926, 2126 do
				table.insert(years, { id = `y{item}`, label = tostring(item), selected = year, value = item })
			end
			return Host.Frame "Board" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				UI.Menu({
					Name = "Year",
					label = "Year",
					items = years,
					isPresented = yearOpen,
					Position = UDim2.fromOffset(200, 60),
				}),
				UI.Menu({
					Name = "Bounded",
					label = "Options",
					items = menuItems(12, "r"),
					maxHeight = 200,
					isPresented = boundedOpen,
					Position = UDim2.fromOffset(700, 60),
				}),
			}
		end, { size = Vector2.new(1280, 720), frames = 12 })
		local yearTrigger = t.find(stage, "Year") and t.find(stage, "Year"):FindFirstChild("Trigger")
		local boundedTrigger = t.find(stage, "Bounded") and t.find(stage, "Bounded"):FindFirstChild("Trigger")
		t.check("both triggers found", yearTrigger ~= nil and boundedTrigger ~= nil)
		if not (yearTrigger and boundedTrigger) then
			return value
		end
		GuiService.SelectedObject = yearTrigger
		yearOpen:set(true)
		t.settle(30)
		local panel = visibleNamed(t, stage, "MenuPanel")
		t.check("the year menu opens", panel ~= nil)
		if panel then
			t.stable(panel)
			t.settle(6)
			t.check("the year menu opens with 2026 selected", selectedName() == "y2026", selectedName())
			local row = buttonNamed(panel, "y2026")
			if row then
				local w = windowRect(panel)
				local rowCentre = row.AbsolutePosition.Y + row.AbsoluteSize.Y / 2
				t.near("2026 is centred in the scrolled list", rowCentre, w.y + w.h / 2, 2)
				t.inside("2026 is inside the list window", t.rect(row), w, 0.5)
			else
				t.check("the 2026 row exists", false)
			end
		end
		yearOpen:set(false)
		t.settle(20)
		GuiService.SelectedObject = boundedTrigger
		boundedOpen:set(true)
		t.settle(30)
		value.panel = visibleNamed(t, stage, "MenuPanel")
		t.check("the bounded menu opens", value.panel ~= nil)
		if value.panel then
			t.stable(value.panel)
			t.check("maxHeight bounds the whole panel", value.panel.AbsoluteSize.Y <= 200.5, value.panel.AbsoluteSize.Y)
			t.note("selection at open", selectedName())
			if selectedName() ~= "r1" then
				local first = buttonNamed(value.panel, "r1")
				if first then
					GuiService.SelectedObject = first
				end
			end
			t.check("the first row holds the selection", selectedName() == "r1", selectedName())
		end
		value.boundedOpen = boundedOpen
		return value
	end,
	{
		afterDown = function(t, value)
			local panel = value.panel
			t.settle(10)
			t.check("Down walks to the last row", selectedName() == "r12", selectedName())
			if panel then
				local last = buttonNamed(panel, "r12")
				if last then
					t.inside("the last row scrolled into view", t.rect(last), windowRect(panel), 0.5)
				end
				t.check("the list scrolled", panel.CanvasPosition.Y > 0, panel.CanvasPosition)
			end
			value.boundedOpen:set(false)
			GuiService.SelectedObject = nil
		end,
	}
)

local CATEGORIES: { [string]: string } =
	{ inputs = "Inputs", actions = "Actions", indicators = "Status", navigation = "Menus" }
local INNER = { "basics", "writing", "leaves", "choices", "pickers" }

add("category-bar-fits-phone-words", { "post-showcase-01", "post-showcase-04" }, function(t)
	local caption = t.themes[1].package.metrics.typography.caption.size
	t.note("caption size", caption)
	local viewport = t.device({
		device = "iphone_14",
		input = Enum.PreferredInput.Touch,
		orientation = Enum.ScreenOrientation.Portrait,
	})
	for _ = 1, 60 do
		if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
			break
		end
		t.settle(1)
	end
	t.note("device viewport", viewport)
	t.check(
		"the phone device reports touch as the preferred input",
		UserInputService.PreferredInput == Enum.PreferredInput.Touch,
		tostring(UserInputService.PreferredInput)
	)
	local screen = t.Facet.Compose.cell(Vector2.new(320, 568))
	local stage = scenario(t, "all_controls", { size = screen, frames = 30 })
	for _, size in { Vector2.new(320, 568), Vector2.new(389, 844) } do
		local where = `{size.X} px`
		screen:set(size)
		t.settle(30)
		t.note(`{where} preferred input`, tostring(UserInputService.PreferredInput))
		local categories = t.find(stage, "Categories")
		t.check(`{where} the category TabView mounts`, categories ~= nil)
		if categories then
			local stageRect = t.rect(stage)
			for id, word in CATEGORIES do
				local button = buttonNamed(categories, id)
				t.check(`{where} {word} tab found`, button ~= nil and t.visible(button))
				if button then
					local label = button:FindFirstChild("Label")
					local text = if label and label:IsA("TextLabel") then label else button
					local ok, styled = pcall(function()
						return text:GetStyled("TextSize")
					end)
					local textSize = if ok and type(styled) == "number" then styled else text.TextSize
					local r = t.rect(button)
					t.check(
						`{where} {word} sits in the bottom bar`,
						r.y > stageRect.y + stageRect.h * 0.6,
						{ r.y, stageRect.h }
					)
					t.check(
						`{where} {word} tab is inside the screen`,
						r.x >= stageRect.x - 0.5 and r.r <= stageRect.r + 0.5,
						{
							r.x,
							r.r,
						}
					)
					t.check(`{where} {word} shows whole`, text.ContentText == word and text.TextFits == true, {
						text.ContentText,
						text.TextFits,
						text.TextBounds,
						text.AbsoluteSize,
					})
					t.check(`{where} {word} text is at least the caption size`, textSize >= caption - 0.01, textSize)
				end
			end
			for _, id in INNER do
				local button = buttonNamed(categories, id)
				if button and t.visible(button) then
					local label = button:FindFirstChild("Label")
					local text = if label and label:IsA("TextLabel") then label else button
					t.check(
						`{where} inner tab {id} widens to its words`,
						text.TextFits == true and text.ContentText ~= "",
						{
							text.ContentText,
							text.TextBounds,
							button.AbsoluteSize,
						}
					)
				else
					t.note(`{where} inner tab {id}`, "not visible")
				end
			end
		end
	end
	t.note(
		"scope",
		"the all-controls scenario mounts standalone in a stage of each phone size on the iphone_14 device for touch; inside the gallery shell its category bar is nested and uses the top bar"
	)
end)

interactive(
	"choices-vote-row-inside-the-page",
	{ "post-showcase-03" },
	"afterReturn: with the Choices tab selected, press Return once",
	function(t)
		local value = {}
		local stage = t.gallery({ size = Vector2.new(1542, 1067), demo = "all-controls" })
		value.stage = stage
		t.settle(20)
		local tab = buttonNamed(stage, "choices")
		t.check("the Choices tab is found", tab ~= nil and t.visible(tab))
		if tab then
			GuiService.SelectedObject = tab
		end
		t.check("the Choices tab holds the selection", selectedName() == "choices", selectedName())
		t.note("preferred input", tostring(UserInputService.PreferredInput))
		return value
	end,
	{
		afterReturn = function(t, value)
			t.settle(30)
			local page = visibleNamed(t, value.stage, "SelectionControls")
			t.check("the Choices page shows", page ~= nil)
			if not page then
				GuiService.SelectedObject = nil
				return
			end
			local scroller = page:FindFirstChild("Content")
			local votes = scroller and t.find(scroller, "Votes")
			t.check("the page scroller and the Vote row are found", scroller ~= nil and votes ~= nil)
			if scroller and votes then
				local window = windowRect(scroller)
				t.inside("the page scroller is inside the window", window, value.stage, 1)
				scroller.CanvasPosition =
					Vector2.new(0, math.max(0, scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y))
				t.settle(10)
				t.inside("the Vote row is inside the page scroller at its end", t.rect(votes), windowRect(scroller), 1)
				t.note("scroller window", window)
			end
			GuiService.SelectedObject = nil
		end,
	}
)

add("outline-section-closes-up", { "post-lab-06" }, function(t)
	local open: any
	local stage = t.mount(function(UI: any, Host: any, Compose: any)
		open = Compose.cell(true)
		local props: { [any]: any } = {
			Name = "Sc",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(400, 300),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
		}
		for index = 1, 2 do
			table.insert(
				props,
				UI.DisclosureGroup({
					Name = "G" .. index,
					LayoutOrder = index,
					label = "Group " .. index,
					expanded = if index == 1 then open else Compose.cell(true),
					content = function()
						local rows: { [any]: any } = {
							Name = "Rows",
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
						}
						for row = 1, 8 do
							table.insert(rows, UI.Button({ Name = `B{row}`, label = `Row {row}`, LayoutOrder = row }))
						end
						return Host.Frame(rows)
					end,
				})
			)
		end
		return Host.ScrollingFrame(props)
	end, { size = Vector2.new(600, 500), frames = 12 })
	local scroller, first, second = t.find(stage, "Sc"), t.find(stage, "G1"), t.find(stage, "G2")
	t.check("the scroller and both groups mount", scroller ~= nil and first ~= nil and second ~= nil)
	if not (scroller and first and second) then
		return
	end
	local function measure(): { number }
		return { second.AbsolutePosition.Y, scroller.AbsoluteCanvasSize.Y, first.AbsoluteSize.Y }
	end
	local open1 = measure()
	open:set(false)
	t.settle(6)
	t.stable(second)
	local closed = measure()
	local moved, shrank, lost = open1[1] - closed[1], open1[2] - closed[2], open1[3] - closed[3]
	t.note("second group moved up, canvas shrank, first group lost", { moved, shrank, lost })
	t.check("the second group moves up", moved > 40, moved)
	t.near("the canvas shrinks by the same amount", shrank, moved, 1)
	t.near("the first group loses that height", lost, moved, 1)
	open:set(true)
	t.settle(6)
	t.stable(second)
	local reopened = measure()
	t.near("expanding restores the second group", reopened[1], open1[1], 1)
	t.near("expanding restores the canvas", reopened[2], open1[2], 1)
end)

local ALIGN_OFFSET = { start = 0, center = 16, ["end"] = 32 }

add("containers-recipes-draw-as-described", {
	"post-recipes-01",
	"post-recipes-02",
	"post-recipes-03",
	"post-recipes-04",
	"post-recipes-05",
	"post-recipes-06",
	"post-recipes-07",
	"post-recipes-08",
	"post-recipes-09",
}, function(t)
	local stage, built = scenario(t, "containers", { size = Vector2.new(1280, 720) })
	local function node(name: string, root: any?): any
		local found = t.find(root or stage, name)
		t.check(`{name} found`, found ~= nil)
		return found
	end
	local group, activate = node("Group"), node("Activate")
	if group and activate then
		local g, a = t.rect(group), t.rect(activate)
		t.near("01 the group insets its button by 8 on the left", a.x - g.x, 8, 1)
		t.near("01 the group insets its button by 8 on the top", a.y - g.y, 8, 1)
		t.near("01 the group insets its button by 8 on the right", g.r - a.r, 8, 1)
		t.near("01 the group insets its button by 8 on the bottom", g.b - a.b, 8, 1)
		built.steps.disable()
		t.settle(4)
		GuiService.SelectedObject = activate
		t.settle(2)
		local refused = GuiService.SelectedObject ~= activate
		t.note("01 disabled button state", { state = tostring(activate.GuiState), refused = refused })
		t.check(
			"01 disabling the group disables its button by inheritance",
			activate.GuiState == Enum.GuiState.NonInteractable or refused,
			tostring(activate.GuiState)
		)
		GuiService.SelectedObject = nil
	end
	local sizing = node("Sizing")
	if sizing then
		local fixed, quarter, fill = node("Fixed", sizing), node("Quarter", sizing), node("Fill", sizing)
		if fixed and quarter and fill then
			local s = t.rect(sizing)
			t.near("02 the fixed tile is 64 wide", fixed.AbsoluteSize.X, 64, 0.5)
			t.near("02 the quarter tile is a quarter of the row", quarter.AbsoluteSize.X, s.w * 0.25, 1.5)
			t.near("02 the fill tile reaches the row's end", t.rect(fill).r, s.r, 1)
			t.check("02 the fill tile has room", fill.AbsoluteSize.X > 16, fill.AbsoluteSize.X)
		end
	end
	for index, want in { Vector2.new(96, 96), Vector2.new(96, 54), Vector2.new(54, 96) } do
		local offer = node(`Offer{index}`)
		local subject = offer and node("Subject", offer)
		if offer and subject then
			local o, s = t.rect(offer), t.rect(subject)
			t.near(`03 offer {index} is 96 wide`, o.w, 96, 0.5)
			t.near(`03 offer {index} is 96 tall`, o.h, 96, 0.5)
			t.near(`03 subject {index} width`, s.w, want.X, 1)
			t.near(`03 subject {index} height`, s.h, want.Y, 1)
			t.inside(`03 subject {index} fits its offer`, s, o, 0.5)
			local a, b = centre(s), centre(o)
			t.check(`03 subject {index} is centred`, math.abs(a.X - b.X) <= 1 and math.abs(a.Y - b.Y) <= 1, { a, b })
		end
	end
	local lefts = {}
	for index, scale in { 0.75, 1, 1.5 } do
		local holder = node(`Scale{index}`)
		local tileNode = holder and node("Tile", holder)
		if holder and tileNode then
			t.near(`04 tile {index} paints at scale {scale}`, tileNode.AbsoluteSize.X, 32 * scale, 1)
			lefts[index] = holder.AbsolutePosition.X
		end
	end
	if lefts[1] and lefts[2] and lefts[3] then
		t.note("04 slot left edges", lefts)
		t.near("04 the scaled tiles keep evenly spaced slots", lefts[3] - lefts[2], lefts[2] - lefts[1], 1)
	end
	local fadeSize: any
	for index = 1, 5 do
		local fade = node(`Fade{index}`)
		if fade then
			fadeSize = fadeSize or fade.AbsoluteSize
			t.near(`05 fade {index} keeps the group's width`, fade.AbsoluteSize.X, fadeSize.X, 0.5)
			t.near(`05 fade {index} keeps the group's height`, fade.AbsoluteSize.Y, fadeSize.Y, 0.5)
		end
	end
	local kept, removed, after = node("Kept"), node("Removed"), node("After")
	if kept and removed and after then
		local k, rm, a = t.rect(kept), t.rect(removed), t.rect(after)
		local gap = rm.x - k.r
		built.steps.hide()
		t.settle(6)
		t.check(
			"05 the transparent group keeps its space",
			sameRect(t.rect(kept), k),
			{ before = k, after = t.rect(kept) }
		)
		t.near("05 the removed node gives its space back", after.AbsolutePosition.X, a.x - rm.w - gap, 1)
	end
	for _, v in { "start", "center", "end" } do
		for _, h in { "start", "center", "end" } do
			local spot = node(`{h}-{v}`)
			local dot = spot and node("Dot", spot)
			if spot and dot then
				local s, d = t.rect(spot), t.rect(dot)
				t.near(`06 {h}-{v} dot x`, d.x - s.x, ALIGN_OFFSET[h], 1)
				t.near(`06 {h}-{v} dot y`, d.y - s.y, ALIGN_OFFSET[v], 1)
			end
		end
	end
	local gapRow = node("Gap")
	if gapRow then
		local a, b, c = node("A", gapRow), node("B", gapRow), node("C", gapRow)
		if a and b and c then
			local ra, rb, rc = t.rect(a), t.rect(b), t.rect(c)
			t.check("07 the gap spaces siblings", rb.x - ra.r > 4, rb.x - ra.r)
			t.near("07 the gaps are equal", rc.x - rb.r, rb.x - ra.r, 0.5)
			t.near("07 the gap does not inset the first sibling", ra.x, t.rect(gapRow).x, 0.5)
		end
	end
	local padded = node("Padding")
	local inset = padded and node("Inset", padded)
	if padded and inset then
		local p, i = t.rect(padded), t.rect(inset)
		t.near("07 the left padding moves the child 32", i.x - p.x, 32, 1)
		t.near("07 the top padding moves the child 8", i.y - p.y, 8, 1)
	end
	local wrap = node("Wrap")
	if wrap then
		local one, two, three = node("One", wrap), node("Two", wrap), node("Three", wrap)
		if one and two and three then
			t.near("08 wrap keeps One and Two on the first line", two.AbsolutePosition.Y, one.AbsolutePosition.Y, 0.5)
			t.check("08 wrap moves Three to a second line", three.AbsolutePosition.Y > one.AbsolutePosition.Y + 10, {
				one.AbsolutePosition.Y,
				three.AbsolutePosition.Y,
			})
			t.inside("08 wrapped children stay inside 180 px", t.rect(three), t.rect(wrap), 0.5)
		end
	end
	local noWrap = node("NoWrap")
	if noWrap then
		local one, three = node("One", noWrap), node("Three", noWrap)
		local outer = noWrap:FindFirstAncestorWhichIsA("ScrollingFrame")
		if outer then
			local offset = noWrap.AbsolutePosition.Y - outer.AbsolutePosition.Y + outer.CanvasPosition.Y - 100
			outer.CanvasPosition = Vector2.new(outer.CanvasPosition.X, math.max(0, offset))
			t.settle(6)
		end
		if one and three then
			local w = windowRect(noWrap)
			t.near("08 no wrap keeps one line", three.AbsolutePosition.Y, one.AbsolutePosition.Y, 0.5)
			t.check("08 no wrap overruns 180 px", t.rect(three).r > w.r + 1, { t.rect(three).r, w.r })
			local seen = t.clipped(three)
			t.check("08 the scroller clips at its edge", seen ~= nil and seen.r <= w.r + 0.5, seen)
		end
	end
	local styled = node("Styled")
	if styled then
		t.near("09 the plate is 120 wide", styled.AbsoluteSize.X, 120, 0.5)
		t.near("09 the plate is 56 tall", styled.AbsoluteSize.Y, 56, 0.5)
		local corner = styled:FindFirstChildWhichIsA("UICorner")
		local stroke = styled:FindFirstChildWhichIsA("UIStroke")
		t.check("09 the plate is rounded 16", corner ~= nil and corner.CornerRadius.Offset == 16)
		t.check("09 the plate has a 2 px stroke", stroke ~= nil and stroke.Thickness == 2)
		t.check("09 the plate has a shadow", styled:FindFirstChild("Shadow") ~= nil)
		t.note("09", "a UICorner rounds every corner with one radius; per-corner radii are not native")
	end
	t.cleanup()
	local stageTwo = t.mount(function(UI: any, Host: any)
		return Host.Frame "Fixtures" {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(600, 400),
			Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
			UI.HStack({
				Name = "FixedRow",
				LayoutOrder = 1,
				width = 100,
				height = 24,
				Host.Frame({ Name = "Wide", Size = UDim2.fromOffset(160, 24), BorderSizePixel = 0 }),
			}),
			UI.ZStack({
				Name = "HugZ",
				LayoutOrder = 2,
				alignH = "end",
				alignV = "end",
				Host.Frame({ Name = "Dot", Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0 }),
			}),
			Host.CanvasGroup({
				Name = "Faded",
				LayoutOrder = 3,
				GroupTransparency = 1,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(200, 50),
				UI.Button({ Name = "FadedButton", label = "Faded" }),
			}),
			Host.CanvasGroup({
				Name = "Hidden",
				LayoutOrder = 4,
				Visible = false,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(200, 50),
				UI.Button({ Name = "HiddenButton", label = "Hidden" }),
			}),
		}
	end, { size = Vector2.new(1280, 720), frames = 12 })
	local fixed, wide = t.find(stageTwo, "FixedRow"), t.find(stageTwo, "Wide")
	if fixed and wide then
		t.near("02 a fixed axis keeps 100 px", fixed.AbsoluteSize.X, 100, 0.5)
		t.check("02 a fixed axis lets its child overflow", t.rect(wide).r > t.rect(fixed).r + 50, {
			row = t.rect(fixed).r,
			child = t.rect(wide).r,
		})
	else
		t.check("02 the fixed row fixture mounts", false)
	end
	local hug = t.find(stageTwo, "HugZ")
	local dot = hug and t.find(hug, "Dot")
	if hug and dot then
		t.check("06 a hugging parent has no spare room", sameRect(t.rect(hug), t.rect(dot)), {
			parent = t.rect(hug),
			dot = t.rect(dot),
		})
	else
		t.check("06 the hugging fixture mounts", false)
	end
	local faded, hidden = t.find(stageTwo, "FadedButton"), t.find(stageTwo, "HiddenButton")
	if faded then
		GuiService.SelectedObject = faded
		t.settle(2)
		t.check("05 a fully faded group still takes the selection", GuiService.SelectedObject == faded, selectedName())
	end
	if hidden then
		GuiService.SelectedObject = hidden
		t.settle(2)
		t.note("05 selection after selecting a button in a hidden group", selectedName())
	end
	GuiService.SelectedObject = nil
end)

interactive(
	"badge-seal-sits-on-the-corner",
	{ "post-badge-01" },
	"afterInbox: click the point noted as 'Inbox seal point'; afterAlerts: click the point noted as 'Alerts seal point'",
	function(t)
		local value = { presses = { Inbox = 0, Alerts = 0 }, connections = {} }
		local stage = scenario(t, "status_family", { size = Vector2.new(1280, 720) })
		local scroller: any
		for _, node in stage:GetDescendants() do
			if node.Name == "Content" and node:IsA("ScrollingFrame") and t.find(node, "Inbox+badge") then
				scroller = node
				break
			end
		end
		local anchor = scroller and t.find(scroller, "Inbox+badge")
		t.check("the badge hosts are found", scroller ~= nil and anchor ~= nil)
		if not (scroller and anchor) then
			return value
		end
		local top = anchor.AbsolutePosition.Y - scroller.AbsolutePosition.Y + scroller.CanvasPosition.Y - 120
		scroller.CanvasPosition = Vector2.new(0, math.max(0, top))
		t.settle(10)
		for _, name in { "Inbox", "Alerts", "Friend" } do
			local wrapper = t.find(scroller, name .. "+badge")
			local host = wrapper and wrapper:FindFirstChild(name)
			local cornerFrame = wrapper and wrapper:FindFirstChild("Corner")
			local seal = cornerFrame and t.find(cornerFrame, "CornerBadge")
			t.check(`{name} host and seal found`, host ~= nil and seal ~= nil)
			if host and seal and cornerFrame then
				local h, s = t.rect(host), t.rect(seal)
				local c = centre(s)
				t.near(`{name} seal is centred on the host's right edge`, c.X, h.r, 1.5)
				t.near(`{name} seal is centred on the host's top edge`, c.Y, h.y, 1.5)
				t.check(
					`{name} seal draws above its host`,
					cornerFrame.ZIndex > host.ZIndex and seal.ZIndex > host.ZIndex,
					{
						corner = cornerFrame.ZIndex,
						seal = seal.ZIndex,
						host = host.ZIndex,
					}
				)
				t.near(`{name} wrapper keeps the host's width`, wrapper.AbsoluteSize.X, h.w, 0.5)
				t.near(`{name} wrapper keeps the host's height`, wrapper.AbsoluteSize.Y, h.h, 0.5)
				local sinks = 0
				for _, part in cornerFrame:GetDescendants() do
					if part:IsA("GuiButton") or (part:IsA("GuiObject") and (part.Active or part.Selectable)) then
						sinks += 1
					end
				end
				t.check(`{name} seal takes no input`, sinks == 0, sinks)
				if name ~= "Friend" then
					local point = screenPoint(h.r - 3, h.y + 3)
					t.check(
						`{name} press point lies on the seal`,
						h.r - 3 >= s.x and h.r - 3 <= s.r and h.y + 3 >= s.y and h.y + 3 <= s.b,
						{ seal = { s.x, s.y, s.w, s.h } }
					)
					t.note(`{name} seal point`, point)
					table.insert(
						value.connections,
						host.Activated:Connect(function()
							value.presses[name] += 1
						end)
					)
				end
			end
		end
		return value
	end,
	{
		afterInbox = function(t, value)
			t.settle(4)
			t.check("a click on the Inbox seal presses Inbox", value.presses.Inbox == 1, value.presses)
		end,
		afterAlerts = function(t, value)
			t.settle(4)
			t.check("a click on the Alerts seal presses Alerts", value.presses.Alerts == 1, value.presses)
			for _, connection in value.connections do
				connection:Disconnect()
			end
			GuiService.SelectedObject = nil
		end,
	}
)

return cases
