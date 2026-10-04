--!strict
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local ComposeTypes = require("../vendor/compose/core")
local sessionOf = require("./drag_session")
local activation = require("./activation")
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
function policy.actions<V, K>(
	ctx: Types.Context,
	spec: {
		rowActions: ((ComposeTypes.Readable<V>, K) -> CollectionTypes.RowActionsOptions?)?,
		rowDeletable: ((V) -> boolean)?,
		disabled: ((V) -> boolean)?,
		reducedMotion: Types.ValueBoolean?,
		editing: Types.ValueBoolean?,
	},
	current: ComposeTypes.Readable<V>,
	key: K,
	row: GuiObject,
	constructor: Types.Constructor<CollectionTypes.RowActionsSpec, Frame>,
	coordinator: ComposeTypes.Cell<{}?>
): GuiObject
	local actions = if spec.rowActions then spec.rowActions(current, key) else nil
	if actions == nil then
		return row
	end
	local actionSpec = table.clone(actions) :: CollectionTypes.RowActionsSpec
	local function gated(list: Types.Value<{ CollectionTypes.RowAction }>?): Types.Value<{ CollectionTypes.RowAction }>?
		if list == nil then
			return nil
		end
		return function(use: ComposeTypes.Use): { CollectionTypes.RowAction }
			local allowed = policy.allows(spec.rowDeletable, use(current))
			local kept = {}
			for _, action in ctx.read(list, use) do
				if allowed or action.role ~= "destructive" then
					table.insert(kept, action)
				end
			end
			return kept
		end
	end
	actionSpec.leading, actionSpec.trailing = gated(actions.leading), gated(actions.trailing)
	actionSpec.enabled = function(use: ComposeTypes.Use): boolean
		return ctx.read(actions.enabled, use) ~= false and not policy.disabled(spec.disabled, use(current))
	end
	actionSpec.content, actionSpec.coordinator = row, actions.coordinator or coordinator
	actionSpec.Size = ctx.types.UDim2.fromScale(1, 1)
	actionSpec.reducedMotion = spec.reducedMotion
	actionSpec.swipeEnabled = function(use: ComposeTypes.Use): boolean
		return ctx.read(actions.swipeEnabled, use) ~= false and ctx.read(spec.editing, use) ~= true
	end
	return constructor(actionSpec)
end
function policy.drop<V, K>(
	ctx: Types.Context,
	spec: CollectionTypes.ReorderOptions<V, K>,
	current: ComposeTypes.Readable<V>,
	key: K,
	row: GuiObject,
	horizontal: boolean
)
	if not spec.rowDrop then
		return
	end
	local authored = spec.rowDrop(current, key)
	if authored == nil then
		return
	end
	local destination: any = table.clone(authored)
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
	local hit = row:FindFirstChild("RowHit")
	if hit then
		ctx.Compose.cleanup(activation.intercept(hit :: GuiObject, function(): boolean
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
