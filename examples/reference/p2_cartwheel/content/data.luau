--!strict

local art = require("./art")

local data = {}

data.ATTRIBUTES = table.freeze({ "spark", "bloom", "frost", "ember", "murk", "zing" })

local function vec(a: number, b: number, c: number, d: number, e: number, f: number)
	return table.freeze({ a, b, c, d, e, f })
end

local function hue(r: number, g: number, b: number)
	return table.freeze({ r = r, g = g, b = b })
end
data.hue = hue

local function ingredient(id: string, name: string, family: string, group: string?, attrs: any)
	return table.freeze({ id = id, name = name, family = family, group = group, attrs = attrs })
end

data.bases = table.freeze({
	ingredient("springwater", "Springwater", "base", nil, vec(1, 2, 3, 0, 0, 1)),
	ingredient("hearthmilk", "Hearthmilk", "base", nil, vec(0, 3, 0, 2, 1, 0)),
	ingredient("emberoil", "Emberoil", "base", nil, vec(2, 0, -1, 5, 0, 1)),
	ingredient("duskbrine", "Duskbrine", "base", nil, vec(0, -1, 2, 0, 4, 1)),
	ingredient("cloudsyrup", "Cloudsyrup", "base", nil, vec(1, 4, 1, 0, 0, 2)),
	ingredient("ironwell", "Ironwell", "base", nil, vec(3, 0, 2, 1, 1, 0)),
	ingredient("fernmash", "Fernmash", "base", nil, vec(0, 5, 0, 0, 2, 1)),
})

data.essences = table.freeze({
	ingredient("rosewisp", "Rosewisp", "essence", nil, vec(0, 3, 0, 1, 0, 1)),
	ingredient("cindershade", "Cindershade", "essence", nil, vec(1, 0, 0, 3, 2, 0)),
	ingredient("palebloom", "Palebloom", "essence", nil, vec(0, 2, 3, 0, 0, 0)),
	ingredient("deepsalt", "Deepsalt", "essence", nil, vec(2, 0, 1, 0, 3, 0)),
	ingredient("thornhoney", "Thornhoney", "essence", nil, vec(0, 1, 0, 2, 1, 3)),
	ingredient("skyveil", "Skyveil", "essence", nil, vec(3, 1, 2, 0, 0, 1)),
	ingredient("gullsmoke", "Gullsmoke", "essence", nil, vec(1, 0, 0, 1, 4, 0)),
})

local GARNISH_ROOTS = { "Rosewisp", "Cindershade", "Palebloom", "Deepsalt", "Thornhoney", "Skyveil", "Gullsmoke" }
local GARNISH_FAMILIES = { "Dust", "Ribbon", "Swirl" }

