--!strict
local createTree = require("./collection_tree")
local TreeTypes = require("./collection_tree")
local State = require("./collection_state")
local createSlots = require("./collection_slots")
local createRows = require("./collection_rows")
local attachFling = require("./collection_fling")
local createFocus = require("./collection_focus")
local bindNavigation = require("./collection_navigation")
local scrollLock = require("./scroll_lock")
local initialScroll = require("./scroll_initial")
local reorder = require("./collection_reorder")
local attachSnap = require("./collection_snap")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local CollectionProps = require("./collection_props")
local ControlTypes = require("./control_types")

export type ScrollPolicy = (ComposeTypes.Use, ComposeTypes.OrderedCollectionViewport) -> number?

export type BuildList = <V, K>(
	CollectionProps.KeyedCollectionSpec<V, K>,
	TreeTypes.Tree<V, K>?,
	boolean?,
	ScrollPolicy?
) -> ScrollingFrame

return function(ctx: Types.Context, UI: ControlTypes.BuilderControls): BuildList
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local observe = ctx.observe
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
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
		"hug",
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
		"scrollReset",
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
	local function collection<V, K>(
		spec: CollectionTypes.CollectionShape<V, K>,
		kind: ComposeTypes.OrderedCollectionLayoutKind,
		keyOf: (V, number) -> K,
		tree: TreeTypes.Tree<V, K>?,
		actionsWrapped: boolean?,
		scrollPolicy: ScrollPolicy?
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
		assert(spec.hug == nil or type(spec.hug) == "boolean", "Facet collection hug must be a boolean")
		assert(not spec.hug or spec.mode == "all", 'Facet collection hug needs mode = "all": it sizes to every row')
		assert(not spec.hug or spec.itemSize ~= "cards", 'Facet collection hug cannot size "cards" from its own extent')
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
		local view = State.create(ctx, spec, kind, keyOf, tree, actionsWrapped, source)
		local viewport, cross, status, controls = view.viewport, view.cross, view.status, view.controls
		local measured, horizontal = view.measured, view.horizontal
		local retiring = view.retiring
		local mainEdge, crossEdge = view.mainEdge, view.crossEdge
		local root: ScrollingFrame
		local writingOffset = false
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
		editor = if spec.drag
				or spec.drop
				or spec.reorderable
				or spec.deletable
				or (spec.editing ~= nil and view.selectionMode ~= "none" and spec.selectionIndicator ~= false)
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
				view.selection,
				Compose.cell(nil :: CollectionTypes.Sort?),
				spec.editing,
				kind == "grid",
				if tree then tree.location else nil,
				nil,
				spec.slots
			)
			else nil
		local overlayReorder = if editor then editor.overlay else nil
		local slots = createSlots(ctx, view)
		local orderedRows = createRows(ctx, UI, view, editor, slots)
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
		local native = ctx.props(spec, behavior, {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = if spec.hug
				then function(use: ComposeTypes.Use): UDim2
					local extent = use(contentExtent)
					return if horizontal then D2.new(0, extent, 1, 0) else D2.new(1, 0, 0, extent)
				end
				else D2.fromScale(1, 1),
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
		table.insert(native, view.unit)
		root = ctx.styled(Host.ScrollingFrame(native), "Collection")
		Compose.cleanup(function()
			for node, release in retiring do
				retiring[node] = nil
				release()
			end
		end)
		scrollLock.own(root, ctx)
		root:SetAttribute("FacetSelectionOwner", true)
		attachFling(ctx, view, root)
		if overlayReorder then
			runtime.mount(function()
				return overlayReorder(true)
			end, root)
		end
		local size: ComposeTypes.Cell<Vector2> = ctx.observeNative.AbsoluteWindowSize(root)
		local position: ComposeTypes.Cell<Vector2> = observe.CanvasPosition(root)
		local mountParent = observe.Parent(root)
		local ancestryVersion = Compose.cell(0)
		runtime.connect(root, "AncestryChanged", function()
			ancestryVersion:update(function(version: number): number
				return version + 1
			end)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local scale = use(view.unitSize).X
			use(size)
			use(position)
			local dimensions, at = root.AbsoluteWindowSize, root.CanvasPosition
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
				viewport:set({ offset = offset, size = extent, offsetRevision = previous.offsetRevision })
			end
		end)
		local resetKey: string? = nil
		Compose.watch(function(use: ComposeTypes.Use)
			local requestedReset = if spec.scrollReset ~= nil then read(spec.scrollReset, use) :: string else nil
			local reset = resetKey ~= nil and requestedReset ~= resetKey
			resetKey = requestedReset
			local current = use(status)
			local desired = if current then current.desiredOffset else nil
			local box = viewport:peek()
			if view.initialFollow and current and current.total ~= nil and box.size > 0 then
				view.initialFollow = false
				desired = math.max(0, current.extent - box.size)
			end
			local policyOffset = if scrollPolicy then scrollPolicy(use, box) else nil
			if policyOffset ~= nil then
				desired = policyOffset
			end
			if reset then
				desired = 0
			end
			if desired ~= nil then
				setOffset(desired)
			end
			if policyOffset ~= nil or reset then
				local current = viewport:peek()
				local at = root.CanvasPosition
				viewport:set({
					offset = math.max(0, (if horizontal then at.X else at.Y) - mainEdge()),
					size = current.size,
					offsetRevision = (current.offsetRevision or 0) + 1,
				})
			end
		end)
		local focusScope, eligible = createFocus(ctx, view, editor, root, setOffset)
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
		bindNavigation(ctx, view, root, focusScope, eligible)
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
		if spec.snap == "item" or view.cardsMode then
			attachSnap(ctx, spec, root, controls, status, viewport, setOffset, function()
				return writingOffset
			end, function()
				local _, perView = view.cardLayout()
				return spec.snap == "item" or perView == 1
			end)
		end
		initialScroll(ctx, root, spec.CanvasPosition)
		return root
	end
	local function construct<V, K>(
		spec: CollectionProps.CollectionSpec<V, K>,
		kind: ComposeTypes.OrderedCollectionLayoutKind,
		tree: TreeTypes.Tree<V, K>?,
		actionsWrapped: boolean?,
		scrollPolicy: ScrollPolicy?
	): ScrollingFrame
		if spec.key == nil then
			return collection(
				(spec :: unknown) :: CollectionTypes.CollectionShape<V, V>,
				kind,
				function(value: V, _index: number): V
					return value
				end
			)
		end
		local key: unknown = spec.key
		if type(key) == "string" then
			assert(key ~= "", "Facet collection: key field must not be empty")
			local fieldSpec = (spec :: unknown) :: CollectionTypes.CollectionShape<V, string>
			return collection(fieldSpec, kind, function(value: V, _index: number): string
				return tostring(((value :: unknown) :: { [string]: unknown })[key])
			end)
		end
		assert(type(key) == "function", "Facet collection: key must be a function or a field name")
		return collection(
			(spec :: unknown) :: CollectionTypes.CollectionShape<V, K>,
			kind,
			(key :: unknown) :: (V, number) -> K,
			tree,
			actionsWrapped,
			scrollPolicy
		)
	end
	local function list<V, K>(spec: CollectionProps.CollectionSpec<V, K>): ScrollingFrame
		return construct(spec, "list")
	end
	local function grid<V, K>(spec: CollectionProps.CollectionSpec<V, K>): ScrollingFrame
		return construct(spec, "grid")
	end

	UI.Outline = ctx.construct("Outline", function<V, K>(spec: CollectionProps.OutlineSpec<V, K>): ScrollingFrame
		assert(spec.children ~= nil, "Facet Outline requires children")
		return construct(spec, "list")
	end) :: ControlTypes.OutlineConstructor
	UI.VirtualList = ctx.construct("VirtualList", list) :: ControlTypes.CollectionConstructor
	UI.VirtualGrid = ctx.construct("VirtualGrid", grid) :: ControlTypes.CollectionConstructor
	return function<V, K>(
		spec: CollectionProps.KeyedCollectionSpec<V, K>,
		tree: TreeTypes.Tree<V, K>?,
		actionsWrapped: boolean?,
		scrollPolicy: ScrollPolicy?
	): ScrollingFrame
		return construct(spec, "list", tree, actionsWrapped, scrollPolicy)
	end
end
