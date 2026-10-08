--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local nativeDrag = require("./lib/native_drag")

	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type ScrollingFrameConstructor = typeof(require("@repo/tools/typecheck/aliases").ScrollingFrameConstructor)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src") :: any
	local engineLib = require("./lib/native_engine")
	local Roblox = require("@lune/roblox")
	local Compose: ComposeModule = Facet.Compose
	local adaptive = Facet.adaptive

	local function signal()
		local handlers: { () -> () } = {}
		return {
			Connect = function(_, fn: () -> ())
				table.insert(handlers, fn)
				return {
					Disconnect = function()
						local index = table.find(handlers, fn)
						if index then
							table.remove(handlers, index)
						end
					end,
				}
			end,
			Fire = function(_self: any)
				for _, fn in table.clone(handlers) do
					fn()
				end
			end,
			count = function()
				return #handlers
			end,
		}
	end

	local function world(services: { [string]: any }?, options: { [string]: any }?)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		local frames = { Heartbeat = signal() }
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			userInputService = input,
			services = { GuiService = gui, UserInputService = input, RunService = frames },
		}
		for key, value in (services or {} :: { [string]: any }) do
			config.services[key] = value
		end
		for key, value in (options or {} :: { [string]: any }) do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config)
		return {
			engine = engine,
			runtime = runtime,
			UI = UI,
			gui = gui,
			input = input,
			frames = frames,
			Enum = engine.types.Enum,
			stop = function()
				runtime:dispose()
			end,
		}
	end

	local function owned(runtime: any, body: () -> ()): () -> ()
		local owner = Compose.createRootOwner(body, runtime.reactor)
		return function()
			owner.dispose()
		end
	end

	verifyHarness:suite("adaptive: pure decisions with no device names", function()
		verifyHarness:case("classifies width into compact, regular and wide at the documented breakpoints", {
			id = "native_environment::adaptive: pure decisions with no device names::classifies width into compact, regular and wide at the documented breakpoints",
			run = function()
				Verify.expect((adaptive.sizeClass(320))):toBe("compact")
				Verify.expect((adaptive.sizeClass(599))):toBe("compact")
				Verify.expect((adaptive.sizeClass(600))):toBe("regular")
				Verify.expect((adaptive.sizeClass(999))):toBe("regular")
				Verify.expect((adaptive.sizeClass(1000))):toBe("wide")
				Verify.expect(adaptive.BREAKPOINTS.regular):toBe(600)
				Verify.expect(adaptive.BREAKPOINTS.wide):toBe(1000)
				Verify.expect(adaptive.HEIGHT_BREAKPOINTS):toBe(adaptive.BREAKPOINTS)
			end,
		})
		verifyHarness:case("classifies height and orientation as shape facts", {
			id = "native_environment::adaptive: pure decisions with no device names::classifies height and orientation as shape facts",
			run = function()
				Verify.expect((adaptive.heightClass(313))):toBe("short")
				Verify.expect((adaptive.heightClass(733))):toBe("medium")
				Verify.expect((adaptive.heightClass(1080))):toBe("tall")
				Verify.expect((adaptive.heightClass(0 / 0))):toBe("short")
				Verify.expect((adaptive.orientationFor(733, 313))):toBe("landscape")
				Verify.expect((adaptive.orientationFor(313, 733))):toBe("portrait")
				Verify.expect((adaptive.orientationFor(500, 500))):toBe("square")
			end,
		})
		verifyHarness:case("chooses a stack axis from available width, not a platform name", {
			id = "native_environment::adaptive: pure decisions with no device names::chooses a stack axis from available width, not a platform name",
			run = function()
				Verify.expect((adaptive.axisFor(400, { stackAbove = 600 }))):toBe("y")
				Verify.expect((adaptive.axisFor(800, { stackAbove = 600 }))):toBe("x")
				Verify.expect((adaptive.axisFor(599))):toBe("y")
				Verify.expect((adaptive.axisFor(adaptive.DEFAULT_STACK_ABOVE))):toBe("x")
			end,
		})
		verifyHarness:case("derives a column count from a minimum cell width and gap", {
			id = "native_environment::adaptive: pure decisions with no device names::derives a column count from a minimum cell width and gap",
			run = function()
				Verify.expect((adaptive.columnsFor(300, 90, 6))):toBe(3)
				Verify.expect((adaptive.columnsFor(100, 90, 6))):toBe(1)
				Verify.expect((adaptive.columnsFor(0, 90, 6))):toBe(1)
				Verify.expect((adaptive.columnsFor(1920, 160, 8))):toBe(11)
				Verify.expect((adaptive.columnsFor(1600, 160, 8))):toBe(9)
				Verify.expect((pcall(adaptive.columnsFor, 300, 0, 6))):toBe(false)
			end,
		})
		verifyHarness:case("tolerates a nonsense width instead of producing a nonsense class", {
			id = "native_environment::adaptive: pure decisions with no device names::tolerates a nonsense width instead of producing a nonsense class",
			run = function()
				Verify.expect((adaptive.sizeClass(0 / 0))):toBe("compact")
				Verify.expect((adaptive.sizeClass(-50))):toBe("compact")
				Verify.expect((adaptive.sizeClass(nil))):toBe("compact")
			end,
		})
		verifyHarness:case("ranks compact < regular < wide", {
			id = "native_environment::adaptive: pure decisions with no device names::ranks compact < regular < wide",
			run = function()
				local order = { "compact", "regular", "wide" }
				for have, value in order do
					for need, target in order do
						Verify.expect((adaptive.sizeClassAtLeast(value, target))):toBe(have >= need)
					end
				end
				Verify.expect((pcall(adaptive.sizeClassAtLeast, "huge", "wide"))):toBe(false)
			end,
		})
		verifyHarness:case("homes app navigation by viewing distance, then shape, then primary input", {
			id = "native_environment::adaptive: pure decisions with no device names::homes app navigation by viewing distance, then shape, then primary input",
			run = function()
				local function home(size: string, height: string, primary: string?, extra: { [string]: any }?): string
					local facts: { [string]: any } = { sizeClass = size, heightClass = height, primary = primary }
					for key, value in (extra or {} :: { [string]: any }) do
						facts[key] = value
					end
					return adaptive.navPlacement(facts)
				end
				Verify.expect((home("compact", "short", "pointer", { tenFoot = true }))):toBe("topBar")
				Verify.expect((home("compact", "medium", "touch"))):toBe("bottomBar")
				Verify.expect((home("compact", "tall", "gamepad"))):toBe("bottomBar")
				Verify.expect((home("wide", "short", "touch"))):toBe("bottomBarCompact")
				Verify.expect((home("regular", "medium", "pointer"))):toBe("sidebar")
				Verify.expect((home("wide", "tall", "pointer"))):toBe("sidebar")
				Verify.expect((home("regular", "medium", "touch"))):toBe("topBar")
				Verify.expect((home("wide", "medium", "gamepad", { displaySize = "Medium" }))):toBe("topBar")
				Verify.expect((home("wide", "medium", "gamepad", { displaySize = "Small" }))):toBe("bottomBar")
				Verify.expect((home("wide", "medium", nil))):toBe("topBar")
			end,
		})
		verifyHarness:case("treats a large display as ten-foot only without touch or a mouse", {
			id = "native_environment::adaptive: pure decisions with no device names::treats a large display as ten-foot only without touch or a mouse",
			run = function()
				Verify.expect((adaptive.isTenFoot({ displaySize = "Large" }))):toBe(true)
				Verify.expect((adaptive.isTenFoot({ displaySize = "Large", mouse = true }))):toBe(false)
				Verify.expect((adaptive.isTenFoot({ displaySize = "Large", touch = true }))):toBe(false)
				Verify.expect((adaptive.isTenFoot({ displaySize = "Medium" }))):toBe(false)
				Verify.expect((adaptive.isTenFoot({ displaySize = "Medium", tenFootInterface = true }))):toBe(true)
				Verify.expect((adaptive.isTenFoot({ displaySize = "Large", tenFootInterface = true, mouse = true })))
					:toBe(false)
			end,
		})
	end)

	verifyHarness:suite("environment: reactive facts from engine sources", function()
		verifyHarness:case("exposes the size class and its boolean tests as readables that follow the viewport", {
			id = "native_environment::environment: reactive facts from engine sources::exposes the size class and its boolean tests as readables that follow the viewport",
			run = function()
				local w = world()
				local screen = w.engine.new("ScreenGui")
				screen.AbsoluteSize = Roblox.Vector2.new(390, 844)
				local env: any
				local reads = 0
				local stop = owned(w.runtime, function()
					env = w.UI.environment(screen)
					Compose.watch(function(use: Use)
						use(env.sizeClass)
						reads += 1
					end)
				end)
				Verify.expect((env.sizeClass:peek())):toBe("compact")
				Verify.expect((env.isCompact:peek())):toBe(true)
				Verify.expect((env.isRegularOrWider:peek())):toBe(false)
				Verify.expect((env.orientation:peek())):toBe("portrait")
				Verify.expect((env.isLandscape:peek())):toBe(false)
				Verify.expect((env.heightClass:peek())):toBe("medium")
				Verify.expect((env.axis:peek())):toBe("y")
				screen.AbsoluteSize = Roblox.Vector2.new(1280, 720)
				Verify.expect((env.viewportWidth:peek())):toBe(1280)
				Verify.expect((env.sizeClass:peek())):toBe("wide")
				Verify.expect((env.isWide:peek())):toBe(true)
				Verify.expect((env.isRegular:peek())):toBe(false)
				Verify.expect((env.isRegularOrWider:peek())):toBe(true)
				Verify.expect((env.atLeast("regular"):peek())):toBe(true)
				Verify.expect((env.orientation:peek())):toBe("landscape")
				Verify.expect((env.axis:peek())):toBe("x")
				local before = reads
				screen.AbsoluteSize = Roblox.Vector2.new(1300, 700)
				Verify.expect(reads):toBe(before)
				Verify.expect((pcall(env.atLeast, "huge"))):toBe(false)
				stop()
				w.stop()
			end,
		})
		verifyHarness:case("refuses the engine's placeholder viewport and keeps the last real fact", {
			id = "native_environment::environment: reactive facts from engine sources::refuses the engine's placeholder viewport and keeps the last real fact",
			run = function()
				local w = world()
				local camera = w.engine.new("Camera")
				camera.ViewportSize = Roblox.Vector2.new(800, 600)
				local env: any
				local stop = owned(w.runtime, function()
					env = w.UI.environment(camera)
				end)
				Verify.expect((env.sizeClass:peek())):toBe("regular")
				camera.ViewportSize = Roblox.Vector2.new(1, 1)
				Verify.expect((env.viewportWidth:peek())):toBe(800)
				Verify.expect((env.sizeClass:peek())):toBe("regular")
				camera.ViewportSize = Roblox.Vector2.new(1920, 1080)
				Verify.expect((env.sizeClass:peek())):toBe("wide")
				Verify.expect((env.isTall:peek())):toBe(true)
				stop()
				w.stop()
			end,
		})
		verifyHarness:case("reads the workspace camera when no source is given", {
			id = "native_environment::environment: reactive facts from engine sources::reads the workspace camera when no source is given",
			run = function()
				local camera = { ViewportSize = Roblox.Vector2.new(500, 900) }
				local w = world({ Workspace = { CurrentCamera = nil } })
				local fake = w.engine.new("Camera")
				fake.ViewportSize = camera.ViewportSize
				w.UI = Facet.controls(w.runtime, {
					types = w.engine.types,
					guiService = w.gui,
					userInputService = w.input,
					services = { GuiService = w.gui, UserInputService = w.input, Workspace = { CurrentCamera = fake } },
				})
				local env: any
				local stop = owned(w.runtime, function()
					env = w.UI.environment()
				end)
				Verify.expect((env.viewportSize:peek())):toBe(camera.ViewportSize)
				Verify.expect((env.isShort:peek())):toBe(false)
				Verify.expect((env.orientation:peek())):toBe("portrait")
				stop()
				w.stop()
			end,
		})
		verifyHarness:case("derives interaction classes from preferred input and live capabilities", {
			id = "native_environment::environment: reactive facts from engine sources::derives interaction classes from preferred input and live capabilities",
			run = function()
				local w = world()
				local E = w.Enum
				w.input.MouseEnabled = true
				w.input.KeyboardEnabled = true
				w.input.TouchEnabled = false
				w.input.GamepadEnabled = false
				w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				local env: any
				local stop = owned(w.runtime, function()
					env = w.UI.environment(w.engine.new("ScreenGui"))
				end)
				local classes = env.interactionClasses:peek()
				Verify.expect(classes.primary):toBe("pointer")
				Verify.expect(classes.pointer):toBe(true)
				Verify.expect(classes.keyboard):toBe(true)
				Verify.expect(classes.gamepad):toBe(false)
				Verify.expect((env.effectiveInput:peek())):toBe("KeyboardAndMouse")
				w.input.GamepadEnabled = true
				Verify.expect(env.interactionClasses:peek().gamepad):toBe(true)
				Verify.expect(env.interactionClasses:peek().primary):toBe("pointer")
				w.input.PreferredInput = E.PreferredInput.Gamepad
				Verify.expect(env.interactionClasses:peek().primary):toBe("gamepad")
				Verify.expect((env.effectiveInput:peek())):toBe("Gamepad")
				w.input.GamepadEnabled = false
				Verify.expect(env.interactionClasses:peek().gamepad):toBe(true)
				w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				w.input.MouseEnabled = false
				w.input.TouchEnabled = true
				Verify.expect(env.interactionClasses:peek().primary):toBe("touch")
				Verify.expect((env.effectiveInput:peek())):toBe("Touch")
				stop()
				w.stop()
			end,
		})
		verifyHarness:case("publishes safe insets, display size, preferred text size and reduced motion", {
			id = "native_environment::environment: reactive facts from engine sources::publishes safe insets, display size, preferred text size and reduced motion",
			run = function()
				local w = world()
				local E = w.Enum
				local topLeft, bottomRight = Roblox.Vector2.new(0, 58), Roblox.Vector2.new(0, 0)
				w.gui.GetGuiInset = function()
					return topLeft, bottomRight
				end
				local screen = w.engine.new("ScreenGui")
				screen.AbsoluteSize = Roblox.Vector2.new(844, 390)
				local env: any
				local stop = owned(w.runtime, function()
					env = w.UI.environment(screen)
				end)
				local insets = env.safeInsets:peek()
				Verify.expect(insets.top):toBe(58)
				Verify.expect(insets.left):toBe(0)
				topLeft, bottomRight = Roblox.Vector2.new(47, 0), Roblox.Vector2.new(47, 21)
				screen.AbsoluteSize = Roblox.Vector2.new(852, 393)
				insets = env.safeInsets:peek()
				Verify.expect(insets.left):toBe(47)
				Verify.expect(insets.right):toBe(47)
				Verify.expect(insets.bottom):toBe(21)
				Verify.expect(insets.top):toBe(0)
				Verify.expect((env.displaySize:peek())):toBe("Medium")
				Verify.expect((env.isTenFoot:peek())):toBe(false)
				Verify.expect((env.navPlacement:peek())):toBe("bottomBarCompact")
				w.gui.ViewportDisplaySize = E.DisplaySize.Large
				w.input.MouseEnabled = false
				w.input.GamepadEnabled = true
				w.input.PreferredInput = E.PreferredInput.Gamepad
				Verify.expect((env.isTenFoot:peek())):toBe(true)
				Verify.expect((env.navPlacement:peek())):toBe("topBar")
				screen.AbsoluteSize = Roblox.Vector2.new(1920, 1080)
				Verify.expect((env.sizeClass:peek())):toBe("regular")
				Verify.expect((env.heightClass:peek())):toBe("medium")
				w.input.MouseEnabled = true
				Verify.expect((env.isTenFoot:peek())):toBe(false)
				Verify.expect((env.sizeClass:peek())):toBe("wide")
				Verify.expect((env.heightClass:peek())):toBe("tall")
				Verify.expect((env.preferredTextSize:peek())):toBe("Medium")
				w.gui.PreferredTextSize = E.PreferredTextSize.Largest
				Verify.expect((env.preferredTextSize:peek())):toBe("Largest")
				Verify.expect((env.reducedMotion:peek())):toBe(false)
				w.gui.ReducedMotionEnabled = true
				Verify.expect((env.reducedMotion:peek())):toBe(true)
				stop()
				w.stop()
			end,
		})
		verifyHarness:case("requires an owner and stops observing when the owner ends", {
			id = "native_environment::environment: reactive facts from engine sources::requires an owner and stops observing when the owner ends",
			run = function()
				local w = world()
				Verify.expect((pcall(w.UI.environment))):toBe(false)
				local screen = w.engine.new("ScreenGui")
				screen.AbsoluteSize = Roblox.Vector2.new(400, 800)
				local env: any
				local stop = owned(w.runtime, function()
					env = w.UI.environment(screen)
				end)
				stop()
				screen.AbsoluteSize = Roblox.Vector2.new(1400, 800)
				Verify.expect((pcall(function()
					return env.viewportWidth:peek()
				end))):toBe(false)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("environment: viewing distance, metric scale and overscan", function()
		local function console(options: { [string]: any }?, touch: boolean?): (any, any, any, any)
			local w = world(nil, options)
			local E = w.Enum
			w.gui.ViewportDisplaySize = E.DisplaySize.Large
			w.input.MouseEnabled = false
			w.input.TouchEnabled = touch == true
			w.input.GamepadEnabled = true
			w.input.PreferredInput = E.PreferredInput.Gamepad
			local screen = w.engine.new("ScreenGui")
			screen.AbsoluteSize = Roblox.Vector2.new(1920, 1080)
			local env: any
			local stop = owned(w.runtime, function()
				env = w.UI.environment(screen)
			end)
			return w, env, function()
				stop()
				w.stop()
			end, screen
		end
		verifyHarness:case(
			"a console-shaped display is ten-foot at 1.5x with the console overscan; a touch handheld is near",
			{
				id = "native_environment::environment: viewing distance, metric scale and overscan::a console-shaped display is ten-foot at 1.5x with the console overscan; a touch handheld is near",
				run = function()
					local _, env, stop = console()
					Verify.expect((env.isTenFoot:peek())):toBe(true)
					Verify.expect((env.metricScale:peek())):toBe(1.5)
					Verify.expect((env.overscanInsets:peek())):toEqual({ top = 60, left = 90, bottom = 60, right = 90 })
					Verify.expect((env.viewingDistanceSource:peek())):toBe("inferred")
					Verify.expect((env.sizeClass:peek())):toBe("regular")
					stop()
					local _, handheld, stopHandheld = console(nil, true)
					Verify.expect((handheld.isTenFoot:peek())):toBe(false)
					Verify.expect((handheld.metricScale:peek())):toBe(1)
					Verify.expect((handheld.overscanInsets:peek()))
						:toEqual({ top = 0, left = 0, bottom = 0, right = 0 })
					Verify.expect((handheld.sizeClass:peek())):toBe("wide")
					stopHandheld()
				end,
			}
		)
		verifyHarness:case("overscan is a proportion of the viewport; authored margins win and none opts out", {
			id = "native_environment::environment: viewing distance, metric scale and overscan::overscan is a proportion of the viewport; authored margins win and none opts out",
			run = function()
				local authored = Compose.cell(nil :: any)
				local _, env, stop, screen = console({ environment = { overscanInsets = authored } })
				screen.AbsoluteSize = Roblox.Vector2.new(1280, 720)
				Verify.expect((env.overscanInsets:peek())):toEqual({ top = 40, left = 60, bottom = 40, right = 60 })
				authored:set({ top = 10, left = 20, bottom = 10, right = 20 })
				Verify.expect((env.overscanInsets:peek())):toEqual({ top = 10, left = 20, bottom = 10, right = 20 })
				authored:set("none")
				Verify.expect((env.overscanInsets:peek())):toEqual({ top = 0, left = 0, bottom = 0, right = 0 })
				stop()
			end,
		})
		verifyHarness:case("an authored viewingDistance outranks the inference and says so", {
			id = "native_environment::environment: viewing distance, metric scale and overscan::an authored viewingDistance outranks the inference and says so",
			run = function()
				local distance = Compose.cell("automatic")
				local w, env, stop = console({ environment = { viewingDistance = distance } })
				distance:set("near")
				Verify.expect((env.isTenFoot:peek())):toBe(false)
				Verify.expect((env.metricScale:peek())):toBe(1)
				Verify.expect((env.viewingDistanceSource:peek())):toBe("authored")
				Verify.expect(env.overscanInsets:peek().left):toBe(0)
				distance:set("ten-foot")
				w.input.MouseEnabled = true
				w.gui.ViewportDisplaySize = w.Enum.DisplaySize.Medium
				Verify.expect((env.isTenFoot:peek())):toBe(true)
				Verify.expect((env.metricScale:peek())):toBe(1.5)
				Verify.expect((env.navPlacement:peek())):toBe("topBar")
				distance:set("automatic")
				Verify.expect((env.isTenFoot:peek())):toBe(false)
				Verify.expect((env.viewingDistanceSource:peek())):toBe("inferred")
				distance:set("far")
				Verify.expect((pcall(function()
					return env.isTenFoot:peek()
				end))):toBe(false)
				stop()
				Verify.expect(
					(pcall(Facet.controls, w.runtime, { types = w.engine.types, environment = { distance = "near" } }))
				)
					:toBe(false)
			end,
		})
	end)

	local function fixture()
		local scene: any = {}
		local camera: any = { NearPlaneZ = -0.5, ViewportSize = Roblox.Vector2.new(800, 600) }
		function camera.WorldToViewportPoint(_, p)
			return { X = 400 + p.X * 100 / -p.Z, Y = 300 - p.Y * 100 / -p.Z, Z = -p.Z }
		end
		scene.CurrentCamera = camera
		local part: any = { CFrame = Roblox.CFrame.new(0, 0, -10), Size = Roblox.Vector3.new(4, 2, 2), live = true }
		function part.IsA(_, name)
			return name == "BasePart"
		end
		function part.IsDescendantOf(self, root)
			return root == scene and self.live
		end
		local w = world({ Workspace = scene })
		return w, scene, part
	end

	verifyHarness:suite("worldAnchor: proximity anchors around world objects", function()
		verifyHarness:case("retains offscreen directions for markers and can suppress occluded targets", {
			id = "native_environment::worldAnchor: proximity anchors around world objects::retains offscreen directions for markers and can suppress occluded targets",
			run = function()
				local w, scene, part = fixture()
				local hit: any = nil
				scene.CurrentCamera.CFrame = Roblox.CFrame.new()
				function scene.Raycast()
					return hit
				end
				part.CFrame = Roblox.CFrame.new(100, 0, -10)
				local binding = w.UI.worldAnchor({ target = part, offscreen = "retain", occlusion = true })
				Verify.expect(binding.anchor:peek().visible):toBe(true)
				Verify.expect(binding.anchor:peek().onscreen):toBe(false)
				Verify.expect(binding.anchor:peek().x > 800):toBe(true)
				part.CFrame = Roblox.CFrame.new(100, 0, 10)
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().x > 400):toBe(true)
				hit = {
					Instance = {
						IsDescendantOf = function()
							return false
						end,
					},
				}
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().visible):toBe(false)
				Verify.expect(binding.anchor:peek().occluded):toBe(true)
				hit = { Instance = part }
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().visible):toBe(true)
				binding.dispose()
				w.stop()
			end,
		})
		verifyHarness:case("encloses projected corners with padding and updates on the frame", {
			id = "native_environment::worldAnchor: proximity anchors around world objects::encloses projected corners with padding and updates on the frame",
			run = function()
				local w, _, part = fixture()
				local binding = w.UI.worldAnchor({ target = part, padding = 0.15 })
				local a = binding.anchor:peek()
				Verify.expect(a.visible):toBe(true)
				Verify.expect(a.x):toBe(400)
				Verify.expect(a.y):toBe(300)
				Verify.expect(math.abs(a.clearance - (math.sqrt(20 * 20 + 10 * 10) / 0.9 * 1.15)) < 0.001):toBe(true)
				part.CFrame = Roblox.CFrame.new(2, 0, -5) * Roblox.CFrame.Angles(0, 0.5, 0.3)
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().x > a.x):toBe(true)
				Verify.expect(binding.anchor:peek().clearance > a.clearance):toBe(true)
				binding.dispose()
				w.stop()
			end,
		})
		verifyHarness:case("uses relative padding at every distance and defaults to fifteen percent", {
			id = "native_environment::worldAnchor: proximity anchors around world objects::uses relative padding at every distance and defaults to fifteen percent",
			run = function()
				for _, padding in { false, 0, 0.15, 0.5, 1 } :: { false | number } do
					local w, _, part = fixture()
					local options: any = { target = part }
					if padding ~= false then
						options.padding = padding
					end
					local binding = w.UI.worldAnchor(options)
					for _, distance in { 5, 10, 20 } do
						part.CFrame = Roblox.CFrame.new(0, 0, -distance)
						w.frames.Heartbeat:Fire()
						local radius = math.sqrt(200 ^ 2 + 100 ^ 2) / (distance - 1)
						local fraction = if type(padding) == "number" then padding else 0.15
						Verify.expect(math.abs(binding.anchor:peek().clearance / radius - (1 + fraction)) < 0.00001)
							:toBe(true)
					end
					binding.dispose()
					w.stop()
				end
			end,
		})
		verifyHarness:case("tracks models, avatar respawns, camera replacement and unavailable targets", {
			id = "native_environment::worldAnchor: proximity anchors around world objects::tracks models, avatar respawns, camera replacement and unavailable targets",
			run = function()
				local w, scene, part = fixture()
				local model: any = { live = true }
				function model.IsA(_, name)
					return name == "Model"
				end
				function model.IsDescendantOf(self, root)
					return self.live and root == scene
				end
				function model.FindFirstChildWhichIsA()
					return part
				end
				function model.GetBoundingBox()
					return part.CFrame, part.Size
				end
				local player: any = { Character = model }
				function player.IsA(_, name)
					return name == "Player"
				end
				local target = Compose.cell(player)
				local binding = w.UI.worldAnchor({ target = target })
				Verify.expect(binding.anchor:peek().clearance > 0):toBe(true)
				player.Character = nil
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().visible):toBe(false)
				player.Character = model
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().visible):toBe(true)
				target:set(nil)
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().visible):toBe(false)
				target:set(player)
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().visible):toBe(true)
				scene.CurrentCamera = nil
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().visible):toBe(false)
				binding.dispose()
				binding.dispose()
				Verify.expect((w.frames.Heartbeat.count())):toBe(0)
				w.stop()
			end,
		})
		verifyHarness:case("rejects near-plane intersections and offscreen or removed objects", {
			id = "native_environment::worldAnchor: proximity anchors around world objects::rejects near-plane intersections and offscreen or removed objects",
			run = function()
				local w, _, part = fixture()
				local binding = w.UI.worldAnchor({ target = part })
				for _, frame in
					{ Roblox.CFrame.new(0, 0, -1), Roblox.CFrame.new(0, 0, 10), Roblox.CFrame.new(100, 0, -10) }
				do
					part.CFrame = frame
					w.frames.Heartbeat:Fire()
					Verify.expect(binding.anchor:peek().visible):toBe(false)
				end
				part.CFrame = Roblox.CFrame.new(0, 0, -10)
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().visible):toBe(true)
				part.live = false
				w.frames.Heartbeat:Fire()
				Verify.expect(binding.anchor:peek().visible):toBe(false)
				binding.dispose()
				w.stop()
			end,
		})
		verifyHarness:case("validates options before allocating a frame hook", {
			id = "native_environment::worldAnchor: proximity anchors around world objects::validates options before allocating a frame hook",
			run = function()
				local w, _, part = fixture()
				for _, options in
					{
						{ target = part, paddding = 1 },
						{ target = part, padding = -1 },
						{ target = part, padding = 1.01 },
						{ target = part, padding = math.huge },
						{ target = part, minimumRadius = 70 },
						{ target = part, offscreen = "keep" },
						{ padding = 0.2 },
					} :: { any }
				do
					Verify.expect((pcall(w.UI.worldAnchor, options))):toBe(false)
				end
				Verify.expect((w.frames.Heartbeat.count())):toBe(0)
				w.stop()
			end,
		})
		verifyHarness:case("feeds a RadialMenu anchor and releases with its owner", {
			id = "native_environment::worldAnchor: proximity anchors around world objects::feeds a RadialMenu anchor and releases with its owner",
			run = function()
				local w, _, part = fixture()
				local binding: any
				local stop = owned(w.runtime, function()
					binding = w.UI.worldAnchor({ target = part })
				end)
				Verify.expect((w.frames.Heartbeat.count())):toBe(1)
				Verify.expect(binding.anchor:peek().visible):toBe(true)
				stop()
				Verify.expect((w.frames.Heartbeat.count())):toBe(0)
				Verify.expect(binding.anchor:peek().visible):toBe(false)
				w.stop()
			end,
		})
	end)

	local function scroller(w: any, name: string, window: Vector2, canvas: Vector2, at: Vector2?): any
		local frame = w.engine.new("ScrollingFrame")
		frame.Name = name
		frame.AbsolutePosition = at or Roblox.Vector2.zero
		frame.AbsoluteWindowSize = window
		frame.AbsoluteCanvasSize = canvas
		return frame
	end

	local function box(w: any, parent: any, position: Vector2, size: Vector2): any
		local node = w.engine.new("Frame")
		node.AbsolutePosition = position
		node.AbsoluteSize = size
		node.Parent = parent
		return node
	end

	verifyHarness:suite("scrollTo and scrollToVisible over native ScrollingFrame", function()
		verifyHarness:case("writes a programmatic position and the canvas limits clamp it", {
			id = "native_environment::scrollTo and scrollToVisible over native ScrollingFrame::writes a programmatic position and the canvas limits clamp it",
			run = function()
				local w = world(nil, { motionLevel = "none" })
				local frame = scroller(w, "List", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(200, 1000))
				Verify.expect((w.UI.scrollTo(frame, Roblox.Vector2.new(0, 250)))):toBe(true)
				Verify.expect(frame.CanvasPosition):toBe(Roblox.Vector2.new(0, 250))
				Verify.expect((w.UI.scrollTo(frame, { y = 5000 }))):toBe(true)
				Verify.expect(frame.CanvasPosition.Y):toBe(900)
				Verify.expect((w.UI.scrollTo(frame, "bottom"))):toBe(false)
				Verify.expect((w.UI.scrollTo(frame, "top"))):toBe(true)
				Verify.expect(frame.CanvasPosition):toBe(Roblox.Vector2.zero)
				Verify.expect((w.UI.scrollTo(frame, { y = -40 }))):toBe(false)
				Verify.expect((pcall(w.UI.scrollTo, w.engine.new("Frame"), "top"))):toBe(false)
				Verify.expect((pcall(w.UI.scrollTo, frame, "middle"))):toBe(false)
				w.stop()
			end,
		})
		verifyHarness:case("animates through TweenService and moves at once under reduced motion", {
			id = "native_environment::scrollTo and scrollToVisible over native ScrollingFrame::animates through TweenService and moves at once under reduced motion",
			run = function()
				local created = {}
				local tweens = {
					Create = function(_, instance: any, info: TweenInfo, goal: { [string]: any })
						local record = { instance = instance, info = info, goal = goal, played = 0, cancelled = 0 }
						function record.Play()
							record.played += 1
						end
						function record.Cancel()
							record.cancelled += 1
						end
						table.insert(created, record)
						return record
					end,
				}
				local w = world({ TweenService = tweens })
				local frame = scroller(w, "List", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(200, 1000))
				Verify.expect((w.UI.scrollTo(frame, { y = 300 }))):toBe(true)
				Verify.expect(#created):toBe(1)
				Verify.expect(created[1].played):toBe(1)
				Verify.expect(created[1].goal.CanvasPosition):toBe(Roblox.Vector2.new(0, 300))
				Verify.expect(frame.CanvasPosition):toBe(Roblox.Vector2.zero)
				Verify.expect((w.UI.scrollTo(frame, { y = 600 }))):toBe(true)
				Verify.expect(created[1].cancelled):toBe(1)
				Verify.expect((w.UI.scrollTo(frame, { y = 700 }, { animated = false }))):toBe(true)
				Verify.expect(created[2].cancelled):toBe(1)
				Verify.expect(frame.CanvasPosition.Y):toBe(700)
				w.gui.ReducedMotionEnabled = true
				Verify.expect((w.UI.scrollTo(frame, "top"))):toBe(true)
				Verify.expect(#created):toBe(2)
				Verify.expect(frame.CanvasPosition.Y):toBe(0)
				w.stop()
			end,
		})
		verifyHarness:case("moves both axes of an xy host to bring a node beyond both edges into view", {
			id = "native_environment::scrollTo and scrollToVisible over native ScrollingFrame::moves both axes of an xy host to bring a node beyond both edges into view",
			run = function()
				local w = world(nil, { motionLevel = "none" })
				local frame = scroller(w, "Board", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(1000, 1000))
				frame.ScrollingDirection = w.engine.types.Enum.ScrollingDirection.XY
				local far = box(w, frame, Roblox.Vector2.new(260, 150), Roblox.Vector2.new(40, 30))
				Verify.expect((w.UI.scrollToVisible(far))):toBe(true)
				Verify.expect(frame.CanvasPosition):toBe(Roblox.Vector2.new(100, 80))
				w.stop()
			end,
		})
		verifyHarness:case("scrolls the minimum distance to bring a node below or above the viewport into view", {
			id = "native_environment::scrollTo and scrollToVisible over native ScrollingFrame::scrolls the minimum distance to bring a node below or above the viewport into view",
			run = function()
				local w = world(nil, { motionLevel = "none" })
				local frame = scroller(w, "List", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(200, 1000))
				local below = box(w, frame, Roblox.Vector2.new(0, 150), Roblox.Vector2.new(200, 30))
				Verify.expect((w.UI.scrollToVisible(below))):toBe(true)
				Verify.expect(frame.CanvasPosition.Y):toBe(80)
				frame.CanvasPosition = Roblox.Vector2.new(0, 400)
				local above = box(w, frame, Roblox.Vector2.new(0, -60), Roblox.Vector2.new(200, 30))
				Verify.expect((w.UI.scrollToVisible(above))):toBe(true)
				Verify.expect(frame.CanvasPosition.Y):toBe(340)
				local inside = box(w, frame, Roblox.Vector2.new(0, 20), Roblox.Vector2.new(200, 30))
				Verify.expect((w.UI.scrollToVisible(inside))):toBe(false)
				Verify.expect(frame.CanvasPosition.Y):toBe(340)
				w.stop()
			end,
		})
		verifyHarness:case("aligns a span taller than the band to its top and clamps to the extent", {
			id = "native_environment::scrollTo and scrollToVisible over native ScrollingFrame::aligns a span taller than the band to its top and clamps to the extent",
			run = function()
				local w = world(nil, { motionLevel = "none" })
				local frame = scroller(w, "List", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(200, 300))
				local tall = box(w, frame, Roblox.Vector2.new(0, 50), Roblox.Vector2.new(200, 400))
				Verify.expect((w.UI.scrollToVisible(tall))):toBe(true)
				Verify.expect(frame.CanvasPosition.Y):toBe(50)
				local late = box(w, frame, Roblox.Vector2.new(0, 900), Roblox.Vector2.new(200, 30))
				Verify.expect((w.UI.scrollToVisible(late))):toBe(true)
				Verify.expect(frame.CanvasPosition.Y):toBe(200)
				local node = box(w, frame, Roblox.Vector2.new(0, 0), Roblox.Vector2.new(200, 20))
				Verify.expect((w.UI.scrollToVisible(node, { x = 0, y = 130, w = 50, h = 20 }))):toBe(false)
				frame.CanvasPosition = Roblox.Vector2.zero
				Verify.expect((w.UI.scrollToVisible(node, { x = 0, y = 130, w = 50, h = 20 }))):toBe(true)
				Verify.expect(frame.CanvasPosition.Y):toBe(50)
				w.stop()
			end,
		})
		verifyHarness:case("walks every scroll ancestor inner to outer, not just a direct parent", {
			id = "native_environment::scrollTo and scrollToVisible over native ScrollingFrame::walks every scroll ancestor inner to outer, not just a direct parent",
			run = function()
				local w = world(nil, { motionLevel = "none" })
				local outer = scroller(w, "Page", Roblox.Vector2.new(300, 200), Roblox.Vector2.new(300, 1000))
				local inner = scroller(
					w,
					"Rail",
					Roblox.Vector2.new(300, 100),
					Roblox.Vector2.new(300, 600),
					Roblox.Vector2.new(0, 400)
				)
				inner.Parent = outer
				local wrapper = w.engine.new("Frame")
				wrapper.Parent = inner
				local node = box(w, wrapper, Roblox.Vector2.new(0, 560), Roblox.Vector2.new(300, 20))
				Verify.expect((w.UI.scrollToVisible(node))):toBe(true)
				Verify.expect(inner.CanvasPosition.Y):toBe(80)
				Verify.expect(outer.CanvasPosition.Y):toBe(300)
				Verify.expect(
					(w.UI.scrollToVisible(box(w, w.engine.new("Frame"), Roblox.Vector2.zero, Roblox.Vector2.one)))
				)
					:toBe(false)
				w.stop()
			end,
		})
		verifyHarness:case("works on the horizontal axis and leaves a locked axis alone", {
			id = "native_environment::scrollTo and scrollToVisible over native ScrollingFrame::works on the horizontal axis and leaves a locked axis alone",
			run = function()
				local w = world(nil, { motionLevel = "none" })
				local E = w.Enum
				local frame = scroller(w, "Rail", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(1000, 400))
				frame.ScrollingDirection = E.ScrollingDirection.X
				local node = box(w, frame, Roblox.Vector2.new(250, 300), Roblox.Vector2.new(50, 50))
				Verify.expect((w.UI.scrollToVisible(node))):toBe(true)
				Verify.expect(frame.CanvasPosition):toBe(Roblox.Vector2.new(100, 0))
				w.stop()
			end,
		})
		verifyHarness:case("scrolls a mounted ScrollView and animates with the view", {
			id = "native_environment::scrollTo and scrollToVisible over native ScrollingFrame::scrolls a mounted ScrollView and animates with the view",
			run = function()
				local w = world(nil, { motionLevel = "none" })
				local UI = w.UI
				local node: any
				local stop, root: any = w.runtime.mount(function()
					node = UI.ScrollView "Feed" { UI.VStack "Rows" {} }
					return node
				end, w.engine.new("Folder"))
				root.AbsoluteWindowSize = Roblox.Vector2.new(100, 100)
				root.AbsoluteCanvasSize = Roblox.Vector2.new(100, 500)
				Verify.expect((UI.scrollTo(node, "bottom"))):toBe(true)
				Verify.expect(root.CanvasPosition.Y):toBe(400)
				stop()
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("focusSection", function()
		verifyHarness:case(
			"returns the selection to the item last selected in the section when it enters from outside",
			{
				id = "native_environment::focusSection::returns the selection to the item last selected in the section when it enters from outside",
				run = function()
					local w = world()
					local screen = w.engine.new("ScreenGui")
					local function button(name: string, parent: any): any
						local node = w.engine.new("TextButton")
						node.Name = name
						node.Selectable = true
						node.Parent = parent
						return node
					end
					local outline, detail = w.engine.new("Frame"), w.engine.new("Frame")
					outline.Parent, detail.Parent = screen, screen
					local rows = { button("Row1", outline), button("Row2", outline), button("Row3", outline) }
					local field = button("Field", detail)
					local stop = owned(w.runtime, function()
						w.UI.focusSection(outline)
					end)
					w.gui.SelectedObject = rows[1]
					w.gui.SelectedObject = rows[3]
					w.gui.SelectedObject = field
					w.gui.SelectedObject = rows[1]
					Verify.expect(w.gui.SelectedObject):toBe(rows[3])
					w.gui.SelectedObject = rows[2]
					Verify.expect(w.gui.SelectedObject):toBe(rows[2])
					rows[2].Parent = nil
					w.gui.SelectedObject = field
					w.gui.SelectedObject = rows[1]
					Verify.expect(w.gui.SelectedObject):toBe(rows[1])
					stop()
					w.gui.SelectedObject = field
					w.gui.SelectedObject = rows[3]
					Verify.expect(w.gui.SelectedObject):toBe(rows[3])
					w.stop()
				end,
			}
		)
	end)

	verifyHarness:suite("draggable and dropTarget", function()
		verifyHarness:case("uses the same touch coordinates at long press and movement", {
			id = "native_environment::draggable and dropTarget::uses the same touch coordinates at long press and movement",
			run = function()
				local w = world()
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				local screen, card = w.engine.new("ScreenGui"), w.engine.new("TextButton")
				local V2, V3 = w.engine.types.Vector2, w.engine.types.Vector3
				card.Parent = screen
				card.AbsolutePosition, card.AbsoluteSize = V2.new(0, 64), V2.new(56, 64)
				local stop = owned(w.runtime, function()
					w.UI.draggable(card, { payload = 1 })
				end)
				local touch = {
					UserInputType = w.Enum.UserInputType.Touch,
					UserInputState = w.Enum.UserInputState.Begin,
					Position = V3.new(10, 80, 0),
				}
				nativeDrag.press(card, touch)
				card.TouchLongPress:Fire({ V2.new(10, 138) }, w.Enum.UserInputState.Begin)
				local ghost = screen:FindFirstChild("DragGhost")
				Verify.expect(ghost.Position.Y.Offset):toBe(80)
				touch.Position = V3.new(11, 81, 0)
				nativeDrag.move(w.input, touch)
				Verify.expect(ghost.Position.Y.Offset):toBe(81)
				stop()
				w.stop()
			end,
		})
		verifyHarness:case("starts immediate touch pickup after travel and preserves scrolling on the other axis", {
			id = "native_environment::draggable and dropTarget::starts immediate touch pickup after travel and preserves scrolling on the other axis",
			run = function()
				for _, scrolling in { false, true } do
					local w = world()
					w.input.PreferredInput = w.Enum.PreferredInput.Touch
					local screen, scroll, card =
						w.engine.new("ScreenGui"), w.engine.new("ScrollingFrame"), w.engine.new("TextButton")
					local V2, V3 = w.engine.types.Vector2, w.engine.types.Vector3
					scroll.Parent, card.Parent = screen, scroll
					scroll.ScrollingEnabled = true
					card.AbsolutePosition, card.AbsoluteSize = V2.new(0, 64), V2.new(56, 64)
					local stop = owned(w.runtime, function()
						w.UI.draggable(
							card,
							{ payload = 1, touchPickup = "immediate", touchDragAxis = "X", armOnTap = true }
						)
					end)
					local touch = {
						UserInputType = w.Enum.UserInputType.Touch,
						UserInputState = w.Enum.UserInputState.Begin,
						Position = V3.new(10, 80, 0),
					}
					nativeDrag.press(card, touch)
					Verify.expect(screen:FindFirstChild("DragGhost")):toBeNil()
					touch.Position = V3.new(12, 81, 0)
					nativeDrag.move(w.input, touch)
					Verify.expect(screen:FindFirstChild("DragGhost")):toBeNil()
					touch.Position = if scrolling then V3.new(12, 90, 0) else V3.new(20, 81, 0)
					nativeDrag.move(w.input, touch)
					local ghost = screen:FindFirstChild("DragGhost")
					if scrolling then
						Verify.expect(ghost):toBeNil()
						Verify.expect(scroll.ScrollingEnabled):toBe(true)
						touch.Position = V3.new(30, 91, 0)
						nativeDrag.move(w.input, touch)
						Verify.expect(screen:FindFirstChild("DragGhost")):toBeNil()
					else
						Verify.expect(ghost ~= nil):toBe(true)
						Verify.expect(ghost.Position):toBe(w.engine.types.UDim2.fromOffset(20, 81))
						Verify.expect(ghost.AnchorPoint.Y):toBe(0.25)
						Verify.expect(scroll.ScrollingEnabled):toBe(false)
					end
					touch.UserInputState = w.Enum.UserInputState.End
					nativeDrag.finish(w.input, touch)
					Verify.expect(scroll.ScrollingEnabled):toBe(true)
					Verify.expect(card:GetAttribute("FacetDragHeld")):toBeNil()
					stop()
					w.stop()
				end
			end,
		})
		local function stage()
			local w = world()
			local screen = w.engine.new("ScreenGui")
			local function box(name: string, y: number): any
				local node = w.engine.new("TextButton")
				node.Name, node.Selectable, node.Parent = name, true, screen
				node.AbsolutePosition, node.AbsoluteSize =
					w.engine.types.Vector2.new(0, y), w.engine.types.Vector2.new(100, 40)
				return node
			end
			local card, open, closed = box("Card", 0), box("Open", 100), box("Closed", 200)
			local log = {}
			local stop = owned(w.runtime, function()
				w.UI.draggable(card, { payload = "sponsor", armOnTap = true })
				w.UI.dropTarget(open, {
					onDrop = function(payload, info)
						table.insert(log, `drop {payload} {info.target.Name} {info.mode}`)
					end,
					onEnter = function(payload)
						table.insert(log, `enter {payload}`)
					end,
					onLeave = function(payload)
						table.insert(log, `leave {payload}`)
					end,
				})
				w.UI.dropTarget(closed, {
					accepts = function()
						return false, "FULL"
					end,
					onDrop = function()
						table.insert(log, "dropped on a full slot")
					end,
					onReject = function(payload, reason)
						table.insert(log, `reject {payload} {reason}`)
					end,
				})
			end)
			return w, screen, card, open, closed, log, stop
		end
		local function pointer(w: any, kind: string, y: number): any
			return {
				UserInputType = w.Enum.UserInputType[kind],
				UserInputState = w.Enum.UserInputState.End,
				Position = w.engine.types.Vector3.new(50, y, 0),
			}
		end
		local function press(screen: any, name: string): boolean
			for _, node in screen:GetDescendants() do
				if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
					node:FindFirstChild(name).Pressed:Fire()
					return true
				end
			end
			return false
		end

		verifyHarness:case(
			"picks a source up after a pointer travels, shows a ghost and drops on the target under it",
			{
				id = "native_environment::draggable and dropTarget::picks a source up after a pointer travels, shows a ghost and drops on the target under it",
				run = function()
					local w, screen, card, _, _, log, stop = stage()
					nativeDrag.press(card, pointer(w, "MouseButton1", 20))
					nativeDrag.move(w.input, pointer(w, "MouseMovement", 23))
					Verify.expect((screen:FindFirstChild("DragGhost"))):toBeNil()
					nativeDrag.move(w.input, pointer(w, "MouseMovement", 120))
					local ghost = screen:FindFirstChild("DragGhost")
					Verify.expect(ghost ~= nil):toBe(true)
					Verify.expect(ghost.Position.Y.Offset):toBe(120)
					screen.AbsolutePosition = w.engine.types.Vector2.new(0, -58)
					nativeDrag.move(w.input, pointer(w, "MouseMovement", 121))

					Verify.expect(ghost.Position.Y.Offset):toBe(121 + 58)
					Verify.expect((card:GetAttribute("FacetDragHeld"))):toBe(true)
					Verify.expect((card:HasTag("facet-drag-held"))):toBe(true)
					nativeDrag.finish(w.input, pointer(w, "MouseButton1", 120))
					Verify.expect((table.concat(log, "; ")))
						:toBe("enter sponsor; drop sponsor Open pointer; leave sponsor")
					Verify.expect((screen:FindFirstChild("DragGhost"))):toBeNil()
					Verify.expect((card:GetAttribute("FacetDragHeld"))):toBeNil()
					table.clear(log)
					nativeDrag.press(card, pointer(w, "MouseButton1", 20))
					nativeDrag.move(w.input, pointer(w, "MouseMovement", 220))
					nativeDrag.finish(w.input, pointer(w, "MouseButton1", 220))
					Verify.expect((table.concat(log, "; "))):toBe("reject sponsor FULL")
					stop()
					w.stop()
				end,
			}
		)
		verifyHarness:case("preserves detector GUI coordinates with a top bar before selecting a nested target", {
			id = "native_environment::draggable and dropTarget::preserves detector GUI coordinates with a top bar before selecting a nested target",
			run = function()
				local w, screen, card, open, _, log, stop = stage()
				local V2 = w.engine.types.Vector2
				w.gui.GetGuiInset = function()
					return V2.new(0, 58), V2.zero
				end
				local outer, inner = w.engine.new("ScrollingFrame"), w.engine.new("ScrollingFrame")
				outer.Parent, inner.Parent, open.Parent = screen, outer, inner
				for _, node in { outer, inner } do
					node.AbsolutePosition, node.AbsoluteWindowSize = V2.zero, V2.new(300, 300)
				end
				local detector = card:FindFirstChild("FacetDragDetector")
				detector.DragStart:Fire(V2.new(50, 20))
				card.InputBegan:Fire(pointer(w, "MouseButton1", 20))
				detector.DragContinue:Fire(V2.new(50, 120))
				Verify.expect(screen:FindFirstChild("DragGhost").Position.Y.Offset):toBe(120)
				detector.DragEnd:Fire(V2.new(50, 120))
				Verify.expect(table.concat(log, "; ")):toBe("enter sponsor; drop sponsor Open pointer; leave sponsor")
				stop()
				w.stop()
			end,
		})

		verifyHarness:case("keeps the original mouse and touch pickup point as the preview moves", {
			id = "native_environment::draggable and dropTarget::keeps the original mouse and touch pickup point as the preview moves",
			run = function()
				for _, kind in { "MouseButton1", "Touch" } do
					local w, screen, card, _, _, _, stop = stage()
					local V2, V3 = w.engine.types.Vector2, w.engine.types.Vector3
					local value = pointer(w, kind, 30)
					value.Position = V3.new(10, 30, 0)
					value.UserInputState = w.Enum.UserInputState.Begin
					nativeDrag.press(card, value)
					if kind == "Touch" then
						value.Position = V3.new(12, 31, 0)
						card.TouchLongPress:Fire({ V2.new(12, 31) }, w.Enum.UserInputState.Begin)
						value.Position = V3.new(25, 32, 0)
						w.input.InputChanged:Fire(value)
					else
						value.Position = V3.new(25, 32, 0)
						local movement = pointer(w, "MouseMovement", 32)
						movement.Position = value.Position
						nativeDrag.move(w.input, movement)
					end
					local ghost = screen:FindFirstChild("DragGhost")
					Verify.expect(math.abs(ghost.AnchorPoint.X - 0.1) < 0.0001):toBe(true)
					Verify.expect(ghost.AnchorPoint.Y):toBe(0.75)
					Verify.expect(ghost.Position):toBe(w.engine.types.UDim2.fromOffset(25, 32))
					Verify.expect(
						math.abs(ghost.Position.X.Offset - ghost.AnchorPoint.X * ghost.Size.X.Offset - 15) < 0.0001
					)
						:toBe(true)
					stop()
					w.stop()
				end
			end,
		})

		verifyHarness:case("arms from the keyboard or pad, drops on the selected target and cancels with B", {
			id = "native_environment::draggable and dropTarget::arms from the keyboard or pad, drops on the selected target and cancels with B",
			run = function()
				local w, screen, card, open, _, log, stop = stage()
				Verify.expect((press(screen, "DragPickUp"))):toBe(false)
				w.gui.SelectedObject = card
				Verify.expect((press(screen, "DragPickUp"))):toBe(true)
				Verify.expect((card:GetAttribute("FacetDragHeld"))):toBe(true)
				w.gui.SelectedObject = open
				Verify.expect((press(screen, "DragDrop"))):toBe(true)
				Verify.expect((table.concat(log, "; "))):toBe("enter sponsor; drop sponsor Open armed; leave sponsor")
				table.clear(log)
				w.gui.SelectedObject = card
				press(screen, "DragPickUp")
				Verify.expect((press(screen, "DragCancel"))):toBe(true)
				Verify.expect((card:GetAttribute("FacetDragHeld"))):toBeNil()
				Verify.expect(#log):toBe(0)
				stop()
				w.stop()
			end,
		})

		verifyHarness:case(
			"arms a Facet Button source and drops on a Facet Button target through their own activation",
			{
				id = "native_environment::draggable and dropTarget::arms a Facet Button source and drops on a Facet Button target through their own activation",
				run = function()
					local w = world()
					local screen = w.engine.new("ScreenGui")
					local log = {}
					local stop, root: any = w.runtime.mount(function()
						local card = w.UI.Button "Card" { label = "Card" }
						local slot = w.UI.Button "Slot" { label = "Slot" }
						w.UI.draggable(card, { payload = "card" })
						w.UI.dropTarget(slot, {
							onDrop = function(payload, info)
								table.insert(log, `{payload} {info.mode}`)
							end,
						})
						return ((w.runtime.constructors.Frame :: unknown) :: FrameConstructor)({ card :: unknown, slot })
					end, screen)
					local card, slot = root:FindFirstChild("Card"), root:FindFirstChild("Slot")

					local pad = { UserInputType = w.Enum.UserInputType.Gamepad1, KeyCode = w.Enum.KeyCode.ButtonA }
					card.Activated:Fire(pad)
					Verify.expect((card:GetAttribute("FacetDragHeld"))):toBe(true)
					slot.Activated:Fire(pad)
					Verify.expect((table.concat(log, ";"))):toBe("card armed")
					card.Activated:Fire({ UserInputType = w.Enum.UserInputType.MouseButton1 })
					Verify.expect((card:GetAttribute("FacetDragHeld"))):toBeNil()
					stop()
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"leaves a moving finger to the scroller and picks up on the engine's long press, whose press never activates",
			{
				id = "native_environment::draggable and dropTarget::leaves a moving finger to the scroller and picks up on the engine's long press, whose press never activates",
				run = function()
					local w = world()
					local screen = w.engine.new("ScreenGui")
					local V2, V3 = w.engine.types.Vector2, w.engine.types.Vector3
					local log, opened = {}, 0
					local stop, root: any = w.runtime.mount(function()
						local card = w.UI.Button "Card" {
							label = "Card",
							onActivate = function()
								opened += 1
							end,
						}
						local slot = ((w.runtime.constructors.Frame :: unknown) :: FrameConstructor)({ Name = "Slot" })
						w.UI.draggable(card, { payload = "card" })
						w.UI.dropTarget(slot, {
							onDrop = function(payload, info)
								table.insert(log, `{payload} {info.mode}`)
							end,
						})
						return ((w.runtime.constructors.ScrollingFrame :: unknown) :: ScrollingFrameConstructor)({
							Name = "List",
							card :: unknown,
							slot,
						})
					end, screen)
					local card, slot = root:FindFirstChild("Card"), root:FindFirstChild("Slot")
					root.AbsoluteWindowSize = V2.new(100, 200)
					root.AbsoluteSize = V2.new(100, 200)
					card.AbsolutePosition, card.AbsoluteSize = V2.new(0, 0), V2.new(100, 40)
					slot.AbsolutePosition, slot.AbsoluteSize = V2.new(0, 100), V2.new(100, 40)
					local function finger(y: number): any
						local value = w.engine.new("InputObject")
						value.UserInputType = w.Enum.UserInputType.Touch
						value.UserInputState = w.Enum.UserInputState.Begin
						value.Position = V3.new(50, y, 0)
						return value
					end
					local flick = finger(20)
					nativeDrag.press(card, flick)
					flick.Position = V3.new(50, 120, 0)
					nativeDrag.move(w.input, flick)
					Verify.expect((screen:FindFirstChild("DragGhost", true))):toBeNil()
					flick.UserInputState = w.Enum.UserInputState.End
					nativeDrag.finish(w.input, flick)
					Verify.expect(#log):toBe(0)
					local hold = finger(20)
					nativeDrag.press(card, hold)
					card.TouchLongPress:Fire({ V2.new(50, 20) }, w.Enum.UserInputState.Begin)
					Verify.expect(screen:FindFirstChild("DragGhost", true) ~= nil):toBe(true)
					Verify.expect(root.ScrollingEnabled):toBe(false)
					hold.Position = V3.new(50, 120, 0)
					nativeDrag.move(w.input, hold)
					hold.UserInputState = w.Enum.UserInputState.End
					nativeDrag.finish(w.input, hold)
					Verify.expect((table.concat(log, ";"))):toBe("card pointer")
					Verify.expect(root.ScrollingEnabled):toBe(true)
					card.Activated:Fire(hold)
					Verify.expect(opened):toBe(0)
					card.Activated:Fire(finger(20))
					Verify.expect(opened):toBe(1)

					local mouse = w.engine.new("InputObject")
					mouse.UserInputType, mouse.Position = w.Enum.UserInputType.MouseButton1, V3.new(50, 20, 0)
					nativeDrag.press(card, mouse)
					nativeDrag.move(w.input, {
						UserInputType = w.Enum.UserInputType.MouseMovement,
						Position = V3.new(50, 120, 0),
					})
					mouse.UserInputState, mouse.Position = w.Enum.UserInputState.End, V3.new(50, 120, 0)
					nativeDrag.finish(w.input, mouse)
					card.Activated:Fire(mouse)
					Verify.expect(opened):toBe(1)
					w.engine.heartbeat:Fire(1 / 60)
					card.Activated:Fire(mouse)
					Verify.expect(opened):toBe(2)
					stop()
					w.stop()
				end,
			}
		)

		verifyHarness:case("arms on a tap when armOnTap is set and places on the next tapped target", {
			id = "native_environment::draggable and dropTarget::arms on a tap when armOnTap is set and places on the next tapped target",
			run = function()
				local w, _, card, open, _, log, stop = stage()
				local tap = pointer(w, "Touch", 20)
				nativeDrag.press(card, tap)
				nativeDrag.finish(w.input, tap)
				Verify.expect((card:GetAttribute("FacetDragHeld"))):toBe(true)
				nativeDrag.press(open, pointer(w, "Touch", 120))
				Verify.expect((table.concat(log, "; "))):toBe("drop sponsor Open armed")
				stop()
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("focusSection focusOnAppear / returnFocus (restored from 0.11)", function()
		local function scene()
			local w = world()
			local screen = w.engine.new("ScreenGui")
			local function button(name: string, parent: any): any
				local node = w.engine.new("TextButton")
				node.Name = name
				node.Selectable = true
				node.Parent = parent
				return node
			end
			w.gui.Select = function(_, parent: any)
				for _, node in parent:GetDescendants() do
					if node:IsA("GuiObject") and node.Selectable then
						w.gui.SelectedObject = node
						return
					end
				end
			end
			local list = w.engine.new("Frame")
			list.Parent = screen
			local rows = { button("Row1", list), button("Row2", list), button("Row3", list) }
			local detail = w.engine.new("Frame")
			detail.Name = "Detail"
			button("Back", detail)
			button("Save", detail)
			local function open(options: any): () -> ()
				return owned(w.runtime, function()
					detail.Parent = screen
					w.UI.focusSection(detail, options)
				end)
			end
			return w, rows, detail, open, screen
		end

		verifyHarness:case("focusOnAppear = true lands the selection on the branch's first stop", {
			id = "native_environment::focusSection focusOnAppear / returnFocus (restored from 0.11)::focusOnAppear = true lands the selection on the branch's first stop",
			run = function()
				local w, rows, detail, open = scene()
				w.gui.SelectedObject = rows[2]
				open({ focusOnAppear = true })
				Verify.expect(w.gui.SelectedObject):toBe(detail:FindFirstChild("Back"))
				w.stop()
			end,
		})

		verifyHarness:case("focusOnAppear names a descendant", {
			id = "native_environment::focusSection focusOnAppear / returnFocus (restored from 0.11)::focusOnAppear names a descendant",
			run = function()
				local w, rows, detail, open = scene()
				w.gui.SelectedObject = rows[1]
				open({ focusOnAppear = "Save" })
				Verify.expect(w.gui.SelectedObject):toBe(detail:FindFirstChild("Save"))
				w.stop()
			end,
		})

		verifyHarness:case("a branch that mounts before it is parented claims when it arrives", {
			id = "native_environment::focusSection focusOnAppear / returnFocus (restored from 0.11)::a branch that mounts before it is parented claims when it arrives",
			run = function()
				local w, rows, detail = scene()
				w.gui.SelectedObject = rows[1]
				local stop = owned(w.runtime, function()
					w.UI.focusSection(detail, { focusOnAppear = true })
				end)
				Verify.expect(w.gui.SelectedObject):toBe(rows[1])
				detail.Parent = rows[1].Parent.Parent
				Verify.expect(w.gui.SelectedObject):toBe(detail:FindFirstChild("Back"))
				stop()
				w.stop()
			end,
		})

		verifyHarness:case("does not take the selection from a pointer or touch player", {
			id = "native_environment::focusSection focusOnAppear / returnFocus (restored from 0.11)::does not take the selection from a pointer or touch player",
			run = function()
				local w, _, _, open = scene()
				open({ focusOnAppear = true, returnFocus = true })()
				Verify.expect(w.gui.SelectedObject):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("returnFocus puts the selection back on what held it before the claim", {
			id = "native_environment::focusSection focusOnAppear / returnFocus (restored from 0.11)::returnFocus puts the selection back on what held it before the claim",
			run = function()
				local w, rows, detail, open = scene()
				w.gui.SelectedObject = rows[3]
				local close = open({ focusOnAppear = "Save", returnFocus = true })
				Verify.expect(w.gui.SelectedObject):toBe(detail:FindFirstChild("Save"))
				detail.Parent = nil
				close()
				Verify.expect(w.gui.SelectedObject):toBe(rows[3])
				w.stop()
			end,
		})

		verifyHarness:case(
			"returns the selection when the engine reselects as the branch leaves, before its owner ends",
			{
				id = "native_environment::focusSection focusOnAppear / returnFocus (restored from 0.11)::returns the selection when the engine reselects as the branch leaves, before its owner ends",
				run = function()
					local w, rows, detail, open = scene()
					w.gui.SelectedObject = rows[3]
					local close = open({ focusOnAppear = "Save", returnFocus = true })
					detail.Parent = nil
					w.gui.SelectedObject = rows[1]
					Verify.expect(w.gui.SelectedObject):toBe(rows[3])
					close()
					Verify.expect(w.gui.SelectedObject):toBe(rows[3])
					w.stop()
				end,
			}
		)

		verifyHarness:case("leaves a selection the player moved outside the branch alone", {
			id = "native_environment::focusSection focusOnAppear / returnFocus (restored from 0.11)::leaves a selection the player moved outside the branch alone",
			run = function()
				local w, rows, _, open = scene()
				w.gui.SelectedObject = rows[3]
				local close = open({ focusOnAppear = true, returnFocus = true })
				w.gui.SelectedObject = rows[1]
				close()
				Verify.expect(w.gui.SelectedObject):toBe(rows[1])
				w.stop()
			end,
		})

		verifyHarness:case("a remembered target that is gone falls through to the screen rather than blanking", {
			id = "native_environment::focusSection focusOnAppear / returnFocus (restored from 0.11)::a remembered target that is gone falls through to the screen rather than blanking",
			run = function()
				local w, rows, detail, open = scene()
				w.gui.SelectedObject = rows[3]
				local close = open({ focusOnAppear = true, returnFocus = true })
				rows[3].Parent = nil
				w.gui.SelectedObject = nil
				detail.Parent = nil
				close()
				Verify.expect(w.gui.SelectedObject):toBe(rows[1])
				w.stop()
			end,
		})

		verifyHarness:case("refuses a misspelled option", {
			id = "native_environment::focusSection focusOnAppear / returnFocus (restored from 0.11)::refuses a misspelled option",
			run = function()
				local w, _, detail = scene()
				local ok, err = pcall(function()
					owned(w.runtime, function()
						w.UI.focusSection(detail, { focusOnApear = true } :: any)
					end)
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(err), "focusOnApear", 1, true) ~= nil):toBe(true)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("focus ring: the engine draws the theme's focus look", function()
		local function ring(package: any?, environment: any?)
			local w = world(nil, { theme = package, environment = environment })
			local playerGui = w.engine.new("PlayerGui")
			local stop = owned(w.runtime, function()
				w.UI.focusRing(playerGui)
			end)
			local template = playerGui.SelectionImageObject
			return w, template, function()
				stop()
				w.stop()
			end
		end
		local function define(focus: any, assets: any?): any
			local package, report = Facet.themes.define({
				base = Facet.themes.neutralPackage(),
				identity = { id = "focus-test" },
				chrome = { focus = focus },
				assets = assets,
			})
			assert(package, report and report.errors[1] and report.errors[1].message)
			return package
		end

		verifyHarness:case("hands the engine one selection object with a thicker ring at ten feet", {
			id = "native_environment::focus ring: the engine draws the theme's focus look::hands the engine one selection object with a thicker ring at ten feet",
			run = function()
				local distance = Compose.cell("near")
				local w, template, stop = ring(nil, { viewingDistance = distance, preferredInput = "Gamepad" })
				Verify.expect(template.Name):toBe("FacetFocusRing")
				local stroke = template:FindFirstChildWhichIsA("UIStroke")
				Verify.expect(stroke.Enabled):toBe(true)
				Verify.expect(stroke.Thickness):toBe(2)
				Verify.expect(stroke.Transparency):toBe(0)
				Verify.expect(template:FindFirstChild("Glow").Enabled):toBe(false)
				Verify.expect(template.ImageTransparency):toBe(1)
				Verify.expect(#template:GetChildren()):toBe(3)
				for _, child in template:GetDescendants() do
					Verify.expect((child:IsA("GuiObject"))):toBe(false)
				end
				Verify.expect(template.Size):toBe(w.engine.types.UDim2.new(1, 4, 1, 4))
				distance:set("ten-foot")
				Verify.expect(stroke.Thickness):toBe(4)
				Verify.expect(template.Size):toBe(w.engine.types.UDim2.new(1, 14, 1, 14))
				Verify.expect(template.Position):toBe(w.engine.types.UDim2.fromOffset(-7, -7))
				stop()
				Verify.expect(w ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("paints focus glow outside the selected control instead of over its glyphs", {
			id = "native_environment::focus ring: the engine draws the theme's focus look::paints focus glow outside the selected control instead of over its glyphs",
			run = function()
				local glowing = define({ kind = "glow" :: "glow", blurRadius = { offset = 26 }, transparency = 0.25 })
				local w, template, stop = ring(glowing, { preferredInput = "Gamepad" })
				local target = w.engine.new("TextButton")
				target.Parent = w.engine.new("ScreenGui")
				w.gui.SelectedObject = target
				Verify.expect(template:FindFirstChild("Glow").Enabled):toBe(false)
				local shadow = target:FindFirstChild("FacetFocusGlow")
				Verify.expect(shadow ~= nil):toBe(true)
				Verify.expect(shadow.Enabled):toBe(true)
				Verify.expect(shadow:IsA("UIStroke")):toBe(true)
				Verify.expect(shadow.ApplyStrokeMode):toBe(w.engine.types.Enum.ApplyStrokeMode.Border)
				Verify.expect(shadow.BorderStrokePosition):toBe(w.engine.types.Enum.BorderStrokePosition.Outer)
				Verify.expect(shadow.Thickness):toBe(2)
				w.gui.SelectedObject = nil
				Verify.expect(target:FindFirstChild("FacetFocusGlow")):toBeNil()
				stop()
			end,
		})

		verifyHarness:case("paints a glow theme as a native shadow that grows at ten feet", {
			id = "native_environment::focus ring: the engine draws the theme's focus look::paints a glow theme as a native shadow that grows at ten feet",
			run = function()
				local glowing =
					define({ kind = "glow" :: "glow", blurRadius = { scale = 0, offset = 26 }, transparency = 0.25 })
				local distance = Compose.cell("near")
				local _, template, stop = ring(glowing, { viewingDistance = distance, preferredInput = "Gamepad" })
				local glow = template:FindFirstChild("Glow")
				Verify.expect(template:FindFirstChildWhichIsA("UIStroke").Enabled):toBe(false)
				Verify.expect(glow.Enabled):toBe(true)
				Verify.expect(glow.BlurRadius.Offset):toBe(26)
				Verify.expect(glow.Transparency):toBe(0.25)
				distance:set("ten-foot")
				Verify.expect(glow.BlurRadius.Offset):toBe(42)
				Verify.expect(math.abs(glow.Transparency - 0.1375) < 0.001):toBe(true)
				stop()
			end,
		})

		verifyHarness:case("stretches sliced focus art around the control with an outset", {
			id = "native_environment::focus ring: the engine draws the theme's focus look::stretches sliced focus art around the control with an outset",
			run = function()
				local package = define({ kind = "nineSlice" :: "nineSlice", asset = "bracket", outset = 4 }, {
					bracket = { content = "rbxassetid://5", sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 } },
				})
				local distance = Compose.cell("near")
				local w, template, stop = ring(package, { viewingDistance = distance, preferredInput = "Gamepad" })
				Verify.expect(template.ClassName):toBe("ImageLabel")
				Verify.expect(template.ImageTransparency):toBe(0)
				Verify.expect(template.Image):toBe("rbxassetid://5")
				Verify.expect(template.ScaleType):toBe(w.Enum.ScaleType.Slice)
				Verify.expect(template.SliceCenter):toBe(w.engine.types.Rect.new(8, 8, 24, 24))
				Verify.expect(template.Size):toBe(w.engine.types.UDim2.new(1, 8, 1, 8))
				Verify.expect(template.Position):toBe(w.engine.types.UDim2.fromOffset(-4, -4))
				Verify.expect(template:FindFirstChildWhichIsA("UIStroke").Enabled):toBe(false)
				distance:set("ten-foot")
				Verify.expect(template.Size):toBe(w.engine.types.UDim2.new(1, 18, 1, 18))
				stop()
			end,
		})

		verifyHarness:case("takes the shape of the selected control: its own corner, a pill, or the theme's square", {
			id = "native_environment::focus ring: the engine draws the theme's focus look::takes the shape of the selected control: its own corner, a pill, or the theme's square",
			run = function()
				local w, template, stop = ring(nil, { preferredInput = "Gamepad" })
				local E, D = w.Enum, w.engine.types.UDim
				local screen = w.engine.new("ScreenGui")
				local round = w.engine.new("TextButton")
				local own = w.engine.new("UICorner")
				own.CornerRadius = D.new(0, 5)
				own.Parent = round
				local chip = w.engine.new("TextButton")
				chip:AddTag("facet-chip")
				local plain = w.engine.new("TextButton")
				for _, node in { round, chip, plain } do
					node.Parent = screen
				end
				local corner = template:FindFirstChildWhichIsA("UICorner")
				w.gui.SelectedObject = round
				Verify.expect(corner.CornerRadius):toBe(D.new(0, 7))
				own.CornerRadius = D.new(0, 9)
				Verify.expect(corner.CornerRadius):toBe(D.new(0, 11))
				w.gui.SelectedObject = chip
				own.CornerRadius = D.new(0, 3)
				Verify.expect(corner.CornerRadius):toBe(D.new(0, 1001))
				Verify.expect(template.Size.Y.Scale):toBe(1)
				chip:SetAttribute("FacetFocusHeight", 1.5)
				Verify.expect(template.Size.Y.Scale):toBe(1.5)
				Verify.expect(corner.CornerRadius):toBe(D.new(0, 1001))
				w.gui.SelectedObject = plain
				Verify.expect(template.Size.Y.Scale):toBe(1)
				Verify.expect(corner.CornerRadius.Scale):toBe(0)
				stop()
				local square = define({ kind = "ring" :: "ring", corner = "square", thickness = 3 })
				w, template, stop = ring(square, { preferredInput = "Gamepad" })
				w.gui.SelectedObject = chip
				Verify.expect(template:FindFirstChildWhichIsA("UICorner").CornerRadius):toBe(D.new(0, 0))
				Verify.expect(template:FindFirstChildWhichIsA("UIStroke").Thickness):toBe(3)
				stop()
				Verify.expect(E ~= nil):toBe(true)
			end,
		})

		verifyHarness:case(
			"draws Pixel Quest's square corner brackets, Fantasy Ornate's gold frame and a lifted ring at ten feet",
			{
				id = "native_environment::focus ring: the engine draws the theme's focus look::draws Pixel Quest's square corner brackets, Fantasy Ornate's gold frame and a lifted ring at ten feet",
				run = function()
					local pixel = require("../examples/themes/pixel_quest").build(Facet.themes)
					local distance = Compose.cell("near")
					local w, template, stop = ring(pixel, { viewingDistance = distance, preferredInput = "Gamepad" })
					local U = w.engine.types.UDim2
					local screen = w.engine.new("ScreenGui")
					local button = w.engine.new("TextButton")
					button.Parent = screen
					button.AbsoluteSize = w.engine.types.Vector2.new(100, 44)
					w.gui.SelectedObject = button
					local stroke = template:FindFirstChildWhichIsA("UIStroke")
					local mask = stroke:FindFirstChild("Brackets")
					Verify.expect(stroke.Enabled):toBe(true)
					Verify.expect(stroke.Thickness):toBe(4)
					Verify.expect(mask.Enabled):toBe(true)
					local keys = mask.Transparency.Keypoints
					Verify.expect(keys[1].Value == 0 and keys[3].Value == 1 and keys[#keys].Value == 0):toBe(true)
					Verify.expect(math.abs(keys[2].Time - 12 / 112) < 0.001):toBe(true)
					button.AbsoluteSize = w.engine.types.Vector2.new(200, 44)
					Verify.expect(math.abs(mask.Transparency.Keypoints[2].Time - 12 / 212) < 0.001):toBe(true)
					button.AbsoluteSize = w.engine.types.Vector2.new(100, 44)
					Verify.expect(template:FindFirstChildWhichIsA("UICorner").CornerRadius)
						:toBe(w.engine.types.UDim.new(0, 0))
					Verify.expect(template.Size):toBe(U.new(1, 12, 1, 12))
					distance:set("ten-foot")
					Verify.expect(stroke.Thickness):toBe(6)
					Verify.expect(template.Size):toBe(U.new(1, 24, 1, 24))
					Verify.expect(template.Position):toBe(U.fromOffset(-12, -12))
					stop()
					local ornate = require("../examples/themes/fantasy_ornate").build(Facet.themes)
					local _, framed, stopFramed = ring(ornate, { preferredInput = "Gamepad" })
					Verify.expect(framed.ImageTransparency):toBe(0)
					Verify.expect(framed.Image):toBe(ornate.assets.ornate_panel_frame.content)
					Verify.expect(framed.SliceScale < 1):toBe(true)
					Verify.expect(framed:FindFirstChildWhichIsA("UICorner").CornerRadius)
						:toBe(w.engine.types.UDim.new(0, 0))
					stopFramed()
				end,
			}
		)

		verifyHarness:case(
			"pulses a theme that asks for it with an engine tween, only while shown and never under reduced motion",
			{
				id = "native_environment::focus ring: the engine draws the theme's focus look::pulses a theme that asks for it with an engine tween, only while shown and never under reduced motion",
				run = function()
					local package = define({ kind = "ring" :: "ring", pulse = true })
					local motionOff = Compose.cell(false)
					local created = {}
					local tweens = {
						Create = function(_, instance: any, info: TweenInfo, goal: { [string]: any })
							local record = { instance = instance, info = info, goal = goal, played = 0, cancelled = 0 }
							function record.Play()
								record.played += 1
							end
							function record.Cancel()
								record.cancelled += 1
							end
							table.insert(created, record)
							return record
						end,
					}
					local w = world({ TweenService = tweens }, {
						theme = package,
						motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
							return if use(motionOff) then "none" else "normal"
						end) :: unknown) :: MotionLevel,
						environment = { preferredInput = "Gamepad" },
					})
					local playerGui = w.engine.new("PlayerGui")
					local stop = owned(w.runtime, function()
						w.UI.focusRing(playerGui)
					end)
					local stroke = playerGui.SelectionImageObject:FindFirstChildWhichIsA("UIStroke")
					Verify.expect(stroke.Transparency):toBe(0)
					Verify.expect(#created):toBe(1)
					local tween = created[1]
					Verify.expect(tween.instance.ClassName):toBe("NumberValue")
					Verify.expect(tween.played):toBe(1)
					Verify.expect(tween.goal.Value):toBe(1)
					Verify.expect(tween.info.RepeatCount):toBe(-1)
					Verify.expect(tween.info.Reverses):toBe(true)
					tween.instance.Value = 0.5
					Verify.expect(math.abs(stroke.Transparency - 0.175) < 1e-6):toBe(true)
					motionOff:set(true)
					Verify.expect(tween.cancelled):toBe(1)
					Verify.expect(stroke.Transparency):toBe(0)
					Verify.expect((engineLib.connections(w.engine.heartbeat))):toBe(0)
					stop()
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"keeps the next control in reach: a keyboard or pad selection scrolls one row of room into view",
			{
				id = "native_environment::focus ring: the engine draws the theme's focus look::keeps the next control in reach: a keyboard or pad selection scrolls one row of room into view",
				run = function()
					local w, _, stop = ring(nil, { preferredInput = "Gamepad" })
					w.input.GetLastInputType = function()
						return w.Enum.UserInputType.Gamepad1
					end
					local V = w.engine.types.Vector2
					local screen = w.engine.new("ScreenGui")
					local list = w.engine.new("ScrollingFrame")
					list.Parent = screen
					list.AbsolutePosition, list.AbsoluteWindowSize = V.new(0, 0), V.new(300, 200)
					list.AbsoluteCanvasSize = V.new(300, 1000)
					local row = w.engine.new("TextButton")
					row.Parent = list
					row.AbsolutePosition, row.AbsoluteSize = V.new(0, 150), V.new(300, 44)
					w.gui.SelectedObject = row
					Verify.expect(list.CanvasPosition.Y):toBe(38)
					stop()
				end,
			}
		)

		verifyHarness:case("never scrolls a tall selection out of view to make room around it", {
			id = "native_environment::focus ring: the engine draws the theme's focus look::never scrolls a tall selection out of view to make room around it",
			run = function()
				local w, _, stop = ring(nil, { preferredInput = "Gamepad" })
				w.input.GetLastInputType = function()
					return w.Enum.UserInputType.Gamepad1
				end
				local V = w.engine.types.Vector2
				local screen = w.engine.new("ScreenGui")
				local list = w.engine.new("ScrollingFrame")
				list.Parent = screen
				list.AbsolutePosition, list.AbsoluteWindowSize = V.new(0, 0), V.new(300, 200)
				list.AbsoluteCanvasSize = V.new(300, 2000)
				list.CanvasPosition = V.new(0, 300)
				local card = w.engine.new("TextButton")
				card.Parent = list
				card.AbsolutePosition, card.AbsoluteSize = V.new(0, 100), V.new(300, 160)
				w.gui.SelectedObject = card
				local top = 100 - (list.CanvasPosition.Y - 300)
				Verify.expect(top >= 0 and top + 160 <= 200):toBe(true)
				stop()
			end,
		})

		verifyHarness:case("shares the one engine selection object among apps and gives back what was there before", {
			id = "native_environment::focus ring: the engine draws the theme's focus look::shares the one engine selection object among apps and gives back what was there before",
			run = function()
				local w = world(nil, { environment = { preferredInput = "Gamepad" } })
				local playerGui = w.engine.new("PlayerGui")
				local own = w.engine.new("Frame")
				playerGui.SelectionImageObject = own
				local stopA = owned(w.runtime, function()
					w.UI.focusRing(playerGui)
				end)
				local first = playerGui.SelectionImageObject
				local stopB = owned(w.runtime, function()
					w.UI.focusRing(playerGui)
				end)
				local second = playerGui.SelectionImageObject
				Verify.expect(first ~= own and second ~= own):toBe(true)
				stopB()
				Verify.expect(playerGui.SelectionImageObject):toBe(first)
				stopA()
				Verify.expect(playerGui.SelectionImageObject):toBe(own)
				w.stop()
			end,
		})

		verifyHarness:case("an app with focusRing = false leaves a game's own selection object alone", {
			id = "native_environment::focus ring: the engine draws the theme's focus look::an app with focusRing = false leaves a game's own selection object alone",
			run = function()
				for _, wanted in { true, false } do
					local engine: any = require("./lib/native_engine").new()
					local gui, input = engine.new("GuiService"), engine.new("UserInputService")
					input.GetFocusedTextBox = function()
						return nil
					end
					local playerGui = engine.new("PlayerGui")
					local own = engine.new("Frame")
					playerGui.SelectionImageObject = own
					local app = Facet.app({
						runtime = Facet.Roblox.createRuntime(engine),
						types = engine.types,
						parent = playerGui,
						guiService = gui,
						services = { GuiService = gui, UserInputService = input },
						focusRing = if wanted then nil else false,
					} :: any)
					local stop = app.mount(function()
						return app.UI.Button "Play" { label = "Play" }
					end)
					Verify.expect(`{wanted} {playerGui.SelectionImageObject == own}`):toBe(`{wanted} {not wanted}`)
					stop()
					Verify.expect(playerGui.SelectionImageObject):toBe(own)
				end
			end,
		})

		verifyHarness:case("colours the focus look from the theme's focus role", {
			id = "native_environment::focus ring: the engine draws the theme's focus look::colours the focus look from the theme's focus role",
			run = function()
				local ornate = require("../examples/themes/fantasy_parchment").build(Facet.themes)
				local w = world()
				local color
				for _, package in { Facet.themes.neutralPackage(), ornate } do
					local _, sheet: any = w.runtime.mount(function()
						return Facet.themes.createStyleSheet(w.runtime, package, { types = w.engine.types })
					end, w.engine.new("Folder"))
					for _, node in sheet:GetChildren() do
						if node.Selector == ".facet-focus-ring" then
							color = node:GetProperties().BackgroundColor3
						end
					end
					if package == ornate then
						Verify.expect(color):toBe(w.engine.types.Color3.fromRGB(214, 154, 46))
					else
						local accent = package.style.themes[1].colors.accent
						Verify.expect(color):toBe(w.engine.types.Color3.new(accent.r, accent.g, accent.b))
					end
				end
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("failed drop feedback", function()
		verifyHarness:case(
			"returns a rejected preview with a native tween, skips motion when reduced, and cleans up on unmount",
			{
				id = "native_environment::failed drop feedback::returns a rejected preview with a native tween, skips motion when reduced, and cleans up on unmount",
				run = function()
					local created: { any } = {}
					local tweens = {
						Create = function(_, node, info, goal)
							local playback = {
								Completed = signal(),
								node = node,
								info = info,
								goal = goal,
								played = false,
								cancelled = false,
							}
							function playback:Play()
								self.played = true
							end
							function playback:Cancel()
								self.cancelled = true
							end
							table.insert(created, playback)
							return playback
						end,
					}
					local w = world({ TweenService = tweens })
					local screen = w.engine.new("ScreenGui")
					local stop, source: any = w.runtime.mount(function()
						local node = w.UI.Button { label = "Asset" }
						w.UI.draggable(node, { payload = "asset" })
						return node
					end, screen)
					source.AbsolutePosition, source.AbsoluteSize =
						Roblox.Vector2.new(20, 30), Roblox.Vector2.new(80, 40)
					local function fail()
						local press = {
							UserInputType = w.Enum.UserInputType.MouseButton1,
							Position = Roblox.Vector3.new(28, 60, 0),
						}
						nativeDrag.press(source, press)
						nativeDrag.move(w.input, {
							UserInputType = w.Enum.UserInputType.MouseMovement,
							Position = Roblox.Vector3.new(300, 400, 0),
						})
						press.Position, press.UserInputState =
							Roblox.Vector3.new(300, 400, 0), w.Enum.UserInputState.End
						nativeDrag.finish(w.input, press)
					end
					fail()
					Verify.expect(#created):toBe(1)
					Verify.expect(created[1].played):toBe(true)
					Verify.expect(created[1].goal.Position):toBe(Roblox.UDim2.fromOffset(28, 60))
					Verify.expect(created[1].node.Parent):toBe(screen)
					created[1].Completed:Fire()
					Verify.expect((screen:FindFirstChild("DragGhost"))):toBe(nil)
					local dropped = 0
					local stopTarget, destination: any = w.runtime.mount(function()
						local node = w.runtime.constructors.Frame {}
						w.UI.dropTarget(node, {
							onDrop = function()
								dropped += 1
							end,
						})
						return node
					end, screen)
					destination.AbsolutePosition = Roblox.Vector2.new(280, 380)
					destination.AbsoluteSize = Roblox.Vector2.new(80, 80)
					fail()
					Verify.expect(dropped):toBe(1)
					Verify.expect(created[2].node.ClassName):toBe("UIScale")
					Verify.expect(created[2].goal.Scale):toBe(0)
					Verify.expect(screen:FindFirstChild("DragGhost") ~= nil):toBe(true)
					created[2].Completed:Fire()
					Verify.expect((screen:FindFirstChild("DragGhost"))):toBe(nil)
					stopTarget()
					w.gui.ReducedMotionEnabled = true
					fail()
					Verify.expect(#created):toBe(2)
					Verify.expect((screen:FindFirstChild("DragGhost"))):toBe(nil)
					w.gui.ReducedMotionEnabled = false
					fail()
					stop()
					Verify.expect(created[3].cancelled):toBe(true)
					Verify.expect((screen:FindFirstChild("DragGhost"))):toBe(nil)
					w.stop()
				end,
			}
		)
	end)
end
