--!strict
-- Shared construction-time grammar for Button and Alert shortcuts.
local guard = require("../spec_guard")
local shortcut = {}
function shortcut.validate(value: any)
	if value ~= nil then
		guard.assertKnownKeys("Button.shortcut", value, guard.keySet({ "keyCode", "modifiers" }), "shortcut")
		assert(type(value.keyCode) == "string" and value.keyCode ~= "", "Button: shortcut requires keyCode")
		if value.modifiers ~= nil then
			guard.assertKnownKeys("Button.shortcut", value.modifiers, guard.keySet({ "shift" }), "shortcut.modifiers")
			assert(
				value.modifiers.shift == nil or type(value.modifiers.shift) == "boolean",
				"Button: shortcut shift modifier must be boolean"
			)
		end
		assert(
			value.keyCode ~= "Escape" and value.keyCode ~= "Tab",
			"Button: Escape and Tab retain engine and navigation ownership"
		)
	end
end
return shortcut
