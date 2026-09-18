--!strict

local Diagnostics = require "../diagnostics"

export type Tier = {
	name: string,
	radius: number,
}

local function checkTiers(tiers: { Tier }, primitive: string)
	if #tiers == 0 then
		Diagnostics.raise("collection/no-tiers", ("%s was given an empty tier list"):format(primitive), {
			primitive = primitive,
			contract = "a spatial collection needs at least one representation tier",
			fix = 'pass tiers = { { name = "full", radius = 100 } }',
		})
	end
	local previous = -math.huge
	for index, tier in tiers do
		if type(tier.name) ~= "string" then
			Diagnostics.raise("collection/tier-unnamed", ("%s was given a tier with no name"):format(primitive), {
				primitive = primitive,
				index = index,
				expected = 'name = a string, e.g. "full"',
				actual = Diagnostics.describe(tier.name),
			})
		end
		if type(tier.radius) ~= "number" or tier.radius ~= tier.radius then
			Diagnostics.raise(
				"collection/tier-radius",
				("%s was given a tier with no usable radius"):format(primitive),
				{
					primitive = primitive,
					index = index,
					detail = ("tier %q"):format(tier.name),
					expected = "radius = a number",
					actual = Diagnostics.describe(tier.radius),
				}
			)
		end
		if tier.radius < previous then
			Diagnostics.raise("collection/tiers-unordered", ("%s was given tiers out of order"):format(primitive), {
				primitive = primitive,
				index = index,
				detail = ("tier %q has radius %s, inside the tier before it"):format(tier.name, tostring(tier.radius)),
				contract = "tiers are listed nearest first, by ascending radius",
				fix = "order the list so each radius is at least the one before it",
			})
		end
		previous = tier.radius
	end
end

local function tierFor(distance: number, current: number?, tiers: { Tier }, hysteresis: number, scale: number): number?
	for index = 1, #tiers do
		local radius = tiers[index].radius * scale

		if current ~= nil and current <= index then
			radius += hysteresis
		end
		if distance <= radius then
			return index
		end
	end
	return nil
end

local function pinnedTier(
	distance: number,
	current: number?,
	tiers: { Tier },
	hysteresis: number,
	scale: number
): number
	local tier = tierFor(distance, current, tiers, hysteresis, scale)
	return if tier ~= nil then tier else #tiers
end

return {
	checkTiers = checkTiers,
	tierFor = tierFor,
	pinnedTier = pinnedTier,
}
