--!strict
local Verify = require("../tools/vendor/verify/src/core")
return function(harness: Verify.Harness)
	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local Geometry = require("../src/ui/diegetic_geometry")
	local function fixture(vr: boolean?, interactive: boolean?)
		local engine, bridge = engines.new()
		local tracking = bridge.track()
		local types = engine.types
		local gui = engine.new("GuiService")
		gui.GetInsetArea = function(_self: GuiService, inset: Enum.ScreenInsets): Rect
			return if inset == types.Enum.ScreenInsets.None
				then types.Rect.new(0, -58, 1280, 662)
				else types.Rect.new(0, 0, 1280, 662)
		end
		local input = engine.new("UserInputService")
		engine.environment.poke(input, "VREnabled", vr == true)
		input.GetFocusedTextBox = function(): nil
			return nil
		end
		local workspace = engine.new("Workspace")
		local original = engine.new("Camera")
		original.Parent = workspace
		engine.environment.poke(original, "ViewportSize", types.Vector2.new(1280, 720))
		workspace.CurrentCamera = original
		local otherCamera = engine.new("Camera")
		otherCamera.Parent = workspace
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			for _, child in workspace:GetChildren() do
				if child:IsA("Camera") and child ~= workspace.CurrentCamera then
					engine.destroy(child)
				end
			end
		end)
		local runtime = Facet.Roblox.createRuntime(engine)
		local Host = Facet.host(runtime)
		local UI = Facet.controls(
			runtime,
			{ types = types, services = { Workspace = workspace, GuiService = gui, UserInputService = input } }
		)
		local presented = Facet.Compose.cell(false)
		local counter = Facet.Compose.cell("Same live content")
		local scenes = 0
		local target = engine.new("PlayerGui")
		local mounted: Folder? = nil
		local function Room(): Model
			scenes += 1
			return Host.Model "Room" { Host.Part "Table" { Anchored = true } }
		end
		local function Application(): Folder
			local content = UI.Text "Counter" { text = counter }
			local backing = Host.ScreenGui "Backdrop" {
				ScreenInsets = types.Enum.ScreenInsets.None,
				DisplayOrder = -1,
				Host.Frame "Gradient" { Size = types.UDim2.fromScale(1, 1) },
			}
			local screen =
				Host.ScreenGui "Application" { ScreenInsets = types.Enum.ScreenInsets.CoreUISafeInsets, content }
			local root = Host.Folder "Root" {
				screen,
				backing,
				UI.DiegeticScreen "Presentation" {
					layers = { screen, backing },
					isPresented = presented,
					scene = Room,
					surface = types.CFrame.new(),
					bounds = types.Vector2.new(3, 2),
					camera = types.CFrame.new(0, 4, 10),
					interactive = interactive,
				},
			}
			mounted = root
			return root
		end
		local stop = runtime.mount(Application, target)
		local root = assert(mounted)
		local function step(frames: number)
			local current = workspace.CurrentCamera
			if current then
				engine.environment.poke(current, "ViewportSize", types.Vector2.new(1280, 720))
			end
			for _ = 1, frames do
				engine.heartbeat:Fire(1 / 60)
			end
		end
		local function close()
			stop()
			runtime:dispose()
			for _, instance in tracking.created do
				engine.destroy(instance)
			end
			tracking.stop()
			Verify.expect(engine.census().connections):toBe(0)
		end
		return {
			root = root,
			engine = engine,
			types = types,
			workspace = workspace,
			original = original,
			otherCamera = otherCamera,
			presented = presented,
			counter = counter,
			step = step,
			close = close,
			scenes = function(): number
				return scenes
			end,
		}
	end
	harness:case(
		"DiegeticScreen moves the same live content and restores its original camera and host",
		function(context)
			local world = fixture()
			context:defer(world.close)
			local app = assert(world.root:FindFirstChild("Application"))
			local content = assert(app:FindFirstChild("Counter"))
			assert(content:IsA("TextLabel"))
			world.presented:set(true)
			world.step(120)
			local display = assert(world.root:FindFirstChild("DiegeticCanvas", true))
			Verify.expect(content:IsDescendantOf(display)):toBe(true)
			Verify.expect(app:FindFirstChild("Counter")):toBe(nil)
			Verify.expect(world.scenes()):toBe(1)
			Verify.expect(world.original:IsDescendantOf(world.workspace)):toBe(true)
			Verify.expect(world.otherCamera:IsDescendantOf(world.workspace)):toBe(true)
			world.counter:set("Updated while on the tablet")
			Verify.expect(content.Text):toBe("Updated while on the tablet")
			world.presented:set(false)
			world.step(240)
			Verify.expect(content.Parent):toBe(app)
			Verify.expect(world.workspace.CurrentCamera):toBe(world.original)
			Verify.expect(world.original.Parent):toBe(world.workspace)
			Verify.expect(world.otherCamera.Parent):toBe(world.workspace)
			Verify.expect(world.root:FindFirstChild("DiegeticCanvas", true)):toBe(nil)
			world.presented:set(true)
			world.step(120)
			world.presented:set(false)
			world.step(240)
			Verify.expect(content.Parent):toBe(app)
			Verify.expect(world.scenes()):toBe(2)
		end
	)
	harness:case("An interactive DiegeticScreen leaves surface presses to the live app", function(context)
		local world = fixture(nil, true)
		context:defer(world.close)
		local app = assert(world.root:FindFirstChild("Application"))
		world.presented:set(true)
		world.step(120)
		local display = assert(world.root:FindFirstChild("DiegeticCanvas", true))
		Verify.expect(display.Parent):toBe(app.Parent)
		Verify.expect(display:FindFirstChild("ReturnToScreen", true)):toBe(nil)
		Verify.expect(world.presented:peek()):toBe(true)
		world.presented:set(false)
		world.step(240)
		Verify.expect(world.root:FindFirstChild("DiegeticCanvas", true)):toBe(nil)
		Verify.expect(world.workspace.CurrentCamera):toBe(world.original)
	end)
	harness:case("DiegeticScreen reverses from its current pose without replacing content", function(context)
		local world = fixture()
		context:defer(world.close)
		world.presented:set(true)
		world.step(10)
		local camera = world.workspace.CurrentCamera
		local before = camera.CFrame
		world.presented:set(false)
		Verify.expect(camera.CFrame):toBe(before)
		world.step(3)
		local reversed = camera.CFrame
		world.presented:set(true)
		Verify.expect(camera.CFrame):toBe(reversed)
		world.step(120)
		Verify.expect(world.scenes()):toBe(1)
	end)
	harness:case("DiegeticScreen paints its matched host before starting the departure spring", function(context)
		local world = fixture()
		context:defer(world.close)
		world.presented:set(true)
		world.step(2)
		local camera = world.workspace.CurrentCamera
		local matched = camera.CFrame
		world.engine.heartbeat:Fire(0.6)
		Verify.expect(camera.CFrame):toBe(matched)
		world.step(1)
		Verify.expect(camera.CFrame == matched):toBe(false)
	end)
	harness:case("DiegeticScreen preserves each safe canvas and adopts later source children", function(context)
		local world = fixture()
		context:defer(world.close)
		local app = assert(world.root:FindFirstChild("Application"))
		local backing = assert(world.root:FindFirstChild("Backdrop"))
		local gradient = assert(backing:FindFirstChild("Gradient"))
		world.presented:set(true)
		world.step(120)
		local content = assert(world.root:FindFirstChild("Counter", true))
		local safeCanvas = assert(content.Parent)
		local fullCanvas = assert(gradient.Parent)
		assert(safeCanvas:IsA("Frame") and fullCanvas:IsA("Frame"))
		Verify.expect(safeCanvas.Position.Y.Offset):toBe(58)
		Verify.expect(safeCanvas.Size.Y.Offset):toBe(662)
		Verify.expect(fullCanvas.Position.Y.Offset):toBe(0)
		Verify.expect(fullCanvas.Size.Y.Offset):toBe(720)
		Verify.expect(fullCanvas.ZIndex < safeCanvas.ZIndex):toBe(true)
		local later = world.engine.new("Frame")
		later.Parent = app
		Verify.expect(later.Parent):toBe(app)
		world.step(1)
		Verify.expect(later.Parent):toBe(content.Parent)
		world.presented:set(false)
		world.step(240)
		Verify.expect(later.Parent):toBe(app)
		Verify.expect(gradient.Parent):toBe(backing)
	end)
	harness:case("DiegeticScreen releases a cancelled preparation", function(context)
		local world = fixture()
		context:defer(world.close)
		world.presented:set(true)
		world.presented:set(false)
		Verify.expect(world.workspace.CurrentCamera):toBe(world.original)
		Verify.expect(world.root:FindFirstChild("DiegeticCanvas", true)):toBe(nil)
	end)
	harness:case("DiegeticScreen returns content without replacing another camera owner", function(context)
		local world = fixture()
		context:defer(world.close)
		local app = assert(world.root:FindFirstChild("Application"))
		local content = assert(app:FindFirstChild("Counter"))
		world.presented:set(true)
		world.step(120)
		local replacement = world.engine.new("Camera")
		replacement.Parent = world.workspace
		world.workspace.CurrentCamera = replacement
		Verify.expect(world.presented:peek()):toBe(false)
		Verify.expect(content.Parent):toBe(app)
		Verify.expect(world.workspace.CurrentCamera):toBe(replacement)
	end)
	harness:case("DiegeticScreen returns to its screen when the viewport changes", function(context)
		local world = fixture()
		context:defer(world.close)
		world.presented:set(true)
		world.step(120)
		world.engine.environment.poke(world.workspace.CurrentCamera, "ViewportSize", world.types.Vector2.new(720, 1280))
		Verify.expect(world.presented:peek()):toBe(false)
		Verify.expect(world.workspace.CurrentCamera):toBe(world.original)
	end)
	harness:case("DiegeticScreen keeps the screen available when VR comfort support is unavailable", function(context)
		local world = fixture(true)
		context:defer(world.close)
		world.presented:set(true)
		world.step(10)
		Verify.expect(world.presented:peek()):toBe(false)
		Verify.expect(world.scenes()):toBe(0)
		Verify.expect(world.workspace.CurrentCamera):toBe(world.original)
	end)
	harness:case("DiegeticScreen fits a fixed logical canvas within the tablet bounds", function()
		local engine = engines.new()
		local v = engine.types.Vector2
		local wide = Geometry.fit(v.new(3, 2), v.new(1920, 1080))
		Verify.expect(wide.X):toBe(3)
		Verify.expect(wide.Y):toBe(1.6875)
		local portrait = Geometry.fit(v.new(3, 2), v.new(390, 844))
		Verify.expect(portrait.Y):toBe(2)
		Verify.expect(math.abs(portrait.X / portrait.Y - 390 / 844) < 1e-6):toBe(true)
	end)
end
