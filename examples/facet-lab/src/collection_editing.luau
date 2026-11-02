--!strict
local Types = require("./catalog_types")
type Row = { id: string, name: string, kind: string, parent: string? }
type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type Draft = { text: string, original: unknown, error: string? }
type Undo = { rows: { Row }, selection: { [string]: boolean } }

return function(c: Types.Context, kind: string)
	local UI, C = c.UI, c.Compose
	local D2, E = c.types.UDim2, c.types.Enum
	local initial: { Row } = {}
	for i, name in { "Coast", "Canyon", "Forest", "City", "Glacier", "Harbour" } do
		initial[i] = { id = tostring(i), name = name, kind = if i % 3 == 0 then "Material" else "Image" }
	end
	if kind == "Outline" then
		for index = 4, 6 do
			initial[index].parent = "folder"
		end
		table.insert(initial, 1, { id = "folder", name = "Championship", kind = "Folder" })
	end
	local rows: Value<{ Row }> = c.cell("editingRows", initial)
	local expanded: Value<{ [string]: boolean }> = c.cell("editingExpanded", { folder = true })
	local function children(parent: string?, all: { Row }): { Row }
		local result: { Row } = {}
		for _, item in all do
			if item.parent == parent then
				table.insert(result, item)
			end
		end
		return result
	end
	local selection: Value<{ [string]: boolean }> = c.cell("editingSelection", {})
	local enabled: Value<boolean> = c.cell("editingEnabled", true)
	local editing: Value<boolean> = c.cell("editingMode", false)
	local cellsEnabled: Value<boolean> = c.cell("cellEditingEnabled", true)
	local serial: Value<number> = c.cell("editingSerial", 6)
	local noUndo: Undo? = nil
	local undo: Value<Undo?> = c.cell("editingUndo", noUndo)
	local noDraft: Draft? = nil
	local drafts: { [string]: Value<Draft?> } = c.cell("editingDrafts", {}):peek()
	local env = UI.environment()
	local function coarse(use: Use)
		return use(env.effectiveInput) ~= "KeyboardAndMouse"
	end
	local function editable(use: Use)
		return use(cellsEnabled)
	end
	local function save(nextRows: { Row })
		undo:set({ rows = rows:peek(), selection = selection:peek() })
		rows:set(nextRows)
	end
	local function remove(keys: { string })
		local removing: { [string]: boolean } = {}
		for _, key in keys do
			removing[key] = true
		end
		local changed = true
		while changed do
			changed = false
			for _, item in rows:peek() do
				if item.parent and removing[item.parent] and not removing[item.id] then
					removing[item.id] = true
					changed = true
				end
			end
		end
		local kept: { Row } = {}
		local chosen = table.clone(selection:peek())
		for _, item in rows:peek() do
			if removing[item.id] then
				chosen[item.id] = nil
			else
				table.insert(kept, item)
			end
		end
		if enabled:peek() then
			save(kept)
			selection:set(chosen)
			for _, key in keys do
				drafts[key] = nil
			end
		end
	end
	local function keys()
		local result = {}
		for _, item in rows:peek() do
			if selection:peek()[item.id] then
				table.insert(result, item.id)
			end
		end
		return result
	end
	local function cell(current: ReadOnlyValue<Row>, _placement: unknown, key: string)
		drafts[key] = drafts[key] or C.cell(noDraft)
		return (if kind == "Outline" then UI.HStack else UI.VStack) {
			Name = "EditableCell",
			align = "center",
			width = "fill",
			gap = "s",
			padding = if kind == "Outline" then nil else "s",
			UI.HStack {
				Visible = kind ~= "Outline",
				width = "fill",
				gap = "s",
				align = "center",
				UI.Image { image = "rbxassetid://75342910516929", Size = D2.fromOffset(32, 32) },
				UI.Text {
					text = function(use: Use)
						return use(current).kind
					end,
					textRole = "caption",
					wrap = true,
					UI.fill(),
				},
			},
			UI.CellEditor "Rename" {
				editLabel = "Rename",
				editor = "text",
				label = if kind == "Outline" then nil else "Name",
				enabled = editable,
				Size = D2.fromScale(1, 0),
				draft = drafts[key],
				if kind == "Outline" then UI.fill() else nil,
				value = function(use: Use)
					return use(current).name
				end,
				validate = function(value: unknown)
					return if string.match(tostring(value), "^%s*$") then "Enter a name." else nil
				end,
				onChange = function(value: unknown)
					if not cellsEnabled:peek() then
						return
					end
					local nextRows: { Row } = table.clone(rows:peek())
					for index, item in nextRows do
						if item.id == key then
							nextRows[index] = table.clone(item)
							nextRows[index].name = tostring(value)
						end
					end
					save(nextRows)
					c.log("rename")(key, value)
				end,
			},
		}
	end
	local spec: any = {
		Name = "EditableItems",
		from = if kind == "Outline"
			then function(use: Use)
				return children(nil, use(rows))
			end
			else rows,
		selectionFrom = rows,
		key = "id",
		selection = selection,
		selectionMode = "multiple",
		editing = function(use: Use)
			return use(enabled) and coarse(use) and use(editing)
		end,
		deletable = true,
		rowDeletable = function()
			return enabled:peek()
		end,
		reorderable = true,
		movable = function()
			return enabled:peek()
		end,
		onDelete = remove,
		onReorder = function(moved: { string }, slot: number, parentKey: string?)
			if not enabled:peek() then
				return
			end
			local kept: { Row } = {}
			local carried: { Row } = {}
			for _, item in rows:peek() do
				table.insert(if table.find(moved, item.id) then carried else kept, item)
			end
			local siblings = children(parentKey, kept)
			local before = siblings[slot + 1]
			local index = #kept + 1
			if before then
				for i, item in kept do
					if item.id == before.id then
						index = i
						break
					end
				end
			end
			for i, item in carried do
				table.insert(kept, index + i - 1, item)
			end
			save(kept)
			c.log("reorder")(moved, slot)
		end,
		measure = true,
		itemSize = if kind == "Outline" then nil else 160,
		Size = D2.new(1, 0, 0, 360),
		gap = if kind == "Outline" then 0 else 8,
	}
	if kind == "Outline" then
		spec.children = function(item: Row)
			return if item.kind == "Folder" then children(item.id, rows:peek()) else nil
		end
		spec.expanded = expanded
	end
	if kind == "Table" or kind == "Outline" then
		local columns: { any } = {
			{ id = "name", label = "Name", render = cell, minWidth = 180 },
			{
				id = "kind",
				label = "Kind",
				width = 100,
				value = function(item: Row)
					return item.kind
				end,
			},
		}
		spec.columns = columns
	else
		spec.render = cell
		if kind == "VirtualGrid" then
			spec.minColumnWidth = 140
			spec.minColumns = 2
		end
	end
	return UI.VStack "EditingDemo" {
		width = "fill",
		gap = "m",
		UI.Text {
			text = function(use: Use)
				return if use(env.effectiveInput) == "Gamepad"
					then "A selects an item. X opens item actions to rename; Edit selects a group. On a move handle, A picks up, D-pad moves, A drops and B cancels."
					elseif
						coarse(use)
					then "Tap an item to select it. The … menu lets you rename; Edit selects a group. Drag the handles to reorder."
					elseif
						kind == "Outline"
					then "Click a selected name or press F2 to rename. Command/Ctrl-click adds to selection; Shift-click selects a range. Drag a row to reorder siblings."
					else "Click a selected name or press F2 to rename. Command/Ctrl-click adds to selection; Shift-click selects a range. Drag a preview to reorder."
			end,
			wrap = true,
			Size = D2.fromScale(1, 0),
			AutomaticSize = E.AutomaticSize.Y,
		},
		UI.HStack {
			width = "fill",
			gap = "s",
			align = "center",
			wrap = true,
			UI.Toggle "EnableEditing" { label = "Container editing", value = enabled },
			UI.Toggle "EnableCellEditing" { label = "Cell editing", value = cellsEnabled },
			UI.Button "EditItems" {
				label = function(use: Use)
					return if use(editing) then "Done" else "Edit"
				end,
				Visible = coarse,
				enabled = enabled,
				onActivate = function()
					editing:set(not editing:peek())
				end,
			},
			UI.Button "NewItem" {
				label = "New item",
				enabled = enabled,
				onActivate = function()
					serial:set(serial:peek() + 1)
					local nextRows: { Row } = table.clone(rows:peek())
					table.insert(
						nextRows,
						1,
						{ id = tostring(serial:peek()), name = "Untitled " .. serial:peek(), kind = "Image" }
					)
					save(nextRows)
				end,
			},
			UI.Button "DeleteSelected" {
				label = "Delete selected",
				enabled = function(use: Use)
					return use(enabled) and next(use(selection)) ~= nil
				end,
				onActivate = function()
					remove(keys())
				end,
			},
			UI.Button "UndoEdit" {
				label = "Undo",
				enabled = function(use: Use)
					return (use(enabled) or use(cellsEnabled)) and use(undo) ~= nil
				end,
				onActivate = function()
					local previous = undo:peek()
					if previous then
						rows:set(previous.rows)
						selection:set(previous.selection)
						undo:set(nil)
					end
				end,
			},
		},
		UI.Text "EditingSummary" {
			textRole = "caption",
			text = function(use: Use)
				local count = 0
				for _ in use(selection) do
					count += 1
				end
				return `{#use(rows)} items · {count} selected`
			end,
		},
		if kind == "Outline" or kind == "Table"
			then UI.Table(spec)
			elseif kind == "VirtualGrid" then UI.VirtualGrid(spec)
			else UI.VirtualList(spec),
	}
end
