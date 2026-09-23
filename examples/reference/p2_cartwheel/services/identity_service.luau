--!strict

local data = require("../content/data")

local identity_service = {}

function identity_service.new(opts: any): any
	local Compose = opts.Compose
	local self: any = {}

	local signedIn = Compose.cell(false)
	local guildName = Compose.cell("")
	self.signedIn = signedIn
	self.guildName = guildName

	local function normalize(name: string): string
		return string.lower((string.gsub(name, "^%s*(.-)%s*$", "%1")))
	end
	self.normalize = normalize

	function self.decide(name: string): (boolean, string?)
		local normalized = normalize(name)
		if normalized == "" then
			return false, "reject.fallback"
		end
		for _, taken in data.takenGuildNames :: any do
			if normalized == taken then
				return false, "reject.guildTaken"
			end
		end
		return true
	end

	function self.signIn(name: string)
		guildName:set(normalize(name))
		signedIn:set(true)
	end

	function self.signOut()
		signedIn:set(false)
		guildName:set("")
	end

	function self.dump(): any
		return { signedIn = signedIn:peek(), guildName = guildName:peek() }
	end

	function self.dispose() end

	return self
end

return table.freeze(identity_service)
