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
return function<V, K>(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	view: State.View<V, K>,
	editor: reorder.Editor<V, K>?,
	slots: Slots.Slots<V, K>
): (CollectionTypes.Follow?) -> ComposeTypes.Child
	type SlotRecord = Slots.Slot<V, K>
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local readSource = ctx.readSource
	local observe = ctx.observe
	local D2, D, V2, E = ctx.types.UDim2, ctx.types.UDim, ctx.types.Vector2, ctx.types.Enum
	local gui = ctx.config.guiService
	local spec, tree = view.spec, view.tree
	local kind: ComposeTypes.OrderedCollectionLayoutKind = view.kind
	local source, viewport, cross = view.source, view.viewport, view.cross
	local mountedVersion, status, controls, selection = view.mountedVersion, view.status, view.controls, view.selection
	local coordinator, selectionMode = view.coordinator, view.selectionMode
	local measured, containsCards, horizontal = view.measured, view.containsCards, view.horizontal
	local reduced, focusActive = view.reduced, view.focusActive
	local liveOverflow = Compose.isReadable(spec.contentOverflow) or type(spec.contentOverflow) == "function"
	local mounted, cellEdits, placed, poolOwner = view.mounted, view.cellEdits, view.placed, view.poolOwner
	local preparing, waiting = view.preparing, view.waiting
	local crossEdge, fullSizes = view.crossEdge, view.fullSizes
	local slotSource, withSlots = slots.source, slots.wrap
	local keyedRows = setmetatable({} :: { [{ V }]: { keys: { K }, index: { [K]: number } } }, { __mode = "k" })
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
	local function wireSelection(node: Instance, key: ComposeTypes.Readable<K>): ()
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
	local function row(
		rowItem: ComposeTypes.Readable<V>,
		rowPlacement: ComposeTypes.Readable<ComposeTypes.Placement>,
		keyCell: ComposeTypes.Readable<K>,
		follows: boolean
	): GuiObject
		local lease = view.pool.acquire()
		local node = runtime.borrow(lease.value.node) :: Frame
		local contentOwner = poolOwner.createChild()
		local function retained<T>(row: ComposeTypes.Readable<T>): ComposeTypes.Readable<T>
			local held = Compose.withOwner(contentOwner, function(): ComposeTypes.Cell<T>
				return Compose.cell(row:peek())
			end)
			Compose.watch(function(use: ComposeTypes.Use)
				held:set(use(row))
			end)
			return held
		end
		local current, placement = retained(rowItem), retained(rowPlacement)
		local springPlacement = spec.slots ~= nil or spec.drag ~= nil or spec.drop ~= nil
		local reservedPosition: ComposeTypes.Readable<Vector2>? = nil
		local glide: ComposeTypes.Cell<number>? = nil
		if editor and (spec.reorderable or spec.drag) then
			reservedPosition = editor.position(keyCell:peek(), placement, spec.reducedMotion)
		elseif springPlacement then
			local position = Compose.cell(V2.new(placement:peek().crossOffset, placement:peek().offset))
			reservedPosition = position
			local target: ComposeTypes.Readable<ComposeTypes.Placement> = if editor
					and (spec.drag or spec.drop)
				then Compose.formula(function(use: ComposeTypes.Use): ComposeTypes.Placement
					return editor.placement(use(keyCell), use(placement), use)
				end)
				else placement
			local engine = travelEngine(ctx, {
				initial = { placement:peek().crossOffset, placement:peek().offset },
				target = function()
					local at = target:peek()
					return { at.crossOffset, at.offset }
				end,
				sample = function(values)
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
		Compose.withOwner(contentOwner, function()
			runtime.decorate(node, {
				Name = tostring(keyCell:peek()),
				ClipsDescendants = tree ~= nil,
				Interactable = if tree == nil and spec.disabled == nil
					then true
					else function(use: ComposeTypes.Use)
						return (tree == nil or tree.visible(use(keyCell), use))
							and not policy.disabled(spec.disabled, use(current))
					end,
			})
			Compose.watch(function(use: ComposeTypes.Use)
				local at = use(placement)
				local main, cross = at.offset + (if glide then use(glide) else 0), at.crossOffset
				if reservedPosition then
					local position = use(reservedPosition)
					main, cross = position.Y, position.X
				end
				node.LayoutOrder = at.index
				node.Position = if horizontal then D2.fromOffset(main, cross) else D2.fromOffset(cross, main)
				node.Size = if horizontal
					then D2.fromOffset(at.size, at.crossSize)
					else D2.fromOffset(at.crossSize, at.size)
			end)
		end)
		local edits: { activation.EditAction } = {}
		local measuredNode: GuiObject
		local actionHeight: ComposeTypes.Readable<number>? = nil
		local painted = Compose.cell(false)
		local stop, mountedContent = Compose.withOwner(contentOwner, function()
			return runtime.mount(function(): CanvasGroup
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
				for _, edit in activation.edits(rendered) do
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
						kind == "grid"
					)
				end
				if editor then
					rendered = editor.wrap(rendered, current, keyCell:peek())
					local press = editor.press
					Compose.cleanup(activation.providePress(rendered, function(value: InputObject)
						press(keyCell:peek(), value)
					end))
				end
				local children: Types.FrameProps = {
					Name = "Content",
					Size = if tree
						then function(use: ComposeTypes.Use): UDim2
							local minimum = read(spec.itemSize or 40, use)
							assert(type(minimum) == "number", "Facet.Outline requires a numeric itemSize")
							local extent = use(measured)[use(keyCell)]
							if spec.measured ~= nil then
								local external = read(spec.measured, use)[use(keyCell)]
								if external ~= nil then
									extent = external
								end
							end
							return D2.new(1, 0, 0, math.max(minimum, extent or 0))
						end
						else D2.fromScale(1, 1),
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
						AnchorPoint = V2.new(0.5, 0.5),
						Position = D2.fromScale(0.5, 0.5),
						Size = D2.fromScale(1, 1),
						Text = "",
						BackgroundTransparency = 1,
						Selectable = true,
						Interactable = function(use: ComposeTypes.Use)
							return (tree == nil or tree.visible(use(keyCell), use))
								and not policy.disabled(spec.disabled, use(current))
						end,
						Activated = function(input: InputObject?, clicks: number?)
							if not activation.intercepted(hit, input) then
								select(keyCell:peek(), current, input, clicks)
							end
						end,
						Attributes = {
							FacetSelectionRequired = selectionMode ~= "none",
							FacetOnlySelected = function(use: ComposeTypes.Use)
								return use(view.onlySelected) == use(keyCell)
							end,
							FacetSelected = function(use: ComposeTypes.Use)
								return read(selection, use)[use(keyCell)] == true
							end,
						} :: EngineTypes.Attributes,
					}
					Compose.cleanup(activation.provide(hit, function(input: unknown, clicks: unknown)
						if not activation.intercepted(hit, input) then
							select(keyCell:peek(), current, input :: InputObject?, clicks :: number?)
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
				local carded = tree == nil
					and rendered:GetAttribute("FacetBody") ~= nil
					and read(spec.contentOverflow) ~= "clip"
				local paintSelection = spec.selectionIndicator ~= false and selectionMode ~= "none"
				if paintSelection and not carded then
					children.BackgroundTransparency = nil
				end
				local groupProperties = (children :: unknown) :: Types.CanvasGroupNativeProps
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
					children.AutomaticSize = E.AutomaticSize.XY
					surface = Host.Frame(children)
					local function crossPadding(use: ComposeTypes.Use): UDim
						local x = edges(use)
						return D.new(0, x)
					end
					local function mainPadding(use: ComposeTypes.Use): UDim
						local _, y = edges(use)
						return D.new(0, y)
					end
					groupProperties = {
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
				end
				groupProperties.GroupTransparency = function(use: ComposeTypes.Use): number
					return if use(painted) then 0 else 1
				end
				groupProperties.AutomaticSize = if read(spec.contentOverflow) == "clip"
					then E.AutomaticSize.None
					else E.AutomaticSize.XY
				local content = Host.CanvasGroup(groupProperties)
				local logical = surface or content
				policy.drop(ctx, spec, current, keyCell:peek(), logical, kind == "grid" or horizontal)
				if paintSelection and not carded then
					ctx.styled(logical, "TableRow")
					if kind == "grid" or horizontal then
						ctx.skin(logical, "control", {
							selected = function(use: ComposeTypes.Use): boolean
								return use(selection)[use(keyCell)] == true
							end,
						})
					end
				end
				if paintSelection then
					Compose.watch(function(use: ComposeTypes.Use)
						if use(selection)[use(keyCell)] == true then
							logical:AddTag("facet-selected")
						else
							logical:RemoveTag("facet-selected")
						end
					end)
				end
				return content
			end, node)
		end)
		local content = mountedContent :: CanvasGroup
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
		wireSelection(content, keyCell)
		view.slotKeys[node] = keyCell
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
			follow(function<T>(readable: ComposeTypes.Readable<T>): T
				return readable:peek()
			end)
		end
		local measureRow: ((ComposeTypes.Use, Vector2) -> ())? = nil
		local automatic = measuredNode.AutomaticSize
		local natural = (
			measuredNode:FindFirstChildWhichIsA("UIListLayout") ~= nil
			or measuredNode:IsA("GuiButton")
			or measuredNode:IsA("TextLabel")
			or measuredNode:IsA("TextBox")
		)
			and (automatic == E.AutomaticSize.XY or automatic == (if horizontal
				then E.AutomaticSize.X
				else E.AutomaticSize.Y))
			and read(spec.contentOverflow) ~= "clip"
		if
			spec.measure
			or (tree and not tree.columnar)
			or (spec.measure == nil and tree == nil and kind == "list" and natural)
		then
			local inferred = spec.measure == nil and tree == nil
			local size = if inferred then nil else observe.AbsoluteSize(measuredNode)
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
				spec.measure == true or measureRow ~= nil
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
			local nextRows = source(function<T>(cell: ComposeTypes.Readable<T>): T
				return cell:peek()
			end)
			local keyed = keysOf(nextRows)
			local wanted = held ~= nil and keyed.index[held] ~= nil
			local pendingReplacement = false
			if not wanted then
				local window = viewport:peek()
				for index, nextKey in keyed.keys do
					if mounted[nextKey] == nil then
						local at = if controls.placementOf then controls.placementOf(index) else nil
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
				and not poolOwner.isDisposed()
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
		runtime.connect(node, "AncestryChanged", function()
			mountedVersion:update(function(value)
				return value + 1
			end)
		end)
		return node
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
				if spec.minColumns ~= nil then
					local least = read(spec.minColumns, use)
					assert(
						spec.minColumnWidth ~= nil and spec.columns == nil and least >= 1 and least % 1 == 0,
						"Facet minColumns needs minColumnWidth, a positive whole number and no columns"
					)
				end
				if spec.minColumnWidth ~= nil then
					local minimum = read(spec.minColumnWidth, use)
					assert(
						kind == "grid" and spec.columns == nil and minimum > 0 and minimum < math.huge,
						"Facet minColumnWidth needs a grid, a positive width and no columns"
					)
				end
				local columns = view.gridColumns(use, math.max(0, use(cross) - 2 * crossEdge(use)))
				local gap: number = read(spec.gap or 0, use)
				local crossGap: number = read(spec.crossGap or gap, use)
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
			recycle = if recycling
				then function(
					record: ComposeTypes.Readable<SlotRecord>,
					rowPlacement: ComposeTypes.Readable<ComposeTypes.Placement>,
					keyCell: ComposeTypes.Readable<K>
				): GuiObject
					return row(
						Compose.formula(function(use: ComposeTypes.Use): V
							return assert(use(record).item)
						end),
						rowPlacement,
						keyCell,
						true
					)
				end
				else nil,
			render = if recycling
				then nil
				else withSlots(
					function(
						rowItem: ComposeTypes.Readable<V>,
						rowPlacement: ComposeTypes.Readable<ComposeTypes.Placement>,
						key: K
					): GuiObject
						return row(rowItem, rowPlacement, Compose.cell(key), false)
					end
				),
		})
	end
	return orderedRows
end
