--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local fadeKit = require("./lib/fade")
	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")

	local function levelWorld(options: any?): (any, any)
		local env: any = nil
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			env = UI.environment()
			return Host.Frame "Screen" {}
		end, options)
		return w, env
	end

	local function alertWorld(options: any?): (any, any)
		local shown = Compose.cell(false)
		local w = overlay.new(function(UI: FacetControls)
			return UI.Alert {
				isPresented = shown,
				title = "Leave?",
				actions = {
					{ id = "stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
				},
			}
		end, options)
		return w, shown
	end

	verifyHarness:suite("motion levels", function()
		verifyHarness:case(
			"the stronger of the game's level and the device's wins; a game adds reduction, never removes it",
			{
				id = "native_motion_level::motion levels::the stronger of the game's level and the device's wins; a game adds reduction, never removes it",
				run = function()
					local w, env = levelWorld({ motionLevel = "none" })
					Verify.expect((env.motionLevel:peek())):toBe("none")
					w.gui.ReducedMotionEnabled = true
					Verify.expect((env.motionLevel:peek())):toBe("none")
					w.stop()
					local chosen = Compose.cell("normal")
					local w2, env2 = levelWorld({ motionLevel = chosen })
					Verify.expect((env2.motionLevel:peek())):toBe("normal")
					w2.gui.ReducedMotionEnabled = true
					Verify.expect((env2.motionLevel:peek())):toBe("limited")
					Verify.expect((env2.reducedMotion:peek())):toBe(true)
					chosen:set("none")
					Verify.expect((env2.motionLevel:peek())):toBe("none")
					w2.gui.ReducedMotionEnabled = false
					chosen:set("limited")
					Verify.expect((env2.motionLevel:peek())):toBe("limited")
					w2.stop()
				end,
			}
		)

		verifyHarness:case("an alert is whole after rest under none and cross-fades in place under normal", {
			id = "native_motion_level::motion levels::an alert is whole after rest under none and cross-fades in place under normal",
			run = function()
				local w, shown = alertWorld({ motionLevel = "none" })
				shown:set(true)
				local panel = w.find("AlertPanel")
				w.find("AlertContent").Parent.AbsoluteSize = w.Vector2.new(300, 60)
				w.advance(1 / 60, 2)
				Verify.expect((panel:FindFirstChild("PresentationContent", true))):toBeNil()
				Verify.expect((fadeKit.of(panel))):toBe(0)
				w.stop()
				local w2, shown2 = alertWorld({ motionLevel = "normal" })
				shown2:set(true)
				local panel2 = w2.find("AlertPanel")
				panel2.AbsoluteSize = w2.Vector2.new(440, 176)
				w2.find("AlertContent").Parent.AbsoluteSize = w2.Vector2.new(300, 60)
				w2.advance(1 / 60, 3)
				Verify.expect(panel2.AbsoluteSize):toBe(w2.Vector2.new(440, 176))
				Verify.expect(w2.find("PresentationPaint")):toBeNil()
				Verify.expect(w2.find("PresentationScale")):toBeNil()
				Verify.expect(fadeKit.of(panel2) > 0 and fadeKit.of(panel2) < 1):toBe(true)
				Verify.expect(w2.find("AlertContent"):IsDescendantOf(panel2:FindFirstChild("Fade"))):toBe(true)
				w2.stop()
			end,
		})
	end);
	(function(verifyHarness: Verify.Harness)
		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
		type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
		type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
		local FixtureNavigationTypes = require("../src/ui/navigation_types")

		local fadeKit = require("./lib/fade")
		local Facet = require("../src")
		local icons = require("../src/ui/icons")
		local engineLib = require("./lib/native_engine")
		local Compose: ComposeModule = Facet.Compose

		local function mount(engine: any, runtime: any, build: () -> any): (() -> (), any)
			local stop, root: any = runtime.mount(build, engine.new("ScreenGui"))
			return stop, root
		end

		verifyHarness:suite("native parity media", function()
			verifyHarness:suite("controls", function()
				local function session(build: (any, any) -> any, prepare: ((any, any) -> ())?): { [string]: any }
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
					if prepare then
						prepare(gui, input)
					end
					local UI = Facet.controls(
						runtime,
						{
							types = engine.types,
							guiService = gui,
							services = { GuiService = gui, UserInputService = input },
						} :: any
					)
					local Host = (runtime.constructors :: unknown) :: RobloxHost
					local stop, screen: any = runtime.mount(function()
						return Host.ScreenGui({ build(UI, Host) })
					end, engine.new("Folder"))
					return {
						engine = engine,
						runtime = runtime,
						gui = gui,
						input = input,
						screen = screen,
						find = function(name: string): any
							return screen:FindFirstChild(name, true)
						end,
						stop = function()
							stop()
							runtime:dispose()
						end,
					}
				end

				local function press(engine: any, node: any)
					local Enum = engine.types.Enum
					node.InputBegan:Fire({
						UserInputType = Enum.UserInputType.MouseButton1,
						KeyCode = Enum.KeyCode:FromValue(0),
					})
				end

				local function release(engine: any, node: any)
					local Enum = engine.types.Enum
					node.InputEnded:Fire({
						UserInputType = Enum.UserInputType.MouseButton1,
						KeyCode = Enum.KeyCode:FromValue(0),
					})
				end

				verifyHarness:case("adds no pop scale without pop and does not re-kick pop on held repeats", {
					id = "native_motion_level::controls::adds no pop scale without pop and does not re-kick pop on held repeats",
					run = function()
						local activations = 0
						local w = session(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({
								UI.Button "Plain" { label = "x", onActivate = function() end } :: unknown,
								UI.Button "Held" {
									label = "x",
									pop = true,
									repeatInterval = 0.1,
									onActivate = function()
										activations += 1
									end,
								},
							})
						end)
						Verify.expect((w.find("Plain"):FindFirstChild("Pop", true))):toBeNil()
						Verify.expect((w.find("Plain"):FindFirstChildWhichIsA("UIScale"))):toBeNil()
						local held = w.find("Held")
						local pop = held:FindFirstChild("Pop", true)
						Verify.expect(pop.ClassName):toBe("UIScale")
						Verify.expect(pop.Scale):toBe(1)
						press(w.engine, held)
						w.engine.heartbeat:Fire(0.4)
						Verify.expect(activations):toBe(1)
						Verify.expect(pop.Scale):toBe(1)
						w.engine.heartbeat:Fire(0.1)
						Verify.expect(activations):toBe(2)
						Verify.expect(pop.Scale):toBe(1)
						w.engine.heartbeat:Fire(0.1)
						Verify.expect(activations):toBe(3)
						Verify.expect(pop.Scale):toBe(1)
						release(w.engine, held)
						held.Activated:Fire()
						Verify.expect(activations):toBe(3)
						held.Activated:Fire()
						Verify.expect(activations):toBe(4)
						w.engine.heartbeat:Fire(0.1)
						Verify.expect(pop.Scale):toBeGreaterThan(1)
						w.stop()
					end,
				})

				verifyHarness:case("follows GuiService reduced motion for button pop, validation pulse and busy dots", {
					id = "native_motion_level::controls::follows GuiService reduced motion for button pop, validation pulse and busy dots",
					run = function()
						local function run(reduced: boolean): { [string]: any }
							local value, number = Compose.cell("2"), Compose.cell(2)
							local w = session(function(UI: FacetControls, Host: RobloxHost)
								return Host.Frame({
									UI.Button "Pop" { label = "Pop", pop = true, onActivate = function() end } :: unknown,
									UI.Button "Busy" { label = "Save", busy = true },
									UI.TextInput "Field" {
										value = value,
										numericValue = number,
										presentation = "number" :: "number",
										min = 1,
										max = 10,
									},
								})
							end, function(gui)
								gui.ReducedMotionEnabled = reduced
							end)
							local button = w.find("Pop")
							button.Activated:Fire()
							local field = w.find("Field")
							field:CaptureFocus()
							field.Text = "1.2.3"
							field:ReleaseFocus(true)
							local dot = w.find("Busy"):FindFirstChild("Dot1", true)
							local before = dot.BackgroundTransparency
							w.engine.heartbeat:Fire(0.1)
							return {
								pop = button:FindFirstChild("Pop", true).Scale,
								pulse = field:FindFirstChild("ValidationPulse", true).Scale,
								dotBefore = before,
								dotAfter = dot.BackgroundTransparency,
								invalid = field:GetAttribute("invalid"),
								w = w,
							}
						end
						local full = run(false)
						Verify.expect(full.invalid):toBe(true)
						Verify.expect(full.pop):toBeGreaterThan(1)
						Verify.expect(full.pulse):toBeLessThan(1)
						Verify.expect(full.dotBefore > 0):toBe(true)
						Verify.expect(full.dotAfter ~= full.dotBefore):toBe(true)
						full.w.gui.ReducedMotionEnabled = true
						Verify.expect(full.w.find("Pop"):FindFirstChild("Pop", true).Scale):toBe(1)
						Verify.expect(full.w.find("Field"):FindFirstChild("ValidationPulse", true).Scale):toBe(1)
						Verify.expect(full.w.find("Busy"):FindFirstChild("Dot1", true).BackgroundTransparency):toBe(0)
						full.w.stop()
						local reduced = run(true)
						Verify.expect(reduced.invalid):toBe(true)
						Verify.expect(reduced.pop):toBe(1)
						Verify.expect(reduced.pulse):toBe(1)
						Verify.expect(reduced.dotBefore):toBe(0)
						Verify.expect(reduced.dotAfter):toBe(0)
						reduced.w.gui.ReducedMotionEnabled = false
						reduced.w.find("Pop").Activated:Fire()
						reduced.w.engine.heartbeat:Fire(0.1)
						Verify.expect(reduced.w.find("Pop"):FindFirstChild("Pop", true).Scale):toBeGreaterThan(1)
						reduced.w.stop()
					end,
				})
			end)
		end)
	end)(verifyHarness)
end
