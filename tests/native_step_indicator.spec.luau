--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureComposeTypes = require("../src/vendor/compose/core")

	local Facet = require("../src")
	local worlds = require("./lib/content_world")
	local Compose: ComposeModule = Facet.Compose

	local function workflow(): { any }
		return {
			{ id = "cart", label = "Cart", state = "complete", navigable = true },
			{ id = "ship", label = "Shipping", description = "Address and speed", navigable = true },
			{ id = "pay", label = "Payment", navigable = true },
			{ id = "done", label = "Review" },
		}
	end

	local function mount(spec: any, width: number?, options: { [string]: any }?): (any, any)
		local world = worlds.new(function(UI: FacetControls)
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

	local function drawn(world: any, scale: number): string
		local strip, underline = world.find("Strip"), world.find("Underline")
		local left = strip.AbsolutePosition.X
			+ underline.Position.X.Scale * strip.AbsoluteSize.X
			+ underline.Position.X.Offset * scale
		local width = underline.Size.X.Scale * strip.AbsoluteSize.X + underline.Size.X.Offset * scale
		return `{math.round(left * 10) / 10} {math.round(width * 10) / 10}`
	end

	verifyHarness:suite("native StepIndicator", function()
		verifyHarness:case("makes only navigable, enabled steps with onSelect into Buttons and the rest into content", {
			id = "native_step_indicator::native StepIndicator::makes only navigable, enabled steps with onSelect into Buttons and the rest into content",
			run = function()
				local world = mount({ steps = workflow(), current = "ship", onSelect = function() end })
				Verify.expect((cell(world, "ship"):IsA("TextButton"))):toBe(true)
				Verify.expect((cell(world, "done"):IsA("TextButton"))):toBe(false)
				Verify.expect((cell(world, "done"):IsA("GuiButton"))):toBe(false)
				world.stop()
				local plain = mount({ steps = workflow(), current = "ship" })
				Verify.expect((cell(plain, "ship"):IsA("GuiButton"))):toBe(false)
				plain.stop()
				local disabledSteps = workflow()
				disabledSteps[3].enabled = false
				local disabled = mount({ steps = disabledSteps, current = "ship", onSelect = function() end })
				Verify.expect((cell(disabled, "pay"):IsA("GuiButton"))):toBe(false)
				Verify.expect((cell(disabled, "pay"):HasTag("facet-disabled"))):toBe(true)
				disabled.stop()
			end,
		})

		verifyHarness:case(
			"moves the underline and the summary only with current, and a refused selection changes nothing",
			{
				id = "native_step_indicator::native StepIndicator::moves the underline and the summary only with current, and a refused selection changes nothing",
				run = function()
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
					}, 900, { motionLevel = "none" })
					local strip = world.find("Strip")
					strip.AbsolutePosition = world.V2(10, 0)
					world.resize(strip, 900, 80)
					local positions: { [string]: number } = { cart = 10, ship = 200, pay = 400, done = 600 }
					for id, x in positions do
						cell(world, id).AbsolutePosition = world.V2(x, 0)
						world.resize(cell(world, id), 150, 60)
					end
					local function under(id: string): boolean
						return drawn(world, 1) == `{positions[id]} 150`
					end
					Verify.expect((under("ship"))):toBe(true)
					Verify.expect((root:GetAttribute("FacetSummary"))):toBe("Step 2 of 4 — Shipping")
					accept = false
					cell(world, "pay").Activated.fire()
					Verify.expect((table.concat(asked, ","))):toBe("pay")
					Verify.expect((root:GetAttribute("FacetCurrent"))):toBe("ship")
					Verify.expect((under("ship"))):toBe(true)
					accept = true
					cell(world, "pay").Activated.fire()
					Verify.expect((root:GetAttribute("FacetCurrent"))):toBe("pay")
					Verify.expect((root:GetAttribute("FacetSummary"))):toBe("Step 3 of 4 — Payment")
					Verify.expect((under("pay"))):toBe(true)
					cell(world, "pay").Activated.fire()
					Verify.expect(#asked):toBe(2)
					world.stop()
				end,
			}
		)

		verifyHarness:case("draws the underline on its step under an ancestor UIScale", {
			id = "native_step_indicator::native StepIndicator::draws the underline on its step under an ancestor UIScale",
			run = function()
				local world = mount({ steps = workflow(), current = "ship" }, 1200, { motionLevel = "none" })
				local strip = world.find("Strip")
				strip.AbsolutePosition = world.V2(12, 0)
				world.resize(strip, 1204.7, 96)
				cell(world, "ship").AbsolutePosition = world.V2(695.1, 0)
				world.resize(cell(world, "ship"), 269, 72)
				Verify.expect((drawn(world, 1.2047))):toBe("695.1 269")
				world.stop()
			end,
		})

		verifyHarness:case("stretches the row cells to one height on one top edge", {
			id = "native_step_indicator::native StepIndicator::stretches the row cells to one height on one top edge",
			run = function()
				local world = mount({ steps = workflow(), current = "ship" })
				local layout = world.find("Row"):FindFirstChildWhichIsA("UIListLayout")
				Verify.expect(layout.FillDirection.Name):toBe("Horizontal")
				Verify.expect(layout.ItemLineAlignment.Name):toBe("Stretch")
				Verify.expect(layout.VerticalAlignment.Name):toBe("Top")
				Verify.expect(layout.HorizontalFlex.Name):toBe("Fill")
				local underline = world.find("Underline")
				Verify.expect(underline.AnchorPoint.Y):toBe(1)
				Verify.expect(underline.Position.Y.Scale):toBe(1)
				Verify.expect((underline:HasTag("facet-selection-indicator"))):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("gives every fill cell one zero basis so the flex fill shares the row equally", {
			id = "native_step_indicator::native StepIndicator::gives every fill cell one zero basis so the flex fill shares the row equally",
			run = function()
				for _, pair in { { "fill", "Y" }, { "hug", "XY" } } do
					local world =
						mount({ steps = workflow(), current = "ship", sizing = pair[1], onSelect = function() end })
					for _, id in { "cart", "ship", "pay", "done" } do
						local node = cell(world, id)
						Verify.expect(
							`{pair[1]} {id} {node.AutomaticSize.Name} {node.Size.X.Scale} {node.Size.X.Offset}`
						)
							:toBe(`{pair[1]} {id} {pair[2]} 0 0`)
					end
					world.stop()
				end
			end,
		})

		verifyHarness:case(
			"insets every cell by the control inset, and its marker off the top edge, whether or not it is a Button",
			{
				id = "native_step_indicator::native StepIndicator::insets every cell by the control inset, and its marker off the top edge, whether or not it is a Button",
				run = function()
					for _, pair in { { size = "regular", height = 12 }, { size = "large", height = 16 } } do
						local world = mount({
							steps = workflow(),
							current = "ship",
							controlSize = pair.size,
							onSelect = function() end,
						})
						for _, id in { "cart", "ship", "pay", "done" } do
							local padding = cell(world, id):FindFirstChildWhichIsA("UIPadding")
							local sides = if padding
								then `{padding.PaddingLeft.Offset} {padding.PaddingRight.Offset} {padding.PaddingTop.Offset} {padding.PaddingBottom.Offset}`
								else "none"
							Verify.expect(`{pair.size} {id} {sides}`)
								:toBe(`{pair.size} {id} {pair.height} {pair.height} 4 4`)
						end
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case("reserves space under the row so the underline never crosses the state word", {
			id = "native_step_indicator::native StepIndicator::reserves space under the row so the underline never crosses the state word",
			run = function()
				local world = mount({ steps = workflow(), current = "ship" })
				local padding = world.find("Row"):FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding ~= nil):toBe(true)
				local underline = world.find("Underline")
				Verify.expect(padding.PaddingBottom.Offset >= underline.Size.Y.Offset + 2):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("keeps the own cue and state word of an errored or completed current step", {
			id = "native_step_indicator::native StepIndicator::keeps the own cue and state word of an errored or completed current step",
			run = function()
				local steps = workflow()
				steps[2].state = "error"
				local world = mount({ steps = steps, current = "ship" })
				local ship = cell(world, "ship")
				Verify.expect(ship:FindFirstChild("Error", true).Visible):toBe(true)
				Verify.expect(ship:FindFirstChild("Check", true).Visible):toBe(false)
				Verify.expect(ship:FindFirstChild("Circle", true).Visible):toBe(false)
				Verify.expect(ship:FindFirstChild("State", true).Text):toBe("Error")
				local cart = cell(world, "cart")
				Verify.expect(cart:FindFirstChild("Check", true).Visible):toBe(true)
				Verify.expect(cart:FindFirstChild("State", true).Text):toBe("Complete")
				local pay = cell(world, "pay")
				Verify.expect(pay:FindFirstChild("Circle", true).Visible):toBe(true)
				Verify.expect(pay:FindFirstChild("Number", true).Text):toBe("3")
				Verify.expect(pay:FindFirstChild("State", true).Text):toBe("Upcoming")
				world.stop()
			end,
		})

		verifyHarness:case("keeps the number marker a circle when the text grows", {
			id = "native_step_indicator::native StepIndicator::keeps the number marker a circle when the text grows",
			run = function()
				local world = mount({ steps = workflow(), current = "ship" })
				local pay = cell(world, "pay")
				local cue = pay:FindFirstChild("Cue")
				world.bounds(pay:FindFirstChild("Number", true), 30, 40)
				Verify.expect(cue.Size.X.Offset):toBe(cue.Size.Y.Offset)
				Verify.expect(cue.Size.Y.Offset > 24):toBe(true)
				Verify.expect(cue:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio):toBe(1)
				Verify.expect(pay:FindFirstChild("Circle", true):FindFirstChildWhichIsA("UICorner").CornerRadius.Scale)
					:toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("sizes the number circle from the styled text size before the text bounds report", {
			id = "native_step_indicator::native StepIndicator::sizes the number circle from the styled text size before the text bounds report",
			run = function()
				local world = mount({ steps = workflow(), current = "ship" })
				local pay = cell(world, "pay")
				local cue = pay:FindFirstChild("Cue")
				local number = pay:FindFirstChild("Number", true)
				number.TextSize = 16
				Verify.expect(cue.Size.X.Offset):toBe(24)
				Verify.expect(cue.Size.Y.Offset):toBe(24)
				world.stop()
			end,
		})

		verifyHarness:case("never guesses a missing current and rebuilds empty and repopulated lists", {
			id = "native_step_indicator::native StepIndicator::never guesses a missing current and rebuilds empty and repopulated lists",
			run = function()
				local steps = Compose.cell(workflow())
				local current = Compose.cell("gone" :: string?)
				local world, root = mount({ steps = steps, current = current })
				Verify.expect((root:GetAttribute("FacetCurrent"))):toBeNil()
				Verify.expect((root:GetAttribute("FacetSummary"))):toBe("No current step")
				for _ = 1, 2 do
					steps:set({})
					Verify.expect((root:GetAttribute("FacetSummary"))):toBe("No steps")
					Verify.expect((world.find("ShowSteps"))):toBeNil()
					Verify.expect((cell(world, "cart"))):toBeNil()
					steps:set(workflow())
					current:set("pay")
					Verify.expect((root:GetAttribute("FacetSummary"))):toBe("Step 3 of 4 — Payment")
					Verify.expect(cell(world, "pay") ~= nil):toBe(true)
				end
				world.stop()
			end,
		})

		verifyHarness:case("keeps each step node across a reorder and renumbers it", {
			id = "native_step_indicator::native StepIndicator::keeps each step node across a reorder and renumbers it",
			run = function()
				local steps = Compose.cell(workflow())
				local world, root = mount({ steps = steps, current = "pay", onSelect = function() end })
				local payNode = cell(world, "pay")
				local reversed = {}
				for index = 4, 1, -1 do
					table.insert(reversed, workflow()[index])
				end
				steps:set(reversed)
				Verify.expect((cell(world, "pay"))):toBe(payNode)
				Verify.expect(payNode:FindFirstChild("Number", true).Text):toBe("2")
				Verify.expect(payNode.LayoutOrder):toBe(2)
				Verify.expect((root:GetAttribute("FacetSummary"))):toBe("Step 2 of 4 — Payment")
				world.stop()
			end,
		})

		verifyHarness:case("refuses conflicts at construction and keeps the last legal snapshot later", {
			id = "native_step_indicator::native StepIndicator::refuses conflicts at construction and keeps the last legal snapshot later",
			run = function()
				local bad: { any } = {
					{ steps = { { id = "a", label = "A", state = "current" } }, current = "b" },
					{ steps = { { id = "a", label = "A" }, { id = "a", label = "B" } }, current = "a" },
					{ steps = { { id = "", label = "A" } } },
					{ steps = { { id = "a", label = "" } } },
					{ steps = { { id = "a", label = "A", state = "done" } } },
					{ steps = { { id = "a", label = "A", extra = 1 } } },
					{ steps = {}, sizing = "wide" :: "wide" },
					{ steps = {}, extra = true },
				}
				for _, spec in bad do
					Verify.expect(worlds.mountError(function(UI: FacetControls)
						return UI.StepIndicator(spec)
					end) ~= nil):toBe(true)
				end
				Verify.expect((worlds.mountError(function(UI: FacetControls)
					return UI.StepIndicator({
						steps = { { id = "r1", label = "Review" }, { id = "r2", label = "Review" } },
						current = "r1",
					})
				end))):toBeNil()
				local controls: { diagnostics: (() -> { string })? } = {}
				local steps = Compose.cell(workflow())
				local world, root = mount({ steps = steps, current = "ship", controls = controls })
				local broken = workflow()
				broken[1].state = "current"
				steps:set(broken)
				Verify.expect((root:GetAttribute("FacetCurrent"))):toBe("ship")
				Verify.expect(#assert(controls.diagnostics)()):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("shows Step n of m and a list that selects through the same path when the width is narrow", {
			id = "native_step_indicator::native StepIndicator::shows Step n of m and a list that selects through the same path when the width is narrow",
			run = function()
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
				Verify.expect((root:GetAttribute("FacetForm"))):toBe("summary")
				Verify.expect(world.find("Strip").Visible):toBe(false)
				Verify.expect(world.find("SummaryRow").Visible):toBe(true)
				Verify.expect(world.find("Summary").Text):toBe("Step 2 of 4 — Shipping")
				world.find("ShowSteps"):FindFirstChild("Trigger").Activated.fire()
				Verify.expect((root:GetAttribute("FacetListOpen"))):toBe(true)
				Verify.expect(#asked):toBe(0)
				refuse = true
				world.find("Item-cart", world.screen.Parent).Activated.fire()
				Verify.expect((root:GetAttribute("FacetListOpen"))):toBe(true)
				Verify.expect(world.find("Item-done", world.screen.Parent).Selectable):toBe(false)
				refuse = false
				world.find("Item-pay", world.screen.Parent).Activated.fire()
				Verify.expect((table.concat(asked, ","))):toBe("pay")
				Verify.expect((root:GetAttribute("FacetListOpen"))):toBe(false)
				Verify.expect(world.find("Summary").Text):toBe("Step 3 of 4 — Payment")
				world.stop()
			end,
		})

		verifyHarness:case("follows its offer both ways between the row and the summary, for fill and hug", {
			id = "native_step_indicator::native StepIndicator::follows its offer both ways between the row and the summary, for fill and hug",
			run = function()
				for _, sizing in { "fill", "hug" } do
					local world, root = mount({ steps = workflow(), current = "ship", sizing = sizing }, 150)
					measureAll(world, root, 60)
					world.find("Row"):FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = world.V2(600, 60)
					Verify.expect(`{sizing} {root:GetAttribute("FacetForm")}`):toBe(`{sizing} summary`)
					world.resize(root, 950, 80)
					Verify.expect(`{sizing} {root:GetAttribute("FacetForm")}`):toBe(`{sizing} row`)
					world.stop()
				end
				local steps = workflow()
				steps[2].label = "A much longer shipping label"
				local fill, fillRoot = mount({ steps = steps, current = "ship", sizing = "fill" :: "fill" }, 640)
				local hug, hugRoot = mount({ steps = steps, current = "ship", sizing = "hug" :: "hug" }, 640)
				for _, pair in { { fill, fillRoot }, { hug, hugRoot } } do
					for _, node in pair[2]:GetDescendants() do
						if node.Name == "Measure" then
							pair[1].bounds(node, if node.Text == steps[2].label then 220 else 50)
						end
					end
				end
				hug.find("Row"):FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = hug.V2(600, 60)
				Verify.expect((fillRoot:GetAttribute("FacetForm"))):toBe("summary")
				Verify.expect((hugRoot:GetAttribute("FacetForm"))):toBe("row")
				fill.stop()
				hug.stop()
			end,
		})

		verifyHarness:case("switches a hug row to the summary when the laid-out row is wider than its offer", {
			id = "native_step_indicator::native StepIndicator::switches a hug row to the summary when the laid-out row is wider than its offer",
			run = function()
				local world, root = mount(
					{ steps = workflow(), current = "ship", sizing = "hug" :: "hug", onSelect = function() end },
					400
				)
				measureAll(world, root, 10)
				local layout = world.find("Row"):FindFirstChildWhichIsA("UIListLayout")
				layout.AbsoluteContentSize = world.V2(520, 60)
				Verify.expect((root:GetAttribute("FacetForm"))):toBe("summary")
				layout.AbsoluteContentSize = world.V2(380, 60)
				Verify.expect((root:GetAttribute("FacetForm"))):toBe("row")
				world.stop()
			end,
		})

		verifyHarness:case("measures the whole fill cell, not the label alone, before it draws the row", {
			id = "native_step_indicator::native StepIndicator::measures the whole fill cell, not the label alone, before it draws the row",
			run = function()
				for _, sizing in { "fill" } do
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
					Verify.expect(`{sizing} {root:GetAttribute("FacetForm")}`):toBe(`{sizing} summary`)
					world.resize(root, 950, 80)
					Verify.expect(`{sizing} {root:GetAttribute("FacetForm")}`):toBe(`{sizing} row`)
					world.stop()
				end
			end,
		})

		verifyHarness:case("leaves nothing open when a callback removes the control", {
			id = "native_step_indicator::native StepIndicator::leaves nothing open when a callback removes the control",
			run = function()
				local show = Compose.cell(true)
				local world = worlds.new(function(UI: FacetControls)
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
				Verify.expect((world.find("Steps"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("moves the narrow summary with a row selection in the Steps scenario and refuses both", {
			id = "native_step_indicator::native StepIndicator::moves the narrow summary with a row selection in the Steps scenario and refuses both",
			run = function()
				local scenario = require("../examples/gallery/scenarios/steps") :: any
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost, engine)
					return scenario.build({ UI = UI, Compose = Compose, Host = Host, types = engine.types }).screen()
				end)
				local checkout, compact = world.find("Checkout"), world.find("Compact")
				local compactSummary = world.find("Summary", compact)
				Verify.expect((compact:GetAttribute("FacetSummary"))):toBe("Step 2 of 4 — Shipping")
				world.find("Step-pay", checkout).Activated.fire()
				Verify.expect((compact:GetAttribute("FacetSummary"))):toBe("Step 3 of 4 — Payment")
				Verify.expect(compactSummary.Text):toBe("Step 3 of 4 — Payment")
				world.find("Refuse").Activated.fire()
				world.find("Step-cart", checkout).Activated.fire()
				Verify.expect((compact:GetAttribute("FacetSummary"))):toBe("Step 3 of 4 — Payment")
				Verify.expect(world.find("Step-pay", checkout):FindFirstChild("State", true).Text):toBe("Error")
				world.stop()
			end,
		})
	end)

	return nil
end
