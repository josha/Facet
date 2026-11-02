--!strict
local ControlTypes = require("./control_types")
local activation = require("./activation")
local preparePaint = require("./collection_paint")
local reorder = require("./collection_reorder")
local policy = require("./collection_policy")
local travelEngine = require("./travel_engine")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local State = require("./collection_state")
local Slots = require("./collection_slots")
local createHighlight = require("./collection_highlight")
return function<V, K>(
	ctx: Types.Context,
	UI: ControlTypes.Controls,
	view: State.View<V, K>,
	editor: reorder.Editor<V, K>?,
	slots: Slots.Slots<V, K>?
): (CollectionTypes.Follow?) -> ComposeTypes.Child
	type SlotRecord = Slots.Slot<V, K>
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local readSource = ctx.readSource
	local readMeasurements = ctx.read<<{ [K]: number }>>
	local observe = ctx.observe
	local D2, D, V2, E = ctx.types.UDim2, ctx.types.UDim, ctx.types.Vector2, ctx.types.Enum
	local gui = ctx.config.guiService
	local spec, tree = view.spec, view.tree
	local kind: ComposeTypes.OrderedCollectionLayoutKind = view.kind
	local source, viewport, cross = view.source, view.viewport, view.cross
	local mountedVersion, status, controls, selection = view.mountedVersion, view.status, view.controls, view.selection
	local coordinator, selectionMode = view.coordinator, view.selectionMode
	local highlight = createHighlight(Compose, selection, spec.selection ~= nil or selectionMode ~= "none")
	local measured, containsCards, horizontal = view.measured, view.containsCards, view.horizontal
	local reduced, focusActive = view.reduced, view.focusActive
	local liveOverflow = Compose.isValue(spec.contentOverflow) or type(spec.contentOverflow) == "function"
	local mounted, cellEdits, placed, poolOwner = view.mounted, view.cellEdits, view.placed, view.poolOwner
	local preparing, waiting = view.preparing, view.waiting
	local crossEdge, fullSizes = view.crossEdge, view.fullSizes
	local fill, middle, centre = D2.fromScale(1, 1), D2.fromScale(0.5, 0.5), V2.new(0.5, 0.5)
	local keyedRows: { [{ V }]: { keys: { K }, index: { [K]: number } } } = setmetatable({}, { __mode = "k" })
	local function keysOf(rows: { V }): { keys: { K }, index: { [K]: number } }
		local cached = keyedRows[rows]
		if cached == nil then
			local keys: { K }, index: { [K]: number } = table.create(#rows), {}
			for position, item in rows do
				local key = view.keyOf(item, position)
				keys[position] = key
				index[key] = position
			end
			cached = { keys = keys, index = index }
			keyedRows[rows] = cached
		end
		return cached
	end
	local function select(key: K, current: ComposeTypes.ReadOnlyValue<V>, input: InputObject?, clicks: number?): ()
		if policy.disabled(spec.disabled, current:peek()) or activation.consumed(input) then
			return
		end
		if editor and spec.onActivate == nil and read(spec.editing) ~= true and editor.pickUp(key, input) then
			return
		end
		local pointer = input ~= nil and input.UserInputType == E.UserInputType.MouseButton1
		local double = pointer and (clicks or 0) >= 2
		if not double then
			view.selectRow(key, current:peek(), input)
		end
		local choosing = selectionMode ~= "none" and read(spec.editing) == true
		if spec.onActivate and not choosing and (selectionMode == "none" or not pointer or double) then
			spec.onActivate(current:peek(), key, input, clicks)
		end
	end
	local function captureSelection(node: Instance, key: K): ()
		if view.scope == nil then
			return
		end
		focusActive:set(true)
		view.focusOwned = true
		local path: { string } = {}
		local current: Instance? = node
		while current and current ~= mounted[key] do
			table.insert(path, 1, current.Name)
			current = current.Parent
		end
		view.focusedPath = path
		view.scope.focus(key)
	end
	local function wireSelection(node: Instance, key: ComposeTypes.ReadOnlyValue<K>): ()
		if node:IsA("GuiObject") and (node.Selectable or node:IsA("GuiButton") or node:IsA("TextBox")) then
			runtime.connect(node, "SelectionGained", function()
				captureSelection(node, key:peek())
			end)
		end
		for _, child in node:GetChildren() do
			wireSelection(child, key)
		end
	end
	local recycling = spec.recycle ~= false
		and spec.slots == nil
		and tree == nil
		and editor == nil
		and spec.rowActions == nil
		and spec.rowDrop == nil
	local function peekRows(): { V }
		return source(function<T>(cell: ComposeTypes.ReadOnlyValue<T>): T
			return cell:peek()
		end)
	end
	local arrivals = spec.arrival ~= nil
	local latestRows: { V }? = if arrivals then peekRows() else nil
	local fresh: { [K]: boolean } = {}
	local clearFresh: (() -> ())? = nil
	local function syncArrivals(rows: { V }): ()
		local previous = latestRows
		if previous == nil or rows == previous then
			return
		end
		latestRows = rows
		local known = keysOf(previous).index
		for _, key in keysOf(rows).keys do
			if known[key] == nil then
				fresh[key] = true
			end
		end
		if clearFresh == nil and next(fresh) ~= nil then
			clearFresh = view.frames.onFrame(function()
				table.clear(fresh)
				if clearFresh then
					clearFresh()
					clearFresh = nil
				end
			end)
		end
	end
	if arrivals then
		Compose.watch(function(use: ComposeTypes.Use)
			syncArrivals(source(use))
		end)
		Compose.cleanup(function()
			if clearFresh then
				clearFresh()
				clearFresh = nil
			end
		end)
	end
	local function arrived(key: K): boolean
		if not arrivals then
			return false
		end
		syncArrivals(peekRows())
		local entering = fresh[key] == true
		fresh[key] = nil
		return entering and read(spec.arrival) == "rise" and not reduced()
	end
	local function row(
		rowItem: ComposeTypes.ReadOnlyValue<V>,
		rowPlacement: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
		keyCell: ComposeTypes.ReadOnlyValue<K>,
		follows: boolean
	): GuiObject
		local lease = view.pool.acquire()
		local node = runtime.borrow(lease.value.node) :: Frame
		local contentOwner = ComposeTypes.owner.createChild(poolOwner)
		local current, placement = Compose.withOwner(contentOwner, function()
			return Compose.cell(rowItem:peek()), Compose.cell(rowPlacement:peek())
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			current:set(use(rowItem))
			placement:set(use(rowPlacement))
		end)
		local springPlacement = spec.slots ~= nil or spec.drag ~= nil or spec.drop ~= nil
		local reservedPosition: ComposeTypes.ReadOnlyValue<Vector2>? = nil
		local glide: ComposeTypes.Value<number>? = nil
		if editor and (spec.reorderable or spec.drag) then
			reservedPosition = editor.position(keyCell:peek(), placement, spec.reducedMotion)
		elseif springPlacement then
			local position = Compose.cell(V2.new(placement:peek().crossOffset, placement:peek().offset))
			reservedPosition = position
			local target: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement> = placement
			if editor and (spec.drag or spec.drop) then
				local activeEditor = editor
				target = Compose.formula(function(use: ComposeTypes.Use): ComposeTypes.Placement
					return activeEditor.placement(use(keyCell), use(placement), use)
				end)
			end
			local engine = travelEngine(ctx, {
				initial = { placement:peek().crossOffset, placement:peek().offset },
				target = function(): { number }
					local at = target:peek()
					return { at.crossOffset, at.offset }
				end,
				sample = function(values: { number })
					position:set(V2.new(values[1], values[2]))
				end,
				reduced = reduced,
				motion = "spring",
				duration = ctx.metric("motion.durations.travel"),
				ease = ctx.motionEase("travel"),
				spring = ctx.motionSpring("travel"),
			})
			Compose.watch(function(use: ComposeTypes.Use)
				use(target)
				engine.retarget()
			end)
		elseif tree == nil and kind == "list" then
			local offset = Compose.cell(0)
			glide = offset
			local stopGlide: (() -> ())? = nil
			local function halt()
				if stopGlide then
					stopGlide()
					stopGlide = nil
				end
			end
			Compose.cleanup(halt)
			local previous, previousKey = placement:peek(), keyCell:peek()
			Compose.watch(function(use: ComposeTypes.Use)
				local at, now = use(placement), use(keyCell)
				local delta = previous.offset + offset:peek() - at.offset
				local moved = at.index ~= previous.index and now == previousKey
				if now ~= previousKey then
					halt()
					offset:set(0)
				end
				previous, previousKey = at, now
				if not moved or math.abs(delta) > viewport:peek().size or reduced() then
					return
				end
				halt()
				local elapsed = 0
				local seconds = ctx.metric("motion.durations.glide")
				local present = ctx.motionEase("present")
				offset:set(delta)
				stopGlide = view.frames.onFrame(function(step: number)
					elapsed = math.min(seconds, elapsed + step)
					offset:set(delta * (1 - present(elapsed / seconds)))
					if elapsed >= seconds then
						halt()
					end
				end)
			end)
		end
		local entering = arrived(keyCell:peek())
		local entrance: ComposeTypes.Value<number>? = if arrivals then Compose.cell(if entering then 0 else 1) else nil
		local interactable: ComposeTypes.Input<boolean> = if tree == nil and spec.disabled == nil
			then true
			else Compose.formula(function(use: ComposeTypes.Use): boolean
				return (tree == nil or tree.visible(use(keyCell), use))
					and not policy.disabled(spec.disabled, use(current))
			end)
		Compose.withOwner(contentOwner, function()
			runtime.decorate(node, {
				ClipsDescendants = tree ~= nil,
				Interactable = interactable,
			})
			local placed = { index = -1, main = math.huge, cross = math.huge, size = -1, crossSize = -1 }
			Compose.watch(function(use: ComposeTypes.Use)
				local at = use(placement)
				local main, cross = at.offset + (if glide then use(glide) else 0), at.crossOffset
				if reservedPosition then
					local position = use(reservedPosition)
					main, cross = position.Y, position.X
				end
				if entrance then
					main += (1 - use(entrance)) * ctx.metric("motion.distances.rowArrival", use)
				end
				if placed.index ~= at.index then
					placed.index = at.index
					node.LayoutOrder = at.index
				end
				if placed.main ~= main or placed.cross ~= cross then
					placed.main, placed.cross = main, cross
					node.Position = if horizontal then D2.fromOffset(main, cross) else D2.fromOffset(cross, main)
				end
				if placed.size ~= at.size or placed.crossSize ~= at.crossSize then
					placed.size, placed.crossSize = at.size, at.crossSize
					node.Size = if horizontal
						then D2.fromOffset(at.size, at.crossSize)
						else D2.fromOffset(at.crossSize, at.size)
				end
			end)
		end)
		local edits: { activation.EditAction } = {}
		local measuredNode: GuiObject
		local actionHeight: ComposeTypes.ReadOnlyValue<number>? = nil
		local painted = Compose.cell(false)
		local stop, mountedContent = Compose.withOwner(contentOwner, function()
			return runtime.mount(function(): GuiObject
				local rendered = assert(spec.render)(current, placement, keyCell)
				if tree and not tree.columnar then
					rendered = tree.wrap(rendered, current, keyCell:peek())
				end
				measuredNode = rendered
				if
					rendered:GetAttribute("FacetBody") ~= nil
					and (kind == "grid" or read(spec.contentOverflow) ~= "clip")
				then
					containsCards:set(true)
				end
				local rowEdits = activation.edits(rendered)
				for _, edit in rowEdits do
					local gated = table.clone(edit)
					gated.enabled = function(use: ComposeTypes.Use?): boolean
						return edit.enabled(use) and not policy.disabled(spec.disabled, readSource(current, use))
					end
					table.insert(edits, gated)
				end
				if not view.actionsWrapped then
					rendered, actionHeight = policy.actions(
						ctx,
						spec,
						current,
						keyCell:peek(),
						rendered,
						UI.RowActions,
						coordinator,
						kind == "grid",
						rowEdits
					)
				end
				if editor then
					rendered = editor.wrap(rendered, current, keyCell:peek())
					local press = editor.press
					Compose.cleanup(activation.providePress(rendered, function(value: InputObject)
						press(keyCell:peek(), value)
					end))
				end
				local selectionHit: TextButton? = nil
				local children: Types.FrameProps = {
					Name = "Content",
					Size = if tree
						then function(use: ComposeTypes.Use): UDim2
							local minimum = read(spec.itemSize or 40, use)
							assert(type(minimum) == "number", "Facet.Outline requires a numeric itemSize")
							local extent = use(measured)[use(keyCell)]
							if spec.measured ~= nil then
								local external = readMeasurements(spec.measured, use)[use(keyCell)]
								if external ~= nil then
									extent = external
								end
							end
							return D2.new(1, 0, 0, math.max(minimum, extent or 0))
						end
						else fill,
					BackgroundTransparency = 1,
					Attributes = { FacetCollectionRow = true } :: EngineTypes.Attributes,
					ClipsDescendants = if liveOverflow
						then function(use: ComposeTypes.Use): boolean
							return read(spec.contentOverflow, use) == "clip"
						end
						else read(spec.contentOverflow) == "clip",
					rendered,
				}
				if
					spec.onSelectionChange
					or spec.onActivate
					or spec.selection
					or spec.selectionMode
					or spec.rowDrop
					or #edits > 0
					or editor
				then
					local hit: TextButton
					hit = Host.TextButton "RowHit" {
						AnchorPoint = centre,
						Position = middle,
						Size = fill,
						Text = "",
						BackgroundTransparency = 1,
						Selectable = true,
						Interactable = interactable,
						Activated = function(input: InputObject?, clicks: number?)
							if not activation.intercepted(hit, input) then
								select(keyCell:peek(), current, input, clicks)
							end
						end,
						Attributes = {
							FacetSelectionRequired = selectionMode ~= "none",
						} :: EngineTypes.Attributes,
					}
					selectionHit = hit
					Compose.cleanup(activation.provide(hit, function(input: InputObject?, clicks: number?)
						if not activation.intercepted(hit, input) then
							select(keyCell:peek(), current, input, clicks)
						end
					end))
					local function pressed(value: InputObject)
						activation.press(rendered, value)
					end
					runtime.connect(hit, "InputBegan", pressed)
					if editor and ctx.config.inputParent and ctx.config.inputParent:IsA("PluginGui") then
						local activeEditor = editor
						runtime.connect(hit, "MouseButton1Down", function(x: number, y: number)
							activeEditor.mouseDown(V2.new(x, y))
						end)
						runtime.connect(hit, "InputEnded", editor.finish)
					end
					Compose.cleanup(activation.providePress(hit, pressed))
					table.insert((children :: unknown) :: { unknown }, 1, hit)
				end
				local carded = tree == nil
					and rendered:GetAttribute("FacetBody") ~= nil
					and read(spec.contentOverflow) ~= "clip"
				local paintSelection = spec.selectionIndicator ~= false and selectionMode ~= "none"
				if paintSelection and not carded then
					children.BackgroundTransparency = nil
				end
				local groupProperties: Types.CanvasGroupProps = (children :: unknown) :: Types.CanvasGroupProps
				local surface: Frame? = nil
				if carded then
					local cardSize = observe.AbsoluteSize(rendered)
					local cardLift = rendered:FindFirstChildWhichIsA("UIScale")
					local lift = if cardLift then observe.Scale(cardLift) else nil
					local function edges(use: ComposeTypes.Use): (number, number)
						if read(spec.contentOverflow, use) == "clip" then
							return 0, 0
						end
						local unit = math.max(use(view.unitSize).X * (if lift then use(lift) else 1), 0.001)
						local size = use(cardSize)
						local length = (if horizontal then size.X else size.Y) / unit
						local growth = math.max(0, ctx.metric("motion.materialize.lift", use) - 1)
						local main = math.max(view.mainEdge(use), math.ceil(length * growth))
						return if horizontal then main else crossEdge(use), if horizontal then crossEdge(use) else main
					end
					children.Name = "Surface"
					children.Attributes = nil
					children.AutomaticSize = if horizontal then E.AutomaticSize.X else E.AutomaticSize.Y
					surface = Host.Frame(children)
					local function crossPadding(use: ComposeTypes.Use): UDim
						local x = edges(use)
						return D.new(0, x)
					end
					local function mainPadding(use: ComposeTypes.Use): UDim
						local _, y = edges(use)
						return D.new(0, y)
					end
					local expanded: Types.CanvasGroupProps = {
						Name = "Content",
						BackgroundTransparency = 1,
						Attributes = { FacetCollectionRow = true } :: EngineTypes.Attributes,
						Position = function(use: ComposeTypes.Use): UDim2
							local x, y = edges(use)
							return D2.fromOffset(-x, -y)
						end,
						Size = function(use: ComposeTypes.Use): UDim2
							local x, y = edges(use)
							return D2.new(1, 2 * x, 1, 2 * y)
						end,
						Host.UIPadding {
							PaddingLeft = crossPadding,
							PaddingRight = crossPadding,
							PaddingTop = mainPadding,
							PaddingBottom = mainPadding,
						},
						surface,
					}
					groupProperties = expanded
				end
				groupProperties.GroupTransparency = function(use: ComposeTypes.Use): number
					return if use(painted) then 1 - (if entrance then use(entrance) else 1) else 1
				end
				groupProperties.Attributes =
					{ FacetCollectionRow = true, FacetCollectionReady = painted } :: EngineTypes.Attributes
				groupProperties.AutomaticSize = if tree ~= nil or read(spec.contentOverflow) == "clip"
					then E.AutomaticSize.None
					elseif carded then (if horizontal then E.AutomaticSize.X else E.AutomaticSize.Y)
					else E.AutomaticSize.XY
				local content = if tree then ctx.fade(groupProperties) else Host.CanvasGroup(groupProperties)
				local logical = surface or content
				policy.drop(ctx, spec, current, keyCell:peek(), logical, kind == "grid" or horizontal, selectionHit)
				local selected = if paintSelection
						and not carded
						and ctx.config.theme ~= nil
					then Compose.cell(false)
					else nil
				if paintSelection and not carded then
					ctx.styled(logical, "TableRow")
					if kind == "grid" or horizontal then
						ctx.skin(logical, "control", {
							selected = selected,
						})
					end
				end
				if selectionHit or paintSelection then
					local shownOnly: boolean?, shownOn: boolean? = nil, nil
					highlight(keyCell, function(state)
						local on, only = state ~= "none", state == "only"
						if selectionHit then
							if (editor or #edits > 0) and shownOnly ~= only then
								selectionHit:SetAttribute("FacetOnlySelected", only)
							end
							if shownOn ~= on then
								selectionHit:SetAttribute("FacetSelected", on)
							end
						end
						local changed = (shownOn == true) ~= on
						shownOnly, shownOn = only, on
						if paintSelection and changed then
							if on then
								logical:AddTag("facet-selected")
							else
								logical:RemoveTag("facet-selected")
							end
						end
						if selected then
							selected:set(on)
						end
					end)
				end
				return content
			end, node)
		end)
		local content = mountedContent :: GuiObject
		local parked: Instance? = nil
		local previousParent: Instance? = node.Parent
		local released = false
		local restoringParent = false
		local destroyed = node.Destroying:Connect(function()
			parked = nil
		end)
		local live = true
		local restore = node.AncestryChanged:Connect(function()
			if node.Parent and parked == nil then
				previousParent = node.Parent
			end
			if
				parked
				and not restoringParent
				and not ComposeTypes.owner.isDisposed(poolOwner)
				and node.Parent == nil
			then
				restoringParent = true
				local ok = pcall(function()
					node.Parent = parked
				end)
				restoringParent = false
				if not ok then
					parked = nil
				end
			end
			if live then
				mountedVersion:update(function(value)
					return value + 1
				end)
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
			Compose.owner.dispose(contentOwner)
			lease.release()
		end
		wireSelection(content, keyCell)
		view.slotKeys[node] = keyCell
		local stopArrival: (() -> ())? = nil
		local function settle(): ()
			if stopArrival then
				stopArrival()
				stopArrival = nil
			end
			if entrance then
				entrance:set(1)
			end
		end
		Compose.cleanup(settle)
		local function animate(): ()
			local cell = entrance
			if cell == nil then
				return
			end
			local elapsed = 0
			local seconds = ctx.metric("motion.durations.rowArrival")
			local present = ctx.motionEase("present")
			stopArrival = view.frames.onFrame(function(step: number)
				if not painted:peek() then
					return
				end
				elapsed = math.min(seconds, elapsed + step)
				cell:set(present(elapsed / seconds))
				if elapsed >= seconds then
					settle()
				end
			end)
		end
		local function arrive(key: K): ()
			settle()
			if entrance and arrived(key) then
				entrance:set(0)
				animate()
			end
		end
		if entering then
			animate()
		end
		local held: K? = nil
		local function follow(use: ComposeTypes.Use)
			local now = use(keyCell)
			local gone = held
			local arriving = gone ~= nil and gone ~= now
			if gone ~= nil and arriving then
				if mounted[gone] == node then
					mounted[gone], placed[gone], cellEdits[gone] = nil, nil, nil
				end
				if gui and State.belongsTo(gui.SelectedObject, node) then
					view.focusOwned = true
					gui.SelectedObject = nil
				end
			end
			if arriving then
				arrive(now)
			end
			held = now
			node.Name = tostring(now)
			mounted[now], placed[now], cellEdits[now] = node, placement, edits
			if arriving then
				if tree == nil and spec.disabled ~= nil then
					node.Interactable = not policy.disabled(spec.disabled, rowItem:peek())
				end
				mountedVersion:update(function(value)
					return value + 1
				end)
			end
		end
		if follows then
			Compose.watch(follow)
		else
			follow(function<T>(readable: ComposeTypes.ReadOnlyValue<T>): T
				return readable:peek()
			end)
		end
		local measureRow: ((ComposeTypes.Use, Vector2) -> ())? = nil
		local natural = false
		if spec.measure == nil and tree == nil and kind == "list" and read(spec.contentOverflow) ~= "clip" then
			local automatic = measuredNode.AutomaticSize
			natural = (
				automatic == E.AutomaticSize.XY
				or automatic == (if horizontal then E.AutomaticSize.X else E.AutomaticSize.Y)
			)
				and (
					measuredNode:FindFirstChildWhichIsA("UIListLayout") ~= nil
					or measuredNode:IsA("GuiButton")
					or measuredNode:IsA("TextLabel")
					or measuredNode:IsA("TextBox")
				)
		end
		if spec.measure or (tree and not tree.columnar) or natural then
			local inferred = spec.measure == nil and tree == nil
			local size = if inferred then nil else observe.AbsoluteSize(measuredNode)
			local lift = measuredNode:FindFirstChildWhichIsA("UIScale")
			local layoutUnit = if measuredNode:GetAttribute("FacetBody")
				then measuredNode:FindFirstChild("LayoutUnit")
				else nil
			local measurementUnit: Frame? = if lift
				then if layoutUnit and layoutUnit:IsA("Frame")
					then layoutUnit
					else Host.Frame {
						Name = "MeasurementUnit",
						Size = D2.fromOffset(1, 1),
						Visible = false,
					}
				else nil
			if measurementUnit then
				measurementUnit.Parent = measuredNode
			end
			local paintedSize = if measurementUnit then observe.AbsoluteSize(measurementUnit) else nil
			local factor = if lift then observe.Scale(lift) else nil
			local function measure(use: ComposeTypes.Use, box: Vector2?)
				use(keyCell)
				if spec.measure == nil and tree == nil then
					local automatic = measuredNode.AutomaticSize
					local axis = if horizontal then E.AutomaticSize.X else E.AutomaticSize.Y
					if automatic ~= axis and automatic ~= E.AutomaticSize.XY then
						return
					end
				end
				local ancestors = use(view.unitSize).X
				if ancestors <= 0 then
					ancestors = 1
				end
				local liftScale = if factor then use(factor) else 1
				local painted = if paintedSize then use(paintedSize).X else 0
				local scale = math.max(if painted > 0 then painted else liftScale * ancestors, 0.001)
				local dimensions = box or use(assert(size))
				local extent = (if horizontal then dimensions.X else dimensions.Y) / scale
					+ (if editor and not horizontal then use(editor.header) else 0)
					+ (if actionHeight and not horizontal then use(actionHeight) else 0)
				extent = math.round(extent)
				if spec.measure == nil and tree == nil and read(spec.contentOverflow, use) ~= "clip" then
					local estimate = read(spec.itemSize or 40, use)
					if type(estimate) == "number" then
						extent = math.max(estimate, extent)
					end
				end
				local previous = measured:peek()[keyCell:peek()]
				if previous and liftScale ~= 1 and math.abs(extent - previous) <= 1 then
					return
				end
				if extent > 0 and previous ~= extent then
					local nextSizes = table.clone(measured:peek())
					nextSizes[keyCell:peek()] = extent
					measured:set(nextSizes)
				end
			end
			if inferred then
				measureRow = measure
			else
				Compose.watch(function(use: ComposeTypes.Use)
					measure(use)
				end)
			end
		end
		local ready = Compose.withOwner(contentOwner, function()
			return preparePaint(
				ctx,
				if measureRow then measuredNode else content,
				measureRow,
				tree == nil and (spec.measure == true or measureRow ~= nil)
			)
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
		Compose.cleanup(function()
			live = false
			if gui and State.belongsTo(gui.SelectedObject, node) then
				view.focusOwned = true
				gui.SelectedObject = nil
			end
			if held ~= nil and mounted[held] == node then
				mounted[held], placed[held], cellEdits[held] = nil, nil, nil
			end
			view.slotKeys[node] = nil
			if preparing[node] then
				preparing[node] = nil
				waiting:update(function(value)
					return math.max(0, value - 1)
				end)
			end
			local nextRows = source(function<T>(cell: ComposeTypes.ReadOnlyValue<T>): T
				return cell:peek()
			end)
			local keyed = keysOf(nextRows)
			local wanted = held ~= nil and keyed.index[held] ~= nil
			local pendingReplacement = false
			if not wanted then
				local window = viewport:peek()
				for index, nextKey in keyed.keys do
					if mounted[nextKey] == nil then
						local locate = controls.placementOf
						local at = if locate then locate(index) else nil
						if
							spec.mode == "all"
							or window.size <= 0
							or (
								at ~= nil
								and at.offset + at.size > window.offset
								and at.offset < window.offset + window.size
							)
						then
							pendingReplacement = true
							break
						end
					end
				end
			end
			if
				not wanted
				and pendingReplacement
				and painted:peek()
				and not ComposeTypes.owner.isDisposed(poolOwner)
				and #nextRows > 0
			then
				parked = previousParent
				node.Parent = parked
				content.Interactable = false
				view.retiring[node] = release
			else
				release()
			end
		end)
		return node
	end
	local function orderedRows<T>(
		rows: ComposeTypes.OrderedCollectionOptions<T, K>,
		follow: CollectionTypes.Follow?
	): ComposeTypes.Child
		return Compose.OrderedCollection {
			from = rows.from,
			key = rows.key,
			mode = spec.mode or "windowed",
			direction = spec.direction or "vertical",
			viewport = viewport,
			status = status,
			controls = controls,
			overscan = spec.overscan or 2,
			measured = Compose.formula(function(use: ComposeTypes.Use)
				local sizes = fullSizes(use)
				return if tree
					then tree.sizes(
						use,
						sizes,
						read(spec.itemSize or 40, use) :: number,
						read<<number>>(spec.gap or 0, use)
					)
					else sizes
			end),
			follow = follow,
			followThreshold = spec.followThreshold,
			layout = function(use: ComposeTypes.Use)
				if spec.minColumns ~= nil then
					local least = read(spec.minColumns, use)
					assert(
						type(least) == "number"
							and spec.minColumnWidth ~= nil
							and spec.columns == nil
							and least >= 1
							and least % 1 == 0,
						"Facet minColumns needs minColumnWidth, a positive whole number and no columns"
					)
				end
				if spec.minColumnWidth ~= nil then
					local minimum = read(spec.minColumnWidth, use)
					assert(
						type(minimum) == "number"
							and kind == "grid"
							and spec.columns == nil
							and minimum > 0
							and minimum < math.huge,
						"Facet minColumnWidth needs a grid, a positive width and no columns"
					)
				end
				local columns = view.gridColumns(use, math.max(0, use(cross) - 2 * crossEdge(use)))
				local gap: number = read<<number>>(spec.gap or 0, use)
				local crossGap: number = read<<number>>(spec.crossGap or gap, use)
				return {
					kind = kind,
					columns = columns,
					itemSize = if view.cardsMode
						then (view.cardLayout(use))
						else read(spec.itemSize or 40, use) :: number,
					gap = if tree then 0 else gap,
					crossGap = crossGap,
					crossSize = math.max(0, (use(cross) - 2 * crossEdge(use) - crossGap * (columns - 1)) / columns),
				}
			end,
			recycle = rows.recycle,
			render = rows.render,
		}
	end
	local function render(
		current: ComposeTypes.ReadOnlyValue<V>,
		placement: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
		key: K
	): GuiObject
		return row(current, placement, Compose.cell(key), false)
	end
	local keys: { K } = {}
	return function(follow: CollectionTypes.Follow?): ComposeTypes.Child
		if slots then
			return orderedRows({
				from = slots.source,
				key = function(record: SlotRecord, _index: number): K
					return record.key
				end,
				render = slots.wrap(render),
			}, follow)
		end
		return orderedRows({
			from = function(use: ComposeTypes.Use): { V }
				local rows = source(use)
				keys = keysOf(rows).keys
				return rows
			end,
			key = function(_item: V, index: number): K
				return keys[index]
			end,
			render = if recycling then nil else render,
			recycle = if recycling
				then function(
					current: ComposeTypes.ReadOnlyValue<V>,
					placement: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
					key: ComposeTypes.ReadOnlyValue<K>
				): GuiObject
					return row(current, placement, key, true)
				end
				else nil,
		}, follow)
	end
end
