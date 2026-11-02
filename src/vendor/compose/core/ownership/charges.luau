--!strict

local Weak = require "../weak"

type Counts = { [string]: number }

return function(tracked: { charges: number })
	local charge: { [unknown]: { owner: unknown, custody: string } } = {}

	Weak.keys(charge)

	local ownerCounts: { [unknown]: Counts } = {}

	Weak.keys(ownerCounts)

	local function releaseCharge(node: unknown)
		local previous = charge[node]
		if previous == nil then
			return
		end
		charge[node] = nil
		tracked.charges -= 1
		local bucket = ownerCounts[previous.owner]
		if bucket ~= nil then
			bucket[previous.custody] -= 1
		end
	end

	local function chargeToOwner(owner: unknown, node: unknown, kind: string)
		if owner == nil then
			return
		end
		releaseCharge(node)
		local bucket = ownerCounts[owner]
		if bucket == nil then
			bucket = { owned = 0, adopted = 0, borrowed = 0 }
			ownerCounts[owner] = bucket
		end
		tracked.charges += 1
		charge[node] = { owner = owner, custody = kind }
		bucket[kind] += 1
	end

	local function resetCharges()
		table.clear(charge)
		table.clear(ownerCounts)
		tracked.charges = 0
	end

	local function ownedCounts(owner: unknown): { ownedNodes: number, borrowedNodes: number }
		local bucket = ownerCounts[owner]
		if bucket == nil then
			return { ownedNodes = 0, borrowedNodes = 0 }
		end
		return { ownedNodes = bucket.owned + bucket.adopted, borrowedNodes = bucket.borrowed }
	end

	return {
		chargeToOwner = chargeToOwner,
		releaseCharge = releaseCharge,
		reset = resetCharges,
		ownedCounts = ownedCounts,
	}
end
