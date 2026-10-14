--!strict
local createTree = require("./collection_tree")
local ListTypes = require("./collections")
local layoutKit = require("./layout_kit")
local reorder = require("./collection_reorder")
local createMetrics = require("./collection_table_metrics")
local createColumns = require("./collection_table_columns")
local createHeader = require("./collection_table_header")
local createRows = require("./collection_table_rows")
local createToolbar = require("./collection_table_toolbar")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local tableEditors = require("./collection_table_editors")
local CollectionProps = require("./collection_props")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local OverlayProps = require("./overlay_props")

type Controls = {
	Table: ControlTypes.TableConstructor,
	CellEditor: Types.Constructor<CollectionProps.CellEditorSpec, Frame>,
	VirtualList: <V, K>(spec: CollectionProps.KeyedCollectionSpec<V, K>) -> ScrollingFrame,
	RowActions: Types.Constructor<CollectionProps.RowActionsSpec, Frame>,
	Popover: Types.Constructor<OverlayProps.PopoverSpec, GuiObject>,
	Button: Types.Constructor<InputProps.ButtonProps, TextButton>,
	TextInput: Types.Constructor<InputProps.TextInputProps, TextBox | Frame>,
	NumberInput: Types.Constructor<InputProps.NumberInputProps, TextBox | Frame>,
	Toggle: Types.Constructor<InputProps.ToggleProps, TextButton>,
	Picker: ControlTypes.PickerConstructor,
}
return function(ctx: Types.Context, UI: Controls, buildList: ListTypes.BuildList): ()
	local lists = layoutKit.of(ctx)
	local editors = tableEditors(ctx, UI)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local behavior = {
		"children",
		"expanded",
		"onExpansionChange",
		"indent",
		"from",
		"selectionFrom",
		"selectionIndicator",
		"focusPolicy",
		"initialFocus",
		"autoFocus",
		"wrapFocus",
		"maxRetained",
		"onReachEnd",
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
		"collectionId",
		"drag",
		"drop",
		"rowDrop",
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
	local function create<V, K>(spec: CollectionTypes.TableShape<V, K>, keyOf: (V, number) -> K): Frame
		assert(spec.columns ~= nil, "Facet.Table requires columns")
		local manageable = spec.reorderable == true or spec.deletable == true
		local ownsToggle = manageable and spec.editing == nil and spec.header ~= false
		local editing: Types.ValueBoolean? = if ownsToggle then Compose.cell(false) else spec.editing
		local rowPolicySpec = table.clone(spec)
		rowPolicySpec.editing = editing
		Compose.watch(function(use: ComposeTypes.Use)
			editors.check(read(spec.columns, use), spec.onCellChange)
		end)
		local sort: ComposeTypes.Cell<CollectionTypes.Sort?> = spec.sort or Compose.cell(nil :: CollectionTypes.Sort?)
		local widths: ComposeTypes.Cell<{ [string]: number }> = spec.widths or Compose.cell({})
		local selection: ComposeTypes.Cell<CollectionTypes.Selection<K>> = spec.selection or Compose.cell({})
		local emptyStatus: ComposeTypes.OrderedCollectionStatus = {
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
		}
		local status = (
			spec.status or Compose.cell(emptyStatus)
		) :: ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus>
		if status:peek() == nil then
			status:set(emptyStatus)
		end
		local contentExtent = Compose.formula(function(use: ComposeTypes.Use): number
			local current = use(status)
			return if current then current.extent else 0
		end)
		local coordinator: ComposeTypes.Cell<{}?> = Compose.cell(nil :: {}?)
		local queries: ComposeTypes.OrderedCollectionControls<K> = spec.controls or {}
		local body: ScrollingFrame
		local unitScale = Compose.cell(1)
		local rowMeasures: ComposeTypes.Cell<{ [K]: number }> = Compose.cell({})
		local actionGutters: ComposeTypes.Cell<{ [K]: number }> = Compose.cell({})
		local headerMeasures: ComposeTypes.Cell<{ [string]: number }> = Compose.cell({})
		local truncatedRows: ComposeTypes.Cell<{ [K]: { [string]: boolean } }> = Compose.cell({})
		local metrics = createMetrics(ctx, spec, ownsToggle, unitScale, headerMeasures)
		local minimumRow, toolbarHeight, headerHeight = metrics.minimumRow, metrics.toolbarHeight, metrics.headerHeight
		local topHeight, textInsets = metrics.topHeight, metrics.textInsets
		local function field(item: V, column: CollectionTypes.TableColumn<V, K>): unknown
			if column.value then
				return column.value(item)
			end
			if type(item) == "table" then
				return (item :: { [string]: unknown })[column.id]
			end
			return nil
		end
		local function sortRows(rows: { V }, use: ComposeTypes.Use): { V }
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
		end
		local tree = if spec.children then createTree(ctx, UI, spec, keyOf, sortRows) else nil
		if tree then
			tree.columnar = true
		end
		local ordered = if tree
			then tree.from
			else Compose.formula(function(use: ComposeTypes.Use): { V }
				return sortRows(read(spec.from, use), use)
			end)
		Compose.watch(function(use: ComposeTypes.Use)
			local valid: { [K]: boolean } = {}
			for index, item in read(if tree then tree.all else spec.from, use) do
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
		local layout = createColumns(ctx, spec, widths, truncatedRows, metrics.touchRows)
		local viewportWidth, narrowest, disclosureWidth = layout.viewportWidth, layout.narrowest, layout.disclosureWidth
		local headerCells = createHeader(ctx, UI, spec, sort, widths, headerMeasures, metrics, layout)
		local editor: reorder.Editor<V, K>? = nil
		local function reorderGutter(use: ComposeTypes.Use): number
			return if editor then use(editor.leading) else 0
		end
		local function trailingGutter(use: ComposeTypes.Use): number
			local gutter = 0
			for _, width in use(actionGutters) do
				gutter = math.max(gutter, width)
			end
			return (if editor then use(editor.trailing) else 0) + gutter
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
		local selectable = (
			spec.selectionMode or (if spec.selection or spec.onSelectionChange then "single" else "none")
		) ~= "none"
		if spec.drag or spec.drop or manageable or (spec.editing ~= nil and selectable) then
			editor = reorder(ctx, UI, spec, ordered, keyOf, queries, function()
				return body
			end, selection, sort, editing, false, if tree then tree.location else nil, true)
		end
		local bodySpec: CollectionProps.KeyedCollectionSpec<V, K> = {
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
					use(headerExtent).X / use(unitScale)
						+ reorderGutter(use)
						+ trailingGutter(use)
						+ use(disclosureWidth),
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
			focusPolicy = spec.focusPolicy,
			initialFocus = spec.initialFocus,
			autoFocus = spec.autoFocus,
			wrapFocus = spec.wrapFocus,
			maxRetained = spec.maxRetained,
			onReachEnd = spec.onReachEnd,
			selectionFrom = spec.selectionFrom or (if tree then tree.all else nil),
			selectionIndicator = false,
			rowDrop = spec.rowDrop,
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
			onActivate = function(item, key, input, clicks)
				if editor and spec.onActivate == nil and read(editing) ~= true and editor.pickUp(key, input) then
					return
				end
				if spec.onActivate then
					spec.onActivate(item, key, input, clicks)
				elseif tree then
					tree.toggle(key)
				end
			end,
			editing = editing,

			render = createRows(ctx, UI, {
				spec = spec,
				rowPolicySpec = rowPolicySpec,
				selection = selection,
				coordinator = coordinator,
				rowMeasures = rowMeasures,
				actionGutters = actionGutters,
				truncatedRows = truncatedRows,
				unitScale = unitScale,
				scrolledX = scrolledX,
				editors = editors,
				field = field,
				tree = tree,
				editor = editor,
				laneWidth = laneWidth,
				metrics = metrics,
				layout = layout,
			}),
		}
		body = buildList(bodySpec, tree, true)
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
			unitScale:set(if scale > 0 then scale else 1)
			local size = use(rendered)
			window:set(if scale > 0 then size / scale else size)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(position)
			viewportWidth:set(use(window).X - reorderGutter(use) - trailingGutter(use))
			coordinator:set(nil)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			scrolledX:set(use(position).X / use(unitScale))
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
		local root = ctx.styled(
			Host.Frame(ctx.props(spec, behavior, {
				Size = function(use: ComposeTypes.Use)
					return if spec.scrolls == false
						then D2.new(1, 0, 0, use(contentExtent) + use(topHeight))
						else D2.fromScale(1, 1)
				end,
				BackgroundTransparency = 1,
				ClipsDescendants = spec.scrolls ~= false,
				unit :: ComposeTypes.Child,
				textInsets :: ComposeTypes.Child,
				ctx.styled(
					Host.Frame({
						Name = "HeaderBand",
						Visible = spec.header ~= false,
						Position = function(use: ComposeTypes.Use)
							return D2.fromOffset(0, use(toolbarHeight))
						end,
						Size = function(use: ComposeTypes.Use)
							return D2.new(1, 0, 0, use(headerHeight))
						end,
					}),
					"TableHead"
				) :: ComposeTypes.Child,
				header,
				createToolbar(ctx, UI, spec, editing, editor, metrics),
				body,
				if editor then editor.overlay() else nil,
			})),
			"Table"
		)
		local function seedWindow()
			if body.AbsoluteWindowSize.X > 0 and body.AbsoluteWindowSize.Y > 0 then
				return
			end
			local parent: Instance? = root.Parent
			local scale = 1
			local ancestor: Instance? = root
			while ancestor do
				local transform = ancestor:FindFirstChildWhichIsA("UIScale")
				if transform then
					scale *= transform.Scale
				end
				ancestor = ancestor.Parent
			end
			while parent do
				if parent:IsA("GuiObject") and parent.AbsoluteSize.X > 0 and parent.AbsoluteSize.Y > 0 then
					local bounds, authored = parent.AbsoluteSize / math.max(scale, 0.001), root.Size
					unitScale:set(scale)
					window:set(
						V2.new(
							bounds.X * authored.X.Scale + authored.X.Offset,
							math.max(0, bounds.Y * authored.Y.Scale + authored.Y.Offset - topHeight:peek())
						)
					)
					return
				end
				parent = parent.Parent
			end
		end
		runtime.connect(root, "AncestryChanged", seedWindow)
		seedWindow()
		return root
	end
	local function constructor<V, K>(spec: CollectionProps.TableSpec<V, K>): Frame
		if spec.key == nil then
			return create((spec :: unknown) :: CollectionTypes.TableShape<V, V>, function(item: V, _index: number): V
				return item
			end)
		end
		local key: unknown = spec.key
		if type(key) == "string" then
			assert(key ~= "", "Facet UI.Table: key field must not be empty")
			local fieldSpec = (spec :: unknown) :: CollectionTypes.TableShape<V, string>
			return create(fieldSpec, function(item: V, _index: number): string
				return tostring(((item :: unknown) :: { [string]: unknown })[key])
			end)
		end
		assert(type(key) == "function", "Facet UI.Table: key must be a function or a field name")
		return create((spec :: unknown) :: CollectionTypes.TableShape<V, K>, (key :: unknown) :: (V, number) -> K)
	end
	local tableConstructor: ControlTypes.TableConstructor = ctx.construct("Table", constructor)
	UI.Table = tableConstructor
end
