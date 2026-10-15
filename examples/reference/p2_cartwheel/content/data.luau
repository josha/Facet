--!strict

local art = require("./art")

export type Hue = { r: number, g: number, b: number }
export type Ingredient = { id: string, name: string, family: string, group: string?, attrs: { number } }
export type Potion = {
	id: string,
	name: string,
	base: string,
	essence: string?,
	garnish: string?,
	hue: Hue,
	mark: art.Mark,
	index: number,
}
export type Plaza = { id: string, name: string, seed: number, weight: number, pitch: string }
export type Post = { id: string, who: string, potion: string, minutes: number, tags: { number } }
export type Tier = { id: string, credits: number, save: number? }

local data = {}

data.ATTRIBUTES = table.freeze({ "spark", "bloom", "frost", "ember", "murk", "zing" })

local function vec(a: number, b: number, c: number, d: number, e: number, f: number): { number }
	return table.freeze({ a, b, c, d, e, f })
end

local function hue(r: number, g: number, b: number): Hue
	return table.freeze({ r = r, g = g, b = b })
end
data.hue = hue

local function ingredient(id: string, name: string, family: string, group: string?, attrs: { number }): Ingredient
	return table.freeze({ id = id, name = name, family = family, group = group, attrs = attrs })
end

local BASES: { Ingredient } = {
	ingredient("springwater", "Springwater", "base", nil, vec(1, 2, 3, 0, 0, 1)),
	ingredient("hearthmilk", "Hearthmilk", "base", nil, vec(0, 3, 0, 2, 1, 0)),
	ingredient("emberoil", "Emberoil", "base", nil, vec(2, 0, -1, 5, 0, 1)),
	ingredient("duskbrine", "Duskbrine", "base", nil, vec(0, -1, 2, 0, 4, 1)),
	ingredient("cloudsyrup", "Cloudsyrup", "base", nil, vec(1, 4, 1, 0, 0, 2)),
	ingredient("ironwell", "Ironwell", "base", nil, vec(3, 0, 2, 1, 1, 0)),
	ingredient("fernmash", "Fernmash", "base", nil, vec(0, 5, 0, 0, 2, 1)),
}
data.bases = table.freeze(BASES)

local ESSENCES: { Ingredient } = {
	ingredient("rosewisp", "Rosewisp", "essence", nil, vec(0, 3, 0, 1, 0, 1)),
	ingredient("cindershade", "Cindershade", "essence", nil, vec(1, 0, 0, 3, 2, 0)),
	ingredient("palebloom", "Palebloom", "essence", nil, vec(0, 2, 3, 0, 0, 0)),
	ingredient("deepsalt", "Deepsalt", "essence", nil, vec(2, 0, 1, 0, 3, 0)),
	ingredient("thornhoney", "Thornhoney", "essence", nil, vec(0, 1, 0, 2, 1, 3)),
	ingredient("skyveil", "Skyveil", "essence", nil, vec(3, 1, 2, 0, 0, 1)),
	ingredient("gullsmoke", "Gullsmoke", "essence", nil, vec(1, 0, 0, 1, 4, 0)),
}
data.essences = table.freeze(ESSENCES)

local GARNISH_ROOTS = { "Rosewisp", "Cindershade", "Palebloom", "Deepsalt", "Thornhoney", "Skyveil", "Gullsmoke" }
local GARNISH_FAMILIES = { "Dust", "Ribbon", "Swirl" }

local garnishes: { Ingredient } = {
	ingredient("corkcurl", "Cork Curl", "garnish", "Simple", vec(0, 0, 0, 0, 0, 1)),
	ingredient("saltrim", "Salt Rim", "garnish", "Simple", vec(1, 0, 0, 0, 1, 0)),
	ingredient("copperpin", "Copper Pin", "garnish", "Simple", vec(0, 0, 1, 1, 0, 0)),
}
for familyIndex, family in GARNISH_FAMILIES do
	for rootIndex, root in GARNISH_ROOTS do
		local weight = rootIndex
		local attrs = if familyIndex == 1
			then vec(weight % 3, 0, 0, 1 + weight % 2, 0, 0)
			elseif familyIndex == 2 then vec(0, 1 + weight % 3, weight % 2, 0, 0, 1)
			else vec(0, 0, 1 + weight % 2, 0, weight % 3, 1)
		table.insert(
			garnishes,
			ingredient(
				string.lower(family) .. "-" .. string.lower(root),
				family .. " · " .. root,
				"garnish",
				family,
				attrs
			)
		)
	end
end
data.garnishes = table.freeze(garnishes)

