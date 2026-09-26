--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local engineLib = require("./lib/native_engine")
local Roblox = require("@lune/roblox")
local Compose = Facet.Compose
local adaptive = Facet.adaptive

local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn)
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
		fire = function()
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
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	local frames = { Heartbeat = signal() }
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		userInputService = input,
		services = { GuiService = gui, UserInputService = input, RunService = frames },
	}
	for key, value in services or {} do
		config.services[key] = value
	end
	for key, value in options or {} do
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

t.describe("adaptive: pure decisions with no device names", function()
	t.it("classifies width into compact, regular and wide at the documented breakpoints", function()
		t.expect(adaptive.sizeClass(320)).toBe("compact")
		t.expect(adaptive.sizeClass(599)).toBe("compact")
		t.expect(adaptive.sizeClass(600)).toBe("regular")
		t.expect(adaptive.sizeClass(999)).toBe("regular")
		t.expect(adaptive.sizeClass(1000)).toBe("wide")
		t.expect(adaptive.BREAKPOINTS.regular).toBe(600)
		t.expect(adaptive.BREAKPOINTS.wide).toBe(1000)
		t.expect(adaptive.HEIGHT_BREAKPOINTS).toBe(adaptive.BREAKPOINTS)
	end)
	t.it("classifies height and orientation as shape facts", function()
		t.expect(adaptive.heightClass(313)).toBe("short")
		t.expect(adaptive.heightClass(733)).toBe("medium")
		t.expect(adaptive.heightClass(1080)).toBe("tall")
		t.expect(adaptive.heightClass(0 / 0)).toBe("short")
		t.expect(adaptive.orientationFor(733, 313)).toBe("landscape")
		t.expect(adaptive.orientationFor(313, 733)).toBe("portrait")
		t.expect(adaptive.orientationFor(500, 500)).toBe("square")
	end)
	t.it("chooses a stack axis from available width, not a platform name", function()
		t.expect(adaptive.axisFor(400, { stackAbove = 600 })).toBe("y")
		t.expect(adaptive.axisFor(800, { stackAbove = 600 })).toBe("x")
		t.expect(adaptive.axisFor(599)).toBe("y")
		t.expect(adaptive.axisFor(adaptive.DEFAULT_STACK_ABOVE)).toBe("x")
	end)
	t.it("derives a column count from a minimum cell width and gap", function()
		t.expect(adaptive.columnsFor(300, 90, 6)).toBe(3)
		t.expect(adaptive.columnsFor(100, 90, 6)).toBe(1)
		t.expect(adaptive.columnsFor(0, 90, 6)).toBe(1)
		t.expect(adaptive.columnsFor(1920, 160, 8)).toBe(11)
		t.expect(adaptive.columnsFor(1600, 160, 8)).toBe(9)
		t.expect(pcall(adaptive.columnsFor, 300, 0, 6)).toBe(false)
	end)
	t.it("tolerates a nonsense width instead of producing a nonsense class", function()
		t.expect(adaptive.sizeClass(0 / 0)).toBe("compact")
		t.expect(adaptive.sizeClass(-50)).toBe("compact")
		t.expect(adaptive.sizeClass(nil)).toBe("compact")
	end)
	t.it("ranks compact < regular < wide", function()
		local order = { "compact", "regular", "wide" }
		for have, value in order do
			for need, target in order do
				t.expect(adaptive.sizeClassAtLeast(value, target)).toBe(have >= need)
			end
		end
		t.expect(pcall(adaptive.sizeClassAtLeast, "huge", "wide")).toBe(false)
	end)
	t.it("homes app navigation by viewing distance, then shape, then primary input", function()
		local function home(size: string, height: string, primary: string?, extra: { [string]: any }?): string
			local facts: { [string]: any } = { sizeClass = size, heightClass = height, primary = primary }
			for key, value in extra or {} do
				facts[key] = value
			end
			return adaptive.navPlacement(facts)
		end
		t.expect(home("compact", "short", "pointer", { tenFoot = true })).toBe("topBar")
		t.expect(home("compact", "medium", "touch")).toBe("bottomBar")
		t.expect(home("compact", "tall", "gamepad")).toBe("bottomBar")
		t.expect(home("wide", "short", "touch")).toBe("bottomBarCompact")
		t.expect(home("regular", "medium", "pointer")).toBe("sidebar")
		t.expect(home("wide", "tall", "pointer")).toBe("sidebar")
		t.expect(home("regular", "medium", "touch")).toBe("topBar")
		t.expect(home("wide", "medium", "gamepad", { displaySize = "Medium" })).toBe("topBar")
		t.expect(home("wide", "medium", "gamepad", { displaySize = "Small" })).toBe("bottomBar")
		t.expect(home("wide", "medium", nil)).toBe("topBar")
	end)
	t.it("treats a large display as ten-foot only without touch or a mouse", function()
		t.expect(adaptive.isTenFoot({ displaySize = "Large" })).toBe(true)
		t.expect(adaptive.isTenFoot({ displaySize = "Large", mouse = true })).toBe(false)
		t.expect(adaptive.isTenFoot({ displaySize = "Large", touch = true })).toBe(false)
		t.expect(adaptive.isTenFoot({ displaySize = "Medium" })).toBe(false)
		t.expect(adaptive.isTenFoot({ displaySize = "Medium", tenFootInterface = true })).toBe(true)
		t.expect(adaptive.isTenFoot({ displaySize = "Large", tenFootInterface = true, mouse = true })).toBe(false)
	end)
end)

