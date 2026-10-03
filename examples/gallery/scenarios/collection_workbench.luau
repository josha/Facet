--!strict
return {
	title = "File library",
	build = function(ctx: any)
		local UI, Host, Compose = ctx.UI, ctx.Host, ctx.Compose
		local D2, E, C3 = ctx.types.UDim2, ctx.types.Enum, ctx.types.Color3
		local rows, selection = Compose.cell({}), Compose.cell({})
		local inbox, inboxSelection = Compose.cell({}), Compose.cell({})
		local transfers, operation = Compose.cell(false), Compose.cell("move")
		local env = UI.environment()
		local filtersOpen = Compose.cell(false)
		local gridSize = Compose.cell(150)
		local function short(use)
			return use(env.heightClass) == "short" or use(env.sizeClass) == "compact"
		end
		local editingEnabled = Compose.cell(true)
		local editing, mode, linked = Compose.cell(false), Compose.cell("icons"), Compose.cell(false)
		local function coarse(use)
			return use(env.effectiveInput) ~= "KeyboardAndMouse"
		end
		local function editable(use)
			return use(editingEnabled) and (not coarse(use) or use(editing))
		end
		local function choosing(use)
			return use(editingEnabled) and coarse(use) and use(editing)
		end

		local creating, newName, refuse = Compose.cell(false), Compose.cell(""), Compose.cell(false)
		local focuses: { [string]: any } = { primary = {}, linked = {} }
		local query, state, message = Compose.cell(""), Compose.cell("ready"), Compose.cell("")
		local drafts, undo, serial = {}, Compose.cell(nil), 0
		local sorts = { primary = Compose.cell(nil), linked = Compose.cell(nil) }
		local colors = {
			{ value = "Red", label = "Red" },
			{ value = "Orange", label = "Orange" },
			{ value = "Yellow", label = "Yellow" },
			{ value = "Green", label = "Green" },
			{ value = "Blue", label = "Blue" },
			{ value = "Purple", label = "Purple" },
			{ value = "Gray", label = "Gray" },
			{ value = "None", label = "No label" },
		}
		local palette = {
			Red = C3.fromRGB(245, 92, 97),
			Orange = C3.fromRGB(255, 166, 75),
			Yellow = C3.fromRGB(250, 211, 81),
			Green = C3.fromRGB(85, 194, 109),
			Blue = C3.fromRGB(76, 159, 245),
			Purple = C3.fromRGB(187, 88, 233),
			Gray = C3.fromRGB(154, 155, 162),
			None = C3.fromRGB(180, 180, 180),
		}

		local function seed(count)
			local nextRows = {}
			for i = 1, count do
				nextRows[i] = {
					id = tostring(i),
					name = ({ "Coast", "Canyon", "Forest", "City" })[(i - 1) % 4 + 1] .. string.format(" %03d", i),
					color = if i == 1 then "Red" elseif i == 2 then "Blue" else "None",
					size = i * 17,
					kind = if i % 3 == 0 then "Material" else "Image",
				}
			end
			serial = count
			drafts = {}
			selection:set({})
			rows:set(nextRows)
			undo:set(nil)
			query:set("")
			state:set("ready")
		end
		seed(24)
		local function draft(key)
			if not drafts[key] then
				drafts[key] = Compose.cell(nil)
			end
			return drafts[key]
		end
		local function validName(value)
			return if type(value) ~= "string" or string.match(value, "^%s*$") then "Enter a file name." else nil
		end
		local function targets(key)
			if key and not selection:peek()[key] then
				return { key }
			end
			local keys = {}
			for _, item in rows:peek() do
				if selection:peek()[item.id] then
					table.insert(keys, item.id)
				end
			end
			return keys
		end
		local function change(key, field, value)
			if not editingEnabled:peek() then
				return
			end
			if refuse:peek() then
				message:set("Save refused by the model. Turn off Refuse edits to retry.")
				return
			end
			if field == "name" and validName(value) then
				return
			end
			local keys = if field == "color" then targets(key) else { key }
			local nextRows: { any } = table.clone(rows:peek())
			for i, item in nextRows do
				if table.find(keys, item.id) then
					local nextItem = table.clone(item)
					nextItem[field] = value
					nextRows[i] = nextItem
				end
			end
			rows:set(nextRows)
			message:set(
				if field == "color" then `Label updated on {#keys} files.` else "Saved. Both views use the same files."
			)
		end
		local function remove(keys)
			if not editingEnabled:peek() then
				return
			end
			local kept, removed, selected = {}, {}, table.clone(selection:peek())
			for i, item in rows:peek() do
				if table.find(keys, item.id) then
					table.insert(removed, { index = i, item = item })
					selected[item.id] = nil
				else
					table.insert(kept, item)
				end
			end
			if #removed == 0 then
				return
			end
			undo:set(removed)
			selection:set(selected)
			rows:set(kept)
			for _, key in keys do
				drafts[key] = nil
			end
			message:set(`Deleted {#removed} files. Undo is available.`)
		end
		local function restore()
			if not editingEnabled:peek() then
				return
			end
			local removed = undo:peek()
			if removed and removed.collections then
				rows:set(removed.collections[1])
				inbox:set(removed.collections[2])
				undo:set(nil)
				message:set("Transfer undone.")
				return
			end
			if not removed then
				return
			end
			local restored, chosen = table.clone(rows:peek()), {}
			for _, entry in removed do
				table.insert(restored, math.min(entry.index, #restored + 1), entry.item)
				chosen[entry.item.id] = true
			end
			rows:set(restored)
			selection:set(chosen)
			undo:set(nil)
			message:set("Files restored.")
		end
		local function create(name)
			if not editingEnabled:peek() then
				return
			end
			serial += 1
			local key = tostring(serial)
			local nextRows: { any } = table.clone(rows:peek())
			table.insert(nextRows, 1, {
				id = key,
				name = name or `Untitled {serial}`,
				color = "None",
				size = 0,
				kind = "Image",
			})
			query:set("")
			state:set("ready")
			rows:set(nextRows)
			selection:set({ [key] = true })
			editing:set(true)
			creating:set(false)
			if focuses.primary.focus then
				focuses.primary.focus(key)
			end
			message:set("New file created. Edit its name in either view.")
		end
		local filtered = Compose.formula(function(use: any)
			local visible, filter = {}, string.lower(use(query))
			for _, item in use(rows) do
				if string.find(string.lower(item.name), filter, 1, true) then
					table.insert(visible, item)
				end
			end
			return visible
		end)
		local function reorder(keys: { string }, slot: number, source: any)
			if not editingEnabled:peek() or refuse:peek() then
				return
			end
			local carried: { any }, remaining: { any }, visible: { string } = {}, {}, {}
			for _, item in rows:peek() do
				table.insert(if table.find(keys, item.id) then carried else remaining, item)
			end
			for _, item in source:peek() do
				if not table.find(keys, item.id) then
					table.insert(visible, item.id)
				end
			end
			local nextKey = visible[slot + 1]
			local previousKey = visible[slot]
			local insertion = #remaining + 1
			for i, item in remaining do
				if item.id == nextKey then
					insertion = i
					break
				elseif nextKey == nil and item.id == previousKey then
					insertion = i + 1
					break
				end
			end
			for i, item in carried do
				table.insert(remaining, insertion + i - 1, item)
			end
			rows:set(remaining)
			message:set(`Moved {#carried} files. Both views use the same order.`)
		end

		local function dragFiles(items, keys, collection)
			return {
				payload = { kind = "files", collection = collection, items = items, keys = keys },
				operations = { "copy", "move", "apply" },
			}
		end
		local function receive(collection)
			local target = if collection == "library" then rows else inbox
			return {
				operation = operation,
				accepts = function(payload)
					if not editingEnabled:peek() or refuse:peek() then
						return false, "Editing is unavailable"
					end
					return type(payload) == "table" and (payload.kind == "files" or payload.kind == "image"),
						"Drop files or an image here"
				end,
				onUpdate = function(_, _, accepted, reason)
					if not accepted then
						message:set(reason or "Cannot drop here")
					end
				end,
				onDrop = function(payload, info)
					local oldRows, oldInbox = rows:peek(), inbox:peek()
					local kept, carried = table.clone(target:peek()), {}
					local origin = if payload.collection == "library"
						then rows
						elseif payload.collection == "inbox" then inbox
						else nil
					if payload.kind == "image" then
						serial += 1
						carried = {
							{
								id = tostring(serial),
								name = payload.name,
								kind = "Image",
								assetId = payload.assetId,
								size = 0,
								color = "None",
							},
						}
					else
						for _, item in payload.items do
							local record = table.clone(item)
							if info.operation == "copy" then
								serial += 1
								record.id = tostring(serial)
							end
							table.insert(carried, record)
						end
					end
					local slot = info.insertion and info.insertion.slot or #kept
					for index, item in carried do
						table.insert(kept, math.min(slot + index, #kept + 1), item)
					end
					ctx.runtime.reactor:batch(function()
						undo:set({ collections = { oldRows, oldInbox } })
						if origin and origin ~= target and info.operation == "move" then
							local remaining = {}
							for _, item in origin:peek() do
								if not table.find(payload.keys, item.id) then
									table.insert(remaining, item)
								end
							end
							origin:set(remaining)
						end
						target:set(kept)
					end)
					message:set(
						`{#carried} files {if info.operation == "copy" then "copied" else "moved"} to {collection}. Undo is available.`
					)
					return true
				end,
			}
		end
		local function inboxView()
			return UI.VirtualList {
				Name = "Inbox",
				from = inbox,
				key = "id",
				collectionId = "inbox",
				selection = inboxSelection,
				selectionMode = "multiple",
				editing = choosing,
				itemSize = 64,
				measure = true,
				Size = D2.fromScale(1, 1),
				drag = function(items, keys)
					return dragFiles(items, keys, "inbox")
				end,
				drop = receive("inbox"),
				movable = function()
					return editingEnabled:peek() and not refuse:peek()
				end,
				onReorder = function(keys: { string }, slot: number)
					local kept: { any }, carried: { any } = {}, {}
					for _, item in inbox:peek() do
						table.insert(if table.find(keys, item.id) then carried else kept, item)
					end
					for index, item in carried do
						table.insert(kept, slot + index, item)
					end
					inbox:set(kept)
				end,
				render = function(current)
					return UI.VStack {
						width = "fill",
						padding = "s",
						UI.Text {
							text = function(use)
								return use(current).name
							end,
						},
						UI.Text {
							text = function(use)
								return use(current).kind
							end,
							textRole = "caption",
						},
					}
				end,
			}
		end
		local function assets()
			local chips = { UI.Text { text = "Drag to add or apply:", textRole = "caption" } }
			for _, color in { "Red", "Green", "Blue" } do
				local chip = UI.Button { Name = "Drag" .. color, label = color, BackgroundColor3 = palette[color] }
				UI.draggable(chip, {
					payload = { kind = "color", value = palette[color], label = color },
					operations = { "apply" },
					armOnTap = true,
				})
				table.insert(chips, chip)
			end
			local chip =
				UI.Button { Name = "DragImageAsset", label = "Portrait image", icon = "rbxassetid://75342910516929" }
			UI.draggable(chip, {
				payload = { kind = "image", assetId = "rbxassetid://75342910516929", name = "Portrait" },
				operations = { "copy", "move", "apply" },
				armOnTap = true,
			})
			table.insert(chips, chip)
			return UI.HStack {
				Name = "DragPalette",
				width = "fill",
				align = "center",
				gap = "s",
				wrap = true,
				table.unpack(chips),
			}
		end

		local function value(current, field)
			return function(use)
				return use(current)[field]
			end
		end
		local function cell(current: any, _placement: any, key: any, icon: boolean, tableCell: boolean?)
			local node = UI.VStack {
				Name = "FileCell",
				width = "fill",
				height = "hug",
				gap = "s",
				padding = "m",
				(if icon then UI.VStack else UI.HStack) {
					Name = "Preview",
					width = "fill",
					align = "center",
					gap = "s",
					UI.Image {
						image = function(use)
							return use(current).assetId or "rbxassetid://75342910516929"
						end,
						Size = function(use: any)
							local side = if icon then math.floor(use(gridSize) * 0.4) else 28
							return D2.fromOffset(side, side)
						end,
						ImageColor3 = function(use)
							return palette[use(current).color]
						end,
					},
					UI.Text {
						text = value(current, "kind"),
						Visible = not tableCell,
						textRole = "caption",
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						TextXAlignment = if icon then E.TextXAlignment.Center else E.TextXAlignment.Left,
						if not icon then UI.fill() else nil,
					},
				},
				UI.CellEditor {
					Name = "Rename",
					editor = "text",
					value = value(current, "name"),
					enabled = editable,
					draft = draft(key),
					validate = validName,
					Size = D2.new(1, 0, 0, 0),
					onChange = function(v)
						change(key, "name", v)
					end,
				},
				UI.HStack {
					Name = "ColorLabel",
					Visible = function(use)
						return not icon or use(current).color ~= "None"
					end,
					align = "center",
					gap = "s",
					Host.Frame {
						Name = "Swatch",
						Size = D2.fromOffset(12, 12),
						BackgroundColor3 = function(use)
							return palette[use(current).color]
						end,
						BorderSizePixel = 0,
						Visible = function(use)
							return use(current).color ~= "None"
						end,
						Host.UICorner { CornerRadius = ctx.types.UDim.new(1, 0) },
					},
					UI.Text {
						text = function(use)
							return if use(current).color == "None" then "No label" else use(current).color
						end,
						textRole = "caption",
					},
				},
			}
			UI.dropTarget(node, {
				operation = "apply",
				passThrough = function(payload)
					return type(payload) ~= "table" or payload.kind == "files"
				end,
				accepts = function(payload)
					return editingEnabled:peek()
						and not refuse:peek()
						and (payload.kind == "color" or payload.kind == "image"),
						"Enable editing to change this file"
				end,
				onDrop = function(payload)
					change(
						key,
						if payload.kind == "color" then "color" else "assetId",
						if payload.kind == "color" then payload.label else payload.assetId
					)
					return true
				end,
			})
			return node
		end

		local function view(kind, id)
			local source = if id == "linked" then rows else filtered
			local spec = {
				Name = id,
				collectionId = "library",
				drag = function(items, keys)
					return dragFiles(items, keys, "library")
				end,
				drop = receive("library"),
				from = source,
				key = "id",
				selection = selection,
				selectionFrom = rows,
				selectionMode = "multiple",
				focus = focuses[id],
				editing = choosing,
				deletable = true,
				rowDeletable = function()
					return editingEnabled:peek()
				end,
				reorderable = true,
				movable = function()
					return editingEnabled:peek() and not refuse:peek()
				end,
				onReorder = function(keys: { string }, slot: number)
					reorder(keys, slot, source)
				end,
				onDelete = remove,
				maxRetained = 120,
				Size = D2.fromScale(1, 1),
				onActivate = function(item)
					message:set(`Opened {item.name}.`)
				end,
				rowActions = function(_, key)
					return {
						swipeEnabled = coarse,
						enabled = editingEnabled,
						trailing = {
							{
								id = "delete",
								label = "Delete",
								role = "destructive",
								onActivate = function()
									remove(targets(key))
								end,
							},
						},
					}
				end,
			}
			if kind == "details" then
				spec.itemSize = 200
				spec.sort = sorts[id]
				local columns: { any } = {
					{
						id = "name",
						label = "File",
						minWidth = 210,
						width = 260,
						value = function(item)
							return item.name
						end,
						render = function(current, placement, key)
							return cell(current, placement, key, false, true)
						end,
					},
					{
						id = "kind",
						label = "Kind",
						minWidth = 100,
						width = 120,
						priority = 1,
						value = function(item)
							return item.kind
						end,
					},
					{
						id = "size",
						label = "KB",
						minWidth = 64,
						width = 80,
						align = "end",
						priority = 2,
						value = function(item)
							return item.size
						end,
					},
				}
				spec.columns = columns
				return UI.Table(spec)
			end
			spec.measure = true
			spec.from, spec.itemSize, spec.gap = source, if kind == "icons" then 200 else 164, 8
			spec.render = function(current, placement, key)
				return cell(current, placement, key, kind == "icons")
			end
			if kind == "icons" then
				spec.minColumnWidth = gridSize
				return UI.VirtualGrid(spec)
			end
			return UI.VirtualList(spec)
		end
		local function button(name, label, action, enabled, visible)
			return UI.Button {
				Name = name,
				label = label,
				onActivate = action,
				enabled = enabled,
				Visible = visible,
			}
		end
		local function hasSelection(use)
			return use(editingEnabled) and next(use(selection)) ~= nil
		end
		local function labels()
			local children = { UI.Text { text = "Label:", textRole = "body" } }
			for _, option in colors do
				table.insert(
					children,
					UI.Button {
						Name = "Label" .. option.value,
						name = option.label,
						label = if option.value == "None" then "×" else "",
						appearance = "utility",
						shape = "circle",
						Size = function(use: any)
							local side = if coarse(use) then 44 else 32
							return D2.fromOffset(side, side)
						end,
						enabled = hasSelection,
						selected = function(use)
							local selected, found = use(selection), false
							for _, item in use(rows) do
								if selected[item.id] then
									if item.color ~= option.value then
										return false
									end
									found = true
								end
							end
							return found
						end,
						onActivate = function()
							change(nil, "color", option.value)
						end,
						if option.value ~= "None"
							then Host.Frame {
								Name = "Swatch",
								AnchorPoint = ctx.types.Vector2.new(0.5, 0.5),
								Position = D2.fromScale(0.5, 0.5),
								Size = function(use: any)
									local side = if coarse(use) then 24 else 20
									return D2.fromOffset(side, side)
								end,
								BorderSizePixel = 0,
								BackgroundColor3 = palette[option.value],
								BackgroundTransparency = function(use)
									return if hasSelection(use) then 0 else 0.65
								end,
								Host.UICorner { CornerRadius = ctx.types.UDim.new(1, 0) },
							}
							else nil,
					}
				)
			end
			return UI.ScrollView {
				Name = "Labels",
				axis = "x",
				width = "fill",
				height = "hug",
				UI.HStack { Name = "Palette", align = "center", gap = 0, wrap = false, table.unpack(children) },
			}
		end
		local function filesPage()
			return UI.VStack {
				Name = "CollectionWorkbench",
				UI.fill(),
				UI.Dialog {
					isPresented = creating,
					title = "New file",
					content = function()
						return UI.TextInput {
							Name = "NewFileName",
							label = "Name",
							value = newName,
							onChange = function(v)
								newName:set(v)
							end,
							onCommit = function(v, reason)
								if reason == "submit" and not validName(v) then
									create(v)
								end
							end,
						}
					end,
					actions = {
						{
							id = "cancel",
							label = "Cancel",
							role = "cancel",
							onActivate = function()
								creating:set(false)
							end,
						},
						{
							id = "create",
							label = "Create",
							role = "default",
							enabled = function(use)
								return validName(use(newName)) == nil
							end,
							onActivate = function()
								create(newName:peek())
							end,
						},
					},
				},
				width = "fill",
				height = "fill",
				gap = "s",
				padding = "m",
				UI.Text {
					text = "File library",
					textRole = "title",
					Visible = function(use)
						return not short(use)
					end,
				},
				UI.Text {
					text = function(use)
						if not use(editingEnabled) then
							return "Read-only. Enable editing to rename, label, reorder, create or delete files."
						end
						if use(message) ~= "" then
							return use(message)
						end
						if coarse(use) and use(editing) then
							return "Change a file name, then press Enter or leave the field to save. Choose Done to finish."
						end
						return if coarse(use)
							then "Tap a file to select it. Choose Edit to select several files or change their names."
							else "Edit names directly. Command/Ctrl-click adds items; Shift-click selects a range. Drag a preview to reorder."
					end,
					Visible = function(use)
						return not short(use)
					end,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					wrap = true,
					textRole = "caption",
				},
				UI.HStack {
					Name = "Toolbar",
					align = "center",
					width = "fill",
					gap = "s",
					wrap = true,
					UI.Picker {
						Name = "ViewMode",
						Size = D2.fromOffset(0, 0),
						AutomaticSize = E.AutomaticSize.XY,
						style = "segmented",
						sizing = "hug",
						controlSize = "regular",
						iconOnly = true,
						selected = mode,
						options = {
							{ value = "icons", label = "Icons", icon = "view.grid" },
							{ value = "list", label = "List", icon = "view.list" },
							{ value = "details", label = "Details", icon = "view.table" },
						},
					},
					UI.Toggle {
						Name = "EnableEditing",
						label = "Enable editing",
						value = editingEnabled,
						onChange = function(value)
							editingEnabled:set(value)
							message:set("")
							if not value then
								editing:set(false)
								creating:set(false)
							end
						end,
					},
					button("Edit", function(use)
						return if use(editing) then "Done" else "Edit"
					end, function()
						editing:set(not editing:peek())
					end, editingEnabled, coarse),
					button("Create", "New file", function()
						newName:set("")
						creating:set(true)
					end, editingEnabled),

					button("Delete", "Delete selected", function()
						remove(targets(nil))
					end, function(use)
						return use(editingEnabled) and next(use(selection)) ~= nil
					end),
					button("Undo", "Undo", restore, function(use)
						return use(editingEnabled) and use(undo) ~= nil
					end),
					button("ShowFilters", "Search & options", function()
						filtersOpen:set(not filtersOpen:peek())
					end, nil, short),
				},
				labels(),
				Compose.show(transfers, function()
					return UI.VStack {
						width = "fill",
						gap = "s",
						UI.Text {
							text = "Drag files between the library and Inbox. Choose Move or Copy. Drag the portrait into either collection to create a file.",
							wrap = true,
							Size = D2.fromScale(1, 0),
							AutomaticSize = E.AutomaticSize.Y,
							textRole = "caption",
						},
						assets(),
					}
				end),
				UI.HStack {
					Name = "Filters",
					align = "center",
					Visible = function(use)
						return not short(use) or use(filtersOpen)
					end,
					width = "fill",
					gap = "s",
					wrap = true,
					UI.TextInput {
						Name = "FilterFiles",
						placeholder = "Filter files",
						value = query,
						Size = D2.fromOffset(200, 36),
						onChange = function(v)
							query:set(v)
						end,
					},
					button("Clear", "Clear filter", function()
						query:set("")
					end),
					UI.Toggle {
						Name = "Linked",
						label = "Linked view",
						value = linked,
						onChange = function(v)
							linked:set(v)
						end,
					},
					UI.Toggle { Name = "Transfers", label = "Show Inbox", value = transfers },
					UI.Picker {
						Name = "TransferOperation",
						Size = D2.fromOffset(0, 0),
						AutomaticSize = E.AutomaticSize.XY,
						sizing = "hug",
						selected = operation,
						Visible = transfers,
						options = { { value = "move", label = "Move" }, { value = "copy", label = "Copy" } },
					},
					UI.Menu {
						Name = "DemoOptions",
						label = "Demo options",
						items = {
							{ id = "refuse", label = "Refuse edits", checked = refuse },
							{
								id = "large",
								label = "Load 1,000 files",
								onSelect = function()
									seed(1000)
								end,
							},
							{
								id = "reset",
								label = "Reset to 24 files",
								onSelect = function()
									seed(24)
								end,
							},
							{
								id = "ready",
								label = "Show files",
								onSelect = function()
									state:set("ready")
								end,
							},
							{
								id = "loading",
								label = "Show loading",
								onSelect = function()
									state:set("loading")
								end,
							},
							{
								id = "error",
								label = "Show load error",
								onSelect = function()
									state:set("error")
								end,
							},
						},
					},
				},
				UI.Text {
					text = function(use)
						local count = 0
						for _, on in use(selection) do
							if on then
								count += 1
							end
						end
						return `{#use(filtered)} of {#use(rows)} files · {count} selected`
					end,
					textRole = "caption",
				},
				UI.VStack {
					Name = "Contents",
					width = "fill",
					height = "fill",
					UI.fill(),
					Compose.show(function(use)
						return use(state) == "ready"
					end, function()
						return UI.AdaptiveStack {
							Name = "Views",
							axis = function(use)
								return if ctx.viewport and use(ctx.viewport).width < 800 then "y" else "x"
							end,
							width = "fill",
							height = "fill",
							gap = "m",
							UI.VStack {
								Name = "PrimaryView",
								width = "fill",
								height = "fill",
								UI.fill(),
								Compose.keyed {
									from = function(use)
										return { use(mode) }
									end,
									render = function(current)
										return view(current:peek(), "primary")
									end,
								},
							},
							Compose.show(transfers, function()
								return UI.VStack {
									Name = "InboxView",
									width = "fill",
									height = "fill",
									UI.fill(),
									UI.Text { text = "Inbox · drop files or images here", textRole = "caption" },
									inboxView(),
								}
							end),
							Compose.show(linked, function()
								return UI.VStack {
									Name = "LinkedView",
									width = "fill",
									height = "fill",
									UI.fill(),
									UI.Text { text = "Same files · independent sort", textRole = "caption" },
									view("details", "linked"),
								}
							end),
						}
					end, function()
						return UI.VStack {
							width = "fill",
							gap = "m",
							UI.Text {
								text = function(use)
									return if use(state) == "loading"
										then "Loading files…"
										elseif use(state) == "error" then "Could not load files. Try again."
										elseif #use(rows) == 0 then "No files yet. Create your first file."
										else "No matching files. Clear the filter to see all files."
								end,
								wrap = true,
								Size = D2.new(1, 0, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
							},
							button("Recover", "Show files", function()
								state:set("ready")
								query:set("")
							end),
						}
					end),
				},
				UI.Slider {
					Name = "GridSize",
					label = "Grid size",
					value = gridSize,
					min = 140,
					max = 300,
					step = 10,
					format = function(value: number)
						return `{math.round(value / 150 * 100)}%`
					end,
					Size = D2.new(1, 0, 0, 0),
					Visible = function(use)
						return use(mode) == "icons"
					end,
					Host.UISizeConstraint { MaxSize = ctx.types.Vector2.new(400, math.huge) },
				},
			}
		end

		return {
			screen = filesPage,
			reset = function()
				seed(24)
			end,
			steps = {
				create = create,
				undo = restore,
				large = function()
					seed(1000)
				end,
			},
			model = {
				rows = rows,
				inbox = inbox,
				transfers = transfers,
				operation = operation,
				selection = selection,
				query = query,
				editing = editing,
				editingEnabled = editingEnabled,
				mode = mode,
				gridSize = gridSize,
				linked = linked,
				state = state,
				draft = draft,
				change = change,
				remove = remove,
				reorder = function(keys, slot)
					reorder(keys, slot, filtered)
				end,
			},
			report = function()
				local order = {}
				for _, item in rows:peek() do
					table.insert(order, item.id)
				end
				return {
					order = order,
					count = #rows:peek(),
					selection = selection:peek(),
					mode = mode:peek(),
					gridSize = gridSize:peek(),
					editing = editing:peek(),
					editingEnabled = editingEnabled:peek(),
					linked = linked:peek(),
					message = message:peek(),
				}
			end,
		}
	end,
}
