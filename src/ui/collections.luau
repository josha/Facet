--!strict
local createTree = require("./collection_tree")
local TreeTypes = require("./collection_tree")
local activation = require("./activation")
local scrollLock = require("./scroll_lock")
local initialScroll = require("./scroll_initial")
local preparePaint = require("./collection_paint")
local reorder = require("./collection_reorder")
local policy = require("./collection_policy")
local createSelection = require("./collection_selection")
local attachSnap = require("./collection_snap")
local reducedMotion = require("./motion").reduced
local adaptive = require("./adaptive")
local travelEngine = require("./travel_engine")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
type Controls = {
	VirtualList: CollectionTypes.CollectionConstructor,
	Outline: CollectionTypes.OutlineConstructor,
	VirtualGrid: CollectionTypes.CollectionConstructor,
	RowActions: Types.Constructor<CollectionTypes.RowActionsSpec, Frame>,
	Button: Types.Constructor<InputTypes.ButtonProps, TextButton>,
}
local FLING_MINIMUM = 200
local FLING_STOP = 20
local FLING_WINDOW = 0.1
type PooledRow = { node: Frame, owner: ComposeTypes.Owner }

export type BuildList = <V, K>(
	CollectionTypes.KeyedCollectionSpec<V, K>,
	TreeTypes.Tree<V, K>?,
	boolean?
) -> ScrollingFrame