t.describe("environment: reactive facts from engine sources", function()
	t.it("exposes the size class and its boolean tests as readables that follow the viewport", function()
		local w = world()
		local screen = w.engine.new("ScreenGui")
		screen.AbsoluteSize = Roblox.Vector2.new(390, 844)
		local env: any
		local reads = 0
		local stop = owned(w.runtime, function()
			env = w.UI.environment(screen)
			Compose.watch(function(use)
				use(env.sizeClass)
				reads += 1
			end)
		end)
		t.expect(env.sizeClass:peek()).toBe("compact")
		t.expect(env.isCompact:peek()).toBe(true)
		t.expect(env.isRegularOrWider:peek()).toBe(false)
		t.expect(env.orientation:peek()).toBe("portrait")
		t.expect(env.isLandscape:peek()).toBe(false)
		t.expect(env.heightClass:peek()).toBe("medium")
		t.expect(env.axis:peek()).toBe("y")
		screen.AbsoluteSize = Roblox.Vector2.new(1280, 720)
		t.expect(env.viewportWidth:peek()).toBe(1280)
		t.expect(env.sizeClass:peek()).toBe("wide")
		t.expect(env.isWide:peek()).toBe(true)
		t.expect(env.isRegular:peek()).toBe(false)
		t.expect(env.isRegularOrWider:peek()).toBe(true)
		t.expect(env.atLeast("regular"):peek()).toBe(true)
		t.expect(env.orientation:peek()).toBe("landscape")
		t.expect(env.axis:peek()).toBe("x")
		local before = reads
		screen.AbsoluteSize = Roblox.Vector2.new(1300, 700)
		t.expect(reads).toBe(before)
		t.expect(pcall(env.atLeast, "huge")).toBe(false)
		stop()
		w.stop()
	end)
	t.it("refuses the engine's placeholder viewport and keeps the last real fact", function()
		local w = world()
		local camera = w.engine.new("Camera")
		camera.ViewportSize = Roblox.Vector2.new(800, 600)
		local env: any
		local stop = owned(w.runtime, function()
			env = w.UI.environment(camera)
		end)
		t.expect(env.sizeClass:peek()).toBe("regular")
		camera.ViewportSize = Roblox.Vector2.new(1, 1)
		t.expect(env.viewportWidth:peek()).toBe(800)
		t.expect(env.sizeClass:peek()).toBe("regular")
		camera.ViewportSize = Roblox.Vector2.new(1920, 1080)
		t.expect(env.sizeClass:peek()).toBe("wide")
		t.expect(env.isTall:peek()).toBe(true)
		stop()
		w.stop()
	end)
	t.it("reads the workspace camera when no source is given", function()
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
		t.expect(env.viewportSize:peek()).toBe(camera.ViewportSize)
		t.expect(env.isShort:peek()).toBe(false)
		t.expect(env.orientation:peek()).toBe("portrait")
		stop()
		w.stop()
	end)
	t.it("derives interaction classes from preferred input and live capabilities", function()
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
		t.expect(classes.primary).toBe("pointer")
		t.expect(classes.pointer).toBe(true)
		t.expect(classes.keyboard).toBe(true)
		t.expect(classes.gamepad).toBe(false)
		t.expect(env.effectiveInput:peek()).toBe("KeyboardAndMouse")
		w.input.GamepadEnabled = true
		t.expect(env.interactionClasses:peek().gamepad).toBe(true)
		t.expect(env.interactionClasses:peek().primary).toBe("pointer")
		w.input.PreferredInput = E.PreferredInput.Gamepad
		t.expect(env.interactionClasses:peek().primary).toBe("gamepad")
		t.expect(env.effectiveInput:peek()).toBe("Gamepad")
		w.input.GamepadEnabled = false
		t.expect(env.interactionClasses:peek().gamepad).toBe(true)
		w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		w.input.MouseEnabled = false
		w.input.TouchEnabled = true
		t.expect(env.interactionClasses:peek().primary).toBe("touch")
		t.expect(env.effectiveInput:peek()).toBe("Touch")
		stop()
		w.stop()
	end)
	t.it("publishes safe insets, display size, preferred text size and reduced motion", function()
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
		t.expect(insets.top).toBe(58)
		t.expect(insets.left).toBe(0)
		topLeft, bottomRight = Roblox.Vector2.new(47, 0), Roblox.Vector2.new(47, 21)
		screen.AbsoluteSize = Roblox.Vector2.new(852, 393)
		insets = env.safeInsets:peek()
		t.expect(insets.left).toBe(47)
		t.expect(insets.right).toBe(47)
		t.expect(insets.bottom).toBe(21)
		t.expect(insets.top).toBe(0)
		t.expect(env.displaySize:peek()).toBe("Medium")
		t.expect(env.isTenFoot:peek()).toBe(false)
		t.expect(env.navPlacement:peek()).toBe("bottomBarCompact")
		w.gui.ViewportDisplaySize = E.DisplaySize.Large
		w.input.MouseEnabled = false
		w.input.GamepadEnabled = true
		w.input.PreferredInput = E.PreferredInput.Gamepad
		t.expect(env.isTenFoot:peek()).toBe(true)
		t.expect(env.navPlacement:peek()).toBe("topBar")
		screen.AbsoluteSize = Roblox.Vector2.new(1920, 1080)
		t.expect(env.sizeClass:peek()).toBe("regular")
		t.expect(env.heightClass:peek()).toBe("medium")
		w.input.MouseEnabled = true
		t.expect(env.isTenFoot:peek()).toBe(false)
		t.expect(env.sizeClass:peek()).toBe("wide")
		t.expect(env.heightClass:peek()).toBe("tall")
		t.expect(env.preferredTextSize:peek()).toBe("Medium")
		w.gui.PreferredTextSize = E.PreferredTextSize.Largest
		t.expect(env.preferredTextSize:peek()).toBe("Largest")
		t.expect(env.reducedMotion:peek()).toBe(false)
		w.gui.ReducedMotionEnabled = true
		t.expect(env.reducedMotion:peek()).toBe(true)
		stop()
		w.stop()
	end)
	t.it("requires an owner and stops observing when the owner ends", function()
		local w = world()
		t.expect(pcall(w.UI.environment)).toBe(false)
		local screen = w.engine.new("ScreenGui")
		screen.AbsoluteSize = Roblox.Vector2.new(400, 800)
		local env: any
		local stop = owned(w.runtime, function()
			env = w.UI.environment(screen)
		end)
		stop()
		screen.AbsoluteSize = Roblox.Vector2.new(1400, 800)
		t.expect(pcall(function()
			return env.viewportWidth:peek()
		end)).toBe(false)
		w.stop()
	end)
end)

