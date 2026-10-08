--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

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
							expect(picker.AutomaticSize.Name):toBe("None")
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
	end)

	verifyHarness:suite("native navigation stack paint", function()
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
