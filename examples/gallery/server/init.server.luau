--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local rules = require(
	ReplicatedStorage:WaitForChild("FacetExamples"):WaitForChild("outpost_terminal"):WaitForChild("rules")
) :: any

local PROMPT_RANGE = rules.RANGE
local CONSOLE_CFRAME = CFrame.new(0, 4, -24)
local SPAWN_CFRAME = CFrame.new(0, 4, -8)

local REMOTE_NAME = "Facet_Outpost"

local remote = Instance.new("RemoteEvent")
remote.Name = REMOTE_NAME
remote.Parent = ReplicatedStorage

local outpost: Model? = nil
local console: BasePart? = nil
local prompt: ProximityPrompt? = nil
local doorPart: BasePart? = nil
local beaconLight: PointLight? = nil
local lampLights: { PointLight } = {}
local doorClosedCFrame = CFrame.new()

local allocation: { [string]: number } = rules.copy(rules.START)
local revision = 0

local holder: Player? = nil
local holderToken = ""
local tokenCounter = 0
local openFor: { [Player]: boolean } = {}
local lastCommandAt: { [Player]: number } = {}
local loadedFor: { [Player]: boolean } = {}

local function send(player: Player, reply: any)
	remote:FireClient(player, reply)
end

local function broadcast(reply: any)
	for player in openFor do
		send(player, reply)
	end
end

local function stateReply(): any
	return { kind = "state", revision = revision, allocation = rules.copy(allocation) }
end

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildFixture()
	if outpost ~= nil then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Outpost"

	local consolePart = part("Console", Vector3.new(8, 6, 1), CONSOLE_CFRAME, Color3.fromRGB(48, 54, 62), model)
	consolePart.CanQuery = true
	consolePart.CanCollide = true

	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAttachment"
	attachment.Position = Vector3.new(0, 3.6, 0)
	attachment.Parent = consolePart

	local usePrompt = Instance.new("ProximityPrompt")
	usePrompt.Name = "UsePrompt"
	usePrompt.ActionText = "Use the power terminal"
	usePrompt.ObjectText = "Outpost 7"
	usePrompt.HoldDuration = 0
	usePrompt.MaxActivationDistance = PROMPT_RANGE
	usePrompt.RequiresLineOfSight = true
	usePrompt.Parent = attachment

	local door = part("BlastDoor", Vector3.new(8, 10, 1), CFrame.new(-11, 5, -24), Color3.fromRGB(120, 84, 48), model)
	doorClosedCFrame = door.CFrame

	local beacon = part("Beacon", Vector3.new(2, 8, 2), CFrame.new(12, 4, -24), Color3.fromRGB(90, 96, 104), model)
	local light = Instance.new("PointLight")
	light.Name = "BeaconLight"
	light.Brightness = 6
	light.Range = 34
	light.Color = Color3.fromRGB(255, 196, 96)
	light.Enabled = false
	light.Parent = beacon

	local lamps = Instance.new("Model")
	lamps.Name = "WorkshopLamps"
	lamps.Parent = model
	local lights: { PointLight } = {}
	for i = 1, 3 do
		local lamp = part(
			`Lamp{i}`,
			Vector3.new(1.6, 0.4, 1.6),
			CFrame.new(-4 + (i - 1) * 4, 8.5, -19),
			Color3.fromRGB(70, 74, 80),
			lamps
		)
		local lampLight = Instance.new("PointLight")
		lampLight.Name = "LampLight"
		lampLight.Brightness = 3
		lampLight.Range = 20
		lampLight.Enabled = false
		lampLight.Parent = lamp
		table.insert(lights, lampLight)
	end

	model.Parent = workspace

	outpost = model
	console = consolePart
	prompt = usePrompt
	doorPart = door
	beaconLight = light
	lampLights = lights

	usePrompt.Triggered:Connect(function(player: Player)
		tokenCounter += 1
		holder = player
		holderToken = `s{tokenCounter}`
		send(player, {
			kind = "session",
			token = holderToken,
			revision = revision,
			allocation = rules.copy(allocation),
			range = PROMPT_RANGE,
		})
	end)
end

local function destroyFixture()
	if outpost == nil then
		return
	end
	(outpost :: Model):Destroy()
	outpost = nil
	console = nil
	prompt = nil
	doorPart = nil
	beaconLight = nil
	lampLights = {}
	holder = nil
	holderToken = ""
