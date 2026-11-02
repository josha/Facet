--!strict

local Core = require "../core"
local Session = require "./session"
local Source = require "./source"
local Types = require "./types"
local Document = require "./document"

export type Status = "synchronized" | "custom" | "conflict"

export type Store = Types.LinkStore

export type Link = {
	status: Core.Value<Status>,
	import: () -> boolean,
	dispose: () -> (),
}

local CHANGED = "Conflict: source kept its changes; visual edits remain on stage. Import source to resolve"
local CUSTOM = "The linked source is custom code. Import a generated design before editing visually"

return function(session: Session.Session, store: Store): Link
	local library = session.library
	local initial: Status = "custom"
	local status: Core.Value<Status> = Core.cell(initial)
	local last = ""
	local baseline = ""
	local exported: string? = nil
	local applying = false
	local pending = false
	local disposed = false
	local function emit(value: Types.Document): string
		return Source.emit(value, library, if exported then { name = exported } else nil)
	end
	local function parsed(code: string): Types.Document?
		local ok, value = pcall(Source.parse, code, library)
		return if ok then value else nil
	end
	local function import(): boolean
		local code = store.read()
		local value = parsed(code)
		last = code
		if value == nil then
			status:set "custom"
			session.problem:set(CUSTOM)
			return false
		end
		exported = nil
		local generated = Source.emit(value, library)
		if generated ~= code then
			local ok, named = pcall(function(): string
				return Source.emit(value, library, { name = value.name })
			end)
			if ok and named == code then
				exported = value.name
			end
		end
		baseline = emit(value)
		if emit(session.document:peek()) ~= baseline then
			local old = session.document:peek()
			local paths: { [string]: string } = {}
			local replacements: { [string]: string } = {}
			local function index(node: Types.Node, path: string, into: { [string]: string }, reverse: boolean)
				if reverse then
					into[path] = node.id
				else
					into[node.id] = path
				end
				local occurrences: { [string]: number } = {}
				for _, child in node.children do
					local key = child.kind .. "\0" .. child.name
					occurrences[key] = (occurrences[key] or 0) + 1
					index(child, path .. "\1" .. key .. "\0" .. tostring(occurrences[key]), into, reverse)
				end
			end
			index(old.root, "", paths, false)
			index(value.root, "", replacements, true)
			local selected: { string } = {}
			for _, id in session.selection:peek() do
				local replacement = replacements[paths[id]]
				if replacement ~= nil and Document.find(value.root, replacement) then
					table.insert(selected, replacement)
				end
			end
			applying = true
			session.replace(value)
			if #selected > 0 then
				session.selectMany(selected)
			end
			applying = false
		end
		status:set "synchronized"
		session.problem:set(nil)
		return true
	end
	local save: () -> ()
	save = function()
		if pending or applying or disposed or status:peek() ~= "synchronized" then
			return
		end
		local function flush()
			if disposed or applying or status:peek() ~= "synchronized" then
				pending = false
				return
			end
			local generated = emit(session.document:peek())
			if generated == baseline then
				pending = false
				return
			end
			if last ~= baseline then
				status:set "custom"
				session.problem:set "Source formatting is custom. Visual edits would change unrelated bytes"
				pending = false
				return
			end
			if store.write(last, generated) then
				last, baseline = generated, generated
			else
				status:set "conflict"
				session.problem:set(CHANGED)
			end
			pending = false
			if status:peek() == "synchronized" and emit(session.document:peek()) ~= baseline then
				save()
			end
		end
		pending = true
		local defer = store.defer
		if defer then
			defer(flush)
		else
			flush()
		end
	end
	local owner = Core.createRootOwner(function()
		Core.watch(function(use: Core.Use)
			use(session.document)
			save()
		end)
	end)
	local stop = store.watch(function()
		local code = store.read()
		if code == last then
			return
		end
		if status:peek() == "conflict" then
			last = code
		else
			import()
		end
	end)
	import()
	return {
		status = status,
		import = import,
		dispose = function()
			disposed = true
			stop()
			owner.dispose()
		end,
	}
end
