--!strict
-- The Sipworks house menu (spec §2): 15 blends, 3 with free recipes and 12
-- behind the Blend Book. Original clean-room content — no smoothies, no fruit,
-- no copy from any reference sample.
--
-- A blend is: a title, one to three description paragraphs each carrying its own
-- EMPHASIS flag (the split-`Text`-runs adaptation — emphasis granularity is the
-- paragraph, and no rich-text engine is built), and its measured botanicals.
-- Caffeine, leaf mass and steep time are DERIVED from those measures by
-- CatalogService; nothing states them twice.
--
-- ORDERING IS NOT ALPHABETICAL on purpose: the list sorts through
-- I18nService's collation, so a menu that arrived pre-sorted would have hidden
-- a sort that never ran.

export type Measure = { botanicalId: string, value: number, unit: string }
export type Paragraph = { text: string, emphasis: boolean? }
export type Blend = {
	id: string,
	title: string,
	free: boolean?, -- free recipe (never gated behind the Blend Book)
	paragraphs: { Paragraph },
	measures: { Measure },
}

local W = "spring-water"

local list: { Blend } = {
	{
		id = "lantern-oolong",
		title = "Lantern Oolong",
		paragraphs = {
			{ text = "Roasted oolong with a thread of jasmine, poured for the walk home.", emphasis = true },
			{ text = "The leaf is rolled tight, so the first steep is quiet and the second one opens up." },
		},
		measures = {
			{ botanicalId = "oolong", value = 2, unit = "tsp" },
			{ botanicalId = "jasmine", value = 0.5, unit = "tsp" },
			{ botanicalId = W, value = 240, unit = "ml" },
		},
	},
	{
		id = "amber-harvest",
		title = "Amber Harvest",
		free = true,
		paragraphs = {
			{ text = "Our house black: broad Assam leaf, a curl of cinnamon, nothing hiding.", emphasis = true },
			{ text = "Brewed strong enough to take milk, honest enough not to need it." },
			{ text = "The autumn pour. We keep the kettle on it from first frost to thaw." },
		},
		measures = {
			{ botanicalId = "assam", value = 2, unit = "tsp" },
			{ botanicalId = "cinnamon", value = 0.5, unit = "tsp" },
			{ botanicalId = W, value = 250, unit = "ml" },
		},
	},
	{
		id = "mistral-mint",
		title = "Mistral Mint",
		free = true,
		paragraphs = {
			{ text = "Two mints and a stalk of lemongrass. It arrives cold on the tongue.", emphasis = true },
			{ text = "No caffeine at all, which is why it is the last pour of the evening." },
		},
		measures = {
			{ botanicalId = "peppermint", value = 1.5, unit = "tsp" },
			{ botanicalId = "spearmint", value = 1, unit = "tsp" },
			{ botanicalId = "lemongrass", value = 1, unit = "tsp" },
			{ botanicalId = W, value = 240, unit = "ml" },
		},
	},
	{
		id = "copper-chai",
		title = "Copper Chai",
		free = true,
		paragraphs = {
			{ text = "The counter chai: Assam under ginger, cardamom and clove.", emphasis = true },
			{ text = "Simmered rather than steeped, so the spice has somewhere to go." },
		},
		measures = {
			{ botanicalId = "assam", value = 2, unit = "tsp" },
			{ botanicalId = "ginger", value = 1, unit = "tsp" },
			{ botanicalId = "cardamom", value = 0.5, unit = "tsp" },
			{ botanicalId = "clove", value = 0.25, unit = "tsp" },
			{ botanicalId = W, value = 260, unit = "ml" },
		},
	},
	{
		id = "first-frost",
		title = "First Frost",
		paragraphs = {
			{ text = "Sencha and spearmint, poured over the cold morning.", emphasis = true },
			{ text = "Short steep. Longer and the leaf turns to grass." },
		},
		measures = {
			{ botanicalId = "sencha", value = 2, unit = "tsp" },
			{ botanicalId = "spearmint", value = 0.5, unit = "tsp" },
			{ botanicalId = W, value = 230, unit = "ml" },
		},
	},
	{
		id = "moonpetal",
		title = "Moonpetal",
		paragraphs = {
			{ text = "Chamomile and lavender, with just enough rosehip to keep it awake.", emphasis = true },
			{ text = "The pour we hand across the counter when someone says they cannot sleep." },
		},
		measures = {
			{ botanicalId = "chamomile", value = 2, unit = "tsp" },
			{ botanicalId = "lavender", value = 0.5, unit = "tsp" },
			{ botanicalId = "rosehip", value = 0.5, unit = "tsp" },
			{ botanicalId = W, value = 240, unit = "ml" },
		},
	},
	{
		id = "emberleaf",
		title = "Emberleaf",
		paragraphs = {
			{ text = "Assam, ginger and clove — the blend that argues back.", emphasis = true },
			{ text = "It is the strongest thing on the board and we do not apologise for it." },
		},
		measures = {
			{ botanicalId = "assam", value = 3, unit = "tsp" },
			{ botanicalId = "ginger", value = 1.5, unit = "tsp" },
			{ botanicalId = "clove", value = 0.5, unit = "tsp" },
			{ botanicalId = W, value = 250, unit = "ml" },
		},
	},
	{
		id = "quiet-meadow",
		title = "Quiet Meadow",
		paragraphs = {
			{ text = "Rooibos and honeybush, sweet without anything added.", emphasis = true },
		},
		measures = {
			{ botanicalId = "rooibos", value = 1.5, unit = "tsp" },
			{ botanicalId = "honeybush", value = 1.5, unit = "tsp" },
			{ botanicalId = W, value = 240, unit = "ml" },
		},
	},
	{
		id = "tidepool",
		title = "Tidepool",
		paragraphs = {
			{ text = "Sencha, lemongrass and a pinch of hibiscus for the colour.", emphasis = true },
			{ text = "Green and sharp. It reads the way a cold rock pool looks." },
		},
		measures = {
			{ botanicalId = "sencha", value = 2, unit = "tsp" },
			{ botanicalId = "lemongrass", value = 1, unit = "tsp" },
			{ botanicalId = "hibiscus", value = 0.5, unit = "tsp" },
			{ botanicalId = W, value = 240, unit = "ml" },
		},
	},
	{
		id = "velvet-smoke",
		title = "Velvet Smoke",
		paragraphs = {
			{ text = "Oolong roasted dark, licorice root underneath it.", emphasis = true },
			{ text = "Sweet at the back of the throat without a grain of sugar in the pot." },
		},
		measures = {
			{ botanicalId = "oolong", value = 2.5, unit = "tsp" },
			{ botanicalId = "licorice-root", value = 0.5, unit = "tsp" },
			{ botanicalId = W, value = 250, unit = "ml" },
		},
	},
	{
		id = "summit-sencha",
		title = "Summit Sencha",
		paragraphs = {
			{ text = "Straight sencha, measured heavy, steeped short.", emphasis = true },
			{ text = "Nothing else in the pot. Some mornings that is the whole recipe." },
		},
		measures = {
			{ botanicalId = "sencha", value = 3, unit = "tsp" },
			{ botanicalId = W, value = 220, unit = "ml" },
		},
	},
	{
		id = "bramble-hearth",
		title = "Bramble Hearth",
		paragraphs = {
			{ text = "Rosehip and hibiscus over rooibos, cut with cinnamon.", emphasis = true },
			{ text = "Deep red in the cup, which is most of why people order it." },
		},
		measures = {
			{ botanicalId = "rooibos", value = 2, unit = "tsp" },
			{ botanicalId = "rosehip", value = 1, unit = "tsp" },
			{ botanicalId = "hibiscus", value = 0.5, unit = "tsp" },
			{ botanicalId = "cinnamon", value = 0.25, unit = "tsp" },
			{ botanicalId = W, value = 250, unit = "ml" },
		},
	},
	{
		id = "golden-hour",
		title = "Golden Hour",
		paragraphs = {
			{ text = "Honeybush, jasmine and a thin slice of ginger.", emphasis = true },
			{ text = "It is the four-o'clock pour: warm, low, and not asking anything of you." },
		},
		measures = {
			{ botanicalId = "honeybush", value = 2, unit = "tsp" },
			{ botanicalId = "jasmine", value = 0.5, unit = "tsp" },
			{ botanicalId = "ginger", value = 0.25, unit = "tsp" },
			{ botanicalId = W, value = 240, unit = "ml" },
		},
	},
	{
		id = "nightporch",
		title = "Nightporch",
		paragraphs = {
			{ text = "Lavender, chamomile and peppermint, poured last.", emphasis = true },
			{ text = "Caffeine free by design, so the last cup of the day stays the last cup." },
		},
		measures = {
			{ botanicalId = "lavender", value = 1, unit = "tsp" },
			{ botanicalId = "chamomile", value = 1.5, unit = "tsp" },
			{ botanicalId = "peppermint", value = 0.5, unit = "tsp" },
			{ botanicalId = W, value = 240, unit = "ml" },
		},
	},
	{
		id = "cinder-chai",
		title = "Cinder Chai",
		paragraphs = {
			{ text = "Copper Chai's louder cousin: double the clove, half the water.", emphasis = true },
			{ text = "Meant to be cut with milk at the table. Taken neat it is a dare." },
		},
		measures = {
			{ botanicalId = "assam", value = 2.5, unit = "tsp" },
			{ botanicalId = "ginger", value = 1, unit = "tsp" },
			{ botanicalId = "cardamom", value = 0.5, unit = "tsp" },
			{ botanicalId = "clove", value = 0.5, unit = "tsp" },
			{ botanicalId = "cinnamon", value = 0.5, unit = "tsp" },
			{ botanicalId = W, value = 180, unit = "ml" },
		},
	},
}

local byId: { [string]: Blend } = {}
for _, b in list do
	byId[b.id] = b
end

return table.freeze({
	list = table.freeze(list),
	byId = table.freeze(byId),
})
