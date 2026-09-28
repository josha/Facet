--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Env = require("./environment_types")
local FocusBeam = require("./focus_beam")

type Level = { child: Instance, parent: Instance, siblings: { Instance } }
type Snapshot = { node: GuiObject, levels: { Level }, modal: boolean }

type Record = { root: Instance, passive: boolean, engaged: ComposeTypes.Cell<boolean> }
export type Selection = {
	track: (Instance) -> (),
	responder: (Instance, Env.ResponderOptions?) -> Env.Responder,
	spaceActivates: (Instance) -> (ComposeTypes.Use) -> boolean,
	query: (GuiObject?) -> Env.FocusQuery,
}

local RESPONDER_KEYS = { passive = true, gameplayGuard = true, traversalWrap = true }

local KEYBOARD_NAVIGATION_DEFAULT = true

return function(ctx: Shared.Context): Selection
	local Compose, runtime, config = ctx.Compose, ctx.runtime, ctx.config
	local E = ctx.types.Enum
	local gui = config.guiService
	local input = config.userInputService
	local responders = Compose.cell({} :: { Record })
	local keyboardNavigation = if config.keyboardNavigation == nil
		then KEYBOARD_NAVIGATION_DEFAULT
		else config.keyboardNavigation
	local registry = (
		setmetatable({} :: { [Instance]: boolean }, { __mode = "k" }) :: unknown
	) :: { [Instance]: boolean }
	local directionKeys = { E.KeyCode.DPadUp, E.KeyCode.DPadDown, E.KeyCode.DPadLeft, E.KeyCode.DPadRight }

	local function ordered(parent: Instance): { Instance }
		local children = parent:GetChildren()
		local sorted = parent:GetAttribute("FacetDocumentOrder") == true
		for _, child in children do
			if child:IsA("UIGridStyleLayout") and child.SortOrder == E.SortOrder.LayoutOrder then
				sorted = true
				break
			end
		end
		if not sorted then
			return children
		end
		local index: { [Instance]: number } = {}
		for position, child in children do
			index[child] = position
		end
		table.sort(children, function(a: Instance, b: Instance): boolean
			local left = if a:IsA("GuiObject") then a.LayoutOrder else 0
			local right = if b:IsA("GuiObject") then b.LayoutOrder else 0
			if left ~= right then
				return left < right
			end
			return index[a] < index[b]
		end)
		return children
	end

	local function shown(node: Instance?): boolean
		local at = node
		while at do
			if at:IsA("GuiObject") and (not at.Visible or not at.Interactable) then
				return false
			end
			if at:IsA("LayerCollector") then
				return at.Enabled
			end
			at = at.Parent
		end
		return false
	end

	local function collect(node: Instance, into: { GuiObject }): ()
		if node:IsA("GuiObject") then
			if not node.Visible or not node.Interactable then
				return
			end
			if node.Selectable then
				table.insert(into, node)
			end
		elseif node:IsA("LayerCollector") and not node.Enabled then
			return
		end
		for _, child in ordered(node) do
			collect(child, into)
		end
	end

	local function candidates(root: Instance): { GuiObject }
		local list: { GuiObject } = {}
		collect(root, list)
		return list
	end

	local function collectorOf(node: Instance): LayerCollector?
		return node:FindFirstAncestorWhichIsA("LayerCollector")
	end

	local function topModal(): Instance?
		local scopes = ctx.modalScopes:peek()
		for index = #scopes, 1, -1 do
			if shown(scopes[index]) then
				return scopes[index]
			end
		end
		return nil
	end

	local function screens(): { LayerCollector }
		local found: { [LayerCollector]: boolean } = {}
		local list: { LayerCollector } = {}
		for node in registry do
			local collector = collectorOf(node)
			if collector and not found[collector] and collector.Enabled then
				found[collector] = true
				table.insert(list, collector)
			end
		end
		table.sort(list, function(a: LayerCollector, b: LayerCollector): boolean
			local left = if a:IsA("ScreenGui") then a.DisplayOrder else 0
			local right = if b:IsA("ScreenGui") then b.DisplayOrder else 0
			return left > right
		end)
		return list
	end

	local function rectOf(node: GuiObject): FocusBeam.Rect
		local at, size = node.AbsolutePosition, node.AbsoluteSize
		return { x = at.X, y = at.Y, width = size.X, height = size.Y }
	end

	local function scopeOf(selected: Instance?): { GuiObject }
		local modal = topModal()
		if modal then
			return candidates(modal)
		end
		if selected and shown(selected) then
			local collector = collectorOf(selected)
			if collector then
				return candidates(collector)
			end
		end
		local records = responders:peek()
		for index = #records, 1, -1 do
			local record = records[index]
			if record.passive and record.engaged:peek() and shown(record.root) then
				local list = candidates(record.root)
				if #list > 0 then
					return list
				end
			end
		end
		for _, screen in screens() do
			local list = candidates(screen)
			if #list > 0 then
				return list
			end
		end
		return {}
	end

	local function beyond(container: GuiObject, from: GuiObject): GuiObject?
		local fp, fs = from.AbsolutePosition, from.AbsoluteSize
		local cp, cs = container.AbsolutePosition, container.AbsoluteSize
		local dx = (cp.X + cs.X / 2) - (fp.X + fs.X / 2)
		local dy = (cp.Y + cs.Y / 2) - (fp.Y + fs.Y / 2)
		local vertical = cp.Y >= fp.Y + fs.Y or cp.Y + cs.Y <= fp.Y or math.abs(dy) >= math.abs(dx)
		local direction: FocusBeam.Direction = if vertical
			then (if dy >= 0 then "down" else "up")
			else (if dx >= 0 then "right" else "left")
		local pool, rects = {}, {}
		for _, candidate in scopeOf(from) do
			if
				candidate ~= from
				and candidate ~= container
				and not candidate:IsA("ScrollingFrame")
				and not candidate:IsDescendantOf(container)
			then
				table.insert(pool, candidate)
				table.insert(rects, rectOf(candidate))
			end
		end
		local index = FocusBeam.neighbor(rectOf(from), rects, direction)
		return if index then pool[index] else nil
	end

	local function entryOf(container: GuiObject, from: GuiObject?): GuiObject?
		local list = candidates(container)
		if list[1] == container then
			table.remove(list, 1)
		end
		if #list == 0 then
			if from == nil or not shown(from) or from:IsDescendantOf(container) then
				return nil
			end
			return beyond(container, from) or from
		end
		if from and table.find(list, from) then
			return from
		end
		local entry = container:GetAttribute("FacetEntry")
		if type(entry) == "string" then
			for _, candidate in list do
				if candidate.Name == entry then
					return candidate
				end
			end
		end
		local target = list[1]
		if from and from ~= container and not from:IsDescendantOf(container) then
			local source = from.AbsolutePosition + from.AbsoluteSize / 2
			local box, window = container.AbsolutePosition, container.AbsoluteSize
			local vertical = source.Y <= box.Y or source.Y >= box.Y + window.Y
			local best = math.huge
			for _, candidate in list do
				local at, extent = candidate.AbsolutePosition, candidate.AbsoluteSize
				local edge = if vertical
					then (if source.Y <= box.Y then at.Y - box.Y else box.Y + window.Y - at.Y - extent.Y)
					else (if source.X <= box.X then at.X - box.X else box.X + window.X - at.X - extent.X)
				local across = if vertical
					then math.abs(at.X + extent.X / 2 - source.X)
					else math.abs(at.Y + extent.Y / 2 - source.Y)
				local score = math.max(edge, 0) * 100000 + across
				if score < best then
					best, target = score, candidate
				end
			end
		end
		return target
	end

	local DIRECTIONS: { Env.FocusDirection } = { "Up", "Down", "Left", "Right" }

	local function visibleOnScreen(node: GuiObject): boolean
		local collector = collectorOf(node)
		local view = if collector and collector:IsA("GuiBase2d") then (collector :: GuiBase2d).AbsoluteSize else nil
		local at, size = node.AbsolutePosition, node.AbsoluteSize
		if view and view.X > 0 and view.Y > 0 then
			if at.X + size.X <= 0 or at.Y + size.Y <= 0 or at.X >= view.X or at.Y >= view.Y then
				return false
			end
		end
		return true
	end

	local function inView(origin: GuiObject, candidate: GuiObject): boolean
		local at, size = candidate.AbsolutePosition, candidate.AbsoluteSize
		local parent = candidate.Parent
		while parent and parent:IsA("GuiObject") do
			if parent:IsA("ScrollingFrame") then
				if origin:IsDescendantOf(parent) then
					return true
				end
				local box, window = parent.AbsolutePosition, parent.AbsoluteSize
				if
					at.X + size.X <= box.X
					or at.Y + size.Y <= box.Y
					or at.X >= box.X + window.X
					or at.Y >= box.Y + window.Y
				then
					return false
				end
			end
			parent = parent.Parent
		end
		return visibleOnScreen(candidate)
	end

	local function groupsOf(node: GuiObject): { GuiObject }
		local found = {}
		local at = node.Parent
		while at and at:IsA("GuiObject") do
			if (at :: GuiObject).SelectionGroup then
				table.insert(found, at :: GuiObject)
			end
			at = at.Parent
		end
		return found
	end

	local function capturedAxis(origin: GuiObject, direction: string): boolean
		if not origin:HasTag("facet-adjustable") or not origin.Selectable or not shown(origin) then
			return false
		end
		local axis = origin:GetAttribute("axis")
		if axis == "horizontal" then
			return direction == "Left" or direction == "Right"
		end
		return axis == "vertical" and (direction == "Up" or direction == "Down")
	end

	local function query(from: GuiObject?): Env.FocusQuery
		local origin = from or (if gui then gui.SelectedObject else nil)
		local result: { [string]: Env.FocusMove } = {}
		if origin == nil then
			for _, direction in DIRECTIONS do
				result[direction] = table.freeze({ target = nil, rule = "none" })
			end
			return table.freeze(result) :: any
		end
		local pool: { GuiObject } = {}
		for _, candidate in scopeOf(origin) do
			local size = candidate.AbsoluteSize
			if
				candidate ~= origin
				and not (candidate:IsA("ScrollingFrame") and origin:IsDescendantOf(candidate))
				and size.X > 0
				and size.Y > 0
				and inView(origin, candidate)
			then
				table.insert(pool, candidate)
			end
		end
		local groups = groupsOf(origin)
		local function nearest(list: { GuiObject }, direction: string): GuiObject?
			local rects = table.create(#list)
			for index, node in list do
				rects[index] = rectOf(node)
			end
			local index = FocusBeam.neighbor(rectOf(origin), rects, string.lower(direction) :: FocusBeam.Direction)
			return if index then list[index] else nil
		end
		local function pick(list: { GuiObject }, direction: string): GuiObject?
			local controls, containers = {}, {}
			for _, node in list do
				table.insert(if node:IsA("ScrollingFrame") then containers else controls, node)
			end
			local target = nearest(controls, direction)
			if target then
				return target
			end
			target = nearest(containers, direction)
			if target and target:GetAttribute("FacetSelectionOwner") ~= true then
				target = entryOf(target, origin)
			end
			return if target == origin then nil else target
		end
		for _, direction in DIRECTIONS do
			local link = (origin :: any)["NextSelection" .. direction] :: GuiObject?
			if link == origin or capturedAxis(origin, direction) then
				result[direction] = table.freeze({ target = origin, rule = "capture" })
				continue
			end
			if link and link.Selectable and shown(link) then
				result[direction] = table.freeze({ target = link, rule = "link" })
				continue
			end
			local target: GuiObject? = nil
			local stopped = false
			for _, group in groups do
				local inside = {}
				for _, node in pool do
					if node:IsDescendantOf(group) then
						table.insert(inside, node)
					end
				end
				target = pick(inside, direction)
				if target or (group :: any)["SelectionBehavior" .. direction] == E.SelectionBehavior.Stop then
					stopped = target == nil
					break
				end
			end
			if target == nil and not stopped then
				target = pick(pool, direction)
			end
			result[direction] = table.freeze({
				target = target,
				rule = if target then "beam" elseif stopped then "stop" else "none",
			})
		end
		return table.freeze(result) :: any
	end

	local function wraps(node: Instance): boolean
		local at: Instance? = node
		while at do
			if at:GetAttribute("FacetTraversalWrap") == false then
				return false
			end
			at = at.Parent
		end
		return true
	end

	local function traverse(step: number): ()
		if gui == nil then
			return
		end
		local selected = gui.SelectedObject
		local list = scopeOf(selected)
		if #list == 0 then
			return
		end
		local position: { [GuiObject]: number } = {}
		for index, node in list do
			position[node] = index
		end
		table.sort(list, function(a: GuiObject, b: GuiObject): boolean
			if a.SelectionOrder ~= b.SelectionOrder then
				return a.SelectionOrder < b.SelectionOrder
			end
			return position[a] < position[b]
		end)
		local at = if selected then table.find(list, selected) else nil
		if at and (at + step < 1 or at + step > #list) and not wraps(list[at]) then
			return
		end
		local target = if at then list[(at - 1 + step) % #list + 1] elseif step < 0 then list[#list] else list[1]
		local editing = if input and input.GetFocusedTextBox then input:GetFocusedTextBox() else nil
		if editing and editing ~= target then
			editing:ReleaseFocus(false)
		end
		gui.SelectedObject = target
	end

	local function resting(node: Instance): boolean
		for _, record in responders:peek() do
			if record.passive and not record.engaged:peek() and node:IsDescendantOf(record.root) then
				return true
			end
		end
		return false
	end

	local function enter(): ()
		if gui == nil then
			return
		end
		local selected = gui.SelectedObject
		if selected and shown(selected) then
			return
		end
		for _, candidate in scopeOf(nil) do
			if not resting(candidate) then
				gui.SelectedObject = candidate
				return
			end
		end
	end

	local function snapshot(node: GuiObject): Snapshot
		local levels: { Level } = {}
		local modal = false
		local scopes = ctx.modalScopes:peek()
		local child: Instance = node
		local parent = node.Parent
		while parent do
			if table.find(scopes, child) then
				modal = true
			end
			table.insert(levels, { child = child, parent = parent, siblings = ordered(parent) })
			if parent:IsA("LayerCollector") then
				break
			end
			child, parent = parent, parent.Parent
		end
		return { node = node, levels = levels, modal = modal }
	end

	local function keyed(record: Snapshot): boolean
		for _, level in record.levels do
			if level.parent:GetAttribute("FacetSelectionOwner") == true and shown(level.parent) then
				return true
			end
		end
		return false
	end

	local function survivor(record: Snapshot): GuiObject?
		for _, level in record.levels do
			local parent = level.parent
			if shown(parent) then
				local at = table.find(level.siblings, level.child) or 0
				for index = at + 1, #level.siblings do
					local sibling = level.siblings[index]
					if sibling.Parent == parent then
						local list = candidates(sibling)
						if list[1] then
							return list[1]
						end
					end
				end
				for index = at - 1, 1, -1 do
					local sibling = level.siblings[index]
					if sibling.Parent == parent then
						local list = candidates(sibling)
						if list[#list] then
							return list[#list]
						end
					end
				end
			end
		end
		return nil
	end

	local function inputHost(): Instance?
		local parent = config.inputParent
		if parent == nil then
			local players = config.services.Players
			local player = if players then players.LocalPlayer else nil
			parent = if player then player:FindFirstChildOfClass("PlayerGui") else nil
		end
		return parent
	end

	local acquire = Compose.createSharedResource(function(): (nil, (() -> ())?)
		local service = gui
		local keys = input
		if service == nil or keys == nil then
			return nil, nil
		end
		if not service.GetPropertyChangedSignal then
			return nil, nil
		end
		local selectedObject = ctx.observe.SelectedObject(service)
		local keyboard = ctx.observe.KeyboardEnabled(keys)
		local preferred = ctx.observe.PreferredInput(keys)
		local padPreferred, padMade = false, false
		local function ownedByFacet(node: Instance?): boolean
			while node do
				if registry[node] then
					return true
				end
				node = node.Parent
			end
			return false
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local selected = use(selectedObject)
			local last = if keys.GetLastInputType then keys:GetLastInputType() else nil
			padMade = last ~= nil and string.find(last.Name, "^Gamepad") ~= nil and ownedByFacet(selected)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local pad = use(preferred) == E.PreferredInput.Gamepad
			if padPreferred and not pad and padMade and service.SelectedObject ~= nil then
				service.SelectedObject = nil
			end
			padPreferred = pad
		end)
		local record: Snapshot? = nil
		local pending = false
		local function recover(): ()
			pending = false
			local current = service.SelectedObject
			if current and shown(current) then
				return
			end
			local previous = record
			if previous == nil or previous.modal or keyed(previous) then
				return
			end
			if shown(previous.node) and previous.node.Selectable then
				return
			end
			local target = survivor(previous)
			if target then
				service.SelectedObject = target
			end
		end
		local wake = Compose.cell(0)
		Compose.watch(function(use: ComposeTypes.Use)
			if use(wake) > 0 and pending then
				recover()
			end
		end)
		local function schedule(): ()
			if pending or record == nil or record.modal or keyed(record) then
				return
			end
			pending = true
			wake:set(wake:peek() + 1)
		end
		local owner = assert(Compose.currentOwner())
		local tracking: ComposeTypes.Owner? = nil
		local function track(current: GuiObject): ()
			if tracking then
				tracking.dispose()
			end
			local child = owner.createChild()
			tracking = child
			Compose.withOwner(child, function()
				local sources: { ComposeTypes.Readable<unknown> } = { ctx.observe.Parent(current) }
				local at: Instance? = current
				while at do
					if at:IsA("GuiObject") then
						table.insert(sources, ctx.observe.Visible(at))
						table.insert(sources, ctx.observe.Interactable(at))
					elseif at:IsA("LayerCollector") then
						table.insert(sources, ctx.observe.Enabled(at))
						break
					end
					at = at.Parent
				end
				Compose.watch(function(use: ComposeTypes.Use)
					for _, source in sources do
						use(source)
					end
					if service.SelectedObject == current and not shown(current) then
						schedule()
					end
				end)
			end)
		end
		local function forward(container: ScrollingFrame): boolean
			if container:GetAttribute("FacetSelectionOwner") == true then
				return false
			end
			local target = entryOf(container, if record then record.node else nil)
			if target == nil then
				return false
			end
			service.SelectedObject = target
			return true
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local current = use(selectedObject) :: GuiObject?
			if current and current:IsA("ScrollingFrame") and shown(current) and forward(current) then
				return
			end
			if current and shown(current) then
				if record == nil or record.node ~= current then
					record = snapshot(current)
					track(current)
				end
			else
				schedule()
			end
		end)
		runtime.connect(keys, "InputBegan", function(event: InputObject)
			if table.find(directionKeys, event.KeyCode) then
				enter()
			end
		end)
		local parent = inputHost()
		if parent then
			ctx.Host.InputContext({
				Name = "FacetEntry",
				Parent = parent,
				Priority = 30,
				Sink = false,
				ctx.Host.InputAction({
					Name = "Enter",
					Type = E.InputActionType.Direction2D,
					StateChanged = function(value: unknown)
						if typeof(value) == "Vector2" and (value :: Vector2).Magnitude >= 0.5 then
							enter()
						end
					end,
					ctx.Host.InputBinding({ KeyCode = E.KeyCode.Thumbstick1 }),
				}),
			})
			ctx.Host.InputContext({
				Name = "FacetTraversal",
				Parent = parent,
				Priority = 1500,
				Sink = true,
				Enabled = function(use: ComposeTypes.Use): boolean
					if not keyboardNavigation or use(keyboard) ~= true then
						return false
					end
					if use(selectedObject) ~= nil then
						return true
					end
					local resting = false
					for _, record in use(responders) do
						if record.passive then
							if use(record.engaged) then
								return true
							end
							resting = true
						end
					end
					return not resting
				end,
				ctx.Host.InputAction({
					Name = "Traverse",
					Type = E.InputActionType.Bool,
					Pressed = function()
						local back = keys.IsKeyDown ~= nil
							and (keys:IsKeyDown(E.KeyCode.LeftShift) or keys:IsKeyDown(E.KeyCode.RightShift))
						traverse(if back then -1 else 1)
					end,
					ctx.Host.InputBinding({ KeyCode = E.KeyCode.Tab }),
				}),
			})
		end
		return nil, nil
	end)

	local function track(node: Instance): ()
		if gui == nil then
			return
		end
		registry[node] = true
		acquire()
	end

	local function responder(root: Instance, options: Env.ResponderOptions?): Env.Responder
		assert(Compose.currentOwner() ~= nil, "Facet UI.responder must run inside a component or Compose owner")
		assert(
			(root :: any) ~= nil and (root :: any).IsA ~= nil and (root:IsA("GuiObject") or root:IsA("LayerCollector")),
			"Facet UI.responder expects a GuiObject or a LayerCollector"
		)
		local settings: Env.ResponderOptions = options or {}
		for key, value in (settings :: unknown) :: { [unknown]: unknown } do
			assert(RESPONDER_KEYS[key :: string] == true, `Facet UI.responder: unknown option '{tostring(key)}'`)
			assert(type(value) == "boolean", `Facet UI.responder: {tostring(key)} must be a boolean`)
		end
		local passive = settings.passive ~= false
		local engaged = Compose.cell(not passive)
		if settings.traversalWrap == false then
			root:SetAttribute("FacetTraversalWrap", false)
		end
		if settings.gameplayGuard == false then
			root:SetAttribute("FacetGameplayGuard", false)
		end
		local record: Record = { root = root, passive = passive, engaged = engaged }
		local list = table.clone(responders:peek())
		table.insert(list, record)
		responders:set(list)
		Compose.cleanup(function()
			local remaining = table.clone(responders:peek())
			local index = table.find(remaining, record)
			if index then
				table.remove(remaining, index)
				responders:set(remaining)
			end
		end)
		local function inside(node: Instance?): boolean
			return node ~= nil and (node == (root :: Instance) or node:IsDescendantOf(root))
		end
		local function engage(): ()
			engaged:set(true)
		end
		local function resign(): ()
			if not passive then
				return
			end
			engaged:set(false)
			if gui and inside(gui.SelectedObject) then
				gui.SelectedObject = nil
			end
		end
		local parent = inputHost()
		if passive and gui and gui.GetPropertyChangedSignal then
			local selected = ctx.observe.SelectedObject(gui)
			Compose.watch(function(use: ComposeTypes.Use)
				local current = use(selected) :: Instance?
				if current == nil then
					return
				end
				if inside(current) then
					engaged:set(true)
				elseif engaged:peek() then
					engaged:set(false)
				end
			end)
			if input then
				runtime.connect(input, "InputBegan", function(event: InputObject)
					local kind = event.UserInputType
					if kind ~= E.UserInputType.MouseButton1 and kind ~= E.UserInputType.Touch then
						return
					end
					local collector = if root:IsA("LayerCollector") then root else collectorOf(root)
					local host = if collector then collector.Parent else nil
					if host == nil or (host :: any).GetGuiObjectsAtPosition == nil then
						return
					end
					local hits = (host :: any):GetGuiObjectsAtPosition(event.Position.X, event.Position.Y)
					for _, hit in hits do
						if inside(hit) then
							engaged:set(true)
							local at: Instance? = hit
							while at and at ~= root.Parent do
								if at:IsA("GuiObject") and at.Selectable then
									gui.SelectedObject = at
									break
								end
								at = at.Parent
							end
							return
						end
					end
					if engaged:peek() then
						resign()
					end
				end)
			end
			if parent then
				ctx.Host.InputContext({
					Name = "FacetResponderCancel",
					Parent = parent,
					Priority = 30,
					Sink = false,
					Enabled = function(use: ComposeTypes.Use): boolean
						return use(engaged)
					end,
					ctx.Host.InputAction({
						Name = "Cancel",
						Type = E.InputActionType.Bool,
						Pressed = resign,
						ctx.Host.InputBinding({ KeyCode = E.KeyCode.ButtonB }),
						ctx.Host.InputBinding({ KeyCode = E.KeyCode.Escape }),
					}),
				})
				if settings.gameplayGuard ~= false then
					ctx.Host.InputContext({
						Name = "FacetGameplayGuard",
						Parent = parent,
						Priority = 3000,
						Sink = true,
						Enabled = function(use: ComposeTypes.Use): boolean
							return use(engaged)
						end,
						ctx.Host.InputAction({
							Name = "Guard",
							Type = E.InputActionType.Bool,
							ctx.Host.InputBinding({ KeyCode = E.KeyCode.Space }),
						}),
					})
				end
			end
		end
		local state = (
			Compose.formula(function(use: ComposeTypes.Use): Env.ResponderState
				return if use(engaged) then "engaged" else "passive"
			end) :: unknown
		) :: ComposeTypes.Readable<Env.ResponderState>
		return table.freeze({
			state = state,
			engage = engage,
			resign = resign,
		})
	end

	local function spaceActivates(node: Instance): (ComposeTypes.Use) -> boolean
		return function(): boolean
			if not keyboardNavigation then
				return false
			end
			local at: Instance? = node
			while at do
				if at:GetAttribute("FacetGameplayGuard") == false then
					return false
				end
				at = at.Parent
			end
			return true
		end
	end

	return { track = track, responder = responder, spaceActivates = spaceActivates, query = query }
end
