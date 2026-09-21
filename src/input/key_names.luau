--!strict
-- Native key labels/images are machine facts. Headless and unavailable answers
-- use readable names, with the caller retaining its raw-key fallback.
local specGuard = require("../spec_guard")
local key_names = {}
local SHARED: { [string]: string } = {
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL2 = "LT",
	ButtonR2 = "RT",
	ButtonL3 = "LS",
	ButtonR3 = "RS",
	ButtonStart = "Start",
	ButtonSelect = "Select",
	DPadUp = "D-Pad Up",
	DPadDown = "D-Pad Down",
	DPadLeft = "D-Pad Left",
	DPadRight = "D-Pad Right",
	Thumbstick1 = "Left Stick",
	Thumbstick2 = "Right Stick",
	Return = "Enter",
	KeypadEnter = "Enter",
	Escape = "Esc",
	Space = "Space",
	Tab = "Tab",
	Backspace = "Backspace",
	Delete = "Delete",
	LeftShift = "Shift",
	RightShift = "Shift",
	LeftControl = "Ctrl",
	RightControl = "Ctrl",
	LeftAlt = "Alt",
	RightAlt = "Alt",
	LeftMeta = "Cmd",
	RightMeta = "Cmd",
	Up = "Up",
	Down = "Down",
	Left = "Left",
	Right = "Right",
}

-- ...and the function keys, by the same rule and in one line rather than twelve
for index = 1, 12 do
	SHARED[`F{index}`] = `F{index}`
end

export type Platform = {
	label: ((keyCode: string) -> string?)?,
	image: ((keyCode: string) -> string?)?,
}
local PLATFORM_KEYS = specGuard.keySet({ "image", "label" })
local providers: { { value: Platform? } } = {}
local platform: Platform? = nil

-- Installations own only their registration. Out-of-order disposal cannot
-- resurrect a removed provider; native providers capture services, never apps.
function key_names.setPlatform(provider: Platform?): () -> ()
	specGuard.assertKnownKeys("keyNames.setPlatform", provider, PLATFORM_KEYS, "provider")
	local registration = { value = provider }
	table.insert(providers, registration)
	platform = provider
	return function()
		local index = table.find(providers, registration)
		if index == nil then
			return
		end
		table.remove(providers, index)
		platform = if #providers > 0 then providers[#providers].value else nil
	end
end

function key_names.label(keyCode: string?): string?
	if type(keyCode) ~= "string" or keyCode == "" then
		return nil
	end
	local ask = if platform ~= nil then platform.label else nil
	if ask ~= nil then
		local answer = ask(keyCode)
		if type(answer) == "string" and string.match(answer, "%S") ~= nil and answer ~= keyCode then
			return answer
		end
	end
	return SHARED[keyCode]
end

-- image(keyCode) -> the platform's own glyph picture for that key, or nil.
-- There is no shared fallback on purpose: art this library does not have is a
-- WORD, not a broken picture.
function key_names.image(keyCode: string?): string?
	if type(keyCode) ~= "string" or keyCode == "" then
		return nil
	end
	local ask = if platform ~= nil then platform.image else nil
	if ask == nil then
		return nil
	end
	local answer = ask(keyCode)
	return if type(answer) == "string" and string.match(answer, "%S") ~= nil then answer else nil
end

return key_names