function data.ingredientById(id: string?): Ingredient?
	if id == nil or id == "" then
		return nil
	end
	local lists: { { Ingredient } } = { data.bases, data.essences, data.garnishes }
	for _, list in lists do
		for _, entry in list do
			if entry.id == id then
				return entry
			end
		end
	end
	return nil
end

type PotionRow = {
	id: string,
	name: string,
	base: string,
	essence: string?,
	garnish: string?,
	r: number,
	g: number,
	b: number,
}
local POTION_ROWS: { PotionRow } = {
	{
		id = "emberdrop",
		name = "Emberdrop",
		base = "emberoil",
		essence = "cindershade",
		garnish = "dust-cindershade",
		r = 0.86,
		g = 0.34,
		b = 0.22,
	},
	{
		id = "moonwell",
		name = "Moonwell",
		base = "springwater",
		essence = "skyveil",
		garnish = "swirl-skyveil",
		r = 0.42,
		g = 0.55,
		b = 0.88,
	},
	{
		id = "thistledown",
		name = "Thistledown",
		base = "fernmash",
		essence = "palebloom",
		garnish = "ribbon-palebloom",
		r = 0.62,
		g = 0.78,
		b = 0.48,
	},
	{
		id = "coppertonic",
		name = "Coppertonic",
		base = "ironwell",
		essence = "deepsalt",
		garnish = "ribbon-deepsalt",
		r = 0.82,
		g = 0.58,
		b = 0.30,
	},
	{
		id = "gullsbreath",
		name = "Gullsbreath",
		base = "duskbrine",
		essence = "gullsmoke",
		garnish = "saltrim",
		r = 0.55,
		g = 0.60,
		b = 0.62,
	},
	{
		id = "nightplum",
		name = "Nightplum",
		base = "duskbrine",
		essence = "cindershade",
		garnish = "swirl-cindershade",
		r = 0.46,
		g = 0.30,
		b = 0.58,
	},
	{
		id = "frostbloom",
		name = "Frostbloom",
		base = "springwater",
		essence = "palebloom",
		garnish = "dust-palebloom",
		r = 0.60,
		g = 0.82,
		b = 0.90,
	},
	{
		id = "marrowmint",
		name = "Marrowmint",
		base = "hearthmilk",
		essence = "palebloom",
		garnish = "ribbon-skyveil",
		r = 0.52,
		g = 0.84,
		b = 0.66,
	},
	{
		id = "sunwake",
		name = "Sunwake",
		base = "cloudsyrup",
		essence = "thornhoney",
		garnish = "swirl-thornhoney",
		r = 0.94,
		g = 0.76,
		b = 0.34,
	},
	{
		id = "rosewispcordial",
		name = "Rosewisp Cordial",
		base = "cloudsyrup",
		essence = "rosewisp",
		garnish = "ribbon-rosewisp",
		r = 0.90,
		g = 0.52,
		b = 0.62,
	},
	{
		id = "deepcurrent",
		name = "Deepcurrent",
		base = "ironwell",
		essence = "gullsmoke",
		garnish = "swirl-gullsmoke",
		r = 0.30,
		g = 0.48,
		b = 0.66,
	},
	{
		id = "bramblefizz",
		name = "Bramblefizz",
		base = "fernmash",
		essence = "thornhoney",
		garnish = "corkcurl",
		r = 0.70,
		g = 0.66,
		b = 0.28,
	},
	{
		id = "hollowlight",
		name = "Hollowlight",
		base = "springwater",
		essence = nil,
		garnish = "dust-skyveil",
		r = 0.74,
		g = 0.80,
		b = 0.84,
	},
	{
		id = "saltglass",
		name = "Saltglass",
		base = "duskbrine",
		essence = "deepsalt",
		garnish = "saltrim",
		r = 0.58,
		g = 0.68,
		b = 0.74,
	},
	{
		id = "wintergleam",
		name = "Wintergleam",
		base = "springwater",
		essence = "skyveil",
		garnish = "dust-palebloom",
		r = 0.66,
		g = 0.86,
		b = 0.94,
	},
	{
		id = "ashroot",
		name = "Ashroot",
		base = "emberoil",
		essence = "gullsmoke",
		garnish = "swirl-gullsmoke",
		r = 0.44,
		g = 0.36,
		b = 0.32,
	},
	{
		id = "quiverleaf",
		name = "Quiverleaf",
		base = "fernmash",
		essence = "rosewisp",
		garnish = "copperpin",
		r = 0.68,
		g = 0.74,
		b = 0.44,
	},
}

local potions: { Potion } = {}
for index, row in POTION_ROWS do
	table.insert(
		potions,
		table.freeze({
			id = row.id,
			name = row.name,
			base = row.base,
			essence = row.essence,
			garnish = row.garnish,
			hue = hue(row.r, row.g, row.b),
			mark = art.markFor(index),
			index = index,
		})
	)
