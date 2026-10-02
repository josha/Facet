--!strict
type ExampleContext = typeof(require("@repo/examples/types")(nil :: any))
local build = require("./collection_demo")
local TEAMS = { "Rustbucket", "Chrome Coyote", "Nine Volt", "Paper Lantern", "Bad Weather" }
return {
	title = "Virtualized table",
	build = function(ctx: ExampleContext)
		local rows = {}
		for index = 1, 2000 do
			rows[index] = {
				id = `e{index}`,
				n = index,
				team = TEAMS[(index - 1) % #TEAMS + 1],
				best = string.format("1:%02d.%03d", 12 + (index * 7) % 40, (index * 137) % 1000),
			}
		end
		return build(ctx, {
			name = "table_virtualized",
			title = "2 000 entrants, one window",
			rows = rows,
			table = true,
			entrants = true,
			editable = true,
			columns = {
				{
					id = "entrant",
					label = "Entrant",
					minWidth = 90,
					value = function(item)
						return `#{item.n}`
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").TableColumn_any(nil :: any)),
				{
					id = "team",
					label = "Team",
					minWidth = 140,
					editor = "menu",
					options = (function()
						local choices = {}
						for _, team in TEAMS do
							table.insert(choices, { value = team, label = team })
						end
						return choices
					end)(),
					value = function(item)
						return item.team
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").TableColumn_any(nil :: any)),
				{
					id = "best",
					label = "Best lap",
					minWidth = 90,
					value = function(item)
						return item.best
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").TableColumn_any(nil :: any)),
			},
		})
	end,
}
