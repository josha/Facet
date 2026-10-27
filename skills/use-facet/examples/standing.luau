--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)

export type Tier = { name: string, icon: string, next: string?, nextAt: number?, floor: number }
export type Record = { wins: number, losses: number, draws: number }
export type Standing = {
	mode: string,
	rating: number,
	tier: Tier,
	record: Record,
	placed: number,
	placements: number,
}

local Standing = {}

local function stat(UI: Facet.Controls, name: string, icon: string, value: (Facet.Use) -> string): Frame
	return UI.VStack(name) {
		align = "center",
		gap = "xs",
		UI.Label { title = name, icon = icon, presentation = "iconOnly", iconSize = 28 },
		UI.Text { text = value, textRole = "numeral" },
		UI.Text { text = name, textRole = "caption", role = "secondary" },
	}
end

function Standing.build(app: Facet.App, standing: Facet.ReadOnlyValue<Standing>): Frame
	local C, UI = Facet.Compose, app.UI
	local function placing(use: Facet.Use): boolean
		local current = use(standing)
		return current.placed < current.placements
	end
	local function count(field: "wins" | "losses" | "draws"): (Facet.Use) -> string
		return function(use: Facet.Use): string
			return Facet.format.grouped(use(standing).record[field])
		end
	end
	return UI.VStack "Standing" {
		width = "fill",
		maxWidth = 560,
		surface = "panel",
		corners = "panel",
		padding = "l",
		gap = "l",
		UI.Text "Mode" {
			text = function(use: Facet.Use): string
				return string.upper(use(standing).mode)
			end,
			textRole = "label",
			role = "secondary",
		},
		UI.HStack "Rank" {
			width = "fill",
			gap = "l",
			align = "center",
			UI.VStack "Emblem" {
				width = 112,
				height = 112,
				surface = "pane",
				corners = "pill",
				align = "center",
				distribute = "center",
				C.keyed({
					from = C.formula(function(use: Facet.Use): { Tier }
						return { use(standing).tier }
					end),
					key = function(tier: Tier): string
						return tier.icon
					end,
					render = function(current: Facet.ReadOnlyValue<Tier>): GuiObject
						return UI.Label {
							title = function(use: Facet.Use): string
								return use(current).name .. " tier"
							end,
							icon = current:peek().icon,
							presentation = "iconOnly",
							iconSize = 64,
						}
					end,
				}),
			},
			UI.VStack "Rating" {
				width = "fill",
				gap = "xs",
				UI.Text "Value" {
					text = function(use: Facet.Use): string
						return Facet.format.grouped(use(standing).rating)
					end,
					textRole = "numeral",
				},
				UI.Text "Tier" {
					text = function(use: Facet.Use): string
						return use(standing).tier.name
					end,
					textRole = "heading",
				},
				UI.ProgressView "NextTier" {
					Visible = function(use: Facet.Use): boolean
						return not placing(use) and use(standing).tier.nextAt ~= nil
					end,
					value = function(use: Facet.Use): number
						local current = use(standing)
						local top = current.tier.nextAt or current.rating
						return math.clamp(
							(current.rating - current.tier.floor) / math.max(1, top - current.tier.floor),
							0,
							1
						)
					end,
					endLabel = "Next tier",
				},
			},
		},
		C.show(placing, function()
			return UI.VStack "Placement" {
				width = "fill",
				gap = "s",
				UI.ProgressView "Placements" {
					value = function(use: Facet.Use): number
						return use(standing).placed
					end,
					max = function(use: Facet.Use): number
						return use(standing).placements
					end,
					segments = standing:peek().placements,
				},
				UI.Text "Goal" {
					text = function(use: Facet.Use): string
						local current = use(standing)
						local left = current.placements - current.placed
						return `Play {left} ranked {if left == 1 then "game" else "games"} to place your rank.`
					end,
					wrap = true,
				},
			}
		end, function()
			return UI.HStack "Record" {
				width = "fill",
				distribute = "spaceEvenly",
				stat(UI, "Wins", "trophy", count("wins")),
				stat(UI, "Losses", "close", count("losses")),
				stat(UI, "Draws", "flag", count("draws")),
			}
		end),
	}
end

return Standing
