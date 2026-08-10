--!strict
-- RewardsService (spec §3, §9): Steam Stamps.
--
-- `stampsEarned` and `stampsSpent` are the durable halves; `unstamped` is the
-- set of SLOTS earned since the player last looked at the card, and it is the
-- whole of the stamp ceremony's state — the pop plays for those slots, once,
-- and `clearUnstamped()` at the moment the surface goes away is what makes it
-- once per visit rather than once per render.
--
-- Economy fixtures are the Game Designer's (spec §2): one stamp per confirmed
-- order, redeem at ten, redeem costs a flat ten.

local rewards = {}

rewards.THRESHOLD = 10
rewards.REDEEM_COST = 10

function rewards.new(opts: any)
	local core = opts.core
	local scope = opts.scope

	local earned = core:signal(opts.startEarned or 0)
	local spent = core:signal(opts.startSpent or 0)
	local unstamped = core:signal({} :: { [number]: boolean })
	scope:own(function()
		earned:dispose()
		spent:dispose()
		unstamped:dispose()
	end)

	local self = {}
	self.earned = earned
	self.spent = spent
	self.unstamped = unstamped

	function self.unspent(): number
		return earned:get() - spent:get()
	end

	-- how many of the card's ten seals are stamped right now
	function self.filled(): number
		return math.clamp(self.unspent(), 0, rewards.THRESHOLD)
	end

	function self.away(): number
		return math.max(0, rewards.THRESHOLD - self.filled())
	end

	function self.canRedeem(): boolean
		return self.unspent() >= rewards.THRESHOLD
	end

	-- earn(n) -> the slot indexes that are NEW. They are the pop timeline's
	-- beats, in slot order, and they survive until the card is visited.
	function self.earn(count: number): { number }
		local before = self.filled()
		core:transaction(function()
			earned:set(earned:get() + math.max(0, count))
		end)
		local after = self.filled()
		local fresh: { number } = {}
		local next = table.clone(unstamped:get())
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
		spent:set(spent:get() + rewards.REDEEM_COST)
		-- the card the player just spent is gone: nothing on it is "new" now
		unstamped:set({})
		return true
	end

	function self.clearUnstamped()
		if next(unstamped:get()) == nil then
			return
		end
		unstamped:set({})
	end

	function self.newSlots(): { number }
		local out: { number } = {}
		for slot in unstamped:get() do
			table.insert(out, slot)
		end
		table.sort(out)
		return out
	end

	function self.reset()
		core:transaction(function()
			earned:set(opts.startEarned or 0)
			spent:set(opts.startSpent or 0)
			unstamped:set({})
		end)
	end

	return self
end

return rewards
