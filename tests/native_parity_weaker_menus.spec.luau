--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)
	type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	local FixtureRadialTypes = require("../src/ui/radial_types")
	local FixtureCollectionTypes = require("../src/ui/collection_types")

	local materialize = require("./lib/materialize")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local navMenu = require("../src/ui/nav_menu")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	type World = {
		engine: any,
		runtime: any,
		gui: any,
		input: any,
		root: any,
		now: () -> number,
		step: (number) -> (),
		stop: () -> (),
	}

	local function setup(build: (any, any, any) -> any, options: { [string]: any }?): World
		local engine: any = engineLib.new(options and options.engine)
		local now = 0
		engine.clock = function()
			return now
		end
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local root = engine.new("ScreenGui")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
			inputParent = root,
			motionLevel = "none",
		}
		for key, value in (options or {}) :: { [string]: any } do
			if key ~= "engine" then
				config[key] = value
			end
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop = runtime.mount(function()
			return Host.Frame "Surface" {
				Size = engine.types.UDim2.fromScale(1, 1),
				build(UI, Host, engine),
			}
		end, root)
		return {
			engine = engine,
			runtime = runtime,
			gui = gui,
			input = input,
			root = root,
			now = function()
				return now
			end,
			step = function(seconds: number)
				for _ = 1, math.ceil(seconds * 60) do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
				end
			end,
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

	local function all(root: any, name: string): { any }
		local found = {}
		for _, node in root:GetDescendants() do
			if node.Name == name then
				table.insert(found, node)
			end
		end
		return found
	end

	local function action(root: any, name: string): any
		for _, node in root:GetDescendants() do
			if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
				return node:FindFirstChild(name)
			end
		end
		return nil
	end

	local function enabledContexts(root: any, name: string): { any }
		local found = {}
		for _, node in root:GetDescendants() do
			if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
				table.insert(found, node)
			end
		end
		return found
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

	local function mountError(build: (any, any) -> any): string?
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local UI =
			Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } } :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local ok, message = pcall(function()
			local stop = runtime.mount(function()
				return Host.ScreenGui({ build(UI, Host) })
			end, engine.new("Folder"))
			stop()
		end)
		runtime:dispose()
		return if ok then nil else tostring(message)
	end

	local function refuses(message: string, build: (any, any) -> any): boolean
		local failure = mountError(build)
		return failure ~= nil and string.find(failure, message, 1, true) ~= nil
	end

	local function settle(world: World, root: any)
		for _ = 1, 3 do
			for _, node in root:GetDescendants() do
				if node:IsA("TextLabel") or node:IsA("TextButton") then
					local fits = node.TextFits
					node.TextFits = not fits
					node.TextFits = fits
				end
			end
			world.step(0.25)
		end
	end

	local function segmentState(segment: any): string
		return `{segment.TextWrapped}|{string.match(tostring(segment.TextTruncate), "%w+$")}`
	end

	local function glyphText(glyph: () -> number): { [string]: any }
		local Vector2 = require("@lune/roblox").Vector2
		local function widest(text: string, pattern: string): number
			local most = 0
			for piece in string.gmatch(text, pattern) do
				most = math.max(most, #piece * glyph())
			end
			return most
		end
		return {
			measureText = function(node: any): any
				local words = widest(node.Text or "", "%S+")
				if node.TextWrapped then
					local width = node.AbsoluteSize.X
					return Vector2.new(
						if words > width then width else math.max(words, math.min(#node.Text * glyph(), width)),
						40
					)
				end
				return Vector2.new(widest(node.Text or "", "[^\n]+"), 20)
			end,
			textFits = function(node: any): boolean?
				if node.Text == "" or node.TextWrapped or node.AbsoluteSize.X == 0 then
					return nil
				end
				return widest(node.Text, "[^\n]+") <= node.AbsoluteSize.X
			end,
		}
	end

	local function V2(world: World, x: number, y: number): any
		return world.engine.types.Vector2.new(x, y)
	end

	local function offer(world: World, segment: any, width: number)
		segment.AbsoluteSize = V2(world, width, 44)
	end

	local function title(row: any): string
		local label = find(row, "Title")
		return if label then label.Text else row.Text
	end

	local function count(row: any): string?
		local badge = row:FindFirstChild("Count", true)
		if badge == nil then
			return nil
		end
		if badge:IsA("TextLabel") then
			return badge.Text
		end
		for _, node in badge:GetDescendants() do
			if node:IsA("TextLabel") and node.Text ~= "" then
				return node.Text
			end
		end
		return nil
	end

	local function selectables(root: any): { any }
		local found = {}
		for _, node in root:GetDescendants() do
			if node:IsA("GuiObject") and node.Selectable and node.Visible and node.Interactable then
				table.insert(found, node)
			end
		end
		return found
	end

	local THREE = {
		{ value = "easy", label = "Easy" },
		{ value = "normal", label = "Normal" },
		{ value = "hard", label = "Hard" },
	}

	local NESTED = {
		{
			id = "adjust",
			label = "Adjust",
			children = {
				{ id = "head", label = "Head Adjustment", onSelect = function() end } :: MenuItem,
				{
					id = "layer",
					label = "Layering",
					children = {
						{ id = "clothing", label = "Clothing Layering", onSelect = function() end },
						{ id = "makeup", label = "Makeup Layering", onSelect = function() end },
					},
				} :: MenuItem,
			},
		} :: MenuItem,
		{ id = "skin", label = "Skin Color", onSelect = function() end } :: MenuItem,
	}

	local function place(world: World, trigger: any, x: number, y: number, width: number, height: number)
		trigger.AbsolutePosition = V2(world, x, y)
		trigger.AbsoluteSize = V2(world, width, height)
	end

	local function extent(world: World, width: number, height: number): any
		local modal = find(world.root, "Modal")
		modal.AbsolutePosition = V2(world, 0, 0)
		modal.AbsoluteSize = V2(world, width, height)
		return modal
	end

	verifyHarness:suite("native parity weaker menus", function()
		verifyHarness:case(
			"opens a radial menu from its launcher, runs only the chosen command and releases every native object",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::opens a radial menu from its launcher, runs only the chosen command and releases every native object",
				run = function()
					local engine: any = engineLib.new()
					local now = 0
					engine.clock = function()
						return now
					end
					local function step(seconds: number)
						for _ = 1, math.ceil(seconds * 60) do
							now += 1 / 60
							engine.heartbeat:Fire(1 / 60)
						end
					end
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = engine.new("GuiService")
					local input = engine.new("UserInputService")
					input.GetFocusedTextBox = function()
						return nil
					end
					local target = engine.new("Folder")
					local baseline = engine.census()
					local fired = 0
					local UI = Facet.controls(
						runtime,
						{
							types = engine.types,
							guiService = gui,
							services = { GuiService = gui, UserInputService = input },
							motionLevel = "normal",
						} :: any
					)
					local stop, screen: any = runtime.mount(function()
						return runtime.constructors.ScreenGui({
							UI.RadialMenu "Actions" {
								items = {
									{
										id = "wave",
										label = "Wave",
										onSelect = function()
											fired += 1
										end,
									} :: FixtureRadialTypes.RadialItem<any>,
									{
										id = "point",
										label = "Point",
										onSelect = function()
											fired += 10
										end,
									} :: FixtureRadialTypes.RadialItem<any>,
								},
							},
						})
					end, target)
					step(0.3)
					Verify.expect((find(screen, "RadialPanel"))):toBeNil()
					find(screen, "Launcher").Activated:Fire()
					step(0.7)
					local panel = find(screen, "RadialPanel")
					Verify.expect(panel ~= nil):toBe(true)
					Verify.expect(find(panel, "point") ~= nil):toBe(true)
					find(panel, "wave").Activated:Fire()
					step(0.7)
					Verify.expect(fired):toBe(1)
					Verify.expect((find(screen, "RadialPanel"))):toBeNil()
					Verify.expect((panel:isDestroyed())):toBe(true)
					stop()
					step(0.5)
					runtime:dispose()
					Verify.expect((screen:isDestroyed())):toBe(true)
					Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
					local after = engine.census()
					Verify.expect(after.live):toBe(baseline.live)
					Verify.expect(after.connections):toBe(baseline.connections)
				end,
			}
		)

		verifyHarness:case(
			"overlays the quick palette on a 393 pixel phone inside its own box and sets the shared palette",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::overlays the quick palette on a 393 pixel phone inside its own box and sets the shared palette",
				run = function()
					local Roblox = require("../src/vendor/compose/roblox")
					local modelModule = require("../examples/virtual_monitors/model")
					local screens = require("../examples/virtual_monitors/screens")
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Roblox.createRuntime(engine)
					local target = engine.new("ScreenGui")
					local gui, input = engine.new("GuiService"), engine.new("UserInputService")
					input.GetFocusedTextBox = function()
						return nil
					end
					input.IsKeyDown = function()
						return false
					end
					local lifetime = Compose.createRootOwner(function()
						local model = modelModule.new(Compose)
						Compose.cleanup(model.dispose)
						local views = screens.create(Facet, runtime, {
							model = model,
							types = engine.types,
							services = { GuiService = gui, UserInputService = input },
							motionLevel = "none",
						})
						local stop, avatar: any = runtime.mount(views.Avatar, target)
						avatar.AbsoluteSize = engine.types.Vector2.new(393, 852)
						local quick = find(avatar, "QuickPalette")
						local launcher = find(quick, "Launcher")
						Verify.expect(launcher.Visible):toBe(true)
						Verify.expect((model.palette:peek())):toBe("sage")
						launcher.Activated:Fire()
						local modal = find(target, "Modal")
						Verify.expect((within(modal, quick))):toBe(false)
						Verify.expect(modal.Size.X.Scale):toBe(1)
						Verify.expect(modal.Size.Y.Scale):toBe(1)
						modal.AbsolutePosition = engine.types.Vector2.new(0, 0)
						modal.AbsoluteSize = engine.types.Vector2.new(393, 852)
						local panel = find(target, "RadialPanel")
						Verify.expect(panel.Parent):toBe(modal)
						local x = panel.Position.X.Scale * 393 + panel.Position.X.Offset
						local y = panel.Position.Y.Scale * 852 + panel.Position.Y.Offset
						local width = panel.Size.X.Scale * 393 + panel.Size.X.Offset
						local height = panel.Size.Y.Scale * 852 + panel.Size.Y.Offset
						Verify.expect(x >= 0 and y >= 0):toBe(true)
						Verify.expect(x + width <= 393):toBe(true)
						Verify.expect(y + height <= 852):toBe(true)
						Verify.expect(height >= 400):toBe(true)
						find(panel, "clay").Activated:Fire()
						Verify.expect((model.palette:peek())):toBe("clay")
						stop()
					end, runtime.reactor)
					lifetime.dispose()
					Verify.expect(#target:GetChildren()):toBe(0)
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"closes an open menu picker on a tap away without changing the selection and restores the trigger",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::closes an open menu picker on a tap away without changing the selection and restores the trigger",
				run = function()
					local selected, opened, changes = Compose.cell("normal"), Compose.cell(false), 0
					local world = setup(function(UI)
						return UI.Picker "Difficulty" {
							style = "menu" :: "menu",
							selected = selected,
							isPresented = opened,
							options = THREE,
							onChange = function()
								changes += 1
							end,
						}
					end)
					local trigger = find(world.root, "Trigger")
					place(world, trigger, 100, 40, 160, 44)
					world.gui.SelectedObject = trigger
					trigger.Activated:Fire()
					Verify.expect((opened:peek())):toBe(true)
					local panel = find(world.root, "MenuPanel")
					Verify.expect((within(world.gui.SelectedObject, panel))):toBe(true)
					extent(world, 800, 600)
					panel.AbsolutePosition = V2(world, 100, 88)
					panel.AbsoluteSize = V2(world, 220, 150)
					local catcher = find(world.root, "DismissOutside")
					Verify.expect(catcher.Size.X.Scale):toBe(1)
					Verify.expect(catcher.Size.Y.Scale):toBe(1)
					catcher.Activated:Fire({ Position = V2(world, 700, 550) })
					Verify.expect((opened:peek())):toBe(false)
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					Verify.expect((selected:peek())):toBe("normal")
					Verify.expect(changes):toBe(0)
					Verify.expect(world.gui.SelectedObject):toBe(trigger)
					trigger.Activated:Fire()
					find(world.root, "Modal").AbsoluteSize = V2(world, 800, 600)
					panel = find(world.root, "MenuPanel")
					panel.AbsolutePosition = V2(world, 100, 88)
					panel.AbsoluteSize = V2(world, 220, 150)
					find(world.root, "DismissOutside").Activated:Fire({ Position = V2(world, 180, 50) })
					Verify.expect((opened:peek())):toBe(false)
					Verify.expect((selected:peek())):toBe("normal")
					Verify.expect(changes):toBe(0)
					Verify.expect(world.gui.SelectedObject):toBe(trigger)
					world.stop()
				end,
			}
		)

		verifyHarness:case("closes an open menu picker on Back and leaves Back unclaimed while it is closed", {
			id = "native_parity_weaker_menus::native parity weaker menus::closes an open menu picker on Back and leaves Back unclaimed while it is closed",
			run = function()
				local selected, opened, changes = Compose.cell("normal"), Compose.cell(false), 0
				local world = setup(function(UI)
					return UI.Picker "Difficulty" {
						style = "menu" :: "menu",
						selected = selected,
						isPresented = opened,
						options = THREE,
						onChange = function()
							changes += 1
						end,
					}
				end)
				local Enum = world.engine.types.Enum
				local function backClaims(): number
					local count = 0
					for _, node in world.root:GetDescendants() do
						if node:IsA("InputContext") and node.Enabled then
							for _, binding in node:GetDescendants() do
								if
									binding:IsA("InputBinding")
									and (
										binding.KeyCode == Enum.KeyCode.ButtonB
										or binding.KeyCode == Enum.KeyCode.Escape
									)
								then
									count += 1
								end
							end
						end
					end
					return count
				end
				local trigger = find(world.root, "Trigger")
				world.gui.SelectedObject = trigger
				Verify.expect((backClaims())):toBe(0)
				trigger.Activated:Fire()
				Verify.expect(backClaims() > 0):toBe(true)
				world.gui.SelectedObject = find(find(world.root, "MenuPanel"), "hard")
				action(world.root, "ModalBack").Pressed:Fire()
				Verify.expect((opened:peek())):toBe(false)
				Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
				Verify.expect((selected:peek())):toBe("normal")
				Verify.expect(changes):toBe(0)
				Verify.expect(world.gui.SelectedObject):toBe(trigger)
				Verify.expect((backClaims())):toBe(0)
				Verify.expect((action(world.root, "ModalBack"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("renders the icon-only glyph without a label and refuses an option without an icon", {
			id = "native_parity_weaker_menus::native parity weaker menus::renders the icon-only glyph without a label and refuses an option without an icon",
			run = function()
				local options: FixtureComposeTypes.Cell<{ { value: string, label: string, icon: string? } }> =
					Compose.cell(
						{ { value = "a", label = "Route", icon = "checkmark" } } :: { { value: string, label: string, icon: string? } }
					)
				local world = setup(function(UI)
					return UI.Picker "Icons" {
						style = "segmented" :: "segmented",
						iconOnly = true,
						selected = Compose.cell("a"),
						options = options,
					}
				end)
				local row = find(find(world.root, "Icons"), "a")
				Verify.expect(find(row, "LeadingIcon").Image):toBe(themes.resolveIcon({}, "checkmark"))
				Verify.expect((title(row))):toBe("")
				Verify.expect((row:GetAttribute("FacetLabel"))):toBe("Route")
				local ok = pcall(function()
					options:set({ { value = "a", label = "Route" } })
				end)
				Verify.expect(ok):toBe(false)
				world.stop()
				for _, style in
					{ "segmented", "inline", "radioGroup", "menu" } :: { "inline" | "menu" | "radioGroup" | "segmented" }
				do
					for _, live in { false, true } do
						local list = { { value = "a", label = "Route" } }
						Verify.expect((refuses("Picker.iconOnly requires an icon on each option", function(UI)
							return UI.Picker({
								style = style :: "inline" | "menu" | "radioGroup" | "segmented",
								iconOnly = true,
								selected = Compose.cell("a"),
								options = if live then Compose.cell(list) else list,
							})
						end))):toBe(true)
					end
				end
			end,
		})

		verifyHarness:case(
			"keeps choice rows, their selection focus and missing selected values through live replacements",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::keeps choice rows, their selection focus and missing selected values through live replacements",
				run = function()
					local selected = Compose.cell("a")
					local options = Compose.cell({
						{ id = "one", value = "a", label = "Alpine", badge = 3 } :: PickerOption,
						{ id = "two", value = "b", label = "Beach" } :: PickerOption,
					})
					local world = setup(function(UI)
						return UI.Picker "Routes" {
							style = "radioGroup" :: "radioGroup",
							selected = selected,
							options = options,
						}
					end)
					local picker = find(world.root, "Routes")
					local row = find(picker, "one")
					world.gui.SelectedObject = row
					Verify.expect((title(row))):toBe("Alpine")
					Verify.expect((count(row))):toBe("3")
					Verify.expect(find(row, "Description").Visible):toBe(false)
					options:set({
						{ id = "one", value = "a", label = "Alpine pass", description = "A mountain route", badge = 7 } :: PickerOption,
						{ id = "two", value = "c", label = "Coast" } :: PickerOption,
					})
					Verify.expect((find(picker, "one"))):toBe(row)
					Verify.expect(world.gui.SelectedObject):toBe(row)
					Verify.expect((title(row))):toBe("Alpine pass")
					Verify.expect((count(row))):toBe("7")
					Verify.expect(find(row, "Description").Text):toBe("A mountain route")
					Verify.expect(find(row, "Description").Visible):toBe(true)
					Verify.expect((selected:peek())):toBe("a")
					options:set({
						{ id = "one", value = "a", label = "Alpine pass" } :: PickerOption,
						{ id = "two", value = "c", label = "Coast" } :: PickerOption,
					})
					Verify.expect((find(picker, "one"))):toBe(row)
					Verify.expect(world.gui.SelectedObject):toBe(row)
					Verify.expect((title(row))):toBe("Alpine pass")
					Verify.expect((count(row))):toBeNil()
					Verify.expect(find(row, "Description").Visible):toBe(false)
					local survivor = find(picker, "two")
					options:set({ { id = "two", value = "c", label = "Coast" } })
					Verify.expect((find(picker, "one"))):toBeNil()
					Verify.expect((find(picker, "two"))):toBe(survivor)
					Verify.expect((selected:peek())):toBe("a")
					survivor.Activated:Fire()
					Verify.expect((selected:peek())):toBe("c")
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"keeps a radio group exclusive and skips a disabled option without rewriting the owner state",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::keeps a radio group exclusive and skips a disabled option without rewriting the owner state",
				run = function()
					local selected, enabled, changes = Compose.cell("a"), Compose.cell(false), 0
					local world = setup(function(UI)
						return UI.Picker "Access" {
							style = "radioGroup" :: "radioGroup",
							selected = selected,
							onChange = function()
								changes += 1
							end,
							options = {
								{ value = "a", label = "Open" } :: FixtureNavigationTypes.PickerOption<any>,
								{
									value = "b",
									label = "Club",
									description = "Requires club membership",
									enabled = enabled,
								} :: FixtureNavigationTypes.PickerOption<any>,
							},
						}
					end)
					local picker = find(world.root, "Access")
					local a, b = find(picker, "a"), find(picker, "b")
					local function current(): { string }
						local names = {}
						for _, node in picker:GetDescendants() do
							if node:HasTag("facet-choice-current") then
								table.insert(names, node.Name)
							end
						end
						return names
					end
					Verify.expect(b.Interactable):toBe(false)
					b.Activated:Fire()
					Verify.expect((selected:peek())):toBe("a")
					Verify.expect(changes):toBe(0)
					Verify.expect((current())):toEqual({ "a" })
					enabled:set(true)
					b.Activated:Fire()
					Verify.expect((selected:peek())):toBe("b")
					Verify.expect(changes):toBe(1)
					Verify.expect((current())):toEqual({ "b" })
					enabled:set(false)
					Verify.expect((selected:peek())):toBe("b")
					Verify.expect(changes):toBe(1)
					Verify.expect((current())):toEqual({ "b" })
					a.Activated:Fire()
					Verify.expect((selected:peek())):toBe("a")
					Verify.expect((current())):toEqual({ "a" })
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"refuses malformed picker options and callback contracts by name for static and live sources",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::refuses malformed picker options and callback contracts by name for static and live sources",
				run = function()
					local optionCases: { { any } } = {
						{ "Picker options require a dense array", { named = { value = "a", label = "Alpha" } } },
						{
							"Picker options require a dense array",
							{ [1] = { value = "a", label = "Alpha" }, [3] = { value = "b", label = "Beta" } },
						},
						{
							"Picker options require unique values or ids",
							{ { value = "a", label = "Alpha" }, { value = "a", label = "Again" } },
						},
						{ "Picker options require unique values or ids", { { label = "Nameless" } } },
						{ "Picker options require nonempty labels", { { value = "a", label = "" } } },
						{
							"Picker description must be text",
							{ { value = "a", label = "Alpha", description = false } },
						},
						{
							"Picker option enabled must be a boolean",
							{ { value = "a", label = "Alpha", enabled = "false" } },
						},
						{
							"Picker option badge must be text or a number",
							{ { value = "a", label = "Alpha", badge = {} } },
						},
						{
							"Picker option icon must be an icon name",
							{ { value = "a", label = "Alpha", icon = false } },
						},
						{
							"Unknown Picker option field misspelled",
							{ { value = "a", label = "Alpha", misspelled = true } },
						},
					}
					for _, style in { "radioGroup", "menu", "segmented" } :: { "menu" | "radioGroup" | "segmented" } do
						for _, live in { false, true } do
							for _, case in optionCases do
								Verify.expect((refuses(case[1], function(UI)
									return UI.Picker({
										style = style :: "menu" | "radioGroup" | "segmented",
										selected = Compose.cell("a"),
										options = if live then Compose.cell(case[2]) else case[2],
									})
								end))):toBe(true)
							end
						end
					end
					local specCases: { { any } } = {
						{ "Picker.onChange must be a function", { onChange = true } },
						{ "Picker.onChanging must be a function", { onChanging = true } },
						{ "Picker.required must be a boolean", { required = "false" } },
						{ "Picker.enabled must be a boolean", { enabled = "false" } },
						{ "Picker.enabled must be a boolean", { enabled = Compose.cell("false") } },
						{ "unknown option 'misspelled'", { misspelled = true } },
					}
					for _, style in
						{ "radioGroup", "menu", "navigationLink", "automatic" } :: { "automatic" | "menu" | "navigationLink" | "radioGroup" }
					do
						for _, live in { false, true } do
							for _, case in specCases do
								Verify.expect((refuses(case[1], function(UI)
									local list = { { value = "a", label = "Alpha" } }
									local spec: { [string]: any } = {
										style = style :: "automatic" | "menu" | "navigationLink" | "radioGroup",
										selected = Compose.cell("a"),
										options = if live then Compose.cell(list) else list,
									}
									for key, value in case[2] do
										spec[key] = value
									end
									return UI.Picker(spec)
								end))):toBe(true)
							end
						end
					end
					Verify.expect((mountError(function(UI)
						return UI.Picker({
							style = "radioGroup" :: "radioGroup",
							selected = Compose.cell("a"),
							enabled = Compose.cell(true),
							required = true,
							onChange = function() end,
							onChanging = function()
								return true
							end,
							options = {
								{ id = "x", value = "a", label = "Alpha", icon = "edit", badge = 2, enabled = true } :: FixtureNavigationTypes.PickerOption<any>,
							},
						})
					end))):toBeNil()
				end,
			}
		)

		verifyHarness:case(
			"collapses four long labels off the segmented strip when their measured width does not fit",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::collapses four long labels off the segmented strip when their measured width does not fit",
				run = function()
					local long = {
						{ value = "a", label = "Screen-anchored heads-up display" },
						{ value = "b", label = "Billboard following a world object" },
						{ value = "c", label = "World-fixed surface on a part" },
						{ value = "d", label = "Nothing presented at all today" },
					}
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Picker "Narrow" { selected = Compose.cell("a"), options = long } :: unknown,
							UI.Picker "Wide" { selected = Compose.cell("a"), options = long },
						})
					end)
					local Enum = world.engine.types.Enum
					world.input.PreferredInput = Enum.PreferredInput.Gamepad
					local narrow, wide = find(world.root, "Narrow"), find(world.root, "Wide")
					find(narrow, "LabelMeasure").TextBounds = V2(world, 960, 18)
					find(wide, "LabelMeasure").TextBounds = V2(world, 960, 18)
					narrow.AbsoluteSize = V2(world, 300, 44)
					wide.AbsoluteSize = V2(world, 1400, 44)
					local function presentation(node: any): any
						return node:FindFirstChild("Presentation")
					end
					Verify.expect((presentation(wide):HasTag("facet-segmented"))):toBe(true)
					Verify.expect((presentation(narrow):HasTag("facet-segmented"))):toBe(false)
					Verify.expect((find(presentation(narrow), "d"):HasTag("facet-choice"))):toBe(true)
					Verify.expect((find(presentation(narrow), "Trigger"))):toBeNil()
					world.input.PreferredInput = Enum.PreferredInput.Touch
					Verify.expect(find(presentation(narrow), "Trigger") ~= nil):toBe(true)
					Verify.expect((presentation(wide):HasTag("facet-segmented"))):toBe(true)
					narrow.AbsoluteSize = V2(world, 1200, 44)
					Verify.expect((presentation(narrow):HasTag("facet-segmented"))):toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case("draws a compact segmented strip at the compact rung, not the touch floor", {
			id = "native_parity_weaker_menus::native parity weaker menus::draws a compact segmented strip at the compact rung, not the touch floor",
			run = function()
				local world = setup(function(UI, Host)
					return Host.Frame({
						UI.Picker "Laps" {
							style = "segmented" :: "segmented",
							controlSize = "compact" :: "compact",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "3" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "5" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						},
					})
				end)
				local floor = find(world.root, "Laps"):FindFirstChild("TargetFloor", true)
				Verify.expect(floor.MinSize.Y < 50):toBe(true)
				world.stop()
			end,
		})

		local LONG = string.rep("Long segment label ", 5):sub(1, 80)
		local function segmentLimits(picker: any): ({ any }, number)
			local segments = {}
			for _, node in picker:GetDescendants() do
				if node:HasTag("facet-segment") then
					table.insert(segments, node)
				end
			end
			local widest = 0
			for _, segment in segments do
				local cap = math.huge
				for _, constraint in segment:GetChildren() do
					if constraint.ClassName == "UISizeConstraint" then
						cap = math.min(cap, constraint.MaxSize.X)
					end
				end
				widest = math.max(widest, cap)
			end
			return segments, widest
		end
		local function captionsWrap(segment: any, bound: number): boolean
			if segment.Text ~= "" then
				return segment.TextWrapped and string.find(tostring(segment.TextTruncate), "None", 1, true) ~= nil
			end
			for _, node in segment:GetDescendants() do
				if node:IsA("TextLabel") and node.Text ~= "" then
					local limit = node:FindFirstChildWhichIsA("UISizeConstraint")
					if not node.TextWrapped or limit == nil or limit.MaxSize.X > bound then
						return false
					end
				end
			end
			return true
		end

		verifyHarness:case("bounds a long segment label by the width of an unlabelled segmented strip", {
			id = "native_parity_weaker_menus::native parity weaker menus::bounds a long segment label by the width of an unlabelled segmented strip",
			run = function()
				for _, readable in { false, true } do
					local options = {
						{ value = "a", label = LONG },
						{ value = "b", label = "Rally" },
					}
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Picker "Mode" {
								style = "segmented" :: "segmented",
								selected = Compose.cell("a"),
								options = if readable then Compose.cell(options) else options,
							},
						})
					end)
					local picker = find(world.root, "Mode")
					picker.AbsoluteSize = V2(world, 300, 50)
					local segments, widest = segmentLimits(picker)
					Verify.expect(#segments):toBe(2)
					Verify.expect(widest <= 294):toBe(true)
					for _, segment in segments do
						Verify.expect((captionsWrap(segment, 294))):toBe(true)
					end
					picker.AbsoluteSize = V2(world, 1000, 50)
					Verify.expect((select(2, segmentLimits(picker)))):toBe(994)
					world.stop()
				end
			end,
		})

		verifyHarness:case("settles a segment whose word cannot fit on both axes, with no writes after it settles", {
			id = "native_parity_weaker_menus::native parity weaker menus::settles a segment whose word cannot fit on both axes, with no writes after it settles",
			run = function()
				for _, axis in { "x", "y" } do
					local writes = 0
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Picker "Status" {
								style = "segmented" :: "segmented",
								axis = axis,
								selected = Compose.cell("a"),
								options = {
									{ value = "a", label = "Supercalifragilistic" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "Go" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							},
						})
					end, {
						engine = {
							measureText = glyphText(function()
								return 11
							end).measureText,
							textFits = function(node: any): boolean?
								if node.Text == "" or node.AbsoluteSize.X == 0 then
									return nil
								end
								if node.TextWrapped then
									return true
								end
								return #node.Text * 11 <= node.AbsoluteSize.X
							end,
						},
					})
					local picker = find(world.root, "Status")
					picker.AbsoluteSize = V2(world, 300, 200)
					local segment = find(picker, "a")
					segment.AbsoluteSize = V2(world, 60, 44)
					settle(world, picker)
					Verify.expect(`{axis}:{segmentState(segment)}`):toBe(`{axis}:false|AtEnd`)
					segment:GetPropertyChangedSignal("TextWrapped"):Connect(function()
						writes += 1
					end)
					for _ = 1, 5 do
						settle(world, picker)
					end
					Verify.expect(`{axis}:{writes}`):toBe(`{axis}:0`)
					Verify.expect(`{axis}:{segmentState(segment)}`):toBe(`{axis}:false|AtEnd`)
					world.stop()
				end
			end,
		})

		verifyHarness:case("wraps a radio caption in a script without spaces instead of ending it in an ellipsis", {
			id = "native_parity_weaker_menus::native parity weaker menus::wraps a radio caption in a script without spaces instead of ending it in an ellipsis",
			run = function()
				local world = setup(function(UI, Host)
					return Host.Frame({
						UI.Picker "Voice" {
							style = "radioGroup" :: "radioGroup",
							selected = Compose.cell("a"),
							options = {
								{
									value = "a",
									label = "日本語",
									description = "音声チャットは近くのプレイヤーにだけ聞こえます",
								} :: FixtureNavigationTypes.PickerOption<any>,
							},
						},
					})
				end, {
					engine = glyphText(function()
						return 11
					end),
				})
				local picker = find(world.root, "Voice")
				picker.AbsoluteSize = V2(world, 200, 200)
				local description = find(find(picker, "a"), "Description")
				description.AbsoluteSize = V2(world, 120, 20)
				settle(world, picker)
				Verify.expect((segmentState(description))):toBe("true|None")
				Verify.expect((find(picker, "WidestWord"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("mounts a word probe only for a segment that has to wrap", {
			id = "native_parity_weaker_menus::native parity weaker menus::mounts a word probe only for a segment that has to wrap",
			run = function()
				local world = setup(function(UI, Host)
					return Host.Frame({
						UI.Picker "Status" {
							style = "segmented" :: "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "Error" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Voice" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "c", label = "High contrast" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						},
					})
				end, {
					engine = glyphText(function()
						return 11
					end),
				})
				local picker = find(world.root, "Status")
				picker.AbsoluteSize = V2(world, 400, 50)
				for _, name in { "a", "b", "c" } do
					find(picker, name).AbsoluteSize = V2(world, 150, 44)
				end
				settle(world, picker)
				local function probes(): number
					local count = 0
					for _, node in picker:GetDescendants() do
						if node.Name == "WidestWord" then
							count += 1
						end
					end
					return count
				end
				Verify.expect((probes())):toBe(0)
				find(picker, "c").AbsoluteSize = V2(world, 60, 44)
				settle(world, picker)
				Verify.expect((probes())):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case(
			"re-checks a wrapped segment on the following frames until its broken word ends in an ellipsis",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::re-checks a wrapped segment on the following frames until its broken word ends in an ellipsis",
				run = function()
					local environment = getfenv(navMenu)
					local originalTask = environment.task
					local threads = {}
					environment.task = {
						spawn = function(callback)
							local thread = coroutine.create(callback)
							table.insert(threads, thread)
							coroutine.resume(thread)
							return thread
						end,
						wait = function()
							return coroutine.yield()
						end,
						cancel = function(thread)
							coroutine.close(thread)
						end,
					}
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Picker "Status" {
								style = "segmented" :: "segmented",
								selected = Compose.cell("a"),
								options = {
									{ value = "a", label = "Error" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "Go" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							},
						})
					end, {
						engine = glyphText(function()
							return 11
						end),
					})
					local picker = find(world.root, "Status")
					picker.AbsoluteSize = V2(world, 300, 50)
					local segment = find(picker, "a")
					segment.AbsoluteSize = V2(world, 40, 44)
					Verify.expect((segmentState(segment))):toBe("true|None")
					local function frame()
						for _, thread in threads do
							if coroutine.status(thread) == "suspended" then
								coroutine.resume(thread)
							end
						end
					end
					frame()
					Verify.expect((segmentState(segment))):toBe("false|AtEnd")
					local function live(): number
						local count = 0
						for _, thread in threads do
							if coroutine.status(thread) == "suspended" then
								count += 1
							end
						end
						return count
					end
					local before = live()
					segment.AbsoluteSize = V2(world, 90, 44)
					segment.AbsoluteSize = V2(world, 30, 44)
					Verify.expect((live())):toBe(before)
					segment.AbsoluteSize = V2(world, 90, 44)
					segment.AbsoluteSize = V2(world, 30, 44)
					Verify.expect((live())):toBe(before)
					world.stop()
					for _, thread in threads do
						Verify.expect((coroutine.status(thread))):toBe("dead")
					end
					environment.task = originalTask
				end,
			}
		)

		verifyHarness:case("floors a strip segment at a 44 pixel target including its padding, not 44 plus padding", {
			id = "native_parity_weaker_menus::native parity weaker menus::floors a strip segment at a 44 pixel target including its padding, not 44 plus padding",
			run = function()
				local world = setup(function(UI, Host)
					return Host.Frame({
						UI.Picker "Strip" {
							style = "segmented" :: "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "On" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Off" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						} :: unknown,
						UI.Picker "Column" {
							style = "segmented" :: "segmented",
							axis = "y" :: "y",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "On" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Off" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						},
					})
				end)
				local function floor(picker: string): number
					for _, child in find(find(world.root, picker), "a"):GetChildren() do
						if child.ClassName == "UISizeConstraint" then
							return child.MinSize.X
						end
					end
					return -1
				end
				Verify.expect((floor("Strip"))):toBe(20)
				Verify.expect((floor("Column"))):toBe(44)
				world.stop()
			end,
		})

		verifyHarness:case(
			"keeps a segment word whole: it wraps between words and ends a word that cannot fit in an ellipsis",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::keeps a segment word whole: it wraps between words and ends a word that cannot fit in an ellipsis",
				run = function()
					local writes = 0
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Picker "Status" {
								style = "segmented" :: "segmented",
								selected = Compose.cell("a"),
								options = {
									{ value = "a", label = "Error" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "High contrast" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							},
						})
					end, {
						engine = glyphText(function()
							return 11
						end),
					})
					local picker = find(world.root, "Status")
					picker.AbsoluteSize = V2(world, 300, 50)
					local word, phrase = find(picker, "a"), find(picker, "b")
					offer(world, word, 80)
					offer(world, phrase, 200)
					settle(world, picker)
					Verify.expect((segmentState(word))):toBe("false|None")
					Verify.expect((segmentState(phrase))):toBe("false|None")
					offer(world, word, 40)
					offer(world, phrase, 100)
					settle(world, picker)
					Verify.expect((segmentState(word))):toBe("false|AtEnd")
					Verify.expect((segmentState(phrase))):toBe("true|None")
					offer(world, phrase, 60)
					settle(world, picker)
					Verify.expect((segmentState(phrase))):toBe("false|AtEnd")
					Verify.expect(phrase.Text):toBe("High contrast")
					word:GetPropertyChangedSignal("TextWrapped"):Connect(function()
						writes += 1
					end)
					word:GetPropertyChangedSignal("TextTruncate"):Connect(function()
						writes += 1
					end)
					settle(world, picker)
					settle(world, picker)
					Verify.expect(writes):toBe(0)
					offer(world, word, 90)
					settle(world, picker)
					Verify.expect((segmentState(word))):toBe("false|None")
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"re-decides a truncated segment caption when the strip's room or its segment count changes",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::re-decides a truncated segment caption when the strip's room or its segment count changes",
				run = function()
					local options = Compose.cell({
						{ value = "a", label = "High contrast" },
						{ value = "b", label = "Go" },
						{ value = "c", label = "On" },
					})
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Picker "Status" {
								style = "segmented" :: "segmented",
								selected = Compose.cell("a"),
								options = options,
							},
						})
					end, {
						engine = glyphText(function()
							return 11
						end),
					})
					local picker = find(world.root, "Status")
					picker.AbsoluteSize = V2(world, 300, 50)
					local segment = find(picker, "a")
					local title = find(segment, "Title")
					segment.AbsoluteSize = V2(world, 80, 44)
					title.AbsoluteSize = V2(world, 60, 20)
					settle(world, picker)
					Verify.expect((segmentState(title))):toBe("false|AtEnd")
					title.AbsoluteSize = V2(world, 200, 20)
					settle(world, picker)
					Verify.expect((segmentState(title))):toBe("false|AtEnd")
					options:set({ { value = "a", label = "High contrast" }, { value = "b", label = "Go" } })
					settle(world, picker)
					Verify.expect((segmentState(title))):toBe("false|None")
					title.AbsoluteSize = V2(world, 60, 20)
					settle(world, picker)
					Verify.expect((segmentState(title))):toBe("false|AtEnd")
					title.AbsoluteSize = V2(world, 200, 20)
					picker.AbsoluteSize = V2(world, 320, 50)
					settle(world, picker)
					Verify.expect((segmentState(title))):toBe("false|None")
					world.stop()
				end,
			}
		)

		verifyHarness:case("bounds a long segment label by the row width of a labelled segmented picker", {
			id = "native_parity_weaker_menus::native parity weaker menus::bounds a long segment label by the row width of a labelled segmented picker",
			run = function()
				local world = setup(function(UI, Host)
					return Host.Frame({
						UI.Picker "Mode" {
							label = "Mode",
							style = "segmented" :: "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = LONG } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Drift" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						},
					})
				end)
				local row = find(world.root, "Mode")
				row.AbsoluteSize = V2(world, 300, 100)
				local segments, widest = segmentLimits(find(row, "Options"))
				Verify.expect(#segments):toBe(2)
				Verify.expect(widest <= 294):toBe(true)
				for _, segment in segments do
					Verify.expect((captionsWrap(segment, 294))):toBe(true)
				end
				world.stop()
			end,
		})

		verifyHarness:case("refuses a search query on a segmented Picker", {
			id = "native_parity_weaker_menus::native parity weaker menus::refuses a search query on a segmented Picker",
			run = function()
				local ok, message = pcall(function()
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Picker "Mode" {
								style = "segmented" :: "segmented",
								query = Compose.cell(""),
								selected = Compose.cell("a"),
								options = {
									{ value = "a", label = "Road" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "Rally" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							},
						})
					end)
					world.stop()
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(
					string.find(tostring(message), "Facet UI.Picker: a segmented picker takes no query", 1, true) ~= nil
				)
					:toBe(true)
			end,
		})

		verifyHarness:case(
			"fits an explicit segmented strip inside the width of its labelled row: one constraint, shared width",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::fits an explicit segmented strip inside the width of its labelled row: one constraint, shared width",
				run = function()
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Picker "Handling" {
								label = "Handling",
								style = "segmented" :: "segmented",
								selected = Compose.cell("a"),
								options = {
									{ value = "a", label = "Arcade handling" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "Simulation handling" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "c", label = "Drift assist" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "d", label = "Rally gravel" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							},
						})
					end)
					local row = find(world.root, "Handling")
					local options = find(row, "Options")

					Verify.expect(options:FindFirstChildWhichIsA("UIListLayout", true).Wraps):toBe(false)
					local floor = options:FindFirstChild("TargetFloor")
					Verify.expect(floor.MinSize.Y):toBe(50)
					local constraints = 0
					for _, child in options:GetChildren() do
						if child.ClassName == "UISizeConstraint" then
							constraints += 1
						end
					end
					Verify.expect(constraints):toBe(1)
					row.AbsoluteSize = V2(world, 390, 100)
					Verify.expect(floor.MaxSize.X):toBe(390)
					row.AbsoluteSize = V2(world, 1280, 100)
					Verify.expect(floor.MaxSize.X):toBe(1280)
					world.stop()
				end,
			}
		)

		verifyHarness:case("leaves the segmented strip when the measured labels do not fit the width", {
			id = "native_parity_weaker_menus::native parity weaker menus::leaves the segmented strip when the measured labels do not fit the width",
			run = function()
				local long = {
					{ value = "a", label = "Automatic transmission mode" },
					{ value = "b", label = "Manual transmission override" },
					{ value = "c", label = "Sequential paddle shift gear" },
					{ value = "d", label = "Assisted launch control mode" },
				}
				local world = setup(function(UI, Host)
					return Host.Frame({ UI.Picker "Gears" { selected = Compose.cell("a"), options = long } })
				end)
				local Enum = world.engine.types.Enum
				world.input.PreferredInput = Enum.PreferredInput.Touch
				local picker = find(world.root, "Gears")
				picker.AbsoluteSize = V2(world, 400, 44)
				local measure = find(picker, "LabelMeasure")
				Verify.expect(measure ~= nil):toBe(true)
				Verify.expect(measure.Visible):toBe(false)
				Verify.expect(measure.Text):toBe(
					"Automatic transmission modeManual transmission overrideSequential paddle shift gearAssisted launch control mode"
				)
				local function presentation(): any
					return picker:FindFirstChild("Presentation")
				end
				measure.TextBounds = V2(world, 200, 18)
				Verify.expect((presentation():HasTag("facet-segmented"))):toBe(true)
				measure.TextBounds = V2(world, 791, 18)
				Verify.expect((presentation():HasTag("facet-segmented"))):toBe(false)
				Verify.expect(find(presentation(), "Trigger") ~= nil):toBe(true)
				picker.AbsoluteSize = V2(world, 920, 44)
				Verify.expect((presentation():HasTag("facet-segmented"))):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case(
			"opens the row menu from ButtonX and Menu, lists leading then trailing actions and scopes it to the selected row",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::opens the row menu from ButtonX and Menu, lists leading then trailing actions and scopes it to the selected row",
				run = function()
					local fired: { string } = {}
					local function row(UI: any, name: string): any
						return UI.RowActions(name)({
							content = UI.Button(name .. "Body")({ label = name }),
							leading = {
								{
									id = "archive",
									label = "Archive",
									onActivate = function()
										table.insert(fired, name .. ":archive")
									end,
								} :: FixtureCollectionTypes.RowAction,
							},
							trailing = {
								{
									id = "flag",
									label = "Flag",
									onActivate = function()
										table.insert(fired, name .. ":flag")
									end,
								} :: FixtureCollectionTypes.RowAction,
								{
									id = "delete",
									label = "Delete",
									role = "destructive" :: "destructive",
									onActivate = function()
										table.insert(fired, name .. ":delete")
									end,
								} :: FixtureCollectionTypes.RowAction,
							},
						})
					end
					local world = setup(function(UI, Host)
						return Host.Frame({ row(UI, "A") :: unknown, row(UI, "B") })
					end)
					local bodyA = find(world.root, "ABody")
					world.gui.SelectedObject = bodyA
					Verify.expect(#enabledContexts(world.root, "RowActionsReveal")):toBe(1)
					local reveal = action(world.root, "RowActionsReveal")
					Verify.expect(within(reveal, find(world.root, "A")) or within(bodyA, find(world.root, "A")))
						:toBe(true)
					local keys = {}
					for _, binding in reveal:GetChildren() do
						table.insert(keys, binding.KeyCode.Name)
					end
					table.sort(keys)
					Verify.expect(keys):toEqual({ "ButtonX", "Menu" })
					reveal.Pressed:Fire()
					local panel = find(world.root, "MenuPanel")
					Verify.expect(panel ~= nil):toBe(true)
					Verify.expect(#all(world.root, "MenuPanel")):toBe(1)
					Verify.expect(world.gui.SelectedObject.Name):toBe("leading:archive")
					local order = {}
					for _, node in panel:GetDescendants() do
						if node:HasTag("facet-menu-item") then
							table.insert(order, node)
						end
					end
					table.sort(order, function(left, right)
						return left.LayoutOrder < right.LayoutOrder
					end)
					local names = {}
					for _, node in order do
						table.insert(names, node.Name)
					end
					Verify.expect(names):toEqual({ "leading:archive", "trailing:flag", "trailing:delete" })
					for _, direction in { "Up", "Down", "Left", "Right" } :: { "Down" | "Left" | "Right" | "Up" } do
						Verify.expect(panel["SelectionBehavior" .. direction])
							:toBe(world.engine.types.Enum.SelectionBehavior.Stop)
					end
					Verify.expect((action(world.root, "RowActionsDelete"))):toBeNil()
					action(world.root, "ModalBack").Pressed:Fire()
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					Verify.expect(world.gui.SelectedObject):toBe(bodyA)
					Verify.expect(#fired):toBe(0)
					action(world.root, "RowActionsReveal").Pressed:Fire()
					find(find(world.root, "MenuPanel"), "trailing:flag").Activated:Fire()
					Verify.expect(fired):toEqual({ "A:flag" })
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					world.gui.SelectedObject = find(world.root, "BBody")
					Verify.expect(#enabledContexts(world.root, "RowActionsReveal")):toBe(1)
					action(world.root, "RowActionsReveal").Pressed:Fire()
					find(find(world.root, "MenuPanel"), "leading:archive").Activated:Fire()
					Verify.expect(fired):toEqual({ "A:flag", "B:archive" })
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"runs a destructive row action from its menu through the full departure and closes the menu first",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::runs a destructive row action from its menu through the full departure and closes the menu first",
				run = function()
					local invoked = 0
					local world = setup(function(UI)
						return UI.RowActions "Row" {
							content = UI.Button "Body" { label = "Row" },
							trailing = {
								{
									id = "delete",
									label = "Delete",
									role = "destructive" :: "destructive",
									onActivate = function()
										invoked += 1
									end,
								} :: FixtureCollectionTypes.RowAction,
							},
						}
					end, { motionLevel = "normal" })
					local row = find(world.root, "Row")
					row.AbsoluteSize = V2(world, 300, 44)
					world.gui.SelectedObject = find(row, "Body")
					action(world.root, "RowActionsReveal").Pressed:Fire()
					local panel = find(world.root, "MenuPanel")
					find(panel, "trailing:delete").Activated:Fire()
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					Verify.expect((find(world.root, "DismissOutside"))):toBeNil()
					Verify.expect(invoked):toBe(0)
					world.step(0.1)
					Verify.expect(invoked):toBe(0)
					Verify.expect(find(row, "Content").Position.X.Offset < 0):toBe(true)
					local frames = 0
					while invoked == 0 and frames < 60 do
						world.step(1 / 60)
						frames += 1
					end
					Verify.expect(invoked):toBe(1)
					Verify.expect(world.now() >= 0.2):toBe(true)
					Verify.expect(row.Size.Y.Offset):toBe(0)
					world.step(0.5)
					Verify.expect(invoked):toBe(1)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"presents a wide menu as a cascade for a pointer and as one sheet panel for gamepad and touch",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::presents a wide menu as a cascade for a pointer and as one sheet panel for gamepad and touch",
				run = function()
					local presented = Compose.cell(true)
					local world = setup(function(UI)
						return UI.Menu "Gear" { isPresented = presented, items = NESTED }
					end)
					local Enum = world.engine.types.Enum
					world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
					extent(world, 1280, 720)
					find(world.root, "adjust").Activated:Fire()
					Verify.expect(find(world.root, "AncestorMenu") ~= nil):toBe(true)
					Verify.expect(find(world.root, "MenuPanel").Size.X.Scale):toBe(0)
					world.input.PreferredInput = Enum.PreferredInput.Gamepad
					Verify.expect((find(world.root, "AncestorMenu"))):toBeNil()
					Verify.expect(find(world.root, "MenuPanel").Size.X.Scale):toBe(1)
					world.input.PreferredInput = Enum.PreferredInput.Touch
					Verify.expect((find(world.root, "AncestorMenu"))):toBeNil()
					Verify.expect(find(world.root, "MenuPanel").Size.X.Scale):toBe(1)
					Verify.expect(find(world.root, "Back") ~= nil):toBe(true)
					Verify.expect(find(world.root, "head") ~= nil):toBe(true)
					world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
					Verify.expect(find(world.root, "AncestorMenu") ~= nil):toBe(true)
					Verify.expect(find(world.root, "MenuPanel").Size.X.Scale):toBe(0)
					Verify.expect((presented:peek())):toBe(true)
					world.stop()
					for _, case in
						{
							{ style = "sheet", input = "KeyboardAndMouse", sheets = 1 },
							{ style = "menu", input = "Touch", sheets = 0 },
						}
					do
						local forced = setup(function(UI)
							return UI.Menu { isPresented = Compose.cell(true), presentation = case.style, items = NESTED }
						end)
						forced.input.PreferredInput = (Enum.PreferredInput :: any)[case.input]
						extent(forced, 1280, 720)
						find(forced.root, "adjust").Activated:Fire()
						Verify.expect(find(forced.root, "MenuPanel").Size.X.Scale):toBe(case.sheets)
						Verify.expect(find(forced.root, "AncestorMenu") == nil):toBe(case.style == "sheet")
						forced.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"opens a menu against its trigger rectangle, flips above it near the bottom and runs an item once",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::opens a menu against its trigger rectangle, flips above it near the bottom and runs an item once",
				run = function()
					local runs = 0
					local world = setup(function(UI)
						return UI.Menu "More" {
							label = "More",
							items = {
								{
									id = "go",
									label = "Go",
									onSelect = function()
										runs += 1
									end,
								} :: FixtureNavigationTypes.MenuItem<any>,
							},
						}
					end)
					local trigger = find(world.root, "Trigger")
					place(world, trigger, 100, 50, 120, 44)
					trigger.Activated:Fire()
					extent(world, 1000, 720)
					local panel = find(world.root, "MenuPanel")
					panel.AbsoluteSize = V2(world, 220, 200)
					Verify.expect(materialize.position(panel).Y.Offset >= 50 + 44):toBe(true)
					Verify.expect(materialize.position(panel).X.Offset):toBe(100)
					place(world, trigger, 950, 600, 120, 44)
					Verify.expect(materialize.position(panel).Y.Offset + 200 <= 600):toBe(true)
					Verify.expect(materialize.position(panel).X.Offset + 220 <= 1000 - 8):toBe(true)
					find(panel, "go").Activated:Fire()
					Verify.expect(runs):toBe(1)
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					Verify.expect((find(world.root, "Modal"))):toBeNil()
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"replaces a compact sheet level on entry and walks back one level from the row, Left and Back",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::replaces a compact sheet level on entry and walks back one level from the row, Left and Back",
				run = function()
					local presented = Compose.cell(false)
					local world = setup(function(UI)
						return UI.Menu "Avatar" { isPresented = presented, items = NESTED }
					end)
					local trigger = find(world.root, "Trigger")
					world.gui.SelectedObject = trigger
					trigger.Activated:Fire()
					extent(world, 360, 640)
					Verify.expect(find(world.root, "MenuPanel").Size.X.Scale):toBe(1)
					Verify.expect((find(world.root, "Back"))):toBeNil()
					Verify.expect(world.gui.SelectedObject.Name):toBe("adjust")
					local function enter(id: string)
						world.gui.SelectedObject = find(find(world.root, "MenuPanel"), id)
						find(find(world.root, "MenuPanel"), id).Activated:Fire()
					end
					enter("adjust")
					Verify.expect((find(world.root, "AncestorMenu"))):toBeNil()
					Verify.expect((find(world.root, "adjust"))):toBeNil()
					Verify.expect(find(world.root, "head") ~= nil):toBe(true)
					Verify.expect(find(world.root, "Back") ~= nil):toBe(true)
					Verify.expect(#all(world.root, "MenuPanel")):toBe(1)
					find(world.root, "Back").Activated:Fire()
					Verify.expect((presented:peek())):toBe(true)
					Verify.expect(find(world.root, "adjust") ~= nil):toBe(true)
					Verify.expect((find(world.root, "Back"))):toBeNil()
					Verify.expect(world.gui.SelectedObject.Name):toBe("adjust")
					enter("adjust")
					enter("layer")
					Verify.expect(find(world.root, "clothing") ~= nil):toBe(true)
					Verify.expect((find(world.root, "head"))):toBeNil()
					action(world.root, "MenuLeft").Pressed:Fire()
					Verify.expect(find(world.root, "head") ~= nil):toBe(true)
					Verify.expect(world.gui.SelectedObject.Name):toBe("layer")
					action(world.root, "ModalBack").Pressed:Fire()
					Verify.expect((presented:peek())):toBe(true)
					Verify.expect(find(world.root, "adjust") ~= nil):toBe(true)
					Verify.expect(world.gui.SelectedObject.Name):toBe("adjust")
					action(world.root, "ModalBack").Pressed:Fire()
					Verify.expect((presented:peek())):toBe(false)
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					Verify.expect(world.gui.SelectedObject):toBe(trigger)
					world.stop()
				end,
			}
		)

		verifyHarness:case("stacks each cascade level beside its parent at the trigger without overlapping it", {
			id = "native_parity_weaker_menus::native parity weaker menus::stacks each cascade level beside its parent at the trigger without overlapping it",
			run = function()
				local world = setup(function(UI)
					return UI.Menu "Avatar" { items = NESTED }
				end)
				local trigger = find(world.root, "Trigger")
				place(world, trigger, 100, 50, 120, 44)
				trigger.Activated:Fire()
				extent(world, 1600, 900)
				find(world.root, "adjust").Activated:Fire()
				local function levels(): { any }
					local found = all(world.root, "AncestorMenu")
					table.sort(found, function(left, right)
						return left.Position.X.Offset < right.Position.X.Offset
					end)
					return found
				end
				local first = levels()
				Verify.expect(#first):toBe(1)
				Verify.expect(find(first[1], "adjust") ~= nil):toBe(true)
				Verify.expect(first[1].Position.X.Offset):toBe(100)
				local panel = find(world.root, "MenuPanel")
				Verify.expect(panel.Position.X.Offset >= first[1].Position.X.Offset + first[1].Size.X.Offset):toBe(true)
				Verify.expect(panel.Position.Y.Offset):toBe(first[1].Position.Y.Offset)
				find(panel, "layer").Activated:Fire()
				local second = levels()
				Verify.expect(#second):toBe(2)
				Verify.expect(find(second[2], "layer") ~= nil):toBe(true)
				Verify.expect(second[2].Position.X.Offset >= second[1].Position.X.Offset + second[1].Size.X.Offset)
					:toBe(true)
				Verify.expect(panel.Position.X.Offset >= second[2].Position.X.Offset + second[2].Size.X.Offset)
					:toBe(true)
				Verify.expect(find(panel, "clothing") ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("labels the sheet Back row with the literal Back unless backLabel replaces it", {
			id = "native_parity_weaker_menus::native parity weaker menus::labels the sheet Back row with the literal Back unless backLabel replaces it",
			run = function()
				for _, case in { { nil, "Back" } :: { string? }, { "Zurück", "Zurück" } :: { string? } } do
					local world = setup(function(UI)
						return UI.Menu {
							isPresented = Compose.cell(true),
							presentation = "sheet" :: "sheet",
							backLabel = case[1],
							items = NESTED,
						}
					end)
					find(world.root, "adjust").Activated:Fire()
					local back = find(world.root, "Back")
					Verify.expect(find(back, "Title").Text):toBe(case[2])
					Verify.expect(find(back, "LeadingIcon") ~= nil):toBe(true)
					Verify.expect((back:HasTag("facet-appearance-utility"))):toBe(true)
					Verify.expect(
						find(back, "LeadingIcon").Parent:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment
					)
						:toBe(world.engine.types.Enum.HorizontalAlignment.Left)
					Verify.expect(back.ClassName):toBe("TextButton")
					Verify.expect(back.LayoutOrder < find(world.root, "head").LayoutOrder):toBe(true)
					world.stop()
				end
			end,
		})

		verifyHarness:case("switches the menu scenario idiom at depth and rebuilds the open chain in place", {
			id = "native_parity_weaker_menus::native parity weaker menus::switches the menu scenario idiom at depth and rebuilds the open chain in place",
			run = function()
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
				local target = engine.new("Folder")
				local ctx = {
					Facet = Facet,
					Compose = Compose,
					runtime = runtime,
					Host = (runtime.constructors :: unknown) :: RobloxHost,
					types = engine.types,
					viewport = Compose.cell({ width = 1200, height = 900 }),
					inputTarget = target,
					guiService = gui,
					runService = { Heartbeat = engine.heartbeat },
					UI = Facet.controls(
						runtime,
						{
							types = engine.types,
							guiService = gui,
							services = { GuiService = gui, UserInputService = input },
							motionLevel = "none",
						} :: any
					),
				}
				local scenario = require("../examples/gallery/scenarios/menu")
				local built
				local stop, screen: any = runtime.mount(function()
					built = scenario.build(ctx)
					return ctx.Host.ScreenGui({ built.screen() })
				end, target)
				local function modal(): any
					local node = find(screen, "Modal")
					node.AbsolutePosition = engine.types.Vector2.new(0, 0)
					node.AbsoluteSize = engine.types.Vector2.new(1200, 900)
					return node
				end
				local function enter(id: string)
					find(find(screen, "MenuPanel"), id).Activated:Fire()
				end
				built.steps.idiom(built, "panel")
				find(find(screen, "CardTap"), "Trigger").Activated:Fire()
				modal()
				enter("layering")
				Verify.expect(#all(screen, "AncestorMenu")):toBe(1)
				Verify.expect(find(find(screen, "MenuPanel"), "clothing") ~= nil):toBe(true)
				enter("makeup")
				Verify.expect(#all(screen, "AncestorMenu")):toBe(2)
				Verify.expect(find(find(screen, "MenuPanel"), "lips") ~= nil):toBe(true)
				built.steps.idiom(built, "sheet")
				Verify.expect(#all(screen, "AncestorMenu")):toBe(0)
				Verify.expect(#all(screen, "MenuPanel")):toBe(1)
				Verify.expect(find(find(screen, "MenuPanel"), "lips") ~= nil):toBe(true)
				Verify.expect(find(find(screen, "MenuPanel"), "Back") ~= nil):toBe(true)
				Verify.expect(string.find(built.report().state, scenario.copy.open, 1, true) ~= nil):toBe(true)
				built.steps.idiom(built, "panel")
				Verify.expect(#all(screen, "AncestorMenu")):toBe(2)
				Verify.expect(find(find(screen, "MenuPanel"), "lips") ~= nil):toBe(true)
				find(find(screen, "MenuPanel"), "lips").Activated:Fire()
				Verify.expect(built.report().ran):toBe(scenario.copy.lips)
				Verify.expect((find(screen, "MenuPanel"))):toBeNil()
				built.steps.idiom(built, "sheet")
				find(find(screen, "CardTap"), "Trigger").Activated:Fire()
				modal()
				Verify.expect((find(find(screen, "MenuPanel"), "Back"))):toBeNil()
				enter("layering")
				Verify.expect(#all(screen, "MenuPanel")):toBe(1)
				Verify.expect((find(find(screen, "MenuPanel"), "accessory"))):toBeNil()
				Verify.expect(find(find(screen, "MenuPanel"), "clothing") ~= nil):toBe(true)
				Verify.expect(find(find(screen, "MenuPanel"), "Back") ~= nil):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"shows the selected value, the disclosure chevron and the label row on a menu picker trigger",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::shows the selected value, the disclosure chevron and the label row on a menu picker trigger",
				run = function()
					local selected, changes = Compose.cell("normal"), {}
					local world = setup(function(UI)
						return UI.Picker "Difficulty" {
							style = "menu" :: "menu",
							label = "Difficulty",
							selected = selected,
							options = THREE,
							onChange = function(value)
								table.insert(changes, value)
							end,
						}
					end)
					local picker = find(world.root, "Difficulty")
					Verify.expect(find(picker, "Label").Text):toBe("Difficulty")
					local value = find(picker, "Value")
					Verify.expect(find(picker, "Label").LayoutOrder < value.LayoutOrder):toBe(true)
					Verify.expect(value.AnchorPoint.X):toBe(0)
					Verify.expect(value.Position.X.Scale):toBe(0)
					local trigger = find(value, "Trigger")
					Verify.expect(trigger.Text):toBe("Normal")
					Verify.expect((trigger:HasTag("facet-disclosure"))):toBe(true)
					local chevron = find(trigger, "Disclosure")
					Verify.expect((chevron:IsA("ImageLabel"))):toBe(true)
					Verify.expect(chevron.Image):toBe(themes.resolveIcon({}, "chevron.up.chevron.down"))
					local focusable = selectables(picker)
					Verify.expect(#focusable):toBe(1)
					Verify.expect(focusable[1]):toBe(trigger)
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					for _, option in THREE do
						Verify.expect((find(picker, option.value))):toBeNil()
					end
					trigger.Activated:Fire()
					local panel = find(world.root, "MenuPanel")
					for _, option in THREE do
						Verify.expect((title(find(panel, option.value)))):toBe(option.label)
					end
					find(panel, "hard").Activated:Fire()
					Verify.expect((selected:peek())):toBe("hard")
					Verify.expect(changes):toEqual({ "hard" })
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					Verify.expect(trigger.Text):toBe("Hard")
					trigger.Activated:Fire()
					find(find(world.root, "MenuPanel"), "hard").Activated:Fire()
					Verify.expect(changes):toEqual({ "hard" })
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					Verify.expect(trigger.Text):toBe("Hard")
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"lists every option with its label and check after pointer and touch activation of the trigger",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::lists every option with its label and check after pointer and touch activation of the trigger",
				run = function()
					for _, kind in { "MouseButton1", "Touch" } :: { "MouseButton1" | "Touch" } do
						local world = setup(function(UI)
							return UI.Picker "Difficulty" {
								style = "menu" :: "menu",
								selected = Compose.cell("normal"),
								options = THREE,
							}
						end)
						local Enum = world.engine.types.Enum
						find(world.root, "Trigger").Activated:Fire({
							UserInputType = (Enum.UserInputType :: any)[kind],
							Position = V2(world, 10, 10),
						})
						local panel = find(world.root, "MenuPanel")
						Verify.expect(panel ~= nil):toBe(true)
						local rows = {}
						for _, node in panel:GetDescendants() do
							if node:HasTag("facet-menu-item") then
								table.insert(rows, node)
							end
						end
						table.sort(rows, function(left, right)
							return left.LayoutOrder < right.LayoutOrder
						end)
						Verify.expect(#rows):toBe(#THREE)
						for index, option in THREE do
							Verify.expect(rows[index].Name):toBe(option.value)
							Verify.expect((title(rows[index]))):toBe(option.label)
							Verify.expect(find(rows[index], "TrailingIcon").Visible):toBe(option.value == "normal")
						end
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"becomes a sheet for a touch, gamepad or narrow menu picker and anchors to its trigger for a wide pointer",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::becomes a sheet for a touch, gamepad or narrow menu picker and anchors to its trigger for a wide pointer",
				run = function()
					local seven = {}
					for index = 1, 7 do
						table.insert(seven, { value = "v" .. index, label = "Value " .. index })
					end
					for _, case in
						{
							{ input = "Touch", width = 1280, options = THREE, sheets = 1 },
							{ input = "Touch", width = 1280, options = seven, sheets = 1 },
							{ input = "KeyboardAndMouse", width = 360, options = THREE, sheets = 1 },
							{ input = "KeyboardAndMouse", width = 1280, options = THREE, sheets = 0 },
							{ input = "Gamepad", width = 1280, options = seven, sheets = 1 },
						}
					do
						local selected = Compose.cell(case.options[1].value)
						local world = setup(function(UI)
							return UI.Picker "Choice" {
								style = "menu" :: "menu",
								selected = selected,
								options = case.options,
							}
						end)
						world.input.PreferredInput = (world.engine.types.Enum.PreferredInput :: any)[case.input]
						local trigger = find(world.root, "Trigger")
						place(world, trigger, 40, 40, 160, 44)
						trigger.Activated:Fire()
						extent(world, case.width, 720)
						local panel = find(world.root, "MenuPanel")
						Verify.expect(panel.Size.X.Scale):toBe(case.sheets)
						if case.sheets == 1 then
							Verify.expect(panel.Size.X.Offset):toBe(-24)
						else
							Verify.expect(panel.Position.X.Offset):toBe(40)
							Verify.expect(panel.Position.Y.Offset >= 84):toBe(true)
						end
						find(panel, case.options[2].value).Activated:Fire()
						Verify.expect((selected:peek())):toBe(case.options[2].value)
						Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case("forwards authored native properties to a navigation link and fills its search rows", {
			id = "native_parity_weaker_menus::native parity weaker menus::forwards authored native properties to a navigation link and fills its search rows",
			run = function()
				local selection, query, opened = Compose.cell("a"), Compose.cell(""), Compose.cell(false)
				local world = setup(function(UI, _, engine)
					return UI.Picker "Track" {
						style = "navigationLink" :: "navigationLink",
						label = "Track",
						selected = selection,
						query = query,
						isPresented = opened,
						Size = engine.types.UDim2.new(1, 0, 0, 44),
						LayoutOrder = 4,
						options = {
							{ value = "a", label = "Alpha" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "b", label = "Beta" } :: FixtureNavigationTypes.PickerOption<any>,
						},
					}
				end)
				local trigger = find(world.root, "Track")
				Verify.expect(trigger.ClassName):toBe("TextButton")
				Verify.expect((title(trigger))):toBe("Track")
				Verify.expect(trigger.Size.X.Scale):toBe(1)
				Verify.expect(trigger.LayoutOrder):toBe(4)
				world.gui.SelectedObject = trigger
				trigger.Activated:Fire()
				local sheet = find(world.root, "PickerSearch")
				Verify.expect(find(sheet, "Search") ~= nil):toBe(true)
				local choices = find(sheet, "Choices")
				Verify.expect(choices.Size.X.Scale):toBe(1)
				for _, id in { "a", "b" } do
					local row = find(choices, id)
					Verify.expect(row.Size.X.Scale):toBe(1)
					Verify.expect(row.Size.X.Offset):toBe(0)
				end
				query:set("Bet")
				Verify.expect((find(choices, "a"))):toBeNil()
				find(choices, "b").Activated:Fire()
				Verify.expect((selection:peek())):toBe("b")
				Verify.expect((opened:peek())):toBe(false)
				Verify.expect((find(world.root, "PickerSearch"))):toBeNil()
				Verify.expect(world.gui.SelectedObject):toBe(trigger)
				world.stop()
			end,
		})

		verifyHarness:case(
			"opens, picks and dismisses every picker style for each theme and input with focus restored",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::opens, picks and dismisses every picker style for each theme and input with focus restored",
				run = function()
					local packages: { any } = { false }
					for _, name in { "glossy_touch", "pixel_quest", "fantasy_ornate" } do
						local package, report = (require :: any)("../examples/themes/" .. name).build(themes)
						Verify.expect(report.ok):toBe(true)
						table.insert(packages, package)
					end
					local inputs = {
						{ input = "Touch", width = 390 },
						{ input = "KeyboardAndMouse", width = 1280 },
						{ input = "Gamepad", width = 1920 },
					}
					local styles = { "automatic", "menu", "segmented", "inline", "radioGroup", "navigationLink" }
					for _, package in packages do
						for _, device in inputs do
							for _, style in styles do
								local selected, changes = Compose.cell("easy"), 0
								local world = setup(function(UI)
									return UI.Picker "Choice" {
										style = style,
										label = "Difficulty",
										selected = selected,
										options = THREE,
										onChange = function()
											changes += 1
										end,
									}
								end, if package then { theme = package } else nil)
								world.input.PreferredInput = (world.engine.types.Enum.PreferredInput :: any)[device.input]
								local picker = find(world.root, "Choice")
								picker.AbsoluteSize = V2(world, device.width, 44)
								local trigger = find(picker, "Trigger")
									or (if style == "navigationLink" then picker else nil)
								if trigger then
									world.gui.SelectedObject = trigger
									trigger.Activated:Fire()
									local surface = find(world.root, "MenuPanel") or find(world.root, "PickerSearch")
									Verify.expect(surface ~= nil):toBe(true)
									Verify.expect((within(world.gui.SelectedObject, surface))):toBe(true)
									action(world.root, "ModalBack").Pressed:Fire()
									Verify.expect((find(world.root, "Modal"))):toBeNil()
									Verify.expect(world.gui.SelectedObject):toBe(trigger)
									Verify.expect((selected:peek())):toBe("easy")
									trigger.Activated:Fire()
									surface = find(world.root, "MenuPanel") or find(world.root, "PickerSearch")
									find(surface, "normal").Activated:Fire()
									Verify.expect((find(world.root, "Modal"))):toBeNil()
									Verify.expect(world.gui.SelectedObject):toBe(trigger)
								else
									find(picker, "normal").Activated:Fire()
								end
								Verify.expect((selected:peek())):toBe("normal")
								Verify.expect(changes):toBe(1)
								world.stop()
							end
						end
					end
				end,
			}
		)

		verifyHarness:case("keeps a focused menu row while its live description appears, changes and disappears", {
			id = "native_parity_weaker_menus::native parity weaker menus::keeps a focused menu row while its live description appears, changes and disappears",
			run = function()
				local options = Compose.cell(
					{ { value = "a", label = "Alpine" }, { value = "b", label = "Beach" } } :: { PickerOption }
				)
				local world = setup(function(UI: FacetControls)
					return UI.Picker "Route" {
						style = "menu" :: "menu",
						selected = Compose.cell("a"),
						isPresented = Compose.cell(false),
						options = options,
					}
				end)
				local trigger = find(world.root, "Trigger")
				world.gui.SelectedObject = trigger
				trigger.Activated:Fire()
				local panel = find(world.root, "MenuPanel")
				local row = find(panel, "a")
				Verify.expect(world.gui.SelectedObject):toBe(row)
				Verify.expect(find(row, "Description").Visible):toBe(false)
				for _, description in { "Added", "", "Returned" } do
					options:set({
						{ value = "a", label = "Alpine", description = description } :: PickerOption,
						{ value = "b", label = "Beach" } :: PickerOption,
					})
					Verify.expect((find(panel, "a"))):toBe(row)
					Verify.expect(world.gui.SelectedObject):toBe(row)
					Verify.expect(find(row, "Description").Visible):toBe(description ~= "")
					if description ~= "" then
						Verify.expect(find(row, "Description").Text):toBe(description)
					end
				end
				options:set({ { value = "a", label = "Alpine" }, { value = "b", label = "Beach" } })
				Verify.expect((find(panel, "a"))):toBe(row)
				Verify.expect(world.gui.SelectedObject):toBe(row)
				Verify.expect(find(row, "Description").Visible):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case(
			"refuses to choose filtered or disabled menu rows and keeps multiple selection after disposal",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::refuses to choose filtered or disabled menu rows and keeps multiple selection after disposal",
				run = function()
					local selected, query, changes =
						Compose.cell({ a = true } :: { [string]: boolean }), Compose.cell(""), 0
					local options = Compose.cell({
						{ value = "a", label = "Alpine" },
						{ value = "b", label = "Beach", enabled = false },
					})
					local world = setup(function(UI: FacetControls)
						return UI.Picker "Route" {
							style = "menu" :: "menu",
							multiple = true :: true,
							selected = selected,
							query = query,
							options = options,
							isPresented = Compose.cell(true),
							onChange = function()
								changes += 1
							end,
						}
					end)
					local panel = find(world.root, "MenuPanel")
					local disabled = find(panel, "b")
					Verify.expect(disabled.Interactable):toBe(false)
					disabled.Activated:Fire()
					Verify.expect(selected:peek().b):toBeNil()
					Verify.expect(changes):toBe(0)
					options:set({ { value = "a", label = "Alpine" }, { value = "b", label = "Beach" } })
					local stale = find(panel, "b")
					query:set("alp")
					Verify.expect((find(panel, "b"))):toBeNil()
					stale.Activated:Fire()
					Verify.expect(selected:peek().b):toBeNil()
					Verify.expect(changes):toBe(0)
					query:set("")
					local row = find(panel, "b")
					row.Activated:Fire()
					Verify.expect(selected:peek().a):toBe(true)
					Verify.expect(selected:peek().b):toBe(true)
					Verify.expect(changes):toBe(1)
					world.stop()
					row.Activated:Fire()
					Verify.expect(selected:peek().a):toBe(true)
					Verify.expect(selected:peek().b):toBe(true)
					Verify.expect(changes):toBe(1)
				end,
			}
		)

		verifyHarness:case(
			"keeps checked and radio menu items open by default with their marks while actions dismiss",
			{
				id = "native_parity_weaker_menus::native parity weaker menus::keeps checked and radio menu items open by default with their marks while actions dismiss",
				run = function()
					local presented, checked, selected, calls =
						Compose.cell(true), Compose.cell(false), Compose.cell("a"), 0
					local world = setup(function(UI: FacetControls)
						return UI.Menu "Filters" {
							isPresented = presented,
							items = {
								{ id = "check", label = "Favorites", checked = checked } :: FixtureNavigationTypes.MenuItem<any>,
								{ id = "a", label = "All", selected = selected, value = "a" } :: FixtureNavigationTypes.MenuItem<any>,
								{ id = "b", label = "Friends", selected = selected, value = "b" } :: FixtureNavigationTypes.MenuItem<any>,
								{
									id = "done",
									label = "Done",
									onSelect = function()
										calls += 1
									end,
								} :: FixtureNavigationTypes.MenuItem<any>,
							},
						}
					end)
					local function mark(id: string): boolean
						return find(find(world.root, id), "TrailingIcon").Visible
					end
					Verify.expect((mark("check"))):toBe(false)
					Verify.expect((mark("a"))):toBe(true)
					Verify.expect((mark("b"))):toBe(false)
					Verify.expect((find(find(world.root, "done"), "TrailingIcon"))):toBeNil()
					find(world.root, "check").Activated:Fire()
					Verify.expect((checked:peek())):toBe(true)
					Verify.expect((presented:peek())):toBe(true)
					Verify.expect((mark("check"))):toBe(true)
					find(world.root, "b").Activated:Fire()
					Verify.expect((selected:peek())):toBe("b")
					Verify.expect((presented:peek())):toBe(true)
					Verify.expect((mark("a"))):toBe(false)
					Verify.expect((mark("b"))):toBe(true)
					find(world.root, "check").Activated:Fire()
					Verify.expect((checked:peek())):toBe(false)
					Verify.expect((mark("check"))):toBe(false)
					find(world.root, "done").Activated:Fire()
					Verify.expect(calls):toBe(1)
					Verify.expect((presented:peek())):toBe(false)
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					world.stop()
				end,
			}
		)
	end)
end
