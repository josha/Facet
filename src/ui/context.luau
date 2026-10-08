--!strict
local ComposeTypes = require("../vendor/compose/core")
local bindThemes = require("./themes")
local Shared = require("./types")
local Theme = require("./theme_types")
local layoutKit = require("./layout_kit")
local selection = require("./selection")
local reservedKeys = require("./reserved_keys")
local adaptive = require("./adaptive")
local preferredInput = require("./preferred_input")
local motion = require("./motion")
local observeGeometry = require("./geometry_observation")

type ModalPortal = { node: Instance, anchor: Instance }
type ActionSettings = {
	onReleased: (() -> ())?,
	priority: number?,
	sink: boolean?,
	capture: boolean?,
	group: string?,
	conditional: { binding: Shared.ActionBinding, when: (ComposeTypes.Use) -> boolean }?,
	direction2D: ((Vector2) -> ())?,
}
return function(Compose: Shared.ComposeModule, runtime: ComposeTypes.Runtime, options: Shared.Config?): Shared.Context
	assert(runtime.host.name == "roblox", "Facet.controls requires a Compose Roblox runtime")
	local config: Shared.Config = if options then table.clone(options) else {}
	assert(
		((config :: unknown) :: { [string]: unknown }).reducedMotion == nil,
		'Facet: the reducedMotion option is gone; set motionLevel = "normal", "limited" or "none"'
	)
	if type(config.motionLevel) == "string" then
		motion.check(config.motionLevel)
	end
	motion.publish(Compose, runtime, config.motionLevel)
	local environment = config.environment
	if environment and environment.preferredTextSize ~= nil then
		local owner = (runtime :: unknown) :: { [string]: unknown }
		local previous = owner.FacetTextPreference
		owner.FacetTextPreference = environment.preferredTextSize
		if Compose.currentOwner() then
			Compose.cleanup(function()
				if owner.FacetTextPreference == environment.preferredTextSize then
					owner.FacetTextPreference = previous
				end
			end)
		end
	end
	local types: Shared.RobloxTypes = config.types
		or {
			UDim = UDim,
			UDim2 = UDim2,
			Vector2 = Vector2,
			Vector3 = Vector3,
			Color3 = Color3,
			CFrame = CFrame,
			Enum = Enum,
			Font = Font,
			Rect = Rect,
			ColorSequence = ColorSequence,
			ColorSequenceKeypoint = ColorSequenceKeypoint,
			NumberSequence = NumberSequence,
			NumberSequenceKeypoint = NumberSequenceKeypoint,
			NumberRange = NumberRange,
			Path2DControlPoint = Path2DControlPoint,
			FloatCurveKey = FloatCurveKey,
			TweenInfo = TweenInfo,
			BrickColor = BrickColor,
		}
	assert(types.UDim2 and types.Enum, "Facet.controls requires Roblox datatypes")
	local services: Shared.Services = if config.services then table.clone(config.services) else {}
	if game then
		services.GamepadService = services.GamepadService or game:GetService("GamepadService")
		services.GuiService = services.GuiService or game:GetService("GuiService")
		services.UserInputService = services.UserInputService or game:GetService("UserInputService")
		services.Players = services.Players or game:GetService("Players")
		services.RunService = services.RunService or game:GetService("RunService")
		services.TextService = services.TextService or game:GetService("TextService")
		services.ContentProvider = services.ContentProvider or game:GetService("ContentProvider")
		services.Workspace = services.Workspace or game:GetService("Workspace")
		services.TweenService = services.TweenService or game:GetService("TweenService")
	end
	config.services = services
	config.guiService = config.guiService or services.GuiService
	config.userInputService = config.userInputService or services.UserInputService
	local Host = (runtime.constructors :: unknown) :: Shared.Host
	local Enum = types.Enum
	local themes = bindThemes(Compose)
	local ctx = {
		runtime = runtime,
		Host = Host,
		Compose = Compose,
		types = types,
		config = config :: Shared.ResolvedConfig,
		metrics = { textSize = 16, controlHeight = 36, gap = 8, cornerRadius = 8 },
	}
	local building: string? = nil
	local track: ((Instance) -> ())? = nil
	local metatableOf = (getmetatable :: unknown) :: (unknown) -> unknown
	local native: { [unknown]: boolean } = {}
	native[metatableOf(Compose.cell(nil))] = true
	native[metatableOf(Compose.sharedCell(nil))] = true
	local probe = Compose.formula(function()
		return nil
	end)
	native[metatableOf(probe)] = true
	probe:dispose()
	local function reject(key: string?)
		local option = if key then ` option '{key}'` else " a value"
		error(
			`Facet UI.{building or "control"}:{option} is a readable from another Compose instance. `
				.. "Facet cannot track it. Bind Facet to that Compose with Facet.bind(Compose, Roblox).",
			0
		)
	end
	local function read<T>(value: T | ComposeTypes.Source<T>, use: ComposeTypes.Use?): T
		if Compose.isReadable(value) then
			local source = value :: ComposeTypes.Readable<T>
			return if use then use(source) else source:peek()
		elseif type(value) == "function" then
			local body = value :: ComposeTypes.Body<T>
			return body(use or function<U>(source: ComposeTypes.Readable<U>): U
				return source:peek()
			end)
		end
		return value :: T
	end
	ctx.read = (read :: unknown) :: Shared.Read
	ctx.readSource = function<T>(source: ComposeTypes.Readable<T>, use: ComposeTypes.Use?): T
		return if use then use(source) else source:peek()
	end
	local function live(value: unknown): boolean
		return Compose.isReadable(value) or type(value) == "function"
	end
	local defaultMetrics = themes.neutralPackage().metrics
	local function valueAt(value: unknown, path: string): unknown
		for key in string.gmatch(path, "[^.]+") do
			if type(value) ~= "table" then
				return nil
			end
			value = (value :: { [string]: unknown })[key]
		end
		return value
	end
	local function metricAt(value: unknown, path: string): number?
		local found = valueAt(value, path)
		return if type(found) == "number" and found == found and math.abs(found) ~= math.huge then found else nil
	end
	local distantMetrics = themes.forDistance(themes.neutralPackage(), "ten-foot").metrics
	local distance: (ComposeTypes.Use?) -> boolean = function()
		return false
	end
	function ctx.neutralMetrics(use: ComposeTypes.Use?): Theme.Metrics
		return if distance(use) then distantMetrics else defaultMetrics
	end
	function ctx.metric(path: string, use: ComposeTypes.Use?): number
		local package = ctx.read(config.theme, use)
		local value = assert(
			metricAt(if package then package.metrics else nil, path) or metricAt(ctx.neutralMetrics(use), path),
			`Facet numeric metric {path} is missing`
		)
		if environment and string.match(path, "^typography%.[^.]+%.size$") then
			local chosen = ctx.read(environment.preferredTextSize, use)
			if chosen ~= nil then
				local ranks = { Medium = 0, Large = 1, Larger = 2, Largest = 3 }
				local function rank(item: unknown): number
					local name = if typeof(item) == "EnumItem" then (item :: EnumItem).Name else item
					return (ranks :: { [unknown]: number })[name] or 0
				end
				local native = if config.guiService then config.guiService.PreferredTextSize else nil
				return math.max(
					1,
					value + (rank(chosen) - rank(native)) * ctx.metric("controls.typography.preferredSizeStep", use)
				)
			end
		end
		return value
	end
	local function motionName(path: string, use: ComposeTypes.Use?): string
		local package = ctx.read(config.theme, use)
		local found = valueAt(if package then package.metrics else nil, path)
		if type(found) ~= "string" then
			found = valueAt(ctx.neutralMetrics(use), path)
		end
		local name = assert(if type(found) == "string" then found else nil, `Facet motion name {path} is missing`)
		return name
	end
	function ctx.motionTiming(role: string, use: ComposeTypes.Use?): { enter: number, exit: number }
		return { enter = ctx.metric(`motion.{role}.enter`, use), exit = ctx.metric(`motion.{role}.exit`, use) }
	end
	function ctx.motionSpring(role: string, use: ComposeTypes.Use?): { period: number, damping: number }
		return {
			period = ctx.metric(`motion.springs.{role}.period`, use),
			damping = ctx.metric(`motion.springs.{role}.damping`, use),
		}
	end
	function ctx.motionEase(role: string, use: ComposeTypes.Use?): (number) -> number
		local name = motionName(`motion.easing.{role}`, use)
		local ease = assert(Compose.easing[name], `Facet motion easing {name} is not a Compose easing`)
		return ease
	end
	function ctx.motionStyle(role: string, use: ComposeTypes.Use?): Enum.EasingStyle
		local name = motionName(`motion.styles.{role}`, use)
		local style = assert(
			((types.Enum.EasingStyle :: unknown) :: { [string]: Enum.EasingStyle })[name],
			`Facet motion style {name} is not an EasingStyle`
		)
		return style
	end
	function ctx.controlSize(
		source: Shared.Value<Shared.ControlSize?>?,
		field: "height" | "paddingX" | "iconSize",
		use: ComposeTypes.Use?
	): number
		local requested = ctx.read(source, use)
		local rung = if requested == nil then "regular" else requested
		assert(
			rung == "xsmall" or rung == "compact" or rung == "regular" or rung == "large",
			"Facet controlSize must be xsmall, compact, regular or large"
		)
		if rung == "xsmall" then
			local package = ctx.read(config.theme, use)
			local authored = metricAt(if package then package.metrics else nil, "controlSizes.xsmall." .. field)
			if authored then
				return authored
			end
			local compact = ctx.metric("controlSizes.compact." .. field, use)
			return math.max(0, 2 * compact - ctx.metric("controlSizes.regular." .. field, use))
		end
		return ctx.metric("controlSizes." .. rung .. "." .. field, use)
	end
	type SharedObservation = { cell: ComposeTypes.Cell<unknown>, users: number, stop: () -> () }
	local serviceNodes: { [Instance]: boolean } = {}
	for _, service in (services :: unknown) :: { [string]: Instance } do
		serviceNodes[service] = true
	end
	if config.guiService then
		serviceNodes[config.guiService] = true
	end
	if config.userInputService then
		serviceNodes[config.userInputService] = true
	end
	local sharedObservations: { [Instance]: { [string]: SharedObservation } } = {}
	local preview: { [string]: unknown } = (config.environment or {}) :: { [string]: unknown }
	local PREVIEWED: { [string]: { key: string, enum: string? } } = {
		PreferredInput = { key = "preferredInput", enum = "PreferredInput" },
		TouchEnabled = { key = "touchEnabled" },
		MouseEnabled = { key = "mouseEnabled" },
		GamepadEnabled = { key = "gamepadEnabled" },
		KeyboardEnabled = { key = "keyboardEnabled" },
		PreferredTextSize = { key = "preferredTextSize", enum = "PreferredTextSize" },
		ViewportDisplaySize = { key = "displaySize", enum = "DisplaySize" },
	}
	local previewKeys: { [string]: boolean } = { viewportSize = true, viewingDistance = true, overscanInsets = true }
	for _, entry in PREVIEWED do
		previewKeys[entry.key] = true
	end
	for key in preview do
		assert(previewKeys[key], `Facet.controls: unknown environment option '{tostring(key)}'`)
	end
	local function previewed(property: string, engine: ComposeTypes.Readable<unknown>): ComposeTypes.Readable<unknown>
		local entry = PREVIEWED[property]
		local source = if entry then preview[entry.key] else nil
		if source == nil then
			return engine
		end
		local enumName = entry.enum
		return Compose.formula(function(use: ComposeTypes.Use): unknown
			local value = ctx.read(source, use)
			if value == nil then
				return use(engine)
			end
			if enumName and type(value) == "string" then
				local item = assert(
					((Enum :: unknown) :: { [string]: { FromName: (unknown, string) -> EnumItem? } })[enumName]:FromName(
						value
					),
					`Facet.controls: environment {entry.key} '{value}' is not a {enumName}`
				)
				return item
			end
			return value
		end)
	end
	local geometryProperties = {
		AbsoluteSize = true,
		AbsolutePosition = true,
		AbsoluteContentSize = true,
		AbsoluteWindowSize = true,
		AbsoluteCanvasSize = true,
		TextBounds = true,
		TextFits = true,
	}
	local sharedProperties = { Visible = true, Interactable = true, Enabled = true }
	local function observe(node: Instance, property: string): ComposeTypes.Cell<unknown>
		local observation = assert(runtime.host.observation, "Roblox property observation is required")
		if serviceNodes[node] or sharedProperties[property] then
			local byProperty = sharedObservations[node]
			if byProperty == nil then
				byProperty = {}
				sharedObservations[node] = byProperty
			end
			local entry = byProperty[property]
			if entry == nil then
				local cell = Compose.cell(observation.readProperty(node, property))
				local selection = property == "SelectedObject"
				local preferred = property == "PreferredInput" and node == config.userInputService
				local stopNudges: (() -> ())? = nil
				local function publish()
					local current = observation.readProperty(node, property)
					if
						preferred
						and preferredInput.withheld(
							node :: UserInputService,
							current,
							Enum.PreferredInput.KeyboardAndMouse
						)
					then
						stopNudges = stopNudges
							or preferredInput.nudges(node :: UserInputService, Enum, function()
								if cell:peek() ~= observation.readProperty(node, property) then
									publish()
								end
							end)
						return
					end
					if stopNudges then
						stopNudges()
						stopNudges = nil
					end
					cell:set(current)
					if selection then
						for _, hook in ctx.selectionHooks :: { (unknown) -> () } do
							hook(current)
						end
					end
				end
				local stop = observation.observeProperty(node, property, publish)
				if preferred then
					local unobserve = stop
					stop = function()
						if stopNudges then
							stopNudges()
							stopNudges = nil
						end
						unobserve()
					end
				end
				local created: SharedObservation = {
					cell = cell,
					users = 0,
					stop = stop,
				}
				byProperty[property] = created
				entry = created
			end
			local held = entry :: SharedObservation
			Compose.cleanup(function()
				held.users -= 1
				if held.users == 0 then
					held.stop()
					if byProperty[property] == held then
						byProperty[property] = nil
					end
					if next(byProperty) == nil then
						sharedObservations[node] = nil
					end
				end
			end)
			held.users += 1
			return (previewed(property, held.cell) :: unknown) :: ComposeTypes.Cell<unknown>
		end
		if geometryProperties[property] then
			return observeGeometry(
				Compose,
				runtime,
				node,
				property,
				if services.RunService then services.RunService.PreRender else nil
			)
		end
		local value = Compose.cell(observation.readProperty(node, property))
		Compose.cleanup(observation.observeProperty(node, property, function()
			value:set(observation.readProperty(node, property))
		end))
		return value
	end
	local function observers(watch: (Instance, string) -> ComposeTypes.Cell<unknown>): Shared.Observe
		local bound: { [string]: (Instance) -> ComposeTypes.Cell<unknown> } = {}
		setmetatable(bound, {
			__index = function(_, property: string): (Instance) -> ComposeTypes.Cell<unknown>
				local read = function(node: Instance): ComposeTypes.Cell<unknown>
					return watch(node, property)
				end
				bound[property] = read
				return read
			end,
		})
		return (bound :: unknown) :: Shared.Observe
	end
	local hapticWaves: { [string]: { number } } = {
		warning = { 0, 0, 10, 0.7, 40, 0, 90, 0.7, 130, 0 },
		error = { 0, 0, 8, 1, 40, 0, 80, 1, 112, 0, 152, 1, 190, 0 },
	}
	local hapticPresets: { [string]: string } =
		{ selection = "UIClick", impact = "GameplayCollision", success = "UINotification" }
	local hapticPool: { [string]: HapticEffect } = {}
	ctx.haptic = function(kind: unknown): HapticEffect?
		if kind == true then
			kind = config.pressHaptic
		end
		if kind == nil or kind == false then
			return nil
		end
		if type(kind) ~= "string" then
			return kind :: HapticEffect
		end
		local pooled = hapticPool[kind]
		if pooled then
			return pooled
		end
		local wave = hapticWaves[kind]
		assert(
			wave or hapticPresets[kind],
			`Facet haptic: unknown feedback kind '{kind}'. Use selection, impact, success, warning or error`
		)
		local effect = runtime.host.render.createNode("HapticEffect") :: HapticEffect
		effect.Name = `FacetHaptic_{kind}`
		if wave then
			effect.Type = Enum.HapticEffectType.Custom
			local keys = {}
			for index = 1, #wave, 2 do
				table.insert(
					keys,
					types.FloatCurveKey.new(wave[index], wave[index + 1], Enum.KeyInterpolationMode.Linear)
				)
			end
			effect:SetWaveformKeys(keys)
		else
			effect.Type = ((Enum.HapticEffectType :: unknown) :: { [string]: Enum.HapticEffectType })[hapticPresets[kind]]
		end
		effect.Parent = services.Workspace
		hapticPool[kind] = effect
		return effect
	end
	ctx.selectionHooks = {}
	ctx.observe = observers(observe)
	type SelectionWaiters = { waiting: { [Instance]: () -> () }, count: number, stop: (() -> ())? }
	local selectionWaiters: { [Instance]: SelectionWaiters } = {}
	function ctx.whenSelected(gui: Instance, node: Instance, callback: () -> ()): ()
		local observation = assert(runtime.host.observation, "Roblox property observation is required")
		local waiters = selectionWaiters[gui]
		if waiters == nil then
			local created: SelectionWaiters = { waiting = {}, count = 0, stop = nil }
			selectionWaiters[gui] = created
			waiters = created
		end
		local registry = waiters :: SelectionWaiters
		Compose.cleanup(function()
			if registry.waiting[node] == callback then
				registry.waiting[node] = nil
				registry.count -= 1
				if registry.count == 0 and registry.stop then
					registry.stop()
					registry.stop = nil
				end
			end
		end)
		registry.waiting[node] = callback
		registry.count += 1
		if registry.stop == nil then
			registry.stop = observation.observeProperty(gui, "SelectedObject", function()
				local target = observation.readProperty(gui, "SelectedObject")
				local waiting = if typeof(target) == "Instance" or type(target) == "table"
					then registry.waiting[target :: Instance]
					else nil
				if waiting then
					waiting()
				end
			end)
		end
		if rawequal(observation.readProperty(gui, "SelectedObject"), node) then
			callback()
		end
	end
	function ctx.pointerOnly(): (ComposeTypes.Use?) -> boolean
		local input = config.userInputService
		if input == nil then
			return function()
				return false
			end
		end
		local mouse, touch, gamepad =
			ctx.observe.MouseEnabled(input), ctx.observe.TouchEnabled(input), ctx.observe.GamepadEnabled(input)
		return function(use: ComposeTypes.Use?): boolean
			return ctx.readSource(mouse, use) == true
				and ctx.readSource(touch, use) ~= true
				and ctx.readSource(gamepad, use) ~= true
		end
	end
	function ctx.viewingDistance(use: ComposeTypes.Use?): adaptive.ViewingDistance
		local value = ctx.read(preview.viewingDistance, use)
		assert(
			value == nil or value == "automatic" or value == "near" or value == "ten-foot",
			"Facet environment viewingDistance must be automatic, near or ten-foot"
		)
		return (value or "automatic") :: adaptive.ViewingDistance
	end
	function ctx.tenFoot(): (ComposeTypes.Use?) -> boolean
		local gui, input = config.guiService, config.userInputService
		local interface = false
		if gui then
			local ok, answer = pcall(function()
				return (gui :: GuiService):IsTenFootInterface()
			end)
			interface = ok and answer == true
		end
		local watchable = function(service: Instance?): boolean
			return service ~= nil and service.GetPropertyChangedSignal ~= nil
		end
		local display = if watchable(gui) then ctx.observe.ViewportDisplaySize(gui :: GuiService) else nil
		local mouse = if watchable(input) then ctx.observe.MouseEnabled(input :: UserInputService) else nil
		local touch = if watchable(input) then ctx.observe.TouchEnabled(input :: UserInputService) else nil
		return function(use: ComposeTypes.Use?): boolean
			local size = if display then ctx.readSource(display, use) else nil
			return adaptive.isTenFoot({
				viewingDistance = ctx.viewingDistance(use),
				tenFootInterface = interface,
				displaySize = if typeof(size) == "EnumItem" then (size :: EnumItem).Name else nil,
				mouse = if mouse then ctx.readSource(mouse, use) == true else false,
				touch = if touch then ctx.readSource(touch, use) == true else false,
			})
		end
	end
	local interface = false
	if config.guiService then
		pcall(function()
			interface = (config.guiService :: GuiService):IsTenFootInterface() == true
		end)
	end
	local function distantNow(use: ComposeTypes.Use?): boolean
		local gui, input = config.guiService, config.userInputService
		local function fact(key: string, service: Instance?, property: string): unknown
			local value = ctx.read(preview[key], use)
			if value == nil and service ~= nil then
				value = (
					(
						service :: unknown
					) :: { ViewportDisplaySize: Enum.DisplaySize?, MouseEnabled: boolean?, TouchEnabled: boolean? }
				)[property]
			end
			return value
		end
		local display = fact("displaySize", gui, "ViewportDisplaySize")
		return adaptive.isTenFoot({
			viewingDistance = ctx.viewingDistance(use),
			tenFootInterface = interface,
			displaySize = if typeof(display) == "EnumItem" then (display :: EnumItem).Name else display :: string?,
			mouse = fact("mouseEnabled", input, "MouseEnabled") == true,
			touch = fact("touchEnabled", input, "TouchEnabled") == true,
		})
	end
	local authored = config.theme
	local previewLive = false
	for _, key in { "viewingDistance", "displaySize", "mouseEnabled", "touchEnabled" } do
		previewLive = previewLive or live(preview[key])
	end
	if previewLive then
		local distant = Compose.formula(distantNow)
		distance = function(use: ComposeTypes.Use?): boolean
			return ctx.readSource(distant, use)
		end
	else
		local fixed = distantNow()
		distance = function(): boolean
			return fixed
		end
	end
	if live(authored) or (authored ~= nil and previewLive) then
		config.theme = Compose.formula(function(use: ComposeTypes.Use): Theme.ThemePackage
			return themes.forDistance(ctx.read(authored, use), if distance(use) then "ten-foot" else "near")
		end)
	elseif authored ~= nil then
		config.theme = themes.forDistance(authored :: Theme.ThemePackage, if distantNow() then "ten-foot" else "near")
	end
	function ctx.hitFloor(): (ComposeTypes.Use?) -> number
		local pointerOnly = ctx.pointerOnly()
		return function(use: ComposeTypes.Use?): number
			local minimum = ctx.metric("targetSizes.minimum", use)
			local package = ctx.read(config.theme, use)
			local pointer = metricAt(if package then package.metrics else nil, "targetSizes.pointer")
			if pointer == nil or pointer >= minimum or not pointerOnly(use) then
				return minimum
			end
			return pointer
		end
	end
	function ctx.effectiveInput(): (ComposeTypes.Use?) -> "Touch" | "Gamepad" | "KeyboardAndMouse"
		local input = config.userInputService
		local function watch(property: string): ComposeTypes.Readable<unknown>?
			if input == nil then
				return nil
			end
			local ok, value = pcall(
				({
					PreferredInput = ctx.observe.PreferredInput,
					MouseEnabled = ctx.observe.MouseEnabled,
					TouchEnabled = ctx.observe.TouchEnabled,
					GamepadEnabled = ctx.observe.GamepadEnabled,
				} :: { [string]: (UserInputService) -> ComposeTypes.Readable<unknown> })[property],
				input
			)
			return if ok then value else nil
		end
		local preferred, mouse, touch, gamepad =
			watch("PreferredInput"), watch("MouseEnabled"), watch("TouchEnabled"), watch("GamepadEnabled")
		local function on(source: ComposeTypes.Readable<unknown>?, use: ComposeTypes.Use?): boolean
			return source ~= nil and ctx.readSource(source, use) == true
		end
		return function(use: ComposeTypes.Use?): "Touch" | "Gamepad" | "KeyboardAndMouse"
			local report = if preferred then ctx.readSource(preferred, use) else nil
			local name = if typeof(report) == "EnumItem" then (report :: EnumItem).Name else report
			if name == "Touch" or name == "Gamepad" then
				return name
			elseif on(mouse, use) then
				return "KeyboardAndMouse"
			elseif on(touch, use) then
				return "Touch"
			elseif on(gamepad, use) then
				return "Gamepad"
			end
			return "KeyboardAndMouse"
		end
	end
	function ctx.touchFloor(): (ComposeTypes.Use?) -> number
		local input = config.userInputService
		if input == nil then
			return function()
				return 0
			end
		end
		local touch, gamepad = ctx.observe.TouchEnabled(input), ctx.observe.GamepadEnabled(input)
		return function(use: ComposeTypes.Use?): number
			if ctx.readSource(touch, use) ~= true and ctx.readSource(gamepad, use) ~= true then
				return 0
			end
			return ctx.metric("targetSizes.minimum", use)
		end
	end
	local shiftRoutes = (
		setmetatable({} :: { [Instance]: () -> () }, { __mode = "k" }) :: unknown
	) :: { [Instance]: () -> () }
	function ctx.shiftRoute(root: Instance, handler: () -> ()): ()
		shiftRoutes[root] = handler
		Compose.cleanup(function()
			if shiftRoutes[root] == handler then
				shiftRoutes[root] = nil
			end
		end)
	end
	function ctx.shiftActivation(node: Instance, input: InputObject?): (() -> ())?
		local service = config.userInputService
		if
			not service
			or not (type(input) == "table" or (typeof(input) == "Instance" and (input :: Instance):IsA("InputObject")))
			or (input :: InputObject).KeyCode ~= Enum.KeyCode.Return
		then
			return nil
		end
		local ok, shifted = pcall(function()
			return service:IsKeyDown(Enum.KeyCode.LeftShift) or service:IsKeyDown(Enum.KeyCode.RightShift)
		end)
		if not ok or not shifted then
			return nil
		end
		local at: Instance? = node
		while at do
			local handler = shiftRoutes[at]
			if handler then
				return handler
			end
			at = at.Parent
		end
		return nil
	end

	function ctx.playWhileShown(timeline: Shared.Playback, node: Instance)
		local owner = assert(Compose.currentOwner(), "Facet playWhileShown requires a Compose owner")
		local ancestryOwner: ComposeTypes.Owner?
		local function locate()
			if owner.isDisposed() then
				return
			end
			if ancestryOwner then
				ancestryOwner.dispose()
			end
			local childOwner = owner.createChild()
			ancestryOwner = childOwner
			Compose.withOwner(childOwner, function()
				local sources: { ComposeTypes.Readable<boolean> } = {}
				local at: Instance? = node
				while at do
					if at:IsA("GuiObject") then
						table.insert(sources, ctx.observe.Visible(at))
					elseif at:IsA("LayerCollector") then
						table.insert(sources, ctx.observe.Enabled(at))
						break
					end
					at = at.Parent
				end
				Compose.watch(function(use: ComposeTypes.Use)
					for _, source in sources do
						if not use(source) then
							timeline:pause()
							return
						end
					end
					timeline:play()
				end)
			end)
		end
		runtime.connect(node, "AncestryChanged", locate)
		locate()
	end
	local function observeStyled(node: Instance, property: string): ComposeTypes.Cell<unknown>
		local initial: unknown = node:GetStyled(property)
		local value = Compose.cell(initial)
		local connection = node:GetStyledPropertyChangedSignal(property):Connect(function()
			local nextValue: unknown = node:GetStyled(property)
			value:set(nextValue)
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
		return value
	end
	ctx.observeStyled = observers(observeStyled)
	local function distance(a: string, b: string): number
		local previous: { number } = {}
		for j = 0, #b do
			previous[j] = j
		end
		for i = 1, #a do
			local current: { number } = { [0] = i }
			for j = 1, #b do
				local cost = if string.byte(a, i) == string.byte(b, j) then 0 else 1
				current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
			end
			previous = current
		end
		return previous[#b]
	end
	local function unknownOption(key: string, known: { [string]: boolean }): string
		local best: string? = nil
		local bestDistance = 3
		for name in known do
			if name ~= "ref" then
				local d = distance(key, name)
				if d < bestDistance or (d == bestDistance and best ~= nil and name < best) then
					best, bestDistance = name, d
				end
			end
		end
		local suggestion = if best then ` Did you mean '{best}'?` else ""
		return `Facet UI.{building or "control"}: unknown option '{key}'.{suggestion}`
	end
	local consumedSets = (
		setmetatable({} :: { [unknown]: { [string]: boolean } }, { __mode = "k" }) :: unknown
	) :: { [unknown]: { [string]: boolean } }
	local function consumedFor(behavioralKeys: { string } | { [string]: boolean }?): { [string]: boolean }
		local frozen = behavioralKeys ~= nil and table.isfrozen(behavioralKeys)
		local cached = if frozen then consumedSets[behavioralKeys] else nil
		if cached then
			return cached
		end
		local consumed: { [string]: boolean } = { ref = true }
		for key, value in ((behavioralKeys or {}) :: unknown) :: { [unknown]: unknown } do
			if type(key) == "number" then
				assert(type(value) == "string")
				consumed[value] = true
			elseif type(key) == "string" then
				consumed[key] = true
			end
		end
		if frozen then
			consumedSets[behavioralKeys] = consumed
		end
		return consumed
	end
	function ctx.props<P>(spec: P, behavioralKeys: { string } | { [string]: boolean }?, defaults: unknown?): P
		local result: { [unknown]: unknown } = if type(defaults) == "table"
			then table.clone(defaults :: { [unknown]: unknown })
			else {}
		local consumed = consumedFor(behavioralKeys)
		for key, value in (spec :: unknown) :: { [unknown]: unknown } do
			if type(key) == "number" then
				result[#result + 1] = value
			elseif type(key) ~= "string" or not consumed[key] then
				if type(key) == "string" and string.match(key, "^[a-z]") then
					error(unknownOption(key, consumed), 0)
				end
				result[key] = value
			end
		end
		return (result :: unknown) :: P
	end
	function ctx.construct<F>(control: string, build: F): F & ((string) -> F)
		assert(type(build) == "function", "Facet constructor requires a builder")
		local apply = (build :: unknown) :: ({ [unknown]: unknown }) -> unknown
		local function construct(fields: { [unknown]: unknown }, name: string?): unknown
			if type(fields) ~= "table" then
				error(`Facet UI.{control}: expected a property table, got {typeof(fields)}`, 0)
			end
			if name then
				fields = table.clone(fields)
				assert(fields.Name == nil, "Facet: supply either a constructor name or Name")
				fields.Name = name
			end
			local outer = building
			building = control
			if Compose.currentOwner() == nil then
				building = outer
				error(
					`Facet UI.{control}: no owner from Facet's Compose is active. Build controls inside app.mount or runtime.mount. `
						.. "If the runtime comes from another Compose instance, "
						.. "bind Facet to that instance with Facet.bind(Compose, Roblox).",
					0
				)
			end
			for key, value in fields do
				if type(key) == "string" then
					if Compose.isReadable(value) then
						if not native[metatableOf(value)] then
							reject(key)
						end
					elseif type(value) == "table" and metatableOf(value) == nil then
						for _, entry in value :: { [unknown]: unknown } do
							if type(entry) == "table" and not Compose.isReadable(entry) then
								for field, inner in entry :: { [unknown]: unknown } do
									if Compose.isReadable(inner) and not native[metatableOf(inner)] then
										reject(`{key}.{tostring(field)}`)
									end
								end
							elseif Compose.isReadable(entry) and not native[metatableOf(entry)] then
								reject(key)
							end
						end
					end
				end
			end
			local node = apply(fields)
			building = outer
			if track and (type(node) == "userdata" or type(node) == "table") then
				track(node :: Instance)
			end
			if fields.ref then
				assert(type(fields.ref) == "function")
				local ref = fields.ref :: (unknown) -> ()
				ref(node)
			end
			return node
		end
		local function overloaded(first: { [unknown]: unknown } | string?): unknown
			if type(first) == "string" then
				return function(fields: { [unknown]: unknown }): unknown
					return construct(fields, first)
				end
			end
			return construct(first or {}, nil)
		end
		return (overloaded :: unknown) :: F & ((string) -> F)
	end
	function ctx.styled<N>(node: N & Instance, role: string): N & Instance
		node:AddTag("facet-" .. string.lower(role))
		return node
	end
	local layout = layoutKit.attach((ctx :: unknown) :: Shared.Context)
	function ctx.padding(horizontal: number, vertical: number): UIPadding
		local sides: Shared.Sides = { top = vertical, right = horizontal, bottom = vertical, left = horizontal }
		return assert(layout.insets(sides))
	end
	local fades = (setmetatable({}, { __mode = "k" }) :: unknown) :: {
		[Instance]: { source: ComposeTypes.Cell<{ Shared.Value<number> }>, transparency: (ComposeTypes.Use) -> number },
	}
	function ctx.fadeTo(node: Instance, value: Shared.Value<number>): ()
		assert(fades[node], "Facet: fadeTo needs a node made by ctx.fade").source:set({ value })
	end
	function ctx.fade(properties: Shared.CanvasGroupNativeProps, persistent: boolean?): Frame
		local fields = (properties :: unknown) :: { [unknown]: unknown }
		local source = Compose.cell({ (fields.GroupTransparency or 0) :: Shared.Value<number> })
		fields.GroupTransparency = nil
		local node = Host.Frame((properties :: unknown) :: Shared.FrameNativeProps)
		local function amount(use: ComposeTypes.Use): number
			return read(use(source)[1] :: Shared.Value<number>, use) or 0
		end
		local shown = ctx.observe.Visible(node)
		local warming = Compose.cell(false)
		local frames = services.RunService
		local function transparency(use: ComposeTypes.Use): number
			return if use(warming) then 1 else amount(use)
		end
		fades[node] = { source = source, transparency = transparency }
		local function paint(use: ComposeTypes.Use): NumberSequence
			return types.NumberSequence.new(transparency(use))
		end
		local latched = Compose.cell(true)
		local stop = runtime.mountFragment(function()
			return {
				Host.UIGradient "FadePaint" { Transparency = paint },
				ctx.styled(
					Host.UIStroke "FadeStroke" {
						Host.UIGradient "FadePaint" {
							Transparency = function(use: ComposeTypes.Use): NumberSequence
								return if use(latched) then types.NumberSequence.new(1) else paint(use)
							end,
						},
					},
					"fade-stroke"
				),
				Compose.show(function(use: ComposeTypes.Use)
					return use(shown) and (persistent == true or amount(use) > 0)
				end, function()
					local automatic = ctx.observe.AutomaticSize(node)
					local leaving = frames ~= nil and (read(source:peek()[1] :: Shared.Value<number>) or 0) < 0.5
					local gather: (() -> ())? = nil
					if frames then
						warming:set(not leaving)
						local connection: RBXScriptConnection? = nil
						connection = frames.Heartbeat:Connect(function()
							if connection then
								connection:Disconnect()
								connection = nil
							end
							warming:set(false)
							if gather then
								gather()
							end
						end)
						Compose.cleanup(function()
							if connection then
								connection:Disconnect()
							end
							warming:set(false)
						end)
					end
					local group = Host.CanvasGroup "Fade" {
						BackgroundTransparency = 1,
						Visible = false,
						Size = function(use: ComposeTypes.Use)
							local mode = use(automatic)
							local freeX = mode == Enum.AutomaticSize.X or mode == Enum.AutomaticSize.XY
							local freeY = mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY
							return types.UDim2.fromScale(if freeX then 0 else 1, if freeY then 0 else 1)
						end,
						AutomaticSize = automatic,
						GroupTransparency = function(use: ComposeTypes.Use)
							return transparency(use)
						end,
					}
					local gui = config.guiService
					local function keepSelection(move: () -> ())
						local held = if gui then gui.SelectedObject else nil
						move()
						if gui and held and gui.SelectedObject ~= held and held:IsDescendantOf(node) then
							gui.SelectedObject = held
						end
					end
					group.Parent = node
					local function carried(child: Instance): boolean
						return child ~= group
							and (
								child:IsA("GuiBase2d")
								or child:IsA("Path2D")
								or child:IsA("Folder")
								or child:IsA("UIGridStyleLayout")
							)
					end
					gather = function()
						gather = nil
						keepSelection(function()
							for _, child: Instance in node:GetChildren() do
								if carried(child) then
									(child :: Instance).Parent = group
								end
							end
							group.Visible = true
						end)
					end
					assert(gather)()
					local collecting = true
					runtime.connect(node, "ChildAdded", function(child: Instance)
						if collecting and carried(child) then
							keepSelection(function()
								child.Parent = group
							end)
						end
					end)
					Compose.cleanup(function()
						collecting = false
						keepSelection(function()
							for _, child in group:GetChildren() do
								child.Parent = node
							end
						end)
					end)
					node:AddTag("facet-fading")
					latched:set(false)
					Compose.cleanup(function()
						node:RemoveTag("facet-fading")
					end)
					return Compose.fragment(function()
						return {}
					end)
				end),
			}
		end, node)
		Compose.cleanup(stop)
		return node
	end
	function ctx.round(use: ComposeTypes.Use?, radius: UDim?): UDim
		return if ctx.metric("radii.pill", use) > 0 then radius or types.UDim.new(1, 0) else types.UDim.new(0, 0)
	end
	function ctx.corner(radius: number?): UICorner
		if radius == nil then
			return Host.UICorner({})
		end
		return Host.UICorner({
			CornerRadius = function(use: ComposeTypes.Use): UDim
				return ctx.round(use, types.UDim.new(0, radius))
			end,
		})
	end
	function ctx.layoutUnit(parent: GuiBase2d, name: string?): ComposeTypes.Readable<number>
		local _, probe = runtime.mount(function()
			return Host.Frame(name or "LayoutUnit")({ Size = types.UDim2.fromOffset(100, 1), Visible = false })
		end, parent)
		local size = ctx.observe.AbsoluteSize(probe :: GuiObject)
		return Compose.formula(function(use: ComposeTypes.Use): number
			local unit = (use(size) :: Vector2).X / 100
			return if unit > 0 then unit else 1
		end)
	end
	function ctx.layoutSize(node: GuiBase2d, unit: ComposeTypes.Readable<number>?): ComposeTypes.Readable<Vector2>
		local size, unit = ctx.observe.AbsoluteSize(node), unit or ctx.layoutUnit(node)
		return Compose.formula(function(use: ComposeTypes.Use): Vector2
			return (use(size) :: Vector2) / use(unit)
		end)
	end
	function ctx.layoutBounds(
		label: TextLabel | TextButton | TextBox,
		unit: ComposeTypes.Readable<number>?
	): ComposeTypes.Readable<Vector2>
		local bounds, unit = ctx.observe.TextBounds(label), unit or ctx.layoutUnit(label)
		return Compose.formula(function(use: ComposeTypes.Use): Vector2
			return (use(bounds) :: Vector2) / use(unit)
		end)
	end
	function ctx.text(properties: Shared.TextLabelNativeProps?): TextLabel
		local native: Shared.TextLabelNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			Size = types.UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			TextXAlignment = Enum.TextXAlignment.Left,
		}
		local fields = (native :: unknown) :: { [unknown]: unknown }
		for key, value in ((properties or {}) :: unknown) :: { [unknown]: unknown } do
			fields[key] = value
		end
		local label = ctx.styled(Host.TextLabel(native), "Text")
		local styledFace, styledSize = ctx.observeStyled.FontFace(label), ctx.observeStyled.TextSize(label)
		local previousFace: Font?, previousSize: number? = nil, nil
		local frames = services.RunService
		local pending: RBXScriptConnection? = nil
		local alive = true
		local refreshing = false
		local function reflow(metrics: boolean?)
			local automatic = label.AutomaticSize
			if automatic ~= Enum.AutomaticSize.None then
				refreshing = true
				local face, points = label:GetStyled("FontFace") :: Font, label:GetStyled("TextSize") :: number
				local resetFace, resetSize =
					metrics == true and label.FontFace ~= face, metrics == true and label.TextSize ~= points
				if resetFace then
					label.FontFace = face
				end
				if resetSize then
					label.TextSize = points
				end
				label.AutomaticSize = Enum.AutomaticSize.None
				label.AutomaticSize = automatic
				if resetFace then
					label:ResetPropertyToDefault("FontFace")
				end
				if resetSize then
					label:ResetPropertyToDefault("TextSize")
				end
				refreshing = false
			end
		end
		local function deferReflow()
			if
				pending == nil
				and frames
				and alive
				and not refreshing
				and label.AutomaticSize ~= Enum.AutomaticSize.None
			then
				local function nextFrame()
					if pending then
						pending:Disconnect()
						pending = nil
					end
					reflow(true)
				end
				pending = if frames.PreRender
					then frames.PreRender:Connect(nextFrame)
					else frames.Heartbeat:Connect(nextFrame)
			end
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local face, points = use(styledFace), use(styledSize)
			if alive and (face ~= previousFace or points ~= previousSize) then
				local changed = previousFace ~= nil or previousSize ~= nil
				previousFace, previousSize = face, points
				reflow()
				if changed or label.FontFace ~= face or label.TextSize ~= points then
					deferReflow()
				end
			end
		end)
		local size, bounds, automatic =
			ctx.observe.AbsoluteSize(label), ctx.observe.TextBounds(label), ctx.observe.AutomaticSize(label)
		Compose.watch(function(use: ComposeTypes.Use)
			local box, glyph, mode = use(size), use(bounds), use(automatic)
			local freeX = mode == Enum.AutomaticSize.X or mode == Enum.AutomaticSize.XY
			local freeY = mode == Enum.AutomaticSize.XY
			if box.X > 0 and box.Y > 0 and ((freeX and glyph.X > box.X) or (freeY and glyph.Y > box.Y)) then
				deferReflow()
			end
		end)
		if label:FindFirstChildWhichIsA("UISizeConstraint") == nil then
			local glyphs = ctx.layoutBounds(label, ctx.layoutUnit(label, "TextBoundsUnit"))
			local wrapped, truncated = ctx.observeStyled.TextWrapped(label), ctx.observeStyled.TextTruncate(label)
			runtime.mount(function()
				return Host.UISizeConstraint "TextBoundsFloor" {
					MinSize = function(use: ComposeTypes.Use): Vector2
						local mode, glyph = use(automatic), use(glyphs)
						local free = use(wrapped) == false and use(truncated) == Enum.TextTruncate.None
						return types.Vector2.new(
							if free and (mode == Enum.AutomaticSize.X or mode == Enum.AutomaticSize.XY)
								then math.ceil(glyph.X)
								else 0,
							if free and (mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY)
								then math.ceil(glyph.Y)
								else 0
						)
					end,
				}
			end, label)
		end
		Compose.cleanup(function()
			alive = false
			if pending then
				pending:Disconnect()
				pending = nil
			end
		end)
		return label
	end
	function ctx.row(children: { ComposeTypes.Child }, properties: Shared.FrameNativeProps?): Frame
		return layout.stack(children, properties, { gap = 8 }, false)
	end
	function ctx.column(children: { ComposeTypes.Child }, properties: Shared.FrameNativeProps?): Frame
		return layout.stack(children, properties, { gap = 8 }, true)
	end
	function ctx.listRow(parts: Shared.ListRow): (Frame, Shared.Value<UDim2>, (GuiObject) -> ())
		for _, caption in parts.captions do
			if caption.Name == "Description" then
				caption:AddTag("facet-secondary")
			end
			if caption:IsA("TextLabel") then
				caption.Size = types.UDim2.fromScale(1, 0)
				caption.AutomaticSize = Enum.AutomaticSize.Y
				caption.TextWrapped = true
			end
		end
		local columns: { ComposeTypes.Child } = table.clone(parts.leading or {})
		table.insert(
			columns,
			ctx.column(parts.captions, {
				Name = "Captions",
				Size = types.UDim2.new(0, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIFlexItem({ FlexMode = Enum.UIFlexMode.Fill }) :: ComposeTypes.Child,
			})
		)
		table.move(parts.trailing or {}, 1, #(parts.trailing or {}), #columns + 1, columns)
		local content = ctx.row(columns, {
			Name = "Content",
			ZIndex = 1,
			Size = types.UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			AnchorPoint = if parts.described then types.Vector2.zero else types.Vector2.new(0, 0.5),
			Position = types.UDim2.fromScale(0, if parts.described then 0 else 0.5),
		})
		assert(content:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = Enum.VerticalAlignment.Center
		local rung: Shared.Value<Shared.ControlSize?>? = parts.controlSize
		local function height(use: ComposeTypes.Use?): UDim2
			return types.UDim2.new(1, 0, 0, ctx.controlSize(rung, "height", use))
		end
		local size = if live(config.theme) or live(rung) then height else height()
		return content,
			size,
			function(node: GuiObject)
				node:AddTag("facet-list-row")
				local captions = assert(content:FindFirstChild("Captions")) :: GuiObject
				local wraps = node.AutomaticSize
				local function hug()
					local parent = node.Parent
					local automatic = if parent and parent:IsA("GuiObject") then parent.AutomaticSize else nil
					local hugging = automatic == Enum.AutomaticSize.X or automatic == Enum.AutomaticSize.XY
					local across = if hugging then Enum.AutomaticSize.XY else Enum.AutomaticSize.Y
					node.AutomaticSize = if hugging then Enum.AutomaticSize.XY else wraps
					content.AutomaticSize, captions.AutomaticSize = across, across
					for _, caption in parts.captions do
						if caption:IsA("TextLabel") then
							caption.Size = types.UDim2.fromScale(if hugging then 0 else 1, 0)
							caption.AutomaticSize = across
						end
					end
				end
				runtime.connect(node, "AncestryChanged", hug)
				hug()
				local function tagRung(use: ComposeTypes.Use?)
					local current = ctx.read(rung, use)
					for _, name in { "xsmall", "compact", "regular", "large" } do
						if current == name then
							node:AddTag("facet-size-" .. name)
						elseif node:HasTag("facet-size-" .. name) then
							node:RemoveTag("facet-size-" .. name)
						end
					end
				end
				if live(rung) then
					Compose.watch(tagRung)
				else
					tagRung()
				end
			end
	end
	function ctx.iconVaries(name: Shared.Value<string>?): boolean
		if name == nil then
			return false
		end
		if live(name) or live(config.theme) or live(config.icons) then
			return true
		end
		local requested = name :: string
		if requested == "" or string.match(requested, "^rbx") then
			return false
		end
		local package: Theme.IconRegistry = ctx.read(config.theme) or {}
		local overrides = ctx.read(config.icons)
		if overrides then
			package = table.clone(package)
			package.icons = overrides
		end
		local resting = themes.resolveIcon(package, requested, "default")
		return themes.resolveIcon(package, requested, "hover") ~= resting
			or themes.resolveIcon(package, requested, "pressed") ~= resting
			or themes.resolveIcon(package, requested, "selected") ~= resting
			or themes.resolveIcon(package, requested, "disabled") ~= resting
	end
	function ctx.icon(
		name: Shared.Value<string>,
		properties: Shared.ImageLabelNativeProps?,
		state: Shared.Value<Theme.SkinState>?
	): ImageLabel
		local function image(use: ComposeTypes.Use?): string
			local requested = ctx.read(name, use)
			if requested == "" then
				return ""
			end
			local package: Theme.IconRegistry = ctx.read(config.theme, use) or {}
			local overrides = ctx.read(config.icons, use)
			if overrides then
				package = table.clone(package)
				package.icons = overrides
			end
			local asset = if type(requested) == "string" and string.match(requested, "^rbx")
				then requested
				else themes.resolveIcon(package, requested, ctx.read(state, use))
			assert(type(asset) == "string", `Facet icon {tostring(requested)} requires an image asset`)
			return asset
		end
		local native: Shared.ImageLabelNativeProps = {
			Image = if live(name) or live(config.theme) or live(config.icons) or live(state) then image else image(),
			BackgroundTransparency = 1,
		}
		local function iconSize(use: ComposeTypes.Use?): UDim2
			local size = ctx.controlSize(config.controlSize, "iconSize", use)
			return types.UDim2.fromOffset(size, size)
		end
		local function resample(use: ComposeTypes.Use?): Enum.ResamplerMode
			local package = ctx.read(config.theme, use)
			return if package and package.identity.rendering == "pixel"
				then Enum.ResamplerMode.Pixelated
				else Enum.ResamplerMode.Default
		end
		local themeLive = live(config.theme)
		native.Size = if themeLive or live(config.controlSize) then iconSize else iconSize()
		if themeLive then
			native.ResampleMode = resample
		elseif resample() ~= Enum.ResamplerMode.Default then
			native.ResampleMode = resample()
		end
		local fields = (native :: unknown) :: { [unknown]: unknown }
		for key, value in ((properties or {}) :: unknown) :: { [unknown]: unknown } do
			fields[key] = value
		end
		return ctx.styled(Host.ImageLabel(native), "Icon")
	end
	ctx.modalScopes = Compose.cell({} :: { Instance })
	ctx.modalPortals = Compose.cell({} :: { ModalPortal })
	function ctx.modalPortal(node: Instance, anchor: Instance)
		local entry = { node = node, anchor = anchor }
		local entries = table.clone(ctx.modalPortals:peek())
		table.insert(entries, entry)
		ctx.modalPortals:set(entries)
		Compose.cleanup(function()
			local remaining = {}
			for _, portal in ctx.modalPortals:peek() do
				if portal ~= entry then
					table.insert(remaining, portal)
				end
			end
			ctx.modalPortals:set(remaining)
		end)
	end
	function ctx.available(node: Instance, use: ComposeTypes.Use?): boolean
		local scopes = ctx.read(ctx.modalScopes, use)
		local portals = ctx.readSource(ctx.modalPortals, use)
		local modal: Instance? = scopes[#scopes]
		local function inside(at: Instance?, visited: { [Instance]: boolean }): boolean
			if not at or visited[at] then
				return false
			end
			visited[at] = true
			while at do
				if at == modal then
					return true
				end
				for _, portal in portals do
					if at == portal.node and inside(portal.anchor, visited) then
						return true
					end
				end
				at = at.Parent
			end
			return false
		end
		local inModal = modal == nil or inside(node, {})
		local at: Instance? = node
		while at do
			if at:IsA("GuiObject") and (not at.Visible or not at.Interactable) then
				return false
			end
			if at:IsA("LayerCollector") and not at.Enabled then
				return false
			end
			at = at.Parent
		end
		return inModal
	end
	type ActionGroup = {
		context: InputContext,
		parent: ComposeTypes.Cell<Instance?>,
		available: ComposeTypes.Cell<boolean>,
	}
	local selected: selection.Selection
	function ctx.reserveKeys(handler: Shared.ReservedKeyHandler): ()
		local input = config.userInputService
		if input == nil then
			return
		end
		Compose.cleanup(reservedKeys.add(input, (Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode }, handler))
	end
	function ctx.navigationGamepads(): { Enum.UserInputType }
		local service = config.userInputService
		local probe = (service :: unknown) :: {
			GetNavigationGamepads: ((UserInputService) -> { Enum.UserInputType })?,
			GetLastInputType: ((UserInputService) -> Enum.UserInputType)?,
		}
		if service and probe.GetNavigationGamepads then
			local pads = service:GetNavigationGamepads()
			if #pads > 0 then
				return pads
			end
		end
		local last = if service and probe.GetLastInputType then service:GetLastInputType() else nil
		if last and string.find(last.Name, "^Gamepad") then
			return { last }
		end
		return { Enum.UserInputType.Gamepad1 }
	end
	local actionGroups = (
		setmetatable({}, { __mode = "k" }) :: unknown
	) :: { [ComposeTypes.Owner]: { [Instance]: { [string]: ActionGroup } } }
	function ctx.action(
		node: Instance,
		name: string,
		keyCodes: Shared.ActionBindings,
		enabledSource: Shared.Value<boolean>?,
		onPressed: () -> (),
		actionSettings: ActionSettings?
	)
		local settings: ActionSettings = actionSettings or {}
		local owner = assert(Compose.currentOwner(), "Facet action requires a Compose owner")
		local group: ActionGroup? = nil
		if settings.group then
			local byNode = actionGroups[owner]
			if byNode == nil then
				byNode = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: { [string]: ActionGroup } }
				actionGroups[owner] = byNode
			end
			local named = byNode[node]
			if named == nil then
				named = {}
				byNode[node] = named
			end
			group = named[settings.group]
		end
		local parent: ComposeTypes.Cell<Instance?>
		local available: ComposeTypes.Cell<boolean>
		if group then
			parent, available = group.parent, group.available
		else
			parent = Compose.cell(nil :: Instance?)
			available = Compose.cell(false)
			local ancestryOwner: ComposeTypes.Owner?
			local function locate()
				if owner.isDisposed() then
					return
				end
				if ancestryOwner then
					ancestryOwner.dispose()
					ancestryOwner = nil
				end
				local inputParent: Instance? = config.inputParent
				if inputParent == nil then
					local root: Instance? = node
					while root and not root:IsA("LayerCollector") do
						root = root.Parent
					end
					if root == nil then
						parent:set(nil :: Instance?)
						available:set(false)
						return
					end
				end
				local childOwner = owner.createChild()
				ancestryOwner = childOwner
				Compose.withOwner(childOwner, function()
					local sources: { ComposeTypes.Readable<boolean> } = {}
					local at: Instance? = node
					local collector: Instance? = nil
					while at do
						if at:IsA("GuiObject") then
							table.insert(sources, ctx.observe.Visible(at))
							table.insert(sources, ctx.observe.Interactable(at))
						elseif at:IsA("LayerCollector") then
							collector = at
							table.insert(sources, ctx.observe.Enabled(at))
							break
						end
						at = at.Parent
					end
					local target: Instance? = if inputParent then inputParent else collector
					parent:set(target)
					Compose.watch(function(use: ComposeTypes.Use)
						local enabled = true
						for _, source in sources do
							if use(source) == false then
								enabled = false
							end
						end
						available:set(enabled)
					end)
				end)
			end
			locate()
			runtime.connect(node, "AncestryChanged", locate)
		end
		local gui = config.guiService
		local selection = if gui and gui.GetPropertyChangedSignal then ctx.observe.SelectedObject(gui) else nil
		local stale = false
		local viaAction, viaInput = false, false
		local p: Shared.InputActionNativeProps = {
			Name = name,
			Type = if settings.direction2D then Enum.InputActionType.Direction2D else Enum.InputActionType.Bool,
			StateChanged = settings.direction2D :: ((unknown) -> ())?,
			Pressed = function()
				if stale or viaInput then
					return
				end
				viaAction = true
				if available:peek() and ctx.available(node) and ctx.read(enabledSource) ~= false then
					onPressed()
				end
			end,
			Released = function()
				stale = false
				viaAction = false
				if settings.onReleased then
					settings.onReleased()
				end
			end,
		}
		local function bind(binding: Shared.ActionBinding): Instance
			return Host.InputBinding(if type(binding) == "table"
				then binding
				else {
					KeyCode = if type(binding) == "string"
						then ((Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode })[binding]
						else binding,
				})
		end
		for _, binding in keyCodes :: { Shared.ActionBinding } do
			p[#p + 1] = bind(binding)
		end
		local conditional = settings.conditional
		if conditional then
			p[#p + 1] = Compose.show(conditional.when, function()
				return bind(conditional.binding)
			end)
		end
		local action = Host.InputAction(p)
		local enabled = Compose.formula(function(use: ComposeTypes.Use): boolean
			if selection then
				use(selection)
			end
			return use(parent) ~= nil
				and use(available)
				and ctx.read(enabledSource, use) ~= false
				and ctx.available(node, use)
		end)
		local reservedBound: { [string]: boolean } = {}
		for _, binding in keyCodes :: { Shared.ActionBinding } do
			local code: unknown = if type(binding) == "string"
				then ((Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode })[binding]
				elseif type(binding) == "table" then (binding :: Shared.InputBindingNativeProps).KeyCode
				else binding
			local codeName = if code ~= nil then (code :: Enum.KeyCode).Name else nil
			if codeName and reservedKeys.KEYS[codeName] then
				reservedBound[codeName] = true
			end
		end
		if next(reservedBound) ~= nil and config.userInputService then
			ctx.reserveKeys({
				keys = reservedBound,
				priority = settings.priority or 2000,
				sink = settings.sink ~= false,
				node = node,
				gui = config.guiService,
				enabled = function(): boolean
					return enabled:peek()
				end,
				press = function()
					if viaAction then
						return
					end
					viaInput = true
					if available:peek() and ctx.available(node) and ctx.read(enabledSource) ~= false then
						onPressed()
					end
				end,
				release = function()
					local pressed = viaInput
					viaAction, viaInput = false, false
					if pressed and settings.onReleased then
						settings.onReleased()
					end
				end,
			})
		end
		local keyInput = config.userInputService
		local held = function(): boolean
			return false
		end
		if keyInput then
			local probe = (keyInput :: unknown) :: {
				IsKeyDown: ((UserInputService, Enum.KeyCode) -> boolean)?,
				IsGamepadButtonDown: ((UserInputService, Enum.UserInputType, Enum.KeyCode) -> boolean)?,
			}
			function held(): boolean
				for _, binding in keyCodes :: { Shared.ActionBinding } do
					local code: unknown = if type(binding) == "string"
						then ((Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode })[binding]
						elseif type(binding) == "table" then (binding :: Shared.InputBindingNativeProps).KeyCode
						else binding
					if typeof(code) == "EnumItem" or type(code) == "table" then
						local key = code :: Enum.KeyCode
						if probe.IsGamepadButtonDown then
							for _, pad in ctx.navigationGamepads() do
								if keyInput:IsGamepadButtonDown(pad, key) then
									return true
								end
							end
						end
						if probe.IsKeyDown and keyInput:IsKeyDown(key) then
							return true
						end
					end
				end
				return false
			end
			local wasOn = false
			Compose.watch(function(use: ComposeTypes.Use)
				local on = use(enabled)
				if on and not wasOn then
					stale = held()
				end
				wasOn = on
			end)
		end
		local context: InputContext
		if group then
			context = group.context
			runtime.decorate(action, { Enabled = enabled })
			action.Parent = context
		elseif settings.group then
			runtime.decorate(action, { Enabled = enabled })
			context = Host.InputContext("Facet" .. settings.group)({
				Parent = parent,
				Priority = settings.priority or 2000,
				Sink = settings.sink ~= false,
				Enabled = function(use: ComposeTypes.Use): boolean
					return use(parent) ~= nil and use(available)
				end,
				action,
			})
			local byNode = actionGroups[owner][node]
			byNode[settings.group] = { context = context, parent = parent, available = available }
		else
			context = Host.InputContext("Facet" .. name)({
				Parent = parent,
				Priority = settings.priority or 2000,
				Sink = settings.sink ~= false,
				Enabled = enabled,
				action,
			})
		end
		local inputService = config.userInputService
		if settings.capture and gui and selection and inputService then
			local steering: { [string]: string } = {}
			for _, binding in keyCodes :: { Shared.ActionBinding } do
				local code: unknown = if type(binding) == "string"
					then ((Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode })[binding]
					elseif type(binding) == "table" then (binding :: Shared.InputBindingNativeProps).KeyCode
					else binding
				for _, direction in { "Up", "Down", "Left", "Right" } do
					local keys = (Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode }
					if code == keys[direction] or code == keys["DPad" .. direction] then
						steering[(code :: Enum.KeyCode).Name] = direction
					end
				end
			end
			local directions: { string } = {}
			if next(steering) == nil then
				return action, context
			end
			for _, direction in steering do
				if not table.find(directions, direction) then
					table.insert(directions, direction)
				end
			end
			local steerable = Compose.formula(function(use: ComposeTypes.Use): boolean
				return use(enabled) and use(selection) ~= nil
			end)
			local function nextSelection(target: GuiObject, direction: string): GuiObject?
				if direction == "Up" then
					return target.NextSelectionUp
				elseif direction == "Down" then
					return target.NextSelectionDown
				elseif direction == "Left" then
					return target.NextSelectionLeft
				end
				return target.NextSelectionRight
			end
			local function setNextSelection(target: GuiObject, direction: string, value: GuiObject?): ()
				if direction == "Up" then
					target.NextSelectionUp = value :: GuiObject
				elseif direction == "Down" then
					target.NextSelectionDown = value :: GuiObject
				elseif direction == "Left" then
					target.NextSelectionLeft = value :: GuiObject
				else
					target.NextSelectionRight = value :: GuiObject
				end
			end
			local pinned: GuiObject? = nil
			local previous: { [string]: GuiObject? } = {}
			local function release(): ()
				local target = pinned
				if target then
					for _, direction in directions do
						if nextSelection(target, direction) == target then
							setNextSelection(target, direction, previous[direction])
						end
					end
				end
				pinned = nil
				table.clear(previous)
			end
			Compose.watch(function(use: ComposeTypes.Use)
				local target = if use(steerable) then use(selection) :: GuiObject? else nil
				if target == pinned then
					return
				end
				if not held() then
					viaAction, viaInput = false, false
				end
				release()
				if target then
					pinned = target
					for _, direction in directions do
						previous[direction] = nextSelection(target, direction)
						setNextSelection(target, direction, target)
					end
				end
			end)
			Compose.cleanup(release)
			runtime.connect(inputService, "InputBegan", function(event: InputObject)
				if event.KeyCode and steering[event.KeyCode.Name] and steerable:peek() and not viaAction then
					viaInput = true
					if available:peek() and ctx.available(node) and ctx.read(enabledSource) ~= false then
						onPressed()
					end
				end
			end)
			local released = settings.onReleased
			runtime.connect(inputService, "InputEnded", function(event: InputObject)
				if event.KeyCode and steering[event.KeyCode.Name] then
					viaAction, viaInput = false, false
					if released then
						released()
					end
				end
			end)
		end
		return action, context
	end

	function ctx.skin(
		node: GuiObject,
		slot: string,
		skinOptions: Shared.SkinStateOptions?
	): (ComposeTypes.Dispose?, GuiObject?)
		if config.theme == nil then
			return nil, nil
		end
		if not Compose.isReadable(config.theme) and type(config.theme) ~= "function" then
			local package = config.theme :: Theme.ThemePackage
			local recipe = (package.chrome or {})[slot]
			if recipe == nil or ((recipe.kind == "native" or recipe.kind == "none") and recipe.shadow == nil) then
				return nil, nil
			end
		end
		local state = ctx.observe.GuiState(node)
		local stateOptions: Shared.SkinStateOptions = skinOptions or {}
		local background = observeStyled(node, "BackgroundTransparency")
		local dispose, art = runtime.mount(function()
			return themes.skin(runtime, config.theme, slot, {
				types = types,
				target = node,
				shadowTransparency = function(use: ComposeTypes.Use)
					local package = ctx.read(config.theme, use)
					local recipe = package and (package.chrome or {})[slot]
					local transparent = recipe and recipe.kind == "native" and use(background) == 1
					return if transparent then 1 elseif fades[node] then fades[node].transparency(use) else 0
				end,
				label = if stateOptions.label ~= nil
					then stateOptions.label
					elseif node:IsA("TextButton") or node:IsA("TextLabel") then ctx.observe.Text(node)
					else nil,
				onCaption = stateOptions.onCaption,
				state = function(use: ComposeTypes.Use)
					if ctx.read(stateOptions.disabled, use) == true then
						return "disabled"
					end
					local value = use(state)
					if value == Enum.GuiState.Press then
						return "pressed"
					end
					if value == Enum.GuiState.Hover then
						return "hover"
					end
					if ctx.read(stateOptions.selected, use) == true then
						return "selected"
					end
					return "default"
				end,
				selected = function(use: ComposeTypes.Use)
					return ctx.read(stateOptions.selected, use) == true
				end,
				ZIndex = 0,
			})
		end, node)
		if art and node:FindFirstChildWhichIsA("UIGridStyleLayout") then
			local _, chrome = runtime.mount(function()
				return Host.Folder "Chrome" {}
			end, node);
			(art :: GuiObject).Parent = chrome :: Instance
		end
		return dispose, art :: GuiObject?
	end

	function ctx.responder(root: Instance, options: Shared.ResponderOptions?): Shared.Responder
		return selected.responder(root, options)
	end
	function ctx.spaceActivates(node: Instance): (ComposeTypes.Use) -> boolean
		return selected.spaceActivates(node)
	end
	selected = selection(ctx)
	track = selected.track
	return ctx
end