t.describe("environment: viewing distance, metric scale and overscan", function()
	local function console(options: { [string]: any }?, touch: boolean?): (any, any, any)
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
	t.it("a console-shaped display is ten-foot at 1.5x with the console overscan; a touch handheld is near", function()
		local _, env, stop = console()
		t.expect(env.isTenFoot:peek()).toBe(true)
		t.expect(env.metricScale:peek()).toBe(1.5)
		t.expect(env.overscanInsets:peek()).toEqual({ top = 60, left = 90, bottom = 60, right = 90 })
		t.expect(env.viewingDistanceSource:peek()).toBe("inferred")
		t.expect(env.sizeClass:peek()).toBe("regular")
		stop()
		local _, handheld, stopHandheld = console(nil, true)
		t.expect(handheld.isTenFoot:peek()).toBe(false)
		t.expect(handheld.metricScale:peek()).toBe(1)
		t.expect(handheld.overscanInsets:peek()).toEqual({ top = 0, left = 0, bottom = 0, right = 0 })
		t.expect(handheld.sizeClass:peek()).toBe("wide")
		stopHandheld()
	end)
	t.it("overscan is a proportion of the viewport; authored margins win and none opts out", function()
		local authored = Compose.cell(nil :: any)
		local _, env, stop, screen = console({ environment = { overscanInsets = authored } })
		screen.AbsoluteSize = Roblox.Vector2.new(1280, 720)
		t.expect(env.overscanInsets:peek()).toEqual({ top = 40, left = 60, bottom = 40, right = 60 })
		authored:set({ top = 10, left = 20, bottom = 10, right = 20 })
		t.expect(env.overscanInsets:peek()).toEqual({ top = 10, left = 20, bottom = 10, right = 20 })
		authored:set("none")
		t.expect(env.overscanInsets:peek()).toEqual({ top = 0, left = 0, bottom = 0, right = 0 })
		stop()
	end)
	t.it("an authored viewingDistance outranks the inference and says so", function()
		local distance = Compose.cell("automatic")
		local w, env, stop = console({ environment = { viewingDistance = distance } })
		distance:set("near")
		t.expect(env.isTenFoot:peek()).toBe(false)
		t.expect(env.metricScale:peek()).toBe(1)
		t.expect(env.viewingDistanceSource:peek()).toBe("authored")
		t.expect(env.overscanInsets:peek().left).toBe(0)
		distance:set("ten-foot")
		w.input.MouseEnabled = true
		w.gui.ViewportDisplaySize = w.Enum.DisplaySize.Medium
		t.expect(env.isTenFoot:peek()).toBe(true)
		t.expect(env.metricScale:peek()).toBe(1.5)
		t.expect(env.navPlacement:peek()).toBe("topBar")
		distance:set("automatic")
		t.expect(env.isTenFoot:peek()).toBe(false)
		t.expect(env.viewingDistanceSource:peek()).toBe("inferred")
		distance:set("far")
		t.expect(pcall(function()
			return env.isTenFoot:peek()
		end)).toBe(false)
		stop()
		t.expect(pcall(Facet.controls, w.runtime, { types = w.engine.types, environment = { distance = "near" } }))
			.toBe(false)
	end)
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

t.describe("worldAnchor: proximity anchors around world objects", function()
	t.it("retains offscreen directions for markers and can suppress occluded targets", function()
		local w, scene, part = fixture()
		local hit: any = nil
		scene.CurrentCamera.CFrame = Roblox.CFrame.new()
		function scene.Raycast()
			return hit
		end
		part.CFrame = Roblox.CFrame.new(100, 0, -10)
		local binding = w.UI.worldAnchor({ target = part, offscreen = "retain", occlusion = true })
		t.expect(binding.anchor:peek().visible).toBe(true)
		t.expect(binding.anchor:peek().onscreen).toBe(false)
		t.expect(binding.anchor:peek().x > 800).toBe(true)
		part.CFrame = Roblox.CFrame.new(100, 0, 10)
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().x > 400).toBe(true)
		hit = {
			Instance = {
				IsDescendantOf = function()
					return false
				end,
			},
		}
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().visible).toBe(false)
		t.expect(binding.anchor:peek().occluded).toBe(true)
		hit = { Instance = part }
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().visible).toBe(true)
		binding.dispose()
		w.stop()
	end)
	t.it("encloses projected corners with padding and updates on the frame", function()
		local w, _, part = fixture()
		local binding = w.UI.worldAnchor({ target = part, padding = 0.15 })
		local a = binding.anchor:peek()
		t.expect(a.visible).toBe(true)
		t.expect(a.x).toBe(400)
		t.expect(a.y).toBe(300)
		t.expect(math.abs(a.clearance - (math.sqrt(20 * 20 + 10 * 10) / 0.9 * 1.15)) < 0.001).toBe(true)
		part.CFrame = Roblox.CFrame.new(2, 0, -5) * Roblox.CFrame.Angles(0, 0.5, 0.3)
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().x > a.x).toBe(true)
		t.expect(binding.anchor:peek().clearance > a.clearance).toBe(true)
		binding.dispose()
		w.stop()
	end)
	t.it("uses relative padding at every distance and defaults to fifteen percent", function()
		for _, padding in { false, 0, 0.15, 0.5, 1 } do
			local w, _, part = fixture()
			local options: any = { target = part }
			if padding ~= false then
				options.padding = padding
			end
			local binding = w.UI.worldAnchor(options)
			for _, distance in { 5, 10, 20 } do
				part.CFrame = Roblox.CFrame.new(0, 0, -distance)
				w.frames.Heartbeat.fire()
				local radius = math.sqrt(200 ^ 2 + 100 ^ 2) / (distance - 1)
				local fraction = if padding == false then 0.15 else padding
				t.expect(math.abs(binding.anchor:peek().clearance / radius - (1 + fraction)) < 0.00001).toBe(true)
			end
			binding.dispose()
			w.stop()
		end
	end)
	t.it("tracks models, avatar respawns, camera replacement and unavailable targets", function()
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
		t.expect(binding.anchor:peek().clearance > 0).toBe(true)
		player.Character = nil
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().visible).toBe(false)
		player.Character = model
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().visible).toBe(true)
		target:set(nil)
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().visible).toBe(false)
		target:set(player)
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().visible).toBe(true)
		scene.CurrentCamera = nil
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().visible).toBe(false)
		binding.dispose()
		binding.dispose()
		t.expect(w.frames.Heartbeat.count()).toBe(0)
		w.stop()
	end)
	t.it("rejects near-plane intersections and offscreen or removed objects", function()
		local w, _, part = fixture()
		local binding = w.UI.worldAnchor({ target = part })
		for _, frame in { Roblox.CFrame.new(0, 0, -1), Roblox.CFrame.new(0, 0, 10), Roblox.CFrame.new(100, 0, -10) } do
			part.CFrame = frame
			w.frames.Heartbeat.fire()
			t.expect(binding.anchor:peek().visible).toBe(false)
		end
		part.CFrame = Roblox.CFrame.new(0, 0, -10)
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().visible).toBe(true)
		part.live = false
		w.frames.Heartbeat.fire()
		t.expect(binding.anchor:peek().visible).toBe(false)
		binding.dispose()
		w.stop()
	end)
	t.it("validates options before allocating a frame hook", function()
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
			t.expect(pcall(w.UI.worldAnchor, options)).toBe(false)
		end
		t.expect(w.frames.Heartbeat.count()).toBe(0)
		w.stop()
	end)
	t.it("feeds a RadialMenu anchor and releases with its owner", function()
		local w, _, part = fixture()
		local binding: any
		local stop = owned(w.runtime, function()
			binding = w.UI.worldAnchor({ target = part })
		end)
		t.expect(w.frames.Heartbeat.count()).toBe(1)
		t.expect(binding.anchor:peek().visible).toBe(true)
		stop()
		t.expect(w.frames.Heartbeat.count()).toBe(0)
		t.expect(binding.anchor:peek().visible).toBe(false)
		w.stop()
	end)
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

