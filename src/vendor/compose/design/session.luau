--!strict

local Core = require "../core"
local Types = require "./types"
local Document = require "./document"
local History = require "./history"

type Cell<T> = Core.Value<T>
type ReadOnlyValue<T> = Core.ReadOnlyValue<T>

export type Session = {
	library: Types.Library,
	document: Cell<Types.Document>,
	selected: Cell<string>,
	hovered: Cell<string?>,
	problem: Cell<string?>,
	canUndo: Cell<boolean>,
	canRedo: Cell<boolean>,
	select: (id: string) -> (),
	selectRelative: (direction: "parent" | "child" | "next" | "previous") -> (),
	insert: (kind: string) -> boolean,
	change: (key: string, value: Types.Value?) -> boolean,
	changeMany: (changes: { [string]: Types.Value }) -> boolean,
	rename: (name: string) -> boolean,
	tag: (tags: { string }?) -> boolean,
	content: (key: string, kind: string) -> boolean,
	bind: (bind: Types.Bind?) -> boolean,
	move: (id: string, destination: string, before: number?) -> boolean,
	remove: () -> boolean,
	duplicate: () -> boolean,
	setContract: (contract: Types.Contract) -> boolean,
	replace: (value: Types.Document) -> boolean,
	undo: () -> boolean,
	redo: () -> boolean,
}

return function(library: Types.Library, initial: Types.Document): Session
	local history = History(Document.validate(initial, library))
	local document = Core.cell(history.current())
	local selected = Core.cell(initial.root.id)
	local none: string? = nil
	local hovered = Core.cell(none)
	local problem = Core.cell(none)
	local canUndo, canRedo = Core.cell(false), Core.cell(false)
	local function publish()
		local current = history.current()
		document:set(current)
		canUndo:set(history.canUndo())
		canRedo:set(history.canRedo())
		if Document.find(current.root, selected:peek()) == nil then
			selected:set(current.root.id)
		end
	end
	local function attempt(edit: (Types.Document, string) -> (Types.Document, string?)): boolean
		local ok, result, focus = pcall(edit, history.current(), selected:peek())
		if not ok then
			problem:set(tostring(result))
			return false
		end
		problem:set(nil)
		history.commit(result)
		if focus then
			selected:set(focus)
		end
		publish()
		return true
	end
	local session: Session
	session = {
		library = library,
		document = document,
		selected = selected,
		hovered = hovered,
		problem = problem,
		canUndo = canUndo,
		canRedo = canRedo,
		select = function(id: string)
			if Document.find(history.current().root, id) then
				selected:set(id)
			end
		end,
		selectRelative = function(direction: "parent" | "child" | "next" | "previous")
			local node, parent, index = Document.find(history.current().root, selected:peek())
			if node == nil then
				return
			end
			if direction == "parent" and parent then
				selected:set(parent.id)
			elseif direction == "child" and node.children[1] then
				selected:set(node.children[1].id)
			elseif parent and index and (direction == "next" or direction == "previous") then
				local step = if direction == "next" then 1 else -1
				selected:set(parent.children[(index - 1 + step) % #parent.children + 1].id)
			end
		end,
		insert = function(kind: string): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, string?)
				local node, parent = Document.find(value.root, id)
				local target = assert(node)
				local container = assert(library.kinds[target.kind])
				local host = if container.children == "none" and parent then parent.id else target.id
				return Document.insert(value, library, host, kind)
			end)
		end,
		change = function(key: string, property: Types.Value?): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, string?)
				return Document.change(value, library, id, key, property), nil
			end)
		end,
		changeMany = function(changes: { [string]: Types.Value }): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, string?)
				local result = value
				for key, property in changes do
					result = Document.change(result, library, id, key, property)
				end
				return result, nil
			end)
		end,
		content = function(key: string, kind: string): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, string?)
				return Document.content(value, library, id, key, kind)
			end)
		end,
		tag = function(tags: { string }?): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, string?)
				return Document.tag(value, library, id, tags), nil
			end)
		end,
		rename = function(name: string): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, string?)
				return Document.rename(value, library, id, name), nil
			end)
		end,
		bind = function(bind: Types.Bind?): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, string?)
				return Document.bind(value, library, id, bind), nil
			end)
		end,
		move = function(id: string, destination: string, before: number?): boolean
			return attempt(function(value: Types.Document): (Types.Document, string?)
				return Document.move(value, library, id, destination, before), id
			end)
		end,
		remove = function(): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, string?)
				local _, parent = Document.find(value.root, id)
				return Document.remove(value, library, id), if parent then parent.id else nil
			end)
		end,
		duplicate = function(): boolean
			return attempt(function(value: Types.Document, id: string): (Types.Document, string?)
				return Document.duplicate(value, library, id)
			end)
		end,
		setContract = function(contract: Types.Contract): boolean
			return attempt(function(value: Types.Document): (Types.Document, string?)
				return Document.setContract(value, library, contract), nil
			end)
		end,
		replace = function(nextValue: Types.Document): boolean
			return attempt(function(): (Types.Document, string?)
				return Document.validate(nextValue, library), nextValue.root.id
			end)
		end,
		undo = function(): boolean
			local moved = history.undo()
			publish()
			return moved
		end,
		redo = function(): boolean
			local moved = history.redo()
			publish()
			return moved
		end,
	}
	return session
end
