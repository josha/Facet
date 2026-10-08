--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local NavigationFixtures = require("../src/ui/navigation_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local transitionOf = require("./lib/transition")
	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local Vector2 = require("@lune/roblox").Vector2
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes
	local expect = Verify.expect

	local THREE = {
		{ value = "easy", label = "Easy" },
		{ value = "normal", label = "Normal" },
		{ value = "hard", label = "Hard" },
	}

	local SHIPPED: { any } = {
		require("../examples/themes/classic_desktop"),
		require("../examples/themes/compact_pointer"),
		require("../examples/themes/fantasy_ornate"),
		require("../examples/themes/fantasy_parchment"),
		require("../examples/themes/glossy_mobile"),
		require("../examples/themes/glossy_touch"),
		require("../examples/themes/pixel_quest"),
		require("../examples/themes/scifi_hud"),
	}

	local function find(root: any, name: string): any
		if root == nil then
			return nil
		end
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

	local function world(build: (any, any, any) -> any, options: { [string]: any }?): any
		local o: { [string]: any } = options or {}
		local engine: any = engines.new({
			measureText = function(node: any): any
				local text = node.Text or ""
				return Vector2.new(#text * 11, if #text > 0 then 20 else 0)
			end,
			textFits = o.textFits,
		})
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local config: { [string]: any } = {
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			theme = o.theme,
			controlSize = o.controlSize,
		}
		local UI: any = Facet.controls(runtime, config :: any)
		local stop, screen: any = runtime.mount(function()
			return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
				build(UI, runtime.constructors, engine),
			})
		end, engine.new("Folder"))
		return {
			engine = engine,
			gui = gui,
			runtime = runtime,
			screen = screen,
			UI = UI,
			V2 = engine.types.Vector2,
			E = engine.types.Enum,
			step = function(count: number?)
				for _ = 1, count or 1 do
					engine.heartbeat:Fire(1 / 60)
				end
			end,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function width(node: any): number
		if node:IsA("TextLabel") or node:IsA("TextButton") then
			return math.max(node.Size.X.Offset, #node.Text * 11)
		end
		local widest = node.Size.X.Offset
		for _, child in node:GetChildren() do
			if child:IsA("GuiObject") and child.Visible ~= false then
				widest = math.max(widest, width(child))
			end
		end
		return widest
	end

	local function placed(row: any): { [any]: { x: number, w: number } }
		local layout = row:FindFirstChildWhichIsA("UIListLayout")
		assert(layout, `{row.Name} places its parts with a list layout`)
		assert(layout.FillDirection.Name == "Horizontal", `{row.Name} is a horizontal row`)
		local parts = {}
		for index, child in row:GetChildren() do
			if child:IsA("GuiObject") and child.Visible ~= false then
				table.insert(parts, { node = child, order = child.LayoutOrder, index = index })
			end
		end
		table.sort(parts, function(a, b)
			return if a.order == b.order then a.index < b.index else a.order < b.order
		end)
		local result, x = {}, 0
		for _, part in parts do
			local w = width(part.node)
			result[part.node] = { x = x, w = w }
			x += w + layout.Padding.Offset
		end
		return result
	end

	local function clear(case: string, button: any, markName: string, edge: string)
		expect(`{case}: row {tostring(button ~= nil)}`):toBe(`{case}: row true`)
		local row = button:FindFirstChild("Content")
		expect(`{case}: content {tostring(row ~= nil)}`):toBe(`{case}: content true`)
		local mark = row:FindFirstChild(markName)
		local label = row:FindFirstChild("Captions") or row:FindFirstChild("Title")
		expect(`{case}: mark in row {tostring(mark ~= nil)}`):toBe(`{case}: mark in row true`)
		expect(`{case}: label in row {tostring(label ~= nil)}`):toBe(`{case}: label in row true`)
		local at = placed(row)
		local m, l = at[mark], at[label]
		expect(m.w):toBeGreaterThan(0)
		if edge == "leading" then
			expect(`{case}: {tostring(l.x >= m.x + m.w)}`):toBe(`{case}: true`)
		else
			expect(`{case}: {tostring(m.x >= l.x + l.w)}`):toBe(`{case}: true`)
		end
	end

	local function sheetFor(w: any, package: any, options: { [string]: any }?): any
		local settings: { [string]: any } =
			{ types = w.engine.types, preferredTransparency = 1, motionLevel = "normal" }
		for key, value in (options or {}) :: { [string]: any } do
			settings[key] = value
		end
		local _, sheet = w.runtime.mount(function()
			return themes.createStyleSheet(w.runtime, package, settings :: any)
		end, w.engine.new("Folder"))
		return sheet
	end

	local function rule(sheet: any, selector: string): any
		local found
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				found = node
			end
		end
		return found
	end

	verifyHarness:suite("native option rows keep the mark in its own slot", function()
		verifyHarness:case("the label starts after the leading radio mark and ends before a trailing one", {
			id = "native_control_polish::native option rows keep the mark in its own slot::the label starts after the leading radio mark and ends before a trailing one",
			run = function()
				for _, edge in { "leading", "trailing" } :: { "leading" | "trailing" } do
					local w = world(function(UI: FacetControls)
						return UI.Picker "P" {
							style = "radioGroup" :: "radioGroup",
							indicatorPosition = edge :: "leading" | "trailing",
							selected = Compose.cell("normal"),
							options = THREE,
						}
					end)
					for _, key in { "easy", "normal", "hard" } do
						clear(`radio {edge} {key}`, find(w.screen, key), "Indicator", edge)
					end
					local dot = find(find(find(w.screen, "normal"), "Indicator"), "Dot")
					expect(dot.Visible):toBe(true)
					expect(find(find(find(w.screen, "easy"), "Indicator"), "Dot").Visible):toBe(false)
					w.stop()
				end
			end,
		})

		verifyHarness:case("a radio row without a description keeps one line centered at the row height", {
			id = "native_control_polish::native option rows keep the mark in its own slot::a radio row without a description keeps one line centered at the row height",
			run = function()
				local options = table.clone(THREE)
				options[2] = { value = "normal", label = "Normal", description = "Most players" }
				local w = world(function(UI: FacetControls)
					return UI.Picker "P" {
						style = "radioGroup" :: "radioGroup",
						selected = Compose.cell("normal"),
						options = options,
					}
				end)
				local plain, described = find(w.screen, "easy"), find(w.screen, "normal")
				expect((plain:HasTag("facet-button-described"))):toBe(false)
				expect(find(plain, "Content").AnchorPoint):toBe(w.V2.new(0, 0.5))
				expect(find(plain, "Content").Position.Y.Scale):toBe(0.5)
				expect((described:HasTag("facet-button-described"))):toBe(true)
				expect(find(described, "Content").AnchorPoint):toBe(w.V2.new(0, 0))
				w.stop()
			end,
		})

		verifyHarness:case("the radio group in a presented popover keeps the same slot", {
			id = "native_control_polish::native option rows keep the mark in its own slot::the radio group in a presented popover keeps the same slot",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.Popover "Status" {
						isPresented = Compose.cell(true),
						onPresentedChange = function() end,
						trigger = UI.Button "Open" { label = "Open" },
						content = function(): Instance
							return UI.Picker "Presence" {
								style = "radioGroup" :: "radioGroup",
								selected = Compose.cell("away"),
								options = {
									{ value = "online", label = "Online" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "away", label = "Away" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "busy", label = "Busy" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							}
						end,
					}
				end)
				for _, key in { "online", "away", "busy" } do
					clear(`popover {key}`, find(w.screen, key), "Indicator", "leading")
				end
				w.stop()
			end,
		})

		verifyHarness:case("an inline list and a menu keep the check after the label", {
			id = "native_control_polish::native option rows keep the mark in its own slot::an inline list and a menu keep the check after the label",
			run = function()
				local inline = world(function(UI: FacetControls)
					return UI.Picker "P" {
						style = "inline" :: "inline",
						indicator = "none" :: "none",
						selected = Compose.cell("normal"),
						options = THREE,
					}
				end)
				clear("inline", find(inline.screen, "normal"), "TrailingIcon", "trailing")
				inline.stop()
				local menu = world(function(UI: FacetControls)
					return UI.Picker "P" { style = "menu" :: "menu", selected = Compose.cell("normal"), options = THREE }
				end)
				find(menu.screen, "Trigger").Activated:Fire()
				local row
				for _, node in menu.screen:GetDescendants() do
					if node.Name == "normal" and node:HasTag("facet-menu-item") then
						row = node
					end
				end
				clear("menu", row, "TrailingIcon", "trailing")
				menu.stop()
			end,
		})
	end)

	verifyHarness:suite("native table cell insets", function()
		verifyHarness:case("a heading and a custom cell start their content where a value does, in every theme", {
			id = "native_control_polish::native table cell insets::a heading and a custom cell start their content where a value does, in every theme",
			run = function()
				local packages: { any } = { themes.neutralPackage() }
				for _, module in SHIPPED do
					table.insert(packages, (module.build(themes)))
				end
				for _, package in packages do
					local id = package.identity.id
					local w = world(function()
						return nil
					end)
					local sheet = sheetFor(w, package)
					local order: { [string]: number } = {}
					for index, node in sheet:GetChildren() do
						order[node.Selector] = index
					end
					local value = rule(sheet, ".facet-tablevalue::UIPadding"):GetProperties()
					local inset = rule(sheet, ".facet-tablecellinset"):GetProperties()
					expect(`{id} inset {inset.Position.X.Offset} {-inset.Size.X.Offset}`):toBe(
						`{id} inset {value.PaddingLeft.Offset} {value.PaddingLeft.Offset + value.PaddingRight.Offset}`
					)
					for _, selector in { ".facet-tableheading::UIPadding" } do
						local found = rule(sheet, selector)
						expect(`{id} {selector} {tostring(found ~= nil)}`):toBe(`{id} {selector} true`)
						local padding = found:GetProperties()
						for _, side in { "PaddingLeft", "PaddingRight" } do
							expect(`{id} {selector} {side} {padding[side].Offset}`):toBe(
								`{id} {selector} {side} {value[side].Offset}`
							)
						end
					end
					expect(
						`{id} heading after tight {tostring(
							order[".facet-tableheading::UIPadding"] > order[".facet-button-tight::UIPadding"]
						)}`
					):toBe(`{id} heading after tight true`)
					w.stop()
				end
			end,
		})
	end)

	verifyHarness:suite("native segmented picker track", function()
		verifyHarness:case(
			"the selected segment sits inside the track with an even inset in every theme and control size",
			{
				id = "native_control_polish::native segmented picker track::the selected segment sits inside the track with an even inset in every theme and control size",
				run = function()
					local packages: { any } = { themes.neutralPackage() }
					for _, module in SHIPPED do
						table.insert(packages, (module.build(themes)))
					end
					local neutralSizes = themes.neutralPackage().metrics.controlSizes
					for _, package in packages do
						local id = package.identity.id
						for _, size in { "compact", "regular", "large" } do
							local w = world(function(UI: FacetControls)
								return UI.Picker "P" {
									style = "segmented" :: "segmented",
									controlSize = size :: "compact" | "regular" | "large",
									selected = Compose.cell("normal"),
									options = THREE,
								}
							end, { theme = package })
							local sheet = sheetFor(w, package)
							local padding = rule(sheet, ".facet-segmented::UIPadding"):GetProperties()
							local inset = padding.PaddingTop.Offset
							for _, side in { "PaddingLeft", "PaddingRight", "PaddingBottom" } do
								expect(`{id} {side}: {padding[side].Offset}`):toBe(`{id} {side}: {inset}`)
							end
							expect(inset >= 3 and inset <= 4):toBe(true)
							local track = rule(sheet, ".facet-segmented::UICorner"):GetProperties().CornerRadius.Offset
							local pill = rule(sheet, ".facet-segment::UICorner")
							expect(`{id}: segment corner {tostring(pill ~= nil)}`):toBe(`{id}: segment corner true`)
							expect(pill:GetProperties().CornerRadius.Offset):toBe(math.max(0, track - inset))
							local height = ((package.metrics.controlSizes or {})[size] or neutralSizes[size]).height
							local picker = find(w.screen, "P")
							local recipe = package.chrome and package.chrome.control
							if recipe and recipe.kind ~= "native" and recipe.kind ~= "none" then
								local chrome = recipe.contentInsets or {}
								local glyph = find(find(picker, "normal"), "Label").TextBounds.Y
								height = math.max(height, glyph + (chrome.top or 0) + (chrome.bottom or 0) + 2 * inset)
							end
							expect(`{id} {size}: track {picker.Size.Y.Scale} {picker.Size.Y.Offset}`):toBe(
								`{id} {size}: track 0 {height}`
							)
							expect(picker.AutomaticSize.Name):toBe("Y")
							local segment = find(picker, "normal")
							expect((segment:HasTag("facet-segment-current"))):toBe(true)
							expect(`{id} {size}: segment {segment.Size.Y.Scale} {segment.Size.Y.Offset}`):toBe(
								`{id} {size}: segment 0 {height - 2 * inset}`
							)
							expect(segment.AutomaticSize.Name == "Y" or segment.AutomaticSize.Name == "XY"):toBe(false)
							local limit = segment:FindFirstChildWhichIsA("UISizeConstraint")
							local inner = height - 2 * inset
							expect(limit.MinSize.Y <= inner):toBe(true)
							local top, bottom = inset, inset + inner
							expect(top >= inset and bottom <= height - inset):toBe(true)
							w.stop()
						end
					end
				end,
			}
		)

		verifyHarness:case("bounds segments in layout units under a scaled ancestor", {
			id = "native_control_polish::native segmented picker track::bounds segments in layout units under a scaled ancestor",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.Picker "P" {
						style = "segmented" :: "segmented",
						label = "Mode",
						selected = Compose.cell("easy"),
						options = THREE,
					}
				end)
				local row = find(w.screen, "P")
				find(row, "Unit").AbsoluteSize = w.V2.new(1.25, 1.25)
				row.AbsoluteSize = w.V2.new(375, 60)
				local options = find(row, "Options")
				local segment = find(options, "easy"):FindFirstChildWhichIsA("UISizeConstraint")
				expect(segment.MaxSize.X):toBe(300 - 6)
				expect(options:FindFirstChild("TargetFloor").MaxSize.X):toBe(300)
				w.stop()
			end,
		})

		verifyHarness:case("an icon-only segment takes the glyph padding so its icon stays centred in a narrow tile", {
			id = "native_control_polish::native segmented picker track::an icon-only segment takes the glyph padding so its icon stays centred in a narrow tile",
			run = function()
				local iconOnly = Compose.cell(true)
				local w = world(function(UI: FacetControls)
					return UI.Picker "Rail" {
						style = "segmented" :: "segmented",
						axis = "y" :: "y",
						iconOnly = iconOnly,
						selected = Compose.cell("a"),
						options = {
							{ value = "a", label = "Browse", icon = "menu" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "b", label = "Compose", icon = "edit" } :: FixtureNavigationTypes.PickerOption<any>,
						},
					}
				end)
				local segment = find(w.screen, "a")
				expect((segment:HasTag("facet-button-glyph"))):toBe(true)
				iconOnly:set(false)
				expect((segment:HasTag("facet-button-glyph"))):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("a caller's fixed 44 point track keeps the segments inside it", {
			id = "native_control_polish::native segmented picker track::a caller's fixed 44 point track keeps the segments inside it",
			run = function()
				local w = world(function(UI: FacetControls, _, engine)
					return UI.Picker "P" {
						style = "segmented" :: "segmented",
						selected = Compose.cell("easy"),
						options = THREE,
						Size = engine.types.UDim2.new(1, 0, 0, 44),
						AutomaticSize = engine.types.Enum.AutomaticSize.None,
					}
				end)
				local picker = find(w.screen, "P")
				expect(picker.Size.Y.Offset):toBe(44)
				for _, key in { "easy", "normal", "hard" } do
					local segment = find(picker, key)
					expect(segment.Size.Y.Scale):toBe(0)
					expect(segment.Size.Y.Offset):toBe(38)
				end
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native NavBar fit", function()
		local function bar(title: string): (any, any)
			local w = world(function(UI: FacetControls, Host: RobloxHost, engine)
				return UI.NavBar "Header" {
					title = title,
					titleSize = "heading",
					trailing = UI.HStack "HeaderActions" {
						gap = "s",
						align = "center" :: "center",
						UI.Button "MenuButton" { icon = "more", name = "Menu", shape = "circle" :: "circle" } :: unknown,
						Host.Frame "Profile" { Size = engine.types.UDim2.fromOffset(36, 36) },
					},
				}
			end)
			local header = find(w.screen, "Header")
			header.AbsoluteSize = w.V2.new(358, 44)
			find(header, "Trailing").AbsoluteSize = w.V2.new(88, 44)
			find(header, "Primary").AbsoluteSize = w.V2.new(262, 44)
			find(header, "Center").AbsoluteSize = w.V2.new(262, 28)
			return w, header
		end

		verifyHarness:case("keeps a short title and the trailing actions on one row at 390 points wide", {
			id = "native_control_polish::native NavBar fit::keeps a short title and the trailing actions on one row at 390 points wide",
			run = function()
				local w, header = bar("Discover")
				expect(header:FindFirstChildWhichIsA("UIListLayout").FillDirection.Name):toBe("Horizontal")
				w.stop()
			end,
		})

		verifyHarness:case("stacks only when the title does not fit beside the actions", {
			id = "native_control_polish::native NavBar fit::stacks only when the title does not fit beside the actions",
			run = function()
				local w, header = bar("Every monitor in the whole office")
				expect(header:FindFirstChildWhichIsA("UIListLayout").FillDirection.Name):toBe("Vertical")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native selection paint", function()
		verifyHarness:case("applies the selected state during the activation that causes it", {
			id = "native_control_polish::native selection paint::applies the selected state during the activation that causes it",
			run = function()
				local w = world(function(UI: FacetControls)
					return UI.VStack "Column" {
						UI.Picker "Segments" {
							style = "segmented" :: "segmented",
							selected = Compose.cell("easy"),
							options = THREE,
						} :: unknown,
						UI.Toggle "Hat" { label = "Hat", value = Compose.cell(false) },
						UI.TabView "Tabs" {
							selection = Compose.cell("one"),
							indicator = "pill" :: "pill",
							placement = "topBar" :: "topBar",
							tabs = {
								{
									id = "one",
									label = "One",
									content = function(): Instance
										return UI.Text "OneBody" { text = "One" }
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "two",
									label = "Two",
									content = function(): Instance
										return UI.Text "TwoBody" { text = "Two" }
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						},
					}
				end)
				local frames = 0
				local watch = w.engine.heartbeat:Connect(function()
					frames += 1
				end)
				local segment = find(find(w.screen, "Segments"), "hard")
				segment.Activated:Fire()
				expect((segment:HasTag("facet-segment-current"))):toBe(true)
				expect((segment:HasTag("facet-selected"))):toBe(true)
				local toggle = find(w.screen, "Hat")
				toggle.Activated:Fire()
				expect((toggle:HasTag("facet-selected"))):toBe(true)
				expect((find(toggle, "Indicator"):HasTag("facet-toggle-on"))):toBe(true)
				local tab = find(find(w.screen, "Tabs"), "two")
				tab.Activated:Fire()
				expect((tab:HasTag("facet-tab-current"))):toBe(true)
				expect((tab:HasTag("facet-selected"))):toBe(true)
				expect(frames):toBe(0)
				watch:Disconnect()
				w.stop()
			end,
		})

		verifyHarness:case(
			"a pressed control keeps its highlight and a pressed current option keeps its selected paint",
			{
				id = "native_control_polish::native selection paint::a pressed control keeps its highlight and a pressed current option keeps its selected paint",
				run = function()
					local w = world(function(UI: FacetControls)
						return UI.VStack "Empty" {}
					end)
					local sheet = sheetFor(w, themes.neutralPackage())
					local seconds = themes.neutralPackage().metrics.motion.normal
					for _, node in sheet:GetChildren() do
						local family = string.match(node.Selector, "^(%.[%w%-]+):Hover$")
						if family then
							local press = rule(sheet, family .. ":Press")
							expect(`{family}:Press {tostring(press ~= nil)}`):toBe(`{family}:Press true`)
							local hover = node:GetProperties()
							local pressed = press:GetProperties()
							for _, property in { "BackgroundColor3", "BackgroundTransparency" } do
								if hover[property] == nil then
									continue
								end
								expect(`{family} {property} {tostring(pressed[property] ~= nil)}`):toBe(
									`{family} {property} true`
								)
							end
							for property, value in pressed do
								if typeof(value) == "Color3" or string.find(property, "Transparency$") then
									expect(transitionOf(press, property).Time):toBe(
										themes.neutralPackage().metrics.motion.press
									)
								end
							end
						end
					end
					for family, current in
						{
							[".facet-segment"] = ".facet-segment-current",
							[".facet-choice"] = ".facet-choice-current",
							[".facet-tab-item"] = ".facet-tab-filled",
						} :: { [string]: string }
					do
						local press = rule(sheet, family .. ":Press")
						expect(rule(sheet, current).Priority > press.Priority):toBe(true)
						expect(rule(sheet, current).Priority > rule(sheet, family .. ":Hover").Priority):toBe(true)
					end
					for _, current in { ".facet-segment-current", ".facet-choice-current" } do
						local base = rule(sheet, current):GetProperties()
						local pressed = rule(sheet, current .. ":Press")
						expect(`{current}:Press {tostring(pressed ~= nil)}`):toBe(`{current}:Press true`)
						expect(pressed:GetProperties().BackgroundColor3):toBe(base.BackgroundColor3)
					end
					w.stop()
				end,
			}
		)
	end)

	verifyHarness:suite("native navigation stack paint", function()
		local function stackWorld(): (any, any, any)
			local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
			local w = world(function(UI: FacetControls, Host: RobloxHost, engine)
				return Host.Frame "Card" {
					BackgroundColor3 = engine.types.Color3.new(0.2, 0.3, 0.4),
					BackgroundTransparency = 0,
					Host.Frame "Clear" {
						BackgroundTransparency = 1,
						UI.NavigationStack "Stack" {
							path = path,
							root = {
								title = "Explorer",
								content = function(): Instance
									return UI.Button "RootAction" { label = "Motion & turning" }
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
							destinations = {
								motion = {
									title = "Motion & turning",
									content = function(): Instance
										return UI.Button "DetailAction" { label = "Turn speed" }
									end,
								} :: NavigationFixtures.NavigationDestination<any>,
							},
						},
					},
				}
			end)
			return w, path, w.engine.types.Color3.new(0.2, 0.3, 0.4)
		end

		local function opaque(w: any, pages: { any }, colour: any)
			for _, page in pages do
				if page.Visible then
					expect(`{page.Name} {page.BackgroundTransparency}`):toBe(`{page.Name} 0`)
					expect(page.BackgroundColor3):toBe(colour)
				end
				for _, node in page:GetDescendants() do
					expect((node:IsA("CanvasGroup"))):toBe(false)
				end
				expect((page:IsA("CanvasGroup"))):toBe(false)
			end
		end

		verifyHarness:case("both pages stay opaque while a push slides the new page over a shaded one", {
			id = "native_control_polish::native navigation stack paint::both pages stay opaque while a push slides the new page over a shaded one",
			run = function()
				local w, path, colour = stackWorld()
				local stack = find(w.screen, "Stack")
				local root = find(stack, "@root")
				path:set({ { id = "motion" } })
				local detail = find(stack, "motion")
				local sampled = 0
				for _ = 1, 30 do
					w.step()
					if root.Visible and detail.Position.X.Scale > 0 then
						sampled += 1
						opaque(w, { root, detail }, colour)
						local shade = find(root, "Dim")
						expect(shade.BackgroundColor3):toBe(w.engine.types.Color3.new(0, 0, 0))
						expect(shade.BackgroundTransparency >= 0.9 and shade.BackgroundTransparency < 1):toBe(true)
					end
				end
				expect(sampled):toBeGreaterThan(5)
				w.step(60)
				expect(detail.Position.X.Scale):toBe(0)
				expect(root.Visible):toBe(false)
				expect(detail.BackgroundTransparency):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("both pages stay opaque while a pop slides the page away", {
			id = "native_control_polish::native navigation stack paint::both pages stay opaque while a pop slides the page away",
			run = function()
				local w, path, colour = stackWorld()
				local stack = find(w.screen, "Stack")
				local root = find(stack, "@root")
				path:set({ { id = "motion" } })
				w.step(60)
				local detail = find(stack, "motion")
				path:set({})
				opaque(w, { root, detail }, colour)
				local sampled = 0
				for _ = 1, 30 do
					w.step()
					if not detail:isDestroyed() and detail.Position.X.Scale < 1 and root.Visible then
						sampled += 1
						opaque(w, { root, detail }, colour)
					end
				end
				expect(sampled):toBeGreaterThan(5)
				w.step(60)
				expect((detail:isDestroyed())):toBe(true)
				expect(root.BackgroundTransparency):toBe(1)
				w.stop()
			end,
		})
		verifyHarness:case("lets a fixed-width button's padding give way before its label vanishes", {
			id = "native_control_polish::native navigation stack paint::lets a fixed-width button's padding give way before its label vanishes",
			run = function()
				local styleRules = require("./lib/style_rules")
				local w = world(function(UI: FacetControls, _, engine)
					return UI.Button "Key" {
						label = "W",
						Size = engine.types.UDim2.fromOffset(31, 44),
						AutomaticSize = engine.types.Enum.AutomaticSize.None,
					}
				end)
				local key = find(w.screen, "Key")
				local sheet: any
				w.runtime.mount(function()
					sheet = themes.createStyleSheet(w.runtime, nil, { types = w.engine.types })
					return sheet
				end, w.engine.new("Folder"))
				local function inset(): number
					return styleRules.resolve(sheet, key, "PaddingLeft", "UIPadding").Offset
				end
				expect((inset())):toBe(12)
				key.AbsoluteSize = w.V2.new(31, 44)
				key.TextFits = false
				expect((key:HasTag("facet-button-tight"))):toBe(true)
				expect((inset())):toBe(0)
				key.TextFits = true
				expect((key:HasTag("facet-button-tight"))):toBe(true)
				key.AbsoluteSize = w.V2.new(120, 44)
				expect((key:HasTag("facet-button-tight"))):toBe(false)
				key.AbsoluteSize = w.V2.new(30, 44)
				key.TextFits = false
				expect((key:HasTag("facet-button-tight"))):toBe(true)
				key.TextFits = true
				for _, arrive in
					{
						function()
							key.TextSize = 18
						end,
						function()
							key.FontFace = w.engine.types.Font.fromName("Gotham")
						end,
						function()
							key.Text = "Q"
						end,
					}
				do
					arrive()
					expect((key:HasTag("facet-button-tight"))):toBe(false)
					key.TextFits = false
					expect((key:HasTag("facet-button-tight"))):toBe(true)
					key.TextFits = true
				end
				key.TextFits = false
				key.AutomaticSize = w.E.AutomaticSize.X
				expect((key:HasTag("facet-button-tight"))):toBe(false)
				key.TextFits = true
				key.TextFits = false
				expect((key:HasTag("facet-button-tight"))):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("decides the tight padding from the engine's live fit, not a fit report still in flight", {
			id = "native_control_polish::native navigation stack paint::decides the tight padding from the engine's live fit, not a fit report still in flight",
			run = function()
				local live: boolean? = nil
				local w = world(function(UI: FacetControls, _, engine)
					return UI.Button "Tab" {
						label = "Inputs",
						Size = engine.types.UDim2.fromOffset(94, 44),
						AutomaticSize = engine.types.Enum.AutomaticSize.None,
					}
				end, {
					textFits = function()
						return live
					end,
				})
				local tab = find(w.screen, "Tab")
				tab.AbsoluteSize = w.V2.new(44, 44)
				tab.TextFits = false
				expect((tab:HasTag("facet-button-tight"))):toBe(true)
				live = true
				tab.AbsoluteSize = w.V2.new(94, 44)
				tab.TextSize = 18
				expect((tab:HasTag("facet-button-tight"))):toBe(false)
				live = nil
				tab.TextFits = true
				tab.TextFits = false
				expect((tab:HasTag("facet-button-tight"))):toBe(true)
				tab.FontFace = w.engine.types.Font.fromName("Gotham")
				expect((tab:HasTag("facet-button-tight"))):toBe(true)
				w.stop()
			end,
		})
	end)
end
