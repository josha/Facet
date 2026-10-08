--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

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
					cell(world, "pay").Activated:Fire()
					Verify.expect((table.concat(asked, ","))):toBe("pay")
					Verify.expect((root:GetAttribute("FacetCurrent"))):toBe("ship")
					Verify.expect((under("ship"))):toBe(true)
					accept = true
					cell(world, "pay").Activated:Fire()
					Verify.expect((root:GetAttribute("FacetCurrent"))):toBe("pay")
					Verify.expect((root:GetAttribute("FacetSummary"))):toBe("Step 3 of 4 — Payment")
					Verify.expect((under("pay"))):toBe(true)
					cell(world, "pay").Activated:Fire()
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
				world.find("ShowSteps"):FindFirstChild("Trigger").Activated:Fire()
				Verify.expect((root:GetAttribute("FacetListOpen"))):toBe(true)
				Verify.expect(#asked):toBe(0)
				refuse = true
				world.find("Item-cart", world.screen.Parent).Activated:Fire()
				Verify.expect((root:GetAttribute("FacetListOpen"))):toBe(true)
				Verify.expect(world.find("Item-done", world.screen.Parent).Selectable):toBe(false)
				refuse = false
				world.find("Item-pay", world.screen.Parent).Activated:Fire()
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
				world.find("Step-pay").Activated:Fire()
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
				world.find("Step-pay", checkout).Activated:Fire()
				Verify.expect((compact:GetAttribute("FacetSummary"))):toBe("Step 3 of 4 — Payment")
				Verify.expect(compactSummary.Text):toBe("Step 3 of 4 — Payment")
				world.find("Refuse").Activated:Fire()
				world.find("Step-cart", checkout).Activated:Fire()
				Verify.expect((compact:GetAttribute("FacetSummary"))):toBe("Step 3 of 4 — Payment")
				Verify.expect(world.find("Step-pay", checkout):FindFirstChild("State", true).Text):toBe("Error")
				world.stop()
			end,
		})
	end)

	return nil
end
