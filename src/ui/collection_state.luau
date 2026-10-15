--!strict
local TreeTypes = require("./collection_tree")
local activation = require("./activation")
local createSelection = require("./collection_selection")
local reducedMotion = require("./motion").reduced
local adaptive = require("./adaptive")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
export type PooledRow = { node: Frame, owner: ComposeTypes.Owner }
export type Preparing = {
	ready: ComposeTypes.Readable<boolean>,
	painted: ComposeTypes.Cell<boolean>,
	required: () -> boolean,
}
export type View<V, K> = {
	spec: CollectionTypes.CollectionShape<V, K>,
	kind: ComposeTypes.OrderedCollectionLayoutKind,
	keyOf: (V, number) -> K,
	tree: TreeTypes.Tree<V, K>?,
	actionsWrapped: boolean?,
	source: (ComposeTypes.Use) -> { V },
	viewport: ComposeTypes.Cell<ComposeTypes.OrderedCollectionViewport>,
	cross: ComposeTypes.Cell<number>,
	mountedVersion: ComposeTypes.Cell<number>,
	status: ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus>,
	controls: ComposeTypes.OrderedCollectionControls<K>,
	selection: ComposeTypes.Cell<CollectionTypes.Selection<K>>,
	onlySelected: ComposeTypes.Formula<K?>,
	coordinator: ComposeTypes.Cell<{}?>,
	selectionMode: "none" | "single" | "multiple",
	selectRow: (K, V, InputObject?) -> (),
	extendSelection: (K?, K) -> (),
	measured: ComposeTypes.Cell<{ [K]: number }>,
	containsCards: ComposeTypes.Cell<boolean>,
	horizontal: boolean,
	cardsMode: boolean,
	preferred: ComposeTypes.Readable<Enum.PreferredInput>?,
	frames: ComposeTypes.Frames,
	reduced: () -> boolean,
	unit: Frame,
	unitSize: ComposeTypes.Cell<Vector2>,
	focusActive: ComposeTypes.Cell<boolean>,
	noFocusCandidates: { V },
	initialFollow: boolean,
	focusedPath: { string },
	focusOwned: boolean,
	scope: ComposeTypes.FocusScope<K>?,
	mounted: { [K]: Frame? },
	cellEdits: { [K]: { activation.EditAction } },
	placed: { [K]: ComposeTypes.Readable<ComposeTypes.Placement> },
	poolOwner: ComposeTypes.Owner,
	preparing: { [Frame]: Preparing },
	retiring: { [Frame]: () -> () },
	waiting: ComposeTypes.Cell<number>,
	pool: ComposeTypes.Pool<PooledRow>,
	mainEdge: (ComposeTypes.Use?) -> number,
	crossEdge: (ComposeTypes.Use?) -> number,
	cardLayout: (ComposeTypes.Use?) -> (number, number),
	fullSizes: (ComposeTypes.Use) -> { [K]: number },
}
local function belongsTo(node: Instance?, ancestor: Instance): boolean
	return node ~= nil and (node == ancestor or node:IsDescendantOf(ancestor))
end
local function findSelectable(node: Instance, names: { string }?, depth: number): GuiObject?
	if node:IsA("GuiObject") and (not node.Visible or not node.Interactable) then
		return nil
	end
	if names and names[depth] then
		for _, child in node:GetChildren() do
			if child.Name == names[depth] then
				local found = findSelectable(child, names, depth + 1)
				if found then
					return found
				end
			end
		end
	end
	if node:IsA("GuiObject") and node.Selectable and node.Visible and node.Interactable then
		return node
	end
	for _, child in node:GetChildren() do
		local found = findSelectable(child, nil, 1)
		if found then
			return found
		end
	end
	return nil
