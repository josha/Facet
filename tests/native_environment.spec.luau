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
