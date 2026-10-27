--!strict

local Core = require "../core"
local Types = require "./types"
local Document = require "./document"
local History = require "./history"

type Cell<T> = Core.Value<T>
type SelectionMode = "replace" | "toggle" | "range"
type Change = Types.Value | ((node: Types.Node) -> Types.Value?)

export type Session = {
	library: Types.Library,
	document: Cell<Types.Document>,
	selected: Cell<string>,
	selection: Cell<{ string }>,
	hovered: Cell<string?>,
	problem: Cell<string?>,
	canUndo: Cell<boolean>,
	canRedo: Cell<boolean>,
	select: (id: string, mode: SelectionMode?) -> (),
	selectMany: (ids: { string }) -> (),
	selectRelative: (direction: "parent" | "child" | "next" | "previous") -> (),
	insert: (kind: string) -> boolean,
	change: (key: string, value: Change?) -> boolean,
	changeMany: (changes: { [string]: Types.Value }) -> boolean,
	rename: (name: string) -> boolean,
	tag: (tags: { string }?) -> boolean,
	content: (key: string, kind: string) -> boolean,
	bind: (bind: Types.Bind?) -> boolean,
	move: (id: string, destination: string, before: number?) -> boolean,
	remove: () -> boolean,
	duplicate: () -> boolean,
	copy: () -> boolean,
	paste: () -> boolean,
	shift: (step: number) -> boolean,
	wrap: () -> boolean,
	unwrap: () -> boolean,
	hide: (id: string, hidden: boolean) -> boolean,
	lock: (id: string, locked: boolean) -> boolean,
	setContract: (contract: Types.Contract) -> boolean,
	replace: (value: Types.Document) -> boolean,
	undo: () -> boolean,
	redo: () -> boolean,
}

