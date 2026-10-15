--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
require(script.World).build()
local RaceService = require(script.RaceService)
local Ledger = require(script.Ledger)
local handlers: { [string]: (string, { [string]: unknown }?) -> unknown } = {}
local locks: { [Player]: boolean } = {}
local function guarded<R, A...>(invoke: (Player, A...) -> R): (Player, A...) -> R
	return function(player: Player, ...: A...): R
		while locks[player] do
			task.wait()
		end
		locks[player] = true
		local ok, value = pcall(invoke, player, ...)
		locks[player] = nil
		if not ok then
			error(value)
		end
		return value
	end
end
do
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local ShopService = require(script.ShopService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetShopState") :: RemoteFunction
	local purchase = remotes:WaitForChild("Purchase") :: RemoteFunction
	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	getState.OnServerInvoke = function(player: Player)
		return ShopService.getState(player)
	end

	purchase.OnServerInvoke = guarded(function(player: Player, itemId: unknown)
		local result = ShopService.purchase(player, itemId)
		if result.ok then
			require(script.InventoryService).give(player, result.item)
		end
		return result
	end)

	local function firstPlayer(): Player
		local player = Players:GetPlayers()[1]
		assert(player ~= nil, "no player is in the server")
		return player
	end

	admin.OnInvoke = function(command: string, args: { [string]: unknown }?): unknown
		local options: { [string]: unknown } = args or {}
		local player = firstPlayer()
		if command == "state" then
			return { state = ShopService.getState(player), journal = ShopService.journal(player) }
		elseif command == "grant" then
			local currency: "Coins" | "Gems" = if options.currency == "Gems" then "Gems" else "Coins"
			local amount = tonumber(options.amount) or 0
			ShopService.grant(player, currency, amount)
			return ShopService.getState(player)
		end
		error("unknown admin command " .. tostring(command))
	end

	handlers["shop"] = admin.OnInvoke
end
do
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local InventoryService = require(script.InventoryService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	local remoteGetInventory = remotes:WaitForChild("GetInventory") :: RemoteFunction
	remoteGetInventory.OnServerInvoke = function(player: Player)
		return InventoryService.getState(player)
	end

	local remoteEquip = remotes:WaitForChild("Equip") :: RemoteFunction
	remoteEquip.OnServerInvoke = guarded(function(player: Player, itemId: unknown)
		return InventoryService.equip(player, itemId)
	end)

	local remoteUnequip = remotes:WaitForChild("Unequip") :: RemoteFunction
	remoteUnequip.OnServerInvoke = guarded(function(player: Player, slot: unknown)
		return InventoryService.unequip(player, slot)
	end)

	admin.OnInvoke = function(command: string, args: { [string]: unknown }?): unknown
		local options: { [string]: unknown } = args or {}
		local player = Players:GetPlayers()[1]
		assert(player ~= nil, "no player is in the server")
		if command == "state" then
			return { state = InventoryService.getState(player), journal = InventoryService.journal(player) }
		elseif command == "give" then
			return InventoryService.give(player, tostring(options.item))
		end
		error("unknown admin command " .. tostring(command))
	end

	handlers["inventory"] = admin.OnInvoke
end
do
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local SettingsStore = require(script.SettingsStore)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	local remoteGetSettings = remotes:WaitForChild("GetSettings") :: RemoteFunction
	remoteGetSettings.OnServerInvoke = function(player: Player)
		return SettingsStore.get(player)
	end

	local remoteSaveSettings = remotes:WaitForChild("SaveSettings") :: RemoteFunction
	remoteSaveSettings.OnServerInvoke = guarded(function(player: Player, patch: unknown)
		return SettingsStore.save(player, patch)
	end)

	admin.OnInvoke = function(command: string, args: { [string]: unknown }?): unknown
		local options: { [string]: unknown } = args or {}
		local player = Players:GetPlayers()[1]
		assert(player ~= nil, "no player is in the server")
		if command == "state" then
			return { values = SettingsStore.get(player), journal = SettingsStore.journal(player) }
		elseif command == "push" then
			return SettingsStore.push(player, options)
		end
		error("unknown admin command " .. tostring(command))
	end

	handlers["settings"] = admin.OnInvoke
end
do
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CodesService = require(script.CodesService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetCodesState") :: RemoteFunction
	local redeem = remotes:WaitForChild("RedeemCode") :: RemoteFunction

	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	getState.OnServerInvoke = function(player: Player)
		return CodesService.getState(player)
	end

	redeem.OnServerInvoke = guarded(function(player: Player, code: unknown)
		return CodesService.redeem(player, code)
	end)

	local function firstPlayer(): Player
		local player = Players:GetPlayers()[1]
		assert(player ~= nil, "no player is in the server")
		return player
	end

	admin.OnInvoke = function(command: string, _args: { [string]: unknown }?): unknown
		local player = firstPlayer()
		if command == "state" then
			return { state = CodesService.getState(player), journal = CodesService.journal(player) }
		end
		error("unknown admin command " .. tostring(command))
	end

	handlers["codes"] = admin.OnInvoke
end
do
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local RewardService = require(script.RewardService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetRewardsState") :: RemoteFunction
	local claim = remotes:WaitForChild("ClaimReward") :: RemoteFunction

	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	getState.OnServerInvoke = function(player: Player)
		return RewardService.getState(player)
	end

	claim.OnServerInvoke = guarded(function(player: Player)
		return RewardService.claim(player)
	end)

	local function firstPlayer(): Player
		local player = Players:GetPlayers()[1]
		assert(player ~= nil, "no player is in the server")
		return player
	end

	admin.OnInvoke = function(command: string, _args: { [string]: unknown }?): unknown
		local player = firstPlayer()
		if command == "state" then
			return {
				state = RewardService.getState(player),
				journal = RewardService.journal(player),
				now = workspace:GetServerTimeNow(),
			}
		elseif command == "advance" then
			RewardService.advance(player)
			return RewardService.getState(player)
		elseif command == "miss" then
			RewardService.miss(player)
			return RewardService.getState(player)
		end
		error("unknown admin command " .. tostring(command))
	end

	handlers["daily-rewards"] = admin.OnInvoke
end
do
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local DialogueService = require(script.DialogueService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetDialogueState") :: RemoteFunction
	local talk = remotes:WaitForChild("Talk") :: RemoteFunction
	local choose = remotes:WaitForChild("Choose") :: RemoteFunction
	local leave = remotes:WaitForChild("Leave") :: RemoteFunction

	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	getState.OnServerInvoke = function(player: Player)
		return DialogueService.getState(player)
	end

	talk.OnServerInvoke = guarded(function(player: Player)
		return DialogueService.talk(player)
	end)

	choose.OnServerInvoke = guarded(function(player: Player, choiceId: unknown)
		return DialogueService.choose(player, choiceId)
	end)

	leave.OnServerInvoke = guarded(function(player: Player)
		return DialogueService.leave(player)
	end)

	local function firstPlayer(): Player
		local player = Players:GetPlayers()[1]
		assert(player ~= nil, "no player is in the server")
		return player
	end

	admin.OnInvoke = function(command: string, _args: { [string]: unknown }?): unknown
		local player = firstPlayer()
		if command == "state" then
			return { state = DialogueService.getState(player), journal = DialogueService.journal(player) }
		elseif command == "approach" then
			DialogueService.setNearby(player, true)
			return DialogueService.getState(player)
		elseif command == "walkAway" then
			DialogueService.setNearby(player, false)
			return DialogueService.getState(player)
		end
		error("unknown admin command " .. tostring(command))
	end

	handlers["npc-dialogue"] = admin.OnInvoke
end
do
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CrateService = require(script.CrateService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetCrateState") :: RemoteFunction
	local open = remotes:WaitForChild("OpenCrate") :: RemoteFunction

	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	getState.OnServerInvoke = function(player: Player)
		return CrateService.getState(player)
	end

	open.OnServerInvoke = guarded(function(player: Player, crateId: unknown)
		return CrateService.open(player, crateId)
	end)

	local function firstPlayer(): Player
		local player = Players:GetPlayers()[1]
		assert(player ~= nil, "no player is in the server")
		return player
	end

	admin.OnInvoke = function(command: string, args: { [string]: unknown }?): unknown
		local options: { [string]: unknown } = args or {}
		local player = firstPlayer()
		if command == "state" then
			return { state = CrateService.getState(player), journal = CrateService.journal(player) }
		elseif command == "grant" then
			CrateService.grant(player, tonumber(options.gems) or 0)
			return CrateService.getState(player)
		end
		error("unknown admin command " .. tostring(command))
	end

	handlers["pack-opening"] = admin.OnInvoke
end
do
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local GarageService = require(script.GarageService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetGarageState") :: RemoteFunction
	local spawnVehicle = remotes:WaitForChild("SpawnVehicle") :: RemoteFunction
	local exitVehicle = remotes:WaitForChild("ExitVehicle") :: RemoteFunction
	local setFavorite = remotes:WaitForChild("SetFavorite") :: RemoteFunction

	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	getState.OnServerInvoke = function(player: Player)
		return GarageService.getState(player)
	end

	spawnVehicle.OnServerInvoke = guarded(function(player: Player, vehicleId: unknown)
		return GarageService.spawn(player, vehicleId)
	end)

	exitVehicle.OnServerInvoke = guarded(function(player: Player)
		return GarageService.exit(player)
	end)

	setFavorite.OnServerInvoke = guarded(function(player: Player, vehicleId: unknown, favorite: unknown)
		return GarageService.setFavorite(player, vehicleId, favorite)
	end)

	admin.OnInvoke = function(command: string, _args: { [string]: unknown }?): unknown
		local player = Players:GetPlayers()[1]
		assert(player ~= nil, "no player is in the server")
		if command == "state" then
			return { state = GarageService.getState(player), journal = GarageService.journal(player) }
		elseif command == "exit" then
			return GarageService.exit(player)
		end
		error("unknown admin command " .. tostring(command))
	end

	handlers["vehicle-garage"] = admin.OnInvoke
end
do
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local DriverService = require(script.DriverService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetDriverState") :: RemoteFunction
	local buy = remotes:WaitForChild("BuyDriver") :: RemoteFunction
	local rent = remotes:WaitForChild("RentDriver") :: RemoteFunction
	local equip = remotes:WaitForChild("EquipDriver") :: RemoteFunction

	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	getState.OnServerInvoke = function(player: Player)
		return DriverService.getState(player)
	end

	buy.OnServerInvoke = guarded(function(player: Player, id: unknown)
		return DriverService.buy(player, id)
	end)

	rent.OnServerInvoke = guarded(function(player: Player, id: unknown)
		return DriverService.rent(player, id)
	end)

	equip.OnServerInvoke = guarded(function(player: Player, id: unknown)
		return DriverService.equip(player, id)
	end)

	admin.OnInvoke = function(command: string, args: { [string]: unknown }?): unknown
		local options: { [string]: unknown } = args or {}
		local player = Players:GetPlayers()[1]
		assert(player ~= nil, "no player is in the server")
		if command == "state" then
			return {
				state = DriverService.getState(player),
				journal = DriverService.journal(player),
				now = workspace:GetServerTimeNow(),
			}
		elseif command == "grant" then
			DriverService.grant(player, tonumber(options.coins) or 0)
			return DriverService.getState(player)
		end
		error("unknown admin command " .. tostring(command))
	end

	handlers["character-shop"] = admin.OnInvoke
end
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Round = require(ReplicatedStorage.Shared.Hub.Round)
	local RoundService = require(script.RoundService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetRoundState") :: RemoteFunction

	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	getState.OnServerInvoke = function(_player: Player)
		return RoundService.snapshot()
	end

	admin.OnInvoke = function(command: string, args: { [string]: unknown }?): unknown
		local options: { [string]: unknown } = args or {}
		if command == "state" then
			local state = RoundService.snapshot()
			return {
				state = state,
				remaining = state.endsAt - workspace:GetServerTimeNow(),
				events = RoundService.events(),
			}
		elseif command == "manual" then
			RoundService.setAutomatic(false)
			return true
		elseif command == "phase" then
			local raw = tostring(options.phase)
			assert(raw == "Intermission" or raw == "Round" or raw == "Results", "unknown phase " .. raw)
			local phase: Round.Phase = if raw == "Round"
				then "Round"
				elseif raw == "Results" then "Results"
				else "Intermission"
			local winner = options.winner
			RoundService.enter(
				phase,
				tonumber(options.seconds),
				if winner == "Red" or winner == "Blue" or winner == "Draw" then winner else nil
			)
			return RoundService.snapshot()
		elseif command == "eliminate" then
			return RoundService.eliminate(tostring(options.victim), tostring(options.by))
		end
		error("unknown admin command " .. tostring(command))
	end

	RoundService.start()

	handlers["round-hud"] = admin.OnInvoke
end
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local QueueService = require(script.QueueService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetLobbyState") :: RemoteFunction
	local join = remotes:WaitForChild("JoinQueue") :: RemoteFunction
	local leave = remotes:WaitForChild("LeaveQueue") :: RemoteFunction

	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	getState.OnServerInvoke = function(_player: Player)
		return QueueService.snapshot()
	end

	join.OnServerInvoke = guarded(function(player: Player, modeId: unknown)
		return QueueService.join(player, modeId)
	end)

	leave.OnServerInvoke = guarded(function(player: Player)
		return QueueService.leave(player)
	end)

	admin.OnInvoke = function(command: string, args: { [string]: unknown }?): unknown
		local options: { [string]: unknown } = args or {}
		if command == "state" then
			local state = QueueService.snapshot()
			local endsAt = state.countdownEndsAt
			return {
				state = state,
				countdown = if endsAt ~= nil then endsAt - workspace:GetServerTimeNow() else nil,
				journal = QueueService.journal(),
			}
		elseif command == "manual" then
			QueueService.setAutomatic(false)
			return true
		elseif command == "addPlayers" then
			QueueService.addBots(tonumber(options.count) or 1)
			return QueueService.snapshot()
		elseif command == "removePlayers" then
			QueueService.addBots(-(tonumber(options.count) or 1))
			return QueueService.snapshot()
		elseif command == "finishCountdown" then
			QueueService.finishCountdown()
			return QueueService.snapshot()
		end
		error("unknown admin command " .. tostring(command))
	end

	QueueService.start()

	handlers["lobby-queue"] = admin.OnInvoke
end
do
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local EconomyService = require(script.EconomyService)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetEconomyState") :: RemoteFunction
	local buyBoost = remotes:WaitForChild("BuyBoost") :: RemoteFunction
	local claimQuest = remotes:WaitForChild("ClaimQuest") :: RemoteFunction
	local buyOffer = remotes:WaitForChild("BuyOffer") :: RemoteFunction

	local admin = {} :: { OnInvoke: (string, { [string]: unknown }?) -> unknown }

	getState.OnServerInvoke = function(player: Player)
		return EconomyService.getState(player)
	end

	buyBoost.OnServerInvoke = guarded(function(player: Player)
		return EconomyService.buyBoost(player)
	end)

	claimQuest.OnServerInvoke = guarded(function(player: Player, questId: unknown)
		return EconomyService.claimQuest(player, questId)
	end)

	buyOffer.OnServerInvoke = guarded(function(player: Player)
		return EconomyService.buyOffer(player)
	end)

	admin.OnInvoke = function(command: string, args: { [string]: unknown }?): unknown
		local options: { [string]: unknown } = args or {}
		local player = Players:GetPlayers()[1]
		assert(player ~= nil, "no player is in the server")
		if command == "state" then
			return {
				state = EconomyService.getState(player),
				journal = EconomyService.journal(player),
				now = workspace:GetServerTimeNow(),
			}
		elseif command == "pause" then
			EconomyService.setPaused(true)
			return true
		elseif command == "resume" then
			EconomyService.setPaused(false)
			return true
		elseif command == "grant" then
			EconomyService.grant(player, tonumber(options.coins) or 0, tonumber(options.gems) or 0)
			return EconomyService.getState(player)
		end
		error("unknown admin command " .. tostring(command))
	end

	EconomyService.start()

	handlers["hud-dock"] = admin.OnInvoke
end

local Hub = require(ReplicatedStorage.Shared.Hub)
local RoundService = require(script.RoundService)
local QueueService = require(script.QueueService)
local EconomyService = require(script.EconomyService)
local GarageService = require(script.GarageService)
local DriverService = require(script.DriverService)
local RewardService = require(script.RewardService)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local admin = Instance.new("BindableFunction")
admin.Name = "AdminCommands"
admin.Parent = ServerStorage
local raceManual = false

local DialogueService = require(script.DialogueService)
local raceLoadouts: { [Player]: { kart: string, driver: string } } = {}
local positions: { string } = { "You", "Nova", "Pip", "Rook", "Zed", "Ivy", "Bolt", "Moss" }
local function hubState(player: Player): Hub.State
	local progress = Ledger.progress(player)
	local race = raceLoadouts[player] or { kart = progress.kart, driver = progress.driver }
	return {
		wallet = table.clone(Ledger.wallet(player)),
		xp = progress.xp,
		level = progress.level,
		races = progress.races,
		crates = progress.crates,
		kart = progress.kart,
		driver = progress.driver,
		raceKart = race.kart,
		raceDriver = race.driver,
		positions = table.clone(positions),
	}
end
(remotes:WaitForChild("GetHubState") :: RemoteFunction).OnServerInvoke = hubState
admin.OnInvoke = function(command: string, args: { [string]: unknown }?): unknown
	local options: { [string]: unknown } = args or {}
	local player = Players:GetPlayers()[1]
	assert(player ~= nil, "no player is in the server")
	if command == "state" or command == "journal" then
		local systems: { [string]: unknown } = {}
		local journals: { [string]: unknown } = {}
		for name, handler in handlers do
			local response = handler("state", {})
			systems[name] = response
			if type(response) == "table" then
				journals[name] = (response :: { [string]: unknown }).journal
			end
		end
		return if command == "journal"
			then journals
			else { state = hubState(player), systems = systems, journal = journals }
	elseif command == "system" then
		if options.system == "round-hud" and options.command == "manual" then
			raceManual = true
		end
		local handler = handlers[tostring(options.system)]
		assert(handler ~= nil, "unknown system")
		local fields = if type(options.args) == "table" then options.args :: { [string]: unknown } else {}
		return handler(tostring(options.command), fields)
	elseif command == "wallet" then
		local wallet = Ledger.wallet(player)
		wallet.Coins = math.max(0, tonumber(options.coins) or wallet.Coins)
		wallet.Gems = math.max(0, tonumber(options.gems) or wallet.Gems)
		return hubState(player)
	elseif command == "grant" then
		EconomyService.grant(player, tonumber(options.coins) or 0, tonumber(options.gems) or 0)
		return hubState(player)
	elseif command == "positions" then
		if type(options.names) == "table" then
			local nextPositions: { string } = {}
			for _, name in options.names :: { unknown } do
				assert(type(name) == "string", "invalid position")
				table.insert(nextPositions, name)
			end
			positions = nextPositions
		end
		return hubState(player)
	elseif command == "phase" or command == "manual" or command == "eliminate" then
		if command == "manual" then
			raceManual = true
		end
		return handlers["round-hud"](command, options)
	elseif command == "advance" or command == "miss" then
		return handlers["daily-rewards"](command, options)
	end
	error("unknown admin command " .. command)
end
local lastQueue = "Lobby"
local lastRound = 0
local signatures: { [Player]: string } = {}
Players.PlayerRemoving:Connect(function(player)
	raceLoadouts[player] = nil
	signatures[player] = nil
	locks[player] = nil
end)
task.spawn(function()
	while true do
		local queue = QueueService.snapshot()
		if queue.phase == "Starting" and lastQueue ~= "Starting" then
			RoundService.enter("Round")
		end
		lastQueue = queue.phase
		local round = RoundService.snapshot()
		if round.phase == "Round" and not raceManual then
			positions = RaceService.positions()
		end
		if round.phase == "Round" and lastRound ~= round.round then
			lastRound = round.round
			for _, player in Players:GetPlayers() do
				local progress = Ledger.progress(player)
				raceLoadouts[player] =
					{ kart = progress.kart, driver = DriverService.getState(player).equipped or "haru" }
			end
		end
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
			DialogueService.autoNearby(
				player,
				root ~= nil and root:IsA("BasePart") and (root.Position - Vector3.new(24, 3, 0)).Magnitude < 12
			)
			local state = hubState(player)
			local signature = game:GetService("HttpService"):JSONEncode(state)
			if signatures[player] ~= signature then
				signatures[player] = signature;
				(remotes:WaitForChild("HubStateChanged") :: RemoteEvent):FireClient(player, state);
				(remotes:WaitForChild("ShopStateChanged") :: RemoteEvent):FireClient(
					player,
					require(script.ShopService).getState(player)
				);
				(remotes:WaitForChild("CodesStateChanged") :: RemoteEvent):FireClient(
					player,
					require(script.CodesService).getState(player)
				);
				(remotes:WaitForChild("RewardsStateChanged") :: RemoteEvent):FireClient(
					player,
					RewardService.getState(player)
				);
				(remotes:WaitForChild("EconomyStateChanged") :: RemoteEvent):FireClient(
					player,
					EconomyService.getState(player)
				);
				(remotes:WaitForChild("CrateStateChanged") :: RemoteEvent):FireClient(
					player,
					require(script.CrateService).getState(player)
				);
				(remotes:WaitForChild("DriverStateChanged") :: RemoteEvent):FireClient(
					player,
					DriverService.getState(player)
				)
			end
		end
		task.wait(0.25)
	end
end)
local returnToHub = remotes:WaitForChild("ReturnToHub") :: RemoteFunction
returnToHub.OnServerInvoke = guarded(function(_player: Player): boolean
	if RoundService.snapshot().phase ~= "Results" then
		return false
	end
	RoundService.enter("Intermission")
	return true
end)
