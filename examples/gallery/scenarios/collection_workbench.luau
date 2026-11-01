--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type CellDraft = typeof(require("@repo/tools/typecheck/aliases").CellDraft)
type DropInfo = typeof(require("@repo/tools/typecheck/aliases").DropInfo)
type DraggableSpec = typeof(require("@repo/tools/typecheck/aliases").DraggableSpec)
type DropTargetSpec = typeof(require("@repo/tools/typecheck/aliases").DropTargetSpec)
type RowActionsOptions = typeof(require("@repo/tools/typecheck/aliases").RowActionsOptions)
type RowAction = typeof(require("@repo/tools/typecheck/aliases").RowAction)
type TableColumn = typeof(require("@repo/tools/typecheck/aliases").TableColumn)
type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)
type StringPickerOption = typeof(require("@repo/tools/typecheck/aliases").StringPickerOption)
type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
type DialogAction = typeof(require("@repo/tools/typecheck/aliases").DialogAction)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type Focus = typeof(require("@repo/tools/typecheck/aliases").FocusControls)
type NavigationEntry = typeof(require("@repo/tools/typecheck/aliases").NavigationEntry)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type File = {
	id: string,
	name: string,
	color: string,
	size: number,
	kind: string,
	parent: string?,
	assetId: string?,
}
type Entry = { id: string, value: string? }
type Removed = { index: number, item: File }
type Undo = { removed: { Removed }?, collections: { { File } }? }
type Payload = {
	kind: "files" | "color" | "image",
	collection: string?,
	items: { File }?,
	keys: { string }?,
	value: Color3?,
	label: string?,
	assetId: string?,
	name: string?,
}
type Selection = { [string]: boolean }
type Operation = "copy" | "move" | "apply"
type Sort = { column: string, direction: "ascending" | "descending" }
type Receiver = {
	operation: (Use) -> Operation,
	accepts: (unknown, DropInfo) -> (boolean, string?),
	onUpdate: (unknown, DropInfo, boolean, string?) -> (),
	onDrop: (unknown, DropInfo) -> boolean,
}
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
return {
	title = "File library",
	build = function(ctx: ExampleContext)
		local UI, Host, Compose = ctx.UI, ctx.Host, ctx.Compose
		local D2, E, C3 = ctx.types.UDim2, ctx.types.Enum, ctx.types.Color3
		local noFiles: { File } = {}
		local noSelection: Selection = {}
		local noEntries: { Entry } = {}
		local rows: Value<{ File }> = Compose.cell(noFiles)
		local selection: Value<Selection> = Compose.cell(noSelection)
		local path: Value<{ Entry }> = Compose.cell(noEntries)
		local expanded: Value<Selection> = Compose.cell(noSelection)
		local linkedPath: Value<{ Entry }> = Compose.cell(noEntries)
		local paths: { [string]: Value<{ Entry }> } = { primary = path, linked = linkedPath }
		local creatingFolder = Compose.cell(false)
		local inbox: Value<{ File }> = Compose.cell(noFiles)
		local inboxSelection: Value<Selection> = Compose.cell(noSelection)
		local transfers = Compose.cell(false)
		local operation = Compose.cell("move")
		local function dropOperation(use: Use): Operation
			local chosen = use(operation)
			if chosen == "copy" then
				return "copy"
			elseif chosen == "apply" then
				return "apply"
			end
			return "move"
		end
		local env = UI.environment()
		local filtersOpen = Compose.cell(false)
		local filtersDetent = Compose.cell("large")
		local gridSize = Compose.cell(150)
		local function short(use: Use): boolean
			return use(env.heightClass) == "short" or use(env.sizeClass) == "compact"
		end
		local editingEnabled = Compose.cell(true)
		local editing, mode, linked = Compose.cell(false), Compose.cell("icons"), Compose.cell(false)
		local function coarse(use: Use): boolean
			return use(env.effectiveInput) ~= "KeyboardAndMouse"
		end
		local function editable(use: Use): boolean
			return use(editingEnabled)
		end
		local function choosing(use: Use): boolean
			return use(editingEnabled) and coarse(use) and use(editing)
		end

		local creating, newName, refuse = Compose.cell(false), Compose.cell(""), Compose.cell(false)
		local focuses: { [string]: Focus } = { primary = {}, linked = {} }
		local query, state, message = Compose.cell(""), Compose.cell("ready"), Compose.cell("")
		local noUndo: Undo? = nil
		local drafts: { [string]: Value<CellDraft?> } = {}
		local undo: Value<Undo?> = Compose.cell(noUndo)
		local serial = 0
		local unsorted: Sort? = nil
		local primarySort: Value<Sort?> = Compose.cell(unsorted)
		local linkedSort: Value<Sort?> = Compose.cell(unsorted)
		local sorts: { [string]: Value<Sort?> } = { primary = primarySort, linked = linkedSort }
		local payloads: { [unknown]: Payload } = {}
		setmetatable(payloads, { __mode = "k" })
		local function register(payload: Payload): Payload
			payloads[payload] = payload
			return payload
		end
		local colors: { StringPickerOption } = {
			{ value = "Red", label = "Red" },
			{ value = "Orange", label = "Orange" },
			{ value = "Yellow", label = "Yellow" },
			{ value = "Green", label = "Green" },
			{ value = "Blue", label = "Blue" },
			{ value = "Purple", label = "Purple" },
			{ value = "Gray", label = "Gray" },
			{ value = "None", label = "No label" },
		}
		local palette: { [string]: Color3 } = {
			Red = C3.fromRGB(245, 92, 97),
			Orange = C3.fromRGB(255, 166, 75),
			Yellow = C3.fromRGB(250, 211, 81),
			Green = C3.fromRGB(85, 194, 109),
			Blue = C3.fromRGB(76, 159, 245),
			Purple = C3.fromRGB(187, 88, 233),
			Gray = C3.fromRGB(154, 155, 162),
			None = C3.fromRGB(180, 180, 180),
		}

		local function children(parent: string?, all: { File }): { File }
			local result: { File } = {}
			for _, item in all do
				if item.parent == parent then
					table.insert(result, item)
				end
			end
			return result
		end
		local function folderNow(use: Use?): string?
			local entries = if use then use(path) else path:peek()
			return if #entries > 0 then entries[#entries].value else nil
		end
		local function subtree(keys: { string }, all: { File }): Selection
			local included: Selection = {}
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
		local function openFolder(item: File, pane: string?)
			local navigation = paths[pane or "primary"]
			if item.kind ~= "Folder" then
				message:set(`Opened {item.name}.`)
				return
			end
			local lookup: { [string]: File } = {}
			local entries: { Entry } = {}
			for _, row in rows:peek() do
				lookup[row.id] = row
			end
			local current: File? = item
			while current do
				table.insert(entries, 1, { id = "folder", value = current.id })
				current = if current.parent then lookup[current.parent] else nil
			end
			selection:set({})
			query:set("")
			editing:set(false)
			navigation:set(entries)
		end
		Compose.watch(function(use: Use)
			local valid: Selection = {}
			for _, item in use(rows) do
				valid[item.id] = true
			end
			for _, navigation in paths do
				local entries = navigation:peek()
				for index, entry in entries do
					local value = entry.value
					if not (value and valid[value]) then
						local kept = table.clone(entries)
						for i = #kept, index, -1 do
							table.remove(kept, i)
						end
						navigation:set(kept)
						break
					end
				end
			end
		end)
		local PLACES = { "Coast", "Canyon", "Forest", "City" }
		local function seed(count: number)
			local nextRows: { File } = {}
			for i = 1, count do
				nextRows[i] = {
					id = tostring(i),
					name = PLACES[(i - 1) % 4 + 1] .. string.format(" %03d", i),
					color = if i == 1 then "Red" elseif i == 2 then "Blue" else "None",
					size = i * 17,
					kind = if i % 3 == 0 then "Material" else "Image",
				}
			end
			local folders: { File } = {
				{ id = "environments", name = "Environments", kind = "Folder", color = "None", size = 0 },
				{ id = "materials", name = "Materials", kind = "Folder", color = "None", size = 0 },
				{
					id = "archive",
					name = "Archive",
					parent = "environments",
					kind = "Folder",
					color = "None",
					size = 0,
				},
			}
			for _, folder in folders do
				table.insert(nextRows, folder)
			end
			for index = math.max(3, count - 7), count do
				nextRows[index].parent = if index > count - 2
					then "archive"
					elseif index % 3 == 0 then "materials"
					else "environments"
			end
			local ordered: { File } = {}
			for index = count + 1, #nextRows do
				table.insert(ordered, nextRows[index])
			end
			for index = 1, count do
				table.insert(ordered, nextRows[index])
			end
			nextRows = ordered
			path:set({})
			linkedPath:set({})
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
		local function draft(key: string): Value<CellDraft?>
			local existing = drafts[key]
			if existing then
				return existing
			end
			local empty: CellDraft? = nil
			local created: Value<CellDraft?> = Compose.cell(empty)
			drafts[key] = created
			return created
		end
		local function validName(value: unknown): string?
			return if type(value) ~= "string" or string.match(value, "^%s*$") then "Enter a file name." else nil
		end
		local function targets(key: string?): { string }
			if key and not selection:peek()[key] then
				return { key }
			end
			local keys: { string } = {}
			for _, item in rows:peek() do
				if selection:peek()[item.id] then
					table.insert(keys, item.id)
				end
			end
			return keys
		end
		local function change(key: string?, field: "name" | "color" | "assetId", value: string?)
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
			local keys: { string } = if field == "color" then targets(key) elseif key then { key } else {}
			local nextRows: { File } = table.clone(rows:peek())
			for i, item in nextRows do
				if table.find(keys, item.id) then
					local nextItem = table.clone(item)
					if field == "assetId" then
						nextItem.assetId = value
					elseif value ~= nil and field == "name" then
						nextItem.name = value
					elseif value ~= nil then
						nextItem.color = value
					end
					nextRows[i] = nextItem
				end
			end
			rows:set(nextRows)
			message:set(
				if field == "color" then `Label updated on {#keys} files.` else "Saved. Both views use the same files."
			)
		end
		local function remove(keys: { string })
			if not editingEnabled:peek() then
				return
			end
			local deleting = subtree(keys, rows:peek())
			local kept: { File }, removed: { Removed } = {}, {}
			local selected = table.clone(selection:peek())
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
			undo:set({ removed = removed })
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
			local last = undo:peek()
			local collections = if last then last.collections else nil
			if collections then
				rows:set(collections[1])
				inbox:set(collections[2])
				undo:set(nil)
				message:set("Transfer undone.")
				return
			end
			local removed = if last then last.removed else nil
			if not removed then
				return
			end
			local restored: { File }, chosen: Selection = table.clone(rows:peek()), {}
			for _, entry in removed do
				table.insert(restored, math.min(entry.index, #restored + 1), entry.item)
				chosen[entry.item.id] = true
			end
			rows:set(restored)
			selection:set(chosen)
			undo:set(nil)
			message:set("Files restored.")
		end
		local function create(name: string?)
			if not editingEnabled:peek() then
				return
			end
			serial += 1
			local key = tostring(serial)
			local nextRows: { File } = table.clone(rows:peek())
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
			local focus = focuses.primary.focus
			if focus then
				focus(key)
			end
			message:set(
				if creatingFolder:peek() then "Folder created." else "New file created. Edit its name in either view."
			)
		end
		local function visibleRows(all: { File }, parent: string?, filter: string): { File }
			local visible: { File } = {}
			for _, item in all do
				if
					(filter ~= "" or item.parent == parent) and string.find(string.lower(item.name), filter, 1, true)
				then
					table.insert(visible, item)
				end
			end
			return visible
		end
		local filtered = Compose.formula(function(use: Use): { File }
			return visibleRows(use(rows), folderNow(use), string.lower(use(query)))
		end)
		local function reorder(keys: { string }, slot: number, source: ReadOnlyValue<{ File }>)
			if not editingEnabled:peek() or refuse:peek() then
				return
			end
			local carried: { File }, remaining: { File }, visible: { string } = {}, {}, {}
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

		local allOperations: { Operation } = { "copy", "move", "apply" }
		local function dragFiles(items: { File }, keys: { string }, collection: string): DraggableSpec
			return {
				payload = register({ kind = "files", collection = collection, items = items, keys = keys }),
				operations = allOperations,
			}
		end
		local function receiver(collection: string, parent: string?): Receiver
			local target: Value<{ File }> = if collection == "library" then rows else inbox
			return {
				operation = dropOperation,
				accepts = function(value: unknown): (boolean, string?)
					if not editingEnabled:peek() or refuse:peek() then
						return false, "Editing is unavailable"
					end
					local payload = payloads[value]
					if payload == nil or (payload.kind ~= "files" and payload.kind ~= "image") then
						return false, "Drop files or an image here"
					end
					if
						payload.kind == "files"
						and payload.collection == collection
						and parent
						and subtree(payload.keys or {}, target:peek())[parent]
					then
						return false, "A folder cannot contain itself"
					end
					return true, nil
				end,
				onUpdate = function(_: unknown, _: DropInfo, accepted: boolean, reason: string?)
					if not accepted then
						message:set(reason or "Cannot drop here")
					end
				end,
				onDrop = function(value: unknown, info: DropInfo): boolean
					local payload = payloads[value]
					if payload == nil then
						return false
					end
					local oldRows, oldInbox = rows:peek(), inbox:peek()
					local origin: Value<{ File }>? = if payload.collection == "library"
						then rows
						elseif payload.collection == "inbox" then inbox
						else nil
					local included: Selection = if origin then subtree(payload.keys or {}, origin:peek()) else {}
					if parent and origin == target and included[parent] then
						return false
					end
					local kept: { File }, carried: { File }, remap: { [string]: string } = {}, {}, {}
					for _, item in target:peek() do
						if not (origin == target and info.operation == "move" and included[item.id]) then
							table.insert(kept, item)
						end
					end
					if payload.kind == "image" then
						serial += 1
						table.insert(carried, {
							id = tostring(serial),
							name = payload.name or "",
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
					local beforeKey = if info.insertion then info.insertion.beforeKey else nil
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
					Compose.reactor.batch(ctx.runtime.reactor, function()
						undo:set({ collections = { oldRows, oldInbox } })
						if origin and origin ~= target and info.operation == "move" then
							local remaining: { File } = {}
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
		local function receive(collection: string, parent: string?): DropTargetSpec
			local spec = receiver(collection, parent)
			return {
				operation = spec.operation,
				accepts = spec.accepts,
				onUpdate = spec.onUpdate,
				onDrop = spec.onDrop,
			}
		end
		local function inboxView(): ScrollingFrame
			return UI.Outline "Inbox" {
				from = function(use: Use): { File }
					return children(nil, use(inbox))
				end,
				selectionFrom = inbox,
				children = function(item: File): { File }?
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
				drag = function(items, keys): DraggableSpec
					return dragFiles(items, keys, "inbox")
				end,
				drop = receive("inbox"),
				movable = function()
					return editingEnabled:peek() and not refuse:peek()
				end,
				onReorder = function(keys, slot, parentKey)
					local kept: { File }, carried: { File } = {}, {}
					for _, item in inbox:peek() do
						table.insert(if table.find(keys, item.id) then carried else kept, item)
					end
					local siblings = children(parentKey, kept)
					local before = siblings[(slot :: number) + 1]
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
				render = function(current: ReadOnlyValue<File>): GuiObject
					return UI.VStack {
						width = "fill",
						padding = "s",
						UI.Text {
							text = function(use: Use): string
								return use(current).name
							end,
						},
						UI.Text {
							text = function(use: Use): string
								return use(current).kind
							end,
							textRole = "caption",
						},
					}
				end,
			}
		end
		local applyOnly: { Operation } = { "apply" }
		local function assets(): Frame
			local palettes: StackProps = {
				Name = "DragPalette",
				width = "fill",
				align = "center",
				gap = "s",
				wrap = true,
				UI.Text { text = "Drag to add or apply:", textRole = "caption" },
			}
			for _, color in { "Red", "Green", "Blue" } do
				local chip = UI.Button { Name = "Drag" .. color, label = color, BackgroundColor3 = palette[color] }
				UI.draggable(chip, {
					payload = register({ kind = "color", value = palette[color], label = color }),
					operations = applyOnly,
					armOnTap = true,
				})
				palettes[#palettes + 1] = chip
			end
			local chip = UI.Button "DragImageAsset" { label = "Portrait image", icon = "rbxassetid://75342910516929" }
			UI.draggable(chip, {
				payload = register({ kind = "image", assetId = "rbxassetid://75342910516929", name = "Portrait" }),
				operations = allOperations,
				armOnTap = true,
			})
			palettes[#palettes + 1] = chip
			return UI.HStack(palettes)
		end

		local function nameOf(current: ReadOnlyValue<File>): (Use) -> string
			return function(use: Use): string
				return use(current).name
			end
		end
		local function kindOf(current: ReadOnlyValue<File>): (Use) -> string
			return function(use: Use): string
				return use(current).kind
			end
		end
		local function cell(
			current: ReadOnlyValue<File>,
			_placement: unknown,
			key: ReadOnlyValue<string>,
			icon: boolean,
			tableCell: boolean?
		): Frame
			local preview = UI.ZStack "FilePreview" {
				Size = function(use: Use): UDim2
					local side = if icon then math.floor(use(gridSize) * 0.4) else 28
					return D2.fromOffset(side, side)
				end,
				UI.Path "FolderIcon" {
					Size = D2.fromScale(1, 1),
					closed = true,
					thickness = 2,
					role = "accent",
					Visible = function(use: Use): boolean
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
					Visible = function(use: Use): boolean
						return use(current).kind ~= "Folder"
					end,
					image = function(use: Use): string
						return use(current).assetId or "rbxassetid://75342910516929"
					end,
					Size = function(use: Use): UDim2
						local side = if icon then math.floor(use(gridSize) * 0.4) else 28
						return D2.fromOffset(side, side)
					end,
					ImageColor3 = function(use: Use): Color3
						return palette[use(current).color]
					end,
				},
			}
			local editor = UI.CellEditor "Rename" {
				editLabel = "Rename",
				editor = "text",
				value = nameOf(current),
				enabled = editable,
				draft = draft(key:peek()),
				validate = validName,
				Size = D2.new(1, 0, 0, 0),
				if not icon then UI.fill() else nil,
				onChange = function(v: unknown)
					change(key:peek(), "name", if type(v) == "string" then v else nil)
				end,
			}
			local label = UI.HStack "ColorLabel" {
				Visible = function(use: Use): boolean
					return use(current).color ~= "None"
				end,
				align = "center",
				gap = "s",
				Host.Frame "Swatch" {
					Size = D2.fromOffset(12, 12),
					BackgroundColor3 = function(use: Use): Color3
						return palette[use(current).color]
					end,
					BorderSizePixel = 0,
					Visible = function(use: Use): boolean
						return use(current).color ~= "None"
					end,
					Host.UICorner { CornerRadius = ctx.types.UDim.new(1, 0) },
				},
				UI.Text {
					text = function(use: Use): string
						return if use(current).color == "None" then "No label" else use(current).color
					end,
					textRole = "caption",
					Visible = icon,
				},
			}
			local kind = UI.Text {
				text = kindOf(current),
				Visible = function(use: Use): boolean
					return not tableCell and (icon or not short(use))
				end,
				textRole = "caption",
			}
			local fileCell: StackProps = {
				Name = "FileCell",
				width = "fill",
				height = "hug",
				align = if icon then "start" else "center",
				gap = "s",
				padding = if icon then "m" else nil,
				preview,
				if icon then kind else editor,
				if icon then editor else kind,
				label,
			}
			return if icon then UI.VStack(fileCell) else UI.HStack(fileCell)
		end
		local function rowDrop(current: ReadOnlyValue<File>, key: string): DropTargetSpec
			local folderDrop = receiver("library", key)
			local function isFolder(): boolean
				return current:peek().kind == "Folder"
			end
			return {
				label = nameOf(current),
				operation = function(use: Use): Operation
					return if use(current).kind == "Folder" then dropOperation(use) else "apply"
				end,
				passThrough = function(value: unknown): boolean
					local payload = payloads[value]
					return payload == nil or (payload.kind == "files" and not isFolder())
				end,
				accepts = function(value: unknown, info: DropInfo): (boolean, string?)
					if isFolder() then
						return folderDrop.accepts(value, info)
					end
					local payload = payloads[value]
					return editingEnabled:peek()
						and not refuse:peek()
						and payload ~= nil
						and (payload.kind == "color" or payload.kind == "image"),
						"Enable editing to change this file"
				end,
				onDrop = function(value: unknown, info: DropInfo): boolean
					if isFolder() then
						return folderDrop.onDrop(value, info)
					end
					local payload = payloads[value]
					if payload == nil then
						return true
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

		local function view(kind: string, id: string, folder: string?): GuiObject
			local iconView = kind == "icons"
			local source = Compose.formula(function(use: Use): { File }
				return visibleRows(use(rows), folder, if id == "linked" then "" else string.lower(use(query)))
			end)
			local function drag(items, keys): DraggableSpec
				return dragFiles(items, keys, "library")
			end
			local drop = receive("library", folder)
			local function rowDeletable(): boolean
				return editingEnabled:peek()
			end
			local function movable(): boolean
				return editingEnabled:peek() and not refuse:peek()
			end
			local function onReorder(keys: { string }, slot: number, parentKey: string?)
				local siblings = if parentKey then children(parentKey, rows:peek()) else source:peek()
				reorder(keys, slot, Compose.cell(siblings))
			end
			local function onActivate(item: File)
				openFolder(item, id)
			end
			local function rowActions(_: ReadOnlyValue<File>, key: string): RowActionsOptions
				local trailing: { RowAction } = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						onActivate = function()
							remove(targets(key))
						end,
					},
				}
				return {
					swipeEnabled = coarse,
					enabled = editingEnabled,
					trailing = trailing,
				}
			end
			local function folderChildren(item: File): { File }?
				return if item.kind == "Folder" and (id == "linked" or query:peek() == "")
					then children(item.id, rows:peek())
					else nil
			end
			if kind == "details" then
				local columns: { TableColumn } = {
					{
						id = "name",
						label = "File",
						minWidth = 260,
						value = function(item: File): string
							return item.name
						end,
						render = function(current: ReadOnlyValue<File>, placement: unknown, key): GuiObject
							return cell(current, placement, key, false, true)
						end,
					},
					{
						id = "kind",
						label = "Kind",
						minWidth = 100,
						width = 120,
						priority = 1,
						value = function(item: File): string
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
						value = function(item: File): number
							return item.size
						end,
					},
				}
				return (UI.Table :: any) {
					Name = id,
					collectionId = "library",
					drag = function(items, keys)
						return drag(items, keys)
					end,
					drop = drop,
					rowDrop = function(current, key)
						return rowDrop(current, key)
					end,
					from = source,
					key = "id",
					selection = selection,
					selectionFrom = rows,
					selectionMode = "multiple",
					focus = focuses[id],
					editing = choosing,
					deletable = true,
					rowDeletable = rowDeletable,
					reorderable = true,
					movable = movable,
					onReorder = function(keys, slot, parentKey)
						onReorder(keys, slot, parentKey)
					end,
					onDelete = function(keys)
						remove(keys)
					end,
					maxRetained = 120,
					Size = D2.fromScale(1, 1),
					onActivate = onActivate,
					rowActions = function(current, key)
						return rowActions(current, key)
					end,
					children = folderChildren,
					expanded = expanded,
					sort = sorts[id],
					columns = columns,
				}
			end
			if kind == "icons" then
				return (UI.VirtualGrid :: any) {
					Name = id,
					collectionId = "library",
					drag = function(items, keys)
						return drag(items, keys)
					end,
					drop = drop,
					rowDrop = function(current, key)
						return rowDrop(current, key)
					end,
					from = source,
					key = "id",
					selection = selection,
					selectionFrom = rows,
					selectionMode = "multiple",
					focus = focuses[id],
					editing = choosing,
					deletable = true,
					rowDeletable = rowDeletable,
					reorderable = true,
					movable = movable,
					onReorder = function(keys, slot, parentKey)
						onReorder(keys, slot, parentKey)
					end,
					onDelete = function(keys)
						remove(keys)
					end,
					maxRetained = 120,
					Size = D2.fromScale(1, 1),
					onActivate = onActivate,
					rowActions = function(current, key)
						return rowActions(current, key)
					end,
					measure = true,
					itemSize = 200,
					gap = 8,
					render = function(current: ReadOnlyValue<File>, placement, key): GuiObject
						return cell(current, placement, key, iconView)
					end,
					minColumnWidth = gridSize,
				}
			end
			return (UI.Outline :: any) {
				Name = id,
				collectionId = "library",
				drag = drag,
				drop = drop,
				rowDrop = rowDrop,
				from = source,
				key = "id",
				selection = selection,
				selectionFrom = rows,
				selectionMode = "multiple",
				focus = focuses[id],
				editing = choosing,
				deletable = true,
				rowDeletable = rowDeletable,
				reorderable = true,
				movable = movable,
				onReorder = onReorder,
				onDelete = remove,
				maxRetained = 120,
				Size = D2.fromScale(1, 1),
				onActivate = onActivate,
				rowActions = rowActions,
				children = folderChildren,
				expanded = expanded,
				measure = true,
				gap = 0,
				render = function(current: ReadOnlyValue<File>, placement, key): GuiObject
					return cell(current, placement, key, iconView)
				end,
			}
		end
		local function button(
			name: string,
			label: string | (Use) -> string,
			action: () -> (),
			enabled: (boolean | ReadOnlyValue<boolean> | (Use) -> boolean)?,
			visible: (boolean | ReadOnlyValue<boolean> | (Use) -> boolean)?
		): TextButton
			return UI.Button {
				Name = name,
				label = label,
				onActivate = function()
					action()
				end,
				enabled = enabled,
				Visible = visible,
			}
		end
		local function wide(use: Use): boolean
			return not short(use)
		end
		local function createPrompt(folder: boolean)
			creatingFolder:set(folder)
			newName:set("")
			creating:set(true)
		end
		local function hasSelection(use: Use): boolean
			return use(editingEnabled) and next(use(selection)) ~= nil
		end
		local function labels(): ScrollingFrame
			local swatches: StackProps = {
				Name = "Palette",
				align = "center",
				gap = 0,
				wrap = true,
				width = "fill",
				UI.Text { text = "Label:", textRole = "body" },
			}
			for _, option in colors do
				local optionValue = if type(option.value) == "string" then option.value else "None"
				local optionLabel = if type(option.label) == "string" then option.label else optionValue
				swatches[#swatches + 1] = UI.Button {
					Name = "Label" .. optionValue,
					name = optionLabel,
					label = if optionValue == "None" then "×" else "",
					appearance = "utility",
					shape = "circle",
					Size = function(use: Use): UDim2
						local side = if coarse(use) then 44 else 32
						return D2.fromOffset(side, side)
					end,
					enabled = hasSelection,
					selected = function(use: Use): boolean
						local selected, found = use(selection), false
						for _, item in use(rows) do
							if selected[item.id] then
								if item.color ~= optionValue then
									return false
								end
								found = true
							end
						end
						return found
					end,
					onActivate = function()
						change(nil, "color", optionValue)
					end,
					if optionValue ~= "None"
						then Host.Frame "Swatch" {
							AnchorPoint = ctx.types.Vector2.new(0.5, 0.5),
							Position = D2.fromScale(0.5, 0.5),
							Size = function(use: Use): UDim2
								local side = if coarse(use) then 24 else 20
								return D2.fromOffset(side, side)
							end,
							BorderSizePixel = 0,
							BackgroundColor3 = palette[optionValue],
							BackgroundTransparency = function(use: Use): number
								return if hasSelection(use) then 0 else 0.65
							end,
							Host.UICorner { CornerRadius = ctx.types.UDim.new(1, 0) },
						}
						else nil,
				}
			end
			return UI.ScrollView "Labels" {
				axis = "x",
				width = "fill",
				height = "hug",
				UI.HStack(swatches),
			}
		end
		local sidebarColumn: "sidebar" | "detail" = "sidebar"
		local splitColumn: Value<"sidebar" | "detail"> = Compose.cell(sidebarColumn)
		local splitWidth = Compose.cell(360)
		local inboxColumn: Value<"sidebar" | "detail"> = Compose.cell(sidebarColumn)
		local inboxWidth = Compose.cell(360)
		Compose.watch(function(use: Use)
			if use(transfers) then
				splitWidth:set(math.max(splitWidth:peek(), 760))
			end
			if not use(transfers) then
				inboxColumn:set("sidebar")
			end
		end)
		Compose.watch(function(use: Use)
			if not use(linked) then
				splitColumn:set("sidebar")
			end
		end)
		local function folderNavigation(id: string): Frame
			local navigation = paths[id]
			local function content(folder: string?): GuiObject
				if id == "linked" then
					return view("details", id, folder)
				end
				return UI.TabView "PrimaryView" {
					Size = D2.fromScale(1, 1),
					UI.fill(),
					selection = mode,
					placement = "none",
					retention = "top",
					tabs = {
						{
							id = "icons",
							label = "Icons",
							content = function()
								return view("icons", id, folder)
							end,
						},
						{
							id = "list",
							label = "Outline",
							content = function()
								return view("list", id, folder)
							end,
						},
						{
							id = "details",
							label = "Details",
							content = function()
								return view("details", id, folder)
							end,
						},
					} :: { Tab },
				}
			end
			return UI.NavigationStack {
				Name = if id == "primary" then "Folders" else "LinkedFolders",
				Size = D2.fromScale(1, 1),
				UI.fill(),
				path = navigation,
				root = {
					title = "Files",
					content = function()
						return content(nil)
					end,
				},
				destinations = {
					folder = {
						title = function(use: Use): string
							local entries = use(navigation)
							local entry = entries[#entries]
							for _, item in use(rows) do
								if entry and item.id == entry.value then
									return item.name
								end
							end
							return "Folder"
						end,
						content = function(entry: NavigationEntry?): Instance
							local value = assert(entry).value
							return content(if type(value) == "string" then value else nil)
						end,
					},
				},
			}
		end
		local function folderViews(): Frame
			return UI.NavigationSplitView "Views" {
				alwaysShowResizeHandle = true,
				detailVisible = linked,
				preferredCompactColumn = splitColumn,
				sidebarWidth = splitWidth,
				maxSidebarWidth = 1000,
				minDetailWidth = 440,
				backLabel = "Back to Files",
				detailLabel = "Open linked view",
				sidebar = function()
					return UI.NavigationSplitView "PrimaryViews" {
						alwaysShowResizeHandle = true,
						detailVisible = transfers,
						preferredCompactColumn = inboxColumn,
						sidebarWidth = inboxWidth,
						backLabel = "Back to Files",
						detailLabel = "Open Inbox",
						sidebar = function()
							return folderNavigation("primary")
						end,
						detail = function()
							return UI.VStack "InboxView" {
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
					return UI.VStack "LinkedView" {
						width = "fill",
						height = "fill",
						UI.Text { text = "Linked view · independent sort", textRole = "caption" },
						folderNavigation("linked"),
					}
				end,
			}
		end

		local function editingToggle(visible: (Use) -> boolean): TextButton
			return UI.Toggle "EnableEditing" {
				Visible = visible,
				label = "Enable editing",
				value = editingEnabled,
				onChange = function(value: boolean)
					editingEnabled:set(value)
					message:set("")
					if not value then
						editing:set(false)
						creating:set(false)
					end
				end,
			}
		end
		local function gridSizeControl(): Frame
			local slider = UI.Slider "GridSize" {
				label = "Grid size",
				value = gridSize,
				min = 140,
				max = 300,
				step = 10,
				format = function(value: number)
					return `{math.round(value / 150 * 100)}%`
				end,
				Size = D2.new(1, 0, 0, 0),
				Visible = function(use: Use): boolean
					return use(mode) == "icons"
				end,
			}
			Host.UISizeConstraint { MaxSize = ctx.types.Vector2.new(400, math.huge) }.Parent = slider
			return slider
		end
		local operations: { StringPickerOption } =
			{ { value = "move", label = "Move" }, { value = "copy", label = "Copy" } }
		local modes: { StringPickerOption } = {
			{ value = "icons", label = "Icons", icon = "view.grid" },
			{ value = "list", label = "List", icon = "view.list" },
			{ value = "details", label = "Details", icon = "view.table" },
		}
		local demoItems: { MenuItem } = {
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
		}
		local function fileOptions(): Frame
			return UI.VStack "FileOptions" {
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
				UI.HStack "Filters" {
					align = "center",
					width = "fill",
					gap = "s",
					wrap = true,
					UI.TextInput "FilterFiles" {
						placeholder = "Filter files",
						value = query,
						Size = D2.fromOffset(200, 36),
						onChange = function(v: string)
							query:set(v)
						end,
					},
					button("Clear", "Clear filter", function()
						query:set("")
					end),

					UI.Picker "TransferOperation" {
						Size = D2.fromOffset(0, 0),
						AutomaticSize = E.AutomaticSize.XY,
						sizing = "hug",
						selected = operation,
						Visible = transfers,
						options = operations,
					},
					UI.Menu "DemoOptions" {
						label = "Demo options",
						items = demoItems,
					},
				},
				Compose.show(short, gridSizeControl),
			}
		end

		local createActions: { DialogAction } = {
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
				enabled = function(use: Use): boolean
					return validName(use(newName)) == nil
				end,
				onActivate = function()
					create(newName:peek())
				end,
			},
		}
		local viewItems: { MenuItem } = {
			{ id = "linked", label = "Linked view", checked = linked, dismiss = true },
			{ id = "inbox", label = "Show Inbox", checked = transfers, dismiss = true },
		}
		local actionItems: { MenuItem } = {
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
				enabled = function(use: Use): boolean
					return use(editingEnabled) and use(undo) ~= nil
				end,
				onSelect = restore,
			},
		}
		local optionDetents: { SheetDetent } = { "large" }
		local function filesPage(): ScrollingFrame
			local page = UI.VStack "CollectionWorkbench" {
				UI.fill(),
				UI.Dialog {
					isPresented = creating,
					title = function(use: Use): string
						return if use(creatingFolder) then "New folder" else "New file"
					end,
					content = function(): Instance
						return UI.TextInput "NewFileName" {
							label = "Name",
							value = newName,
							onChange = function(v: string)
								newName:set(v)
							end,
							onCommit = function(v: string, reason: "focusLost" | "submit")
								if reason == "submit" and not validName(v) then
									create(v)
								end
							end,
						}
					end,
					actions = createActions,
				},
				width = "fill",
				height = "fill",
				gap = "s",
				padding = "m",
				UI.Text {
					text = "File library",
					textRole = "title",
					Visible = function(use: Use): boolean
						return not short(use)
					end,
				},
				UI.Text {
					text = function(use: Use): string
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
					Visible = function(use: Use): boolean
						return not short(use)
					end,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					wrap = true,
					textRole = "caption",
				},
				UI.HStack "Toolbar" {
					align = "center",
					width = "fill",
					gap = "s",
					wrap = true,
					UI.Picker "ViewMode" {
						Size = D2.fromOffset(0, 0),
						AutomaticSize = E.AutomaticSize.XY,
						style = "segmented",
						sizing = "hug",
						controlSize = "regular",
						iconOnly = true,
						selected = mode,
						options = modes,
					},
					UI.Menu "ViewOptions" {
						label = "Views",
						items = viewItems,
					},
					editingToggle(wide),
					button("Edit", function(use: Use): string
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
					end, function(use: Use): boolean
						return use(editingEnabled) and next(use(selection)) ~= nil
					end, wide),
					button("Undo", "Undo", restore, function(use: Use): boolean
						return use(editingEnabled) and use(undo) ~= nil
					end, wide),
					UI.Menu "FileActions" {
						label = "Actions",
						Visible = short,
						items = actionItems,
					},
					button("ShowFilters", "Search & options", function()
						filtersOpen:set(not filtersOpen:peek())
					end, nil, short),
				},
				Compose.show(wide, fileOptions),
				UI.Sheet "FileOptionsSheet" {
					title = "Search & options",
					isPresented = filtersOpen,
					detent = filtersDetent,
					detents = optionDetents,
					content = function(): Instance
						return UI.VStack "FileOptionsBody" {
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
					text = function(use: Use): string
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
				UI.VStack "Contents" {
					Host.UISizeConstraint { MinSize = ctx.types.Vector2.new(0, 320) },
					width = "fill",
					height = "fill",
					UI.fill(),
					Compose.show(function(use: Use): boolean
						return use(state) == "ready"
					end, function(): Instance
						return folderViews()
					end, function(): Instance
						return UI.VStack {
							width = "fill",
							gap = "m",
							UI.Text {
								text = function(use: Use): string
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
			return UI.ScrollView "FileViewport" { width = "fill", height = "fill", page }
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
				linkedPath = paths.linked,
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
				reorder = function(keys: { string }, slot: number)
					reorder(keys, slot, filtered)
				end,
			},
			report = function()
				local order: { string } = {}
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
