--!strict

local RobloxTypes = require "./types"

export type Class = RobloxTypes.PreferredInputClass

export type Spec = RobloxTypes.PreferredInputSpec

local touch: Spec = { class = "Touch", token = "touch" }
local keyboardAndMouse: Spec = { class = "KeyboardAndMouse", token = "keyboard-and-mouse" }
local gamepad: Spec = { class = "Gamepad", token = "gamepad" }

local SPECS: { [string]: Spec } = {
	Touch = touch,
	KeyboardAndMouse = keyboardAndMouse,
	Gamepad = gamepad,
}

local function nameOf(value: unknown): string
	return (string.gsub(tostring(value), "^Enum%.PreferredInput%.", ""))
end

local function specOf(value: unknown): Spec
	return SPECS[nameOf(value)] or keyboardAndMouse
end

return {
	specOf = specOf,
}
