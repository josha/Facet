--!strict

local Diagnostics = require "../diagnostics"
local Host = require "../host"

type Node = Host.Node

export type Custody = "owned" | "adopted" | "borrowed"

local WEAK_KEYS = table.freeze { __mode = "k" }

local custody: { [any]: Custody } = setmetatable({}, WEAK_KEYS) :: any

local function assertReference(node: Node, operation: string)
	local kind = type(node)
	if kind == "table" or kind == "userdata" then
		return
	end
	Diagnostics.raise(
		"host/node-not-a-reference",
		("%s received a node that is not a reference value"):format(operation),
		{
			actual = Diagnostics.describe(node),
			expected = "a table or userdata",
			contract = "host nodes must be reference values so custody and identity can be tracked",
		}
	)
end

local function mark(node: Node, kind: Custody)
	custody[node] = kind
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

local function isDestructible(node: Node): boolean
	local known = custody[node]
	return known == "owned" or known == "adopted"
end

local dependents: { [any]: { () -> () } } = setmetatable({}, WEAK_KEYS) :: any

local function attachDependent(node: Node, dispose: () -> ()): () -> ()
	assertReference(node, "mount")
	local list = dependents[node]
	if list == nil then
		list = {}
		dependents[node] = list
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
	local list = dependents[node]
	if list == nil then
		return
	end
	dependents[node] = nil
	local failure: string? = nil
	for index = #list, 1, -1 do
		local ok, err: any = pcall(list[index])
		if not ok and failure == nil then
			failure = tostring(err)
		end
	end
	if failure ~= nil then
		error(failure, 0)
	end
end

local labels: { [any]: string } = setmetatable({}, WEAK_KEYS) :: any

local function label(node: Node, name: string)
	labels[node] = name
end

local function labelOf(node: Node): string?
	return labels[node]
end

export type OwnedCounts = { ownedNodes: number, borrowedNodes: number }

local charge: { [any]: { owner: any, custody: Custody } } = setmetatable({}, WEAK_KEYS) :: any

local ownerCounts: { [any]: { owned: number, adopted: number, borrowed: number } } = setmetatable({}, WEAK_KEYS) :: any

local function bucketFor(owner: any)
	local bucket = ownerCounts[owner]
	if bucket == nil then
		bucket = { owned = 0, adopted = 0, borrowed = 0 }
		ownerCounts[owner] = bucket
	end
	return bucket
end

local function chargeToOwner(owner: any, node: Node, kind: Custody)
	if owner == nil then
		return
	end
	local previous = charge[node]
	if previous ~= nil then
		local previousBucket = ownerCounts[previous.owner]
		if previousBucket ~= nil then
			previousBucket[previous.custody] -= 1
		end
	end
	charge[node] = { owner = owner, custody = kind }
	bucketFor(owner)[kind] += 1
end

local function releaseCharge(node: Node)
	local previous = charge[node]
	if previous == nil then
		return
	end
	charge[node] = nil
	local bucket = ownerCounts[previous.owner]
	if bucket ~= nil then
		bucket[previous.custody] -= 1
	end
end

local function resetCharges()
	table.clear(charge)
	table.clear(ownerCounts)
end

local function ownedCounts(owner: any): OwnedCounts
	local bucket = ownerCounts[owner]
	if bucket == nil then
		return { ownedNodes = 0, borrowedNodes = 0 }
	end
	return { ownedNodes = bucket.owned + bucket.adopted, borrowedNodes = bucket.borrowed }
end

local function forget(node: Node)
	custody[node] = nil
	labels[node] = nil
	releaseCharge(node)
	releaseDependents(node)
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
	resetCharges()
end

return {
	mark = mark,
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
	releaseCharge = releaseCharge,
	resetCharges = resetCharges,
	ownedCounts = ownedCounts,
	resetForTests = resetForTests,
}
