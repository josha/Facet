--!strict
local Compose = require("../vendor/compose/core")
local themes = require("./themes")
local Shared = require("./types")
local Theme = require("./theme_types")

type ModalPortal = { node: Instance, anchor: Instance }
type ActionSettings = { onReleased: (() -> ())?, priority: number?, sink: boolean? }
return function(runtime: Compose.Runtime, options: Shared.Config?): Shared.Context
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
	end
	config.services = services
	config.guiService = config.guiService or services.GuiService
	config.userInputService = config.userInputService or services.UserInputService
	local Host = (runtime.constructors :: unknown) :: Shared.Host
	local Enum = types.Enum
	local ctx = {
		runtime = runtime,
		Host = Host,
		Compose = Compose,
		types = types,
		config = config :: Shared.ResolvedConfig,
		metrics = { textSize = 16, controlHeight = 36, gap = 8, cornerRadius = 8 },
	}
	local function read<T>(value: T | Compose.Source<T>, use: Compose.Use?): T
		if Compose.isReadable(value) then
			local source = value :: Compose.Readable<T>
			return if use then use(source) else source:peek()
		elseif type(value) == "function" then
			local body = value :: Compose.Body<T>
			return body(use or function<U>(source: Compose.Readable<U>): U
				return source:peek()
			end)
		end
		return value :: T
	end
	ctx.read = (read :: unknown) :: Shared.Read
	local defaultMetrics = themes.neutralPackage().metrics
	local function metricAt(value: unknown, path: string): number?
		for key in string.gmatch(path, "[^.]+") do
			if type(value) ~= "table" then
				return nil
			end
			value = (value :: { [string]: unknown })[key]
		end
		return if type(value) == "number" then value else nil
	end
	function ctx.metric(path: string, use: Compose.Use?): number
		local package = ctx.read(config.theme, use)
		return assert(
			metricAt(if package then package.metrics else nil, path) or metricAt(defaultMetrics, path),
			`Facet numeric metric {path} is missing`
		)
	end
	function ctx.controlSize(
		source: Shared.Value<Shared.ControlSize>?,
		field: "height" | "paddingX" | "iconSize",
		use: Compose.Use?
	): number
		local requested = ctx.read(source, use)
		local rung = if requested == nil then "regular" else requested
		assert(
			rung == "compact" or rung == "regular" or rung == "large",
			"Facet controlSize must be compact, regular or large"
		)
		return ctx.metric("controlSizes." .. rung .. "." .. field, use)
	end
	local function observe(node: Instance, property: string): Compose.Cell<unknown>
		local observation = assert(runtime.host.observation, "Roblox property observation is required")
		local value = Compose.cell(observation.readProperty(node, property))
		Compose.cleanup(observation.observeProperty(node, property, function()
			value:set(observation.readProperty(node, property))
		end))
		return value
	end
	ctx.observe = (observe :: unknown) :: Shared.Observe
	local function observeStyled(node: Instance, property: string): Compose.Cell<unknown>
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
	function ctx.props<P>(spec: P, behavioralKeys: { string } | { [string]: boolean }?, defaults: unknown?): P
		local result: { [unknown]: unknown } = if type(defaults) == "table"
			then table.clone(defaults :: { [unknown]: unknown })
			else {}
		local consumed: { [string]: boolean } = { ref = true }
		for key, value in ((behavioralKeys or {}) :: unknown) :: { [unknown]: unknown } do
			if type(key) == "number" then
				assert(type(value) == "string")
				consumed[value] = true
			elseif type(key) == "string" then
				consumed[key] = true
			end
		end
		for key, value in (spec :: unknown) :: { [unknown]: unknown } do
			if type(key) == "number" then
				result[#result + 1] = value
			elseif type(key) ~= "string" or not consumed[key] then
				assert(type(key) ~= "string" or not string.match(key, "^[a-z]"), `Unknown Facet option {tostring(key)}`)
				result[key] = value
			end
		end
		return (result :: unknown) :: P
	end
	function ctx.construct<F>(build: F): F & ((string) -> F)
		assert(type(build) == "function", "Facet constructor requires a builder")
		local apply = (build :: unknown) :: ({ [unknown]: unknown }) -> unknown
		local function construct(fields: { [unknown]: unknown }, name: string?): unknown
			assert(type(fields) == "table", "Facet control expects a property table")
			if name then
				fields = table.clone(fields)
				assert(fields.Name == nil, "Facet: supply either a constructor name or Name")
				fields.Name = name
			end
			local node = apply(fields)
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
	function ctx.padding(horizontal: number, vertical: number): UIPadding
		return Host.UIPadding({
			PaddingLeft = types.UDim.new(0, horizontal),
			PaddingRight = types.UDim.new(0, horizontal),
			PaddingTop = types.UDim.new(0, vertical),
			PaddingBottom = types.UDim.new(0, vertical),
		})
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
	local function stack(
		children: { Compose.Child },
		properties: Shared.FrameNativeProps?,
		direction: Enum.FillDirection
	): Frame
		local native: Shared.FrameNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = types.UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Host.UIListLayout({
				FillDirection = direction,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = types.UDim.new(0, 8),
			}),
		}
		local fields = (native :: unknown) :: { [unknown]: unknown }
		for key, value in ((properties or {}) :: unknown) :: { [unknown]: unknown } do
			if type(key) == "number" then
				fields[#fields + 1] = value
			else
				fields[key] = value
			end
		end
		for index, child in children do
			if type(child) ~= "function" then
				local node = child :: Instance
				if node:IsA("GuiObject") then
					runtime.decorate(node, { LayoutOrder = index })
				end
			end
			table.insert(native, child)
		end
		return Host.Frame(native)
	end
	function ctx.row(children: { Compose.Child }, properties: Shared.FrameNativeProps?): Frame
		return stack(children, properties, Enum.FillDirection.Horizontal)
	end
	function ctx.column(children: { Compose.Child }, properties: Shared.FrameNativeProps?): Frame
		return stack(children, properties, Enum.FillDirection.Vertical)
	end
	function ctx.icon(
		name: Shared.Value<string>,
		properties: Shared.ImageLabelNativeProps?,
		state: Shared.Value<Theme.SkinState>?
	): ImageLabel
		local native: Shared.ImageLabelNativeProps = {
			Image = function(use: Compose.Use)
				local requested = ctx.read(name, use)
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
			end,
			BackgroundTransparency = 1,
			Size = function(use: Compose.Use)
				local size = ctx.controlSize(config.controlSize, "iconSize", use)
				return types.UDim2.fromOffset(size, size)
			end,
			ResampleMode = function(use: Compose.Use)
				local package = ctx.read(config.theme, use)
				return if package and package.identity.rendering == "pixel"
					then Enum.ResamplerMode.Pixelated
					else Enum.ResamplerMode.Default
			end,
		}
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
	function ctx.available(node: Instance, use: Compose.Use?): boolean
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
		local ancestryOwner: Compose.Owner?
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
				local sources: { Compose.Readable<boolean> } = {}
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
				parent:set(config.inputParent or collector)
				Compose.watch(function(use: Compose.Use)
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
		local context = Host.InputContext({
			Name = "Facet" .. name,
			Parent = parent,
			Priority = settings.priority or 2000,
			Sink = settings.sink ~= false,
			Enabled = function(use: Compose.Use)
				if selection then
					use(selection)
				end
				return use(parent) ~= nil
					and use(available)
					and ctx.available(node, use)
					and ctx.read(enabledSource, use) ~= false
			end,
			action,
		})
		return action, context
	end

	function ctx.skin(node: GuiObject, slot: string, skinOptions: Shared.SkinStateOptions?): Compose.Dispose?
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
				state = function(use: Compose.Use)
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

	return ctx
end
