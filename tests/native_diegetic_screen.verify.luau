--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Roblox = require("../tools/vendor/verify/src/roblox")
return function(harness: Verify.Harness)
	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local Geometry = require("../src/ui/diegetic_geometry")
	local function fixture(vr: boolean?, interactive: boolean?, rigged: boolean?, retainScene: boolean?)
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
		local runtime = Facet.Roblox.createRuntime(bridge.engine)
		local Host = Facet.host(runtime)
		local UI = Facet.controls(
			runtime,
			{ types = types, services = { Workspace = workspace, GuiService = gui, UserInputService = input } }
		)
		local presented = Facet.Compose.cell(false)
		local counter = Facet.Compose.cell("Same live content")
		local scenes = 0
		local target = engine.new("PlayerGui")
		local hits: { GuiObject } = {}
		input.GetMouseLocation = function(): Vector2
			return types.Vector2.new(30, 30)
		end
		target.GetGuiObjectsAtPosition = function(): { GuiObject }
			return hits
		end
		local mounted: Folder? = nil
		local presentation: Folder? = nil
		local rig: Facet.CameraRig? = nil
		local function Room(): Model
			scenes += 1
			return Host.Model "Room" { Host.Part "Table" { Anchored = true } }
		end
		local function Application(): Folder
			if rigged then
				rig = UI.cameraRig {
					inputRoot = target,
					initial = { focus = types.Vector3.zero, yaw = 0, pitch = 0, distance = 10 },
					focusBounds = { min = types.Vector3.new(-2, -2, -2), max = types.Vector3.new(2, 2, 2) },
					distanceBounds = types.Vector2.new(2, 20),
					enabled = presented,
				}
			end
			local content = UI.Text "Counter" { text = counter }
			local backing = Host.ScreenGui "Backdrop" {
				ScreenInsets = types.Enum.ScreenInsets.None,
				DisplayOrder = -1,
				Host.Frame "Gradient" { Size = types.UDim2.fromScale(1, 1) },
			}
			local screen =
				Host.ScreenGui "Application" { ScreenInsets = types.Enum.ScreenInsets.CoreUISafeInsets, content }
			local display = UI.DiegeticScreen "Presentation" {
				layers = { screen, backing },
				isPresented = presented,
				scene = Room,
				surface = types.CFrame.new(),
				bounds = types.Vector2.new(3, 2),
				camera = if rig then rig.camera else types.CFrame.new(0, 4, 10),
				interactive = interactive,
				retainScene = retainScene,
			}
			presentation = display
			local root = Host.Folder "Root" {
				screen,
				backing,
				display,
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
			input = input,
			hits = hits,
			original = original,
			otherCamera = otherCamera,
			presented = presented,
			counter = counter,
			rig = rig,
			step = step,
			close = close,
			scenes = function(): number
				return scenes
			end,
			progress = function(): unknown
				return assert(presentation):GetAttribute("FacetDiegeticProgress")
			end,
		}
	end
	harness:case("DiegeticScreen keeps its settled room camera Scriptable and follows the camera input", function(t)
		local world = fixture(nil, true, true)
		t:defer(world.close)
		world.presented:set(true)
		world.step(120)
		local camera = world.workspace.CurrentCamera
		local rig = assert(world.rig)
		Verify.expect(camera.CFrame):toBe(rig.camera:peek())
		Verify.expect(camera.CameraType):toBe(world.types.Enum.CameraType.Scriptable)
		camera.CameraType = world.types.Enum.CameraType.Fixed
		camera.CFrame = world.types.CFrame.new(0, 2.5, 2.45)
		world.step(1)
		Verify.expect(world.workspace.CurrentCamera):toBe(camera)
		Verify.expect(camera.CameraType):toBe(world.types.Enum.CameraType.Scriptable)
		Verify.expect(camera.CFrame):toBe(rig.camera:peek())
		rig.focus:set(world.types.Vector3.new(1, 1, 1))
		world.step(120)
		Verify.expect(camera.CFrame):toBe(rig.camera:peek())
	end)
	harness:case("DiegeticScreen lets wheel input zoom over empty room and yields over the app surface", function(t)
		local world = fixture(nil, true, true)
		t:defer(world.close)
		world.presented:set(true)
		world.step(120)
		local rig = assert(world.rig)
		local wheel = world.engine.new("InputObject")
		world.engine.environment.poke(wheel, "UserInputType", world.types.Enum.UserInputType.MouseWheel)
		world.engine.environment.poke(wheel, "Position", world.types.Vector3.new(0, 0, 1))
		world.engine.environment.fire(Roblox.assertInstance(world.input), "InputChanged", wheel, false)
		world.step(1)
		Verify.expect(rig.state:peek().distance):toBe(2)
		Verify.expect(world.workspace.CurrentCamera.CFrame):toBe(rig.camera:peek())
		local content = assert(world.root:FindFirstChild("Counter", true))
		assert(content:IsA("TextLabel"))
		Verify.expect(content.Active):toBe(false)
		table.insert(world.hits, content)
		world.engine.environment.poke(wheel, "Position", world.types.Vector3.new(0, 0, -1))
		world.engine.environment.fire(Roblox.assertInstance(world.input), "InputChanged", wheel, true)
		world.engine.environment.fire(Roblox.assertInstance(world.input), "InputChanged", wheel, false)
		world.step(1)
		Verify.expect(rig.state:peek().distance):toBe(2)
		table.clear(world.hits)
		world.engine.environment.fire(Roblox.assertInstance(world.input), "InputChanged", wheel, false)
		world.step(1)
		Verify.expect(rig.state:peek().distance):toBe(10)
	end)
	harness:case("DiegeticScreen follows a cameraRig focus without rebuilding its live scene", function(context)
		local world = fixture(nil, true, true)
		context:defer(world.close)
		world.presented:set(true)
		world.step(120)
		local camera = world.workspace.CurrentCamera
		local before = camera.CFrame
		local rig = assert(world.rig)
		rig.focus:set(world.types.Vector3.new(1, 1, 1))
		world.step(120)
		Verify.expect(camera.CFrame):toBe(rig.camera:peek())
		Verify.expect(camera.CFrame == before):toBe(false)
		Verify.expect(world.scenes()):toBe(1)
		world.presented:set(false)
		world.step(240)
		Verify.expect(world.workspace.CurrentCamera):toBe(world.original)
	end)
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
		world.step(1)
		Verify.expect(camera.CFrame == matched):toBe(false)
	end)
	for calm = 0, 1 do
		harness:case(
			`DiegeticScreen starts the entry clock after a slow frame {calm} frames after the transfer`,
			function(context)
				local world = fixture()
				context:defer(world.close)
				world.presented:set(true)
				world.step(2)
				local camera = world.workspace.CurrentCamera
				local matched = camera.CFrame
				Verify.expect(world.progress()):toBe(0)
				world.step(calm)
				world.engine.heartbeat:Fire(0.32)
				Verify.expect(camera.CFrame):toBe(matched)
				Verify.expect(world.progress()):toBe(0)
				local first = 0
				for _ = 1, 10 do
					world.step(1)
					local current = world.progress()
					assert(type(current) == "number")
					if current > 0 then
						first = current
						break
					end
				end
				Verify.expect(first > 0 and first < 0.15):toBe(true)
				world.step(240)
				Verify.expect(world.progress()):toBe(1)
			end
		)
	end
	harness:case("A DiegeticScreen with retainScene keeps one room across presentations", function(context)
		local world = fixture(nil, nil, nil, true)
		context:defer(world.close)
		Verify.expect(world.scenes()):toBe(1)
		local room = assert(world.workspace:FindFirstChild("Room", true))
		Verify.expect(world.workspace.CurrentCamera):toBe(world.original)
		world.presented:set(true)
		world.step(120)
		Verify.expect(world.progress()):toBe(1)
		world.presented:set(false)
		world.step(240)
		Verify.expect(world.workspace.CurrentCamera):toBe(world.original)
		Verify.expect(world.root:FindFirstChild("DiegeticCanvas", true)):toBe(nil)
		Verify.expect(room:IsDescendantOf(world.workspace)):toBe(true)
		world.presented:set(true)
		world.step(2)
		local camera = world.workspace.CurrentCamera
		local matched = camera.CFrame
		world.step(1)
		world.engine.heartbeat:Fire(0.32)
		Verify.expect(camera.CFrame):toBe(matched)
		world.step(120)
		Verify.expect(world.progress()):toBe(1)
		Verify.expect(world.scenes()):toBe(1)
		Verify.expect(world.workspace:FindFirstChild("Room", true)):toBe(room)
		world.presented:set(false)
		world.step(240)
		Verify.expect(room:IsDescendantOf(world.workspace)):toBe(true)
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
