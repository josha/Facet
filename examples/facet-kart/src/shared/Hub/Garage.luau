--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Category = "Sprint" | "Circuit" | "Coast"

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type Vehicle = {
	id: string,
	name: string,
	category: Category,
	rarity: Rarity,
	level: number,
	speed: number,
	armor: number,
	firepower: number,
	controls: { string },
}

export type State = {
	favorites: { [string]: boolean },
	spawned: string?,
}

export type Failure = "unknown_vehicle" | "already_spawned" | "nothing_spawned" | "busy"

export type Result = { ok: boolean, reason: Failure?, state: State }

export type Client = {
	vehicles: { Vehicle },
	categories: { Category },
	rarities: { Rarity },
	getState: () -> State,
	spawn: (vehicleId: string) -> Result,
	exit: () -> Result,
	setFavorite: (vehicleId: string, favorite: boolean) -> Result,
	onStateChanged: (callback: (State) -> ()) -> RBXScriptConnection,
}

local AIR = { "Drive: W A S D", "Accelerate: W", "Brake: S", "Exit: Leave Vehicle" }
local LAND = { "Drive: W A S D", "Steer: A D", "Exit: Leave Vehicle" }
local SEA = { "Drive: W A S D", "Brake: S", "Exit: Leave Vehicle" }

local vehicles: { Vehicle } = {
	{
		id = "sprint_kart",
		name = "Sprint Kart",
		category = "Sprint",
		rarity = "Common",
		level = 3,
		speed = 70,
		armor = 20,
		firepower = 10,
		controls = AIR,
	},
	{
		id = "aero_kart",
		name = "Aero Kart",
		category = "Sprint",
		rarity = "Rare",
		level = 8,
		speed = 85,
		armor = 35,
		firepower = 45,
		controls = AIR,
	},
	{
		id = "heavy_kart",
		name = "Heavy Kart",
		category = "Sprint",
		rarity = "Epic",
		level = 14,
		speed = 55,
		armor = 80,
		firepower = 70,
		controls = AIR,
	},
	{
		id = "summit_kart",
		name = "Summit Kart",
		category = "Sprint",
		rarity = "Legendary",
		level = 21,
		speed = 95,
		armor = 60,
		firepower = 90,
		controls = AIR,
	},
	{
		id = "rookie_kart",
		name = "Rookie Kart",
		category = "Circuit",
		rarity = "Common",
		level = 1,
		speed = 60,
		armor = 30,
		firepower = 5,
		controls = LAND,
	},
	{
		id = "scout_kart",
		name = "Scout Kart",
		category = "Circuit",
		rarity = "Rare",
		level = 6,
		speed = 80,
		armor = 25,
		firepower = 20,
		controls = LAND,
	},
	{
		id = "iron_kart",
		name = "Iron Kart",
		category = "Circuit",
		rarity = "Epic",
		level = 12,
		speed = 30,
		armor = 95,
		firepower = 85,
		controls = LAND,
	},
	{
		id = "rail_kart",
		name = "Rail Kart",
		category = "Circuit",
		rarity = "Legendary",
		level = 19,
		speed = 25,
		armor = 70,
		firepower = 100,
		controls = LAND,
	},
	{
		id = "coast_kart",
		name = "Coast Kart",
		category = "Coast",
		rarity = "Common",
		level = 2,
		speed = 50,
		armor = 10,
		firepower = 0,
		controls = SEA,
	},
	{
		id = "patrol_kart",
		name = "Patrol Kart",
		category = "Coast",
		rarity = "Rare",
		level = 7,
		speed = 65,
		armor = 40,
		firepower = 35,
		controls = SEA,
	},
	{
		id = "stream_kart",
		name = "Stream Kart",
		category = "Coast",
		rarity = "Epic",
		level = 13,
		speed = 45,
		armor = 75,
		firepower = 60,
		controls = SEA,
	},
	{
		id = "cruise_kart",
		name = "Cruise Kart",
		category = "Coast",
		rarity = "Epic",
		level = 20,
		speed = 35,
		armor = 100,
		firepower = 95,
		controls = SEA,
	},
}

local function client(): Client
	assert(RunService:IsClient(), "Garage.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetGarageState") :: RemoteFunction
	local spawnVehicle = remotes:WaitForChild("SpawnVehicle") :: RemoteFunction
	local exitVehicle = remotes:WaitForChild("ExitVehicle") :: RemoteFunction
	local setFavorite = remotes:WaitForChild("SetFavorite") :: RemoteFunction
	local changed = remotes:WaitForChild("GarageStateChanged") :: RemoteEvent
	return {
		vehicles = vehicles,
		categories = { "Sprint", "Circuit", "Coast" },
		rarities = { "Common", "Rare", "Epic", "Legendary" },
		getState = function(): State
			return getState:InvokeServer()
		end,
		spawn = function(vehicleId: string): Result
			return spawnVehicle:InvokeServer(vehicleId)
		end,
		exit = function(): Result
			return exitVehicle:InvokeServer()
		end,
		setFavorite = function(vehicleId: string, favorite: boolean): Result
			return setFavorite:InvokeServer(vehicleId, favorite)
		end,
		onStateChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
	}
end

return {
	client = client,
	vehicles = vehicles,
}
