--!strict

export type Item = { kind: string, rotation: number, palette: string }
export type Layout = { schema: string, revision: number, slots: { [string]: Item } }
local model = {}
model.catalog = {
	{ id = "sofa", name = "Leather loveseat", category = "Comfort" },
	{ id = "table", name = "Oak table", category = "Living" },
	{ id = "lamp", name = "Reading lamp", category = "Lighting" },
	{ id = "plant", name = "Monstera", category = "Greenery" },
	{ id = "shelf", name = "Story shelf", category = "Living" },
	{ id = "rug", name = "Sunrise rug", category = "Comfort" },
}
model.palettes = { "sage", "clay", "cream", "midnight" }
model.SLOTS = 6
function model.empty(): Layout
	return { schema = "facet-home/1", revision = 0, slots = {} }
end
function model.validate(value: any): Layout
	assert(type(value) == "table" and value.schema == "facet-home/1", "Unsupported home layout")
	assert(type(value.revision) == "number" and value.revision % 1 == 0 and value.revision >= 0, "Invalid revision")
	assert(type(value.slots) == "table", "Invalid room slots")
	local clean = model.empty()
	clean.revision = value.revision
	for key, item in value.slots do
		local slot = tonumber(key)
		assert(
			type(key) == "string"
				and slot
				and tostring(slot) == key
				and slot % 1 == 0
				and slot >= 1
				and slot <= model.SLOTS,
			"Invalid room slot"
		)
		assert(type(item) == "table", "Invalid furniture")
		local known = false
		for _, entry in model.catalog do
			known = known or entry.id == item.kind
		end
		assert(known, "Unknown furniture")
		assert(
			type(item.rotation) == "number" and item.rotation % 1 == 0 and item.rotation >= 0 and item.rotation < 4,
			"Invalid rotation"
		)
		assert(table.find(model.palettes, item.palette), "Unknown palette")
		clean.slots[key] = { kind = item.kind, rotation = item.rotation, palette = item.palette }
	end
	return clean
end
function model.edit(value: Layout, operation: string, slot: number, kind: string?, palette: string?): Layout
	local nextValue = model.validate(value)
	assert(slot % 1 == 0 and slot >= 1 and slot <= model.SLOTS, "Choose a room slot")
	local key = tostring(slot)
	if operation == "place" then
		nextValue.slots[key] = { kind = assert(kind), rotation = 0, palette = palette or "sage" }
	elseif operation == "rotate" then
		local item = assert(nextValue.slots[key], "This slot is empty")
		item.rotation = (item.rotation + 1) % 4
	elseif operation == "paint" then
		assert(nextValue.slots[key], "This slot is empty").palette = assert(palette)
	elseif operation == "remove" then
		nextValue.slots[key] = nil
	else
		error("Unknown room operation")
	end
	return model.validate(nextValue)
end
function model.replace(previous: any, expectedRevision: number, draft: Layout): Layout
	local old = if previous then model.validate(previous) else model.empty()
	assert(old.revision == expectedRevision, "Home changed in another session")
	local nextValue = model.validate(draft)
	nextValue.revision = old.revision + 1
	return nextValue
end
function model.count(value: Layout): number
	local count = 0
	for _ in value.slots do
		count += 1
	end
	return count
end
function model.matches(item: { id: string, name: string, category: string }, query: string): boolean
	return string.find(string.lower(item.id .. " " .. item.name .. " " .. item.category), string.lower(query), 1, true)
		~= nil
end
function model.puzzleNext(score: number, chosen: number): (number, boolean)
	assert(score >= 0 and score <= 4 and score % 1 == 0, "Invalid activity progress")
	assert(chosen >= 1 and chosen <= 4 and chosen % 1 == 0, "Invalid activity tile")
	if score == 4 then
		return 4, true
	end
	local sequence = { 2, 4, 1, 3 }
	return if chosen == sequence[score + 1] then score + 1 else 0, chosen == sequence[score + 1]
end
return model
