--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type ExampleContext = typeof(require("@repo/examples/types").Context)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	local FixtureEngineTypes = require("../src/ui/engine_types")
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureRadialTypes = require("../src/ui/radial_types")
	local RadialProps = require("../src/ui/radial_props")
	local NavigationFixtures = require("../src/ui/navigation_types")
	local FixtureThemeTypes = require("../src/ui/theme_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Use = FixtureComposeTypes.Use
	local Navigation = require("../src/ui/navigation_types")
	local NavigationProps = require("../src/ui/navigation_props")
	local SharedTypes = require("../src/ui/control_types")
	local Shared = require("../src/ui/types")

	local cells = require("./lib/cells")
	local materialize = require("./lib/materialize")
	local fadeKit = require("./lib/fade")
	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local controls = require("../src/ui")
	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local LIFT = 16 * math.sqrt(2) / 2
	local function noop() end
	local function menuCommand(id: string, label: string): Navigation.MenuCommand
		return { id = id, label = label, onSelect = noop }
	end
	local function submenu(
		id: string,
		label: string,
		children: { Navigation.MenuItem<string> }
	): Navigation.MenuSubmenu<string>
		return { id = id, label = label, children = children }
	end
	local function corner(panel: GuiObject): (number, number)
		return panel.Position.X.Offset - panel.AnchorPoint.X * panel.AbsoluteSize.X,
			panel.Position.Y.Offset - panel.AnchorPoint.Y * panel.AbsoluteSize.Y
	end
	local function near(actual: number, expected: number): boolean
		return math.abs(actual - expected) <= 1
	end
	local function play(engine: engines.Engine, seconds: number)
		local steps = math.ceil(seconds * 60)
		for _ = 1, steps do
			engine.heartbeat:Fire(seconds / steps)
		end
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
		build: (
			SharedTypes.Controls,
			RobloxHost,
			engines.Engine,
			GuiService,
			ComposeRuntime
		) -> Shared.Child,
		options: {
			theme: any?,
			pressHaptic: ((any) -> HapticEffect)?,
			motionLevel: Shared.Input<Shared.MotionLevel>?,
			runService: boolean?,
			preRender: boolean?,
			suspendGameplay: boolean?,
			tweens: unknown?,
		}?
	)
		local engine = engines.new()
		local gui = engine.new("GuiService")
		gui.GuiNavigationEnabled = true
		gui.AutoSelectGuiEnabled = true
		gui.TouchControlsEnabled = true
		engine.environment.fakeOn(gui, "GetInsetArea", function()
			return engine.types.Rect.new(0, 0, 1280, 720)
		end)
		engine.environment.fakeOn(gui, "GetGuiInset", function()
			return engine.types.Vector2.zero, engine.types.Vector2.zero
		end)
		local input = engine.new("UserInputService")
		engine.environment.fakeOn(input, "GetLastInputType", function()
			return engine.types.Enum.UserInputType.Keyboard
		end)
		for _, method in { "IsKeyDown", "IsGamepadButtonDown" } do
			engine.environment.fakeOn(input, method, function()
				return false
			end)
		end
		for _, method in { "GetNavigationGamepads", "GetKeysPressed", "GetMouseButtonsPressed", "GetGamepadState" } do
			engine.environment.fakeOn(input, method, function()
				return {}
			end)
		end
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local runService = if options and (options.runService or options.preRender)
			then { Heartbeat = engine.heartbeat, PreRender = if options.preRender then engine.heartbeat else nil }
			else nil
		local UI = controls(Compose, runtime, {
			types = engine.types,
			services = {
				GuiService = (gui :: unknown) :: GuiService,
				UserInputService = (input :: unknown) :: UserInputService,
				RunService = (runService :: unknown) :: RunService?,
				TweenService = ((if options then options.tweens else nil) :: unknown) :: TweenService?,
			},
			theme = options and options.theme,
			pressHaptic = options and options.pressHaptic and options.pressHaptic(engine),
			motionLevel = options and options.motionLevel,
			suspendGameplay = options and options.suspendGameplay,
		})
		local target = engine.new("Folder")
		local stop, screen: any = runtime.mount(function()
			return Facet.host(runtime).ScreenGui({
				build(UI, Facet.host(runtime), engine, gui, runtime),
			})
		end, target)
		for _, node in screen:GetDescendants() do
			if node:IsA("ScrollingFrame") then
				engine.environment.fakeOn(node, "GetScrollVelocity", function()
					return engine.types.Vector2.zero
				end)
				engine.environment.fakeOn(node, "ResetScrollVelocity", function() end)
			end
		end
		return {
			engine = engine,
			gui = (gui :: unknown) :: GuiService,
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

	describe("native navigation controls", function()
		type ReleaseSample = { name: string, distance: number, seconds: number, idle: number, expected: string }
		local samples: { ReleaseSample } = {
			{ name = "short flick", distance = 30, seconds = 0.02, idle = 0, expected = "four" },
			{ name = "slow long drag", distance = 180, seconds = 1, idle = 0, expected = "four" },
			{ name = "slow short drag", distance = 120, seconds = 1, idle = 0, expected = "three" },
			{ name = "stopped flick", distance = 30, seconds = 0.02, idle = 0.2, expected = "three" },
			{ name = "long flick cannot skip", distance = 600, seconds = 0.02, idle = 0, expected = "four" },
			{ name = "reverse flick", distance = -30, seconds = 0.02, idle = 0, expected = "two" },
			{ name = "native reverse velocity", distance = 180, seconds = 1, idle = 0, expected = "two" },
		}
		for _, sample in samples do
			it("PageView release " .. sample.name, {
				id = "native_navigation::page release::" .. sample.name,
				run = function()
					local chosen = Compose.cell("three")
					local world = setup(function(UI: FacetControls)
						local pages: { Navigation.Tab } = {}
						for _, id in { "one", "two", "three", "four", "five" } do
							table.insert(pages, { id = id, content = UI.Text { text = id } })
						end
						return UI.PageView {
							selection = chosen,
							pages = pages,
							indicatorPlacement = "overlay",
							scrollWheel = true,
						}
					end)
					local pages, V2, E =
						find(world.screen, "Pages"), world.engine.types.Vector2, world.engine.types.Enum
					world.engine.environment.poke(pages, "AbsoluteWindowSize", V2.new(320, 160))
					world.engine.environment.poke(pages, "AbsoluteCanvasSize", V2.new(1600, 160))
					local touch = world.engine.new("InputObject")
					world.engine.environment.poke(touch, "UserInputType", E.UserInputType.Touch)
					pages.InputBegan:Fire(touch)
					world.engine.environment.step(sample.seconds)
					pages.CanvasPosition = V2.new(640 + sample.distance, 0)
					if sample.name == "native reverse velocity" then
						world.engine.environment.fakeOn(pages, "GetScrollVelocity", function()
							return V2.new(-1200, 0)
						end)
					end
					world.engine.environment.step(sample.idle)
					world.engine.environment.fire(world.input, "InputEnded", touch)
					expect(chosen:peek()):toBe("three")
					expect(find(find(world.screen, "Indicators"), "three"):HasTag("facet-selected")):toBe(true)
					expect(pages.CanvasPosition.X):toBe(640 + sample.distance)
					world.settle()
					expect(chosen:peek()):toBe(sample.expected)
					expect(find(find(world.screen, "Indicators"), sample.expected):HasTag("facet-selected")):toBe(true)
					expect(pages.CanvasPosition.X):toBe(
						if sample.expected == "four" then 960 elseif sample.expected == "two" then 320 else 640
					)
					world.stop()
					expect(world.engine.census().connections):toBe(0)
				end,
			})
		end
		it("PageView measures a release from the page in view when a contact stops a selection animation", {
			id = "native_navigation::page release::contact during selection animation",
			run = function()
				local chosen = Compose.cell("one")
				local created: { { goal: { [string]: any }, cancelled: number } } = {}
				local tweens = {
					Create = function(_, _instance: any, _info: any, goal: { [string]: any })
						local record = { goal = goal, cancelled = 0 }
						table.insert(created, record)
						return {
							Play = function() end,
							Cancel = function()
								record.cancelled += 1
							end,
						}
					end,
				}
				local world = setup(function(UI: FacetControls)
					local pages: { Navigation.Tab } = {}
					for _, id in { "one", "two", "three", "four" } do
						table.insert(pages, { id = id, content = UI.Text { text = id } })
					end
					return UI.PageView {
						selection = chosen,
						pages = pages,
						scrollWheel = true,
					}
				end, { tweens = tweens })
				local pages, V2, E = find(world.screen, "Pages"), world.engine.types.Vector2, world.engine.types.Enum
				world.engine.environment.poke(pages, "AbsoluteWindowSize", V2.new(320, 160))
				world.engine.environment.poke(pages, "AbsoluteCanvasSize", V2.new(1280, 160))
				expect(pages.CanvasPosition.X):toBe(0)
				chosen:set("two")
				expect(#created):toBe(1)
				expect(created[1].goal.CanvasPosition.X):toBe(320)
				pages.CanvasPosition = V2.new(100, 0)
				local touch = world.engine.new("InputObject")
				world.engine.environment.poke(touch, "UserInputType", E.UserInputType.Touch)
				pages.InputBegan:Fire(touch)
				expect(created[1].cancelled):toBe(1)
				expect(pages.CanvasPosition.X):toBe(100)
				world.engine.environment.step(0.02)
				pages.CanvasPosition = V2.new(130, 0)
				world.engine.environment.fire(world.input, "InputEnded", touch)
				world.settle()
				expect(pages.CanvasPosition.X):toBe(320)
				expect(chosen:peek()):toBe("two")
				expect(find(find(world.screen, "Indicators"), "two"):HasTag("facet-selected")):toBe(true)
				world.stop()
				expect(world.engine.census().connections):toBe(0)
			end,
		})
		it("PageView interrupts a release snap and keeps the current contact position", {
			id = "native_navigation::page release::interruption",
			run = function()
				local chosen = Compose.cell("one")
				local world = setup(function(UI: FacetControls)
					return UI.PageView {
						selection = chosen,
						pages = {
							{ id = "one", content = UI.Text { text = "One" } },
							{ id = "two", content = UI.Text { text = "Two" } },
						},
					}
				end)
				local pages, V2, E = find(world.screen, "Pages"), world.engine.types.Vector2, world.engine.types.Enum
				world.engine.environment.poke(pages, "AbsoluteWindowSize", V2.new(320, 160))
				world.engine.environment.poke(pages, "AbsoluteCanvasSize", V2.new(640, 160))
				local touch = world.engine.new("InputObject")
				world.engine.environment.poke(touch, "UserInputType", E.UserInputType.Touch)
				pages.InputBegan:Fire(touch)
				world.engine.environment.step(0.02)
				pages.CanvasPosition = V2.new(40, 0)
				world.engine.environment.fire(world.input, "InputEnded", touch)
				world.engine.environment.step(0.04)
				local interrupted = pages.CanvasPosition.X
				expect(interrupted > 40 and interrupted < 320):toBe(true)
				pages.InputBegan:Fire(touch)
				world.settle()
				expect(pages.CanvasPosition.X):toBe(interrupted)
				pages.CanvasPosition = V2.new(20, 0)
				world.engine.environment.step(0.2)
				world.engine.environment.fire(world.input, "InputEnded", touch)
				world.settle()
				expect(pages.CanvasPosition.X):toBe(0)
				expect(chosen:peek()):toBe("one")
				world.stop()
			end,
		})
		it("PageView release stops horizontal mouse inertia at one page", {
			id = "native_navigation::page release::mouse inertia",
			run = function()
				local chosen = Compose.cell("one")
				local world = setup(function(UI: FacetControls)
					return UI.PageView {
						selection = chosen,
						scrollWheel = true,
						pages = {
							{ id = "one", content = UI.Text { text = "One" } },
							{ id = "two", content = UI.Text { text = "Two" } },
							{ id = "three", content = UI.Text { text = "Three" } },
						},
					}
				end)
				local pages, V2, V3, E =
					find(world.screen, "Pages"),
					world.engine.types.Vector2,
					world.engine.types.Vector3,
					world.engine.types.Enum
				world.engine.environment.poke(pages, "AbsoluteSize", V2.new(320, 160))
				world.engine.environment.poke(pages, "AbsoluteWindowSize", V2.new(320, 160))
				world.engine.environment.poke(pages, "AbsoluteCanvasSize", V2.new(960, 160))
				local mouse, movement = world.engine.new("InputObject"), world.engine.new("InputObject")
				world.engine.environment.poke(mouse, "UserInputType", E.UserInputType.MouseButton1)
				world.engine.environment.poke(mouse, "Position", V3.new(200, 80, 0))
				world.engine.environment.poke(movement, "UserInputType", E.UserInputType.MouseMovement)
				world.engine.environment.poke(movement, "Position", V3.new(50, 80, 0))
				pages.InputBegan:Fire(mouse)
				world.engine.environment.fire(world.input, "InputBegan", mouse)
				world.engine.environment.step(0.02)
				world.engine.environment.fire(world.input, "InputChanged", movement)
				expect(pages.CanvasPosition.X):toBe(150)
				world.engine.environment.fire(world.input, "InputEnded", mouse)
				world.settle()
				expect(pages.CanvasPosition.X):toBe(320)
				expect(chosen:peek()):toBe("two")
				world.settle()
				expect(pages.CanvasPosition.X):toBe(320)
				pages.CanvasPosition = V2.new(450, 0)
				world.engine.environment.step(0.25)
				world.settle()
				expect(pages.CanvasPosition.X):toBe(320)
				pages.CanvasPosition = V2.new(520, 0)
				world.engine.environment.step(0.25)
				world.settle()
				expect(pages.CanvasPosition.X):toBe(640)
				expect(chosen:peek()):toBe("three")
				world.stop()
			end,
		})
		it("PageView reduced motion settles on release and touch pauses automatic advance", {
			id = "native_navigation::page release::reduced motion and automatic advance",
			run = function()
				local chosen = Compose.cell("one")
				local world = setup(function(UI: FacetControls)
					return UI.PageView {
						selection = chosen,
						autoAdvanceSeconds = 0.1,
						pages = {
							{ id = "one", content = UI.Button "TouchCard" { label = "One" } },
							{ id = "two", content = UI.Text { text = "Two" } },
						},
					}
				end, { motionLevel = "none" })
				local pages, V2, E = find(world.screen, "Pages"), world.engine.types.Vector2, world.engine.types.Enum
				world.engine.environment.poke(pages, "AbsoluteWindowSize", V2.new(320, 160))
				world.engine.environment.poke(pages, "AbsoluteCanvasSize", V2.new(640, 160))
				local touch = world.engine.new("InputObject")
				world.engine.environment.poke(touch, "UserInputType", E.UserInputType.Touch)
				find(world.screen, "TouchCard").InputBegan:Fire(touch)
				world.engine.heartbeat:Fire(3)
				expect(chosen:peek()):toBe("one")
				pages.CanvasPosition = V2.new(200, 0)
				world.engine.environment.fire(world.input, "InputEnded", touch)
				expect(chosen:peek()):toBe("two")
				expect(pages.CanvasPosition.X):toBe(320)
				world.engine.heartbeat:Fire(0.2)
				pages.MouseLeave:Fire(0, 0)
				expect(chosen:peek()):toBe("two")
				world.engine.heartbeat:Fire(0.05)
				world.engine.heartbeat:Fire(0.1)
				expect(chosen:peek()):toBe("one")
				world.stop()
			end,
		})
		it("overlay indicators stay over the page and leave the footer empty", function()
			local chosen = Compose.cell("one")
			local world = setup(function(UI: FacetControls)
				return UI.PageView {
					selection = chosen,
					pages = {
						{ id = "one", content = UI.Text { text = "One" } },
						{ id = "two", content = UI.Text { text = "Two" } },
					},
					indicatorPlacement = "overlay",
					controls = false,
					summary = false,
				}
			end)
			local pages, dots, footer =
				find(world.screen, "Pages"), find(world.screen, "Indicators"), find(world.screen, "Footer")
			expect(pages.Size.Y.Scale):toBe(1)
			expect(pages.Size.Y.Offset):toBe(0)
			expect(dots.Parent):toBe(pages.Parent)
			expect(dots.AnchorPoint.Y):toBe(1)
			expect(dots.Position.Y.Scale):toBe(1)
			expect(footer.Size.Y.Offset):toBe(0)
			world.engine.environment.poke(world.input, "TouchEnabled", true)
			for _, id in { "one", "two" } do
				local button = find(dots, id)
				expect(button.Size.X.Offset):toBe(24)
				expect(button:FindFirstChild("TargetFloor").MinSize.X):toBe(24)
				expect(button:FindFirstChild("TargetFloor").MinSize.Y):toBe(44)
			end
			find(dots, "two").Activated:Fire()
			expect(chosen:peek()):toBe("two")
			world.stop()
		end)
		it("keyboard paging keeps focus on pages without an interactive child", function()
			local chosen = Compose.cell("one")
			local world = setup(function(UI: FacetControls)
				return UI.PageView {
					selection = chosen,
					pages = {
						{ id = "one", content = UI.Button "FirstCard" { label = "First" } },
						{ id = "two", content = UI.Text { text = "Read this tip" } },
						{ id = "three", content = UI.Button "LastCard" { label = "Last" } },
					},
				}
			end)
			local pages, V2, E = find(world.screen, "Pages"), world.engine.types.Vector2, world.engine.types.Enum
			world.engine.environment.poke(pages, "AbsoluteWindowSize", V2.new(320, 160))
			world.engine.environment.poke(pages, "AbsoluteCanvasSize", V2.new(960, 160))
			world.gui.SelectedObject = find(world.screen, "FirstCard")
			for index = 1, 2 do
				local input = world.engine.new("InputObject")
				world.engine.environment.poke(input, "KeyCode", E.KeyCode.Right)
				world.engine.environment.poke(input, "UserInputType", E.UserInputType.Keyboard)
				world.engine.environment.fire(world.input, "InputBegan", input)
				world.engine.environment.fire(world.input, "InputEnded", input)
				expect(chosen:peek()):toBe(if index == 1 then "two" else "three")
				expect(assert(world.gui.SelectedObject).Name):toBe(if index == 1 then "two" else "LastCard")
			end
			world.stop()
		end)
		it("PageView owns automatic advance and restarts after input and pauses", {
			id = "native_navigation::native navigation controls::PageView owns automatic advance and restarts after input and pauses",
			run = function()
				local chosen = Compose.cell("one")
				local seconds = Compose.cell<<number?>>(20)
				local wheel = Compose.cell(false)
				local world = setup(function(UI: FacetControls)
					local function page(): Instance
						return UI.Text { text = "Card" }
					end
					local tabs: { Navigation.Tab } = {
						{ id = "one", content = page },
						{ id = "two", content = page },
					}
					local props: NavigationProps.PageViewSpec = {
						selection = chosen,
						pages = tabs,
						autoAdvanceSeconds = seconds,
						scrollWheel = wheel,
					}
					return UI.PageView "TimedCards"(props)
				end)
				local viewport = find(world.screen, "Pages")
				expect(viewport.ScrollingEnabled):toBe(false)
				wheel:set(true)
				expect(viewport.ScrollingEnabled):toBe(true)
				wheel:set(false)
				expect(viewport.ScrollingEnabled):toBe(false)
				world.engine.heartbeat:Fire(19)
				expect(chosen:peek()):toBe("one")
				world.engine.heartbeat:Fire(1)
				expect(chosen:peek()):toBe("two")
				chosen:set("one")
				world.engine.heartbeat:Fire(19)
				expect(chosen:peek()):toBe("one")
				local pages = find(world.screen, "Pages")
				pages.MouseEnter:Fire(0, 0)
				world.engine.heartbeat:Fire(30)
				expect(chosen:peek()):toBe("one")
				pages.MouseLeave:Fire(0, 0)
				world.engine.heartbeat:Fire(20)
				expect(chosen:peek()):toBe("two")
				seconds:set(nil)
				world.engine.heartbeat:Fire(60)
				expect(chosen:peek()):toBe("two")
				seconds:set(20)
				world.engine.heartbeat:Fire(20)
				expect(chosen:peek()):toBe("one")
				world.stop()
				world.engine.heartbeat:Fire(60)
				expect(chosen:peek()):toBe("one")
			end,
		})
		it("PageView restores a retained selection without animation when its ancestor returns", function()
			local shown = Compose.cell(true)
			local chosen = Compose.cell("two")
			local world = setup(function(UI: FacetControls, Host: RobloxHost)
				local function page(): Instance
					return UI.Text { text = "Card" }
				end
				return Host.Frame "Retained" {
					Visible = shown,
					UI.PageView {
						selection = chosen,
						pages = { { id = "one", content = page }, { id = "two", content = page } },
					},
				}
			end)
			local pages = find(world.screen, "Pages")
			world.engine.environment.poke(pages, "AbsoluteWindowSize", world.engine.types.Vector2.new(320, 160))
			world.engine.environment.poke(pages, "AbsoluteCanvasSize", world.engine.types.Vector2.new(640, 160))
			expect(pages.CanvasPosition.X):toBe(320)
			shown:set(false)
			chosen:set("one")
			expect(pages.CanvasPosition.X):toBe(320)
			shown:set(true)
			expect(pages.CanvasPosition.X):toBe(0)
			world.screen.Enabled = false
			chosen:set("two")
			expect(pages.CanvasPosition.X):toBe(0)
			world.screen.Enabled = true
			expect(pages.CanvasPosition.X):toBe(320)
			local connections = world.engine.census().connections
			for _ = 1, 8 do
				shown:set(false)
				shown:set(true)
			end
			expect(world.engine.census().connections):toBe(connections)
			world.stop()
			expect(world.engine.census().connections):toBe(0)
		end)
		it("Button owns its native leading glyph through caption and availability changes", {
			id = "native_navigation::native navigation controls::Button owns its native leading glyph through caption and availability changes",
			run = function()
				local label = Compose.cell("Create game")
				local enabled = Compose.cell(true)
				local created, cleaned, invoked = 0, 0, 0
				local world = setup(function(UI: FacetControls)
					local function glyph(): GuiObject
						created += 1
						Compose.cleanup(function()
							cleaned += 1
						end)
						return UI.Path "CreateGlyph" {
							points = {
								{ x = 0.2, y = 0.2, inX = 0, inY = 0, outX = 0, outY = 0 },
								{ x = 0.8, y = 0.8, inX = 0, inY = 0, outX = 0, outY = 0 },
							},
						}
					end
					return UI.Button "Create" {
						glyph = glyph,
						label = label,
						enabled = enabled,
						onActivate = function()
							invoked += 1
						end,
					}
				end)
				local button = find(world.screen, "Create")
				local glyph = find(button, "CreateGlyph")
				expect(glyph.Parent.Name):toBe("LeadingGlyph")
				button.Activated:Fire(nil, 1)
				expect(invoked):toBe(1)
				label:set("Another game")
				enabled:set(false)
				button.Activated:Fire(nil, 1)
				expect(invoked):toBe(1)
				expect(find(button, "Title").Text):toBe("Another game")
				expect(find(button, "CreateGlyph")):toBe(glyph)
				expect(created):toBe(1)
				world.stop()
				expect(cleaned):toBe(1)
			end,
		})
		it("owns native glyphs across icon-only and labelled tabs and keeps accessible names", {
			id = "native_navigation::native navigation controls::owns native glyphs across icon-only and labelled tabs and keeps accessible names",
			run = function()
				local chosen = Compose.cell("games")
				local iconOnly = Compose.cell(true)
				type Placement = "bottomBar" | "sidebar"
				local placement = Compose.cell<<Placement>>("bottomBar")
				local created = 0
				local cleaned = 0
				local world = setup(function(UI: FacetControls)
					local function glyph(): GuiObject
						created += 1
						Compose.cleanup(function()
							cleaned += 1
						end)
						return UI.Path "NativeGlyph" {
							points = {
								{ x = 0.2, y = 0.2, inX = 0, inY = 0, outX = 0, outY = 0 },
								{ x = 0.8, y = 0.8, inX = 0, inY = 0, outX = 0, outY = 0 },
							},
						}
					end
					local function page(): Instance
						return UI.Text { text = "Page" }
					end
					local tabs: { Navigation.Tab } = {
						{ id = "games", label = "Games", glyph = glyph, badge = 2, content = page },
						{ id = "profile", label = "Profile", glyph = glyph, content = page },
					}
					local props: NavigationProps.TabViewSpec = {
						selection = chosen,
						placement = placement,
						iconOnly = iconOnly,
						tabs = tabs,
					}
					return UI.TabView "NativeTabs"(props)
				end)
				local button = find(world.screen, "games")
				local glyph = find(button, "NativeGlyph")
				expect(created):toBe(2)
				expect(button.Text):toBe("")
				expect(button:GetAttribute("label")):toBe("Games (2)")
				local leading = find(button, "LeadingGlyph")
				expect(find(button, "Content"):FindFirstChild("Title") ~= nil):toBe(true)
				expect(glyph.Parent):toBe(leading)
				expect(glyph.Size.X.Scale):toBe(1)
				expect(leading.Size.X.Offset > 0):toBe(true)
				chosen:set("profile")
				expect(created):toBe(2)
				iconOnly:set(false)
				placement:set("sidebar")
				expect(find(button, "Title").Text):toBe("Games")
				expect(find(button, "Title").Visible):toBe(true)
				expect(find(button, "NativeGlyph")):toBe(glyph)
				expect(created):toBe(2)
				iconOnly:set(true)
				placement:set("bottomBar")
				expect(find(button, "Title").Visible):toBe(false)
				expect(created):toBe(2)
				world.stop()
				expect(cleaned):toBe(2)
			end,
		})
		it("touch never retains selection through command scopes or focus restoration", {
			id = "native_navigation::native navigation controls::touch never retains selection through command scopes or focus restoration",
			run = function()
				local world = setup(function(UI: FacetControls)
					local Commands = require("../src/ui/command_types")
					local primary = UI.Button "Primary" { label = "Rematch" }
					local targets: { Commands.CommandTarget<string> } = { { key = "primary", node = primary } }
					UI.commandScope(primary, { targets = targets, commands = {} })
					return primary
				end)
				local primary = find(world.screen, "Primary")
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Touch
				)
				local touch = world.engine.new("InputObject")
				world.engine.environment.poke(touch, "UserInputType", world.engine.types.Enum.UserInputType.Touch)
				primary.InputBegan:Fire(touch)
				world.settle()
				expect(world.gui.SelectedObject):toBe(nil)
				world.gui.SelectedObject = primary
				world.settle()
				expect(world.gui.SelectedObject):toBe(nil)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				world.gui.SelectedObject = primary
				world.settle()
				expect(world.gui.SelectedObject):toBe(primary)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Touch
				)
				world.settle()
				expect(world.gui.SelectedObject):toBe(nil)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Gamepad
				)
				world.gui.SelectedObject = primary
				world.settle()
				expect(world.gui.SelectedObject):toBe(primary)
				world.stop()
			end,
		})
		it("lets a destination keep its page when the player asks to go back", {
			id = "native_navigation::native navigation controls::lets a destination keep its page when the player asks to go back",
			run = function()
				local path = Compose.cell({} :: { Navigation.NavigationEntry<number> })
				local dirty = true
				local asked: { Navigation.NavigationEntry<number> } = {}
				local world = setup(function(UI: FacetControls)
					local spec: NavigationProps.NavigationStackSpec<number> = {
						path = path,
						transition = false :: false,
						root = {
							title = "Home",
							content = function()
								return UI.Button "HomeAction" { label = "Open" }
							end,
						} :: Navigation.NavigationDestination<number>,
						destinations = {
							livery = {
								title = "Livery",
								onBack = function(entry: Navigation.NavigationEntry<number>): boolean
									table.insert(asked, entry)
									return not dirty
								end,
								content = function()
									return UI.Button "Save" { label = "Save" }
								end,
							} :: Navigation.NavigationDestination<number>,
						},
					}
					return UI.NavigationStack "Stack"(spec)
				end, { motionLevel = "none" })
				local entry: Navigation.NavigationEntry<number> = { id = "livery", value = 7 }
				path:set({ entry })
				world.settle()
				local action = find(world.screen, "NavigationBack")
				action.Pressed:Fire()
				world.settle()
				expect(#path:peek()):toBe(1)
				expect(asked[1]):toBe(entry)
				find(find(world.screen, "Stack"), "Back").Activated:Fire()
				world.settle()
				expect(#path:peek()):toBe(1)
				expect(#asked):toBe(2)
				dirty = false
				action.Pressed:Fire()
				world.settle()
				expect(#path:peek()):toBe(0)
				path:set({ entry })
				path:set({})
				expect(#asked):toBe(3)
			end,
		})

		it("omits owned-page chrome without removing Back or selection restoration", {
			id = "native_navigation::native navigation controls::omits owned-page chrome without removing Back or selection restoration",
			run = function()
				local path = Compose.cell({} :: { Navigation.NavigationEntry<number> })
				local chrome = Compose.cell("hidden" :: "automatic" | "hidden")
				local world = setup(function(UI: FacetControls)
					local spec: NavigationProps.NavigationStackSpec<number> = {
						path = path,
						chrome = "hidden" :: "hidden",
						transition = false :: false,
						root = {
							title = "Home",
							content = function()
								return UI.Button "HomeAction" { label = "Open" }
							end,
						} :: Navigation.NavigationDestination<number>,
						destinations = {
							owned = {
								title = "",
								chrome = chrome,
								content = function()
									return UI.Button "OwnedHeader" { label = "My own header" }
								end,
							} :: Navigation.NavigationDestination<number>,
							inherited = {
								title = "Inherited",
								content = function()
									return UI.Button "InheritedAction" { label = "Page" }
								end,
							} :: Navigation.NavigationDestination<number>,
						},
					}
					return UI.NavigationStack "Stack"(spec)
				end, { motionLevel = "none" })
				local stack = find(world.screen, "Stack") :: Frame
				local Vector2, UDim2 = world.engine.types.Vector2, world.engine.types.UDim2
				expect(find(stack, "Back")):toBeNil()
				world.gui.SelectedObject = find(stack, "HomeAction")
				for _, size in { Vector2.new(320, 640), Vector2.new(390, 844), Vector2.new(844, 390) } do
					world.engine.environment.poke(VerifyRoblox.assertInstance(stack), "AbsoluteSize", size)
					path:set({ { id = "owned", value = 1 } })
					world.settle()
					local page = find(stack, "owned")
					local destination = find(page, "Destination") :: Frame
					expect(destination.Position.Y.Offset):toBe(0)
					expect(destination.Size):toBe(UDim2.fromScale(1, 1))
					expect(find(page, "NavigationBar").Visible):toBe(false)
					expect(find(page, "Back")):toBeNil()
					local action = find(world.screen, "NavigationBack")
					expect(action.Parent.Enabled):toBe(true)
					action.Pressed:Fire()
					world.settle()
					expect(#path:peek()):toBe(0)
					expect(world.gui.SelectedObject):toBe(find(stack, "HomeAction"))
				end
				path:set({ { id = "inherited" } })
				expect(find(find(stack, "inherited"), "Destination").Position.Y.Offset):toBe(0)
				path:set({ { id = "owned" } })
				chrome:set("automatic")
				expect(find(find(stack, "owned"), "NavigationBar").Visible):toBe(true)
				expect(find(find(stack, "owned"), "Destination").Position.Y.Offset > 0):toBe(true)
				chrome:set("hidden")
				for _, origin in { 25, 200 } do
					find(world.screen, "Stack").InputBegan:Fire({
						UserInputType = world.engine.types.Enum.UserInputType.Touch,
						Position = world.engine.types.Vector3.new(origin, 0, 0),
					})
					find(world.screen, "Stack").TouchSwipe:Fire(world.engine.types.Enum.SwipeDirection.Right, 1)
					expect(#path:peek()):toBe(1)
				end
				find(world.screen, "Stack").InputBegan:Fire({
					UserInputType = world.engine.types.Enum.UserInputType.Touch,
					Position = world.engine.types.Vector3.new(0, 0, 0),
				})
				find(world.screen, "Stack").TouchSwipe:Fire(world.engine.types.Enum.SwipeDirection.Right, 1)
				expect(#path:peek()):toBe(0)
				world.stop()
			end,
		})

		it("hides the root page's top bar strip while a destination covers the page", {
			id = "native_navigation::native navigation controls::hides the root page's top bar strip while a destination covers the page",
			run = function()
				local path = Compose.cell({} :: { Navigation.NavigationEntry<number> })
				local wallet: Frame? = nil
				local world = setup(function(UI: FacetControls, _, engine, gui)
					engine.environment.poke(
						VerifyRoblox.assertInstance(gui),
						"TopbarInset",
						engine.types.Rect.new(164, 0, 844, 58)
					)
					local spec: NavigationProps.NavigationStackSpec<number> = {
						path = path,
						transition = false :: false,
						root = {
							title = "Home",
							content = function()
								local region = UI.Region "Wallet" {
									zone = "topbar" :: "topbar",
									rank = 1,
									UI.Text { text = "12.4K Credits" },
								}
								wallet = region
								return UI.Composition "Hud" { region }
							end,
						} :: Navigation.NavigationDestination<number>,
						destinations = {
							shop = {
								title = "Shop",
								content = function()
									return UI.Button "Buy" { label = "Buy" }
								end,
							} :: Navigation.NavigationDestination<number>,
						},
					}
					return UI.NavigationStack "Stack"(spec)
				end, { motionLevel = "none" })
				local strip = assert(wallet):FindFirstAncestorWhichIsA("ScreenGui") :: ScreenGui
				expect(strip.Name):toBe("CompositionTopbar")
				expect(strip.Enabled):toBe(true)
				path:set({ { id = "shop", value = 1 } })
				world.settle()
				expect(find(world.screen, "@root").Visible):toBe(false)
				expect(strip.Enabled):toBe(false)
				path:set({})
				world.settle()
				expect(strip.Enabled):toBe(true)
				world.stop()
			end,
		})

		it("moves the whole owned-header page and retains it through departure", {
			id = "native_navigation::native navigation controls::moves the whole owned-header page and retains it through departure",
			run = function()
				local path = Compose.cell({} :: { Navigation.NavigationEntry<unknown> })
				local world = setup(function(UI: FacetControls)
					local spec: NavigationProps.NavigationStackSpec<unknown> = {
						path = path,
						chrome = "hidden" :: "hidden",
						root = {
							content = function(): Instance
								return UI.Button "RootAction" { label = "Root" }
							end,
						} :: Navigation.NavigationDestination<unknown>,
						destinations = {
							detail = {
								content = function(): Instance
									return UI.Button "OwnedHeader" { label = "Own header" }
								end,
							} :: Navigation.NavigationDestination<unknown>,
						},
					}
					return UI.NavigationStack "OwnedMotion"(spec)
				end)
				local stack = find(world.screen, "OwnedMotion")
				world.gui.SelectedObject = find(stack, "RootAction")
				path:set({ { id = "detail" } })
				local page = find(stack, "detail")
				expect(page.Position.X.Scale):toBe(1)
				local last = 1
				for _ = 1, 12 do
					world.engine.heartbeat:Fire(1 / 60)
					expect(page.Position.X.Scale < last):toBe(true)
					expect(find(page, "Destination").Size):toBe(world.engine.types.UDim2.fromScale(1, 1))
					expect(find(page, "NavigationBar").Visible):toBe(false)
					expect(find(page, "Back")):toBeNil()
					last = page.Position.X.Scale
				end
				world.settle()
				path:set({})
				expect(not world.engine.environment.isAlive(page)):toBe(false)
				expect(page.Interactable):toBe(false)
				world.engine.heartbeat:Fire(1 / 60)
				expect(page.Position.X.Scale > 0):toBe(true)
				world.settle()
				expect(not world.engine.environment.isAlive(page)):toBe(true)
				expect(world.gui.SelectedObject):toBe(find(stack, "RootAction"))
				world.stop()
			end,
		})
		it("leaves a sibling's selection alone when the stack pops to an empty root", {
			id = "native_navigation::native navigation controls::leaves a sibling's selection alone when the stack pops to an empty root",
			run = function()
				local path = Compose.cell({} :: { Navigation.NavigationEntry<unknown> })
				local world = setup(function(UI: FacetControls)
					local spec: NavigationProps.NavigationStackSpec<unknown> = {
						path = path,
						chrome = "hidden" :: "hidden",
						root = {
							content = function(): Instance
								return UI.Text "Empty" { text = "Nothing here" }
							end,
						} :: Navigation.NavigationDestination<unknown>,
						destinations = {
							detail = {
								content = function(): Instance
									return UI.Button "DetailAction" { label = "Detail" }
								end,
							} :: Navigation.NavigationDestination<unknown>,
						},
					}
					return UI.VStack "Room" {
						UI.Button "Sibling" { label = "Sibling" },
						UI.NavigationStack "App"(spec),
					}
				end)
				local stack = find(world.screen, "App")
				local sibling = find(world.screen, "Sibling")
				path:set({ { id = "detail" } })
				world.settle()
				expect(world.gui.SelectedObject):toBe(nil)
				world.gui.SelectedObject = find(stack, "DetailAction")
				world.settle()
				world.gui.SelectedObject = sibling
				path:set({})
				world.settle()
				expect(world.gui.SelectedObject):toBe(sibling)
				path:set({ { id = "detail" } })
				world.settle()
				expect(world.gui.SelectedObject):toBe(find(stack, "DetailAction"))
				world.stop()
			end,
		})
		it("owns gameplay suspension across destination replacement and restores prior input", function()
			for _, inKart in { true, false } do
				local path = Compose.cell({} :: { Navigation.NavigationEntry<unknown> })
				local driving = Compose.cell(inKart)
				local disposed: { [string]: boolean } = {}
				local writes = 0
				local gameplay: InputContext
				local suspended: Compose.ReadOnlyValue<boolean>
				local world = setup(function(UI: FacetControls, _Host: RobloxHost, engine)
					gameplay = (engine.new("InputContext") :: unknown) :: InputContext
					suspended = UI.environment().gameplaySuspended
					Compose.watch(function(use: Compose.Use)
						gameplay.Enabled = use(driving) and not use(suspended)
						writes += 1
					end)
					local function destination(name: string): Navigation.NavigationDestination<unknown>
						return {
							content = function(): Instance
								Compose.cleanup(function()
									disposed[name] = true
								end)
								return UI.Button { label = name }
							end,
						}
					end
					local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
						path = path,
						chrome = "hidden",
						root = {
							content = function(): Instance
								return UI.Button { label = "Gameplay" }
							end,
						},
						destinations = { first = destination("first"), second = destination("second") },
					}
					return UI.NavigationStack(controlProps)
				end, { suspendGameplay = true })
				expect(gameplay.Enabled):toBe(inKart)
				path:set({ { id = "first" } })
				world.settle()
				expect(gameplay.Enabled):toBe(false)
				expect(world.gui.TouchControlsEnabled):toBe(false)
				local before = writes
				path:set({ { id = "first" }, { id = "second" } })
				path:set({ { id = "second" } })
				expect(writes):toBe(before)
				world.settle()
				expect(disposed.first):toBe(true)
				driving:set(not inKart)
				expect(gameplay.Enabled):toBe(false)
				path:set({})
				expect(gameplay.Enabled):toBe(not inKart)
				expect(world.gui.TouchControlsEnabled):toBe(true)
				world.settle()
				expect(disposed.second):toBe(true)
				path:set({ { id = "first" } })
				expect(suspended:peek()):toBe(true)
				world.stop()
				expect(gameplay.Enabled):toBe(not inKart)
				expect(world.gui.TouchControlsEnabled):toBe(true)
			end
		end)
		it("keeps gameplay suspended until both a page and a Sheet over it close", function()
			for _, pageFirst in { true, false } do
				local path = Compose.cell({} :: { Navigation.NavigationEntry<unknown> })
				local opened = Compose.cell(false)
				local suspended: Compose.ReadOnlyValue<boolean>
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					suspended = UI.environment().gameplaySuspended
					local navigationstackProps1: NavigationProps.NavigationStackSpec<unknown> = {
						path = path,
						chrome = "hidden",
						root = {
							content = function(): Instance
								return UI.Button { label = "Gameplay" }
							end,
						},
						destinations = {
							shop = {
								content = function(): Instance
									return UI.Button { label = "Shop" }
								end,
							},
						},
					}
					return Host.Frame {
						UI.NavigationStack(navigationstackProps1),
						UI.Sheet {
							isPresented = opened,
							content = function(): Instance
								return Host.Frame {}
							end,
						},
					}
				end, { suspendGameplay = true })
				expect(suspended:peek()):toBe(false)
				world.gui.TouchControlsEnabled = false
				path:set({ { id = "shop" } })
				world.gui.TouchControlsEnabled = true
				expect(world.gui.TouchControlsEnabled):toBe(false)
				opened:set(true)
				world.settle()
				expect(suspended:peek()):toBe(true)
				expect(world.gui.TouchControlsEnabled):toBe(false)
				if pageFirst then
					path:set({})
				else
					opened:set(false)
				end
				world.settle()
				expect(suspended:peek()):toBe(true)
				expect(world.gui.TouchControlsEnabled):toBe(false)
				if pageFirst then
					opened:set(false)
				else
					path:set({})
				end
				world.settle()
				expect(suspended:peek()):toBe(false)
				expect(world.gui.TouchControlsEnabled):toBe(true)
				world.stop()
			end
		end)
		it("places floating tab tracks and marks inside phone and landscape bounds", {
			id = "native_navigation::native navigation controls::places floating tab tracks and marks inside phone and landscape bounds",
			run = function()
				local selected = Compose.cell("games")
				local placement = Compose.cell("bottomBar" :: Navigation.Placement)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local spec: NavigationProps.TabViewSpec = {
						selection = selected,
						placement = placement,
						track = "floating" :: "floating",
						indicator = "mark" :: "mark",
						labelPlacement = "belowIcon" :: "belowIcon",
						controlSize = "compact" :: "compact",
						railWidth = 140,
						tabs = {
							{
								id = "games",
								label = "Games",
								icon = "view.grid",
								badge = 1,
								badgeAnchor = "topLeading" :: "topLeading",
								content = function()
									return Host.Frame {}
								end,
							} :: Navigation.Tab,
							{
								id = "profile",
								label = "Profile",
								icon = "person",
								content = function()
									return Host.Frame {}
								end,
							} :: Navigation.Tab,
						},
					}
					return UI.TabView "Floating"(spec)
				end, { motionLevel = "none" })
				local root = find(world.screen, "Floating") :: Frame
				local Vector2, UDim2 = world.engine.types.Vector2, world.engine.types.UDim2
				for _, size in { Vector2.new(320, 640), Vector2.new(390, 844) } do
					world.engine.environment.poke(VerifyRoblox.assertInstance(root), "AbsoluteSize", size)
					local track, tabs = find(root, "Track"), find(root, "Tabs")
					expect(track.Visible):toBe(true)
					expect(track.Position):toBe(UDim2.new(0, 16, 1, -76))
					expect(track.Size):toBe(UDim2.new(1, -32, 0, 64))
					expect(find(root, "TabBand").Position):toBe(track.Position)
					expect(find(root, "TabBand").Size):toBe(track.Size)
					expect(tabs.Size):toBe(UDim2.fromScale(1, 1))
					expect(track:FindFirstChildWhichIsA("UICorner").CornerRadius.Offset):toBe(20)
					local button = find(tabs, "games")
					expect(button:HasTag("facet-selected")):toBe(false)
					expect(button:HasTag("facet-tab-filled")):toBe(false)
					local mark = find(button, "SelectionIndicator")
					expect(mark ~= nil):toBe(true)
					expect(mark.Size):toBe(UDim2.fromOffset(20, 4))
					expect(mark.AnchorPoint):toBe(Vector2.new(0.5, 1))
					expect(mark.Position):toBe(UDim2.new(0.5, 0, 0, -4))
					expect(mark:FindFirstChildWhichIsA("UICorner").CornerRadius.Offset):toBe(2)
					expect(find(button, "Corner").Position):toBe(UDim2.fromScale(0, 0))
					expect((assert(root:FindFirstChild("Content")) :: Frame).Size.Y.Offset):toBe(-84)
				end
				placement:set("sidebar")
				world.engine.environment.poke(VerifyRoblox.assertInstance(root), "AbsoluteSize", Vector2.new(844, 390))
				local track = find(root, "Track")
				expect(track.Position):toBe(UDim2.fromOffset(8, 8))
				expect(track.Size):toBe(UDim2.new(0, 124, 1, -16))
				local mark = find(find(root, "games"), "SelectionIndicator")
				expect(mark.Position):toBe(UDim2.fromOffset(8, 4))
				expect(mark.Size):toBe(UDim2.new(1, -16, 1, -8))
				selected:set("profile")
				expect(find(find(root, "games"), "SelectionIndicator")):toBeNil()
				expect(find(find(root, "profile"), "SelectionIndicator") ~= nil):toBe(true)
				world.stop()
			end,
		})
		it("slides the tab bar out before the content grows and back in when placement returns", {
			id = "native_navigation::native navigation controls::slides the tab bar out before the content grows and back in when placement returns",
			run = function()
				local placement = Compose.cell("bottomBar" :: Navigation.Placement)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local spec: NavigationProps.TabViewSpec = {
						selection = Compose.cell("games"),
						placement = placement,
						tabs = {
							{
								id = "games",
								label = "Games",
								content = function()
									return Host.Frame {}
								end,
							} :: Navigation.Tab,
							{
								id = "profile",
								label = "Profile",
								content = function()
									return Host.Frame {}
								end,
							} :: Navigation.Tab,
						},
					}
					return UI.TabView "Chrome"(spec)
				end, { motionLevel = "normal" })
				local root = find(world.screen, "Chrome") :: Frame
				world.engine.environment.poke(
					VerifyRoblox.assertInstance(root),
					"AbsoluteSize",
					world.engine.types.Vector2.new(390, 760)
				)
				world.settle()
				local band, content = find(root, "TabBand"), assert(root:FindFirstChild("Content")) :: Frame
				local rest, inset = band.Position, content.Size
				placement:set("none")
				expect(band.Position):toBe(rest)
				expect(content.Size):toBe(inset)
				world.engine.heartbeat:Fire(1 / 60)
				world.engine.heartbeat:Fire(1 / 60)
				expect(band.Position.Y.Offset > rest.Y.Offset):toBe(true)
				expect(content.Size):toBe(inset)
				world.settle()
				expect(find(root, "Tabs").Visible):toBe(false)
				expect(content.Size):toBe(world.engine.types.UDim2.fromScale(1, 1))
				placement:set("bottomBar")
				expect(find(root, "Tabs").Visible):toBe(true)
				expect(content.Size):toBe(inset)
				expect(band.Position.Y.Offset > rest.Y.Offset):toBe(true)
				world.settle()
				expect(band.Position):toBe(rest)
				world.stop()
			end,
		})
		it("uses themed mark spacing and all badge corners without changing the default track", {
			id = "native_navigation::native navigation controls::uses themed mark spacing and all badge corners without changing the default track",
			run = function()
				local themes = require("../src/ui/themes")(Compose)
				local package = themes.neutralPackage()
				local metrics = assert(package.metrics.controls)
				metrics.tabBottomTrack = { height = 96, sideInset = 20, bottomInset = 18, radius = 0, contentGap = 10 }
				metrics.tabMark = { width = 24, height = 6, gap = 5, radius = 0 }
				local track = Compose.cell("floating" :: "automatic" | "floating")
				local indicator = Compose.cell("mark" :: Navigation.TabSelectionIndicator)
				local anchor =
					Compose.cell("topTrailing" :: "topLeading" | "topTrailing" | "bottomLeading" | "bottomTrailing")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local spec: NavigationProps.TabViewSpec = {
						selection = Compose.cell("one"),
						placement = "bottomBar" :: "bottomBar",
						track = track,
						indicator = indicator,
						indicatorPlacement = "belowIcon" :: "belowIcon",
						labelPlacement = "belowIcon" :: "belowIcon",
						controlSize = "compact" :: "compact",
						tabs = {
							{
								id = "one",
								label = "One",
								icon = "person",
								badge = 1,
								badgeAnchor = anchor,
								content = function()
									return Host.Frame {}
								end,
							} :: Navigation.Tab,
						},
					}
					return UI.TabView "ThemedTabs"(spec)
				end, { theme = assert((themes.define(package))), motionLevel = "none" })
				local root = find(world.screen, "ThemedTabs")
				local D2, V2 = world.engine.types.UDim2, world.engine.types.Vector2
				for _, size in { V2.new(320, 640), V2.new(390, 844), V2.new(844, 390) } do
					world.engine.environment.poke(VerifyRoblox.assertInstance(root), "AbsoluteSize", size)
					local plate = find(root, "Track")
					expect(plate.Position):toBe(D2.new(0, 20, 1, -114))
					expect(plate.Size):toBe(D2.new(1, -40, 0, 96))
					expect(size.X + plate.Size.X.Offset > 0):toBe(true)
					expect(size.Y + plate.Position.Y.Offset >= 0):toBe(true)
					expect(plate:FindFirstChildWhichIsA("UICorner").CornerRadius.Offset):toBe(0)
					expect(assert(root:FindFirstChild("Content")).Size.Y.Offset):toBe(-124)
				end
				local button = find(root, "one")
				local mark = find(button, "SelectionIndicator")
				expect(mark.Position):toBe(D2.new(0.5, 0, 1, 5))
				expect(mark.AnchorPoint):toBe(V2.new(0.5, 0))
				expect(mark.Size):toBe(D2.fromOffset(24, 6))
				local flow = assert(find(button, "Content"):FindFirstChildWhichIsA("UIListLayout"))
				expect(flow.Padding.Offset >= 16):toBe(true)
				local function checkCorner(
					choice: "topLeading" | "topTrailing" | "bottomLeading" | "bottomTrailing",
					x: number,
					y: number
				)
					anchor:set(choice)
					expect(find(button, "Corner").Position):toBe(D2.fromScale(x, y))
				end
				checkCorner("topLeading", 0, 0)
				checkCorner("topTrailing", 1, 0)
				checkCorner("bottomLeading", 0, 1)
				checkCorner("bottomTrailing", 1, 1)
				anchor:set("topTrailing")
				track:set("automatic")
				indicator:set("automatic")
				expect(find(button, "SelectionIndicator")):toBeNil()
				expect(find(root, "Track").Visible):toBe(false)
				expect(find(root, "Tabs").Position.X.Offset):toBe(0)
				expect(find(root, "Tabs").Size.X.Offset):toBe(0)
				expect(button:HasTag("facet-tab-filled")):toBe(true)
				world.stop()
			end,
		})
		it("bounds bottom tab captions and ellipsizes them inside every phone slot", {
			id = "native_navigation::native navigation controls::bounds bottom tab captions and ellipsizes them inside every phone slot",
			run = function()
				for _, width in { 320, 360, 375, 389, 430 } do
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local tabs: { Navigation.Tab } = {}
						for _, label in { "Discover", "Avatar", "Chat", "Flap" } do
							table.insert(tabs, {
								id = label,
								label = label,
								icon = "person",
								content = function()
									return Host.Frame {}
								end,
							})
						end
						return UI.TabView {
							selection = Compose.cell("Discover"),
							placement = "bottomBar" :: "bottomBar",
							tabs = tabs,
						}
					end)
					local bar = find(world.screen, "Tabs")
					world.engine.environment.poke(bar, "AbsoluteSize", world.engine.types.Vector2.new(width, 70))
					local button = find(bar, "Discover")
					world.engine.environment.poke(
						button,
						"AbsoluteSize",
						world.engine.types.Vector2.new(width / 4 - 4, 44)
					)
					world.engine.environment.poke(
						find(button, "Content"),
						"AbsoluteSize",
						world.engine.types.Vector2.new(width / 4 - 4, 44)
					)
					local title = find(button, "Title")
					expect(title.Size.X.Scale):toBe(0)
					expect(title.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
					expect(title.TextTruncate):toBe(world.engine.types.Enum.TextTruncate.AtEnd)
					expect(title.Size.X.Offset > 0 and title.Size.X.Offset < width / 4 - 4):toBe(true)
					world.stop()
				end
			end,
		})

		it("stacks destination labels below icons in an equal phone bar", {
			id = "native_navigation::native navigation controls::stacks destination labels below icons in an equal phone bar",
			run = function()
				local choice = Compose.cell("belowIcon" :: "belowIcon" | "besideIcon")
				local selection = Compose.cell("games")
				local textSize = Compose.cell(32)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local function page(): Instance
						return Host.Frame {}
					end
					local tabs: { Navigation.Tab } = {
						{ id = "games", label = "Games", icon = "view.list", badge = 3, content = page },
						{ id = "profile", label = "Profile", icon = "person", content = page },
						{ id = "settings", label = "Settings", icon = "settings", content = page },
					}
					local props: NavigationProps.TabViewSpec = {
						selection = selection,
						labelPlacement = choice,
						textSize = textSize,
						placement = "bottomBar" :: "bottomBar",
						tabs = tabs,
					}
					return UI.TabView(props)
				end)
				local bar = find(world.screen, "Tabs")
				world.engine.environment.poke(bar, "AbsoluteSize", world.engine.types.Vector2.new(389, 80))
				for _, id in { "games", "profile", "settings" } do
					local button = find(bar, id)
					expect(button.Size.X.Scale):toBe(world.engine.types.UDim.new(1 / 3, 0).Scale)
					expect(find(button, "Title").Size.Y.Offset >= 32):toBe(true)
					expect(button.Size.Y.Offset >= 72):toBe(true)
					expect(find(button, "Content"):FindFirstChildWhichIsA("UIListLayout").FillDirection):toBe(
						world.engine.types.Enum.FillDirection.Vertical
					)
					expect(find(button, "Title").Size.X.Scale):toBe(1)
				end
				textSize:set(16)
				expect(find(find(bar, "games"), "Title").Size.Y.Offset >= 16):toBe(true)
				expect(find(bar, "games").Size.Y.Offset < 72):toBe(true)
				find(bar, "profile").Activated:Fire()
				expect(selection:peek()):toBe("profile")
				choice:set("besideIcon")
				expect(find(find(bar, "games"), "Content"):FindFirstChildWhichIsA("UIListLayout").FillDirection):toBe(
					world.engine.types.Enum.FillDirection.Horizontal
				)
				world.stop()
			end,
		})
		it("keeps five lower phone commands and Close inside the safe modal room", {
			id = "native_navigation::native navigation controls::keeps five lower phone commands and Close inside the safe modal room",
			run = function()
				local opened = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					local items: { Navigation.MenuItem<string> } = {}
					for _, id in { "swap", "pass", "zoom", "help", "resign" } do
						local command: Navigation.MenuCommand = { id = id, label = id, onSelect = noop }
						table.insert(items, command)
					end
					local controlProps: NavigationProps.MenuSpec<string> = { isPresented = opened, items = items }
					return UI.Menu(controlProps)
				end)
				world.engine.environment.poke(world.screen, "AbsoluteSize", world.engine.types.Vector2.new(389, 704))
				world.engine.environment.poke(world.input, "TouchEnabled", true)
				world.engine.environment.poke(world.input, "MouseEnabled", false)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Touch
				)
				local panel = find(world.screen, "MenuPanel")
				world.engine.environment.poke(panel.Parent, "AbsoluteSize", world.engine.types.Vector2.new(389, 704))
				world.engine.environment.poke(
					find(panel, "MenuRows"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(349, 320)
				)
				world.engine.environment.poke(
					panel,
					"AbsoluteSize",
					world.engine.types.Vector2.new(365, panel.Size.Y.Offset)
				)
				expect(panel.Size.Y.Offset):toBeLessThanOrEqual(704 - 24)
				expect(panel.Size.X.Scale):toBe(1)
				expect(find(panel, "CloseCommand") ~= nil):toBe(true)
				find(panel, "resign").Activated:Fire()
				expect(opened:peek()):toBe(false)
				world.stop()
			end,
		})
		it("limits the default menu Close to sheets and retains explicit overrides", {
			id = "native_navigation::native navigation controls::limits the default menu Close to sheets and retains explicit overrides",
			run = function()
				local opened = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					local command: Navigation.MenuCommand = menuCommand("action", "Action")
					local spec: NavigationProps.MenuSpec<string> = {
						isPresented = opened,
						items = { command },
					}
					return UI.Menu(spec)
				end)
				local command = find(world.screen, "CloseCommand")
				expect(command == nil or not command.Visible):toBe(true)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Touch
				)
				command = find(world.screen, "CloseCommand")
				expect(command ~= nil):toBe(true)
				expect(command.Visible):toBe(true)
				expect(command.Text):toBe("")
				expect(command:GetAttribute("label")):toBe("Close")
				command.Activated:Fire()
				expect(opened:peek()):toBe(false)
				world.stop()
				for _, override in { true, false } do
					opened:set(true)
					local explicit = setup(function(UI: FacetControls)
						local command: Navigation.MenuCommand = menuCommand("action", "Action")
						local spec: NavigationProps.MenuSpec<string> = {
							isPresented = opened,
							closeButton = override,
							items = { command },
						}
						return UI.Menu(spec)
					end)
					local close = find(explicit.screen, "CloseCommand")
					expect(close ~= nil and close.Visible):toBe(override)
					explicit.engine.environment.poke(
						explicit.input,
						"PreferredInput",
						explicit.engine.types.Enum.PreferredInput.Touch
					)
					close = find(explicit.screen, "CloseCommand")
					expect(close ~= nil and close.Visible):toBe(override)
					explicit.stop()
				end
				opened:set(true)
				world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = opened,
						detent = Compose.cell("medium"),
						placement = "center",
						content = function(): Instance
							return Host.Frame {}
						end,
					}
				end)
				find(world.screen, "Close").Activated:Fire()
				expect(opened:peek()):toBe(false)
				world.stop()
			end,
		})
		it("accepts a fresh route object after departure and during reversal", {
			id = "native_navigation::native navigation controls::accepts a fresh route object after departure and during reversal",
			run = function()
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<number> })
				local world = setup(function(UI)
					local controlProps: NavigationProps.NavigationStackSpec<number> = {
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
					return UI.NavigationStack(controlProps)
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
							expect(node.Interactable):toBe(true)
							expect(node.Visible):toBe(true)
						end
					end
					expect(panels):toBe(1)
				end
				world.stop()
			end,
		})
		it("prepares CollapsibleView chrome before content paints without travel", {
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
					world.engine.environment.poke(
						world.screen,
						"AbsoluteSize",
						world.engine.types.Vector2.new(960, 720)
					)
					world.engine.environment.poke(
						find(world.screen, "Summary"),
						"AbsoluteSize",
						world.engine.types.Vector2.new(240, 44)
					)
					expanded:set(true)
					local panel, fade = find(world.screen, "Expanded"), find(world.screen, "ExpandedFade")
					local content = find(panel, "ContentBox")
					local V2 = world.engine.types.Vector2.new
					world.engine.environment.poke(panel, "AbsoluteSize", V2(360, 200))
					world.engine.environment.poke(content, "AbsoluteSize", V2(360, 200))
					expect(fadeKit.of(panel)):toBe(1)
					world.engine.heartbeat:Fire(1 / 60)
					world.engine.environment.poke(content, "AbsoluteSize", V2(328, 168))
					world.engine.environment.poke(find(panel, "Copy"), "AbsoluteSize", V2(296, 48))
					world.engine.heartbeat:Fire(1 / 60)
					expect(fadeKit.of(panel)):toBe(1)
					for _ = 1, 6 do
						world.engine.heartbeat:Fire(1 / 60)
						expect(panel.Size.X.Offset):toBe(360)
						expect(panel.Size.Y.Offset):toBe(44)
					end
					world.settle()
					expect(fadeKit.of(panel)):toBe(0)
					expect(fade.Size.X.Offset):toBe(328)
					expanded:set(false)
					world.settle()
					expect(find(world.screen, "Expanded")):toBe(nil)
					world.stop()
				end
			end,
		})
		it("selects enabled picker values once and honors changing veto", {
			id = "native_navigation::native navigation controls::selects enabled picker values once and honors changing veto",
			run = function()
				local selected, changes = Compose.cell("one"), 0
				local world = setup(function(UI: FacetControls)
					local spec: NavigationProps.SinglePickerSpec<string> = {
						selected = selected,
						style = "segmented" :: "segmented",
						options = {
							{ value = "one", label = "One" } :: Navigation.PickerOption<string>,
							{ value = "two", label = "Two" } :: Navigation.PickerOption<string>,
							{ value = "three", label = "Three", enabled = false } :: Navigation.PickerOption<string>,
						},
						onChanging = function(value: string)
							return value ~= "one"
						end,
						onChange = function()
							changes += 1
						end,
					}
					return UI.Picker(spec)
				end)
				find(world.screen, "three").Activated:Fire()
				expect((selected:peek())):toBe("one")
				find(world.screen, "two").Activated:Fire()
				find(world.screen, "two").Activated:Fire()
				find(world.screen, "one").Activated:Fire()
				expect((selected:peek())):toBe("two")
				expect(changes):toBe(1)
				world.stop()
			end,
		})

		it("shows a labelled segmented picker beside its label and a labelled list above it", {
			id = "native_navigation::native navigation controls::shows a labelled segmented picker beside its label and a labelled list above it",
			run = function()
				local selected = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local pickerProps1: NavigationProps.SinglePickerSpec<string> = {
						label = "Mode",
						LayoutOrder = 3,
						selected = selected,
						style = "segmented" :: "segmented",
						options = {
							{ value = "one", label = "One", icon = "edit" } :: Navigation.PickerOption<string>,
							{ value = "two", label = "Two", icon = "edit" } :: Navigation.PickerOption<string>,
						},
					}
					local pickerProps2: NavigationProps.SinglePickerSpec<string> = {
						label = "Group",
						selected = selected,
						style = "inline" :: "inline",
						options = {
							{ value = "one", label = "One", icon = "edit" } :: Navigation.PickerOption<string>,
							{ value = "two", label = "Two", icon = "edit" } :: Navigation.PickerOption<string>,
						},
					}
					return Host.Frame {
						UI.Picker "Segments"(pickerProps1),
						UI.Picker "List"(pickerProps2),
					}
				end)
				local segments = find(world.screen, "Segments")
				expect(segments.LayoutOrder):toBe(3)
				expect(segments:FindFirstChild("Label").Text):toBe("Mode")
				local options = segments:FindFirstChild("Options")
				expect((options:HasTag("facet-segmented"))):toBe(true)
				expect(segments:FindFirstChild("Label"):FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(
					world.engine.types.Enum.UIFlexMode.Grow
				)
				expect(segments:FindFirstChildWhichIsA("UIListLayout").Wraps):toBe(true)
				expect(options.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.X)
				expect(options.Size.Y.Offset):toBe(50)
				expect(find(options, "one").Size.Y.Offset + 6):toBe(options.Size.Y.Offset)
				expect(segments:FindFirstChildWhichIsA("UIListLayout").FillDirection):toBe(
					world.engine.types.Enum.FillDirection.Horizontal
				)
				local list = find(world.screen, "List")
				expect(list:FindFirstChild("Label").Text):toBe("Group")
				expect(list:FindFirstChildWhichIsA("UIListLayout").FillDirection):toBe(
					world.engine.types.Enum.FillDirection.Vertical
				)
				local Horizontal = world.engine.types.Enum.HorizontalAlignment
				local function alignment(button)
					return button:FindFirstChild("Content"):FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment
				end
				expect((alignment(find(segments, "one")))):toBe(Horizontal.Center)
				expect((alignment(find(list, "one")))):toBe(Horizontal.Left)
				find(segments, "two").Activated:Fire()
				expect((selected:peek())):toBe("two")
				world.stop()
			end,
		})

		it("mounts menus in the native layer, traverses submenus and closes after action", {
			id = "native_navigation::native navigation controls::mounts menus in the native layer, traverses submenus and closes after action",
			run = function()
				local opened, count = Compose.cell(false), 0
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.MenuSpec<string> = {
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
					}
					return UI.Menu(controlProps)
				end)
				opened:set(true)
				local panel = find(world.screen, "MenuPanel")
				expect(panel.Parent.Parent):toBe(world.screen)
				find(world.screen, "Nested").Activated:Fire()
				find(world.screen, "Run").Activated:Fire()
				expect(count):toBe(1)
				expect((opened:peek())):toBe(false)
				world.settle()
				expect((find(world.screen, "MenuPanel"))):toBe(nil)
				world.stop()
			end,
		})

		it("traps all modal selection directions and restores surviving focus on Back", {
			id = "native_navigation::native navigation controls::traps all modal selection directions and restores surviving focus on Back",
			run = function()
				local presented = Compose.cell(false)
				local cancelled = 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost, _, gui)
					local button = UI.Button "Original" { label = "Original" }
					gui.SelectedObject = button
					local alertProps1: NavigationProps.AlertSpec<unknown> = {
						isPresented = presented,
						title = "Confirm",
						actions = {
							{ id = "Disabled", label = "No", enabled = false },
							{
								id = "Cancel",
								label = "Cancel",
								role = "cancel" :: "cancel",
								onActivate = function()
									cancelled += 1
								end,
							},
							{ id = "Accept", label = "Accept" },
						},
					}
					return Host.Frame {
						button,
						UI.Alert(alertProps1),
					}
				end)
				presented:set(true)
				local panel = find(world.screen, "AlertPanel")
				for _, direction in { "Up", "Down", "Left", "Right" } :: { "Down" | "Left" | "Right" | "Up" } do
					expect(panel["SelectionBehavior" .. direction]):toBe(world.engine.types.Enum.SelectionBehavior.Stop)
				end
				expect(assert(world.gui.SelectedObject).Name):toBe("Cancel")
				local back = find(world.screen, "ModalBack")
				expect(back.Parent.Parent):toBe(world.screen)
				back.Pressed:Fire()
				expect((presented:peek())):toBe(false)
				expect(cancelled):toBe(1)
				expect(assert(world.gui.SelectedObject).Name):toBe("Original")
				world.settle()
				expect((not world.engine.environment.isAlive(back))):toBe(true)
				world.stop()
			end,
		})

		it("captures alert payload and closes before invoking its action", {
			id = "native_navigation::native navigation controls::captures alert payload and closes before invoking its action",
			run = function()
				local item = Compose.cell({ id = "payload" } :: { id: string }?)
				local result: { id: string, item: { id: string }? }? = nil
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.AlertSpec<{ id: string }> = {
						item = item,
						title = function(payload)
							return payload.id
						end,
						actions = {
							{
								id = "Accept",
								label = "Accept",
								onActivate = function(payload)
									result = { id = payload.id, item = item:peek() }
								end,
							},
						},
					}
					return UI.Alert<<{ id: string }>>(controlProps)
				end)
				find(world.screen, "Accept").Activated:Fire()
				expect((item:peek())):toBe(nil)
				expect(assert(result).id):toBe("payload")
				expect(assert(result).item):toBe(nil)
				world.stop()
			end,
		})

		it("owns disclosure content only while expanded", {
			id = "native_navigation::native navigation controls::owns disclosure content only while expanded",
			run = function()
				for _, appearance in { "plain", "contained", "divided" } :: { "contained" | "divided" | "plain" } do
					local expanded, built, disposed = Compose.cell(false), 0, 0
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.DisclosureGroup {
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
						}
					end)
					local header = find(world.screen, "Header")
					expect(built):toBe(0)
					local function checkOrder()
						local content = find(world.screen, "Details")
						local wrapped = if appearance == "divided" then content.Parent else content
						local body = fadeKit.layer(wrapped).Parent
						expect(body.Name):toBe("Reveal")
						expect(fadeKit.layer(wrapped).Name):toBe("RevealFade")
						expect(body.Parent):toBe(header.Parent)
						expect(header.LayoutOrder < body.LayoutOrder):toBe(true)
						expect(header.Parent:FindFirstChildWhichIsA("UIListLayout").SortOrder):toBe(
							world.engine.types.Enum.SortOrder.LayoutOrder
						)
						if appearance == "divided" then
							expect(find(wrapped, "Divider").LayoutOrder < content.LayoutOrder):toBe(true)
						end
						return content
					end
					local caret = find(header, "LeadingIcon")
					local closedIcon = caret.Image
					expanded:set(true)
					expect(caret.Image ~= closedIcon):toBe(true)
					local old = checkOrder()
					expanded:set(false)
					expect(caret.Image):toBe(closedIcon)
					expect((not world.engine.environment.isAlive(old))):toBe(true)
					expect(disposed):toBe(1)
					expanded:set(true)
					expect(checkOrder() ~= old):toBe(true)
					expect((find(world.screen, "Header"))):toBe(header)
					expect(built):toBe(2)
					world.stop()
					expect(disposed):toBe(2)
				end
			end,
		})

		it("retains visited tab state across selection and declaration reorders", {
			id = "native_navigation::native navigation controls::retains visited tab state across selection and declaration reorders",
			run = function()
				local selected, built, disposed = Compose.cell("one"), 0, 0
				local tabs: FixtureComposeTypes.Value<{ FixtureNavigationTypes.Tab }>? = nil
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local function content()
						built += 1
						Compose.cleanup(function()
							disposed += 1
						end)
						return Host.Frame "ContentState" {}
					end
					tabs = (Compose.cell :: any)({
						{ id = "one", label = "One", content = content },
						{ id = "two", label = "Two", content = content },
					})
					return UI.TabView { selection = selected, tabs = tabs :: any }
				end)
				selected:set("two")
				selected:set("one")
				local activeTabs = assert(tabs)
				local old = activeTabs:peek()
				activeTabs:set({ old[2], old[1] })
				expect(built):toBe(2)
				expect(disposed):toBe(0)
				expect((selected:peek())):toBe("one")
				world.stop()
				expect(disposed):toBe(2)
			end,
		})

		it("retains covered navigation destinations and disposes popped pages", {
			id = "native_navigation::native navigation controls::retains covered navigation destinations and disposes popped pages",
			run = function()
				local path, built, disposed = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> }), 0, 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local function content(entry: any): Instance
						built += 1
						Compose.cleanup(function()
							disposed += 1
						end)
						return Host.Frame { Name = if entry then "Detail" else "Root" }
					end
					local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
						path = path,
						root = { title = "Root", content = content } :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							detail = { title = "Detail", content = content } :: NavigationFixtures.NavigationDestination<any>,
						},
					}
					return UI.NavigationStack(controlProps)
				end)
				path:set({ { id = "detail" } })
				expect(built):toBe(2)
				expect(disposed):toBe(0)
				find(world.screen, "Back").Activated:Fire()
				expect(#path:peek()):toBe(0)
				expect(disposed):toBe(1)
				world.stop()
				expect(disposed):toBe(2)
			end,
		})

		it("uses native canvas scrolling for model navigation and completed swipes", {
			id = "native_navigation::native navigation controls::uses native canvas scrolling for model navigation and completed swipes",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.PageView {
						selection = selection,
						pages = {
							{ id = "one", title = "One", content = Host.Frame {} },
							{ id = "two", title = "Two", content = Host.Frame {} },
						},
					}
				end)
				local pages = find(world.screen, "Pages")
				world.engine.environment.poke(pages, "AbsoluteWindowSize", world.engine.types.Vector2.new(320, 160))
				world.engine.environment.poke(pages, "AbsoluteCanvasSize", world.engine.types.Vector2.new(640, 160))
				find(world.screen, "Next").Activated:Fire()
				expect((selection:peek())):toBe("two")
				expect(pages.CanvasPosition.X):toBe(320)
				pages.CanvasPosition = world.engine.types.Vector2.zero
				expect((selection:peek())):toBe("one")
				world.stop()
			end,
		})

		it("PageView measures pages while its ancestor blocks input for presentation", function()
			local world = setup(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame "PreparingPage" {
					Interactable = false,
					UI.PageView {
						selection = Compose.cell("one"),
						pages = {
							{ id = "one", label = "One", content = Host.Frame "FirstBody" {} },
							{ id = "two", label = "Two", content = Host.Frame "SecondBody" {} },
						},
					},
				}
			end)
			local pages = find(world.screen, "Pages")
			world.engine.environment.poke(pages, "AbsoluteWindowSize", world.engine.types.Vector2.new(320, 160))
			local row = find(pages, "Items"):FindFirstChild("one")
			expect(row.Size.X.Offset):toBe(320)
			expect(find(world.screen, "PreparingPage").Interactable):toBe(false)
			world.engine.environment.poke(pages, "AbsoluteWindowSize", world.engine.types.Vector2.new(480, 160))
			expect(row.Size.X.Offset):toBe(480)
			world.stop()
			expect(world.engine.census().connections):toBe(0)
		end)

		it("hugs its tallest page and centres the footer under it when its height is automatic", {
			id = "native_navigation::native navigation controls::hugs its tallest page and centres the footer under it when its height is automatic",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					return UI.PageView {
						Size = engine.types.UDim2.new(1, 0, 0, 0),
						AutomaticSize = engine.types.Enum.AutomaticSize.Y,
						selection = selection,
						pages = {
							{ id = "one", title = "One", content = Host.Frame "BodyOne" {} },
							{ id = "two", title = "Two", content = Host.Frame "BodyTwo" {} },
						},
					}
				end)
				local V = world.engine.types.Vector2
				world.engine.environment.poke(find(world.screen, "BodyOne"), "AbsoluteSize", V.new(300, 180))
				world.engine.environment.poke(find(world.screen, "BodyTwo"), "AbsoluteSize", V.new(300, 212.5))
				local pages, footer = find(world.screen, "Pages"), find(world.screen, "Footer")
				expect(pages.Size):toBe(world.engine.types.UDim2.new(1, 0, 0, 213))
				expect(footer.Position):toBe(world.engine.types.UDim2.fromOffset(0, 213))
				expect(footer:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment):toBe(
					world.engine.types.Enum.HorizontalAlignment.Center
				)
				world.stop()
			end,
		})

		it("keeps native drag position while card descendants hold contacts and snaps only after all release", {
			id = "native_navigation::native navigation controls::keeps native drag position while card descendants hold contacts and snaps only after all release",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls)
					return UI.PageView {
						selection = selection,
						pages = {
							{ id = "one", title = "One", content = UI.Button "CardOne" { label = "One" } },
							{ id = "two", title = "Two", content = UI.Button "CardTwo" { label = "Two" } },
						},
					}
				end)
				local pages = find(world.screen, "Pages")
				local V2, E = world.engine.types.Vector2, world.engine.types.Enum
				world.engine.environment.poke(pages, "AbsoluteWindowSize", V2.new(320, 160))
				world.engine.environment.poke(pages, "AbsoluteCanvasSize", V2.new(640, 160))
				local first, second = world.engine.new("InputObject"), world.engine.new("InputObject")
				world.engine.environment.poke(first, "UserInputType", E.UserInputType.Touch)
				world.engine.environment.poke(second, "UserInputType", E.UserInputType.Touch)
				local artwork = world.engine.new("Frame")
				artwork.Name = "LateArtwork"
				artwork.Parent = find(world.screen, "CardOne")
				artwork.InputBegan:Fire(first)
				pages.CanvasPosition = V2.new(120, 0)
				world.engine.heartbeat:Fire(1)
				expect(pages.CanvasPosition.X):toBe(120)
				expect(selection:peek()):toBe("one")
				find(world.screen, "CardOne").InputBegan:Fire(second)
				world.engine.environment.fire(world.input, "InputEnded", first)
				world.engine.heartbeat:Fire(1)
				expect(pages.CanvasPosition.X):toBe(120)
				world.engine.environment.fire(world.input, "InputEnded", second)
				for _ = 1, 120 do
					world.engine.heartbeat:Fire(0.016)
				end
				expect(pages.CanvasPosition.X):toBe(0)
				world.stop()
				expect(world.engine.census().connections):toBe(0)
			end,
		})

		it("snaps the showing page into place without motion when the pages frame resizes", {
			id = "native_navigation::native navigation controls::snaps the showing page into place without motion when the pages frame resizes",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.PageView {
						selection = Compose.cell("two"),
						pages = {
							{ id = "one", title = "One", content = Host.Frame {} },
							{ id = "two", title = "Two", content = Host.Frame {} },
						},
					}
				end)
				local pages = find(world.screen, "Pages")
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(pages, "AbsoluteWindowSize", V2.new(320, 160))
				world.engine.environment.poke(pages, "AbsoluteCanvasSize", V2.new(640, 160))
				expect(pages.CanvasPosition.X):toBe(320)
				world.engine.environment.poke(pages, "AbsoluteWindowSize", V2.new(640, 240))
				world.engine.environment.poke(pages, "AbsoluteCanvasSize", V2.new(1280, 240))
				expect(pages.CanvasPosition.X):toBe(640)
				world.stop()
			end,
		})

		it("pages by direction from a control inside the showing page", {
			id = "native_navigation::native navigation controls::pages by direction from a control inside the showing page",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.PageView {
						selection = selection,
						pages = {
							{
								id = "one",
								title = "One",
								content = Host.Frame { UI.Button "PlayOne" { label = "One" } },
							},
							{
								id = "two",
								title = "Two",
								content = Host.Frame { UI.Button "PlayTwo" { label = "Two" } },
							},
						},
					}
				end)
				local Enum = world.engine.types.Enum
				local play = find(world.screen, "PlayOne")
				local pages = find(world.screen, "Pages")
				world.engine.environment.poke(pages, "AbsoluteWindowSize", world.engine.types.Vector2.new(320, 160))
				world.engine.environment.poke(pages, "AbsoluteCanvasSize", world.engine.types.Vector2.new(640, 160))
				world.gui.SelectedObject = play
				expect(play.NextSelectionRight):toBe(play)
				world.engine.environment.fire(world.input, "InputBegan", {
					KeyCode = Enum.KeyCode.DPadRight,
					UserInputType = Enum.UserInputType.Gamepad1,
				})
				expect((selection:peek())):toBe("two")
				expect(world.gui.SelectedObject):toBe(find(world.screen, "PlayTwo"))
				world.engine.environment.fire(
					world.input,
					"InputBegan",
					{ KeyCode = Enum.KeyCode.Left, UserInputType = Enum.UserInputType.Keyboard }
				)
				expect((selection:peek())):toBe("one")
				world.gui.SelectedObject = find(world.screen, "Next")
				world.engine.environment.fire(world.input, "InputBegan", {
					KeyCode = Enum.KeyCode.Right,
					UserInputType = Enum.UserInputType.Keyboard,
				})
				expect((selection:peek())):toBe("one")
				world.stop()
			end,
		})

		it("validates combo custom commits and cancels editable text", {
			id = "native_navigation::native navigation controls::validates combo custom commits and cancels editable text",
			run = function()
				local value, text, changes = Compose.cell("a"), Compose.cell("Alpha"), 0
				local world = setup(function(UI: FacetControls)
					return UI.ComboBox {
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
					}
				end)
				local editor = find(world.screen, "Editor")
				editor.Focused:Fire()
				editor.Text = "Rejected"
				editor.FocusLost:Fire(true)
				expect((value:peek())):toBe("a")
				expect(find(world.screen, "Validation").Text):toBe("Rejected")
				editor.Focused:Fire()
				editor.Text = "Custom"
				editor.FocusLost:Fire(true)
				expect((value:peek())):toBe("Custom")
				expect(changes):toBe(1)
				world.stop()
			end,
		})

		it("hides an empty ComboBox popup and restores it when matches return", {
			id = "native_navigation::native navigation controls::hides an empty ComboBox popup and restores it when matches return",
			run = function()
				local text = Compose.cell("zzq")
				local world = setup(function(UI: FacetControls)
					return UI.ComboBox {
						value = Compose.cell("a"),
						text = text,
						options = { { value = "a", label = "Alpha" } },
						acceptCustom = function()
							return false, nil
						end,
					}
				end)
				find(find(world.screen, "Suggestions"), "Trigger").Activated:Fire()
				expect(find(world.screen, "MenuPanel")):toBe(nil)
				text:set("Al")
				expect(find(world.screen, "MenuPanel") ~= nil):toBe(true)
				text:set("zzq")
				expect(find(world.screen, "MenuPanel")):toBe(nil)
				world.stop()
			end,
		})

		it("keeps combo suggestions beside a single line and preserves native typing until Down", {
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
							return true, nil
						end,
						onChange = function()
							changes += 1
						end,
					}
				end)
				local root = find(world.screen, "SearchCombo")
				local row, editor, suggestions = find(root, "Row"), find(root, "Editor"), find(root, "Suggestions")
				local trigger = find(suggestions, "Trigger")
				expect(editor.Parent):toBe(row)
				expect(suggestions.Parent):toBe(row)
				expect(row.Size.Y.Offset):toBe(44)
				expect(editor.Size.X.Scale):toBe(1)
				expect(editor.Size.X.Offset):toBe(-60)
				expect(editor.Size.Y.Scale):toBe(1)
				expect(suggestions.Position.X.Scale):toBe(1)
				expect(suggestions.Position.X.Offset):toBe(-56)
				expect(suggestions.Position.Y.Offset):toBe(0)
				expect(suggestions.Size.Y.Scale):toBe(1)
				expect(trigger.Size.Y.Scale):toBe(1)
				expect(trigger.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				editor:CaptureFocus()
				world.gui.SelectedObject = editor
				editor.Text = "a"
				local overlay = find(world.screen, "SuggestionsOverlay")
				expect(overlay ~= nil):toBe(true)
				expect(overlay.Parent):toBe(world.screen)
				expect((find(overlay, "ModalBack"))):toBe(nil)
				expect((editor:IsFocused())):toBe(true)
				expect(editor.TextEditable):toBe(true)
				expect(world.gui.SelectedObject):toBe(editor)
				editor.Text = "be"
				expect(find(overlay, "b") ~= nil):toBe(true)
				expect((find(overlay, "a"))):toBe(nil)
				expect((find(root, "Editor"))):toBe(editor)
				expect((editor:IsFocused())):toBe(true)
				find(world.screen, "ComboSuggestions").Pressed:Fire()
				expect((editor:IsFocused())):toBe(false)
				expect(world.gui.SelectedObject):toBe(find(overlay, "b"))
				expect(validations):toBe(0)
				expect(changes):toBe(0)
				find(overlay, "b").Activated:Fire()
				expect((value:peek())):toBe("b")
				expect((text:peek())):toBe("Beta")
				expect(changes):toBe(1)
				expect((find(world.screen, "SuggestionsOverlay"))):toBe(nil)
				expect(world.gui.SelectedObject):toBe(editor)
				editor:CaptureFocus()
				editor.Text = "al"
				find(world.screen, "ComboSuggestions").Pressed:Fire()
				expect(assert(world.gui.SelectedObject).Name):toBe("a")
				find(world.screen, "ComboCancel").Pressed:Fire()
				expect((text:peek())):toBe("Beta")
				expect((value:peek())):toBe("b")
				expect((editor:IsFocused())):toBe(true)
				expect((find(world.screen, "SuggestionsOverlay"))):toBe(nil)
				expect(validations):toBe(0)
				expect(changes):toBe(1)
				world.stop()
			end,
		})

		it("closes combo suggestions outside the field and honors custom focus-loss policy", {
			id = "native_navigation::native navigation controls::closes combo suggestions outside the field and honors custom focus-loss policy",
			run = function()
				local value, text, enabled = Compose.cell("a"), Compose.cell("Alpha"), Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.ComboBox {
						value = value,
						text = text,
						enabled = enabled,
						options = { { value = "a", label = "Alpha" } :: Navigation.PickerOption<string> },
						acceptCustom = function()
							return true, nil
						end,
					}
				end)
				local editor = find(world.screen, "Editor")
				editor:CaptureFocus()
				editor.Text = "Custom"
				editor:ReleaseFocus(false)
				expect((value:peek())):toBe("a")
				expect((text:peek())):toBe("Custom")
				world.engine.environment.fire(world.input, "InputBegan", {
					UserInputType = world.engine.types.Enum.UserInputType.MouseButton1,
					Position = world.engine.types.Vector3.new(1000, 1000, 0),
				})
				expect((find(world.screen, "SuggestionsOverlay"))):toBe(nil)
				find(find(world.screen, "Suggestions"), "Trigger").Activated:Fire()
				expect(find(world.screen, "SuggestionsOverlay")):toBe(nil)
				text:set("Al")
				find(find(world.screen, "Suggestions"), "Trigger").Activated:Fire()
				expect(find(world.screen, "SuggestionsOverlay") ~= nil):toBe(true)
				enabled:set(false)
				expect((find(world.screen, "SuggestionsOverlay"))):toBe(nil)
				world.stop()

				local enabledCommit = Compose.cell(true)
				local committing = setup(function(UI: FacetControls)
					return UI.ComboBox {
						value = value,
						text = text,
						enabled = enabledCommit,
						commitOnFocusLost = true,
						options = { { value = "a", label = "Alpha" } :: Navigation.PickerOption<string> },
						acceptCustom = function(candidate)
							if candidate == "Disable" then
								enabledCommit:set(false)
							end
							return true, nil
						end,
					}
				end)
				local committingEditor = find(committing.screen, "Editor")
				committingEditor:CaptureFocus()
				committingEditor.Text = "Custom"
				committingEditor:ReleaseFocus(false)
				expect((value:peek())):toBe("Custom")
				committingEditor:CaptureFocus()
				committingEditor.Text = "Disable"
				committingEditor:ReleaseFocus(true)
				expect((value:peek())):toBe("Custom")
				committing.stop()
			end,
		})

		it("reopens combo suggestions after selected-result alerts finish their exit and the editor refocuses", {
			id = "native_navigation::native navigation controls::reopens combo suggestions after selected-result alerts finish their exit and the editor refocuses",
			run = function()
				local value, text, presented = Compose.cell(""), Compose.cell(""), Compose.cell(false)
				local changes = 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local alertProps1: NavigationProps.AlertSpec<unknown> = {
						isPresented = presented,
						title = "Selected game",
						transition = { seconds = 0.1 },
						actions = {
							{ id = "CloseResult", label = "Close", role = "cancel" :: "cancel" },
						},
					}
					return Host.Frame {
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
								return true, nil
							end,
							onChange = function()
								changes += 1
								presented:set(true)
							end,
						},
						UI.Alert "Result"(alertProps1),
					}
				end)
				local editor = find(world.screen, "Editor")
				world.engine.environment.fakeOn(world.input, "GetFocusedTextBox", function()
					return if editor:IsFocused() then editor else nil
				end)
				for index, choice in { "Circuit", "Forest", "Circuit" } do
					editor:CaptureFocus()
					expect((editor:IsFocused())):toBe(true)
					editor.Text = ""
					expect((text:peek())):toBe("")
					for length = 1, #choice do
						editor.Text = string.sub(choice, 1, length)
					end
					expect((text:peek())):toBe(choice)
					expect((editor:IsFocused())):toBe(true)
					local menu = find(world.screen, "MenuPanel")
					expect(menu ~= nil):toBe(true)
					find(menu, string.lower(choice)).Activated:Fire()
					expect((value:peek())):toBe(string.lower(choice))
					expect(changes):toBe(index)
					expect((find(world.screen, "MenuPanel"))):toBe(nil)
					expect((presented:peek())):toBe(true)
					expect((editor:IsFocused())):toBe(false)
					find(world.screen, "CloseResult").Activated:Fire()
					expect((presented:peek())):toBe(false)
					world.engine.heartbeat:Fire(0.2)
					expect((find(world.screen, "AlertModal"))):toBe(nil)
					expect((find(world.screen, "Editor"))):toBe(editor)
				end
				world.stop()
			end,
		})

		it("snaps native sheet drags to declared detents and respects dismissal policy", {
			id = "native_navigation::native navigation controls::snaps native sheet drags to declared detents and respects dismissal policy",
			run = function()
				local opened, detent = Compose.cell(true), Compose.cell("large")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = opened,
						detent = detent,
						title = "Sheet",
						content = function(): Instance
							return Host.Frame "Body" {}
						end,
						interactiveDismissDisabled = true,
					}
				end)
				local drag = find(world.screen, "UIDragDetector")
				drag.DragStart:Fire(world.engine.types.Vector2.new(0, 0))
				drag.DragContinue:Fire(world.engine.types.Vector2.new(0, 400))
				drag.DragEnd:Fire()
				expect((detent:peek())):toBe("medium")
				find(world.screen, "ModalBack").Pressed:Fire()
				expect((opened:peek())):toBe(true)
				world.stop()
			end,
		})

		it("navigates radial branches and applies action completion", {
			id = "native_navigation::native navigation controls::navigates radial branches and applies action completion",
			run = function()
				local opened, count = Compose.cell(true), 0
				local world = setup(function(UI: FacetControls)
					local action: FixtureRadialTypes.RadialAction<string> = {
						id = "Action",
						label = "Action",
						completion = "root",
						onSelect = function()
							count += 1
						end,
					}
					local branch: FixtureRadialTypes.RadialAction<string> = {
						id = "Branch",
						label = "Branch",
						children = { action },
					}
					local unavailable: FixtureRadialTypes.RadialAction<string> =
						{ id = "Unavailable", label = "Unavailable", enabled = false }
					local radialProps: RadialProps.RadialMenuSpec<string> = {
						isPresented = opened,
						items = { branch, unavailable },
					}
					return (UI.RadialMenu :: any)(radialProps)
				end)
				find(world.screen, "Branch").Activated:Fire()
				find(world.screen, "Action").Activated:Fire()
				expect(count):toBe(1)
				expect((opened:peek())):toBe(true)
				expect(find(world.screen, "Branch") ~= nil):toBe(true)
				world.stop()
			end,
		})
		it("hides touch controls for a radial menu without suspending gameplay", function()
			local opened = Compose.cell(false)
			local suspended: Compose.ReadOnlyValue<boolean>
			local world = setup(function(UI: FacetControls)
				suspended = UI.environment().gameplaySuspended
				local action: FixtureRadialTypes.RadialAction<string> = { id = "Wave", label = "Wave" }
				local radialProps: RadialProps.RadialMenuSpec<string> = {
					isPresented = opened,
					items = { action },
				}
				return (UI.RadialMenu :: any)(radialProps)
			end, { suspendGameplay = true })
			opened:set(true)
			world.settle()
			expect(world.gui.TouchControlsEnabled):toBe(false)
			expect(suspended:peek()):toBe(false)
			opened:set(false)
			world.settle()
			expect(world.gui.TouchControlsEnabled):toBe(true)
			world.stop()
		end)
		it("blocks background shortcuts until the top modal leaves", {
			id = "native_navigation::native navigation controls::blocks background shortcuts until the top modal leaves",
			run = function()
				local presented, count = Compose.cell(false), 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local alertProps1: NavigationProps.AlertSpec<unknown> = { isPresented = presented, title = "Modal" }
					return Host.Frame {
						UI.Button "Background" {
							label = "Background",
							shortcut = { keyCode = "K" },
							onActivate = function()
								count += 1
							end,
						},
						UI.Alert(alertProps1),
					}
				end)
				local shortcut = find(world.screen, "Shortcut")
				shortcut.Pressed:Fire()
				expect(count):toBe(1)
				presented:set(true)
				expect(shortcut.Parent.Enabled):toBe(false)
				shortcut.Pressed:Fire()
				expect(count):toBe(1)
				presented:set(false)
				expect(shortcut.Parent.Enabled):toBe(true)
				shortcut.Pressed:Fire()
				expect(count):toBe(2)
				world.stop()
			end,
		})

		it("lets Back dismiss a disabled cancel action without invoking it", {
			id = "native_navigation::native navigation controls::lets Back dismiss a disabled cancel action without invoking it",
			run = function()
				local presented, count = Compose.cell(true), 0
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.AlertSpec<unknown> = {
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
							},
							{ id = "Continue", label = "Continue", shortcut = "defaultAction" },
						},
					}
					return UI.Alert(controlProps)
				end)
				find(world.screen, "ModalBack").Pressed:Fire()
				expect((presented:peek())):toBe(false)
				expect(count):toBe(0)
				world.stop()
			end,
		})

		it("runs a cancelAction action on Back and refuses a non-table transition", {
			id = "native_navigation::native navigation controls::runs a cancelAction action on Back and refuses a non-table transition",
			run = function()
				local presented, stayed = Compose.cell(true), 0
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.AlertSpec<unknown> = {
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
							},
							{ id = "Leave", label = "Leave" },
						},
					}
					return UI.Alert(controlProps)
				end)
				find(world.screen, "ModalBack").Pressed:Fire()
				expect(stayed):toBe(1)
				expect((presented:peek())):toBe(false)
				world.stop()
				expect(function()
					setup(function(UI: FacetControls)
						local controlProps: NavigationProps.AlertSpec<unknown> = {
							isPresented = Compose.cell(true),
							title = "Leave?",
							transition = ("instant" :: unknown) :: false,
						}
						return UI.Alert(controlProps)
					end)
				end):toThrow()
			end,
		})

		it("a disclosure given an Instance as content shows it again after a collapse", {
			id = "native_navigation::native navigation controls::a disclosure given an Instance as content shows it again after a collapse",
			run = function()
				local expanded = Compose.cell(true)
				local inside: any
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					inside = Host.TextLabel "Inside" { Text = "Inside" }
					return UI.DisclosureGroup { expanded = expanded, label = "Details", content = inside }
				end)
				world.engine.environment.poke(VerifyRoblox.assertInstance(world.gui), "ReducedMotionEnabled", true)
				expect((inside:IsDescendantOf(world.screen))):toBe(true)
				expanded:set(false)
				world.engine.heartbeat:Fire(1)
				expect((not world.engine.environment.isAlive(inside))):toBe(false)
				expanded:set(true)
				expect((inside:IsDescendantOf(world.screen))):toBe(true)
				world.stop()
			end,
		})

		it("a collapsible view given an Instance as content shows it again after a collapse", {
			id = "native_navigation::native navigation controls::a collapsible view given an Instance as content shows it again after a collapse",
			run = function()
				local expanded = Compose.cell(true)
				local inside: any
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					inside = Host.TextLabel "Inside" { Text = "Inside" }
					return UI.CollapsibleView { expanded = expanded, label = "Summary", content = inside }
				end)
				world.engine.environment.poke(VerifyRoblox.assertInstance(world.gui), "ReducedMotionEnabled", true)
				expect((inside:IsDescendantOf(world.screen))):toBe(true)
				expanded:set(false)
				world.engine.heartbeat:Fire(1)
				expect((not world.engine.environment.isAlive(inside))):toBe(false)
				expanded:set(true)
				expect((inside:IsDescendantOf(world.screen))):toBe(true)
				world.stop()
			end,
		})

		it("pins a collapsible view's Close below its scrolling content", {
			id = "native_navigation::native navigation controls::pins a collapsible view's Close below its scrolling content",
			run = function()
				local expanded = Compose.cell(true)
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					return UI.CollapsibleView {
						expanded = expanded,
						label = "Summary",
						content = Host.Frame "Tall" { Size = engine.types.UDim2.fromOffset(200, 2000) },
					}
				end)
				local scroll = find(world.screen, "ExpandedScroll")
				local footer = find(world.screen, "ExpandedFooter")
				local close = find(footer, "Close")
				expect(close:IsDescendantOf(scroll)):toBe(false)
				expect(footer.AnchorPoint):toBe(world.engine.types.Vector2.new(0, 1))
				world.engine.environment.poke(footer, "AbsoluteSize", world.engine.types.Vector2.new(320, 60))
				expect(scroll.Size):toBe(world.engine.types.UDim2.new(1, 0, 1, -60))
				close.Activated:Fire()
				expect(expanded:peek()):toBe(false)
				world.stop()
			end,
		})

		it("returns disclosure focus before unmounting its content", {
			id = "native_navigation::native navigation controls::returns disclosure focus before unmounting its content",
			run = function()
				local expanded = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.DisclosureGroup {
						expanded = expanded,
						label = "Details",
						content = function(): Instance
							return UI.Button "Inside" { label = "Inside" }
						end,
					}
				end)
				world.gui.SelectedObject = find(world.screen, "Inside")
				expanded:set(false)
				expect(assert(world.gui.SelectedObject).Name):toBe("Header")
				world.stop()
			end,
		})

		it("draws the ancestor column of a cascade as menu rows in item order", {
			id = "native_navigation::native navigation controls::draws the ancestor column of a cascade as menu rows in item order",
			run = function()
				local presented, follow = Compose.cell(true), Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.MenuSpec<string> = {
						isPresented = presented,
						items = {
							submenu("Parent", "Parent", { menuCommand("Leaf", "Leaf") }) :: FixtureNavigationTypes.MenuItem<any>,
							{ id = "Follow", label = "Follow", checked = follow, onSelect = noop } :: FixtureNavigationTypes.MenuItem<any>,
							{ divider = true } :: FixtureNavigationTypes.MenuItem<any>,
							{
								id = "Clear",
								label = "Clear",
								role = "destructive" :: "destructive",
								onSelect = noop,
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					}
					return UI.Menu(controlProps)
				end)
				local modal = find(world.screen, "Modal")
				world.engine.environment.poke(modal, "AbsoluteSize", world.engine.types.Vector2.new(1000, 720))
				find(world.screen, "Parent").Activated:Fire()
				local ancestor = find(world.screen, "AncestorMenu")
				expect(ancestor ~= nil):toBe(true)
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
				expect((table.concat(names, ","))):toBe("Parent,Follow,-,Clear")
				for _, name in { "Parent", "Follow", "Clear" } do
					expect((ancestor:FindFirstChild(name):HasTag("facet-menu-item"))):toBe(true)
				end
				expect((ancestor:FindFirstChild("Clear"):HasTag("facet-menu-destructive"))):toBe(true)
				expect(find(ancestor:FindFirstChild("Parent"), "TrailingIcon") ~= nil):toBe(true)
				expect(find(ancestor:FindFirstChild("Follow"), "TrailingIcon").Visible):toBe(true)
				follow:set(false)
				expect(find(ancestor:FindFirstChild("Follow"), "TrailingIcon").Visible):toBe(false)
				world.stop()
			end,
		})

		it("keeps a right-edge cascade inside the room with disjoint ancestor and child columns", {
			id = "native_navigation::native navigation controls::keeps a right-edge cascade inside the room with disjoint ancestor and child columns",
			run = function()
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.MenuSpec<string> = {
						isPresented = Compose.cell(true),
						trigger = UI.Button "Anchor" { label = "Anchor" },
						items = {
							submenu("Parent", "Parent", { menuCommand("Leaf", "Leaf") }),
						},
					}
					return UI.Menu "Cascade"(controlProps)
				end)
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(find(world.screen, "Modal"), "AbsoluteSize", V2.new(920, 640))
				world.engine.environment.poke(find(world.screen, "Cascade"), "AbsolutePosition", V2.new(760, 100))
				world.engine.environment.poke(find(world.screen, "Cascade"), "AbsoluteSize", V2.new(0, 40))
				find(world.screen, "Parent").Activated:Fire()
				local panel, ancestor = find(world.screen, "MenuPanel"), find(world.screen, "AncestorMenu")
				world.engine.environment.poke(panel, "AbsoluteSize", V2.new(220, 96))
				world.engine.environment.poke(ancestor, "AbsoluteSize", V2.new(280, 141))
				world.settle()
				local x = corner(panel)
				expect(ancestor.Position.X.Offset):toBeGreaterThanOrEqual(8)
				expect(ancestor.Position.X.Offset + 280):toBeLessThanOrEqual(x - 8)
				expect(x + 220):toBeLessThanOrEqual(912)
				expect(ancestor.Position.Y.Offset + 141):toBeLessThanOrEqual(632)
				world.stop()
			end,
		})

		it("adapts an open menu to a compact sheet without losing its branch", {
			id = "native_navigation::native navigation controls::adapts an open menu to a compact sheet without losing its branch",
			run = function()
				local presented = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.MenuSpec<string> = {
						isPresented = presented,
						items = {
							submenu("Parent", "Parent", { menuCommand("Leaf", "Leaf") }) :: FixtureNavigationTypes.MenuItem<any>,
						},
					}
					return UI.Menu(controlProps)
				end)
				local modal = find(world.screen, "Modal")
				world.engine.environment.poke(modal, "AbsoluteSize", world.engine.types.Vector2.new(1000, 720))
				find(world.screen, "Parent").Activated:Fire()
				expect(find(world.screen, "AncestorMenu") ~= nil):toBe(true)
				world.engine.environment.poke(modal, "AbsoluteSize", world.engine.types.Vector2.new(360, 640))
				expect((find(world.screen, "AncestorMenu"))):toBe(nil)
				expect(find(world.screen, "Leaf") ~= nil):toBe(true)
				find(world.screen, "Back").Activated:Fire()
				expect(find(world.screen, "Parent") ~= nil):toBe(true)
				world.stop()
			end,
		})

		it("keeps checked menu state and required radio values while honoring dismissal", {
			id = "native_navigation::native navigation controls::keeps checked menu state and required radio values while honoring dismissal",
			run = function()
				local presented, checked, selected = Compose.cell(true), Compose.cell(false), Compose.cell("a")
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.MenuSpec<string> = {
						isPresented = presented,
						items = {
							{ id = "Check", label = "Check", checked = checked, dismiss = false } :: FixtureNavigationTypes.MenuItem<any>,
							{ id = "Radio", label = "Radio", selected = selected, value = "b", dismiss = false } :: FixtureNavigationTypes.MenuItem<any>,
							menuCommand("Finish", "Finish") :: FixtureNavigationTypes.MenuItem<any>,
						},
					}
					return UI.Menu(controlProps)
				end)
				find(world.screen, "Check").Activated:Fire()
				find(world.screen, "Radio").Activated:Fire()
				expect((checked:peek())):toBe(true)
				expect((selected:peek())):toBe("b")
				expect((presented:peek())):toBe(true)
				find(world.screen, "Finish").Activated:Fire()
				expect((presented:peek())):toBe(false)
				world.stop()
			end,
		})

		it("rehomes tab accessories with native measured space and owner cleanup", {
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
						return Host.Frame {}
					end
					return UI.TabView {
						selection = selected,
						style = "sidebarAdaptable" :: "sidebarAdaptable",
						sidebarPreference = preference,
						placement = placement,
						tabs = {
							{
								id = "one",
								content = function(): Instance
									return Host.Frame {}
								end,
							},
						},
						accessories = { head = accessory, foot = accessory, trailing = accessory, aboveBar = accessory },
					}
				end)
				local root = find(world.screen, "TabView")
				expect(find(root, "Tabs").ZIndex > find(root, "Content").ZIndex):toBe(true)
				world.engine.environment.poke(
					VerifyRoblox.assertInstance(root),
					"AbsoluteSize",
					world.engine.types.Vector2.new(1200, 800)
				)
				expect(find(world.screen, "Accessory-head") ~= nil):toBe(true)
				expect((find(world.screen, "Accessory-trailing"))):toBe(nil)
				local foot = find(world.screen, "Accessory-foot")
				expect(foot.AnchorPoint.Y):toBe(1)
				local footPosition = foot.Position
				world.engine.environment.poke(foot, "AbsoluteSize", world.engine.types.Vector2.new(180, 52))
				expect(foot.Position):toBe(footPosition)
				world.engine.environment.poke(
					find(world.screen, "Accessory-head"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(180, 52)
				)
				expect(find(world.screen, "TabBand").Position.Y.Offset):toBe(52)
				preference:set("topBar")
				expect((find(world.screen, "Accessory-head"))):toBe(nil)
				expect(find(world.screen, "Accessory-trailing") ~= nil):toBe(true)
				local trailing = find(world.screen, "Accessory-trailing")
				expect(trailing.AnchorPoint.X):toBe(1)
				local trailingPosition = trailing.Position
				world.engine.environment.poke(trailing, "AbsoluteSize", world.engine.types.Vector2.new(75, 44))
				expect(trailing.Position):toBe(trailingPosition)
				world.engine.environment.poke(
					VerifyRoblox.assertInstance(root),
					"AbsoluteSize",
					world.engine.types.Vector2.new(401, 777)
				)
				expect((find(world.screen, "Accessory-head"))):toBe(nil)
				expect(find(world.screen, "Accessory-aboveBar") ~= nil):toBe(true)
				expect(find(world.screen, "TabBand").Position.Y.Scale):toBe(1)
				preference:set("sidebar")
				expect((find(world.screen, "Accessory-head"))):toBe(nil)
				expect(find(world.screen, "Accessory-aboveBar") ~= nil):toBe(true)
				placement:set("topBar")
				expect(find(world.screen, "Accessory-trailing") ~= nil):toBe(true)
				expect((find(world.screen, "Accessory-aboveBar"))):toBe(nil)
				placement:set("automatic")
				world.engine.environment.poke(
					VerifyRoblox.assertInstance(root),
					"AbsoluteSize",
					world.engine.types.Vector2.new(1200, 800)
				)
				expect(find(world.screen, "Accessory-head") ~= nil):toBe(true)
				world.stop()
				expect(retired):toBe(built)
			end,
		})

		it("hides the bar and gives the content the whole view with placement none", {
			id = "native_navigation::native navigation controls::hides the bar and gives the content the whole view with placement none",
			run = function()
				local selected, placement =
					Compose.cell("one"),
					Compose.cell(
						"none" :: "automatic" | "bottomBar" | "bottomBarCompact" | "none" | "sidebar" | "topBar"
					)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView {
						selection = selected,
						style = "sidebarAdaptable" :: "sidebarAdaptable",
						placement = placement,
						tabs = {
							{
								id = "one",
								content = function(): Instance
									return Host.Frame {}
								end,
							},
							{
								id = "two",
								content = function(): Instance
									return Host.Frame {}
								end,
							},
						},
					}
				end)
				local root = find(world.screen, "TabView")
				world.engine.environment.poke(
					VerifyRoblox.assertInstance(root),
					"AbsoluteSize",
					world.engine.types.Vector2.new(844, 332)
				)
				local T = world.engine.types
				expect(find(root, "Tabs").Visible):toBe(false)
				expect(find(root, "Content").Position):toBe(T.UDim2.fromOffset(0, 0))
				expect(find(root, "Content").Size):toBe(T.UDim2.fromScale(1, 1))
				placement:set("topBar")
				expect(find(root, "Tabs").Visible):toBe(true)
				expect(find(root, "Content").Position):toBe(T.UDim2.fromOffset(0, 52))
				world.stop()
			end,
		})

		it("removes dynamically deleted tab owners and preserves the selected survivor", {
			id = "native_navigation::native navigation controls::removes dynamically deleted tab owners and preserves the selected survivor",
			run = function()
				local selection, disposed = Compose.cell("one"), 0
				local tabs: FixtureComposeTypes.Value<{ Navigation.Tab }>
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local function content()
						Compose.cleanup(function()
							disposed += 1
						end)
						return Host.Frame {}
					end
					tabs = (Compose.cell :: any)({
						{ id = "one", content = content },
						{ id = "two", content = content },
					})
					return UI.TabView { selection = selection, tabs = tabs :: any }
				end)
				selection:set("two")
				selection:set("one")
				tabs:set({ tabs:peek()[1] })
				expect(disposed):toBe(1)
				expect((selection:peek())):toBe("one")
				world.stop()
			end,
		})

		it("shows button help after a pointer rests on it and never on touch", {
			id = "native_navigation::native navigation controls::shows button help after a pointer rests on it and never on touch",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Screen" {
						UI.Button "Plus" { label = "+", help = "Posts this avatar" },
					}
				end)
				local plus = find(world.screen, "Plus")
				local Enum = world.engine.types.Enum
				world.engine.environment.poke(world.input, "PreferredInput", Enum.PreferredInput.KeyboardAndMouse)
				world.engine.environment.poke(plus, "GuiState", Enum.GuiState.Hover)
				expect((find(world.screen, "HelpText"))):toBe(nil)
				world.engine.heartbeat:Fire(0.3)
				expect((find(world.screen, "HelpText"))):toBe(nil)
				world.engine.heartbeat:Fire(0.3)
				expect(find(world.screen, "HelpText").Text):toBe("Posts this avatar")
				world.engine.environment.poke(plus, "GuiState", Enum.GuiState.Idle)
				world.settle()
				expect((find(world.screen, "HelpText"))):toBe(nil)
				world.engine.environment.poke(world.input, "PreferredInput", Enum.PreferredInput.Touch)
				world.engine.environment.poke(plus, "GuiState", Enum.GuiState.Hover)
				world.engine.heartbeat:Fire(0.6)
				expect((find(world.screen, "HelpText"))):toBe(nil)
				world.stop()
			end,
		})

		it("takes selection into a modal only for players navigating by selection", {
			id = "native_navigation::native navigation controls::takes selection into a modal only for players navigating by selection",
			run = function()
				local presented = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local alertProps1: NavigationProps.AlertSpec<unknown> = {
						isPresented = presented,
						title = "Leave race?",
						actions = {
							{ id = "stay", label = "Stay", role = "cancel" :: "cancel" },
						},
					}
					return Host.Frame "Screen" {
						UI.Button "Opener" { label = "Open" },
						UI.Alert(alertProps1),
					}
				end)
				presented:set(true)
				expect(world.gui.SelectedObject):toBe(nil)
				presented:set(false)
				world.gui.SelectedObject = find(world.screen, "Opener")
				presented:set(true)
				expect(assert(world.gui.SelectedObject).Name):toBe("stay")
				presented:set(false)
				expect(assert(world.gui.SelectedObject).Name):toBe("Opener")
				world.gui.SelectedObject = nil
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Gamepad
				)
				presented:set(true)
				expect(assert(world.gui.SelectedObject).Name):toBe("stay")
				world.stop()
			end,
		})

		it("clears background selection when a modal opens after pointer input", {
			id = "native_navigation::native navigation controls::clears background selection when a modal opens after pointer input",
			run = function()
				local presented = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local alertProps1: NavigationProps.AlertSpec<unknown> = {
						isPresented = presented,
						title = "Confirm",
						actions = { { id = "stay", label = "Stay", role = "cancel" :: "cancel" } },
					}
					return Host.Frame {
						UI.Button "Opener" { label = "Open" },
						UI.Alert(alertProps1),
					}
				end)
				world.gui.SelectedObject = find(world.screen, "Opener")
				world.engine.environment.fakeOn(world.input, "GetLastInputType", function()
					return world.engine.types.Enum.UserInputType.MouseMovement
				end)
				presented:set(true)
				expect(world.gui.SelectedObject):toBeNil()
				world.settle()
				world.gui.SelectedObject = find(world.screen, "Opener")
				expect(world.gui.SelectedObject):toBeNil()
				world.stop()
			end,
		})

		it("hands selection to the shown tab panel and restores it on return", {
			id = "native_navigation::native navigation controls::hands selection to the shown tab panel and restores it on return",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls)
					return UI.TabView {
						selection = selection,
						tabs = {
							{ id = "one", content = UI.Button "OneAction" { label = "One" } },
							{ id = "two", content = UI.Button "TwoAction" { label = "Two" } },
						},
					}
				end)
				world.gui.SelectedObject = find(world.screen, "OneAction")
				selection:set("two")
				expect(assert(world.gui.SelectedObject).Name):toBe("TwoAction")
				selection:set("one")
				expect(assert(world.gui.SelectedObject).Name):toBe("OneAction")
				expect(#world.engine.rejectedSelections()):toBe(0)
				world.stop()
			end,
		})

		it("collapses a nested tab strip into one menu row when its region is short", {
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
									local tabs: { Tab } = {
										{ id = "x", label = "Swipe actions", content = Host.Frame "X" {} },
										{ id = "y", label = "Permissions", content = Host.Frame "Y" {} },
									}
									return UI.TabView "Inner" {
										selection = inner,
										tabs = tabs,
									}
								end,
							},
						},
					}
				end)
				local nested = find(world.screen, "Inner")
				local strip = find(nested, "Tabs")
				world.engine.environment.poke(nested, "AbsoluteSize", world.engine.types.Vector2.new(705, 200))
				expect(strip.Visible):toBe(false)
				expect(find(nested, "TabsMenu") ~= nil):toBe(true)
				world.engine.environment.poke(nested, "AbsoluteSize", world.engine.types.Vector2.new(705, 600))
				expect(strip.Visible):toBe(true)
				expect((find(nested, "TabsMenu"))):toBe(nil)
				world.engine.environment.poke(
					nested:FindFirstChild("LayoutUnit"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(60, 0.6)
				)
				world.engine.environment.poke(nested, "AbsoluteSize", world.engine.types.Vector2.new(423, 360))
				expect(strip.Visible):toBe(true)
				expect((find(nested, "TabsMenu"))):toBe(nil)
				world.engine.environment.poke(nested, "AbsoluteSize", world.engine.types.Vector2.new(423, 240))
				expect(strip.Visible):toBe(false)
				world.stop()
			end,
		})

		it("pauses repeating progress motion while its retained tab is hidden", {
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
							},
							{ id = "two", content = Host.Frame "Two" {} },
						},
					}
				end)
				local spinner = find(world.screen, "Spinner")
				local function snapshot()
					local values: { [Instance]: string } = {}
					for _, node in spinner:GetDescendants() do
						if node:IsA("GuiObject") then
							values[node] = `{node.BackgroundTransparency}|{node.Rotation}|{node.Size}|{node.Position}`
						end
					end
					return values
				end
				local function changed(before: { [Instance]: string }, after: { [Instance]: string })
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
				expect(changed(shown, snapshot()) > 0):toBe(true)
				selection:set("two")
				advance()
				local hidden = snapshot()
				advance()
				expect((changed(hidden, snapshot()))):toBe(0)
				selection:set("one")
				local returned = snapshot()
				advance()
				expect(changed(returned, snapshot()) > 0):toBe(true)
				world.stop()
			end,
		})

		it("queues callouts by priority and retires once without writing model facts", {
			id = "native_navigation::native navigation controls::queues callouts by priority and retires once without writing model facts",
			run = function()
				local seen, used, retired = Compose.cell(false), Compose.cell(false), {}
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame {
						anchor,
						UI.Callout {
							anchor = anchor :: GuiObject,
							seen = seen,
							priority = 1,
							content = function(): Instance
								return Host.TextLabel "FirstTip" {}
							end,
							onRetire = function(reason: "action" | "dismissed" | "featureUsed" | "seen" | "tapAway")
								table.insert(retired, "low:" .. reason)
							end,
						},
						UI.Callout {
							anchor = anchor :: GuiObject,
							featureUsed = used,
							priority = 2,
							content = function(): Instance
								return Host.TextLabel "PriorityTip" {}
							end,
							onRetire = function(reason: "action" | "dismissed" | "featureUsed" | "seen" | "tapAway")
								table.insert(retired, "high:" .. reason)
							end,
						},
					}
				end)
				expect((find(world.screen, "FirstTip"))):toBe(nil)
				expect(find(world.screen, "PriorityTip") ~= nil):toBe(true)
				used:set(true)
				world.settle()
				expect((find(world.screen, "PriorityTip"))):toBe(nil)
				expect(find(world.screen, "FirstTip") ~= nil):toBe(true)
				find(world.screen, "Dismiss").Activated:Fire()
				expect(#retired):toBe(2)
				expect((seen:peek())):toBe(false)
				world.stop()
				expect(#retired):toBe(2)
			end,
		})

		it("keeps sheet content in a native flex remainder and explicit close operable", {
			id = "native_navigation::native navigation controls::keeps sheet content in a native flex remainder and explicit close operable",
			run = function()
				local presented, detent = Compose.cell(true), Compose.cell("medium")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = presented,
						detent = detent,
						title = "Details",
						closeButton = true,
						interactiveDismissDisabled = true,
						content = function(): Instance
							return Host.ScrollingFrame "DetailBody" {}
						end,
					}
				end)
				expect(find(world.screen, "DetailBody").Parent.Name):toBe("SheetFlow")
				local body = find(world.screen, "SheetContent")
				expect(body.ClassName):toBe("ScrollingFrame")
				expect(body.AutomaticCanvasSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				world.engine.environment.poke(
					find(world.screen, "SheetFlow"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(400, 1800)
				)
				expect(body.CanvasSize.Y.Offset):toBe(1800)
				expect(find(body, "UIListLayout") ~= nil):toBe(true)
				expect(find(find(world.screen, "SheetContent"), "UIFlexItem").FlexMode):toBe(
					world.engine.types.Enum.UIFlexMode.Fill
				)
				expect((find(world.screen, "Size"))):toBe(nil)
				expect(find(world.screen, "Close").Parent.Name):toBe("Header")
				local grabber = find(world.screen, "Grabber")
				expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Resize: Medium")
				expect(grabber.Selectable or grabber.Visible):toBe(false)
				expect(grabber.Size.Y.Offset >= 44 and grabber.Size.X.Offset >= 44):toBe(true)
				expect((detent:peek())):toBe("medium")
				find(world.screen, "Close").Activated:Fire()
				expect((presented:peek())):toBe(false)
				world.stop()
			end,
		})
		it("contains failed alert factories and accepts a later valid presentation", {
			id = "native_navigation::native navigation controls::contains failed alert factories and accepts a later valid presentation",
			run = function()
				local item, disposed = Compose.cell(nil :: { id: string }?), 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local controlProps: NavigationProps.AlertSpec<{ id: string }> = {
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
					}
					return UI.Alert<<{ id: string }>>(controlProps)
				end)
				item:set({ id = "bad" })
				expect((item:peek())):toBe(nil)
				expect(disposed):toBe(1)
				item:set({ id = "good" })
				expect(find(world.screen, "Recovered") ~= nil):toBe(true)
				world.stop()
				expect(disposed):toBe(2)
			end,
		})

		it("wraps alert actions and bounds long message scrolling to native measurements", {
			id = "native_navigation::native navigation controls::wraps alert actions and bounds long message scrolling to native measurements",
			run = function()
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.AlertSpec<unknown> = {
						isPresented = Compose.cell(true),
						message = string.rep("Long message ", 100),
						actions = {
							{ id = "Cancel", label = "Cancel", role = "cancel" :: "cancel" },
							{ id = "Accept", label = "Continue" },
						},
					}
					return UI.Alert(controlProps)
				end)
				world.engine.environment.poke(
					find(world.screen, "AlertModal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(360, 240)
				)
				world.engine.environment.poke(
					find(world.screen, "Actions"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(320, 96)
				)
				world.engine.environment.poke(
					find(world.screen, "AlertContent"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(320, 1000)
				)
				expect(find(find(world.screen, "Actions"), "UIListLayout").FillDirection):toBe(
					world.engine.types.Enum.FillDirection.Vertical
				)
				expect(find(world.screen, "Cancel").LayoutOrder > find(world.screen, "Accept").LayoutOrder):toBe(true)
				expect(find(world.screen, "AlertMessage").Size.Y.Offset < 100):toBe(true)
				world.stop()
			end,
		})

		it("gives the one default alert action the emphasis appearance and refuses a second default", {
			id = "native_navigation::native navigation controls::gives the one default alert action the emphasis appearance and refuses a second default",
			run = function()
				type Action = FixtureNavigationTypes.AlertAction<unknown>
				local function act(id: string, role: ("default" | "cancel" | "destructive")?): Action
					return { id = id, label = id, role = role }
				end
				local list = { act("Stay", "cancel"), act("Sell", "destructive"), act("Gift"), act("Buy", "default") }
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.AlertSpec<unknown> =
						{ isPresented = Compose.cell(true), title = "Buy Turbo Boost?", actions = list }
					return UI.Alert(controlProps)
				end)
				local appearances = {}
				for _, id in { "Stay", "Sell", "Gift", "Buy" } do
					table.insert(appearances, `{id}={find(world.screen, id):GetAttribute("appearance")}`)
				end
				local expected = "Stay=standard,Sell=standard,Gift=standard,Buy=emphasis"
				expect((table.concat(appearances, ","))):toBe(expected)
				expect((find(world.screen, "Buy"):HasTag("facet-accent"))):toBe(true)
				expect((find(world.screen, "Sell"):HasTag("facet-role-destructive"))):toBe(true)
				expect((find(world.screen, "Stay"):HasTag("facet-role-cancel"))):toBe(true)
				world.stop()
				local twice = Compose.cell(true)
				local doubledList = { act("Buy", "default"), act("Gift", "default") }
				local doubled = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.AlertSpec<unknown> =
						{ isPresented = twice, title = "Buy?", actions = doubledList }
					return UI.Alert(controlProps)
				end)
				doubled.settle()
				local failure = tostring(find(doubled.screen, "Alert"):GetAttribute("FacetError"))
				expect((string.find(failure, "one default action", 1, true) ~= nil)):toBe(true)
				expect((twice:peek())):toBe(false)
				doubled.stop()
			end,
		})

		it("keeps the alert card inside the screen when the theme chrome adds to its height", {
			id = "native_navigation::native navigation controls::keeps the alert card inside the screen when the theme chrome adds to its height",
			run = function()
				local themes = require("../src/ui/themes")(Compose)
				local package = themes.neutralPackage()
				package.chrome = package.chrome or {}
				assert(package.chrome).panel =
					{ kind = "native" :: "native", contentInsets = { top = 18, bottom = 18, left = 18, right = 18 } }
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.AlertSpec<unknown> = {
						isPresented = Compose.cell(true),
						message = string.rep("Long message ", 100),
						actions = {
							{ id = "Stay", label = "Stay", role = "cancel" :: "cancel" },
							{ id = "Save", label = "Save and leave" },
							{ id = "Leave", label = "Leave without saving", role = "destructive" :: "destructive" },
						},
					}
					return UI.Alert(controlProps)
				end, { theme = assert((themes.define(package))) })
				local V2 = world.engine.types.Vector2.new
				world.engine.environment.poke(find(world.screen, "AlertModal"), "AbsoluteSize", V2(667, 375))
				world.engine.environment.poke(find(world.screen, "Actions"), "AbsoluteSize", V2(400, 148))
				world.engine.environment.poke(find(world.screen, "AlertContent").Parent, "AbsoluteSize", V2(400, 1000))
				local message = find(world.screen, "AlertMessage")
				local card = message.Size.Y.Offset + 148 + 20 * 2 + 8 + 18 * 2
				expect(message.Size.Y.Offset):toBe(375 - 148 - (20 * 2 + 8 + 18 * 2) - 32)
				expect(card <= 375 - 32):toBe(true)
				world.stop()
			end,
		})

		it("grows a segmented strip at a larger text size so its caption fits inside the theme control insets", {
			id = "native_navigation::native navigation controls::grows a segmented strip at a larger text size so its caption fits inside the theme control insets",
			run = function()
				local themes = require("../src/ui/themes")(Compose)
				local package = themes.neutralPackage()
				package.chrome = package.chrome or {}
				assert(package.chrome).control =
					{ kind = "fill" :: "fill", contentInsets = { top = 10, bottom = 10, left = 12, right = 12 } }
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.SinglePickerSpec<string> = {
						style = "segmented" :: "segmented",
						selected = Compose.cell("a"),
						options = {
							{ value = "a", label = "Open" } :: Navigation.PickerOption<string>,
							{ value = "b", label = "Club" } :: Navigation.PickerOption<string>,
						},
					}
					return UI.Picker(controlProps)
				end, { theme = assert((themes.define(package))) })
				local V2 = world.engine.types.Vector2.new
				local picker = find(world.screen, "Picker")
				world.engine.environment.poke(find(find(world.screen, "a"), "Label"), "TextBounds", V2(56, 31))
				expect(picker.Size.Y.Offset):toBe(31 + 20 + 6)
				world.engine.environment.poke(find(find(world.screen, "a"), "Label"), "TextBounds", V2(48, 16))
				world.engine.environment.poke(
					VerifyRoblox.assertInstance(world.gui),
					"PreferredTextSize",
					world.engine.types.Enum.PreferredTextSize.Largest
				)
				expect(picker.Size.Y.Offset):toBe(50)
				world.engine.environment.poke(find(find(world.screen, "a"), "Label"), "TextBounds", V2(56, 31))
				world.engine.environment.poke(find(find(world.screen, "b"), "Label"), "TextBounds", V2(48, 29))
				expect(picker.Size.Y.Offset):toBe(31 + 20 + 6)
				world.engine.environment.poke(find(find(world.screen, "a"), "Label"), "TextBounds", V2(56, 20))
				expect(picker.Size.Y.Offset):toBe(29 + 20 + 6)
				world.stop()
			end,
		})

		it("reserves segmented caption width and keeps one row instead of clipping whole words", {
			id = "native_navigation::native navigation controls::reserves segmented caption width and keeps one row instead of clipping whole words",
			run = function()
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.SinglePickerSpec<string> = {
						style = "segmented" :: "segmented",
						selected = Compose.cell("normal"),
						options = {
							{ value = "normal", label = "Normal" },
							{ value = "limited", label = "Limited" },
						},
					}
					return UI.Picker "Motion"(controlProps)
				end)
				local picker, button = find(world.screen, "Motion"), find(world.screen, "normal")
				local floor = button:FindFirstChildWhichIsA("UISizeConstraint")
				local minimum = floor.MinSize
				world.engine.environment.poke(button, "TextBounds", world.engine.types.Vector2.new(54, 16))
				expect(button.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.X)
				expect(floor.MinSize):toBe(minimum)
				expect(picker:FindFirstChildWhichIsA("UIListLayout").Wraps):toBe(false)
				world.stop()
			end,
		})

		it("fits segmented glyphs inside compact chrome at the default text preference", {
			id = "native_navigation::native navigation controls::fits segmented glyphs inside compact chrome at the default text preference",
			run = function()
				local themes = require("../src/ui/themes")(Compose)
				local package = themes.neutralPackage()
				package.metrics.controlSizes.compact.height = 22
				package.chrome = { control = { kind = "fill", contentInsets = { top = 2, bottom = 2 } } }
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.SinglePickerSpec<string> = {
						style = "segmented" :: "segmented",
						controlSize = "compact" :: "compact",
						selected = Compose.cell("3"),
						options = {
							{ value = "3", label = "3" } :: Navigation.PickerOption<string>,
							{ value = "10", label = "10" } :: Navigation.PickerOption<string>,
						},
					}
					return UI.Picker "Laps"(controlProps)
				end, { theme = assert((themes.define(package))) })
				local picker = find(world.screen, "Laps")
				world.engine.environment.poke(
					find(find(picker, "3"), "Label"),
					"TextBounds",
					world.engine.types.Vector2.new(8, 13)
				)
				world.engine.environment.poke(
					find(find(picker, "10"), "Label"),
					"TextBounds",
					world.engine.types.Vector2.new(16, 13)
				)
				expect(picker.Size.Y.Offset):toBe(13 + 4 + 6)
				world.engine.environment.poke(
					find(find(picker, "10"), "Label"),
					"TextBounds",
					world.engine.types.Vector2.new(16, 18)
				)
				expect(picker.Size.Y.Offset):toBe(18 + 4 + 6)
				world.engine.environment.poke(
					find(find(picker, "10"), "Label"),
					"TextBounds",
					world.engine.types.Vector2.new(16, 13)
				)
				expect(picker.Size.Y.Offset):toBe(13 + 4 + 6)
				world.stop()
			end,
		})

		it("keeps split primary activation separate from touch long-press alternatives", {
			id = "native_navigation::native navigation controls::keeps split primary activation separate from touch long-press alternatives",
			run = function()
				local primary, alternative = 0, 0
				local world = setup(function(UI: FacetControls, _, engine)
					local controlProps: NavigationProps.SplitButtonSpec<string> = {
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
					}
					return UI.SplitButton(controlProps)
				end)
				find(world.screen, "Primary").Activated:Fire()
				expect(primary):toBe(1)
				local chevron = find(world.screen, "Alternatives")
				expect((chevron:HasTag("facet-button"))):toBe(true)
				expect((chevron:FindFirstChildWhichIsA("UISizeConstraint"))):toBe(nil)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Touch
				)
				local trigger = find(world.screen, "Primary")
				expect(trigger.Size):toBe(world.engine.types.UDim2.fromScale(1, 1))
				expect(trigger.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				trigger.TouchLongPress:Fire({}, world.engine.types.Enum.UserInputState.Begin)
				trigger.Activated:Fire()
				expect(primary):toBe(1)
				expect(find(world.screen, "MenuPanel") ~= nil):toBe(true)
				find(world.screen, "Alternate").Activated:Fire()
				expect(alternative):toBe(1)
				world.stop()
			end,
		})

		it("opens searchable picker content only when presented and commits filtered results", {
			id = "native_navigation::native navigation controls::opens searchable picker content only when presented and commits filtered results",
			run = function()
				local selection, query, opened = Compose.cell("a"), Compose.cell(""), Compose.cell(false)
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.SinglePickerSpec<string> = {
						selected = selection,
						query = query,
						isPresented = opened,
						style = "navigationLink" :: "navigationLink",
						options = {
							{ value = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
							{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
						},
					}
					return UI.Picker(controlProps)
				end)
				expect((find(world.screen, "PickerSearch"))):toBe(nil)
				opened:set(true)
				query:set("Bet")
				expect((find(find(world.screen, "Choices"), "a"))):toBe(nil)
				find(find(world.screen, "Choices"), "b").Activated:Fire()
				expect((selection:peek())):toBe("b")
				expect((opened:peek())):toBe(false)
				world.stop()
			end,
		})
		it("uses the native navigation width before its framed observation publishes", {
			id = "native_navigation::native navigation controls::uses the native navigation width before its framed observation publishes",
			run = function()
				local engine = engines.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local ctx = require("../src/ui/context")(Compose, runtime, { types = engine.types })
				local UI = ({} :: unknown) :: SharedTypes.Controls
				require("../src/ui/layout")(ctx, UI)
				require("../src/ui/inputs")(ctx, UI)
				require("../src/ui/nav_pages")(ctx, UI, require("../src/ui/nav_modal")(ctx))
				local observeSize = ctx.observe.AbsoluteSize
				local stale = Compose.cell(engine.types.Vector2.zero)
				ctx.observe.AbsoluteSize = function(node: GuiBase2d)
					return if node.Name == "NavigationBar" then stale else observeSize(node)
				end
				local Host = Facet.host(runtime)
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<unknown> })
				local stop, mounted = runtime.mount(function()
					return Host.ScreenGui {
						UI.NavigationStack {
							path = path,
							root = {
								title = "Recipe book",
								content = function(): GuiBase2d
									return Host.Frame {}
								end,
							},
							destinations = {},
						},
					}
				end, engine.new("Folder"))
				local screen = (mounted :: unknown) :: ScreenGui
				local bar = assert(screen:FindFirstChild("NavigationBar", true)) :: Frame
				local title = assert(bar:FindFirstChild("Title")) :: TextLabel
				local geometry = VerifyRoblox.assertInstance(bar)
				engine.environment.poke(geometry, "AbsoluteSize", engine.types.Vector2.new(1024, 44))
				expect(title:HasTag("facet-type-title")):toBe(true)
				expect(title:HasTag("facet-type-heading")):toBe(false)
				expect(stale:peek()):toBe(engine.types.Vector2.zero)
				stop()
				runtime:dispose()
			end,
		})
		it("reveals a Composition in a host that never lays out", {
			id = "native_navigation::native navigation controls::reveals a Composition in a host that never lays out",
			run = function()
				local world = setup(function(UI: SharedTypes.Controls)
					return UI.Composition "HUD" {
						UI.Region "Status" { zone = "topRight", rank = 1, UI.Text { text = "Ready" } },
					}
				end, { preRender = true })
				local root = assert(world.screen:FindFirstChild("HUD", true)) :: Instance
				expect(root:GetAttribute("FacetPreparing")):toBe(true)
				for _ = 1, 30 do
					world.engine.heartbeat:Fire(1 / 60)
				end
				expect(root:GetAttribute("FacetPreparing")):toBe(true)
				for _ = 1, 60 do
					world.engine.heartbeat:Fire(1 / 60)
				end
				expect(root:GetAttribute("FacetPreparing")):toBe(false)
				world.stop()
			end,
		})
		it("resolves an automatic picker from native width and text bounds before framed observations", {
			id = "native_navigation::native navigation controls::resolves an automatic picker from native width and text bounds before framed observations",
			run = function()
				local engine = engines.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local input = engine.new("UserInputService")
				engine.environment.fakeOn(input, "GetLastInputType", function()
					return engine.types.Enum.UserInputType.Keyboard
				end)
				for _, method in { "IsKeyDown", "IsGamepadButtonDown" } do
					engine.environment.fakeOn(input, method, function()
						return false
					end)
				end
				for _, method in
					{ "GetNavigationGamepads", "GetKeysPressed", "GetMouseButtonsPressed", "GetGamepadState" }
				do
					engine.environment.fakeOn(input, method, function()
						return {}
					end)
				end
				engine.environment.poke(input, "PreferredInput", engine.types.Enum.PreferredInput.KeyboardAndMouse)
				local ctx = require("../src/ui/context")(Compose, runtime, {
					types = engine.types,
					services = { UserInputService = (input :: unknown) :: UserInputService },
				})
				local UI = ({} :: unknown) :: SharedTypes.Controls
				require("../src/ui/layout")(ctx, UI)
				require("../src/ui/inputs")(ctx, UI)
				require("../src/ui/nav_menu")(ctx, UI, require("../src/ui/nav_modal")(ctx))
				local observeSize, observeBounds = ctx.observe.AbsoluteSize, ctx.observe.TextBounds
				local stale = Compose.cell(engine.types.Vector2.zero)
				ctx.observe.AbsoluteSize = function(node: GuiBase2d)
					return if node.Name == "Auto" then stale else observeSize(node)
				end
				ctx.observe.TextBounds = function(node: TextBox | TextButton | TextLabel)
					return if node.Name == "LabelMeasure" then stale else observeBounds(node)
				end
				local stop, mounted = runtime.mount(function()
					local controlProps: NavigationProps.SinglePickerSpec<string> = {
						selected = Compose.cell("a"),
						options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
					}
					return UI.Picker "Auto"(controlProps)
				end, engine.new("ScreenGui"))
				local picker = (mounted :: unknown) :: Frame
				local measure = assert(picker:FindFirstChild("LabelMeasure")) :: TextLabel
				local geometry = VerifyRoblox.assertInstance(picker)
				local metrics = VerifyRoblox.assertInstance(measure)
				engine.environment.poke(geometry, "AbsoluteSize", engine.types.Vector2.new(120, 44))
				engine.environment.poke(metrics, "TextBounds", engine.types.Vector2.new(500, 18))
				expect(picker:FindFirstChild("Trigger", true) ~= nil):toBe(true)
				engine.environment.poke(geometry, "AbsoluteSize", engine.types.Vector2.new(1000, 44))
				expect(picker:FindFirstChild("Trigger", true) == nil):toBe(true)
				engine.environment.poke(metrics, "TextBounds", engine.types.Vector2.new(1200, 18))
				expect(picker:FindFirstChild("Trigger", true) ~= nil):toBe(true)
				expect(stale:peek()):toBe(engine.types.Vector2.zero)
				stop()
				runtime:dispose()
			end,
		})
		it("retains styled automatic picker forms and disables hidden choices", {
			id = "native_navigation::native navigation controls::retains styled automatic picker forms and disables hidden choices",
			run = function()
				local selected, opened = Compose.cell("a"), Compose.cell(false)
				local initial: { Navigation.PickerOption<string> } =
					{ { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } }
				local options = Compose.cell(initial)
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.SinglePickerSpec<string> = {
						selected = selected,
						isPresented = opened,
						options = options,
					}
					return UI.Picker "Auto"(controlProps)
				end, { runService = true })
				local picker = find(world.screen, "Auto")
				local segmented, menu, inline
				local count = 0
				for _, child in picker:GetChildren() do
					if child.Name == "Presentation" then
						count += 1
						if child:HasTag("facet-segmented") then
							segmented = child
						elseif find(child, "Trigger") then
							menu = child
						else
							inline = child
						end
					end
				end
				expect(count):toBe(3)
				expect(segmented.Visible):toBe(true)
				expect(menu.Visible):toBe(false)
				expect(inline.Visible):toBe(false)
				local hidden = find(inline, "b")
				expect(hidden.Interactable):toBe(false)
				hidden.Activated:Fire()
				expect(selected:peek()):toBe("a")
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				world.engine.environment.poke(picker, "AbsoluteSize", world.engine.types.Vector2.new(120, 44))
				world.engine.environment.poke(
					find(picker, "LabelMeasure"),
					"TextBounds",
					world.engine.types.Vector2.new(500, 18)
				)
				expect(menu.Visible):toBe(true)
				expect(segmented.Visible):toBe(false)
				find(menu, "Trigger").Activated:Fire()
				expect(opened:peek()):toBe(true)
				world.engine.environment.poke(picker, "AbsoluteSize", world.engine.types.Vector2.new(1000, 44))
				expect(segmented.Visible):toBe(true)
				expect(menu.Visible):toBe(false)
				expect(opened:peek()):toBe(false)
				world.engine.environment.poke(picker, "AbsoluteSize", world.engine.types.Vector2.new(120, 44))
				find(menu, "Trigger").Activated:Fire()
				expect(opened:peek()):toBe(true)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Gamepad
				)
				expect(inline.Visible):toBe(true)
				expect(menu.Visible):toBe(false)
				expect(opened:peek()):toBe(false)
				hidden.Activated:Fire()
				expect(selected:peek()):toBe("b")
				world.engine.environment.poke(picker, "AbsoluteSize", world.engine.types.Vector2.new(1000, 44))
				expect(segmented.Visible):toBe(true)
				expect(segmented.Parent):toBe(picker)
				expect(hidden.Interactable):toBe(false)
				local many = {}
				for index = 1, 7 do
					table.insert(many, { value = tostring(index), label = "Choice " .. tostring(index) })
				end
				options:set(many)
				count = 0
				for _, child in picker:GetChildren() do
					if child.Name == "Presentation" then
						count += 1
					end
				end
				expect(count):toBe(1)
				expect(menu.Parent):toBe(picker)
				expect(menu.Visible):toBe(true)
				world.stop()
				expect(world.engine.census().connections):toBe(0)
			end,
		})
		it("shows a menu when the automatic segmented strip would scroll", {
			id = "native_navigation::native navigation controls::shows a menu when the automatic segmented strip would scroll",
			run = function()
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.SinglePickerSpec<string> = {
						selected = Compose.cell("a"),
						options = {
							{ value = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
							{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
							{ value = "c", label = "Gamma" } :: Navigation.PickerOption<string>,
						},
					}
					return UI.Picker "Auto"(controlProps)
				end, { runService = true })
				local Vector2 = world.engine.types.Vector2
				local poke = world.engine.environment.poke
				local picker = find(world.screen, "Auto")
				local segmented, menu
				for _, child in picker:GetChildren() do
					if child.Name == "Presentation" then
						if child:HasTag("facet-segmented") then
							segmented = child
						elseif find(child, "Trigger") then
							menu = child
						end
					end
				end
				poke(world.input, "PreferredInput", world.engine.types.Enum.PreferredInput.Touch)
				poke(picker, "AbsoluteSize", Vector2.new(401, 60))
				expect(segmented.Visible):toBe(true)
				expect(menu.Visible):toBe(false)
				local layout = segmented:FindFirstChildWhichIsA("UIListLayout")
				poke(segmented, "AbsoluteWindowSize", Vector2.new(401, 50))
				poke(layout, "AbsoluteContentSize", Vector2.new(470, 44))
				expect(segmented:GetAttribute("FacetOverflow")):toBe(true)
				expect(segmented.Visible):toBe(false)
				expect(menu.Visible):toBe(true)
				local flex = {}
				for _, node in segmented:GetDescendants() do
					if node:IsA("UIFlexItem") then
						table.insert(flex, node)
					end
				end
				expect(#flex):toBe(3)
				for _, item in flex do
					expect(item.FlexMode):toBe(world.engine.types.Enum.UIFlexMode.None)
				end
				poke(layout, "AbsoluteContentSize", Vector2.new(300, 44))
				expect(segmented.Visible):toBe(true)
				expect(menu.Visible):toBe(false)
				for _, item in flex do
					expect(item.FlexMode):toBe(world.engine.types.Enum.UIFlexMode.Grow)
				end
				world.stop()
				expect(world.engine.census().connections):toBe(0)
			end,
		})

		it("reveals the navigation title after its initial styled bounds settle", {
			id = "native_navigation::native navigation controls::reveals the navigation title after its initial styled bounds settle",
			run = function()
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<unknown> })
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
						path = path,
						root = { title = "Recipe book", content = Host.Frame {} },
						destinations = {},
					}
					return UI.NavigationStack(controlProps)
				end, { runService = true })
				local bar = find(world.screen, "NavigationBar") :: Frame
				local title = assert(bar:FindFirstChild("Title")) :: TextLabel
				local box = VerifyRoblox.assertInstance(bar)
				local text = VerifyRoblox.assertInstance(title)
				world.engine.environment.poke(box, "AbsoluteSize", world.engine.types.Vector2.new(1024, 44))
				world.engine.environment.poke(text, "AbsoluteSize", bar.AbsoluteSize)
				expect(title.Visible):toBe(false)
				world.engine.environment.poke(text, "TextBounds", world.engine.types.Vector2.new(100, 20))
				world.engine.heartbeat:Fire(1 / 60)
				world.engine.environment.poke(text, "TextBounds", world.engine.types.Vector2.new(120, 24))
				world.engine.heartbeat:Fire(1 / 60)
				expect(title.Visible):toBe(false)
				for _ = 1, 4 do
					world.engine.heartbeat:Fire(1 / 60)
				end
				expect(title.Visible):toBe(true)
				world.engine.environment.poke(box, "AbsoluteSize", world.engine.types.Vector2.new(390, 44))
				expect(title.Visible):toBe(true)
				world.stop()
			end,
		})
		it("sizes the navigation bar title by the stack's width class", {
			id = "native_navigation::native navigation controls::sizes the navigation bar title by the stack's width class",
			run = function()
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
						path = path,
						root = {
							title = "Garage",
							content = function(): Instance
								return Host.Frame {}
							end,
						} :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							detail = {
								title = "Engine",
								content = function(): Instance
									return Host.Frame {}
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
						},
					}
					return UI.NavigationStack(controlProps)
				end)
				local bar = find(world.screen, "NavigationBar")
				local title = find(bar, "Title")
				world.engine.environment.poke(bar, "AbsoluteSize", world.engine.types.Vector2.new(390, 44))
				expect((title:HasTag("facet-type-heading"))):toBe(true)
				expect((title:HasTag("facet-type-title"))):toBe(false)
				world.engine.environment.poke(bar, "AbsoluteSize", world.engine.types.Vector2.new(1024, 44))
				expect((title:HasTag("facet-type-title"))):toBe(true)
				expect((title:HasTag("facet-type-heading"))):toBe(false)
				local inset = title:FindFirstChildWhichIsA("UIPadding")
				expect(inset and inset.PaddingLeft.Offset):toBe(12)
				expect(inset and inset.PaddingRight.Offset):toBe(12)
				world.stop()
			end,
		})
		it("restores surviving navigation focus and moves paging focus into the visible page", {
			id = "native_navigation::native navigation controls::restores surviving navigation focus and moves paging focus into the visible page",
			run = function()
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
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
					}
					return UI.NavigationStack(controlProps)
				end)
				world.gui.SelectedObject = find(world.screen, "RootAction")
				path:set({ { id = "detail" } })
				world.settle()
				expect(assert(world.gui.SelectedObject).Name):toBe("DetailAction")
				path:set({})
				world.settle()
				expect(assert(world.gui.SelectedObject).Name):toBe("RootAction")
				world.stop()
				local selection = Compose.cell("one")
				local pager = setup(function(UI: FacetControls)
					return UI.PageView {
						selection = selection,
						pages = {
							{ id = "one", content = UI.Button "PageOne" { label = "One" } },
							{ id = "two", content = UI.Button "PageTwo" { label = "Two" } },
						},
					}
				end)
				local pages = find(pager.screen, "Pages")
				pager.engine.environment.poke(pages, "AbsoluteWindowSize", pager.engine.types.Vector2.new(320, 160))
				pager.engine.environment.poke(pages, "AbsoluteCanvasSize", pager.engine.types.Vector2.new(640, 160))
				pager.gui.SelectedObject = find(pager.screen, "PageOne")
				selection:set("two")
				expect(assert(pager.gui.SelectedObject).Name):toBe("PageTwo")
				pager.stop()
			end,
		})
		it("starts a pushed page on its named or first content control before the stack Back", {
			id = "native_navigation::native navigation controls::starts a pushed page on its named or first content control before the stack Back",
			run = function()
				local path = Compose.cell({} :: { Navigation.NavigationEntry<unknown> })
				local asked = 0
				local rows = Compose.cell(false)
				local function page(UI: FacetControls, named: boolean): Instance
					return UI.VStack {
						UI.NavBar "Header" {
							title = "Shop",
							trailing = UI.Button "Close" {
								label = "Close",
								onActivate = function()
									path:set({})
								end,
							},
						},
						UI.VStack(if named then "Body" else "Content")({ UI.Button "FirstCard" { label = "Card" } }),
					}
				end
				local world = setup(function(UI: FacetControls)
					local spec: NavigationProps.NavigationStackSpec<unknown> = {
						path = path,
						root = {
							content = function(): Instance
								return UI.Button "RootAction" { label = "Root" }
							end,
						} :: Navigation.NavigationDestination<unknown>,
						destinations = {
							empty = {
								title = "Empty",
								content = function(): Instance
									return UI.Text { text = "Nothing to act on" }
								end,
							} :: Navigation.NavigationDestination<unknown>,
							missing = {
								title = "Missing",
								initialFocus = "Nowhere",
								content = function(): Instance
									return UI.Button "MissingAction" { label = "Missing" }
								end,
							} :: Navigation.NavigationDestination<unknown>,
							header = {
								chrome = "hidden" :: "hidden",
								content = function(): Instance
									return page(UI, false)
								end,
							} :: Navigation.NavigationDestination<unknown>,
							late = {
								chrome = "hidden" :: "hidden",
								content = function(): Instance
									return UI.VStack {
										UI.NavBar "Header" {
											title = "Garage",
											trailing = UI.Button "Close" { label = "Close" },
										},
										UI.VStack "Rows" {
											Compose.show(rows, function()
												return UI.Button "Row" { label = "Row" }
											end),
										},
									}
								end,
							} :: Navigation.NavigationDestination<unknown>,
							named = {
								chrome = "hidden" :: "hidden",
								initialFocus = function(): string?
									asked += 1
									return "Body"
								end,
								content = function(): Instance
									return page(UI, true)
								end,
							} :: Navigation.NavigationDestination<unknown>,
						},
					}
					return UI.NavigationStack(spec)
				end, { motionLevel = "none" })
				local function open(id: string): string
					path:set({ { id = id } })
					world.settle()
					return assert(world.gui.SelectedObject).Name
				end
				world.gui.SelectedObject = find(world.screen, "RootAction")
				expect(open("empty")):toBe("Back")
				expect(open("missing")):toBe("MissingAction")
				expect(open("header")):toBe("FirstCard")
				expect(open("named")):toBe("FirstCard")
				expect(open("late")):toBe("Close")
				rows:set(true)
				local row = find(world.screen, "Row")
				world.engine.environment.poke(row, "AbsoluteSize", world.engine.types.Vector2.new(120, 44))
				world.settle()
				expect(assert(world.gui.SelectedObject).Name):toBe("Row")
				rows:set(false)
				expect(open("header")):toBe("FirstCard")
				expect(open("late")):toBe("Close")
				local moved = world.gui.SelectedObject
				world.gui.SelectedObject = nil
				world.gui.SelectedObject = moved
				rows:set(true)
				world.engine.environment.poke(
					find(world.screen, "Row"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(120, 44)
				)
				world.settle()
				expect(assert(world.gui.SelectedObject).Name):toBe("Close")
				expect(asked):toBe(1)
				path:set({})
				world.settle()
				expect(assert(world.gui.SelectedObject).Name):toBe("RootAction")
				world.stop()
			end,
		})
		it("bounds menu scrolling, prunes removed branches and closes every level on tap away", {
			id = "native_navigation::native navigation controls::bounds menu scrolling, prunes removed branches and closes every level on tap away",
			run = function()
				local shown, items: FixtureComposeTypes.Value<{ FixtureNavigationTypes.MenuItem<any> }> =
					Compose.cell(true), Compose.cell({ { id = "branch", label = "Branch", children = {
						menuCommand("leaf", "Leaf"),
					} } } :: { Navigation.MenuItem<any> })
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.MenuSpec<string> = { isPresented = shown, items = items }
					return UI.Menu(controlProps)
				end)
				local panel = find(world.screen, "MenuPanel")
				world.engine.environment.poke(panel.Parent, "AbsoluteSize", world.engine.types.Vector2.new(700, 300))
				world.engine.environment.poke(
					find(world.screen, "MenuRows"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(280, 1000)
				)
				expect(find(panel, "MenuScroll").ClassName):toBe("ScrollingFrame")
				expect(panel.Size.Y.Offset):toBe(276)
				find(world.screen, "branch").Activated:Fire()
				items:set({ menuCommand("other", "Other") })
				expect((find(world.screen, "leaf"))):toBe(nil)
				expect(find(world.screen, "other") ~= nil):toBe(true)
				items:set({
					submenu("branch", "Branch", { menuCommand("leaf", "Leaf") }),
				})
				find(world.screen, "branch").Activated:Fire()
				find(world.screen, "DismissTarget").Activated:Fire()
				expect((shown:peek())):toBe(false)
				world.stop()
			end,
		})

		it("adapts automatic pickers and updates native segment axis and badges without replacing options", {
			id = "native_navigation::native navigation controls::adapts automatic pickers and updates native segment axis and badges without replacing options",
			run = function()
				local value, axis, badge = Compose.cell("a"), cells.axis("x"), Compose.cell(1)
				local position, visible, interactable = Compose.cell(24), Compose.cell(true), Compose.cell(true)
				local reference, references, enters = nil, 0, 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local pickerProps1: NavigationProps.SinglePickerSpec<string> = {
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
						MouseEnter = function()
							enters += 1
						end,
						Host.UICorner "AuthoredCorner" {},
						selected = value,
						options = {
							{ value = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
							{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
						},
					}
					local pickerProps2: NavigationProps.SinglePickerSpec<string> = {
						style = "segmented" :: "segmented",
						axis = axis,
						selected = value,
						options = {
							{ value = "a", label = "Alpha", badge = badge } :: Navigation.PickerOption<string>,
							{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
						},
					}
					return Host.Frame {
						UI.Picker "Auto"(pickerProps1),
						UI.Picker "Segments"(pickerProps2),
					}
				end)
				local automatic = find(world.screen, "Auto")
				local decoration = find(automatic, "AuthoredCorner")
				expect(reference):toBe(automatic)
				expect(automatic.Position.X.Offset):toBe(24)
				expect(automatic.Position.Y.Offset):toBe(70)
				expect(automatic.AnchorPoint.X):toBe(0.5)
				expect(automatic.Size.X.Offset):toBe(240)
				expect(automatic.Size.Y.Offset):toBe(44)
				expect(automatic.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				expect(automatic.LayoutOrder):toBe(7)
				expect((automatic:GetAttribute("role"))):toBe("choice")
				expect(decoration.Parent):toBe(automatic)
				local presentation = find(automatic, "Presentation")
				expect(presentation.Position.X.Offset):toBe(0)
				expect(presentation.Size.X.Scale):toBe(1)
				expect(presentation.Size.Y.Scale):toBe(1)
				expect((presentation:GetAttribute("role"))):toBe(nil)
				automatic.MouseEnter:Fire()
				presentation.MouseEnter:Fire()
				expect(enters):toBe(1)
				position:set(52)
				visible:set(false)
				interactable:set(false)
				expect(automatic.Position.X.Offset):toBe(52)
				expect(automatic.Visible):toBe(false)
				expect(automatic.Interactable):toBe(false)
				visible:set(true)
				interactable:set(true)
				local segments = find(world.screen, "Segments")
				local a = find(segments, "a")
				axis:set("y")
				badge:set(3)
				expect((find(segments, "a"))):toBe(a)
				expect(a.Size.X.Scale):toBe(1)
				expect((a:GetAttribute("label"))):toBe("Alpha (3)")
				expect(find(a, "Count").Text):toBe("3")
				expect(segments:FindFirstChildWhichIsA("UIListLayout").FillDirection):toBe(
					world.engine.types.Enum.FillDirection.Vertical
				)

				world.engine.environment.poke(
					find(automatic, "LabelMeasure"),
					"TextBounds",
					world.engine.types.Vector2.new(100, 18)
				)
				world.engine.environment.poke(automatic, "AbsoluteSize", world.engine.types.Vector2.new(120, 44))
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Touch
				)
				expect(find(find(world.screen, "Auto"), "Trigger") ~= nil):toBe(true)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Gamepad
				)
				expect(find(find(world.screen, "Auto"), "b") ~= nil):toBe(true)
				expect((find(world.screen, "Auto"))):toBe(automatic)
				expect((find(automatic, "AuthoredCorner"))):toBe(decoration)
				expect(automatic.Position.X.Offset):toBe(52)
				expect(find(automatic, "Presentation").Position.X.Offset):toBe(0)
				expect(references):toBe(1)
				automatic.MouseEnter:Fire()
				expect(enters):toBe(2)
				expect((value:peek())):toBe("a")
				world.stop()
			end,
		})

		it("bounds menu picker triggers to authored widths without losing their full label", {
			id = "native_navigation::native navigation controls::bounds menu picker triggers to authored widths without losing their full label",
			run = function()
				local selected = Compose.cell("hud")
				local sizing: FixtureComposeTypes.Value<Enum.AutomaticSize>
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					sizing = Compose.cell(engine.types.Enum.AutomaticSize.None)
					local pickerProps1: NavigationProps.SinglePickerSpec<string> = {
						style = "menu" :: "menu",
						Size = engine.types.UDim2.new(1, -160, 0, 44),
						selected = selected,
						options = {
							{ value = "hud", label = "Screen-anchored HUD with a long title" } :: Navigation.PickerOption<string>,
							{ value = "other", label = "Another destination with a long title" } :: Navigation.PickerOption<string>,
						},
					}
					local menuProps1: NavigationProps.MenuSpec<string> = {
						Size = engine.types.UDim2.new(1, 0, 0, 0),
						AutomaticSize = sizing,
						label = "Menu",
						items = {
							menuCommand("one", "One") :: FixtureNavigationTypes.MenuItem<any>,
						},
					}
					return Host.Frame {
						UI.Picker "Bounded"(pickerProps1),
						UI.Menu "AdaptiveHeight"(menuProps1),
					}
				end)
				local bounded = find(world.screen, "Bounded")
				local trigger = find(bounded, "Trigger")
				expect(bounded.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				expect(trigger.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				expect(trigger.Size.X.Scale):toBe(1)
				expect(trigger.Size.X.Offset):toBe(0)
				expect(trigger.Size.Y.Scale):toBe(1)
				expect(trigger.TextTruncate):toBe(world.engine.types.Enum.TextTruncate.AtEnd)
				expect(trigger.TextWrapped):toBe(false)
				expect(trigger.ClipsDescendants):toBe(true)
				expect(trigger.Text):toBe("Screen-anchored HUD with a long title")
				expect((trigger:GetAttribute("FacetLabel"))):toBe(trigger.Text)
				trigger.Activated:Fire()
				find(find(world.screen, "MenuPanel"), "other").Activated:Fire()
				expect((selected:peek())):toBe("other")
				expect(trigger.Text):toBe("Another destination with a long title")
				expect((trigger:GetAttribute("FacetLabel"))):toBe(trigger.Text)
				local adaptive = find(find(world.screen, "AdaptiveHeight"), "Trigger")
				sizing:set(world.engine.types.Enum.AutomaticSize.Y)
				expect(adaptive.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.Y)
				expect(adaptive.Size.X.Scale):toBe(1)
				expect(adaptive.Size.Y.Scale):toBe(0)
				expect(adaptive.Size.Y.Offset >= 44):toBe(true)
				world.stop()
			end,
		})

		it("keeps plain picker segments native while retaining live description sources", {
			id = "native_navigation::native navigation controls::keeps plain picker segments native while retaining live description sources",
			run = function()
				local selected, description = Compose.cell("a"), Compose.cell("")
				local initial: { Navigation.PickerOption<string> } = { { value = "a", label = "Alpha" } }
				local options = Compose.cell(initial)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local pickerProps1: NavigationProps.SinglePickerSpec<string> = {
						style = "segmented" :: "segmented",
						selected = selected,
						options = {
							{ value = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
							{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
						},
					}
					local pickerProps2: NavigationProps.SinglePickerSpec<string> = {
						style = "segmented" :: "segmented",
						selected = selected,
						options = {
							{ value = "a", label = "Alpha", description = description } :: Navigation.PickerOption<string>,
						},
					}
					local pickerProps3: NavigationProps.SinglePickerSpec<string> = {
						style = "segmented" :: "segmented",
						selected = selected,
						options = options,
					}
					return Host.Frame {
						UI.Picker "Plain"(pickerProps1),
						UI.Picker "ReadableDescription"(pickerProps2),
						UI.Picker "ReadableOptions"(pickerProps3),
					}
				end)
				local plain = find(find(world.screen, "Plain"), "a")
				expect(plain.ClassName):toBe("TextButton")
				expect(plain.Text):toBe("Alpha")
				expect((find(plain, "Content"))):toBe(nil)
				expect((find(plain, "Description"))):toBe(nil)
				find(find(world.screen, "Plain"), "b").Activated:Fire()
				expect((selected:peek())):toBe("b")
				local described = find(find(world.screen, "ReadableDescription"), "a")
				description:set("Appeared")
				expect((find(find(world.screen, "ReadableDescription"), "a"))):toBe(described)
				expect(find(described, "Description").Text):toBe("Appeared")
				expect(find(described, "Description").Visible):toBe(true)
				description:set("")
				expect(find(described, "Description").Visible):toBe(false)
				local replaced = find(find(world.screen, "ReadableOptions"), "a")
				options:set({ { value = "a", label = "Alpha updated", description = "Added later" } })
				expect((find(find(world.screen, "ReadableOptions"), "a"))):toBe(replaced)
				expect(find(replaced, "Title").Text):toBe("Alpha updated")
				expect(find(replaced, "Description").Text):toBe("Added later")
				expect((find(find(world.screen, "Plain"), "a"))):toBe(plain)
				world.stop()
			end,
		})

		it("quarantines invalid paths and contains destination faults while preserving Back", {
			id = "native_navigation::native navigation controls::quarantines invalid paths and contains destination faults while preserving Back",
			run = function()
				local path, disposed = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> }), 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
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
									Host.Frame {}
									error("failed page")
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
						},
					}
					return UI.NavigationStack(controlProps)
				end)
				local root = find(world.screen, "@root")
				expect(find(root, "Destination").Position.Y.Offset):toBe(0)
				path:set({ { id = "good" } })
				local good = find(world.screen, "Good")
				path:set({ { id = "unknown" } })
				expect((find(world.screen, "Good"))):toBe(good)
				expect(find(world.screen, "NavigationStack"):GetAttribute("FacetError") ~= nil):toBe(true)
				path:set({ { id = "bad" } })
				expect(find(world.screen, "DestinationError") ~= nil):toBe(true)
				expect(disposed):toBe(1)
				find(find(world.screen, "bad"), "Back").Activated:Fire()
				expect(#path:peek()):toBe(0)
				expect(find(world.screen, "RootAction") ~= nil):toBe(true)
				world.stop()
			end,
		})

		it("routes nested Back through the focused native context before its parent", {
			id = "native_navigation::native navigation controls::routes nested Back through the focused native context before its parent",
			run = function()
				local outer, inner =
					Compose.cell({ { id = "child" } } :: { NavigationFixtures.NavigationEntry<any> }),
					Compose.cell({ { id = "detail" } } :: { NavigationFixtures.NavigationEntry<any> })
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
						path = outer,
						root = {
							content = function(): Instance
								return UI.Button { label = "Root" }
							end,
						} :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							child = {
								content = function(): Instance
									local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
										path = inner,
										root = {
											content = function(): Instance
												return UI.Button { label = "Child root" }
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
									return UI.NavigationStack "ChildStack"(controlProps)
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
						},
					}
					return UI.NavigationStack(controlProps)
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
				expect(winner ~= nil):toBe(true)
				winner.Pressed:Fire()
				expect(#inner:peek()):toBe(0)
				expect(#outer:peek()):toBe(1)
				world.stop()
			end,
		})

		it("routes Back through separately created nested controls", {
			id = "native_navigation::native navigation controls::routes Back through separately created nested controls",
			run = function()
				local outer, inner =
					Compose.cell({ { id = "child" } } :: { NavigationFixtures.NavigationEntry<any> }),
					Compose.cell({ { id = "detail" } } :: { NavigationFixtures.NavigationEntry<any> })
				local world = setup(function(UI: FacetControls, _Host, engine, gui, runtime)
					local Child = controls(Compose, runtime, { types = engine.types, services = { GuiService = gui } })
					local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
						path = outer,
						root = {
							content = function(): Instance
								return UI.Button { label = "Root" }
							end,
						} :: NavigationFixtures.NavigationDestination<any>,
						destinations = {
							child = {
								content = function(): Instance
									local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
										path = inner,
										root = {
											content = function(): Instance
												return UI.Button { label = "Child root" }
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
									return Child.NavigationStack "ChildStack"(controlProps)
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
						},
					}
					return UI.NavigationStack(controlProps)
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
				expect(winner ~= nil):toBe(true)
				winner.Pressed:Fire()
				expect(#inner:peek()):toBe(0)
				expect(#outer:peek()):toBe(1)
				world.stop()
			end,
		})

		it("keeps callouts nonmodal, fits their plate and observes nonconsuming tap away", {
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
					return Host.Frame {
						anchor,
						UI.Callout {
							anchor = anchor :: GuiObject,
							isPresented = shown,
							onRetire = function(reason)
								retired = reason
							end,
							content = function(): Instance
								return UI.Button { label = "Tip" }
							end,
						},
					}
				end)
				local V = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsoluteSize", V.new(320, 400))
				local anchor, panel = find(world.screen, "Anchor"), find(world.screen, "CalloutPanel")
				world.engine.environment.poke(anchor, "AbsolutePosition", V.new(280, 20))
				world.engine.environment.poke(anchor, "AbsoluteSize", V.new(32, 44))
				world.engine.environment.poke(panel, "AbsoluteSize", V.new(280, 100))
				world.settle()
				expect((near((corner(panel)), 32))):toBe(true)
				expect(world.gui.SelectedObject):toBe(anchor)
				anchor.Activated:Fire()
				expect(presses):toBe(1)
				world.engine.environment.fire(
					world.input,
					"InputBegan",
					{ UserInputType = world.engine.types.Enum.UserInputType.MouseButton1, Position = V.new(10, 350) },
					false
				)
				expect(retired):toBe("tapAway")
				expect((shown:peek())):toBe(true)
				world.settle()
				expect((find(world.screen, "CalloutPanel"))):toBe(nil)
				world.stop()
			end,
		})

		it("places a callout inside the overlay parent that receives it", {
			id = "native_navigation::native navigation controls::places a callout inside the overlay parent that receives it",
			run = function()
				local engine = engines.new()
				local gui = engine.new("GuiService")
				gui.GuiNavigationEnabled = true
				gui.AutoSelectGuiEnabled = true
				gui.TouchControlsEnabled = true
				engine.environment.fakeOn(gui, "GetInsetArea", function()
					return engine.types.Rect.new(0, 0, 1280, 720)
				end)
				engine.environment.fakeOn(gui, "GetGuiInset", function()
					return engine.types.Vector2.zero, engine.types.Vector2.zero
				end)
				local input = engine.new("UserInputService")
				engine.environment.fakeOn(input, "GetLastInputType", function()
					return engine.types.Enum.UserInputType.Keyboard
				end)
				for _, method in { "IsKeyDown", "IsGamepadButtonDown" } do
					engine.environment.fakeOn(input, method, function()
						return false
					end)
				end
				for _, method in
					{ "GetNavigationGamepads", "GetKeysPressed", "GetMouseButtonsPressed", "GetGamepadState" }
				do
					engine.environment.fakeOn(input, method, function()
						return {}
					end)
				end
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local overlay = engine.new("Frame")
				local UI = controls(Compose, runtime, {
					types = engine.types,
					services = {
						GuiService = (gui :: unknown) :: GuiService,
						UserInputService = (input :: unknown) :: UserInputService,
					},
					overlayParent = overlay,
				})
				local stop, screen: any = runtime.mount(function()
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Facet.host(runtime).ScreenGui({
						Facet.host(runtime).Frame({
							anchor,
							UI.Callout {
								anchor = anchor :: GuiObject,
								isPresented = Compose.cell(true),
								onRetire = function() end,
								content = function(): Instance
									return UI.Button { label = "Tip" }
								end,
							},
						}),
					})
				end, engine.new("Folder"))
				overlay.Parent = screen
				local V = engine.types.Vector2
				engine.environment.poke(screen, "AbsoluteSize", V.new(1920, 1080))
				engine.environment.poke(overlay, "AbsolutePosition", V.new(100, 50))
				engine.environment.poke(overlay, "AbsoluteSize", V.new(320, 400))
				local anchor, panel = find(screen, "Anchor"), find(screen, "CalloutPanel")
				expect((panel:IsDescendantOf(overlay))):toBe(true)
				engine.environment.poke(anchor, "AbsolutePosition", V.new(380, 70))
				engine.environment.poke(anchor, "AbsoluteSize", V.new(32, 44))
				engine.environment.poke(panel, "AbsoluteSize", V.new(280, 100))
				for _ = 1, 60 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect((near((corner(panel)), 32))):toBe(true)
				expect(panel.Size.X.Offset):toBe(280)
				engine.environment.poke(overlay, "AbsoluteSize", V.new(200, 400))
				for _ = 1, 60 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect(panel.Size.X.Offset):toBe(184)
				stop()
				runtime:dispose()
			end,
		})

		it("retargets native sheet motion and honors live reduced motion without losing content", {
			id = "native_navigation::native navigation controls::retargets native sheet motion and honors live reduced motion without losing content",
			run = function()
				local selected, shown = Compose.cell("medium"), Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.Sheet {
						detent = selected,
						isPresented = shown,
						content = function(): Instance
							return UI.Button "KeptContent" { label = "Content" }
						end,
					}
				end)
				world.engine.environment.poke(
					find(world.screen, "Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(800, 720)
				)
				world.engine.heartbeat:Fire(1 / 600)
				world.engine.heartbeat:Fire(1 / 600)
				local panel, content = find(world.screen, "SheetPanel"), find(world.screen, "KeptContent")
				local before = panel.Size.Y.Offset
				selected:set("large")
				expect(panel.Size.Y.Offset):toBe(before)
				world.engine.heartbeat:Fire(0.1)
				expect(panel.Size.Y.Offset > before):toBe(true)
				world.engine.environment.poke(VerifyRoblox.assertInstance(world.gui), "ReducedMotionEnabled", true)
				expect(panel.Size.Y.Offset):toBe(684)
				expect((find(world.screen, "KeptContent"))):toBe(content)
				world.stop()
			end,
		})

		it("fades native tab layers with Compose and reveals an offscreen selected tab", {
			id = "native_navigation::native navigation controls::fades native tab layers with Compose and reveals an offscreen selected tab",
			run = function()
				local selected = Compose.cell("a")
				local world = setup(function(UI: FacetControls)
					return UI.TabView {
						selection = selected,
						placement = "topBar" :: "topBar",
						transition = { seconds = 0.2 },
						tabs = {
							{
								id = "a",
								content = function(): Instance
									return UI.Button "AContent" { label = "A" }
								end,
							},
							{
								id = "b",
								content = function(): Instance
									return UI.Button "BContent" { label = "B" }
								end,
							},
						},
					}
				end)
				local bar = find(world.screen, "Tabs")
				expect(find(world.screen, "Content").Position.Y.Offset > bar.Size.Y.Offset):toBe(true)
				world.engine.environment.poke(bar, "AbsoluteSize", world.engine.types.Vector2.new(100, 44))
				local b = find(bar, "b")
				world.engine.environment.poke(b, "AbsolutePosition", world.engine.types.Vector2.new(160, 0))
				world.engine.environment.poke(b, "AbsoluteSize", world.engine.types.Vector2.new(80, 44))
				selected:set("b")
				expect(bar.CanvasPosition.X):toBe(140)
				local panel = fadeKit.layer(find(world.screen, "BContent"))
				expect(panel.ClassName):toBe("Frame")
				play(world.engine, 0.2)
				expect((fadeKit.of(panel))):toBe(0)
				selected:set("a")
				expect(panel.Interactable):toBe(false)
				world.engine.environment.poke(VerifyRoblox.assertInstance(world.gui), "ReducedMotionEnabled", true)
				play(world.engine, 0.2)
				expect((fadeKit.of(fadeKit.layer(find(world.screen, "AContent"))))):toBe(0)
				world.stop()
			end,
		})

		it("clears bound alert errors and turns native page animation off for reduced motion", {
			id = "native_navigation::native navigation controls::clears bound alert errors and turns native page animation off for reduced motion",
			run = function()
				local shown, errorValue: FixtureComposeTypes.Value<string?>, page =
					Compose.cell(true), cells.optionalString("Oops"), Compose.cell("a")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local alertProps1: NavigationProps.AlertSpec<unknown> = { isPresented = shown, error = errorValue }
					return Host.Frame {
						UI.Alert(alertProps1),
						UI.PageView {
							selection = page,
							pages = {
								{
									id = "a",
									content = function(): Instance
										return Host.Frame {}
									end,
								},
								{
									id = "b",
									content = function(): Instance
										return Host.Frame {}
									end,
								},
							},
						},
					}
				end)
				find(world.screen, "ModalBack").Pressed:Fire()
				expect((errorValue:peek())):toBe(nil)
				world.engine.environment.poke(VerifyRoblox.assertInstance(world.gui), "ReducedMotionEnabled", true)
				local pages = find(world.screen, "Pages")
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(pages, "AbsoluteWindowSize", V2.new(320, 160))
				world.engine.environment.poke(pages, "AbsoluteCanvasSize", V2.new(640, 160))
				page:set("b")
				expect(pages.CanvasPosition.X):toBe(320)
				world.stop()
			end,
		})
		it("lets one arrow from the anchor reach a callout plate and B dismiss it back to the anchor", {
			id = "native_navigation::native navigation controls::lets one arrow from the anchor reach a callout plate and B dismiss it back to the anchor",
			run = function()
				local reasons: { "action" | "dismissed" | "featureUsed" | "seen" | "tapAway" } = {}
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame {
						anchor,
						UI.Callout {
							anchor = anchor :: GuiObject,
							edge = "bottom" :: "bottom",
							title = "New",
							onRetire = function(reason)
								table.insert(reasons, reason)
							end,
						},
					}
				end)
				local V = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsoluteSize", V.new(960, 720))
				local anchor, panel = find(world.screen, "Anchor"), find(world.screen, "CalloutPanel")
				world.engine.environment.poke(anchor, "AbsolutePosition", V.new(100, 100))
				world.engine.environment.poke(anchor, "AbsoluteSize", V.new(200, 44))
				world.engine.environment.poke(panel, "AbsolutePosition", V.new(100, 160))
				world.engine.environment.poke(panel, "AbsoluteSize", V.new(280, 120))
				world.settle()
				local dismiss = find(world.screen, "Dismiss")
				world.gui.SelectedObject = anchor
				expect(anchor.NextSelectionDown):toBe(dismiss)
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
				expect(back ~= nil):toBe(true)
				back.Pressed:Fire()
				expect(reasons[1]):toBe("dismissed")
				world.settle()
				expect(world.gui.SelectedObject):toBe(anchor)
				expect(anchor.NextSelectionDown):toBe(nil)
				world.stop()
			end,
		})

		it("restores only the anchor link the callout set and leaves an app's own link", {
			id = "native_navigation::native navigation controls::restores only the anchor link the callout set and leaves an app's own link",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame {
						anchor,
						UI.Button "Own" { label = "Own" },
						UI.Callout {
							anchor = anchor :: GuiObject,
							edge = "bottom" :: "bottom",
							title = "New",
							onRetire = function() end,
						},
					}
				end)
				local V = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsoluteSize", V.new(960, 720))
				local anchor, panel = find(world.screen, "Anchor"), find(world.screen, "CalloutPanel")
				local own = find(world.screen, "Own")
				world.engine.environment.poke(anchor, "AbsolutePosition", V.new(100, 300))
				world.engine.environment.poke(anchor, "AbsoluteSize", V.new(200, 44))
				world.engine.environment.poke(panel, "AbsolutePosition", V.new(100, 360))
				world.engine.environment.poke(panel, "AbsoluteSize", V.new(280, 120))
				world.settle()
				expect(anchor.NextSelectionDown):toBe(find(world.screen, "Dismiss"))
				anchor.NextSelectionDown = own
				world.engine.environment.poke(panel, "AbsolutePosition", V.new(100, 160))
				world.settle()
				expect(anchor.NextSelectionDown):toBe(own)
				expect(anchor.NextSelectionUp):toBe(find(world.screen, "Dismiss"))
				local dismiss = find(world.screen, "Dismiss")
				local holder = dismiss.Parent
				dismiss.Parent = nil
				world.settle()
				expect(anchor.NextSelectionUp):toBe(nil)
				local fresh = world.engine.new("TextButton")
				fresh.Name = "Fresh"
				fresh.Parent = holder
				world.settle()
				expect(anchor.NextSelectionUp):toBe(fresh)
				world.stop()
				expect(anchor.NextSelectionDown):toBe(own)
				expect(anchor.NextSelectionUp):toBe(nil)
			end,
		})

		it("keeps measured callout arrows outside automatic content bounds", {
			id = "native_navigation::native navigation controls::keeps measured callout arrows outside automatic content bounds",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame {
						anchor,
						UI.Callout {
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
						},
					}
				end)
				local V = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsoluteSize", V.new(960, 720))
				local anchor, panel, arrow =
					find(world.screen, "Anchor"), find(world.screen, "CalloutPanel"), find(world.screen, "Arrow")
				world.engine.environment.poke(anchor, "AbsolutePosition", V.new(160, 560))
				world.engine.environment.poke(anchor, "AbsoluteSize", V.new(240, 44))
				expect(panel.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.Y)
				expect(panel.Size.Y.Scale):toBe(0)
				expect(panel.Size.Y.Offset):toBe(0)
				expect((arrow:IsDescendantOf(panel))):toBe(false)
				expect(arrow.Parent):toBe(panel.Parent)
				expect((arrow:HasTag("facet-tail"))):toBe(true)
				expect(arrow.Rotation):toBe(45)
				expect(arrow.ZIndex < panel.ZIndex):toBe(true)
				expect((find(world.screen, "ArrowSeam"))):toBe(nil)
				local outline = find(world.screen, "Outline")
				expect(outline.ClassName):toBe("Path2D")
				expect(outline.Parent.Name):toBe("OutlineBoundary")
				expect(find(world.screen, "OutlineFade").Parent):toBe(panel.Parent)
				expect(outline.Closed):toBe(true)
				expect((outline:HasTag("facet-outline"))):toBe(true)
				expect((panel:HasTag("facet-outlined"))):toBe(true)
				world.settle()
				for _, height in { 96, 128, 96 } do
					world.engine.environment.poke(panel, "AbsoluteSize", V.new(280, height))
					local _, top = corner(panel)
					expect((near(top, 560 - height - 8 - LIFT))):toBe(true)
					expect((near(arrow.Position.Y.Offset, 560 - 8 - LIFT))):toBe(true)
					local points = outline:GetControlPoints()
					expect(#points):toBe(11)
					local lowest = 0
					for _, point in points do
						lowest = math.max(lowest, point.Position.Y.Scale * height)
					end
					expect((near(lowest, height + arrow.Size.X.Offset * math.sqrt(2) / 2))):toBe(true)
				end
				world.engine.environment.poke(panel, "AbsoluteSize", V.new(30, 96))
				local previous = math.huge
				for _, point in outline:GetControlPoints() do
					if point.Position.Y.Scale * 96 >= 96 - 0.01 then
						local x = point.Position.X.Scale * 30
						expect(`short side runs one way {x <= previous + 0.01} at {x}`):toBe(
							`short side runs one way true at {x}`
						)
						previous = x
					end
				end
				local first = outline:GetControlPoints()[1]
				expect(math.abs(first.Position.X.Scale * 30 - 12) < 0.01):toBe(true)
				world.engine.environment.poke(panel, "AbsoluteSize", V.new(280, 96))
				world.engine.environment.poke(anchor, "AbsolutePosition", V.new(0, 560))
				world.engine.environment.poke(anchor, "AbsoluteSize", V.new(8, 44))
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
				expect(`tail clears the corner arc by a tail width: {tip - radius - half >= half - 0.01}`):toBe(
					"tail clears the corner arc by a tail width: true"
				)
				anchor.Visible = false
				expect((find(world.screen, "Arrow"))):toBe(nil)
				expect((find(world.screen, "CalloutPanel"))):toBe(nil)
				world.stop()
			end,
		})

		it("moves a top callout below its anchor when only the bottom has room", {
			id = "native_navigation::native navigation controls::moves a top callout below its anchor when only the bottom has room",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame {
						anchor,
						UI.Callout {
							anchor = anchor :: GuiObject,
							edge = "top" :: "top",
							onRetire = function() end,
							content = function(): Instance
								return UI.Text { text = "Tip" }
							end,
						},
					}
				end)
				local V = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsoluteSize", V.new(844, 311))
				local anchor, panel, arrow =
					find(world.screen, "Anchor"), find(world.screen, "CalloutPanel"), find(world.screen, "Arrow")
				world.engine.environment.poke(anchor, "AbsolutePosition", V.new(8, 18))
				world.engine.environment.poke(anchor, "AbsoluteSize", V.new(109, 44))
				world.engine.environment.poke(panel, "AbsoluteSize", V.new(280, 106))
				world.settle()
				expect(materialize.of(panel).Scale):toBe(1)
				expect((near(select(2, corner(panel)), 18 + 44 + 8 + LIFT))):toBe(true)
				expect((near(arrow.Position.Y.Offset, 18 + 44 + 8 + LIFT))):toBe(true)
				world.engine.environment.poke(anchor, "AbsolutePosition", V.new(8, 200))
				expect((near(select(2, corner(panel)), 200 - 106 - 8 - LIFT))):toBe(true)
				world.engine.environment.poke(anchor, "AbsolutePosition", V.new(8, 100))
				world.engine.environment.poke(panel, "AbsoluteSize", V.new(280, 250))
				expect((near(select(2, corner(panel)), 8))):toBe(true)
				world.stop()
			end,
		})

		it("renders disclosure appearances and collapsible summaries with native assets and close policy", {
			id = "native_navigation::native navigation controls::renders disclosure appearances and collapsible summaries with native assets and close policy",
			run = function()
				local expanded, image = Compose.cell(false), Compose.cell("rbxassetid://1")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.DisclosureGroup "Disclosure" {
							label = "Details",
							appearance = "divided" :: "divided",
							chevronPosition = "leading" :: "leading",
							expanded = Compose.cell(true),
							content = function(): Instance
								return UI.Text { text = "Details" }
							end,
						},
						UI.CollapsibleView "Summary" {
							label = "Summary",
							image = image,
							expanded = expanded,
							dismissButton = false,
							content = function(): Instance
								return UI.Button "DetailsAction" { label = "Details" }
							end,
						},
					}
				end)
				expect(find(find(world.screen, "Disclosure"), "LeadingIcon") ~= nil):toBe(true)
				expect(find(find(world.screen, "Disclosure"), "Divider") ~= nil):toBe(true)
				local summary = find(world.screen, "Summary")
				image:set("rbxassetid://2")
				expect(find(summary, "Image").Image):toBe("rbxassetid://2")
				summary.Activated:Fire()
				expect((find(world.screen, "Close"))):toBe(nil)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Gamepad
				)
				expect(find(world.screen, "Close") ~= nil):toBe(true)
				find(world.screen, "Close").Activated:Fire()
				expect((expanded:peek())):toBe(false)
				expect((find(world.screen, "DetailsAction"))):toBe(nil)
				expect((find(world.screen, "Summary"))):toBe(summary)
				world.stop()
			end,
		})

		it("renders sidebar sections and collapsed tab destinations through the shared menu", {
			id = "native_navigation::native navigation controls::renders sidebar sections and collapsed tab destinations through the shared menu",
			run = function()
				local selected = Compose.cell("a")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local sidebarTabs: { Tab } = {
						{
							id = "a",
							section = "s",
							content = function(): Instance
								return Host.Frame {}
							end,
						},
						{
							id = "b",
							section = "s",
							content = function(): Instance
								return Host.Frame {}
							end,
						},
					}
					local collapsedTabs: { Tab } = {
						{
							id = "a",
							label = "Alpha",
							content = function(): Instance
								return Host.Frame {}
							end,
						},
						{
							id = "b",
							label = "Beta",
							content = function(): Instance
								return Host.Frame {}
							end,
						},
					}
					return Host.Frame {
						UI.TabView "Sidebar" {
							selection = selected,
							placement = "sidebar" :: "sidebar",
							sections = { { id = "s", label = "Section" } },
							tabs = sidebarTabs,
						},
						UI.TabView "Collapsed" {
							selection = selected,
							style = "collapsible" :: "collapsible",
							tabs = collapsedTabs,
						},
					}
				end)
				expect(find(find(world.screen, "Sidebar"), "Section").Text):toBe("Section")
				local collapsed = find(world.screen, "Collapsed")
				expect(find(collapsed, "Tabs").Visible):toBe(false)
				find(find(collapsed, "TabsMenu"), "Trigger").Activated:Fire()
				find(find(world.screen, "MenuPanel"), "b").Activated:Fire()
				expect((selected:peek())):toBe("b")
				expect(find(find(collapsed, "TabsMenu"), "Trigger").Text):toBe("Beta")
				world.stop()
			end,
		})

		it("closes menu and picker presentations when native ancestors become unavailable", {
			id = "native_navigation::native navigation controls::closes menu and picker presentations when native ancestors become unavailable",
			run = function()
				local selected, opened = Compose.cell("a"), Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local pickerProps1: NavigationProps.SinglePickerSpec<string> = {
						selected = selected,
						style = "menu" :: "menu",
						isPresented = opened,
						options = {
							{ value = "a", label = "Alpha" } :: Navigation.PickerOption<string>,
							{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
						},
					}
					return Host.Frame "Surface" {
						UI.Picker(pickerProps1),
					}
				end)
				opened:set(true)
				local row = find(find(world.screen, "MenuPanel"), "b")
				find(world.screen, "Surface").Interactable = false
				expect((opened:peek())):toBe(false)
				expect((find(world.screen, "MenuPanel"))):toBe(nil)
				row.Activated:Fire()
				expect((selected:peek())):toBe("a")
				find(world.screen, "Surface").Interactable = true
				find(world.screen, "Trigger").Activated:Fire()
				expect((opened:peek())):toBe(true)
				world.stop()
			end,
		})

		it("keeps panel art outside native layout and exposes alert artwork", {
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
					local alertProps1: NavigationProps.AlertSpec<unknown> =
						{ isPresented = alert, severity = "critical" :: "critical", title = "Danger" }
					return Host.Frame {
						UI.Alert(alertProps1),
						UI.Sheet {
							isPresented = sheet,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return Host.Frame {}
							end,
						},
					}
				end, { theme = package })
				local panel = find(world.screen, "AlertPanel")
				expect(panel.BackgroundTransparency):toBe(0)
				expect((panel:HasTag("facet-panel"))):toBe(true)
				expect(find(panel, "AlertIcon").Image ~= ""):toBe(true)
				local alertArt = find(panel, "panel1")
				expect(alertArt.Image):toBe("rbxassetid://42")
				alert:set(false)
				sheet:set(true)
				world.settle()
				panel = find(world.screen, "SheetPanel")
				expect(panel.BackgroundTransparency):toBe(0)
				expect((not world.engine.environment.isAlive(alertArt))):toBe(true)
				local skin, boundary = find(panel, "Skin"), find(panel, "SkinBoundary")
				local bounds, art = skin.Parent, find(skin, "panel1")
				expect(art.Image):toBe("rbxassetid://42")
				expect((panel:FindFirstChildWhichIsA("UIGridStyleLayout"))):toBeNil()
				expect(boundary.Parent):toBe(panel:FindFirstChild("Fade"))
				expect(bounds.Parent):toBe(boundary)
				expect(boundary.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
				expect(boundary.Size.X.Offset):toBe(1)
				expect(boundary.Size.Y.Offset):toBe(1)
				expect(boundary.Position.X.Scale):toBe(1)
				expect(boundary.Position.Y.Scale):toBe(1)
				expect(bounds.AnchorPoint):toBe(world.engine.types.Vector2.new(1, 1))
				world.engine.environment.poke(panel, "AbsoluteSize", world.engine.types.Vector2.new(360, 240))
				world.engine.environment.poke(boundary, "AbsoluteSize", world.engine.types.Vector2.new(2, 2))
				expect(bounds.Size.X.Offset):toBe(180)
				expect(bounds.Size.Y.Offset):toBe(120)
				world.engine.environment.poke(panel, "AbsoluteSize", world.engine.types.Vector2.new(200, 120))
				expect(bounds.Size.X.Offset):toBe(100)
				expect(bounds.Size.Y.Offset):toBe(60)
				world.stop()
				expect((not world.engine.environment.isAlive(art))):toBe(true)
				expect((not world.engine.environment.isAlive(boundary))):toBe(true)
			end,
		})

		it("animates alerts from native sources and reclaims interrupted Compose presence", {
			id = "native_navigation::native navigation controls::animates alerts from native sources and reclaims interrupted Compose presence",
			run = function()
				local shown = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local source = UI.Button "Source" { label = "Open" }
					local alertProps1: NavigationProps.AlertSpec<unknown> = {
						isPresented = shown,
						title = "Detail",
						transition = { source = source :: GuiObject, seconds = 0.2 },
					}
					return Host.Frame {
						source,
						UI.Alert(alertProps1),
					}
				end)
				local source = find(world.screen, "Source")
				world.engine.environment.poke(source, "AbsolutePosition", world.engine.types.Vector2.new(20, 30))
				world.engine.environment.poke(source, "AbsoluteSize", world.engine.types.Vector2.new(100, 60))
				shown:set(true)
				local panel = find(world.screen, "AlertPanel")
				expect(panel.Position.X.Offset):toBe(70)
				expect(panel.Position.Y.Offset):toBe(60)
				expect((fadeKit.of(panel))):toBe(1)
				world.engine.environment.poke(
					find(world.screen, "AlertModal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(800, 600)
				)
				world.engine.heartbeat:Fire(0.2)
				expect(panel.Position.X.Offset):toBe(400)
				expect((find(panel, "PresentationScale"))):toBeNil()
				shown:set(false)
				world.engine.heartbeat:Fire(0.1)
				expect((find(world.screen, "AlertPanel"))):toBe(panel)
				shown:set(true)
				expect((find(world.screen, "AlertPanel"))):toBe(panel)
				world.engine.heartbeat:Fire(0.2)
				expect((fadeKit.of(panel))):toBe(0)
				shown:set(false)
				world.engine.heartbeat:Fire(0.2)
				expect((find(world.screen, "AlertPanel"))):toBe(nil)
				world.stop()
			end,
		})

		it("keeps a full-screen alert layout inside the theme's panel insets", {
			id = "native_navigation::native navigation controls::keeps a full-screen alert layout inside the theme's panel insets",
			run = function()
				local shown = Compose.cell(false)
				local themes = require("../src/ui/themes")(Compose)
				local package = themes.neutralPackage()
				package.chrome =
					{ panel = { kind = "native", contentInsets = { left = 14, right = 14, top = 14, bottom = 14 } } }
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local alertProps1: NavigationProps.AlertSpec<unknown> = {
						isPresented = shown,
						title = "Detail",
						surface = "fullScreen" :: "fullScreen",
					}
					return Host.Frame {
						UI.Alert(alertProps1),
					}
				end, { theme = assert((themes.define(package))) })
				local V2 = world.engine.types.Vector2
				shown:set(true)
				local modal = find(world.screen, "AlertModal")
				world.engine.environment.poke(modal, "AbsoluteSize", V2.new(800, 600))
				expect(find(world.screen, "AlertLayout").Size):toBe(
					world.engine.types.UDim2.fromOffset(800 - 28, 600 - 28)
				)
				world.stop()
			end,
		})

		it("expands a source rectangle into full screen and reverses the same Compose-owned snapshot", {
			id = "native_navigation::native navigation controls::expands a source rectangle into full screen and reverses the same Compose-owned snapshot",
			run = function()
				local shown = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local camera = Host.Camera "PreviewCamera" {}
					local externalCamera = Host.Camera "ExternalCamera" {}
					local source = Host.Frame "Card" {
						Host.UICorner { CornerRadius = engine.types.UDim.new(0, 12) },
						Host.ViewportFrame "Scene" {
							CurrentCamera = Compose.static(camera),
							Host.Camera "PreviewCamera" { Archivable = false },
							camera,
							Host.WorldModel "World" {},
						},
						Host.ViewportFrame "OtherScene" { CurrentCamera = Compose.static(externalCamera) },
						UI.Button "Open" { label = "Open" },
						Host.UIDragDetector "CardDrag" {},
					}
					local alertProps1: NavigationProps.AlertSpec<unknown> = {
						isPresented = shown,
						title = "Detail",
						surface = "fullScreen" :: "fullScreen",
						transition = { source = source :: GuiObject, seconds = 0.4 },
					}
					return Host.Frame {
						source,
						externalCamera,
						UI.Alert(alertProps1),
					}
				end)
				local V2 = world.engine.types.Vector2
				local source = find(world.screen, "Card")
				local originalParent = source.Parent
				world.engine.environment.poke(source, "AbsolutePosition", V2.new(20, 30))
				world.engine.environment.poke(source, "AbsoluteSize", V2.new(120, 80))
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
				world.engine.environment.poke(modal, "AbsolutePosition", V2.new(10, 10))
				world.engine.environment.poke(modal, "AbsoluteSize", V2.new(800, 600))
				expect(panel:HasTag("facet-pane")):toBe(true)
				expect(panel:HasTag("facet-panel")):toBe(false)
				local snapshot = find(panel, "SourceSnapshot")
				expect(snapshot ~= nil):toBe(true)
				expect(snapshot == source):toBe(false)
				expect(snapshot.Interactable):toBe(false)
				expect(find(snapshot, "Open").Selectable):toBe(false)
				expect(find(snapshot, "CardDrag").Enabled):toBe(false)
				expect(find(snapshot, "Scene").CurrentCamera):toBe(find(snapshot, "PreviewCamera"))
				expect(find(snapshot, "Scene").CurrentCamera == find(source, "Scene").CurrentCamera):toBe(false)
				expect(find(snapshot, "OtherScene").CurrentCamera):toBe(find(world.screen, "ExternalCamera"))
				expect((find(snapshot, "ExternalCamera"))):toBe(nil)
				expect(panel.Size.X.Offset):toBe(120)
				expect(panel.Size.Y.Offset):toBe(80)
				expect(panel.Position.X.Offset):toBe(10)
				expect(panel.Position.Y.Offset):toBe(20)
				expect((fadeKit.of(panel))):toBe(0)
				expect(panel.ClipsDescendants):toBe(true)
				expect(find(panel, "AlertLayout").ClassName):toBe("Frame")
				expect(find(panel, "AlertLayout").Size):toBe(world.engine.types.UDim2.fromOffset(800, 600))
				expect(snapshot.Size):toBe(world.engine.types.UDim2.fromOffset(120, 80))
				expect((fadeKit.of(find(panel, "SourcePreview")))):toBe(0)
				world.engine.heartbeat:Fire(0.1)
				local width, height = panel.Size.X.Offset, panel.Size.Y.Offset
				expect(width > 120 and width < 800):toBe(true)
				expect(height > 80 and height < 600):toBe(true)
				expect(math.abs((width - 120) / 680 - (height - 80) / 520) < 0.0001):toBe(true)
				expect(find(panel, "AlertLayout").Size):toBe(world.engine.types.UDim2.fromOffset(800, 600))
				expect(find(panel, "AlertLayout").ClassName):toBe("Frame")
				expect(snapshot.Size):toBe(world.engine.types.UDim2.fromOffset(120, 80))
				shown:set(false)
				expect(panel.Size.X.Offset):toBe(width)
				world.engine.heartbeat:Fire(0.05)
				expect(panel.Size.X.Offset < width):toBe(true)
				local returningWidth = panel.Size.X.Offset
				shown:set(true)
				expect((find(world.screen, "AlertPanel"))):toBe(panel)
				expect(panel.Size.X.Offset):toBe(returningWidth)
				world.engine.heartbeat:Fire(0.4)
				expect(panel.Position.X.Offset):toBe(0)
				expect(panel.Position.Y.Offset):toBe(0)
				expect(panel.Size.X.Offset):toBe(800)
				expect(panel.Size.Y.Offset):toBe(600)
				expect(find(panel, "SourcePreview").Visible):toBe(false)
				expect(source.Parent):toBe(originalParent)
				shown:set(false)
				world.engine.heartbeat:Fire(0.4)
				expect((not world.engine.environment.isAlive(snapshot))):toBe(true)
				expect((find(world.screen, "AlertPanel"))):toBe(nil)
				expect(source.Parent):toBe(originalParent)
				expect((not world.engine.environment.isAlive(source))):toBe(false)
				expect(find(source, "Scene").CurrentCamera.Parent):toBe(find(source, "Scene"))
				expect((not world.engine.environment.isAlive(find(world.screen, "ExternalCamera")))):toBe(false)
				world.stop()
			end,
		})

		it("starts source expansion after the native overlay becomes visible", {
			id = "native_navigation::native navigation controls::starts source expansion after the native overlay becomes visible",
			run = function()
				local shown = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local source = Host.Frame "Card" {}
					local alertProps1: NavigationProps.AlertSpec<unknown> = {
						isPresented = shown,
						surface = "fullScreen",
						transition = { source = source :: GuiObject, seconds = 0.4 },
					}
					return Host.Frame {
						source,
						UI.Alert(alertProps1),
					}
				end, { preRender = true })
				local V2 = world.engine.types.Vector2
				local source = find(world.screen, "Card")
				world.engine.environment.poke(source, "AbsoluteSize", V2.new(120, 80))
				shown:set(true)
				local panel = find(world.screen, "AlertPanel")
				local modal = find(world.screen, "AlertModal")
				local wrapper = find(world.screen, "OverlayArrival")
				world.engine.environment.poke(modal, "AbsoluteSize", V2.new(800, 600))
				local release = require("../src/ui/text_measure").hold(find(panel, "OK"))
				for _ = 1, 8 do
					world.engine.heartbeat:Fire(0.1)
				end
				expect(fadeKit.of(wrapper)):toBe(1)
				release()
				for _, node in world.screen:GetDescendants() do
					if node:IsA("TextLabel") or node:IsA("TextButton") then
						world.engine.environment.poke(node, "TextBounds", V2.new(40, 20))
					end
				end
				for _ = 1, 20 do
					if fadeKit.of(wrapper) == 0 then
						break
					end
					world.engine.heartbeat:Fire(1 / 60)
				end
				expect(fadeKit.of(wrapper)):toBe(0)
				expect(panel.Size.X.Offset < 800):toBe(true)
				local width = panel.Size.X.Offset
				world.engine.heartbeat:Fire(0.1)
				expect(panel.Size.X.Offset > width and panel.Size.X.Offset < 800):toBe(true)
				world.engine.heartbeat:Fire(0.4)
				expect(panel.Size.X.Offset):toBe(800)
				shown:set(false)
				world.engine.heartbeat:Fire(0.1)
				expect(panel.Size.X.Offset < 800 and panel.Size.X.Offset > 120):toBe(true)
				world.engine.heartbeat:Fire(0.4)
				expect(find(world.screen, "AlertPanel")):toBe(nil)
				world.stop()
				expect(world.engine.census().connections):toBe(0)
			end,
		})

		it("makes full-screen source transitions immediate under native reduced motion", {
			id = "native_navigation::native navigation controls::makes full-screen source transitions immediate under native reduced motion",
			run = function()
				local shown = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine, gui)
					engine.environment.poke(VerifyRoblox.assertInstance(gui), "ReducedMotionEnabled", true)
					local source = UI.Button "Card" { label = "Card" }
					local alertProps1: NavigationProps.AlertSpec<unknown> = {
						isPresented = shown,
						surface = "fullScreen" :: "fullScreen",
						transition = { source = source :: GuiObject, seconds = 0.4 },
					}
					return Host.Frame {
						source,
						UI.Alert(alertProps1),
					}
				end)
				shown:set(true)
				local panel = find(world.screen, "AlertPanel")
				world.engine.environment.poke(
					find(world.screen, "AlertModal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(390, 720)
				)
				expect(panel.Size.X.Offset):toBe(390)
				expect(panel.Size.Y.Offset):toBe(720)
				expect(panel.Position.X.Offset):toBe(0)
				expect(find(panel, "AlertLayout").ClassName):toBe("Frame")
				expect(find(panel, "SourcePreview").Visible):toBe(false)
				shown:set(false)
				expect((find(world.screen, "AlertPanel"))):toBe(nil)
				world.stop()
			end,
		})

		it("resets the mounted callout showcase without replacing anchor identities", {
			id = "native_navigation::native navigation controls::resets the mounted callout showcase without replacing anchor identities",
			run = function()
				local built: any
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local current = require("../examples/gallery/scenarios/callout").build(({
						UI = UI,
						Host = Host,
						Compose = Compose,
						types = engine.types,
					} :: unknown) :: ExampleContext)
					built = current
					return current.screen()
				end)
				local anchor = find(world.screen, "Plus")
				built.steps.show()
				expect(built.report().tip.state):toBe("showing")
				find(world.screen, "Dismiss").Activated:Fire()
				expect(built.report().tip.state):toBe("retired")
				built.steps.reset()
				expect((find(world.screen, "Plus"))):toBe(anchor)
				built.steps.show()
				expect(built.report().tip.state):toBe("showing")
				world.stop()
			end,
		})
		it("keeps filtered multiple selections and reactive row descriptions through source replacement", {
			id = "native_navigation::native navigation controls::keeps filtered multiple selections and reactive row descriptions through source replacement",
			run = function()
				local selected, query, opened =
					Compose.cell({ a = true } :: { [string]: boolean }), Compose.cell(""), Compose.cell(true)
				local options = Compose.cell(
					{ { value = "a", label = "Alpha" }, { value = "b", label = "Beta", enabled = false } } :: { Navigation.PickerOption<string> }
				)
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.MultiplePickerSpecInput<string> = {
						selected = selected,
						multiple = true,
						required = true,
						style = "menu" :: "menu",
						options = options,
						query = query,
						isPresented = opened,
					}
					return (UI.Picker :: any)(controlProps)
				end)
				local first = find(find(world.screen, "MenuPanel"), "a")
				first.Activated:Fire()
				expect(selected:peek().a):toBe(true)
				query:set("missing")
				expect(selected:peek().a):toBe(true)
				options:set({
					{ value = "a", label = "Alpha", description = "Added" } :: Navigation.PickerOption<string>,
					{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
				})
				query:set("")
				local row = find(find(world.screen, "MenuPanel"), "a")
				expect(find(row, "Description").Text):toBe("Added")
				options:set({
					{ value = "a", label = "Alpha", description = "Changed" } :: Navigation.PickerOption<string>,
					{ value = "b", label = "Beta" } :: Navigation.PickerOption<string>,
				})
				expect((find(find(world.screen, "MenuPanel"), "a"))):toBe(row)
				expect(find(row, "Description").Text):toBe("Changed")
				find(find(world.screen, "MenuPanel"), "b").Activated:Fire()
				expect(selected:peek().b):toBe(true)
				expect((opened:peek())):toBe(true)
				options:set({ { value = "b", label = "Coast" } })
				expect(selected:peek().a):toBe(true)
				expect(find(world.screen, "Trigger").Text):toBe("Coast")
				world.stop()
			end,
		})
		it("forgives near-miss backdrop taps and closes only the top native modal", {
			id = "native_navigation::native navigation controls::forgives near-miss backdrop taps and closes only the top native modal",
			run = function()
				local outer, inner = Compose.cell(true), Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Sheet {
							isPresented = outer,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return UI.Button { label = "Outer" }
							end,
						},
						UI.Sheet {
							isPresented = inner,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return UI.Button { label = "Inner" }
							end,
						},
					}
				end)
				local panel = find(world.screen, "SheetPanel")
				world.engine.environment.poke(panel, "AbsolutePosition", world.engine.types.Vector2.new(100, 100))
				world.engine.environment.poke(panel, "AbsoluteSize", world.engine.types.Vector2.new(200, 200))
				local backdrop = find(world.screen, "DismissTarget")
				backdrop.Activated:Fire({ Position = world.engine.types.Vector2.new(90, 150) })
				expect((outer:peek())):toBe(true)
				inner:set(true)
				backdrop.Activated:Fire({ Position = world.engine.types.Vector2.new(50, 150) })
				expect((outer:peek())):toBe(true)
				local top
				for _, node in world.screen:GetDescendants() do
					if node.Name == "DismissTarget" and node ~= backdrop then
						top = node
					end
				end
				expect(top ~= nil):toBe(true)
				top.Activated:Fire({ Position = world.engine.types.Vector2.new(0, 0) })
				expect((inner:peek())):toBe(false)
				expect((outer:peek())):toBe(true)
				backdrop.Activated:Fire({ Position = world.engine.types.Vector2.new(50, 150) })
				expect((outer:peek())):toBe(false)
				world.stop()
			end,
		})
		it("keeps the navigation handoff out of neighbouring scroll panes", {
			id = "native_navigation::native navigation controls::keeps the navigation handoff out of neighbouring scroll panes",
			run = function()
				for _, mode in
					{ "normal", "limited", "none", "false", "custom" } :: { "custom" | "false" | "limited" | "none" | "normal" }
				do
					local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local navigationstackProps1: NavigationProps.NavigationStackSpec<unknown> = {
							path = path,
							transition = if mode == "false"
								then false :: false
								elseif mode == "custom" then { seconds = 0.2 }
								else nil,
							root = {
								content = function(): Instance
									return UI.VStack {
										UI.Button "RootAction" { label = "Root" },
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
						}
						return Host.Frame {
							UI.ScrollView "Neighbour" { UI.Button "Outside" { label = "Outside" } },
							UI.NavigationStack(navigationstackProps1),
						}
					end, { motionLevel = if mode == "none" then "none" else "normal" })
					if mode == "limited" then
						world.engine.environment.poke(
							VerifyRoblox.assertInstance(world.gui),
							"ReducedMotionEnabled",
							true
						)
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
					local function watch(panel: GuiObject)
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
					expect((assert(world.gui.SelectedObject):IsDescendantOf(detail))):toBe(true)
					local detailWatch = watch(detail)
					path:set({})
					world.settle()
					expect(world.gui.SelectedObject):toBe(original)
					path:set({ { id = "detail" } })
					world.engine.heartbeat:Fire(1 / 60)
					path:set({})
					world.settle()
					expect(world.gui.SelectedObject):toBe(original)
					original.Visible = false
					expect(world.gui.SelectedObject):toBe(find(root, "RootNext"))
					expect(outside):toBe(0)
					expect(inactive):toBe(0)
					selection:Disconnect()
					rootWatch:Disconnect()
					detailWatch:Disconnect()
					world.stop()
				end
			end,
		})

		it("slides pages with parallax and restores selection after push and pop settle", {
			id = "native_navigation::native navigation controls::slides pages with parallax and restores selection after push and pop settle",
			run = function()
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
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
					}
					return UI.NavigationStack(controlProps)
				end)
				local stack = find(world.screen, "NavigationStack")
				local root = find(stack, "@root")
				world.gui.SelectedObject = find(root, "RootAction")
				path:set({ { id = "detail" } })
				local detail = find(stack, "detail")
				expect(detail.Position.X.Scale):toBe(1)
				expect(detail.Interactable):toBe(true)
				expect(root.Interactable):toBe(false)
				expect(world.gui.SelectedObject):toBe(nil)
				local previous, elapsed = 1, 0
				while elapsed < 0.35 do
					world.engine.heartbeat:Fire(1 / 60)
					elapsed += 1 / 60
					local front, back = detail.Position.X.Scale, root.Position.X.Scale
					expect(front < previous):toBe(true)
					expect(back):toBeCloseTo(-0.3 * (1 - front), 1e-6)
					expect(root.Visible):toBe(true)
					expect(root.ClipsDescendants):toBe(true)
					expect(stack.ClipsDescendants):toBe(true)
					expect(find(root, "Page").Size):toBe(world.engine.types.UDim2.fromScale(1, 1))
					expect(find(root, "Dim").BackgroundTransparency):toBeCloseTo(1 - 0.1 * (1 - front), 1e-6)
					previous = front
				end
				expect(previous < 0.01):toBe(true)
				world.settle()
				expect(detail.Position.X.Scale):toBe(0)
				expect((assert(world.gui.SelectedObject):IsDescendantOf(detail))):toBe(true)
				expect(root.Visible):toBe(false)
				expect((find(root, "Dim"))):toBe(nil)
				expect(stack.ClipsDescendants):toBe(false)
				path:set({})
				expect(stack.ClipsDescendants):toBe(true)
				expect(detail.Position.X.Scale):toBe(0)
				expect(root.Visible):toBe(true)
				expect((not world.engine.environment.isAlive(detail))):toBe(false)
				expect(detail.Interactable):toBe(false)
				expect(root.Interactable):toBe(true)
				expect(world.gui.SelectedObject):toBe(nil)
				previous = 0
				for _ = 1, 12 do
					world.engine.heartbeat:Fire(1 / 60)
					local front = detail.Position.X.Scale
					expect(front > previous):toBe(true)
					expect(root.Position.X.Scale):toBeCloseTo(-0.3 * (1 - front), 1e-6)
					expect(not world.gui.SelectedObject or not world.gui.SelectedObject:IsDescendantOf(detail)):toBe(
						true
					)
					previous = front
				end
				world.settle()
				expect((not world.engine.environment.isAlive(detail))):toBe(true)
				expect(assert(world.gui.SelectedObject).Name):toBe("RootAction")
				expect(root.Position.X.Scale):toBe(0)
				expect(root.Visible):toBe(true)
				world.stop()
			end,
		})

		it("slides replacement paths in without reversing and preserves distinct entry owners", {
			id = "native_navigation::native navigation controls::slides replacement paths in without reversing and preserves distinct entry owners",
			run = function()
				for _, replacementDepth in { 1, 2, 3 } do
					local first: Navigation.NavigationEntry<number> = { id = "detail", value = 1 }
					local second: Navigation.NavigationEntry<number> = { id = "detail", value = 2 }
					local path = Compose.cell({ first, second })
					local bodies: { [number]: GuiObject } = {}
					local world = setup(function(UI: FacetControls)
						local spec: NavigationProps.NavigationStackSpec<number> = {
							path = path,
							root = {
								content = function()
									return UI.Text { text = "Root" }
								end,
							},
							destinations = {
								detail = {
									content = function(entry: Navigation.NavigationEntry<number>?): Instance
										local value = assert(assert(entry).value)
										local body = UI.Button { label = tostring(value) }
										bodies[value] = body
										return body
									end,
								},
							},
						}
						return UI.NavigationStack(spec)
					end)
					local outgoing = assert(bodies[2]:FindFirstAncestor("detail")) :: GuiObject
					world.gui.SelectedObject = bodies[2]
					local replacement: { Navigation.NavigationEntry<number> } = {}
					for index = 1, replacementDepth do
						table.insert(replacement, { id = "detail", value = index + 10 })
					end
					path:set(replacement)
					local incoming = assert(bodies[replacementDepth + 10]:FindFirstAncestor("detail")) :: GuiObject
					expect(incoming.Position.X.Scale):toBe(1)
					expect(outgoing.Position.X.Scale):toBe(0)
					expect(outgoing.Interactable):toBe(false)
					local previous = 1
					for _ = 1, 120 do
						world.engine.heartbeat:Fire(1 / 60)
						local position = incoming.Position.X.Scale
						expect(position >= 0 and position <= previous):toBe(true)
						if position > 0 then
							expect(world.engine.environment.isAlive(VerifyRoblox.assertInstance(outgoing))):toBe(true)
							expect(outgoing.Position.X.Scale):toBeCloseTo(-0.3 * (1 - position), 1e-6)
						end
						previous = position
					end
					expect(previous):toBe(0)
					expect(world.engine.environment.isAlive(VerifyRoblox.assertInstance(outgoing))):toBe(false)
					expect(world.gui.SelectedObject):toBe(bodies[replacementDepth + 10])
					if replacementDepth > 1 then
						local retained = bodies[replacementDepth + 9]
						local back = table.clone(replacement)
						table.remove(back)
						path:set(back)
						world.settle()
						expect(world.gui.SelectedObject):toBe(retained)
						expect(world.engine.environment.isAlive(VerifyRoblox.assertInstance(retained))):toBe(true)
					end
					world.stop()
				end
			end,
		})

		it("places a new push above an interrupted pop", {
			id = "native_navigation::native navigation controls::places a new push above an interrupted pop",
			run = function()
				for _, elapsed in { 0, 4 } do
					local path = Compose.cell({ { id = "menu" } } :: { Navigation.NavigationEntry<string> })
					local world = setup(function(UI: FacetControls)
						local controlProps: NavigationProps.NavigationStackSpec<string> = {
							path = path,
							root = {
								content = function()
									return UI.Button "HUD" { label = "Open" }
								end,
							},
							destinations = {
								menu = {
									content = function()
										return UI.Button { label = "Garage" }
									end,
								},
								garage = {
									content = function()
										return UI.Button "Equip" { label = "Equip" }
									end,
								},
							},
						}
						return UI.NavigationStack(controlProps)
					end)
					local menu = find(world.screen, "menu") :: GuiObject
					local root = find(world.screen, "@root") :: GuiObject
					world.gui.SelectedObject = menu:FindFirstChildWhichIsA("TextButton", true)
					path:set({})
					for _ = 1, elapsed do
						world.engine.heartbeat:Fire(1 / 60)
					end
					path:set({ { id = "garage" } })
					local garage = find(world.screen, "garage") :: GuiObject
					expect(garage.Position.X.Scale):toBe(1)
					expect(root.Visible):toBe(false)
					expect(menu.Interactable):toBe(false)
					for _ = 1, 8 do
						world.engine.heartbeat:Fire(1 / 60)
						expect(garage.Position.X.Scale > 0 and garage.Position.X.Scale < 1):toBe(true)
						expect(menu.Visible):toBe(true)
						expect(menu.Position.X.Scale):toBeCloseTo(-0.3 * (1 - garage.Position.X.Scale), 1e-6)
						expect(root.Visible):toBe(false)
					end
					world.settle()
					expect(world.engine.environment.isAlive(VerifyRoblox.assertInstance(menu))):toBe(false)
					expect(garage.Position.X.Scale):toBe(0)
					expect(assert(world.gui.SelectedObject).Name):toBe("Equip")
					path:set({})
					world.settle()
					expect(root.Visible):toBe(true)
					expect(assert(world.gui.SelectedObject).Name):toBe("HUD")
					world.stop()
				end
			end,
		})

		it("settles interrupted replacements and retains Back history across motion policies", {
			id = "native_navigation::native navigation controls::settles interrupted replacements and retains Back history across motion policies",
			run = function()
				for _, mode in { "normal", "limited", "none", "false", "custom" } do
					local path =
						Compose.cell({ { id = "detail", value = 1 } } :: { Navigation.NavigationEntry<number> })
					local bodies: { [number]: GuiObject } = {}
					local world = setup(function(UI: FacetControls)
						local spec: NavigationProps.NavigationStackSpec<number> = {
							path = path,
							transition = if mode == "false"
								then false
								elseif mode == "custom" then { seconds = 0.2 }
								else nil,
							root = {
								content = function()
									return UI.Text { text = "Root" }
								end,
							},
							destinations = {
								detail = {
									content = function(entry: Navigation.NavigationEntry<number>?): Instance
										local value = assert(assert(entry).value)
										local body = UI.Button { label = tostring(value) }
										bodies[value] = body
										return body
									end,
								},
							},
						}
						return UI.NavigationStack(spec)
					end, {
						motionLevel = if mode == "limited"
							then "limited"
							elseif mode == "none" then "none"
							else "normal",
					})
					world.gui.SelectedObject = bodies[1]
					local retained: Navigation.NavigationEntry<number> = { id = "detail", value = 2 }
					path:set({ retained, { id = "detail", value = 3 } })
					local retainedBody = bodies[2]
					for _ = 1, 4 do
						world.engine.heartbeat:Fire(1 / 60)
					end
					path:set({ retained })
					world.settle()
					expect(bodies[2]):toBe(retainedBody)
					expect(world.gui.SelectedObject):toBe(retainedBody)
					expect(world.engine.environment.isAlive(VerifyRoblox.assertInstance(bodies[1]))):toBe(false)
					expect(world.engine.environment.isAlive(VerifyRoblox.assertInstance(bodies[3]))):toBe(false)
					path:set({ { id = "detail", value = 4 } })
					for _ = 1, 4 do
						world.engine.heartbeat:Fire(1 / 60)
					end
					path:set({ { id = "detail", value = 5 } })
					local incoming = assert(bodies[5]:FindFirstAncestor("detail")) :: GuiObject
					local previous = incoming.Position.X.Scale
					for _ = 1, 120 do
						world.engine.heartbeat:Fire(1 / 60)
						local position = incoming.Position.X.Scale
						expect(position >= 0 and position <= previous):toBe(true)
						if mode ~= "normal" then
							expect(position):toBe(0)
						end
						previous = position
					end
					expect(previous):toBe(0)
					expect(world.gui.SelectedObject):toBe(bodies[5])
					for value = 1, 4 do
						expect(world.engine.environment.isAlive(VerifyRoblox.assertInstance(bodies[value]))):toBe(false)
					end
					path:set({})
					world.settle()
					expect(world.engine.environment.isAlive(VerifyRoblox.assertInstance(bodies[5]))):toBe(false)
					world.stop()
				end
			end,
		})

		it("keeps a stack that fills its ScreenGui unclipped while its pages move", {
			id = "native_navigation::native navigation controls::keeps a stack that fills its ScreenGui unclipped while its pages move",
			run = function()
				local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<string> })
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.NavigationStackSpec<string> = {
						path = path,
						root = {
							title = "Root",
							content = function(): Instance
								return UI.Button "RootAction" { label = "Root" }
							end,
						} :: NavigationFixtures.NavigationDestination<string>,
						destinations = {
							detail = {
								title = "Detail",
								content = function(): Instance
									return UI.Button "DetailAction" { label = "Detail" }
								end,
							} :: NavigationFixtures.NavigationDestination<string>,
						},
					}
					return UI.NavigationStack(controlProps)
				end)
				local V2 = world.engine.types.Vector2
				local stack = find(world.screen, "NavigationStack")
				world.engine.environment.poke(world.screen, "AbsoluteSize", V2.new(1280, 720))
				world.engine.environment.poke(stack, "AbsoluteSize", V2.new(1280, 720))
				path:set({ { id = "detail" } })
				expect(find(stack, "detail").Position.X.Scale):toBe(1)
				expect(stack.ClipsDescendants):toBe(false)
				world.settle()
				path:set({})
				expect(find(stack, "detail").Position.X.Scale):toBe(0)
				expect(stack.ClipsDescendants):toBe(false)
				world.settle()
				world.engine.environment.poke(stack, "AbsoluteSize", V2.new(640, 720))
				path:set({ { id = "detail" } })
				expect(stack.ClipsDescendants):toBe(true)
				world.settle()
				expect(stack.ClipsDescendants):toBe(false)
				world.stop()
			end,
		})

		it("pushes and pops without travel under reduced motion (a fade) or a false transition (none)", {
			id = "native_navigation::native navigation controls::pushes and pops without travel under reduced motion (a fade) or a false transition (none)",
			run = function()
				for _, mode in { "reduced", "false" } :: { "false" | "reduced" } do
					local path = Compose.cell({} :: { NavigationFixtures.NavigationEntry<any> })
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local controlProps: NavigationProps.NavigationStackSpec<unknown> = {
							path = path,
							transition = if mode == "false" then false :: false else nil,
							root = { title = "Root", content = Host.Frame "RootBody" {} } :: NavigationFixtures.NavigationDestination<any>,
							destinations = {
								detail = { title = "Detail", content = Host.Frame "DetailBody" {} } :: NavigationFixtures.NavigationDestination<any>,
							},
						}
						return UI.NavigationStack(controlProps)
					end)
					world.engine.environment.poke(
						VerifyRoblox.assertInstance(world.gui),
						"ReducedMotionEnabled",
						mode == "reduced"
					)
					local stack = find(world.screen, "NavigationStack")
					local root = find(stack, "@root")
					path:set({ { id = "detail" } })
					local detail = find(stack, "detail")
					expect(detail.Position.X.Scale):toBe(0)
					expect(root.Visible):toBe(false)
					expect(stack.ClipsDescendants):toBe(false)
					world.engine.heartbeat:Fire(1 / 60)
					if mode == "reduced" then
						expect(detail.Position.X.Scale):toBe(0)
						world.engine.heartbeat:Fire(0.16)
					end
					expect((engines.connections(world.engine.heartbeat))):toBe(0)
					path:set({})
					expect((not world.engine.environment.isAlive(detail))):toBe(true)
					expect(root.Visible):toBe(true)
					world.stop()
				end
			end,
		})

		it("keeps the outgoing tab visible until incoming collection rows can paint", function(_own, t)
			for _, grouped in { true, false } do
				local selection = Compose.cell("one")
				local hidden = Compose.cell(1)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView {
						selection = selection,
						placement = "none",
						retention = "top",
						tabs = {
							{
								id = "one",
								content = function()
									return Host.Frame "OneBody" {}
								end,
							},
							{
								id = "two",
								content = function(): GuiObject
									if not grouped then
										return Host.Frame "TwoBody" {
											Attributes = {
												FacetCollectionRow = true,
												FacetCollectionReady = function(use)
													return use(hidden) == 0
												end,
											} :: Shared.Attributes,
										}
									end
									return Host.CanvasGroup "TwoBody" {
										Attributes = { FacetCollectionRow = true } :: Shared.Attributes,
										GroupTransparency = hidden,
									}
								end,
							},
						},
					}
				end, { preRender = true })
				t:defer(world.stop)
				local function step()
					for _, node in world.screen:GetDescendants() do
						if node:IsA("GuiObject") then
							world.engine.environment.poke(
								node,
								"AbsoluteSize",
								world.engine.types.Vector2.new(400, 240)
							)
						end
						if node:IsA("TextLabel") or node:IsA("TextButton") then
							world.engine.environment.poke(node, "TextBounds", world.engine.types.Vector2.new(40, 20))
						end
					end
					world.engine.heartbeat:Fire(1 / 60)
				end
				for _ = 1, 30 do
					step()
				end
				local one = fadeKit.layer(find(world.screen, "OneBody"))
				selection:set("two")
				for _ = 1, 20 do
					step()
					t:expect(fadeKit.of(one)):toBe(0)
				end
				hidden:set(0)
				for _ = 1, 30 do
					step()
				end
				t:expect(find(world.screen, "OneBody")):toBe(nil)
				t:expect(fadeKit.of(fadeKit.layer(find(world.screen, "TwoBody")))):toBe(0)
			end
		end)

		it("shows the incoming tab when its collection rows have no area to paint", function(_own, t)
			local selection = Compose.cell("one")
			local world = setup(function(UI: FacetControls, Host: RobloxHost)
				return UI.TabView {
					selection = selection,
					placement = "none",
					retention = "top",
					tabs = {
						{
							id = "one",
							content = function()
								return Host.Frame "OneBody" {}
							end,
						},
						{
							id = "two",
							content = function()
								return Host.Frame "TwoBody" {
									Host.CanvasGroup "EmptyRow" {
										Attributes = {
											FacetCollectionRow = true,
											FacetCollectionReady = false,
										} :: Shared.Attributes,
										GroupTransparency = 1,
									},
								}
							end,
						},
					},
				}
			end, { preRender = true })
			t:defer(world.stop)
			local function step()
				for _, node in world.screen:GetDescendants() do
					if node:IsA("GuiObject") and node.Name ~= "EmptyRow" then
						world.engine.environment.poke(node, "AbsoluteSize", world.engine.types.Vector2.new(400, 240))
					end
					if node:IsA("TextLabel") or node:IsA("TextButton") then
						world.engine.environment.poke(node, "TextBounds", world.engine.types.Vector2.new(40, 20))
					end
				end
				world.engine.heartbeat:Fire(1 / 60)
			end
			for _ = 1, 30 do
				step()
			end
			selection:set("two")
			for _ = 1, 60 do
				step()
			end
			t:expect(find(world.screen, "OneBody")):toBe(nil)
			t:expect(fadeKit.of(fadeKit.layer(find(world.screen, "TwoBody")))):toBe(0)
		end)

		it("crossfades tab pages without blocking the incoming page and shows the first page at once", {
			id = "native_navigation::native navigation controls::crossfades tab pages without blocking the incoming page and shows the first page at once",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView {
						selection = selection,
						tabs = {
							{ id = "one", content = Host.Frame "OneBody" {} },
							{ id = "two", content = Host.Frame "TwoBody" {} },
						},
					}
				end)
				local one = fadeKit.layer(find(world.screen, "OneBody"))
				expect(one.ClassName):toBe("Frame")
				expect((fadeKit.of(one))):toBe(0)
				selection:set("two")
				local two = fadeKit.layer(find(world.screen, "TwoBody"))
				expect((fadeKit.of(two))):toBe(1)
				expect(two.Interactable):toBe(true)
				expect(one.Interactable):toBe(false)
				local previous = 1
				for _ = 1, 6 do
					world.engine.heartbeat:Fire(1 / 60)
					expect(fadeKit.of(two) < previous):toBe(true)
					expect((fadeKit.of(one))):toBeCloseTo(1 - fadeKit.of(two), 1e-6)
					expect(one.Visible):toBe(true)
					previous = fadeKit.of(two)
				end
				expect(previous > 0):toBe(true)
				for _ = 1, 7 do
					world.engine.heartbeat:Fire(1 / 60)
				end
				expect((fadeKit.of(two))):toBe(0)
				expect(one.Visible):toBe(false)
				world.engine.environment.poke(VerifyRoblox.assertInstance(world.gui), "ReducedMotionEnabled", true)
				selection:set("one")
				expect(one.Visible):toBe(true)
				play(world.engine, 0.16)
				expect((fadeKit.of(one))):toBe(0)
				expect(two.Visible):toBe(false)
				world.stop()
			end,
		})

		it("slides a sheet up over a fading scrim and releases input when its dismissal starts", {
			id = "native_navigation::native navigation controls::slides a sheet up over a fading scrim and releases input when its dismissal starts",
			run = function()
				local shown, detent = Compose.cell(false), Compose.cell("medium")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Button "Opener" { label = "Open" },
						UI.Sheet {
							isPresented = shown,
							detent = detent,
							title = "Sheet",
							content = Host.Frame {} :: Instance,
						},
					}
				end)
				world.gui.SelectedObject = find(world.screen, "Opener")
				shown:set(true)
				local panel = find(world.screen, "SheetPanel")
				local fade = find(world.screen, "ScrimFade")
				world.engine.environment.poke(
					find(world.screen, "Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(800, 720)
				)
				local hidden = panel.Position.Y.Offset
				expect(fade.Transparency.Keypoints[1].Value):toBe(1)
				world.engine.heartbeat:Fire(1 / 60)
				expect(panel.Position.Y.Offset):toBe(hidden)
				expect(fade.Transparency.Keypoints[1].Value):toBe(1)
				world.engine.heartbeat:Fire(1 / 60)
				expect(panel.Position.Y.Offset > 0):toBe(true)
				local previous = panel.Position.Y.Offset
				for _ = 1, 10 do
					world.engine.heartbeat:Fire(1 / 60)
					expect(panel.Position.Y.Offset < previous):toBe(true)
					previous = panel.Position.Y.Offset
				end
				world.settle()
				expect(panel.Position):toBe(world.engine.types.UDim2.fromScale(0.5, 1))
				expect(find(world.screen, "ScrimFade")):toBeNil()
				shown:set(false)
				local modal = find(world.screen, "Modal")
				expect(modal.Interactable):toBe(false)
				expect(assert(world.gui.SelectedObject).Name):toBe("Opener")
				world.engine.heartbeat:Fire(0.1)
				expect(panel.Position.Y.Offset > 0):toBe(true)
				expect(find(world.screen, "ScrimFade").Transparency.Keypoints[1].Value > 0):toBe(true)
				world.engine.heartbeat:Fire(0.11)
				expect((not world.engine.environment.isAlive(panel))):toBe(true)
				world.engine.environment.poke(VerifyRoblox.assertInstance(world.gui), "ReducedMotionEnabled", true)
				shown:set(true)
				panel = find(world.screen, "SheetPanel")
				world.engine.environment.poke(
					find(world.screen, "Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(800, 720)
				)
				expect(panel.Position.Y.Offset > 0):toBe(true)
				world.engine.heartbeat:Fire(1 / 600)
				world.engine.heartbeat:Fire(1 / 600)
				expect(panel.Position):toBe(world.engine.types.UDim2.fromScale(0.5, 1))
				shown:set(false)
				expect((not world.engine.environment.isAlive(panel))):toBe(false)
				expect(panel.Position):toBe(world.engine.types.UDim2.fromScale(0.5, 1))
				world.engine.heartbeat:Fire(0.16)
				expect((not world.engine.environment.isAlive(panel))):toBe(true)
				world.stop()
			end,
		})

		it("keeps alert layout fixed while its group fades and dismisses faster than it entered", {
			id = "native_navigation::native navigation controls::keeps alert layout fixed while its group fades and dismisses faster than it entered",
			run = function()
				local shown = Compose.cell(false)
				local world = setup(function(UI: FacetControls)
					local controlProps: NavigationProps.AlertSpec<unknown> = {
						isPresented = shown,
						title = "Leave?",
						actions = {
							{ id = "stay", label = "Stay", role = "cancel" :: "cancel" },
						},
					}
					return UI.Alert(controlProps)
				end)
				shown:set(true)
				local panel = find(world.screen, "AlertPanel")
				local V = world.engine.types.Vector2
				world.engine.environment.poke(panel, "AbsoluteSize", V.new(440, 176))
				local layout = find(panel, "AlertLayout")
				world.engine.environment.poke(find(panel, "AlertContent").Parent, "AbsoluteSize", V.new(300, 60))
				world.engine.heartbeat:Fire(0)
				world.engine.heartbeat:Fire(0)
				local parent, size = layout.Parent, panel.Size
				expect(panel.AbsoluteSize):toBe(V.new(440, 176))
				expect(find(panel, "PresentationPaint")):toBeNil()
				expect(layout:IsDescendantOf(panel:FindFirstChild("Fade"))):toBe(true)
				expect((fadeKit.of(panel))):toBe(1)
				world.engine.heartbeat:Fire(0.1)
				expect(panel.Size):toBe(size)
				expect(panel.AbsoluteSize):toBe(V.new(440, 176))
				expect(layout.Parent):toBe(parent)
				expect(fadeKit.of(panel) > 0 and fadeKit.of(panel) < 1):toBe(true)
				world.engine.heartbeat:Fire(0.1)
				expect(panel.Size.X.Scale):toBe(1)
				expect(panel.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.Y)
				expect((fadeKit.of(panel))):toBe(0)
				shown:set(false)
				world.engine.heartbeat:Fire(0.1)
				expect((not world.engine.environment.isAlive(panel))):toBe(false)
				expect(fadeKit.of(panel) > 0):toBe(true)
				world.engine.heartbeat:Fire(0.06)
				expect((not world.engine.environment.isAlive(panel))):toBe(true)
				world.stop()
			end,
		})

		it("grows callouts and fades help and menus at their final anchor", {
			id = "native_navigation::native navigation controls::grows callouts and fades help and menus at their final anchor",
			run = function()
				local opened = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = Host.TextButton "Anchor" {}
					local menuProps1: NavigationProps.MenuSpec<string> = {
						isPresented = opened,
						items = {
							menuCommand("Run", "Run") :: FixtureNavigationTypes.MenuItem<any>,
						},
					}
					return Host.Frame {
						anchor,
						UI.Button "Plus" { label = "+", help = "Adds one" },
						UI.Callout {
							anchor = anchor :: GuiObject,
							content = Host.TextLabel "Tip" {} :: Instance,
							onRetire = function() end,
						},
						UI.Menu(menuProps1),
					}
				end)
				local V = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsoluteSize", V.new(960, 720))
				local anchor = find(world.screen, "Anchor")
				world.engine.environment.poke(anchor, "AbsolutePosition", V.new(160, 100))
				world.engine.environment.poke(anchor, "AbsoluteSize", V.new(240, 44))
				local callout = find(world.screen, "CalloutPanel")
				world.engine.environment.poke(callout, "AbsoluteSize", V.new(280, 100))
				local scale = materialize.of(callout)
				world.engine.heartbeat:Fire(1 / 60)
				expect(scale.Scale):toBe(1)
				expect((fadeKit.of(callout))):toBe(1)
				expect(callout.Position.X.Offset):toBe(280)
				expect((near(callout.Position.Y.Offset, 152 + LIFT))):toBe(true)
				expect(callout.AnchorPoint):toBe(V.new(0.5, 0))
				world.engine.heartbeat:Fire(1 / 60)
				world.engine.heartbeat:Fire(0.075)
				expect(scale.Scale > 0.9 and scale.Scale < 1):toBe(true)
				world.engine.heartbeat:Fire(0.075)
				expect(scale.Scale):toBe(1)
				expect((fadeKit.of(callout))):toBe(0)
				local left, top = corner(callout)
				expect(left == 140 and near(top, 152 + LIFT)):toBe(true)
				local plus = find(world.screen, "Plus")
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				world.engine.environment.poke(plus, "GuiState", world.engine.types.Enum.GuiState.Hover)
				world.engine.heartbeat:Fire(0.5)
				local help = find(world.screen, "Help")
				expect(help.ClassName):toBe("Frame")
				world.engine.environment.poke(help, "AbsoluteSize", V.new(80, 30))
				local text = find(help, "HelpText")
				world.engine.environment.poke(text, "AbsolutePosition", help.AbsolutePosition + V.new(8, 6))
				world.engine.environment.poke(text, "AbsoluteSize", V.new(64, 18))
				world.engine.environment.poke(text, "TextBounds", V.new(56, 16))
				world.engine.heartbeat:Fire(1 / 60)
				world.engine.heartbeat:Fire(1 / 60)
				expect(materialize.of(help).Scale):toBe(1)
				expect(fadeKit.of(help)):toBe(1)
				local position, anchorPoint = help.Position, help.AnchorPoint
				local restOrigin = text.AbsolutePosition - help.AbsolutePosition
				local previous, intermediate = 1, 0
				for _ = 1, 12 do
					world.engine.heartbeat:Fire(1 / 60)
					local alpha = fadeKit.of(help)
					expect(alpha <= previous):toBe(true)
					expect(materialize.of(help).Scale):toBe(1)
					expect(help.Position):toBe(position)
					expect(help.AnchorPoint):toBe(anchorPoint)
					expect(text.AbsolutePosition - help.AbsolutePosition):toBe(restOrigin)
					local fade = find(help, "Fade")
					expect(text:IsDescendantOf(fade)):toBe(true)
					expect(math.abs(fade.GroupTransparency - alpha) < 1e-6):toBe(true)
					expect(text.TextTransparency):toBe(0)
					if alpha > 0 and alpha < 1 then
						intermediate += 1
					end
					previous = alpha
				end
				expect(intermediate > 0):toBe(true)
				world.settle()
				expect(materialize.of(help).Scale):toBe(1)
				expect((fadeKit.of(help))):toBe(0)
				world.engine.environment.poke(plus, "GuiState", world.engine.types.Enum.GuiState.Idle)
				world.engine.heartbeat:Fire(0.06)
				expect((not world.engine.environment.isAlive(help))):toBe(false)
				world.engine.heartbeat:Fire(0.06)
				expect((not world.engine.environment.isAlive(help))):toBe(true)
				opened:set(true)
				local menu = find(world.screen, "MenuPanel")
				local group = find(menu, "MenuGroup")
				expect((fadeKit.of(group))):toBe(1)
				expect(find(menu, "PresentationFade").Transparency.Keypoints[1].Value):toBe(1)
				expect(materialize.of(menu).Scale):toBe(1)
				world.engine.environment.poke(menu, "AbsoluteSize", V.new(220, 60))
				world.engine.heartbeat:Fire(1 / 60)
				world.engine.heartbeat:Fire(1 / 60)
				local growing = materialize.of(menu).Scale
				expect(growing):toBe(1)
				expect(fadeKit.of(group) > 0):toBe(true)
				world.settle()
				expect((fadeKit.of(group))):toBe(0)
				expect(materialize.of(menu).Scale):toBe(1)
				find(menu, "Run").Activated:Fire()
				expect(find(world.screen, "Modal").Interactable):toBe(false)
				world.engine.heartbeat:Fire(0.11)
				expect((not world.engine.environment.isAlive(menu))):toBe(true)
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
		type Use = FixtureComposeTypes.Use

		local materialize = require("./lib/materialize")
		local engineLib = require("./lib/native_engine")
		local Compose: ComposeModule = Facet.Compose

		type World = {
			engine: engineLib.Engine,
			runtime: ComposeRuntime,
			gui: any,
			input: any,
			screen: any,
			stop: () -> (),
		}

		local function setup(
			build: (Facet.Controls, RobloxHost, engineLib.Engine) -> Facet.Child,
			options: { [string]: any }?
		): World
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			gui.GuiNavigationEnabled = true
			gui.AutoSelectGuiEnabled = true
			gui.TouchControlsEnabled = true
			engine.environment.fakeOn(gui, "GetInsetArea", function()
				return engine.types.Rect.new(0, 0, 1280, 720)
			end)
			engine.environment.fakeOn(gui, "GetGuiInset", function()
				return engine.types.Vector2.zero, engine.types.Vector2.zero
			end)
			local input = engine.new("UserInputService")
			engine.environment.fakeOn(input, "GetLastInputType", function()
				return engine.types.Enum.UserInputType.Keyboard
			end)
			for _, method in { "IsKeyDown", "IsGamepadButtonDown" } do
				engine.environment.fakeOn(input, method, function()
					return false
				end)
			end
			for _, method in { "GetNavigationGamepads", "GetKeysPressed", "GetMouseButtonsPressed", "GetGamepadState" } do
				engine.environment.fakeOn(input, method, function()
					return {}
				end)
			end
			engine.environment.fakeOn(input, "IsKeyDown", function()
				return false
			end)
			local config: { [string]: any } = {
				types = engine.types,
				guiService = gui,
				services = {
					GuiService = (gui :: unknown) :: GuiService,
					UserInputService = (input :: unknown) :: UserInputService,
				},
			}
			for key, value in (options or {}) :: { [string]: any } do
				config[key] = value
			end
			local UI = Facet.controls(runtime, config :: any)
			local Host = Facet.host(runtime)
			local stop, screen: any = runtime.mount(function()
				return Host.ScreenGui { build(UI, Host, engine) }
			end, engine.new("Folder"))
			return {
				engine = engine,
				runtime = runtime,
				gui = (gui :: unknown) :: GuiService,
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

		local function mountError(build: (Facet.Controls, RobloxHost) -> Facet.Child): string?
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			gui.GuiNavigationEnabled = true
			gui.AutoSelectGuiEnabled = true
			gui.TouchControlsEnabled = true
			engine.environment.fakeOn(gui, "GetInsetArea", function()
				return engine.types.Rect.new(0, 0, 1280, 720)
			end)
			engine.environment.fakeOn(gui, "GetGuiInset", function()
				return engine.types.Vector2.zero, engine.types.Vector2.zero
			end)
			local UI = Facet.controls(
				runtime,
				{ types = engine.types, guiService = gui, services = { GuiService = gui } } :: any
			)
			local Host = Facet.host(runtime)
			local ok, message = pcall(function()
				local stop = runtime.mount(function()
					return Host.ScreenGui { build(UI, Host) }
				end, engine.new("Folder"))
				stop()
			end)
			runtime:dispose()
			return if ok then nil else tostring(message)
		end

		local function refuses(message: string, build: (Facet.Controls, RobloxHost) -> Facet.Child): boolean
			local failure = mountError(build)
			return failure ~= nil and string.find(failure, message, 1, true) ~= nil
		end

		local function V2(world: World, x: number, y: number): Vector2
			return world.engine.types.Vector2.new(x, y)
		end

		local function page(
			Host: RobloxHost,
			name: string,
			builds: { [string]: number }?,
			cleanups: { [string]: number }?
		): () -> Frame
			return function()
				if builds then
					builds[name] = (builds[name] or 0) + 1
				end
				if cleanups then
					local counts = cleanups
					Compose.cleanup(function()
						counts[name] = (counts[name] or 0) + 1
					end)
				end
				return Host.Frame(name .. "Body")({})
			end
		end

		describe("native parity navigation", function()
			it("sizes segments by fill or hug without replacing them and refuses unknown sizing", {
				id = "native_navigation::native parity navigation::sizes segments by fill or hug without replacing them and refuses unknown sizing",
				run = function()
					local sizing, selected =
						(function(value: "fill" | "hug"): FixtureComposeTypes.Value<"fill" | "hug">
							return Compose.cell(value)
						end)("fill"), Compose.cell("a")
					local world = setup(function(UI: FacetControls)
						local spec: NavigationProps.SinglePickerSpec<string> = {
							selected = selected,
							style = "segmented" :: "segmented",
							sizing = sizing,
							options = {
								{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Much longer" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}
						return UI.Picker(spec)
					end)
					local Enum = world.engine.types.Enum
					local picker = find(world.screen, "Picker")
					local layout = picker:FindFirstChildWhichIsA("UIListLayout")
					local a = find(picker, "a")
					expect(layout.HorizontalFlex):toBe(Enum.UIFlexAlignment.Fill)
					expect(a.AutomaticSize):toBe(Enum.AutomaticSize.X)
					expect(a.Size.Y.Scale):toBe(0)
					expect(a.Size.Y.Offset):toBe(44)
					sizing:set("hug")
					expect(layout.HorizontalFlex):toBe(Enum.UIFlexAlignment.None)
					expect((find(picker, "a"))):toBe(a)
					sizing:set("fill")
					expect(layout.HorizontalFlex):toBe(Enum.UIFlexAlignment.Fill)
					world.stop()
					expect((refuses("Picker.sizing must be fill or hug", function(UI: FacetControls)
						local controlProps = {
							selected = Compose.cell("a"),
							style = "segmented",
							sizing = "wide",
							options = { { value = "a", label = "A" } },
						} :: any
						local function constructor(spec: NavigationProps.SinglePickerSpec<string>): GuiObject
							return UI.Picker(spec)
						end
						return constructor(controlProps)
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
		local engineLib = require("./lib/native_engine")
		local Compose: ComposeModule = Facet.Compose
		local themes = Facet.themes

		type World = {
			engine: engineLib.Engine,
			runtime: ComposeRuntime,
			gui: any,
			input: any,
			root: any,
			now: () -> number,
			step: (number) -> (),
			stop: () -> (),
		}

		local function setup(
			build: (Facet.Controls, RobloxHost, engineLib.Engine) -> Facet.Child,
			options: { [string]: any }?
		): World
			local engine = engineLib.new(options and options.engine)
			local now = 0
			engine.clock = function()
				return now
			end
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			gui.GuiNavigationEnabled = true
			gui.AutoSelectGuiEnabled = true
			gui.TouchControlsEnabled = true
			engine.environment.fakeOn(gui, "GetInsetArea", function()
				return engine.types.Rect.new(0, 0, 1280, 720)
			end)
			engine.environment.fakeOn(gui, "GetGuiInset", function()
				return engine.types.Vector2.zero, engine.types.Vector2.zero
			end)
			local input = engine.new("UserInputService")
			engine.environment.fakeOn(input, "GetLastInputType", function()
				return engine.types.Enum.UserInputType.Keyboard
			end)
			for _, method in { "IsKeyDown", "IsGamepadButtonDown" } do
				engine.environment.fakeOn(input, method, function()
					return false
				end)
			end
			for _, method in { "GetNavigationGamepads", "GetKeysPressed", "GetMouseButtonsPressed", "GetGamepadState" } do
				engine.environment.fakeOn(input, method, function()
					return {}
				end)
			end
			engine.environment.fakeOn(input, "IsKeyDown", function()
				return false
			end)
			local root = engine.new("ScreenGui")
			local config: { [string]: any } = {
				types = engine.types,
				guiService = gui,
				services = {
					GuiService = (gui :: unknown) :: GuiService,
					UserInputService = (input :: unknown) :: UserInputService,
				},
				inputParent = root,
				motionLevel = "none",
			}
			for key, value in (options or {}) :: { [string]: any } do
				if key ~= "engine" then
					config[key] = value
				end
			end
			local UI = Facet.controls(runtime, config :: any)
			local Host = Facet.host(runtime)
			local stop = runtime.mount(function()
				return Host.Frame "Surface" {
					Size = engine.types.UDim2.fromScale(1, 1),
					build(UI, Host, engine),
				}
			end, root)
			return {
				engine = engine,
				runtime = runtime,
				gui = (gui :: unknown) :: GuiService,
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

		local function mountError(build: (Facet.Controls, RobloxHost) -> Facet.Child): string?
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			gui.GuiNavigationEnabled = true
			gui.AutoSelectGuiEnabled = true
			gui.TouchControlsEnabled = true
			engine.environment.fakeOn(gui, "GetInsetArea", function()
				return engine.types.Rect.new(0, 0, 1280, 720)
			end)
			engine.environment.fakeOn(gui, "GetGuiInset", function()
				return engine.types.Vector2.zero, engine.types.Vector2.zero
			end)
			local UI = Facet.controls(
				runtime,
				{ types = engine.types, guiService = gui, services = { GuiService = gui } } :: any
			)
			local Host = Facet.host(runtime)
			local ok, message = pcall(function()
				local stop = runtime.mount(function()
					return Host.ScreenGui { build(UI, Host) }
				end, engine.new("Folder"))
				stop()
			end)
			runtime:dispose()
			return if ok then nil else tostring(message)
		end

		local function refuses(message: string, build: (Facet.Controls, RobloxHost) -> Facet.Child): boolean
			local failure = mountError(build)
			return failure ~= nil and string.find(failure, message, 1, true) ~= nil
		end

		local function settle(world: World, root: any)
			for _ = 1, 3 do
				for _, node in root:GetDescendants() do
					if node:IsA("TextLabel") or node:IsA("TextButton") then
						local fits = node.TextFits
						world.engine.environment.poke(node, "TextFits", not fits)
						world.engine.environment.poke(node, "TextFits", fits)
					end
				end
				world.step(0.25)
			end
		end

		local function V2(world: World, x: number, y: number): Vector2
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

		describe("native parity weaker menus", function()
			it("fits an explicit segmented strip inside the width of its labelled row: one constraint, shared width", {
				id = "native_navigation::native parity weaker menus::fits an explicit segmented strip inside the width of its labelled row: one constraint, shared width",
				run = function()
					local world = setup(function(UI, Host)
						local pickerProps1: NavigationProps.SinglePickerSpec<string> = {
							label = "Handling",
							style = "segmented" :: "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "Arcade handling" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Simulation handling" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "c", label = "Drift assist" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "d", label = "Rally gravel" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}
						return Host.Frame {
							UI.Picker "Handling"(pickerProps1),
						}
					end)
					local row = find(world.root, "Handling")
					local options = find(row, "Options")

					expect(options.ClassName):toBe("ScrollingFrame")
					expect(options:FindFirstChildWhichIsA("UIListLayout", true).Wraps):toBe(false)
					local floor = options:FindFirstChild("TargetFloor")
					expect(floor.MinSize.Y):toBe(50)
					local constraints = 0
					for _, child in options:GetChildren() do
						if child.ClassName == "UISizeConstraint" then
							constraints += 1
						end
					end
					expect(constraints):toBe(1)
					world.engine.environment.poke(row, "AbsoluteSize", V2(world, 390, 100))
					expect(floor.MaxSize.X):toBe(390)
					world.engine.environment.poke(row, "AbsoluteSize", V2(world, 1280, 100))
					expect(floor.MaxSize.X):toBe(1280)
					world.stop()
				end,
			})
		end)
		describe("Segmented Picker caption geometry", function()
			it("shares one horizontal height and keeps compact touch targets", {
				id = "native_navigation::Segmented Picker caption geometry::shares one horizontal height and keeps compact touch targets",
				run = function()
					for _, touch in { false, true } do
						local world = setup(function(UI: FacetControls)
							local controlProps: NavigationProps.SinglePickerSpec<string> = {
								style = "segmented",
								controlSize = "compact",
								selected = Compose.cell("a"),
								options = { { value = "a", label = "Device" }, { value = "b", label = "Theme" } },
							}
							return UI.Picker "Mode"(controlProps)
						end)
						world.engine.environment.poke(
							world.input,
							"PreferredInput",
							if touch
								then world.engine.types.Enum.PreferredInput.Touch
								else world.engine.types.Enum.PreferredInput.KeyboardAndMouse
						)
						local picker, segment = find(world.root, "Mode"), find(world.root, "a")
						expect(picker.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
						expect(picker.Size.Y.Offset):toBe(segment.Size.Y.Offset + 6)
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
			it("paints a segmented field label only with its settled options", {
				id = "native_navigation::Segmented Picker caption geometry::paints a segmented field label only with its settled options",
				run = function()
					local world = setup(function(UI)
						local controlProps: NavigationProps.SinglePickerSpec<string> = {
							label = "Motion",
							style = "segmented",
							selected = Compose.cell("device"),
							options = { { value = "device", label = "Device" }, { value = "none", label = "None" } },
						}
						return UI.Picker "Motion"(controlProps)
					end)
					local paint = find(world.root, "Motion"):FindFirstChild("Label")
					expect(paint:FindFirstChild("FadePaint") ~= nil):toBe(true)
					local options = find(world.root, "Options")
					local function opacity(node)
						return fadeKit.of(node)
					end
					expect(opacity(paint)):toBe(opacity(options))
					expect(opacity(paint)):toBe(1)
					for _, node in options:GetDescendants() do
						if node:IsA("GuiObject") then
							world.engine.environment.poke(node, "AbsoluteSize", V2(world, 70, 44))
						end
					end
					world.engine.environment.poke(options, "AbsoluteSize", V2(world, 160, 50))
					world.step(0.05)
					expect(opacity(paint)):toBe(1)
					world.engine.environment.poke(paint, "AbsoluteSize", V2(world, 44, 16))
					world.engine.environment.poke(paint, "TextBounds", V2(world, 44, 16))
					world.step(0.1)
					expect(opacity(paint)):toBe(opacity(options))
					expect(opacity(paint)):toBe(0)
					world.stop()
				end,
			})
			it("keeps a touch segment target inside an authored 44-point format strip", {
				id = "native_navigation::Segmented Picker caption geometry::keeps a touch segment target inside an authored 44-point format strip",
				run = function()
					local world = setup(function(UI, Host, engine)
						local controlProps: NavigationProps.SinglePickerSpec<string> = {
							style = "segmented",
							selected = Compose.cell("rgb"),
							options = { { value = "rgb", label = "RGB" }, { value = "hsv", label = "HSV" } },
							Size = engine.types.UDim2.fromOffset(0, 44),
							AutomaticSize = engine.types.Enum.AutomaticSize.X,
						}
						return UI.Picker "Format"(controlProps)
					end)
					world.engine.environment.poke(
						world.input,
						"PreferredInput",
						world.engine.types.Enum.PreferredInput.Touch
					)
					local picker, segment = find(world.root, "Format"), find(world.root, "rgb")
					expect(segment.Size.Y.Offset >= 44):toBe(true)
					expect(picker:FindFirstChild("TargetFloor").MinSize.Y >= segment.Size.Y.Offset + 6):toBe(true)
					world.stop()
				end,
			})
			it("fits compact skinned segment captions when the painted font is taller", {
				id = "native_navigation::Segmented Picker caption geometry::fits compact skinned segment captions when the painted font is taller",
				run = function()
					local samples = {
						{
							package = require("../examples/themes/compact_pointer").build(themes),
							base = 12,
							painted = 13,
							chrome = 4,
						},
						{
							package = require("../examples/themes/pixel_quest").build(themes),
							base = 14,
							painted = 16,
							chrome = 16,
						},
					}
					for _, sample in samples do
						local world = setup(function(UI: FacetControls)
							local controlProps: NavigationProps.SinglePickerSpec<string> = {
								style = "segmented",
								controlSize = "compact",
								selected = Compose.cell("3"),
								options = {
									{ value = "3", label = "3" },
									{ value = "5", label = "5" },
									{ value = "10", label = "10" },
								},
							}
							return UI.Picker "Laps"(controlProps)
						end, { theme = sample.package })
						local picker = find(world.root, "Laps")
						for _, name in { "3", "5", "10" } do
							local segment = find(picker, name)
							local caption = assert(segment:FindFirstChild("Label", true))
							world.engine.environment.poke(segment, "TextBounds", V2(world, 11, sample.base))
							world.engine.environment.poke(caption, "TextBounds", V2(world, 11, sample.painted))
							expect(segment.Size.Y.Offset >= sample.painted + sample.chrome):toBe(true)
							expect(picker.Size.Y.Offset >= sample.painted + sample.chrome + 6):toBe(true)
						end
						world.stop()
					end
				end,
			})
			it("reserves the caption and both native padding edges", {
				id = "native_navigation::Segmented Picker caption geometry::reserves the caption and both native padding edges",
				run = function()
					local world = setup(function(UI)
						local controlProps: NavigationProps.SinglePickerSpec<string> = {
							style = "segmented",
							selected = Compose.cell("a"),
							options = { { value = "a", label = "Device" }, { value = "b", label = "Theme" } },
						}
						return UI.Picker "Device"(controlProps)
					end)
					local segment = find(world.root, "a")
					world.runtime.mount(function()
						return world.runtime.constructors.UIPadding {
							PaddingLeft = world.engine.types.UDim.new(0, 17),
							PaddingRight = world.engine.types.UDim.new(0, 19),
						}
					end, segment)
					local padding = segment:FindFirstChildWhichIsA("UIPadding")
					local floor = segment:FindFirstChildWhichIsA("UISizeConstraint")
					local minimum = floor.MinSize
					world.engine.environment.poke(segment, "TextBounds", V2(world, 68, 16))
					expect(segment.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.X)
					expect(padding.PaddingLeft.Offset + padding.PaddingRight.Offset):toBe(36)
					expect(floor.MinSize):toBe(minimum)
					world.stop()
				end,
			})
			it("uses logical caption height without reading its own painted height", {
				id = "native_navigation::Segmented Picker caption geometry::uses logical caption height without reading its own painted height",
				run = function()
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local pickerProps1: NavigationProps.SinglePickerSpec<string> = {
							style = "segmented",
							selected = Compose.cell("a"),
							options = { { value = "a", label = "Device" }, { value = "b", label = "Theme" } },
						}
						return Host.Frame {
							Host.UIScale { Scale = 2 },
							UI.Picker "Mode"(pickerProps1),
						}
					end, { theme = require("../examples/themes/glossy_touch").build(themes) })
					local picker, segment = find(world.root, "Mode"), find(world.root, "a")
					for _, node in picker:GetDescendants() do
						if node.Name == "LayoutUnit" then
							world.engine.environment.poke(node, "AbsoluteSize", V2(world, 200, 2))
						end
					end
					local caption = segment:FindFirstChild("Title", true)
						or segment:FindFirstChild("Label", true)
						or segment
					world.engine.environment.poke(caption, "TextBounds", V2(world, 136, 80))
					expect(picker.Size.Y.Offset):toBe(62)
					local height = picker.Size.Y.Offset
					for frame = 1, 30 do
						world.engine.environment.poke(segment, "AbsoluteSize", V2(world, 140, 80 + frame * 10))
						world.step(1 / 30)
						expect(picker.Size.Y.Offset):toBe(height)
					end
					world.stop()
				end,
			})
		end)
		describe("Segmented Picker overflow", function()
			local categories: { Navigation.PickerOption<string> } = {
				{ value = "all", label = "All" },
				{ value = "motors", label = "Motors" },
				{ value = "boosts", label = "Boosts" },
				{ value = "wheels", label = "Wheels" },
				{ value = "cosmetics", label = "Cosmetics" },
			}
			it("scrolls a strip that does not fit on one row and keeps the chosen segment in view", {
				id = "native_navigation::Segmented Picker overflow::scrolls a strip that does not fit on one row and keeps the chosen segment in view",
				run = function()
					local selected = Compose.cell("all")
					local world = setup(function(UI)
						local controlProps: NavigationProps.SinglePickerSpec<string> = {
							style = "segmented",
							selected = selected,
							options = categories,
						}
						return UI.Picker "Category"(controlProps)
					end)
					local types = world.engine.types
					local poke = world.engine.environment.poke
					local picker = find(world.root, "Category")
					local layout = picker:FindFirstChildWhichIsA("UIListLayout")
					expect(picker.ClassName):toBe("ScrollingFrame")
					expect(picker:HasTag("facet-segmented")):toBe(true)
					expect(layout.Wraps):toBe(false)
					expect(picker.ScrollingDirection):toBe(types.Enum.ScrollingDirection.X)
					expect(picker.Selectable):toBe(false)
					expect(picker.ScrollBarThickness):toBe(0)
					expect(find(picker, "cosmetics"):FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(
						types.Enum.UIFlexMode.Grow
					)
					local function place(shift: number)
						for index, option in categories do
							local segment = find(picker, option.value)
							poke(segment, "AbsolutePosition", V2(world, 3 + (index - 1) * 94 - shift, 3))
							poke(segment, "AbsoluteSize", V2(world, 90, 44))
						end
					end
					place(0)
					poke(picker, "AbsoluteSize", V2(world, 401, 50))
					poke(picker, "AbsoluteWindowSize", V2(world, 401, 50))
					poke(picker, "AbsoluteCanvasSize", V2(world, 472, 50))
					poke(layout, "AbsoluteContentSize", V2(world, 395, 44))
					expect(picker.ScrollingEnabled):toBe(false)
					expect(picker.ClipsDescendants):toBe(false)
					expect(picker.CanvasSize):toBe(types.UDim2.new(0, 401, 1, 0))
					expect(picker:GetAttribute("FacetOverflow")):toBe(nil)
					expect(picker.ScrollBarThickness):toBe(0)
					poke(layout, "AbsoluteContentSize", V2(world, 466, 44))
					expect(picker.ScrollBarThickness):toBe(2)
					expect(picker.ScrollingEnabled):toBe(true)
					expect(picker.ClipsDescendants):toBe(true)
					expect(picker.CanvasSize):toBe(types.UDim2.new(0, 472, 1, 0))
					expect(picker:GetAttribute("FacetOverflow")):toBe(true)
					expect(picker.CanvasPosition.X):toBe(0)
					selected:set("cosmetics")
					expect(picker.CanvasPosition.X):toBe(71)
					place(71)
					expect(picker.CanvasPosition.X):toBe(71)
					selected:set("all")
					expect(picker.CanvasPosition.X):toBe(0)
					place(0)
					selected:set("cosmetics")
					expect(picker.CanvasPosition.X):toBe(71)
					poke(picker, "AbsoluteWindowSize", V2(world, 600, 50))
					expect(picker.CanvasPosition.X):toBe(0)
					expect(picker.ScrollingEnabled):toBe(false)
					expect(picker.CanvasSize):toBe(types.UDim2.new(0, 600, 1, 0))
					expect(picker:GetAttribute("FacetOverflow")):toBe(nil)
					world.stop()
				end,
			})
			it("shows a scroll bar on an overflowing tab bar and hands a vertical drag to the page", {
				id = "native_navigation::Segmented Picker overflow::shows a scroll bar on an overflowing tab bar and hands a vertical drag to the page",
				run = function()
					local world = setup(function(UI)
						local tabs: { Navigation.Tab } = {}
						for _, option in categories do
							table.insert(
								tabs,
								{ id = option.value, label = option.label, content = UI.Text { text = option.label } }
							)
						end
						return UI.ScrollView "Page" {
							UI.TabView "Shop" { selection = Compose.cell("all"), tabs = tabs },
						}
					end)
					local types = world.engine.types
					local poke = world.engine.environment.poke
					local page = find(world.root, "Page")
					local bar = find(page, "Tabs")
					poke(page, "AbsoluteWindowSize", V2(world, 401, 300))
					poke(page, "AbsoluteCanvasSize", V2(world, 401, 900))
					page.CanvasPosition = V2(world, 0, 100)
					poke(bar, "AbsoluteSize", V2(world, 401, 50))
					poke(bar, "AbsoluteWindowSize", V2(world, 401, 50))
					expect(bar.ScrollBarThickness):toBe(0)
					poke(
						find(bar, "Strip"):FindFirstChildWhichIsA("UIListLayout"),
						"AbsoluteContentSize",
						V2(world, 520, 44)
					)
					expect(bar.ScrollBarThickness):toBe(2)
					local touch = {
						UserInputType = types.Enum.UserInputType.Touch,
						UserInputState = types.Enum.UserInputState.Begin,
						Position = types.Vector3.new(50, 20, 0),
					}
					bar.InputBegan:Fire(touch)
					touch.UserInputState = types.Enum.UserInputState.Change
					touch.Position = types.Vector3.new(50, 60, 0)
					world.input.InputChanged:Fire(touch)
					expect(bar.ScrollingEnabled):toBe(false)
					expect(page.ScrollingEnabled):toBe(true)
					world.input.InputEnded:Fire(touch)
					expect(bar.ScrollingEnabled):toBe(true)
					world.stop()
				end,
			})
			it("keeps hugging segments at their natural widths", {
				id = "native_navigation::Segmented Picker overflow::keeps hugging segments at their natural widths",
				run = function()
					local sizing = Compose.cell<<"fill" | "hug">>("fill")
					local world = setup(function(UI)
						local controlProps: NavigationProps.SinglePickerSpec<string> = {
							style = "segmented",
							sizing = sizing,
							selected = Compose.cell("all"),
							options = categories,
						}
						return UI.Picker "Category"(controlProps)
					end)
					local Enum = world.engine.types.Enum
					local grow = find(find(world.root, "Category"), "all"):FindFirstChildWhichIsA("UIFlexItem")
					expect(grow.FlexMode):toBe(Enum.UIFlexMode.Grow)
					sizing:set("hug")
					expect(grow.FlexMode):toBe(Enum.UIFlexMode.None)
					world.stop()
				end,
			})
			it("lets ViewThatFits show the next candidate while the strip scrolls", {
				id = "native_navigation::Segmented Picker overflow::lets ViewThatFits show the next candidate while the strip scrolls",
				run = function()
					local selected = Compose.cell("all")
					local world = setup(function(UI)
						return UI.ViewThatFits "Categories" {
							UI.Picker "Tabs" { style = "segmented", selected = selected, options = categories },
							UI.Picker "Dropdown" { style = "menu", selected = selected, options = categories },
						}
					end)
					local poke = world.engine.environment.poke
					local fits = find(world.root, "Categories")
					local tabs, menu = find(fits, "Tabs"), find(fits, "Dropdown")
					poke(fits, "AbsoluteSize", V2(world, 401, 60))
					poke(tabs, "AbsoluteSize", V2(world, 401, 50))
					poke(menu, "AbsoluteSize", V2(world, 160, 44))
					expect(tabs.Visible):toBe(true)
					expect(menu.Visible):toBe(false)
					poke(tabs, "AbsoluteWindowSize", V2(world, 401, 50))
					poke(tabs:FindFirstChildWhichIsA("UIListLayout"), "AbsoluteContentSize", V2(world, 466, 44))
					expect(tabs.Visible):toBe(false)
					expect(menu.Visible):toBe(true)
					poke(tabs, "AbsoluteWindowSize", V2(world, 600, 50))
					expect(tabs.Visible):toBe(true)
					expect(menu.Visible):toBe(false)
					world.stop()
				end,
			})
			it("marks the row of a labelled strip while its options scroll", {
				id = "native_navigation::Segmented Picker overflow::marks the row of a labelled strip while its options scroll",
				run = function()
					local world = setup(function(UI)
						local controlProps: NavigationProps.SinglePickerSpec<string> = {
							label = "Handling",
							style = "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "Arcade handling" },
								{ value = "b", label = "Simulation handling" },
								{ value = "c", label = "Drift assist" },
								{ value = "d", label = "Rally gravel" },
							},
						}
						return UI.Picker "Handling"(controlProps)
					end)
					local poke = world.engine.environment.poke
					local row = find(world.root, "Handling")
					local options = find(row, "Options")
					expect(options.ClassName):toBe("ScrollingFrame")
					expect(options:HasTag("facet-segmented")):toBe(true)
					expect(row:GetAttribute("FacetOverflow")):toBe(nil)
					local layout = options:FindFirstChildWhichIsA("UIListLayout", true)
					poke(options, "AbsoluteWindowSize", V2(world, 390, 50))
					poke(layout, "AbsoluteContentSize", V2(world, 600, 44))
					expect(options.ScrollingEnabled):toBe(true)
					expect(row:GetAttribute("FacetOverflow")):toBe(true)
					expect(options:GetAttribute("FacetOverflow")):toBe(nil)
					poke(options, "AbsoluteWindowSize", V2(world, 640, 50))
					expect(options.ScrollingEnabled):toBe(false)
					expect(row:GetAttribute("FacetOverflow")):toBe(nil)
					world.stop()
				end,
			})
			it("hands a vertical touch drag on a scrolling strip to the page around it", {
				id = "native_navigation::Segmented Picker overflow::hands a vertical touch drag on a scrolling strip to the page around it",
				run = function()
					local world = setup(function(UI)
						return UI.ScrollView "Page" {
							UI.Picker "Category" {
								style = "segmented",
								selected = Compose.cell("all"),
								options = categories,
							},
						}
					end)
					local types = world.engine.types
					local poke = world.engine.environment.poke
					local page = find(world.root, "Page")
					local strip = find(page, "Category")
					poke(page, "AbsoluteWindowSize", V2(world, 401, 300))
					poke(page, "AbsoluteCanvasSize", V2(world, 401, 900))
					page.CanvasPosition = V2(world, 0, 100)
					poke(strip, "AbsoluteWindowSize", V2(world, 401, 50))
					poke(strip:FindFirstChildWhichIsA("UIListLayout"), "AbsoluteContentSize", V2(world, 466, 44))
					expect(strip.ScrollingEnabled):toBe(true)
					local touch = {
						UserInputType = types.Enum.UserInputType.Touch,
						UserInputState = types.Enum.UserInputState.Begin,
						Position = types.Vector3.new(50, 20, 0),
					}
					strip.InputBegan:Fire(touch)
					touch.UserInputState = types.Enum.UserInputState.Change
					touch.Position = types.Vector3.new(50, 60, 0)
					world.input.InputChanged:Fire(touch)
					expect(strip.ScrollingEnabled):toBe(false)
					expect(page.ScrollingEnabled):toBe(true)
					world.input.InputEnded:Fire(touch)
					expect(strip.ScrollingEnabled):toBe(true)
					world.stop()
				end,
			})
		end)
	end)(verifyHarness)
end
