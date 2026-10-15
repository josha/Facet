--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shop = require(script.Shop)
local Inventory = require(script.Inventory)
local Settings = require(script.Settings)
local Codes = require(script.Codes)
local DailyRewards = require(script.DailyRewards)
local Dialogue = require(script.Dialogue)
local Crates = require(script.Crates)
local Garage = require(script.Garage)
local Drivers = require(script.Drivers)
local Round = require(script.Round)
local Lobby = require(script.Lobby)
local Economy = require(script.Economy)

export type State = {
	wallet: { Coins: number, Gems: number },
	xp: number,
	level: number,
	races: number,
	crates: number,
	kart: string,
	driver: string,
	raceKart: string,
	raceDriver: string,
	positions: { string },
}
export type Client = {
	getState: () -> State,
	onStateChanged: ((State) -> ()) -> RBXScriptConnection,
	serverNow: () -> number,
	returnToHub: () -> boolean,
}
export type Context = {
	player: Player,
	playerGui: PlayerGui,
	hub: Client,
	shop: Shop.Client,
	inventory: Inventory.Client,
	settings: Settings.Client,
	codes: Codes.Client,
	rewards: DailyRewards.Client,
	dialogue: Dialogue.Client,
	crates: Crates.Client,
	garage: Garage.Client,
	drivers: Drivers.Client,
	round: Round.Client,
	lobby: Lobby.Client,
	economy: Economy.Client,
}
local function client(): Client
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local get = remotes:WaitForChild("GetHubState") :: RemoteFunction
	local changed = remotes:WaitForChild("HubStateChanged") :: RemoteEvent
	return {
		returnToHub = function(): boolean
			return (remotes:WaitForChild("ReturnToHub") :: RemoteFunction):InvokeServer()
		end,
		getState = function(): State
			return get:InvokeServer()
		end,
		onStateChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
		serverNow = function(): number
			return workspace:GetServerTimeNow()
		end,
	}
end
local function context(player: Player): Context
	return {
		player = player,
		playerGui = player:WaitForChild("PlayerGui") :: PlayerGui,
		hub = client(),
		shop = Shop.client(),
		inventory = Inventory.client(),
		settings = Settings.client(),
		codes = Codes.client(),
		rewards = DailyRewards.client(),
		dialogue = Dialogue.client(),
		crates = Crates.client(),
		garage = Garage.client(),
		drivers = Drivers.client(),
		round = Round.client(),
		lobby = Lobby.client(),
		economy = Economy.client(),
	}
end
return { context = context }
