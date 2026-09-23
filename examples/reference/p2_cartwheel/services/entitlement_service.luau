--!strict

local entitlement_service = {}

function entitlement_service.new(opts: any): any
	local Compose = opts.Compose
	local self: any = {}

	local chatterPlus = Compose.cell(false)
	local fullLedger = Compose.cell(false)
	local attempts: { [string]: number } = {}

	self.chatterPlus = chatterPlus
	self.fullLedger = fullLedger

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
		return { chatterPlus = chatterPlus:peek(), fullLedger = fullLedger:peek(), attempts = table.clone(attempts) }
	end

	function self.dispose() end

	return self
end

return table.freeze(entitlement_service)
