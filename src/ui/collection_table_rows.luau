--!strict
local layoutKit = require("./layout_kit")
local reorder = require("./collection_reorder")
local policy = require("./collection_policy")
local activation = require("./activation")
local TreeTypes = require("./collection_tree")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local CollectionProps = require("./collection_props")
local InputProps = require("./input_props")
local OverlayProps = require("./overlay_props")
local Metrics = require("./collection_table_metrics")
local Columns = require("./collection_table_columns")
type Controls = {
	RowActions: Types.Constructor<CollectionProps.RowActionsSpec, Frame>,
	Popover: Types.Constructor<OverlayProps.PopoverSpec, GuiObject>,
	Button: Types.Constructor<InputProps.ButtonProps, TextButton>,
}
export type Rows<V, K> = {
	spec: CollectionTypes.TableShape<V, K>,
	rowPolicySpec: CollectionTypes.TableShape<V, K>,
	selection: ComposeTypes.Cell<CollectionTypes.Selection<K>>,
	coordinator: ComposeTypes.Cell<{}?>,
	rowMeasures: ComposeTypes.Cell<{ [K]: number }>,
	actionGutters: ComposeTypes.Cell<{ [K]: number }>,
	truncatedRows: ComposeTypes.Cell<{ [K]: { [string]: boolean } }>,
	unitScale: ComposeTypes.Cell<number>,
	scrolledX: ComposeTypes.Cell<number>,
	editors: {
		render: <Item, Key>(
			CollectionTypes.TableColumn<Item, Key>,
			(Item) -> unknown,
			(Key, string, unknown) -> (),
			(ComposeTypes.Use) -> boolean
		) -> CollectionTypes.RowRender<Item, Key>,
	},
	field: (V, CollectionTypes.TableColumn<V, K>) -> unknown,
	tree: TreeTypes.Tree<V, K>?,
	editor: reorder.Editor<V, K>?,
	laneWidth: (ComposeTypes.Use) -> number?,
	metrics: Metrics.Metrics,
	layout: Columns.Columns<V, K>,
}
return function<V, K>(ctx: Types.Context, UI: Controls, shared: Rows<V, K>): CollectionTypes.RowRender<V, K>
	local lists = layoutKit.of(ctx)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local D2, E = ctx.types.UDim2, ctx.types.Enum
	local spec, rowPolicySpec, selection, coordinator =
		shared.spec, shared.rowPolicySpec, shared.selection, shared.coordinator
	local rowMeasures, actionGutters, truncatedRows = shared.rowMeasures, shared.actionGutters, shared.truncatedRows
	local unitScale, scrolledX, editors, field = shared.unitScale, shared.scrolledX, shared.editors, shared.field
	local tree, editor, laneWidth = shared.tree, shared.editor, shared.laneWidth
	local metrics, layout = shared.metrics, shared.layout
	local CELL_PADDING, minimumRow, touchRows = metrics.cellPadding, metrics.minimumRow, metrics.touchRows
	local recordHeight, textInsetSize = metrics.recordHeight, metrics.textInsetSize
	local collapsed, disclosureWidth, disclosureShare = layout.collapsed, layout.disclosureWidth, layout.disclosureShare
	local setPrimaryMeasure, textWrap, columnFrame = layout.setPrimaryMeasure, layout.textWrap, layout.columnFrame
	return function(
		current: ComposeTypes.Readable<V>,
		placement: ComposeTypes.Readable<ComposeTypes.Placement>,
		key: K
	): GuiObject
		local cellHeights: ComposeTypes.Cell<{ [string]: number }> = Compose.cell({})
		local truncated: ComposeTypes.Cell<{ [string]: boolean }> = Compose.cell({})
		Compose.cleanup(function()
			if truncatedRows:peek()[key] == nil then
				return
			end
			local rows = table.clone(truncatedRows:peek())
			rows[key] = nil
			truncatedRows:set(rows)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local height = use(minimumRow)
			local sizes, hidden = use(cellHeights), use(collapsed)
			for _, column in read(spec.columns, use) do
				if not hidden[column.id] then
					height = math.max(height, sizes[column.id] or 0)
				end
			end
			if (height > use(minimumRow) or rowMeasures:peek()[key] ~= nil) and rowMeasures:peek()[key] ~= height then
				local nextHeights = table.clone(rowMeasures:peek())
				nextHeights[key] = height
				rowMeasures:set(nextHeights)
			end
		end)
		local rowProps: Types.FrameProps = {
			Name = "Row",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Attributes = {
				FacetSelected = function(use: ComposeTypes.Use)
					return read(selection, use)[key] == true
				end,
			} :: EngineTypes.Attributes,
			lists.list({}, false) :: ComposeTypes.Child,
			Compose.keyed({
				from = function(use: ComposeTypes.Use)
					return read(spec.columns, use)
				end,
				key = function(column: CollectionTypes.TableColumn<V, K>)
					return column.id
				end,
				render = function(
					column: ComposeTypes.Readable<CollectionTypes.TableColumn<V, K>>,
					index: ComposeTypes.Readable<number>
				)
					local definition = column:peek()
					local render: CollectionTypes.RowRender<V, K>? = definition.render
						or if definition.editor
							then editors.render(
								definition,
								function(item: V): unknown
									return field(item, definition)
								end,
								assert(spec.onCellChange),
								function(use: ComposeTypes.Use): boolean
									return not policy.disabled(spec.disabled, use(current))
								end
							)
							else nil
					local function valueText(use: ComposeTypes.Use): string
						local result = field(use(current), use(column))
						return if result == nil then "" else tostring(result)
					end
					local function words(use: ComposeTypes.Use): string
						local lines: { string } = {}
						for word in string.gmatch(valueText(use), "%S+") do
							table.insert(lines, word)
						end
						return table.concat(lines, "\n")
					end
					local function probe(
						name: string,
						text: (ComposeTypes.Use) -> string,
						share: boolean,
						lines: (ComposeTypes.Use) -> boolean
					): TextLabel
						return ctx.styled(
							ctx.text({
								Name = name,
								TextWrapped = false,
								TextTransparency = 1,
								Interactable = false,
								Size = function(use: ComposeTypes.Use)
									return D2.new(
										1,
										if share then use(disclosureShare) else 0,
										if lines(use) then 0 else 1,
										0
									)
								end,
								AutomaticSize = function(use: ComposeTypes.Use)
									return if lines(use) then E.AutomaticSize.Y else E.AutomaticSize.None
								end,
								Text = text,
							}),
							"TableValue"
						)
					end
					local longestWord = if render
						then nil
						else probe("LongestWord", words, false, function()
							return true
						end)
					local undisclosed = if render
						then nil
						else probe("Undisclosed", function(use: ComposeTypes.Use): string
							return valueText(use)
						end, true, touchRows)
					local wordFits = if longestWord then ctx.observe.TextFits(longestWord) else nil
					local custom = render
					local content: GuiObject = if custom
						then ctx.styled(
							Host.Frame "Inset" {
								BackgroundTransparency = 1,
								custom(current, placement, key) :: ComposeTypes.Child,
								Host.UIListLayout {
									FillDirection = E.FillDirection.Vertical,
									VerticalAlignment = E.VerticalAlignment.Center,
									SortOrder = E.SortOrder.LayoutOrder,
								} :: ComposeTypes.Child,
							},
							"TableCellInset"
						)
						elseif render then render(current, placement, key)
						else ctx.styled(
							ctx.text({
								Name = "Value",
								TextXAlignment = function(use: ComposeTypes.Use)
									local align = use(column).align or "start"
									return if align == "end"
										then E.TextXAlignment.Right
										elseif align == "center" then E.TextXAlignment.Center
										else E.TextXAlignment.Left
								end,
								TextTruncate = E.TextTruncate.AtEnd,
								TextWrapped = function(use: ComposeTypes.Use): boolean
									return textWrap(use(column), use) and use(assert(wordFits)) ~= false
								end,
								Size = D2.fromScale(1, 1),
								AutomaticSize = E.AutomaticSize.None,
								Text = valueText,
							}),
							"TableValue"
						)
					if render then
						local measured = if custom then content:GetChildren()[1] :: GuiObject else content
						local size = ctx.observe.AbsoluteSize(measured)
						local automatic = ctx.observe.AutomaticSize(measured)
						local authored = ctx.observe.Size(measured)
						Compose.watch(function(use: ComposeTypes.Use)
							local sizing = use(automatic)
							if
								sizing == E.AutomaticSize.Y
								or sizing == E.AutomaticSize.XY
								or use(authored).Y.Scale == 0
							then
								local height = use(size).Y / use(unitScale) + CELL_PADDING
								if height > 0 and cellHeights:peek()[definition.id] ~= height then
									local nextHeights = table.clone(cellHeights:peek())
									nextHeights[definition.id] = height
									cellHeights:set(nextHeights)
								end
							end
						end)
					end
					if not render and index:peek() == 1 then
						local natural = ctx.observe.TextBounds(assert(undisclosed))
						Compose.watch(function(use: ComposeTypes.Use)
							local padding = content:FindFirstChildWhichIsA("UIPadding")
							local inset = if padding
								then (padding:GetStyled("PaddingLeft") :: UDim).Offset + (padding:GetStyled(
									"PaddingRight"
								) :: UDim).Offset
								else math.max(CELL_PADDING, use(textInsetSize).X / use(unitScale))
							setPrimaryMeasure(key, math.ceil(use(natural).X / use(unitScale)) + inset)
						end)
						Compose.cleanup(function()
							setPrimaryMeasure(key, nil)
						end)
					end
					if not render then
						recordHeight(cellHeights, definition.id, content :: TextLabel, CELL_PADDING)
						local fits = ctx.observe.TextFits(assert(undisclosed))
						Compose.watch(function(use: ComposeTypes.Use)
							local id = use(column).id
							local hidden = use(fits) == false
							if (truncated:peek()[id] == true) ~= hidden then
								local cells = table.clone(truncated:peek())
								if hidden then
									cells[id] = true
								else
									cells[id] = nil
								end
								truncated:set(cells)
								local rows = table.clone(truncatedRows:peek())
								if next(cells) then
									rows[key] = cells
								else
									rows[key] = nil
								end
								truncatedRows:set(rows)
							end
						end)
					end
					if tree and index:peek() == 1 then
						content = tree.wrap(content, current, key)
						local outlineSize = ctx.observe.AbsoluteSize(content)
						Compose.watch(function(use: ComposeTypes.Use)
							local sizes = table.clone(cellHeights:peek())
							sizes[definition.id] = use(outlineSize).Y / use(unitScale)
							cellHeights:set(sizes)
						end)
					end
					local cell = ctx.styled(columnFrame(column, index, content, longestWord, undisclosed), "TableCell")
					cell.ClipsDescendants = true
					return cell
				end,
			}),
		}
		local row = Host.Frame(rowProps)
		runtime.decorate(row, {
			Size = function(use: ComposeTypes.Use)
				local lane = laneWidth(use)
				return if lane then D2.new(0, lane, 1, 0) else D2.new(1, -use(disclosureWidth), 1, 0)
			end,
			Position = function(use: ComposeTypes.Use)
				return D2.fromOffset(-use(scrolledX), 0)
			end,
		})
		local cellRow = row
		local rowProps: Types.FrameProps = {
			Name = "DisclosingRow",
			Size = D2.fromScale(1, 1),
			ClipsDescendants = true,
			cellRow :: ComposeTypes.Child,
			Compose.show(function(use: ComposeTypes.Use)
				return use(disclosureWidth) > 0
			end, function()
				local open = Compose.cell(false)
				return UI.Popover {
					isPresented = open,
					onPresentedChange = function(value: boolean)
						open:set(value)
					end,
					trigger = UI.Button "Details" {
						icon = "status.info",
						name = "Show details",
						appearance = "utility",
						Size = D2.new(0, 48, 1, 0),
						Position = D2.new(1, -48, 0, 0),
						AutomaticSize = E.AutomaticSize.None,
					} :: GuiButton,
					content = function(): Instance
						return ctx.column({
							Compose.keyed({
								from = function(use: ComposeTypes.Use)
									local hidden, result = use(collapsed), {}
									for _, column in read(spec.columns, use) do
										if hidden[column.id] or use(truncated)[column.id] then
											table.insert(result, column)
										end
									end
									return result
								end,
								key = function(column: CollectionTypes.TableColumn<V, K>)
									return column.id
								end,
								render = function(
									column: ComposeTypes.Readable<CollectionTypes.TableColumn<V, K>>,
									index: ComposeTypes.Readable<number>
								)
									return ctx.column({
										ctx.text({
											Text = function(use: ComposeTypes.Use)
												return tostring(use(column).label or use(column).id)
											end,
										}),
										if column:peek().detailRender
											then (assert(column:peek().detailRender))(current, placement, key)
											else ctx.text({
												Name = "FullValue",
												TextWrapped = true,
												Size = D2.new(1, 0, 0, 0),
												AutomaticSize = E.AutomaticSize.Y,
												Text = function(use: ComposeTypes.Use)
													local value, item = use(column), use(current)
													local result = if value.value
														then value.value(item)
														else field(item, value)
													return if result == nil then "" else tostring(result)
												end,
											}),
									}, {
										Name = column:peek().id,
										LayoutOrder = index,
										Size = D2.new(1, 0, 0, 0),
										AutomaticSize = E.AutomaticSize.Y,
									})
								end,
							}),
						}, { Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
					end,
				}
			end),
		}
		if editor then
			rowProps.BackgroundTransparency = 1
		end
		row = Host.Frame(rowProps)
		local disclosing = row
		row = policy.actions(ctx, rowPolicySpec, current, key, row, UI.RowActions, coordinator) :: Frame
		local actionButton = row:FindFirstChild("CellActions")
		if actionButton and actionButton:IsA("GuiObject") then
			local visible = ctx.observe.Visible(actionButton)
			local size = ctx.observe.AbsoluteSize(actionButton)
			Compose.watch(function(use: ComposeTypes.Use)
				local width = if use(visible) then use(size).X / use(unitScale) else 0
				if actionGutters:peek()[key] ~= width then
					local gutters = table.clone(actionGutters:peek())
					gutters[key] = width
					actionGutters:set(gutters)
				end
			end)
			Compose.cleanup(function()
				local gutters = table.clone(actionGutters:peek())
				gutters[key] = nil
				actionGutters:set(gutters)
			end)
		end
		if editor then
			row = editor.wrap(row, current, key, true)
		end
		local painted = ctx.styled(if editor then row else disclosing, "TableRow")
		runtime.decorate(painted, {
			Position = function(use: ComposeTypes.Use)
				return D2.fromOffset(use(scrolledX), 0)
			end,
		})
		Compose.watch(function(use: ComposeTypes.Use)
			if read(spec.alternatingRows, use) == true and use(placement).index % 2 == 0 then
				painted:AddTag("facet-tablerow-alternate")
			elseif painted:HasTag("facet-tablerow-alternate") then
				painted:RemoveTag("facet-tablerow-alternate")
			end
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local on = read(selection, use)[key] == true
			if on ~= painted:HasTag("facet-selected") then
				if on then
					painted:AddTag("facet-selected")
				else
					painted:RemoveTag("facet-selected")
				end
			end
		end)
		if editor then
			local press = editor.press
			Compose.cleanup(activation.providePress(row, function(value: InputObject)
				press(key, value)
			end))
		end
		return row
	end
end
