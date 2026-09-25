--!strict

export type Botanical = {
	id: string,
	name: string,
	gramsPerTsp: number,
	caffeinePerGram: number,
	steepMinutes: number,
	warmth: number,
	water: boolean?,
}

local list: { Botanical } = {
	{ id = "assam", name = "Assam", gramsPerTsp = 2.3, caffeinePerGram = 22, steepMinutes = 4, warmth = 3 },
	{ id = "sencha", name = "Sencha", gramsPerTsp = 2.0, caffeinePerGram = 18, steepMinutes = 2, warmth = 2 },
	{ id = "oolong", name = "Oolong", gramsPerTsp = 2.2, caffeinePerGram = 16, steepMinutes = 3, warmth = 3 },
	{ id = "rooibos", name = "Rooibos", gramsPerTsp = 2.4, caffeinePerGram = 0, steepMinutes = 5, warmth = 3 },
	{ id = "chamomile", name = "Chamomile", gramsPerTsp = 1.2, caffeinePerGram = 0, steepMinutes = 5, warmth = 3 },
	{ id = "peppermint", name = "Peppermint", gramsPerTsp = 1.0, caffeinePerGram = 0, steepMinutes = 5, warmth = 1 },
	{ id = "spearmint", name = "Spearmint", gramsPerTsp = 1.0, caffeinePerGram = 0, steepMinutes = 5, warmth = 1 },
	{ id = "ginger", name = "Ginger", gramsPerTsp = 2.6, caffeinePerGram = 0, steepMinutes = 6, warmth = 5 },
	{ id = "cardamom", name = "Cardamom", gramsPerTsp = 2.0, caffeinePerGram = 0, steepMinutes = 5, warmth = 4 },
	{ id = "cinnamon", name = "Cinnamon", gramsPerTsp = 2.6, caffeinePerGram = 0, steepMinutes = 6, warmth = 5 },
	{ id = "clove", name = "Clove", gramsPerTsp = 2.1, caffeinePerGram = 0, steepMinutes = 5, warmth = 5 },
	{ id = "hibiscus", name = "Hibiscus", gramsPerTsp = 1.6, caffeinePerGram = 0, steepMinutes = 5, warmth = 2 },
	{ id = "lemongrass", name = "Lemongrass", gramsPerTsp = 1.1, caffeinePerGram = 0, steepMinutes = 4, warmth = 2 },
	{ id = "jasmine", name = "Jasmine", gramsPerTsp = 1.4, caffeinePerGram = 4, steepMinutes = 3, warmth = 2 },
	{ id = "lavender", name = "Lavender", gramsPerTsp = 1.0, caffeinePerGram = 0, steepMinutes = 4, warmth = 2 },
	{ id = "rosehip", name = "Rosehip", gramsPerTsp = 2.2, caffeinePerGram = 0, steepMinutes = 6, warmth = 2 },
	{
		id = "licorice-root",
		name = "Licorice root",
		gramsPerTsp = 2.4,
		caffeinePerGram = 0,
		steepMinutes = 5,
		warmth = 3,
	},
	{ id = "honeybush", name = "Honeybush", gramsPerTsp = 2.0, caffeinePerGram = 0, steepMinutes = 5, warmth = 3 },

	{
		id = "spring-water",
		name = "Spring water",
		gramsPerTsp = 0,
		caffeinePerGram = 0,
		steepMinutes = 0,
		warmth = 1,
		water = true,
	},
}

local byId: { [string]: Botanical } = {}
for _, b in list do
	byId[b.id] = b
end

return table.freeze({
	list = table.freeze(list),
	byId = table.freeze(byId),
	WATER_ID = "spring-water",
})
