--!strict
local FacetTypes = require("../../src")

type Use = FacetTypes.Use
type FacetModule = FacetTypes.Facet
type FacetControls = FacetTypes.Controls
type Result = { ok: boolean, rewards: { string }?, reason: string? }
type Model = { redeem: (code: string) -> Result }

return function(Facet: FacetModule, UI: FacetControls, model: Model): Instance
	local Compose = Facet.Compose
	local code = Compose.cell("")
	local busy = Compose.cell(false)
	local message = Compose.cell("")
	return UI.Screen "CodeRedeem" {
		padding = "m",
		gap = "m",
		UI.Text "Title" { text = "Redeem a code", textRole = "title" },
		UI.TextInput "Code" {
			label = "Code",
			value = code,
			enabled = function(use: Use)
				return not use(busy)
			end,
		},
		UI.Button "Redeem" {
			label = "Redeem",
			appearance = "emphasis",
			busy = busy,
			enabled = function(use: Use)
				return use(code) ~= "" and not use(busy)
			end,
			onActivate = function()
				busy:set(true)
				local result = model.redeem(code:peek())
				message:set(
					if result.ok
						then "Received: " .. table.concat(result.rewards or {}, ", ")
						else result.reason or "Redeem failed"
				)
				busy:set(false)
			end,
		},
		UI.Text "Result" { text = message, textRole = "body", wrap = true },
	}
end
