--!strict
local Facet = require("../../src")

return function(UI: Facet.Controls)
	local value = Facet.Compose.cell("")
	local enabled = Facet.Compose.formula(function()
		return true
	end)
	local message = Facet.Compose.formula(function()
		return ""
	end)
	local function change(text: string)
		value:set(text)
	end
	local function commit(_text: string, _reason: "focusLost" | "submit") end
	return UI.TextInput "Username" {
		presentation = "search",
		value = value,
		placeholder = "Username",
		maxLength = 20,
		enabled = enabled,
		onChange = change,
		errorText = message,
		trailing = UI.Button "Find" { label = "Find", enabled = enabled },
		onCommit = commit,
	}
end
