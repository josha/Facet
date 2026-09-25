--!strict

local catalog = {}
local titles = {
	"Afterlight",
	"Circuit",
	"Terrarium",
	"Deepwater",
	"Skyline",
	"Outpost",
	"Orbit",
	"Wildwood",
	"Drift",
	"Summit",
	"Neon Harbor",
	"Daybreak",
}
local genres = { "Adventure", "Racing", "Building", "Exploration", "Roleplay", "Survival" }
local descriptions = {
	"Find a path across the rooftops as the city lights come on.",
	"Learn the racing line, chase a clean lap, and race your friends.",
	"Grow a small forest into a world of your own.",
	"Follow the lights beneath the surface and explore the islands above.",
	"Meet above the city and find your next rooftop route.",
	"Build a base, gather supplies, and plan your next expedition.",
}
local colors = {
	{ r = 0.22, g = 0.48, b = 0.42 },
	{ r = 0.55, g = 0.28, b = 0.35 },
	{ r = 0.33, g = 0.43, b = 0.23 },
	{ r = 0.18, g = 0.36, b = 0.53 },
	{ r = 0.41, g = 0.30, b = 0.60 },
	{ r = 0.54, g = 0.38, b = 0.20 },
}
local CREATOR_HEADSHOTS = { 1, 156, 261 }
local FRIENDS = {
	{ id = "ada", name = "Ada Quill", presence = "online" },
	{ id = "bo", name = "Bo Lane", presence = "online" },
	{ id = "noel", name = "Noel Park", presence = "away" },
	{ id = "ivy", name = "Ivy Moss", presence = "online" },
	{ id = "kai", name = "Kai North", presence = "busy" },
}
local function friendsFor(index: number): { any }
	local list = {}
	for offset = 0, (index * 7) % 6 - 1 do
		table.insert(list, FRIENDS[(index + offset) % #FRIENDS + 1])
	end
	return list
end
local studios = {
	"Lumen Works",
	"Northbridge Games",
	"Hollow Peak",
	"Driftwood Interactive",
	"Paper Compass",
	"Ember & Co.",
}
function catalog.new(Compose: any)
	local items = Compose.cell({})
	local pending, disposed = true, false
	local function step()
		if not pending or disposed then
			return
		end
		pending = false
		items:update(function(current)
			local nextItems = table.clone(current)
			for index = #current + 1, #current + 36 do
				local variant = math.floor((index - 1) / #titles)
				table.insert(nextItems, {
					id = tostring(index),
					index = index,
					title = titles[(index - 1) % #titles + 1]
						.. (if variant == 0 then "" else `: Chapter {variant + 1}`),
					genre = genres[(index - 1) % #genres + 1],
					description = descriptions[(index - 1) % #descriptions + 1],
					color = colors[(index - 1) % #colors + 1],
					players = `{(index * 137) % 24 + 1}.{index % 10}K playing`,
					rating = `{92 + index % 8}%`,
					percent = 92 + index % 8,
					stars = 4 + index % 2,
					playing = (index * 137) % 24 + 1 + (index % 10) / 10,
					creator = studios[(index - 1) % #studios + 1],
					friends = friendsFor(index),

					creatorImage = `rbxthumb://type=AvatarHeadShot&id={CREATOR_HEADSHOTS[(index - 1) % #CREATOR_HEADSHOTS + 1]}&w=48&h=48`,
				})
			end
			return nextItems
		end)
	end
	step()
	return {
		items = items,
		seen = function(index)
			if index >= #items:peek() - 12 then
				pending = true
			end
		end,
		step = step,
		dispose = function()
			disposed = true
		end,
	}
end
catalog.genres = table.freeze(table.clone(genres))
return catalog