t.describe("scrollTo and scrollToVisible over native ScrollingFrame", function()
	t.it("writes a programmatic position and the canvas limits clamp it", function()
		local w = world(nil, { reducedMotion = true })
		local frame = scroller(w, "List", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(200, 1000))
		t.expect(w.UI.scrollTo(frame, Roblox.Vector2.new(0, 250))).toBe(true)
		t.expect(frame.CanvasPosition).toBe(Roblox.Vector2.new(0, 250))
		t.expect(w.UI.scrollTo(frame, { y = 5000 })).toBe(true)
		t.expect(frame.CanvasPosition.Y).toBe(900)
		t.expect(w.UI.scrollTo(frame, "bottom")).toBe(false)
		t.expect(w.UI.scrollTo(frame, "top")).toBe(true)
		t.expect(frame.CanvasPosition).toBe(Roblox.Vector2.zero)
		t.expect(w.UI.scrollTo(frame, { y = -40 })).toBe(false)
		t.expect(pcall(w.UI.scrollTo, w.engine.new("Frame"), "top")).toBe(false)
		t.expect(pcall(w.UI.scrollTo, frame, "middle")).toBe(false)
		w.stop()
	end)
	t.it("animates through TweenService and moves at once under reduced motion", function()
		local created = {}
		local tweens = {
			Create = function(_, instance, info, goal)
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
		t.expect(w.UI.scrollTo(frame, { y = 300 })).toBe(true)
		t.expect(#created).toBe(1)
		t.expect(created[1].played).toBe(1)
		t.expect(created[1].goal.CanvasPosition).toBe(Roblox.Vector2.new(0, 300))
		t.expect(frame.CanvasPosition).toBe(Roblox.Vector2.zero)
		t.expect(w.UI.scrollTo(frame, { y = 600 })).toBe(true)
		t.expect(created[1].cancelled).toBe(1)
		t.expect(w.UI.scrollTo(frame, { y = 700 }, { animated = false })).toBe(true)
		t.expect(created[2].cancelled).toBe(1)
		t.expect(frame.CanvasPosition.Y).toBe(700)
		w.gui.ReducedMotionEnabled = true
		t.expect(w.UI.scrollTo(frame, "top")).toBe(true)
		t.expect(#created).toBe(2)
		t.expect(frame.CanvasPosition.Y).toBe(0)
		w.stop()
	end)
	t.it("moves both axes of an xy host to bring a node beyond both edges into view", function()
		local w = world(nil, { reducedMotion = true })
		local frame = scroller(w, "Board", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(1000, 1000))
		frame.ScrollingDirection = w.engine.types.Enum.ScrollingDirection.XY
		local far = box(w, frame, Roblox.Vector2.new(260, 150), Roblox.Vector2.new(40, 30))
		t.expect(w.UI.scrollToVisible(far)).toBe(true)
		t.expect(frame.CanvasPosition).toBe(Roblox.Vector2.new(100, 80))
		w.stop()
	end)
	t.it("scrolls the minimum distance to bring a node below or above the viewport into view", function()
		local w = world(nil, { reducedMotion = true })
		local frame = scroller(w, "List", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(200, 1000))
		local below = box(w, frame, Roblox.Vector2.new(0, 150), Roblox.Vector2.new(200, 30))
		t.expect(w.UI.scrollToVisible(below)).toBe(true)
		t.expect(frame.CanvasPosition.Y).toBe(80)
		frame.CanvasPosition = Roblox.Vector2.new(0, 400)
		local above = box(w, frame, Roblox.Vector2.new(0, -60), Roblox.Vector2.new(200, 30))
		t.expect(w.UI.scrollToVisible(above)).toBe(true)
		t.expect(frame.CanvasPosition.Y).toBe(340)
		local inside = box(w, frame, Roblox.Vector2.new(0, 20), Roblox.Vector2.new(200, 30))
		t.expect(w.UI.scrollToVisible(inside)).toBe(false)
		t.expect(frame.CanvasPosition.Y).toBe(340)
		w.stop()
	end)
	t.it("aligns a span taller than the band to its top and clamps to the extent", function()
		local w = world(nil, { reducedMotion = true })
		local frame = scroller(w, "List", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(200, 300))
		local tall = box(w, frame, Roblox.Vector2.new(0, 50), Roblox.Vector2.new(200, 400))
		t.expect(w.UI.scrollToVisible(tall)).toBe(true)
		t.expect(frame.CanvasPosition.Y).toBe(50)
		local late = box(w, frame, Roblox.Vector2.new(0, 900), Roblox.Vector2.new(200, 30))
		t.expect(w.UI.scrollToVisible(late)).toBe(true)
		t.expect(frame.CanvasPosition.Y).toBe(200)
		local node = box(w, frame, Roblox.Vector2.new(0, 0), Roblox.Vector2.new(200, 20))
		t.expect(w.UI.scrollToVisible(node, { x = 0, y = 130, w = 50, h = 20 })).toBe(false)
		frame.CanvasPosition = Roblox.Vector2.zero
		t.expect(w.UI.scrollToVisible(node, { x = 0, y = 130, w = 50, h = 20 })).toBe(true)
		t.expect(frame.CanvasPosition.Y).toBe(50)
		w.stop()
	end)
	t.it("walks every scroll ancestor inner to outer, not just a direct parent", function()
		local w = world(nil, { reducedMotion = true })
		local outer = scroller(w, "Page", Roblox.Vector2.new(300, 200), Roblox.Vector2.new(300, 1000))
		local inner =
			scroller(w, "Rail", Roblox.Vector2.new(300, 100), Roblox.Vector2.new(300, 600), Roblox.Vector2.new(0, 400))
		inner.Parent = outer
		local wrapper = w.engine.new("Frame")
		wrapper.Parent = inner
		local node = box(w, wrapper, Roblox.Vector2.new(0, 560), Roblox.Vector2.new(300, 20))
		t.expect(w.UI.scrollToVisible(node)).toBe(true)
		t.expect(inner.CanvasPosition.Y).toBe(80)
		t.expect(outer.CanvasPosition.Y).toBe(300)
		t.expect(w.UI.scrollToVisible(box(w, w.engine.new("Frame"), Roblox.Vector2.zero, Roblox.Vector2.one)))
			.toBe(false)
		w.stop()
	end)
	t.it("works on the horizontal axis and leaves a locked axis alone", function()
		local w = world(nil, { reducedMotion = true })
		local E = w.Enum
		local frame = scroller(w, "Rail", Roblox.Vector2.new(200, 100), Roblox.Vector2.new(1000, 400))
		frame.ScrollingDirection = E.ScrollingDirection.X
		local node = box(w, frame, Roblox.Vector2.new(250, 300), Roblox.Vector2.new(50, 50))
		t.expect(w.UI.scrollToVisible(node)).toBe(true)
		t.expect(frame.CanvasPosition).toBe(Roblox.Vector2.new(100, 0))
		w.stop()
	end)
	t.it("scrolls a mounted ScrollView and animates with the view", function()
		local w = world(nil, { reducedMotion = true })
		local UI = w.UI
		local node: any
		local stop, root = w.runtime.mount(function()
			node = UI.ScrollView "Feed" { UI.VStack "Rows" {} }
			return node
		end, w.engine.new("Folder"))
		root.AbsoluteWindowSize = Roblox.Vector2.new(100, 100)
		root.AbsoluteCanvasSize = Roblox.Vector2.new(100, 500)
		t.expect(UI.scrollTo(node, "bottom")).toBe(true)
		t.expect(root.CanvasPosition.Y).toBe(400)
		stop()
		w.stop()
	end)
end)

t.describe("focusSection", function()
	t.it("returns the selection to the item last selected in the section when it enters from outside", function()
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
		t.expect(w.gui.SelectedObject).toBe(rows[3])
		w.gui.SelectedObject = rows[2]
		t.expect(w.gui.SelectedObject).toBe(rows[2])
		rows[2].Parent = nil
		w.gui.SelectedObject = field
		w.gui.SelectedObject = rows[1]
		t.expect(w.gui.SelectedObject).toBe(rows[1])
		stop()
		w.gui.SelectedObject = field
		w.gui.SelectedObject = rows[3]
		t.expect(w.gui.SelectedObject).toBe(rows[3])
		w.stop()
	end)
end)

t.describe("draggable and dropTarget", function()
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
				node:FindFirstChild(name).Pressed.fire()
				return true
			end
		end
		return false
	end

	t.it("picks a source up after a pointer travels, shows a ghost and drops on the target under it", function()
		local w, screen, card, _, _, log, stop = stage()
		card.InputBegan.fire(pointer(w, "MouseButton1", 20))
		w.input.InputChanged.fire(pointer(w, "MouseMovement", 23))
		t.expect(screen:FindFirstChild("DragGhost")).toBeNil()
		w.input.InputChanged.fire(pointer(w, "MouseMovement", 120))
		local ghost = screen:FindFirstChild("DragGhost")
		t.expect(ghost ~= nil).toBe(true)
		t.expect(ghost.Position.Y.Offset).toBe(120)
		screen.AbsolutePosition = w.engine.types.Vector2.new(0, -58)
		w.input.InputChanged.fire(pointer(w, "MouseMovement", 121))

		t.expect(ghost.Position.Y.Offset).toBe(121 + 58)
		t.expect(card:GetAttribute("FacetDragHeld")).toBe(true)
		t.expect(card:HasTag("facet-drag-held")).toBe(true)
		w.input.InputEnded.fire(pointer(w, "MouseButton1", 120))
		t.expect(table.concat(log, "; ")).toBe("enter sponsor; leave sponsor; drop sponsor Open pointer")
		t.expect(screen:FindFirstChild("DragGhost")).toBeNil()
		t.expect(card:GetAttribute("FacetDragHeld")).toBeNil()
		table.clear(log)
		card.InputBegan.fire(pointer(w, "MouseButton1", 20))
		w.input.InputChanged.fire(pointer(w, "MouseMovement", 220))
		w.input.InputEnded.fire(pointer(w, "MouseButton1", 220))
		t.expect(table.concat(log, "; ")).toBe("reject sponsor FULL")
		stop()
		w.stop()
	end)

	t.it("arms from the keyboard or pad, drops on the selected target and cancels with B", function()
		local w, screen, card, open, _, log, stop = stage()
		t.expect(press(screen, "DragPickUp")).toBe(false)
		w.gui.SelectedObject = card
		t.expect(press(screen, "DragPickUp")).toBe(true)
		t.expect(card:GetAttribute("FacetDragHeld")).toBe(true)
		w.gui.SelectedObject = open
		t.expect(press(screen, "DragDrop")).toBe(true)
		t.expect(table.concat(log, "; ")).toBe("enter sponsor; leave sponsor; drop sponsor Open armed")
		table.clear(log)
		w.gui.SelectedObject = card
		press(screen, "DragPickUp")
		t.expect(press(screen, "DragCancel")).toBe(true)
		t.expect(card:GetAttribute("FacetDragHeld")).toBeNil()
		t.expect(#log).toBe(0)
		stop()
		w.stop()
	end)

	t.it("arms a Facet Button source and drops on a Facet Button target through their own activation", function()
		local w = world()
		local screen = w.engine.new("ScreenGui")
		local log = {}
		local stop, root = w.runtime.mount(function()
			local card = w.UI.Button "Card" { label = "Card" }
			local slot = w.UI.Button "Slot" { label = "Slot" }
			w.UI.draggable(card, { payload = "card" })
			w.UI.dropTarget(slot, {
				onDrop = function(payload, info)
					table.insert(log, `{payload} {info.mode}`)
				end,
			})
			return w.runtime.constructors.Frame({ card, slot })
		end, screen)
		local card, slot = root:FindFirstChild("Card"), root:FindFirstChild("Slot")

		local pad = { UserInputType = w.Enum.UserInputType.Gamepad1, KeyCode = w.Enum.KeyCode.ButtonA }
		card.Activated.fire(pad)
		t.expect(card:GetAttribute("FacetDragHeld")).toBe(true)
		slot.Activated.fire(pad)
		t.expect(table.concat(log, ";")).toBe("card armed")
		card.Activated.fire({ UserInputType = w.Enum.UserInputType.MouseButton1 })
		t.expect(card:GetAttribute("FacetDragHeld")).toBeNil()
		stop()
		w.stop()
	end)

	t.it(
		"leaves a moving finger to the scroller and picks up on the engine's long press, whose press never activates",
		function()
			local w = world()
			local screen = w.engine.new("ScreenGui")
			local V2, V3 = w.engine.types.Vector2, w.engine.types.Vector3
			local log, opened = {}, 0
			local stop, root = w.runtime.mount(function()
				local card = w.UI.Button "Card" {
					label = "Card",
					onActivate = function()
						opened += 1
					end,
				}
				local slot = w.runtime.constructors.Frame({ Name = "Slot" })
				w.UI.draggable(card, { payload = "card" })
				w.UI.dropTarget(slot, {
					onDrop = function(payload, info)
						table.insert(log, `{payload} {info.mode}`)
					end,
				})
				return w.runtime.constructors.ScrollingFrame({ Name = "List", card, slot })
			end, screen)
			local card, slot = root:FindFirstChild("Card"), root:FindFirstChild("Slot")
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
			card.InputBegan.fire(flick)
			flick.Position = V3.new(50, 120, 0)
			w.input.InputChanged.fire(flick)
			t.expect(screen:FindFirstChild("DragGhost", true)).toBeNil()
			flick.UserInputState = w.Enum.UserInputState.End
			w.input.InputEnded.fire(flick)
			t.expect(#log).toBe(0)
			local hold = finger(20)
			card.InputBegan.fire(hold)
			card.TouchLongPress.fire({ V2.new(50, 20) }, w.Enum.UserInputState.Begin)
			t.expect(screen:FindFirstChild("DragGhost", true) ~= nil).toBe(true)
			t.expect(root.ScrollingEnabled).toBe(false)
			hold.Position = V3.new(50, 120, 0)
			w.input.InputChanged.fire(hold)
			hold.UserInputState = w.Enum.UserInputState.End
			w.input.InputEnded.fire(hold)
			t.expect(table.concat(log, ";")).toBe("card pointer")
			t.expect(root.ScrollingEnabled).toBe(true)
			card.Activated.fire(hold)
			t.expect(opened).toBe(0)
			card.Activated.fire(finger(20))
			t.expect(opened).toBe(1)

			local mouse = w.engine.new("InputObject")
			mouse.UserInputType, mouse.Position = w.Enum.UserInputType.MouseButton1, V3.new(50, 20, 0)
			card.InputBegan.fire(mouse)
			w.input.InputChanged.fire({
				UserInputType = w.Enum.UserInputType.MouseMovement,
				Position = V3.new(50, 120, 0),
			})
			mouse.UserInputState, mouse.Position = w.Enum.UserInputState.End, V3.new(50, 120, 0)
			w.input.InputEnded.fire(mouse)
			card.Activated.fire(mouse)
			t.expect(opened).toBe(1)
			w.engine.heartbeat.fire(1 / 60)
			card.Activated.fire(mouse)
			t.expect(opened).toBe(2)
			stop()
			w.stop()
		end
	)

	t.it("arms on a tap when armOnTap is set and places on the next tapped target", function()
		local w, _, card, open, _, log, stop = stage()
		local tap = pointer(w, "Touch", 20)
		card.InputBegan.fire(tap)
		w.input.InputEnded.fire(tap)
		t.expect(card:GetAttribute("FacetDragHeld")).toBe(true)
		open.InputBegan.fire(pointer(w, "Touch", 120))
		t.expect(table.concat(log, "; ")).toBe("drop sponsor Open armed")
		stop()
		w.stop()
	end)
end)

t.describe("focusSection focusOnAppear / returnFocus (restored from 0.11)", function()
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

	t.it("focusOnAppear = true lands the selection on the branch's first stop", function()
		local w, rows, detail, open = scene()
		w.gui.SelectedObject = rows[2]
		open({ focusOnAppear = true })
		t.expect(w.gui.SelectedObject).toBe(detail:FindFirstChild("Back"))
		w.stop()
	end)

	t.it("focusOnAppear names a descendant", function()
		local w, rows, detail, open = scene()
		w.gui.SelectedObject = rows[1]
		open({ focusOnAppear = "Save" })
		t.expect(w.gui.SelectedObject).toBe(detail:FindFirstChild("Save"))
		w.stop()
	end)

	t.it("a branch that mounts before it is parented claims when it arrives", function()
		local w, rows, detail = scene()
		w.gui.SelectedObject = rows[1]
		local stop = owned(w.runtime, function()
			w.UI.focusSection(detail, { focusOnAppear = true })
		end)
		t.expect(w.gui.SelectedObject).toBe(rows[1])
		detail.Parent = rows[1].Parent.Parent
		t.expect(w.gui.SelectedObject).toBe(detail:FindFirstChild("Back"))
		stop()
		w.stop()
	end)

	t.it("does not take the selection from a pointer or touch player", function()
		local w, _, _, open = scene()
		open({ focusOnAppear = true, returnFocus = true })()
		t.expect(w.gui.SelectedObject).toBeNil()
		w.stop()
	end)

	t.it("returnFocus puts the selection back on what held it before the claim", function()
		local w, rows, detail, open = scene()
		w.gui.SelectedObject = rows[3]
		local close = open({ focusOnAppear = "Save", returnFocus = true })
		t.expect(w.gui.SelectedObject).toBe(detail:FindFirstChild("Save"))
		detail.Parent = nil
		close()
		t.expect(w.gui.SelectedObject).toBe(rows[3])
		w.stop()
	end)

	t.it("returns the selection when the engine reselects as the branch leaves, before its owner ends", function()
		local w, rows, detail, open = scene()
		w.gui.SelectedObject = rows[3]
		local close = open({ focusOnAppear = "Save", returnFocus = true })
		detail.Parent = nil
		w.gui.SelectedObject = rows[1]
		t.expect(w.gui.SelectedObject).toBe(rows[3])
		close()
		t.expect(w.gui.SelectedObject).toBe(rows[3])
		w.stop()
	end)

	t.it("leaves a selection the player moved outside the branch alone", function()
		local w, rows, _, open = scene()
		w.gui.SelectedObject = rows[3]
		local close = open({ focusOnAppear = true, returnFocus = true })
		w.gui.SelectedObject = rows[1]
		close()
		t.expect(w.gui.SelectedObject).toBe(rows[1])
		w.stop()
	end)

	t.it("a remembered target that is gone falls through to the screen rather than blanking", function()
		local w, rows, detail, open = scene()
		w.gui.SelectedObject = rows[3]
		local close = open({ focusOnAppear = true, returnFocus = true })
		rows[3].Parent = nil
		w.gui.SelectedObject = nil
		detail.Parent = nil
		close()
		t.expect(w.gui.SelectedObject).toBe(rows[1])
		w.stop()
	end)

	t.it("refuses a misspelled option", function()
		local w, _, detail = scene()
		local ok, err = pcall(function()
			owned(w.runtime, function()
				w.UI.focusSection(detail, { focusOnApear = true } :: any)
			end)
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "focusOnApear", 1, true) ~= nil).toBe(true)
		w.stop()
	end)
end)

t.describe("focus ring: the engine draws the theme's focus look", function()
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

	t.it("hands the engine one selection object with a thicker ring at ten feet", function()
		local distance = Compose.cell("near")
		local w, template, stop = ring(nil, { viewingDistance = distance, preferredInput = "Gamepad" })
		t.expect(template.Name).toBe("FacetFocusRing")
		local stroke = template:FindFirstChildWhichIsA("UIStroke")
		t.expect(stroke.Enabled).toBe(true)
		t.expect(stroke.Thickness).toBe(2)
		t.expect(stroke.Transparency).toBe(0)
		t.expect(template:FindFirstChild("Glow").Enabled).toBe(false)
		t.expect(template.ImageTransparency).toBe(1)
		t.expect(#template:GetChildren()).toBe(3)
		for _, child in template:GetDescendants() do
			t.expect(child:IsA("GuiObject")).toBe(false)
		end
		t.expect(template.Size).toBe(w.engine.types.UDim2.new(1, 4, 1, 4))
		distance:set("ten-foot")
		t.expect(stroke.Thickness).toBe(4)
		t.expect(template.Size).toBe(w.engine.types.UDim2.new(1, 14, 1, 14))
		t.expect(template.Position).toBe(w.engine.types.UDim2.fromOffset(-7, -7))
		stop()
		t.expect(w ~= nil).toBe(true)
	end)

	t.it("paints a glow theme as a native shadow that grows at ten feet", function()
		local glowing = define({ kind = "glow", blurRadius = { scale = 0, offset = 26 }, transparency = 0.25 })
		local distance = Compose.cell("near")
		local _, template, stop = ring(glowing, { viewingDistance = distance, preferredInput = "Gamepad" })
		local glow = template:FindFirstChild("Glow")
		t.expect(template:FindFirstChildWhichIsA("UIStroke").Enabled).toBe(false)
		t.expect(glow.Enabled).toBe(true)
		t.expect(glow.BlurRadius.Offset).toBe(26)
		t.expect(glow.Transparency).toBe(0.25)
		distance:set("ten-foot")
		t.expect(glow.BlurRadius.Offset).toBe(42)
		t.expect(math.abs(glow.Transparency - 0.1375) < 0.001).toBe(true)
		stop()
	end)

	t.it("stretches sliced focus art around the control with an outset", function()
		local package = define({ kind = "nineSlice", asset = "bracket", outset = 4 }, {
			bracket = { content = "rbxassetid://5", sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 } },
		})
		local distance = Compose.cell("near")
		local w, template, stop = ring(package, { viewingDistance = distance, preferredInput = "Gamepad" })
		t.expect(template.ClassName).toBe("ImageLabel")
		t.expect(template.ImageTransparency).toBe(0)
		t.expect(template.Image).toBe("rbxassetid://5")
		t.expect(template.ScaleType).toBe(w.Enum.ScaleType.Slice)
		t.expect(template.SliceCenter).toBe(w.engine.types.Rect.new(8, 8, 24, 24))
		t.expect(template.Size).toBe(w.engine.types.UDim2.new(1, 8, 1, 8))
		t.expect(template.Position).toBe(w.engine.types.UDim2.fromOffset(-4, -4))
		t.expect(template:FindFirstChildWhichIsA("UIStroke").Enabled).toBe(false)
		distance:set("ten-foot")
		t.expect(template.Size).toBe(w.engine.types.UDim2.new(1, 18, 1, 18))
		stop()
	end)

	t.it("takes the shape of the selected control: its own corner, a pill, or the theme's square", function()
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
		t.expect(corner.CornerRadius).toBe(D.new(0, 7))
		own.CornerRadius = D.new(0, 9)
		t.expect(corner.CornerRadius).toBe(D.new(0, 11))
		w.gui.SelectedObject = chip
		own.CornerRadius = D.new(0, 3)
		t.expect(corner.CornerRadius).toBe(D.new(0, 1001))
		t.expect(template.Size.Y.Scale).toBe(1)
		chip:SetAttribute("FacetFocusHeight", 1.5)
		t.expect(template.Size.Y.Scale).toBe(1.5)
		t.expect(corner.CornerRadius).toBe(D.new(0, 1001))
		w.gui.SelectedObject = plain
		t.expect(template.Size.Y.Scale).toBe(1)
		t.expect(corner.CornerRadius.Scale).toBe(0)
		stop()
		local square = define({ kind = "ring", corner = "square", thickness = 3 })
		w, template, stop = ring(square, { preferredInput = "Gamepad" })
		w.gui.SelectedObject = chip
		t.expect(template:FindFirstChildWhichIsA("UICorner").CornerRadius).toBe(D.new(0, 0))
		t.expect(template:FindFirstChildWhichIsA("UIStroke").Thickness).toBe(3)
		stop()
		t.expect(E ~= nil).toBe(true)
	end)

	t.it(
		"draws Pixel Quest's square corner brackets, Fantasy Ornate's gold frame and a lifted ring at ten feet",
		function()
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
			t.expect(stroke.Enabled).toBe(true)
			t.expect(stroke.Thickness).toBe(4)
			t.expect(mask.Enabled).toBe(true)
			local keys = mask.Transparency.Keypoints
			t.expect(keys[1].Value == 0 and keys[3].Value == 1 and keys[#keys].Value == 0).toBe(true)
			t.expect(math.abs(keys[2].Time - 12 / 112) < 0.001).toBe(true)
			button.AbsoluteSize = w.engine.types.Vector2.new(200, 44)
			t.expect(math.abs(mask.Transparency.Keypoints[2].Time - 12 / 212) < 0.001).toBe(true)
			button.AbsoluteSize = w.engine.types.Vector2.new(100, 44)
			t.expect(template:FindFirstChildWhichIsA("UICorner").CornerRadius).toBe(w.engine.types.UDim.new(0, 0))
			t.expect(template.Size).toBe(U.new(1, 12, 1, 12))
			distance:set("ten-foot")
			t.expect(stroke.Thickness).toBe(6)
			t.expect(template.Size).toBe(U.new(1, 24, 1, 24))
			t.expect(template.Position).toBe(U.fromOffset(-12, -12))
			stop()
			local ornate = require("../examples/themes/fantasy_ornate").build(Facet.themes)
			local _, framed, stopFramed = ring(ornate, { preferredInput = "Gamepad" })
			t.expect(framed.ImageTransparency).toBe(0)
			t.expect(framed.Image).toBe(ornate.assets.ornate_panel_frame.content)
			t.expect(framed.SliceScale < 1).toBe(true)
			t.expect(framed:FindFirstChildWhichIsA("UICorner").CornerRadius).toBe(w.engine.types.UDim.new(0, 0))
			stopFramed()
		end
	)

	t.it("pulses a theme that asks for it with an engine tween, only while shown and never under reduced motion", function()
		local package = define({ kind = "ring", pulse = true })
		local motionOff = Compose.cell(false)
		local created = {}
		local tweens = {
			Create = function(_, instance, info, goal)
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
			reducedMotion = motionOff,
			environment = { preferredInput = "Gamepad" },
		})
		local playerGui = w.engine.new("PlayerGui")
		local stop = owned(w.runtime, function()
			w.UI.focusRing(playerGui)
		end)
		local stroke = playerGui.SelectionImageObject:FindFirstChildWhichIsA("UIStroke")
		t.expect(stroke.Transparency).toBe(0)
		t.expect(#created).toBe(1)
		local tween = created[1]
		t.expect(tween.instance.ClassName).toBe("NumberValue")
		t.expect(tween.played).toBe(1)
		t.expect(tween.goal.Value).toBe(1)
		t.expect(tween.info.RepeatCount).toBe(-1)
		t.expect(tween.info.Reverses).toBe(true)
		tween.instance.Value = 0.5
		t.expect(math.abs(stroke.Transparency - 0.175) < 1e-6).toBe(true)
		motionOff:set(true)
		t.expect(tween.cancelled).toBe(1)
		t.expect(stroke.Transparency).toBe(0)
		t.expect(w.engine.heartbeat.count()).toBe(0)
		stop()
		w.stop()
	end)

	t.it("keeps the next control in reach: a keyboard or pad selection scrolls one row of room into view", function()
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
		t.expect(list.CanvasPosition.Y).toBe(38)
		stop()
	end)

	t.it("never scrolls a tall selection out of view to make room around it", function()
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
		t.expect(top >= 0 and top + 160 <= 200).toBe(true)
		stop()
	end)

	t.it("shares the one engine selection object among apps and gives back what was there before", function()
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
		t.expect(first ~= own and second ~= own).toBe(true)
		stopB()
		t.expect(playerGui.SelectionImageObject).toBe(first)
		stopA()
		t.expect(playerGui.SelectionImageObject).toBe(own)
		w.stop()
	end)

	t.it("an app with focusRing = false leaves a game's own selection object alone", function()
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
			t.expect(`{wanted} {playerGui.SelectionImageObject == own}`).toBe(`{wanted} {not wanted}`)
			stop()
			t.expect(playerGui.SelectionImageObject).toBe(own)
		end
	end)

	t.it("colours the focus look from the theme's focus role", function()
		local ornate = require("../examples/themes/fantasy_parchment").build(Facet.themes)
		local w = world()
		local color
		for _, package in { Facet.themes.neutralPackage(), ornate } do
			local _, sheet = w.runtime.mount(function()
				return Facet.themes.createStyleSheet(w.runtime, package, { types = w.engine.types })
			end, w.engine.new("Folder"))
			for _, node in sheet:GetChildren() do
				if node.Selector == ".facet-focus-ring" then
					color = node:GetProperties().BackgroundColor3
				end
			end
			if package == ornate then
				t.expect(color).toBe(w.engine.types.Color3.fromRGB(214, 154, 46))
			else
				local accent = package.style.themes[1].colors.accent
				t.expect(color).toBe(w.engine.types.Color3.new(accent.r, accent.g, accent.b))
			end
		end
		w.stop()
	end)
end)
