--!strict

local storage, players = game:GetService("ReplicatedStorage"), game:GetService("Players")
local Facet = require(storage:WaitForChild("Facet"))
local modules = storage:WaitForChild("FacetHome")
local policy = require(modules:WaitForChild("model"))
local world = require(modules:WaitForChild("world"))
local assets = game:GetService("ServerStorage"):WaitForChild("FurnitureAssets")
local runtime = Facet.Roblox.createRuntime()
local Host = (runtime.constructors :: unknown) :: any
local owner = Facet.Compose.createOwner(runtime.reactor)
local function own(callback: () -> ...any): ...any
	return Facet.Compose.withOwner(owner, callback)
end
local root = own(function()
	return Host.Folder "FacetHomes" {}
end)
root.Parent = workspace
local remote = own(function()
	return Host.RemoteFunction "FacetHomeRequest" {}
end)
remote.Parent = storage
local signal = own(function()
	return Host.RemoteEvent "FacetHomeSelect" {}
end)
signal.Parent = storage
local storeOk, store = pcall(function()
	return game:GetService("DataStoreService"):GetDataStore("FacetHome.Layout.v1")
end)
local sessions: { [Player]: any } = {}
local sequence = 0
local function repaint(session: any)
	if session.furnitureOwner then
		session.furnitureOwner.dispose()
	end
	session.furnitureOwner = Facet.Compose.createOwner(runtime.reactor)
	Facet.Compose.withOwner(session.furnitureOwner, function()
		local pieces: { Instance } = {}
		for key, item in session.draft.slots do
			local at = CFrame.new(session.origin + world.position(assert(tonumber(key))))
				* CFrame.Angles(0, item.rotation * math.pi / 2, 0)
			local piece = world.furniture(Host, item, at, assets)
			Facet.Compose.cleanup(function()
				piece:Destroy()
			end)
			table.insert(pieces, piece)
		end
		session.furniture = Host.Model("Furniture")(pieces)
		session.furniture.Parent = session.room
	end)
end
local function open(player: Player): any
	if sessions[player] then
		return sessions[player]
	end
	sequence += 1
	local origin = Vector3.new(((sequence - 1) % 4) * 65, 0, ((sequence - 1) // 4) * 70)
	local roomOwner = Facet.Compose.createOwner(runtime.reactor)
	local room, markers = Facet.Compose.withOwner(roomOwner, function()
		return world.room(Host, player, origin)
	end)
	room.Parent = root
	local session: any = {
		origin = origin,
		room = room,
		roomOwner = roomOwner,
		draft = policy.empty(),
		saved = policy.empty(),
		cloud = false,
		busy = true,
		nextRequest = 0,
		nextSave = 0,
	}
	sessions[player] = session
	for index, marker in markers do
		local prompt = marker:FindFirstChildWhichIsA("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(visitor: Player)
				if visitor == player then
					signal:FireClient(player, index)
				end
			end)
		end
	end
	local ok, value = pcall(function()
		assert(storeOk)
		local data = store:GetAsync(tostring(player.UserId))
		return if data then policy.validate(data) else policy.empty()
	end)
	if ok then
		session.draft, session.saved, session.cloud = value, policy.validate(value), true
	end
	session.busy = false
	repaint(session)
	local function arrive(character: Model)
		local part = character:WaitForChild("HumanoidRootPart", 10)
		if part and part:IsA("BasePart") then
			character:PivotTo(CFrame.lookAt(origin + Vector3.new(0, 4, -18), origin + Vector3.new(0, 4, 0)))
		end
	end
	session.arrival = player.CharacterAdded:Connect(arrive)
	if player.Character then
		task.spawn(arrive, player.Character)
	end
	return session
end
remote.OnServerInvoke = function(player: Player, request: any): any
	local ok, result = pcall(function()
		return own(function()
			assert(type(request) == "table" and type(request.action) == "string", "Invalid request")
			local session = open(player)
			assert(not session.busy, "Home is busy. Try again")
			assert(os.clock() >= session.nextRequest, "Please slow down")
			session.nextRequest = os.clock() + 0.08
			local message = "Room ready"
			if request.action == "save" then
				assert(os.clock() >= session.nextSave, "Please wait before saving again")
				session.nextSave = os.clock() + 6
				if session.cloud then
					session.busy = true
					local savedOk, saved = pcall(function()
						return store:UpdateAsync(tostring(player.UserId), function(previous)
							return policy.replace(previous, session.saved.revision, session.draft), { player.UserId }
						end)
					end)
					session.busy = false
					assert(savedOk, "Cloud save failed. Your room is still here; retry Save")
					session.draft, session.saved = saved, policy.validate(saved)
					message = "Room saved to your account"
				else
					session.saved = policy.validate(session.draft)
					message = "Saved for this session only. Cloud storage is unavailable"
				end
			elseif request.action == "restore" then
				session.draft = policy.validate(session.saved)
				repaint(session)
				message = "Saved room restored"
			elseif request.action ~= "load" then
				assert(type(request.slot) == "number", "Choose a room slot")
				session.draft = policy.edit(session.draft, request.action, request.slot, request.kind, request.palette)
				repaint(session)
				message = "Room updated"
			end
			return {
				ok = true,
				layout = session.draft,
				origin = { session.origin.X, session.origin.Z },
				cloud = session.cloud,
				message = message,
			}
		end)
	end)
	return if ok then result else { ok = false, message = tostring(result) }
end
players.PlayerRemoving:Connect(function(player: Player)
	local session = sessions[player]
	if session then
		session.arrival:Disconnect()
		session.furnitureOwner.dispose()
		session.roomOwner.dispose()
		sessions[player] = nil
	end
end)
script.Destroying:Connect(function()
	for _, session in sessions do
		session.arrival:Disconnect()
		session.furnitureOwner.dispose()
		session.roomOwner.dispose()
	end
	root:Destroy()
	remote:Destroy()
	signal:Destroy()
	owner.dispose()
	runtime:dispose()
end)
