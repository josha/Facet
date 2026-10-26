--!strict
local activation = require("./activation")
local reorder = require("./collection_reorder")
local policy = require("./collection_policy")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local State = require("./collection_state")
return function<V, K>(
	ctx: Types.Context,
	view: State.View<V, K>,
	editor: reorder.Editor<V, K>?,
	root: ScrollingFrame,
	setOffset: (number) -> ()
): (ComposeTypes.FocusScope<K>, (ComposeTypes.Use) -> boolean)
	local Compose = ctx.Compose
	local read = ctx.read
	local readSource = ctx.readSource
	local observe = ctx.observe
	local E = ctx.types.Enum
	local gui = ctx.config.guiService
	local input = ctx.config.userInputService
	local belongsTo, findSelectable = State.belongsTo, State.findSelectable
	local spec, kind, keyOf, tree = view.spec, view.kind, view.keyOf, view.tree
	local source, viewport, mountedVersion = view.source, view.viewport, view.mountedVersion
	local status, controls = view.status, view.controls
	local horizontal, focusActive = view.horizontal, view.focusActive
	local nodeOf = view.nodeOf
	local restoring = false
	local focusGeometry = Compose.formula(function(use: ComposeTypes.Use)
		use(mountedVersion)
		for _, placement in view.placed do
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
				return view.noFocusCandidates
			end
			if kind == "list" then
				return source(use)
			end
			use(focusGeometry)
			use(view.cross)
			use(view.measured)
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
			return if horizontal then at.offset else at.crossOffset, if horizontal then at.crossOffset else at.offset
		end,
	})
	view.scope = focusScope
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
		if lost == nil or key == lost or not view.focusOwned then
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
	local focusPosition = observe.AbsolutePosition(root)
	local focusSize = observe.AbsoluteSize(root)
	local function restoreFocus(key: K?): ()
		if
			gui == nil
			or root.Parent == nil
			or not view.focusOwned
			or key == nil
			or nodeOf(key) == nil
			or not belongsTo(nodeOf(key), root)
		then
			return
		end
		local node = findSelectable(assert(nodeOf(key)), view.focusedPath, 1)
		if node and policy.selectionVisible(node) then
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
		view.focusOwned = true
		local arm = view.armPaging
		if arm then
			Compose.sample(function(): boolean
				arm()
				return true
			end)
		end
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
		use(focusPosition)
		use(focusSize)
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
		for node, held in view.slotKeys do
			local key = held:peek()
			if field:IsDescendantOf(node) then
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
		for candidate in readSource(view.selection, use) do
			if key ~= nil then
				return nil
			end
			key = candidate
		end
		key = key or readSource(focusScope.current, use)
		local edits = if key ~= nil then view.cellEdits[key] else nil
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
				for row, held in view.slotKeys do
					local key = held:peek()
					if belongsTo(node, row) then
						local neighbour = neighbourOf(key)
						if neighbour ~= nil then
							view.focusOwned = true
							focusScope.focus(neighbour)
							restoreFocus(neighbour)
						end
						break
					end
				end
			else
				local lost = lastFocused or focusScope.current:peek()
				local neighbour = if view.focusOwned and lost ~= nil then neighbourOf(lost) else nil
				if neighbour ~= nil and nodeOf(neighbour) then
					focusScope.focus(neighbour)
					restoreFocus(neighbour)
				else
					view.focusOwned = false
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
		if key ~= nil and nodeOf(key) then
			target = findSelectable(assert(nodeOf(key)), nil, 1)
		end
		if target == nil then
			local rows: { V } = read(spec.from) or {}
			for index, item in rows do
				local candidate = keyOf(item, index)
				if nodeOf(candidate) and not policy.disabled(spec.disabled, item) then
					target = findSelectable(assert(nodeOf(candidate)), nil, 1)
					if target then
						break
					end
				end
			end
		end
		if target and policy.selectionVisible(target) then
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
	return focusScope, eligible
end
