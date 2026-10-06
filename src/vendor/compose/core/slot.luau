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
	local parent = explicit
	if parent == nil then
		parent = Active.current()
		if parent == nil then
			Diagnostics.raise("slot/no-active-owner", "createSlot ran outside an owner", {
				contract = "a slot cannot outlive the owner responsible for what it holds",
				fix = "create it inside a component, Compose.withOwner(owner, ...), or pass an owner",
			})
		end
	elseif type(parent) ~= "table" or type((parent :: Owner.Owner).createChild) ~= "function" then
		Diagnostics.raise("slot/invalid-owner", "a slot can only be bound to an owner", {
			actual = Diagnostics.describe(parent),
			expected = "an owner from Compose.createOwner or owner.createChild",
		})
	end
	local scope = (parent :: Owner.Owner).createChild()
	local currentKey: unknown = nil
	local currentOwner: Owner.Owner? = nil
	scope.own(function()
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
			owner.dispose()
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
		if scope.isDisposed() or currentKey == key then
			return false
		end
		local staged = scope.createChild()
		local ok, failure: unknown = pcall(function()
			Active.withOwner(staged, function()
				attach(staged, function()
					release(key)
				end)
			end)
			return nil
		end)
		if not ok then
			pcall(staged.dispose)
			error(failure, 0)
		end
		if scope.isDisposed() then
			return false
		end
		local prior = currentOwner
		currentKey = key
		currentOwner = staged
		if prior ~= nil then
			prior.dispose()
		end
		return true
	end

	return {
		bind = bind,
		release = release,
		current = function(): unknown
			return currentKey
		end,
		dispose = scope.dispose,
	}
end

return createSlot
