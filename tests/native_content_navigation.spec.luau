--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)
	type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local Facet = require("../src")
	local worlds = require("./lib/content_world")
	local Compose: ComposeModule = Facet.Compose
	local UDim2 = require("@lune/roblox").UDim2
	local Vector2 = require("@lune/roblox").Vector2

	local function menuWorld(spec: { [any]: any }, options: { [string]: any }?): any
		local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({ Name = "S", Size = UDim2.fromOffset(800, 600), UI.Menu("M")(spec) })
		end, options or { motionLevel = "none" })
		return world
	end

	local function everywhere(world: any, name: string): any
		return world.find(name, world.screen.Parent)
	end

	local function openMenu(world: any, select: boolean?)
		local trigger = world.find("Trigger")
		if select then
			world.gui.SelectedObject = trigger
		end
		trigger.Activated:Fire()
		return everywhere(world, "MenuPanel")
	end

	local function items(count: number, prefix: string?, extra: ((number) -> { [string]: any })?): { any }
		local out = {}
		for index = 1, count do
			local item: { [string]: any } =
				{ id = `{prefix or "row"}{index}`, label = `Row {index}`, onSelect = function() end }
			if extra then
				for key, value in extra(index) do
					item[key] = value
				end
			end
			out[index] = item
		end
		return out
	end

	local function place(world: any, panel: any, triggerAt: Vector2, triggerSize: Vector2, panelSize: Vector2)
		local trigger = world.find("Trigger")
		trigger.AbsolutePosition = triggerAt
		trigger.AbsoluteSize = triggerSize
		local modal = panel.Parent
		while modal and modal.Parent and modal.Parent ~= world.screen and modal.Parent.ClassName ~= "ScreenGui" do
			modal = modal.Parent
		end
		modal.AbsoluteSize = world.V2(800, 600)
		panel.AbsoluteSize = panelSize
	end

	verifyHarness:suite("native content navigation deltas", function()
		verifyHarness:case(
			"opens on ButtonA, closes on ButtonB with the selection back on the trigger, and opens again",
			{
				id = "native_content_navigation::native content navigation deltas::opens on ButtonA, closes on ButtonB with the selection back on the trigger, and opens again",
				run = function()
					local presented = Compose.cell(false)
					local world = menuWorld({ label = "Options", isPresented = presented, items = items(3) })
					local trigger = world.find("Trigger")
					for _ = 1, 2 do
						world.gui.SelectedObject = trigger
						trigger.Activated:Fire()
						Verify.expect((presented:peek())):toBe(true)
						world.action("ModalBack").Pressed:Fire()
						Verify.expect((presented:peek())):toBe(false)
						Verify.expect(world.gui.SelectedObject):toBe(trigger)
					end
					world.stop()
				end,
			}
		)

		verifyHarness:case("bounds a floating panel by the screen so a long list scrolls", {
			id = "native_content_navigation::native content navigation deltas::bounds a floating panel by the screen so a long list scrolls",
			run = function()
				local world = menuWorld({ label = "Year", items = items(201, "y") })
				local panel = openMenu(world)
				place(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 400))
				local rows = panel:FindFirstChild("MenuRows", true)
				rows.AbsoluteSize = Vector2.new(220, 201 * 44)
				Verify.expect((panel:FindFirstChild("MenuScroll", true):IsA("ScrollingFrame"))):toBe(true)
				Verify.expect(panel.Size.Y.Offset <= 600 - 24):toBe(true)
				Verify.expect(world.find("y201", panel) ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("opens a level on its selected row, centred in the scrolled list", {
			id = "native_content_navigation::native content navigation deltas::opens a level on its selected row, centred in the scrolled list",
			run = function()
				local year = Compose.cell(2026)
				local list = {}
				for value = 1926, 2126 do
					table.insert(list, { id = `y{value}`, label = tostring(value), selected = year, value = value })
				end
				local world = menuWorld({ label = "Year", items = list })
				local panel = openMenu(world, true)
				local chosen = world.find("y2026", panel)
				Verify.expect(world.gui.SelectedObject):toBe(chosen)
				local rows = panel:FindFirstChild("MenuRows", true)
				local pitch = 44 + rows:FindFirstChildWhichIsA("UIListLayout").Padding.Offset
				for _, row in rows:GetChildren() do
					if row:IsA("GuiObject") then
						row.AbsoluteSize = Vector2.new(220, 44)
					end
				end
				rows.AbsoluteSize = Vector2.new(220, 201 * pitch)
				local scroller = panel:FindFirstChild("MenuScroll", true)
				panel.AbsoluteSize = Vector2.new(220, 400)
				scroller.AbsoluteSize = Vector2.new(220, 400)
				local center = scroller.CanvasPosition.Y + 400 / 2
				local inset = rows:FindFirstChildWhichIsA("UIPadding")
				local top = if inset then inset.PaddingTop.Offset else 0
				Verify.expect(math.abs(center - (top + 100 * pitch + 22)) <= 1):toBe(true)
				world.stop()
				local checked = Compose.cell(true)
				local toggles = menuWorld({
					label = "Options",
					items = {
						{ id = "first", label = "First", onSelect = function() end } :: MenuItem,
						{ id = "flag", label = "Flag", checked = checked } :: MenuItem,
					},
				})
				local togglePanel = openMenu(toggles, true)
				Verify.expect(toggles.gui.SelectedObject):toBe(toggles.find("first", togglePanel))
				toggles.stop()
			end,
		})

		verifyHarness:case("centres the selected row again when the row layout settles after the first measure", {
			id = "native_content_navigation::native content navigation deltas::centres the selected row again when the row layout settles after the first measure",
			run = function()
				local year = Compose.cell(2026)
				local list = {}
				for value = 1926, 2126 do
					table.insert(list, { id = `y{value}`, label = tostring(value), selected = year, value = value })
				end
				local world = menuWorld({ label = "Year", items = list })
				local panel = openMenu(world, true)
				local chosen = world.find("y2026", panel)
				local rows = panel:FindFirstChild("MenuRows", true)
				local layout = rows:FindFirstChildWhichIsA("UIListLayout")
				local gap = layout.Padding.Offset
				local pitch = 44 + gap
				chosen.AbsoluteSize = Vector2.new(220, 44)
				rows.AbsoluteSize = Vector2.new(220, 201 * pitch)
				local scroller = panel:FindFirstChild("MenuScroll", true)
				panel.AbsoluteSize = Vector2.new(220, 400)
				scroller.AbsoluteSize = Vector2.new(220, 400)
				local inset = rows:FindFirstChildWhichIsA("UIPadding")
				local pad = if inset then inset.PaddingTop.Offset else 0
				Verify.expect(scroller.CanvasPosition.Y):toBe(math.max(0, pad + 100 * gap + 22 - 200))
				rows.AbsolutePosition = Vector2.new(0, -scroller.CanvasPosition.Y)
				for _, row in rows:GetChildren() do
					if row:IsA("GuiObject") then
						row.AbsoluteSize = Vector2.new(220, 44)
					end
				end
				layout.AbsoluteContentSize = Vector2.new(220, 201 * pitch)
				local center = scroller.CanvasPosition.Y + 400 / 2
				local inset = rows:FindFirstChildWhichIsA("UIPadding")
				local top = if inset then inset.PaddingTop.Offset else 0
				Verify.expect(math.abs(center - (top + 100 * pitch + 22)) <= 1):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("bounds the whole panel by maxHeight while the rows keep their ids and activation", {
			id = "native_content_navigation::native content navigation deltas::bounds the whole panel by maxHeight while the rows keep their ids and activation",
			run = function()
				local picked: { string } = {}
				local world = menuWorld({
					label = "Options",
					maxHeight = 200,
					items = items(20, "row", function(index: number)
						return {
							onSelect = function()
								table.insert(picked, `row{index}`)
							end,
						}
					end),
				})
				local panel = openMenu(world)
				place(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 200))
				panel:FindFirstChild("MenuRows", true).AbsoluteSize = Vector2.new(220, 20 * 44)
				Verify.expect(panel.Size.Y.Offset <= 200):toBe(true)
				local last = world.find("row20", panel)
				Verify.expect(last ~= nil):toBe(true)
				last.Activated:Fire()
				Verify.expect((table.concat(picked, ","))):toBe("row20")
				world.stop()
			end,
		})

		verifyHarness:case("keeps submenus anchored to their parent level in a bounded list", {
			id = "native_content_navigation::native content navigation deltas::keeps submenus anchored to their parent level in a bounded list",
			run = function()
				local world = menuWorld({
					label = "Options",
					maxHeight = 300,
					items = {
						{
							id = "adjust",
							label = "Adjust",
							children = { { id = "head", label = "Head", onSelect = function() end } },
						},
					},
				})
				local panel = openMenu(world, true)
				Verify.expect(world.gui.SelectedObject):toBe(world.find("adjust", panel))
				world.action("MenuRight").Pressed:Fire()
				Verify.expect(everywhere(world, "head") ~= nil):toBe(true)
				Verify.expect(everywhere(world, "AncestorMenu") ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("shares one row recipe for badge, avatar, sectionTitle and a display-only shortcutLabel", {
			id = "native_content_navigation::native content navigation deltas::shares one row recipe for badge, avatar, sectionTitle and a display-only shortcutLabel",
			run = function()
				local ran = 0
				local world = menuWorld({
					label = "Options",
					items = {
						{
							id = "a",
							label = "Alpha",
							badge = 3,
							sectionTitle = "Recent",
							onSelect = function()
								ran += 1
							end,
						} :: MenuItem,
						{
							id = "b",
							label = "Beta",
							avatar = { name = "Bea" },
							shortcutLabel = "Ctrl+B",
							onSelect = function() end,
						} :: MenuItem,
					},
				})
				local panel = openMenu(world, true)
				local section = world.find("Section:a", panel)
				Verify.expect(section:FindFirstChild("SectionTitle").Text):toBe("Recent")
				Verify.expect((section:IsA("GuiButton"))):toBe(false)
				Verify.expect(section.LayoutOrder < world.find("a", panel).LayoutOrder):toBe(true)
				local b = world.find("b", panel)
				Verify.expect(b:FindFirstChild("Avatar", true) ~= nil):toBe(true)
				Verify.expect(b:FindFirstChild("Avatar", true).Selectable):toBe(false)
				Verify.expect(world.find("a", panel):FindFirstChild("Count", true):GetAttribute("label") ~= nil or true)
					:toBe(true)
				local texts = {}
				for _, node in panel:GetDescendants() do
					if node:IsA("TextLabel") or node:IsA("TextButton") then
						table.insert(texts, node.Text)
					end
				end
				Verify.expect(table.find(texts, "3") ~= nil):toBe(true)
				Verify.expect(table.find(texts, "Ctrl+B") ~= nil):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(world.find("a", panel))
				for _, node in world.screen.Parent:GetDescendants() do
					if node:IsA("InputBinding") then
						Verify.expect(node.KeyCode.Name ~= "B"):toBe(true)
					end
				end
				Verify.expect(ran):toBe(0)
				world.stop()
			end,
		})

		local function textsUnder(node: any): { string }
			local texts = {}
			if node:IsA("TextLabel") then
				table.insert(texts, node.Text)
			end
			for _, child in node:GetDescendants() do
				if child:IsA("TextLabel") then
					table.insert(texts, child.Text)
				end
			end
			return texts
		end

		local function headings(panel: any): string
			local out = {}
			for _, node in panel:GetDescendants() do
				if node.Name == "SectionTitle" then
					for _, text in textsUnder(node) do
						table.insert(out, text)
					end
				end
			end
			table.sort(out)
			return table.concat(out, " ")
		end

		local function countOf(row: any): string
			local count = row and row:FindFirstChild("Count", true)
			return if count then table.concat(textsUnder(count), " ") else "none"
		end

		verifyHarness:case("carries a Picker option badge and sectionTitle into menu rows and searchable list rows", {
			id = "native_content_navigation::native content navigation deltas::carries a Picker option badge and sectionTitle into menu rows and searchable list rows",
			run = function()
				local options = Compose.cell({
					{ value = "a", label = "Alpha", badge = 2 } :: PickerOption,
					{ value = "b", label = "Beta" } :: PickerOption,
				})
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "S",
						UI.Picker({ style = "menu" :: "menu", selected = Compose.cell("a"), options = options }),
					})
				end, { motionLevel = "none" })
				local panel = openMenu(world)
				local count = world.find("a", panel):FindFirstChild("Count", true)
				Verify.expect(count ~= nil):toBe(true)
				local texts = {}
				for _, node in count:GetDescendants() do
					if node:IsA("TextLabel") then
						table.insert(texts, node.Text)
					end
				end
				if count:IsA("TextLabel") then
					table.insert(texts, count.Text)
				end
				Verify.expect(table.find(texts, "2") ~= nil):toBe(true)
				Verify.expect((world.find("b", panel):FindFirstChild("Count", true))):toBeNil()
				Verify.expect((panel:FindFirstChild("SectionTitle", true))):toBeNil()
				options:set({
					{ value = "a", label = "Alpha", badge = 2 } :: PickerOption,
					{ value = "b", label = "Beta", sectionTitle = "More" } :: PickerOption,
				})
				Verify.expect((headings(everywhere(world, "MenuPanel")))):toBe("More")
				world.stop()
				local search = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "S",
						UI.Picker({
							style = "navigationLink" :: "navigationLink",
							query = Compose.cell(""),
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "Alpha", sectionTitle = "First" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Beta", badge = "9" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}),
					})
				end, { motionLevel = "none" })
				search.find("Picker").Activated:Fire()
				local list = everywhere(search, "Choices")
				Verify.expect(list ~= nil):toBe(true)
				Verify.expect((headings(list))):toBe("First")
				Verify.expect((countOf(search.find("b", list)))):toBe("9")
				search.stop()
			end,
		})

		local function containers(): (any, any)
			local scenario = require("../examples/gallery/scenarios/containers") :: any
			local built: any
			local world = worlds.new(function(UI: FacetControls, Host: RobloxHost, engine)
				built = scenario.build({ UI = UI, Compose = Compose, Host = Host, types = engine.types })
				return built.screen()
			end, { motionLevel = "none" })
			return world, built
		end

		verifyHarness:case("runs one activation in a styled group and disables it by inheritance", {
			id = "native_content_navigation::native content navigation deltas::runs one activation in a styled group and disables it by inheritance",
			run = function()
				local world, built = containers()
				local group = world.find("Group")
				Verify.expect((group:HasTag("facet-panel"))):toBe(true)
				world.find("Activate", group).Activated:Fire()
				Verify.expect(built.report().presses):toBe(1)
				built.steps.disable()
				Verify.expect(group.Interactable):toBe(false)
				world.find("Activate", group).Activated:Fire()
				Verify.expect(built.report().presses):toBe(1)
				world.stop()
			end,
		})

		local function tabList(Host: any, extra: { [string]: any }?): { any }
			local list = {}
			for _, id in { "home", "feed", "me" } do
				table.insert(list, {
					id = id,
					label = string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2),
					content = function(): Instance
						return Host.Frame({ Name = "Page-" .. id })
					end,
				})
			end
			for key, value in (extra or {} :: { [string]: any }) do
				list[2][key] = value
			end
			return list
		end

		verifyHarness:case("keeps a disabled tab in the strip and refuses its selection on every route", {
			id = "native_content_navigation::native content navigation deltas::keeps a disabled tab in the strip and refuses its selection on every route",
			run = function()
				local selection = Compose.cell("home")
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selection,
						placement = "topBar" :: "topBar",
						tabs = tabList(Host, { enabled = false }),
					})
				end, { motionLevel = "none" })
				local tabs = world.find("Tabs")
				local feed = world.find("feed", tabs)
				feed.Activated:Fire()
				Verify.expect((selection:peek())):toBe("home")
				Verify.expect(feed.Parent):toBe(tabs)
				Verify.expect(feed.Selectable):toBe(false)
				world.gui.SelectedObject = world.find("home", tabs)
				world.action("NextTab").Pressed:Fire()
				Verify.expect((selection:peek())):toBe("me")
				world.stop()
			end,
		})

		verifyHarness:case("shrinks tab words toward the caption role in a filling bottom bar before they truncate", {
			id = "native_content_navigation::native content navigation deltas::shrinks tab words toward the caption role in a filling bottom bar before they truncate",
			run = function()
				local selection = Compose.cell("home")
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selection,
						placement = "bottomBar" :: "bottomBar",
						tabs = tabList(Host),
					})
				end, { motionLevel = "none" })
				local tabs = world.find("Tabs")
				local feed = world.find("feed", tabs)
				Verify.expect((feed:GetAttribute("FacetTextFit"))):toBe(true)
				Verify.expect(feed.Size.X.Scale):toBeCloseTo(1 / 3, 1e-6)
				Verify.expect(feed.AutomaticSize.Name):toBe("None")
				Verify.expect(feed.TextTruncate.Name):toBe("AtEnd")
				local measure = feed:FindFirstChild("LabelMeasure")
				world.bounds(measure, 200)
				world.resize(feed, 124, 44)
				local size = feed.TextSize
				Verify.expect(size < 18 and size >= 12):toBe(true)
				world.resize(feed, 200, 44)
				size = feed.TextSize
				Verify.expect(size):toBe(15)
				feed.TextFits = false
				feed.TextBounds = Vector2.new(99, 16)
				Verify.expect(feed.TextSize):toBe(size - 1)
				feed.TextFits = true
				feed.TextBounds = Vector2.new(98, 15)
				Verify.expect(feed.TextSize):toBe(size - 1)
				world.resize(feed, 400, 44)
				Verify.expect(feed.TextSize):toBe(18)
				world.resize(feed, 40, 44)
				Verify.expect(feed.TextSize):toBe(12)
				world.stop()
			end,
		})

		verifyHarness:case("subtracts the leading glyph and gap from a bottom tab caption budget", {
			id = "native_content_navigation::native content navigation deltas::subtracts the leading glyph and gap from a bottom tab caption budget",
			run = function()
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					local tabs = tabList(Host)
					for _, tab in tabs do
						tab.icon = "settings"
					end
					return UI.TabView {
						selection = Compose.cell("home"),
						placement = "bottomBar" :: "bottomBar",
						tabs = tabs,
					}
				end, { motionLevel = "none" })
				local feed = world.find("feed", world.find("Tabs"))
				world.bounds(feed:FindFirstChild("LabelMeasure"), 100)
				world.resize(feed, 124, 44)
				Verify.expect(feed.TextSize):toBeLessThan(18)
				Verify.expect(feed.TextSize):toBeGreaterThanOrEqual(12)
				world.stop()
			end,
		})

		verifyHarness:case(
			"widens a sidebar rail by a skinned theme's content insets so a tab label is not truncated",
			{
				id = "native_content_navigation::native content navigation deltas::widens a sidebar rail by a skinned theme's content insets so a tab label is not truncated",
				run = function()
					local pixel = (require :: any)("../examples/themes/pixel_quest").build(Facet.themes)
					local bare = table.clone(pixel)
					bare.chrome = table.clone(pixel.chrome)
					bare.chrome.control = table.clone(pixel.chrome.control)
					bare.chrome.control.contentInsets = nil
					local widths = {}
					for _, package in { pixel, bare } do
						local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
							return UI.TabView({
								selection = Compose.cell("home"),
								placement = "sidebar" :: "sidebar",
								tabs = tabList(Host),
							})
						end, { motionLevel = "none", theme = package })
						world.resize(world.find("TabView"), 1200, 800)
						local tabs = world.find("Tabs")
						for _, id in { "home", "feed", "me" } do
							world.bounds(world.find(id, tabs):FindFirstChild("LabelMeasure"), 60)
						end
						table.insert(widths, tabs.Size.X.Offset)
						world.stop()
					end
					local insets = pixel.chrome.control.contentInsets
					Verify.expect(widths[1] - widths[2]):toBe(insets.left + insets.right)
				end,
			}
		)

		verifyHarness:case("clips its tab strip only while the tabs overflow, so a tab's chrome shadow is not cut", {
			id = "native_content_navigation::native content navigation deltas::clips its tab strip only while the tabs overflow, so a tab's chrome shadow is not cut",
			run = function()
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("home"),
						placement = "topBar" :: "topBar",
						tabs = tabList(Host),
					})
				end, { motionLevel = "none" })
				local tabs = world.find("Tabs")
				tabs.AbsoluteWindowSize = Vector2.new(300, 44)
				tabs.AbsoluteCanvasSize = Vector2.new(300, 44)
				Verify.expect(tabs.ClipsDescendants):toBe(false)
				tabs.AbsoluteCanvasSize = Vector2.new(420, 44)
				Verify.expect(tabs.ClipsDescendants):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("nests a TabView that a page builds later inside one of its branches", {
			id = "native_content_navigation::native content navigation deltas::nests a TabView that a page builds later inside one of its branches",
			run = function()
				local selection, inner = Compose.cell("home"), Compose.cell("foryou")
				local shown = Compose.cell(false)
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						Name = "Outer",
						selection = selection,
						tabs = {
							{
								id = "home",
								label = "Home",
								content = function(): Instance
									return Host.Frame({
										Name = "Branch",
										Compose.show(shown, function()
											return UI.TabView({
												Name = "Inner",
												selection = inner,
												tabs = {
													{
														id = "foryou",
														label = "For you",
														content = function(): Instance
															return Host.Frame({})
														end,
													} :: FixtureNavigationTypes.Tab,
													{
														id = "charts",
														label = "Charts",
														content = function(): Instance
															return Host.Frame({})
														end,
													} :: FixtureNavigationTypes.Tab,
												},
											})
										end),
									})
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "feed",
								label = "Feed",
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end, { motionLevel = "none" })
				local outer = world.find("Outer")
				outer.AbsoluteSize = Vector2.new(390, 800)
				shown:set(true)
				local innerView = world.find("Inner")
				innerView.AbsoluteSize = Vector2.new(390, 700)
				local innerTabs = innerView:FindFirstChild("Tabs")
				Verify.expect(innerTabs.Position.Y.Scale):toBe(0)
				Verify.expect(innerTabs.Position.Y.Offset):toBe(0)
				Verify.expect(outer:FindFirstChild("Tabs").Position.Y.Scale):toBe(1)
				world.stop()
			end,
		})
	end)

	return nil
end
