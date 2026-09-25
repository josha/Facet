--!strict
local reorder = require("./collection_reorder")
local policy = require("./collection_policy")
local createSelection = require("./collection_selection")
local attachSnap = require("./collection_snap")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
type Controls = {
	VirtualList: CollectionTypes.CollectionConstructor,
	VirtualGrid: CollectionTypes.CollectionConstructor,
	Button: Types.Constructor<InputTypes.ButtonProps, TextButton>,
}
type PooledRow = { node: Frame, owner: ComposeTypes.Owner }

return function(ctx: Types.Context, UI: Controls): ()
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local readSource = ctx.readSource
	local props, observe = ctx.props, ctx.observe
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local gui = ctx.config.guiService
	local behavior = {
		"from",
		"key",
		"render",
		"mode",
		"snap",
		"reducedMotion",
		"direction",
		"itemSize",
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
		"autoFocus",
		"wrapFocus",
		"disabled",
		"selection",
		"selectionMode",
		"selectable",
		"reorderable",
		"onReorder",
		"movable",
		"dragLabel",
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
		keyOf: (V, number) -> K
	): ScrollingFrame
		assert(
			spec.snap == nil or spec.snap == "none" or spec.snap == "item",
			"Facet collection snap must be none or item"
		)
		assert(type(spec.render) == "function", "Facet collection requires render(current, placement, key)")
		local source = function(use: ComposeTypes.Use): { V }
			return read(spec.from, use)
		end

		local viewport: ComposeTypes.Cell<ComposeTypes.OrderedCollectionViewport> =
			Compose.cell({ offset = 0, size = 0 })
		local cross, mountedVersion = Compose.cell(0), Compose.cell(0)
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
		local controls: ComposeTypes.OrderedCollectionControls<K> = spec.controls or {}
		local selection: ComposeTypes.Cell<CollectionTypes.Selection<K>> = spec.selection or Compose.cell({})
		local selectionMode: "none" | "single" | "multi" = spec.selectionMode
			or (if spec.selection or spec.onSelectionChange then "single" else "none")
		local selectRow, extendSelection = createSelection(ctx, spec, source, keyOf, controls, selection, selectionMode)
		local measured: ComposeTypes.Cell<{ [K]: number }> = Compose.cell({})
		local horizontal = spec.direction == "horizontal"
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
		local placed: { [K]: ComposeTypes.Readable<ComposeTypes.Placement> } = {}
		local poolOwner = assert(Compose.currentOwner()).createChild()
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
				record.node.Parent = nil
			end,
			destroy = function(record: PooledRow)
				record.owner.dispose()
			end,
		})
		local function edgeOf(gutter: Types.Value<number>?, use: ComposeTypes.Use?): number
			return if kind == "grid" then math.ceil(math.max(0, read(gutter or 0, use)) / 2) else 0
		end
		local function mainEdge(use: ComposeTypes.Use?): number
			return edgeOf(spec.gap, use)
		end
		local function crossEdge(use: ComposeTypes.Use?): number
			return edgeOf(spec.crossGap or spec.gap, use)
		end
		local function setOffset(requested: number): ()
			local edge = mainEdge()
			local offset = requested
			if edge > 0 then
				local current, box = status:peek(), viewport:peek()
				local last = if current and current.extent then current.extent - box.size else math.huge
				offset = if requested <= 0
					then 0
					elseif requested >= last then math.max(0, last + 2 * edge)
					else requested + edge
			end
			local position = root.CanvasPosition
			local nextPosition = if horizontal then V2.new(offset, position.Y) else V2.new(position.X, offset)
			if position ~= nextPosition then
				writingOffset = true
				root.CanvasPosition = nextPosition
				writingOffset = false
			end
		end
		local function select(key: K, current: ComposeTypes.Readable<V>, input: InputObject?, clicks: number?): ()
			if policy.disabled(spec.disabled, current:peek()) then
				return
			end
			local pointer = input ~= nil and input.UserInputType == E.UserInputType.MouseButton1
			local double = pointer and (clicks or 1) >= 2
			if not double then
				selectRow(key, current:peek(), input)
			end
			if spec.onActivate and (selectionMode == "none" or not pointer or double) then
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
			if node:IsA("GuiObject") then
				runtime.connect(node, "SelectionGained", function()
					captureSelection(node, key)
				end)
			end
			for _, child in node:GetChildren() do
				wireSelection(child, key)
			end
		end
		local wrapReorder: ((GuiObject, ComposeTypes.Readable<V>, K) -> Frame)?
		local overlayReorder: ((boolean?) -> Frame)?
		if spec.reorderable then
			wrapReorder, overlayReorder = reorder(ctx, UI, spec, source, keyOf, controls, function()
				return root
			end, selection, Compose.cell(nil :: CollectionTypes.Sort?))
		end
		local function orderedRows(follow: CollectionTypes.Follow?): ComposeTypes.Child
			return Compose.OrderedCollection({
				from = source,
				key = keyOf,
				mode = spec.mode or "windowed",
				direction = spec.direction or "vertical",
				viewport = viewport,
				status = status,
				controls = controls,
				overscan = spec.overscan or 2,
				measured = function(use: ComposeTypes.Use)
					if spec.measured ~= nil then
						local combined = table.clone(use(measured))
						for key, size in read(spec.measured, use) do
							combined[key] = size
						end
						return combined
					end
					return use(measured)
				end,
				follow = follow,
				followThreshold = spec.followThreshold,
				layout = function(use: ComposeTypes.Use)
					local columns = if kind == "grid" then math.max(1, math.floor(read(spec.columns or 1, use))) else 1
					local gap: number = read(spec.gap or 0, use)
					local crossGap: number = read(spec.crossGap or gap, use)
					return {
						kind = kind,
						columns = columns,
						itemSize = read(spec.itemSize or 40, use),
						gap = gap,
						crossGap = crossGap,
						crossSize = math.max(0, (use(cross) - 2 * crossEdge(use) - crossGap * (columns - 1)) / columns),
					}
				end,
				render = function(current, placement, key)
					local lease = pool.acquire()
					local node = runtime.borrow(lease.value.node) :: Frame
					runtime.decorate(node, {
						Name = tostring(key),
						Position = function(use: ComposeTypes.Use)
							local at = use(placement)
							return if horizontal
								then D2.fromOffset(at.offset, at.crossOffset)
								else D2.fromOffset(at.crossOffset, at.offset)
						end,
						Size = function(use: ComposeTypes.Use)
							local at = use(placement)
							return if horizontal
								then D2.fromOffset(at.size, at.crossSize)
								else D2.fromOffset(at.crossSize, at.size)
						end,
					})
					mounted[key] = node
					placed[key] = placement
					local stop, mountedContent = runtime.mount(function(): Frame
						local rendered = spec.render(current, placement, key)
						if wrapReorder then
							rendered = wrapReorder(rendered, current, key)
						end
						local children: Types.FrameProps = {
							Name = "Content",
							Size = D2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Attributes = { FacetCollectionRow = true } :: EngineTypes.Attributes,
							rendered,
						}
						if spec.onSelectionChange or spec.onActivate or spec.selection or spec.selectionMode then
							table.insert(
								children,
								1,
								Host.TextButton "RowHit" {
									AnchorPoint = V2.new(0.5, 0.5),
									Position = D2.fromScale(0.5, 0.5),
									Size = D2.fromScale(1, 1),
									Text = "",
									BackgroundTransparency = 1,
									Selectable = true,
									Interactable = function(use: ComposeTypes.Use)
										return not policy.disabled(spec.disabled, use(current))
									end,
									Activated = function(input: InputObject?, clicks: number?)
										select(key, current, input, clicks)
									end,
									Attributes = {
										FacetSelected = function(use: ComposeTypes.Use)
											return read(selection, use)[key] == true
										end,
									} :: EngineTypes.Attributes,
								}
							)
						end
						return Host.Frame(children)
					end, node)
					local content = mountedContent :: Frame
					wireSelection(content, key)
					if spec.measure then
						local measuredNode = content:GetChildren()[#content:GetChildren()] :: GuiObject
						local size: ComposeTypes.Cell<Vector2> = observe.AbsoluteSize(measuredNode)
						local lift = measuredNode:FindFirstChildWhichIsA("UIScale")
						local factor: ComposeTypes.Readable<number> = if lift
							then observe.Scale(lift)
							else Compose.cell(1)
						Compose.watch(function(use: ComposeTypes.Use)
							local scale = math.max(use(factor), 0.001)
							local extent = (if horizontal then use(size).X else use(size).Y) / scale
							if extent > 0 and measured:peek()[key] ~= extent then
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
						stop()
						lease.release()
					end)
					runtime.connect(node, "AncestryChanged", function()
						mountedVersion:update(function(value)
							return value + 1
						end)
					end)
					return node
				end,
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
			ScrollBarThickness = 6,
			SelectionGroup = true,
			CanvasSize = function(use: ComposeTypes.Use)
				local extent = use(contentExtent)
				return if horizontal then D2.fromOffset(extent, 0) else D2.fromOffset(0, extent)
			end,
		})
		table.insert(
			native,
			Compose.show(function(use: ComposeTypes.Use)
				return spec.mode == "all" or use(viewport).size > 0
			end, function()
				local nativeProps: Types.FrameProps =
					{ Name = "Items", BackgroundTransparency = 1, Size = D2.fromScale(1, 1), directive }
				if kind == "grid" then
					table.insert(
						nativeProps,
						Host.UIPadding({
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
					)
				end
				return Host.Frame(nativeProps)
			end)
		)
		root = ctx.styled(Host.ScrollingFrame(native), "Collection")
		root:SetAttribute("FacetSelectionOwner", true)
		if overlayReorder then
			runtime.mount(function()
				return overlayReorder(true)
			end, root)
		end
		local size: ComposeTypes.Cell<Vector2> = observe.AbsoluteWindowSize(root)
		local position: ComposeTypes.Cell<Vector2> = observe.CanvasPosition(root)
		Compose.watch(function(use: ComposeTypes.Use)
			local dimensions, at = use(size), use(position)
			local offset = math.max(0, (if horizontal then at.X else at.Y) - mainEdge(use))
			local extent = if horizontal then dimensions.X else dimensions.Y
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
				return policy.disabled(spec.disabled, item)
			end,
			initial = spec.initialFocus,
			autoFocus = spec.autoFocus,
			wrap = spec.wrapFocus,
			position = function(_, index)
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
			ctx.action(root, "Collection" .. binding.name, binding.keys, eligible, function()
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
		if spec.snap == "item" then
			attachSnap(ctx, spec, root, controls, status, viewport, setOffset, function()
				return writingOffset
			end)
		end
		return root
	end
	local function construct<V, K>(
		spec: CollectionTypes.CollectionSpec<V, K>,
		kind: ComposeTypes.OrderedCollectionLayoutKind
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
			(key :: unknown) :: (V, number) -> K
		)
	end
	local function list<V, K>(spec: CollectionTypes.CollectionSpec<V, K>): ScrollingFrame
		return construct(spec, "list")
	end
	local function grid<V, K>(spec: CollectionTypes.CollectionSpec<V, K>): ScrollingFrame
		return construct(spec, "grid")
	end

	UI.VirtualList = ctx.construct("VirtualList", list) :: CollectionTypes.CollectionConstructor
	UI.VirtualGrid = ctx.construct("VirtualGrid", grid) :: CollectionTypes.CollectionConstructor
end
