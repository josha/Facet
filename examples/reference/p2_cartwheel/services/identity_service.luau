--!strict
-- IdentityService — the signed-in fact and the sign-up command.
--
-- STATED ON SCREEN, because the responsibility ledger requires it: Roblox
-- identity is ambient (`Players.LocalPlayer`), so a guild sign-up has no
-- production job at all. It is kept as a UI-capability exercise — validation
-- gating, focus autoset, a field-level rejection — and the modal says so in its
-- own header rather than in a comment nobody reads.
--
-- The rejection fixture is a taken-name list (content/data.luau), so both
-- outcomes are one typed word apart on screen.
local data = require("../content/data")

local identity_service = {}

function identity_service.new(opts: any): any
	local core = opts.core
	local self: any = {}

	local signedIn = core:signal(false)
	local guildName = core:signal("")
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
		return { signedIn = signedIn:get(), guildName = guildName:get() }
	end

	function self.dispose()
		signedIn:dispose()
		guildName:dispose()
	end

	return self
end

return table.freeze(identity_service)
