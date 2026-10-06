--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local worlds = require("./lib/content_world")
	local overlay = require("./lib/overlay_world")
	local Vector2 = require("@lune/roblox").Vector2
	local Compose: ComposeModule = Facet.Compose

	local PREVIEW = 0.62

	local function scaleProbes(world: any, factor: number)
		for _, node in world.screen:GetDescendants() do
			if node.Name == "LayoutUnit" then
				node.AbsoluteSize = world.V2(100 * factor, factor)
			end
		end
	end

	local function both(label: string, run: (factor: number) -> string)
		local plain, scaled = run(1), run(PREVIEW)
		Verify.expect(`{label} at {PREVIEW}: {scaled}`):toBe(`{label} at {PREVIEW}: {plain}`)
	end

	verifyHarness:suite("layout decisions under a preview UIScale", function()
		verifyHarness:case("a nested TabView collapses and places its strip as it does unscaled", {
			id = "native_layout_unit::layout decisions under a preview UIScale::a nested TabView collapses and places its strip as it does unscaled",
			run = function()
				for _, height in { 360, 240 } do
					both(`TabView {height}`, function(factor)
						local world: any = worlds.new(function(UI: FacetControls, Host: RobloxHost)
							return UI.TabView {
								selection = Compose.cell("a"),
								tabs = {
									{
										id = "a",
										content = function(): Instance
											return UI.TabView "Inner" {
												selection = Compose.cell("x"),
												tabs = {
													{ id = "x", label = "Swipe actions", content = Host.Frame "X" {} } :: FixtureNavigationTypes.Tab,
													{ id = "y", label = "Permissions", content = Host.Frame "Y" {} } :: FixtureNavigationTypes.Tab,
												},
											}
										end,
									} :: FixtureNavigationTypes.Tab,
								},
							}
						end)
						local nested = world.find("Inner")
						scaleProbes(world, factor)
						nested.AbsoluteSize = world.V2(705 * factor, height * factor)
						local out = `menu {world.find("TabsMenu", nested) ~= nil}`
						world.stop()
						return out
					end)
				end
			end,
		})

		verifyHarness:case("an environment read from a scaled frame keeps its size class", {
			id = "native_layout_unit::layout decisions under a preview UIScale::an environment read from a scaled frame keeps its size class",
			run = function()
				for _, width in { 389, 700, 1200 } do
					both(`environment {width}`, function(factor)
						local class = "?"
						local world: any = worlds.new(function(UI: FacetControls, Host: RobloxHost)
							local frame = Host.Frame "Region" {}
							local env = UI.environment(frame)
							Compose.watch(function(use: Use)
								class = use(env.sizeClass)
							end)
							return frame
						end)
						scaleProbes(world, factor)
						world.find("Region").AbsoluteSize = world.V2(width * factor, 800 * factor)
						local out = class
						world.stop()
						return out
					end)
				end
			end,
		})

		verifyHarness:case("Pagination keeps the same page window", {
			id = "native_layout_unit::layout decisions under a preview UIScale::Pagination keeps the same page window",
			run = function()
				for _, width in { 360, 240, 120 } do
					both(`Pagination {width}`, function(factor)
						local world: any = worlds.new(function(UI: FacetControls)
							return UI.Pagination "P" {
								page = Compose.cell(5000),
								pageCount = 9999,
								onChange = function() end,
							}
						end)
						scaleProbes(world, factor)
						local root = world.find("P")
						world.bounds(root:FindFirstChild("DigitMeasure"), 100 * factor, 20 * factor)
						world.bounds(root:FindFirstChild("EllipsisMeasure"), 10 * factor, 20 * factor)
						world.resize(root, width * factor, 44 * factor)
						local shown = {}
						for _, child in root:FindFirstChild("Row"):GetChildren() do
							if child:IsA("GuiObject") and child.Visible then
								table.insert(shown, child.Name)
							end
						end
						table.sort(shown)
						world.stop()
						return table.concat(shown, ",")
					end)
				end
			end,
		})

		verifyHarness:case("a Sheet's measured scroller sets its canvas to the whole content, rounded up", {
			id = "native_layout_unit::layout decisions under a preview UIScale::a Sheet's measured scroller sets its canvas to the whole content, rounded up",
			run = function()
				both("Sheet canvas", function(factor)
					local world: any = worlds.new(function(UI: FacetControls, Host: RobloxHost)
						return UI.Sheet "Briefing" {
							isPresented = Compose.cell(true),
							detent = Compose.cell("medium"),
							content = function(): Instance
								return Host.Frame "Details" {}
							end,
						}
					end)
					scaleProbes(world, factor)
					local body = world.find("SheetContent")
					world.resize(body:FindFirstChild("SheetFlow", true), 347 * factor, 292.8 * factor)
					local out = tostring(body.CanvasSize.Y.Offset)
					world.stop()
					return out
				end)
				local world: any = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet "Briefing" {
						isPresented = Compose.cell(true),
						detent = Compose.cell("medium"),
						content = function(): Instance
							return Host.Frame "Details" {}
						end,
					}
				end)
				local body = world.find("SheetContent")
				world.resize(body:FindFirstChild("SheetFlow", true), 347, 292.8)
				Verify.expect(body.CanvasSize.Y.Offset):toBe(293)
				world.stop()
			end,
		})

		verifyHarness:case("StepIndicator picks the row or the summary as it does unscaled", {
			id = "native_layout_unit::layout decisions under a preview UIScale::StepIndicator picks the row or the summary as it does unscaled",
			run = function()
				for _, width in { 900, 300 } do
					both(`StepIndicator {width}`, function(factor)
						local world: any = worlds.new(function(UI: FacetControls)
							return UI.StepIndicator "Steps" {
								steps = {
									{ id = "cart", label = "Cart" },
									{ id = "ship", label = "Shipping" },
									{ id = "pay", label = "Payment" },
									{ id = "done", label = "Review" },
								},
								current = Compose.cell("ship"),
							}
						end)
						scaleProbes(world, factor)
						local root = world.find("Steps")
						for _, node in root:GetDescendants() do
							if node.Name == "Measure" then
								world.bounds(node, 90 * factor, 20 * factor)
							end
						end
						world.resize(root, width * factor, 80 * factor)
						local out = tostring(root:GetAttribute("FacetForm"))
						world.stop()
						return out
					end)
				end
			end,
		})
		verifyHarness:case("a HUD Composition picks the same region forms", {
			id = "native_layout_unit::layout decisions under a preview UIScale::a HUD Composition picks the same region forms",
			run = function()
				local sizes: { [string]: { number } } = {
					TasksFull = { 240, 130 },
					TasksChip = { 90, 44 },
					ClockFull = { 170, 60 },
					ClockChip = { 80, 44 },
					RailFull = { 130, 132 },
					RailChip = { 80, 44 },
				}
				for _, box in { { 844, 330 }, { 844, 230 }, { 390, 780 } } do
					both(`Composition {box[1]}x{box[2]}`, function(factor)
						local world: any = worlds.new(function(UI: FacetControls, Host: RobloxHost)
							local function form(name: string): any
								return Host.Frame { Name = name }
							end
							return UI.Composition "Hud" {
								gap = 8,
								padding = 0,
								UI.Region "Tasks" {
									zone = "left" :: "left",
									rank = 3,
									form("TasksFull") :: unknown,
									form("TasksChip"),
								} :: unknown,
								UI.Region "Clock" {
									zone = "top" :: "top",
									rank = 1,
									form("ClockFull") :: unknown,
									form("ClockChip"),
								},
								UI.Region "Rail" {
									zone = "topRight" :: "topRight",
									rank = 2,
									form("RailFull") :: unknown,
									form("RailChip"),
								},
							}
						end)
						scaleProbes(world, factor)
						for name, size in sizes do
							world.resize(world.find(name), size[1] * factor, size[2] * factor)
						end
						world.resize(world.find("Zones"), box[1] * factor, box[2] * factor)
						local out = {}
						for _, name in { "Tasks", "Clock", "Rail" } do
							table.insert(out, `{name}={world.find(name):GetAttribute("FacetForm")}`)
						end
						world.stop()
						return table.concat(out, ",")
					end)
				end
			end,
		})
		verifyHarness:case("a hugging PageView sizes its pages and footer as it does unscaled", {
			id = "native_layout_unit::layout decisions under a preview UIScale::a hugging PageView sizes its pages and footer as it does unscaled",
			run = function()
				both("PageView", function(factor)
					local world: any = worlds.new(function(UI: FacetControls, Host: RobloxHost, engine)
						return UI.PageView {
							Size = engine.types.UDim2.new(1, 0, 0, 0),
							AutomaticSize = engine.types.Enum.AutomaticSize.Y,
							selection = Compose.cell("one"),
							pages = {
								{ id = "one", title = "One", content = Host.Frame "BodyOne" {} } :: FixtureNavigationTypes.Tab,
								{ id = "two", title = "Two", content = Host.Frame "BodyTwo" {} } :: FixtureNavigationTypes.Tab,
							},
						}
					end)
					scaleProbes(world, factor)
					world.resize(world.find("BodyOne"), 300 * factor, 180 * factor)
					world.resize(world.find("BodyTwo"), 300 * factor, 212 * factor)
					local out = `{world.find("Pages").Size} {world.find("Footer").Position}`
					world.stop()
					return out
				end)
			end,
		})
		verifyHarness:case("a Toast with an action places it beside or below the copy as it does unscaled", {
			id = "native_layout_unit::layout decisions under a preview UIScale::a Toast with an action places it beside or below the copy as it does unscaled",
			run = function()
				for _, copy in { 120, 250 } do
					both(`Toast {copy}`, function(factor)
						local w = overlay.new(function(UI: FacetControls)
							return UI.Toast "Saved" {
								isPresented = Compose.cell(true),
								onPresentedChange = function() end,
								message = "Saved to garage",
								action = { label = "Undo", onActivate = function() end },
							}
						end, { size = Vector2.new(390 * factor, 844 * factor), motionLevel = "none" })
						for _, node in w.screen:GetDescendants() do
							if node.Name == "LayoutUnit" then
								node.AbsoluteSize = w.Vector2.new(100 * factor, factor)
							end
						end
						local row = w.find("Snack")
						overlay.find(row, "Action").AbsoluteSize = w.Vector2.new(100 * factor, 44 * factor)
						overlay.find(row, "MessageMeasure").TextBounds = w.Vector2.new(copy * factor, 18 * factor)
						local out =
							tostring(overlay.find(row, "Body"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
						w.stop()
						return out
					end)
				end
			end,
		})
	end)
end
