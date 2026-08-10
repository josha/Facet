--!strict
-- EntitlementService — Chatter+ (a subscription-shaped fact) and the Full Ledger
-- (a non-consumable-shaped one). Fake, deterministic, and reachable in BOTH
-- outcomes through on-screen controls alone (acceptance obligation 2).
--
-- THE FIRST ATTEMPT ON EACH PRODUCT DECLINES. That is a fixture, not a mood: a
-- rejection path nobody can reach is a rejection path nobody has tested, and the
-- alternative — a hidden "make it fail" switch — would be a test-only shortcut
-- standing in for an on-screen control. So the player taps Unlock, reads
-- "Purchase declined — nothing was charged", and taps it again; both halves of
-- the lifecycle are one button away and the sequence is identical every run.
--
-- Production mapping: Roblox Subscriptions for the tier, a game pass or
-- developer product for the unlock — and in both cases the PROMPT itself is a
-- host sheet, so the in-experience UI ends at the call.
local entitlement_service = {}

function entitlement_service.new(opts: any): any
	local core = opts.core
	local self: any = {}

	local chatterPlus = core:signal(false)
	local fullLedger = core:signal(false)
	local attempts: { [string]: number } = {}

	self.chatterPlus = chatterPlus
	self.fullLedger = fullLedger

	-- the scripted verdict for the next attempt on `product`
	function self.decide(product: string): (boolean, string?)
		local n = (attempts[product] or 0) + 1
		attempts[product] = n
		if n == 1 then
			return false, "reject.purchase"
		end
		return true
	end

	function self.attemptsOn(product: string): number
		return attempts[product] or 0
	end

	function self.grant(product: string)
		if product == "ledger" then
			fullLedger:set(true)
		else
			chatterPlus:set(true)
		end
	end

	function self.revoke(product: string)
		if product == "ledger" then
			fullLedger:set(false)
		else
			chatterPlus:set(false)
		end
	end

	function self.dump(): any
		return { chatterPlus = chatterPlus:get(), fullLedger = fullLedger:get(), attempts = table.clone(attempts) }
	end

	function self.dispose()
		chatterPlus:dispose()
		fullLedger:dispose()
	end

	return self
end

return table.freeze(entitlement_service)
