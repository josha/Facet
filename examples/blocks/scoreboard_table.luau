--!strict
local FacetTypes = require("../../src")

type FacetModule = FacetTypes.Facet
type FacetControls = FacetTypes.Controls
type SortCell = FacetTypes.Value<{ column: string, direction: "ascending" | "descending" }?>
type ReadOnlyValue<T> = FacetTypes.ReadOnlyValue<T>
type Player = { id: string, name: string, kills: number, deaths: number, score: number }
type Model = { players: ReadOnlyValue<{ Player }>, localPlayerId: string }

return function(Facet: FacetModule, UI: FacetControls, model: Model): Instance
	local sort: SortCell = Facet.Compose.cell(
		{ column = "score", direction = "descending" } :: { column: string, direction: "ascending" | "descending" }?
	)
	local columns: { FacetTypes.TableColumn<Player, string> } = {
		{
			id = "name",
			label = "Player",
			sortable = false,
			value = function(player: Player): unknown
				return player.name .. (if player.id == model.localPlayerId then " (You)" else "")
			end,
		},
		{
			id = "kills",
			label = "Kills",
			sortable = false,
			value = function(player: Player): unknown
				return player.kills
			end,
		},
		{
			id = "deaths",
			label = "Deaths",
			sortable = false,
			value = function(player: Player): unknown
				return player.deaths
			end,
		},
		{
			id = "score",
			label = "Score",
			sortable = false,
			value = function(player: Player): unknown
				return player.score
			end,
		},
	}
	local tableSpec: FacetTypes.KeyedTableSpec<Player, string> = {
		UI.fill(),
		from = model.players,
		key = "id",
		sort = sort,
		columns = columns,
	}
	return UI.Screen "Scoreboard" {
		padding = "m",
		gap = "m",
		UI.Text "Title" { text = "Scoreboard", textRole = "title" },
		UI.Table "Standings"(tableSpec),
	}
end
