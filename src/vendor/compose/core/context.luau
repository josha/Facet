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
		local owner = Active.nearest()
		while owner ~= nil do
			if Owner.isDisposed(owner) then
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
			pcall(Owner.dispose, owner)
			error(select(1, ...), 0)
		end
		return ...
	end

	local function provide<R...>(value: T, body: () -> R...): R...
		local parent = Active.current()
		local owner = if parent ~= nil then Owner.createChild(parent) else Owner.createOwner()
		if not Owner.isDisposed(owner) then
			provided[owner] = { value = value }
			Owner.own(owner, function()
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