end

local function applyToWorld()
	local door = doorPart
	if door ~= nil then
		local open = rules.isRunning(allocation, "door")
		door.CFrame = if open then doorClosedCFrame * CFrame.new(0, -9.5, 0) else doorClosedCFrame
		door.CanCollide = not open
	end
	if beaconLight ~= nil then
		beaconLight.Enabled = rules.isRunning(allocation, "beacon")
	end
	local lampsOn = rules.isRunning(allocation, "workshop")
	for _, light in lampLights do
		light.Enabled = lampsOn
	end
end

local function measure(player: Player, payload: any): any
	local consolePart = console
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local distance: number? = nil
	if consolePart ~= nil and root ~= nil and root:IsA("BasePart") then
		distance = (root.Position - consolePart.Position).Magnitude
	end
	local last = lastCommandAt[player]
	return {
		holderId = if holder ~= nil then tostring((holder :: Player).UserId) else nil,
		senderId = tostring(player.UserId),
		holderToken = if holderToken == "" then nil else holderToken,
		token = payload.token,
		sinceLast = if last ~= nil then os.clock() - last else nil,
		distance = distance,
		allocation = payload.allocation,
	}
end

local COMMANDS: { [string]: (Player, any) -> () } = {}

COMMANDS.open = function(player: Player, _payload: any)
	openFor[player] = true
	buildFixture()
	applyToWorld()
	send(player, stateReply())
end

COMMANDS.close = function(player: Player, _payload: any)
	openFor[player] = nil
	if holder == player then
		holder = nil
		holderToken = ""
	end
	if loadedFor[player] then
		loadedFor[player] = nil
		if player.Character ~= nil then
			(player.Character :: Model):Destroy()
			player.Character = nil
		end
	end
	if next(openFor) == nil then
		destroyFixture()
	end
end

COMMANDS.character = function(player: Player, payload: any)
	if payload.action == "load" then
		player:LoadCharacter()
		loadedFor[player] = true
		local character = player.Character
		if character ~= nil then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root ~= nil and root:IsA("BasePart") then
				(character :: Model):PivotTo(SPAWN_CFRAME)
			end
		end
		send(player, { kind = "character", loaded = true })
	elseif payload.action == "remove" then
		loadedFor[player] = nil
		if player.Character ~= nil then
			(player.Character :: Model):Destroy()
			player.Character = nil
		end
		if holder == player then
			holder = nil
			holderToken = ""
			send(player, { kind = "closed", reason = "character-removed" })
		end
		send(player, { kind = "character", loaded = false })
	end
end

COMMANDS.console = function(_player: Player, payload: any)
	if payload.action == "remove" then
		destroyFixture()
		broadcast({ kind = "closed", reason = "adornee-lost" })
	elseif payload.action == "restore" then
		destroyFixture()
		buildFixture()
		applyToWorld()
		broadcast(stateReply())
	end
end

COMMANDS.release = function(player: Player, _payload: any)
	if holder == player then
		holder = nil
		holderToken = ""
	end
end

COMMANDS.apply = function(player: Player, payload: any)
	local requestId = payload.requestId
	local verdict = rules.authorize(measure(player, payload))
	lastCommandAt[player] = os.clock()
	if not verdict.ok then
		send(player, {
			kind = "verdict",
			requestId = requestId,
			ok = false,
			code = verdict.code,
			message = verdict.message,
			revision = revision,
			allocation = rules.copy(allocation),
		})
		return
	end
	allocation = rules.copy(payload.allocation)
	revision += 1
	applyToWorld()
	send(player, {
		kind = "verdict",
		requestId = requestId,
		ok = true,
		revision = revision,
		allocation = rules.copy(allocation),
	})

	for other in openFor do
		if other ~= player then
			send(other, stateReply())
		end
	end
end

remote.OnServerEvent:Connect(function(player: Player, payload: any)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return
	end
	local command = COMMANDS[payload.kind]
	if command == nil then
		return
	end
	command(player, payload)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	openFor[player] = nil
	loadedFor[player] = nil
	lastCommandAt[player] = nil
	if holder == player then
		holder = nil
		holderToken = ""
	end
	if next(openFor) == nil then
		destroyFixture()
	end
end)