end
data.potions = table.freeze(potions)

function data.potionById(id: string): Potion?
	for _, potion in data.potions do
		if potion.id == id then
			return potion
		end
	end
	return nil
end

function data.attributesOf(baseId: string?, essenceId: string?, garnishId: string?): { number }
	local out = { 0, 0, 0, 0, 0, 0 }
	for _, id in { baseId, essenceId, garnishId } do
		local entry = data.ingredientById(id)
		if entry ~= nil then
			for axis = 1, 6 do
				out[axis] += entry.attrs[axis]
			end
		end
	end
	return out
end

function data.strongestAxis(attrs: { number }): number
	local best, bestValue = 1, attrs[1]
	for axis = 2, 6 do
		if attrs[axis] > bestValue then
			best, bestValue = axis, attrs[axis]
		end
	end
	return best
end

local BASE_HUES: { [string]: Hue } = {
	springwater = hue(0.56, 0.78, 0.92),
	hearthmilk = hue(0.94, 0.88, 0.76),
	emberoil = hue(0.88, 0.42, 0.24),
	duskbrine = hue(0.44, 0.40, 0.60),
	cloudsyrup = hue(0.92, 0.80, 0.52),
	ironwell = hue(0.58, 0.62, 0.68),
	fernmash = hue(0.52, 0.76, 0.48),
}
data.baseHues = table.freeze(BASE_HUES)

function data.baseHueFor(baseId: string?): Hue
	local found = if baseId == nil then nil else BASE_HUES[baseId]
	return found or BASE_HUES.springwater
end

local PLAZAS: { Plaza } = {
	table.freeze({ id = "gullsgate", name = "Gullsgate Quay", seed = 1, weight = 0.5, pitch = "Lantern Steps" }),
	table.freeze({ id = "willowmere", name = "Willowmere Market", seed = 2, weight = 1.0, pitch = "The Long Awning" }),
	table.freeze({ id = "emberfall", name = "Emberfall Rows", seed = 3, weight = 0.75, pitch = "Kiln Corner" }),
}
data.plazas = table.freeze(PLAZAS)

function data.plazaById(id: string): Plaza?
	for _, plaza in data.plazas do
		if plaza.id == id then
			return plaza
		end
	end
	return nil
end

local CHATTER_TAGS: { string } = {
	"Fresh Cork",
	"No-Sting",
	"Potion vs Philtre",
	"Lantern Hours",
	"Bottle Deposit",
	"Quay Queue",
	"Second Pour",
	"Cold Steep",
	"Market Day",
	"Kiln Corner",
	"Ribbon Talk",
	"Dust Ratio",
	"Cork Pop",
	"Sweet Set",
	"Awning Shade",
	"Bring a Flask",
}
data.chatterTags = table.freeze(CHATTER_TAGS)

local CHATTER_POSTS: { Post } = {
	table.freeze({ id = "c1", who = "Halva of the Quay", potion = "moonwell", minutes = 4, tags = { 1, 4 } }),
	table.freeze({ id = "c2", who = "Bell the Cooper", potion = "coppertonic", minutes = 21, tags = { 5, 13 } }),
	table.freeze({ id = "c3", who = "Marrow", potion = "marrowmint", minutes = 55, tags = { 2, 8 } }),
	table.freeze({ id = "c4", who = "Fen of Emberfall", potion = "emberdrop", minutes = 96, tags = { 10, 3 } }),
	table.freeze({ id = "c5", who = "Quill", potion = "thistledown", minutes = 180, tags = { 11, 12 } }),
	table.freeze({ id = "c6", who = "Oster", potion = "saltglass", minutes = 300, tags = { 6, 16 } }),
}
data.chatterPosts = table.freeze(CHATTER_POSTS)

local BONUS_POSTS: { Post } = {
	table.freeze({ id = "b1", who = "The Cellarer", potion = "nightplum", minutes = 12, tags = { 7, 14 } }),
	table.freeze({ id = "b2", who = "Wren", potion = "frostbloom", minutes = 40, tags = { 8, 15 } }),
	table.freeze({ id = "b3", who = "Piper of Willowmere", potion = "sunwake", minutes = 132, tags = { 9, 1 } }),
}
data.chatterBonusPosts = table.freeze(BONUS_POSTS)

local TIERS: { Tier } = {
	table.freeze({ id = "monthly", credits = 9 }),
	table.freeze({ id = "yearly", credits = 79, save = 27 }),
}
data.chatterTiers = table.freeze(TIERS)

data.fullLedgerCredits = 79

local TAKEN: { string } = { "gullsgate", "cartwheel", "willowmere" }
data.takenGuildNames = table.freeze(TAKEN)

return table.freeze(data)
