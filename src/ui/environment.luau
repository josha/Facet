--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Env = require("./environment_types")
local adaptive = require("./adaptive")
local motion = require("./motion")
local freeze = require("./freeze")

type Point = { X: number, Y: number, Z: number }
type Projector = {
	CFrame: CFrame,
	ViewportSize: Vector2,
	NearPlaneZ: number,
	WorldToViewportPoint: (Projector, Vector3) -> Point,
}
type Hit = { Instance: Instance }
type Scene = { CurrentCamera: Projector?, Raycast: (Scene, Vector3, Vector3) -> Hit? }
type Hook = { Disconnect: (Hook) -> () }
type Frames = { Heartbeat: { Connect: (unknown, () -> ()) -> Hook } }

local ANCHOR_KEYS = { target = true, padding = true, offscreen = true, occlusion = true, camera = true }

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function enumName(value: unknown, fallback: string): string
	if typeof(value) == "EnumItem" then
		return (value :: EnumItem).Name
	end
	return fallback
end

return function(ctx: Shared.Context, UI: Env.EnvironmentControls)
	local Compose = ctx.Compose
	local config = ctx.config
	local V2 = ctx.types.Vector2

	local function watched(node: Instance?, property: string, fallback: unknown): ComposeTypes.Readable<unknown>
		if node ~= nil then
			local observers = (ctx.observe :: unknown) :: { [string]: (Instance) -> ComposeTypes.Readable<unknown> }
			local ok, value = pcall(observers[property], node)
			if ok then
				return value
			end
		end
		return Compose.cell(fallback)
	end

	local function scene(): Instance?
		local services = (config.services :: unknown) :: { Workspace: Instance? }
		return services.Workspace
	end

	UI.environment = function(source: Env.EnvironmentSource?): Env.Environment
		assert(Compose.currentOwner() ~= nil, "Facet UI.environment must run inside a component or Compose owner")
		local node: Instance? = source
		if node == nil then
			local world = scene()
			node = if world then ((world :: unknown) :: { CurrentCamera: Instance? }).CurrentCamera else nil
		end
		local property = if node and node:IsA("GuiBase2d") then "AbsoluteSize" else "ViewportSize"
		local raw = watched(node, property, V2.zero)
		local last: Vector2 = V2.zero
		local viewportSize: ComposeTypes.Readable<Vector2> = Compose.formula(function(use: ComposeTypes.Use): Vector2
			local size = use(raw)
			if typeof(size) == "Vector2" and size.X >= 2 and size.Y >= 2 then
				last = size
			end
			return last
		end)
		local function derived<T>(body: (ComposeTypes.Use) -> T): ComposeTypes.Readable<T>
			return Compose.formula(body)
		end
		local viewportWidth = derived(function(use): number
			return use(viewportSize).X
		end)
		local viewportHeight = derived(function(use): number
			return use(viewportSize).Y
		end)
		local sizeClass = (
			derived(function(use): Env.SizeClass
				return adaptive.sizeClass(use(viewportWidth))
			end) :: unknown
		) :: ComposeTypes.Readable<Env.SizeClass>
		local heightClass = (
			derived(function(use): Env.HeightClass
				return adaptive.heightClass(use(viewportHeight))
			end) :: unknown
		) :: ComposeTypes.Readable<Env.HeightClass>
		local function atLeast(target: Env.SizeClass): ComposeTypes.Readable<boolean>
			local wanted: Env.SizeClass = target
			assert(
				target == "compact" or target == "regular" or target == "wide",
				"Facet environment.atLeast expects compact, regular or wide"
			)
			return derived(function(use): boolean
				local current = (use(sizeClass) :: unknown) :: Env.SizeClass
				return adaptive.sizeClassAtLeast(current, wanted)
			end)
		end
		local gui = config.guiService
		local input = config.userInputService
		local preferred = watched(input, "PreferredInput", nil)
		local mouse = watched(input, "MouseEnabled", false)
		local touch = watched(input, "TouchEnabled", false)
		local gamepad = watched(input, "GamepadEnabled", false)
		local keyboard = watched(input, "KeyboardEnabled", false)
		local interactionClasses = derived(function(use): Env.InteractionClasses
			local classes: Env.InteractionClasses = {
				primary = "pointer",
				pointer = use(mouse) == true,
				touch = use(touch) == true,
				gamepad = use(gamepad) == true,
				keyboard = use(keyboard) == true,
			}
			local report = enumName(use(preferred), "")
			if report == "Touch" then
				classes.primary = "touch"
			elseif report == "Gamepad" then
				classes.primary = "gamepad"
			elseif not classes.pointer and classes.touch then
				classes.primary = "touch"
			elseif not classes.pointer and classes.gamepad then
				classes.primary = "gamepad"
			end
			if classes.primary == "pointer" then
				classes.pointer = true
			elseif classes.primary == "touch" then
				classes.touch = true
			else
				classes.gamepad = true
			end
			return freeze(classes)
		end)
		local effectiveInput = (
			derived(function(use): "Touch" | "Gamepad" | "KeyboardAndMouse"
				local primary = use(interactionClasses).primary
				return if primary == "touch"
					then "Touch"
					elseif primary == "gamepad" then "Gamepad"
					else "KeyboardAndMouse"
			end) :: unknown
		) :: ComposeTypes.Readable<"Touch" | "Gamepad" | "KeyboardAndMouse">
		local displayRaw = watched(gui, "ViewportDisplaySize", nil)
		local displaySize = (
			derived(function(use): Env.DisplaySize
				local name = enumName(use(displayRaw), "Medium")
				return if name == "Small" or name == "Large" then name else "Medium"
			end) :: unknown
		) :: ComposeTypes.Readable<Env.DisplaySize>
		local textRaw = watched(gui, "PreferredTextSize", nil)
		local preferredTextSize = derived(function(use): string
			return enumName(use(textRaw), "Medium")
		end)
		local topbar = watched(gui, "TopbarInset", nil)
		local safeInsets = derived(function(use): Env.SafeInsets
			use(viewportSize)
			use(topbar)
			local insets: Env.SafeInsets = { top = 0, left = 0, bottom = 0, right = 0 }
			if gui then
				local ok, topLeft, bottomRight = pcall(function()
					return gui:GetGuiInset()
				end)
				if ok and typeof(topLeft) == "Vector2" and typeof(bottomRight) == "Vector2" then
					insets = { top = topLeft.Y, left = topLeft.X, bottom = bottomRight.Y, right = bottomRight.X }
				end
			end
			return freeze(insets)
		end)
		local reduced = motion(ctx)
		local environment: Env.Environment = freeze({
			viewportSize = viewportSize,
			viewportWidth = viewportWidth,
			viewportHeight = viewportHeight,
			sizeClass = sizeClass,
			heightClass = heightClass,
			orientation = (derived(function(use): Env.Orientation
				local size = use(viewportSize)
				return adaptive.orientationFor(size.X, size.Y)
			end) :: unknown) :: ComposeTypes.Readable<Env.Orientation>,
			isCompact = derived(function(use): boolean
				return use(sizeClass) == "compact"
			end),
			isRegular = derived(function(use): boolean
				return use(sizeClass) == "regular"
			end),
			isWide = derived(function(use): boolean
				return use(sizeClass) == "wide"
			end),
			isRegularOrWider = atLeast("regular"),
			isShort = derived(function(use): boolean
				return use(heightClass) == "short"
			end),
			isTall = derived(function(use): boolean
				return use(heightClass) == "tall"
			end),
			isLandscape = derived(function(use): boolean
				local size = use(viewportSize)
				return size.X > size.Y
			end),
			axis = (derived(function(use): "x" | "y"
				return adaptive.axisFor(use(viewportWidth))
			end) :: unknown) :: ComposeTypes.Readable<"x" | "y">,
			atLeast = atLeast,
			interactionClasses = interactionClasses,
			effectiveInput = effectiveInput,
			displaySize = displaySize,
			safeInsets = safeInsets,
			preferredTextSize = preferredTextSize,
			reducedMotion = derived(function(use): boolean
				return reduced(use)
			end),
		})
		return environment
	end

	UI.worldAnchor = function(options: Env.WorldAnchorOptions): Env.WorldAnchor
		assert(type(options) == "table", "Facet UI.worldAnchor expects an options table")
		for key in (options :: unknown) :: { [unknown]: unknown } do
			assert(ANCHOR_KEYS[key :: string] == true, `Facet UI.worldAnchor: unknown option '{tostring(key)}'`)
		end
		assert(options.target ~= nil, "Facet UI.worldAnchor: target is required")
		local padding = if options.padding == nil then 0.15 else options.padding
		assert(
			finite(padding) and padding >= 0 and padding <= 1,
			"Facet UI.worldAnchor: padding must be a fraction from 0 to 1"
		)
		assert(
			options.offscreen == nil or options.offscreen == "hide" or options.offscreen == "retain",
			"Facet UI.worldAnchor: offscreen must be hide or retain"
		)
		assert(
			options.occlusion == nil or type(options.occlusion) == "boolean",
			"Facet UI.worldAnchor: occlusion must be a boolean"
		)
		local world = (scene() :: unknown) :: Scene?
		local function sample(): Env.WorldAnchorPoint
			local found = (ctx.read(options.target) :: unknown) :: Instance?
			local chosen = (ctx.read(options.camera) :: unknown) :: Projector?
			local camera = chosen or (if world then world.CurrentCamera else nil)
			if found == nil or camera == nil or world == nil then
				return { visible = false }
			end
			assert(
				found:IsA("BasePart") or found:IsA("Model") or found:IsA("Player"),
				"Facet UI.worldAnchor: target must be a BasePart, Model or Player"
			)
			local target: Instance? = if found:IsA("Player") then (found :: Player).Character else found
			if target == nil or not target:IsDescendantOf((world :: unknown) :: Instance) then
				return { visible = false }
			end
			local frame: CFrame, size: Vector3
			if target:IsA("Model") then
				if not target:FindFirstChildWhichIsA("BasePart", true) then
					return { visible = false }
				end
				frame, size = (target :: Model):GetBoundingBox()
			else
				frame, size = (target :: BasePart).CFrame, (target :: BasePart).Size
			end
			if options.occlusion then
				local origin = camera.CFrame.Position
				local hit = world:Raycast(origin, frame.Position - origin)
				if hit and hit.Instance ~= target and not hit.Instance:IsDescendantOf(target) then
					return { visible = false, occluded = true }
				end
			end
			local near = math.abs(camera.NearPlaneZ)
			local view = camera.ViewportSize
			if options.offscreen == "retain" then
				local point = camera:WorldToViewportPoint(frame.Position)
				if not finite(point.X) or not finite(point.Y) or not finite(point.Z) then
					return { visible = false }
				end
				local x, y = point.X, point.Y
				local onscreen = point.Z > near and x >= 0 and y >= 0 and x <= view.X and y <= view.Y
				if point.Z <= 0 then
					local dx, dy = view.X / 2 - x, view.Y / 2 - y
					local length = math.sqrt(dx * dx + dy * dy)
					if length < 0.001 then
						dx, dy, length = 0, 1, 1
					end
					local reach = math.max(view.X, view.Y) * 2
					x, y = view.X / 2 + dx / length * reach, view.Y / 2 + dy / length * reach
				end
				return { x = x, y = y, visible = true, onscreen = onscreen, clearance = 0 }
			end
			local points: { Point } = {}
			local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = frame.Position
							+ frame.RightVector * (size.X * sx / 2)
							+ frame.UpVector * (size.Y * sy / 2)
							+ frame.LookVector * (size.Z * sz / 2)
						local p = camera:WorldToViewportPoint(corner)
						if not finite(p.X) or not finite(p.Y) or not finite(p.Z) or p.Z <= near then
							return { visible = false }
						end
						minX = math.min(minX, p.X)
						minY = math.min(minY, p.Y)
						maxX = math.max(maxX, p.X)
						maxY = math.max(maxY, p.Y)
						table.insert(points, p)
					end
				end
			end
			local x, y = (minX + maxX) / 2, (minY + maxY) / 2
			if x < 0 or y < 0 or x > view.X or y > view.Y then
				return { visible = false }
			end
			local radius = 0
			for _, p in points do
				radius = math.max(radius, math.sqrt((p.X - x) ^ 2 + (p.Y - y) ^ 2))
			end
			return { x = x, y = y, clearance = radius * (1 + padding), visible = true }
		end
		local anchor = Compose.cell(sample())
		local frames = (config.services.RunService :: unknown) :: Frames?
		local hook: Hook? = nil
		if frames then
			hook = frames.Heartbeat:Connect(function()
				local ok, fresh = pcall(sample)
				local nextValue: Env.WorldAnchorPoint = if ok then fresh else { visible = false }
				local old = anchor:peek()
				if
					old.visible ~= nextValue.visible
					or old.x ~= nextValue.x
					or old.y ~= nextValue.y
					or old.clearance ~= nextValue.clearance
					or old.onscreen ~= nextValue.onscreen
					or old.occluded ~= nextValue.occluded
				then
					anchor:set(nextValue)
				end
			end)
		end
		local disposed = false
		local function dispose()
			if disposed then
				return
			end
			disposed = true
			if hook then
				hook:Disconnect()
				hook = nil
			end
			anchor:set({ visible = false })
		end
		if Compose.currentOwner() then
			Compose.cleanup(dispose)
		end
		return freeze({ anchor = anchor, dispose = dispose })
	end
end
