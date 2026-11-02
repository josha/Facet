--!strict
local Facet = require("../../src")

return function(UI: Facet.Controls)
	local presented = Facet.Compose.cell(false)
	local function content(): Instance
		return UI.Text { text = "Content" }
	end
	local function nodes(): { Instance }
		return { content() }
	end
	local function activate() end
	local command: Facet.MenuCommand = { label = "Remove", role = "destructive", onSelect = activate }
	local language: Facet.ReadOnlyValue<"en" | "es"> = Facet.Compose.cell<<"en" | "es">>("en")
	return {
		UI.Sheet "Panel" {
			isPresented = presented,
			content = content,
			detents = { { id = "compact", fraction = 0.8 } },
		},
		UI.Dialog "Confirm" {
			isPresented = presented,
			actions = { { id = "accept", label = "Accept", onActivate = activate } },
		},
		(UI.Menu "Commands")<<string>> { items = { command } },
		Facet.Compose.fragment(nodes),
		language,
	}
end
