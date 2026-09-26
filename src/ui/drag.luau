--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Env = require("./environment_types")

-- One drag session per Facet controls instance. A pointer or finger picks a source up by pressing and travelling
-- (a release before that is still a tap); a keyboard or gamepad arms it with Return or A on the selected source,
-- moves the selection to a target and drops with Return or A. Every route ends in the same commit.
type Session = {
	payload: unknown,
	source: GuiObject,
	mode: "pointer" | "armed",
	hover: GuiObject?,
	ghost: GuiObject?,
}
type Target = Env.DropTargetSpec

local TRAVEL = 6

return function(ctx: Shared.Context, UI: Env.EnvironmentControls)
	local Compose, config = ctx.Compose, ctx.config
	local E, V2, D2 = ctx.types.Enum, ctx.types.Vector2, ctx.types.UDim2
	local input, gui = config.userInputService, config.guiService
	local session: ComposeTypes.Cell<Session?> = Compose.cell(nil :: Session?)
	local targets: { [GuiObject]: Target } = {}
	local order: { GuiObject } = {}

	local function point(value: InputObject): Vector2
		return V2.new(value.Position.X, value.Position.Y)
	end
	local function inside(node: GuiObject, at: Vector2): boolean
		local from, size = node.AbsolutePosition, node.AbsoluteSize
		return at.X >= from.X and at.Y >= from.Y and at.X <= from.X + size.X and at.Y <= from.Y + size.Y
	end
	-- the last registered target under the point, so a target nested in another wins
	local function targetAt(at: Vector2): GuiObject?
		for index = #order, 1, -1 do
			local node = order[index]
			if node.Visible and inside(node, at) then
				return node
			end
		end
		return nil
	end
	local function targetOf(node: Instance?): GuiObject?
		local at = node
		while at do
			if at:IsA("GuiObject") and targets[at] then
				return at
			end
			at = at.Parent
		end
		return nil
	end
	local function hover(next: GuiObject?)
		local current = session:peek()
		if current == nil or current.hover == next then
			return
		end
		local previous = current.hover
		local updated = table.clone(current)
		updated.hover = next
		session:set(updated)
		if previous and targets[previous] and targets[previous].onLeave then
			(targets[previous].onLeave :: (unknown) -> ())(current.payload)
		end
		if next and targets[next].onEnter then
			(targets[next].onEnter :: (unknown) -> ())(current.payload)
		end
	end
	local function finish()
		local current = session:peek()
		if current == nil then
			return
		end
		session:set(nil)
		if current.ghost then
			current.ghost:Destroy()
		end
		current.source:RemoveTag("facet-drag-held")
		current.source:SetAttribute("FacetDragHeld", nil)
		if current.hover and targets[current.hover] and targets[current.hover].onLeave then
			(targets[current.hover].onLeave :: (unknown) -> ())(current.payload)
		end
	end
	local function commit(target: GuiObject?)
		local current = session:peek()
		finish()
		local spec = if target then targets[target] else nil
		if current == nil or target == nil or spec == nil then
			return
		end
		local legal, reason = true, nil :: string?
		if spec.accepts then
			legal, reason = spec.accepts(current.payload)
		end
		if legal then
			spec.onDrop(current.payload, { source = current.source, target = target, mode = current.mode })
		elseif spec.onReject then
			spec.onReject(current.payload, reason)
		end
	end
	local function begin(source: GuiObject, spec: Env.DraggableSpec, mode: "pointer" | "armed"): Session
		finish()
		local payload = if type(spec.payload) == "function"
			then (spec.payload :: (GuiObject) -> unknown)(source)
			else spec.payload
		local started: Session = { payload = payload, source = source, mode = mode }
		source:AddTag("facet-drag-held")
		source:SetAttribute("FacetDragHeld", true)
		session:set(started)
		return started
	end
	-- The ghost is an inert clone of the source at the root of its screen. A pointer position and the screen's
	-- AbsolutePosition share one space (an IgnoreGuiInset screen starts above the pointer's origin), and only a
	-- UIScale on that root separates it from the ghost's offsets.
	local function ghostOf(source: GuiObject): GuiObject?
		local layer = source:FindFirstAncestorWhichIsA("LayerCollector")
		if layer == nil then
			return nil
		end
		local ghost = source:Clone()
		local nodes = ghost:GetDescendants()
		table.insert(nodes, ghost)
		for _, node in nodes do
			if node:IsA("GuiObject") then
				node.Interactable, node.Active, node.Selectable = false, false, false
			elseif node:IsA("UIDragDetector") or node:IsA("InputContext") then
				(node :: any).Enabled = false
			end
		end
		ghost:RemoveTag("facet-drag-held")
		ghost.Name, ghost.ZIndex, ghost.AnchorPoint = "DragGhost", 1000, V2.new(0.5, 0.5)
		ghost.Parent = layer
		return ghost
	end
	local function place(ghost: GuiObject, source: GuiObject, at: Vector2)
		local layer = ghost.Parent :: Instance
		local origin: Vector2 = if layer:IsA("GuiBase2d") then layer.AbsolutePosition else V2.zero
		local scale = 1
		for _, child in layer:GetChildren() do
			if child:IsA("UIScale") and child.Scale > 0 then
				scale = child.Scale
			end
		end
		local size = source.AbsoluteSize / scale
		ghost.Size = D2.fromOffset(size.X, size.Y)
		ghost.Position = D2.fromOffset((at.X - origin.X) / scale, (at.Y - origin.Y) / scale)
	end

	UI.draggable = function(source: GuiObject, spec: Env.DraggableSpec)
		assert(Compose.currentOwner() ~= nil, "Facet UI.draggable must run inside a component or Compose owner")
		assert(type(spec) == "table" and spec.payload ~= nil, "Facet UI.draggable needs a payload")
		local function enabled(use: ComposeTypes.Use?): boolean
			return spec.enabled == nil or ctx.read(spec.enabled, use) == true
		end
		Compose.cleanup(function()
			local current = session:peek()
			if current and current.source == source then
				finish()
			end
		end)
		local selected = if gui then ctx.observe.SelectedObject(gui) else nil
		if selected then
			-- while armed, the target that holds the selection is the aim
			Compose.watch(function(use: ComposeTypes.Use)
				local node = use(selected) :: Instance?
				local current = session:peek()
				if current and current.source == source and current.mode == "armed" then
					hover(targetOf(node))
				end
			end)
		end
		if input then
			local pressed: InputObject?, origin: Vector2? = nil, nil
			ctx.runtime.connect(source, "InputBegan", function(value: InputObject)
				local kind = value.UserInputType
				if (kind == E.UserInputType.MouseButton1 or kind == E.UserInputType.Touch) and enabled() then
					pressed, origin = value, point(value)
				end
			end)
			ctx.runtime.connect(input, "InputChanged", function(value: InputObject)
				local moved = pressed ~= nil
					and (
						value == pressed
						or (
							pressed.UserInputType == E.UserInputType.MouseButton1
							and value.UserInputType == E.UserInputType.MouseMovement
						)
					)
				if not moved or origin == nil then
					return
				end
				local at = point(value)
				local current = session:peek()
				if current == nil or current.source ~= source then
					if (at - origin).Magnitude < TRAVEL then
						return
					end
					current = begin(source, spec, "pointer")
					local ghost = ghostOf(source)
					local updated = table.clone(current :: Session)
					updated.ghost = ghost
					session:set(updated)
				end
				local live = session:peek() :: Session
				if live.ghost then
					place(live.ghost, source, at)
				end
				hover(targetAt(at))
			end)
			ctx.runtime.connect(input, "InputEnded", function(value: InputObject)
				if pressed == nil then
					return
				end
				local ended = value == pressed
					or (
						pressed.UserInputType == E.UserInputType.MouseButton1
						and value.UserInputType == E.UserInputType.MouseButton1
					)
				if not ended then
					return
				end
				local tapped = origin ~= nil and (point(value) - origin).Magnitude < TRAVEL
				pressed, origin = nil, nil
				local current = session:peek()
				if current and current.source == source and current.mode == "pointer" then
					if value.UserInputState == E.UserInputState.Cancel then
						finish()
					else
						commit(targetAt(point(value)))
					end
				elseif tapped and spec.armOnTap and current == nil and value.UserInputType == E.UserInputType.Touch then
					begin(source, spec, "armed")
				end
			end)
		end
		local function selectedHere(use: ComposeTypes.Use): boolean
			local node = if selected then use(selected) :: Instance? else nil
			return node ~= nil and (node == source or node:IsDescendantOf(source))
		end
		ctx.action(source, "DragPickUp", { E.KeyCode.Return, E.KeyCode.ButtonA }, function(use: ComposeTypes.Use)
			return use(session) == nil and enabled(use) and selectedHere(use)
		end, function()
			begin(source, spec, "armed")
		end, { priority = 250 })
		ctx.action(source, "DragCancel", { E.KeyCode.Escape, E.KeyCode.ButtonB }, function(use: ComposeTypes.Use)
			local current = use(session)
			return current ~= nil and current.source == source
		end, finish, { priority = 250 })
	end

	UI.dropTarget = function(target: GuiObject, spec: Env.DropTargetSpec)
		assert(Compose.currentOwner() ~= nil, "Facet UI.dropTarget must run inside a component or Compose owner")
		assert(type(spec) == "table" and type(spec.onDrop) == "function", "Facet UI.dropTarget needs onDrop")
		targets[target] = spec
		table.insert(order, target)
		Compose.cleanup(function()
			targets[target] = nil
			local index = table.find(order, target)
			if index then
				table.remove(order, index)
			end
		end)
		-- a tap on a target places what a tap armed
		ctx.runtime.connect(target, "InputBegan", function(value: InputObject)
			local current = session:peek()
			local kind = value.UserInputType
			if
				current
				and current.mode == "armed"
				and (kind == E.UserInputType.Touch or kind == E.UserInputType.MouseButton1)
			then
				commit(target)
			end
		end)
		ctx.action(target, "DragDrop", { E.KeyCode.Return, E.KeyCode.ButtonA }, function(use: ComposeTypes.Use)
			local current = use(session)
			return current ~= nil and current.mode == "armed" and current.hover == target
		end, function()
			commit(target)
		end, { priority = 250 })
	end
end
