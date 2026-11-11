--!strict
local ControlTypes = require("./control_types")
local layoutKit = require("./layout_kit")
local reorder = require("./collection_reorder")
local policy = require("./collection_policy")
local activation = require("./activation")
local TreeTypes = require("./collection_tree")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local Metrics = require("./collection_table_metrics")
local Columns = require("./collection_table_columns")
local createHighlight = require("./collection_highlight")
export type Rows<V, K> = {
	spec: CollectionTypes.TableShape<V, K>,
	rowPolicySpec: CollectionTypes.TableShape<V, K>,
	selection: ComposeTypes.Value<CollectionTypes.Selection<K>>,
	coordinator: ComposeTypes.Value<{}?>,
	rowMeasures: ComposeTypes.Value<{ [K]: number }>,
	actionGutters: ComposeTypes.Value<{ [K]: number }>,
	truncatedRows: ComposeTypes.Value<{ [K]: { [string]: boolean } }>,
	mountedRows: { [K]: number },
	unitScale: ComposeTypes.Value<number>,
	scrolledX: ComposeTypes.Value<number>,
	editors: {
		render: <Item, Key>(
			CollectionTypes.TableColumn<Item, Key>,
			(Item) -> unknown,
			(Key, string, unknown) -> (),
			(ComposeTypes.Use) -> boolean
		) -> (ComposeTypes.ReadOnlyValue<Item>, ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>, Key) -> GuiObject,
	},
	field: (V, CollectionTypes.TableColumn<V, K>) -> unknown,
	tree: TreeTypes.Tree<V, K>?,
	editor: reorder.Editor<V, K>?,
	laneWidth: (ComposeTypes.Use) -> number?,
	metrics: Metrics.Metrics,
	layout: Columns.Columns<V, K>,
}
return function<V, K>(ctx: Types.Context, UI: ControlTypes.Controls, shared: Rows<V, K>): CollectionTypes.RowRender<V, K>
	local lists = layoutKit.of(ctx)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local readColumns = ctx.read<<{ CollectionTypes.TableColumn<V, K> }>>
	local readColumn = ctx.read<<CollectionTypes.TableColumn<V, K>>>
	local readNumber = ctx.read<<number>>
	local D2, E = ctx.types.UDim2, ctx.types.Enum
	local spec, rowPolicySpec, selection, coordinator =
		shared.spec, shared.rowPolicySpec, shared.selection, shared.coordinator
	type Marked = { row: Instance, painted: Instance }
	local highlight: createHighlight.Highlight<K, Marked>? = if spec.selection ~= nil
			or spec.onSelectionChange ~= nil
			or spec.selectionMode ~= nil
		then createHighlight(Compose, selection, true, function(marked: Marked, state: createHighlight.State)
			local on = state ~= "none"
			local row, painted = marked.row, marked.painted
			if row:GetAttribute("FacetSelected") ~= on then
				row:SetAttribute("FacetSelected", on)
			end
			if on ~= painted:HasTag("facet-selected") then
				if on then
					painted:AddTag("facet-selected")
				else
					painted:RemoveTag("facet-selected")
				end
			end
		end)
		else nil
	local rowMeasures, actionGutters, truncatedRows = shared.rowMeasures, shared.actionGutters, shared.truncatedRows
	local mountedRows = shared.mountedRows
	local unitScale, scrolledX, editors, field = shared.unitScale, shared.scrolledX, shared.editors, shared.field
	local tree, editor, laneWidth = shared.tree, shared.editor, shared.laneWidth
	local metrics, layout = shared.metrics, shared.layout
	local CELL_PADDING, minimumRow = metrics.cellPadding, metrics.minimumRow
	local collapsed, disclosureWidth = layout.collapsed, layout.disclosureWidth
	local setPrimaryMeasure = layout.setPrimaryMeasure
	type Column = CollectionTypes.TableColumn<V, K>
	local staticColumns = if type(spec.columns) ~= "function" and not Compose.isValue(spec.columns)
		then readColumns(spec.columns)
		else nil
	local function build(
		current: ComposeTypes.ReadOnlyValue<V>,
		placement: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
		key: ComposeTypes.ReadOnlyValue<K>
	): GuiObject
		local heights: { [string]: (ComposeTypes.Use) -> number? } = {}
		local hides: { [string]: (ComposeTypes.Use) -> boolean } = {}
		local sourcesChanged = Compose.cell(0)
		local function measureHeight(id: string, source: (ComposeTypes.Use) -> number?)
			heights[id] = source
			sourcesChanged:set(sourcesChanged:peek() + 1)
		end
		local truncated: ComposeTypes.Value<{ [string]: boolean }> = Compose.cell({})
		local held: K? = nil
		local function release(gone: K?)
			if gone ~= nil then
				local count = (mountedRows[gone] or 1) - 1
				if count > 0 then
					mountedRows[gone] = count
				else
					mountedRows[gone] = nil
				end
			end
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local now, cells = use(key), use(truncated)
			if held ~= now then
				release(held)
				held = now
				mountedRows[now] = (mountedRows[now] or 0) + 1
			end
			local wanted = if next(cells) then cells else nil
			if truncatedRows:peek()[now] ~= wanted then
				local rows = table.clone(truncatedRows:peek())
				if wanted then
					rows[now] = wanted
				else
					rows[now] = nil
				end
				truncatedRows:set(rows)
			end
		end)
		Compose.cleanup(function()
			release(held)
		end)
		local function measureRow()
			Compose.watch(function(use: ComposeTypes.Use)
				use(sourcesChanged)
				local height = use(minimumRow)
				local hidden = use(collapsed)
				local cells = truncated:peek()
				local changed = false
				for _, column in readColumns(spec.columns, use) do
					local id = column.id
					local source = heights[id]
					if source and not hidden[id] then
						height = math.max(height, source(use) or 0)
					end
					local hide = hides[id]
					if hide and (cells[id] == true) ~= hide(use) then
						if not changed then
							cells, changed = table.clone(cells), true
						end
						cells[id] = if cells[id] then nil else true
					end
				end
				if changed then
					truncated:set(cells)
				end
				local now = use(key)
				if
					(height > use(minimumRow) or rowMeasures:peek()[now] ~= nil)
					and rowMeasures:peek()[now] ~= height
				then
					local nextHeights = table.clone(rowMeasures:peek())
					nextHeights[now] = height
					rowMeasures:set(nextHeights)
				end
			end)
		end
		local function renderColumn(column: Types.Input<Column>, index: Types.Input<number>)
			local definition = readColumn(column)
			local authored = definition.render
			local editorCell = if authored == nil and definition.editor
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
			local build: ((K) -> GuiObject)? = if authored
				then function(value: K): GuiObject
					return authored(current, placement, Compose.cell(value))
				end
				elseif editorCell then function(value: K): GuiObject
					return editorCell(current, placement, value)
				end
				else nil
			local render: ((ComposeTypes.ReadOnlyValue<K>) -> ComposeTypes.Child)? = if build
				then function(rowKey: ComposeTypes.ReadOnlyValue<K>): ComposeTypes.Child
					return Compose.switch(rowKey, {}, function(): GuiObject
						return build(rowKey:peek())
					end)
				end
				else nil
			local function valueText(use: ComposeTypes.Use): string
				local result = field(use(current), readColumn(column, use))
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
								if share then use(layout.disclosureShare) else 0,
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
			local wordFits = Compose.cell<<boolean?>>(nil)
			local longestWord: Types.Child? = if render or definition.wrap == false
				then nil
				else Compose.show(function(use: ComposeTypes.Use): boolean
					return layout.textWrap(readColumn(column, use), use)
				end, function()
					local measure = probe("LongestWord", words, false, function()
						return true
					end)
					local fits = ctx.observe.TextFits(measure)
					Compose.watch(function(use: ComposeTypes.Use)
						wordFits:set(use(fits))
					end)
					Compose.cleanup(function()
						wordFits:set(nil)
					end)
					return measure
				end)
			local undisclosed = if render then nil else probe("Undisclosed", valueText, true, metrics.touchRows)
			local content: GuiObject = if render
				then ctx.styled(
					Host.Frame "Inset" {
						BackgroundTransparency = 1,
						render(key),
						Host.UIListLayout {
							FillDirection = E.FillDirection.Vertical,
							VerticalAlignment = E.VerticalAlignment.Center,
							SortOrder = E.SortOrder.LayoutOrder,
						},
					},
					"TableCellInset"
				)
				else ctx.styled(
					ctx.text({
						Name = "Value",
						TextXAlignment = function(use: ComposeTypes.Use)
							local align = readColumn(column, use).align or "start"
							return if align == "end"
								then E.TextXAlignment.Right
								elseif align == "center" then E.TextXAlignment.Center
								else E.TextXAlignment.Left
						end,
						TextTruncate = E.TextTruncate.AtEnd,
						TextWrapped = function(use: ComposeTypes.Use): boolean
							return layout.textWrap(readColumn(column, use), use) and use(wordFits) ~= false
						end,
						Size = D2.fromScale(1, 1),
						AutomaticSize = E.AutomaticSize.None,
						Text = valueText,
					}),
					"TableValue"
				)
			if render then
				local measured = content:FindFirstChildWhichIsA("GuiObject") or content
				local size = ctx.observe.AbsoluteSize(measured)
				local owner = assert(Compose.currentOwner())
				local settled: ComposeTypes.ReadOnlyValue<boolean>? = nil
				local automatic = ctx.observe.AutomaticSize(measured)
				local authored: ComposeTypes.ReadOnlyValue<UDim2>? = nil
				local previous: number? = nil
				measureHeight(definition.id, function(use: ComposeTypes.Use): number?
					local sizing = use(automatic)
					if sizing ~= E.AutomaticSize.Y and sizing ~= E.AutomaticSize.XY then
						if authored == nil then
							authored = Compose.withOwner(owner, function()
								return ctx.observe.Size(measured)
							end)
						end
						if use(assert(authored)).Y.Scale ~= 0 then
							return previous
						end
					end
					local pixels = use(size).Y
					local height = pixels / use(unitScale) + CELL_PADDING
					if previous == height or (pixels == 0 and previous == nil and use(minimumRow) >= height) then
						return previous
					end
					if pixels == 0 and runtime.host.frames then
						if settled == nil then
							settled = Compose.withOwner(owner, function()
								return runtime.settled {
									restart = size,
									sample = function(): Vector2
										return measured.AbsoluteSize
									end,
								}
							end)
						end
						if not use(assert(settled)) then
							return previous
						end
					end
					previous = height
					return height
				end)
			end
			if not render and readNumber(index) == 1 then
				local natural = ctx.observe.TextBounds(assert(undisclosed))
				Compose.watch(function(use: ComposeTypes.Use)
					local padding = content:FindFirstChildWhichIsA("UIPadding")
					local inset = math.max(CELL_PADDING, use(metrics.textInsetSize).X / use(unitScale))
					if padding then
						local left: UDim = padding:GetStyled("PaddingLeft")
						local right: UDim = padding:GetStyled("PaddingRight")
						inset = left.Offset + right.Offset
					end
					setPrimaryMeasure(
						key:peek(),
						assert(undisclosed),
						math.ceil(use(natural).X / use(unitScale)),
						inset
					)
				end)
			end
			if not render then
				assert(content:IsA("TextLabel"))
				local fits = ctx.observe.TextFits(assert(undisclosed))
				local bounds = ctx.observe.TextBounds(assert(undisclosed))
				local size = ctx.observe.AbsoluteSize(assert(undisclosed))
				local hidden = false
				hides[definition.id] = function(use: ComposeTypes.Use): boolean
					if
						not tree
						or (
							use(size).X > 0
							and use(bounds).Y > 0
							and use(size).Y >= use(bounds).Y + CELL_PADDING * use(unitScale)
						)
					then
						hidden = use(fits) == false
					end
					return hidden
				end
				measureHeight(definition.id, metrics.textHeight(content, CELL_PADDING))
			end
			if tree and readNumber(index) == 1 then
				content = tree.wrap(content, current, key:peek())
				local outlineSize = ctx.observe.AbsoluteSize(content)
				measureHeight(definition.id, function(use: ComposeTypes.Use): number?
					return use(outlineSize).Y / use(unitScale)
				end)
			end
			local cell = ctx.styled(layout.columnFrame(column, index, content, longestWord, undisclosed), "TableCell")
			cell.ClipsDescendants = true
			return cell
		end
		local attributes: EngineTypes.Attributes = { FacetSelected = false }
		local rowProps: Types.FrameProps = {
			Name = "Row",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Attributes = attributes,
			lists.list({}, false),
		}
		if staticColumns then
			for index, column in staticColumns do
				table.insert(rowProps, renderColumn(column, index))
			end
		else
			table.insert(
				rowProps,
				Compose.keyed({
					from = function(use: ComposeTypes.Use)
						return readColumns(spec.columns, use)
					end,
					key = function(column: Column): string
						return column.id
					end,
					render = renderColumn,
				})
			)
		end
		local row: GuiObject = Host.Frame(rowProps)
		measureRow()
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
			cellRow,
			Compose.show(function(use: ComposeTypes.Use)
				return use(disclosureWidth) > 0
			end, function()
				local open = Compose.cell(false)
				local trigger = UI.Button "Details" {
					icon = "status.info",
					name = "Show details",
					appearance = "utility",
					Size = D2.new(0, 48, 1, 0),
					Position = D2.new(1, -48, 0, 0),
					AutomaticSize = E.AutomaticSize.None,
				}
				assert(trigger:IsA("GuiButton"))
				return UI.Popover {
					isPresented = open,
					onPresentedChange = function(value: boolean)
						open:set(value)
					end,
					trigger = trigger,
					content = function(): Instance
						return ctx.column({
							Compose.keyed({
								from = function(use: ComposeTypes.Use)
									local hidden, result = use(collapsed), {}
									for _, column in readColumns(spec.columns, use) do
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
									column: ComposeTypes.ReadOnlyValue<CollectionTypes.TableColumn<V, K>>,
									index: ComposeTypes.ReadOnlyValue<number>
								)
									return ctx.column({
										ctx.text({
											Text = function(use: ComposeTypes.Use)
												return tostring(use(column).label or use(column).id)
											end,
											AutomaticSize = E.AutomaticSize.XY,
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
		row = policy.actions(ctx, rowPolicySpec, current, key:peek(), row, UI.RowActions, coordinator)
		local actionButton = row:FindFirstChild("CellActions")
		if actionButton and actionButton:IsA("GuiObject") then
			local visible = ctx.observe.Visible(actionButton)
			local size = ctx.observe.AbsoluteSize(actionButton)
			Compose.watch(function(use: ComposeTypes.Use)
				local width = if use(visible) then use(size).X / use(unitScale) else 0
				if actionGutters:peek()[key:peek()] ~= width then
					local gutters = table.clone(actionGutters:peek())
					gutters[key:peek()] = width
					actionGutters:set(gutters)
				end
			end)
			Compose.cleanup(function()
				local gutters = table.clone(actionGutters:peek())
				gutters[key:peek()] = nil
				actionGutters:set(gutters)
			end)
		end
		if editor then
			row = editor.wrap(row, current, key:peek(), true)
		end
		local painted = ctx.styled<<GuiObject>>(if editor then row else disclosing, "TableRow")
		runtime.decorate(painted, {
			Position = function(use: ComposeTypes.Use)
				return D2.fromOffset(use(scrolledX), 0)
			end,
		})
		if spec.alternatingRows then
			Compose.watch(function(use: ComposeTypes.Use)
				if read(spec.alternatingRows, use) == true and use(placement).index % 2 == 0 then
					painted:AddTag("facet-tablerow-alternate")
				elseif painted:HasTag("facet-tablerow-alternate") then
					painted:RemoveTag("facet-tablerow-alternate")
				end
			end)
		end
		if highlight then
			highlight.bind(key, { row = cellRow, painted = painted })
		end
		if editor then
			local press = editor.press
			Compose.cleanup(activation.providePress(row, function(value: InputObject)
				press(key:peek(), value)
			end))
		end
		return row
	end
	return build
end