return function(ctx: Types.Context, UI: Controls): BuildList
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local readSource = ctx.readSource
	local props, observe = ctx.props, ctx.observe
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local gui = ctx.config.guiService
	local behavior = {
		"children",
		"expanded",
		"onExpansionChange",
		"indent",
		"from",
		"slots",
		"slotControls",
		"selectionFrom",
		"selectionIndicator",
		"minColumnWidth",
		"rowActions",
		"key",
		"render",
		"contentOverflow",
		"mode",
		"snap",
		"reducedMotion",
		"direction",
		"itemSize",
		"cards",
		"gap",
		"crossGap",
		"columns",
		"overscan",
		"measured",
		"measure",
		"status",
		"controls",
		"follow",
		"followThreshold",
		"maxRetained",
		"focus",
		"initialFocus",
		"focusPolicy",
		"autoFocus",
		"wrapFocus",
		"disabled",
		"selection",
		"selectionMode",
		"selectable",
		"reorderable",
		"collectionId",
		"drag",
		"drop",
		"rowDrop",
		"onReorder",
		"movable",
		"deletable",
		"rowDeletable",
		"onDelete",
		"editing",
		"dragLabel",
		"autoscroll",
		"onSelectionChange",
		"onActivate",
		"onReachEnd",
	}
	local function belongsTo(node: Instance?, ancestor: Instance): boolean
		while node do
			if node == ancestor then
				return true
			end
			node = node.Parent
		end
		return false
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
	local function collection<V, K>(
		spec: CollectionTypes.CollectionOptions<V, K>,
		kind: ComposeTypes.OrderedCollectionLayoutKind,
		keyOf: (V, number) -> K,
		tree: TreeTypes.Tree<V, K>?,
		actionsWrapped: boolean?
	): ScrollingFrame
		assert(
			spec.contentOverflow == nil or table.find({ "visible", "clip" }, read(spec.contentOverflow)),
			"Facet collection contentOverflow must be visible or clip"
		)
		assert(
			spec.snap == nil or spec.snap == "none" or spec.snap == "item",
			"Facet collection snap must be none or item"
		)
		assert(type(spec.render) == "function", "Facet collection requires render(current, placement, key)")
		tree = tree or (if spec.children then createTree(ctx, UI, spec, keyOf) else nil)
		if tree then
			assert(kind == "list" and spec.direction ~= "horizontal", "Facet hierarchy needs a vertical list")
			spec = table.clone(spec)
			spec.selectionFrom = spec.selectionFrom or tree.all
			spec.focus = spec.focus or {}
			local hierarchy = tree
			spec.onActivate = spec.onActivate or function(_item, key)
				hierarchy.toggle(key)
			end
		end
		local source = function(use: ComposeTypes.Use): { V }
			return read(if tree then tree.from else spec.from, use)
		end

		local viewport: ComposeTypes.Cell<ComposeTypes.OrderedCollectionViewport> =
			Compose.cell({ offset = 0, size = 0 })
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
		local status = (
			spec.status or Compose.cell(emptyStatus)
		) :: ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus>
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
		local root: ScrollingFrame
		local scope: ComposeTypes.FocusScope<K>? = nil
		local restoring = false
		local focusActive = Compose.cell(spec.focus ~= nil or spec.initialFocus ~= nil or spec.autoFocus == true)
		local noFocusCandidates: { V } = {}
		local writingOffset = false
		local initialFollow = read(spec.follow) == "end" and spec.CanvasPosition == nil
		local focusedPath: { string } = {}
		local focusOwned = false
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
		local function setOffset(requested: number): ()
			local edge = mainEdge()
			local offset = requested
			if edge > 0 then
				local current, box = status:peek(), viewport:peek()
				local last = if current and current.extent then current.extent - box.size else math.huge
				offset = if requested <= 0 then 0 elseif requested >= last then math.max(0, last) else requested + edge
			end
			local position = root.CanvasPosition
			local nextPosition = if horizontal then V2.new(offset, position.Y) else V2.new(position.X, offset)
			if position ~= nextPosition then
				writingOffset = true
				root.CanvasPosition = nextPosition
				writingOffset = false
			end
		end
		local editor: reorder.Editor<V, K>?
		local function select(key: K, current: ComposeTypes.Readable<V>, input: InputObject?, clicks: number?): ()
			if policy.disabled(spec.disabled, current:peek()) or activation.consumed(input) then
				return
			end
			if editor and spec.onActivate == nil and read(spec.editing) ~= true and editor.pickUp(key, input) then
				return
			end
			local pointer = input ~= nil and input.UserInputType == E.UserInputType.MouseButton1
			local double = pointer and (clicks or 0) >= 2
			if not double then
				selectRow(key, current:peek(), input)
			end
			local choosing = selectionMode ~= "none" and read(spec.editing) == true
			if spec.onActivate and not choosing and (selectionMode == "none" or not pointer or double) then
				spec.onActivate(current:peek(), key, input, clicks)
			end
		end
		local function captureSelection(node: Instance, key: K): ()
			if scope == nil then
				return
			end
			focusActive:set(true)
			focusOwned = true
			local path: { string } = {}
			local current: Instance? = node
			while current and current ~= mounted[key] do
				table.insert(path, 1, current.Name)
				current = current.Parent
			end
			focusedPath = path
			scope.focus(key)
		end
		local function wireSelection(node: Instance, key: K): ()
			if node:IsA("GuiObject") and (node.Selectable or node:IsA("GuiButton") or node:IsA("TextBox")) then
				runtime.connect(node, "SelectionGained", function()
					captureSelection(node, key)
				end)
			end
			for _, child in node:GetChildren() do
				wireSelection(child, key)
			end
		end
		editor = if spec.drag
				or spec.drop
				or spec.reorderable
				or spec.deletable
				or (spec.editing ~= nil and selectionMode ~= "none" and spec.selectionIndicator ~= false)
			then reorder(
				ctx,
				UI,
				spec,
				source,
				keyOf,
				controls,
				function()
					return root
				end,
				selection,
				Compose.cell(nil :: CollectionTypes.Sort?),
				spec.editing,
				kind == "grid",
				if tree then tree.location else nil,
				nil,
				spec.slots
			)
			else nil
		local overlayReorder = if editor then editor.overlay else nil
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
		local slotNodes: { [K]: GuiObject } = {}
		if spec.slotControls then
			assert(spec.slots ~= nil, "Facet collection slotControls requires slots")
			spec.slotControls.nodeOfKey = function(key: K): GuiObject?
				return slotNodes[key]
			end
			Compose.cleanup(function()
				(spec.slotControls :: CollectionTypes.SlotControls<K>).nodeOfKey = nil
			end)
		end
		type SlotRecord = { key: K, item: V? }
		local slotSource = Compose.formula(function(use: ComposeTypes.Use): { SlotRecord }
			local items, result, included = {} :: { [K]: V }, {} :: { SlotRecord }, {} :: { [K]: boolean }
			local rows = source(use)
			for index, item in rows do
				items[keyOf(item, index)] = item
			end
			for _, key in read(spec.slots or {}, use) do
				assert(not included[key], "Facet collection slots must have unique keys")
				included[key] = true
				table.insert(result, { key = key, item = items[key] })
			end
			for index, item in rows do
				local key = keyOf(item, index)
				if not included[key] then
					table.insert(result, { key = key, item = item })
				end
			end
			return result
		end, function(before: { SlotRecord }?, after: { SlotRecord }): boolean
			if before == nil or spec.slots == nil or #before ~= #after then
				return false
			end
			for index, entry in before do
				if entry.key ~= after[index].key then
					return false
				end
			end
			return true
		end)
		local function withSlots(renderItem: CollectionTypes.RowRender<V, K>)
			return function(
				record: ComposeTypes.Readable<SlotRecord>,
				placement: ComposeTypes.Readable<ComposeTypes.Placement>,
				key: K
			)
				if spec.slots == nil then
					return renderItem(
						Compose.formula(function(use: ComposeTypes.Use): V
							return assert(use(record).item)
						end),
						placement,
						key
					)
				end
				local function itemForKey(use: ComposeTypes.Use): V?
					for index, item in source(use) do
						if keyOf(item, index) == key then
							return item
						end
					end
					return nil
				end
				local last = record:peek().item
				local current = Compose.formula(function(use: ComposeTypes.Use): V
					local item = itemForKey(use)
					if item ~= nil then
						last = item
					end
					return assert(last)
				end)
				local recess: GuiObject = ctx.styled(
					Host.Frame {
						Name = "ReservedSlot",
						Visible = function(use: ComposeTypes.Use): boolean
							return itemForKey(use) == nil
						end,
						Interactable = false,
						Selectable = false,
						Attributes = { FacetReservedKey = tostring(key) } :: EngineTypes.Attributes,
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
					},
					"fill"
				)
				slotNodes[key] = recess
				Compose.cleanup(function()
					if slotNodes[key] == recess then
						slotNodes[key] = nil
					end
				end)
				local shellProps: Types.FrameProps = {
					Name = "Slot",
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					Compose.show(function(use: ComposeTypes.Use): boolean
						return itemForKey(use) ~= nil
					end, function()
						return renderItem(current, placement, key)
					end),
					recess,
				}
				return Host.Frame(shellProps)
			end
		end

		local function orderedRows(follow: CollectionTypes.Follow?): ComposeTypes.Child
			return Compose.OrderedCollection({
				from = slotSource,
				key = function(record: SlotRecord, _index: number): K
					return record.key
				end,
				mode = spec.mode or "windowed",
				direction = spec.direction or "vertical",
				viewport = viewport,
				status = status,
				controls = controls,
				overscan = spec.overscan or 2,
				measured = Compose.formula(function(use: ComposeTypes.Use)
					local sizes = fullSizes(use)
					return if tree
						then tree.sizes(use, sizes, read(spec.itemSize or 40, use) :: number, read(spec.gap or 0, use))
						else sizes
				end),
				follow = follow,
				followThreshold = spec.followThreshold,
				layout = function(use: ComposeTypes.Use)
					local columns = if kind == "grid" then math.max(1, math.floor(read(spec.columns or 1, use))) else 1
					if spec.minColumnWidth ~= nil then
						local minimum = read(spec.minColumnWidth, use)
						assert(
							kind == "grid" and spec.columns == nil and minimum > 0 and minimum < math.huge,
							"Facet minColumnWidth needs a grid, a positive width and no columns"
						)
						columns = adaptive.columnsFor(
							math.max(0, use(cross) - 2 * crossEdge(use)),
							minimum,
							read(spec.crossGap or spec.gap or 0, use)
						)
					end
					local gap: number = read(spec.gap or 0, use)
					local crossGap: number = read(spec.crossGap or gap, use)
					return {
						kind = kind,
						columns = columns,
						itemSize = if cardsMode then (cardLayout(use)) else read(spec.itemSize or 40, use) :: number,
						gap = if tree then 0 else gap,
						crossGap = crossGap,
						crossSize = math.max(0, (use(cross) - 2 * crossEdge(use) - crossGap * (columns - 1)) / columns),
					}
				end,
				render = withSlots(function(current, placement, key)
					local lease = pool.acquire()
					local node = runtime.borrow(lease.value.node) :: Frame
					local contentOwner = poolOwner.createChild()
					local glide = Compose.cell(0)
					local stopGlide: (() -> ())? = nil
					local function halt()
						if stopGlide then
							stopGlide()
							stopGlide = nil
						end
					end
					Compose.cleanup(halt)
					local function shift(use: ComposeTypes.Use?): number
						return if use then use(glide) else glide:peek()
					end
					local paintPlacement = Compose.formula(function(use: ComposeTypes.Use): ComposeTypes.Placement
						local at = use(placement)
						return if editor and (spec.drag or spec.drop) then editor.placement(key, at, use) else at
					end)
					local reservedPosition = Compose.cell(V2.new(placement:peek().crossOffset, placement:peek().offset))
					local springPlacement = spec.slots ~= nil or spec.drag ~= nil or spec.drop ~= nil
					if springPlacement then
						local engine = travelEngine(ctx, {
							initial = { placement:peek().crossOffset, placement:peek().offset },
							target = function()
								local at = paintPlacement:peek()
								return { at.crossOffset, at.offset }
							end,
							sample = function(values)
								reservedPosition:set(V2.new(values[1], values[2]))
							end,
							reduced = reduced,
							motion = "spring",
							duration = ctx.metric("motion.durations.travel"),
							ease = ctx.motionEase("travel"),
							spring = ctx.motionSpring("travel"),
						})
						Compose.watch(function(use: ComposeTypes.Use)
							use(paintPlacement)
							engine.retarget()
						end)
					end
					local previous = placement:peek()
					Compose.watch(function(use: ComposeTypes.Use)
						local at = use(placement)
						local delta = previous.offset + glide:peek() - at.offset
						local moved = at.index ~= previous.index
						previous = at
						if
							springPlacement
							or tree
							or not moved
							or kind ~= "list"
							or math.abs(delta) > viewport:peek().size
							or reduced()
						then
							return
						end
						halt()
						local elapsed = 0
						local seconds = ctx.metric("motion.durations.glide")
						local present = ctx.motionEase("present")
						glide:set(delta)
						stopGlide = frames.onFrame(function(step: number)
							elapsed = math.min(seconds, elapsed + step)
							glide:set(delta * (1 - present(elapsed / seconds)))
							if elapsed >= seconds then
								halt()
							end
						end)
					end)
					Compose.withOwner(contentOwner, function()
						runtime.decorate(node, {
							Name = tostring(key),
							ClipsDescendants = tree ~= nil,
							Interactable = function(use: ComposeTypes.Use)
								return (tree == nil or tree.visible(key, use))
									and not policy.disabled(spec.disabled, use(current))
							end,
							LayoutOrder = function(use: ComposeTypes.Use)
								return use(placement).index
							end,
							Position = function(use: ComposeTypes.Use)
								local at = use(placement)
								if springPlacement then
									local position = use(reservedPosition)
									return if horizontal
										then D2.fromOffset(position.Y, position.X)
										else D2.fromOffset(position.X, position.Y)
								end
								local offset = at.offset + shift(use)
								return if horizontal
									then D2.fromOffset(offset, at.crossOffset)
									else D2.fromOffset(at.crossOffset, offset)
							end,
							Size = function(use: ComposeTypes.Use)
								local at = use(placement)
								return if horizontal
									then D2.fromOffset(at.size, at.crossSize)
									else D2.fromOffset(at.crossSize, at.size)
							end,
						})
					end)
					mounted[key] = node
					placed[key] = placement
					local measuredNode: GuiObject
					local actionHeight: ComposeTypes.Readable<number>? = nil
					local painted = Compose.cell(false)
					local stop, mountedContent = Compose.withOwner(contentOwner, function()
						return runtime.mount(function(): CanvasGroup
							local rendered = spec.render(current, placement, key)
							if tree and not tree.columnar then
								rendered = tree.wrap(rendered, current, key)
							end
							measuredNode = rendered
							if kind == "grid" and rendered:GetAttribute("FacetBody") ~= nil then
								containsCards:set(true)
							end
							cellEdits[key] = {}
							for _, edit in activation.edits(rendered) do
								local gated = table.clone(edit)
								gated.enabled = function(use: ComposeTypes.Use?): boolean
									return edit.enabled(use)
										and not policy.disabled(spec.disabled, readSource(current, use))
								end
								table.insert(cellEdits[key], gated)
							end
							if not actionsWrapped then
								rendered, actionHeight = policy.actions(
									ctx,
									spec,
									current,
									key,
									rendered,
									UI.RowActions,
									coordinator,
									kind == "grid"
								)
							end
							if editor then
								rendered = editor.wrap(rendered, current, key)
								local press = editor.press
								Compose.cleanup(activation.providePress(rendered, function(value: InputObject)
									press(key, value)
								end))
							end
							local children: Types.FrameProps = {
								Name = "Content",
								Size = if tree
									then function(use: ComposeTypes.Use): UDim2
										return D2.new(
											1,
											0,
											0,
											math.max(read(spec.itemSize or 40, use) :: number, fullSizes(use)[key] or 0)
										)
									end
									else D2.fromScale(1, 1),
								BackgroundTransparency = 1,
								Attributes = { FacetCollectionRow = true } :: EngineTypes.Attributes,
								ClipsDescendants = function(use)
									return read(spec.contentOverflow, use) == "clip"
								end,
								rendered,
							}
							if
								spec.onSelectionChange
								or spec.onActivate
								or spec.selection
								or spec.selectionMode
								or spec.rowDrop
								or #cellEdits[key] > 0
								or editor
							then
								local hit: TextButton
								hit = Host.TextButton "RowHit" {
									AnchorPoint = V2.new(0.5, 0.5),
									Position = D2.fromScale(0.5, 0.5),
									Size = D2.fromScale(1, 1),
									Text = "",
									BackgroundTransparency = 1,
									Selectable = true,
									Interactable = function(use: ComposeTypes.Use)
										return (tree == nil or tree.visible(key, use))
											and not policy.disabled(spec.disabled, use(current))
									end,
									Activated = function(input: InputObject?, clicks: number?)
										if not activation.intercepted(hit, input) then
											select(key, current, input, clicks)
										end
									end,
									Attributes = {
										FacetSelectionRequired = selectionMode ~= "none",
										FacetOnlySelected = function(use: ComposeTypes.Use)
											return use(onlySelected) == key
										end,
										FacetSelected = function(use: ComposeTypes.Use)
											return read(selection, use)[key] == true
										end,
									} :: EngineTypes.Attributes,
								}
								Compose.cleanup(activation.provide(hit, function(input: unknown, clicks: unknown)
									if not activation.intercepted(hit, input) then
										select(key, current, input :: InputObject?, clicks :: number?)
									end
								end))
								local function pressed(value: InputObject)
									activation.press(rendered, value)
								end
								runtime.connect(hit, "InputBegan", pressed)
								if editor and ctx.config.inputParent and ctx.config.inputParent:IsA("PluginGui") then
									runtime.connect(hit, "MouseButton1Down", function(x: number, y: number)
										editor.mouseDown(V2.new(x, y))
									end)
									runtime.connect(hit, "InputEnded", editor.finish)
								end
								Compose.cleanup(activation.providePress(hit, pressed))
								table.insert((children :: unknown) :: { unknown }, 1, hit)
							end
							local paintSelection = spec.selectionIndicator ~= false and selectionMode ~= "none"
							if paintSelection then
								children.BackgroundTransparency = nil
							end
							local groupProperties = (children :: unknown) :: Types.CanvasGroupNativeProps
							groupProperties.GroupTransparency = function(use: ComposeTypes.Use): number
								return if use(painted) then 0 else 1
							end
							groupProperties.AutomaticSize = if read(spec.contentOverflow) == "clip"
								then E.AutomaticSize.None
								else E.AutomaticSize.XY
							local content = Host.CanvasGroup(groupProperties)
							policy.drop(ctx, spec, current, key, content, kind == "grid" or horizontal)
							if paintSelection then
								ctx.styled(content, "TableRow")
								if kind == "grid" or horizontal then
									ctx.skin(content, "control", {
										selected = function(use: ComposeTypes.Use): boolean
											return use(selection)[key] == true
										end,
									})
								end
								Compose.watch(function(use: ComposeTypes.Use)
									if use(selection)[key] == true then
										content:AddTag("facet-selected")
									else
										content:RemoveTag("facet-selected")
									end
								end)
							end
							return content
						end, node)
					end)
					local content = mountedContent :: CanvasGroup
					local ready = Compose.withOwner(contentOwner, function()
						return preparePaint(ctx, content)
					end)
					preparing[node] = {
						ready = ready,
						painted = painted,
						required = function(): boolean
							local at, window = placement:peek(), viewport:peek()
							return spec.mode == "all"
								or window.size <= 0
								or (at.offset + at.size > window.offset and at.offset < window.offset + window.size)
						end,
					}
					waiting:update(function(value)
						return value + 1
					end)
					local parked: Instance? = nil
					local previousParent: Instance? = node.Parent
					local released = false
					local restoringParent = false
					local destroyed = node.Destroying:Connect(function()
						parked = nil
					end)
					local restore = node.AncestryChanged:Connect(function()
						if node.Parent and parked == nil then
							previousParent = node.Parent
						end
						if parked and not restoringParent and not poolOwner.isDisposed() and node.Parent == nil then
							restoringParent = true
							local ok = pcall(function()
								node.Parent = parked
							end)
							restoringParent = false
							if not ok then
								parked = nil
							end
						end
					end)
					local function release()
						if released then
							return
						end
						released = true
						parked = nil
						restore:Disconnect()
						destroyed:Disconnect()
						stop()
						contentOwner.dispose()
						lease.release()
					end
					wireSelection(content, key)
					if spec.measure or (tree and not tree.columnar) then
						local size: ComposeTypes.Cell<Vector2> = observe.AbsoluteSize(measuredNode)
						local lift = measuredNode:FindFirstChildWhichIsA("UIScale")
						local layoutUnit = if measuredNode:GetAttribute("FacetBody")
							then measuredNode:FindFirstChild("LayoutUnit")
							else nil
						local measurementUnit: Frame? = if lift
							then if layoutUnit and layoutUnit:IsA("Frame")
								then layoutUnit
								else Host.Frame({
									Name = "MeasurementUnit",
									Size = D2.fromOffset(1, 1),
									Visible = false,
								})
							else nil
						if measurementUnit then
							measurementUnit.Parent = measuredNode
						end
						local paintedSize = if measurementUnit then observe.AbsoluteSize(measurementUnit) else nil
						local factor: ComposeTypes.Readable<number> = if lift
							then observe.Scale(lift)
							else Compose.cell(1)
						Compose.watch(function(use: ComposeTypes.Use)
							local ancestors = use(unitSize).X
							if ancestors <= 0 then
								ancestors = 1
							end
							local liftScale = use(factor)
							local painted = if paintedSize then use(paintedSize).X else 0
							local scale = math.max(if painted > 0 then painted else liftScale * ancestors, 0.001)
							local dimensions = use(size)
							local extent = (if horizontal then dimensions.X else dimensions.Y) / scale
								+ (if editor and not horizontal then use(editor.header) else 0)
								+ (if actionHeight and not horizontal then use(actionHeight) else 0)
							extent = math.round(extent)
							local previous = measured:peek()[key]
							if previous and liftScale ~= 1 and math.abs(extent - previous) <= 1 then
								return
							end
							if extent > 0 and previous ~= extent then
								local nextSizes = table.clone(measured:peek())
								nextSizes[key] = extent
								measured:set(nextSizes)
							end
						end)
					end
					Compose.cleanup(function()
						if gui and belongsTo(gui.SelectedObject, node) then
							focusOwned = true
							gui.SelectedObject = nil
						end
						mounted[key] = nil
						placed[key] = nil
						cellEdits[key] = nil
						if preparing[node] then
							preparing[node] = nil
							waiting:update(function(value)
								return math.max(0, value - 1)
							end)
						end
						local wanted = false
						local pendingReplacement = false
						local nextRows = source(function<T>(cell: ComposeTypes.Readable<T>): T
							return cell:peek()
						end)
						for index, item in nextRows do
							local nextKey = keyOf(item, index)
							wanted = wanted or nextKey == key
							local window = viewport:peek()
							local at = if controls.placementOf then controls.placementOf(index) else nil
							local inWindow = spec.mode == "all"
								or window.size <= 0
								or (
									at ~= nil
									and at.offset + at.size > window.offset
									and at.offset < window.offset + window.size
								)
							pendingReplacement = pendingReplacement or (mounted[nextKey] == nil and inWindow)
						end
						if
							not wanted
							and pendingReplacement
							and painted:peek()
							and not poolOwner.isDisposed()
							and #source(function<T>(cell: ComposeTypes.Readable<T>): T
									return cell:peek()
								end)
								> 0
						then
							parked = previousParent
							node.Parent = parked
							content.Interactable = false
							retiring[node] = release
						else
							release()
						end
					end)
					runtime.connect(node, "AncestryChanged", function()
						mountedVersion:update(function(value)
							return value + 1
						end)
					end)
					return node
				end),
			})
		end
		local function followOf(use: ComposeTypes.Use?): CollectionTypes.Follow
			local value = read(spec.follow, use)
			assert(value == nil or value == "end" or value == "none", "Facet collection follow must be none or end")
			return if value == "end" then "end" else "none"
		end
		local directive = if Compose.isReadable(spec.follow) or type(spec.follow) == "function"
			then Compose.switch(followOf, {
				none = function()
					return orderedRows("none")
				end,
				["end"] = function()
					return orderedRows("end")
				end,
			})
			else orderedRows(followOf())
		local contentExtent = Compose.formula(function(use: ComposeTypes.Use): number
			local current = use(status)
			local extent = if current and current.extent then current.extent else 0
			return if extent > 0 then extent + 2 * mainEdge(use) else 0
		end)
		local native = props(spec, behavior, {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.fromScale(1, 1),
			AutomaticCanvasSize = E.AutomaticSize.None,
			ScrollingDirection = if horizontal then E.ScrollingDirection.X else E.ScrollingDirection.Y,
			VerticalScrollBarInset = if horizontal then E.ScrollBarInset.ScrollBar else nil,
			ScrollBarThickness = 6,
			SelectionGroup = true,
			CanvasSize = function(use: ComposeTypes.Use)
				local extent = use(contentExtent)
				return if horizontal then D2.fromOffset(extent, 0) else D2.fromOffset(0, extent)
			end,
		})
		native[#native + 1] = Compose.show(function(use: ComposeTypes.Use)
			return spec.mode == "all" or use(viewport).size > 0
		end, function()
			local nativeProps: Types.FrameProps = {
				Name = "Items",
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 1),

				Attributes = { FacetDocumentOrder = true } :: EngineTypes.Attributes,
				directive,
			}
			if kind == "grid" then
				nativeProps[#nativeProps + 1] = Host.UIPadding({
					PaddingLeft = function(use: ComposeTypes.Use)
						return ctx.types.UDim.new(0, if horizontal then mainEdge(use) else crossEdge(use))
					end,
					PaddingRight = function(use: ComposeTypes.Use)
						return ctx.types.UDim.new(0, if horizontal then 0 else crossEdge(use))
					end,
					PaddingTop = function(use: ComposeTypes.Use)
						return ctx.types.UDim.new(0, if horizontal then crossEdge(use) else mainEdge(use))
					end,
					PaddingBottom = function(use: ComposeTypes.Use)
						return ctx.types.UDim.new(0, if horizontal then crossEdge(use) else 0)
					end,
				}) :: Types.Child
			end
			return Host.Frame(nativeProps)
		end)
		table.insert(native, unit)
		root = ctx.styled(Host.ScrollingFrame(native), "Collection")
		Compose.cleanup(function()
			for node, release in retiring do
				retiring[node] = nil
				release()
			end
		end)
		scrollLock.own(root, ctx)
		root:SetAttribute("FacetSelectionOwner", true)

		local input = ctx.config.userInputService
		if horizontal and input and not spec.reorderable then
			local pressAt: number? = nil
			local startOffset, dragging = 0, false
			local samples: { Vector2 } = {}
			local velocity = 0
			local stopFling: (() -> ())? = nil
			local function halt(): ()
				if stopFling then
					stopFling()
					stopFling = nil
				end
			end
			Compose.cleanup(halt)
			local function limit(): number
				return math.max(0, root.CanvasSize.X.Offset - root.AbsoluteWindowSize.X)
			end
			local function items(): Instance?
				return root:FindFirstChild("Items")
			end
			local function inside(position: Vector3): boolean
				local point = V2.new(position.X, position.Y)
				local layer = root:FindFirstAncestorWhichIsA("LayerCollector")
				if layer and layer:IsA("ScreenGui") and layer.IgnoreGuiInset and gui then
					point += gui:GetGuiInset()
				end
				local at, size = root.AbsolutePosition, root.AbsoluteSize
				return point.X >= at.X and point.Y >= at.Y and point.X <= at.X + size.X and point.Y <= at.Y + size.Y
			end
			runtime.connect(input, "InputBegan", function(value: InputObject)
				if
					value.UserInputType == E.UserInputType.MouseButton1
					and inside(value.Position)
					and ctx.available(root)
				then
					halt()
					pressAt, startOffset, dragging = value.Position.X, root.CanvasPosition.X, false
					samples = { V2.new(frames.now(), value.Position.X) }
				end
			end)
			runtime.connect(input, "InputChanged", function(value: InputObject)
				if pressAt == nil or value.UserInputType ~= E.UserInputType.MouseMovement then
					return
				end
				local travel = value.Position.X - pressAt
				if not dragging and math.abs(travel) >= 6 then
					dragging = true
					local node = items()
					if node and node:IsA("GuiObject") then
						node.Interactable = false
					end
				end
				local now = frames.now()
				table.insert(samples, V2.new(now, value.Position.X))
				while #samples > 2 and now - samples[1].X > FLING_WINDOW do
					table.remove(samples, 1)
				end
				if dragging then
					root.CanvasPosition = V2.new(math.clamp(startOffset - travel, 0, limit()), root.CanvasPosition.Y)
				end
			end)
			runtime.connect(input, "InputEnded", function(value: InputObject)
				if value.UserInputType ~= E.UserInputType.MouseButton1 or pressAt == nil then
					return
				end
				pressAt = nil
				if dragging then
					dragging = false
					local stop: (() -> ())? = nil
					stop = frames.onFrame(function()
						if stop then
							stop()
						end
						local node = items()
						if node and node:IsA("GuiObject") then
							node.Interactable = true
						end
					end)
					local first, last = samples[1], samples[#samples]
					local span = last.X - first.X
					velocity = if span > 0 then (first.Y - last.Y) / span else 0
					if frames.now() - last.X < FLING_WINDOW and math.abs(velocity) > FLING_MINIMUM then
						local friction = ctx.metric("motion.fling.friction")
						stopFling = frames.onFrame(function(step: number)
							velocity *= math.exp(-friction * step)
							local at = root.CanvasPosition.X
							local nextX = math.clamp(at + velocity * step, 0, limit())
							root.CanvasPosition = V2.new(nextX, root.CanvasPosition.Y)
							if math.abs(velocity) < FLING_STOP or nextX == at then
								halt()
							end
						end)
					end
				end
			end)
		end
		if overlayReorder then
			runtime.mount(function()
				return overlayReorder(true)
			end, root)
		end
		local size: ComposeTypes.Cell<Vector2> = observe.AbsoluteWindowSize(root)
		local position: ComposeTypes.Cell<Vector2> = observe.CanvasPosition(root)
		local mountParent = observe.Parent(root)
		local ancestryVersion = Compose.cell(0)
		runtime.connect(root, "AncestryChanged", function()
			ancestryVersion:update(function(version: number): number
				return version + 1
			end)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local scale = use(unitSize).X
			local dimensions, at = use(size), use(position)
			use(ancestryVersion)
			local ancestor = use(mountParent)
			if dimensions.X <= 0 or dimensions.Y <= 0 then
				while ancestor do
					if ancestor:IsA("GuiObject") and ancestor.AbsoluteSize.X > 0 and ancestor.AbsoluteSize.Y > 0 then
						local bounds = ancestor.AbsoluteSize
						local authored = root.Size
						local unitScale = if scale > 0 then scale else 1
						dimensions = V2.new(
							bounds.X * authored.X.Scale + authored.X.Offset * unitScale,
							bounds.Y * authored.Y.Scale + authored.Y.Offset * unitScale
						)
						break
					end
					ancestor = ancestor.Parent
				end
			end
			if scale > 0 then
				dimensions /= scale
			end
			local offset = math.max(0, (if horizontal then at.X else at.Y) - mainEdge(use))
			local extent = math.max(0, (if horizontal then dimensions.X else dimensions.Y) - 2 * mainEdge(use))
			cross:set(if horizontal then dimensions.Y else dimensions.X)
			local previous = viewport:peek()
			if previous.offset ~= offset or previous.size ~= extent then
				viewport:set({ offset = offset, size = extent })
			end
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local current = use(status)
			local desired = if current then current.desiredOffset else nil
			local box = viewport:peek()
			if initialFollow and current and current.total ~= nil and box.size > 0 then
				initialFollow = false
				desired = math.max(0, current.extent - box.size)
			end
			if desired ~= nil then
				setOffset(desired)
			end
		end)
		local focusGeometry = Compose.formula(function(use: ComposeTypes.Use)
			use(mountedVersion)
			for _, placement in placed do
				use(placement)
			end
			local current = use(status)
			if current.total == 0 then
				return ""
			end
			local at = assert(controls.placementOf)(math.max(1, current.total or 1))
			return table.concat({
				tostring(current.extent),
				tostring(current.rowCount),
				tostring(current.total),
				tostring(at.column),
				tostring(at.crossSize),
				tostring(at.crossOffset),
			}, ":")
		end)
		local focusScope = Compose.createFocusScope({
			from = function(use: ComposeTypes.Use)
				if not use(focusActive) then
					return noFocusCandidates
				end
				if kind == "list" then
					return source(use)
				end
				use(focusGeometry)
				use(cross)
				use(measured)
				read(spec.measured, use)
				read(spec.columns, use)
				read(spec.itemSize, use)
				read(spec.gap, use)
				return source(use)
			end,
			key = keyOf,
			disabled = function(item)
				return (tree ~= nil and not tree.visible(keyOf(item, 1))) or policy.disabled(spec.disabled, item)
			end,
			initial = spec.initialFocus,
			autoFocus = spec.autoFocus,
			wrap = spec.wrapFocus,
			position = function(_, index)
				if kind == "list" then
					return if horizontal then index else 0, if horizontal then 0 else index
				end
				local current = status:peek()
				if current == nil or current.total == nil or current.total == 0 then
					return 0, 0
				end
				local at = assert(controls.placementOf)(math.min(index, current.total))
				return if horizontal then at.offset else at.crossOffset,
					if horizontal then at.crossOffset else at.offset
			end,
		})
		scope = focusScope
		local knownKeys: { K } = {}
		local priorKeys: { K } = {}
		local function liveKeys(rows: { V }?): ({ K }, { [K]: boolean })
			local keys, present = {}, {}
			local list: { V } = rows or {}
			for index, item in list do
				local key = keyOf(item, index)
				table.insert(keys, key)
				if not policy.disabled(spec.disabled, item) then
					present[key] = true
				end
			end
			return keys, present
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local keys = liveKeys(source(use))
			priorKeys, knownKeys = knownKeys, keys
		end)
		local function peekRows(): { V }
			return source(function<T>(value: ComposeTypes.Readable<T>): T
				return value:peek()
			end)
		end
		local function neighbourOf(lost: K): K?
			local ancestor = if tree then tree.ancestor(lost) else nil
			if ancestor ~= nil then
				return ancestor
			end
			local keys, present = liveKeys(peekRows())
			if table.find(keys, lost) then
				return nil
			end
			local before = if table.find(knownKeys, lost) then knownKeys else priorKeys
			local at = table.find(before, lost)
			if at == nil then
				return nil
			end
			for index = at + 1, #before do
				if present[before[index]] then
					return before[index]
				end
			end
			for index = at - 1, 1, -1 do
				if present[before[index]] then
					return before[index]
				end
			end
			return nil
		end
		local focusPolicy = spec.focusPolicy or "key"
		assert(focusPolicy == "key" or focusPolicy == "index", "Facet collection focusPolicy must be key or index")
		if focusPolicy == "index" then
			local slot: number? = nil
			local function indexOf(rows: { V }, wanted: K): number?
				for index, item in rows do
					if keyOf(item, index) == wanted then
						return index
					end
				end
				return nil
			end
			Compose.watch(function(use: ComposeTypes.Use)
				local key = use(focusScope.current)
				slot = if key ~= nil then indexOf(peekRows(), key) else nil
			end)
			Compose.watch(function(use: ComposeTypes.Use)
				local rows = source(use)
				local key = focusScope.current:peek()
				if key == nil or slot == nil or (editor and editor.busy()) or indexOf(rows, key) == slot then
					return
				end
				local at = math.min(slot :: number, #rows)
				if rows[at] ~= nil and not policy.disabled(spec.disabled, rows[at]) then
					focusScope.focus(keyOf(rows[at], at))
				end
			end)
		end
		local lastFocused: K? = nil
		Compose.watch(function(use: ComposeTypes.Use)
			local key = use(focusScope.current)
			local lost = lastFocused
			lastFocused = key
			if lost == nil or key == lost or not focusOwned then
				return
			end
			local neighbour = neighbourOf(lost)
			if neighbour ~= nil and neighbour ~= key then
				focusScope.focus(neighbour)
			end
		end)
		if spec.focus then
			spec.focus.current = focusScope.current
			spec.focus.focus = focusScope.focus
			spec.focus.clear = focusScope.clear
			spec.focus.next = focusScope.next
			spec.focus.previous = focusScope.previous
			spec.focus.move = focusScope.move
			spec.focus.first = focusScope.first
			spec.focus.last = focusScope.last
			spec.focus.isFocused = focusScope.isFocused
		end
		if tree then
			tree.bind(root, focusScope)
		end
		local parent = observe.Parent(root)
		local function restoreFocus(key: K?): ()
			if
				gui == nil
				or root.Parent == nil
				or not focusOwned
				or key == nil
				or mounted[key] == nil
				or not belongsTo(mounted[key], root)
			then
				return
			end
			local node = findSelectable(assert(mounted[key]), focusedPath, 1)
			if node then
				restoring = true
				pcall(function()
					gui.SelectedObject = node
				end)
				restoring = false
			end
		end
		local ready = Compose.formula(function(use: ComposeTypes.Use)
			local current = use(status)
			return current.total > 0
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(ready)
			local key = use(focusScope.current)
			if key == nil then
				return
			end
			focusOwned = true
			local currentStatus = status:peek()
			local index = if currentStatus.total > 0 then assert(controls.indexOfKey)(key) else nil
			if index then
				local at, current = assert(controls.placementOf)(index), viewport:peek()
				if at.offset < current.offset then
					setOffset(assert(controls.offsetOf)(index, "start", current.size))
				elseif at.offset + at.size > current.offset + current.size then
					setOffset(assert(controls.offsetOf)(index, "end", current.size))
				end
			end
			restoreFocus(key)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(mountedVersion)
			use(parent)
			restoreFocus(focusScope.current:peek())
		end)
		local selected: ComposeTypes.Cell<GuiObject?> = if gui
			then observe.SelectedObject(gui)
			else Compose.cell(nil :: GuiObject?)
		Compose.watch(function(use: ComposeTypes.Use)
			local field = use(selected)
			if
				field == nil
				or not field:IsA("TextBox")
				or not belongsTo(field, root)
				or read(spec.ScrollingEnabled, use) == false
			then
				return
			end
			local current = use(viewport)
			if current.size <= 0 then
				return
			end
			use(status)
			for key, node in mounted do
				if node and field:IsDescendantOf(node) then
					local index = assert(controls.indexOfKey)(key)
					local at = index and assert(controls.placementOf)(index)
					if at and at.offset < current.offset then
						setOffset(at.offset)
					elseif at and at.offset + at.size > current.offset + current.size then
						setOffset(math.max(at.offset, at.offset + at.size - current.size))
					end
					break
				end
			end
		end)
		local function renameAction(use: ComposeTypes.Use?): activation.EditAction?
			readSource(mountedVersion, use)
			local focused = readSource(selected, use)
			if
				(focused and not belongsTo(focused, root))
				or not readSource(focusActive, use)
				or (editor and editor.busy())
				or (input and input.GetFocusedTextBox and input:GetFocusedTextBox())
			then
				return nil
			end
			local key: K? = nil
			for candidate in readSource(selection, use) do
				if key ~= nil then
					return nil
				end
				key = candidate
			end
			key = key or readSource(focusScope.current, use)
			local edits = if key ~= nil then cellEdits[key] else nil
			if edits then
				for _, action in edits do
					if action.enabled(use) then
						return action
					end
				end
			end
			return nil
		end
		ctx.action(root, "RenameCell", { E.KeyCode.F2 }, function(use: ComposeTypes.Use): boolean
			return renameAction(use) ~= nil
		end, function()
			local action = renameAction()
			if action then
				action.onActivate()
			end
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local node = use(selected)
			if node and not restoring then
				if belongsTo(node, root) then
					focusActive:set(true)
					for key, row in mounted do
						if row and belongsTo(node, row) then
							local neighbour = neighbourOf(key)
							if neighbour ~= nil then
								focusOwned = true
								focusScope.focus(neighbour)
								restoreFocus(neighbour)
							end
							break
						end
					end
				else
					local lost = lastFocused or focusScope.current:peek()
					local neighbour = if focusOwned and lost ~= nil then neighbourOf(lost) else nil
					if neighbour ~= nil and mounted[neighbour] then
						focusScope.focus(neighbour)
						restoreFocus(neighbour)
					else
						focusOwned = false
					end
				end
			end
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(mountedVersion)
			if gui == nil or use(selected) ~= root then
				return
			end
			local target: GuiObject? = nil
			local key = focusScope.current:peek()
			if key ~= nil and mounted[key] then
				target = findSelectable(assert(mounted[key]), nil, 1)
			end
			if target == nil then
				local rows: { V } = read(spec.from) or {}
				for index, item in rows do
					local candidate = keyOf(item, index)
					if mounted[candidate] and not policy.disabled(spec.disabled, item) then
						target = findSelectable(assert(mounted[candidate]), nil, 1)
						if target then
							break
						end
					end
				end
			end
			if target then
				gui.SelectedObject = target
			end
		end)
		local function eligible(use: ComposeTypes.Use): boolean
			local node = readSource(selected, use)
			if node == nil or not belongsTo(node, root) then
				return false
			end
			local input = ctx.config.userInputService
			return not (input and input:GetFocusedTextBox()) and not (node:IsA("TextBox") and node:IsFocused())
		end
		if spec.measure then
			Compose.watch(function(use: ComposeTypes.Use)
				local rows = source(use)
				if next(measured:peek()) == nil then
					return
				end
				local valid: { [K]: boolean } = {}
				local pruned: { [K]: number } = {}
				local changed = false
				for index, item in rows do
					valid[keyOf(item, index)] = true
				end
				for key, extent in measured:peek() do
					if valid[key] then
						pruned[key] = extent
					else
						changed = true
					end
				end
				if changed then
					measured:set(pruned)
				end
			end)
		end
		local directions: { { name: string, direction: ComposeTypes.FocusDirection, keys: { Enum.KeyCode } } } = {
			{ name = "Left", direction = "left", keys = { E.KeyCode.Left, E.KeyCode.DPadLeft } },
			{ name = "Right", direction = "right", keys = { E.KeyCode.Right, E.KeyCode.DPadRight } },
			{ name = "Up", direction = "up", keys = { E.KeyCode.Up, E.KeyCode.DPadUp } },
			{ name = "Down", direction = "down", keys = { E.KeyCode.Down, E.KeyCode.DPadDown } },
		}
		local function atEdge(key: K, step: number): boolean
			local rows = read(spec.from)
			local at: number? = nil
			for index, item in rows do
				if keyOf(item, index) == key then
					at = index
					break
				end
			end
			if at == nil then
				return false
			end
			local index = at + step
			while index >= 1 and index <= #rows do
				if not policy.disabled(spec.disabled, rows[index]) then
					return false
				end
				index += step
			end
			return true
		end
		local function wrapStep(direction: ComposeTypes.FocusDirection): number
			local along = if kind == "grid"
				then true
				elseif horizontal then direction == "left" or direction == "right"
				else direction == "up" or direction == "down"
			if not along then
				return 0
			end
			return if direction == "right" or direction == "down" then 1 else -1
		end
		for _, binding in directions do
			local along = binding.direction == (if horizontal then "left" else "up")
				or binding.direction == (if horizontal then "right" else "down")
			local function enabled(use: ComposeTypes.Use): boolean
				return (along or kind == "grid") and eligible(use)
			end
			ctx.action(root, "Collection" .. binding.name, binding.keys, enabled, function()
				local before = focusScope.current:peek()
				local after = focusScope.move(binding.direction)
				if kind == "grid" and spec.wrapFocus and before ~= nil and after == before then
					local rows = read(spec.from)
					local columns = math.max(1, math.floor(read(spec.columns or 1)))
					local at: number? = nil
					for index, item in rows do
						if keyOf(item, index) == before then
							at = index
							break
						end
					end
					if at ~= nil then
						local column = (at - 1) % columns
						local rowStart = at - column
						local rowEnd = math.min(rowStart + columns - 1, #rows)
						local target = if binding.direction == "right"
							then rowStart
							elseif binding.direction == "left" then rowEnd
							elseif binding.direction == "down" then column + 1
							else column + 1 + math.floor((#rows - 1 - column) / columns) * columns
						if target ~= at and rows[target] ~= nil then
							focusScope.focus(keyOf(rows[target], target))
						end
					end
					return
				end
				local step = if spec.wrapFocus
						and before ~= nil
						and after == before
					then wrapStep(binding.direction)
					else 0
				if step ~= 0 and not atEdge(assert(before), step) then
					step = 0
				end
				if step > 0 then
					focusScope.next()
				elseif step < 0 then
					focusScope.previous()
				end
				local landed = focusScope.current:peek()
				if landed ~= nil then
					extendSelection(before, landed)
				end
			end, { priority = 200 })
		end
		local function jump(move: () -> ()): () -> ()
			return function()
				local before = focusScope.current:peek()
				move()
				local landed = focusScope.current:peek()
				if landed ~= nil then
					extendSelection(before, landed)
				end
			end
		end
		ctx.action(root, "CollectionFirst", { E.KeyCode.Home }, eligible, jump(focusScope.first), { priority = 200 })
		ctx.action(root, "CollectionLast", { E.KeyCode.End }, eligible, jump(focusScope.last), { priority = 200 })

		if spec.onReachEnd then
			local previousTotal = -1
			Compose.watch(function(use: ComposeTypes.Use)
				local current = use(status)
				if
					current
					and current.total > 0
					and current.last == current.total
					and current.total ~= previousTotal
				then
					previousTotal = current.total
					spec.onReachEnd()
				end
			end)
		end
		if spec.snap == "item" or cardsMode then
			attachSnap(ctx, spec, root, controls, status, viewport, setOffset, function()
				return writingOffset
			end, function()
				local _, perView = cardLayout()
				return spec.snap == "item" or perView == 1
			end)
		end
		initialScroll(ctx, root, spec.CanvasPosition)
		return root
	end
	local function construct<V, K>(
		spec: CollectionTypes.CollectionSpec<V, K>,
		kind: ComposeTypes.OrderedCollectionLayoutKind,
		tree: TreeTypes.Tree<V, K>?,
		actionsWrapped: boolean?
	): ScrollingFrame
		if spec.key == nil then
			return collection(spec, kind, function(value: V, _index: number): V
				return value
			end)
		end
		local key: unknown = spec.key
		if type(key) == "string" then
			assert(key ~= "", "Facet collection: key field must not be empty")
			local fieldSpec = (spec :: unknown) :: CollectionTypes.KeyedCollectionSpec<V, string>
			return collection(fieldSpec, kind, function(value: V, _index: number): string
				return tostring(((value :: unknown) :: { [string]: unknown })[key])
			end)
		end
		assert(type(key) == "function", "Facet collection: key must be a function or a field name")
		return collection(
			(spec :: unknown) :: CollectionTypes.KeyedCollectionSpec<V, K>,
			kind,
			(key :: unknown) :: (V, number) -> K,
			tree,
			actionsWrapped
		)
	end
	local function list<V, K>(spec: CollectionTypes.CollectionSpec<V, K>): ScrollingFrame
		return construct(spec, "list")
	end
	local function grid<V, K>(spec: CollectionTypes.CollectionSpec<V, K>): ScrollingFrame
		return construct(spec, "grid")
	end

	UI.Outline = ctx.construct("Outline", function<V, K>(spec: CollectionTypes.OutlineSpec<V, K>): ScrollingFrame
		assert(spec.children ~= nil, "Facet Outline requires children")
		return construct(spec, "list")
	end) :: CollectionTypes.OutlineConstructor
	UI.VirtualList = ctx.construct("VirtualList", list) :: CollectionTypes.CollectionConstructor
	UI.VirtualGrid = ctx.construct("VirtualGrid", grid) :: CollectionTypes.CollectionConstructor
	return function<V, K>(
		spec: CollectionTypes.KeyedCollectionSpec<V, K>,
		tree: TreeTypes.Tree<V, K>?,
		actionsWrapped: boolean?
	): ScrollingFrame
		return construct(spec, "list", tree, actionsWrapped)
	end
end
