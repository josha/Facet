--!strict
local Types = require("./types")
local Engine = require("./engine_types")
local ComposeTypes = require("../vendor/compose/core")
local prepareMedia = require("./media_readiness")
local ControlTypes = require("./control_types")
local MediaProps = require("./media_props")
local MediaShared = require("./media_shared")

local SETTLE_SECONDS = 0.15
local VISIBLE_FRACTION = 0.5

return function(ctx: Types.Context, UI: ControlTypes.Controls, shared: MediaShared.Shared)
	local Host, runtime, Compose = ctx.Host, ctx.runtime, ctx.Compose
	local types = ctx.types
	local D2 = types.UDim2
	local bind = shared.bind
	local frames = runtime.host.frames
	local pending: { () -> () } = {}
	local stopQueue: (() -> ())? = nil
	local function enqueue(job: () -> (), owner: ComposeTypes.Owner)
		table.insert(pending, job)
		Compose.withOwner(owner, function()
			Compose.cleanup(function()
				local index = table.find(pending, job)
				if index then
					table.remove(pending, index)
				end
				if #pending == 0 and stopQueue then
					stopQueue()
					stopQueue = nil
				end
			end)
		end)
		if stopQueue == nil and frames then
			stopQueue = frames.onFrame(function()
				local next = table.remove(pending, 1)
				if next then
					next()
				end
				if #pending == 0 and stopQueue then
					stopQueue()
					stopQueue = nil
				end
			end)
		end
	end
	local function stageLive(
		stage: ViewportFrame,
		displayed: ComposeTypes.ReadOnlyValue<boolean>
	): (ComposeTypes.ReadOnlyValue<boolean>, ComposeTypes.ReadOnlyValue<boolean>)
		local owner = assert(Compose.currentOwner())
		local moving = Compose.cell(false)
		local visible = Compose.cell(true)
		local near = Compose.cell(true)
		local position = ctx.observe.AbsolutePosition(stage)
		local size = ctx.observe.AbsoluteSize(stage)
		local current: ScrollingFrame? = nil
		local tracking: ComposeTypes.Owner? = nil
		local function track(frame: ScrollingFrame)
			local canvas = ctx.observe.CanvasPosition(frame)
			local origin = ctx.observe.AbsolutePosition(frame)
			local window = ctx.observe.AbsoluteWindowSize(frame)
			local last = canvas:peek()
			local lastMove = -math.huge
			local stopWatch: (() -> ())? = nil
			local function halt()
				if stopWatch then
					stopWatch()
					stopWatch = nil
				end
			end
			Compose.watch(function(use: ComposeTypes.Use)
				local value = use(canvas)
				local clock = frames
				if value == last or clock == nil then
					return
				end
				last = value
				lastMove = clock.now()
				moving:set(true)
				if stopWatch == nil then
					stopWatch = clock.onFrame(function()
						if clock.now() - lastMove >= SETTLE_SECONDS then
							halt()
							moving:set(false)
						end
					end)
				end
			end)
			Compose.cleanup(halt)
			Compose.watch(function(use: ComposeTypes.Use)
				local at, extent = use(position), use(size)
				local top, box = use(origin), use(window)
				if extent.X <= 0 or extent.Y <= 0 or box.X <= 0 or box.Y <= 0 then
					visible:set(false)
					near:set(false)
					return
				end
				local reachX, reachY = box.X / 2, box.Y / 2
				near:set(
					at.X + extent.X > top.X - reachX
						and at.X < top.X + box.X + reachX
						and at.Y + extent.Y > top.Y - reachY
						and at.Y < top.Y + box.Y + reachY
				)
				local width = math.min(at.X + extent.X, top.X + box.X) - math.max(at.X, top.X)
				local height = math.min(at.Y + extent.Y, top.Y + box.Y) - math.max(at.Y, top.Y)
				if width <= 0 or height <= 0 then
					visible:set(false)
					return
				end
				local shown = width * height / (extent.X * extent.Y)
				visible:set(shown >= VISIBLE_FRACTION or height >= box.Y * VISIBLE_FRACTION)
			end)
		end
		local function locate()
			if ComposeTypes.owner.isDisposed(owner) then
				return
			end
			local found: ScrollingFrame? = nil
			local at = stage.Parent
			while at do
				if at:IsA("ScrollingFrame") then
					found = at
					break
				end
				if at:IsA("LayerCollector") then
					break
				end
				at = at.Parent
			end
			if found == current and tracking ~= nil then
				return
			end
			current = found
			if tracking then
				ComposeTypes.owner.dispose(tracking)
				tracking = nil
			end
			moving:set(false)
			visible:set(true)
			near:set(true)
			if found then
				local child = ComposeTypes.owner.createChild(owner)
				tracking = child
				Compose.withOwner(child, function()
					track(found)
				end)
			end
		end
		runtime.connect(stage, "AncestryChanged", locate)
		locate()
		return Compose.formula(function(use: ComposeTypes.Use): boolean
			return use(displayed) and use(visible) and not use(moving)
		end),
			Compose.formula(function(use: ComposeTypes.Use): boolean
				return use(displayed) and use(near)
			end)
	end

	UI.Stage = ctx.construct("Stage", function(spec: MediaProps.StageProps): ViewportFrame
		local world = Host.WorldModel "World" {}
		local externalCamera = spec.camera
			and (
				typeof(spec.camera) == "Instance"
				or (
					type(spec.camera) == "table"
					and type(((spec.camera :: unknown) :: { IsA: unknown }).IsA) == "function"
					and ((spec.camera :: unknown) :: Camera):IsA("Camera")
				)
			)
		local camera = if externalCamera
			then spec.camera :: Camera
			else Host.Camera "Camera" {
				FieldOfView = bind<<number>>(spec.fieldOfView, 45),
				CFrame = (spec.camera :: Types.Input<CFrame>?)
					or types.CFrame.lookAt(types.Vector3.new(0, 2, 8), types.Vector3.new(0, 0, 0)),
			}
		local native = ctx.props(
			spec,
			{ "content", "camera", "fieldOfView", "lazy" },
			{
				Size = D2.fromOffset(240, 180),
				CurrentCamera = Compose.static(camera),
				world,
				if not externalCamera then camera else nil,
			} :: Engine.ViewportFrameNativeProps
		)
		local stage = ctx.styled(Host.ViewportFrame(native), "panel")
		local initialCamera = stage.CurrentCamera
		local cameraSource: Engine.ValueCameraOptional = if Compose.isValue(native.CurrentCamera)
				or type(native.CurrentCamera) == "function"
			then native.CurrentCamera :: Engine.ValueCameraOptional
			else function(): Camera?
				return initialCamera
			end
		local ancestry = Compose.cell(0)
		local displayed = Compose.cell(true)
		runtime.connect(stage, "AncestryChanged", function()
			ancestry:set(ancestry:peek() + 1)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(ancestry)
			local sources: { ComposeTypes.ReadOnlyValue<boolean> } = {}
			local at: Instance? = stage
			while at do
				if at:IsA("GuiObject") then
					table.insert(sources, ctx.observe.Visible(at))
				elseif at:IsA("LayerCollector") then
					table.insert(sources, ctx.observe.Enabled(at))
					break
				end
				at = at.Parent
			end
			Compose.watch(function(read: ComposeTypes.Use)
				for _, source in sources do
					if not read(source) then
						displayed:set(false)
						return
					end
				end
				displayed:set(true)
			end)
		end)
		runtime.decorate(stage, {
			CurrentCamera = function(use: ComposeTypes.Use): Camera?
				return if use(displayed) then ctx.read<<Camera?>>(cameraSource, use) else nil
			end,
		})
		local live, shown = stageLive(stage, displayed)
		stage:SetAttribute("FacetLive", live:peek())
		Compose.watch(function(use: ComposeTypes.Use)
			stage:SetAttribute("FacetLive", use(live))
		end)
		if spec.content then
			local content = spec.content
			local owner = assert(Compose.currentOwner())
			local built = false
			local function build()
				if built or ComposeTypes.owner.isDisposed(owner) then
					return
				end
				built = true
				Compose.withOwner(owner, function()
					local cleanup = content(runtime, world, live)
					if type(cleanup) == "function" then
						Compose.cleanup(cleanup)
					end
				end)
				stage:SetAttribute("FacetBuilt", true)
			end
			stage:SetAttribute("FacetBuilt", false)
			if spec.lazy ~= true or frames == nil then
				build()
			else
				local queued = false
				local function attempt()
					queued = false
					if not ComposeTypes.owner.isDisposed(owner) and shown:peek() then
						build()
					end
				end
				Compose.watch(function(use: ComposeTypes.Use)
					if use(shown) and not built and not queued then
						queued = true
						enqueue(attempt, owner)
					end
				end)
			end
		end
		if spec.LightDirection == nil then
			local frame = runtime.observe(camera, "CFrame") :: ComposeTypes.ReadOnlyValue<CFrame>
			runtime.decorate(stage, {
				LightDirection = function(use: ComposeTypes.Use): Vector3
					local look = use(frame).LookVector
					return (look + types.Vector3.new(0, -0.6, 0)).Unit
				end,
			})
		end
		prepareMedia(ctx, stage, spec.ImageTransparency)
		return stage
	end)
end
