--!strict
--!native

local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Weak = require "../weak"

type Node = Host.Node

export type Custody = "owned" | "adopted" | "borrowed"

type Counts = { owned: number, adopted: number, borrowed: number }

local custody: { [Node]: Custody } = {}

Weak.keys(custody)

local tracked = { dependents = 0, labels = 0, charges = 0 }

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
	local kind = type(node)
	if kind ~= "table" and kind ~= "userdata" then
		assertReference(node, "createNode")
	end
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

local charge: { [Node]: { owner: unknown, custody: Custody } } = {}

Weak.keys(charge)

local ownerCounts: { [unknown]: Counts } = {}

Weak.keys(ownerCounts)

local function bucketFor(owner: unknown): Counts
	local existing = ownerCounts[owner]
	if existing ~= nil then
		return existing
	end
	local bucket: Counts = { owned = 0, adopted = 0, borrowed = 0 }
	ownerCounts[owner] = bucket
	return bucket
end

local function adjust(bucket: Counts, kind: Custody, delta: number)
	if kind == "owned" then
		bucket.owned += delta
	elseif kind == "adopted" then
		bucket.adopted += delta
	else
		bucket.borrowed += delta
	end
end

local function chargeToOwner(owner: unknown, node: Node, kind: Custody)
	if owner == nil then
		return
	end
	local previous = charge[node]
	if previous ~= nil then
		local previousBucket = ownerCounts[previous.owner]
		if previousBucket ~= nil then
			adjust(previousBucket, previous.custody, -1)
		end
	else
		tracked.charges += 1
	end
	charge[node] = { owner = owner, custody = kind }
	adjust(bucketFor(owner), kind, 1)
end

local function releaseCharge(node: Node)
	if tracked.charges == 0 then
		return
	end
	local previous = charge[node]
	if previous == nil then
		return
	end
	charge[node] = nil
	tracked.charges -= 1
	local bucket = ownerCounts[previous.owner]
	if bucket ~= nil then
		adjust(bucket, previous.custody, -1)
	end
end

local function resetCharges()
	table.clear(charge)
	table.clear(ownerCounts)
	tracked.charges = 0
end

local function ownedCounts(owner: unknown): OwnedCounts
	local bucket = ownerCounts[owner]
	if bucket == nil then
		return { ownedNodes = 0, borrowedNodes = 0 }
	end
	return { ownedNodes = bucket.owned + bucket.adopted, borrowedNodes = bucket.borrowed }
end

local function forget(node: Node)
	custody[node] = nil
	if tracked.labels > 0 and labels[node] ~= nil then
		labels[node] = nil
		tracked.labels -= 1
	end
	if tracked.charges > 0 then
		releaseCharge(node)
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
	tracked = tracked,
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
