--!strict
return {
	title = "File library",
	build = function(ctx: any)
		local UI, Host, Compose = ctx.UI, ctx.Host, ctx.Compose
		local D2, E, C3 = ctx.types.UDim2, ctx.types.Enum, ctx.types.Color3
		local rows, selection = Compose.cell({}), Compose.cell({})
		local path, expanded = Compose.cell({}), Compose.cell({})
		local creatingFolder = Compose.cell(false)
		local inbox, inboxSelection = Compose.cell({}), Compose.cell({})
		local transfers, operation = Compose.cell(false), Compose.cell("move")
		local env = UI.environment()
		local filtersOpen = Compose.cell(false)
		local filtersDetent = Compose.cell("large")
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
			return use(editingEnabled)
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

		local function children(parent, all)
			local result = {}
			for _, item in all do
				if item.parent == parent then
					table.insert(result, item)
				end
			end
			return result
		end
		local function folderNow(use: any?)
			local entries = if use then use(path) else path:peek()
			return if #entries > 0 then entries[#entries].value else nil
		end
		local function subtree(keys, all)
			local included = {}
			for _, key in keys do
				included[key] = true
			end
			local changed = true
			while changed do
				changed = false
				for _, item in all do
					if item.parent and included[item.parent] and not included[item.id] then
						included[item.id] = true
						changed = true
					end
				end
			end
			return included
		end
		local function openFolder(item)
			if item.kind ~= "Folder" then
				message:set(`Opened {item.name}.`)
				return
			end
			local lookup, entries = {}, {}
			for _, row in rows:peek() do
				lookup[row.id] = row
			end
			local current = item
			while current do
				table.insert(entries, 1, { id = "folder", value = current.id })
				current = if current.parent then lookup[current.parent] else nil
			end
			selection:set({})
			query:set("")
			editing:set(false)
			path:set(entries)
		end
		Compose.watch(function(use)
			local valid = {}
			for _, item in use(rows) do
				valid[item.id] = true
			end
			local entries = path:peek()
			for index, entry in entries do
				if not valid[entry.value] then
					local kept = table.clone(entries)
					for i = #kept, index, -1 do
						table.remove(kept, i)
					end
					path:set(kept)
					break
				end
			end
		end)
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
			for _, folder in
				{
					{ id = "environments", name = "Environments" },
					{ id = "materials", name = "Materials" },
					{ id = "archive", name = "Archive", parent = "environments" },
				}
			do
				folder.kind, folder.color, folder.size = "Folder", "None", 0
				table.insert(nextRows, folder)
			end
			for index = math.max(3, count - 7), count do
				nextRows[index].parent = if index > count - 2
					then "archive"
					elseif index % 3 == 0 then "materials"
					else "environments"
			end
			local ordered = {}
			for index = count + 1, #nextRows do
				table.insert(ordered, nextRows[index])
			end
			for index = 1, count do
				table.insert(ordered, nextRows[index])
			end
			nextRows = ordered
			path:set({})
			expanded:set({})
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
			local deleting = subtree(keys, rows:peek())
			local kept, removed, selected = {}, {}, table.clone(selection:peek())
			for i, item in rows:peek() do
				if deleting[item.id] then
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
				kind = if creatingFolder:peek() then "Folder" else "Image",
				parent = folderNow(),
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
			message:set(
				if creatingFolder:peek() then "Folder created." else "New file created. Edit its name in either view."
			)
		end
		local function visibleRows(all, parent, filter)
			local visible = {}
			for _, item in all do
				if
					(filter ~= "" or item.parent == parent) and string.find(string.lower(item.name), filter, 1, true)
				then
					table.insert(visible, item)
				end
			end
			return visible
		end
		local filtered = Compose.formula(function(use)
			return visibleRows(use(rows), folderNow(use), string.lower(use(query)))
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
		local function receive(collection, parent)
			local target = if collection == "library" then rows else inbox
			return {
				operation = operation,
				accepts = function(payload): (boolean, string?)
					if not editingEnabled:peek() or refuse:peek() then
						return false, "Editing is unavailable"
					end
					if type(payload) ~= "table" or (payload.kind ~= "files" and payload.kind ~= "image") then
						return false, "Drop files or an image here"
					end
					if
						payload.kind == "files"
						and payload.collection == collection
						and parent
						and subtree(payload.keys, target:peek())[parent]
					then
						return false, "A folder cannot contain itself"
					end
					return true, nil
				end,
				onUpdate = function(_, _, accepted, reason)
					if not accepted then
						message:set(reason or "Cannot drop here")
					end
				end,
				onDrop = function(payload, info)
					local oldRows, oldInbox = rows:peek(), inbox:peek()
					local origin = if payload.collection == "library"
						then rows
						elseif payload.collection == "inbox" then inbox
						else nil
					local included = if origin then subtree(payload.keys, origin:peek()) else {}
					if parent and origin == target and included[parent] then
						return false
					end
					local kept, carried, remap = {}, {}, {}
					for _, item in target:peek() do
						if not (origin == target and info.operation == "move" and included[item.id]) then
							table.insert(kept, item)
						end
					end
					if payload.kind == "image" then
						serial += 1
						table.insert(carried, {
							id = tostring(serial),
							name = payload.name,
							kind = "Image",
							assetId = payload.assetId,
							size = 0,
							color = "None",
							parent = parent,
						})
					elseif origin then
						for _, item in origin:peek() do
							if included[item.id] then
								local record = table.clone(item)
								if info.operation == "copy" then
									serial += 1
									record.id = tostring(serial)
								end
								remap[item.id] = record.id
								table.insert(carried, record)
							end
						end
						for _, item in carried do
							item.parent = if item.parent and included[item.parent] then remap[item.parent] else parent
						end
					else
						return false
					end
					local insertion = #kept + 1
					local beforeKey = info.insertion and info.insertion.beforeKey
					if beforeKey then
						for index, item in kept do
							if item.id == beforeKey then
								insertion = index
								break
							end
						end
					end
					for index, item in carried do
						table.insert(kept, insertion + index - 1, item)
					end
					ctx.runtime.reactor:batch(function()
						undo:set({ collections = { oldRows, oldInbox } })
						if origin and origin ~= target and info.operation == "move" then
							local remaining = {}
							for _, item in origin:peek() do
								if not included[item.id] then
									table.insert(remaining, item)
								end
							end
							origin:set(remaining)
						end
						target:set(kept)
					end)
					message:set(
						`{#carried} items {if info.operation == "copy" then "copied" else "moved"}. Undo is available.`
					)
					return true
				end,
			}
		end
		local function inboxView()
			return UI.Outline {
				Name = "Inbox",
				from = function(use)
					return children(nil, use(inbox))
				end,
				selectionFrom = inbox,
				children = function(item)
					return if item.kind == "Folder" then children(item.id, inbox:peek()) else nil
				end,
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
				onReorder = function(keys: { string }, slot: number, parentKey: string?)
					local kept: { any }, carried: { any } = {}, {}
					for _, item in inbox:peek() do
						table.insert(if table.find(keys, item.id) then carried else kept, item)
					end
					local siblings = children(parentKey, kept)
					local before = siblings[slot + 1]
					local insertion = #kept + 1
					if before then
						for index, item in kept do
							if item.id == before.id then
								insertion = index
								break
							end
						end
					end
					for index, item in carried do
						table.insert(kept, insertion + index - 1, item)
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
			local preview = UI.ZStack {
				Size = function(use: any)
					local side = if icon then math.floor(use(gridSize) * 0.4) else 28
					return D2.fromOffset(side, side)
				end,
				UI.Path {
					Name = "FolderIcon",
					Size = D2.fromScale(1, 1),
					closed = true,
					thickness = 2,
					role = "accent",
					Visible = function(use)
						return use(current).kind == "Folder"
					end,
					points = {
						{ x = 0.08, y = 0.2, inX = 0, inY = 0, outX = 0, outY = 0 },
						{ x = 0.4, y = 0.2, inX = 0, inY = 0, outX = 0, outY = 0 },
						{ x = 0.5, y = 0.32, inX = 0, inY = 0, outX = 0, outY = 0 },
						{ x = 0.92, y = 0.32, inX = 0, inY = 0, outX = 0, outY = 0 },
						{ x = 0.92, y = 0.82, inX = 0, inY = 0, outX = 0, outY = 0 },
						{ x = 0.08, y = 0.82, inX = 0, inY = 0, outX = 0, outY = 0 },
					},
				},
				UI.Image {
					Visible = function(use)
						return use(current).kind ~= "Folder"
					end,
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
			}
			local editor = UI.CellEditor {
				Name = "Rename",
				editLabel = "Rename",
				editor = "text",
				value = value(current, "name"),
				enabled = editable,
				draft = draft(key),
				validate = validName,
				Size = D2.new(1, 0, 0, 0),
				if not icon then UI.fill() else nil,
				onChange = function(v)
					change(key, "name", v)
				end,
			}
			local label = UI.HStack {
				Name = "ColorLabel",
				Visible = function(use)
					return use(current).color ~= "None"
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
					Visible = icon,
				},
			}
			local kind = UI.Text {
				text = value(current, "kind"),
				Visible = function(use)
					return not tableCell and (icon or not short(use))
				end,
				textRole = "caption",
			}
			local node = (if icon then UI.VStack else UI.HStack) {
				Name = "FileCell",
				width = "fill",
				height = "hug",
				align = "center",
				gap = "s",
				padding = if icon then "m" else nil,
				preview,
				if icon then kind else editor,
				if icon then editor else kind,
				label,
			}
			return node
		end
		local function rowDrop(current, key)
			local folderDrop = receive("library", key)
			local function isFolder()
				return current:peek().kind == "Folder"
			end
			return {
				label = value(current, "name"),
				operation = function(use)
					return if use(current).kind == "Folder" then use(operation) else "apply"
				end,
				passThrough = function(payload)
					return type(payload) ~= "table" or (payload.kind == "files" and not isFolder())
				end,
				accepts = function(payload)
					if isFolder() then
						return folderDrop.accepts(payload)
					end
					return editingEnabled:peek()
						and not refuse:peek()
						and (payload.kind == "color" or payload.kind == "image"),
						"Enable editing to change this file"
				end,
				onDrop = function(payload, info)
					if isFolder() then
						return folderDrop.onDrop(payload, info)
					end
					change(
						key,
						if payload.kind == "color" then "color" else "assetId",
						if payload.kind == "color" then payload.label else payload.assetId
					)
					return true
				end,
			}
		end

		local function view(kind, id, folder)
			local source = Compose.formula(function(use)
				return visibleRows(use(rows), folder, if id == "linked" then "" else string.lower(use(query)))
			end)
			local spec = {
				Name = id,
				collectionId = "library",
				drag = function(items, keys)
					return dragFiles(items, keys, "library")
				end,
				drop = receive("library", folder),
				rowDrop = rowDrop,
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
				onReorder = function(keys: { string }, slot: number, parentKey: string?)
					local siblings = if parentKey then children(parentKey, rows:peek()) else source:peek()
					reorder(keys, slot, Compose.cell(siblings))
				end,
				onDelete = remove,
				maxRetained = 120,
				Size = D2.fromScale(1, 1),
				onActivate = openFolder,
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
			if kind ~= "icons" then
				spec.children = function(item)
					return if item.kind == "Folder" and (id == "linked" or query:peek() == "")
						then children(item.id, rows:peek())
						else nil
				end
				spec.expanded = expanded
			end
			if kind == "details" then
				spec.sort = sorts[id]
				local columns: { any } = {
					{
						id = "name",
						label = "File",
						minWidth = 260,
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
			spec.from = source
			spec.itemSize = if kind == "icons" then 200 else nil
			spec.gap = if kind == "icons" then 8 else 0
			spec.render = function(current, placement, key)
				return cell(current, placement, key, kind == "icons")
			end
			if kind == "icons" then
				spec.minColumnWidth = gridSize
				return UI.VirtualGrid(spec)
			end
			return UI.Outline(spec)
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
		local function wide(use)
			return not short(use)
		end
		local function createPrompt(folder)
			creatingFolder:set(folder)
			newName:set("")
			creating:set(true)
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
		local splitColumn = Compose.cell("sidebar")
		local splitWidth = Compose.cell(360)
		local inboxColumn, inboxWidth = Compose.cell("sidebar"), Compose.cell(360)
		Compose.watch(function(use)
			if use(transfers) then
				splitWidth:set(math.max(splitWidth:peek(), 760))
			end
			if not use(transfers) then
				inboxColumn:set("sidebar")
			end
		end)
		Compose.watch(function(use)
			if not use(linked) then
				splitColumn:set("sidebar")
			end
		end)
		local function folderViews(folder)
			return UI.NavigationSplitView {
				Name = "Views",
				alwaysShowResizeHandle = true,
				detailVisible = linked,
				preferredCompactColumn = splitColumn,
				sidebarWidth = splitWidth,
				maxSidebarWidth = 1000,
				minDetailWidth = 440,
				backLabel = "Back to Files",
				detailLabel = "Open linked view",
				sidebar = function()
					return UI.NavigationSplitView {
						Name = "PrimaryViews",
						alwaysShowResizeHandle = true,
						detailVisible = transfers,
						preferredCompactColumn = inboxColumn,
						sidebarWidth = inboxWidth,
						backLabel = "Back to Files",
						detailLabel = "Open Inbox",
						sidebar = function()
							return UI.VStack {
								Name = "PrimaryView",
								width = "fill",
								height = "fill",
								UI.fill(),
								Compose.keyed {
									from = function(use)
										return { use(mode) }
									end,
									render = function(current)
										return view(current:peek(), "primary", folder)
									end,
								},
							}
						end,
						detail = function()
							return UI.VStack {
								Name = "InboxView",
								width = "fill",
								height = "fill",
								UI.fill(),
								UI.Text { text = "Inbox · drop files or images here", textRole = "caption" },
								inboxView(),
							}
						end,
					}
				end,
				detail = function()
					return UI.VStack {
						Name = "LinkedView",
						width = "fill",
						height = "fill",
						UI.Text { text = "Linked view · independent sort", textRole = "caption" },
						view("details", "linked", folder),
					}
				end,
			}
		end

		local function editingToggle(visible)
			return UI.Toggle {
				Name = "EnableEditing",
				Visible = visible,
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
			}
		end
		local function gridSizeControl()
			return UI.Slider {
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
			}
		end
		local function fileOptions()
			return UI.VStack {
				Name = "FileOptions",
				width = "fill",
				gap = "s",
				editingToggle(short),
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
				Compose.show(short, gridSizeControl),
			}
		end

		local function filesPage()
			local page = UI.VStack {
				Name = "CollectionWorkbench",
				UI.fill(),
				UI.Dialog {
					isPresented = creating,
					title = function(use: any)
						return if use(creatingFolder) then "New folder" else "New file"
					end,
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
							return "Select files for group actions. Choose Rename for one file; Enter saves and Escape cancels."
						end
						return if use(env.effectiveInput) == "Gamepad"
							then "A opens folders; B goes back. Left/Right expands lists. X opens item actions to rename. Edit selects a group; use a move handle to drag."
							elseif
								coarse(use)
							then "Tap a folder to open it. Use Back to leave it. Use the item’s … menu to rename. Edit selects several items."
							else "Double-click a folder to open it. Click a selected name or press F2 to rename. Command/Ctrl-click adds to selection; Shift-click selects a range."
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
					UI.Menu {
						Name = "ViewOptions",
						label = "Views",
						items = {
							{ id = "linked", label = "Linked view", checked = linked, dismiss = true },
							{ id = "inbox", label = "Show Inbox", checked = transfers, dismiss = true },
						},
					},
					editingToggle(wide),
					button("Edit", function(use)
						return if use(editing) then "Done" else "Edit"
					end, function()
						editing:set(not editing:peek())
					end, editingEnabled, coarse),
					button("Create", "New file", function()
						createPrompt(false)
					end, editingEnabled, wide),
					button("CreateFolder", "New folder", function()
						createPrompt(true)
					end, editingEnabled, wide),

					button("Delete", "Delete selected", function()
						remove(targets(nil))
					end, function(use)
						return use(editingEnabled) and next(use(selection)) ~= nil
					end, wide),
					button("Undo", "Undo", restore, function(use)
						return use(editingEnabled) and use(undo) ~= nil
					end, wide),
					UI.Menu {
						Name = "FileActions",
						label = "Actions",
						Visible = short,
						items = {
							{
								id = "newFile",
								label = "New file",
								enabled = editingEnabled,
								onSelect = function()
									createPrompt(false)
								end,
							},
							{
								id = "newFolder",
								label = "New folder",
								enabled = editingEnabled,
								onSelect = function()
									createPrompt(true)
								end,
							},
							{
								id = "delete",
								label = "Delete selected",
								role = "destructive",
								enabled = hasSelection,
								onSelect = function()
									remove(targets(nil))
								end,
							},
							{
								id = "undo",
								label = "Undo",
								enabled = function(use)
									return use(editingEnabled) and use(undo) ~= nil
								end,
								onSelect = restore,
							},
						},
					},
					button("ShowFilters", "Search & options", function()
						filtersOpen:set(not filtersOpen:peek())
					end, nil, short),
				},
				Compose.show(wide, fileOptions),
				UI.Sheet {
					Name = "FileOptionsSheet",
					title = "Search & options",
					isPresented = filtersOpen,
					detent = filtersDetent,
					detents = { "large" },
					content = function()
						return UI.VStack {
							width = "fill",
							gap = "m",
							fileOptions(),
							button("CloseFileOptions", "Done", function()
								filtersOpen:set(false)
							end),
						}
					end,
				},
				UI.Text {
					text = function(use)
						local count = 0
						for _, on in use(selection) do
							if on then
								count += 1
							end
						end
						return `{#use(filtered)} of {#use(rows)} items · {count} selected`
					end,
					textRole = "caption",
				},
				UI.VStack {
					Name = "Contents",
					Host.UISizeConstraint { MinSize = ctx.types.Vector2.new(0, 320) },
					width = "fill",
					height = "fill",
					UI.fill(),
					Compose.show(function(use)
						return use(state) == "ready"
					end, function()
						return UI.NavigationStack {
							Name = "Folders",
							Size = D2.fromScale(1, 1),
							path = path,
							root = {
								title = "Files",
								content = function()
									return folderViews(nil)
								end,
							},
							destinations = {
								folder = {
									title = function(use: any)
										local id = folderNow(use)
										for _, item in use(rows) do
											if item.id == id then
												return item.name
											end
										end
										return "Folder"
									end,
									content = function(entry)
										return folderViews(assert(entry).value)
									end,
								},
							},
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
				Compose.show(wide, gridSizeControl),
			}
			return UI.ScrollView { Name = "FileViewport", width = "fill", height = "fill", page }
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
				path = path,
				expanded = expanded,
				openFolder = openFolder,
				receive = receive,
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
