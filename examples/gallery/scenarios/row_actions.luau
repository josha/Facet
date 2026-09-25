--!strict
local build = require("./collection_demo")
local SEED = {
	{
		id = "m1",
		from = "Ari Foyer",
		subject = "Kickoff notes",
		preview = "Quick recap from the sync — three follow-ups, none urgent.",
		read = false,
		flagged = false,
	},
	{
		id = "m2",
		from = "Sip Works",
		subject = "Order confirmed",
		preview = "Your order #4521 ships Thursday.",
		read = true,
		flagged = false,
	},
	{
		id = "m3",
		from = "Glade Team",
		subject = "Weekly digest",
		preview = "Here's what happened in the glade this week.",
		read = false,
		flagged = true,
	},
	{
		id = "m4",
		from = "Wardrobe Co",
		subject = "Restock alert",
		preview = "Back in stock: the item you asked about.",
		read = true,
		flagged = false,
	},
	{
		id = "m5",
		from = "Cartwheel Studio",
		subject = "Beta invite",
		preview = "You're in — here's how to get started.",
		read = false,
		flagged = false,
	},
	{
		id = "m6",
		from = "Rally Ops",
		subject = "Standings update",
		preview = "Leaderboard shuffled after today's heats.",
		read = true,
		flagged = false,
	},
}
return {
	title = "Mail row actions",
	build = function(ctx)
		local Compose, UI = ctx.Compose, ctx.UI
		local selected = Compose.cell("list")
		local tabs, surfaces = {}, {}
		for _, entry in { { "list", "List" }, { "table", "Table" }, { "virtual", "Virtual list" } } do
			local kind, label = entry[1], entry[2]
			table.insert(tabs, {
				id = kind,
				label = label,
				content = function()
					local rows = table.clone(SEED)
					local built = build(ctx, {
						name = "Mail_" .. kind,
						title = "Mail",
						rows = rows,
						count = #rows,
						actions = true,
						mail = true,
						table = kind == "table",
						list = kind == "list",
					})
					surfaces[kind] = built
					return built.screen()
				end,
			})
		end
		return {
			report = function()
				local result = { active = selected:peek(), surfaces = {} }
				for kind, built in surfaces do
					result.surfaces[kind] = built.report()
				end
				return result
			end,
			screen = function()
				return UI.TabView "RowActions" {
					selection = selected,
					tabs = tabs,
					Size = ctx.types.UDim2.fromScale(1, 1),
				}
			end,
		}
	end,
}
