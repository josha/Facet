--!strict

local Players = game:GetService("Players")

export type Wallet = { Coins: number, Gems: number }
export type Progress = { xp: number, level: number, races: number, crates: number, kart: string, driver: string }
type Profile = { wallet: Wallet, progress: Progress, rewarded: number }
local profiles: { [Player]: Profile } = {}

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if profile == nil then
		profile = {
			wallet = { Coins = 320, Gems = 40 },
			progress = { xp = 0, level = 1, races = 0, crates = 0, kart = "rookie_kart", driver = "haru" },
			rewarded = 0,
		}
		profiles[player] = profile
	end
	return profile
end

Players.PlayerRemoving:Connect(function(player)
	profiles[player] = nil
end)

return {
	wallet = function(player: Player): Wallet
		return profileOf(player).wallet
	end,
	progress = function(player: Player): Progress
		return table.clone(profileOf(player).progress)
	end,
	setKart = function(player: Player, id: string)
		profileOf(player).progress.kart = id
	end,
	setDriver = function(player: Player, id: string)
		profileOf(player).progress.driver = id
	end,
	addCrate = function(player: Player)
		profileOf(player).progress.crates += 1
	end,
	consumeCrate = function(player: Player): boolean
		local progress = profileOf(player).progress
		if progress.crates < 1 then
			return false
		end
		progress.crates -= 1
		return true
	end,
	reward = function(player: Player, round: number, coins: number)
		local profile = profileOf(player)
		if round <= profile.rewarded then
			return
		end
		profile.rewarded = round
		profile.wallet.Coins += coins
		profile.wallet.Gems += 5
		profile.progress.xp += 120
		profile.progress.level = 1 + profile.progress.xp // 100
		profile.progress.races += 1
	end,
}
