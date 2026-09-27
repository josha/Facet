--!strict
local layoutKit = require("./layout_kit")
local reorder = require("./collection_reorder")
local policy = require("./collection_policy")
local activation = require("./activation")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
local NavigationTypes = require("./navigation_types")
local OverlayTypes = require("./overlay_types")
local tableEditors = require("./collection_table_editors")

local CELL_PADDING = 16

type Controls = {
	Table: CollectionTypes.TableConstructor,
	VirtualList: <V, K>(spec: CollectionTypes.KeyedCollectionSpec<V, K>) -> ScrollingFrame,
	RowActions: Types.Constructor<CollectionTypes.RowActionsSpec, Frame>,
	Popover: Types.Constructor<OverlayTypes.PopoverSpec, GuiObject>,
	Button: Types.Constructor<InputTypes.ButtonProps, TextButton>,
	TextInput: Types.Constructor<InputTypes.TextInputProps, TextBox | Frame>,
	NumberInput: Types.Constructor<InputTypes.NumberInputProps, TextBox | Frame>,
	Toggle: Types.Constructor<InputTypes.ToggleProps, TextButton>,
	Picker: NavigationTypes.PickerConstructor,
}
return function(ctx: Types.Context, UI: Controls): ()
	local lists = layoutKit.of(ctx)
	local editors = tableEditors(ctx, UI)
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
		"autoscroll",
		"onCellChange",
		"alternatingRows",
		"deletable",
		"rowDeletable",
		"onDelete",
	}
	local function create<V, K>(spec: CollectionTypes.TableOptions<V, K>, keyOf: (V, number) -> K): Frame
		assert(spec.columns ~= nil, "Facet.Table requires columns")
		local manageable = spec.reorderable == true or spec.deletable == true
		local ownsToggle = manageable and spec.editing == nil and spec.header ~= false
		local editing: Types.ValueBoolean? = if ownsToggle then Compose.cell(false) else spec.editing
		Compose.watch(function(use: ComposeTypes.Use)
			editors.check(read(spec.columns, use), spec.onCellChange)
		end)
		local sort: ComposeTypes.Cell<CollectionTypes.Sort?> = spec.sort or Compose.cell(nil :: CollectionTypes.Sort?)
		local widths: ComposeTypes.Cell<{ [string]: number }> = spec.widths or Compose.cell({})
		local selection: ComposeTypes.Cell<CollectionTypes.Selection<K>> = spec.selection or Compose.cell({})
		local status: ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus> = spec.status
			or Compose.cell((nil :: unknown) :: ComposeTypes.OrderedCollectionStatus)
		if status:peek() == nil then
			status:set({
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
		end
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
		local input = ctx.config.userInputService
		local preferredInput: ComposeTypes.Readable<Enum.PreferredInput>? = if input
			then ctx.observe.PreferredInput(input)
			else nil
		local tenFoot = ctx.tenFoot()
		local function touchRows(use: ComposeTypes.Use): boolean
			return preferredInput ~= nil and use(preferredInput) == E.PreferredInput.Touch
		end
		local function lineBox(use: ComposeTypes.Use): number
			return math.ceil(ctx.metric("typography.body.size", use) * ctx.metric("typography.body.lineHeight", use))
		end

		local minimumRow = Compose.formula(function(use: ComposeTypes.Use)
			if spec.itemSize ~= nil then
				return read(spec.itemSize, use)
			end
			if touchRows(use) then
				return math.max(ctx.metric("targetSizes.minimum", use), 2 * lineBox(use) + CELL_PADDING)
			end
			if tenFoot(use) then
				return math.max(ctx.controlSize("large", "height", use), lineBox(use) + CELL_PADDING)
			end
			local kind = if preferredInput then use(preferredInput) else nil
			return math.max(40, ctx.controlSize(nil, "height", use), if kind == E.PreferredInput.Gamepad then 44 else 0)
		end)
		local function coarse(use: ComposeTypes.Use): boolean
			local kind = if preferredInput then use(preferredInput) else nil
			return kind == E.PreferredInput.Touch or kind == E.PreferredInput.Gamepad
		end
		local mouse = if input then ctx.observe.MouseEnabled(input) else nil
		local keyboard = if input then ctx.observe.KeyboardEnabled(input) else nil
		local function toolbarShown(use: ComposeTypes.Use): boolean
			local keysOnly = spec.reorderable == true
				and keyboard ~= nil
				and use(keyboard) == true
				and mouse ~= nil
				and use(mouse) == false
			return ownsToggle and (coarse(use) or keysOnly)
		end
		local toolbarHeight = Compose.formula(function(use: ComposeTypes.Use)
			return if toolbarShown(use)
				then math.max(ctx.controlSize(nil, "height", use), 44) + ctx.metric("space.s", use)
				else 0
		end)
		local cellsLive = function(use: ComposeTypes.Use): boolean
			return not toolbarShown(use) or read(editing, use) == true
		end
		local headerHeight = Compose.formula(function(use: ComposeTypes.Use)
			if spec.header == false then
				return 0
			end
			local size = read(spec.headerHeight, use) or 40
			if coarse(use) then
				size = math.max(size, 44)
			end
			for _, column in read(spec.columns, use) do
				size = math.max(size, use(headerMeasures)[column.id] or 0)
			end
			return size
		end)
		local topHeight = Compose.formula(function(use: ComposeTypes.Use)
			return use(toolbarHeight) + use(headerHeight)
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
				if index > 1 and type(column.priority) == "number" then
					table.insert(candidates, { id = column.id, width = width, priority = column.priority })
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
		local disclosureShare = Compose.formula(function(use: ComposeTypes.Use): number
			if next(use(collapsed)) ~= nil then
				return 0
			end
			local hidden, resized, flexible = use(collapsed), readSource(widths, use), 0
			for _, column in read(spec.columns, use) do
				if not hidden[column.id] and resized[column.id] == nil and column.width == nil then
					flexible += 1
				end
			end
			return if flexible > 0 then use(disclosureWidth) / flexible else 0
		end)
		local function minimumOf(column: CollectionTypes.TableColumn<V, K>, use: ComposeTypes.Use): number
			local minimum = column.minWidth or 48
			return if coarse(use) then math.min(minimum, (ctx.metric("targetSizes.minimum", use))) else minimum
		end
		local narrowest = Compose.formula(function(use: ComposeTypes.Use): number
			local hidden, resized, total = use(collapsed), readSource(widths, use), 0
			for _, column in read(spec.columns, use) do
				if not hidden[column.id] then
					total += resized[column.id] or column.width or minimumOf(column, use)
				end
			end
			return total
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
			extra: GuiObject?,
			more: GuiObject?
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
						return V2.new(minimumOf(use(current), use), 0)
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
				more,
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
						if column.sortable == false then
							return
						end
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
				local button = ctx.styled(UI.Button(buttonProps), "TableHeading")
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
				Compose.cleanup((runtime.mount(function()
					return ctx.styled(
						Host.Frame({
							Name = "ColumnDivider",
							AnchorPoint = V2.new(0, 0.5),
							Position = D2.fromScale(0, 0.5),
							Size = function(use: ComposeTypes.Use)
								return D2.new(0, ctx.metric("strokes.hairline", use), 0.6, 0)
							end,
							Visible = function(use: ComposeTypes.Use)
								return use(index) > 1
							end,
							ZIndex = 2,
						}),
						"divider"
					)
				end, frame)))
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
					local heading = Compose.cell(false)
					runtime.connect(button, "SelectionGained", function()
						heading:set(true)
					end)
					runtime.connect(button, "SelectionLost", function()
						heading:set(false)
					end)
					local function engaged(use: ComposeTypes.Use): boolean
						return use(selected) or use(heading)
					end
					ctx.action(grip, "NarrowColumnKey", { E.KeyCode.Comma }, engaged, function()
						adjust(-8)
					end, { priority = 300 })
					ctx.action(grip, "WidenColumnKey", { E.KeyCode.Period }, engaged, function()
						adjust(8)
					end, { priority = 300 })
					ctx.action(
						grip,
						"SortColumn",
						{ E.KeyCode.Up, E.KeyCode.Down, E.KeyCode.DPadUp, E.KeyCode.DPadDown },
						selected,
						function()
							activation.trigger(button)
						end,
						{ priority = 300, capture = true }
					)
					ctx.action(grip, "ReleaseColumn", { E.KeyCode.Escape, E.KeyCode.ButtonB }, selected, function()
						local gui = ctx.config.guiService
						if gui then
							gui.SelectedObject = button
						end
					end, { priority = 300 })
				end
				return frame
			end,
		})
		local editor: reorder.Editor<V, K>? = nil
		local function reorderGutter(use: ComposeTypes.Use): number
			return if editor then use(editor.leading) else 0
		end
		local function trailingGutter(use: ComposeTypes.Use): number
			return if editor then use(editor.trailing) else 0
		end
		local window = Compose.cell(V2.zero)
		local scrolledX = Compose.cell(0)
		local function laneWidth(use: ComposeTypes.Use): number?
			local width = use(window).X
			return if width > 0
				then math.max(use(narrowest), width - reorderGutter(use) - trailingGutter(use) - use(disclosureWidth))
				else nil
		end
		local headerLayout = lists.list({}, false)
		local headerProps: Types.FrameProps = {
			Name = "Header",
			BackgroundTransparency = 1,
			Visible = spec.header ~= false,
			Size = function(use: ComposeTypes.Use)
				return D2.new(1, 0, 0, use(headerHeight))
			end,
			headerLayout :: ComposeTypes.Child,
			headerCells,
		}
		local header = Host.Frame(headerProps)
		local headerExtent = ctx.observe.AbsoluteContentSize(headerLayout)
		local selectable = spec.selectionMode ~= nil and spec.selectionMode ~= "none"
		if manageable or (spec.editing ~= nil and selectable) then
			editor = reorder(ctx, UI, spec, ordered, keyOf, queries, function()
				return body
			end, selection, sort, editing)
		end
		local bodySpec: CollectionTypes.KeyedCollectionSpec<V, K> = {
			Name = "Body",
			Position = function(use: ComposeTypes.Use)
				return D2.fromOffset(0, use(topHeight))
			end,
			Size = function(use: ComposeTypes.Use)
				return if spec.scrolls == false
					then D2.new(1, 0, 0, use(contentExtent))
					else D2.new(1, 0, 1, -use(topHeight))
			end,
			ScrollingEnabled = spec.scrolls ~= false,
			ClipsDescendants = spec.scrolls ~= false,
			mode = if spec.scrolls == false then "all" :: ComposeTypes.OrderedCollectionMode else spec.mode,
			ScrollingDirection = E.ScrollingDirection.XY,
			CanvasSize = function(use: ComposeTypes.Use)
				return D2.fromOffset(
					use(headerExtent).X + reorderGutter(use) + trailingGutter(use) + use(disclosureWidth),
					use(contentExtent)
				)
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
							local render: CollectionTypes.RowRender<V, K>? = definition.render
								or if definition.editor
									then editors.render(definition, function(item: V): unknown
										return field(item, definition)
									end, assert(spec.onCellChange), cellsLive)
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
									return if touchRows(use) then words(use) else valueText(use)
								end, true, touchRows)
							local wordFits = if longestWord then ctx.observe.TextFits(longestWord) else nil
							local content = if definition.render
								then ctx.styled(
									Host.Frame "Inset" {
										BackgroundTransparency = 1,
										render(current, placement, key) :: ComposeTypes.Child,
									},
									"TableCellInset"
								)
								elseif render then render(current, placement, key)
								else ctx.styled(
									ctx.text({
										Name = "Value",
										TextTruncate = E.TextTruncate.AtEnd,
										TextWrapped = function(use: ComposeTypes.Use): boolean
											return touchRows(use) and use(assert(wordFits)) ~= false
										end,
										Size = D2.fromScale(1, 1),
										AutomaticSize = E.AutomaticSize.None,
										Text = valueText,
									}),
									"TableValue"
								)
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
										rows[key] = cells
										truncatedRows:set(rows)
									end
								end)
							end
							local cell =
								ctx.styled(columnFrame(column, index, content, longestWord, undisclosed), "TableCell")
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
								icon = "more",
								name = "More actions",
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
				if editor then
					rowProps.BackgroundTransparency = 1
				end
				row = Host.Frame(rowProps)
				local disclosing = row
				local actions = if spec.rowActions then spec.rowActions(current, key) else nil
				if actions then
					local actionSpec: CollectionTypes.RowActionsSpec =
						table.clone(actions) :: CollectionTypes.RowActionsSpec
					local function gated(
						list: Types.Value<{ CollectionTypes.RowAction }>?
					): Types.Value<{ CollectionTypes.RowAction }>?
						if list == nil or spec.rowDeletable == nil then
							return list
						end
						return function(use: ComposeTypes.Use): { CollectionTypes.RowAction }
							local allowed = policy.allows(spec.rowDeletable, use(current))
							local kept = {}
							for _, action in read(list, use) do
								if allowed or action.role ~= "destructive" then
									table.insert(kept, action)
								end
							end
							return kept
						end
					end
					actionSpec.leading, actionSpec.trailing = gated(actionSpec.leading), gated(actionSpec.trailing)
					actionSpec.content, actionSpec.coordinator = row, coordinator
					actionSpec.Size = D2.fromScale(1, 1)
					actionSpec.reducedMotion = spec.reducedMotion
					row = UI.RowActions(actionSpec)
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
				ctx.skin(painted, "control", {
					selected = function(use: ComposeTypes.Use): boolean
						return read(selection, use)[key] == true
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
			end,
		}
		body = UI.VirtualList(bodySpec)
		local unit = Host.Frame({
			Name = "LayoutUnit",
			Size = D2.fromOffset(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
		})
		local position, rendered = ctx.observe.CanvasPosition(body), ctx.observe.AbsoluteWindowSize(body)
		local unitSize = ctx.observe.AbsoluteSize(unit)
		Compose.watch(function(use: ComposeTypes.Use)
			local scale = use(unitSize).X
			local size = use(rendered)
			window:set(if scale > 0 then size / scale else size)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(position)
			viewportWidth:set(use(window).X - reorderGutter(use) - trailingGutter(use))
			coordinator:set(nil)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			scrolledX:set(use(position).X)
		end)
		runtime.decorate(header, {
			Position = function(use: ComposeTypes.Use)
				return D2.fromOffset(reorderGutter(use) - use(scrolledX), use(toolbarHeight))
			end,
			Size = function(use: ComposeTypes.Use)
				local lane = laneWidth(use)
				return if lane
					then D2.fromOffset(lane, use(headerHeight))
					else D2.new(
						1,
						-reorderGutter(use) - trailingGutter(use) - use(disclosureWidth),
						0,
						use(headerHeight)
					)
			end,
		})
		return ctx.styled(
			Host.Frame(ctx.props(spec, behavior, {
				Size = function(use: ComposeTypes.Use)
					return if spec.scrolls == false
						then D2.new(1, 0, 0, use(contentExtent) + use(topHeight))
						else D2.fromScale(1, 1)
				end,
				BackgroundTransparency = 1,
				ClipsDescendants = spec.scrolls ~= false,
				unit :: ComposeTypes.Child,
				ctx.styled(
					Host.Frame({
						Name = "HeaderBand",
						Visible = spec.header ~= false,
						Position = function(use: ComposeTypes.Use)
							return D2.fromOffset(0, use(toolbarHeight))
						end,
						Size = function(use: ComposeTypes.Use)
							local width = use(window).X
							return if width > 0
								then D2.fromOffset(width, use(headerHeight))
								else D2.new(1, 0, 0, use(headerHeight))
						end,
					}),
					"TableHead"
				) :: ComposeTypes.Child,
				header,
				Compose.show(toolbarShown, function()
					local button = UI.Button("Edit")({
						label = function(use: ComposeTypes.Use): string
							return if read(editing, use) then "Done" else "Edit"
						end,
						AnchorPoint = V2.new(1, 0),
						Position = D2.fromScale(1, 0),
						Size = D2.new(0, 0, 1, 0),
						AutomaticSize = E.AutomaticSize.X,
						onActivate = function()
							local cell = (editing :: unknown) :: ComposeTypes.Cell<boolean>
							cell:set(not cell:peek())
						end,
					})
					local font, size = ctx.observeStyled.FontFace(button), ctx.observeStyled.TextSize(button)
					local function reserve(word: string): TextLabel
						return ctx.text({
							Name = word,
							Text = word,
							TextTransparency = 1,
							FontFace = font,
							TextSize = size,
						})
					end
					runtime.mount(function()
						return Host.Frame({
							Name = "WidthReserve",
							BackgroundTransparency = 1,
							AutomaticSize = E.AutomaticSize.XY,
							reserve("Edit") :: ComposeTypes.Child,
							reserve("Done"),
						})
					end, button)
					local words = {}
					if spec.deletable then
						table.insert(words, "X Delete")
					end
					if spec.reorderable then
						table.insert(words, "L1 / R1 Move")
					end
					return Host.Frame({
						Name = "Toolbar",
						BackgroundTransparency = 1,
						Size = function(use: ComposeTypes.Use)
							return D2.new(1, 0, 0, use(toolbarHeight) - ctx.metric("space.s", use))
						end,
						button :: ComposeTypes.Child,
						ctx.styled(
							ctx.text({
								Name = "PadHints",
								Text = table.concat(words, " · "),
								AnchorPoint = V2.new(0, 0.5),
								Position = D2.fromScale(0, 0.5),
								AutomaticSize = E.AutomaticSize.XY,
								Visible = function(use: ComposeTypes.Use)
									return read(editing, use) == true
										and preferredInput ~= nil
										and use(preferredInput) == E.PreferredInput.Gamepad
								end,
							}),
							"secondary"
						),
					})
				end),
				body,
				if editor then editor.overlay() else nil,
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
