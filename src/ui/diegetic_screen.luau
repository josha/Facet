--!strict
local Types = require("./types")
local Core = require("../vendor/compose/core")
local Controls = require("./control_types")
local Props = require("./diegetic_types")
local Geometry = require("./diegetic_geometry")
local Motion = require("./motion")
type Layer = { source: ScreenGui, slot: Frame, children: { Instance } }
return function(ctx: Types.Context, UI: Controls.Controls)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local D2, V2, V3, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Vector3, ctx.types.Enum
	UI.DiegeticScreen = ctx.construct("DiegeticScreen", function(spec: Props.DiegeticScreenProps): Folder
		assert(#spec.layers > 0, "DiegeticScreen.layers must contain the application ScreenGui")
		local workspace = assert(ctx.config.services.Workspace, "DiegeticScreen requires Workspace")
		local gui = assert(ctx.config.services.GuiService, "DiegeticScreen requires GuiService")
		local reduce = Motion.reduced(ctx)
		local live, attached = Compose.cell(false), Compose.cell(false)
		local goal = Compose.cell(0)
		local schedule = runtime.scheduler()
		local spring = ctx.motionSpring(spec.motion or "move")
		local progress = runtime.spring(function(use: Types.Use): number
			return use(goal)
		end, { period = spring.period, damping = spring.damping, reducedMotion = reduce })
		local camera = Compose.cell<<Camera?>>(nil)
		local surface = Compose.cell<<SurfaceGui?>>(nil)
		local ready = Compose.cell<<Types.ReadOnlyValue<boolean>?>>(nil)
		local moved, ownsCamera = false, false
		local previous: Camera? = nil
		local parked: { Camera } = {}
		local cameraStorage: Folder? = nil
		local layerOwner: Core.Owner? = nil
		local layers: { Layer } = {}
		local known: { [ScreenGui]: Layer } = {}
		local canvas = V2.new(1, 1)
		local full = ctx.types.Rect.new(0, 0, 1, 1)
		local root: Folder
		local fieldOfView = spec.fieldOfView or 48
		assert(fieldOfView > 0 and fieldOfView < 180, "DiegeticScreen.fieldOfView must be between zero and 180")
		local function ownedLayer(candidate: Instance): boolean
			if not candidate:IsA("ScreenGui") then
				return false
			end
			if table.find(spec.layers, candidate) then
				return true
			end
			local source = ctx.overlayHosts[candidate]
			return source and source:IsA("ScreenGui") and table.find(spec.layers, source) ~= nil or false
		end
		local function restore()
			if not moved then
				return
			end
			moved = false
			local screen = surface:peek()
			if screen then
				screen.Enabled = false
			end
			for _, layer in layers do
				for _, child in layer.children do
					if child.Parent == layer.slot then
						child.Parent = layer.source
					end
				end
			end
		end
		local function restoreCameras()
			ownsCamera = false
			if previous and workspace.CurrentCamera == camera:peek() then
				workspace.CurrentCamera = previous
			end
			for _, parkedCamera in parked do
				if parkedCamera.Parent == cameraStorage then
					parkedCamera.Parent = workspace
				end
			end
			table.clear(parked)
		end
		local function release()
			schedule.cancel("readiness")
			restore()
			restoreCameras()
			previous = nil
			attached:set(false)
			live:set(false)
			table.clear(layers)
			table.clear(known)
		end
		local function refuse(reason: string)
			release()
			spec.isPresented:set(false)
			if spec.onUnavailable then
				spec.onUnavailable(reason)
			end
		end
		local function addLayer(source: ScreenGui)
			if known[source] then
				return
			end
			local screen = assert(surface:peek())
			Compose.withOwner(assert(layerOwner), function()
				local area = gui:GetInsetArea(source.ScreenInsets)
				local slot = Host.Frame "LogicalCanvas" {
					Parent = Compose.static(screen),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Position = D2.fromOffset(area.Min.X - full.Min.X, area.Min.Y - full.Min.Y),
					Size = D2.fromOffset(area.Width, area.Height),
					Visible = ctx.observe.Enabled(source),
				}
				local layer: Layer = { source = source, slot = slot, children = {} }
				known[source] = layer
				table.insert(layers, layer)
				local function transfer(child: Instance)
					if moved and child.Parent == source then
						if not table.find(layer.children, child) then
							table.insert(layer.children, child)
						end
						child.Parent = slot
					end
				end
				local transfers = runtime.scheduler()
				runtime.connect(source, "ChildAdded", function(child: Instance)
					transfers.replace(child, 0, function()
						transfer(child)
					end)
				end)
				if moved then
					for _, child in source:GetChildren() do
						transfer(child)
					end
				end
			end)
			local ordered = table.clone(layers)
			table.sort(ordered, function(a: Layer, b: Layer): boolean
				if a.source.DisplayOrder ~= b.source.DisplayOrder then
					return a.source.DisplayOrder < b.source.DisplayOrder
				end
				return assert(table.find(layers, a)) < assert(table.find(layers, b))
			end)
			for index, layer in ordered do
				layer.slot.ZIndex = index
			end
		end
		local function transfer()
			schedule.cancel("readiness")
			moved = true
			for _, layer in layers do
				for _, child in layer.source:GetChildren() do
					table.insert(layer.children, child)
					child.Parent = layer.slot
				end
			end
			assert(surface:peek()).Enabled = true
			attached:set(true)
			Compose.withOwner(assert(layerOwner), function()
				local painted = runtime.settled {
					sample = function(): string
						local sizes = table.create(#layers)
						for index, layer in layers do
							sizes[index] = tostring(layer.slot.AbsoluteSize)
						end
						return table.concat(sizes, ";")
					end,
					timeout = ctx.metric("motion.restLimit"),
				}
				Compose.watch(function(use: Types.Use)
					if use(painted) and attached:peek() and spec.isPresented:peek() then
						goal:set(1)
					end
				end)
			end)
		end
		local function SessionNodes(): { Core.Node }
			layerOwner = assert(Compose.currentOwner())
			local extent = Geometry.fit(ctx.read(spec.bounds), canvas)
			local plate = Host.Part "Display" {
				Anchored = true,
				CanCollide = false,
				CanTouch = false,
				CanQuery = true,
				Transparency = 1,
				Size = V3.new(extent.X, extent.Y, 0.01),
				CFrame = function(use: Types.Use): CFrame
					local pose: CFrame = ctx.read(spec.surface, use)
					return pose * ctx.types.CFrame.new(0, 0, 0.005)
				end,
			}
			local pose = Compose.formula(function(use: Types.Use): CFrame
				local p = if reduce(use) then use(goal) else math.clamp(use(progress), 0, 1)
				local matched = Geometry.match(ctx.read(spec.surface, use), extent, fieldOfView, ctx.types.CFrame)
				return matched:Lerp(ctx.read(spec.camera, use), p)
			end)
			local worldCamera = Host.Camera "DiegeticCamera" {
				CameraType = E.CameraType.Scriptable,
				FieldOfViewMode = E.FieldOfViewMode.Vertical,
				FieldOfView = fieldOfView,
				CFrame = pose,
			}
			Compose.cleanup(assert(runtime.host.frames).onFrame(function()
				if ownsCamera and workspace.CurrentCamera == worldCamera then
					worldCamera.CameraType = E.CameraType.Scriptable
					worldCamera.CFrame = pose:peek()
				end
			end))
			local storage = Host.Folder "Cameras" { worldCamera }
			cameraStorage = storage
			local interactive = spec.interactive == true
			local returnButton = if interactive
				then nil
				else UI.Button "ReturnToScreen" {
					label = "",
					name = "Return to screen",
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 1000,
					onActivate = function()
						spec.isPresented:set(false)
					end,
				}
			local host = if interactive
				then assert(spec.layers[1].Parent, "An interactive screen needs a mounted layer")
				else root
			local screen = Host.SurfaceGui "DiegeticCanvas" {
				Parent = Compose.static(host),
				Adornee = Compose.static(plate),
				Face = E.NormalId.Front,
				SizingMode = E.SurfaceGuiSizingMode.FixedSize,
				CanvasSize = canvas,
				LightInfluence = 0,
				Enabled = false,
				ZIndexBehavior = E.ZIndexBehavior.Sibling,
				returnButton,
			}
			ctx.overlayHosts[screen] = spec.layers[1]
			surface:set(screen)
			camera:set(worldCamera)
			local settled = runtime.settled {
				ready = function(): boolean
					return workspace.CurrentCamera == worldCamera
						and worldCamera.ViewportSize.X > 1
						and worldCamera.ViewportSize.Y > 1
				end,
				sample = function(): string
					return tostring(worldCamera.ViewportSize)
				end,
			}
			local viewport = runtime.observe(worldCamera, "ViewportSize")
			local dimensions: Vector2? = nil
			Compose.watch(function(use: Types.Use)
				use(viewport)
				local current = worldCamera.ViewportSize
				if not attached:peek() then
					dimensions = current
				elseif dimensions and current ~= dimensions then
					refuse("The viewport changed; enter the room again")
				end
			end)
			ready:set(settled)
			Compose.cleanup(function()
				ctx.overlayHosts[screen] = nil
				restoreCameras()
				ready:set(nil)
				surface:set(nil)
				camera:set(nil)
				layerOwner = nil
				cameraStorage = nil
			end)
			return { storage, plate }
		end
		local function SceneNodes(): { Core.Node }
			return { spec.scene() }
		end
		local function Session(): Folder
			return Host.Folder "OwnedSession" { Compose.portal(workspace, SessionNodes) }
		end
		local function Scene(): Folder
			return Host.Folder "OwnedWorld" { Compose.portal(workspace, SceneNodes), Compose.show(live, Session) }
		end
		local retained = spec.retainScene == true
		local built = Compose.formula(function(use: Types.Use): boolean
			return retained or use(live)
		end)
		root = Host.Folder "DiegeticScreen" { Compose.show(built, Scene) }
		Compose.watch(function(use: Types.Use)
			if not use(spec.isPresented) then
				goal:set(0)
				if live:peek() and not attached:peek() then
					release()
				end
				return
			end
			if live:peek() then
				if attached:peek() then
					goal:set(1)
				end
				return
			end
			local input = ctx.config.services.UserInputService
			if input and input.VREnabled then
				refuse("The spatial transition is not available in VR yet")
				return
			end
			previous = workspace.CurrentCamera
			if not previous then
				refuse("The current camera is unavailable")
				return
			end
			full = gui:GetInsetArea(E.ScreenInsets.None)
			canvas = V2.new(full.Width, full.Height)
			if canvas.X <= 1 or canvas.Y <= 1 then
				refuse("The viewport is not ready")
				return
			end
			live:set(true)
			schedule.replace("readiness", ctx.metric("motion.restLimit"), function()
				if live:peek() and not attached:peek() then
					refuse("The spatial viewport did not become ready")
				end
			end)
		end)
		Compose.watch(function(use: Types.Use)
			local worldCamera = use(camera)
			local settled = use(ready)
			if not use(live) or not worldCamera or not settled or attached:peek() then
				return
			end
			if not ownsCamera then
				local storage = assert(cameraStorage)
				for _, child in workspace:GetChildren() do
					if child:IsA("Camera") then
						table.insert(parked, child)
						child.Parent = storage
					end
				end
				ownsCamera = true
			end
			workspace.CurrentCamera = worldCamera
			if not use(settled) then
				return
			end
			for _, layer in spec.layers do
				addLayer(layer)
			end
			local related: { ScreenGui } = {}
			for candidate in ctx.overlayHosts do
				if ownedLayer(candidate) and candidate:IsA("ScreenGui") then
					table.insert(related, candidate)
				end
			end
			for _, layer in related do
				addLayer(layer)
			end
			local parents: { [Instance]: boolean } = {}
			for _, layer in spec.layers do
				local parent = layer.Parent
				if parent and not parents[parent] then
					parents[parent] = true
					Compose.withOwner(assert(layerOwner), function()
						runtime.connect(parent, "ChildAdded", function(candidate: Instance)
							if candidate:IsA("ScreenGui") then
								schedule.after(0, function()
									if moved and ownedLayer(candidate) then
										addLayer(candidate)
									end
								end)
							end
						end)
					end)
				end
			end
			transfer()
		end)
		Compose.watch(function(use: Types.Use)
			local p = if reduce(use) then use(goal) else use(progress)
			root:SetAttribute("FacetDiegeticProgress", p)
			if not use(spec.isPresented) and use(attached) and p == 0 then
				release()
			end
		end)
		local currentCamera = runtime.observe(workspace, "CurrentCamera")
		Compose.watch(function(use: Types.Use)
			local current = use(currentCamera)
			if ownsCamera and current ~= camera:peek() then
				refuse("The camera owner changed")
			end
		end)
		Compose.cleanup(release)
		return root
	end)
end
