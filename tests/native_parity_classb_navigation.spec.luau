--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	type World = {
		engine: any,
		runtime: any,
		gui: any,
		input: any,
		inputParent: any,
		screen: any,
		stop: () -> (),
	}

	local function setup(build: (any, any, any) -> any, options: { [string]: any }?): World
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local inputParent = engine.new("Folder")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			inputParent = inputParent,
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, screen: any = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host, engine) })
		end, engine.new("Folder"))
		return {
			engine = engine,
			runtime = runtime,
			gui = gui,
			input = input,
			inputParent = inputParent,
			screen = screen,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function find(root: any, name: string): any
		if root.Name == name then
			return root
		end
		for _, child in root:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	local function tagged(root: any, tag: string): { any }
		local out = {}
		for _, node in root:GetDescendants() do
			if node:HasTag(tag) then
				table.insert(out, node)
			end
		end
		return out
	end

	local function within(node: any, ancestor: any): boolean
		while node do
			if node == ancestor then
				return true
			end
			node = node.Parent
		end
		return false
	end

	local function sheetFor(engine: any, runtime: any, package: any): (any, () -> ())
		local stop, sheet: any = runtime.mount(function()
			return themes.createStyleSheet(runtime, package, { types = engine.types, motionLevel = "none" } :: any)
		end, engine.new("Folder"))
		return sheet, stop
	end

	local function rule(sheet: any, selector: string): { [string]: any }?
		local found
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				found = node
			end
		end
		return if found then found:GetProperties() else nil
	end

	local function priority(sheet: any, selector: string): number
		local best = -math.huge
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				best = math.max(best, node.Priority)
			end
		end
		return best
	end

	local function radiusPackage(control: number): any
		return assert(themes.define({
			identity = { id = `classb-radius-{control}` },
			metrics = { radii = { control = control, panel = 12, pill = 999 } },
		} :: any))
	end

	local function skinnedPackage(): any
		local package = themes.neutralPackage()
		package.assets = package.assets or {}
		assert(package.assets).controlArt = { content = "rbxassetid://7" }
		assert(package.chrome).control = { kind = "nineSlice" :: "nineSlice", asset = "controlArt" }
		return package
	end

	verifyHarness:suite("native parity classb navigation", function()
		verifyHarness:case("mounts a nameplate in a BillboardGui and updates its health text in place", {
			id = "native_parity_classb_navigation::native parity classb navigation::mounts a nameplate in a BillboardGui and updates its health text in place",
			run = function()
				local health = Compose.cell("100")
				local billboard
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					billboard = Host.BillboardGui({
						Name = "Nameplate",
						Size = engine.types.UDim2.fromOffset(300, 96),
						UI.VStack("Plate")({
							padding = 8,
							gap = 4,
							width = "fill" :: "fill",
							UI.Text("Name")({ text = "Razz Raccoon", TextSize = 18 }) :: unknown,
							UI.Text("Health")({ text = health, TextSize = 14 }),
						}),
					})
					return billboard
				end)
				Verify.expect(billboard.ClassName):toBe("BillboardGui")
				local plate = find(billboard, "Plate")
				local padding = plate:FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingLeft.Offset):toBe(8)
				Verify.expect(padding.PaddingTop.Offset):toBe(8)
				Verify.expect(padding.PaddingRight.Offset):toBe(8)
				Verify.expect(plate:FindFirstChildWhichIsA("UIListLayout").Padding.Offset):toBe(4)
				local label = find(plate, "Health")
				Verify.expect(label.Text):toBe("100")
				Verify.expect(find(plate, "Name").LayoutOrder < label.LayoutOrder):toBe(true)
				local made = #world.engine.made
				health:set("87")
				Verify.expect(label.Text):toBe("87")
				Verify.expect((find(plate, "Health"))):toBe(label)
				Verify.expect(#world.engine.made):toBe(made)
				world.stop()
			end,
		})

		verifyHarness:case(
			"insets the segment corner by the 3 pixel inset of the track for square, rounded and round themes",
			{
				id = "native_parity_classb_navigation::native parity classb navigation::insets the segment corner by the 3 pixel inset of the track for square, rounded and round themes",
				run = function()
					for _, control in { 0, 8, 999 } do
						local world = setup(function()
							return nil
						end)
						local sheet, stop = sheetFor(world.engine, world.runtime, radiusPackage(control))
						local track = rule(sheet, ".facet-segmented::UICorner")
						local fill = rule(sheet, ".facet-segment::UICorner")
						local rounded = if control > 0 then control + 2 else 0
						Verify.expect(track and track.CornerRadius.Offset):toBe(rounded)
						Verify.expect(fill and fill.CornerRadius.Offset):toBe(math.max(0, rounded - 3))
						local padding = rule(sheet, ".facet-segmented::UIPadding")
						Verify.expect(padding and padding.PaddingTop.Offset):toBe(3)
						stop()
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"gives the segments of a pill strip a capsule corner and of a square strip a square corner",
			{
				id = "native_parity_classb_navigation::native parity classb navigation::gives the segments of a pill strip a capsule corner and of a square strip a square corner",
				run = function()
					for _, corners in { "pill", "square" } do
						local world = setup(function(UI: FacetControls)
							return UI.Picker({
								selected = Compose.cell("a"),
								style = "segmented" :: "segmented",
								corners = corners :: "pill" | "square",
								options = {
									{ value = "a", label = "One" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "Two" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							})
						end)
						local strip = tagged(world.screen, "facet-segmented")[1]
						Verify.expect((strip:HasTag("facet-segmented-" .. corners))):toBe(true)
						Verify.expect(find(strip, "Corners").CornerRadius.Scale)
							:toBe(if corners == "pill" then 1 else 0)
						local sheet, stop = sheetFor(world.engine, world.runtime, radiusPackage(8))
						local inner = rule(sheet, ".facet-segmented-" .. corners .. " >> .facet-segment::UICorner")
						Verify.expect(inner and inner.CornerRadius.Scale):toBe(if corners == "pill" then 1 else 0)
						Verify.expect(inner and inner.CornerRadius.Offset):toBe(0)
						Verify.expect(
							priority(sheet, ".facet-segmented-" .. corners .. " >> .facet-segment::UICorner")
								> priority(sheet, ".facet-segment::UICorner")
						):toBe(true)
						local fill = find(strip, "SelectionFill")
						Verify.expect(fill ~= nil and fill:FindFirstChildWhichIsA("UICorner")):toBe(nil)
						local highlight =
							rule(sheet, ".facet-segmented-" .. corners .. " >> .facet-segment-fill::UICorner")
						Verify.expect(highlight and highlight.CornerRadius.Scale)
							:toBe(if corners == "pill" then 1 else 0)
						stop()
						world.stop()
					end
					local plain = setup(function(UI: FacetControls)
						return UI.Picker({
							selected = Compose.cell("a"),
							style = "segmented" :: "segmented",
							options = {
								{ value = "a", label = "One" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Two" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						})
					end)
					local strip = tagged(plain.screen, "facet-segmented")[1]
					Verify.expect(strip:HasTag("facet-segmented-pill") or strip:HasTag("facet-segmented-square"))
						:toBe(false)
					plain.stop()
				end,
			}
		)

		verifyHarness:case(
			"keeps the accent plate and hides the control art under the current segment of a skinned theme",
			{
				id = "native_parity_classb_navigation::native parity classb navigation::keeps the accent plate and hides the control art under the current segment of a skinned theme",
				run = function()
					local package = skinnedPackage()
					local world = setup(function(UI: FacetControls)
						return UI.Picker({
							selected = Compose.cell("full"),
							style = "segmented" :: "segmented",
							options = {
								{ value = "full", label = "Full" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "reduced", label = "Reduced" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						})
					end, { theme = package })
					local current = tagged(world.screen, "facet-segment-current")
					Verify.expect(#current):toBe(1)
					Verify.expect((current[1]:HasTag("facet-skinned"))):toBe(true)
					Verify.expect(current[1]:FindFirstChild("SkinBoundary") ~= nil):toBe(true)
					local sheet, stop = sheetFor(world.engine, world.runtime, package)
					local plate = rule(sheet, ".facet-segment-current.facet-skinned")
					Verify.expect(plate and plate.BackgroundTransparency):toBe(0)
					Verify.expect(
						priority(sheet, ".facet-segment-current.facet-skinned") > priority(sheet, ".facet-skinned")
					)
						:toBe(true)
					local art = rule(sheet, ".facet-segment-current > #SkinBoundary")
					Verify.expect(art and art.Visible):toBe(false)
					local accent = rule(sheet, ".facet-segment-current")
					local ink = rule(sheet, ".facet-segment-current >> .facet-button-caption")
					Verify.expect(accent and accent.BackgroundTransparency):toBe(0)
					Verify.expect(ink and ink.TextColor3):toEqual(accent and accent.TextColor3)
					stop()
					world.stop()
				end,
			}
		)

		verifyHarness:case("parents the underline to the chosen option in whichever home the strip mounts", {
			id = "native_parity_classb_navigation::native parity classb navigation::parents the underline to the chosen option in whichever home the strip mounts",
			run = function()
				local atTop, selected = Compose.cell(true), Compose.cell("a")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local function strip()
						return UI.Picker("Strip")({
							selected = selected,
							style = "inline" :: "inline",
							indicator = "underline" :: "underline",
							axis = "x" :: "x",
							options = {
								{ value = "a", label = "Alpha" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Beta" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						})
					end
					return Host.Frame({
						Host.Frame({ Name = "Top", Compose.show(atTop, strip) }) :: unknown,
						Host.Frame({
							Name = "Bottom",
							Compose.show(function(use: Use)
								return not use(atTop)
							end, strip),
						}),
					})
				end)
				local function underline(): any
					local found = {}
					for _, node in world.screen:GetDescendants() do
						if node.Name == "SelectionIndicator" then
							table.insert(found, node)
						end
					end
					Verify.expect(#found):toBe(1)
					return found[1]
				end
				local top = find(world.screen, "Top")
				local bottom = find(world.screen, "Bottom")
				local first = underline()
				Verify.expect(first.Parent.Name):toBe("a")
				Verify.expect((within(first, top))):toBe(true)
				atTop:set(false)
				Verify.expect((find(top, "Strip"))):toBeNil()
				local moved = underline()
				Verify.expect((within(moved, bottom))):toBe(true)
				Verify.expect(moved.Parent.Name):toBe("a")
				Verify.expect(moved.Size.X.Scale):toBe(1)
				selected:set("b")
				local after = underline()
				Verify.expect((within(after, bottom))):toBe(true)
				Verify.expect(after.Parent.Name):toBe("b")
				world.stop()
			end,
		})

		verifyHarness:case("reorders customized tabs by moving the same buttons without rebuilding the page", {
			id = "native_parity_classb_navigation::native parity classb navigation::reorders customized tabs by moving the same buttons without rebuilding the page",
			run = function()
				local order, builds = Compose.cell({ "home", "feed", "me" }), 0
				local world = setup(function(UI: FacetControls)
					return UI.TabView({
						selection = Compose.cell("home"),
						placement = "bottomBar" :: "bottomBar",
						customization = function(use: Use): { order: { string }?, hidden: { string }? }
							return { order = use(order) }
						end,
						tabs = {
							{
								id = "home",
								label = "Home",
								content = function(): Instance
									builds += 1
									return UI.Button("First")({ label = "First" })
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "feed",
								label = "Feed",
								content = function(): Instance
									return UI.Text({ text = "Feed" })
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "me",
								label = "Me",
								content = function(): Instance
									return UI.Text({ text = "Me" })
								end,
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local strip = find(world.screen, "Tabs")
				local buttons = {
					home = strip:FindFirstChild("home"),
					feed = strip:FindFirstChild("feed"),
					me = strip:FindFirstChild("me"),
				}
				local first = find(world.screen, "First")
				Verify.expect(buttons.home.LayoutOrder < buttons.me.LayoutOrder):toBe(true)
				order:set({ "me", "feed", "home" })
				Verify.expect((strip:FindFirstChild("home"))):toBe(buttons.home)
				Verify.expect((strip:FindFirstChild("me"))):toBe(buttons.me)
				Verify.expect(buttons.me.LayoutOrder < buttons.feed.LayoutOrder):toBe(true)
				Verify.expect(buttons.feed.LayoutOrder < buttons.home.LayoutOrder):toBe(true)
				Verify.expect((find(world.screen, "First"))):toBe(first)
				Verify.expect(builds):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("lets Tab walk both nested tab strips and the page in one open order without a trap", {
			id = "native_parity_classb_navigation::native parity classb navigation::lets Tab walk both nested tab strips and the page in one open order without a trap",
			run = function()
				local outerSelection, innerSelection = Compose.cell("discover"), Compose.cell("foryou")
				local world = setup(function(UI: FacetControls)
					return UI.TabView("App")({
						selection = outerSelection,
						placement = "bottomBar" :: "bottomBar",
						tabs = {
							{
								id = "discover",
								label = "Discover",
								content = function(): Instance
									return UI.TabView("Inner")({
										selection = innerSelection,
										tabs = {
											{
												id = "foryou",
												label = "For you",
												content = function(): Instance
													return UI.Button("Play")({ label = "Play" })
												end,
											} :: FixtureNavigationTypes.Tab,
											{
												id = "charts",
												label = "Charts",
												content = function(): Instance
													return UI.Text({ text = "Charts" })
												end,
											} :: FixtureNavigationTypes.Tab,
										},
									})
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "me",
								label = "Me",
								content = function(): Instance
									return UI.Text({ text = "Me" })
								end,
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local app = find(world.screen, "App")
				local inner = find(world.screen, "Inner")
				local outerStrip = app:FindFirstChild("Tabs")
				local innerStrip = inner:FindFirstChild("Tabs")
				Verify.expect(outerStrip.Position.Y.Scale):toBe(1)
				Verify.expect(innerStrip.Position.Y.Scale):toBe(0)
				local traverse
				for _, node in world.inputParent:GetDescendants() do
					if node.Name == "Traverse" then
						traverse = node
					end
				end
				local visited = {}
				for _ = 1, 12 do
					traverse.Pressed.fire()
					local selected = world.gui.SelectedObject
					local label = if within(selected, innerStrip)
						then "inner:" .. selected.Name
						elseif within(selected, outerStrip) then "outer:" .. selected.Name
						else "page:" .. selected.Name
					if visited[1] == label then
						break
					end
					table.insert(visited, label)
				end
				table.sort(visited)
				Verify.expect(visited)
					:toEqual({ "inner:charts", "inner:foryou", "outer:discover", "outer:me", "page:Play" })
				local innerAt, pageAt = nil, nil
				world.gui.SelectedObject = nil
				for index = 1, 5 do
					traverse.Pressed.fire()
					local selected = world.gui.SelectedObject
					if within(selected, innerStrip) and innerAt == nil then
						innerAt = index
					elseif selected.Name == "Play" then
						pageAt = index
					end
				end
				Verify.expect(innerAt ~= nil and pageAt ~= nil and innerAt < pageAt):toBe(true)
				for _, node in { app, inner, outerStrip, innerStrip } do
					Verify.expect(
						node.SelectionGroup == true
							and node.SelectionBehaviorUp == world.engine.types.Enum.SelectionBehavior.Stop
					):toBe(false)
					Verify.expect((node:GetAttribute("FacetSelectionOwner"))):toBeNil()
				end
				world.stop()
			end,
		})

		verifyHarness:case("paints the ring fill above its track by explicit Path2D ZIndex", {
			id = "native_parity_classb_navigation::native parity classb navigation::paints the ring fill above its track by explicit Path2D ZIndex",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.ProgressView({ presentation = "circular" :: "circular", value = Compose.cell(0.5) })
				end)
				local track = find(world.screen, "RingTrack")
				local fill = find(world.screen, "RingFill")
				Verify.expect(track.ClassName):toBe("Path2D")
				Verify.expect(fill.ClassName):toBe("Path2D")
				Verify.expect(track.Parent):toBe(fill.Parent)
				Verify.expect(track.ZIndex):toBe(1)
				Verify.expect(fill.ZIndex):toBe(2)
				Verify.expect(fill.ZIndex > track.ZIndex):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("leaves the engine selection image in place on selectable controls in every theme", {
			id = "native_parity_classb_navigation::native parity classb navigation::leaves the engine selection image in place on selectable controls in every theme",
			run = function()
				local packages = { themes.neutralPackage() }
				for _, name in { "fantasy_ornate", "scifi_hud", "fantasy_parchment" } do
					table.insert(packages, ((require :: any)("../examples/themes/" .. name).build(themes)))
				end
				for _, package in packages do
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Button({ label = "Go" }) :: unknown,
							UI.Toggle({ label = "Sound", value = Compose.cell(true) }),
							UI.Picker({
								selected = Compose.cell("a"),
								style = "segmented" :: "segmented",
								options = {
									{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							}),
							UI.Slider({ value = Compose.cell(0.5) }),
						})
					end, { theme = package })
					local selectable = 0
					for _, node in world.screen:GetDescendants() do
						if node:IsA("GuiObject") and node.Selectable then
							selectable += 1
							Verify.expect(node.SelectionImageObject):toBeNil()
						end
					end
					Verify.expect(selectable >= 5):toBe(true)
					world.stop()
				end
			end,
		})
	end)
end
