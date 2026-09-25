--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local worlds = require("./lib/content_world")
local window = require("../src/ui/pagination_window")
local Compose = Facet.Compose

local function controlled(initial: number, extra: { [string]: any }?): (any, any, { number })
	local page = Compose.cell(initial)
	local asked: { number } = {}
	local spec: { [string]: any } = {
		page = page,
		onChange = function(nextPage: number)
			table.insert(asked, nextPage)
			page:set(nextPage)
		end,
	}
	for key, value in extra or {} do
		spec[key] = value
	end
	return spec, page, asked
end

local function mount(spec: any, width: number?, digit: number?): any
	local world = worlds.new(function(UI, Host)
		return Host.Frame({
			Name = "Page",
			UI.Button({ Name = "Before", label = "Before" }),
			UI.Pagination("P")(spec),
			UI.Button({ Name = "After", label = "After" }),
		})
	end)
	local root = world.find("P")
	if digit then
		world.bounds(root:FindFirstChild("DigitMeasure"), digit * 10)
		world.bounds(root:FindFirstChild("EllipsisMeasure"), digit)
	end
	world.resize(root, width or 800, 44)
	return world, root
end

local function mounted(root: any): { any }
	local items = {}
	for _, child in root:FindFirstChild("Row"):GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(items, child)
		end
	end
	table.sort(items, function(a: any, b: any): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	return items
end

local function text(root: any): string
	local out = {}
	for _, item in mounted(root) do
		local name = item.Name
		local page = string.match(name, "^Slot%-(%d+)$")
		if page then
			local button = item:FindFirstChild("Page-" .. page)
			table.insert(out, if button:GetAttribute("selected") then `[{page}]` else page)
		elseif string.match(name, "^gap%-") then
			table.insert(out, item.Text)
		elseif name == "Label" then
			table.insert(out, item.Text)
		else
			table.insert(out, string.lower(name))
		end
	end
	return table.concat(out, " ")
end

local function row(current: number, count: number): string
	local out = {}
	local previous = nil
	for _, entry in window(current, count, 1, 1) do
		if previous ~= nil and entry.page > previous + 1 then
			table.insert(out, "…")
		end
		table.insert(out, tostring(entry.page))
		previous = entry.page
	end
	return table.concat(out, " ")
end

t.describe("native Pagination", function()
	t.it("shows the seven-slot pattern near each edge and in the middle, and a gap of one shows the page", function()
		t.expect(row(1, 10)).toBe("1 2 3 4 5 … 10")
		t.expect(row(5, 10)).toBe("1 … 4 5 6 … 10")
		t.expect(row(10, 10)).toBe("1 … 6 7 8 9 10")
		t.expect(row(4, 10)).toBe("1 2 3 4 5 … 10")
		t.expect(row(3, 7)).toBe("1 2 3 4 5 6 7")
		t.expect(row(1, 1)).toBe("1")
		local huge = 9007199254740991
		t.expect(#window(huge - 3, huge, 20, 20) <= 83).toBe(true)
		t.expect(row(huge, huge)).toBe(`1 … {huge - 4} {huge - 3} {huge - 2} {huge - 1} {huge}`)
	end)

	t.it("mounts the window, marks the current page and proposes without writing", function()
		local page = Compose.cell(5)
		local asked: { number } = {}
		local world, root = mount({
			page = page,
			pageCount = 10,
			onChange = function(nextPage: number)
				table.insert(asked, nextPage)
			end,
		})
		t.expect(text(root)).toBe("previous 1 … 4 [5] 6 … 10 next")
		world.find("Page-6").Activated.fire()
		world.find("Next").Activated.fire()
		world.find("Page-5").Activated.fire()
		t.expect(table.concat(asked, ",")).toBe("6,6")
		t.expect(page:peek()).toBe(5)
		t.expect(text(root)).toBe("previous 1 … 4 [5] 6 … 10 next")
		t.expect(world.find("Page-5"):GetAttribute("selected")).toBe(true)
		t.expect(root:GetAttribute("FacetCurrent")).toBe(5)
		world.stop()
	end)

	t.it("keeps the overlapping page nodes when the window moves", function()
		local spec, page = controlled(5, { pageCount = 20 })
		local world, root = mount(spec)
		local six = world.find("Page-6")
		page:set(6)
		t.expect(text(root)).toBe("previous 1 … 5 [6] 7 … 20 next")
		t.expect(world.find("Page-6")).toBe(six)
		world.stop()
	end)

	t.it("shows zero pages as inert context and one page with no enabled navigation", function()
		local count = Compose.cell(0)
		local spec, _, asked = controlled(1, { pageCount = count })
		local world, root = mount(spec)
		t.expect(text(root)).toBe("No pages")
		for _, node in root:GetDescendants() do
			t.expect(node:IsA("GuiButton") and node.Selectable == true).toBe(false)
		end
		count:set(1)
		t.expect(text(root)).toBe("previous [1] next")
		world.find("Previous").Activated.fire()
		world.find("Next").Activated.fire()
		t.expect(#asked).toBe(0)
		t.expect(world.find("Next").Selectable).toBe(false)
		t.expect(world.find("Previous").Selectable).toBe(false)
		world.stop()
	end)

	t.it("follows the flags of an unknown count, shows the page label and never a last page", function()
		local more = Compose.cell(true)
		local spec, _, asked = controlled(3, { hasNext = more, hasPrevious = true, showFirstLast = true })
		local world, root = mount(spec)
		t.expect(text(root)).toBe("first previous Page 3 next")
		world.find("Next").Activated.fire()
		world.find("First").Activated.fire()
		t.expect(table.concat(asked, ",")).toBe("4,1")
		more:set(false)
		world.find("Next").Activated.fire()
		t.expect(#asked).toBe(2)
		t.expect(world.find("Last")).toBeNil()
		world.stop()
	end)

	t.it("shows an outside page clamped with a diagnostic and never writes it back", function()
		local controls: { [string]: any } = {}
		local spec, page, asked = controlled(40, { pageCount = 12, controls = controls })
		local world, root = mount(spec)
		t.expect(root:GetAttribute("FacetCurrent")).toBe(12)
		t.expect(page:peek()).toBe(40)
		t.expect(#asked).toBe(0)
		t.expect(#controls.diagnostics() >= 1).toBe(true)
		world.stop()
	end)

	t.it("refuses malformed construction and keeps the last legal value for a late one", function()
		local Enum = require("@lune/roblox").Enum
		local bad: { { [string]: any } } = {
			{ page = 1.5, onChange = print },
			{ page = 0 / 0, onChange = print },
			{ page = math.huge, onChange = print },
			{ page = 1 },
			{ page = 1, onChange = print, pageCount = -1 },
			{ page = 1, onChange = print, siblingCount = 21 },
			{ page = 1, onChange = print, form = "dots" },
			{ page = 1, onChange = print, direction = "up" },
			{ page = 1, onChange = print, extra = true },
			{ page = 1, onChange = print, AutomaticSize = Enum.AutomaticSize.X },
		}
		for _, spec in bad do
			t.expect(worlds.mountError(function(UI)
				return UI.Pagination(spec)
			end) ~= nil).toBe(true)
		end
		local spec, page = controlled(3, { pageCount = 10 })
		local world, root = mount(spec)
		page:set(2.5)
		t.expect(root:GetAttribute("FacetCurrent")).toBe(3)
		page:set(4)
		t.expect(root:GetAttribute("FacetCurrent")).toBe(4)
		world.stop()
	end)

	t.it(
		"drops the farthest boundary page, then the farthest neighbour, then shows the label as room narrows",
		function()
			local wide, wideRoot = mount((controlled(5000, { pageCount = 9999 })), 800, 10)
			t.expect(text(wideRoot)).toBe("previous 1 … 4999 [5000] 5001 … 9999 next")
			t.expect(wide.find("Slot-5000").Size.X.Offset >= 44).toBe(true)
			t.expect(wide.find("Slot-5000").Size.X.Offset).toBe(56)
			t.expect(wide.find("Page-5000"):FindFirstChild("SlotLimit").MaxSize.X).toBe(56)
			local compact = require("../src").themes.neutralPackage().metrics.controlSizes.compact.height
			t.expect(wide.find("Page-1"):FindFirstChild("SlotLimit").MinSize.X).toBe(compact)
			wide.stop()
			local expected = {
				[360] = "previous 1 … 4999 [5000] 5001 next",
				[330] = "previous 4999 [5000] 5001 next",
				[240] = "previous 4999 [5000] next",
				[190] = "previous [5000] next",
				[120] = "previous Page 5000 of 9999 next",
			}
			for width, want in expected do
				local world, root = mount((controlled(5000, { pageCount = 9999 })), width, 10)
				t.expect(`{width}: {text(root)}`).toBe(`{width}: {want}`)
				world.stop()
			end
			local world, root = mount((controlled(5000, { pageCount = 9999 })), 800, 10)
			world.resize(root, 330, 44)
			t.expect(text(root)).toBe("previous 4999 [5000] 5001 next")
			world.resize(root, 800, 44)
			t.expect(text(root)).toBe("previous 1 … 4999 [5000] 5001 … 9999 next")
			world.stop()
		end
	)

	t.it("reverses the row once in rtl and keeps the meaning of previous and next", function()
		local spec, _, asked = controlled(5, { pageCount = 10, direction = "rtl" })
		local world, root = mount(spec)
		t.expect(text(root)).toBe("next 10 … 6 [5] 4 … 1 previous")
		t.expect(world.find("Next").LayoutOrder < world.find("Previous").LayoutOrder).toBe(true)
		world.find("Next").Activated.fire()
		t.expect(asked[1]).toBe(6)
		world.stop()
	end)

	t.it("hands the selection of a page that leaves the window to the current page", function()
		local spec, page = controlled(5, { pageCount = 20 })
		local world = mount(spec)
		world.gui.SelectedObject = world.find("Page-4")
		page:set(9)
		t.expect(world.gui.SelectedObject).toBe(world.find("Page-9"))
		world.stop()
	end)

	t.it("takes the current page back when the engine moves the selection of a removed page away", function()
		for _, target in { "outside", "Page-20" } do
			local spec, page = controlled(5, { pageCount = 20 })
			local world = mount(spec)
			local four = world.find("Page-4")
			local outside = world.engine.new("TextButton")
			world.gui.SelectedObject = four
			four.AncestryChanged:Connect(function()
				if four.Parent == nil and world.gui.SelectedObject == four then
					world.gui.SelectedObject = if target == "outside" then outside else world.find("Page-20")
				end
			end)
			page:set(9)
			world.resize(world.find("Page-9"), 44, 44)
			t.expect(`{target} {world.gui.SelectedObject == world.find("Page-9")}`).toBe(`{target} true`)
			world.stop()
		end
	end)

	t.it("takes the current page back when the engine moves the handed selection before layout", function()
		local spec, page = controlled(5, { pageCount = 20 })
		local world = mount(spec)
		world.gui.SelectedObject = world.find("Page-4")
		page:set(9)
		local nine = world.find("Page-9")
		local outside = world.engine.new("TextButton")
		world.gui.SelectedObject = outside
		world.resize(nine, 44, 44)
		t.expect(world.gui.SelectedObject).toBe(nine)
		world.gui.SelectedObject = world.find("Page-20")
		world.resize(nine, 45, 44)
		t.expect(world.gui.SelectedObject).toBe(world.find("Page-20"))
		world.stop()
	end)

	t.it("is reached from a neighbour off its axis and lands on the current page", function()
		local spec, page = controlled(5, { pageCount = 20, showFirstLast = true })
		local world = mount(spec)
		local row = world.find("P"):FindFirstChild("Row")
		world.gui.SelectedObject = world.find("Before")
		t.expect(row.Selectable).toBe(true)
		t.expect(row:GetAttribute("FacetEntry")).toBe("Page-5")
		world.gui.SelectedObject = row
		t.expect(world.gui.SelectedObject).toBe(world.find("Page-5"))
		t.expect(row.Selectable).toBe(false)
		world.gui.SelectedObject = world.find("First")
		t.expect(row.Selectable).toBe(false)
		page:set(7)
		t.expect(row:GetAttribute("FacetEntry")).toBe("Page-7")
		world.gui.SelectedObject = world.find("After")
		t.expect(row.Selectable).toBe(true)
		world.stop()
	end)

	t.it("hands the selection of an arrow that disables at an edge to the current page", function()
		for _, case in
			{
				{ from = 9, arrow = "Next", lands = "Page-10" },
				{ from = 2, arrow = "Previous", lands = "Page-1" },
				{ from = 3, arrow = "First", lands = "Page-1" },
				{ from = 7, arrow = "Last", lands = "Page-10" },
			}
		do
			local spec = controlled(case.from, { pageCount = 10, showFirstLast = true })
			local world = mount(spec)
			local arrow = world.find(case.arrow)
			world.gui.SelectedObject = arrow
			arrow.Activated.fire()
			t.expect(`{case.arrow}: {world.gui.SelectedObject and world.gui.SelectedObject.Name}`)
				.toBe(`{case.arrow}: {case.lands}`)
			world.stop()
		end
	end)

	t.it("gives every page and arrow a slot at the target floor and a compact plate centred in it", function()
		local world, root = mount((controlled(5, { pageCount = 200, showFirstLast = true })))
		local slots = 0
		for _, item in mounted(root) do
			if item:IsA("GuiButton") then
				t.expect(item.Size.X.Offset >= 44 and item.Size.Y.Offset >= 44).toBe(true)
				slots += 1
			elseif string.match(item.Name, "^Slot%-") then
				t.expect(item.Size.X.Offset >= 44 and item.Size.Y.Offset >= 44).toBe(true)
				local plate = item:FindFirstChildWhichIsA("TextButton")
				t.expect(plate:GetAttribute("controlSize")).toBe("compact")
				t.expect(plate.AnchorPoint).toBe(world.V2(0.5, 0.5))
				t.expect(plate.Position.X.Scale).toBe(0.5)
				t.expect(plate.Position.Y.Scale).toBe(0.5)
				t.expect(plate.Size.Y.Offset < 44).toBe(true)
				slots += 1
			end
		end
		t.expect(slots).toBe(9)
		world.stop()
	end)

	t.it("keeps the label reservation while the label gains a digit, ltr and rtl, known and unknown", function()
		for _, case in
			{
				{ extra = { pageCount = 12, form = "label" }, from = 9, to = 10 },
				{ extra = { pageCount = 12, form = "label", direction = "rtl" }, from = 9, to = 10 },
				{ extra = { hasNext = true, hasPrevious = true }, from = 9, to = 10 },
				{ extra = { hasNext = true, hasPrevious = true, direction = "rtl" }, from = 99, to = 100 },
			}
		do
			local spec, page = controlled(case.from, case.extra)
			local world, root = mount(spec)
			local twin = root:FindFirstChild("LabelMeasure")
			world.bounds(twin, 120)
			local before = `{twin.Text} {world.find("Label").Size.X.Offset}`
			page:set(case.to)
			local where = `{case.extra.direction or "ltr"} {case.extra.pageCount or "?"} {case.to}`
			t.expect(`{where} {twin.Text} {world.find("Label").Size.X.Offset}`).toBe(`{where} {before}`)
			t.expect(world.find("Label").Size.X.Offset).toBe(120)
			world.stop()
		end
	end)

	t.it("leaves no stop inside the row when the count drops to zero", function()
		local count = Compose.cell(3)
		local world, root = mount((controlled(2, { pageCount = count })))
		world.resize(world.find("Before"), 80, 44)
		world.resize(world.find("After"), 80, 44)
		world.gui.SelectedObject = world.find("Page-3")
		count:set(0)
		t.expect(text(root)).toBe("No pages")
		for _, node in root:GetDescendants() do
			t.expect(node:IsA("GuiButton")).toBe(false)
		end
		local selected = world.gui.SelectedObject
		t.expect(selected ~= nil and (selected.Name == "Before" or selected.Name == "After")).toBe(true)
		world.stop()
	end)

	t.it("stays safe when a callback changes the count and removes the control", function()
		local show = Compose.cell(true)
		local count = Compose.cell(10)
		local page = Compose.cell(2)
		local asked = 0
		local world = worlds.new(function(UI)
			return Compose.show(show, function()
				return UI.Pagination("P")({
					page = page,
					pageCount = count,
					onChange = function(nextPage: number)
						asked += 1
						count:set(3)
						page:set(nextPage)
						show:set(false)
					end,
				})
			end)
		end)
		world.find("Next").Activated.fire()
		t.expect(asked).toBe(1)
		t.expect(world.find("P")).toBeNil()
		world.stop()
	end)

	t.it("follows an accepted page in the Paging scenario context and changes nothing on a refusal", function()
		local scenario = require("../examples/gallery/scenarios/paging") :: any
		local world = worlds.new(function(UI, Host, engine)
			return scenario.build({ UI = UI, Compose = Compose, Host = Host, types = engine.types }).screen()
		end)
		local context = world.find("ResultsContext")
		t.expect(context.Text).toBe("Showing results 81–100 of 4000")
		local results = world.find("Results")
		world.find("Next", results).Activated.fire()
		t.expect(context.Text).toBe("Showing results 101–120 of 4000")
		world.find("Refuse").Activated.fire()
		world.find("Next", results).Activated.fire()
		t.expect(context.Text).toBe("Showing results 101–120 of 4000")
		t.expect(world.find("Rtl"):GetAttribute("FacetDirection")).toBe("rtl")
		local forms = {}
		for _, node in world.findAll("Label") do
			table.insert(forms, tostring(node:GetAttribute("FacetForm")))
		end
		t.expect(table.find(forms, "label") ~= nil).toBe(true)
		world.stop()
	end)
end)

return nil
