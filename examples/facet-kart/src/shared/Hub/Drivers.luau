--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type Driver = {
	id: string,
	name: string,
	series: "Circuit" | "Rally",
	rarity: Rarity,
	price: number,
	rentPrice: number,
	strength: number,
	speed: number,
	durability: number,
}

export type State = {
	coins: number,
	owned: { [string]: boolean },
	rented: { [string]: number },
	equipped: string?,
}

export type Failure = "insufficient_funds" | "already_owned" | "not_available" | "unknown_driver" | "busy"

export type Result = { ok: boolean, reason: Failure?, state: State }

export type Client = {
	drivers: { Driver },
	rentSeconds: number,
	getState: () -> State,
	buy: (driverId: string) -> Result,
	rent: (driverId: string) -> Result,
	equip: (driverId: string) -> Result,
	serverNow: () -> number,
	onStateChanged: (callback: (State) -> ()) -> RBXScriptConnection,
}

local drivers: { Driver } = {
	{
		id = "kira",
		name = "Kira",
		series = "Circuit",
		rarity = "Legendary",
		price = 900,
		rentPrice = 90,
		strength = 92,
		speed = 80,
		durability = 70,
	},
	{
		id = "ren",
		name = "Ren",
		series = "Circuit",
		rarity = "Epic",
		price = 600,
		rentPrice = 60,
		strength = 75,
		speed = 85,
		durability = 55,
	},
	{
		id = "aiko",
		name = "Aiko",
		series = "Circuit",
		rarity = "Rare",
		price = 350,
		rentPrice = 35,
		strength = 50,
		speed = 90,
		durability = 40,
	},
	{
		id = "tomo",
		name = "Tomo",
		series = "Circuit",
		rarity = "Uncommon",
		price = 150,
		rentPrice = 15,
		strength = 45,
		speed = 50,
		durability = 60,
	},
	{
		id = "haru",
		name = "Haru",
		series = "Circuit",
		rarity = "Common",
		price = 60,
		rentPrice = 6,
		strength = 30,
		speed = 40,
		durability = 45,
	},
	{
		id = "blaze",
		name = "Blaze",
		series = "Rally",
		rarity = "Legendary",
		price = 1000,
		rentPrice = 100,
		strength = 95,
		speed = 75,
		durability = 85,
	},
	{
		id = "pixel",
		name = "Pixel",
		series = "Rally",
		rarity = "Rare",
		price = 300,
		rentPrice = 30,
		strength = 40,
		speed = 95,
		durability = 35,
	},
	{
		id = "golem",
		name = "Golem",
		series = "Rally",
		rarity = "Common",
		price = 80,
		rentPrice = 8,
		strength = 70,
		speed = 20,
		durability = 90,
	},
}

local function client(): Client
	assert(RunService:IsClient(), "Drivers.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetDriverState") :: RemoteFunction
	local buy = remotes:WaitForChild("BuyDriver") :: RemoteFunction
	local rent = remotes:WaitForChild("RentDriver") :: RemoteFunction
	local equip = remotes:WaitForChild("EquipDriver") :: RemoteFunction
	local changed = remotes:WaitForChild("DriverStateChanged") :: RemoteEvent
	return {
		drivers = drivers,
		rentSeconds = 600,
		getState = function(): State
			return getState:InvokeServer()
		end,
		buy = function(driverId: string): Result
			return buy:InvokeServer(driverId)
		end,
		rent = function(driverId: string): Result
			return rent:InvokeServer(driverId)
		end,
		equip = function(driverId: string): Result
			return equip:InvokeServer(driverId)
		end,
		serverNow = function(): number
			return workspace:GetServerTimeNow()
		end,
		onStateChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
	}
end

return {
	client = client,
	drivers = drivers,
	rentSeconds = 600,
}
