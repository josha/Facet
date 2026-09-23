--!strict

local dataset = {}

dataset.VERSION = "perf-dataset/1"

local function newRng(seed: number)
	local state = bit32.band(math.floor(seed), 0xffffffff)
	if state == 0 then
		state = 0x9e3779b9
	end
	local rng = {}
	function rng.next(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.band(state, 0xffffffff)
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		state = bit32.band(state, 0xffffffff)
		return state
	end

	function rng.int(lo: number, hi: number): number
		return lo + rng.next() % (hi - lo + 1)
	end

	function rng.unit(): number
		return rng.next() / 4294967296
	end
	function rng.pick<T>(list: { T }): T
		return list[rng.int(1, #list)]
	end
	return rng
end

dataset.newRng = newRng

local FIRST = {
	"Ash",
	"Bram",
	"Cleo",
	"Dex",
	"Enid",
	"Fen",
	"Gil",
	"Hana",
	"Ivo",
	"Juno",
	"Kit",
	"Lark",
	"Mio",
	"Nell",
	"Osk",
	"Pim",
	"Quill",
	"Rue",
	"Sol",
	"Tam",
}
local LAST = {
	"Ashdown",
	"Brightwater",
	"Cinderfell",
	"Dunmore",
	"Eastvale",
	"Foxglove",
	"Grimsby",
	"Hallowell",
	"Ironwood",
	"Jessup",
	"Kestrel",
	"Lindqvist",
	"Marchetti",
	"Nakamura",
	"Oyelaran",
	"Pemberton",
	"Quintero",
	"Rasmussen",
	"Stroud",
	"Thackeray",
}
local STATUS = {
	"Qualified",
	"On the grid",
	"In the pits",
	"Practice lap",
	"Warming up",
	"Cooldown",
	"Retired",
	"Waiting",
}
local TEAM = { "Ember", "Frost", "Dune", "Tidal", "Cobalt", "Verdant", "Ochre", "Slate" }

local IMAGE_IDS = { 1, 2, 5, 8, 13, 21, 34, 55, 89, 144, 156, 261, 377, 610, 987, 1597 }
local IMAGE_KEYS: { string } = {}
for _, id in IMAGE_IDS do
	table.insert(IMAGE_KEYS, `rbxthumb://type=AvatarHeadShot&id={id}&w=48&h=48`)
end
dataset.IMAGE_KEYS = IMAGE_KEYS

dataset.FAILING_IMAGE_KEY = "rbxassetid://1"

local LOCALE_SUFFIX = " — Qualifikationsrunde abgeschlossen"
local IDENTITY_RUNS = { "Wolkenkratzergesellschaft", "Donaudampfschifffahrt", "Rechtsschutzversicherung" }

export type Item = {
	id: string,
	name: string,
	detail: string,
	team: string,
	imageKey: string,
	value: number,
	enabled: boolean,
	rank: number,
}

export type Options = {
	count: number?,
	seed: number?,

	content: string?,
}

dataset.CONTENT_VARIANTS = { "normal", "locale", "identity" }

function dataset.build(opts: Options?): { Item }
	local o = opts or {}
	local count = math.max(0, math.floor(o.count or 200))
	local seed = math.floor(o.seed or 1)
	local content = o.content or "normal"
	assert(
		content == "normal" or content == "locale" or content == "identity",
		`[perf dataset] unknown content variant '{content}'`
	)
	local rng = newRng(seed)
	local rows = table.create(count)
	for i = 1, count do
		local first = rng.pick(FIRST)
		local last = rng.pick(LAST)
		local team = rng.pick(TEAM)
		local status = rng.pick(STATUS)
		local name = `{first} {last}`
		local detail = `{team} · {status} · lap {rng.int(1, 40)}`
		if content == "locale" then
			name = `{name} {rng.pick(TEAM)}stadt`
			detail = detail .. LOCALE_SUFFIX
		elseif content == "identity" then
			name = `{first}{rng.pick(IDENTITY_RUNS)}{last}`
		end
		rows[i] = {
			id = `r{i}`,
			name = name,
			detail = detail,
			team = team,
			imageKey = IMAGE_KEYS[(i - 1) % #IMAGE_KEYS + 1],

			value = rng.int(0, 100) / 100,
			enabled = rng.unit() < 0.5,
			rank = i,
		}
	end
	return rows
end

function dataset.digest(rows: { Item }): string
	local h = 2166136261
	local function mix(s: string)
		for i = 1, #s do
			h = bit32.bxor(h, string.byte(s, i))
			h = bit32.band(h * 16777619, 0xffffffff)
		end
	end
	for _, item in rows do
		mix(item.id)
		mix(item.name)
		mix(item.detail)
		mix(item.imageKey)
		mix(string.format("%.4f", item.value))
		mix(tostring(item.enabled))
	end
	return string.format("%08x", h)
end

dataset.RAMP_STEPS = { 100, 500, 2000, 10000, 40000 }
dataset.MAX_ROWS = 40000

return dataset
