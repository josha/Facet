--!strict

local rewardsService = require("./rewards")

local task = {}

task.FIRST_BLEND = "amber-harvest"
task.FREE_POUR_BLEND = "mistral-mint"

task.PHASES = { "order", "placing", "rejected", "redeem", "done" }

export type Opts = {
	Compose: any,
	batch: (() -> ()) -> (),
	rewards: any,
	order: any,
}

function task.new(opts: Opts): any
	local Compose = opts.Compose

	local batch = opts.batch
	local rewards = opts.rewards
	local order = opts.order

	local served = Compose.cell(false)
	local redeemed = Compose.cell(false)
	local refused = Compose.cell(false)

	local self = {}
	self.served = served
	self.redeemed = redeemed
	self.refused = refused
	self.firstBlendId = task.FIRST_BLEND
	self.freePourBlendId = task.FREE_POUR_BLEND

	local stamps = Compose.formula(function(use)
		return math.clamp(use(rewards.earned) - use(rewards.spent), 0, rewardsService.THRESHOLD)
	end)
	local phase = Compose.formula(function(use)
		if use(redeemed) then
			return "done"
		end
		if use(order.status) == "pending" then
			return "placing"
		end
		if use(refused) then
			return "rejected"
		end
		if use(stamps) >= rewardsService.THRESHOLD then
			return "redeem"
		end
		return "order"
	end)

	local ctaBlendId = Compose.formula(function(use)
		return if use(phase) == "redeem" then task.FREE_POUR_BLEND else task.FIRST_BLEND
	end)
	self.stamps = stamps
	self.phase = phase
	self.ctaBlendId = ctaBlendId

	function self.noteConfirmed(mode: string)
		if mode == "redeem" then
			redeemed:set(true)
		else
			served:set(true)
		end
		refused:set(false)
	end

	function self.noteRejected()
		refused:set(true)
	end

	function self.notePlacing()
		refused:set(false)
	end

	function self.reset()
		batch(function()
			served:set(false)
			redeemed:set(false)
			refused:set(false)
		end)
	end

	function self.rows(): { { id: string, done: boolean } }
		return {
			{ id = "serve", done = served:peek() },
			{ id = "redeem", done = redeemed:peek() },
		}
	end

	function self.dump(): string
		return table.concat({
			phase:peek(),
			tostring(stamps:peek()),
			tostring(served:peek()),
			tostring(redeemed:peek()),
			tostring(refused:peek()),
		}, "/")
	end

	return self
end

return task
