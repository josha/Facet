--!strict
local ComposeTypes = require("../vendor/compose/core")
local CollectionTypes = require("./collection_types")
local Types = require("./types")
local State = require("./collection_state")
local policy = require("./collection_policy")

return function<V, K>(
	ctx: Types.Context,
	view: State.View<V, K>,
	recycle: CollectionTypes.RowRecycle<V, K>
): (CollectionTypes.Follow?) -> ComposeTypes.Child
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local D2, E = ctx.types.UDim2, ctx.types.Enum
	local spec, horizontal = view.spec, view.horizontal
	local kind: ComposeTypes.OrderedCollectionLayoutKind = view.kind
	local selection, selectionMode, mounted = view.selection, view.selectionMode, view.mounted
	local function activate(key: K, current: ComposeTypes.Readable<V>, input: InputObject?, clicks: number?)
		if policy.disabled(spec.disabled, current:peek()) then
			return
		end
		local pointer = input ~= nil and input.UserInputType == E.UserInputType.MouseButton1
		local double = pointer and (clicks or 0) >= 2
		if not double then
			view.selectRow(key, current:peek(), input)
		end
		if spec.onActivate and (selectionMode == "none" or not pointer or double) then
			spec.onActivate(current:peek(), key, input, clicks)
		end
	end
	assert(not view.cardsMode, "Facet collection recycle needs a numeric itemSize")
	return function(follow: CollectionTypes.Follow?): ComposeTypes.Child
		return Compose.OrderedCollection({
			from = view.source,
			key = view.keyOf,
			mode = spec.mode or "windowed",
			direction = spec.direction or "vertical",
			viewport = view.viewport,
			status = view.status,
			controls = view.controls,
			overscan = spec.overscan or 2,
			measured = Compose.formula(view.fullSizes),
			follow = follow,
			followThreshold = spec.followThreshold,
			layout = function(use: ComposeTypes.Use)
				local gap: number = read(spec.gap or 0, use)
				local crossGap: number = read(spec.crossGap or gap, use)
				local columns = view.gridColumns(use, math.max(0, use(view.cross)))
				return {
					kind = kind,
					columns = columns,
					itemSize = read(spec.itemSize or 40, use) :: number,
					gap = gap,
					crossGap = crossGap,
					crossSize = math.max(0, (use(view.cross) - crossGap * (columns - 1)) / columns),
				}
			end,
			recycle = function(
				current: ComposeTypes.Readable<V>,
				placement: ComposeTypes.Readable<ComposeTypes.Placement>,
				key: ComposeTypes.Readable<K>
			): GuiObject
				local hit: TextButton
				hit = Host.TextButton "RowHit" {
					Size = D2.fromScale(1, 1),
					Text = "",
					BackgroundTransparency = 1,
					Selectable = true,
					Interactable = function(use: ComposeTypes.Use): boolean
						return not policy.disabled(spec.disabled, use(current))
					end,
					Activated = function(input: InputObject?, clicks: number?)
						activate(key:peek(), current, input, clicks)
					end,
				}
				local hitChild: GuiObject = hit
				local row = Host.Frame {
					BackgroundTransparency = 1,
					LayoutOrder = function(use: ComposeTypes.Use): number
						return use(placement).index
					end,
					Position = function(use: ComposeTypes.Use): UDim2
						local at = use(placement)
						return if horizontal
							then D2.fromOffset(at.offset, at.crossOffset)
							else D2.fromOffset(at.crossOffset, at.offset)
					end,
					Size = function(use: ComposeTypes.Use): UDim2
						local at = use(placement)
						return if horizontal
							then D2.fromOffset(at.size, at.crossSize)
							else D2.fromOffset(at.crossSize, at.size)
					end,
					hitChild,
					recycle(current, placement, key),
				}
				row:SetAttribute("FacetCollectionRow", true)
				local painted = spec.selectionIndicator ~= false and selectionMode ~= "none"
				if painted then
					ctx.styled(row, "TableRow")
				end
				Compose.watch(function(use: ComposeTypes.Use)
					local chosen = read(selection, use)[use(key)] == true
					hit:SetAttribute("FacetSelected", chosen)
					if painted and chosen then
						row:AddTag("facet-selected")
					elseif painted then
						row:RemoveTag("facet-selected")
					end
				end)
				local held: K? = nil
				Compose.watch(function(use: ComposeTypes.Use)
					local next = use(key)
					if held ~= nil and mounted[held] == row then
						mounted[held] = nil
					end
					held = next
					mounted[next] = row
					row.Name = tostring(next)
				end)
				Compose.cleanup(function()
					if held ~= nil and mounted[held] == row then
						mounted[held] = nil
					end
				end)
				runtime.connect(hit, "SelectionGained", function()
					if view.scope then
						view.focusOwned = true
						view.scope.focus(key:peek())
					end
				end)
				return row
			end,
		})
	end
end
