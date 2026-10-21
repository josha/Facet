--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Preset = "Low" | "Medium" | "High"

export type Values = {
	musicVolume: number,
	effectsVolume: number,
	showDamageNumbers: boolean,
	cameraShake: boolean,
	graphics: Preset,
}

export type Patch = {
	musicVolume: number?,
	effectsVolume: number?,
	showDamageNumbers: boolean?,
	cameraShake: boolean?,
	graphics: Preset?,
}

export type Keybind = { action: string, keyboard: string, gamepad: string }

export type Failure = "invalid_value"

export type SaveResult = {
	ok: boolean,
	reason: Failure?,
	field: string?,
	values: Values,
}

export type Client = {
	defaults: Values,
	presets: { Preset },
	keybinds: { Keybind },
	get: () -> Values,
	save: (patch: Patch) -> SaveResult,
	onChanged: (callback: (Values) -> ()) -> RBXScriptConnection,
}

local defaults: Values = {
	musicVolume = 70,
	effectsVolume = 70,
	showDamageNumbers = true,
	cameraShake = true,
	graphics = "High",
}

local presets: { Preset } = { "Low", "Medium", "High" }

local keybinds: { Keybind } = {
	{ action = "Sprint", keyboard = "Left Shift", gamepad = "L3" },
	{ action = "Interact", keyboard = "E", gamepad = "X" },
	{ action = "Inventory", keyboard = "I", gamepad = "Y" },
	{ action = "Map", keyboard = "M", gamepad = "Select" },
}

local function client(): Client
	assert(RunService:IsClient(), "Settings.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getSettings = remotes:WaitForChild("GetSettings") :: RemoteFunction
	local saveSettings = remotes:WaitForChild("SaveSettings") :: RemoteFunction
	local changed = remotes:WaitForChild("SettingsChanged") :: RemoteEvent
	return {
		defaults = table.clone(defaults),
		presets = table.clone(presets),
		keybinds = keybinds,
		get = function(): Values
			return getSettings:InvokeServer()
		end,
		save = function(patch: Patch): SaveResult
			return saveSettings:InvokeServer(patch)
		end,
		onChanged = function(callback: (Values) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
	}
end

return {
	client = client,
	defaults = defaults,
	presets = presets,
	keybinds = keybinds,
}
