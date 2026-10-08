--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	local FixtureEngineTypes = require("../src/ui/engine_types")
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureRadialTypes = require("../src/ui/radial_types")
	local NavigationFixtures = require("../src/ui/navigation_types")
	local FixtureThemeTypes = require("../src/ui/theme_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T
	local Navigation = require("../src/ui/navigation_types")
	local SharedTypes = require("../src/ui/control_types")
	local Shared = require("../src/ui/types")

	local cells = require("./lib/cells")
	local materialize = require("./lib/materialize")
	local fadeKit = require("./lib/fade")
	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local controls = require("../src/ui")
	local engines = require("./lib/native_engine")
	local LIFT = 16 * math.sqrt(2) / 2
	local function corner(panel: GuiObject): (number, number)
		return panel.Position.X.Offset - panel.AnchorPoint.X * panel.AbsoluteSize.X,
			panel.Position.Y.Offset - panel.AnchorPoint.Y * panel.AbsoluteSize.Y
	end
	local function near(actual: number, expected: number): boolean
		return math.abs(actual - expected) <= 1
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
	local function setup(
		build: (SharedTypes.Controls, Shared.Host, any, any, ComposeRuntime) -> unknown,
		options: {
			theme: any?,
			pressHaptic: ((any) -> HapticEffect)?,
			motionLevel: Shared.Value<Shared.MotionLevel>?,
		}?
	)
		local engine = engines.new()
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local UI = controls(Compose, runtime, {
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			theme = options and options.theme,
			pressHaptic = options and options.pressHaptic and options.pressHaptic(engine),
			motionLevel = options and options.motionLevel,
		})
		local target = engine.new("Folder")
		local stop, screen: any = runtime.mount(function()
			return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
				build(UI, (runtime.constructors :: unknown) :: Shared.Host, engine, gui, runtime),
			})
		end, target)
		return {
			engine = engine,
			gui = gui,
			input = input,
			runtime = runtime,
			screen = screen,
			settle = function()
				for _ = 1, 60 do
					engine.heartbeat:Fire(1 / 60)
				end
			end,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	verifyHarness:suite("native navigation controls", function()
		verifyHarness:case("stacks destination labels below icons in an equal phone bar", {
			id = "native_navigation::native navigation controls::stacks destination labels below icons in an equal phone bar",
			run = function()
				local choice = Compose.cell("belowIcon" :: "belowIcon" | "besideIcon")
				local selection = Compose.cell("games")
				local textSize = Compose.cell(32)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local function page(): Instance
						return Host.Frame({})
					end
					local tabs: { Navigation.Tab } = {
						{ id = "games", label = "Games", icon = "view.list", badge = 3, content = page },
						{ id = "profile", label = "Profile", icon = "person", content = page },
						{ id = "settings", label = "Settings", icon = "settings", content = page },
					}
					local props: Navigation.TabViewSpec = {
						selection = selection,
						labelPlacement = choice,
						textSize = textSize,
						placement = "bottomBar" :: "bottomBar",
						tabs = tabs,
					}
					return UI.TabView(props)
				end)
				local bar = find(world.screen, "Tabs")
				bar.AbsoluteSize = world.engine.types.Vector2.new(389, 80)
				for _, id in { "games", "profile", "settings" } do
					local button = bar:FindFirstChild(id)
					Verify.expect(button.Size.X.Scale):toBe(world.engine.types.UDim.new(1 / 3, 0).Scale)
					Verify.expect(find(button, "Title").Size.Y.Offset >= 32):toBe(true)
					Verify.expect(button.Size.Y.Offset >= 72):toBe(true)
					Verify.expect(find(button, "Content"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
						:toBe(world.engine.types.Enum.FillDirection.Vertical)
					Verify.expect(find(button, "Title").Size.X.Scale):toBe(1)
				end
				textSize:set(16)
				Verify.expect(find(bar:FindFirstChild("games"), "Title").Size.Y.Offset >= 16):toBe(true)
				Verify.expect(bar:FindFirstChild("games").Size.Y.Offset < 72):toBe(true)
				bar:FindFirstChild("profile").Activated:Fire()
				Verify.expect(selection:peek()):toBe("profile")
				choice:set("besideIcon")
				Verify.expect(
					find(bar:FindFirstChild("games"), "Content"):FindFirstChildWhichIsA("UIListLayout").FillDirection
				)
					:toBe(world.engine.types.Enum.FillDirection.Horizontal)
				world.stop()
			end,
		})
		verifyHarness:case("keeps five lower phone commands and Close inside the safe modal room", {
			id = "native_navigation::native navigation controls::keeps five lower phone commands and Close inside the safe modal room",
			run = function()
				local opened = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					local items = {}
					for _, id in { "swap", "pass", "zoom", "help", "resign" } do
						table.insert(items, { id = id, label = id, onSelect = function() end })
					end
					return UI.Menu({ isPresented = opened, items = items })
				end)
				world.screen.AbsoluteSize = world.engine.types.Vector2.new(389, 704)
				world.input.TouchEnabled = true
				world.input.MouseEnabled = false
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
				local panel = find(world.screen, "MenuPanel")
				panel.Parent.AbsoluteSize = world.engine.types.Vector2.new(389, 704)
				find(panel, "MenuRows").AbsoluteSize = world.engine.types.Vector2.new(349, 320)
				panel.AbsoluteSize = world.engine.types.Vector2.new(365, panel.Size.Y.Offset)
				Verify.expect(panel.Size.Y.Offset):toBeLessThanOrEqual(704 - 24)
				Verify.expect(panel.Size.X.Scale):toBe(1)
				Verify.expect(find(panel, "CloseCommand") ~= nil):toBe(true)
				find(panel, "resign").Activated:Fire()
				Verify.expect(opened:peek()):toBe(false)
				world.stop()
			end,
		})
		verifyHarness:case("limits the default menu Close to sheets and retains explicit overrides", {
			id = "native_navigation::native navigation controls::limits the default menu Close to sheets and retains explicit overrides",
			run = function()
				local opened = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.Menu({
						isPresented = opened,
						items = { { id = "action", label = "Action", onSelect = function() end } },
					})
				end)
				local command = find(world.screen, "CloseCommand")
				Verify.expect(command.Visible):toBe(false)
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
				Verify.expect(command.Visible):toBe(true)
				Verify.expect(command.Text):toBe("")
				Verify.expect(command:GetAttribute("label")):toBe("Close")
				command.Activated:Fire()
				Verify.expect(opened:peek()):toBe(false)
				world.stop()
				for _, override in { true, false } do
					opened:set(true)
					local explicit = setup(function(UI: FacetControls)
						return UI.Menu({
							isPresented = opened,
							closeButton = override,
							items = { { id = "action", label = "Action", onSelect = function() end } },
						})
					end)
					local close = find(explicit.screen, "CloseCommand")
					Verify.expect(close ~= nil and close.Visible):toBe(override)
					explicit.input.PreferredInput = explicit.engine.types.Enum.PreferredInput.Touch
					close = find(explicit.screen, "CloseCommand")
					Verify.expect(close ~= nil and close.Visible):toBe(override)
					explicit.stop()
				end
				opened:set(true)
				world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet({
						isPresented = opened,
						detent = Compose.cell("medium" :: Navigation.SheetDetent),
						content = function(): Instance
							return Host.Frame({})
						end,
					})
				end)
				find(world.screen, "Close").Activated:Fire()
				Verify.expect(opened:peek()):toBe(false)
				world.stop()
			end,
		})
		verifyHarness:case("accepts a fresh route object after departure and during reversal", {
			id = "native_navigation::native navigation controls::accepts a fresh route object after departure and during reversal",
			run = function()
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<number> })
				local world = setup(function(UI)
					return UI.NavigationStack {
						path = path,
						root = {
							content = function()
								return UI.Button { label = "Root" }
							end,
						} :: NavigationFixtures.NavigationDestination<number>,
						destinations = {
							match = {
								content = function()
									return UI.Button "Counter" { label = "Counter" }
								end,
							} :: NavigationFixtures.NavigationDestination<number>,
						},
					}
				end)
				for _, completed in { true, false } do
					path:set({ { id = "match", value = 1 } })
					world.settle()
					path:set({})
					if completed then
						world.settle()
					else
						world.engine.heartbeat:Fire(1 / 60)
					end
					path:set({ { id = "match", value = 1 } })
					world.settle()
					local panels = 0
					for _, node in world.screen:GetDescendants() do
						if node.Name == "match" then
							panels += 1
							Verify.expect(node.Interactable):toBe(true)
							Verify.expect(node.Visible):toBe(true)
						end
					end
					Verify.expect(panels):toBe(1)
				end
				world.stop()
			end,
		})
		verifyHarness:case("prepares CollapsibleView chrome before content paints without travel", {
			id = "native_navigation::native navigation controls::prepares CollapsibleView chrome before content paints without travel",
			run = function()
				for _, level in { "normal", "limited", "none" } do
					local expanded = Compose.cell(false)
					local world = setup(function(UI: FacetControls, _, engine)
						return UI.CollapsibleView "Summary" {
							expanded = expanded,
							label = "Summary",
							content = function(): Instance
								return UI.Text "Copy" {
									text = "The copy must keep its final content width.",
									Size = engine.types.UDim2.new(1, 0, 0, 0),
									AutomaticSize = engine.types.Enum.AutomaticSize.Y,
									TextWrapped = true,
								}
							end,
						}
					end, { motionLevel = level :: "normal" | "limited" | "none" })
					world.screen.AbsoluteSize = world.engine.types.Vector2.new(960, 720)
					find(world.screen, "Summary").AbsoluteSize = world.engine.types.Vector2.new(240, 44)
					expanded:set(true)
					local panel, fade = find(world.screen, "Expanded"), find(world.screen, "ExpandedFade")
					local content = find(panel, "ContentBox")
					local V2 = world.engine.types.Vector2.new
					panel.AbsoluteSize = V2(360, 200)
					content.AbsoluteSize = V2(360, 200)
					Verify.expect(fadeKit.of(panel)):toBe(1)
					world.engine.heartbeat:Fire(1 / 60)
					content.AbsoluteSize = V2(328, 168)
					find(panel, "Copy").AbsoluteSize = V2(296, 48)
					world.engine.heartbeat:Fire(1 / 60)
					Verify.expect(fadeKit.of(panel)):toBe(1)
					for _ = 1, 6 do
						world.engine.heartbeat:Fire(1 / 60)
						Verify.expect(panel.Size.X.Offset):toBe(360)
						Verify.expect(panel.Size.Y.Offset):toBe(44)
					end
					world.settle()
					Verify.expect(fadeKit.of(panel)):toBe(0)
					Verify.expect(fade.Size.X.Offset):toBe(328)
					expanded:set(false)
					world.settle()
					Verify.expect(find(world.screen, "Expanded")):toBe(nil)
					world.stop()
				end
			end,
		})
		verifyHarness:case("selects enabled picker values once and honors changing veto", {
			id = "native_navigation::native navigation controls::selects enabled picker values once and honors changing veto",
			run = function()
				local selected, changes = Compose.cell("one"), 0
				local world = setup(function(UI: FacetControls)
					return UI.Picker({
						selected = selected,
						style = "segmented" :: "segmented",
						options = {
							{ value = "one", label = "One" } :: Navigation.PickerOption<string>,
							{ value = "two", label = "Two" } :: Navigation.PickerOption<string>,
							{ value = "three", label = "Three", enabled = false } :: Navigation.PickerOption<string>,
						},
						onChanging = function(value)
							return value ~= "one"
						end,
						onChange = function()
							changes += 1
						end,
					})
				end)
				find(world.screen, "three").Activated:Fire()
				Verify.expect((selected:peek())):toBe("one")
				find(world.screen, "two").Activated:Fire()
				find(world.screen, "two").Activated:Fire()
				find(world.screen, "one").Activated:Fire()
				Verify.expect((selected:peek())):toBe("two")
				Verify.expect(changes):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("shows a labelled segmented picker beside its label and a labelled list above it", {
			id = "native_navigation::native navigation controls::shows a labelled segmented picker beside its label and a labelled list above it",
			run = function()
				local selected = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Picker "Segments" {
							label = "Mode",
							LayoutOrder = 3,
							selected = selected,
							style = "segmented" :: "segmented",
							options = {
								{ value = "one", label = "One", icon = "edit" } :: Navigation.PickerOption<string>,
								{ value = "two", label = "Two", icon = "edit" } :: Navigation.PickerOption<string>,
							},
						} :: unknown,
						UI.Picker "List" {
							label = "Group",
							selected = selected,
							style = "inline" :: "inline",
							options = {
								{ value = "one", label = "One", icon = "edit" } :: Navigation.PickerOption<string>,
								{ value = "two", label = "Two", icon = "edit" } :: Navigation.PickerOption<string>,
							},
						},
					})
				end)
				local segments = find(world.screen, "Segments")
				Verify.expect(segments.LayoutOrder):toBe(3)
				Verify.expect(segments:FindFirstChild("Label").Text):toBe("Mode")
				local options = segments:FindFirstChild("Options")
				Verify.expect((options:HasTag("facet-segmented"))):toBe(true)
				Verify.expect(segments:FindFirstChild("Label"):FindFirstChildWhichIsA("UIFlexItem").FlexMode)
					:toBe(world.engine.types.Enum.UIFlexMode.Grow)
				Verify.expect(segments:FindFirstChildWhichIsA("UIListLayout").Wraps):toBe(true)
				Verify.expect(options.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.X)
				Verify.expect(options.Size.Y.Offset):toBe(50)
				Verify.expect(find(options, "one").Size.Y.Offset + 6):toBe(options.Size.Y.Offset)
				Verify.expect(segments:FindFirstChildWhichIsA("UIListLayout").FillDirection)
					:toBe(world.engine.types.Enum.FillDirection.Horizontal)
				local list = find(world.screen, "List")
				Verify.expect(list:FindFirstChild("Label").Text):toBe("Group")
				Verify.expect(list:FindFirstChildWhichIsA("UIListLayout").FillDirection)
					:toBe(world.engine.types.Enum.FillDirection.Vertical)
				local Horizontal = world.engine.types.Enum.HorizontalAlignment
				local function alignment(button)
					return button:FindFirstChild("Content"):FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment
				end
				Verify.expect((alignment(find(segments, "one")))):toBe(Horizontal.Center)
				Verify.expect((alignment(find(list, "one")))):toBe(Horizontal.Left)
				find(segments, "two").Activated:Fire()
				Verify.expect((selected:peek())):toBe("two")
				world.stop()
			end,
		})

		verifyHarness:case("mounts menus in the native layer, traverses submenus and closes after action", {
			id = "native_navigation::native navigation controls::mounts menus in the native layer, traverses submenus and closes after action",
			run = function()
				local opened, count = Compose.cell(false), 0
				local world = setup(function(UI: FacetControls)
					return UI.Menu({
						isPresented = opened,
						items = {
							{
								id = "Nested",
								label = "Nested",
								children = {
									{
										id = "Run",
										label = "Run",
										onSelect = function()
											count += 1
										end,
									},
								},
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				opened:set(true)
				local panel = find(world.screen, "MenuPanel")
				Verify.expect(panel.Parent.Parent):toBe(world.screen)
				find(world.screen, "Nested").Activated:Fire()
				find(world.screen, "Run").Activated:Fire()
				Verify.expect(count):toBe(1)
				Verify.expect((opened:peek())):toBe(false)
				world.settle()
				Verify.expect((find(world.screen, "MenuPanel"))):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("traps all modal selection directions and restores surviving focus on Back", {
			id = "native_navigation::native navigation controls::traps all modal selection directions and restores surviving focus on Back",
			run = function()
				local presented = Compose.cell(false)
				local cancelled = 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost, _, gui)
					local button = UI.Button "Original" { label = "Original" }
					gui.SelectedObject = button
					return Host.Frame({
						button :: unknown,
						UI.Alert({
							isPresented = presented,
							title = "Confirm",
							actions = {
								{ id = "Disabled", label = "No", enabled = false } :: FixtureNavigationTypes.AlertAction<any>,
								{
									id = "Cancel",
									label = "Cancel",
									role = "cancel" :: "cancel",
									onActivate = function()
										cancelled += 1
									end,
								} :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "Accept", label = "Accept" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				presented:set(true)
				local panel = find(world.screen, "AlertPanel")
				for _, direction in { "Up", "Down", "Left", "Right" } :: { "Down" | "Left" | "Right" | "Up" } do
					Verify.expect(panel["SelectionBehavior" .. direction])
						:toBe(world.engine.types.Enum.SelectionBehavior.Stop)
				end
				Verify.expect(world.gui.SelectedObject.Name):toBe("Cancel")
				local back = find(world.screen, "ModalBack")
				Verify.expect(back.Parent.Parent):toBe(world.screen)
				back.Pressed:Fire()
				Verify.expect((presented:peek())):toBe(false)
				Verify.expect(cancelled):toBe(1)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Original")
				world.settle()
				Verify.expect((back:isDestroyed())):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("captures alert payload and closes before invoking its action", {
			id = "native_navigation::native navigation controls::captures alert payload and closes before invoking its action",
			run = function()
				local item, result = Compose.cell({ id = "payload" } :: { id: string }?), nil
				local world = setup(function(UI: FacetControls)
					return UI.Alert({
						item = item,
						title = function(payload)
							return payload.id
						end,
						actions = {
							{
								id = "Accept",
								label = "Accept",
								onActivate = function(payload)
									result = { payload.id, item:peek() }
								end,
							} :: FixtureNavigationTypes.AlertAction<any>,
						},
					})
				end)
				find(world.screen, "Accept").Activated:Fire()
				Verify.expect((item:peek())):toBe(nil)
				Verify.expect(result[1]):toBe("payload")
				Verify.expect(result[2]):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("owns disclosure content only while expanded", {
			id = "native_navigation::native navigation controls::owns disclosure content only while expanded",
			run = function()
				for _, appearance in { "plain", "contained", "divided" } :: { "contained" | "divided" | "plain" } do
					local expanded, built, disposed = Compose.cell(false), 0, 0
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.DisclosureGroup({
							expanded = expanded,
							label = "Details",
							appearance = appearance :: "contained" | "divided" | "plain",
							content = function(): Instance
								built += 1
								Compose.cleanup(function()
									disposed += 1
								end)
								return Host.Frame "Details" { LayoutOrder = -10 }
							end,
						})
					end)
					local header = find(world.screen, "Header")
					Verify.expect(built):toBe(0)
					local function checkOrder()
						local content = find(world.screen, "Details")
						local wrapped = if appearance == "divided" then content.Parent else content
						local body = fadeKit.layer(wrapped).Parent
						Verify.expect(body.Name):toBe("Reveal")
						Verify.expect(fadeKit.layer(wrapped).Name):toBe("RevealFade")
						Verify.expect(body.Parent):toBe(header.Parent)
						Verify.expect(header.LayoutOrder < body.LayoutOrder):toBe(true)
						Verify.expect(header.Parent:FindFirstChildWhichIsA("UIListLayout").SortOrder)
							:toBe(world.engine.types.Enum.SortOrder.LayoutOrder)
						if appearance == "divided" then
							Verify.expect(find(wrapped, "Divider").LayoutOrder < content.LayoutOrder):toBe(true)
						end
						return content
					end
					local caret = find(header, "LeadingIcon")
					local closedIcon = caret.Image
					expanded:set(true)
					Verify.expect(caret.Image ~= closedIcon):toBe(true)
					local old = checkOrder()
					expanded:set(false)
					Verify.expect(caret.Image):toBe(closedIcon)
					Verify.expect((old:isDestroyed())):toBe(true)
					Verify.expect(disposed):toBe(1)
					expanded:set(true)
					Verify.expect(checkOrder() ~= old):toBe(true)
					Verify.expect((find(world.screen, "Header"))):toBe(header)
					Verify.expect(built):toBe(2)
					world.stop()
					Verify.expect(disposed):toBe(2)
				end
			end,
		})

		verifyHarness:case("retains visited tab state across selection and declaration reorders", {
			id = "native_navigation::native navigation controls::retains visited tab state across selection and declaration reorders",
			run = function()
				local selected, built, disposed = Compose.cell("one"), 0, 0
				local tabs
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local function content()
						built += 1
						Compose.cleanup(function()
							disposed += 1
						end)
						return Host.Frame "ContentState" {}
					end
					tabs = Compose.cell({
						{ id = "one", label = "One", content = content } :: FixtureNavigationTypes.Tab,
						{ id = "two", label = "Two", content = content } :: FixtureNavigationTypes.Tab,
					})
					return UI.TabView({ selection = selected, tabs = tabs })
				end)
				selected:set("two")
				selected:set("one")
				local old = tabs:peek()
				tabs:set({ old[2], old[1] })
				Verify.expect(built):toBe(2)
				Verify.expect(disposed):toBe(0)
				Verify.expect((selected:peek())):toBe("one")
				world.stop()
				Verify.expect(disposed):toBe(2)
			end,
		})

		verifyHarness:case("retains covered navigation destinations and disposes popped pages", {
			id = "native_navigation::native navigation controls::retains covered navigation destinations and disposes popped pages",
			run = function()
				local path, built, disposed = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> }), 0, 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local function content(entry: any): Instance
						built += 1
						Compose.cleanup(function()
							disposed += 1
						end)
						return Host.Frame({ Name = if entry then "Detail" else "Root" })
					end
					return UI.NavigationStack({
						path = path,
						root = { title = "Root", content = content } :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							detail = { title = "Detail", content = content } :: NavigationFixtures.NavigationDestination<any>,
						},
					})
				end)
				path:set({ { id = "detail" } })
				Verify.expect(built):toBe(2)
				Verify.expect(disposed):toBe(0)
				find(world.screen, "Back").Activated:Fire()
				Verify.expect(#path:peek()):toBe(0)
				Verify.expect(disposed):toBe(1)
				world.stop()
				Verify.expect(disposed):toBe(2)
			end,
		})

		verifyHarness:case("uses native page layout for model navigation and engine swipes", {
			id = "native_navigation::native navigation controls::uses native page layout for model navigation and engine swipes",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.PageView({
						selection = selection,
						pages = {
							{ id = "one", title = "One", content = Host.Frame({}) } :: FixtureNavigationTypes.Tab,
							{ id = "two", title = "Two", content = Host.Frame({}) } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				find(world.screen, "Next").Activated:Fire()
				Verify.expect((selection:peek())):toBe("two")
				local layout = find(world.screen, "PagesLayout")
				Verify.expect(layout.CurrentPage.Name):toBe("two")
				layout:JumpTo(find(find(world.screen, "Pages"), "one"))
				Verify.expect((selection:peek())):toBe("one")
				world.stop()
			end,
		})

		verifyHarness:case("hugs its tallest page and centres the footer under it when its height is automatic", {
			id = "native_navigation::native navigation controls::hugs its tallest page and centres the footer under it when its height is automatic",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					return UI.PageView({
						Size = engine.types.UDim2.new(1, 0, 0, 0),
						AutomaticSize = engine.types.Enum.AutomaticSize.Y,
						selection = selection,
						pages = {
							{ id = "one", title = "One", content = Host.Frame "BodyOne" {} } :: FixtureNavigationTypes.Tab,
							{ id = "two", title = "Two", content = Host.Frame "BodyTwo" {} } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local V = world.engine.types.Vector2
				find(world.screen, "BodyOne").AbsoluteSize = V.new(300, 180)
				find(world.screen, "BodyTwo").AbsoluteSize = V.new(300, 212.5)
				local pages, footer = find(world.screen, "Pages"), find(world.screen, "Footer")
				Verify.expect(pages.Size):toBe(world.engine.types.UDim2.new(1, 0, 0, 213))
				Verify.expect(footer.Position):toBe(world.engine.types.UDim2.fromOffset(0, 213))
				Verify.expect(footer:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment)
					:toBe(world.engine.types.Enum.HorizontalAlignment.Center)
				world.stop()
			end,
		})

		verifyHarness:case("eases between pages with Cubic Out, and a fast swipe with Quint Out, never overshooting", {
			id = "native_navigation::native navigation controls::eases between pages with Cubic Out, and a fast swipe with Quint Out, never overshooting",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.PageView({
						selection = selection,
						pages = {
							{ id = "one", title = "One", content = Host.Frame({}) } :: FixtureNavigationTypes.Tab,
							{ id = "two", title = "Two", content = Host.Frame({}) } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local Enum = world.engine.types.Enum
				local layout = find(world.screen, "PagesLayout")
				Verify.expect(layout.EasingStyle):toBe(Enum.EasingStyle.Cubic)
				Verify.expect(layout.EasingDirection):toBe(Enum.EasingDirection.Out)
				local pages = find(world.screen, "Pages")
				local function swipe(distance: number)
					local V3 = world.engine.types.Vector3
					pages.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch, Position = V3.new(300, 100, 0) })
					pages.InputEnded:Fire({
						UserInputType = Enum.UserInputType.Touch,
						Position = V3.new(300 - distance, 100, 0),
					})
				end
				swipe(1)
				Verify.expect(layout.EasingStyle):toBe(Enum.EasingStyle.Cubic)
				swipe(300)
				Verify.expect(layout.EasingStyle):toBe(Enum.EasingStyle.Quint)
				Verify.expect(layout.EasingStyle ~= Enum.EasingStyle.Back):toBe(true)
				find(world.screen, "Next").Activated:Fire()
				Verify.expect(layout.EasingStyle):toBe(Enum.EasingStyle.Cubic)
				world.stop()
			end,
		})

		verifyHarness:case("snaps the showing page into place without motion when the pages frame resizes", {
			id = "native_navigation::native navigation controls::snaps the showing page into place without motion when the pages frame resizes",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.PageView({
						selection = Compose.cell("two"),
						pages = {
							{ id = "one", title = "One", content = Host.Frame({}) } :: FixtureNavigationTypes.Tab,
							{ id = "two", title = "Two", content = Host.Frame({}) } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local layout = find(world.screen, "PagesLayout")
				local writes = {}
				layout:GetPropertyChangedSignal("Animated"):Connect(function()
					table.insert(writes, tostring(layout.Animated))
				end)
				Verify.expect(layout.Animated):toBe(true)
				find(world.screen, "Pages").AbsoluteSize = world.engine.types.Vector2.new(640, 240)
				Verify.expect((table.concat(writes, ","))):toBe("false,true")
				Verify.expect(layout.CurrentPage.Name):toBe("two")
				world.stop()
			end,
		})

		verifyHarness:case("pages by direction from a control inside the showing page", {
			id = "native_navigation::native navigation controls::pages by direction from a control inside the showing page",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.PageView({
						selection = selection,
						pages = {
							{
								id = "one",
								title = "One",
								content = Host.Frame({ UI.Button "PlayOne" { label = "One" } }),
							} :: FixtureNavigationTypes.Tab,
							{
								id = "two",
								title = "Two",
								content = Host.Frame({ UI.Button "PlayTwo" { label = "Two" } }),
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local Enum = world.engine.types.Enum
				local play = find(world.screen, "PlayOne")
				world.gui.SelectedObject = play
				Verify.expect(play.NextSelectionRight):toBe(play)
				world.input.InputBegan:Fire({
					KeyCode = Enum.KeyCode.DPadRight,
					UserInputType = Enum.UserInputType.Gamepad1,
				})
				Verify.expect((selection:peek())):toBe("two")
				Verify.expect(world.gui.SelectedObject):toBe(find(world.screen, "PlayTwo"))
				world.input.InputBegan:Fire({ KeyCode = Enum.KeyCode.Left, UserInputType = Enum.UserInputType.Keyboard })
				Verify.expect((selection:peek())):toBe("one")
				world.gui.SelectedObject = find(world.screen, "Next")
				world.input.InputBegan:Fire({
					KeyCode = Enum.KeyCode.Right,
					UserInputType = Enum.UserInputType.Keyboard,
				})
				Verify.expect((selection:peek())):toBe("one")
				world.stop()
			end,
		})

		verifyHarness:case("validates combo custom commits and cancels editable text", {
			id = "native_navigation::native navigation controls::validates combo custom commits and cancels editable text",
			run = function()
				local value, text, changes = Compose.cell("a"), Compose.cell("Alpha"), 0
				local world = setup(function(UI: FacetControls)
					return UI.ComboBox({
						value = value,
						text = text,
						options = {
							{ id = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
							{ id = "b", label = "Beta" } :: Navigation.PickerOption<string>,
						},
						acceptCustom = function(candidate)
							return candidate == "Custom", "Rejected"
						end,
						onChange = function()
							changes += 1
						end,
					})
				end)
				local editor = find(world.screen, "Editor")
				editor.Focused:Fire()
				editor.Text = "Rejected"
				editor.FocusLost:Fire(true)
				Verify.expect((value:peek())):toBe("a")
				Verify.expect(find(world.screen, "Validation").Text):toBe("Rejected")
				editor.Focused:Fire()
				editor.Text = "Custom"
				editor.FocusLost:Fire(true)
				Verify.expect((value:peek())):toBe("Custom")
				Verify.expect(changes):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("hides an empty ComboBox popup and restores it when matches return", {
			id = "native_navigation::native navigation controls::hides an empty ComboBox popup and restores it when matches return",
			run = function()
				local text = Compose.cell("zzq")
				local world = setup(function(UI: FacetControls)
					return UI.ComboBox {
						value = Compose.cell("a"),
						text = text,
						options = { { value = "a", label = "Alpha" } },
						acceptCustom = function()
							return false
						end,
					}
				end)
				find(find(world.screen, "Suggestions"), "Trigger").Activated:Fire()
				Verify.expect(find(world.screen, "MenuPanel")):toBe(nil)
				text:set("Al")
				Verify.expect(find(world.screen, "MenuPanel") ~= nil):toBe(true)
				text:set("zzq")
				Verify.expect(find(world.screen, "MenuPanel")):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("keeps combo suggestions beside a single line and preserves native typing until Down", {
			id = "native_navigation::native navigation controls::keeps combo suggestions beside a single line and preserves native typing until Down",
			run = function()
				local value, text, changes, validations = Compose.cell("a"), Compose.cell("Alpha"), 0, 0
				local world = setup(function(UI: FacetControls, _, engine)
					return UI.ComboBox "SearchCombo" {
						Size = engine.types.UDim2.fromOffset(320, 44),
						value = value,
						text = text,
						commitOnFocusLost = true,
						options = {
							{ value = "locked", label = "Alabama", enabled = false } :: Navigation.PickerOption<string>,
							{ value = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
							{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
						},
						acceptCustom = function()
							validations += 1
							return true
						end,
						onChange = function()
							changes += 1
						end,
					}
				end)
				local root = find(world.screen, "SearchCombo")
				local row, editor, suggestions = find(root, "Row"), find(root, "Editor"), find(root, "Suggestions")
				local trigger = find(suggestions, "Trigger")
				Verify.expect(editor.Parent):toBe(row)
				Verify.expect(suggestions.Parent):toBe(row)
				Verify.expect(row.Size.Y.Offset):toBe(44)
				Verify.expect(editor.Size.X.Scale):toBe(1)
				Verify.expect(editor.Size.X.Offset):toBe(-60)
				Verify.expect(editor.Size.Y.Scale):toBe(1)
				Verify.expect(suggestions.Position.X.Scale):toBe(1)
				Verify.expect(suggestions.Position.X.Offset):toBe(-56)
				Verify.expect(suggestions.Position.Y.Offset):toBe(0)
				Verify.expect(suggestions.Size.Y.Scale):toBe(1)
				Verify.expect(trigger.Size.Y.Scale):toBe(1)
				Verify.expect(trigger.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				editor:CaptureFocus()
				world.gui.SelectedObject = editor
				editor.Text = "a"
				local overlay = find(world.screen, "SuggestionsOverlay")
				Verify.expect(overlay ~= nil):toBe(true)
				Verify.expect(overlay.Parent):toBe(world.screen)
				Verify.expect((find(overlay, "ModalBack"))):toBe(nil)
				Verify.expect((editor:IsFocused())):toBe(true)
				Verify.expect(editor.TextEditable):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(editor)
				editor.Text = "be"
				Verify.expect(find(overlay, "b") ~= nil):toBe(true)
				Verify.expect((find(overlay, "a"))):toBe(nil)
				Verify.expect((find(root, "Editor"))):toBe(editor)
				Verify.expect((editor:IsFocused())):toBe(true)
				find(world.screen, "ComboSuggestions").Pressed:Fire()
				Verify.expect((editor:IsFocused())):toBe(false)
				Verify.expect(world.gui.SelectedObject):toBe(find(overlay, "b"))
				Verify.expect(validations):toBe(0)
				Verify.expect(changes):toBe(0)
				find(overlay, "b").Activated:Fire()
				Verify.expect((value:peek())):toBe("b")
				Verify.expect((text:peek())):toBe("Beta")
				Verify.expect(changes):toBe(1)
				Verify.expect((find(world.screen, "SuggestionsOverlay"))):toBe(nil)
				Verify.expect(world.gui.SelectedObject):toBe(editor)
				editor:CaptureFocus()
				editor.Text = "al"
				find(world.screen, "ComboSuggestions").Pressed:Fire()
				Verify.expect(world.gui.SelectedObject.Name):toBe("a")
				find(world.screen, "ComboCancel").Pressed:Fire()
				Verify.expect((text:peek())):toBe("Beta")
				Verify.expect((value:peek())):toBe("b")
				Verify.expect((editor:IsFocused())):toBe(true)
				Verify.expect((find(world.screen, "SuggestionsOverlay"))):toBe(nil)
				Verify.expect(validations):toBe(0)
				Verify.expect(changes):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("closes combo suggestions outside the field and honors custom focus-loss policy", {
			id = "native_navigation::native navigation controls::closes combo suggestions outside the field and honors custom focus-loss policy",
			run = function()
				local value, text, enabled = Compose.cell("a"), Compose.cell("Alpha"), Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.ComboBox({
						value = value,
						text = text,
						enabled = enabled,
						options = { { value = "a", label = "Alpha" } :: Navigation.PickerOption<string> },
						acceptCustom = function()
							return true
						end,
					})
				end)
				local editor = find(world.screen, "Editor")
				editor:CaptureFocus()
				editor.Text = "Custom"
				editor:ReleaseFocus(false)
				Verify.expect((value:peek())):toBe("a")
				Verify.expect((text:peek())):toBe("Custom")
				world.input.InputBegan:Fire({
					UserInputType = world.engine.types.Enum.UserInputType.MouseButton1,
					Position = world.engine.types.Vector3.new(1000, 1000, 0),
				})
				Verify.expect((find(world.screen, "SuggestionsOverlay"))):toBe(nil)
				find(find(world.screen, "Suggestions"), "Trigger").Activated:Fire()
				Verify.expect(find(world.screen, "SuggestionsOverlay")):toBe(nil)
				text:set("Al")
				find(find(world.screen, "Suggestions"), "Trigger").Activated:Fire()
				Verify.expect(find(world.screen, "SuggestionsOverlay") ~= nil):toBe(true)
				enabled:set(false)
				Verify.expect((find(world.screen, "SuggestionsOverlay"))):toBe(nil)
				world.stop()

				local enabledCommit = Compose.cell(true)
				local committing = setup(function(UI: FacetControls)
					return UI.ComboBox({
						value = value,
						text = text,
						enabled = enabledCommit,
						commitOnFocusLost = true,
						options = { { value = "a", label = "Alpha" } :: Navigation.PickerOption<string> },
						acceptCustom = function(candidate)
							if candidate == "Disable" then
								enabledCommit:set(false)
							end
							return true
						end,
					})
				end)
				local committingEditor = find(committing.screen, "Editor")
				committingEditor:CaptureFocus()
				committingEditor.Text = "Custom"
				committingEditor:ReleaseFocus(false)
				Verify.expect((value:peek())):toBe("Custom")
				committingEditor:CaptureFocus()
				committingEditor.Text = "Disable"
				committingEditor:ReleaseFocus(true)
				Verify.expect((value:peek())):toBe("Custom")
				committing.stop()
			end,
		})

		verifyHarness:case(
			"reopens combo suggestions after selected-result alerts finish their exit and the editor refocuses",
			{
				id = "native_navigation::native navigation controls::reopens combo suggestions after selected-result alerts finish their exit and the editor refocuses",
				run = function()
					local value, text, presented = Compose.cell(""), Compose.cell(""), Compose.cell(false)
					local changes = 0
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.ComboBox "Search" {
								value = value,
								text = text,
								options = function(use: Use): { Navigation.PickerOption<string> }
									local query = string.lower(use(text))
									local options: { Navigation.PickerOption<string> } = {}
									for _, option in
										{
											{ value = "circuit", label = "Circuit" },
											{ value = "forest", label = "Forest" },
										}
									do
										if string.find(string.lower(option.label), query, 1, true) then
											table.insert(options, option)
										end
									end
									return options
								end,
								acceptCustom = function()
									return true
								end,
								onChange = function()
									changes += 1
									presented:set(true)
								end,
							} :: unknown,
							UI.Alert "Result" {
								isPresented = presented,
								title = "Selected game",
								transition = { seconds = 0.1 },
								actions = {
									{ id = "CloseResult", label = "Close", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
								},
							},
						})
					end)
					local editor = find(world.screen, "Editor")
					world.input.GetFocusedTextBox = function()
						return if editor:IsFocused() then editor else nil
					end
					for index, choice in { "Circuit", "Forest", "Circuit" } do
						editor:CaptureFocus()
						Verify.expect((editor:IsFocused())):toBe(true)
						editor.Text = ""
						Verify.expect((text:peek())):toBe("")
						for length = 1, #choice do
							editor.Text = string.sub(choice, 1, length)
						end
						Verify.expect((text:peek())):toBe(choice)
						Verify.expect((editor:IsFocused())):toBe(true)
						local menu = find(world.screen, "MenuPanel")
						Verify.expect(menu ~= nil):toBe(true)
						find(menu, string.lower(choice)).Activated:Fire()
						Verify.expect((value:peek())):toBe(string.lower(choice))
						Verify.expect(changes):toBe(index)
						Verify.expect((find(world.screen, "MenuPanel"))):toBe(nil)
						Verify.expect((presented:peek())):toBe(true)
						Verify.expect((editor:IsFocused())):toBe(false)
						find(world.screen, "CloseResult").Activated:Fire()
						Verify.expect((presented:peek())):toBe(false)
						world.engine.heartbeat:Fire(0.2)
						Verify.expect((find(world.screen, "AlertModal"))):toBe(nil)
						Verify.expect((find(world.screen, "Editor"))):toBe(editor)
					end
					world.stop()
				end,
			}
		)

		verifyHarness:case("snaps native sheet drags to declared detents and respects dismissal policy", {
			id = "native_navigation::native navigation controls::snaps native sheet drags to declared detents and respects dismissal policy",
			run = function()
				local opened, detent = Compose.cell(true), Compose.cell("large")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet({
						isPresented = opened,
						detent = detent,
						title = "Sheet",
						content = function(): Instance
							return Host.Frame "Body" {}
						end,
						interactiveDismissDisabled = true,
					})
				end)
				local drag = find(world.screen, "UIDragDetector")
				drag.DragStart:Fire(world.engine.types.Vector2.new(0, 0))
				drag.DragContinue:Fire(world.engine.types.Vector2.new(0, 400))
				drag.DragEnd:Fire()
				Verify.expect((detent:peek())):toBe("medium")
				find(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((opened:peek())):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("navigates radial branches and applies action completion", {
			id = "native_navigation::native navigation controls::navigates radial branches and applies action completion",
			run = function()
				local opened, count = Compose.cell(true), 0
				local world = setup(function(UI: FacetControls)
					return UI.RadialMenu({
						isPresented = opened,
						items = {
							{
								id = "Branch",
								label = "Branch",
								children = {
									{
										id = "Action",
										label = "Action",
										completion = "root" :: "root",
										onSelect = function()
											count += 1
										end,
									},
								},
							} :: FixtureRadialTypes.RadialItem<any>,
							{ id = "Unavailable", label = "Unavailable", enabled = false } :: FixtureRadialTypes.RadialItem<any>,
						},
					})
				end)
				find(world.screen, "Branch").Activated:Fire()
				find(world.screen, "Action").Activated:Fire()
				Verify.expect(count):toBe(1)
				Verify.expect((opened:peek())):toBe(true)
				Verify.expect(find(world.screen, "Branch") ~= nil):toBe(true)
				world.stop()
			end,
		})
		verifyHarness:case("blocks background shortcuts until the top modal leaves", {
			id = "native_navigation::native navigation controls::blocks background shortcuts until the top modal leaves",
			run = function()
				local presented, count = Compose.cell(false), 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button "Background" {
							label = "Background",
							shortcut = { keyCode = "K" },
							onActivate = function()
								count += 1
							end,
						} :: unknown,
						UI.Alert({ isPresented = presented, title = "Modal" }),
					})
				end)
				local shortcut = find(world.screen, "Shortcut")
				shortcut.Pressed:Fire()
				Verify.expect(count):toBe(1)
				presented:set(true)
				Verify.expect(shortcut.Parent.Enabled):toBe(false)
				shortcut.Pressed:Fire()
				Verify.expect(count):toBe(1)
				presented:set(false)
				Verify.expect(shortcut.Parent.Enabled):toBe(true)
				shortcut.Pressed:Fire()
				Verify.expect(count):toBe(2)
				world.stop()
			end,
		})

		verifyHarness:case("lets Back dismiss a disabled cancel action without invoking it", {
			id = "native_navigation::native navigation controls::lets Back dismiss a disabled cancel action without invoking it",
			run = function()
				local presented, count = Compose.cell(true), 0
				local world = setup(function(UI: FacetControls)
					return UI.Alert({
						isPresented = presented,
						actions = {
							{
								id = "Cancel",
								label = "Cancel",
								role = "cancel" :: "cancel",
								enabled = false,
								onActivate = function()
									count += 1
								end,
							} :: FixtureNavigationTypes.AlertAction<any>,
							{ id = "Continue", label = "Continue", shortcut = "defaultAction" } :: FixtureNavigationTypes.AlertAction<any>,
						},
					})
				end)
				find(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((presented:peek())):toBe(false)
				Verify.expect(count):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("runs a cancelAction action on Back and refuses a non-table transition", {
			id = "native_navigation::native navigation controls::runs a cancelAction action on Back and refuses a non-table transition",
			run = function()
				local presented, stayed = Compose.cell(true), 0
				local world = setup(function(UI: FacetControls)
					return UI.Alert({
						isPresented = presented,
						title = "Leave?",
						actions = {
							{
								id = "Stay",
								label = "Stay",
								shortcut = "cancelAction",
								onActivate = function()
									stayed += 1
								end,
							} :: FixtureNavigationTypes.AlertAction<any>,
							{ id = "Leave", label = "Leave" } :: FixtureNavigationTypes.AlertAction<any>,
						},
					})
				end)
				find(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect(stayed):toBe(1)
				Verify.expect((presented:peek())):toBe(false)
				world.stop()
				Verify.expect(function()
					setup(function(UI: FacetControls)
						return UI.Alert({
							isPresented = Compose.cell(true),
							title = "Leave?",
							transition = ("instant" :: unknown) :: false,
						})
					end)
				end):toThrow()
			end,
		})

		verifyHarness:case("a disclosure given an Instance as content shows it again after a collapse", {
			id = "native_navigation::native navigation controls::a disclosure given an Instance as content shows it again after a collapse",
			run = function()
				local expanded = Compose.cell(true)
				local inside: any
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					inside = Host.TextLabel "Inside" { Text = "Inside" }
					return UI.DisclosureGroup({ expanded = expanded, label = "Details", content = inside })
				end)
				world.gui.ReducedMotionEnabled = true
				Verify.expect((inside:IsDescendantOf(world.screen))):toBe(true)
				expanded:set(false)
				world.engine.heartbeat:Fire(1)
				Verify.expect((inside:isDestroyed())):toBe(false)
				expanded:set(true)
				Verify.expect((inside:IsDescendantOf(world.screen))):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("a collapsible view given an Instance as content shows it again after a collapse", {
			id = "native_navigation::native navigation controls::a collapsible view given an Instance as content shows it again after a collapse",
			run = function()
				local expanded = Compose.cell(true)
				local inside: any
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					inside = Host.TextLabel "Inside" { Text = "Inside" }
					return UI.CollapsibleView({ expanded = expanded, label = "Summary", content = inside })
				end)
				world.gui.ReducedMotionEnabled = true
				Verify.expect((inside:IsDescendantOf(world.screen))):toBe(true)
				expanded:set(false)
				world.engine.heartbeat:Fire(1)
				Verify.expect((inside:isDestroyed())):toBe(false)
				expanded:set(true)
				Verify.expect((inside:IsDescendantOf(world.screen))):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("returns disclosure focus before unmounting its content", {
			id = "native_navigation::native navigation controls::returns disclosure focus before unmounting its content",
			run = function()
				local expanded = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.DisclosureGroup({
						expanded = expanded,
						label = "Details",
						content = function(): Instance
							return UI.Button "Inside" { label = "Inside" }
						end,
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Inside")
				expanded:set(false)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Header")
				world.stop()
			end,
		})

		verifyHarness:case("draws the ancestor column of a cascade as menu rows in item order", {
			id = "native_navigation::native navigation controls::draws the ancestor column of a cascade as menu rows in item order",
			run = function()
				local presented, follow = Compose.cell(true), Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.Menu({
						isPresented = presented,
						items = {
							{
								id = "Parent",
								label = "Parent",
								children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
							} :: FixtureNavigationTypes.MenuItem<any>,
							{ id = "Follow", label = "Follow", checked = follow, onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
							{ divider = true } :: FixtureNavigationTypes.MenuItem<any>,
							{
								id = "Clear",
								label = "Clear",
								role = "destructive" :: "destructive",
								onSelect = function() end,
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				local modal = find(world.screen, "Modal")
				modal.AbsoluteSize = world.engine.types.Vector2.new(1000, 720)
				find(world.screen, "Parent").Activated:Fire()
				local ancestor = find(world.screen, "AncestorMenu")
				Verify.expect(ancestor ~= nil):toBe(true)
				local order = {}
				for _, child in ancestor:GetChildren() do
					if child:IsA("GuiObject") then
						table.insert(order, child)
					end
				end
				table.sort(order, function(a: any, b: any)
					return a.LayoutOrder < b.LayoutOrder
				end)
				local names = {}
				for _, child in order do
					table.insert(names, if child:IsA("GuiButton") then child.Name else "-")
				end
				Verify.expect((table.concat(names, ","))):toBe("Parent,Follow,-,Clear")
				for _, name in { "Parent", "Follow", "Clear" } do
					Verify.expect((ancestor:FindFirstChild(name):HasTag("facet-menu-item"))):toBe(true)
				end
				Verify.expect((ancestor:FindFirstChild("Clear"):HasTag("facet-menu-destructive"))):toBe(true)
				Verify.expect(find(ancestor:FindFirstChild("Parent"), "TrailingIcon") ~= nil):toBe(true)
				Verify.expect(find(ancestor:FindFirstChild("Follow"), "TrailingIcon").Visible):toBe(true)
				follow:set(false)
				Verify.expect(find(ancestor:FindFirstChild("Follow"), "TrailingIcon").Visible):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("keeps a right-edge cascade inside the room with disjoint ancestor and child columns", {
			id = "native_navigation::native navigation controls::keeps a right-edge cascade inside the room with disjoint ancestor and child columns",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.Menu "Cascade" {
						isPresented = Compose.cell(true),
						trigger = UI.Button "Anchor" { label = "Anchor" },
						items = {
							{
								id = "Parent",
								label = "Parent",
								children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
							},
						},
					}
				end)
				local V2 = world.engine.types.Vector2
				find(world.screen, "Modal").AbsoluteSize = V2.new(920, 640)
				find(world.screen, "Cascade").AbsolutePosition = V2.new(760, 100)
				find(world.screen, "Cascade").AbsoluteSize = V2.new(0, 40)
				find(world.screen, "Parent").Activated:Fire()
				local panel, ancestor = find(world.screen, "MenuPanel"), find(world.screen, "AncestorMenu")
				panel.AbsoluteSize = V2.new(220, 96)
				ancestor.AbsoluteSize = V2.new(280, 141)
				world.settle()
				local x = corner(panel)
				Verify.expect(ancestor.Position.X.Offset):toBeGreaterThanOrEqual(8)
				Verify.expect(ancestor.Position.X.Offset + 280):toBeLessThanOrEqual(x - 8)
				Verify.expect(x + 220):toBeLessThanOrEqual(912)
				Verify.expect(ancestor.Position.Y.Offset + 141):toBeLessThanOrEqual(632)
				world.stop()
			end,
		})

		verifyHarness:case("adapts an open menu to a compact sheet without losing its branch", {
			id = "native_navigation::native navigation controls::adapts an open menu to a compact sheet without losing its branch",
			run = function()
				local presented = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.Menu({
						isPresented = presented,
						items = {
							{
								id = "Parent",
								label = "Parent",
								children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				local modal = find(world.screen, "Modal")
				modal.AbsoluteSize = world.engine.types.Vector2.new(1000, 720)
				find(world.screen, "Parent").Activated:Fire()
				Verify.expect(find(world.screen, "AncestorMenu") ~= nil):toBe(true)
				modal.AbsoluteSize = world.engine.types.Vector2.new(360, 640)
				Verify.expect((find(world.screen, "AncestorMenu"))):toBe(nil)
				Verify.expect(find(world.screen, "Leaf") ~= nil):toBe(true)
				find(world.screen, "Back").Activated:Fire()
				Verify.expect(find(world.screen, "Parent") ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("keeps checked menu state and required radio values while honoring dismissal", {
			id = "native_navigation::native navigation controls::keeps checked menu state and required radio values while honoring dismissal",
			run = function()
				local presented, checked, selected = Compose.cell(true), Compose.cell(false), Compose.cell("a")
				local world = setup(function(UI: FacetControls)
					return UI.Menu({
						isPresented = presented,
						items = {
							{ id = "Check", label = "Check", checked = checked, dismiss = false } :: FixtureNavigationTypes.MenuItem<any>,
							{ id = "Radio", label = "Radio", selected = selected, value = "b", dismiss = false } :: FixtureNavigationTypes.MenuItem<any>,
							{ id = "Finish", label = "Finish", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				find(world.screen, "Check").Activated:Fire()
				find(world.screen, "Radio").Activated:Fire()
				Verify.expect((checked:peek())):toBe(true)
				Verify.expect((selected:peek())):toBe("b")
				Verify.expect((presented:peek())):toBe(true)
				find(world.screen, "Finish").Activated:Fire()
				Verify.expect((presented:peek())):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("rehomes tab accessories with native measured space and owner cleanup", {
			id = "native_navigation::native navigation controls::rehomes tab accessories with native measured space and owner cleanup",
			run = function()
				local selected, retired, built = Compose.cell("one"), 0, 0
				local preference, placement = cells.sidebar("automatic"), cells.placement("automatic")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local function accessory(): Instance
						built += 1
						Compose.cleanup(function()
							retired += 1
						end)
						return Host.Frame({})
					end
					return UI.TabView({
						selection = selected,
						style = "sidebarAdaptable" :: "sidebarAdaptable",
						sidebarPreference = preference,
						placement = placement,
						tabs = {
							{
								id = "one",
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
						},
						accessories = { head = accessory, foot = accessory, trailing = accessory, aboveBar = accessory },
					})
				end)
				local root = find(world.screen, "TabView")
				Verify.expect(find(root, "Tabs").ZIndex > find(root, "Content").ZIndex):toBe(true)
				root.AbsoluteSize = world.engine.types.Vector2.new(1200, 800)
				Verify.expect(find(world.screen, "Accessory-head") ~= nil):toBe(true)
				Verify.expect((find(world.screen, "Accessory-trailing"))):toBe(nil)
				find(world.screen, "Accessory-head").AbsoluteSize = world.engine.types.Vector2.new(180, 52)
				Verify.expect(find(world.screen, "Tabs").Position.Y.Offset):toBe(52)
				preference:set("topBar")
				Verify.expect((find(world.screen, "Accessory-head"))):toBe(nil)
				Verify.expect(find(world.screen, "Accessory-trailing") ~= nil):toBe(true)
				root.AbsoluteSize = world.engine.types.Vector2.new(401, 777)
				Verify.expect((find(world.screen, "Accessory-head"))):toBe(nil)
				Verify.expect(find(world.screen, "Accessory-aboveBar") ~= nil):toBe(true)
				Verify.expect(find(world.screen, "Tabs").Position.Y.Scale):toBe(1)
				preference:set("sidebar")
				Verify.expect((find(world.screen, "Accessory-head"))):toBe(nil)
				Verify.expect(find(world.screen, "Accessory-aboveBar") ~= nil):toBe(true)
				placement:set("topBar")
				Verify.expect(find(world.screen, "Accessory-trailing") ~= nil):toBe(true)
				Verify.expect((find(world.screen, "Accessory-aboveBar"))):toBe(nil)
				placement:set("automatic")
				root.AbsoluteSize = world.engine.types.Vector2.new(1200, 800)
				Verify.expect(find(world.screen, "Accessory-head") ~= nil):toBe(true)
				world.stop()
				Verify.expect(retired):toBe(built)
			end,
		})

		verifyHarness:case("hides the bar and gives the content the whole view with placement none", {
			id = "native_navigation::native navigation controls::hides the bar and gives the content the whole view with placement none",
			run = function()
				local selected, placement =
					Compose.cell("one"),
					Compose.cell(
						"none" :: "automatic" | "bottomBar" | "bottomBarCompact" | "none" | "sidebar" | "topBar"
					)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selected,
						style = "sidebarAdaptable" :: "sidebarAdaptable",
						placement = placement,
						tabs = {
							{
								id = "one",
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "two",
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local root = find(world.screen, "TabView")
				root.AbsoluteSize = world.engine.types.Vector2.new(844, 332)
				local T = world.engine.types
				Verify.expect(find(root, "Tabs").Visible):toBe(false)
				Verify.expect(find(root, "Content").Position):toBe(T.UDim2.fromOffset(0, 0))
				Verify.expect(find(root, "Content").Size):toBe(T.UDim2.fromScale(1, 1))
				placement:set("topBar")
				Verify.expect(find(root, "Tabs").Visible):toBe(true)
				Verify.expect(find(root, "Content").Position):toBe(T.UDim2.fromOffset(0, 52))
				world.stop()
			end,
		})

		verifyHarness:case("removes dynamically deleted tab owners and preserves the selected survivor", {
			id = "native_navigation::native navigation controls::removes dynamically deleted tab owners and preserves the selected survivor",
			run = function()
				local selection, tabs, disposed = Compose.cell("one"), nil, 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local function content()
						Compose.cleanup(function()
							disposed += 1
						end)
						return Host.Frame({})
					end
					tabs = Compose.cell({
						{ id = "one", content = content } :: FixtureNavigationTypes.Tab,
						{ id = "two", content = content } :: FixtureNavigationTypes.Tab,
					})
					return UI.TabView({ selection = selection, tabs = tabs })
				end)
				selection:set("two")
				selection:set("one")
				tabs:set({ tabs:peek()[1] })
				Verify.expect(disposed):toBe(1)
				Verify.expect((selection:peek())):toBe("one")
				world.stop()
			end,
		})

		verifyHarness:case("shows button help after a pointer rests on it and never on touch", {
			id = "native_navigation::native navigation controls::shows button help after a pointer rests on it and never on touch",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Screen" {
						UI.Button "Plus" { label = "+", help = "Posts this avatar" },
					}
				end)
				local plus = find(world.screen, "Plus")
				local Enum = world.engine.types.Enum
				world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
				plus.GuiState = Enum.GuiState.Hover
				Verify.expect((find(world.screen, "HelpText"))):toBe(nil)
				world.engine.heartbeat:Fire(0.3)
				Verify.expect((find(world.screen, "HelpText"))):toBe(nil)
				world.engine.heartbeat:Fire(0.3)
				Verify.expect(find(world.screen, "HelpText").Text):toBe("Posts this avatar")
				plus.GuiState = Enum.GuiState.Idle
				world.settle()
				Verify.expect((find(world.screen, "HelpText"))):toBe(nil)
				world.input.PreferredInput = Enum.PreferredInput.Touch
				plus.GuiState = Enum.GuiState.Hover
				world.engine.heartbeat:Fire(0.6)
				Verify.expect((find(world.screen, "HelpText"))):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("takes selection into a modal only for players navigating by selection", {
			id = "native_navigation::native navigation controls::takes selection into a modal only for players navigating by selection",
			run = function()
				local presented = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Screen" {
						UI.Button "Opener" { label = "Open" } :: unknown,
						UI.Alert {
							isPresented = presented,
							title = "Leave race?",
							actions = {
								{ id = "stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						},
					}
				end)
				presented:set(true)
				Verify.expect(world.gui.SelectedObject):toBe(nil)
				presented:set(false)
				world.gui.SelectedObject = find(world.screen, "Opener")
				presented:set(true)
				Verify.expect(world.gui.SelectedObject.Name):toBe("stay")
				presented:set(false)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Opener")
				world.gui.SelectedObject = nil
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
				presented:set(true)
				Verify.expect(world.gui.SelectedObject.Name):toBe("stay")
				world.stop()
			end,
		})

		verifyHarness:case("clears background selection when a modal opens after pointer input", {
			id = "native_navigation::native navigation controls::clears background selection when a modal opens after pointer input",
			run = function()
				local presented = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Button "Opener" { label = "Open" } :: unknown,
						UI.Alert {
							isPresented = presented,
							title = "Confirm",
							actions = { { id = "stay", label = "Stay", role = "cancel" :: "cancel" } },
						},
					}
				end)
				world.gui.SelectedObject = find(world.screen, "Opener")
				world.input.GetLastInputType = function()
					return world.engine.types.Enum.UserInputType.MouseMovement
				end
				presented:set(true)
				Verify.expect(world.gui.SelectedObject):toBeNil()
				world.settle()
				world.gui.SelectedObject = find(world.screen, "Opener")
				Verify.expect(world.gui.SelectedObject):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("hands selection to the shown tab panel and restores it on return", {
			id = "native_navigation::native navigation controls::hands selection to the shown tab panel and restores it on return",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls)
					return UI.TabView({
						selection = selection,
						tabs = {
							{ id = "one", content = UI.Button "OneAction" { label = "One" } } :: FixtureNavigationTypes.Tab,
							{ id = "two", content = UI.Button "TwoAction" { label = "Two" } } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				world.gui.SelectedObject = find(world.screen, "OneAction")
				selection:set("two")
				Verify.expect(world.gui.SelectedObject.Name):toBe("TwoAction")
				selection:set("one")
				Verify.expect(world.gui.SelectedObject.Name):toBe("OneAction")
				Verify.expect(#world.engine.rejectedSelections()):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("collapses a nested tab strip into one menu row when its region is short", {
			id = "native_navigation::native navigation controls::collapses a nested tab strip into one menu row when its region is short",
			run = function()
				local outer, inner = Compose.cell("a"), Compose.cell("x")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView {
						selection = outer,
						tabs = {
							{
								id = "a",
								content = function(): Instance
									return UI.TabView "Inner" {
										selection = inner,
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
				local nested = find(world.screen, "Inner")
				local strip = nested:FindFirstChild("Tabs")
				nested.AbsoluteSize = world.engine.types.Vector2.new(705, 200)
				Verify.expect(strip.Visible):toBe(false)
				Verify.expect(find(nested, "TabsMenu") ~= nil):toBe(true)
				nested.AbsoluteSize = world.engine.types.Vector2.new(705, 600)
				Verify.expect(strip.Visible):toBe(true)
				Verify.expect((find(nested, "TabsMenu"))):toBe(nil)
				nested:FindFirstChild("LayoutUnit").AbsoluteSize = world.engine.types.Vector2.new(60, 0.6)
				nested.AbsoluteSize = world.engine.types.Vector2.new(423, 360)
				Verify.expect(strip.Visible):toBe(true)
				Verify.expect((find(nested, "TabsMenu"))):toBe(nil)
				nested.AbsoluteSize = world.engine.types.Vector2.new(423, 240)
				Verify.expect(strip.Visible):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("pauses repeating progress motion while its retained tab is hidden", {
			id = "native_navigation::native navigation controls::pauses repeating progress motion while its retained tab is hidden",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView {
						selection = selection,
						tabs = {
							{
								id = "one",
								content = UI.ProgressView "Spinner" { presentation = "spinner" :: "spinner" },
							} :: FixtureNavigationTypes.Tab,
							{ id = "two", content = Host.Frame "Two" {} } :: FixtureNavigationTypes.Tab,
						},
					}
				end)
				local spinner = find(world.screen, "Spinner")
				local function snapshot()
					local values = {}
					for _, node in spinner:GetDescendants() do
						if node:IsA("GuiObject") then
							values[node] = `{node.BackgroundTransparency}|{node.Rotation}|{node.Size}|{node.Position}`
						end
					end
					return values
				end
				local function changed(before, after)
					local count = 0
					for node, value in before do
						if after[node] ~= value then
							count += 1
						end
					end
					return count
				end
				local function advance()
					for _ = 1, 10 do
						world.engine.heartbeat:Fire(1 / 30)
					end
				end
				local shown = snapshot()
				advance()
				Verify.expect(changed(shown, snapshot()) > 0):toBe(true)
				selection:set("two")
				advance()
				local hidden = snapshot()
				advance()
				Verify.expect((changed(hidden, snapshot()))):toBe(0)
				selection:set("one")
				local returned = snapshot()
				advance()
				Verify.expect(changed(returned, snapshot()) > 0):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("queues callouts by priority and retires once without writing model facts", {
			id = "native_navigation::native navigation controls::queues callouts by priority and retires once without writing model facts",
			run = function()
				local seen, used, retired = Compose.cell(false), Compose.cell(false), {}
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame({
						anchor :: unknown,
						UI.Callout({
							anchor = anchor :: GuiObject,
							seen = seen,
							priority = 1,
							content = function(): Instance
								return Host.TextLabel "FirstTip" {}
							end,
							onRetire = function(reason: "action" | "dismissed" | "featureUsed" | "seen" | "tapAway")
								table.insert(retired, "low:" .. reason)
							end,
						}),
						UI.Callout({
							anchor = anchor :: GuiObject,
							featureUsed = used,
							priority = 2,
							content = function(): Instance
								return Host.TextLabel "PriorityTip" {}
							end,
							onRetire = function(reason: "action" | "dismissed" | "featureUsed" | "seen" | "tapAway")
								table.insert(retired, "high:" .. reason)
							end,
						}),
					})
				end)
				Verify.expect((find(world.screen, "FirstTip"))):toBe(nil)
				Verify.expect(find(world.screen, "PriorityTip") ~= nil):toBe(true)
				used:set(true)
				world.settle()
				Verify.expect((find(world.screen, "PriorityTip"))):toBe(nil)
				Verify.expect(find(world.screen, "FirstTip") ~= nil):toBe(true)
				find(world.screen, "Dismiss").Activated:Fire()
				Verify.expect(#retired):toBe(2)
				Verify.expect((seen:peek())):toBe(false)
				world.stop()
				Verify.expect(#retired):toBe(2)
			end,
		})

		verifyHarness:case("keeps sheet content in a native flex remainder and explicit close operable", {
			id = "native_navigation::native navigation controls::keeps sheet content in a native flex remainder and explicit close operable",
			run = function()
				local presented, detent = Compose.cell(true), Compose.cell("medium")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet({
						isPresented = presented,
						detent = detent,
						title = "Details",
						closeButton = true,
						interactiveDismissDisabled = true,
						content = function(): Instance
							return Host.ScrollingFrame "DetailBody" {}
						end,
					})
				end)
				Verify.expect(find(world.screen, "DetailBody").Parent.Name):toBe("SheetFlow")
				local body = find(world.screen, "SheetContent")
				Verify.expect(body.ClassName):toBe("ScrollingFrame")
				Verify.expect(body.AutomaticCanvasSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				find(world.screen, "SheetFlow").AbsoluteSize = world.engine.types.Vector2.new(400, 1800)
				Verify.expect(body.CanvasSize.Y.Offset):toBe(1800)
				Verify.expect(find(body, "UIListLayout") ~= nil):toBe(true)
				Verify.expect(find(find(world.screen, "SheetContent"), "UIFlexItem").FlexMode)
					:toBe(world.engine.types.Enum.UIFlexMode.Fill)
				Verify.expect((find(world.screen, "Size"))):toBe(nil)
				Verify.expect(find(world.screen, "Close").Parent.Name):toBe("Header")
				local grabber = find(world.screen, "Grabber")
				Verify.expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Resize: Medium")
				Verify.expect(grabber.Selectable):toBe(true)
				Verify.expect(grabber.Size.Y.Offset >= 44 and grabber.Size.X.Offset >= 44):toBe(true)
				grabber.Activated:Fire()
				Verify.expect((detent:peek())):toBe("large")
				Verify.expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Close sheet")
				find(world.screen, "Close").Activated:Fire()
				Verify.expect((presented:peek())):toBe(false)
				world.stop()
			end,
		})
		verifyHarness:case("contains failed alert factories and accepts a later valid presentation", {
			id = "native_navigation::native navigation controls::contains failed alert factories and accepts a later valid presentation",
			run = function()
				local item, disposed = Compose.cell(nil :: { id: string }?), 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Alert({
						item = item,
						title = function(value)
							return value.id
						end,
						content = function(value): Instance
							Compose.cleanup(function()
								disposed += 1
							end)
							if value.id == "bad" then
								error("invalid content")
							end
							return Host.Frame "Recovered" {}
						end,
					})
				end)
				item:set({ id = "bad" })
				Verify.expect((item:peek())):toBe(nil)
				Verify.expect(disposed):toBe(1)
				item:set({ id = "good" })
				Verify.expect(find(world.screen, "Recovered") ~= nil):toBe(true)
				world.stop()
				Verify.expect(disposed):toBe(2)
			end,
		})

		verifyHarness:case("wraps alert actions and bounds long message scrolling to native measurements", {
			id = "native_navigation::native navigation controls::wraps alert actions and bounds long message scrolling to native measurements",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.Alert({
						isPresented = Compose.cell(true),
						message = string.rep("Long message ", 100),
						actions = {
							{ id = "Cancel", label = "Cancel", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
							{ id = "Accept", label = "Continue" } :: FixtureNavigationTypes.AlertAction<any>,
						},
					})
				end)
				find(world.screen, "AlertModal").AbsoluteSize = world.engine.types.Vector2.new(360, 240)
				find(world.screen, "Actions").AbsoluteSize = world.engine.types.Vector2.new(320, 96)
				find(world.screen, "AlertContent").AbsoluteSize = world.engine.types.Vector2.new(320, 1000)
				Verify.expect(find(find(world.screen, "Actions"), "UIListLayout").FillDirection)
					:toBe(world.engine.types.Enum.FillDirection.Vertical)
				Verify.expect(find(world.screen, "Cancel").LayoutOrder > find(world.screen, "Accept").LayoutOrder)
					:toBe(true)
				Verify.expect(find(world.screen, "AlertMessage").Size.Y.Offset < 100):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("keeps the alert card inside the screen when the theme chrome adds to its height", {
			id = "native_navigation::native navigation controls::keeps the alert card inside the screen when the theme chrome adds to its height",
			run = function()
				local themes = require("../src/ui/themes")(Compose)
				local package = themes.neutralPackage()
				package.chrome = package.chrome or {}
				assert(package.chrome).panel =
					{ kind = "native" :: "native", contentInsets = { top = 18, bottom = 18, left = 18, right = 18 } }
				local world = setup(function(UI: FacetControls)
					return UI.Alert({
						isPresented = Compose.cell(true),
						message = string.rep("Long message ", 100),
						actions = {
							{ id = "Stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
							{ id = "Save", label = "Save and leave" } :: FixtureNavigationTypes.AlertAction<any>,
							{ id = "Leave", label = "Leave without saving", role = "destructive" :: "destructive" } :: FixtureNavigationTypes.AlertAction<any>,
						},
					})
				end, { theme = assert(themes.define(package)) })
				local V2 = world.engine.types.Vector2.new
				find(world.screen, "AlertModal").AbsoluteSize = V2(667, 375)
				find(world.screen, "Actions").AbsoluteSize = V2(400, 148)
				find(world.screen, "AlertContent").Parent.AbsoluteSize = V2(400, 1000)
				local message = find(world.screen, "AlertMessage")
				local card = message.Size.Y.Offset + 148 + 20 * 2 + 8 + 18 * 2
				Verify.expect(message.Size.Y.Offset):toBe(375 - 148 - (20 * 2 + 8 + 18 * 2) - 32)
				Verify.expect(card <= 375 - 32):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case(
			"grows a segmented strip at a larger text size so its caption fits inside the theme control insets",
			{
				id = "native_navigation::native navigation controls::grows a segmented strip at a larger text size so its caption fits inside the theme control insets",
				run = function()
					local themes = require("../src/ui/themes")(Compose)
					local package = themes.neutralPackage()
					package.chrome = package.chrome or {}
					assert(package.chrome).control =
						{ kind = "fill" :: "fill", contentInsets = { top = 10, bottom = 10, left = 12, right = 12 } }
					local world = setup(function(UI: FacetControls)
						return UI.Picker({
							style = "segmented" :: "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "Open" } :: Navigation.PickerOption<string>,
								{ value = "b", label = "Club" } :: Navigation.PickerOption<string>,
							},
						})
					end, { theme = assert(themes.define(package)) })
					local V2 = world.engine.types.Vector2.new
					local picker = find(world.screen, "Picker")
					find(world.screen, "a").TextBounds = V2(56, 31)
					Verify.expect(picker.Size.Y.Offset):toBe(31 + 20 + 6)
					find(world.screen, "a").TextBounds = V2(48, 16)
					world.gui.PreferredTextSize = world.engine.types.Enum.PreferredTextSize.Largest
					Verify.expect(picker.Size.Y.Offset):toBe(50)
					find(world.screen, "a").TextBounds = V2(56, 31)
					find(world.screen, "b").TextBounds = V2(48, 29)
					Verify.expect(picker.Size.Y.Offset):toBe(31 + 20 + 6)
					find(world.screen, "a").TextBounds = V2(56, 20)
					Verify.expect(picker.Size.Y.Offset):toBe(29 + 20 + 6)
					world.stop()
				end,
			}
		)

		verifyHarness:case("reserves segmented caption width and wraps rows instead of clipping whole words", {
			id = "native_navigation::native navigation controls::reserves segmented caption width and wraps rows instead of clipping whole words",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.Picker "Motion" {
						style = "segmented" :: "segmented",
						selected = Compose.cell("normal"),
						options = {
							{ value = "normal", label = "Normal" },
							{ value = "limited", label = "Limited" },
						},
					}
				end)
				local picker, button = find(world.screen, "Motion"), find(world.screen, "normal")
				find(button, "CaptionMeasure").TextBounds = world.engine.types.Vector2.new(54, 16)
				Verify.expect(button:FindFirstChildWhichIsA("UISizeConstraint").MinSize.X):toBeGreaterThanOrEqual(78)
				Verify.expect(picker:FindFirstChildWhichIsA("UIListLayout").Wraps):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("fits segmented glyphs inside compact chrome at the default text preference", {
			id = "native_navigation::native navigation controls::fits segmented glyphs inside compact chrome at the default text preference",
			run = function()
				local themes = require("../src/ui/themes")(Compose)
				local package = themes.neutralPackage()
				package.metrics.controlSizes.compact.height = 22
				package.chrome = { control = { kind = "fill", contentInsets = { top = 2, bottom = 2 } } }
				local world = setup(function(UI: FacetControls)
					return UI.Picker "Laps" {
						style = "segmented" :: "segmented",
						controlSize = "compact" :: "compact",
						selected = Compose.cell("3"),
						options = {
							{ value = "3", label = "3" } :: Navigation.PickerOption<string>,
							{ value = "10", label = "10" } :: Navigation.PickerOption<string>,
						},
					}
				end, { theme = assert(themes.define(package)) })
				local picker = find(world.screen, "Laps")
				find(picker, "3").TextBounds = world.engine.types.Vector2.new(8, 13)
				find(picker, "10").TextBounds = world.engine.types.Vector2.new(16, 13)
				Verify.expect(picker.Size.Y.Offset):toBe(13 + 4 + 6)
				find(picker, "10").TextBounds = world.engine.types.Vector2.new(16, 18)
				Verify.expect(picker.Size.Y.Offset):toBe(18 + 4 + 6)
				find(picker, "10").TextBounds = world.engine.types.Vector2.new(16, 13)
				Verify.expect(picker.Size.Y.Offset):toBe(13 + 4 + 6)
				world.stop()
			end,
		})

		verifyHarness:case("keeps split primary activation separate from touch long-press alternatives", {
			id = "native_navigation::native navigation controls::keeps split primary activation separate from touch long-press alternatives",
			run = function()
				local primary, alternative = 0, 0
				local world = setup(function(UI: FacetControls, _, engine)
					return UI.SplitButton({
						Size = engine.types.UDim2.fromOffset(148, 44),
						AutomaticSize = engine.types.Enum.AutomaticSize.None,
						label = "Run",
						onActivate = function()
							primary += 1
						end,
						items = {
							{
								id = "Alternate",
								label = "Alternate",
								onSelect = function()
									alternative += 1
								end,
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				find(world.screen, "Primary").Activated:Fire()
				Verify.expect(primary):toBe(1)
				local chevron = find(world.screen, "Alternatives")
				Verify.expect((chevron:HasTag("facet-button"))):toBe(true)
				Verify.expect((chevron:FindFirstChildWhichIsA("UISizeConstraint"))):toBe(nil)
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
				local trigger = find(world.screen, "Primary")
				Verify.expect(trigger.Size):toBe(world.engine.types.UDim2.fromScale(1, 1))
				Verify.expect(trigger.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				trigger.TouchLongPress:Fire({}, world.engine.types.Enum.UserInputState.Begin)
				trigger.Activated:Fire()
				Verify.expect(primary):toBe(1)
				Verify.expect(find(world.screen, "MenuPanel") ~= nil):toBe(true)
				find(world.screen, "Alternate").Activated:Fire()
				Verify.expect(alternative):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("opens searchable picker content only when presented and commits filtered results", {
			id = "native_navigation::native navigation controls::opens searchable picker content only when presented and commits filtered results",
			run = function()
				local selection, query, opened = Compose.cell("a"), Compose.cell(""), Compose.cell(false)
				local world = setup(function(UI: FacetControls)
					return UI.Picker({
						selected = selection,
						query = query,
						isPresented = opened,
						style = "navigationLink" :: "navigationLink",
						options = {
							{ value = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
							{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
						},
					})
				end)
				Verify.expect((find(world.screen, "PickerSearch"))):toBe(nil)
				opened:set(true)
				query:set("Bet")
				Verify.expect((find(find(world.screen, "Choices"), "a"))):toBe(nil)
				find(find(world.screen, "Choices"), "b").Activated:Fire()
				Verify.expect((selection:peek())):toBe("b")
				Verify.expect((opened:peek())):toBe(false)
				world.stop()
			end,
		})
		verifyHarness:case("sizes the navigation bar title by the stack's width class", {
			id = "native_navigation::native navigation controls::sizes the navigation bar title by the stack's width class",
			run = function()
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.NavigationStack({
						path = path,
						root = {
							title = "Garage",
							content = function(): Instance
								return Host.Frame({})
							end,
						} :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							detail = {
								title = "Engine",
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
						},
					})
				end)
				local bar = find(world.screen, "NavigationBar")
				local title = find(bar, "Title")
				bar.AbsoluteSize = world.engine.types.Vector2.new(390, 44)
				Verify.expect((title:HasTag("facet-type-heading"))):toBe(true)
				Verify.expect((title:HasTag("facet-type-title"))):toBe(false)
				bar.AbsoluteSize = world.engine.types.Vector2.new(1024, 44)
				Verify.expect((title:HasTag("facet-type-title"))):toBe(true)
				Verify.expect((title:HasTag("facet-type-heading"))):toBe(false)
				local inset = title:FindFirstChildWhichIsA("UIPadding")
				Verify.expect(inset and inset.PaddingLeft.Offset):toBe(12)
				Verify.expect(inset and inset.PaddingRight.Offset):toBe(12)
				world.stop()
			end,
		})
		verifyHarness:case("restores surviving navigation focus and moves paging focus into the visible page", {
			id = "native_navigation::native navigation controls::restores surviving navigation focus and moves paging focus into the visible page",
			run = function()
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
				local world = setup(function(UI: FacetControls)
					return UI.NavigationStack({
						path = path,
						root = {
							content = function(): Instance
								return UI.Button "RootAction" { label = "Root" }
							end,
						} :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							detail = {
								content = function(): Instance
									return UI.Button "DetailAction" { label = "Detail" }
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
						},
					})
				end)
				world.gui.SelectedObject = find(world.screen, "RootAction")
				path:set({ { id = "detail" } })
				world.settle()
				Verify.expect(world.gui.SelectedObject.Name):toBe("Back")
				path:set({})
				world.settle()
				Verify.expect(world.gui.SelectedObject.Name):toBe("RootAction")
				world.stop()
				local selection = Compose.cell("one")
				local pager = setup(function(UI: FacetControls)
					return UI.PageView({
						selection = selection,
						pages = {
							{ id = "one", content = UI.Button "PageOne" { label = "One" } } :: FixtureNavigationTypes.Tab,
							{ id = "two", content = UI.Button "PageTwo" { label = "Two" } } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				pager.gui.SelectedObject = find(pager.screen, "PageOne")
				selection:set("two")
				Verify.expect(pager.gui.SelectedObject.Name):toBe("PageTwo")
				pager.stop()
			end,
		})
		verifyHarness:case("bounds menu scrolling, prunes removed branches and closes every level on tap away", {
			id = "native_navigation::native navigation controls::bounds menu scrolling, prunes removed branches and closes every level on tap away",
			run = function()
				local shown, items: FixtureComposeTypes.Cell<{ FixtureNavigationTypes.MenuItem<any> }> =
					Compose.cell(true), Compose.cell({ { id = "branch", label = "Branch", children = {
						{ id = "leaf", label = "Leaf", onSelect = function() end },
					} } } :: { Navigation.MenuItem<any> })
				local world = setup(function(UI: FacetControls)
					return UI.Menu({ isPresented = shown, items = items })
				end)
				local panel = find(world.screen, "MenuPanel")
				panel.Parent.AbsoluteSize = world.engine.types.Vector2.new(700, 300)
				find(world.screen, "MenuRows").AbsoluteSize = world.engine.types.Vector2.new(280, 1000)
				Verify.expect(find(panel, "MenuScroll").ClassName):toBe("ScrollingFrame")
				Verify.expect(panel.Size.Y.Offset):toBe(276)
				find(world.screen, "branch").Activated:Fire()
				items:set({ { id = "other", label = "Other", onSelect = function() end } })
				Verify.expect((find(world.screen, "leaf"))):toBe(nil)
				Verify.expect(find(world.screen, "other") ~= nil):toBe(true)
				items:set({
					{
						id = "branch",
						label = "Branch",
						children = { { id = "leaf", label = "Leaf", onSelect = function() end } },
					},
				})
				find(world.screen, "branch").Activated:Fire()
				find(world.screen, "DismissOutside").Activated:Fire()
				Verify.expect((shown:peek())):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case(
			"adapts automatic pickers and updates native segment axis and badges without replacing options",
			{
				id = "native_navigation::native navigation controls::adapts automatic pickers and updates native segment axis and badges without replacing options",
				run = function()
					local value, axis, badge = Compose.cell("a"), cells.axis("x"), Compose.cell(1)
					local position, visible, interactable = Compose.cell(24), Compose.cell(true), Compose.cell(true)
					local reference, references, enters = nil, 0, 0
					local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
						return Host.Frame({
							UI.Picker("Auto")({
								Position = function(use: Use)
									return engine.types.UDim2.fromOffset(use(position), 70)
								end,
								AnchorPoint = engine.types.Vector2.new(0.5, 0),
								Size = engine.types.UDim2.fromOffset(240, 44),
								AutomaticSize = engine.types.Enum.AutomaticSize.None,
								LayoutOrder = 7,
								Visible = visible,
								Interactable = interactable,
								Attributes = { role = "choice" :: "choice" } :: FixtureEngineTypes.Attributes,
								ref = function(node)
									reference = node
									references += 1
								end,
								[Compose.event("MouseEnter") :: number | typeof(Compose.event(""))] = (function()
									enters += 1
								end) :: unknown,
								Host.UICorner "AuthoredCorner" {} :: unknown,
								selected = value,
								options = {
									{ value = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
									{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
								},
							}) :: unknown,
							UI.Picker "Segments" {
								style = "segmented" :: "segmented",
								axis = axis,
								selected = value,
								options = {
									{ value = "a", label = "Alpha", badge = badge } :: Navigation.PickerOption<string>,
									{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
								},
							},
						})
					end)
					local automatic = find(world.screen, "Auto")
					local decoration = find(automatic, "AuthoredCorner")
					Verify.expect(reference):toBe(automatic)
					Verify.expect(automatic.Position.X.Offset):toBe(24)
					Verify.expect(automatic.Position.Y.Offset):toBe(70)
					Verify.expect(automatic.AnchorPoint.X):toBe(0.5)
					Verify.expect(automatic.Size.X.Offset):toBe(240)
					Verify.expect(automatic.Size.Y.Offset):toBe(44)
					Verify.expect(automatic.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
					Verify.expect(automatic.LayoutOrder):toBe(7)
					Verify.expect((automatic:GetAttribute("role"))):toBe("choice")
					Verify.expect(decoration.Parent):toBe(automatic)
					local presentation = find(automatic, "Presentation")
					Verify.expect(presentation.Position.X.Offset):toBe(0)
					Verify.expect(presentation.Size.X.Scale):toBe(1)
					Verify.expect(presentation.Size.Y.Scale):toBe(1)
					Verify.expect((presentation:GetAttribute("role"))):toBe(nil)
					automatic.MouseEnter:Fire()
					presentation.MouseEnter:Fire()
					Verify.expect(enters):toBe(1)
					position:set(52)
					visible:set(false)
					interactable:set(false)
					Verify.expect(automatic.Position.X.Offset):toBe(52)
					Verify.expect(automatic.Visible):toBe(false)
					Verify.expect(automatic.Interactable):toBe(false)
					visible:set(true)
					interactable:set(true)
					local segments = find(world.screen, "Segments")
					local a = find(segments, "a")
					axis:set("y")
					badge:set(3)
					Verify.expect((find(segments, "a"))):toBe(a)
					Verify.expect(a.Size.X.Scale):toBe(1)
					Verify.expect((a:GetAttribute("label"))):toBe("Alpha (3)")
					Verify.expect(find(a, "Count").Text):toBe("3")
					Verify.expect(segments:FindFirstChildWhichIsA("UIListLayout").FillDirection)
						:toBe(world.engine.types.Enum.FillDirection.Vertical)

					find(automatic, "LabelMeasure").TextBounds = world.engine.types.Vector2.new(100, 18)
					automatic.AbsoluteSize = world.engine.types.Vector2.new(120, 44)
					world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
					Verify.expect(find(find(world.screen, "Auto"), "Trigger") ~= nil):toBe(true)
					world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
					Verify.expect(find(find(world.screen, "Auto"), "b") ~= nil):toBe(true)
					Verify.expect((find(world.screen, "Auto"))):toBe(automatic)
					Verify.expect((find(automatic, "AuthoredCorner"))):toBe(decoration)
					Verify.expect(automatic.Position.X.Offset):toBe(52)
					Verify.expect(find(automatic, "Presentation").Position.X.Offset):toBe(0)
					Verify.expect(references):toBe(1)
					automatic.MouseEnter:Fire()
					Verify.expect(enters):toBe(2)
					Verify.expect((value:peek())):toBe("a")
					world.stop()
				end,
			}
		)

		verifyHarness:case("bounds menu picker triggers to authored widths without losing their full label", {
			id = "native_navigation::native navigation controls::bounds menu picker triggers to authored widths without losing their full label",
			run = function()
				local selected = Compose.cell("hud")
				local sizing
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					sizing = Compose.cell(engine.types.Enum.AutomaticSize.None)
					return Host.Frame({
						UI.Picker "Bounded" {
							style = "menu" :: "menu",
							Size = engine.types.UDim2.new(1, -160, 0, 44),
							selected = selected,
							options = {
								{ value = "hud", label = "Screen-anchored HUD with a long title" } :: Navigation.PickerOption<string>,
								{ value = "other", label = "Another destination with a long title" } :: Navigation.PickerOption<string>,
							},
						} :: unknown,
						UI.Menu "AdaptiveHeight" {
							Size = engine.types.UDim2.new(1, 0, 0, 0),
							AutomaticSize = sizing,
							label = "Menu",
							items = {
								{ id = "one", label = "One", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
							},
						},
					})
				end)
				local bounded = find(world.screen, "Bounded")
				local trigger = find(bounded, "Trigger")
				Verify.expect(bounded.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				Verify.expect(trigger.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				Verify.expect(trigger.Size.X.Scale):toBe(1)
				Verify.expect(trigger.Size.X.Offset):toBe(0)
				Verify.expect(trigger.Size.Y.Scale):toBe(1)
				Verify.expect(trigger.TextTruncate):toBe(world.engine.types.Enum.TextTruncate.AtEnd)
				Verify.expect(trigger.TextWrapped):toBe(false)
				Verify.expect(trigger.ClipsDescendants):toBe(true)
				Verify.expect(trigger.Text):toBe("Screen-anchored HUD with a long title")
				Verify.expect((trigger:GetAttribute("FacetLabel"))):toBe(trigger.Text)
				trigger.Activated:Fire()
				find(find(world.screen, "MenuPanel"), "other").Activated:Fire()
				Verify.expect((selected:peek())):toBe("other")
				Verify.expect(trigger.Text):toBe("Another destination with a long title")
				Verify.expect((trigger:GetAttribute("FacetLabel"))):toBe(trigger.Text)
				local adaptive = find(find(world.screen, "AdaptiveHeight"), "Trigger")
				sizing:set(world.engine.types.Enum.AutomaticSize.Y)
				Verify.expect(adaptive.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.Y)
				Verify.expect(adaptive.Size.X.Scale):toBe(1)
				Verify.expect(adaptive.Size.Y.Scale):toBe(0)
				Verify.expect(adaptive.Size.Y.Offset >= 44):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("keeps plain picker segments native while retaining live description sources", {
			id = "native_navigation::native navigation controls::keeps plain picker segments native while retaining live description sources",
			run = function()
				local selected, description = Compose.cell("a"), Compose.cell("")
				local options = Compose.cell({ { value = "a", label = "Alpha" } })
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Picker "Plain" {
							style = "segmented" :: "segmented",
							selected = selected,
							options = {
								{ value = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
								{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
							},
						} :: unknown,
						UI.Picker "ReadableDescription" {
							style = "segmented" :: "segmented",
							selected = selected,
							options = {
								{ value = "a", label = "Alpha", description = description } :: Navigation.PickerOption<string>,
							},
						},
						UI.Picker "ReadableOptions" {
							style = "segmented" :: "segmented",
							selected = selected,
							options = options,
						},
					})
				end)
				local plain = find(find(world.screen, "Plain"), "a")
				Verify.expect(plain.ClassName):toBe("TextButton")
				Verify.expect(plain.Text):toBe("Alpha")
				Verify.expect((find(plain, "Content"))):toBe(nil)
				Verify.expect((find(plain, "Description"))):toBe(nil)
				find(find(world.screen, "Plain"), "b").Activated:Fire()
				Verify.expect((selected:peek())):toBe("b")
				local described = find(find(world.screen, "ReadableDescription"), "a")
				description:set("Appeared")
				Verify.expect((find(find(world.screen, "ReadableDescription"), "a"))):toBe(described)
				Verify.expect(find(described, "Description").Text):toBe("Appeared")
				Verify.expect(find(described, "Description").Visible):toBe(true)
				description:set("")
				Verify.expect(find(described, "Description").Visible):toBe(false)
				local replaced = find(find(world.screen, "ReadableOptions"), "a")
				options:set({ { value = "a", label = "Alpha updated", description = "Added later" } })
				Verify.expect((find(find(world.screen, "ReadableOptions"), "a"))):toBe(replaced)
				Verify.expect(find(replaced, "Title").Text):toBe("Alpha updated")
				Verify.expect(find(replaced, "Description").Text):toBe("Added later")
				Verify.expect((find(find(world.screen, "Plain"), "a"))):toBe(plain)
				world.stop()
			end,
		})

		verifyHarness:case("quarantines invalid paths and contains destination faults while preserving Back", {
			id = "native_navigation::native navigation controls::quarantines invalid paths and contains destination faults while preserving Back",
			run = function()
				local path, disposed = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> }), 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.NavigationStack({
						path = path,
						root = {
							content = function(): Instance
								return UI.Button "RootAction" { label = "Root" }
							end,
						} :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							good = {
								content = function(): Instance
									return UI.Button "Good" { label = "Good" }
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
							bad = {
								content = function()
									Compose.cleanup(function()
										disposed += 1
									end)
									Host.Frame({})
									error("failed page")
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
						},
					})
				end)
				local root = find(world.screen, "@root")
				Verify.expect(find(root, "Destination").Position.Y.Offset):toBe(0)
				path:set({ { id = "good" } })
				local good = find(world.screen, "Good")
				path:set({ { id = "unknown" } })
				Verify.expect((find(world.screen, "Good"))):toBe(good)
				Verify.expect(find(world.screen, "NavigationStack"):GetAttribute("FacetError") ~= nil):toBe(true)
				path:set({ { id = "bad" } })
				Verify.expect(find(world.screen, "DestinationError") ~= nil):toBe(true)
				Verify.expect(disposed):toBe(1)
				find(world.screen, "Back").Activated:Fire()
				Verify.expect(#path:peek()):toBe(0)
				Verify.expect(find(world.screen, "RootAction") ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("routes nested Back through the focused native context before its parent", {
			id = "native_navigation::native navigation controls::routes nested Back through the focused native context before its parent",
			run = function()
				local outer, inner =
					Compose.cell({ { id = "child" } } :: { NavigationFixtures.NavigationEntry<any> }),
					Compose.cell({ { id = "detail" } } :: { NavigationFixtures.NavigationEntry<any> })
				local world = setup(function(UI: FacetControls)
					return UI.NavigationStack({
						path = outer,
						root = {
							content = function(): Instance
								return UI.Button({ label = "Root" })
							end,
						} :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							child = {
								content = function(): Instance
									return UI.NavigationStack "ChildStack" {
										path = inner,
										root = {
											content = function(): Instance
												return UI.Button({ label = "Child root" })
											end,
										} :: NavigationFixtures.NavigationDestination<any>,
										destinations = {
											detail = {
												content = function(): Instance
													return UI.Button "DeepAction" { label = "Deep" }
												end,
											} :: NavigationFixtures.NavigationDestination<any>,
										},
									}
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
						},
					})
				end)
				world.gui.SelectedObject = find(world.screen, "DeepAction")
				local winner
				for _, node in world.screen:GetDescendants() do
					if
						node.Name == "NavigationBack"
						and node.Parent.Enabled
						and (not winner or node.Parent.Priority > winner.Parent.Priority)
					then
						winner = node
					end
				end
				Verify.expect(winner ~= nil):toBe(true)
				winner.Pressed:Fire()
				Verify.expect(#inner:peek()):toBe(0)
				Verify.expect(#outer:peek()):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("routes Back through separately created nested controls", {
			id = "native_navigation::native navigation controls::routes Back through separately created nested controls",
			run = function()
				local outer, inner =
					Compose.cell({ { id = "child" } } :: { NavigationFixtures.NavigationEntry<any> }),
					Compose.cell({ { id = "detail" } } :: { NavigationFixtures.NavigationEntry<any> })
				local world = setup(function(UI: FacetControls, _Host, engine, gui, runtime)
					local Child = controls(Compose, runtime, { types = engine.types, services = { GuiService = gui } })
					return UI.NavigationStack({
						path = outer,
						root = {
							content = function(): Instance
								return UI.Button({ label = "Root" })
							end,
						} :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							child = {
								content = function(): Instance
									return Child.NavigationStack "ChildStack" {
										path = inner,
										root = {
											content = function(): Instance
												return UI.Button({ label = "Child root" })
											end,
										} :: NavigationFixtures.NavigationDestination<any>,
										destinations = {
											detail = {
												content = function(): Instance
													return UI.Button "DeepAction" { label = "Deep" }
												end,
											} :: NavigationFixtures.NavigationDestination<any>,
										},
									}
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
						},
					})
				end)
				world.gui.SelectedObject = find(world.screen, "DeepAction")
				local winner
				for _, node in world.screen:GetDescendants() do
					if
						node.Name == "NavigationBack"
						and node.Parent.Enabled
						and (not winner or node.Parent.Priority > winner.Parent.Priority)
					then
						winner = node
					end
				end
				Verify.expect(winner ~= nil):toBe(true)
				winner.Pressed:Fire()
				Verify.expect(#inner:peek()):toBe(0)
				Verify.expect(#outer:peek()):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("keeps callouts nonmodal, fits their plate and observes nonconsuming tap away", {
			id = "native_navigation::native navigation controls::keeps callouts nonmodal, fits their plate and observes nonconsuming tap away",
			run = function()
				local shown, retired, presses = Compose.cell(true), nil, 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine, gui)
					local anchor = UI.Button "Anchor" {
						label = "Anchor",
						onActivate = function()
							presses += 1
						end,
					}
					gui.SelectedObject = anchor
					return Host.Frame({
						anchor :: unknown,
						UI.Callout({
							anchor = anchor :: GuiObject,
							isPresented = shown,
							onRetire = function(reason)
								retired = reason
							end,
							content = function(): Instance
								return UI.Button({ label = "Tip" })
							end,
						}),
					})
				end)
				local V = world.engine.types.Vector2
				world.screen.AbsoluteSize = V.new(320, 400)
				local anchor, panel = find(world.screen, "Anchor"), find(world.screen, "CalloutPanel")
				anchor.AbsolutePosition = V.new(280, 20)
				anchor.AbsoluteSize = V.new(32, 44)
				panel.AbsoluteSize = V.new(280, 100)
				world.settle()
				Verify.expect((near((corner(panel)), 32))):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(anchor)
				anchor.Activated:Fire()
				Verify.expect(presses):toBe(1)
				world.input.InputBegan:Fire(
					{ UserInputType = world.engine.types.Enum.UserInputType.MouseButton1, Position = V.new(10, 350) },
					false
				)
				Verify.expect(retired):toBe("tapAway")
				Verify.expect((shown:peek())):toBe(true)
				world.settle()
				Verify.expect((find(world.screen, "CalloutPanel"))):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("places a callout inside the overlay parent that receives it", {
			id = "native_navigation::native navigation controls::places a callout inside the overlay parent that receives it",
			run = function()
				local engine = engines.new()
				local gui = engine.new("GuiService")
				local input = engine.new("UserInputService")
				input.GetFocusedTextBox = function()
					return nil
				end
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local overlay = engine.new("Frame")
				local UI = controls(Compose, runtime, {
					types = engine.types,
					services = { GuiService = gui, UserInputService = input },
					overlayParent = overlay,
				})
				local stop, screen: any = runtime.mount(function()
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
						((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							anchor :: unknown,
							UI.Callout({
								anchor = anchor :: GuiObject,
								isPresented = Compose.cell(true),
								onRetire = function() end,
								content = function(): Instance
									return UI.Button({ label = "Tip" })
								end,
							}),
						}),
					})
				end, engine.new("Folder"))
				overlay.Parent = screen
				local V = engine.types.Vector2
				screen.AbsoluteSize = V.new(1920, 1080)
				overlay.AbsolutePosition = V.new(100, 50)
				overlay.AbsoluteSize = V.new(320, 400)
				local anchor, panel = find(screen, "Anchor"), find(screen, "CalloutPanel")
				Verify.expect((panel:IsDescendantOf(overlay))):toBe(true)
				anchor.AbsolutePosition = V.new(380, 70)
				anchor.AbsoluteSize = V.new(32, 44)
				panel.AbsoluteSize = V.new(280, 100)
				for _ = 1, 60 do
					engine.heartbeat:Fire(1 / 60)
				end
				Verify.expect((near((corner(panel)), 32))):toBe(true)
				Verify.expect(panel.Size.X.Offset):toBe(280)
				overlay.AbsoluteSize = V.new(200, 400)
				for _ = 1, 60 do
					engine.heartbeat:Fire(1 / 60)
				end
				Verify.expect(panel.Size.X.Offset):toBe(184)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("retargets native sheet motion and honors live reduced motion without losing content", {
			id = "native_navigation::native navigation controls::retargets native sheet motion and honors live reduced motion without losing content",
			run = function()
				local selected, shown = Compose.cell("medium"), Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.Sheet({
						detent = selected,
						isPresented = shown,
						content = function(): Instance
							return UI.Button "KeptContent" { label = "Content" }
						end,
					})
				end)
				find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(800, 720)
				world.engine.heartbeat:Fire(1 / 600)
				world.engine.heartbeat:Fire(1 / 600)
				local panel, content = find(world.screen, "SheetPanel"), find(world.screen, "KeptContent")
				local before = panel.Size.Y.Offset
				selected:set("large")
				Verify.expect(panel.Size.Y.Offset):toBe(before)
				world.engine.heartbeat:Fire(0.1)
				Verify.expect(panel.Size.Y.Offset > before):toBe(true)
				world.gui.ReducedMotionEnabled = true
				Verify.expect(panel.Size.Y.Offset):toBe(684)
				Verify.expect((find(world.screen, "KeptContent"))):toBe(content)
				world.stop()
			end,
		})

		verifyHarness:case("fades native tab layers with Compose and reveals an offscreen selected tab", {
			id = "native_navigation::native navigation controls::fades native tab layers with Compose and reveals an offscreen selected tab",
			run = function()
				local selected = Compose.cell("a")
				local world = setup(function(UI: FacetControls)
					return UI.TabView({
						selection = selected,
						placement = "topBar" :: "topBar",
						transition = { seconds = 0.2 },
						tabs = {
							{
								id = "a",
								content = function(): Instance
									return UI.Button "AContent" { label = "A" }
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "b",
								content = function(): Instance
									return UI.Button "BContent" { label = "B" }
								end,
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local bar = find(world.screen, "Tabs")
				Verify.expect(find(world.screen, "Content").Position.Y.Offset > bar.Size.Y.Offset):toBe(true)
				bar.AbsoluteSize = world.engine.types.Vector2.new(100, 44)
				local b = find(bar, "b")
				b.AbsolutePosition = world.engine.types.Vector2.new(160, 0)
				b.AbsoluteSize = world.engine.types.Vector2.new(80, 44)
				selected:set("b")
				Verify.expect(bar.CanvasPosition.X):toBe(140)
				local panel = fadeKit.layer(find(world.screen, "BContent"))
				Verify.expect(panel.ClassName):toBe("Frame")
				world.engine.heartbeat:Fire(0.2)
				Verify.expect((fadeKit.of(panel))):toBe(0)
				selected:set("a")
				Verify.expect(panel.Interactable):toBe(false)
				world.gui.ReducedMotionEnabled = true
				world.engine.heartbeat:Fire(0.2)
				Verify.expect((fadeKit.of(fadeKit.layer(find(world.screen, "AContent"))))):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("clears bound alert errors and turns native page animation off for reduced motion", {
			id = "native_navigation::native navigation controls::clears bound alert errors and turns native page animation off for reduced motion",
			run = function()
				local shown, errorValue: FixtureComposeTypes.Cell<string?>, page =
					Compose.cell(true), cells.optionalString("Oops"), Compose.cell("a")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Alert({ isPresented = shown, error = errorValue }) :: unknown,
						UI.PageView({
							selection = page,
							pages = {
								{
									id = "a",
									content = function(): Instance
										return Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "b",
									content = function(): Instance
										return Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						}),
					})
				end)
				find(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((errorValue:peek())):toBe(nil)
				world.gui.ReducedMotionEnabled = true
				Verify.expect(find(world.screen, "PagesLayout").Animated):toBe(false)
				world.stop()
			end,
		})
		verifyHarness:case("lets one arrow from the anchor reach a callout plate and B dismiss it back to the anchor", {
			id = "native_navigation::native navigation controls::lets one arrow from the anchor reach a callout plate and B dismiss it back to the anchor",
			run = function()
				local reasons = {}
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame({
						anchor :: unknown,
						UI.Callout({
							anchor = anchor :: GuiObject,
							edge = "bottom" :: "bottom",
							title = "New",
							onRetire = function(reason)
								table.insert(reasons, reason)
							end,
						}),
					})
				end)
				local V = world.engine.types.Vector2
				world.screen.AbsoluteSize = V.new(960, 720)
				local anchor, panel = find(world.screen, "Anchor"), find(world.screen, "CalloutPanel")
				anchor.AbsolutePosition, anchor.AbsoluteSize = V.new(100, 100), V.new(200, 44)
				panel.AbsolutePosition, panel.AbsoluteSize = V.new(100, 160), V.new(280, 120)
				world.settle()
				local dismiss = find(world.screen, "Dismiss")
				world.gui.SelectedObject = anchor
				Verify.expect(anchor.NextSelectionDown):toBe(dismiss)
				world.gui.SelectedObject = dismiss
				local back
				for _, node in world.screen:GetDescendants() do
					if node:IsA("InputContext") and node.Enabled then
						for _, action in node:GetChildren() do
							for _, binding in action:GetChildren() do
								if
									binding:IsA("InputBinding")
									and binding.KeyCode == world.engine.types.Enum.KeyCode.ButtonB
								then
									back = action
								end
							end
						end
					end
				end
				Verify.expect(back ~= nil):toBe(true)
				back.Pressed:Fire()
				Verify.expect(reasons[1]):toBe("dismissed")
				world.settle()
				Verify.expect(world.gui.SelectedObject):toBe(anchor)
				Verify.expect(anchor.NextSelectionDown):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("restores only the anchor link the callout set and leaves an app's own link", {
			id = "native_navigation::native navigation controls::restores only the anchor link the callout set and leaves an app's own link",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame({
						anchor :: unknown,
						UI.Button "Own" { label = "Own" },
						UI.Callout({
							anchor = anchor :: GuiObject,
							edge = "bottom" :: "bottom",
							title = "New",
							onRetire = function() end,
						}),
					})
				end)
				local V = world.engine.types.Vector2
				world.screen.AbsoluteSize = V.new(960, 720)
				local anchor, panel = find(world.screen, "Anchor"), find(world.screen, "CalloutPanel")
				local own = find(world.screen, "Own")
				anchor.AbsolutePosition, anchor.AbsoluteSize = V.new(100, 300), V.new(200, 44)
				panel.AbsolutePosition, panel.AbsoluteSize = V.new(100, 360), V.new(280, 120)
				world.settle()
				Verify.expect(anchor.NextSelectionDown):toBe(find(world.screen, "Dismiss"))
				anchor.NextSelectionDown = own
				panel.AbsolutePosition = V.new(100, 160)
				world.settle()
				Verify.expect(anchor.NextSelectionDown):toBe(own)
				Verify.expect(anchor.NextSelectionUp):toBe(find(world.screen, "Dismiss"))
				local dismiss = find(world.screen, "Dismiss")
				local holder = dismiss.Parent
				dismiss.Parent = nil
				world.settle()
				Verify.expect(anchor.NextSelectionUp):toBe(nil)
				local fresh = world.engine.new("TextButton")
				fresh.Name = "Fresh"
				fresh.Parent = holder
				world.settle()
				Verify.expect(anchor.NextSelectionUp):toBe(fresh)
				world.stop()
				Verify.expect(anchor.NextSelectionDown):toBe(own)
				Verify.expect(anchor.NextSelectionUp):toBe(nil)
			end,
		})

		verifyHarness:case("keeps measured callout arrows outside automatic content bounds", {
			id = "native_navigation::native navigation controls::keeps measured callout arrows outside automatic content bounds",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame({
						anchor :: unknown,
						UI.Callout({
							anchor = anchor :: GuiObject,
							edge = "top" :: "top",
							onRetire = function() end,
							content = function(): Instance
								return Host.TextLabel "TipContent" {
									Text = "Start from a prompt, then edit it before you send.",
									TextWrapped = true,
									Size = engine.types.UDim2.new(1, 0, 0, 0),
									AutomaticSize = engine.types.Enum.AutomaticSize.Y,
								}
							end,
						}),
					})
				end)
				local V = world.engine.types.Vector2
				world.screen.AbsoluteSize = V.new(960, 720)
				local anchor, panel, arrow =
					find(world.screen, "Anchor"), find(world.screen, "CalloutPanel"), find(world.screen, "Arrow")
				anchor.AbsolutePosition = V.new(160, 560)
				anchor.AbsoluteSize = V.new(240, 44)
				Verify.expect(panel.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.Y)
				Verify.expect(panel.Size.Y.Scale):toBe(0)
				Verify.expect(panel.Size.Y.Offset):toBe(0)
				Verify.expect((arrow:IsDescendantOf(panel))):toBe(false)
				Verify.expect(arrow.Parent):toBe(panel.Parent)
				Verify.expect((arrow:HasTag("facet-tail"))):toBe(true)
				Verify.expect(arrow.Rotation):toBe(45)
				Verify.expect(arrow.ZIndex < panel.ZIndex):toBe(true)
				Verify.expect((find(world.screen, "ArrowSeam"))):toBe(nil)
				local outline = find(world.screen, "Outline")
				Verify.expect(outline.ClassName):toBe("Path2D")
				Verify.expect(outline.Parent.Name):toBe("OutlineBoundary")
				Verify.expect(find(world.screen, "OutlineFade").Parent):toBe(panel.Parent)
				Verify.expect(outline.Closed):toBe(true)
				Verify.expect((outline:HasTag("facet-outline"))):toBe(true)
				Verify.expect((panel:HasTag("facet-outlined"))):toBe(true)
				world.settle()
				for _, height in { 96, 128, 96 } do
					panel.AbsoluteSize = V.new(280, height)
					local _, top = corner(panel)
					Verify.expect((near(top, 560 - height - 8 - LIFT))):toBe(true)
					Verify.expect((near(arrow.Position.Y.Offset, 560 - 8 - LIFT))):toBe(true)
					local points = outline:GetControlPoints()
					Verify.expect(#points):toBe(11)
					local lowest = 0
					for _, point in points do
						lowest = math.max(lowest, point.Position.Y.Scale * height)
					end
					Verify.expect((near(lowest, height + arrow.Size.X.Offset * math.sqrt(2) / 2))):toBe(true)
				end
				panel.AbsoluteSize = V.new(30, 96)
				local previous = math.huge
				for _, point in outline:GetControlPoints() do
					if point.Position.Y.Scale * 96 >= 96 - 0.01 then
						local x = point.Position.X.Scale * 30
						Verify.expect(`short side runs one way {x <= previous + 0.01} at {x}`)
							:toBe(`short side runs one way true at {x}`)
						previous = x
					end
				end
				local first = outline:GetControlPoints()[1]
				Verify.expect(math.abs(first.Position.X.Scale * 30 - 12) < 0.01):toBe(true)
				panel.AbsoluteSize = V.new(280, 96)
				anchor.AbsolutePosition = V.new(0, 560)
				anchor.AbsoluteSize = V.new(8, 44)
				local points = outline:GetControlPoints()
				local radius = points[1].Position.X.Scale * 280
				local tip, depth = 0, 0
				for _, point in points do
					local y = point.Position.Y.Scale * 96
					if y > depth then
						depth, tip = y, point.Position.X.Scale * 280
					end
				end
				local half = depth - 96
				Verify.expect(`tail clears the corner arc by a tail width: {tip - radius - half >= half - 0.01}`)
					:toBe("tail clears the corner arc by a tail width: true")
				anchor.Visible = false
				Verify.expect((find(world.screen, "Arrow"))):toBe(nil)
				Verify.expect((find(world.screen, "CalloutPanel"))):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("moves a top callout below its anchor when only the bottom has room", {
			id = "native_navigation::native navigation controls::moves a top callout below its anchor when only the bottom has room",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame({
						anchor :: unknown,
						UI.Callout({
							anchor = anchor :: GuiObject,
							edge = "top" :: "top",
							onRetire = function() end,
							content = function(): Instance
								return UI.Text({ text = "Tip" })
							end,
						}),
					})
				end)
				local V = world.engine.types.Vector2
				world.screen.AbsoluteSize = V.new(844, 311)
				local anchor, panel, arrow =
					find(world.screen, "Anchor"), find(world.screen, "CalloutPanel"), find(world.screen, "Arrow")
				anchor.AbsolutePosition = V.new(8, 18)
				anchor.AbsoluteSize = V.new(109, 44)
				panel.AbsoluteSize = V.new(280, 106)
				world.settle()
				Verify.expect(materialize.of(panel).Scale):toBe(1)
				Verify.expect((near(select(2, corner(panel)), 18 + 44 + 8 + LIFT))):toBe(true)
				Verify.expect((near(arrow.Position.Y.Offset, 18 + 44 + 8 + LIFT))):toBe(true)
				anchor.AbsolutePosition = V.new(8, 200)
				Verify.expect((near(select(2, corner(panel)), 200 - 106 - 8 - LIFT))):toBe(true)
				anchor.AbsolutePosition = V.new(8, 100)
				panel.AbsoluteSize = V.new(280, 250)
				Verify.expect((near(select(2, corner(panel)), 8))):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case(
			"renders disclosure appearances and collapsible summaries with native assets and close policy",
			{
				id = "native_navigation::native navigation controls::renders disclosure appearances and collapsible summaries with native assets and close policy",
				run = function()
					local expanded, image = Compose.cell(false), Compose.cell("rbxassetid://1")
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.DisclosureGroup "Disclosure" {
								label = "Details",
								appearance = "divided" :: "divided",
								chevronPosition = "leading" :: "leading",
								expanded = Compose.cell(true),
								content = function(): Instance
									return UI.Text({ text = "Details" })
								end,
							} :: unknown,
							UI.CollapsibleView "Summary" {
								label = "Summary",
								image = image,
								expanded = expanded,
								dismissButton = false,
								content = function(): Instance
									return UI.Button "DetailsAction" { label = "Details" }
								end,
							},
						})
					end)
					Verify.expect(find(find(world.screen, "Disclosure"), "LeadingIcon") ~= nil):toBe(true)
					Verify.expect(find(find(world.screen, "Disclosure"), "Divider") ~= nil):toBe(true)
					local summary = find(world.screen, "Summary")
					image:set("rbxassetid://2")
					Verify.expect(find(summary, "Image").Image):toBe("rbxassetid://2")
					summary.Activated:Fire()
					Verify.expect((find(world.screen, "Close"))):toBe(nil)
					world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
					Verify.expect(find(world.screen, "Close") ~= nil):toBe(true)
					find(world.screen, "Close").Activated:Fire()
					Verify.expect((expanded:peek())):toBe(false)
					Verify.expect((find(world.screen, "DetailsAction"))):toBe(nil)
					Verify.expect((find(world.screen, "Summary"))):toBe(summary)
					world.stop()
				end,
			}
		)

		verifyHarness:case("renders sidebar sections and collapsed tab destinations through the shared menu", {
			id = "native_navigation::native navigation controls::renders sidebar sections and collapsed tab destinations through the shared menu",
			run = function()
				local selected = Compose.cell("a")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.TabView "Sidebar" {
							selection = selected,
							placement = "sidebar" :: "sidebar",
							sections = { { id = "s", label = "Section" } },
							tabs = {
								{
									id = "a",
									section = "s",
									content = function(): Instance
										return Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "b",
									section = "s",
									content = function(): Instance
										return Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						} :: unknown,
						UI.TabView "Collapsed" {
							selection = selected,
							style = "collapsible" :: "collapsible",
							tabs = {
								{
									id = "a",
									label = "Alpha",
									content = function(): Instance
										return Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "b",
									label = "Beta",
									content = function(): Instance
										return Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						},
					})
				end)
				Verify.expect(find(find(world.screen, "Sidebar"), "Section").Text):toBe("Section")
				local collapsed = find(world.screen, "Collapsed")
				Verify.expect(find(collapsed, "Tabs").Visible):toBe(false)
				find(find(collapsed, "TabsMenu"), "Trigger").Activated:Fire()
				find(find(world.screen, "MenuPanel"), "b").Activated:Fire()
				Verify.expect((selected:peek())):toBe("b")
				Verify.expect(find(find(collapsed, "TabsMenu"), "Trigger").Text):toBe("Beta")
				world.stop()
			end,
		})

		verifyHarness:case("closes menu and picker presentations when native ancestors become unavailable", {
			id = "native_navigation::native navigation controls::closes menu and picker presentations when native ancestors become unavailable",
			run = function()
				local selected, opened = Compose.cell("a"), Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Surface" {
						UI.Picker({
							selected = selected,
							style = "menu" :: "menu",
							isPresented = opened,
							options = {
								{ value = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
								{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
							},
						}),
					}
				end)
				opened:set(true)
				local row = find(find(world.screen, "MenuPanel"), "b")
				find(world.screen, "Surface").Interactable = false
				Verify.expect((opened:peek())):toBe(false)
				Verify.expect((find(world.screen, "MenuPanel"))):toBe(nil)
				row.Activated:Fire()
				Verify.expect((selected:peek())):toBe("a")
				find(world.screen, "Surface").Interactable = true
				find(world.screen, "Trigger").Activated:Fire()
				Verify.expect((opened:peek())):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("keeps panel art outside native layout and exposes alert artwork", {
			id = "native_navigation::native navigation controls::keeps panel art outside native layout and exposes alert artwork",
			run = function()
				local package = require("../src/ui/themes")(Compose).neutralPackage()
				assert(package.assets).panel = { content = "rbxassetid://42" }
				assert(package.chrome).panel = {
					kind = "layered" :: "layered",
					layers = { { kind = "fill" :: "fill", asset = "panel" } :: FixtureThemeTypes.SkinLayer },
				}
				local alert, sheet = Compose.cell(true), Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Alert({ isPresented = alert, severity = "critical" :: "critical", title = "Danger" }) :: unknown,
						UI.Sheet({
							isPresented = sheet,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return Host.Frame({})
							end,
						}),
					})
				end, { theme = package })
				local panel = find(world.screen, "AlertPanel")
				Verify.expect(panel.BackgroundTransparency):toBe(0)
				Verify.expect((panel:HasTag("facet-panel"))):toBe(true)
				Verify.expect(find(panel, "AlertIcon").Image ~= ""):toBe(true)
				local alertArt = find(panel, "panel1")
				Verify.expect(alertArt.Image):toBe("rbxassetid://42")
				alert:set(false)
				sheet:set(true)
				world.settle()
				panel = find(world.screen, "SheetPanel")
				Verify.expect(panel.BackgroundTransparency):toBe(0)
				Verify.expect((alertArt:isDestroyed())):toBe(true)
				local skin, boundary = find(panel, "Skin"), find(panel, "SkinBoundary")
				local bounds, art = skin.Parent, find(skin, "panel1")
				Verify.expect(art.Image):toBe("rbxassetid://42")
				Verify.expect((panel:FindFirstChildWhichIsA("UIGridStyleLayout"))):toBeNil()
				Verify.expect(boundary.Parent):toBe(panel:FindFirstChild("Fade"))
				Verify.expect(bounds.Parent):toBe(boundary)
				Verify.expect(boundary.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				Verify.expect(boundary.Size.X.Offset):toBe(1)
				Verify.expect(boundary.Size.Y.Offset):toBe(1)
				Verify.expect(boundary.Position.X.Scale):toBe(1)
				Verify.expect(boundary.Position.Y.Scale):toBe(1)
				Verify.expect(bounds.AnchorPoint):toBe(world.engine.types.Vector2.new(1, 1))
				panel.AbsoluteSize = world.engine.types.Vector2.new(360, 240)
				boundary.AbsoluteSize = world.engine.types.Vector2.new(2, 2)
				Verify.expect(bounds.Size.X.Offset):toBe(180)
				Verify.expect(bounds.Size.Y.Offset):toBe(120)
				panel.AbsoluteSize = world.engine.types.Vector2.new(200, 120)
				Verify.expect(bounds.Size.X.Offset):toBe(100)
				Verify.expect(bounds.Size.Y.Offset):toBe(60)
				world.stop()
				Verify.expect((art:isDestroyed())):toBe(true)
				Verify.expect((boundary:isDestroyed())):toBe(true)
			end,
		})

		verifyHarness:case("animates alerts from native sources and reclaims interrupted Compose presence", {
			id = "native_navigation::native navigation controls::animates alerts from native sources and reclaims interrupted Compose presence",
			run = function()
				local shown = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local source = UI.Button "Source" { label = "Open" }
					return Host.Frame({
						source :: unknown,
						UI.Alert({
							isPresented = shown,
							title = "Detail",
							transition = { source = source :: GuiObject, seconds = 0.2 },
						}),
					})
				end)
				local source = find(world.screen, "Source")
				source.AbsolutePosition = world.engine.types.Vector2.new(20, 30)
				source.AbsoluteSize = world.engine.types.Vector2.new(100, 60)
				shown:set(true)
				local panel = find(world.screen, "AlertPanel")
				Verify.expect(panel.Position.X.Offset):toBe(70)
				Verify.expect(panel.Position.Y.Offset):toBe(60)
				Verify.expect((fadeKit.of(panel))):toBe(1)
				find(world.screen, "AlertModal").AbsoluteSize = world.engine.types.Vector2.new(800, 600)
				world.engine.heartbeat:Fire(0.2)
				Verify.expect(panel.Position.X.Offset):toBe(400)
				Verify.expect((find(panel, "PresentationScale"))):toBeNil()
				shown:set(false)
				world.engine.heartbeat:Fire(0.1)
				Verify.expect((find(world.screen, "AlertPanel"))):toBe(panel)
				shown:set(true)
				Verify.expect((find(world.screen, "AlertPanel"))):toBe(panel)
				world.engine.heartbeat:Fire(0.2)
				Verify.expect((fadeKit.of(panel))):toBe(0)
				shown:set(false)
				world.engine.heartbeat:Fire(0.2)
				Verify.expect((find(world.screen, "AlertPanel"))):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("expands a source rectangle into full screen and reverses the same Compose-owned snapshot", {
			id = "native_navigation::native navigation controls::expands a source rectangle into full screen and reverses the same Compose-owned snapshot",
			run = function()
				local shown = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local camera = Host.Camera "PreviewCamera" {}
					local externalCamera = Host.Camera "ExternalCamera" {}
					local source = Host.Frame "Card" {
						Host.UICorner({ CornerRadius = engine.types.UDim.new(0, 12) }) :: unknown,
						Host.ViewportFrame "Scene" {
							CurrentCamera = Compose.static(camera),
							Host.Camera "PreviewCamera" { Archivable = false } :: unknown,
							camera,
							Host.WorldModel "World" {},
						},
						Host.ViewportFrame "OtherScene" { CurrentCamera = Compose.static(externalCamera) },
						UI.Button "Open" { label = "Open" },
						Host.UIDragDetector "CardDrag" {},
					}
					return Host.Frame({
						source :: unknown,
						externalCamera,
						UI.Alert({
							isPresented = shown,
							title = "Detail",
							surface = "fullScreen" :: "fullScreen",
							transition = { source = source :: GuiObject, seconds = 0.4 },
						}),
					})
				end)
				local V2 = world.engine.types.Vector2
				local source = find(world.screen, "Card")
				local originalParent = source.Parent
				source.AbsolutePosition = V2.new(20, 30)
				source.AbsoluteSize = V2.new(120, 80)
				shown:set(true)
				local panel = find(world.screen, "AlertPanel")
				local modal = find(world.screen, "AlertModal")
				do
					for _, d in world.screen:GetDescendants() do
						if d:GetAttribute("FacetError") then
							error(d:GetAttribute("FacetError"))
						end
					end
				end
				modal.AbsolutePosition = V2.new(10, 10)
				modal.AbsoluteSize = V2.new(800, 600)
				Verify.expect(panel:HasTag("facet-pane")):toBe(true)
				Verify.expect(panel:HasTag("facet-panel")):toBe(false)
				local snapshot = find(panel, "SourceSnapshot")
				Verify.expect(snapshot ~= nil):toBe(true)
				Verify.expect(snapshot == source):toBe(false)
				Verify.expect(snapshot.Interactable):toBe(false)
				Verify.expect(find(snapshot, "Open").Selectable):toBe(false)
				Verify.expect(find(snapshot, "CardDrag").Enabled):toBe(false)
				Verify.expect(find(snapshot, "Scene").CurrentCamera):toBe(find(snapshot, "PreviewCamera"))
				Verify.expect(find(snapshot, "Scene").CurrentCamera == find(source, "Scene").CurrentCamera):toBe(false)
				Verify.expect(find(snapshot, "OtherScene").CurrentCamera):toBe(find(world.screen, "ExternalCamera"))
				Verify.expect((find(snapshot, "ExternalCamera"))):toBe(nil)
				Verify.expect(panel.Size.X.Offset):toBe(120)
				Verify.expect(panel.Size.Y.Offset):toBe(80)
				Verify.expect(panel.Position.X.Offset):toBe(10)
				Verify.expect(panel.Position.Y.Offset):toBe(20)
				Verify.expect((fadeKit.of(panel))):toBe(0)
				Verify.expect(panel.ClipsDescendants):toBe(true)
				Verify.expect(find(panel, "AlertLayout").ClassName):toBe("Frame")
				Verify.expect(find(panel, "AlertLayout").Size):toBe(world.engine.types.UDim2.fromOffset(800, 600))
				Verify.expect(snapshot.Size):toBe(world.engine.types.UDim2.fromOffset(120, 80))
				Verify.expect((fadeKit.of(find(panel, "SourcePreview")))):toBe(0)
				world.engine.heartbeat:Fire(0.1)
				local width, height = panel.Size.X.Offset, panel.Size.Y.Offset
				Verify.expect(width > 120 and width < 800):toBe(true)
				Verify.expect(height > 80 and height < 600):toBe(true)
				Verify.expect(math.abs((width - 120) / 680 - (height - 80) / 520) < 0.0001):toBe(true)
				Verify.expect(find(panel, "AlertLayout").Size):toBe(world.engine.types.UDim2.fromOffset(800, 600))
				Verify.expect(find(panel, "AlertLayout").ClassName):toBe("Frame")
				Verify.expect(snapshot.Size):toBe(world.engine.types.UDim2.fromOffset(120, 80))
				shown:set(false)
				Verify.expect(panel.Size.X.Offset):toBe(width)
				world.engine.heartbeat:Fire(0.05)
				Verify.expect(panel.Size.X.Offset < width):toBe(true)
				local returningWidth = panel.Size.X.Offset
				shown:set(true)
				Verify.expect((find(world.screen, "AlertPanel"))):toBe(panel)
				Verify.expect(panel.Size.X.Offset):toBe(returningWidth)
				world.engine.heartbeat:Fire(0.4)
				Verify.expect(panel.Position.X.Offset):toBe(0)
				Verify.expect(panel.Position.Y.Offset):toBe(0)
				Verify.expect(panel.Size.X.Offset):toBe(800)
				Verify.expect(panel.Size.Y.Offset):toBe(600)
				Verify.expect(find(panel, "SourcePreview").Visible):toBe(false)
				Verify.expect(source.Parent):toBe(originalParent)
				shown:set(false)
				world.engine.heartbeat:Fire(0.4)
				Verify.expect((snapshot:isDestroyed())):toBe(true)
				Verify.expect((find(world.screen, "AlertPanel"))):toBe(nil)
				Verify.expect(source.Parent):toBe(originalParent)
				Verify.expect((source:isDestroyed())):toBe(false)
				Verify.expect(find(source, "Scene").CurrentCamera.Parent):toBe(find(source, "Scene"))
				Verify.expect((find(world.screen, "ExternalCamera"):isDestroyed())):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("makes full-screen source transitions immediate under native reduced motion", {
			id = "native_navigation::native navigation controls::makes full-screen source transitions immediate under native reduced motion",
			run = function()
				local shown = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine, gui)
					gui.ReducedMotionEnabled = true
					local source = UI.Button "Card" { label = "Card" }
					return Host.Frame({
						source :: unknown,
						UI.Alert({
							isPresented = shown,
							surface = "fullScreen" :: "fullScreen",
							transition = { source = source :: GuiObject, seconds = 0.4 },
						}),
					})
				end)
				shown:set(true)
				local panel = find(world.screen, "AlertPanel")
				find(world.screen, "AlertModal").AbsoluteSize = world.engine.types.Vector2.new(390, 720)
				Verify.expect(panel.Size.X.Offset):toBe(390)
				Verify.expect(panel.Size.Y.Offset):toBe(720)
				Verify.expect(panel.Position.X.Offset):toBe(0)
				Verify.expect(find(panel, "AlertLayout").ClassName):toBe("Frame")
				Verify.expect(find(panel, "SourcePreview").Visible):toBe(false)
				shown:set(false)
				Verify.expect((find(world.screen, "AlertPanel"))):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("resets the mounted callout showcase without replacing anchor identities", {
			id = "native_navigation::native navigation controls::resets the mounted callout showcase without replacing anchor identities",
			run = function()
				local built
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					built = require("../examples/gallery/scenarios/callout").build({
						UI = UI,
						Host = Host,
						Compose = Compose,
						types = engine.types,
					})
					return built.screen()
				end)
				local anchor = find(world.screen, "Plus")
				built.steps.show()
				Verify.expect(built.report().tip.state):toBe("showing")
				find(world.screen, "Dismiss").Activated:Fire()
				Verify.expect(built.report().tip.state):toBe("retired")
				built.steps.reset()
				Verify.expect((find(world.screen, "Plus"))):toBe(anchor)
				built.steps.show()
				Verify.expect(built.report().tip.state):toBe("showing")
				world.stop()
			end,
		})
		verifyHarness:case(
			"keeps filtered multiple selections and reactive row descriptions through source replacement",
			{
				id = "native_navigation::native navigation controls::keeps filtered multiple selections and reactive row descriptions through source replacement",
				run = function()
					local selected, query, opened =
						Compose.cell({ a = true } :: { [string]: boolean }), Compose.cell(""), Compose.cell(true)
					local options = Compose.cell(
						{ { value = "a", label = "Alpha" }, { value = "b", label = "Beta", enabled = false } } :: { Navigation.PickerOption<string> }
					)
					local world = setup(function(UI: FacetControls)
						return UI.Picker({
							selected = selected,
							multiple = true :: true,
							required = true,
							style = "menu" :: "menu",
							options = options,
							query = query,
							isPresented = opened,
						})
					end)
					local first = find(find(world.screen, "MenuPanel"), "a")
					first.Activated:Fire()
					Verify.expect(selected:peek().a):toBe(true)
					query:set("missing")
					Verify.expect(selected:peek().a):toBe(true)
					options:set({
						{ value = "a", label = "Alpha", description = "Added" } :: Navigation.PickerOption<string>,
						{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
					})
					query:set("")
					local row = find(find(world.screen, "MenuPanel"), "a")
					Verify.expect(find(row, "Description").Text):toBe("Added")
					options:set({
						{ value = "a", label = "Alpha", description = "Changed" } :: Navigation.PickerOption<string>,
						{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
					})
					Verify.expect((find(find(world.screen, "MenuPanel"), "a"))):toBe(row)
					Verify.expect(find(row, "Description").Text):toBe("Changed")
					find(find(world.screen, "MenuPanel"), "b").Activated:Fire()
					Verify.expect(selected:peek().b):toBe(true)
					Verify.expect((opened:peek())):toBe(true)
					options:set({ { value = "b", label = "Coast" } })
					Verify.expect(selected:peek().a):toBe(true)
					Verify.expect(find(world.screen, "Trigger").Text):toBe("Coast")
					world.stop()
				end,
			}
		)
		verifyHarness:case("forgives near-miss backdrop taps and closes only the top native modal", {
			id = "native_navigation::native navigation controls::forgives near-miss backdrop taps and closes only the top native modal",
			run = function()
				local outer, inner = Compose.cell(true), Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Sheet({
							isPresented = outer,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return UI.Button({ label = "Outer" })
							end,
						}) :: unknown,
						UI.Sheet({
							isPresented = inner,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return UI.Button({ label = "Inner" })
							end,
						}),
					})
				end)
				local panel = find(world.screen, "SheetPanel")
				panel.AbsolutePosition = world.engine.types.Vector2.new(100, 100)
				panel.AbsoluteSize = world.engine.types.Vector2.new(200, 200)
				local backdrop = find(world.screen, "DismissOutside")
				backdrop.Activated:Fire({ Position = world.engine.types.Vector2.new(90, 150) })
				Verify.expect((outer:peek())):toBe(true)
				inner:set(true)
				backdrop.Activated:Fire({ Position = world.engine.types.Vector2.new(50, 150) })
				Verify.expect((outer:peek())):toBe(true)
				local top
				for _, node in world.screen:GetDescendants() do
					if node.Name == "DismissOutside" and node ~= backdrop then
						top = node
					end
				end
				Verify.expect(top ~= nil):toBe(true)
				top.Activated:Fire({ Position = world.engine.types.Vector2.new(0, 0) })
				Verify.expect((inner:peek())):toBe(false)
				Verify.expect((outer:peek())):toBe(true)
				backdrop.Activated:Fire({ Position = world.engine.types.Vector2.new(50, 150) })
				Verify.expect((outer:peek())):toBe(false)
				world.stop()
			end,
		})
		verifyHarness:case("keeps the navigation handoff out of neighbouring scroll panes", {
			id = "native_navigation::native navigation controls::keeps the navigation handoff out of neighbouring scroll panes",
			run = function()
				for _, mode in
					{ "normal", "limited", "none", "false", "custom" } :: { "custom" | "false" | "limited" | "none" | "normal" }
				do
					local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.ScrollView "Neighbour" { UI.Button "Outside" { label = "Outside" } } :: unknown,
							UI.NavigationStack({
								path = path,
								transition = if mode == "false"
									then false :: false
									elseif mode == "custom" then { seconds = 0.2 }
									else nil,
								root = {
									content = function(): Instance
										return UI.VStack {
											UI.Button "RootAction" { label = "Root" } :: unknown,
											UI.Button "RootNext" { label = "Next" },
										}
									end,
								} :: NavigationFixtures.NavigationDestination<any>,
								destinations = {
									detail = {
										content = function(): Instance
											return UI.Button "DetailAction" { label = "Detail" }
										end,
									} :: NavigationFixtures.NavigationDestination<any>,
								},
							}),
						})
					end, { motionLevel = if mode == "none" then "none" else "normal" })
					if mode == "limited" then
						world.gui.ReducedMotionEnabled = true
					end
					local stack = find(world.screen, "NavigationStack")
					local root = find(stack, "@root")
					local original = find(root, "RootAction")
					world.gui.SelectedObject = original
					local outside, inactive = 0, 0
					local selection = world.gui:GetPropertyChangedSignal("SelectedObject"):Connect(function()
						local selected = world.gui.SelectedObject
						if selected and selected:IsDescendantOf(find(world.screen, "Neighbour")) then
							outside += 1
						end
					end)
					local function watch(panel)
						return panel:GetPropertyChangedSignal("Interactable"):Connect(function()
							local selected = world.gui.SelectedObject
							if not panel.Interactable and selected and selected:IsDescendantOf(panel) then
								inactive += 1
							end
						end)
					end
					local rootWatch = watch(root)
					path:set({ { id = "detail" } })
					world.settle()
					local detail = find(stack, "detail")
					Verify.expect((world.gui.SelectedObject:IsDescendantOf(detail))):toBe(true)
					local detailWatch = watch(detail)
					path:set({})
					world.settle()
					Verify.expect(world.gui.SelectedObject):toBe(original)
					path:set({ { id = "detail" } })
					world.engine.heartbeat:Fire(1 / 60)
					path:set({})
					world.settle()
					Verify.expect(world.gui.SelectedObject):toBe(original)
					original.Visible = false
					Verify.expect(world.gui.SelectedObject):toBe(find(root, "RootNext"))
					Verify.expect(outside):toBe(0)
					Verify.expect(inactive):toBe(0)
					selection:Disconnect()
					rootWatch:Disconnect()
					detailWatch:Disconnect()
					world.stop()
				end
			end,
		})

		verifyHarness:case("slides pages with parallax and restores selection after push and pop settle", {
			id = "native_navigation::native navigation controls::slides pages with parallax and restores selection after push and pop settle",
			run = function()
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
				local world = setup(function(UI: FacetControls)
					return UI.NavigationStack({
						path = path,
						root = {
							title = "Root",
							content = function(): Instance
								return UI.Button "RootAction" { label = "Root" }
							end,
						} :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							detail = {
								title = "Detail",
								content = function(): Instance
									return UI.Button "DetailAction" { label = "Detail" }
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
						},
					})
				end)
				local stack = find(world.screen, "NavigationStack")
				local root = find(stack, "@root")
				world.gui.SelectedObject = find(root, "RootAction")
				path:set({ { id = "detail" } })
				local detail = find(stack, "detail")
				Verify.expect(detail.Position.X.Scale):toBe(1)
				Verify.expect(detail.Interactable):toBe(true)
				Verify.expect(root.Interactable):toBe(false)
				Verify.expect(world.gui.SelectedObject):toBe(nil)
				local previous, elapsed = 1, 0
				while elapsed < 0.35 do
					world.engine.heartbeat:Fire(1 / 60)
					elapsed += 1 / 60
					local front, back = detail.Position.X.Scale, root.Position.X.Scale
					Verify.expect(front < previous):toBe(true)
					Verify.expect(back):toBeCloseTo(-0.3 * (1 - front), 1e-6)
					Verify.expect(root.Visible):toBe(true)
					Verify.expect(root.ClipsDescendants):toBe(true)
					Verify.expect(stack.ClipsDescendants):toBe(true)
					Verify.expect(find(root, "Page").Size):toBe(world.engine.types.UDim2.fromScale(1, 1))
					Verify.expect(find(root, "Dim").BackgroundTransparency):toBeCloseTo(1 - 0.1 * (1 - front), 1e-6)
					previous = front
				end
				Verify.expect(previous < 0.01):toBe(true)
				world.settle()
				Verify.expect(detail.Position.X.Scale):toBe(0)
				Verify.expect((world.gui.SelectedObject:IsDescendantOf(detail))):toBe(true)
				Verify.expect(root.Visible):toBe(false)
				Verify.expect((find(root, "Dim"))):toBe(nil)
				Verify.expect(stack.ClipsDescendants):toBe(false)
				path:set({})
				Verify.expect(stack.ClipsDescendants):toBe(true)
				Verify.expect(detail.Position.X.Scale):toBe(0)
				Verify.expect(root.Visible):toBe(true)
				Verify.expect((detail:isDestroyed())):toBe(false)
				Verify.expect(detail.Interactable):toBe(false)
				Verify.expect(root.Interactable):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(nil)
				previous = 0
				for _ = 1, 12 do
					world.engine.heartbeat:Fire(1 / 60)
					local front = detail.Position.X.Scale
					Verify.expect(front > previous):toBe(true)
					Verify.expect(root.Position.X.Scale):toBeCloseTo(-0.3 * (1 - front), 1e-6)
					Verify.expect(
						world.gui.SelectedObject == nil or not world.gui.SelectedObject:IsDescendantOf(detail)
					)
						:toBe(true)
					previous = front
				end
				world.settle()
				Verify.expect((detail:isDestroyed())):toBe(true)
				Verify.expect(world.gui.SelectedObject.Name):toBe("RootAction")
				Verify.expect(root.Position.X.Scale):toBe(0)
				Verify.expect(root.Visible):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case(
			"pushes and pops without travel under reduced motion (a fade) or a false transition (none)",
			{
				id = "native_navigation::native navigation controls::pushes and pops without travel under reduced motion (a fade) or a false transition (none)",
				run = function()
					for _, mode in { "reduced", "false" } :: { "false" | "reduced" } do
						local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
						local world = setup(function(UI: FacetControls, Host: RobloxHost)
							return UI.NavigationStack({
								path = path,
								transition = if mode == "false" then false :: false else nil,
								root = { title = "Root", content = Host.Frame "RootBody" {} } :: NavigationFixtures.NavigationDestination<any>,
								destinations = {
									detail = { title = "Detail", content = Host.Frame "DetailBody" {} } :: NavigationFixtures.NavigationDestination<any>,
								},
							})
						end)
						world.gui.ReducedMotionEnabled = mode == "reduced"
						local stack = find(world.screen, "NavigationStack")
						local root = find(stack, "@root")
						path:set({ { id = "detail" } })
						local detail = find(stack, "detail")
						Verify.expect(detail.Position.X.Scale):toBe(0)
						Verify.expect(root.Visible):toBe(false)
						Verify.expect(stack.ClipsDescendants):toBe(false)
						world.engine.heartbeat:Fire(1 / 60)
						if mode == "reduced" then
							Verify.expect(detail.Position.X.Scale):toBe(0)
							world.engine.heartbeat:Fire(0.16)
						end
						Verify.expect((engines.connections(world.engine.heartbeat))):toBe(0)
						path:set({})
						Verify.expect((detail:isDestroyed())):toBe(true)
						Verify.expect(root.Visible):toBe(true)
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case("crossfades tab pages without blocking the incoming page and shows the first page at once", {
			id = "native_navigation::native navigation controls::crossfades tab pages without blocking the incoming page and shows the first page at once",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selection,
						tabs = {
							{ id = "one", content = Host.Frame "OneBody" {} } :: FixtureNavigationTypes.Tab,
							{ id = "two", content = Host.Frame "TwoBody" {} } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local one = fadeKit.layer(find(world.screen, "OneBody"))
				Verify.expect(one.ClassName):toBe("Frame")
				Verify.expect((fadeKit.of(one))):toBe(0)
				selection:set("two")
				local two = fadeKit.layer(find(world.screen, "TwoBody"))
				Verify.expect((fadeKit.of(two))):toBe(1)
				Verify.expect(two.Interactable):toBe(true)
				Verify.expect(one.Interactable):toBe(false)
				local previous = 1
				for _ = 1, 6 do
					world.engine.heartbeat:Fire(1 / 60)
					Verify.expect(fadeKit.of(two) < previous):toBe(true)
					Verify.expect((fadeKit.of(one))):toBeCloseTo(1 - fadeKit.of(two), 1e-6)
					Verify.expect(one.Visible):toBe(true)
					previous = fadeKit.of(two)
				end
				Verify.expect(previous > 0):toBe(true)
				for _ = 1, 7 do
					world.engine.heartbeat:Fire(1 / 60)
				end
				Verify.expect((fadeKit.of(two))):toBe(0)
				Verify.expect(one.Visible):toBe(false)
				world.gui.ReducedMotionEnabled = true
				selection:set("one")
				Verify.expect(one.Visible):toBe(true)
				world.engine.heartbeat:Fire(0.16)
				Verify.expect((fadeKit.of(one))):toBe(0)
				Verify.expect(two.Visible):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("slides a sheet up over a fading scrim and releases input when its dismissal starts", {
			id = "native_navigation::native navigation controls::slides a sheet up over a fading scrim and releases input when its dismissal starts",
			run = function()
				local shown, detent = Compose.cell(false), Compose.cell("medium")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button "Opener" { label = "Open" } :: unknown,
						UI.Sheet({
							isPresented = shown,
							detent = detent,
							title = "Sheet",
							content = Host.Frame({}) :: Instance,
						}),
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Opener")
				shown:set(true)
				local panel = find(world.screen, "SheetPanel")
				local fade = find(world.screen, "ScrimFade")
				find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(800, 720)
				local hidden = panel.Position.Y.Offset
				Verify.expect(fade.Transparency.Keypoints[1].Value):toBe(1)
				world.engine.heartbeat:Fire(1 / 60)
				Verify.expect(panel.Position.Y.Offset):toBe(hidden)
				Verify.expect(fade.Transparency.Keypoints[1].Value):toBe(1)
				world.engine.heartbeat:Fire(1 / 60)
				Verify.expect(panel.Position.Y.Offset > 0):toBe(true)
				local previous = panel.Position.Y.Offset
				for _ = 1, 10 do
					world.engine.heartbeat:Fire(1 / 60)
					Verify.expect(panel.Position.Y.Offset < previous):toBe(true)
					previous = panel.Position.Y.Offset
				end
				world.settle()
				Verify.expect(panel.Position):toBe(world.engine.types.UDim2.fromScale(0.5, 1))
				Verify.expect(fade.Transparency.Keypoints[1].Value):toBe(0)
				shown:set(false)
				local modal = find(world.screen, "Modal")
				Verify.expect(modal.Interactable):toBe(false)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Opener")
				world.engine.heartbeat:Fire(0.1)
				Verify.expect(panel.Position.Y.Offset > 0):toBe(true)
				Verify.expect(fade.Transparency.Keypoints[1].Value > 0):toBe(true)
				world.engine.heartbeat:Fire(0.11)
				Verify.expect((panel:isDestroyed())):toBe(true)
				world.gui.ReducedMotionEnabled = true
				shown:set(true)
				panel = find(world.screen, "SheetPanel")
				find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(800, 720)
				Verify.expect(panel.Position.Y.Offset > 0):toBe(true)
				world.engine.heartbeat:Fire(1 / 600)
				world.engine.heartbeat:Fire(1 / 600)
				Verify.expect(panel.Position):toBe(world.engine.types.UDim2.fromScale(0.5, 1))
				shown:set(false)
				Verify.expect((panel:isDestroyed())):toBe(false)
				Verify.expect(panel.Position):toBe(world.engine.types.UDim2.fromScale(0.5, 1))
				world.engine.heartbeat:Fire(0.16)
				Verify.expect((panel:isDestroyed())):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("keeps alert layout fixed while its group fades and dismisses faster than it entered", {
			id = "native_navigation::native navigation controls::keeps alert layout fixed while its group fades and dismisses faster than it entered",
			run = function()
				local shown = Compose.cell(false)
				local world = setup(function(UI: FacetControls)
					return UI.Alert({
						isPresented = shown,
						title = "Leave?",
						actions = {
							{ id = "stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
						},
					})
				end)
				shown:set(true)
				local panel = find(world.screen, "AlertPanel")
				local V = world.engine.types.Vector2
				panel.AbsoluteSize = V.new(440, 176)
				local layout = find(panel, "AlertLayout")
				find(panel, "AlertContent").Parent.AbsoluteSize = V.new(300, 60)
				world.engine.heartbeat:Fire(0)
				world.engine.heartbeat:Fire(0)
				local parent, size = layout.Parent, panel.Size
				Verify.expect(panel.AbsoluteSize):toBe(V.new(440, 176))
				Verify.expect(find(panel, "PresentationPaint")):toBeNil()
				Verify.expect(layout:IsDescendantOf(panel:FindFirstChild("Fade"))):toBe(true)
				Verify.expect((fadeKit.of(panel))):toBe(1)
				world.engine.heartbeat:Fire(0.1)
				Verify.expect(panel.Size):toBe(size)
				Verify.expect(panel.AbsoluteSize):toBe(V.new(440, 176))
				Verify.expect(layout.Parent):toBe(parent)
				Verify.expect(fadeKit.of(panel) > 0 and fadeKit.of(panel) < 1):toBe(true)
				world.engine.heartbeat:Fire(0.1)
				Verify.expect(panel.Size.X.Scale):toBe(1)
				Verify.expect(panel.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.Y)
				Verify.expect((fadeKit.of(panel))):toBe(0)
				shown:set(false)
				world.engine.heartbeat:Fire(0.1)
				Verify.expect((panel:isDestroyed())):toBe(false)
				Verify.expect(fadeKit.of(panel) > 0):toBe(true)
				world.engine.heartbeat:Fire(0.06)
				Verify.expect((panel:isDestroyed())):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("grows callouts and help and cross-fades menus at their final anchor", {
			id = "native_navigation::native navigation controls::grows callouts and help and cross-fades menus at their final anchor",
			run = function()
				local opened = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = Host.TextButton "Anchor" {}
					return Host.Frame({
						anchor :: unknown,
						UI.Button "Plus" { label = "+", help = "Adds one" },
						UI.Callout({
							anchor = anchor :: GuiObject,
							content = Host.TextLabel "Tip" {} :: Instance,
							onRetire = function() end,
						}),
						UI.Menu({
							isPresented = opened,
							items = {
								{ id = "Run", label = "Run", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
							},
						}),
					})
				end)
				local V = world.engine.types.Vector2
				world.screen.AbsoluteSize = V.new(960, 720)
				local anchor = find(world.screen, "Anchor")
				anchor.AbsolutePosition = V.new(160, 100)
				anchor.AbsoluteSize = V.new(240, 44)
				local callout = find(world.screen, "CalloutPanel")
				callout.AbsoluteSize = V.new(280, 100)
				local scale = materialize.of(callout)
				world.engine.heartbeat:Fire(1 / 60)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect((fadeKit.of(callout))):toBe(1)
				Verify.expect(callout.Position.X.Offset):toBe(280)
				Verify.expect((near(callout.Position.Y.Offset, 152 + LIFT))):toBe(true)
				Verify.expect(callout.AnchorPoint):toBe(V.new(0.5, 0))
				world.engine.heartbeat:Fire(1 / 60)
				world.engine.heartbeat:Fire(0.075)
				Verify.expect(scale.Scale > 0.9 and scale.Scale < 1):toBe(true)
				world.engine.heartbeat:Fire(0.075)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect((fadeKit.of(callout))):toBe(0)
				local left, top = corner(callout)
				Verify.expect(left == 140 and near(top, 152 + LIFT)):toBe(true)
				local plus = find(world.screen, "Plus")
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
				plus.GuiState = world.engine.types.Enum.GuiState.Hover
				world.engine.heartbeat:Fire(0.5)
				local help = find(world.screen, "Help")
				Verify.expect(help.ClassName):toBe("Frame")
				help.AbsoluteSize = V.new(80, 30)
				world.engine.heartbeat:Fire(1 / 60)
				world.engine.heartbeat:Fire(1 / 60)
				local entering = materialize.of(help).Scale
				Verify.expect(entering >= 0.9 and entering < 1):toBe(true)
				world.settle()
				Verify.expect(materialize.of(help).Scale):toBe(1)
				Verify.expect((fadeKit.of(help))):toBe(0)
				plus.GuiState = world.engine.types.Enum.GuiState.Idle
				world.engine.heartbeat:Fire(0.06)
				Verify.expect((help:isDestroyed())):toBe(false)
				world.engine.heartbeat:Fire(0.06)
				Verify.expect((help:isDestroyed())):toBe(true)
				opened:set(true)
				local menu = find(world.screen, "MenuPanel")
				local group = find(menu, "MenuGroup")
				Verify.expect((fadeKit.of(group))):toBe(1)
				Verify.expect(find(menu, "PresentationFade").Transparency.Keypoints[1].Value):toBe(1)
				Verify.expect(materialize.of(menu).Scale):toBe(1)
				menu.AbsoluteSize = V.new(220, 60)
				world.engine.heartbeat:Fire(1 / 60)
				world.engine.heartbeat:Fire(1 / 60)
				local growing = materialize.of(menu).Scale
				Verify.expect(growing):toBe(1)
				Verify.expect(fadeKit.of(group) > 0):toBe(true)
				world.settle()
				Verify.expect((fadeKit.of(group))):toBe(0)
				Verify.expect(materialize.of(menu).Scale):toBe(1)
				find(menu, "Run").Activated:Fire()
				Verify.expect(find(world.screen, "Modal").Interactable):toBe(false)
				world.engine.heartbeat:Fire(0.11)
				Verify.expect((menu:isDestroyed())):toBe(true)
				world.stop()
			end,
		})
	end);
	(function(verifyHarness: Verify.Harness)
		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
		type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
		type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
		type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
		local FixtureComposeTypes = require("../src/vendor/compose/core")
		local FixtureCollectionTypes = require("../src/ui/collection_types")
		local FixtureNavigationTypes = require("../src/ui/navigation_types")
		type Readable<T> = { peek: (Readable<T>) -> T }
		type Use = <T>(Readable<T>) -> T

		local materialize = require("./lib/materialize")
		local Facet = require("../src")
		local engineLib = require("./lib/native_engine")
		local Compose: ComposeModule = Facet.Compose

		type World = {
			engine: any,
			runtime: any,
			gui: any,
			input: any,
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
			local config: { [string]: any } = {
				types = engine.types,
				guiService = gui,
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

		local function action(root: any, name: string): any
			for _, node in root:GetDescendants() do
				if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
					return node:FindFirstChild(name)
				end
			end
			return nil
		end

		local function mountError(build: (any, any) -> any): string?
			local engine: any = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local UI = Facet.controls(
				runtime,
				{ types = engine.types, guiService = gui, services = { GuiService = gui } } :: any
			)
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

		local function V2(world: World, x: number, y: number): any
			return world.engine.types.Vector2.new(x, y)
		end

		local function page(
			Host: any,
			name: string,
			builds: { [string]: number }?,
			cleanups: { [string]: number }?
		): () -> any
			return function()
				if builds then
					builds[name] = (builds[name] or 0) + 1
				end
				if cleanups then
					Compose.cleanup(function()
						cleanups[name] = (cleanups[name] or 0) + 1
					end)
				end
				return Host.Frame(name .. "Body")({})
			end
		end

		verifyHarness:suite("native parity navigation", function()
			for _, case in
				{
					{ kind = "VirtualGrid", editing = false },
					{ kind = "Table", editing = false },
					{
						kind = "Table",
						editing = true,
					},
				}
			do
				local kind, editing = case.kind, case.editing
			end

			verifyHarness:case("sizes segments by fill or hug without replacing them and refuses unknown sizing", {
				id = "native_navigation::native parity navigation::sizes segments by fill or hug without replacing them and refuses unknown sizing",
				run = function()
					local sizing, selected =
						(function(value: "fill" | "hug"): FixtureComposeTypes.Cell<"fill" | "hug">
							return Compose.cell(value)
						end)("fill"), Compose.cell("a")
					local world = setup(function(UI: FacetControls)
						return UI.Picker({
							selected = selected,
							style = "segmented" :: "segmented",
							sizing = sizing,
							options = {
								{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Much longer" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						})
					end)
					local Enum = world.engine.types.Enum
					local picker = find(world.screen, "Picker")
					local layout = picker:FindFirstChildWhichIsA("UIListLayout")
					local a = find(picker, "a")
					Verify.expect(layout.HorizontalFlex):toBe(Enum.UIFlexAlignment.Fill)
					Verify.expect(a.AutomaticSize):toBe(Enum.AutomaticSize.X)
					Verify.expect(a.Size.Y.Scale):toBe(0)
					Verify.expect(a.Size.Y.Offset):toBe(44)
					sizing:set("hug")
					Verify.expect(layout.HorizontalFlex):toBe(Enum.UIFlexAlignment.None)
					Verify.expect((find(picker, "a"))):toBe(a)
					sizing:set("fill")
					Verify.expect(layout.HorizontalFlex):toBe(Enum.UIFlexAlignment.Fill)
					world.stop()
					Verify.expect((refuses("Picker.sizing must be fill or hug", function(UI: FacetControls)
						return UI.Picker({
							selected = Compose.cell("a"),
							style = "segmented",
							sizing = "wide",
							options = { { value = "a", label = "A" } },
						} :: any)
					end))):toBe(true)
				end,
			})
		end)
	end)(verifyHarness);
	(function(verifyHarness: Verify.Harness)
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

		local function action(root: any, name: string): any
			for _, node in root:GetDescendants() do
				if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
					return node:FindFirstChild(name)
				end
			end
			return nil
		end

		local function mountError(build: (any, any) -> any): string?
			local engine: any = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local UI = Facet.controls(
				runtime,
				{ types = engine.types, guiService = gui, services = { GuiService = gui } } :: any
			)
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

		local function V2(world: World, x: number, y: number): any
			return world.engine.types.Vector2.new(x, y)
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
				if node:IsA("TextLabel") and node.Text ~= "" and node.Name ~= "CaptionMeasure" then
					return node.Text
				end
			end
			return nil
		end

		verifyHarness:suite("native parity weaker menus", function()
			verifyHarness:case(
				"fits an explicit segmented strip inside the width of its labelled row: one constraint, shared width",
				{
					id = "native_navigation::native parity weaker menus::fits an explicit segmented strip inside the width of its labelled row: one constraint, shared width",
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

						Verify.expect(options:FindFirstChildWhichIsA("UIListLayout", true).Wraps):toBe(true)
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
		end)
		verifyHarness:suite("Segmented Picker caption geometry", function()
			verifyHarness:case("shares one horizontal height and keeps compact touch targets", {
				id = "native_navigation::Segmented Picker caption geometry::shares one horizontal height and keeps compact touch targets",
				run = function()
					for _, touch in { false, true } do
						local world = setup(function(UI)
							return UI.Picker "Mode" {
								style = "segmented",
								controlSize = "compact",
								selected = Compose.cell("a"),
								options = { { value = "a", label = "Device" }, { value = "b", label = "Theme" } },
							}
						end)
						world.input.PreferredInput = if touch
							then world.engine.types.Enum.PreferredInput.Touch
							else world.engine.types.Enum.PreferredInput.KeyboardAndMouse
						local picker, segment = find(world.root, "Mode"), find(world.root, "a")
						Verify.expect(picker.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
						Verify.expect(picker.Size.Y.Offset):toBe(segment.Size.Y.Offset + 6)
						if touch then
							assert(
								segment.Size.Y.Offset >= 44,
								`Touch segment height {segment.Size.Y.Offset} is below 44`
							)
						end
						world.stop()
					end
				end,
			})
			verifyHarness:case("keeps a touch segment target inside an authored 44-point format strip", {
				id = "native_navigation::Segmented Picker caption geometry::keeps a touch segment target inside an authored 44-point format strip",
				run = function()
					local world = setup(function(UI, Host, engine)
						return UI.Picker "Format" {
							style = "segmented",
							selected = Compose.cell("rgb"),
							options = { { value = "rgb", label = "RGB" }, { value = "hsv", label = "HSV" } },
							Size = engine.types.UDim2.fromOffset(0, 44),
							AutomaticSize = engine.types.Enum.AutomaticSize.X,
						}
					end)
					world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
					local picker, segment = find(world.root, "Format"), find(world.root, "rgb")
					Verify.expect(segment.Size.Y.Offset >= 44):toBe(true)
					Verify.expect(picker:FindFirstChild("TargetFloor").MinSize.Y >= segment.Size.Y.Offset + 6)
						:toBe(true)
					world.stop()
				end,
			})
			verifyHarness:case("reserves the caption and both native padding edges", {
				id = "native_navigation::Segmented Picker caption geometry::reserves the caption and both native padding edges",
				run = function()
					local world = setup(function(UI)
						return UI.Picker "Device" {
							style = "segmented",
							selected = Compose.cell("a"),
							options = { { value = "a", label = "Device" }, { value = "b", label = "Theme" } },
						}
					end)
					local segment = find(world.root, "a")
					world.runtime.mount(function()
						return world.runtime.constructors.UIPadding {
							PaddingLeft = world.engine.types.UDim.new(0, 17),
							PaddingRight = world.engine.types.UDim.new(0, 19),
						}
					end, segment)
					local measure = segment:FindFirstChild("CaptionMeasure", true)
					Verify.expect(measure.TextTransparency):toBe(1)
					Verify.expect(measure.Interactable):toBe(false)
					measure.TextBounds = V2(world, 68, 16)
					local minimum = 0
					for _, child in segment:GetChildren() do
						if child:IsA("UISizeConstraint") then
							minimum = math.max(minimum, child.MinSize.X)
						end
					end
					assert(minimum >= 104, `Caption width {minimum} does not include both edges`)
					world.stop()
				end,
			})
			verifyHarness:case("uses logical caption height without reading its own painted height", {
				id = "native_navigation::Segmented Picker caption geometry::uses logical caption height without reading its own painted height",
				run = function()
					local world = setup(function(UI, Host)
						return Host.Frame {
							Host.UIScale { Scale = 2 },
							UI.Picker "Mode" {
								style = "segmented",
								selected = Compose.cell("a"),
								options = { { value = "a", label = "Device" }, { value = "b", label = "Theme" } },
							},
						}
					end, { theme = require("../examples/themes/glossy_touch").build(themes) })
					local picker, segment = find(world.root, "Mode"), find(world.root, "a")
					for _, node in picker:GetDescendants() do
						if node.Name == "LayoutUnit" then
							node.AbsoluteSize = V2(world, 200, 2)
						end
					end
					local caption = segment:FindFirstChild("Title", true) or segment
					caption.TextBounds = V2(world, 136, 80)
					Verify.expect(picker.Size.Y.Offset):toBe(62)
					local height = picker.Size.Y.Offset
					for frame = 1, 30 do
						segment.AbsoluteSize = V2(world, 140, 80 + frame * 10)
						world.step(1 / 30)
						Verify.expect(picker.Size.Y.Offset):toBe(height)
					end
					world.stop()
				end,
			})
		end)
	end)(verifyHarness)
end