local garnishes: { any } = {
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

function data.ingredientById(id: string?): any?
	if id == nil or id == "" then
		return nil
	end
	for _, list in { data.bases, data.essences, data.garnishes } do
		for _, entry in list :: any do
			if entry.id == id then
				return entry
			end
		end
	end
	return nil
end

local POTION_ROWS = {
	{ "emberdrop", "Emberdrop", "emberoil", "cindershade", "dust-cindershade", 0.86, 0.34, 0.22 },
	{ "moonwell", "Moonwell", "springwater", "skyveil", "swirl-skyveil", 0.42, 0.55, 0.88 },
	{ "thistledown", "Thistledown", "fernmash", "palebloom", "ribbon-palebloom", 0.62, 0.78, 0.48 },
	{ "coppertonic", "Coppertonic", "ironwell", "deepsalt", "ribbon-deepsalt", 0.82, 0.58, 0.30 },
	{ "gullsbreath", "Gullsbreath", "duskbrine", "gullsmoke", "saltrim", 0.55, 0.60, 0.62 },
	{ "nightplum", "Nightplum", "duskbrine", "cindershade", "swirl-cindershade", 0.46, 0.30, 0.58 },
	{ "frostbloom", "Frostbloom", "springwater", "palebloom", "dust-palebloom", 0.60, 0.82, 0.90 },
	{ "marrowmint", "Marrowmint", "hearthmilk", "palebloom", "ribbon-skyveil", 0.52, 0.84, 0.66 },
	{ "sunwake", "Sunwake", "cloudsyrup", "thornhoney", "swirl-thornhoney", 0.94, 0.76, 0.34 },
	{ "rosewispcordial", "Rosewisp Cordial", "cloudsyrup", "rosewisp", "ribbon-rosewisp", 0.90, 0.52, 0.62 },
	{ "deepcurrent", "Deepcurrent", "ironwell", "gullsmoke", "swirl-gullsmoke", 0.30, 0.48, 0.66 },
	{ "bramblefizz", "Bramblefizz", "fernmash", "thornhoney", "corkcurl", 0.70, 0.66, 0.28 },
	{ "hollowlight", "Hollowlight", "springwater", nil, "dust-skyveil", 0.74, 0.80, 0.84 },
	{ "saltglass", "Saltglass", "duskbrine", "deepsalt", "saltrim", 0.58, 0.68, 0.74 },
	{ "wintergleam", "Wintergleam", "springwater", "skyveil", "dust-palebloom", 0.66, 0.86, 0.94 },
	{ "ashroot", "Ashroot", "emberoil", "gullsmoke", "swirl-gullsmoke", 0.44, 0.36, 0.32 },
	{ "quiverleaf", "Quiverleaf", "fernmash", "rosewisp", "copperpin", 0.68, 0.74, 0.44 },
}

local potions: { any } = {}
for index, row in POTION_ROWS do
	table.insert(
		potions,
		table.freeze({
			id = row[1] :: string,
			name = row[2] :: string,
			base = row[3] :: string,
			essence = row[4] :: string?,
			garnish = row[5] :: string?,
			hue = hue(row[6] :: number, row[7] :: number, row[8] :: number),
			mark = art.markFor(index),
			index = index,
		})
	)
end
data.potions = table.freeze(potions)

function data.potionById(id: string): any?
	for _, potion in data.potions :: any do
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

data.baseHues = table.freeze({
	springwater = hue(0.56, 0.78, 0.92),
	hearthmilk = hue(0.94, 0.88, 0.76),
	emberoil = hue(0.88, 0.42, 0.24),
	duskbrine = hue(0.44, 0.40, 0.60),
	cloudsyrup = hue(0.92, 0.80, 0.52),
	ironwell = hue(0.58, 0.62, 0.68),
	fernmash = hue(0.52, 0.76, 0.48),
})

function data.baseHueFor(baseId: string?): any
	local found = if baseId == nil then nil else (data.baseHues :: any)[baseId]
	return found or (data.baseHues :: any).springwater
end

data.plazas = table.freeze({
	table.freeze({ id = "gullsgate", name = "Gullsgate Quay", seed = 1, weight = 0.5, pitch = "Lantern Steps" }),
	table.freeze({ id = "willowmere", name = "Willowmere Market", seed = 2, weight = 1.0, pitch = "The Long Awning" }),
	table.freeze({ id = "emberfall", name = "Emberfall Rows", seed = 3, weight = 0.75, pitch = "Kiln Corner" }),
})

function data.plazaById(id: string): any?
	for _, plaza in data.plazas :: any do
		if plaza.id == id then
			return plaza
		end
	end
	return nil
end

data.chatterTags = table.freeze({
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
})

data.chatterPosts = table.freeze({
	table.freeze({ id = "c1", who = "Halva of the Quay", potion = "moonwell", minutes = 4, tags = { 1, 4 } }),
	table.freeze({ id = "c2", who = "Bell the Cooper", potion = "coppertonic", minutes = 21, tags = { 5, 13 } }),
	table.freeze({ id = "c3", who = "Marrow", potion = "marrowmint", minutes = 55, tags = { 2, 8 } }),
	table.freeze({ id = "c4", who = "Fen of Emberfall", potion = "emberdrop", minutes = 96, tags = { 10, 3 } }),
	table.freeze({ id = "c5", who = "Quill", potion = "thistledown", minutes = 180, tags = { 11, 12 } }),
	table.freeze({ id = "c6", who = "Oster", potion = "saltglass", minutes = 300, tags = { 6, 16 } }),
})

data.chatterBonusPosts = table.freeze({
	table.freeze({ id = "b1", who = "The Cellarer", potion = "nightplum", minutes = 12, tags = { 7, 14 } }),
	table.freeze({ id = "b2", who = "Wren", potion = "frostbloom", minutes = 40, tags = { 8, 15 } }),
	table.freeze({ id = "b3", who = "Piper of Willowmere", potion = "sunwake", minutes = 132, tags = { 9, 1 } }),
})

data.chatterTiers = table.freeze({
	table.freeze({ id = "monthly", credits = 9, save = nil }),
	table.freeze({ id = "yearly", credits = 79, save = 27 }),
})

data.fullLedgerCredits = 79

data.takenGuildNames = table.freeze({ "gullsgate", "cartwheel", "willowmere" })

return table.freeze(data)
