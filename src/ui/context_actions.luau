--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local reservedKeys = require("./reserved_keys")

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

return function(ctx: Shared.Context, config: Shared.Config)
	local Compose, runtime, Host, Enum = ctx.Compose, ctx.runtime, ctx.Host, ctx.types.Enum
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
		local registry = waiters
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
	local shiftRoutes: { [Instance]: () -> () } = setmetatable({}, { __mode = "k" })
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
			or not (type(input) == "table" or (typeof(input) == "Instance" and input:IsA("InputObject")))
			or input.KeyCode ~= Enum.KeyCode.Return
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
	local function withinModal(node: Instance, use: ComposeTypes.Use?): boolean
		local scopes = ctx.readSource(ctx.modalScopes, use)
		local modal: Instance? = scopes[#scopes]
		if modal == nil then
			return true
		end
		local portals = ctx.readSource(ctx.modalPortals, use)
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
		return inside(node, {})
	end
	ctx.withinModal = withinModal
	local GUI, LAYER, OPEN = 1, 2, 0
	local gates: { [Instance]: number } = setmetatable({}, { __mode = "k" })
	function ctx.available(node: Instance, use: ComposeTypes.Use?): boolean
		local at: Instance? = node
		while at do
			local gate = gates[at]
			if gate == nil then
				gate = if at:IsA("GuiObject") then GUI elseif at:IsA("LayerCollector") then LAYER else OPEN
				gates[at] = gate
			end
			if gate == GUI then
				local gui = at :: GuiObject
				if not gui.Visible or not gui.Interactable then
					return false
				end
			elseif gate == LAYER and not (at :: LayerCollector).Enabled then
				return false
			end
			at = at.Parent
		end
		return withinModal(node, use)
	end
	type ActionGroup = {
		context: InputContext,
	}
	type ActionScope = {
		parent: ComposeTypes.Value<Instance?>,
		available: ComposeTypes.Value<boolean>,
		groups: { [string]: ActionGroup },
	}
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
	local actionScopes: { [ComposeTypes.Owner]: { [Instance]: ActionScope } } = setmetatable({}, { __mode = "k" })
	function ctx.action(
		node: Instance,
		name: string,
		keyCodes: Shared.ActionBindings,
		enabledSource: Shared.Input<boolean>?,
		onPressed: () -> (),
		actionSettings: ActionSettings?
	)
		local settings: ActionSettings = actionSettings or {}
		local owner = assert(Compose.currentOwner(), "Facet action requires a Compose owner")
		local byNode = actionScopes[owner]
		if byNode == nil then
			local nodes: { [Instance]: ActionScope } = setmetatable({}, { __mode = "k" })
			actionScopes[owner] = nodes
			byNode = nodes
		end
		local scope = byNode[node]
		if scope == nil then
			local parent: ComposeTypes.Value<Instance?> = Compose.cell(nil :: Instance?)
			local available = Compose.cell(false)
			local ancestryOwner: ComposeTypes.Owner?
			local function locate()
				if ComposeTypes.owner.isDisposed(owner) then
					return
				end
				if ancestryOwner then
					ComposeTypes.owner.dispose(ancestryOwner)
					ancestryOwner = nil
				end
				local inputParent: Instance? = config.inputParent
				if inputParent == nil then
					local root: Instance? = node
					while root and not root:IsA("LayerCollector") do
						root = root.Parent
					end
					if root == nil then
						parent:set(nil)
						available:set(false)
						return
					end
				end
				local childOwner = ComposeTypes.owner.createChild(owner)
				ancestryOwner = childOwner
				Compose.withOwner(childOwner, function()
					local sources: { ComposeTypes.ReadOnlyValue<boolean> } = {}
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
			local created: ActionScope = { parent = parent, available = available, groups = {} }
			scope = created
			byNode[node] = created
		end
		local activeScope = assert(scope)
		local parent, available = activeScope.parent, activeScope.available
		local groups = activeScope.groups
		local group = if settings.group then groups[settings.group] else nil
		local gui = config.guiService
		local selection = if gui and gui.GetPropertyChangedSignal then ctx.observe.SelectedObject(gui) else nil
		local stale = false
		local viaAction, viaInput = false, false
		local p: Shared.InputActionProps = {
			Name = name,
			Type = if settings.direction2D then Enum.InputActionType.Direction2D else Enum.InputActionType.Bool,
			StateChanged = settings.direction2D :: ((unknown) -> ())?,
			Pressed = function()
				if stale or viaInput then
					return
				end
				viaAction = true
				if ctx.readSource(available) and ctx.available(node) and ctx.read(enabledSource) ~= false then
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
		local function enabledBody(use: ComposeTypes.Use): boolean
			if selection then
				use(selection)
			end
			return use(parent) ~= nil
				and ctx.read(enabledSource, use) ~= false
				and use(available)
				and withinModal(node, use)
		end
		local enabled = if conditional ~= nil
				and ctx.config.services.GuiService == nil
				and config.userInputService == nil
			then nil
			else Compose.formula(enabledBody)
		local enabledBinding = enabled or enabledBody
		local reservedBound: { [string]: boolean } = {}
		for _, binding in keyCodes :: { Shared.ActionBinding } do
			local code: unknown = if type(binding) == "string"
				then ((Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode })[binding]
				elseif type(binding) == "table" then binding.KeyCode
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
					return assert(enabled):peek()
				end,
				press = function()
					if viaAction then
						return
					end
					viaInput = true
					if ctx.readSource(available) and ctx.available(node) and ctx.read(enabledSource) ~= false then
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
						elseif type(binding) == "table" then binding.KeyCode
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
				local on = use(assert(enabled))
				if on and not wasOn then
					stale = held()
				end
				wasOn = on
			end)
		end
		local context: InputContext
		if group then
			context = group.context
			runtime.decorate(action, { Enabled = enabledBinding })
			action.Parent = context
		elseif settings.group then
			runtime.decorate(action, { Enabled = enabledBinding })
			context = Host.InputContext("Facet" .. settings.group)({
				Parent = parent,
				Priority = settings.priority or 2000,
				Sink = settings.sink ~= false,
				Enabled = function(use: ComposeTypes.Use): boolean
					return use(parent) ~= nil and use(available)
				end,
				action,
			})
			groups[settings.group] = { context = context }
		else
			context = Host.InputContext("Facet" .. name)({
				Parent = parent,
				Priority = settings.priority or 2000,
				Sink = settings.sink ~= false,
				Enabled = enabledBinding,
				action,
			})
		end
		local inputService = config.userInputService
		if settings.capture and gui and selection and inputService then
			local steering: { [string]: string } = {}
			local letters: { [string]: string } = {}
			local dedicated: { [string]: boolean } = {}
			for _, binding in keyCodes :: { Shared.ActionBinding } do
				local code: unknown = if type(binding) == "string"
					then ((Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode })[binding]
					elseif type(binding) == "table" then binding.KeyCode
					else binding
				for _, direction in { "Up", "Down", "Left", "Right" } do
					local keys = (Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode }
					local letter = ({ Up = "W", Down = "S", Left = "A", Right = "D" })[direction]
					if code == keys[direction] or code == keys["DPad" .. direction] or code == keys[letter] then
						steering[(code :: Enum.KeyCode).Name] = direction
						if code == keys[letter] then
							letters[letter] = direction
						else
							dedicated[direction] = true
						end
					end
				end
			end
			local directions: { string } = {}
			if next(steering) == nil then
				return action, context
			end
			local heldDirections: ComposeTypes.Value<{ [string]: boolean }> = Compose.cell({})
			for _, direction in steering do
				if not table.find(directions, direction) then
					table.insert(directions, direction)
				end
			end
			local steerable = Compose.formula(function(use: ComposeTypes.Use): boolean
				return use(assert(enabled)) and use(selection) ~= nil
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
			local pinnedLetters: { [string]: boolean }? = nil
			local pinnedDirections: { string } = {}
			local previous: { [string]: GuiObject? } = {}
			local function release(): ()
				local target = pinned
				if target then
					for _, direction in pinnedDirections do
						if nextSelection(target, direction) == target then
							setNextSelection(target, direction, previous[direction])
						end
					end
				end
				pinned = nil
				table.clear(pinnedDirections)
				table.clear(previous)
			end
			Compose.watch(function(use: ComposeTypes.Use)
				local target: GuiObject? = if use(steerable) then use(selection) else nil
				local heldLetters = use(heldDirections)
				if target == pinned and heldLetters == pinnedLetters then
					return
				end
				if target and pinned and target ~= pinned and not viaAction and not viaInput then
					for letter in letters do
						local code = ((Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode })[letter]
						if inputService:IsKeyDown(code) then
							gui.SelectedObject = pinned
							return
						end
					end
				end
				if target ~= pinned and not held() then
					viaAction, viaInput = false, false
				end
				release()
				pinnedLetters = heldLetters
				if target then
					pinned = target
					for _, direction in directions do
						if dedicated[direction] or heldLetters[direction] then
							table.insert(pinnedDirections, direction)
							previous[direction] = nextSelection(target, direction)
							setNextSelection(target, direction, target)
						end
					end
				end
			end)
			Compose.cleanup(release)
			runtime.connect(inputService, "InputBegan", function(event: InputObject)
				if event.KeyCode and steering[event.KeyCode.Name] and steerable:peek() then
					local direction = letters[event.KeyCode.Name]
					if direction then
						local heldLetters = table.clone(heldDirections:peek())
						heldLetters[direction] = true
						heldDirections:set(heldLetters)
					end
					if viaAction then
						return
					end
					viaInput = true
					if ctx.readSource(available) and ctx.available(node) and ctx.read(enabledSource) ~= false then
						onPressed()
					end
				end
			end)
			local released = settings.onReleased
			runtime.connect(inputService, "InputEnded", function(event: InputObject)
				if event.KeyCode and steering[event.KeyCode.Name] then
					local direction = letters[event.KeyCode.Name]
					if direction then
						local heldLetters = table.clone(heldDirections:peek())
						heldLetters[direction] = nil
						heldDirections:set(heldLetters)
					end
					viaAction, viaInput = false, false
					if released then
						released()
					end
				end
			end)
		end
		return action, context
	end
end
