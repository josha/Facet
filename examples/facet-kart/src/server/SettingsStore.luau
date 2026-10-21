--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage.Shared.Hub.Settings)

type Values = Settings.Values
type SaveResult = Settings.SaveResult

export type Entry = { kind: string, fields: { string }, ok: boolean, reason: string?, at: number }

local SAVED: Values = {
	musicVolume = 60,
	effectsVolume = 80,
	showDamageNumbers = true,
	cameraShake = false,
	graphics = "Medium",
}
local SAVE_DELAY = 0.2

local stored: { [Player]: Values } = {}
local journals: { [Player]: { Entry } } = {}
local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SettingsChanged") :: RemoteEvent

local function valuesOf(player: Player): Values
	local values = stored[player]
	if values == nil then
		values = table.clone(SAVED)
		stored[player] = values
	end
	return values
end

local function journalOf(player: Player): { Entry }
	local journal = journals[player]
	if journal == nil then
		journal = {}
		journals[player] = journal
	end
	return journal
end

local function get(player: Player): Values
	return table.clone(valuesOf(player))
end

local function volume(value: unknown): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	if value < 0 or value > 100 then
		return nil
	end
	return math.floor(value + 0.5)
end

local function save(player: Player, patch: unknown): SaveResult
	local current = valuesOf(player)
	local journal = journalOf(player)
	if type(patch) ~= "table" then
		table.insert(journal, { kind = "save", fields = {}, ok = false, reason = "invalid_value", at = os.clock() })
		return { ok = false, reason = "invalid_value", field = nil, values = table.clone(current) }
	end
	local raw = patch :: { [string]: unknown }
	local next = table.clone(current)
	local fields: { string } = {}
	for key, value in raw do
		local accepted = true
		if key == "musicVolume" or key == "effectsVolume" then
			local level = volume(value)
			if level == nil then
				accepted = false
			elseif key == "musicVolume" then
				next.musicVolume = level
			else
				next.effectsVolume = level
			end
		elseif key == "showDamageNumbers" or key == "cameraShake" then
			if type(value) ~= "boolean" then
				accepted = false
			elseif key == "showDamageNumbers" then
				next.showDamageNumbers = value
			else
				next.cameraShake = value
			end
		elseif key == "graphics" then
			if value == "Low" or value == "Medium" or value == "High" then
				next.graphics = value
			else
				accepted = false
			end
		else
			accepted = false
		end
		if not accepted then
			table.insert(
				journal,
				{ kind = "save", fields = { key }, ok = false, reason = "invalid_value", at = os.clock() }
			)
			return { ok = false, reason = "invalid_value", field = key, values = table.clone(current) }
		end
		table.insert(fields, key)
	end
	task.wait(SAVE_DELAY)
	stored[player] = next
	table.sort(fields)
	table.insert(journal, { kind = "save", fields = fields, ok = true, reason = nil, at = os.clock() })
	changed:FireClient(player, table.clone(next))
	return { ok = true, reason = nil, field = nil, values = table.clone(next) }
end

local function push(player: Player, patch: { [string]: unknown }): SaveResult
	return save(player, patch)
end

local function journal(player: Player): { Entry }
	return table.clone(journalOf(player))
end

Players.PlayerRemoving:Connect(function(player)
	stored[player] = nil
	journals[player] = nil
end)

return {
	get = get,
	save = save,
	push = push,
	journal = journal,
}