end
local function create<V, K>(
	ctx: Types.Context,
	spec: CollectionTypes.CollectionShape<V, K>,
	kind: ComposeTypes.OrderedCollectionLayoutKind,
	keyOf: (V, number) -> K,
	tree: TreeTypes.Tree<V, K>?,
	actionsWrapped: boolean?,
	source: (ComposeTypes.Use) -> { V }
): View<V, K>
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local readSource = ctx.readSource
	local observe = ctx.observe
	local D2, E = ctx.types.UDim2, ctx.types.Enum
	local viewport: ComposeTypes.Cell<ComposeTypes.OrderedCollectionViewport> = Compose.cell({ offset = 0, size = 0 })
	local cross, mountedVersion = Compose.cell(0), Compose.cell(0)
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
	local status = (spec.status or Compose.cell(emptyStatus)) :: ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus>
	if status:peek() == nil then
		status:set(emptyStatus)
	end
	local controls: ComposeTypes.OrderedCollectionControls<K> = spec.controls or {}
	local selection: ComposeTypes.Cell<CollectionTypes.Selection<K>> = spec.selection or Compose.cell({})
	local onlySelected = Compose.formula(function(use: ComposeTypes.Use): K?
		local only: K? = nil
		local chosen: CollectionTypes.Selection<K> = use(selection)
		for key, selected in chosen do
			if selected then
				if only ~= nil then
					return nil
				end
				only = key
			end
		end
		return only
	end)
	local coordinator = Compose.cell(nil :: {}?)
	local selectionMode: "none" | "single" | "multiple" = spec.selectionMode
		or (if spec.selection or spec.onSelectionChange then "single" else "none")
	local selectRow, extendSelection = createSelection(ctx, spec, source, keyOf, controls, selection, selectionMode)
	local measured: ComposeTypes.Cell<{ [K]: number }> = Compose.cell({})
	local containsCards = Compose.cell(false)
	local horizontal = spec.direction == "horizontal"
	local cardsMode = spec.itemSize == "cards"
	assert(not cardsMode or horizontal, 'Facet collection: itemSize = "cards" needs a horizontal list')
	assert(spec.cards == nil or cardsMode, 'Facet collection: cards needs itemSize = "cards"')
	local preferred: ComposeTypes.Readable<Enum.PreferredInput>? = if ctx.config.userInputService
		then observe.PreferredInput(ctx.config.userInputService)
		else nil
	local frames = assert(runtime.host.frames)
	local motionReduced = reducedMotion(ctx)
	local function reduced(): boolean
		return if spec.reducedMotion == nil then motionReduced() else read(spec.reducedMotion) == true
	end
	local unit = Host.Frame({
		Name = "LayoutUnit",
		Size = D2.fromOffset(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local unitSize: ComposeTypes.Cell<Vector2> = observe.AbsoluteSize(unit)
	local focusActive = Compose.cell(spec.focus ~= nil or spec.initialFocus ~= nil or spec.autoFocus == true)
	local noFocusCandidates: { V } = {}
	local initialFollow = read(spec.follow) == "end" and spec.CanvasPosition == nil
	local mounted: { [K]: Frame? } = {}
	local cellEdits: { [K]: { activation.EditAction } } = {}
	local placed: { [K]: ComposeTypes.Readable<ComposeTypes.Placement> } = {}
	local poolOwner = assert(Compose.currentOwner()).createChild()
	local preparing: {
		[Frame]: {
			ready: ComposeTypes.Readable<boolean>,
			painted: ComposeTypes.Cell<boolean>,
			required: () -> boolean,
		},
	} =
		{}
	local retiring: { [Frame]: () -> () } = {}
	local waiting = Compose.cell(0)
	Compose.watch(function(use: ComposeTypes.Use)
		use(waiting)
		use(viewport)
		for _, entry in preparing do
			if entry.required() and not use(entry.ready) then
				return
			end
		end
		for node, entry in preparing do
			if use(entry.ready) then
				entry.painted:set(true)
				preparing[node] = nil
			end
		end
		waiting:set(0)
		for node, release in retiring do
			retiring[node] = nil
			release()
		end
	end)
	local pool: ComposeTypes.Pool<PooledRow> = Compose.createPool({
		maxRetained = spec.maxRetained or 32,
		create = function()
			local owner = poolOwner.createChild()
			local node = Compose.withOwner(owner, function()
				local nativeProps: Types.FrameProps = {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ClipsDescendants = false,
				}
				return Host.Frame(nativeProps)
			end)
			return { node = node, owner = owner }
		end,
		reset = function(record: PooledRow)
			if record.node.Parent ~= nil then
				record.node.Parent = nil
			end
		end,
		destroy = function(record: PooledRow)
			record.owner.dispose()
		end,
	})
	local function edgeOf(gutter: Types.Value<number>?, use: ComposeTypes.Use?): number
		return if kind == "grid" then math.ceil(math.max(0, read(gutter or 0, use)) / 2) else 0
	end
	local function mainEdge(use: ComposeTypes.Use?): number
		local edge = edgeOf(spec.gap, use)
		if kind ~= "grid" or not readSource(containsCards, use) then
			return edge
		end
		local extent = read(spec.itemSize or 40, use) :: number
		for _, size in readSource(measured, use) do
			extent = math.max(extent, size)
		end
		for _, size in read(spec.measured or {}, use) do
			extent = math.max(extent, size)
		end
		return math.max(edge, math.ceil(extent * math.max(0, ctx.metric("motion.materialize.lift", use) - 1)))
	end
	local function crossEdge(use: ComposeTypes.Use?): number
		local edge = edgeOf(spec.crossGap or spec.gap, use)
		if kind ~= "grid" or not readSource(containsCards, use) then
			return edge
		end
		local available = readSource(cross, use)
		local columns = if spec.minColumnWidth ~= nil
			then adaptive.columnsFor(
				available,
				read(spec.minColumnWidth, use),
				read(spec.crossGap or spec.gap or 0, use)
			)
			else math.max(1, math.floor(read(spec.columns or 1, use)))
		return math.max(
			edge,
			math.ceil(available / columns * math.max(0, ctx.metric("motion.materialize.lift", use) - 1))
		)
	end
	local function cardLayout(use: ComposeTypes.Use?): (number, number)
		local options: { perView: number?, minWidth: number?, peek: number? } = spec.cards or {}
		local available = if use then use(viewport).size else viewport:peek().size
		local gap: number = read(spec.gap or 0, use)
		local touch = preferred ~= nil and readSource(preferred, use) == E.PreferredInput.Touch
		local perView = options.perView
			or if touch and available < adaptive.BREAKPOINTS.regular
				then 1
				else adaptive.columnsFor(available, options.minWidth or 200, gap)
		local peek = options.peek
			or if perView == 1 and options.perView == nil then math.clamp(available * 0.1, 24, 56) else 0
		local extent = (available - peek - gap * (perView - 1) - (if peek > 0 then gap else 0)) / perView
		return math.max(1, math.floor(extent)), perView
	end
	local function fullSizes(use: ComposeTypes.Use): { [K]: number }
		local combined = table.clone(use(measured))
		for key, size in read(spec.measured or {}, use) do
			combined[key] = size
		end
		return combined
	end
	return {
		spec = spec,
		kind = kind,
		keyOf = keyOf,
		tree = tree,
		actionsWrapped = actionsWrapped,
		source = source,
		viewport = viewport,
		cross = cross,
		mountedVersion = mountedVersion,
		status = status,
		controls = controls,
		selection = selection,
		onlySelected = onlySelected,
		coordinator = coordinator,
		selectionMode = selectionMode,
		selectRow = selectRow,
		extendSelection = extendSelection,
		measured = measured,
		containsCards = containsCards,
		horizontal = horizontal,
		cardsMode = cardsMode,
		preferred = preferred,
		frames = frames,
		reduced = reduced,
		unit = unit,
		unitSize = unitSize,
		focusActive = focusActive,
		noFocusCandidates = noFocusCandidates,
		initialFollow = initialFollow,
		focusedPath = {},
		focusOwned = false,
		scope = nil,
		mounted = mounted,
		cellEdits = cellEdits,
		placed = placed,
		poolOwner = poolOwner,
		preparing = preparing,
		retiring = retiring,
		waiting = waiting,
		pool = pool,
		mainEdge = mainEdge,
		crossEdge = crossEdge,
		cardLayout = cardLayout,
		fullSizes = fullSizes,
	}
end
return { create = create, belongsTo = belongsTo, findSelectable = findSelectable }
