--!strict
-- TaskService — "Today's order", the played loop Sipworks is about.
--
-- WHY THIS EXISTS. The app already had a catalogue, an order command, a stamp
-- card, a reward and a recipe unlock; what it did not have was a TASK. A visitor
-- opened on a blend menu, browsed, and never learned that ten stamps buy a free
-- pour — the app's best material sat ten repetitive orders away. This service is
-- the small state machine that turns those existing parts into a loop a player
-- can finish once: place an order, take the last stamp, redeem the free pour.
--
-- IT OWNS NO RULES OF ITS OWN. Every number it reads belongs to RewardsService
-- and OrderService; it derives a PHASE from them and latches the two facts a
-- derivation cannot recover — "an order of mine was accepted" and "the free pour
-- was redeemed" — because both are events, not states, and the services return
-- to idle after each one.
--
-- THE SEED IS THE DESIGN DECISION, and it lives in `init.luau`: the card starts
-- one stamp short (`rewards.THRESHOLD - 1`), so a single accepted order completes
-- it. At ten orders a visitor never sees the stamp ceremony, the reward, or the
-- free pour.
--
-- THE REJECTION IS A PHASE, NOT A DISAPPEARANCE. OrderService acknowledges a
-- rejection immediately (its status returns to `idle` on the same turn), so a
-- memo over `order.status` can never see one. The latch below is what gives a
-- refused order somewhere to be READ — a task line that says what happened, says
-- the stamps are untouched, and says what to press next.

local rewardsService = require("./rewards")

local task = {}

-- The two blends the task NAMES. A first action a player has to hunt for is not
-- a first action, so the task offers one by name — and a second, different one
-- for the free pour, because "choose ANOTHER blend" is the step. Both are free
-- recipes, so neither is hidden behind the Blend Book.
task.FIRST_BLEND = "amber-harvest"
task.FREE_POUR_BLEND = "mistral-mint"

-- the five phases, in the order the loop walks them. `rejected` is a detour off
-- `order` that keeps every stamp, never a sixth step.
task.PHASES = { "order", "placing", "rejected", "redeem", "done" }

export type Opts = {
	core: any,
	scope: any,
	rewards: any,
	order: any,
}

function task.new(opts: Opts): any
	local core = opts.core
	local scope = opts.scope
	local rewards = opts.rewards
	local order = opts.order

	-- the two latched events (see the header): both are cleared by `reset`
	local served = core:signal(false)
	local redeemed = core:signal(false)
	local refused = core:signal(false)
	scope:own(function()
		served:dispose()
		redeemed:dispose()
		refused:dispose()
	end)

	local self = {}
	self.served = served
	self.redeemed = redeemed
	self.refused = refused
	self.firstBlendId = task.FIRST_BLEND
	self.freePourBlendId = task.FREE_POUR_BLEND

	-- how many of the card's ten seals are stamped right now. The number IS the
	-- lesson here — a stamp card is a counter — so it is on the player surface.
	local stamps = core:memo(function(use)
		return math.clamp(use(rewards.earned) - use(rewards.spent), 0, rewardsService.THRESHOLD)
	end)
	local phase = core:memo(function(use)
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
	-- the blend the CTA names, which is the step's own subject: the first order,
	-- then a different blend for the free pour
	local ctaBlendId = core:memo(function(use)
		return if use(phase) == "redeem" then task.FREE_POUR_BLEND else task.FIRST_BLEND
	end)
	scope:own(function()
		stamps:dispose()
		phase:dispose()
		ctaBlendId:dispose()
	end)
	self.stamps = stamps
	self.phase = phase
	self.ctaBlendId = ctaBlendId

	-- ---- the two events the phases are latched from ------------------------

	-- a confirmed order. `mode` is OrderService's own word: a redeem order is the
	-- free pour and ends the loop; a paid one is the order that fills the card.
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

	-- pressing the CTA again is the retry, and a retry clears the notice it is
	-- answering. Nothing else clears it: a player who browses away comes back to
	-- the same explanation.
	function self.notePlacing()
		refused:set(false)
	end

	function self.reset()
		core:transaction(function()
			served:set(false)
			redeemed:set(false)
			refused:set(false)
		end)
	end

	-- the two checklist rows, as data: id + done, in the order they are walked
	function self.rows(): { { id: string, done: boolean } }
		return {
			{ id = "serve", done = served:get() },
			{ id = "redeem", done = redeemed:get() },
		}
	end

	function self.dump(): string
		return table.concat({
			phase:get(),
			tostring(stamps:get()),
			tostring(served:get()),
			tostring(redeemed:get()),
			tostring(refused:get()),
		}, "/")
	end

	return self
end

return task
