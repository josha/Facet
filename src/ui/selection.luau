--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

type Level = { child: Instance, parent: Instance, siblings: { Instance } }
type Snapshot = { node: GuiObject, levels: { Level }, modal: boolean }

return function(ctx: Shared.Context): (Instance) -> ()
	local Compose, runtime, config = ctx.Compose, ctx.runtime, ctx.config
	local E = ctx.types.Enum
	local gui = config.guiService
	local input = config.userInputService
	local registry = (
		setmetatable({} :: { [Instance]: boolean }, { __mode = "k" }) :: unknown
	) :: { [Instance]: boolean }
	local directionKeys = { E.KeyCode.DPadUp, E.KeyCode.DPadDown, E.KeyCode.DPadLeft, E.KeyCode.DPadRight }

	local function ordered(parent: Instance): { Instance }
		local children = parent:GetChildren()
		local sorted = false
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
		for _, screen in screens() do
			local list = candidates(screen)
			if #list > 0 then
				return list
			end
		end
		return {}
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
		local at = if selected then table.find(list, selected) else nil
		local target = if at then list[(at - 1 + step) % #list + 1] elseif step < 0 then list[#list] else list[1]
		gui.SelectedObject = target
	end

	local function enter(): ()
		if gui == nil then
			return
		end
		local selected = gui.SelectedObject
		if selected and shown(selected) then
			return
		end
		local list = scopeOf(nil)
		if list[1] then
			gui.SelectedObject = list[1]
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

	local acquire = Compose.createSharedResource(function()
		if gui == nil or input == nil or not gui.GetPropertyChangedSignal then
			return nil
		end
		local selectedObject = ctx.observe.SelectedObject(gui)
		local record: Snapshot? = nil
		local pending = false
		local function recover(): ()
			pending = false
			local current = gui.SelectedObject
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
				gui.SelectedObject = target
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
				local parent = ctx.observe.Parent(current)
				local visible = ctx.observe.Visible(current)
				Compose.watch(function(use: ComposeTypes.Use)
					use(parent)
					use(visible)
					if gui.SelectedObject == current and not shown(current) then
						schedule()
					end
				end)
			end)
		end
		local function beyond(container: GuiObject, from: GuiObject): GuiObject?
			local fp, fs = from.AbsolutePosition, from.AbsoluteSize
			local cp, cs = container.AbsolutePosition, container.AbsoluteSize
			local dx = (cp.X + cs.X / 2) - (fp.X + fs.X / 2)
			local dy = (cp.Y + cs.Y / 2) - (fp.Y + fs.Y / 2)
			local vertical = cp.Y >= fp.Y + fs.Y or cp.Y + cs.Y <= fp.Y or math.abs(dy) >= math.abs(dx)
			local sign = if vertical then (if dy >= 0 then 1 else -1) else (if dx >= 0 then 1 else -1)
			local best, target = math.huge, nil
			for _, candidate in scopeOf(from) do
				if
					candidate ~= from
					and candidate ~= container
					and not candidate:IsA("ScrollingFrame")
					and not candidate:IsDescendantOf(container)
				then
					local at, extent = candidate.AbsolutePosition, candidate.AbsoluteSize
					local gap, across, overlap
					if vertical then
						gap = if sign > 0 then at.Y - (fp.Y + fs.Y) else fp.Y - (at.Y + extent.Y)
						across = math.abs(at.X + extent.X / 2 - (fp.X + fs.X / 2))
						overlap = at.X < fp.X + fs.X and fp.X < at.X + extent.X
					else
						gap = if sign > 0 then at.X - (fp.X + fs.X) else fp.X - (at.X + extent.X)
						across = math.abs(at.Y + extent.Y / 2 - (fp.Y + fs.Y / 2))
						overlap = at.Y < fp.Y + fs.Y and fp.Y < at.Y + extent.Y
					end
					if gap >= -1 then
						local score = gap + 2 * across + (if overlap then 0 else 100000)
						if score < best then
							best, target = score, candidate
						end
					end
				end
			end
			return target
		end
		local function forward(container: ScrollingFrame): boolean
			if container:GetAttribute("FacetSelectionOwner") == true then
				return false
			end
			local list = candidates(container)
			if list[1] == container then
				table.remove(list, 1)
			end
			if #list == 0 then
				local from = if record then record.node else nil
				if from == nil or not shown(from) or from:IsDescendantOf(container) then
					return false
				end
				gui.SelectedObject = beyond(container, from) or from
				return true
			end
			local from = if record then record.node else nil
			local target = list[1]
			local entry = container:GetAttribute("FacetEntry")
			local preferred: GuiObject? = nil
			if type(entry) == "string" then
				for _, candidate in list do
					if candidate.Name == entry then
						preferred = candidate
						break
					end
				end
			end
			if preferred then
				target = preferred
			elseif from and from ~= container and not from:IsDescendantOf(container) then
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
			gui.SelectedObject = target
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
		runtime.connect(input, "InputBegan", function(event: InputObject)
			if table.find(directionKeys, event.KeyCode) then
				enter()
			end
		end)
		local parent = config.inputParent
		if parent == nil then
			local players = config.services.Players
			local player = if players then players.LocalPlayer else nil
			parent = if player then player:FindFirstChildOfClass("PlayerGui") else nil
		end
		if parent then
			ctx.Host.InputContext({
				Name = "FacetTraversal",
				Parent = parent,
				Priority = 1500,
				Sink = true,
				ctx.Host.InputAction({
					Name = "Traverse",
					Type = E.InputActionType.Bool,
					Pressed = function()
						local back = input.IsKeyDown ~= nil
							and (input:IsKeyDown(E.KeyCode.LeftShift) or input:IsKeyDown(E.KeyCode.RightShift))
						traverse(if back then -1 else 1)
					end,
					ctx.Host.InputBinding({ KeyCode = E.KeyCode.Tab }),
				}),
			})
		end
		return nil
	end)

	return function(node: Instance): ()
		if gui == nil then
			return
		end
		registry[node] = true
		acquire()
	end
end