return function(library: Types.Library, initial: Types.Document): Session
	local owner = Core.currentOwner()
	local reactor = if owner and owner.reactor then owner.reactor else Core.reactor.create()
	local clipboard: { Types.Node } = {}
	local history = History(Document.validate(initial, library))
	local document = Core.cell(history.current())
	local selected = Core.cell(initial.root.id)
	local selection = Core.cell { initial.root.id }
	local anchor = initial.root.id
	local past: { { string } } = {}
	local future: { { string } } = {}
	local none: string? = nil
	local hovered = Core.cell(none)
	local problem = Core.cell(none)
	local canUndo, canRedo = Core.cell(false), Core.cell(false)
	local function choose(ids: { string }, focus: string?)
		local ordered: { string } = {}
		for _, row in Document.nodes(history.current().root) do
			if table.find(ids, row.node.id) then
				table.insert(ordered, row.node.id)
			end
		end
		Core.reactor.batch(reactor, function()
			selection:set(ordered)
			selected:set(if focus and table.find(ordered, focus) then focus else ordered[#ordered] or "")
		end)
	end
	local function publish()
		document:set(history.current())
		canUndo:set(history.canUndo())
		canRedo:set(history.canRedo())
		choose(selection:peek(), selected:peek())
	end
	local function roots(value: Types.Document): { string }
		local result: { string } = {}
		local function visit(node: Types.Node)
			if table.find(selection:peek(), node.id) then
				table.insert(result, node.id)
			else
				for _, child in node.children do
					visit(child)
				end
			end
		end
		visit(value.root)
		return result
	end
	local function attempt(edit: (Types.Document, string) -> (Types.Document, { string }?)): boolean
		local ok, result, focus = pcall(edit, history.current(), selected:peek())
		if not ok then
			problem:set(tostring(result))
			return false
		end
		problem:set(nil)
		table.insert(past, table.clone(selection:peek()))
		if #past > 100 then
			table.remove(past, 1)
		end
		table.clear(future)
		Core.reactor.batch(reactor, function()
			history.commit(result)
			if focus then
				choose(focus, nil)
			end
			publish()
		end)
		return true
	end
	local function each(edit: (Types.Document, string) -> Types.Document): boolean
		return attempt(function(value: Types.Document): (Types.Document, { string }?)
			assert(#selection:peek() > 0, "Choose a node")
			local result = value
			for _, id in selection:peek() do
				result = edit(result, id)
			end
			return result, nil
		end)
	end
	local function detach(value: Types.Document, id: string): Types.Node
		local node, parent, index = Document.find(value.root, id)
		assert(node and parent and index, "The root cannot move or be removed")
		table.remove(parent.children, index)
		return node
	end
	local function twins(value: Types.Document, copied: { Types.Node }): { Types.Node }
		local result: { Types.Node } = {}
		local remapped: { [string]: string } = {}
		for _, node in copied do
			local twin = Document.copyNode(node)
			for _, row in Document.nodes(twin) do
				local id = `n{value.nextId}`
				value.nextId += 1
				remapped[row.node.id] = id
				row.node.id = id
			end
			table.insert(result, twin)
		end
		local function remapLiteral(literal: Types.Literal)
			if type(literal) == "table" then
				local template = literal["$template"]
				if type(template) == "string" and remapped[template] then
					literal["$template"] = remapped[template]
				end
				for _, child in literal do
					remapLiteral(child)
				end
			end
		end
		for _, twin in result do
			for _, row in Document.nodes(twin) do
				local bind = row.node.bind
				if bind and bind.row then
					bind.row = remapped[bind.row] or bind.row
				end
				for _, property in row.node.props do
					local id = property.node
					if id and remapped[id] then
						property.node = remapped[id]
					end
					if property.nodes then
						for index, target in property.nodes do
							property.nodes[index] = remapped[target] or target
						end
					end
					if property.literal ~= nil then
						remapLiteral(property.literal)
					end
				end
			end
		end
		return result
	end
	local session: Session
	session = {
		library = library,
		document = document,
		selected = selected,
		selection = selection,
		hovered = hovered,
		problem = problem,
		canUndo = canUndo,
		canRedo = canRedo,
		selectMany = function(ids: { string })
			choose(ids, nil)
			anchor = selected:peek()
		end,
		select = function(id: string, mode: SelectionMode?)
			local value = history.current()
			local node, parent, index = Document.find(value.root, id)
			if node == nil then
				return
			end
			if mode == "range" then
				local _, origin, at = Document.find(value.root, anchor)
				if parent and origin == parent and at and index then
					local ids: { string } = {}
					for position = math.min(at, index), math.max(at, index) do
						table.insert(ids, parent.children[position].id)
					end
					choose(ids, id)
					return
				end
			end
			if mode == "toggle" or mode == "range" then
				local ids = table.clone(selection:peek())
				local at = table.find(ids, id)
				if at then
					table.remove(ids, at)
				else
					table.insert(ids, id)
				end
				choose(ids, id)
			else
				choose({ id }, id)
			end
			anchor = id
		end,
		selectRelative = function(direction: "parent" | "child" | "next" | "previous")
			local node, parent, index = Document.find(history.current().root, selected:peek())
			if node == nil then
				return
			end
			if direction == "parent" and parent then
				session.select(parent.id)
			elseif direction == "child" and node.children[1] then
				session.select(node.children[1].id)
			elseif parent and index and (direction == "next" or direction == "previous") then
				local step = if direction == "next" then 1 else -1
				session.select(parent.children[(index - 1 + step) % #parent.children + 1].id)
			end
		end,
		insert = function(kind: string): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, { string }?)
				local node, parent, index = Document.find(value.root, id)
				local target = node or value.root
				local container = assert(library.kinds[target.kind])
				local result, focus
				if parent and index and (container.children == "none" or container.leaf == true) then
					result, focus = Document.insert(value, library, parent.id, kind, index + 1)
				else
					result, focus = Document.insert(value, library, target.id, kind)
				end
				return result, { focus }
			end)
		end,
		change = function(key: string, property: Change?): boolean
			return each(function(value: Types.Document, id: string): Types.Document
				local node = assert(Document.find(value.root, id), "Choose a node")
				local nextProperty = if type(property) == "function" then property(node) else property
				return Document.change(value, library, id, key, nextProperty)
			end)
		end,
		changeMany = function(changes: { [string]: Types.Value }): boolean
			return each(function(value: Types.Document, id: string): Types.Document
				local result = value
				for key, property in changes do
					result = Document.change(result, library, id, key, property)
				end
				return result
			end)
		end,
		content = function(key: string, kind: string): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, { string }?)
				local result, focus = Document.content(value, library, id, key, kind)
				return result, { focus }
			end)
		end,
		tag = function(tags: { string }?): boolean
			return each(function(value: Types.Document, id: string): Types.Document
				return Document.tag(value, library, id, tags)
			end)
		end,
		rename = function(name: string): boolean
			return each(function(value: Types.Document, id: string): Types.Document
				return Document.rename(value, library, id, name)
			end)
		end,
		bind = function(bind: Types.Bind?): boolean
			return each(function(value: Types.Document, id: string): Types.Document
				return Document.bind(value, library, id, bind)
			end)
		end,
		move = function(id: string, destination: string, before: number?): boolean
			return attempt(function(value: Types.Document): (Types.Document, { string }?)
				local ids: { string } = if table.find(selection:peek(), id) then roots(value) else { id }
				local result = Document.copy(value)
				local target = assert(Document.find(result.root, destination), "Choose a container")
				local moving: { Types.Node } = {}
				for _, current in ids do
					local node = assert(Document.find(result.root, current), "Choose a node")
					assert(Document.find(node, destination) == nil, "A node cannot move into itself")
					table.insert(moving, detach(result, current))
				end
				local at = math.clamp(before or #target.children + 1, 1, #target.children + 1)
				for offset, node in moving do
					table.insert(target.children, at + offset - 1, node)
				end
				return Document.validate(result, library), ids
			end)
		end,
		remove = function(): boolean
			return attempt(function(value: Types.Document): (Types.Document, { string }?)
				local ids = roots(value)
				assert(#ids > 0, "Choose a node")
				local _, parent = Document.find(value.root, ids[1])
				local result = Document.copy(value)
				for _, id in ids do
					detach(result, id)
				end
				return Document.validate(result, library), if parent then { parent.id } else {}
			end)
		end,
		duplicate = function(): boolean
			return attempt(function(value: Types.Document): (Types.Document, { string }?)
				local ids = roots(value)
				assert(#ids > 0, "Choose a node")
				local copied: { Types.Node } = {}
				for _, id in ids do
					local node, parent = Document.find(value.root, id)
					assert(node and parent, "The root cannot be duplicated")
					table.insert(copied, node)
				end
				local result = Document.copy(value)
				local focus: { string } = {}
				for index, twin in twins(result, copied) do
					local _, parent, at = Document.find(result.root, ids[index])
					assert(parent and at)
					table.insert(parent.children, at + 1, twin)
					table.insert(focus, twin.id)
				end
				return Document.validate(result, library), focus
			end)
		end,
		copy = function(): boolean
			local copied: { Types.Node } = {}
			for _, id in roots(history.current()) do
				local node, parent = Document.find(history.current().root, id)
				if node == nil or parent == nil then
					return false
				end
				table.insert(copied, Document.copyNode(node))
			end
			if #copied == 0 then
				return false
			end
			clipboard = copied
			return true
		end,
		paste = function(): boolean
			if #clipboard == 0 then
				return false
			end
			return attempt(function(value: Types.Document, id: string): (Types.Document, { string }?)
				local result = Document.copy(value)
				local node, parent, index = Document.find(result.root, id)
				local target = node or result.root
				local kind = library.kinds[target.kind]
				local at = #target.children + 1
				if parent and index and (kind.children ~= "list" or kind.leaf == true) then
					target, at = parent, index + 1
				end
				local focus: { string } = {}
				for offset, twin in twins(result, clipboard) do
					table.insert(target.children, at + offset - 1, twin)
					table.insert(focus, twin.id)
				end
				return Document.validate(result, library), focus
			end)
		end,
		shift = function(step: number): boolean
			return attempt(function(value: Types.Document): (Types.Document, { string }?)
				local ids = roots(value)
				assert(#ids > 0, "Choose a node")
				assert(step % 1 == 0 and step ~= 0, "Choose a nonzero integer step")
				local result = Document.copy(value)
				for _, id in ids do
					local _, parent = Document.find(result.root, id)
					assert(parent, "The root cannot move")
				end
				local changed = false
				for _ = 1, math.abs(step) do
					for _, row in Document.nodes(result.root) do
						local children = row.node.children
						for offset = 1, #children do
							local index = if step < 0 then offset else #children + 1 - offset
							local to = index + if step < 0 then -1 else 1
							if
								children[to]
								and table.find(ids, children[index].id)
								and not table.find(ids, children[to].id)
							then
								children[index], children[to] = children[to], children[index]
								changed = true
							end
						end
					end
				end
				assert(changed, "The selection is already at the edge")
				return Document.validate(result, library), nil
			end)
		end,
		wrap = function(): boolean
			return attempt(function(value: Types.Document): (Types.Document, { string }?)
				local ids = roots(value)
				assert(#ids > 0, "Choose siblings to wrap")
				local _, parent, at = Document.find(value.root, ids[1])
				assert(parent and at, "The root cannot be wrapped")
				for _, id in ids do
					local _, holder = Document.find(value.root, id)
					assert(holder == parent, "Choose siblings to wrap")
				end
				local kind = library.containerKind or value.root.kind
				assert(
					library.kinds[kind].children == "list" and library.kinds[kind].leaf ~= true,
					"Choose a default list container"
				)
				local result, focus = Document.insert(value, library, parent.id, kind, at)
				local container = assert(Document.find(result.root, focus), "Choose a container")
				table.clear(container.children)
				for _, id in ids do
					table.insert(container.children, detach(result, id))
				end
				return Document.validate(result, library), { focus }
			end)
		end,
		unwrap = function(): boolean
			return attempt(function(value: Types.Document): (Types.Document, { string }?)
				local ids = roots(value)
				assert(#ids > 0, "Choose a container")
				local result = Document.copy(value)
				local focus: { string } = {}
				for _, id in ids do
					local node, parent, at = Document.find(result.root, id)
					assert(node and parent and at, "The root cannot be unwrapped")
					assert(library.kinds[node.kind].children == "list", "Choose a list container")
					table.remove(parent.children, at)
					for offset, child in node.children do
						table.insert(parent.children, at + offset - 1, child)
						table.insert(focus, child.id)
					end
				end
				return Document.validate(result, library), focus
			end)
		end,
		hide = function(id: string, hidden: boolean): boolean
			return attempt(function(value: Types.Document): (Types.Document, { string }?)
				local result = Document.copy(value)
				assert(Document.find(result.root, id), "Choose a node").hidden = if hidden then true else nil
				return Document.validate(result, library), nil
			end)
		end,
		lock = function(id: string, locked: boolean): boolean
			return attempt(function(value: Types.Document): (Types.Document, { string }?)
				local result = Document.copy(value)
				assert(Document.find(result.root, id), "Choose a node").locked = if locked then true else nil
				return Document.validate(result, library), nil
			end)
		end,
		setContract = function(contract: Types.Contract): boolean
			return attempt(function(value: Types.Document): (Types.Document, { string }?)
				return Document.setContract(value, library, contract), nil
			end)
		end,
		replace = function(nextValue: Types.Document): boolean
			return attempt(function(): (Types.Document, { string }?)
				return Document.validate(nextValue, library), { nextValue.root.id }
			end)
		end,
		undo = function(): boolean
			if not history.undo() then
				return false
			end
			table.insert(future, table.clone(selection:peek()))
			Core.reactor.batch(reactor, function()
				choose(assert(table.remove(past)), nil)
				publish()
			end)
			return true
		end,
		redo = function(): boolean
			if not history.redo() then
				return false
			end
			table.insert(past, table.clone(selection:peek()))
			Core.reactor.batch(reactor, function()
				choose(assert(table.remove(future)), nil)
				publish()
			end)
			return true
		end,
	}
	return session
end
