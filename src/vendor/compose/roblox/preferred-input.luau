--!strict

export type Class = "Touch" | "KeyboardAndMouse" | "Gamepad"

export type Spec = {
	class: Class,
	token: string,
}

local touch: Spec = { class = "Touch", token = "touch" }
local keyboardAndMouse: Spec = { class = "KeyboardAndMouse", token = "keyboard-and-mouse" }
local gamepad: Spec = { class = "Gamepad", token = "gamepad" }

local SPECS: { [string]: Spec } = {
	Touch = touch,
	KeyboardAndMouse = keyboardAndMouse,
	Gamepad = gamepad,
}

local function nameOf(value: any): string
	return (string.gsub(tostring(value), "^Enum%.PreferredInput%.", ""))
end

local function specOf(value: any): Spec
	return SPECS[nameOf(value)] or keyboardAndMouse
end

return {
	specOf = specOf,
}
