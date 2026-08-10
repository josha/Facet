--!strict
-- RecipeUnlockService (spec §3, §10): the non-consumable-shaped `blend-book`
-- product and its purchase command.
--
-- Production is a `MarketplaceService` non-consumable and a host purchase sheet
-- (responsibility ledger). The proof imitates NO purchase chrome: the card
-- shows the product's own facts, the button says what it costs, and the
-- lifecycle is the ledger's `idle → pending → confirmed | rejected`.
--
-- TWO fixtures, both scripted rather than random:
--   * availability is `pending` for the first second, so the "price is not
--     known yet" state is a real state a screen has to render (no buy button is
--     mounted while it holds);
--   * the FIRST purchase attempt is declined. That is what makes the rejection
--     path reachable through the on-screen button alone — no test seam, no
--     fixture toggle, and the second attempt confirms.

local unlock = {}

unlock.AVAILABLE_AFTER = 1.0
unlock.RESOLVE_AFTER = 0.6

function unlock.new(opts: any)
	local core = opts.core
	local scope = opts.scope
	local clock = opts.clock

	local availability = core:signal("pending")
	local status = core:signal("idle")
	local unlocked = core:signal(opts.startUnlocked == true)
	local attempts = 0
	local listeners: { (boolean, string?) -> () } = {}
	scope:own(function()
		availability:dispose()
		status:dispose()
		unlocked:dispose()
	end)

	local self = {}
	self.availability = availability
	self.status = status
	self.unlocked = unlocked
	self.product = table.freeze({
		id = "blend-book",
		nameKey = "unlock.name",
		descriptionKey = "unlock.description",
		price = "149 Credits",
	})
	-- the scripted rejection fixture: attempt indexes that come back declined
	self.rejectAt = opts.rejectAt or { 1 }

	local function armAvailability()
		availability:set("pending")
		clock.after(unlock.AVAILABLE_AFTER, function()
			availability:set("available")
		end, "unlock-availability")
	end

	local function rejects(attempt: number): boolean
		for _, at in self.rejectAt do
			if at == attempt then
				return true
			end
		end
		return false
	end

	function self.onResolved(fn: (boolean, string?) -> ()): () -> ()
		table.insert(listeners, fn)
		return function()
			local index = table.find(listeners, fn)
			if index ~= nil then
				table.remove(listeners, index)
			end
		end
	end

	function self.canBuy(): boolean
		return availability:get() == "available" and not unlocked:get() and status:get() ~= "pending"
	end

	function self.purchase(): boolean
		if not self.canBuy() then
			return false
		end
		status:set("pending")
		clock.after(unlock.RESOLVE_AFTER, function()
			attempts += 1
			if rejects(attempts) then
				status:set("rejected")
				for _, fn in listeners do
					fn(false, "declined")
				end
			else
				core:transaction(function()
					unlocked:set(true)
					status:set("confirmed")
				end)
				for _, fn in listeners do
					fn(true, nil)
				end
			end
		end, "unlock-resolve")
		return true
	end

	-- the card returns to idle after a rejection has been read
	function self.acknowledge()
		if status:get() == "rejected" then
			status:set("idle")
		end
	end

	function self.attempts(): number
		return attempts
	end

	function self.reset()
		attempts = 0
		core:transaction(function()
			status:set("idle")
			unlocked:set(opts.startUnlocked == true)
		end)
		armAvailability()
	end

	armAvailability()
	return self
end

return unlock
