--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Collections = require("./collection_types")
local Inputs = require("./input_types")
local motion = require("./motion")
local policy = require("./collection_policy")
local sessionOf = require("./drag_session")

type Node<V, K> = { item: V, key: K, parent: K?, depth: number, branch: boolean, visible: boolean }
type Snapshot<V, K> = {
	nodes: { Node<V, K> },
	byKey: { [K]: Node<V, K> },
	changing: { Node<V, K> },
	groups: { { Node<V, K> } },
	start: number,
	weights: { [K]: number },
}
export type Tree<V, K> = {
	from: ComposeTypes.Readable<{ V }>,
	all: ComposeTypes.Readable<{ V }>,
	columnar: boolean?,
	visible: (K, ComposeTypes.Use?) -> boolean,
	ancestor: (K) -> K?,
	sizes: (ComposeTypes.Use, { [K]: number }, number, number) -> { [K]: number },
	wrap: (GuiObject, ComposeTypes.Readable<V>, K) -> GuiObject,
	bind: (ScrollingFrame, Collections.FocusControls<K>) -> (),
	toggle: (K) -> (),
	location: ({ K }, number) -> (boolean, number, K?),
}

return function<V, K>(
	ctx: Types.Context,
	UI: { Button: Types.Constructor<Inputs.ButtonProps, TextButton> },
	spec: Collections.HierarchyOptions<V, K> & {
		from: Types.Value<{ V }>,
		disabled: Collections.RowPredicate<V>?,
		reducedMotion: Types.ValueBoolean?,
	},
	keyOf: (V, number) -> K,
	order: (({ V }, ComposeTypes.Use) -> { V })?
): Tree<V, K>
	local C, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local expanded: ComposeTypes.Cell<Collections.Selection<K>> = spec.expanded
		or C.cell({} :: Collections.Selection<K>)
	assert(expanded.set, "Facet outline expanded requires a writable Compose cell")
	assert(type(spec.children) == "function" or type(spec.children) == "string", "Facet outline requires children")
	local reduced = motion.reduced(ctx)
	local timing = ctx.motionTiming("reveal")
	local inputKind = ctx.effectiveInput()
	local function targetFloor(use: ComposeTypes.Use?): number
		return if inputKind(use) == "KeyboardAndMouse" then 0 else ctx.metric("targetSizes.minimum", use)
	end
	local clockTarget = C.cell(0)
	local clock = runtime.tween(function(use: ComposeTypes.Use): number
		return use(clockTarget)
	end, {
		seconds = timing.enter,
		ease = ctx.motionEase("present"),
		reducedMotion = function(use: ComposeTypes.Use): boolean
			return reduced(use) or read(spec.reducedMotion, use) == true
		end,
	})
	local data =
		C.cell({ nodes = {}, byKey = {}, changing = {}, groups = {}, weights = {}, start = -1 } :: Snapshot<V, K>)
	local settled = C.formula(function(use: ComposeTypes.Use): boolean
		return reduced(use) or read(spec.reducedMotion, use) == true or use(clock) >= use(data).start + 1
	end)
	local animatedWeights = C.formula(function(use: ComposeTypes.Use): { [K]: number }
		local current = use(data)
		local result: { [K]: number } = {}
		if use(settled) then
			return result
		end
		local progress = math.clamp(use(clock) - current.start, 0, 1)
		for _, group in current.groups do
			local previous = 0
			for _, node in group do
				previous += current.weights[node.key] or 0
			end
			local destination = if group[1].visible then #group else 0
			local extent = previous + (destination - previous) * progress
			for index, node in group do
				result[node.key] = math.clamp(extent - index + 1, 0, 1)
			end
		end
		return result
	end)
	local function weight(key: K, use: ComposeTypes.Use?): number
		local current = if use then use(data) else data:peek()
		local node = current.byKey[key]
		if not node then
			return 0
		end
		local destination = if node.visible then 1 else 0
		local weights = read(animatedWeights, use)
		return if weights[key] ~= nil then weights[key] else destination
	end
	local initialized = false
	local priorExpanded = expanded:peek()
	C.watch(function(use: ComposeTypes.Use)
		local open = use(expanded)
		local expansionChanged = initialized and open ~= priorExpanded
		priorExpanded = open
		local nodes: { Node<V, K> }, byKey: { [K]: Node<V, K> } = {}, {}
		local function visit(items: { V }, parent: K?, depth: number, visible: boolean)
			local ordered: { V } = if order then order(items, use) else items
			for index, item in ordered do
				local key = keyOf(item, index)
				assert(key ~= nil and byKey[key] == nil, "Facet outline requires unique keys and an acyclic tree")
				local accessor = spec.children
				local children = if type(accessor) == "function"
					then accessor(item)
					else ((item :: unknown) :: { [string]: { V }? })[accessor :: string]
				assert(children == nil or type(children) == "table", "Facet outline children must be an array or nil")
				local node = {
					item = item,
					key = key,
					parent = parent,
					depth = depth,
					branch = children ~= nil,
					visible = visible,
				}
				byKey[key] = node
				table.insert(nodes, node)
				if children then
					visit(children, key, depth + 1, visible and open[key] == true)
				end
			end
		end
		visit(read(spec.from, use), nil, 0, true)
		local weights: { [K]: number } = {}
		local changing: { Node<V, K> } = {}
		local groups: { { Node<V, K> } } = {}
		local group: { Node<V, K> }? = nil
		for _, node in nodes do
			weights[node.key] = if expansionChanged and data:peek().byKey[node.key] ~= nil
				then weight(node.key)
				else if node.visible then 1 else 0
			if weights[node.key] ~= (if node.visible then 1 else 0) then
				table.insert(changing, node)
				if group == nil or group[1].visible ~= node.visible then
					local nextGroup: { Node<V, K> } = {}
					group = nextGroup
					table.insert(groups, nextGroup)
				end
				table.insert(assert(group), node)
			else
				group = nil
			end
		end
		local start = if #changing > 0 then clock:peek() else -1

		data:set({
			nodes = nodes,
			byKey = byKey,
			changing = changing,
			groups = groups,
			weights = weights,
			start = start,
		})
		if #changing > 0 then
			clockTarget:set(start + 1)
		end
		initialized = true
	end)
	local function change(key: K, value: boolean)
		local node = data:peek().byKey[key]
		if not node or not node.branch or policy.disabled(spec.disabled, node.item) then
			return
		end
		local nextOpen = table.clone(expanded:peek())
		if value then
			nextOpen[key] = true
		else
			nextOpen[key] = nil
		end
		if spec.onExpansionChange then
			spec.onExpansionChange(nextOpen)
		else
			expanded:set(nextOpen)
		end
	end
	local locatedSnapshot: Snapshot<V, K>? = nil
	local locatedRows: { V }? = nil
	local locatedKeys: { K }? = nil
	local remainingKeys: { K } = {}
	local siblingSlots: { [K]: number } = {}
	local remainingSiblings = 0
	local tree: Tree<V, K>
	tree = {
		from = C.formula(function(use: ComposeTypes.Use): { V }
			local rows = {}
			local snapshot, weights = use(data), use(animatedWeights)
			for _, node in snapshot.nodes do
				if if weights[node.key] ~= nil then weights[node.key] > 0 else node.visible then
					table.insert(rows, node.item)
				end
			end
			return rows
		end),
		all = C.formula(function(use: ComposeTypes.Use): { V }
			local rows = {}
			for _, node in use(data).nodes do
				table.insert(rows, node.item)
			end
			return rows
		end),
		visible = function(key: K, use: ComposeTypes.Use?): boolean
			local snapshot = if use then use(data) else data:peek()
			local node = snapshot.byKey[key]
			return node ~= nil and node.visible
		end,
		ancestor = function(key: K): K?
			local snapshot = data:peek()
			local node: Node<V, K>? = snapshot.byKey[key]
			if not node or node.visible then
				return nil
			end
			while node and not node.visible do
				node = if node.parent ~= nil then snapshot.byKey[node.parent] else nil
			end
			return if node then node.key else nil
		end,
		sizes = function(use: ComposeTypes.Use, sizes: { [K]: number }, minimum: number, gap: number): { [K]: number }
			local result = {}
			local snapshot = use(data)
			for key, size in sizes do
				if snapshot.byKey[key] and snapshot.byKey[key].visible then
					result[key] = math.max(minimum, size) + gap
				end
			end
			if gap > 0 then
				for _, node in snapshot.nodes do
					if node.visible and result[node.key] == nil then
						result[node.key] = minimum + gap
					end
				end
			end
			if not use(settled) then
				for _, node in snapshot.changing do
					result[node.key] = (math.max(minimum, sizes[node.key] or minimum) + gap) * weight(node.key, use)
				end
			end
			return result
		end,
		toggle = function(key: K)
			change(key, expanded:peek()[key] ~= true)
		end,
		location = function(keys: { K }, slot: number): (boolean, number, K?)
			local snapshot = data:peek()
			local first = snapshot.byKey[keys[1]]
			if not first then
				return false, 0, nil
			end
			local parent, carried = first.parent, {}
			for _, key in keys do
				local node = snapshot.byKey[key]
				if not node or node.parent ~= parent then
					return false, 0, nil
				end
				carried[key] = true
			end
			local rows = tree.from:peek()
			if snapshot ~= locatedSnapshot or rows ~= locatedRows or keys ~= locatedKeys then
				locatedSnapshot, locatedRows, locatedKeys = snapshot, rows, keys
				remainingKeys, siblingSlots, remainingSiblings = {}, {}, 0
				for _, item in rows do
					local key = keyOf(item, 1)
					if not carried[key] then
						table.insert(remainingKeys, key)
					end
				end
				for _, node in snapshot.nodes do
					siblingSlots[node.key] = remainingSiblings
					if node.parent == parent and not carried[node.key] then
						remainingSiblings += 1
					end
				end
			end
			local remaining = remainingKeys
			local before = remaining[slot + 1]
			local target = if before ~= nil then snapshot.byKey[before] else nil
			if target == nil or target.parent ~= parent then
				if target and target.depth > first.depth then
					return false, 0, nil
				end
				local previousKey = remaining[slot]
				local previous = if previousKey ~= nil then snapshot.byKey[previousKey] else nil
				while previous and previous.key ~= parent and previous.parent ~= parent do
					previous = if previous.parent ~= nil then snapshot.byKey[previous.parent] else nil
				end
				if parent ~= nil and previous == nil then
					return false, 0, nil
				end
			end
			return true, if before ~= nil then siblingSlots[before] else remainingSiblings, parent
		end,
		wrap = function(content: GuiObject, current: ComposeTypes.Readable<V>, key: K): GuiObject
			local natural, authored, automatic =
				ctx.observe.AbsoluteSize(content), ctx.observe.Size(content), ctx.observe.AutomaticSize(content)
			local unit = Host.Frame { Name = "OutlineUnit", Size = D2.fromOffset(1, 1), Visible = false }
			local unitSize = ctx.observe.AbsoluteSize(unit)
			local function scale(use: ComposeTypes.Use): number
				return if use(unitSize).X > 0 then use(unitSize).X else 1
			end
			local function side(use: ComposeTypes.Use): number
				return math.max(ctx.controlSize("compact", "height", use), targetFloor(use))
			end

			local width = C.cell(0)
			local function left(use: ComposeTypes.Use): number
				local node = use(data).byKey[key]
				local step = read(spec.indent, use) or ctx.metric("space.l", use)
				assert(step >= 0 and step < math.huge, "Facet outline indent must be a finite non-negative number")
				return ctx.metric("space.s", use)
					+ math.min((if node then node.depth else 0) * step, math.max(0, use(width) - side(use) * 3))
			end
			local disclosure = C.show(function(use: ComposeTypes.Use): boolean
				local node = use(data).byKey[key]
				return node ~= nil and node.branch
			end, function()
				local angle = runtime.tween(function(use: ComposeTypes.Use): number
					return if use(expanded)[key] then 90 else 0
				end, {
					seconds = timing.enter,
					ease = ctx.motionEase("present"),
					reducedMotion = function(use: ComposeTypes.Use): boolean
						return reduced(use) or read(spec.reducedMotion, use) == true
					end,
				})
				local button = UI.Button {
					Name = "Disclosure",
					name = function(use: ComposeTypes.Use): string
						return if use(expanded)[key] then "Collapse" else "Expand"
					end,
					controlSize = "compact" :: "compact",
					icon = "chevron.trailing",
					appearance = "utility",
					Visible = function(use: ComposeTypes.Use): boolean
						local node = use(data).byKey[key]
						return node ~= nil and node.branch
					end,
					enabled = function(use: ComposeTypes.Use): boolean
						return tree.visible(key, use) and not policy.disabled(spec.disabled, use(current))
					end,
					onActivate = function()
						tree.toggle(key)
					end,
				}
				local caret = button:FindFirstChild("Content")
				if caret and caret:IsA("GuiObject") then
					runtime.decorate(caret, { Rotation = angle })
				end
				runtime.decorate(button, {
					AutomaticSize = E.AutomaticSize.None,
					AnchorPoint = V2.new(0, 0.5),
					Position = function(use: ComposeTypes.Use): UDim2
						return D2.new(0, left(use), 0.5, 0)
					end,
					Size = function(use: ComposeTypes.Use): UDim2
						local size = math.max(ctx.controlSize("compact", "height", use), targetFloor(use))
						return D2.fromOffset(size, size)
					end,
				})
				return button
			end)
			local root = Host.Frame {
				Name = "OutlineRow",
				AnchorPoint = V2.new(0, 0.5),
				Position = D2.fromScale(0, 0.5),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Size = function(use: ComposeTypes.Use): UDim2
					local auto, size = use(automatic), use(authored)
					local height = if auto == E.AutomaticSize.Y
							or auto == E.AutomaticSize.XY
							or size.Y.Scale == 0
						then use(natural).Y / scale(use)
						else 0
					return D2.new(
						1,
						0,
						0,
						math.max(side(use), height) + ctx.metric("space.xs", use) + ctx.metric("space.xs", use)
					)
				end,
				disclosure :: ComposeTypes.Child,
				unit :: ComposeTypes.Child,
				Host.Frame {
					Name = "OutlineContent",
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					Position = function(use: ComposeTypes.Use): UDim2
						return D2.fromOffset(left(use) + side(use), ctx.metric("space.xs", use))
					end,
					Size = function(use: ComposeTypes.Use): UDim2
						return D2.new(
							1,
							-left(use) - side(use) - ctx.metric("space.s", use),
							1,
							-ctx.metric("space.xs", use) - ctx.metric("space.xs", use)
						)
					end,
					Host.UIListLayout {
						FillDirection = E.FillDirection.Vertical,
						VerticalAlignment = E.VerticalAlignment.Center,
						SortOrder = E.SortOrder.LayoutOrder,
					} :: ComposeTypes.Child,
					content :: ComposeTypes.Child,
				},
			}
			local bounds = ctx.observe.AbsoluteSize(root)
			C.watch(function(use: ComposeTypes.Use)
				width:set(use(bounds).X / scale(use))
				local node = use(data).byKey[key]
				root:SetAttribute("FacetOutlineDepth", if node then node.depth else 0)
				root:SetAttribute("FacetExpanded", use(expanded)[key] == true)
			end)
			return root
		end,
		bind = function(root: ScrollingFrame, controls: Collections.FocusControls<K>)
			local gui = ctx.config.guiService
			local selected = if gui then ctx.observe.SelectedObject(gui) else C.cell(nil :: GuiObject?)
			local drag = sessionOf(ctx)
			local function enabled(use: ComposeTypes.Use): boolean
				local selected = use(selected)
				local session = use(drag.state)
				return (session == nil or (session.mode == "armed" and not session.pending))
					and selected ~= nil
					and selected:IsDescendantOf(root)
					and (selected.Name == "RowHit" or selected.Name == "Disclosure")
			end
			local function current(use: ComposeTypes.Use): Node<V, K>?
				local key = if controls.current then use(controls.current) else nil
				return if key ~= nil then use(data).byKey[key] else nil
			end
			local function expands(use: ComposeTypes.Use): boolean
				local node = current(use)
				return enabled(use) and node ~= nil and node.branch == true
			end
			local function collapses(use: ComposeTypes.Use): boolean
				local node = current(use)
				return enabled(use)
					and node ~= nil
					and ((node.branch == true and use(expanded)[node.key] == true) or node.parent ~= nil)
			end
			ctx.action(root, "OutlineExpand", { E.KeyCode.Right, E.KeyCode.DPadRight }, expands, function()
				local key = controls.current and controls.current:peek()
				local node = if key ~= nil then data:peek().byKey[key] else nil
				if node and node.branch then
					if not expanded:peek()[node.key] then
						change(node.key, true)
					elseif controls.focus then
						for _, child in data:peek().nodes do
							if child.parent == node.key and not policy.disabled(spec.disabled, child.item) then
								controls.focus(child.key)
								break
							end
						end
					end
				end
			end, { priority = 300, capture = true })
			ctx.action(root, "OutlineCollapse", { E.KeyCode.Left, E.KeyCode.DPadLeft }, collapses, function()
				local key = controls.current and controls.current:peek()
				local node = if key ~= nil then data:peek().byKey[key] else nil
				if node then
					if node.branch and expanded:peek()[node.key] then
						change(node.key, false)
					elseif node.parent ~= nil and controls.focus then
						controls.focus(node.parent)
					end
				end
			end, { priority = 300, capture = true })
		end,
	}
	return tree
end
