--!strict

export type Slot = "Motor" | "Body" | "Wheels" | "Trail"

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type Definition = {
	id: string,
	name: string,
	slot: Slot,
	rarity: Rarity,
	power: number,
	description: string,
}

local definitions: { Definition } = {
	{
		id = "starter_motor",
		name = "Starter Motor",
		slot = "Motor",
		rarity = "Common",
		power = 5,
		description = "A reliable motor for new racers.",
	},
	{
		id = "frost_motor",
		name = "Frost Motor",
		slot = "Motor",
		rarity = "Rare",
		power = 42,
		description = "A stable motor for cold tracks.",
	},
	{
		id = "ember_motor",
		name = "Ember Motor",
		slot = "Motor",
		rarity = "Epic",
		power = 77,
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "night_motor",
		name = "Night Motor",
		slot = "Motor",
		rarity = "Legendary",
		power = 128,
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "light_body",
		name = "Light Body",
		slot = "Body",
		rarity = "Common",
		power = 8,
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "steel_body",
		name = "Steel Body",
		slot = "Body",
		rarity = "Rare",
		power = 36,
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "storm_body",
		name = "Storm Body",
		slot = "Body",
		rarity = "Epic",
		power = 61,
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "city_wheels",
		name = "City Wheels",
		slot = "Wheels",
		rarity = "Common",
		power = 3,
		description = "Road wheels for daily hub runs.",
	},
	{
		id = "snow_wheels",
		name = "Snow Wheels",
		slot = "Wheels",
		rarity = "Rare",
		power = 19,
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "flame_wheels",
		name = "Flame Wheels",
		slot = "Wheels",
		rarity = "Legendary",
		power = 95,
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "spark_trail",
		name = "Spark Trail",
		slot = "Trail",
		rarity = "Common",
		power = 1,
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "galaxy_trail",
		name = "Galaxy Trail",
		slot = "Trail",
		rarity = "Epic",
		power = 4,
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "golden_trail",
		name = "Golden Trail",
		slot = "Trail",
		rarity = "Legendary",
		power = 6,
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
}

for _, item in require(script.Parent.Catalog).items do
	if item.id ~= "starter_motor" then
		local definition: Definition = {
			id = item.id,
			name = item.name,
			slot = if item.category == "Motors" or item.category == "Boosts"
				then "Motor"
				elseif item.category == "Wheels" then "Wheels"
				else "Trail",
			rarity = "Rare",
			power = item.price,
			description = item.description,
		}
		table.insert(definitions, definition)
	end
end
local byId: { [string]: Definition } = {}
for _, definition in definitions do
	byId[definition.id] = definition
end

local slots: { Slot } = { "Motor", "Body", "Wheels", "Trail" }

return {
	definitions = definitions,
	byId = byId,
	slots = slots,
}
