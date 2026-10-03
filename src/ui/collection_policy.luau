--!strict
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local ComposeTypes = require("../vendor/compose/core")
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
return policy
