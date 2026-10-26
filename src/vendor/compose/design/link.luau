--!strict

local Core = require "../core"
local Session = require "./session"
local Source = require "./source"
local Types = require "./types"

export type Status = "synchronized" | "custom" | "conflict"

export type Store = Types.LinkStore

export type Link = {
	status: Core.Value<Status>,
	import: () -> boolean,
	dispose: () -> (),
}

local CHANGED = "Source changed outside the editor. Import it before editing visually"
local CUSTOM = "The linked source is custom code. Import a generated design before editing visually"

return function(session: Session.Session, store: Store): Link
	local library = session.library
	local initial: Status = "custom"
	local status: Core.Value<Status> = Core.cell(initial)
	local last = ""
	local baseline = ""
	local applying = false
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
		baseline = Source.emit(value, library)
		if Source.emit(session.document:peek(), library) ~= baseline then
			applying = true
			session.replace(value)
			applying = false
		end
		status:set "synchronized"
		session.problem:set(nil)
		return true
	end
	local owner = Core.createRootOwner(function()
		Core.watch(function(use: Core.Use)
			local value = use(session.document)
			if applying or status:peek() ~= "synchronized" then
				return
			end
			local generated = Source.emit(value, library)
			if generated == baseline then
				return
			end
			if store.write(last, generated) then
				last, baseline = generated, generated
			else
				status:set "conflict"
				session.problem:set(CHANGED)
			end
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
			stop()
			owner.dispose()
		end,
	}
end
