--!strict

export type Currency = "Coins" | "Gems"

export type Category = "Motors" | "Boosts" | "Wheels" | "Cosmetics"

export type Item = {
	id: string,
	name: string,
	category: Category,
	price: number,
	currency: Currency,
	description: string,
}

local items: { Item } = {
	{
		id = "starter_motor",
		name = "Starter Motor",
		category = "Motors",
		price = 50,
		currency = "Coins",
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "sport_motor",
		name = "Sport Motor",
		category = "Motors",
		price = 250,
		currency = "Coins",
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "crystal_motor",
		name = "Crystal Motor",
		category = "Motors",
		price = 75,
		currency = "Gems",
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "turbo_kit",
		name = "Turbo Kit",
		category = "Boosts",
		price = 400,
		currency = "Coins",
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "lucky_charm",
		name = "Lucky Charm",
		category = "Boosts",
		price = 10,
		currency = "Gems",
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "amber_wheels",
		name = "Amber Wheels",
		category = "Wheels",
		price = 25,
		currency = "Gems",
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "road_wheels",
		name = "Road Wheels",
		category = "Wheels",
		price = 150,
		currency = "Coins",
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "gold_paint",
		name = "Gold Paint",
		category = "Cosmetics",
		price = 120,
		currency = "Gems",
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
	{
		id = "rainbow_trail",
		name = "Rainbow Trail",
		category = "Cosmetics",
		price = 900,
		currency = "Coins",
		description = "A tested racing part. Fit it in the garage before the next race.",
	},
}

local byId: { [string]: Item } = {}
for _, item in items do
	byId[item.id] = item
end

local categories: { Category } = { "Motors", "Boosts", "Wheels", "Cosmetics" }

return {
	items = items,
	byId = byId,
	categories = categories,
}
