--!strict

local Players = game:GetService("Players")
local Ledger = require(script.Parent.Ledger)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dialogue = require(ReplicatedStorage.Shared.Hub.Dialogue)

type State = Dialogue.State
type Node = Dialogue.Node
type Result = Dialogue.Result

export type Entry = { kind: string, node: string?, choice: string?, ok: boolean, at: number }

type Option = { id: string, text: string, goes: string }

type Step = { speaker: string, text: string, choices: { Option }, ended: boolean, grant: number? }

type Profile = {
	nearby: string?,
	node: string?,
	wallet: Ledger.Wallet,
	questAccepted: boolean,
	busy: boolean,
	journal: { Entry },
}

local NPC = "Mechanic"

local TREE: { [string]: Step } = {
	start = {
		speaker = NPC,
		text = "Hello, racer! Help me test the hub equipment. Will you help me?",
		choices = {
			{ id = "help", text = "I will help you.", goes = "thanks" },
			{ id = "ask", text = "What needs a test?", goes = "well" },
			{ id = "refuse", text = "Not today.", goes = "later" },
		},
		ended = false,
	},
	well = {
		speaker = NPC,
		text = "The kart motor needs a test before the next race.",
		choices = {
			{ id = "help", text = "I will help you.", goes = "thanks" },
			{ id = "refuse", text = "Not today.", goes = "later" },
		},
		ended = false,
	},
	thanks = {
		speaker = NPC,
		text = "Thank you! Take 50 Coins and a Starter Crate for the test.",
		choices = { { id = "bye", text = "Goodbye.", goes = "farewell" } },
		ended = false,
		grant = 50,
	},
	later = {
		speaker = NPC,
		text = "Maybe another day, then.",
		choices = {},
		ended = true,
	},
	farewell = {
		speaker = NPC,
		text = "Safe racing. Open your crate before the next race!",
		choices = {},
		ended = true,
	},
}

local profiles: { [Player]: Profile } = {}
local overrides: { [Player]: boolean } = {}
local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DialogueStateChanged") :: RemoteEvent

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if profile == nil then
		local created: Profile = {
			nearby = nil,
			node = nil,
			wallet = Ledger.wallet(player),
			questAccepted = false,
			busy = false,
			journal = {},
		}
		profiles[player] = created
		return created
	end
	return profile
end

local function nodeOf(id: string?): Node?
	if id == nil then
		return nil
	end
	local step = TREE[id :: string]
	local choices: { Dialogue.Choice } = {}
	for _, choice in step.choices do
		table.insert(choices, { id = choice.id, text = choice.text })
	end
	return { id = id :: string, speaker = step.speaker, text = step.text, choices = choices, ended = step.ended }
end

local function snapshot(profile: Profile): State
	return {
		nearby = profile.nearby,
		node = nodeOf(profile.node),
		coins = profile.wallet.Coins,
		questAccepted = profile.questAccepted,
	}
end

local function publish(player: Player)
	changed:FireClient(player, snapshot(profileOf(player)))
end

local function answer(profile: Profile, ok: boolean, reason: Dialogue.Failure?): Result
	return { ok = ok, reason = reason, state = snapshot(profile) }
end

local function record(profile: Profile, kind: string, node: string?, choice: string?, ok: boolean)
	table.insert(profile.journal, { kind = kind, node = node, choice = choice, ok = ok, at = os.clock() })
end

local function getState(player: Player): State
	return snapshot(profileOf(player))
end

local function talk(player: Player): Result
	local profile = profileOf(player)
	if profile.nearby == nil then
		return answer(profile, false, "not_nearby")
	end
	profile.node = "start"
	record(profile, "talk", "start", nil, true)
	publish(player)
	return answer(profile, true, nil)
end

local function choose(player: Player, choiceId: unknown): Result
	local profile = profileOf(player)
	if profile.node == nil then
		return answer(profile, false, "no_conversation")
	end
	if profile.busy then
		return answer(profile, false, "busy")
	end
	local step = TREE[profile.node :: string]
	local chosen: Option? = nil
	for _, choice in step.choices do
		if choice.id == choiceId then
			chosen = choice
		end
	end
	if chosen == nil then
		record(profile, "choose", profile.node, tostring(choiceId), false)
		return answer(profile, false, "unknown_choice")
	end
	profile.busy = true
	task.wait(0.2)
	local target = (chosen :: Option).goes
	profile.node = target
	local grant = TREE[target].grant
	if grant ~= nil and not profile.questAccepted then
		profile.questAccepted = true
		profile.wallet.Coins += grant
		Ledger.addCrate(player)
	end
	profile.busy = false
	record(profile, "choose", target, tostring(choiceId), true)
	publish(player)
	return answer(profile, true, nil)
end

local function leave(player: Player): Result
	local profile = profileOf(player)
	profile.node = nil
	record(profile, "leave", nil, nil, true)
	publish(player)
	return answer(profile, true, nil)
end

local function setNearby(player: Player, nearby: boolean)
	local profile = profileOf(player)
	profile.nearby = if nearby then NPC else nil
	if not nearby then
		profile.node = nil
	end
	publish(player)
end

local function journal(player: Player): { Entry }
	return table.clone(profileOf(player).journal)
end

Players.PlayerRemoving:Connect(function(player)
	profiles[player] = nil
	overrides[player] = nil
end)

return {
	getState = getState,
	talk = talk,
	choose = choose,
	leave = leave,
	setNearby = function(player: Player, nearby: boolean)
		overrides[player] = true
		setNearby(player, nearby)
	end,
	autoNearby = function(player: Player, nearby: boolean)
		if overrides[player] == nil and (profileOf(player).nearby ~= nil) ~= nearby then
			setNearby(player, nearby)
		end
	end,
	journal = journal,
}
