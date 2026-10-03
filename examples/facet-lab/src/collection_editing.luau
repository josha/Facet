--!strict
return function(c: any, kind: string)
	local UI, C = c.UI, c.Compose
	local D2, E = c.ctx.types.UDim2, c.ctx.types.Enum
	local initial = {}
	for i, name in { "Coast", "Canyon", "Forest", "City", "Glacier", "Harbour" } do
		initial[i] = { id = tostring(i), name = name, kind = if i % 3 == 0 then "Material" else "Image" }
	end
	local rows = c.cell("editingRows", initial)
	local selection = c.cell("editingSelection", {})
	local enabled, editing = c.cell("editingEnabled", true), c.cell("editingMode", false)
	local serial, undo = c.cell("editingSerial", 6), c.cell("editingUndo", nil)
	local drafts = c.cell("editingDrafts", {}):peek()
	local env = UI.environment()
	local function coarse(use)
		return use(env.effectiveInput) ~= "KeyboardAndMouse"
	end
	local function editable(use)
		return use(enabled) and (not coarse(use) or use(editing))
	end
	local function save(nextRows)
		if not enabled:peek() then
			return
		end
		undo:set({ rows = rows:peek(), selection = selection:peek() })
		rows:set(nextRows)
	end
	local function remove(keys)
		local kept, chosen = {}, table.clone(selection:peek())
		for _, item in rows:peek() do
			if table.find(keys, item.id) then
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
	local function cell(current, _placement, key)
		drafts[key] = drafts[key] or C.cell(nil)
		return UI.VStack {
			Name = "EditableCell",
			width = "fill",
			gap = "s",
			padding = "s",
			UI.HStack {
				width = "fill",
				gap = "s",
				align = "center",
				UI.Image { image = "rbxassetid://75342910516929", Size = D2.fromOffset(32, 32) },
				UI.Text {
					text = function(use)
						return use(current).kind
					end,
					textRole = "caption",
					wrap = true,
					UI.fill(),
				},
			},
			UI.CellEditor {
				Name = "Rename",
				editor = "text",
				label = "Name",
				enabled = editable,
				Size = D2.fromScale(1, 0),
				draft = drafts[key],
				value = function(use)
					return use(current).name
				end,
				validate = function(value)
					return if string.match(value, "^%s*$") then "Enter a name." else nil
				end,
				onChange = function(value)
					if not enabled:peek() then
						return false
					end
					local nextRows: { any } = table.clone(rows:peek())
					for index, item in nextRows do
						if item.id == key then
							nextRows[index] = table.clone(item)
							nextRows[index].name = value
						end
					end
					save(nextRows)
					c.log("rename")(key, value)
					return true
				end,
			},
		}
	end
	local spec: any = {
		Name = "EditableItems",
		from = rows,
		key = "id",
		selection = selection,
		selectionMode = "multiple",
		editing = function(use)
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
		onReorder = function(moved: { string }, slot: number)
			local kept: { any }, carried: { any } = {}, {}
			for _, item in rows:peek() do
				table.insert(if table.find(moved, item.id) then carried else kept, item)
			end
			for i, item in carried do
				table.insert(kept, slot + i, item)
			end
			save(kept)
			c.log("reorder")(moved, slot)
		end,
		measure = true,
		itemSize = 160,
		Size = D2.new(1, 0, 0, 360),
		gap = 8,
	}
	if kind == "Table" then
		local columns: { any } = {
			{ id = "name", label = "Name", render = cell, minWidth = 160 },
			{
				id = "kind",
				label = "Kind",
				width = 100,
				value = function(item)
					return item.kind
				end,
			},
		}
		spec.columns = columns
	else
		spec.render = cell
		if kind == "VirtualGrid" then
			spec.minColumnWidth = 140
		end
	end
	return UI.VStack {
		Name = "EditingDemo",
		width = "fill",
		gap = "m",
		UI.Text {
			text = function(use)
				return if coarse(use)
					then "Choose Edit to rename items and select a group. Drag the handles to reorder."
					else "Edit names directly. Command/Ctrl-click adds to selection; Shift-click selects a range. Drag a preview to reorder."
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
			UI.Toggle { Name = "EnableEditing", label = "Enable editing", value = enabled },
			UI.Button {
				Name = "EditItems",
				label = function(use)
					return if use(editing) then "Done" else "Edit"
				end,
				Visible = coarse,
				enabled = enabled,
				onActivate = function()
					editing:set(not editing:peek())
				end,
			},
			UI.Button {
				Name = "NewItem",
				label = "New item",
				enabled = enabled,
				onActivate = function()
					serial:set(serial:peek() + 1)
					local nextRows: { any } = table.clone(rows:peek())
					table.insert(
						nextRows,
						1,
						{ id = tostring(serial:peek()), name = "Untitled " .. serial:peek(), kind = "Image" }
					)
					save(nextRows)
				end,
			},
			UI.Button {
				Name = "DeleteSelected",
				label = "Delete selected",
				enabled = function(use)
					return use(enabled) and next(use(selection)) ~= nil
				end,
				onActivate = function()
					remove(keys())
				end,
			},
			UI.Button {
				Name = "UndoEdit",
				label = "Undo",
				enabled = function(use)
					return use(enabled) and use(undo) ~= nil
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
		UI.Text {
			Name = "EditingSummary",
			textRole = "caption",
			text = function(use)
				local count = 0
				for _ in use(selection) do
					count += 1
				end
				return `{#use(rows)} items · {count} selected`
			end,
		},
		UI[kind](spec),
	}
end
