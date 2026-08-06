--!strict
-- The performance lab's DETERMINISTIC DATASET (roadmap Step 9, acceptance PL-2/PL-12).
--
-- ONE definition of "the dense list", shared by the Roblox place and the headless
-- Lune scenes. That sharing is the whole point of this file: two independently
-- written row generators would drift, and the day they did, the headless budget
-- would be guarding a workload the place does not run — a gate that passes while
-- the thing it names regresses.
--
-- ENGINE-FREE AND REQUIRE-FREE. It runs identically under Lune (`require` by
-- relative path from bench/) and inside Roblox (replicated as a ModuleScript), so
-- it must not touch `game`, `Instance`, `Random`, `os`, or `math.randomseed`.
--
-- WHY ITS OWN PRNG. `Random.new(seed)` is Roblox-only and `math.random` is seeded
-- per host, so neither reproduces a row set across the two environments. The
-- generator below is a plain 32-bit xorshift with fixed constants: the same seed
-- yields byte-identical rows in Lune, in Studio, and on a phone, which is what
-- makes "same seed, same workload" a checkable claim rather than an intention.
--
-- VERSIONING. `dataset.VERSION` travels with every capture. If the row shape, the
-- word lists, the image set, or the generator changes, the version changes with
-- it — a changed workload is a NEW workload, never a quietly re-based comparison
-- against older numbers.

local dataset = {}

-- Bump on ANY change to the generated content or its shape. Captures carrying a
-- different version are not comparable and the capture checker refuses to treat
-- them as such.
dataset.VERSION = "perf-dataset/1"

-- ---- deterministic 32-bit xorshift ----------------------------------------
-- Small, exactly reproducible, and deliberately not cryptographic. `//` and the
-- bit32 library are both available in Lune and Roblox Luau.
local function newRng(seed: number)
	-- a zero state is a fixed point for xorshift, so it is mapped away rather
	-- than left to silently produce a constant "random" sequence
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
	-- inclusive integer in [lo, hi]
	function rng.int(lo: number, hi: number): number
		return lo + rng.next() % (hi - lo + 1)
	end
	-- [0, 1)
	function rng.unit(): number
		return rng.next() / 4294967296
	end
	function rng.pick<T>(list: { T }): T
		return list[rng.int(1, #list)]
	end
	return rng
end

dataset.newRng = newRng

-- ---- the vocabulary -------------------------------------------------------
-- Varied but bounded. Text VARIETY matters to a layout profile (every row hitting
-- the same string would let a measurement cache answer the whole list from one
-- entry, which is not what a real screen does), while a BOUNDED vocabulary keeps
-- the premeasure cache's behaviour interpretable instead of unbounded-by-design.
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

-- ---- the image set --------------------------------------------------------
-- DETERMINISTIC and SMALL. `rbxthumb://` avatar headshots are real, cheap,
-- publicly resolvable content ids that need no uploaded asset and no place
-- permission, which is what keeps the emitted place self-contained and
-- publishable by the user with nothing attached to it (PL-1).
--
-- Sixteen distinct keys, assigned round-robin: enough for cold-fetch cost to be
-- visible without turning the workload into a network test, and few enough that
-- the WARM variant genuinely reuses cached content.
local IMAGE_IDS = { 1, 2, 5, 8, 13, 21, 34, 55, 89, 144, 156, 261, 377, 610, 987, 1597 }
local IMAGE_KEYS: { string } = {}
for _, id in IMAGE_IDS do
	table.insert(IMAGE_KEYS, `rbxthumb://type=AvatarHeadShot&id={id}&w=48&h=48`)
end
dataset.IMAGE_KEYS = IMAGE_KEYS

-- A key that CANNOT resolve, for the asset-failure pass. It is a separate,
-- declared member of the dataset rather than a magic string in one scenario, so
-- the failure workload and the success workload demonstrably share a generator.
dataset.FAILING_IMAGE_KEY = "rbxassetid://1"

-- ---- long-content variants (the large-text workload) ----------------------
-- `locale` = the ~1.4x German-class expansion the localization rule requires
-- every player-facing string to survive; `identity` = a long unbroken name, the
-- one string class that legitimately truncates and therefore must disclose.
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
	-- "normal" (default), "locale" (expanded strings), "identity" (long unbroken
	-- names). A content variant is part of the workload identity and is recorded
	-- in the capture beside the seed.
	content: string?,
}

dataset.CONTENT_VARIANTS = { "normal", "locale", "identity" }

-- Build `count` rows. Pure: same (count, seed, content) => byte-identical rows.
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
			-- the expansion rides BOTH lines: a layout that survives a long title
			-- and a short subtitle has not been tested at all
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
			-- a value control's position, deterministic per row
			value = rng.int(0, 100) / 100,
			enabled = rng.unit() < 0.5,
			rank = i,
		}
	end
	return rows
end

-- A stable fingerprint of a generated row set. Two captures claiming the same
-- workload must produce the same digest; a drifting generator shows up here
-- rather than as an unexplained shift in a frame time.
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

-- The declared, SAFE ramp ladder (PL-11). A stress tool exists to find the knee
-- of the curve, not to make the device it is measuring unrecoverable, so the
-- steps are a fixed list with a hard ceiling rather than "keep doubling".
dataset.RAMP_STEPS = { 100, 500, 2000, 10000, 40000 }
dataset.MAX_ROWS = 40000

return dataset
