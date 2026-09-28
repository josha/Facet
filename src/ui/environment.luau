--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Env = require("./environment_types")
local ThemeTypes = require("./theme_types")
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

type SelectionOwner = { prior: GuiObject?, rings: { GuiObject } }
local selectionOwners: { [Instance]: SelectionOwner } = setmetatable({} :: any, { __mode = "k" })

return function(ctx: Shared.Context, UI: Env.EnvironmentControls)
	local Compose = ctx.Compose
	local config = ctx.config
	local runtime = ctx.runtime
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

	UI.focusRing = function(playerGui: PlayerGui): Frame
		assert(Compose.currentOwner() ~= nil, "Facet UI.focusRing must run inside a component or Compose owner")
		local Host, E, D, D2 = ctx.Host, ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2
		local input = (config.services :: unknown) :: { UserInputService: UserInputService? }
		local keyed = Compose.cell(false)
		local function heard(kind: Enum.UserInputType)
			keyed:set(kind == E.UserInputType.Keyboard or string.find(kind.Name, "^Gamepad") ~= nil)
		end
		local service = input.UserInputService
		if service then
			local ok, last = pcall(function()
				return service:GetLastInputType()
			end)
			if ok and last then
				heard(last)
			end
			local connection = service.LastInputTypeChanged:Connect(heard)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
		end
		local env = UI.environment()
		local far = ctx.tenFoot()
		local reduced = motion.reduced(ctx)
		local package = Compose.formula(function(use: ComposeTypes.Use): ThemeTypes.ThemePackage?
			return ctx.read(config.theme, use)
		end)
		local recipe = Compose.formula(function(use: ComposeTypes.Use): ThemeTypes.SkinLayer
			local current = use(package) :: ThemeTypes.ThemePackage?
			local chrome = if current then current.chrome else nil
			return (if chrome then chrome.focus else nil) or { kind = "ring" }
		end)
		local function layer(use: ComposeTypes.Use): ThemeTypes.SkinLayer
			return use(recipe) :: ThemeTypes.SkinLayer
		end
		local function shown(use: ComposeTypes.Use): boolean
			return use(keyed) or use(env.effectiveInput) == "Gamepad"
		end
		local function scaled(use: ComposeTypes.Use, value: number, factor: number): number
			return if far(use) then math.round(value * factor) else value
		end
		local pulse = Compose.cell(0)
		local function fade(use: ComposeTypes.Use, depth: number): number
			return if shown(use) then use(pulse) * depth else 1
		end
		local corner = Host.UICorner({})
		local paint = Host.Frame({ Name = "FocusRingPaint", Visible = false, Size = D2.fromOffset(0, 0), corner })
		paint:AddTag("facet-focus-ring")
		local color = ctx.observeStyled.BackgroundColor3(paint)
		local themeRadius = ctx.observeStyled.CornerRadius(corner)
		local gui = config.guiService
		local selected = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil)
		local reshaped = Compose.cell(0)
		local function partOf(target: Instance?): GuiObject?
			local path = if target then target:GetAttribute("FacetFocusPart") else nil
			if type(path) ~= "string" then
				return nil
			end
			local at: Instance? = target
			for name in string.gmatch(path, "[^/]+") do
				at = if at then at:FindFirstChild(name) else nil
			end
			return if at and at:IsA("GuiObject") then at :: GuiObject else nil
		end
		local partRevision = Compose.cell(0)
		local observation = runtime.host.observation
		local tracking: { () -> () } = {}
		local function untrack()
			for _, stop in tracking do
				stop()
			end
			table.clear(tracking)
		end
		local function bump()
			reshaped:set(reshaped:peek() + 1)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local target = use(selected) :: Instance?
			use(partRevision)
			untrack()
			if observation and target and target:IsA("GuiObject") then
				table.insert(tracking, observation.observeProperty(target, "AbsoluteSize", bump))
				local reach = target:GetAttributeChangedSignal("FacetFocusHeight"):Connect(bump)
				local named = target:GetAttributeChangedSignal("FacetFocusPart"):Connect(function()
					partRevision:set(partRevision:peek() + 1)
					bump()
				end)
				table.insert(tracking, function()
					reach:Disconnect()
					named:Disconnect()
				end)
				local part = partOf(target)
				if part then
					table.insert(tracking, observation.observeProperty(part, "AbsoluteSize", bump))
					table.insert(tracking, observation.observeProperty(part, "AbsolutePosition", bump))
					table.insert(tracking, observation.observeProperty(target, "AbsolutePosition", bump))
				end
				local own = (part or target):FindFirstChildWhichIsA("UICorner")
				if own then
					table.insert(tracking, observation.observeProperty(own, "CornerRadius", bump))
				end
			end
		end)
		Compose.cleanup(untrack)
		local tweens = (config.services :: unknown) :: { TweenService: TweenService? }
		local tweenService = tweens.TweenService
		if tweenService and observation then
			runtime.mountFragment(function()
				return {
					Compose.show(function(use: ComposeTypes.Use): boolean
						return shown(use) and layer(use).pulse == true and not reduced(use)
					end, function()
						local value = runtime.host.render.createNode("NumberValue") :: NumberValue
						value.Name = "FocusPulse"
						local playback = tweenService:Create(
							value,
							ctx.types.TweenInfo.new(
								ctx.metric("motion.durations.focusPulse"),
								ctx.motionStyle("pulse"),
								E.EasingDirection.InOut,
								-1,
								true
							),
							{ Value = 1 }
						)
						local stop = observation.observeProperty(value, "Value", function()
							pulse:set(value.Value)
						end)
						playback:Play()
						Compose.cleanup(function()
							playback:Cancel()
							stop()
							pulse:set(0)
						end)
						return value
					end),
				}
			end, paint)
		end
		local function art(use: ComposeTypes.Use): ThemeTypes.Asset?
			local current = use(package) :: ThemeTypes.ThemePackage?
			local focus = layer(use)
			if focus.kind ~= "nineSlice" or type(focus.asset) ~= "string" or current == nil then
				return nil
			end
			return (current.assets or {})[focus.asset :: string]
		end
		local function outset(use: ComposeTypes.Use): number
			return scaled(use, layer(use).outset or 0, 1.5)
		end
		local function stroked(use: ComposeTypes.Use): boolean
			local kind = layer(use).kind
			return kind == "ring" or kind == "brackets"
		end
		local function thickness(use: ComposeTypes.Use): number
			local focus = layer(use)
			if focus.kind == "brackets" then
				return scaled(use, focus.thickness or 4, 1.5)
			end
			return scaled(use, focus.thickness or 2, 2)
		end
		local lift = function(use: ComposeTypes.Use): number
			return (if far(use) then 3 else 0)
				+ (if stroked(use) then thickness(use) else 0)
				+ (if layer(use).kind == "ring" then 0 else outset(use))
		end
		local ring = Host.ImageLabel({
			Name = "FacetFocusRing",
			BackgroundTransparency = 1,
			ScaleType = E.ScaleType.Slice,
			Size = function(use: ComposeTypes.Use): UDim2
				local grow = lift(use)
				use(reshaped)
				local target = use(selected) :: Instance?
				local part = partOf(target)
				if part then
					return D2.fromOffset(part.AbsoluteSize.X + 2 * grow, part.AbsoluteSize.Y + 2 * grow)
				end
				local height = if target then target:GetAttribute("FacetFocusHeight") else nil
				return D2.new(1, 2 * grow, if type(height) == "number" then height else 1, 2 * grow)
			end,
			Position = function(use: ComposeTypes.Use): UDim2
				local grow = lift(use)
				use(reshaped)
				local target = use(selected) :: Instance?
				local part = partOf(target)
				if part and target and target:IsA("GuiObject") then
					local offset = part.AbsolutePosition - (target :: GuiObject).AbsolutePosition
					return D2.fromOffset(offset.X - grow, offset.Y - grow)
				end
				return D2.fromOffset(-grow, -grow)
			end,
			ImageTransparency = function(use: ComposeTypes.Use): number
				return if art(use) then fade(use, 0.35) else 1
			end,
			Image = function(use: ComposeTypes.Use): string
				local asset = art(use)
				return if asset then asset.content or asset.contentId or "" else ""
			end,
			SliceCenter = function(use: ComposeTypes.Use): Rect
				local asset = art(use)
				local slice = if asset then asset.sliceCenter else nil
				return if slice
					then ctx.types.Rect.new(slice.x0, slice.y0, slice.x1, slice.y1)
					else ctx.types.Rect.new(0, 0, 0, 0)
			end,
			SliceScale = function(use: ComposeTypes.Use): number
				local asset = art(use)
				local base = layer(use).sliceScale or (if asset then asset.sliceScale else nil) or 1
				return if far(use) then base * 1.5 else base
			end,
			Host.UICorner({
				CornerRadius = function(use: ComposeTypes.Use): UDim
					local shape = layer(use).corner
					if shape == "square" or art(use) then
						return D.new(0, 0)
					elseif shape == "pill" then
						return D.new(0.5, 0)
					end
					use(reshaped)
					local target = use(selected) :: Instance?
					local radius = use(themeRadius) :: UDim
					if target then
						local own = (partOf(target) or target):FindFirstChildWhichIsA("UICorner")
						if own then
							radius = own.CornerRadius
						elseif target:HasTag("facet-shape-circle") then
							return D.new(0.5, 0)
						elseif target:HasTag("facet-chip") then
							radius = D.new(0, ctx.metric("radii.pill", use))
						end
					end
					return if radius.Scale > 0 then radius else D.new(0, radius.Offset + lift(use))
				end,
			}) :: ComposeTypes.Child,
			Host.UIStroke({
				ApplyStrokeMode = E.ApplyStrokeMode.Border,
				BorderStrokePosition = E.BorderStrokePosition.Inner,
				Color = color,
				Enabled = stroked,
				Thickness = thickness,
				Transparency = function(use: ComposeTypes.Use): number
					return fade(use, 0.35)
				end,
				Host.UIGradient({
					Name = "Brackets",
					Enabled = function(use: ComposeTypes.Use): boolean
						return layer(use).kind == "brackets"
					end,
					Transparency = function(use: ComposeTypes.Use): NumberSequence
						local focus = layer(use)
						use(reshaped)
						local target = use(selected) :: GuiObject?
						local shape = partOf(target) or target
						local width = (if shape then shape.AbsoluteSize.X else 0) + 2 * lift(use)
						local arm = scaled(use, if type(focus.size) == "number" then focus.size else 12, 1.5)
						local reach = if width > 0 then math.clamp(arm / width, 0.02, 0.45) else 0.2
						local K = ctx.types.NumberSequenceKeypoint
						return ctx.types.NumberSequence.new({
							K.new(0, 0),
							K.new(reach, 0),
							K.new(reach + 0.001, 1),
							K.new(1 - reach - 0.001, 1),
							K.new(1 - reach, 0),
							K.new(1, 0),
						})
					end,
				}) :: ComposeTypes.Child,
			}),
			Host.UIShadow({
				Name = "Glow",
				Color = color,
				Enabled = function(use: ComposeTypes.Use): boolean
					return layer(use).kind == "glow" and shown(use)
				end,
				BlurRadius = function(use: ComposeTypes.Use): UDim
					local blur = layer(use).blurRadius
					return D.new(0, math.round(scaled(use, (if blur then blur.offset else nil) or 24, 1.6)))
				end,
				Transparency = function(use: ComposeTypes.Use): number
					local value = layer(use).transparency or 0.25
					return math.clamp((if far(use) then value * 0.55 else value) + use(pulse) * 0.2, 0, 1)
				end,
				ZIndex = function(use: ComposeTypes.Use): number
					return layer(use).zIndex or -1
				end,
			}),
		})
		local owner = selectionOwners[playerGui]
		if owner == nil then
			owner = { prior = playerGui.SelectionImageObject, rings = {} }
			selectionOwners[playerGui] = owner
		end
		local held = owner :: SelectionOwner
		table.insert(held.rings, ring)
		playerGui.SelectionImageObject = ring
		Compose.cleanup(function()
			local index = table.find(held.rings, ring)
			if index then
				table.remove(held.rings, index)
			end
			if playerGui.SelectionImageObject == ring then
				(playerGui :: any).SelectionImageObject = held.rings[#held.rings] or held.prior
			end
			if #held.rings == 0 then
				selectionOwners[playerGui] = nil
			end
		end)
		return paint
	end

	UI.environment = function(source: Env.EnvironmentSource?): Env.Environment
		assert(Compose.currentOwner() ~= nil, "Facet UI.environment must run inside a component or Compose owner")
		local node: Instance? = source
		if node == nil then
			local world = scene()
			node = if world then ((world :: unknown) :: { CurrentCamera: Instance? }).CurrentCamera else nil
		end
		local gui2d = node ~= nil and node:IsA("GuiBase2d")
		local property = if gui2d then "AbsoluteSize" else "ViewportSize"
		local screenSize = watched(node, property, V2.zero)
		local unit = if gui2d then ctx.layoutUnit(node :: GuiBase2d) else nil
		local engineSize: ComposeTypes.Readable<unknown> = if unit
			then Compose.formula(function(use: ComposeTypes.Use): unknown
				local size = use(screenSize)
				return if typeof(size) == "Vector2" then size / use(unit) else size
			end)
			else screenSize
		local forced = if source == nil and config.environment then config.environment.viewportSize else nil
		local raw: ComposeTypes.Readable<unknown> = if forced == nil
			then engineSize
			else Compose.formula(function(use: ComposeTypes.Use): unknown
				local size = ctx.read(forced, use)
				return if size == nil then use(engineSize) else size
			end)
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
		local tenFoot = ctx.tenFoot()
		local sizeClass = (
			derived(function(use): Env.SizeClass
				local class: Env.SizeClass = adaptive.sizeClass(use(viewportWidth))
				return if class == "wide" and tenFoot(use) then "regular" else class
			end) :: unknown
		) :: ComposeTypes.Readable<Env.SizeClass>
		local heightClass = (
			derived(function(use): Env.HeightClass
				local class: Env.HeightClass = adaptive.heightClass(use(viewportHeight))
				return if class == "tall" and tenFoot(use) then "medium" else class
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
		local primaryInput = ctx.effectiveInput()
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
			local primary = primaryInput(use)
			classes.primary = if primary == "Touch"
				then "touch"
				elseif primary == "Gamepad" then "gamepad"
				else "pointer"
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
				return primaryInput(use)
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
				local service: GuiService = gui
				local ok, topLeft, bottomRight = pcall(function()
					return service:GetGuiInset()
				end)
				if ok and typeof(topLeft) == "Vector2" and typeof(bottomRight) == "Vector2" then
					insets = { top = topLeft.Y, left = topLeft.X, bottom = bottomRight.Y, right = bottomRight.X }
				end
			end
			return freeze(insets)
		end)
		local overscan = derived(function(use): Env.SafeInsets
			local authored = ctx.read(config.environment and config.environment.overscanInsets, use)
			if authored == "none" or (authored == nil and not tenFoot(use)) then
				return freeze({ top = 0, left = 0, bottom = 0, right = 0 })
			end
			if type(authored) == "table" then
				return freeze(table.clone(authored))
			end
			local size = use(viewportSize)
			return adaptive.overscanInsets(size.X, size.Y)
		end)
		local level = motion.level(ctx)
		local isTenFoot = derived(function(use): boolean
			return tenFoot(use)
		end)
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
			isLandscape = derived(function(use: ComposeTypes.Use): boolean
				local size = use(viewportSize)
				return size.X > size.Y
			end),
			axis = (derived(function(use: ComposeTypes.Use): "x" | "y"
				return adaptive.axisFor(use(viewportWidth))
			end) :: unknown) :: ComposeTypes.Readable<"x" | "y">,
			atLeast = atLeast,
			interactionClasses = interactionClasses,
			effectiveInput = effectiveInput,
			displaySize = displaySize,
			isTenFoot = isTenFoot,
			viewingDistanceSource = (derived(function(use): "authored" | "inferred"
				return if ctx.viewingDistance(use) == "automatic" then "inferred" else "authored"
			end) :: unknown) :: ComposeTypes.Readable<"authored" | "inferred">,
			metricScale = derived(function(use): number
				return if use(isTenFoot) then adaptive.TEN_FOOT_SCALE else 1
			end),
			overscanInsets = overscan,
			navPlacement = (derived(function(use): adaptive.NavPlacement
				return adaptive.navPlacement({
					sizeClass = use(sizeClass),
					heightClass = use(heightClass),
					primary = use(interactionClasses).primary,
					displaySize = use(displaySize),
					tenFoot = use(isTenFoot),
				})
			end) :: unknown) :: ComposeTypes.Readable<adaptive.NavPlacement>,
			safeInsets = safeInsets,
			preferredTextSize = preferredTextSize,
			reducedMotion = derived(function(use): boolean
				return level(use) ~= "normal"
			end),
			motionLevel = (derived(function(use): Shared.MotionLevel
				return level(use)
			end) :: unknown) :: ComposeTypes.Readable<Shared.MotionLevel>,
		})
		return environment
	end

	UI.responder = ctx.responder
	local SECTION_KEYS = { entry = true, preferred = true, focusOnAppear = true, returnFocus = true }
	UI.focusSection = function(group: GuiObject, options: Env.FocusSectionOptions?)
		assert(Compose.currentOwner() ~= nil, "Facet UI.focusSection must run inside a component or Compose owner")
		assert(
			(group :: any) ~= nil and (group :: any).IsA ~= nil and group:IsA("GuiObject"),
			"Facet UI.focusSection expects a GuiObject"
		)
		local settings: Env.FocusSectionOptions = options or {}
		for key in (settings :: unknown) :: { [unknown]: unknown } do
			assert(SECTION_KEYS[key :: string] == true, `Facet UI.focusSection: unknown option '{tostring(key)}'`)
		end
		local entry = settings.entry or "restore"
		assert(
			entry == "restore" or entry == "first" or entry == "nearest",
			"Facet UI.focusSection: entry must be restore, first or nearest"
		)
		local appear = settings.focusOnAppear
		assert(
			appear == nil or type(appear) == "boolean" or (type(appear) == "string" and appear ~= ""),
			"Facet UI.focusSection: focusOnAppear is a boolean or a descendant name"
		)
		local gui = config.guiService
		if gui == nil then
			return
		end
		local function usable(node: GuiObject?): boolean
			return node ~= nil
				and node:IsDescendantOf(group)
				and node.Selectable
				and node.Visible
				and node:FindFirstAncestorWhichIsA("LayerCollector") ~= nil
		end
		local function ordered(node: Instance, into: { GuiObject })
			local children = node:GetChildren()
			local index: { [Instance]: number } = {}
			for position, child in children do
				index[child] = position
			end
			table.sort(children, function(a: Instance, b: Instance): boolean
				local left = if a:IsA("GuiObject") then a.LayoutOrder else 0
				local right = if b:IsA("GuiObject") then b.LayoutOrder else 0
				return if left ~= right then left < right else index[a] < index[b]
			end)
			for _, child in children do
				if child:IsA("GuiObject") then
					if not child.Visible then
						continue
					end
					if child.Selectable then
						table.insert(into, child)
					end
				end
				ordered(child, into)
			end
		end
		local function named(name: string): GuiObject?
			local at: Instance? = group
			for part in string.gmatch(name, "[^/]+") do
				at = if at then at:FindFirstChild(part, true) else nil
			end
			return if at and at:IsA("GuiObject") and usable(at :: GuiObject) then at :: GuiObject else nil
		end
		local function first(): GuiObject?
			local list: { GuiObject } = {}
			ordered(group, list)
			return list[1]
		end
		local selected = ctx.observe.SelectedObject(gui)
		local last: GuiObject? = nil
		local inside = false
		Compose.watch(function(use: ComposeTypes.Use)
			local current = use(selected) :: GuiObject?
			local entered = current ~= nil and current:IsDescendantOf(group)
			if entered and not inside and entry ~= "nearest" then
				local target: GuiObject? = nil
				if entry == "first" then
					target = first()
				elseif usable(last) then
					target = last
				elseif settings.preferred then
					target = named(settings.preferred)
				end
				inside = true
				if target and target ~= current then
					gui.SelectedObject = target
					return
				end
			end
			inside = entered
			if entered then
				last = current
			end
		end)
		if appear or settings.returnFocus then
			local input = config.userInputService
			local before: GuiObject? = nil
			local layer: LayerCollector? = nil
			local function claim()
				local at = group:FindFirstAncestorWhichIsA("LayerCollector")
				if layer or at == nil then
					return
				end
				layer, before = at, gui.SelectedObject
				local navigating = before ~= nil
					or (input ~= nil and input.PreferredInput == ctx.types.Enum.PreferredInput.Gamepad)
				if not navigating or not appear then
					return
				end
				local target = if type(appear) == "string" then named(appear) else first()
				if target then
					gui.SelectedObject = target
				elseif appear == true then
					gui:Select(group)
				end
			end
			runtime.connect(group, "AncestryChanged", claim)
			claim()
			if settings.returnFocus then
				local held, returned = false, false
				local function restore()
					returned = true
					local target = before
					if target and target:FindFirstAncestorWhichIsA("LayerCollector") then
						gui.SelectedObject = target
					elseif target and layer then
						gui:Select(layer)
					end
				end
				Compose.watch(function(use: ComposeTypes.Use)
					local current = use(selected) :: GuiObject?
					local within = current ~= nil and current:IsDescendantOf(group)
					if
						held
						and not within
						and not returned
						and group:FindFirstAncestorWhichIsA("LayerCollector") == nil
					then
						restore()
						return
					end
					held = within
				end)
				Compose.cleanup(function()
					local current = gui.SelectedObject
					if returned or before == nil or (current ~= nil and not current:IsDescendantOf(group)) then
						return
					end
					restore()
				end)
			end
		end
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
			local place = world
			local found = (ctx.read(options.target) :: unknown) :: Instance?
			local chosen = (ctx.read(options.camera) :: unknown) :: Projector?
			local camera = chosen or (if place then place.CurrentCamera else nil)
			if found == nil or camera == nil or place == nil then
				return { visible = false }
			end
			assert(
				found:IsA("BasePart") or found:IsA("Model") or found:IsA("Player"),
				"Facet UI.worldAnchor: target must be a BasePart, Model or Player"
			)
			local target: Instance? = if found:IsA("Player") then (found :: Player).Character else found
			if target == nil or not target:IsDescendantOf((place :: unknown) :: Instance) then
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
				local hit = place:Raycast(origin, frame.Position - origin)
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
		local handle: Env.WorldAnchor = { anchor = anchor, dispose = dispose }
		return freeze(handle)
	end
end
