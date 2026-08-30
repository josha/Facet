--!strict
--[[ THE OUTPOST'S AUTHORITY — the whole server side of the showcase, in one file.

	WHY THERE IS A SERVER AT ALL, AND WHY THERE NEVER WAS ONE BEFORE. Every other
	example in this repository is client-only, and that has been correct: none of
	them changes anything another player could see. This one does — opening the
	blast door is a fact about the world, not about one player's screen — so
	`examples/gallery.project.json` gains a `ServerScriptService` mapping and it
	holds the outpost's authority and nothing else.

	IT IS DELIBERATELY SMALL AND DELIBERATELY READABLE. A reader should be able to
	see, in one file, WHAT THE SERVER CHECKS AND WHY. That list is five things,
	and the split between them and this file is deliberate: `measure` below READS
	them off the engine, and the shared `rules.authorize` DECIDES — so every
	refusal is exhaustively testable with no engine at all, and the client and the
	server cannot end up with two rulebooks.

	  1. the values are whole numbers inside their declared ranges;
	  2. the total is at most six;
	  3. the sender is the player who engaged THIS console (identity + staleness);
	  4. the request is not arriving faster than a human could send it;
	  5. the player is within range of the console RIGHT NOW, measured here.

	THE FIFTH IS THE ONE WORTH STARING AT. The client has a `ProximityPrompt`
	that will not even show itself past ten studs — and that is a suggestion, not
	a fact, because the thing making the claim is the thing being checked. The
	server measures the distance itself, from the character it can see, at the
	moment the command lands.

	WHAT CROSSES THE WIRE. One `RemoteEvent`, an intent one way and an outcome
	back. THE UI TREE IS NEVER REPLICATED — the `SurfaceGui` is built on each
	client, under that client's own `PlayerGui`, and only the ALLOCATION travels.

	THE VOCABULARY IS SHARED, NOT COPIED. Every refusal sentence comes out of
	`ReplicatedStorage.FacetExamples.outpost_terminal.rules`, which is the same
	pure module the terminal screen reads. A server that phrased its own refusals
	would be a second rulebook.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local rules = require(
	ReplicatedStorage:WaitForChild("FacetExamples"):WaitForChild("outpost_terminal"):WaitForChild("rules")
) :: any

-- ── the fixture's own numbers ───────────────────────────────────────────────

--[[ THE PROMPT'S ACTIVATION DISTANCE AND THE DISTANCE THIS FILE RE-MEASURES ARE
	THE SAME NUMBER, and it lives in the shared rules module so the affordance and
	the check cannot drift apart. `rules.MIN_COMMAND_INTERVAL` is there for the
	same reason. ]]
local PROMPT_RANGE = rules.RANGE
local CONSOLE_CFRAME = CFrame.new(0, 4, -24)
local SPAWN_CFRAME = CFrame.new(0, 4, -8)

local REMOTE_NAME = "Facet_Outpost"

-- ── replicated state ────────────────────────────────────────────────────────

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

--[[ ONE CONSOLE, ONE HOLDER. A session is the answer to "who engaged THIS
	console", and it is opened by the engine's own `ProximityPrompt.Triggered` on
	the SERVER — not by a client saying it did. `token` makes staleness visible:
	a client that re-engages gets a new one, and a command carrying the old one is
	refused rather than quietly honoured. ]]
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

-- ── the world fixture ───────────────────────────────────────────────────────

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

--[[ THE WORLD THE TERMINAL TALKS ABOUT. Built here rather than on a client for
	the reason the whole file exists: a console a client built would be a console
	only that client can see, and a door only that client can open. ]]
local function buildFixture()
	if outpost ~= nil then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Outpost"

	--[[ THE ADORNEE. 8 x 6 studs, which is the terminal's own 640 x 480 canvas
		aspect — `surface_target`'s canvas is invariant to the part, so an 8 x 2
		console would show the same canvas squashed. `CanQuery` STAYS TRUE: with it
		false the surface renders at full size and receives nothing at all, with no
		error anywhere (measured; it is why the adapter asserts it). ]]
	local consolePart = part("Console", Vector3.new(8, 6, 1), CONSOLE_CFRAME, Color3.fromRGB(48, 54, 62), model)
	consolePart.CanQuery = true
	consolePart.CanCollide = true

	--[[ THE WALK-UP INVITATION, and it is the platform's own. A `ProximityPrompt`
		on an `Attachment` works on keyboard, gamepad and touch without this example
		writing an input branch, and players already know what it is. Facet does not
		wrap it.

		THE ATTACHMENT SITS ABOVE THE CONSOLE ON PURPOSE. A live Facet surface SINKS
		the world input beneath it (measured: a `ClickDetector` on the same part
		fired while the surfaces were inert and fired zero times once they were
		live), so the prompt's own affordance is kept off the painted face. ]]
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

	--[[ ENGAGEMENT IS THE ENGINE'S EVENT, ON THE SERVER. `Triggered` arrives here
		with the player who actually triggered it, which is the only trustworthy
		answer to "who is at this console". The client hears its own copy of the
		same event and mounts its own surface; nothing about the session is taken
		from the client. ]]
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

--[[ THE WORLD ANSWERS. This is the only place the outpost's objects move, and it
	runs only after `validate` has said yes. ]]
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

-- ── the five checks: MEASURED here, DECIDED in the shared rules ─────────────

--[[ THE ENGINE HALF OF THE AUTHORITY, AND IT IS FOUR READS. Who holds the
	console, which token arrived, how long since this sender's last command, and
	how far the sender's character actually is from the console — measured HERE,
	on the server, from the character this server can see, at the moment the
	command lands. `rules.authorize` then decides, and every sentence it refuses
	with is the one the terminal itself would have used.

	THE DISTANCE READ IS THE POINT OF THE WHOLE FILE. The client has a
	`ProximityPrompt` that will not even show itself past ten studs — and that is
	a suggestion, not a fact, because the thing making the claim is the thing
	being checked. ]]
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

-- ── the commands ────────────────────────────────────────────────────────────

local COMMANDS: { [string]: (Player, any) -> () } = {}

-- build the fixture (if nobody has yet) and answer with the outpost's state
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

--[[ THE CHARACTER, LOADED ON REQUEST. `Players.CharacterAutoLoads` is false in
	the showcase and that is deliberate — forty-odd UI demos do not want an avatar
	standing in front of them — but a `ProximityPrompt` measures distance from a
	character and requires line of sight to one. Only the server can load one, so
	the scenario asks. Removing it again is one of the eight exit paths, driven by
	the same control that switches demos. ]]
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

--[[ THE STREAMED-OUT ADORNEE, driveable. `.Adornee` still names a DESTROYED part
	(measured), so a client cannot notice this by reading the property — it has to
	watch the instance's own lifetime, which is what `surface_target`'s
	`onAdorneeLost` does. This command is how that path gets exercised. ]]
COMMANDS.console = function(_player: Player, payload: any)
	if payload.action == "remove" then
		--[[ THE WHOLE FIXTURE GOES, not just the part. Destroying the console alone
			would leave an `Outpost` model behind that `buildFixture` then refuses to
			rebuild — and the client cannot re-adopt a destroyed adornee anyway, since
			`surface_target` holds the part it was constructed with. A stream-out is a
			fixture that is gone; a stream-in is a new one. ]]
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

--[[ THE ONE COMMAND THAT CHANGES THE WORLD. Everything above is fixture drive;
	this is the domain intent, and it is the only path to `applyToWorld`. ]]
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
	-- ...and everyone else learns the outpost changed, because it did
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
