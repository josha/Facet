--!strict
local layoutKit = require("./layout_kit")
local reorder = require("./collection_reorder")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
local NavigationTypes = require("./navigation_types")
type Controls = {
	Table: CollectionTypes.TableConstructor,
	VirtualList: <V, K>(spec: CollectionTypes.KeyedCollectionSpec<V, K>) -> ScrollingFrame,
	RowActions: Types.Constructor<CollectionTypes.RowActionsSpec, Frame>,
	CollapsibleView: Types.Constructor<NavigationTypes.CollapsibleViewSpec, TextButton>,
	Button: Types.Constructor<InputTypes.ButtonProps, TextButton>,
}
return function(ctx: Types.Context, UI: Controls): ()
	local lists = layoutKit.of(ctx)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local readSource = ctx.readSource
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local behavior = {
		"from",
		"key",
		"columns",
		"itemSize",
		"gap",
		"overscan",
		"sort",
		"onSortChange",
		"widths",
		"onWidthsChange",
		"selection",
		"selectionMode",
		"onSelectionChange",
		"onActivate",
		"rowActions",
		"headerHeight",
		"status",
		"controls",
		"focus",
		"disabled",
		"measure",
		"measured",
		"follow",
		"followThreshold",
		"reducedMotion",
		"reorderable",
		"onReorder",
		"movable",
		"selectable",
		"editing",
		"scrolls",
		"mode",
		"snap",
		"header",
		"dragLabel",
	}
	local function create<V, K>(spec: CollectionTypes.TableOptions<V, K>, keyOf: (V, number) -> K): Frame
		assert(spec.columns ~= nil, "Facet.Table requires columns")
		local sort: ComposeTypes.Cell<CollectionTypes.Sort?> = spec.sort or Compose.cell(nil :: CollectionTypes.Sort?)
		local widths: ComposeTypes.Cell<{ [string]: number }> = spec.widths or Compose.cell({})
		local selection: ComposeTypes.Cell<CollectionTypes.Selection<K>> = spec.selection or Compose.cell({})
		local status: ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus> = spec.status
			or Compose.cell({
				mode = "windowed",
				direction = "vertical",
				total = 0,
				retained = 0,
				first = 0,
				last = 0,
				firstRow = 0,
				lastRow = 0,
				rowCount = 0,
				extent = 0,
				following = false,
				measured = 0,
			} :: ComposeTypes.OrderedCollectionStatus)
		local contentExtent = Compose.formula(function(use: ComposeTypes.Use): number
			local current = use(status)
			return if current then current.extent else 0
		end)
		local coordinator: ComposeTypes.Cell<{}?> = Compose.cell(nil :: {}?)
		local queries: ComposeTypes.OrderedCollectionControls<K> = spec.controls or {}
		local body: ScrollingFrame
		local rowMeasures: ComposeTypes.Cell<{ [K]: number }> = Compose.cell({})
		local headerMeasures: ComposeTypes.Cell<{ [string]: number }> = Compose.cell({})
		local truncatedRows: ComposeTypes.Cell<{ [K]: { [string]: boolean } }> = Compose.cell({})
		local editGutters: ComposeTypes.Cell<{ [K]: number }> = Compose.cell({})
		local editGutter = Compose.formula(function(use: ComposeTypes.Use)
			local widest = 0
			for _, gutter in use(editGutters) do
				widest = math.max(widest, gutter)
			end
			return widest
		end)
		local input = ctx.config.userInputService
		local preferredInput: ComposeTypes.Readable<Enum.PreferredInput>? = if input
			then ctx.observe.PreferredInput(input)
			else nil
		local minimumRow = Compose.formula(function(use: ComposeTypes.Use)
			if spec.itemSize ~= nil then
				return read(spec.itemSize, use)
			end
			local kind = if preferredInput then use(preferredInput) else nil
			return math.max(
				40,
				ctx.controlSize(nil, "height", use),
				if kind == E.PreferredInput.Touch or kind == E.PreferredInput.Gamepad then 44 else 0
			)
		end)
		local headerHeight = Compose.formula(function(use: ComposeTypes.Use)
			if spec.header == false then
				return 0
			end
			local kind = if preferredInput then use(preferredInput) else nil
			local size = read(spec.headerHeight, use) or 40
			if kind == E.PreferredInput.Touch or kind == E.PreferredInput.Gamepad then
				size = math.max(size, 44)
			end
			for _, column in read(spec.columns, use) do
				size = math.max(size, use(headerMeasures)[column.id] or 0)
			end
			return size
		end)
		local function recordHeight(
			cell: ComposeTypes.Cell<{ [string]: number }>,
			id: string,
			node: TextLabel | TextButton,
			extra: number
		): ()
			local observed: ComposeTypes.Readable<Vector2> = if node:IsA("TextLabel")
				then ctx.observe.TextBounds(node)
				else ctx.observe.TextBounds(node)
			Compose.watch(function(use: ComposeTypes.Use)
				local bounds = use(observed)
				local height = bounds.Y + extra
				if height > 0 and cell:peek()[id] ~= height then
					local nextHeights = table.clone(cell:peek())
					nextHeights[id] = height
					cell:set(nextHeights)
				end
			end)
		end
		local viewportWidth = Compose.cell(0)
		local function setWidths(value: { [string]: number }): ()
			if spec.onWidthsChange then
				spec.onWidthsChange(value)
			else
				widths:set(value)
			end
		end
		local function field(item: V, column: CollectionTypes.TableColumn<V, K>): unknown
			if column.value then
				return column.value(item)
			end
			if type(item) == "table" then
				return (item :: { [string]: unknown })[column.id]
			end
			return nil
		end
		local ordered: ComposeTypes.Formula<{ V }> = Compose.formula(function(use: ComposeTypes.Use)
			local rows: { V } = read(spec.from, use)
			local order = use(sort)
			if order == nil then
				return rows
			end
			local column: CollectionTypes.TableColumn<V, K>?
			for _, candidate in read(spec.columns, use) do
				if candidate.id == order.column then
					column = candidate
					break
				end
			end
			if column == nil then
				return rows
			end
			local indexed: { { item: V, index: number } } = table.create(#rows)
			for index, item in rows do
				indexed[index] = { item = item, index = index }
			end
			table.sort(indexed, function(a, b)
				local left = field(a.item, assert(column))
				local right = field(b.item, assert(column))
				if left == right then
					return a.index < b.index
				end
				local before
				if left == nil then
					before = true
				elseif right == nil then
					before = false
				elseif type(left) == "number" and type(right) == "number" then
					before = left < right
				else
					before = tostring(left) < tostring(right)
				end
				return if order.direction == "descending" then not before else before
			end)
			local result: { V } = table.create(#rows)
			for index, entry in indexed do
				result[index] = entry.item
			end
			return result
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local valid: { [K]: boolean } = {}
			for index, item in read(spec.from, use) do
				valid[keyOf(item, index)] = true
			end
			local sizes: { [K]: number } = {}
			local changed = false
			for key, height in rowMeasures:peek() do
				if valid[key] then
					sizes[key] = height
				else
					changed = true
				end
			end
			if changed then
				rowMeasures:set(sizes)
			end
		end)
		local collapsed = Compose.formula(function(use: ComposeTypes.Use)
			local columns, offer, resized = read(spec.columns, use), use(viewportWidth), readSource(widths, use)
			local hidden: { [string]: boolean } = {}
			local candidates: { { id: string, width: number, priority: number } } = {}
			local needed = 0
			for index, column in columns do
				local width = resized[column.id] or column.width or column.minWidth or 48
				needed += width
				if index > 1 and column.priority ~= "always" then
					table.insert(candidates, { id = column.id, width = width, priority = column.priority or index })
				end
			end
			table.sort(candidates, function(a, b)
				return a.priority > b.priority
			end)
			if offer > 0 then
				for _, candidate in candidates do
					if needed <= offer then
						break
					end
					if next(hidden) == nil then
						offer -= 48
					end
					hidden[candidate.id] = true
					needed -= candidate.width
				end
			end
			return hidden
		end)
		local disclosureWidth = Compose.formula(function(use: ComposeTypes.Use)
			if next(use(collapsed)) ~= nil then
				return 48
			end
			for _, value in use(truncatedRows) do
				if next(value) ~= nil then
					return 48
				end
			end
			return 0
		end)
		local function columnWidth(
			current: ComposeTypes.Readable<CollectionTypes.TableColumn<V, K>>,
			use: ComposeTypes.Use
		): number?
			local column = use(current)
			return readSource(widths, use)[column.id] or column.width
		end
		local function columnFrame(
			current: ComposeTypes.Readable<CollectionTypes.TableColumn<V, K>>,
			index: ComposeTypes.Readable<number>,
			content: GuiObject,
			extra: GuiObject?
		): Frame
			local nativeProps: Types.FrameProps = {
				Name = current:peek().id,
				Visible = function(use: ComposeTypes.Use)
					return not use(collapsed)[use(current).id]
				end,
				LayoutOrder = index,
				BackgroundTransparency = 1,
				Size = function(use: ComposeTypes.Use)
					return D2.new(0, columnWidth(current, use) or 0, 1, 0)
				end,
				Host.UISizeConstraint({
					MinSize = function(use: ComposeTypes.Use)
						return V2.new(use(current).minWidth or 48, 0)
					end,
					MaxSize = function(use: ComposeTypes.Use)
						return V2.new(use(current).maxWidth or 1000000, 1000000)
					end,
				}) :: ComposeTypes.Child,
				Host.UIFlexItem({
					FlexMode = function(use: ComposeTypes.Use)
						return if columnWidth(current, use) == nil then E.UIFlexMode.Fill else E.UIFlexMode.None
					end,
				}),
				content,
				extra,
			}
			return Host.Frame(nativeProps)
		end
		local headerCells = Compose.keyed({
			from = function(use: ComposeTypes.Use)
				return read(spec.columns, use)
			end,
			key = function(column: CollectionTypes.TableColumn<V, K>)
				return column.id
			end,
			render = function(
				current: ComposeTypes.Readable<CollectionTypes.TableColumn<V, K>>,
				index: ComposeTypes.Readable<number>
			)
				local column = current:peek()
				local buttonProps: InputTypes.ButtonProps = {
					Name = "Sort",
					Size = D2.fromScale(1, 1),
					AutomaticSize = E.AutomaticSize.None,
					appearance = "utility",
					TextXAlignment = E.TextXAlignment.Left,
					label = function(use: ComposeTypes.Use): string
						local value, order = use(current), readSource(sort, use)
						local suffix = if order and order.column == value.id
							then (if order.direction == "descending" then " ↓" else " ↑")
							else ""
						return tostring(read(value.label or value.id, use)) .. suffix
					end,
					enabled = function(use: ComposeTypes.Use): boolean
						return use(current).sortable ~= false
					end,
					onActivate = function()
						local order = readSource(sort)
						local descending = order and order.column == column.id and order.direction == "ascending"
						local nextSort: CollectionTypes.Sort = {
							column = column.id,
							direction = if descending then "descending" else "ascending",
						}
						if spec.onSortChange then
							spec.onSortChange(nextSort)
						else
							sort:set(nextSort)
						end
					end,
				}
				local button = UI.Button(buttonProps)
				local frame: Frame
				local grip: TextButton?
				if column.resizable ~= false then
					local startingPosition, startingWidth = 0, 0
					local gripProps: Types.TextButtonProps = {
						Name = "Resize",
						Text = "",
						Attributes = {
							AccessibleLabel = (function(use: ComposeTypes.Use): string
								local value = use(current)
								return "Resize " .. tostring(read(value.label or value.id, use))
							end) :: Types.Value<Types.AttributeValue?>,
						},
						Selectable = true,
						AnchorPoint = V2.new(1, 0),
						Position = D2.fromScale(1, 0),
						Size = function(use: ComposeTypes.Use)
							return D2.new(
								0,
								if preferredInput and use(preferredInput) == E.PreferredInput.Touch then 44 else 12,
								1,
								0
							)
						end,
						BackgroundTransparency = 1,
						ZIndex = 3,
						Host.UIDragDetector({
							DragStyle = E.UIDragDetectorDragStyle.TranslateLine,
							DragAxis = V2.new(1, 0),
							ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
							DragStart = function(position)
								startingPosition, startingWidth = position.X, frame.AbsoluteSize.X
							end,
							DragContinue = function(position)
								local value = current:peek()
								local nextWidths = table.clone(readSource(widths))
								nextWidths[value.id] = math.clamp(
									startingWidth + position.X - startingPosition,
									value.minWidth or 48,
									value.maxWidth or 1000000
								)
								setWidths(nextWidths)
							end,
						}),
					}
					grip = Host.TextButton(gripProps)
				end
				frame = ctx.styled(columnFrame(current, index, button, grip), "TableHeader")
				recordHeight(headerMeasures, column.id, button, 16)
				if grip then
					local selected = Compose.cell(false)
					runtime.connect(grip, "SelectionGained", function()
						selected:set(true)
					end)
					runtime.connect(grip, "SelectionLost", function()
						selected:set(false)
					end)
					local function adjust(delta: number): ()
						local value = current:peek()
						local nextWidths = table.clone(readSource(widths))
						nextWidths[value.id] = math.clamp(
							(nextWidths[value.id] or frame.AbsoluteSize.X) + delta,
							value.minWidth or 48,
							value.maxWidth or 1000000
						)
						setWidths(nextWidths)
					end
					ctx.action(grip, "NarrowColumn", { E.KeyCode.Left, E.KeyCode.DPadLeft }, selected, function()
						adjust(-8)
					end, { priority = 300, capture = true })
					ctx.action(grip, "WidenColumn", { E.KeyCode.Right, E.KeyCode.DPadRight }, selected, function()
						adjust(8)
					end, { priority = 300, capture = true })
				end
				return frame
			end,
		})
		local headerLayout = lists.list({}, false)
		local headerProps: Types.FrameProps = {
			Name = "Header",
			Visible = spec.header ~= false,
			Size = function(use: ComposeTypes.Use)
				return D2.new(1, 0, 0, use(headerHeight))
			end,
			BackgroundTransparency = 1,
			headerLayout :: ComposeTypes.Child,
			headerCells,
		}
		local header = Host.Frame(headerProps)
		local headerExtent = ctx.observe.AbsoluteContentSize(headerLayout)
		local reorderGutter = if spec.reorderable then 56 else 0
		local wrapReorder: ((GuiObject, ComposeTypes.Readable<V>, K) -> Frame)?
		local overlayReorder: ((boolean?) -> Frame)?
		if spec.reorderable then
			wrapReorder, overlayReorder = reorder(ctx, UI, spec, ordered, keyOf, queries, function()
				return body
			end, selection, sort)
		end
		local bodySpec: CollectionTypes.KeyedCollectionSpec<V, K> = {
			Name = "Body",
			Position = function(use: ComposeTypes.Use)
				return D2.fromOffset(0, use(headerHeight))
			end,
			Size = function(use: ComposeTypes.Use)
				return if spec.scrolls == false
					then D2.new(1, 0, 0, use(contentExtent))
					else D2.new(1, 0, 1, -use(headerHeight))
			end,
			ScrollingEnabled = spec.scrolls ~= false,
			ClipsDescendants = spec.scrolls ~= false,
			mode = if spec.scrolls == false then "all" :: ComposeTypes.OrderedCollectionMode else spec.mode,
			ScrollingDirection = E.ScrollingDirection.XY,
			CanvasSize = function(use: ComposeTypes.Use)
				return D2.fromOffset(use(headerExtent).X + reorderGutter + use(editGutter), use(contentExtent))
			end,
			from = ordered,
			key = keyOf,
			itemSize = minimumRow,
			gap = spec.gap,
			overscan = spec.overscan,
			status = status,
			controls = queries,
			focus = spec.focus,
			disabled = spec.disabled,
			measure = spec.measure,
			measured = function(use: ComposeTypes.Use)
				local result = table.clone(use(rowMeasures))
				for key, height in result do
					result[key] = math.max(height, use(minimumRow))
				end
				local external: { [K]: number } = read(spec.measured or {}, use)
				for key, height in external do
					result[key] = height
				end
				return result
			end,
			follow = spec.follow,
			snap = spec.snap,
			reducedMotion = spec.reducedMotion,
			followThreshold = spec.followThreshold,
			selection = selection,
			selectionMode = spec.selectionMode,
			selectable = spec.selectable,
			onSelectionChange = spec.onSelectionChange,
			onActivate = spec.onActivate,

			render = function(
				current: ComposeTypes.Readable<V>,
				placement: ComposeTypes.Readable<ComposeTypes.Placement>,
				key: K
			): GuiObject
				local cellHeights: ComposeTypes.Cell<{ [string]: number }> = Compose.cell({})
				local truncated: ComposeTypes.Cell<{ [string]: boolean }> = Compose.cell({})
				Compose.cleanup(function()
					local rows = table.clone(truncatedRows:peek())
					rows[key] = nil
					truncatedRows:set(rows)
				end)
				Compose.watch(function(use: ComposeTypes.Use)
					local height = use(minimumRow)
					local sizes = use(cellHeights)
					for _, column in read(spec.columns, use) do
						height = math.max(height, sizes[column.id] or 0)
					end
					if
						(height > use(minimumRow) or rowMeasures:peek()[key] ~= nil)
						and rowMeasures:peek()[key] ~= height
					then
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
							local content = if definition.render
								then definition.render(current, placement, key)
								else ctx.styled(
									ctx.text({
										Name = "Value",
										TextTruncate = E.TextTruncate.AtEnd,
										Size = D2.fromScale(1, 1),
										AutomaticSize = E.AutomaticSize.None,
										Text = function(use: ComposeTypes.Use)
											local item, value = use(current), use(column)
											local result = field(item, value)
											return if result == nil then "" else tostring(result)
										end,
									}),
									"TableValue"
								)
							if not definition.render then
								recordHeight(cellHeights, definition.id, content :: TextLabel, 16)
								local fits = ctx.observe.TextFits(content :: TextLabel)
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
										rows[key] = cells
										truncatedRows:set(rows)
									end
								end)
							end
							return ctx.styled(columnFrame(column, index, content), "TableCell")
						end,
					}),
				}
				local row = Host.Frame(rowProps)
				runtime.decorate(row, {
					Size = function(use: ComposeTypes.Use)
						return D2.new(1, -use(disclosureWidth), 1, 0)
					end,
				})
				local cellRow = row
				local rowProps: Types.FrameProps = {
					Name = "DisclosingRow",
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					cellRow :: ComposeTypes.Child,
					Compose.show(function(use: ComposeTypes.Use)
						return use(disclosureWidth) > 0
					end, function()
						return UI.CollapsibleView "Details" {
							label = "More",
							expanded = Compose.cell(false),
							Size = D2.new(0, 48, 1, 0),
							Position = D2.new(1, -48, 0, 0),
							AutomaticSize = E.AutomaticSize.None,
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
												ctx.text({
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
				row = Host.Frame(rowProps)
				if wrapReorder then
					row = wrapReorder(row, current, key)
				end
				local actions = if spec.rowActions then spec.rowActions(current, key) else nil
				if actions then
					local actionSpec: CollectionTypes.RowActionsSpec =
						table.clone(actions) :: CollectionTypes.RowActionsSpec
					actionSpec.content, actionSpec.coordinator = row, coordinator
					actionSpec.Size = D2.fromScale(1, 1)
					actionSpec.reducedMotion = spec.reducedMotion
					actionSpec.editing = spec.editing
					local wrapped = UI.RowActions(actionSpec)
					local content = wrapped:FindFirstChild("Content")
					if content and content:IsA("GuiObject") then
						local size: ComposeTypes.Readable<UDim2> = ctx.observe.Size(content)
						Compose.watch(function(use: ComposeTypes.Use)
							local gutter = math.max(0, -use(size).X.Offset)
							if (editGutters:peek()[key] or 0) ~= gutter then
								local gutters = table.clone(editGutters:peek())
								if gutter > 0 then
									gutters[key] = gutter
								else
									gutters[key] = nil
								end
								editGutters:set(gutters)
							end
						end)
						Compose.cleanup(function()
							if editGutters:peek()[key] ~= nil then
								local gutters = table.clone(editGutters:peek())
								gutters[key] = nil
								editGutters:set(gutters)
							end
						end)
					end
					return wrapped
				end
				return row
			end,
		}
		body = UI.VirtualList(bodySpec)
		local position, window = ctx.observe.CanvasPosition(body), ctx.observe.AbsoluteWindowSize(body)
		Compose.watch(function(use: ComposeTypes.Use)
			use(position)
			viewportWidth:set(use(window).X - reorderGutter - use(editGutter))
			coordinator:set(nil)
		end)
		local scrolledX = Compose.formula(function(use: ComposeTypes.Use): number
			return use(position).X
		end)
		runtime.decorate(header, {
			Position = function(use: ComposeTypes.Use)
				return D2.fromOffset(reorderGutter + use(editGutter) - use(scrolledX), 0)
			end,
			Size = function(use: ComposeTypes.Use)
				local width = use(window).X
				return if width > 0
					then D2.fromOffset(
						math.max(0, width - reorderGutter - use(editGutter) - use(disclosureWidth)),
						use(headerHeight)
					)
					else D2.new(1, -reorderGutter - use(editGutter) - use(disclosureWidth), 0, use(headerHeight))
			end,
		})
		return ctx.styled(
			Host.Frame(ctx.props(spec, behavior, {
				Size = function(use: ComposeTypes.Use)
					return if spec.scrolls == false
						then D2.new(1, 0, 0, use(contentExtent) + use(headerHeight))
						else D2.fromScale(1, 1)
				end,
				BackgroundTransparency = 1,
				ClipsDescendants = spec.scrolls ~= false,
				header :: ComposeTypes.Child,
				body,
				if overlayReorder then overlayReorder() else nil,
			})),
			"Table"
		)
	end
	local function constructor<V, K>(spec: CollectionTypes.TableSpec<V, K>): Frame
		if spec.key == nil then
			return create(spec, function(item: V, _index: number): V
				return item
			end)
		end
		local key: unknown = spec.key
		if type(key) == "string" then
			assert(key ~= "", "Facet UI.Table: key field must not be empty")
			local fieldSpec = (spec :: unknown) :: CollectionTypes.KeyedTableSpec<V, string>
			return create(fieldSpec, function(item: V, _index: number): string
				return tostring(((item :: unknown) :: { [string]: unknown })[key])
			end)
		end
		assert(type(key) == "function", "Facet UI.Table: key must be a function or a field name")
		return create((spec :: unknown) :: CollectionTypes.KeyedTableSpec<V, K>, (key :: unknown) :: (V, number) -> K)
	end
	local tableConstructor: CollectionTypes.TableConstructor = ctx.construct("Table", constructor)
	UI.Table = tableConstructor
end
