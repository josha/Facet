--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local hud = require("../examples/gallery/scenarios/hud")
	local measured = require("./lib/hud_measure")
	local selectionControls = require("../examples/gallery/scenarios/selection_controls")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	local SHIPPED = {
		"classic_desktop",
		"compact_pointer",
		"fantasy_ornate",
		"fantasy_parchment",
		"glossy_mobile",
		"glossy_touch",
		"pixel_quest",
		"scifi_hud",
	}

	type World = {
		engine: any,
		runtime: any,
		gui: any,
		input: any,
		screen: any,
		parent: any,
		stop: () -> (),
	}

	local function setup(build: (any, any, any, any) -> any, options: { [string]: any }?): World
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
		local parent = engine.new("Folder")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			inputParent = parent,
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, screen: any = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host, engine, runtime) })
		end, parent)
		return {
			engine = engine,
			runtime = runtime,
			gui = gui,
			input = input,
			screen = screen,
			parent = parent,
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

	local function tab(world: World)
		local traverse = find(world.parent, "FacetTraversal")
		assert(traverse, "the traversal context exists")
		traverse:FindFirstChild("Traverse").Pressed:Fire()
	end

	local function selected(world: World): string
		local node = world.gui.SelectedObject
		return if node then node.Name else "nil"
	end

	local function ring(world: World, limit: number): { string }
		world.gui.SelectedObject = nil
		local names = {}
		for _ = 1, limit do
			tab(world)
			local name = selected(world)
			if names[1] == name then
				break
			end
			table.insert(names, name)
		end
		return names
	end

	local function inputCensus(root: any): string
		local contexts, actions, keys = 0, 0, {}
		for _, node in root:GetDescendants() do
			if node:IsA("InputContext") and node.Enabled then
				contexts += 1
			elseif node:IsA("InputAction") and node.Enabled and node.Parent.Enabled then
				actions += 1
			elseif node:IsA("InputBinding") and node.Parent.Parent.Enabled then
				table.insert(keys, node.KeyCode.Name)
			end
		end
		table.sort(keys)
		return `contexts={contexts} actions={actions} keys={table.concat(keys, ",")}`
	end

	local function sheetFor(package: any): (any, any, () -> ())
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local stop, sheet: any = runtime.mount(function()
			return themes.createStyleSheet(runtime, package, { types = engine.types } :: any)
		end, engine.new("Folder"))
		return sheet, engine, function()
			stop()
			runtime:dispose()
		end
	end

	local function ruleNode(sheet: any, selector: string): any
		local found
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				found = node
			end
		end
		assert(found, "No rule: " .. selector)
		return found
	end

	local function packages(): { { name: string, package: any } }
		local list = { { name = "Neutral", package = themes.neutralPackage() } }
		for _, name in SHIPPED do
			local module: any = (require :: any)("../examples/themes/" .. name)
			table.insert(list, { name = name, package = module.build(themes) })
		end
		return list
	end

	local function luminance(color: any): number
		local function channel(value: number): number
			return if value <= 0.03928 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
	end

	local function contrast(a: any, b: any): number
		local x, y = luminance(a), luminance(b)
		return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
	end

	verifyHarness:suite("native parity classb keyboard", function()
		verifyHarness:case("walks Tab through a top strip, the content and a bottom strip in layout order and wraps", {
			id = "native_parity_classb_keyboard::native parity classb keyboard::walks Tab through a top strip, the content and a bottom strip in layout order and wraps",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.Screen("Page")({
						UI.HStack("Bar")({
							UI.Button("Left")({ label = "Left" }) :: unknown,
							UI.Button("Right")({ label = "Right" }),
						}) :: unknown,
						UI.Button("A")({ label = "Content A" }),
						UI.Button("B")({ label = "Content B" }),
						UI.HStack("Foot")({
							UI.Button("FootLeft")({ label = "Left" }) :: unknown,
							UI.Button("FootRight")({ label = "Right" }),
						}),
					})
				end)
				Verify.expect((ring(world, 12))):toEqual({ "Left", "Right", "A", "B", "FootLeft", "FootRight" })
				world.gui.SelectedObject = find(world.screen, "B")
				tab(world)
				Verify.expect((selected(world))):toBe("FootLeft")
				tab(world)
				tab(world)
				Verify.expect((selected(world))):toBe("Left")
				world.stop()
			end,
		})

		verifyHarness:case("places a row mounted after the first press at its layout position on the next Tab", {
			id = "native_parity_classb_keyboard::native parity classb keyboard::places a row mounted after the first press at its layout position on the next Tab",
			run = function()
				local late = Compose.cell(false)
				local world = setup(function(UI: FacetControls)
					return UI.Screen("S")({
						UI.Button("A")({ label = "A" }) :: unknown,
						Compose.show(late, function()
							return UI.Button("Late")({ label = "Late" })
						end),
						UI.Slider("V")({ label = "V", value = Compose.cell(0.5) }),
						UI.Button("B")({ label = "B" }),
					})
				end)
				Verify.expect((ring(world, 10))):toEqual({ "A", "V", "B" })
				world.gui.SelectedObject = find(world.screen, "A")
				late:set(true)
				tab(world)
				Verify.expect((selected(world))):toBe("Late")
				tab(world)
				Verify.expect((selected(world))):toBe("V")
				Verify.expect((ring(world, 10))):toEqual({ "A", "Late", "V", "B" })
				world.stop()
			end,
		})

		verifyHarness:case("tabs down a scroll view one row per press without control wiring", {
			id = "native_parity_classb_keyboard::native parity classb keyboard::tabs down a scroll view one row per press without control wiring",
			run = function()
				local world = setup(function(UI: FacetControls)
					local rows = {}
					for index = 1, 12 do
						rows[index] = UI.Button("Btn" .. index)({ label = "Row " .. index })
					end
					return UI.Screen("S")({
						UI.ScrollView("List")({ height = 160, table.unpack((rows :: unknown) :: { unknown }) }),
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Btn1")
				for press = 1, 8 do
					tab(world)
					Verify.expect((selected(world))):toBe("Btn" .. (press + 1))
				end
				Verify.expect(find(world.screen, "List").ClassName):toBe("ScrollingFrame")
				world.stop()
			end,
		})

		verifyHarness:case("makes the slider its one selection stop and leaves the engine selection ring in place", {
			id = "native_parity_classb_keyboard::native parity classb keyboard::makes the slider its one selection stop and leaves the engine selection ring in place",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.Screen("S")({
						UI.Button("Before")({ label = "Before" }) :: unknown,
						UI.Slider("Vol")({ label = "Volume", value = Compose.cell(0.5), step = 0.1 }),
					})
				end)
				local slider = find(world.screen, "Vol")
				local stops = {}
				for _, node in slider:GetDescendants() do
					if node:IsA("GuiObject") and node.Selectable then
						table.insert(stops, node.Name)
					end
					if node:IsA("GuiObject") then
						Verify.expect(node.SelectionImageObject):toBeNil()
					end
				end
				Verify.expect(stops):toEqual({})
				Verify.expect(slider.Selectable):toBe(true)
				Verify.expect(slider.SelectionImageObject):toBeNil()
				Verify.expect(find(world.screen, "Before").SelectionImageObject):toBeNil()
				Verify.expect((ring(world, 6))):toEqual({ "Before", "Vol" })
				world.stop()
			end,
		})

		verifyHarness:case("reaches the checkbox and the Join button of the selection controls form by Tab", {
			id = "native_parity_classb_keyboard::native parity classb keyboard::reaches the checkbox and the Join button of the selection controls form by Tab",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine, runtime)
					local built = selectionControls.build({
						Facet = Facet,
						Compose = Compose,
						runtime = runtime,
						Host = Host,
						UI = UI,
						types = engine.types,
					})
					return built.screen()
				end)
				local names = ring(world, 200)
				local seen = { Checkbox = false, Join = false }
				for _, name in names do
					if seen[name] ~= nil then
						seen[name] = true
					end
				end
				local checkbox = find(world.screen, "Checkbox")
				if not seen.Checkbox and checkbox then
					for _, node in checkbox:GetDescendants() do
						if table.find(names, node.Name) and node.Selectable then
							seen.Checkbox = true
						end
					end
				end
				Verify.expect(seen):toEqual({ Checkbox = true, Join = true })
				world.stop()
			end,
		})

		verifyHarness:case(
			"restores the HUD selection stops and input bindings of a fresh mount after the rotation sequence",
			{
				id = "native_parity_classb_keyboard::native parity classb keyboard::restores the HUD selection stops and input bindings of a fresh mount after the rotation sequence",
				run = function()
					local function hudWorld(size: { width: number, height: number })
						local viewport = Compose.cell(size)
						local built
						local world = setup(function(UI: FacetControls, Host: RobloxHost, engine, runtime)
							built = hud.build({
								Facet = Facet,
								Compose = Compose,
								runtime = runtime,
								Host = Host,
								UI = UI,
								types = engine.types,
								viewport = viewport,
							})
							return built.screen()
						end, { viewport = viewport })
						return world, built, viewport
					end
					local landscape, portrait = { width = 844, height = 390 }, { width = 390, height = 844 }
					local function settle(world: World, box: { number })
						measured.measure(world.screen, world.engine, box)
						world.engine.heartbeat:Fire(1)
					end
					local fresh = hudWorld(landscape)
					settle(fresh, measured.LANDSCAPE)
					local wantRing, wantInput = ring(fresh, 80), inputCensus(fresh.parent)
					Verify.expect(#wantRing > 3):toBe(true)
					fresh.stop()
					local live, built, viewport = hudWorld(landscape)
					settle(live, measured.LANDSCAPE)
					local start = ring(live, 80)
					Verify.expect(start):toEqual(wantRing)
					built.steps.openUrlBar()
					viewport:set(portrait)
					settle(live, measured.PORTRAIT)
					local midway = ring(live, 80)
					Verify.expect(table.concat(midway, ",") ~= table.concat(start, ",")):toBe(true)
					built.steps.closeUrlBar()
					viewport:set(landscape)
					settle(live, measured.LANDSCAPE)
					Verify.expect((ring(live, 80))):toEqual(wantRing)
					Verify.expect((inputCensus(live.parent))):toBe(wantInput)
					live.stop()
				end,
			}
		)

		verifyHarness:case(
			"orders the role rules after the base fills and gives them their own hover and press rules",
			{
				id = "native_parity_classb_keyboard::native parity classb keyboard::orders the role rules after the base fills and gives them their own hover and press rules",
				run = function()
					for _, entry in packages() do
						local sheet, _, stop = sheetFor(entry.package)
						local destructive = ruleNode(sheet, ".facet-role-destructive")
						local hover = ruleNode(sheet, ".facet-role-destructive:Hover")
						local press = ruleNode(sheet, ".facet-role-destructive:Press")
						for _, base in
							{ ".facet-control", ".facet-button", ".facet-button:Hover", ".facet-button:Press" }
						do
							Verify.expect(destructive.Priority > ruleNode(sheet, base).Priority):toBe(true)
						end
						Verify.expect(hover.Priority > ruleNode(sheet, ".facet-button:Hover").Priority):toBe(true)
						Verify.expect(press.Priority > ruleNode(sheet, ".facet-button:Press").Priority):toBe(true)
						local danger = destructive:GetProperties().BackgroundColor3
						Verify.expect(danger ~= nil):toBe(true)
						Verify.expect(hover:GetProperties().BackgroundColor3):toBe(danger)
						Verify.expect(press:GetProperties().BackgroundColor3):toBe(danger)
						Verify.expect(danger ~= ruleNode(sheet, ".facet-control"):GetProperties().BackgroundColor3)
							:toBe(true)
						Verify.expect(
							ruleNode(sheet, ".facet-role-cancel >> .facet-button-caption"):GetProperties().TextColor3
								~= nil
						):toBe(true)
						stop()
					end
				end,
			}
		)

		verifyHarness:case("rounds a circle Button with one real corner in every state and tags it for the sheet", {
			id = "native_parity_classb_keyboard::native parity classb keyboard::rounds a circle Button with one real corner in every state and tags it for the sheet",
			run = function()
				for _, entry in packages() do
					local world = setup(function(UI: FacetControls)
						return UI.Screen("S")({
							UI.Button("Plain")({ label = "x", shape = "circle" :: "circle" }) :: unknown,
							UI.Button("Danger")({
								label = "x",
								shape = "circle" :: "circle",
								role = "destructive" :: "destructive",
							}),
							UI.Button("Picked")({
								label = "x",
								shape = "circle" :: "circle",
								selected = Compose.cell(true),
							}),
							UI.Button("Soft")({ label = "x", shape = "circle" :: "circle", appearance = "soft" }),
							UI.Button("Rect")({ label = "Save" }),
						})
					end, { theme = entry.package })
					local T = world.engine.types
					for _, name in { "Plain", "Danger", "Picked", "Soft" } do
						local node = find(world.screen, name)
						local corners, aspects = {}, 0
						for _, child in node:GetChildren() do
							if child:IsA("UICorner") then
								table.insert(corners, child)
							elseif child:IsA("UIAspectRatioConstraint") then
								aspects += 1
							end
						end
						Verify.expect((node:HasTag("facet-shape-circle"))):toBe(true)
						Verify.expect(#corners):toBe(1)
						local round = entry.package.metrics.radii.pill > 0
						Verify.expect(corners[1].CornerRadius)
							:toBe(if round then T.UDim.new(1, 0) else T.UDim.new(0, 0))
						Verify.expect(aspects):toBe(1)
					end
					Verify.expect((find(world.screen, "Danger"):HasTag("facet-role-destructive"))):toBe(true)
					Verify.expect((find(world.screen, "Picked"):HasTag("facet-selected"))):toBe(true)
					local rect = find(world.screen, "Rect")
					Verify.expect((rect:HasTag("facet-shape-circle"))):toBe(false)
					Verify.expect((rect:FindFirstChildWhichIsA("UICorner"))):toBeNil()
					if entry.name == "Neutral" then
						local plain = find(world.screen, "Plain")
						Verify.expect(#plain:GetChildren()):toBe(2)
					end
					world.stop()
				end
				local sheet, engine, stop = sheetFor(themes.neutralPackage())
				local circle = ruleNode(sheet, ".facet-shape-circle::UIPadding")
				Verify.expect(circle.Priority > ruleNode(sheet, ".facet-button::UIPadding").Priority):toBe(true)
				Verify.expect(circle:GetProperties().PaddingLeft):toBe(engine.types.UDim.new(0, 0))
				stop()
			end,
		})

		verifyHarness:case("paints the key cap strong on a strong surface and lets it grow as a square", {
			id = "native_parity_classb_keyboard::native parity classb keyboard::paints the key cap strong on a strong surface and lets it grow as a square",
			run = function()
				for _, entry in packages() do
					local sheet, _, stop = sheetFor(entry.package)
					local cap = ruleNode(sheet, ".facet-shortcut-hint"):GetProperties()
					Verify.expect(contrast(cap.TextColor3, cap.BackgroundColor3) >= 4.5):toBe(true)
					for _, palette in entry.package.style.themes do
						local colors = palette.colors
						local text =
							{ R = colors.contentStrong.r, G = colors.contentStrong.g, B = colors.contentStrong.b }
						local fill =
							{ R = colors.surfaceStrong.r, G = colors.surfaceStrong.g, B = colors.surfaceStrong.b }
						Verify.expect(contrast(text, fill) >= 4.5):toBe(true)
					end
					stop()
				end
				local world = setup(function(UI: FacetControls)
					return UI.Screen("S")({ UI.ShortcutHint("Hint")({ keys = { { "K" } } }) })
				end)
				local hint = find(world.screen, "Hint")
				local E = world.engine.types.Enum
				Verify.expect(hint.AutomaticSize):toBe(E.AutomaticSize.XY)
				Verify.expect(hint.Size.X.Offset):toBe(hint.Size.Y.Offset)
				Verify.expect(hint.Size.Y.Offset < 44):toBe(true)
				Verify.expect(hint.Selectable):toBe(false)
				Verify.expect((hint:HasTag("facet-shortcut-hint"))):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("declares a 44 pixel strip for bar, glyph and star level pickers", {
			id = "native_parity_classb_keyboard::native parity classb keyboard::declares a 44 pixel strip for bar, glyph and star level pickers",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.Screen("S")({
						UI.LevelPicker("Bars")({ value = Compose.cell(3), count = 10 }) :: unknown,
						UI.LevelPicker("Glyphs")({ value = Compose.cell(2), count = 5, segment = "glyph" :: "glyph" }),
						UI.LevelPicker("Large")({
							value = Compose.cell(2),
							count = 3,
							segmentSize = "large" :: "large",
						}),
						UI.Rating("Stars")({ value = Compose.cell(3) }),
					})
				end)
				for _, name in { "Bars", "Glyphs", "Large", "Stars" } do
					local node = find(world.screen, name)
					Verify.expect(node.Size.Y.Offset >= 44):toBe(true)
					Verify.expect(node.Selectable):toBe(true)
					for _, child in node:GetDescendants() do
						if child:IsA("GuiObject") and string.match(child.Name, "^Level%d+$") then
							Verify.expect(child.Size.X.Offset > 0 and child.Size.Y.Offset > 0):toBe(true)
							Verify.expect(child.Selectable):toBe(false)
						end
					end
				end
				world.stop()
			end,
		})

		verifyHarness:case("reserves label clearance for the thumb and centres the stepper readout", {
			id = "native_parity_classb_keyboard::native parity classb keyboard::reserves label clearance for the thumb and centres the stepper readout",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.Screen("S")({
						UI.Slider("Vol")({ label = "Vol", value = Compose.cell(50), min = 0, max = 100 }) :: unknown,
						UI.Stepper("Qty")({ label = "Volume", value = Compose.cell(9), min = 0, max = 100 }),
					})
				end)
				local label = find(find(world.screen, "Vol"), "Label")
				local padding = label:FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding ~= nil):toBe(true)
				local thumb = find(find(world.screen, "Vol"), "Thumb")
				Verify.expect(padding.PaddingRight.Offset - thumb.Size.X.Offset / 2 >= 8):toBe(true)
				local readout = find(find(world.screen, "Qty"), "Value")
				Verify.expect(readout.TextXAlignment):toBe(world.engine.types.Enum.TextXAlignment.Center)
				world.stop()
			end,
		})
	end)
end
