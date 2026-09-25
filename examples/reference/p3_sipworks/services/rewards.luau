--!strict

local rewards = {}

rewards.THRESHOLD = 10
rewards.REDEEM_COST = 10

function rewards.new(opts: any)
	local Compose = opts.Compose

	local batch = opts.batch

	local earned = Compose.cell(opts.startEarned or 0)
	local spent = Compose.cell(opts.startSpent or 0)
	local unstamped = Compose.cell({} :: { [number]: boolean })

	local self = {}
	self.earned = earned
	self.spent = spent
	self.unstamped = unstamped

	function self.unspent(): number
		return earned:peek() - spent:peek()
	end

	function self.filled(): number
		return math.clamp(self.unspent(), 0, rewards.THRESHOLD)
	end

	function self.away(): number
		return math.max(0, rewards.THRESHOLD - self.filled())
	end

	function self.canRedeem(): boolean
		return self.unspent() >= rewards.THRESHOLD
	end

	function self.earn(count: number): { number }
		local before = self.filled()
		batch(function()
			earned:set(earned:peek() + math.max(0, count))
		end)
		local after = self.filled()
		local fresh: { number } = {}
		local next = table.clone(unstamped:peek())
		for slot = before + 1, after do
			table.insert(fresh, slot)
			next[slot] = true
		end
		unstamped:set(next)
		return fresh
	end

	function self.redeem(): boolean
		if not self.canRedeem() then
			return false
		end
		spent:set(spent:peek() + rewards.REDEEM_COST)

		unstamped:set({})
		return true
	end

	function self.clearUnstamped()
		if next(unstamped:peek()) == nil then
			return
		end
		unstamped:set({})
	end

	function self.newSlots(): { number }
		local out: { number } = {}
		for slot in unstamped:peek() do
			table.insert(out, slot)
		end
		table.sort(out)
		return out
	end

	function self.reset()
		batch(function()
			earned:set(opts.startEarned or 0)
			spent:set(opts.startSpent or 0)
			unstamped:set({})
		end)
	end

	return self
end

return rewards
