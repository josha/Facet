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
