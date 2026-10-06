--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local materialize = require("./lib/materialize")
	local fadeKit = require("./lib/fade")
	local Facet = require("../src")
	local worlds = require("./lib/content_world")
	local Compose: ComposeModule = Facet.Compose
	local Roblox = require("../src/vendor/compose/roblox")
	local themes = require("../src/ui/themes")(Compose)
	local engineLib = require("./lib/native_engine")
	local lune = require("@lune/roblox")
	local UDim2, UDim, Vector2 = lune.UDim2, lune.UDim, lune.Vector2

	local FRAME = 1 / 60

	local function items(count: number, log: { string }?): { any }
		local out = {}
		for index = 1, count do
			out[index] = {
				id = `row{index}`,
				label = `Row {index}`,
				onSelect = function()
					if log then
						table.insert(log, `row{index}`)
					end
				end,
			}
		end
		return out
	end

	local NESTED = {
		{ id = "plain", label = "Plain", onSelect = function() end } :: MenuItem,
		{
			id = "adjust",
			label = "Adjust",
			children = {
				{ id = "head", label = "Head", onSelect = function() end },
				{ id = "body", label = "Body", onSelect = function() end },
			},
		} :: MenuItem,
		{ id = "skin", label = "Skin", onSelect = function() end } :: MenuItem,
	}

	local function labelled(spec: { [any]: any }, options: { [string]: any }?): any
		local fields = table.clone(spec)
		if fields.trigger == nil and fields.label == nil then
			fields.label = "Options"
		end
		return worlds.new(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({ Name = "S", Size = UDim2.fromOffset(800, 600), UI.Menu("M")(fields) })
		end, options or { motionLevel = "none" })
	end

	local function panelOf(world: any): any
		return world.find("MenuPanel", world.screen.Parent)
	end

	local function modalOf(world: any, panel: any): any
		local modal = panel.Parent
		while modal and modal.Parent and modal.Parent ~= world.screen and modal.Parent.ClassName ~= "ScreenGui" do
			modal = modal.Parent
		end
		return modal
	end

	local function lay(world: any, panel: any, at: Vector2, size: Vector2, panelSize: Vector2)
		local trigger = world.find("Trigger")
		trigger.AbsolutePosition = at
		trigger.AbsoluteSize = size
		modalOf(world, panel).AbsoluteSize = Vector2.new(800, 600)
		panel.AbsoluteSize = panelSize
	end

	local function open(world: any): any
		world.find("Trigger").Activated:Fire()
		return panelOf(world)
	end

	local function sheetRules(): (any, any)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local sheet
		local stop = runtime.mount(function()
			sheet = themes.createStyleSheet(runtime, themes.neutralPackage(), { types = engine.types })
			return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({ sheet :: unknown })
		end, engine.new("Folder"))
		return sheet, function()
			stop()
			runtime:dispose()
		end
	end

	local function ruleIndex(sheet: any, selector: string): (number, any)
		for index, node in sheet:GetChildren() do
			if node.Selector == selector then
				return index, node:GetProperties()
			end
		end
		error("No rule: " .. selector)
	end

	local function luminance(color: any): number
		local function channel(value: number): number
			return if value <= 0.03928 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
	end

	verifyHarness:suite("native menu parity with main", function()
		verifyHarness:case("anchors a secondary-click menu at the pointer and resets to the trigger on activation", {
			id = "native_menu_parity::native menu parity with main::anchors a secondary-click menu at the pointer and resets to the trigger on activation",
			run = function()
				local shown = Compose.cell(false)
				local enabled = Compose.cell(true)
				local world =
					labelled({ items = items(2), isPresented = shown, enabled = enabled, presentation = "menu" })
				local trigger = world.find("Trigger")
				local caption = world.engine.new("TextLabel")
				caption.Parent = trigger
				caption.InputBegan:Fire({
					UserInputType = world.engine.types.Enum.UserInputType.MouseButton2,
					Position = world.engine.types.Vector3.new(240, 180, 0),
				})
				local panel = panelOf(world)
				lay(world, panel, Vector2.new(20, 30), Vector2.new(500, 40), Vector2.new(280, 100))
				Verify.expect(panel.Position.X.Offset):toBe(240)
				Verify.expect(panel.Position.Y.Offset):toBe(180)
				shown:set(false)
				enabled:set(false)
				caption.InputBegan:Fire({
					UserInputType = world.engine.types.Enum.UserInputType.MouseButton2,
					Position = world.engine.types.Vector3.new(300, 220, 0),
				})
				Verify.expect((shown:peek())):toBe(false)
				enabled:set(true)
				panel = open(world)
				lay(world, panel, Vector2.new(20, 30), Vector2.new(500, 40), Vector2.new(280, 100))
				Verify.expect(panel.Position.X.Offset):toBe(20)
				Verify.expect(panel.Position.Y.Offset):toBe(74)
				world.stop()
			end,
		})

		verifyHarness:case("attaches to the caller's trigger node and returns that same node without a wrapper", {
			id = "native_menu_parity::native menu parity with main::attaches to the caller's trigger node and returns that same node without a wrapper",
			run = function()
				local authored: any, returned
				local ran: { string } = {}
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					authored = UI.Button "Opener" { label = "More" }
					returned = UI.Menu({
						trigger = authored,
						LayoutOrder = 3,
						items = items(2, ran),
					})
					return Host.Frame({ Name = "S", Size = UDim2.fromOffset(800, 600), returned :: unknown })
				end, { motionLevel = "none" })
				Verify.expect(returned):toBe(authored)
				Verify.expect(authored.Parent.Name):toBe("S")
				Verify.expect(authored.Name):toBe("Opener")
				Verify.expect(authored.LayoutOrder):toBe(3)
				authored.Activated:Fire()
				local panel = panelOf(world)
				Verify.expect(panel ~= nil):toBe(true)
				world.find("row2", panel).Activated:Fire()
				Verify.expect(ran):toEqual({ "row2" })
				world.stop()
				local named = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Menu "Actions" { trigger = UI.Button "Opener" { label = "More" }, items = items(1) },
					})
				end, { motionLevel = "none" })
				Verify.expect(named.find("Actions").ClassName):toBe("TextButton")
				Verify.expect((named.find("Opener"))):toBeNil()
				named.stop()
			end,
		})

		verifyHarness:case("fills each row title so a submenu chevron or check sits at the trailing edge", {
			id = "native_menu_parity::native menu parity with main::fills each row title so a submenu chevron or check sits at the trailing edge",
			run = function()
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "S",
						Size = UDim2.fromOffset(800, 600),
						UI.Menu {
							trigger = UI.Button "Opener" { label = "More" },
							items = {
								{ id = "plain", label = "Plain", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
								{
									id = "deeper",
									label = "Deeper",
									children = { { id = "leaf", label = "Leaf", onSelect = function() end } },
								} :: FixtureNavigationTypes.MenuItem<any>,
							},
						},
					})
				end, { motionLevel = "none" })
				world.find("Opener").Activated:Fire()
				local panel = panelOf(world)
				for _, id in { "plain", "deeper" } do
					local content = world.find(id, panel):FindFirstChild("Content")
					local words = content:FindFirstChild("Captions") or content:FindFirstChild("Title")
					Verify.expect(words ~= nil and words:FindFirstChildWhichIsA("UIFlexItem") ~= nil):toBe(true)
					Verify.expect(content.Size.X.Scale):toBe(1)
				end
				world.stop()
			end,
		})

		verifyHarness:case("dims the page behind a menu presented as a sheet and not behind a panel", {
			id = "native_menu_parity::native menu parity with main::dims the page behind a menu presented as a sheet and not behind a panel",
			run = function()
				for _, case in { { "sheet" :: unknown, true }, { "menu" :: unknown, false } } do
					local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							Name = "S",
							Size = UDim2.fromOffset(800, 600),
							UI.Menu {
								trigger = UI.Button "Opener" { label = "More" },
								presentation = case[1] :: "sheet" | "menu",
								items = {
									{ id = "one", label = "One", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
								},
							},
						})
					end, { motionLevel = "none" })
					world.find("Opener").Activated:Fire()
					local catcher = world.find("DismissOutside")
					Verify.expect(`{case[1]}: {catcher.BackgroundTransparency < 1}`):toBe(`{case[1]}: {case[2]}`)
					world.stop()
				end
			end,
		})

		verifyHarness:case("refuses label and trigger together", {
			id = "native_menu_parity::native menu parity with main::refuses label and trigger together",
			run = function()
				local message = worlds.mountError(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Menu({ label = "More", trigger = UI.Button "Opener" { label = "More" }, items = items(1) }),
					})
				end)
				Verify.expect(message ~= nil and string.find(message, "label or trigger, not both", 1, true) ~= nil)
					:toBe(true)
			end,
		})

		verifyHarness:case("calls onOpen and onClose once for each open and each close on every route", {
			id = "native_menu_parity::native menu parity with main::calls onOpen and onClose once for each open and each close on every route",
			run = function()
				local log: { string } = {}
				local presented = Compose.cell(false)
				local world = labelled({
					items = NESTED,
					isPresented = presented,
					presentation = "menu" :: "menu",
					onOpen = function()
						table.insert(log, "open")
					end,
					onClose = function()
						table.insert(log, "close")
					end,
				})
				Verify.expect(log):toEqual({})
				open(world)
				world.find("skin", panelOf(world)).Activated:Fire()
				Verify.expect(log):toEqual({ "open", "close" })
				open(world)
				world.find("DismissOutside", world.screen.Parent).Activated:Fire()
				Verify.expect(log):toEqual({ "open", "close", "open", "close" })
				presented:set(true)
				Verify.expect(log):toEqual({ "open", "close", "open", "close", "open" })
				world.find("Trigger").Activated:Fire()
				Verify.expect(#log):toBe(5)
				world.gui.SelectedObject = world.find("adjust", panelOf(world))
				world.action("ModalBack").Pressed:Fire()
				Verify.expect(log):toEqual({ "open", "close", "open", "close", "open", "close" })
				Verify.expect((presented:peek())):toBe(false)
				presented:set(true)
				world.stop()
				Verify.expect(log[#log]):toBe("close")
				Verify.expect(#log):toBe(8)
			end,
		})

		verifyHarness:case("takes a dimension table, a UDim or pixels for width and refuses a malformed one by name", {
			id = "native_menu_parity::native menu parity with main::takes a dimension table, a UDim or pixels for width and refuses a malformed one by name",
			run = function()
				for
					_,
					case: {
					width: number | typeof(UDim.new(0.5, 10)) | typeof(UDim2.new(0.25, 0, 0, 0)) | {
						type: string,
						px: (number | string)?,
						fraction: number?,
						offset: typeof(-8)?,
						min: number?,
						max: number?,
					},
					expected: number,
				}
				in
					{
						{ width = 300, expected = 300 },
						{ width = { type = "fixed", px = 300 }, expected = 300 },
						{ width = UDim.new(0.5, 10), expected = 402 },
						{ width = UDim2.new(0.25, 0, 0, 0), expected = 196 },
						{ width = { type = "percent", fraction = 0.5, offset = -8 }, expected = 384 },
						{ width = { type = "hug", min = 320 }, expected = 320 },
						{ width = { type = "hug", max = 200 }, expected = 200 },
						{ width = { type = "fill" }, expected = 784 },
						{ width = { type = "fixed", px = "targetSizes.minimum" }, expected = 44 },
					} :: {
						{
							width: number | typeof(UDim.new(0.5, 10)) | typeof(UDim2.new(0.25, 0, 0, 0)) | {
								type: string,
								px: (number | string)?,
								fraction: number?,
								offset: typeof(-8)?,
								min: number?,
								max: number?,
							},
							expected: number,
						}
					}
				do
					local world = labelled({ width = case.width, items = items(3) })
					local panel = open(world)
					lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 200))
					Verify.expect(`{typeof(case.width)} {panel.Size.X.Offset}`)
						:toBe(`{typeof(case.width)} {case.expected}`)
					world.stop()
				end
				for
					_,
					case: {
					width: typeof(-4) | { type: string, ratio: number?, px: number?, weight: number? },
					words: string,
				}
				in
					{
						{ width = { type = "aspect", ratio = 1 }, words = "width.type must be" },
						{ width = { type = "fixed" }, words = "a fixed width requires px" },
						{ width = { type = "fixed", px = 10, weight = 1 }, words = "does not take 'weight'" },
						{ width = -4, words = "width must be a finite number" },
					} :: {
						{
							width: typeof(-4) | { type: string, ratio: number?, px: number?, weight: number? },
							words: string,
						}
					}
				do
					local message = worlds.mountError(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({ UI.Menu({ label = "More", width = case.width, items = items(1) } :: any) })
					end)
					Verify.expect(message ~= nil and string.find(message, case.words, 1, true) ~= nil):toBe(true)
				end
			end,
		})

		verifyHarness:case("draws the anchored panel as one card with one hairline between each pair of rows", {
			id = "native_menu_parity::native menu parity with main::draws the anchored panel as one card with one hairline between each pair of rows",
			run = function()
				local checked = Compose.cell(true)
				local world = labelled({
					presentation = "menu" :: "menu",
					items = {
						{ id = "a", label = "Alpha", onSelect = function() end } :: MenuItem,
						{ id = "b", label = "Beta", checked = checked } :: MenuItem,
						{ id = "c", label = "Gamma", onSelect = function() end } :: MenuItem,
						{ divider = true } :: MenuItem,
						{ id = "d", label = "Delta", onSelect = function() end } :: MenuItem,
					},
				})
				local panel = open(world)
				Verify.expect((panel:HasTag("facet-menu"))):toBe(true)
				Verify.expect((panel:FindFirstChildWhichIsA("UICorner"))):toBeNil()
				Verify.expect((panel:FindFirstChildWhichIsA("UIStroke"))):toBeNil()
				Verify.expect((panel:FindFirstChildWhichIsA("UIShadow"))):toBeNil()
				Verify.expect((world.find("MenuGroup", panel):HasTag("facet-menu-group"))):toBe(true)
				local rows = panel:FindFirstChild("MenuRows", true)
				Verify.expect(rows:FindFirstChildWhichIsA("UIListLayout").Padding.Offset):toBe(0)
				local padding = rows:FindFirstChildWhichIsA("UIPadding")
				for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
					Verify.expect(padding[side].Offset):toBe(4)
				end
				local ruled = {}
				for _, id in { "a", "b", "c", "d" } do
					local row = world.find(id, panel)
					Verify.expect((row:HasTag("facet-menu-item"))):toBe(true)
					Verify.expect((row:FindFirstChildWhichIsA("UICorner"))):toBeNil()
					local hairline = row:FindFirstChild("Hairline")
					Verify.expect((hairline:HasTag("facet-menu-hairline"))):toBe(true)
					Verify.expect(hairline.Size):toBe(UDim2.new(1, 0, 0, 1))
					ruled[id] = hairline.Visible
				end
				Verify.expect(ruled):toEqual({ a = false, b = true, c = true, d = false })
				Verify.expect((world.find("b", panel):HasTag("facet-selected"))):toBe(true)
				Verify.expect((world.find("a", panel):HasTag("facet-selected"))):toBe(false)
				checked:set(false)
				Verify.expect((world.find("b", panel):HasTag("facet-selected"))):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("keeps the sheet rows spaced and unruled, since the card is a presentation branch", {
			id = "native_menu_parity::native menu parity with main::keeps the sheet rows spaced and unruled, since the card is a presentation branch",
			run = function()
				local world = labelled({ presentation = "sheet" :: "sheet", items = items(3) })
				local panel = open(world)
				local rows = panel:FindFirstChild("MenuRows", true)
				Verify.expect(rows:FindFirstChildWhichIsA("UIListLayout").Padding.Offset):toBe(8)
				for index = 1, 3 do
					Verify.expect(world.find(`row{index}`, panel):FindFirstChild("Hairline").Visible):toBe(false)
				end
				world.stop()
			end,
		})

		verifyHarness:case("grows a Back row only in the sheet and shows the open path on the parent level", {
			id = "native_menu_parity::native menu parity with main::grows a Back row only in the sheet and shows the open path on the parent level",
			run = function()
				for _, presentation in { "menu", "sheet" } :: { "menu" | "sheet" } do
					local world = labelled({ presentation = presentation :: "menu" | "sheet", items = NESTED })
					local panel = open(world)
					world.find("adjust", panel).Activated:Fire()
					Verify.expect(`{presentation} {world.find("Back", panel) ~= nil}`)
						:toBe(`{presentation} {presentation == "sheet"}`)
					if presentation == "menu" then
						local parent = world.find("AncestorMenu", world.screen.Parent)
						local row = world.find("adjust", parent)
						Verify.expect((row:HasTag("facet-selected"))):toBe(true)
						Verify.expect((world.find("skin", parent):HasTag("facet-selected"))):toBe(false)
						Verify.expect(world.find("skin", parent):FindFirstChild("Hairline").Visible):toBe(true)
						for _, id in { "plain", "adjust", "skin" } do
							local layout =
								world.find(id, parent):FindFirstChild("Content"):FindFirstChildWhichIsA("UIListLayout")
							Verify.expect(`{id} {layout.HorizontalAlignment.Name}`):toBe(`{id} Left`)
						end
					end
					world.stop()
				end
			end,
		})

		verifyHarness:case("insets an open ancestor level by the current theme's space.xs, following a theme swap", {
			id = "native_menu_parity::native menu parity with main::insets an open ancestor level by the current theme's space.xs, following a theme swap",
			run = function()
				local theme = Compose.cell(themes.neutralPackage())
				local world = labelled(
					{ presentation = "menu" :: "menu", items = NESTED },
					{ motionLevel = "none", theme = theme }
				)
				local panel = open(world)
				world.find("adjust", panel).Activated:Fire()
				local parent = world.find("AncestorMenu", world.screen.Parent)
				local padding = parent:FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingLeft.Offset):toBe(theme:peek().metrics.space.xs)
				local roomy = themes.neutralPackage()
				roomy.metrics.space.xs = 10
				theme:set(roomy)
				Verify.expect(`{padding.PaddingLeft.Offset} {padding.PaddingTop.Offset}`):toBe("10 10")
				world.stop()
			end,
		})

		verifyHarness:case("paints a selected row with the accent under an onAccent label at 4.5:1 or better", {
			id = "native_menu_parity::native menu parity with main::paints a selected row with the accent under an onAccent label at 4.5:1 or better",
			run = function()
				local sheet, stop = sheetRules()
				local hover = ruleIndex(sheet, ".facet-menu-item:Hover")
				local generic = ruleIndex(sheet, ".facet-selected")
				local _, accent = ruleIndex(sheet, ".facet-accent")
				for _, selector in
					{
						".facet-menu-item.facet-selected",
						".facet-menu-item.facet-selected:Hover",
						".facet-menu-item.facet-selected:Press",
					}
				do
					local index, props = ruleIndex(sheet, selector)
					Verify.expect(index > hover and index > generic):toBe(true)
					Verify.expect(props.BackgroundTransparency):toBe(0)
					Verify.expect(props.BackgroundColor3):toBe(accent.BackgroundColor3)
				end
				local _, caption = ruleIndex(sheet, ".facet-menu-item.facet-selected >> .facet-button-caption")
				local _, text = ruleIndex(sheet, ".facet-menu-item.facet-selected >> .facet-text")
				local _, icon = ruleIndex(sheet, ".facet-menu-item.facet-selected >> .facet-icon")
				Verify.expect(caption.TextColor3):toBe(accent.TextColor3)
				Verify.expect(text.TextColor3):toBe(accent.TextColor3)
				Verify.expect(icon.ImageColor3):toBe(accent.TextColor3)
				local a, b = luminance(accent.BackgroundColor3), luminance(accent.TextColor3)
				Verify.expect((math.max(a, b) + 0.05) / (math.min(a, b) + 0.05) >= 4.5):toBe(true)
				local _, card = ruleIndex(sheet, ".facet-menu::UICorner")
				local _, panelCorner = ruleIndex(sheet, ".facet-panel::UICorner")
				Verify.expect(card.CornerRadius):toBe(panelCorner.CornerRadius)
				local _, clip = ruleIndex(sheet, ".facet-menu-group::UICorner")
				Verify.expect(clip.CornerRadius):toBe(panelCorner.CornerRadius)
				local _, stroke = ruleIndex(sheet, ".facet-menu::UIStroke")
				Verify.expect(stroke.Thickness):toBe(1)
				Verify.expect(stroke.ApplyStrokeMode.Name):toBe("Border")
				local _, shadow = ruleIndex(sheet, ".facet-menu::UIShadow")
				Verify.expect(shadow.BlurRadius.Offset > 0):toBe(true)
				local _, rule = ruleIndex(sheet, ".facet-menu-hairline")
				Verify.expect(rule.BackgroundTransparency < 1):toBe(true)
				stop()
			end,
		})

		verifyHarness:case("a skinned panel sizes to its rows plus the art carve and keeps them in its content box", {
			id = "native_menu_parity::native menu parity with main::a skinned panel sizes to its rows plus the art carve and keeps them in its content box",
			run = function()
				for _, name in { "pixel_quest", "fantasy_ornate" } do
					local package = (require :: any)("../examples/themes/" .. name).build(Facet.themes)
					local carve = package.chrome.panel.contentInsets
					for _, count in { 3, 30 } do
						local world = labelled(
							{ items = items(count), presentation = "menu" :: "menu" },
							{ theme = package }
						)
						local panel = open(world)
						lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 200))
						local rows = panel:FindFirstChild("MenuRows", true)
						rows.AbsoluteSize = Vector2.new(220, count * 44)
						local padding = panel:FindFirstChildWhichIsA("UIPadding")
						Verify.expect(
							`{padding.PaddingLeft.Offset} {padding.PaddingTop.Offset} {padding.PaddingRight.Offset} {padding.PaddingBottom.Offset}`
						):toBe(`{carve.left} {carve.top} {carve.right} {carve.bottom}`)
						local at = rows.Parent
						while at ~= panel do
							if at ~= rows.Parent or at:IsA("ScrollingFrame") then
								Verify.expect(`{at.Name} {at.Size} {at.Position}`)
									:toBe(`{at.Name} {UDim2.fromScale(1, 1)} {UDim2.new()}`)
							end
							at = at.Parent
						end
						local want = math.min(count * 44 + carve.top + carve.bottom, 600 - 24)
						Verify.expect(`{name} {count} {panel.Size.Y.Offset}`):toBe(`{name} {count} {want}`)
						Verify.expect(panel.Size.X.Offset):toBe(220 + carve.left + carve.right)
						world.stop()
					end
				end
			end,
		})

		verifyHarness:case("a 300-row menu fades through a window-sized group, never one as tall as its rows", {
			id = "native_menu_parity::native menu parity with main::a 300-row menu fades through a window-sized group, never one as tall as its rows",
			run = function()
				local world = labelled({ items = items(300), presentation = "menu" :: "menu" }, {})
				local panel = open(world)
				local rows = panel:FindFirstChild("MenuRows", true)
				local groups = {}
				for _, node in panel:GetDescendants() do
					if node:IsA("CanvasGroup") and rows:IsDescendantOf(node) then
						table.insert(groups, node)
					end
				end
				Verify.expect(#groups):toBe(1)
				local group = groups[1]
				Verify.expect(group.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				Verify.expect(group.Size):toBe(UDim2.fromScale(1, 1))
				local at = group.Parent
				while at and at ~= panel do
					Verify.expect((at:IsA("ScrollingFrame"))):toBe(false)
					at = at.Parent
				end
				Verify.expect((panel:IsA("ScrollingFrame"))):toBe(false)
				Verify.expect((rows.Parent:IsA("ScrollingFrame"))):toBe(true)
				Verify.expect((rows.Parent:IsDescendantOf(group))):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case(
			"a 300-row sheet level cross-fades through a window-sized group, never one as tall as its rows",
			{
				id = "native_menu_parity::native menu parity with main::a 300-row sheet level cross-fades through a window-sized group, never one as tall as its rows",
				run = function()
					local world = labelled({
						items = { { id = "big", label = "Big", children = items(300) } },
						presentation = "sheet" :: "sheet",
					}, {})
					local panel = open(world)
					lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(776, 200))
					for _ = 1, 40 do
						world.engine.heartbeat:Fire(FRAME)
					end
					world.find("big", panel).Activated:Fire()
					for _ = 1, 3 do
						world.engine.heartbeat:Fire(FRAME)
					end
					local rows = panel:FindFirstChild("MenuRows", true)
					local scroller = panel:FindFirstChild("MenuScroll", true)
					local fading = 0
					for _, node in panel:GetDescendants() do
						if node:IsA("CanvasGroup") then
							Verify.expect((node:IsDescendantOf(scroller))):toBe(false)
							if rows:IsDescendantOf(node) then
								Verify.expect(node.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
								Verify.expect(node.Size):toBe(UDim2.fromScale(1, 1))
								fading += 1
							end
						end
					end
					Verify.expect(fading >= 1):toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case("grows each level from 0.96 at the corner it hangs at, fades in and dips out faster", {
			id = "native_menu_parity::native menu parity with main::grows each level from 0.96 at the corner it hangs at, fades in and dips out faster",
			run = function()
				local world = labelled(
					{ edge = "top" :: "top", align = "end" :: "end", items = NESTED, presentation = "menu" :: "menu" },
					{}
				)
				local panel = open(world)
				lay(world, panel, Vector2.new(300, 300), Vector2.new(200, 40), Vector2.new(220, 200))
				local scale = materialize.of(panel)
				local group = world.find("MenuGroup", panel)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect((fadeKit.of(group))):toBe(1)
				world.engine.heartbeat:Fire(FRAME)
				world.engine.heartbeat:Fire(FRAME)
				Verify.expect(scale.Scale >= 0.95 and scale.Scale < 1):toBe(true)
				local shrink = 1 - scale.Scale
				Verify.expect(materialize.position(panel).X.Offset):toBeCloseTo(280 + 220 * shrink, 1)
				Verify.expect(materialize.position(panel).Y.Offset):toBeCloseTo(96 + 200 * shrink, 2)
				local enter = 0
				while scale.Scale < 1 and enter < 60 do
					world.engine.heartbeat:Fire(FRAME)
					enter += 1
				end
				for _ = 1, 30 do
					world.engine.heartbeat:Fire(FRAME)
				end
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect((materialize.position(panel))):toBe(UDim2.fromOffset(280, 96))
				world.find("adjust", panel).Activated:Fire()
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect((fadeKit.of(group))):toBe(1)
				world.engine.heartbeat:Fire(FRAME)
				world.engine.heartbeat:Fire(FRAME)
				Verify.expect(scale.Scale >= 0.95 and scale.Scale < 1):toBe(true)
				for _ = 1, 30 do
					world.engine.heartbeat:Fire(FRAME)
				end
				Verify.expect(scale.Scale):toBe(1)
				world.find("DismissOutside", world.screen.Parent).Activated:Fire()
				local exit, cleared = 0, 0
				while not panel:isDestroyed() and exit < 60 do
					world.engine.heartbeat:Fire(FRAME)
					exit += 1
					if cleared == 0 and fadeKit.of(group) >= 0.95 then
						cleared = exit
					end
				end
				Verify.expect(exit > 0 and exit < enter):toBe(true)
				Verify.expect(cleared > 0 and cleared < exit):toBe(true)
				for _ = 1, 30 do
					world.engine.heartbeat:Fire(FRAME)
				end
				Verify.expect((panel:isDestroyed())):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case(
			"pivots a default panel at its top leading corner and a trailing panel at its leading side",
			{
				id = "native_menu_parity::native menu parity with main::pivots a default panel at its top leading corner and a trailing panel at its leading side",
				run = function()
					for
						_,
						case: {
						edge: "trailing" | "bottom" | nil,
						align: "start" | "center" | nil,
						pivot: typeof(Vector2.new(0, 0)) | typeof(Vector2.new(110, 0)),
						at: typeof(Vector2.new(100, 144))
							| typeof(Vector2.new(304, 100))
							| typeof(Vector2.new(90, 144)),
					}
					in
						{
							{ edge = nil, align = nil, pivot = Vector2.new(0, 0), at = Vector2.new(100, 144) },
							{
								edge = "trailing" :: "trailing",
								align = "start" :: "start",
								pivot = Vector2.new(0, 0),
								at = Vector2.new(304, 100),
							},
							{
								edge = "bottom" :: "bottom",
								align = "center" :: "center",
								pivot = Vector2.new(110, 0),
								at = Vector2.new(90, 144),
							},
						} :: {
							{
								edge: "trailing" | "bottom" | nil,
								align: "start" | "center" | nil,
								pivot: typeof(Vector2.new(0, 0)) | typeof(Vector2.new(110, 0)),
								at: typeof(Vector2.new(100, 144))
									| typeof(Vector2.new(304, 100))
									| typeof(Vector2.new(90, 144)),
							}
						}
					do
						local world = labelled({ edge = case.edge, align = case.align, items = items(3) }, {})
						local panel = open(world)
						lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 200))
						world.engine.heartbeat:Fire(FRAME)
						world.engine.heartbeat:Fire(FRAME)
						local shrink = 1 - materialize.of(panel).Scale
						Verify.expect(shrink > 0):toBe(true)
						Verify.expect(materialize.position(panel).X.Offset)
							:toBeCloseTo(case.at.X + case.pivot.X * shrink, 1)
						Verify.expect(materialize.position(panel).Y.Offset)
							:toBeCloseTo(case.at.Y + case.pivot.Y * shrink, 1)
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case("removes the travel under reduced motion for the panel and each submenu level", {
			id = "native_menu_parity::native menu parity with main::removes the travel under reduced motion for the panel and each submenu level",
			run = function()
				local world = labelled({ items = NESTED, presentation = "menu" :: "menu" })
				local panel = open(world)
				lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 200))
				world.engine.heartbeat:Fire(FRAME)
				world.engine.heartbeat:Fire(FRAME)
				Verify.expect(materialize.of(panel).Scale):toBe(1)
				Verify.expect((fadeKit.of(world.find("MenuGroup", panel)))):toBe(0)
				world.find("adjust", panel).Activated:Fire()
				Verify.expect(materialize.of(panel).Scale):toBe(1)
				world.engine.heartbeat:Fire(FRAME)
				world.engine.heartbeat:Fire(FRAME)
				Verify.expect(materialize.of(panel).Scale):toBe(1)
				Verify.expect((fadeKit.of(world.find("MenuGroup", panel)))):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("follows a trigger that moves while the menu is open", {
			id = "native_menu_parity::native menu parity with main::follows a trigger that moves while the menu is open",
			run = function()
				local world = labelled({ items = items(3) })
				local panel = open(world)
				lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 200))
				Verify.expect((materialize.position(panel))):toBe(UDim2.fromOffset(100, 144))
				world.find("Trigger").AbsolutePosition = Vector2.new(260, 180)
				Verify.expect((materialize.position(panel))):toBe(UDim2.fromOffset(260, 224))
				world.find("Trigger").AbsolutePosition = Vector2.new(260, 500)
				Verify.expect((materialize.position(panel))):toBe(UDim2.fromOffset(260, 296))
				world.stop()
			end,
		})

		verifyHarness:case("clamps the panel inside the GuiService inset when its screen ignores the inset", {
			id = "native_menu_parity::native menu parity with main::clamps the panel inside the GuiService inset when its screen ignores the inset",
			run = function()
				local world = labelled({ edge = "top" :: "top", items = items(3) })
				world.screen.IgnoreGuiInset = true
				world.gui.GetGuiInset = function()
					return Vector2.new(40, 58), Vector2.new(24, 34)
				end
				local panel = open(world)
				lay(world, panel, Vector2.new(10, 20), Vector2.new(60, 40), Vector2.new(220, 200))
				Verify.expect((materialize.position(panel))):toBe(UDim2.fromOffset(48, 66))
				lay(world, panel, Vector2.new(700, 400), Vector2.new(60, 40), Vector2.new(220, 200))
				Verify.expect((materialize.position(panel))):toBe(UDim2.fromOffset(800 - 24 - 8 - 220, 196))
				world.find("Trigger").AbsolutePosition = Vector2.new(300, 560)
				Verify.expect(materialize.position(panel).Y.Offset + 200 <= 600 - 34 - 8):toBe(true)
				world.stop()
				local plain = labelled({ edge = "top" :: "top", items = items(3) })
				plain.gui.GetGuiInset = function()
					return Vector2.new(40, 58), Vector2.new(24, 34)
				end
				local inside = open(plain)
				lay(plain, inside, Vector2.new(10, 20), Vector2.new(60, 40), Vector2.new(220, 200))
				Verify.expect((materialize.position(inside))):toBe(UDim2.fromOffset(10, 64))
				plain.stop()
			end,
		})

		verifyHarness:case("a menu shown as a sheet slides up from below the layer and never scales", {
			id = "native_menu_parity::native menu parity with main::a menu shown as a sheet slides up from below the layer and never scales",
			run = function()
				local world = labelled({ items = items(3), presentation = "sheet" :: "sheet" }, {})
				local panel = open(world)
				lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(776, 200))
				for _ = 1, 3 do
					world.engine.heartbeat:Fire(FRAME)
				end
				local scale = materialize.of(panel)
				Verify.expect(scale.Scale):toBe(1)
				local early = materialize.position(panel).Y.Offset
				for _ = 1, 40 do
					world.engine.heartbeat:Fire(FRAME)
				end
				local rest = materialize.position(panel).Y.Offset
				Verify.expect(early > rest):toBe(true)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect(rest):toBe(600 - 200 - 12)
				world.stop()
			end,
		})

		verifyHarness:case("a sheet menu level change cross-fades its rows while they slide", {
			id = "native_menu_parity::native menu parity with main::a sheet menu level change cross-fades its rows while they slide",
			run = function()
				local world = labelled({ items = NESTED, presentation = "sheet" :: "sheet" }, {})
				local panel = open(world)
				lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(776, 200))
				for _ = 1, 40 do
					world.engine.heartbeat:Fire(FRAME)
				end
				world.find("adjust", panel).Activated:Fire()
				for _ = 1, 3 do
					world.engine.heartbeat:Fire(FRAME)
				end
				local rows = world.find("MenuLevel", panel)
				Verify.expect(fadeKit.of(rows) > 0):toBe(true)
				for _ = 1, 30 do
					world.engine.heartbeat:Fire(FRAME)
				end
				Verify.expect((fadeKit.of(rows))):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case(
			"a pointer submenu grows from the chosen row, and Back grows the parent from the child's side",
			{
				id = "native_menu_parity::native menu parity with main::a pointer submenu grows from the chosen row, and Back grows the parent from the child's side",
				run = function()
					local world = labelled({ items = NESTED, presentation = "menu" :: "menu" }, {})
					local panel = open(world)
					lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 132))
					for _ = 1, 40 do
						world.engine.heartbeat:Fire(FRAME)
					end
					local adjust = world.find("adjust", panel)
					adjust.AbsolutePosition = Vector2.new(panel.AbsolutePosition.X, panel.AbsolutePosition.Y + 44)
					adjust.Activated:Fire()
					for _ = 1, 3 do
						world.engine.heartbeat:Fire(FRAME)
					end
					local scale = materialize.of(panel)
					Verify.expect(scale.Scale < 1):toBe(true)
					local shrink = 1 - scale.Scale
					Verify.expect(materialize.position(panel).X.Offset):toBeCloseTo(100 + 288, 1)
					Verify.expect(materialize.position(panel).Y.Offset):toBeCloseTo(144 + 44 * shrink, 1)
					for _ = 1, 40 do
						world.engine.heartbeat:Fire(FRAME)
					end
					world.action("MenuLeft").Pressed:Fire()
					Verify.expect(world.find("adjust", panel) ~= nil):toBe(true)
					for _ = 1, 3 do
						world.engine.heartbeat:Fire(FRAME)
					end
					Verify.expect(scale.Scale < 1):toBe(true)
					shrink = 1 - scale.Scale
					Verify.expect(materialize.position(panel).X.Offset):toBeCloseTo(100 + 220 * shrink, 2)
					Verify.expect(materialize.position(panel).X.Offset > 101):toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"each level remembers its own row, Back to the root uses the root's row, and a root exit faces the trigger",
			{
				id = "native_menu_parity::native menu parity with main::each level remembers its own row, Back to the root uses the root's row, and a root exit faces the trigger",
				run = function()
					local function leaf(id: string): any
						return { id = id, label = id, onSelect = function() end }
					end
					local deep = {
						leaf("plain"),
						{ divider = true },
						{
							id = "Divider",
							label = "More",
							children = {
								leaf("x"),
								leaf("y"),
								{ id = "b", label = "B", children = { leaf("p"), leaf("q") } },
							},
						},
					}
					local world = labelled({ items = deep, presentation = "menu" :: "menu" }, {})
					local panel = open(world)
					lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 132))
					local function settle()
						for _ = 1, 40 do
							world.engine.heartbeat:Fire(FRAME)
						end
					end
					settle()
					local scale = materialize.of(panel)
					local more = world.find("Divider", panel)
					for _, node in panel:GetDescendants() do
						if node.Name == "Divider" and node:IsA("GuiButton") then
							more = node
						end
					end
					more.AbsolutePosition = Vector2.new(panel.AbsolutePosition.X, panel.AbsolutePosition.Y + 10)
					more.Activated:Fire()
					settle()
					local b = world.find("b", panel)
					b.AbsolutePosition = Vector2.new(panel.AbsolutePosition.X, panel.AbsolutePosition.Y + 120)
					b.Activated:Fire()
					settle()
					world.action("MenuLeft").Pressed:Fire()
					for _ = 1, 2 do
						world.engine.heartbeat:Fire(FRAME)
					end
					local shrink = 1 - scale.Scale
					Verify.expect(shrink > 0):toBe(true)
					local top = materialize.position(panel).Y.Offset
					settle()
					Verify.expect(math.abs(top - (materialize.position(panel).Y.Offset + 120 * shrink)) < 1.5)
						:toBe(true)
					world.action("MenuLeft").Pressed:Fire()
					for _ = 1, 3 do
						world.engine.heartbeat:Fire(FRAME)
					end
					shrink = 1 - scale.Scale
					Verify.expect(shrink > 0):toBe(true)
					top = materialize.position(panel).Y.Offset
					settle()
					Verify.expect(math.abs(top - (materialize.position(panel).Y.Offset + 10 * shrink)) < 1.5):toBe(true)
					local rest = materialize.position(panel).X.Offset
					world.find("DismissOutside", world.screen.Parent).Activated:Fire()
					world.engine.heartbeat:Fire(FRAME)
					world.engine.heartbeat:Fire(FRAME)
					Verify.expect(scale.Scale < 1):toBe(true)
					Verify.expect(materialize.position(panel).X.Offset):toBe(rest)
					world.stop()
				end,
			}
		)

		verifyHarness:case("a level change during the exit does not re-measure: the panel keeps shrinking", {
			id = "native_menu_parity::native menu parity with main::a level change during the exit does not re-measure: the panel keeps shrinking",
			run = function()
				local list = Compose.cell(NESTED)
				local world = labelled({ items = list, presentation = "menu" :: "menu" }, {})
				local panel = open(world)
				lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 132))
				for _ = 1, 40 do
					world.engine.heartbeat:Fire(FRAME)
				end
				world.find("adjust", panel).Activated:Fire()
				for _ = 1, 40 do
					world.engine.heartbeat:Fire(FRAME)
				end
				local scale = materialize.of(panel)
				world.find("DismissOutside", world.screen.Parent).Activated:Fire()
				world.engine.heartbeat:Fire(FRAME)
				local leaving = scale.Scale
				Verify.expect(leaving < 1):toBe(true)
				list:set({ NESTED[1], NESTED[3] })
				world.engine.heartbeat:Fire(FRAME)
				Verify.expect(scale.Scale <= leaving):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("bounds a sheet by the inset at the bottom and the sides", {
			id = "native_menu_parity::native menu parity with main::bounds a sheet by the inset at the bottom and the sides",
			run = function()
				local world = labelled({ presentation = "sheet" :: "sheet", items = items(3) })
				world.screen.IgnoreGuiInset = true
				world.gui.GetGuiInset = function()
					return Vector2.new(40, 58), Vector2.new(24, 34)
				end
				local panel = open(world)
				lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(736, 200))
				world.engine.heartbeat:Fire(FRAME)
				world.engine.heartbeat:Fire(FRAME)
				Verify.expect(panel.Size.X.Offset):toBe(-24 - 40 - 24)
				Verify.expect((materialize.position(panel))):toBe(UDim2.fromOffset(52, 600 - 34 - 200 - 12))
				world.stop()
			end,
		})

		for _, reduced in { false, true } do
			verifyHarness:case(`slides sheet submenus forward on entry and backward on Back; reduced={reduced}`, {
				id = "native_menu_parity::"
					.. "native menu parity with main"
					.. "::"
					.. `slides sheet submenus forward on entry and backward on Back; reduced={reduced}`,
				run = function()
					local world = labelled(
						{ presentation = "sheet" :: "sheet", items = NESTED },
						{ motionLevel = if reduced then "none" else "normal" }
					)
					local panel = open(world)
					lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(776, 200))
					for _ = 1, 30 do
						world.engine.heartbeat:Fire(FRAME)
					end
					local rows = panel:FindFirstChild("MenuRows", true)
					Verify.expect(rows.Position.X.Offset):toBe(0)
					world.find("adjust", panel).Activated:Fire()
					world.engine.heartbeat:Fire(FRAME)
					world.engine.heartbeat:Fire(FRAME)
					local forward = rows.Position.X.Offset
					Verify.expect(if reduced then forward == 0 else forward > 0):toBe(true)
					world.engine.heartbeat:Fire(FRAME)
					Verify.expect(if reduced then true else rows.Position.X.Offset < forward):toBe(true)
					for _ = 1, 30 do
						world.engine.heartbeat:Fire(FRAME)
					end
					Verify.expect(rows.Position.X.Offset):toBe(0)
					world.find("Back", panel).Activated:Fire()
					local backward = rows.Position.X.Offset
					Verify.expect(if reduced then backward == 0 else backward < 0):toBe(true)
					for _ = 1, 30 do
						world.engine.heartbeat:Fire(FRAME)
					end
					Verify.expect(rows.Position.X.Offset):toBe(0)
					Verify.expect(world.find("adjust", panel) ~= nil):toBe(true)
					world.stop()
				end,
			})
		end
	end)
end
