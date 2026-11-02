--!strict
--!native
local Weak = require "../weak"

local Diagnostics = require "../diagnostics"
local Host = require "../host"

type Node = Host.Node

export type Custody = "owned" | "adopted" | "borrowed"

local custody: { [unknown]: Custody } = {}

Weak.keys(custody)

local tracked = { dependents = 0, labels = 0, charges = 0 }

local inspecting = { active = false }

local function assertReference(node: Node, operation: string)
	local kind = type(node)
	if kind == "table" or kind == "userdata" then
		return
	end
	return Diagnostics.raise(
		"host/node-not-a-reference",
		("%s received a node that is not a reference value"):format(operation),
		{
			actual = Diagnostics.describe(node),
			expected = "a table or userdata",
			contract = "host nodes must be reference values so custody and identity can be tracked",
		}
	)
end

local function markOwned(node: Node)
	assertReference(node, "createNode")
	custody[node] = "owned"
end

local function markAdopted(node: Node)
	assertReference(node, "adopt")
	custody[node] = "adopted"
end

local function markBorrowed(node: Node)
	assertReference(node, "borrow")
	custody[node] = "borrowed"
end

local function custodyOf(node: Node): Custody
	local known: Custody? = custody[node]
	if known ~= nil then
		return known
	end
	return "borrowed"
end

local function isDestructible(node: unknown): boolean
	local known = custody[node]
	return known == "owned" or known == "adopted"
end

local dependents: { [Node]: { () -> () } } = {}

Weak.keys(dependents)

local function attachDependent(node: Node, dispose: () -> ()): () -> ()
	assertReference(node, "mount")
	local list = dependents[node]
	if list == nil then
		list = {}
		dependents[node] = list
		tracked.dependents += 1
	end
	table.insert(list, dispose)

	local detached = false
	return function()
		if detached then
			return
		end
		detached = true
		local current = dependents[node]
		if current == nil then
			return
		end
		local index = table.find(current, dispose)
		if index ~= nil then
			table.remove(current, index)
		end
	end
end

local function releaseDependents(node: Node)
	if tracked.dependents == 0 then
		return
	end
	local list = dependents[node]
	if list == nil then
		return
	end
	dependents[node] = nil
	tracked.dependents -= 1
	local failure: string? = nil
	for index = #list, 1, -1 do
		local ok, err: unknown = pcall(list[index])
		if not ok and failure == nil then
			failure = tostring(err)
		end
	end
	if failure ~= nil then
		error(failure, 0)
	end
end

local labels: { [Node]: string } = {}

Weak.keys(labels)

local function label(node: Node, name: string)
	if labels[node] == nil then
		tracked.labels += 1
	end
	labels[node] = name
end

local function labelOf(node: Node): string?
	return labels[node]
end

export type OwnedCounts = { ownedNodes: number, borrowedNodes: number }

type Charges = typeof((require "./charges")(tracked))
local charges: Charges? = nil

local function chargeToOwner(owner: unknown, node: Node, kind: Custody)
	local loaded = charges or (require "./charges")(tracked)
	charges = loaded
	loaded.chargeToOwner(owner, node, kind)
end

local function resetCharges()
	local loaded = charges
	if loaded ~= nil then
		loaded.reset()
	end
end

local function ownedCounts(owner: unknown): OwnedCounts
	local loaded = charges
	return if loaded ~= nil then loaded.ownedCounts(owner) else { ownedNodes = 0, borrowedNodes = 0 }
end

local function forget(node: Node)
	custody[node] = nil
	if tracked.labels > 0 and labels[node] ~= nil then
		labels[node] = nil
		tracked.labels -= 1
	end
	if tracked.charges > 0 then
		local loaded = charges
		if loaded ~= nil then
			loaded.releaseCharge(node)
		end
	end
	if tracked.dependents > 0 then
		releaseDependents(node)
	end
end

local function trackedCount(): number
	local total = 0
	for _ in custody do
		total += 1
	end
	return total
end

local function resetForTests()
	table.clear(custody)
	table.clear(dependents)
	table.clear(labels)
	tracked.dependents = 0
	tracked.labels = 0
	resetCharges()
end

return {
	inspecting = inspecting,
	tracked = tracked,
	markOwned = markOwned,
	markAdopted = markAdopted,
	markBorrowed = markBorrowed,
	custodyOf = custodyOf,
	label = label,
	labelOf = labelOf,
	isDestructible = isDestructible,
	attachDependent = attachDependent,
	releaseDependents = releaseDependents,
	forget = forget,
	trackedCount = trackedCount,
	chargeToOwner = chargeToOwner,
	resetCharges = resetCharges,
	ownedCounts = ownedCounts,
	resetForTests = resetForTests,
}
