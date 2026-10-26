--!strict

local Active = require "./ownership/active"
local Owner = require "./ownership/owner"

export type Context<T> = {
	provide: <R...>(value: T, body: () -> R...) -> R...,
	read: () -> T,
}

local function createContext<T>(default: T): Context<T>
	local provided: { [Owner.Owner]: { value: T } } = {}
	setmetatable(provided, { __mode = "k" })

	local function read(): T
		local owner = Active.current()
		while owner ~= nil do
			if owner.isDisposed() then
				return default
			end
			local entry = provided[owner]
			if entry ~= nil then
				return entry.value
			end
			owner = owner.parent
		end
		return default
	end

	local function finish<R...>(owner: Owner.Owner, ok: boolean, ...: R...): R...
		if not ok then
			pcall(owner.dispose)
			error(select(1, ...), 0)
		end
		return ...
	end

	local function provide<R...>(value: T, body: () -> R...): R...
		local parent = Active.current()
		local owner = if parent ~= nil then parent.createChild() else Owner.createOwner()
		if not owner.isDisposed() then
			provided[owner] = { value = value }
			owner.own(function()
				provided[owner] = nil
			end)
		end
		return finish(owner, pcall(Active.withOwner, owner, body))
	end

	return {
		provide = provide,
		read = read,
	}
end

return createContext
