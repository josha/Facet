--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)

local document = require("./document")
local library = require("./library")
local history = require("./history")
local templates = require("./templates")
local render = require("./design_render")
local export = require("./export")
local sourceReader = require("./source")
local shell = require("./design_shell")
local workbench = require("./workbench")
local transfer = require("./transfer")
local savedLibrary = require("./saved_library")
local galleryPages = require("./gallery")

local designer = {}

function designer.mount(Facet: any, parent: Instance, dependencies: any): any
	local Compose: ComposeModule = Facet.Compose
	local saved = dependencies.read and dependencies.read() or {}
	local initial = templates[1]
	if saved.draft and pcall(document.validate, saved.draft) then
		initial = saved.draft
	end
	local stack = history.new(initial)
	local selected, interactive = Compose.cell(initial.root.id), Compose.cell(false)
	local model = Compose.cell({
		compact = (parent :: any).AbsoluteSize.X < 980,
		pane = "Canvas",
		name = initial.name,
		selected = initial.root.id,
		selectedKind = "Screen",
		rows = {},
		fields = {},
		status = "Ready",
		code = "",
		showCode = false,
		device = "Phone",
		palette = "Light",
		textSize = "Medium",
		comparison = "Single",
		zoom = if (parent :: any).AbsoluteSize.X >= 980 then "Fit" else "Width",
		canUndo = false,
		canRedo = false,
		canEditLayer = false,
		interactive = false,
		menu = {},
		menuTitle = "",
		menuQuery = "",
		dataTitle = "",
		dataFields = {},
		dataArray = false,
		galleryTitle = "",
		galleryEntries = {} :: { { id: string, value: any } },
		galleryQuery = "",
		galleryPage = 1,
		transferTitle = "",
		transferText = "",
		transferEditable = false,
	})
	local view, bench: any
	local automaticZoom = true
	local actions: any = {}
	local menuCallback: any
	local disposed = false
	local function jsonEncode(value)
		return game:GetService("HttpService"):JSONEncode(value)
	end
	local function jsonDecode(text)
		return game:GetService("HttpService"):JSONDecode(text)
	end
	local structured: any
	local galleryCallback: any
	local transferCallback: any
	local function patch(values: any)
		model:update(function(previous)
			local nextValue = table.clone(previous)
			for key, value in values do
				nextValue[key] = value
			end
			return nextValue
		end)
	end
	local function attempt<T...>(callback: () -> T...): boolean
		local ok, err = pcall(function()
			callback()
			return true
		end)
		if not ok then
			patch({ status = string.match(tostring(err), ":%d+: (.+)") or tostring(err) })
		end
		return ok
	end
	local function persist()
		saved.draft = stack.current()
		if dependencies.write then
			dependencies.write(saved)
		end
	end
	local function sync(rebuild: boolean?)
		local value, id = stack.current()
		local node, parent = document.find(value.root, id)
		assert(node)
		local fields: { any } = {
			{ id = id .. ".name", key = "name", label = "Layer name", kind = "string" :: "string", value = node.name },
		}
		for _, descriptor in library.definitions[node.kind].fields do
			if
				(descriptor.kind == "column" and (not parent or parent.kind ~= "Table"))
				or (descriptor.kind == "binding" and not document.collection(value, id))
				or not library.visible(node.kind, descriptor.key, node.props)
			then
				continue
			end
			local item = table.clone(descriptor)
			if descriptor.kind == "column" then
				item.options = {}
				for _, column in assert(parent).props.columns or library.definitions.Table.defaults.columns do
					table.insert(item.options, column.id)
				end
			end
			item.id = id .. "." .. item.key
			item.explicit = node.props[item.key] ~= nil
			item.value = node.props[item.key]
			if item.value == nil then
				item.value = library.definitions[node.kind].defaults[item.key]
			end
			table.insert(fields, item)
		end
		if node.kind == "Table" then
			table.insert(fields, {
				id = id .. ".cells",
				key = "columnTemplates",
				label = "Reusable column cells",
				kind = "command",
				value = "Design a cell",
			})
		end
		selected:set(id)
		patch({
			name = value.name,
			selected = id,
			selectedKind = node.kind,
			rows = document.rows(value.root),
			fields = fields,
			code = export.component(value),
			canUndo = stack.canUndo(),
			canRedo = stack.canRedo(),
			canEditLayer = id ~= value.root.id,
		})
		if rebuild then
			bench.actions.design(
				render.definition(value, { selected = selected, interactive = interactive, select = actions.select })
			)
			local state = bench.model:peek()
			patch({
				status = if state.error ~= ""
					then state.error
					else "Design updated · " .. tostring(#document.rows(value.root)) .. " controls",
			})
			attempt(persist)
		end
	end
	local function commit(callback: any): boolean
		return attempt(function()
			local value, id = stack.current()
			local nextValue, nextId = callback(value, id)
			document.validate(nextValue)
			assert(document.find(nextValue.root, nextId or id), "Selection does not exist")
			local applied = bench.actions.design(
				render.definition(
					nextValue,
					{ selected = selected, interactive = interactive, select = actions.select }
				)
			)
			assert(applied, bench.model:peek().error)
			local ok, err = pcall(function()
				if dependencies.updateSource then
					dependencies.updateSource(nextValue, export.component(nextValue))
				end
				return true
			end)
			if not ok then
				bench.actions.design(
					render.definition(
						value,
						{ selected = selected, interactive = interactive, select = actions.select }
					)
				)
				error(err, 0)
			end
			stack.commit(nextValue, nextId or id)
			sync(false)
			persist()
			patch({ status = "Design updated · " .. tostring(#document.rows(nextValue.root)) .. " controls" })
		end)
	end
	local function gallery(title: string, entries: { any }, callback: any)
		galleryCallback = callback
		patch({
			galleryTitle = title,
			galleryEntries = entries,
			galleryQuery = "",
			galleryPage = 1,
			menuTitle = "",
			menu = {},
		})
	end
	actions.galleryClose = function()
		galleryCallback = nil
		patch({ galleryTitle = "", galleryEntries = {} })
	end
	actions.galleryPick = function(id)
		for _, entry in model:peek().galleryEntries do
			if entry.id == id then
				local callback = galleryCallback
				actions.galleryClose()
				attempt(function()
					callback(entry.value)
				end)
				return
			end
		end
	end
	actions.gallerySearch = function(query)
		patch({ galleryQuery = query, galleryPage = 1 })
	end
	actions.galleryPage = function(delta)
		local state = model:peek()
		local _, pages = galleryPages.page(state.galleryEntries, state.galleryQuery, state.galleryPage)
		patch({ galleryPage = math.clamp(state.galleryPage + delta, 1, pages) })
	end
	local function textDialog(title: string, text: string, editable: boolean, callback: any)
		transferCallback = callback
		patch({
			transferTitle = title,
			transferText = text,
			transferEditable = editable,
			galleryTitle = "",
			galleryEntries = {},
		})
	end
	actions.transferClose = function()
		transferCallback = nil
		patch({ transferTitle = "", transferText = "" })
	end
	actions.transferApply = function(text)
		if transferCallback and attempt(function()
			transferCallback(text)
		end) then
			actions.transferClose()
		end
	end
	local function menu(title, entries, callback)
		menuCallback = callback
		patch({ menuTitle = title, menu = entries, menuQuery = "" })
	end
	actions.menuPick = function(value)
		local callback = menuCallback
		menuCallback = nil
		patch({ menu = {}, menuTitle = "" })
		if callback then
			attempt(function()
				callback(value)
			end)
		end
	end
	actions.menuClose = function()
		menuCallback = nil
		patch({ menu = {}, menuTitle = "" })
	end
	actions.menuSearch = function(value)
		patch({ menuQuery = value })
	end
	actions.pane = function(name)
		patch({ pane = name, showCode = false })
	end
	actions.select = function(id)
		attempt(function()
			stack.select(id)
			sync(false)
			if model:peek().compact then
				patch({ pane = "Inspector" })
			end
		end)
	end
	actions.property = function(key, value)
		commit(function(current, id)
			return document.change(current, id, key, value)
		end)
	end
	local function showStructured()
		local fields: { any } = {}
		local function flatten(item: any, path: any, label: string)
			if type(item) == "table" then
				local keys: { any } = {}
				for key in item do
					table.insert(keys, key)
				end
				table.sort(keys, function(a, b)
					if type(a) == type(b) then
						return a < b
					end
					return type(a) == "number"
				end)
				for _, key in keys do
					local nextPath = table.clone(path)
					table.insert(nextPath, key)
					flatten(item[key], nextPath, if label == "" then tostring(key) else label .. " / " .. tostring(key))
				end
			else
				table.insert(fields, { id = label, path = path, label = label, value = item, kind = type(item) })
			end
		end
		flatten(structured.value, {}, "")
		patch({ dataFields = fields, dataTitle = structured.label, dataArray = #structured.value > 0 })
	end
	actions.editStructured = function(key)
		local value, id = stack.current()
		local node = assert(document.find(value.root, id))
		local descriptor = assert(library.descriptor(node.kind, key))
		structured = {
			key = key,
			selected = id,
			label = descriptor.label,
			value = document.copy(
				node.props[key] or library.definitions[node.kind].defaults[key] or descriptor.exemplar or {}
			),
		}
		showStructured()
	end
	actions.dataProperty = function(path, proposed, kind)
		attempt(function()
			local value = structured.value
			for index = 1, #path - 1 do
				value = value[path[index]]
			end
			value[path[#path]] = if kind == "number" then assert(tonumber(proposed), "Enter a number") else proposed
			showStructured()
		end)
	end
	actions.dataField = function()
		textDialog("Add field · path = JSON value", 'label = "New label"', true, function(text)
			assert(structured, "Choose data to edit")
			local path, literal = string.match(text, "^%s*(.-)%s*=%s*(.+)$")
			assert(path and literal, "Enter path = JSON value")
			local keys = string.split(path, "/")
			assert(#keys > 0 and #keys <= 12 and keys[#keys] ~= "", "Enter a field path")
			local value = document.copy(structured.value)
			local target = value
			for index, key in keys do
				local at: any = tonumber(key) or key
				if index == #keys then
					target[at] = jsonDecode(literal)
				else
					target[at] = target[at] or {}
					target = target[at]
				end
			end
			library.parse({ kind = "json" :: "json" }, value)
			structured.value = value
			showStructured()
		end)
	end
	actions.dataAdd = function()
		attempt(function()
			assert(structured, "Choose data to edit")
			local copied = document.copy(structured.value[#structured.value] or structured.exemplar or {})
			if type(copied) == "table" then
				if copied.id then
					copied.id = "item" .. tostring(#structured.value + 1)
				end
				if copied.value then
					copied.value = "item" .. tostring(#structured.value + 1)
				end
			end
			table.insert(structured.value, copied)
			showStructured()
		end)
	end
	actions.dataRemove = function()
		if structured and #structured.value > 0 then
			table.remove(structured.value)
			showStructured()
		end
	end
	actions.dataApply = function()
		if structured then
			local previous = structured
			local applied = commit(function(value)
				return document.change(value, previous.selected, previous.key, previous.value), previous.selected
			end)
			if applied then
				structured = nil
				patch({ dataTitle = "", dataFields = {} })
			end
		end
	end
	actions.dataClose = function()
		structured = nil
		patch({ dataTitle = "", dataFields = {} })
	end
	actions.chooseProperty = function(key, options)
		local entries = {}
		for _, value in options do
			table.insert(entries, { label = value, value = value })
		end
		menu("Choose " .. key, entries, function(value)
			actions.property(key, value)
		end)
	end
	actions.bindProperty = function(key)
		local value, id = stack.current()
		local collection = assert(document.collection(value, id), "Select a control in a reusable cell")
		local node = assert(document.find(value.root, id))
		local descriptor = assert(library.descriptor(node.kind, key))
		local rows = collection.props.from or library.definitions[collection.kind].defaults.from
		local names = {}
		for _, row in rows do
			for name, item in row do
				if
					type(name) == "string"
					and (type(item) == "string" or type(item) == "number" or type(item) == "boolean")
					and (descriptor.conversion ~= "number" or type(item) == "number")
				then
					names[name] = true
				end
			end
		end
		local entries = { { label = "Use static value", value = "" } }
		local ordered = {}
		for name in names do
			table.insert(ordered, name)
		end
		table.sort(ordered)
		for _, name in ordered do
			table.insert(entries, { label = name, value = name })
		end
		menu("Bind " .. descriptor.target .. " to a row field", entries, function(field)
			actions.property(key, if field == "" then nil else field)
		end)
	end
	actions.columnTemplates = function()
		local value, id = stack.current()
		local node = assert(document.find(value.root, id))
		assert(node.kind == "Table", "Select a table")
		local entries = {}
		for _, column in node.props.columns or library.definitions.Table.defaults.columns do
			table.insert(entries, { label = column.label or column.id, value = column.id })
		end
		menu("Design a reusable column cell", entries, function(column)
			commit(function(current)
				return document.columnTemplate(current, id, column)
			end)
		end)
	end
	actions.insertMenu = function()
		local value, id = stack.current()
		local node = assert(document.find(value.root, id))
		if node.kind == "Table" then
			actions.columnTemplates()
			return
		end
		local entries = {}
		for _, name in library.names() do
			if name ~= "Screen" then
				local preview = document.insert(document.new(name), "n1", name)
				table.insert(entries, {
					id = name,
					label = name,
					detail = library.definitions[name].category,
					value = name,
					design = preview,
				})
			end
		end
		gallery("Insert a Facet control", entries, function(kind)
			commit(function(value, id)
				return document.insert(value, id, kind)
			end)
		end)
	end
	actions.rename = function(name)
		commit(function(value)
			value.name = name
			return document.validate(value)
		end)
	end
	actions.duplicate = function()
		if model:peek().selected and model:peek().canEditLayer then
			commit(document.duplicate)
		end
	end
	actions.delete = function()
		if model:peek().selected and model:peek().canEditLayer then
			commit(document.remove)
		end
	end
	local function navigate(forward: boolean)
		attempt(function()
			local changed = if forward then stack.redo() else stack.undo()
			if not changed then
				return
			end
			local value = stack.current()
			if dependencies.updateSource then
				local ok, err = pcall(dependencies.updateSource, value, export.component(value))
				if not ok then
					if forward then
						stack.undo()
					else
						stack.redo()
					end
					error(err, 0)
				end
			end
			sync(true)
		end)
	end
	actions.undo = function()
		navigate(false)
	end
	actions.redo = function()
		navigate(true)
	end

	actions.moveMenu = function()
		local value, id = stack.current()
		local source = assert(document.find(value.root, id))
		local entries = {}
		for _, row in document.rows(value.root) do
			if library.definitions[row.kind].container and not document.find(source, row.id) then
				table.insert(entries, { label = row.name, value = row.id })
			end
		end
		menu("Move into a container", entries, function(target)
			commit(function(current, selection)
				return document.move(current, selection, target)
			end)
		end)
	end
	actions.reorderLayers = function(keys, slot)
		commit(function(value)
			return document.reorder(value, keys[1], slot), keys[1]
		end)
	end
	actions.renameLayer = function(id, name)
		return commit(function(value)
			return document.change(value, id, "name", name), id
		end)
	end
	local function load(value)
		if dependencies.disconnectSource then
			dependencies.disconnectSource()
		end
		stack.commit(document.validate(value), value.root.id)
		sync(true)
	end
	actions.templates = function()
		local entries = {}
		for index, value in templates do
			table.insert(entries, {
				id = tostring(index),
				label = value.name,
				detail = tostring(#document.rows(value.root)) .. " editable controls",
				value = index,
				design = value,
			})
		end
		gallery("Start from a template", entries, function(index)
			load(templates[index])
		end)
	end
	actions.home = actions.templates
	actions.commands = function()
		local entries = {
			{ label = "Insert control", value = actions.insertMenu },
			{ label = "Start from a template", value = actions.templates },
			{ label = "My designs", value = actions.saved },
			{ label = "Save design", value = actions.save },
			{ label = "Edit Luau code", value = actions.code },
			{ label = "Export Luau", value = actions.export },
			{ label = "Export design file", value = actions.exportFile },
			{ label = "Import design file", value = actions.importFile },
		}
		if next(saved.archived or {}) then
			table.insert(entries, { label = "Recently removed", value = actions.restoreSaved })
		end
		if dependencies.import then
			table.insert(entries, { label = "Import selected component", value = actions.import })
		end
		menu("Design commands", entries, function(callback)
			callback()
		end)
	end
	actions.save = function()
		attempt(function()
			local value = stack.current()
			local proposed = document.copy(saved)
			proposed.designs = proposed.designs or {}
			proposed.designs[value.name] = value
			proposed.draft = value
			local clean = savedLibrary.validate(proposed)
			if dependencies.write then
				dependencies.write(clean)
			end
			saved = clean
			patch({ status = "Saved “" .. value.name .. "”" })
			if dependencies.flush then
				patch({ status = "Saving to your private library…" })
				dependencies.flush()
			end
		end)
	end
	actions.saved = function()
		local entries = {}
		for name in saved.designs or {} do
			table.insert(entries, {
				id = name,
				label = name,
				detail = tostring(#document.rows(saved.designs[name].root)) .. " controls · Private",
				value = name,
				design = saved.designs[name],
			})
		end
		table.sort(entries, function(a, b)
			return a.label < b.label
		end)
		gallery("My designs", entries, function(name)
			load(saved.designs[name])
		end)
	end
	actions.exportFile = function()
		attempt(function()
			textDialog("Export design file · copy this text", transfer.encode(stack.current(), jsonEncode), false, nil)
		end)
	end
	actions.importFile = function()
		textDialog("Import design file · paste its text", "", true, function(text)
			local value = transfer.decode(text, jsonDecode)
			local applied = commit(function()
				return value, value.root.id
			end)
			assert(applied, model:peek().status)
		end)
	end
	local function saveLibrary(proposed)
		local clean = savedLibrary.validate(proposed)
		if dependencies.write then
			dependencies.write(clean)
		end
		saved = clean
		if dependencies.flush then
			dependencies.flush()
		end
	end
	actions.galleryManage = function(name: string)
		if model:peek().galleryTitle ~= "My designs" then
			return
		end
		actions.galleryClose()
		menu(name, {
			{ label = "Rename", value = "rename" },
			{ label = "Duplicate", value = "duplicate" },
			{ label = "Remove from library", value = "remove" },
		}, function(command)
			if command == "rename" then
				textDialog("Rename saved design", name, true, function(proposed: string)
					assert(proposed ~= "" and #proposed <= 120, "Enter a name of 1 to 120 bytes")
					assert(proposed == name or saved.designs[proposed] == nil, "A design already has that name")
					local nextValue = document.copy(saved)
					local value = assert(nextValue.designs[name])
					nextValue.designs[name] = nil
					value.name = proposed
					nextValue.designs[proposed] = value
					saveLibrary(nextValue)
					patch({ status = "Renamed “" .. proposed .. "”" })
				end)
			elseif command == "duplicate" then
				local nextValue = document.copy(saved)
				local value = document.copy(assert(nextValue.designs[name]))
				local suffix = 1
				while nextValue.designs[string.sub(name, 1, 104) .. " copy " .. tostring(suffix)] do
					suffix += 1
				end
				value.name = string.sub(name, 1, 104) .. " copy " .. tostring(suffix)
				nextValue.designs[value.name] = value
				saveLibrary(nextValue)
				actions.saved()
			else
				menu("Remove “" .. name .. "”?", {
					{ label = "Remove (can restore later)", value = true },
					{ label = "Cancel", value = false },
				}, function(confirmed)
					if not confirmed then
						return
					end
					local nextValue = document.copy(saved)
					local previous = assert(nextValue.designs[name])
					nextValue.designs[name] = nil
					nextValue.archived = nextValue.archived or {}
					nextValue.archived[name] = previous
					saveLibrary(nextValue)
					patch({ status = "Removed from library · Restore is in Design commands" })
				end)
			end
		end)
	end
	actions.restoreSaved = function()
		local entries = {}
		for name, value in saved.archived or {} do
			table.insert(
				entries,
				{ id = name, label = name, detail = "Restore to My designs", value = name, design = value }
			)
		end
		table.sort(entries, function(a, b)
			return a.label < b.label
		end)
		gallery("Recently removed", entries, function(name)
			assert(not saved.designs[name], "That name is in use. Rename it before restoring")
			local nextValue = document.copy(saved)
			nextValue.designs[name] = assert(nextValue.archived[name])
			nextValue.archived[name] = nil
			saveLibrary(nextValue)
			actions.saved()
		end)
	end
	actions.import = function()
		attempt(function()
			assert(dependencies.import, "Import from Explorer is available in the Studio plugin")
			stack = history.new(dependencies.import())
			sync(true)
			patch({ status = "Linked component · source and visual edits are synchronized" })
		end)
	end
	actions.applyCode = function(code)
		commit(function(value)
			return sourceReader.parse(code, value.name), "n1"
		end)
	end
	actions.code = function()
		patch({ showCode = not model:peek().showCode, pane = "Canvas" })
	end
	actions.export = function()
		attempt(function()
			local value = stack.current()
			if dependencies.export then
				dependencies.export(value, export.component(value), export.preview)
				patch({ status = "Exported “" .. value.name .. "” to ReplicatedStorage.FacetDesigns" })
			else
				patch({
					showCode = true,
					status = "Select and copy the generated Luau. Studio plugin export creates ModuleScripts.",
				})
			end
		end)
	end
	local choices = {
		device = { "Phone", "Tablet", "Desktop", "Television" },
		palette = { "Light", "Dark" },
		textSize = { "Medium", "Large", "Larger", "Largest" },
		comparison = { "Single", "Devices", "Palettes" },
		zoom = { "Width", "Fit", "50%", "75%", "100%", "150%" },
	}
	actions.layout = function(compact)
		if automaticZoom then
			local zoom = if compact then "Width" else "Fit"
			if model:peek().zoom ~= zoom then
				patch({ zoom = zoom })
				if bench then
					bench.actions.setting("zoom", zoom)
				end
			end
		end
	end
	actions.settingMenu = function(key)
		local entries = {}
		for _, value in choices[key] do
			table.insert(entries, { label = value, value = value })
		end
		menu("Preview " .. key, entries, function(value)
			if key == "zoom" then
				automaticZoom = false
			end
			bench.actions.setting(key, value)
			patch({ [key] = value })
		end)
	end
	actions.rotate = function()
		bench.actions.rotate()
	end
	actions.interactive = function()
		interactive:set(not interactive:peek())
		patch({ interactive = interactive:peek() })
	end
	view = shell.mount(
		Facet,
		parent,
		model,
		actions,
		{ inputParent = dependencies.inputParent or parent, keyboardNavigation = dependencies.keyboardNavigation }
	)
	bench = workbench.mount(
		Facet,
		view.canvas,
		{ roots = {}, canvasOnly = true, inputParent = dependencies.inputParent or parent, keyboardNavigation = false }
	)
	bench.actions.setting("palette", "Light")
	bench.actions.setting("zoom", model:peek().zoom)
	sync(true)
	local sourceConnection = dependencies.watchSource
		and dependencies.watchSource(function(value, err)
			if disposed then
				return
			end
			if err then
				patch({ status = tostring(err) .. " · visual source writes paused" })
			else
				stack.commit(document.validate(value), value.root.id)
				sync(true)
			end
		end)
	return {
		model = model,
		actions = actions,
		view = view,
		document = function()
			return stack.current()
		end,
		dispose = function()
			if disposed then
				return
			end
			disposed = true
			if sourceConnection then
				sourceConnection:Disconnect()
			end
			attempt(persist)
			bench.dispose()
			view.dispose()
		end,
	}
end

return designer
