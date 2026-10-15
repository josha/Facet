--!strict
local FacetTypes = require("../../src")

type FacetModule = FacetTypes.Facet
type FacetControls = FacetTypes.Controls
type NumberCell = FacetTypes.Cell<number>
type StringCell = FacetTypes.Cell<string>
type TimerControls = FacetTypes.TimerControls
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Model = {
	phase: StringCell,
	deadline: NumberCell,
	now: () -> number,
	coins: NumberCell,
	gems: NumberCell,
}

return function(Facet: FacetModule, UI: FacetControls, model: Model): Instance
	local timer: TimerControls = {}
	return UI.Screen "RoundHud" {
		padding = "m",
		UI.Composition "Corners" {
			UI.fill(),
			padding = "s",
			UI.Region "Phase" {
				zone = "top",
				rank = 1,
				UI.VStack "PhaseStack" {
					gap = "xs",
					align = "center",
					UI.Text "PhaseName" { text = model.phase, textRole = "caption" },
					UI.Timer "Clock" {
						deadline = model.deadline,
						now = model.now,
						controls = timer,
						textRole = "numeral",
					},
				},
			},
			UI.Region "Wallet" {
				zone = "topLeft",
				rank = 2,
				UI.HStack "Counters" {
					gap = "s",
					UI.Text "Coins" {
						text = function(use: Use)
							return `{Facet.format.compact(use(model.coins))} Coins`
						end,
						textRole = "numeral",
					},
					UI.Text "Gems" {
						text = function(use: Use)
							return `{Facet.format.grouped(use(model.gems))} Gems`
						end,
						textRole = "numeral",
					},
				},
			},
		},
	}
end
