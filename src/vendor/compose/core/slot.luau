--!strict

local Active = require "./ownership/active"
local Diagnostics = require "./diagnostics"
local Owner = require "./ownership/owner"

export type Slot = {
	bind: (key: unknown, attach: (owner: Owner.Owner, release: () -> ()) -> ()) -> boolean,
	release: (key: unknown) -> boolean,
	current: () -> unknown,
	dispose: () -> (),
}

local function createSlot(explicit: Owner.Owner?): Slot
	if explicit ~= nil and (not Owner.isOwner(explicit)) then
		Diagnostics.raise("slot/invalid-owner", "a slot can only be bound to an owner", {
			actual = Diagnostics.describe(explicit),
			expected = "an owner from Compose.createOwner or Compose.owner.createChild",
		})
	end
	local parent = explicit or Active.current()
	if parent == nil then
		return Diagnostics.raise("slot/no-active-owner", "createSlot ran outside an owner", {
			contract = "a slot cannot outlive the owner responsible for what it holds",
			fix = "create it inside a component, Compose.withOwner(owner, ...), or pass an owner",
		})
	end
	local scope = Owner.createChild(parent)
	local currentKey: unknown = nil
	local currentOwner: Owner.Owner? = nil
	Owner.own(scope, function()
		currentKey = nil
		currentOwner = nil
	end)

	local function release(key: unknown): boolean
		if key == nil or currentKey ~= key then
			return false
		end
		currentKey = nil
		local owner = currentOwner
		currentOwner = nil
		if owner ~= nil then
			Owner.dispose(owner)
		end
		return true
	end

	local function bind(key: unknown, attach: (owner: Owner.Owner, release: () -> ()) -> ()): boolean
		if key == nil or key ~= key then
			Diagnostics.raise("slot/invalid-key", "a slot key must be a value other than nil or NaN", {
				actual = Diagnostics.describe(key),
				expected = "the value the slot holds the attachment for",
			})
		end
		if type(attach) ~= "function" then
			Diagnostics.raise("slot/invalid-attach", "a slot needs a function that attaches the new value", {
				actual = Diagnostics.describe(attach),
				expected = "a function receiving the owner for the attachment and a release callback",
			})
		end
		if Owner.isDisposed(scope) or currentKey == key then
			return false
		end
		local staged = Owner.createChild(scope)
		local ok, failure: unknown = pcall(function()
			Active.withOwner(staged, function()
				attach(staged, function()
					release(key)
				end)
			end)
			return nil
		end)
		if not ok then
			pcall(Owner.dispose, staged)
			error(failure, 0)
		end
		if Owner.isDisposed(scope) then
			return false
		end
		local prior = currentOwner
		currentKey = key
		currentOwner = staged
		if prior ~= nil then
			Owner.dispose(prior)
		end
		return true
	end

	return {
		bind = bind,
		release = release,
		current = function(): unknown
			return currentKey
		end,
		dispose = Owner.disposer(scope),
	}
end

return createSlot
