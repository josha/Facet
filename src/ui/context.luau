--!strict
local ComposeTypes = require("../vendor/compose/core")
local bindThemes = require("./themes")
local Shared = require("./types")
local Theme = require("./theme_types")
local layoutKit = require("./layout_kit")
local selection = require("./selection")

type ModalPortal = { node: Instance, anchor: Instance }
type ActionSettings = { onReleased: (() -> ())?, priority: number?, sink: boolean?, capture: boolean? }
return function(Compose: Shared.ComposeModule, runtime: ComposeTypes.Runtime, options: Shared.Config?): Shared.Context
	assert(runtime.host.name == "roblox", "Facet.controls requires a Compose Roblox runtime")
	local config: Shared.Config = table.clone(options or {})
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
	local services: Shared.Services = table.clone(config.services or {})
	if game then
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
	local function live(value: unknown): boolean
		return Compose.isReadable(value) or type(value) == "function"
	end
	local defaultMetrics = themes.neutralPackage().metrics
	local function metricAt(value: unknown, path: string): number?
		for key in string.gmatch(path, "[^.]+") do
			if type(value) ~= "table" then
				return nil
			end
			value = (value :: { [string]: unknown })[key]
		end
		return if type(value) == "number" and value == value and math.abs(value) ~= math.huge then value else nil
	end
	function ctx.metric(path: string, use: ComposeTypes.Use?): number
		local package = ctx.read(config.theme, use)
		return assert(
			metricAt(if package then package.metrics else nil, path) or metricAt(defaultMetrics, path),
			`Facet numeric metric {path} is missing`
		)
	end
	function ctx.controlSize(
		source: Shared.Value<Shared.ControlSize>?,
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
	local function observe(node: Instance, property: string): ComposeTypes.Cell<unknown>
		local observation = assert(runtime.host.observation, "Roblox property observation is required")
		if serviceNodes[node] then
			local byProperty = sharedObservations[node]
			if byProperty == nil then
				byProperty = {}
				sharedObservations[node] = byProperty
			end
			local entry = byProperty[property]
			if entry == nil then
				local cell = Compose.cell(observation.readProperty(node, property))
				local created: SharedObservation = {
					cell = cell,
					users = 0,
					stop = observation.observeProperty(node, property, function()
						cell:set(observation.readProperty(node, property))
					end),
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
				end
			end)
			held.users += 1
			return held.cell
		end
		local value = Compose.cell(observation.readProperty(node, property))
		Compose.cleanup(observation.observeProperty(node, property, function()
			value:set(observation.readProperty(node, property))
		end))
		return value
	end
	ctx.observe = (observe :: unknown) :: Shared.Observe
	type SelectionWaiters = { waiting: { [Instance]: () -> () }, count: number, stop: (() -> ())? }
	local selectionWaiters: { [Instance]: SelectionWaiters } = {}
	function ctx.whenSelected(gui: Instance, node: Instance, callback: () -> ()): ()
		local observation = assert(runtime.host.observation, "Roblox property observation is required")
		local waiters = selectionWaiters[gui]
		if waiters == nil then
			waiters = { waiting = {}, count = 0, stop = nil }
			selectionWaiters[gui] = waiters
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
			observe(input, "MouseEnabled"), observe(input, "TouchEnabled"), observe(input, "GamepadEnabled")
		return function(use: ComposeTypes.Use?): boolean
			return ctx.read(mouse, use) == true and ctx.read(touch, use) ~= true and ctx.read(gamepad, use) ~= true
		end
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
						table.insert(sources, ctx.observe(at, "Visible"))
					elseif at:IsA("LayerCollector") then
						table.insert(sources, ctx.observe(at, "Enabled"))
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
	ctx.observeStyled = (observeStyled :: unknown) :: Shared.Observe
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
		return assert(layout.insets({ top = vertical, right = horizontal, bottom = vertical, left = horizontal }))
	end
	function ctx.corner(radius: number?): UICorner
		return if radius then Host.UICorner({ CornerRadius = types.UDim.new(0, radius) }) else Host.UICorner({})
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
		return ctx.styled(Host.TextLabel(native), "Text")
	end
	function ctx.row(children: { ComposeTypes.Child }, properties: Shared.FrameNativeProps?): Frame
		return layout.stack(children, properties, { gap = 8 }, false)
	end
	function ctx.column(children: { ComposeTypes.Child }, properties: Shared.FrameNativeProps?): Frame
		return layout.stack(children, properties, { gap = 8 }, true)
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
		local portals = ctx.read(ctx.modalPortals, use)
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
	function ctx.action(
		node: Instance,
		name: string,
		keyCodes: { Shared.ActionBinding },
		enabledSource: Shared.Value<boolean>?,
		onPressed: () -> (),
		actionSettings: ActionSettings?
	)
		local settings: ActionSettings = actionSettings or {}
		local owner = assert(Compose.currentOwner(), "Facet action requires a Compose owner")
		local parent = Compose.cell(nil :: Instance?)
		local available = Compose.cell(false)
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
						table.insert(sources, ctx.observe(at, "Visible"))
						table.insert(sources, ctx.observe(at, "Interactable"))
					elseif at:IsA("LayerCollector") then
						collector = at
						table.insert(sources, ctx.observe(at, "Enabled"))
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
		local gui = config.guiService
		local selection = if gui and gui.GetPropertyChangedSignal then ctx.observe(gui, "SelectedObject") else nil
		local p: Shared.InputActionNativeProps = {
			Name = name,
			Type = Enum.InputActionType.Bool,
			Pressed = function()
				if available:peek() and ctx.available(node) and ctx.read(enabledSource) ~= false then
					onPressed()
				end
			end,
		}
		if settings.onReleased then
			p.Released = settings.onReleased
		end
		for _, binding in keyCodes do
			table.insert(
				p,
				Host.InputBinding(if type(binding) == "table"
					then binding
					else {
						KeyCode = if type(binding) == "string"
							then ((Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode })[binding]
							else binding,
					})
			)
		end
		local action = Host.InputAction(p)
		local function enabled(use: ComposeTypes.Use): boolean
			if selection then
				use(selection)
			end
			return use(parent) ~= nil
				and use(available)
				and ctx.read(enabledSource, use) ~= false
				and ctx.available(node, use)
		end
		local context = Host.InputContext({
			Name = "Facet" .. name,
			Parent = parent,
			Priority = settings.priority or 2000,
			Sink = settings.sink ~= false,
			Enabled = enabled,
			action,
		})
		local inputService = config.userInputService
		if settings.capture and gui and selection and inputService then
			local steering: { [string]: string } = {}
			for _, binding in keyCodes do
				local code = if type(binding) == "string"
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
				return enabled(use) and use(selection) ~= nil
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
				if event.KeyCode and steering[event.KeyCode.Name] and steerable:peek() then
					if available:peek() and ctx.available(node) and ctx.read(enabledSource) ~= false then
						onPressed()
					end
				end
			end)
			if settings.onReleased then
				local released = settings.onReleased
				runtime.connect(inputService, "InputEnded", function(event: InputObject)
					if event.KeyCode and steering[event.KeyCode.Name] then
						released()
					end
				end)
			end
		end
		return action, context
	end

	function ctx.skin(node: GuiObject, slot: string, skinOptions: Shared.SkinStateOptions?): ComposeTypes.Dispose?
		if config.theme == nil then
			return nil
		end
		if not Compose.isReadable(config.theme) and type(config.theme) ~= "function" then
			local package = config.theme :: Theme.ThemePackage
			local recipe = (package.chrome or {})[slot]
			if recipe == nil or ((recipe.kind == "native" or recipe.kind == "none") and recipe.shadow == nil) then
				return nil
			end
		end
		local state = ctx.observe(node, "GuiState")
		local stateOptions: Shared.SkinStateOptions = skinOptions or {}
		return runtime.mount(function()
			return themes.skin(runtime, config.theme, slot, {
				types = types,
				target = node,
				label = if node:IsA("TextButton")
					then ctx.observe(node, "Text")
					elseif node:IsA("TextLabel") then ctx.observe(node, "Text")
					else nil,
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
				ZIndex = 0,
			})
		end, node)
	end

	track = selection(ctx)
	return ctx
end
