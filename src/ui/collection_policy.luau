--!strict
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local ComposeTypes = require("../vendor/compose/core")
local sessionOf = require("./drag_session")
local DragTypes = require("./drag_types")
local activation = require("./activation")
local CollectionProps = require("./collection_props")
local policy = {}
function policy.allows<V>(predicate: ((V) -> boolean)?, item: V): boolean
	if predicate == nil then
		return true
	end
	local ok, allowed = pcall(predicate, item)
	return ok and allowed == true
end
function policy.disabled<V>(predicate: ((V) -> boolean)?, item: V): boolean
	if predicate == nil then
		return false
	end
	local ok, disabled = pcall(predicate, item)
	return not ok or disabled == true
end
function policy.selectionVisible(node: GuiObject): boolean
	local position, size = node.AbsolutePosition, node.AbsoluteSize
	local left = position.X
	local top = position.Y
	local right = left + size.X
	local bottom = top + size.Y
	local measured = size.X > 0 and size.Y > 0
	local ancestor: Instance? = node
	while ancestor do
		if ancestor:IsA("GuiObject") then
			if not ancestor.Visible or not ancestor.Interactable then
				return false
			end
			if measured and ancestor.ClipsDescendants then
				local p, s = ancestor.AbsolutePosition, ancestor.AbsoluteSize
				left = math.max(left, p.X)
				top = math.max(top, p.Y)
				right = math.min(right, p.X + s.X)
				bottom = math.min(bottom, p.Y + s.Y)
				if right <= left or bottom <= top then
					return false
				end
			end
		elseif ancestor:IsA("LayerCollector") and not ancestor.Enabled then
			return false
		end
		ancestor = ancestor.Parent
	end
	return true
end
function policy.actions<V, K>(
	ctx: Types.Context,
	spec: {
		rowActions: ((ComposeTypes.ReadOnlyValue<V>, K) -> CollectionTypes.RowActionsShape?)?,
		rowDeletable: ((V) -> boolean)?,
		disabled: ((V) -> boolean)?,
		reducedMotion: Types.ValueBoolean?,
		editing: Types.ValueBoolean?,
	},
	current: ComposeTypes.ReadOnlyValue<V>,
	key: K,
	row: GuiObject,
	constructor: Types.Constructor<CollectionProps.RowActionsSpecInput, Frame>,
	coordinator: ComposeTypes.Value<{}?>,
	tiled: boolean?
): (GuiObject, ComposeTypes.ReadOnlyValue<number>?)
	local readActions = ctx.read<<{ CollectionTypes.RowAction }>>
	local authored = if spec.rowActions then spec.rowActions(current, key) else nil
	local edits = activation.edits(row)
	if authored == nil and #edits == 0 then
		return row, nil
	end
	local actions: CollectionTypes.RowActionsFields = authored or {}
	local actionSpec: CollectionProps.RowActionsSpec = { content = row }
	if authored then
		for key, value in authored do
			actionSpec[key] = value
		end
	end
	local function gated(list: Types.Input<{ CollectionTypes.RowAction }>?): Types.Input<{ CollectionTypes.RowAction }>?
		if list == nil then
			return nil
		end
		return function(use: ComposeTypes.Use): { CollectionTypes.RowAction }
			local allowed = policy.allows(spec.rowDeletable, use(current))
			local kept = {}
			for _, action in readActions(list, use) do
				if allowed or action.role ~= "destructive" then
					table.insert(kept, action)
				end
			end
			return kept
		end
	end
	actionSpec.leading, actionSpec.trailing = gated(actions.leading), gated(actions.trailing)
	if #edits > 0 then
		local trailing = actionSpec.trailing
		actionSpec.trailing = function(use: ComposeTypes.Use): { CollectionTypes.RowAction }
			local result = if trailing == nil then {} else table.clone(readActions(trailing, use))
			for index, edit in edits do
				local action: CollectionTypes.RowAction = {
					id = "edit:" .. index,
					label = edit.label,
					icon = edit.icon,
					role = edit.role,
					enabled = edit.enabled,
					onActivate = edit.onActivate,
				}
				table.insert(result, action)
			end
			return result
		end
	end
	actionSpec.enabled = function(use: ComposeTypes.Use): boolean
		return ctx.read(actions.enabled, use) ~= false and not policy.disabled(spec.disabled, use(current))
	end
	actionSpec.actionPlacement = actions.actionPlacement or (if tiled then "bottom" else "trailing")
	actionSpec.content, actionSpec.coordinator = row, actions.coordinator or coordinator
	actionSpec.Size = ctx.types.UDim2.fromScale(1, 1)
	actionSpec.reducedMotion = spec.reducedMotion
	actionSpec.swipeEnabled = function(use: ComposeTypes.Use): boolean
		return ctx.read(actions.swipeEnabled, use) ~= false and ctx.read(spec.editing, use) ~= true
	end
	local root = constructor(actionSpec)
	local button = root:FindFirstChild("CellActions")
	local footer = if tiled
			and actionSpec.actionPlacement == "bottom"
			and button
			and button:IsA("GuiObject")
		then button
		else nil
	if footer then
		local size, visible = ctx.layoutSize(footer), ctx.observe.Visible(footer)
		return root,
			ctx.Compose.formula(function(use: ComposeTypes.Use): number
				return if use(visible) then use(size).Y else 0
			end)
	end
	return root, nil
end
function policy.drop<V, K>(
	ctx: Types.Context,
	spec: CollectionTypes.ReorderShape<V, K>,
	current: ComposeTypes.ReadOnlyValue<V>,
	key: K,
	row: GuiObject,
	horizontal: boolean,
	hit: GuiObject?
)
	if not spec.rowDrop then
		return
	end
	local authored = spec.rowDrop(current, key)
	if authored == nil then
		return
	end
	local destination: DragTypes.TargetSpec = (table.clone(authored) :: unknown) :: DragTypes.TargetSpec
	local service = sessionOf(ctx)
	destination.collectionAxis = if horizontal then "X" else "Y"
	destination.accepts = function(payload, info): (boolean, string?)
		if policy.disabled(spec.disabled, current:peek()) then
			return false, "This item is unavailable"
		end
		if authored.accepts then
			return authored.accepts(payload, info)
		end
		return true, nil
	end
	service.register(row, destination)
	ctx.runtime.connect(row, "InputBegan", function(input: InputObject)
		local session = service.state:peek()
		if
			session
			and session.mode == "armed"
			and (
				input.UserInputType == ctx.types.Enum.UserInputType.Touch
				or input.UserInputType == ctx.types.Enum.UserInputType.MouseButton1
			)
		then
			local target = service.targetOf(row)
			if target then
				activation.consume(input)
				service.commit(target)
			end
		end
	end)
	if hit then
		ctx.Compose.cleanup(activation.intercept(hit, function(): boolean
			local session = service.state:peek()
			if not session or session.mode ~= "armed" then
				return false
			end
			local target = service.targetOf(row)
			if target then
				service.commit(target)
				return true
			end
			return false
		end))
	end
end
return policy
