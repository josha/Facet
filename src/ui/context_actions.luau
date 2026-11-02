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
	local function bindingKey(binding: Shared.ActionBinding): Enum.KeyCode?
		return if type(binding) == "string"
			then assert(Enum.KeyCode:FromName(binding), `Facet action: unknown key '{binding}'`)
			elseif type(binding) == "table" then ctx.read<<Enum.KeyCode?>>(binding.KeyCode)
			else binding
	end
	local reservedCodes: { [string]: Enum.KeyCode } = setmetatable({}, { __index = Enum.KeyCode })
	type SelectionWaiters = { waiting: { [unknown]: () -> () }, count: number, stop: (() -> ())? }
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
				local waiting = registry.waiting[target]
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
	ctx.modalScopes = Compose.cell<<{ Instance }>>({})
	ctx.modalReturn = {}
	ctx.modalPortals = Compose.cell<<{ ModalPortal }>>({})
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
			if at == modal or at:IsDescendantOf(modal) then
				return true
			end
			for _, portal in portals do
				if (at == portal.node or at:IsDescendantOf(portal.node)) and inside(portal.anchor, visited) then
					return true
				end
			end
			return false
		end
		return inside(node, {})
	end
	ctx.withinModal = withinModal
	local guiGates: { [Instance]: GuiObject } = setmetatable({}, { __mode = "kv" })
	local layerGates: { [Instance]: LayerCollector } = setmetatable({}, { __mode = "kv" })
	local openGates: { [Instance]: boolean } = setmetatable({}, { __mode = "k" })
	function ctx.available(node: Instance, use: ComposeTypes.Use?): boolean
		local at: Instance? = node
		while at do
			local gui = guiGates[at]
			local layer = if gui == nil then layerGates[at] else nil
			if gui == nil and layer == nil and not openGates[at] then
				if at:IsA("GuiObject") then
					gui = at
					guiGates[at] = at
				elseif at:IsA("LayerCollector") then
					layer = at
					layerGates[at] = at
				else
					openGates[at] = true
				end
			end
			if gui then
				if not gui.Visible or not gui.Interactable then
					return false
				end
			elseif layer and not layer.Enabled then
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
		Compose.cleanup(reservedKeys.add(input, reservedCodes, handler))
	end
	function ctx.navigationGamepads(): { Enum.UserInputType }
		local service = config.userInputService
		if service and service.GetNavigationGamepads then
			local pads = service:GetNavigationGamepads()
			if #pads > 0 then
				return pads
			end
		end
		local last = if service and service.GetLastInputType then service:GetLastInputType() else nil
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
			local parent = Compose.cell<<Instance?>>(nil)
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
		local stale = false
		local viaAction, viaInput = false, false
		local p: Shared.InputActionProps = {
			Name = name,
			Type = if settings.direction2D then Enum.InputActionType.Direction2D else Enum.InputActionType.Bool,
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
					KeyCode = bindingKey(binding),
				})
		end
		for _, binding in keyCodes do
			p[#p + 1] = bind(binding)
		end
		local conditional = settings.conditional
		if conditional then
			p[#p + 1] = Compose.show(conditional.when, function()
				return bind(conditional.binding)
			end)
		end
		local action = Host.InputAction(p)
		if settings.direction2D then
			runtime.connect(action, "StateChanged", settings.direction2D)
		end
		local function enabledBody(use: ComposeTypes.Use): boolean
			return use(parent) ~= nil
				and ctx.read(enabledSource, use) ~= false
				and use(available)
				and withinModal(node, use)
		end
		local activationGate: (InputContext | InputAction)? = nil
		local reservedBound: { [string]: boolean } = {}
		for _, binding in keyCodes do
			local code = bindingKey(binding)
			local codeName = if code then code.Name else nil
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
					local gate = activationGate
					return gate ~= nil and gate.Enabled
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
			function held(): boolean
				for _, binding in keyCodes do
					local key = bindingKey(binding)
					if key then
						if keyInput.IsGamepadButtonDown then
							for _, pad in ctx.navigationGamepads() do
								if keyInput:IsGamepadButtonDown(pad, key) then
									return true
								end
							end
						end
						if keyInput.IsKeyDown and keyInput:IsKeyDown(key) then
							return true
						end
					end
				end
				return false
			end
		end
		local context: InputContext
		if group then
			context = group.context
			runtime.decorate(action, { Enabled = enabledBody })
			action.Parent = context
		elseif settings.group then
			runtime.decorate(action, { Enabled = enabledBody })
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
				Enabled = enabledBody,
				action,
			})
		end
		local gate = if settings.group then action else context
		activationGate = gate
		if keyInput then
			local function changed()
				if gate.Enabled then
					stale = held()
				end
			end
			Compose.cleanup(assert(runtime.host.observation).observeProperty(gate, "Enabled", changed))
			changed()
		end
		local inputService = config.userInputService
		if settings.capture and gui and gui.GetPropertyChangedSignal and inputService then
			local selection = ctx.observe.SelectedObject(gui)
			local enabled = ctx.observe.Enabled(gate)
			local steering: { [string]: string } = {}
			local letters: { [string]: string } = {}
			local dedicated: { [string]: boolean } = {}
			for _, binding in keyCodes do
				local code = bindingKey(binding)
				for _, direction in { "Up", "Down", "Left", "Right" } do
					local letter = ({ Up = "W", Down = "S", Left = "A", Right = "D" })[direction]
					if
						code
						and (
							code == Enum.KeyCode:FromName(direction)
							or code == Enum.KeyCode:FromName("DPad" .. direction)
							or code == Enum.KeyCode:FromName(letter)
						)
					then
						steering[code.Name] = direction
						if code == Enum.KeyCode:FromName(letter) then
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
				runtime.host.render.setProperty(target, "NextSelection" .. direction, value)
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
						local code = assert(Enum.KeyCode:FromName(letter))
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
