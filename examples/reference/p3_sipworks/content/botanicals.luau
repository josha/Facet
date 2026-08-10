--!strict
-- The Sipworks botanical shelf (spec §2): 18 botanicals plus spring water.
--
-- Original clean-room content. Every number here is DOMAIN data — how heavy a
-- teaspoon of a leaf is, how much caffeine a gram of it carries, how long it
-- steeps, how warm it drinks — so the brew facts on a botanical card are
-- DERIVED from the blend's own measured quantity rather than authored twice.
--
-- `water = true` marks the filler: spring water is excluded from every menu and
-- tile surface and from the searchable ingredient names, and still appears in a
-- recipe's measures, exactly as the spec requires.

export type Botanical = {
	id: string,
	name: string,
	gramsPerTsp: number,
	caffeinePerGram: number,
	steepMinutes: number,
	warmth: number, -- 1..5
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
	-- the filler, and the one entry no menu surface may show
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
