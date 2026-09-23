--!strict
local build = require("./collection_demo")
local TEAMS = { "Rustbucket", "Chrome Coyote", "Nine Volt", "Paper Lantern", "Bad Weather" }
return {
	title = "Virtualized table",
	build = function(ctx)
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
			columns = {
				{
					id = "entrant",
					label = "Entrant",
					minWidth = 90,
					value = function(item)
						return `#{item.n}`
					end,
				},
				{
					id = "team",
					label = "Team",
					minWidth = 100,
					value = function(item)
						return item.team
					end,
				},
				{
					id = "best",
					label = "Best lap",
					minWidth = 90,
					value = function(item)
						return item.best
					end,
				},
			},
		})
	end,
}
