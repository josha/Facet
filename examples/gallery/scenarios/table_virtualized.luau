--!strict

type TableColumn = typeof(require("@repo/tools/typecheck/aliases").TableColumn)
type ExampleContext = typeof(require("@repo/examples/types").Context)
local build = require("./collection_demo")
local TEAMS = { "Rustbucket", "Chrome Coyote", "Nine Volt", "Paper Lantern", "Bad Weather" }
return {
	title = "Virtualized table",
	build = function(ctx: ExampleContext)
		local rows: { build.Row } = {}
		for index = 1, 2000 do
			rows[index] = {
				id = `e{index}`,
				n = index,
				team = TEAMS[(index - 1) % #TEAMS + 1],
				best = string.format("1:%02d.%03d", 12 + (index * 7) % 40, (index * 137) % 1000),
			}
		end
		local columns: { TableColumn } = {
			{
				id = "entrant",
				label = "Entrant",
				minWidth = 90,
				value = function(item: build.Row): string
					return `#{item.n}`
				end,
			},
			{
				id = "team",
				label = "Team",
				minWidth = 140,
				editor = "menu",
				options = (function(): { { value: unknown, label: string } }
					local choices: { { value: unknown, label: string } } = {}
					for _, team in TEAMS do
						table.insert(choices, { value = team, label = team })
					end
					return choices
				end)(),
				value = function(item: build.Row): string?
					return item.team
				end,
			},
			{
				id = "best",
				label = "Best lap",
				minWidth = 90,
				value = function(item: build.Row): string?
					return item.best
				end,
			},
		}
		return build(ctx, {
			name = "table_virtualized",
			title = "2 000 entrants, one window",
			rows = rows,
			table = true,
			entrants = true,
			editable = true,
			columns = columns,
		})
	end,
}
