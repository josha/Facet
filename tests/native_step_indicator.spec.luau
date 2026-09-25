--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local worlds = require("./lib/content_world")
local Compose = Facet.Compose

local function workflow(): { any }
	return {
		{ id = "cart", label = "Cart", state = "complete", navigable = true },
		{ id = "ship", label = "Shipping", description = "Address and speed", navigable = true },
		{ id = "pay", label = "Payment", navigable = true },
		{ id = "done", label = "Review" },
	}
end

local function mount(spec: any, width: number?, options: { [string]: any }?): (any, any)
	local world = worlds.new(function(UI)
		return UI.StepIndicator("Steps")(spec)
	end, options)
	local root = world.find("Steps")
	world.resize(root, width or 900, 80)
	return world, root
end

local function measureAll(world: any, root: any, width: number)
	for _, node in root:GetDescendants() do
		if node.Name == "Measure" then
			world.bounds(node, width)
		end
	end
end

local function cell(world: any, id: string): any
	return world.find(`Step-{id}`)
end

t.describe("native StepIndicator", function()
	t.it("makes only navigable, enabled steps with onSelect into Buttons and the rest into content", function()
		local world = mount({ steps = workflow(), current = "ship", onSelect = function() end })
		t.expect(cell(world, "ship"):IsA("TextButton")).toBe(true)
		t.expect(cell(world, "done"):IsA("TextButton")).toBe(false)
		t.expect(cell(world, "done"):IsA("GuiButton")).toBe(false)
		world.stop()
		local plain = mount({ steps = workflow(), current = "ship" })
		t.expect(cell(plain, "ship"):IsA("GuiButton")).toBe(false)
		plain.stop()
		local disabledSteps = workflow()
		disabledSteps[3].enabled = false
		local disabled = mount({ steps = disabledSteps, current = "ship", onSelect = function() end })
		t.expect(cell(disabled, "pay"):IsA("GuiButton")).toBe(false)
		t.expect(cell(disabled, "pay"):HasTag("facet-disabled")).toBe(true)
		disabled.stop()
	end)

	t.it("moves the underline and the summary only with current, and a refused selection changes nothing", function()
		local current = Compose.cell("ship")
		local asked: { string } = {}
		local accept = true
		local world, root = mount({
			steps = workflow(),
			current = current,
			onSelect = function(id: string)
				table.insert(asked, id)
				if accept then
					current:set(id)
				end
			end,
		}, 900, { reducedMotion = true })
		local strip = world.find("Strip")
		strip.AbsolutePosition = world.V2(10, 0)
		local positions = { cart = 10, ship = 200, pay = 400, done = 600 }
		for id, x in positions do
			cell(world, id).AbsolutePosition = world.V2(x, 0)
			world.resize(cell(world, id), 150, 60)
		end
		local underline = world.find("Underline")
		local function under(id: string): boolean
			return underline.Position.X.Offset == positions[id] - 10 and underline.Size.X.Offset == 150
		end
		t.expect(under("ship")).toBe(true)
		t.expect(root:GetAttribute("FacetSummary")).toBe("Step 2 of 4 — Shipping")
		accept = false
		cell(world, "pay").Activated.fire()
		t.expect(table.concat(asked, ",")).toBe("pay")
		t.expect(root:GetAttribute("FacetCurrent")).toBe("ship")
		t.expect(under("ship")).toBe(true)
		accept = true
		cell(world, "pay").Activated.fire()
		t.expect(root:GetAttribute("FacetCurrent")).toBe("pay")
		t.expect(root:GetAttribute("FacetSummary")).toBe("Step 3 of 4 — Payment")
		t.expect(under("pay")).toBe(true)
		cell(world, "pay").Activated.fire()
		t.expect(#asked).toBe(2)
		world.stop()
	end)

	t.it("stretches the row cells to one height on one top edge", function()
		local world = mount({ steps = workflow(), current = "ship" })
		local layout = world.find("Row"):FindFirstChildWhichIsA("UIListLayout")
		t.expect(layout.FillDirection.Name).toBe("Horizontal")
		t.expect(layout.ItemLineAlignment.Name).toBe("Stretch")
		t.expect(layout.VerticalAlignment.Name).toBe("Top")
		t.expect(layout.HorizontalFlex.Name).toBe("Fill")
		local underline = world.find("Underline")
		t.expect(underline.AnchorPoint.Y).toBe(1)
		t.expect(underline.Position.Y.Scale).toBe(1)
		t.expect(underline:HasTag("facet-selection-indicator")).toBe(true)
		world.stop()
	end)

	t.it("reserves space under the row so the underline never crosses the state word", function()
		local world = mount({ steps = workflow(), current = "ship" })
		local padding = world.find("Row"):FindFirstChildWhichIsA("UIPadding")
		t.expect(padding ~= nil).toBe(true)
		local underline = world.find("Underline")
		t.expect(padding.PaddingBottom.Offset >= underline.Size.Y.Offset + 2).toBe(true)
		world.stop()
	end)

	t.it("keeps the own cue and state word of an errored or completed current step", function()
		local steps = workflow()
		steps[2].state = "error"
		local world = mount({ steps = steps, current = "ship" })
		local ship = cell(world, "ship")
		t.expect(ship:FindFirstChild("Error", true).Visible).toBe(true)
		t.expect(ship:FindFirstChild("Check", true).Visible).toBe(false)
		t.expect(ship:FindFirstChild("Circle", true).Visible).toBe(false)
		t.expect(ship:FindFirstChild("State", true).Text).toBe("Error")
		local cart = cell(world, "cart")
		t.expect(cart:FindFirstChild("Check", true).Visible).toBe(true)
		t.expect(cart:FindFirstChild("State", true).Text).toBe("Complete")
		local pay = cell(world, "pay")
		t.expect(pay:FindFirstChild("Circle", true).Visible).toBe(true)
		t.expect(pay:FindFirstChild("Number", true).Text).toBe("3")
		t.expect(pay:FindFirstChild("State", true).Text).toBe("Upcoming")
		world.stop()
	end)

	t.it("keeps the number marker a circle when the text grows", function()
		local world = mount({ steps = workflow(), current = "ship" })
		local pay = cell(world, "pay")
		local cue = pay:FindFirstChild("Cue")
		world.bounds(pay:FindFirstChild("Number", true), 30, 40)
		t.expect(cue.Size.X.Offset).toBe(cue.Size.Y.Offset)
		t.expect(cue.Size.Y.Offset > 24).toBe(true)
		t.expect(cue:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio).toBe(1)
		t.expect(pay:FindFirstChild("Circle", true):FindFirstChildWhichIsA("UICorner").CornerRadius.Scale).toBe(1)
		world.stop()
	end)

	t.it("sizes the number circle from the styled text size before the text bounds report", function()
		local world = mount({ steps = workflow(), current = "ship" })
		local pay = cell(world, "pay")
		local cue = pay:FindFirstChild("Cue")
		local number = pay:FindFirstChild("Number", true)
		number.TextSize = 16
		t.expect(cue.Size.X.Offset).toBe(24)
		t.expect(cue.Size.Y.Offset).toBe(24)
		world.stop()
	end)

	t.it("never guesses a missing current and rebuilds empty and repopulated lists", function()
		local steps = Compose.cell(workflow())
		local current = Compose.cell("gone" :: string?)
		local world, root = mount({ steps = steps, current = current })
		t.expect(root:GetAttribute("FacetCurrent")).toBeNil()
		t.expect(root:GetAttribute("FacetSummary")).toBe("No current step")
		for _ = 1, 2 do
			steps:set({})
			t.expect(root:GetAttribute("FacetSummary")).toBe("No steps")
			t.expect(world.find("ShowSteps")).toBeNil()
			t.expect(cell(world, "cart")).toBeNil()
			steps:set(workflow())
			current:set("pay")
			t.expect(root:GetAttribute("FacetSummary")).toBe("Step 3 of 4 — Payment")
			t.expect(cell(world, "pay") ~= nil).toBe(true)
		end
		world.stop()
	end)

	t.it("keeps each step node across a reorder and renumbers it", function()
		local steps = Compose.cell(workflow())
		local world, root = mount({ steps = steps, current = "pay", onSelect = function() end })
		local payNode = cell(world, "pay")
		local reversed = {}
		for index = 4, 1, -1 do
			table.insert(reversed, workflow()[index])
		end
		steps:set(reversed)
		t.expect(cell(world, "pay")).toBe(payNode)
		t.expect(payNode:FindFirstChild("Number", true).Text).toBe("2")
		t.expect(payNode.LayoutOrder).toBe(2)
		t.expect(root:GetAttribute("FacetSummary")).toBe("Step 2 of 4 — Payment")
		world.stop()
	end)

	t.it("refuses conflicts at construction and keeps the last legal snapshot later", function()
		local bad: { any } = {
			{ steps = { { id = "a", label = "A", state = "current" } }, current = "b" },
			{ steps = { { id = "a", label = "A" }, { id = "a", label = "B" } }, current = "a" },
			{ steps = { { id = "", label = "A" } } },
			{ steps = { { id = "a", label = "" } } },
			{ steps = { { id = "a", label = "A", state = "done" } } },
			{ steps = { { id = "a", label = "A", extra = 1 } } },
			{ steps = {}, sizing = "wide" },
			{ steps = {}, extra = true },
		}
		for _, spec in bad do
			t.expect(worlds.mountError(function(UI)
				return UI.StepIndicator(spec)
			end) ~= nil).toBe(true)
		end
		t.expect(worlds.mountError(function(UI)
			return UI.StepIndicator({
				steps = { { id = "r1", label = "Review" }, { id = "r2", label = "Review" } },
				current = "r1",
			})
		end)).toBeNil()
		local controls: { [string]: any } = {}
		local steps = Compose.cell(workflow())
		local world, root = mount({ steps = steps, current = "ship", controls = controls })
		local broken = workflow()
		broken[1].state = "current"
		steps:set(broken)
		t.expect(root:GetAttribute("FacetCurrent")).toBe("ship")
		t.expect(#controls.diagnostics()).toBe(1)
		world.stop()
	end)

	t.it("shows Step n of m and a list that selects through the same path when the width is narrow", function()
		local current = Compose.cell("ship")
		local asked: { string } = {}
		local refuse = false
		local world, root = mount({
			steps = workflow(),
			current = current,
			onSelect = function(id: string)
				if refuse then
					return
				end
				table.insert(asked, id)
				current:set(id)
			end,
		}, 300)
		measureAll(world, root, 90)
		t.expect(root:GetAttribute("FacetForm")).toBe("summary")
		t.expect(world.find("Strip").Visible).toBe(false)
		t.expect(world.find("SummaryRow").Visible).toBe(true)
		t.expect(world.find("Summary").Text).toBe("Step 2 of 4 — Shipping")
		world.find("ShowSteps"):FindFirstChild("Trigger").Activated.fire()
		t.expect(root:GetAttribute("FacetListOpen")).toBe(true)
		t.expect(#asked).toBe(0)
		refuse = true
		world.find("Item-cart", world.screen.Parent).Activated.fire()
		t.expect(root:GetAttribute("FacetListOpen")).toBe(true)
		t.expect(world.find("Item-done", world.screen.Parent).Selectable).toBe(false)
		refuse = false
		world.find("Item-pay", world.screen.Parent).Activated.fire()
		t.expect(table.concat(asked, ",")).toBe("pay")
		t.expect(root:GetAttribute("FacetListOpen")).toBe(false)
		t.expect(world.find("Summary").Text).toBe("Step 3 of 4 — Payment")
		world.stop()
	end)

	t.it("follows its offer both ways between the row and the summary, for fill and hug", function()
		for _, sizing in { "fill", "hug" } do
			local world, root = mount({ steps = workflow(), current = "ship", sizing = sizing }, 150)
			measureAll(world, root, 60)
			t.expect(`{sizing} {root:GetAttribute("FacetForm")}`).toBe(`{sizing} summary`)
			world.resize(root, 950, 80)
			t.expect(`{sizing} {root:GetAttribute("FacetForm")}`).toBe(`{sizing} row`)
			world.stop()
		end
		local steps = workflow()
		steps[2].label = "A much longer shipping label"
		local fill, fillRoot = mount({ steps = steps, current = "ship", sizing = "fill" }, 540)
		local hug, hugRoot = mount({ steps = steps, current = "ship", sizing = "hug" }, 540)
		for _, pair in { { fill, fillRoot }, { hug, hugRoot } } do
			for _, node in pair[2]:GetDescendants() do
				if node.Name == "Measure" then
					pair[1].bounds(node, if node.Text == steps[2].label then 220 else 50)
				end
			end
		end
		t.expect(fillRoot:GetAttribute("FacetForm")).toBe("summary")
		t.expect(hugRoot:GetAttribute("FacetForm")).toBe("row")
		fill.stop()
		hug.stop()
	end)

	t.it("measures the whole cell, not the label alone, before it draws the row", function()
		for _, sizing in { "fill", "hug" } do
			local world, root =
				mount({ steps = workflow(), current = "ship", sizing = sizing, onSelect = function() end }, 484)
			for _, node in root:GetDescendants() do
				if node.Name == "Measure" then
					world.bounds(node, 60)
				elseif node.Name == "State" then
					world.bounds(node, 64)
				elseif node.Name == "Description" then
					world.bounds(node, if node.Text == "" then 0 else 130)
				end
			end
			t.expect(`{sizing} {root:GetAttribute("FacetForm")}`).toBe(`{sizing} summary`)
			world.resize(root, 950, 80)
			t.expect(`{sizing} {root:GetAttribute("FacetForm")}`).toBe(`{sizing} row`)
			world.stop()
		end
	end)

	t.it("leaves nothing open when a callback removes the control", function()
		local show = Compose.cell(true)
		local world = worlds.new(function(UI)
			return Compose.show(show, function()
				return UI.StepIndicator("Steps")({
					steps = workflow(),
					current = "ship",
					onSelect = function()
						show:set(false)
					end,
				})
			end)
		end)
		world.find("Step-pay").Activated.fire()
		t.expect(world.find("Steps")).toBeNil()
		world.stop()
	end)

	t.it("moves the narrow summary with a row selection in the Steps scenario and refuses both", function()
		local scenario = require("../examples/gallery/scenarios/steps") :: any
		local world = worlds.new(function(UI, Host, engine)
			return scenario.build({ UI = UI, Compose = Compose, Host = Host, types = engine.types }).screen()
		end)
		local checkout, compact = world.find("Checkout"), world.find("Compact")
		local compactSummary = world.find("Summary", compact)
		t.expect(compact:GetAttribute("FacetSummary")).toBe("Step 2 of 4 — Shipping")
		world.find("Step-pay", checkout).Activated.fire()
		t.expect(compact:GetAttribute("FacetSummary")).toBe("Step 3 of 4 — Payment")
		t.expect(compactSummary.Text).toBe("Step 3 of 4 — Payment")
		world.find("Refuse").Activated.fire()
		world.find("Step-cart", checkout).Activated.fire()
		t.expect(compact:GetAttribute("FacetSummary")).toBe("Step 3 of 4 — Payment")
		t.expect(world.find("Step-pay", checkout):FindFirstChild("State", true).Text).toBe("Error")
		world.stop()
	end)
end)

return nil
