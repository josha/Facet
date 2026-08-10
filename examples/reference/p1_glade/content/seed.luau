--!strict
-- Glade (RA-P1) — the seeded world. Original content, fixed at authoring time,
-- read by every fake service. Nothing here reads a clock or a random number:
-- the whole world is a function of these tables plus the injected `now`, which
-- is what makes "same seed + same steps ⇒ identical dump" mechanical rather
-- than careful.
--
-- COLOURS IN THIS FILE ARE SCENE ART DATA, NOT UI TOKENS (spec §2). The sky
-- ramp, the silhouette wash and each wisp's/nectar's identity hue describe a
-- PICTURE — the same authority a texture has — and they reach the tree only
-- through `UI.gradient` stops and the `tint` channel's declared `direct` form,
-- never through a surface, a role, or a state. Every UI surface, every piece of
-- chrome and every state in this proof is a theme role. They are stored as
-- `{ r, g, b }` ARRAYS (0..1) and converted at the call site, so no line here or
-- downstream reads as a colour literal in a role's place.

local seed = {}

-- The world seed. It is a NUMBER rather than a comment because the scenario's
-- reset re-derives from it and the report publishes it, so "which world is this"
-- is answerable from a dump.
seed.WORLD = 20260808

-- ---- demo-scale time --------------------------------------------------------
-- Drain constants (spec §1). Deliberately demo scale: a player watching the
-- overview must SEE a ring move inside a session, which is the whole point of
-- the row. Production would read these from the server.
seed.DRAIN = {
	nectar = { empty = 540, low = 450 }, -- 9 min to empty, "Low" from 7.5 min
	dew = { empty = 960, low = 780 }, -- 16 min to empty, "Low" from 13 min
}

-- A demo day is five minutes, split into the five phase buckets, so the sky
-- ramp visibly moves during a played slice and each glade's fixed offset puts
-- it in a different bucket at t = 0.
seed.DAY_SECONDS = 300
seed.PHASES = { "night", "dawn", "day", "dusk", "eve" }

-- how long a scripted commerce command takes to resolve, in injected seconds.
-- Short, because the loop's subject is the STATES, not the wait.
seed.COMMAND_SECONDS = 0.75

-- ---- structural metrics -----------------------------------------------------
-- These are STRUCTURAL numbers (breakpoint-shaped), not style values: they say
-- how much room a thing needs before the layout has to change shape, which is
-- the same class of decision `adaptive.BREAKPOINTS` is. Everything a theme owns
-- — spacing, radii, type, control sizes, hit floors — is named, never numbered,
-- everywhere in this proof.
seed.METRICS = {
	shellContentMin = 320, -- the content lane's floor; below it the shell re-lanes
	gladeCardMin = 236, -- overview grid column floor
	nectarCardMin = 168, -- picker shelf card
	packCardMin = 176, -- shop shelf card
	detailPaneMin = 320, -- the shell's detail lane
	ringSmall = 34, -- glance ring on a card
	ringLarge = 56, -- supply-row ring
	portrait = 48, -- wisp portrait well
	heroPortrait = 96, -- S5/S6 portrait
	sceneShort = 132, -- hero scene, three declared steps
	sceneMedium = 190,
	sceneTall = 244,
	wispSize = 26, -- the wisp's own box at natural scale
	offerActionsMax = 360, -- the offer card's action row: full width, and no wider
	-- the supply row's trailing verb: a floor that keeps it legible and a cap
	-- past which it truncates through its declared disclose — because lineLimit
	-- caps LINES, never the width a text asks for, and under the 1.4x locale
	-- the verb's natural ask set the row minimum past the detail lane
	affordanceMin = 64,
	affordanceMax = 132,
}

-- ---- the sky ramp (scene art) ----------------------------------------------
-- Two-to-three stop gradients per phase bucket, plus the silhouette wash the
-- tree line takes in that phase. Interpolated by a memo and fed to UI.gradient.
seed.SKY = {
	night = { high = { 0.04, 0.05, 0.13 }, low = { 0.10, 0.11, 0.22 }, silhouette = { 0.02, 0.03, 0.07 } },
	dawn = { high = { 0.28, 0.24, 0.42 }, low = { 0.86, 0.60, 0.44 }, silhouette = { 0.10, 0.09, 0.16 } },
	day = { high = { 0.36, 0.62, 0.86 }, low = { 0.74, 0.86, 0.92 }, silhouette = { 0.14, 0.22, 0.20 } },
	dusk = { high = { 0.20, 0.18, 0.36 }, low = { 0.90, 0.52, 0.34 }, silhouette = { 0.09, 0.08, 0.14 } },
	eve = { high = { 0.09, 0.10, 0.24 }, low = { 0.38, 0.24, 0.38 }, silhouette = { 0.05, 0.05, 0.11 } },
}

-- the identity base a gradient multiplies (a UIGradient multiplies the node's own
-- fill, so a wash needs something to act on)
seed.WHITE = { 1, 1, 1 }

seed.MOSS = { 0.20, 0.34, 0.20 }
seed.MOSS_DEEP = { 0.13, 0.24, 0.15 }
seed.FERN = { 0.17, 0.31, 0.19 }
seed.DEWSTONE = { 0.52, 0.56, 0.58 }
seed.DEWWATER = { 0.62, 0.82, 0.88 }

-- ---- glades -----------------------------------------------------------------
-- `nectarAge` / `dewAge` are the seeded elapsed seconds at t = 0, chosen so the
-- overview shows all three supply states — full, low, empty — on the first
-- frame, without any step having to be driven first.
seed.GLADES = {
	{ id = "mossholm", favourite = true, nectar = "clover", phaseOffset = 180, nectarAge = 0, dewAge = 120 },
	{ id = "fernhollow", favourite = false, nectar = "meadow", phaseOffset = 0, nectarAge = 460, dewAge = 800 },
	{ id = "lanternDell", favourite = false, nectar = "fern", phaseOffset = 60, nectarAge = 600, dewAge = 300 },
	{ id = "brambleRest", favourite = false, nectar = "bramble", phaseOffset = 120, nectarAge = 200, dewAge = 1000 },
	{ id = "stillpond", favourite = false, nectar = "heather", phaseOffset = 240, nectarAge = 470, dewAge = 790 },
}

-- ---- wisps ------------------------------------------------------------------
-- `scale` is the species' natural size in the scene; `lumenOnly` gates the early
-- arrival on the top charm tier (spec §1).
seed.WISPS = {
	{
		id = "emberwisp",
		scale = 0.83,
		phase = "eve",
		favourite = "bramble",
		core = { 1.00, 0.86, 0.62 },
		glow = { 0.96, 0.54, 0.24 },
	},
	{
		id = "palewisp",
		scale = 1.00,
		phase = "dawn",
		favourite = "clover",
		core = { 0.98, 0.98, 0.94 },
		glow = { 0.78, 0.82, 0.92 },
	},
	{
		id = "frostwisp",
		scale = 0.71,
		phase = "night",
		favourite = "moonpetal",
		lumenOnly = true,
		core = { 0.90, 0.98, 1.00 },
		glow = { 0.46, 0.74, 0.96 },
	},
	{
		id = "duskwisp",
		scale = 1.00,
		phase = "dusk",
		favourite = "moonpetal",
		core = { 0.92, 0.86, 1.00 },
		glow = { 0.52, 0.38, 0.82 },
	},
	{
		id = "sunwisp",
		scale = 1.00,
		phase = "day",
		favourite = "meadow",
		core = { 1.00, 0.96, 0.74 },
		glow = { 0.98, 0.80, 0.28 },
	},
	{
		id = "tidewisp",
		scale = 0.76,
		phase = "eve",
		favourite = "gilded",
		hero = true,
		core = { 0.86, 0.98, 0.96 },
		glow = { 0.24, 0.70, 0.72 },
	},
}

-- ---- nectars ----------------------------------------------------------------
-- Six standard (free) in shelf order, three premium in priority order. `art` is
-- the jar's identity hue — game data, so it rides the tint channel's declared
-- `direct` form and is deliberately theme-exempt (a variety is not a state).
seed.NECTARS = {
	{ id = "clover", premium = false, art = { 0.72, 0.80, 0.46 } },
	{ id = "meadow", premium = false, art = { 0.84, 0.78, 0.38 } },
	{ id = "fern", premium = false, art = { 0.46, 0.68, 0.44 } },
	{ id = "thistle", premium = false, art = { 0.66, 0.52, 0.74 } },
	{ id = "bramble", premium = false, art = { 0.44, 0.24, 0.36 } },
	{ id = "heather", premium = false, art = { 0.80, 0.56, 0.70 } },
	{ id = "starlight", premium = true, priority = 3, art = { 0.80, 0.86, 1.00 } },
	{ id = "moonpetal", premium = true, priority = 2, art = { 0.68, 0.72, 0.94 } },
	{ id = "gilded", premium = true, priority = 1, art = { 0.92, 0.72, 0.30 } },
}

-- ---- packs (the provision shop's shelves) -----------------------------------
-- One single and one bundle-of-five per premium nectar; the Starlight bundle is
-- the declared "best value" hero. `price` is a number here and NEVER composed in
-- UI copy — CommerceService publishes the string (spec §1).
seed.PACKS = {
	{ id = "starlightSingle", nectar = "starlight", quantity = 1, price = 79, art = { 0.80, 0.86, 1.00 } },
	{
		id = "starlightBundle",
		nectar = "starlight",
		quantity = 5,
		price = 299,
		hero = true,
		art = { 0.62, 0.72, 0.98 },
	},
	{ id = "moonpetalSingle", nectar = "moonpetal", quantity = 1, price = 69, art = { 0.68, 0.72, 0.94 } },
	{ id = "moonpetalBundle", nectar = "moonpetal", quantity = 5, price = 259, art = { 0.52, 0.58, 0.88 } },
	{ id = "gildedSingle", nectar = "gilded", quantity = 1, price = 59, art = { 0.92, 0.72, 0.30 } },
	{ id = "gildedBundle", nectar = "gilded", quantity = 5, price = 219, art = { 0.82, 0.58, 0.20 } },
}

-- the satchel a fresh keeper starts with (spec §1)
seed.SATCHEL = { starlight = 3 }

-- ---- the Keeper's Charm -----------------------------------------------------
seed.CHARM_TIERS = {
	{ id = "ember", rank = 1, price = 99 },
	{ id = "grove", rank = 2, price = 199 },
	{ id = "lumen", rank = 3, price = 349 },
}
seed.CHARM_RANK = { none = 0, ember = 1, grove = 2, lumen = 3 }

-- ---- the keeper -------------------------------------------------------------
seed.KEEPER = { displayName = "Wren of the Low Fen", contact = "wren@glade", joined = "the third thaw" }

-- ---- visit windows ----------------------------------------------------------
-- Seconds relative to t = 0 (session start). A negative window is in the past, a
-- window containing 0 is a CURRENT visit, positive is scheduled. `earlyStart` is
-- the Lumen-only early arrival: VisitScheduler reads it instead of `start` while
-- the charm tier is Lumen, which is the entitlement gate made of data.
seed.VISITS = {
	{ id = "v1", glade = "mossholm", wisp = "emberwisp", start = -900, finish = -720 },
	{ id = "v2", glade = "mossholm", wisp = "emberwisp", start = -60, finish = 240 },
	{ id = "v3", glade = "mossholm", wisp = "tidewisp", start = 600, finish = 900 },
	{ id = "v4", glade = "fernhollow", wisp = "palewisp", start = -1500, finish = -1200 },
	{ id = "v5", glade = "fernhollow", wisp = "duskwisp", start = 300, finish = 600 },
	{ id = "v6", glade = "lanternDell", wisp = "sunwisp", start = -600, finish = -400 },
	{ id = "v7", glade = "lanternDell", wisp = "frostwisp", start = 480, finish = 760, earlyStart = 60 },
	{ id = "v8", glade = "stillpond", wisp = "duskwisp", start = -2000, finish = -1800 },
	{ id = "v9", glade = "stillpond", wisp = "tidewisp", start = -30, finish = 300 },
	-- brambleRest deliberately has NO visits: its detail must show the empty state
}

-- ---- flora (browse-only section) --------------------------------------------
seed.FLORA = {
	{ id = "mosscap", art = { 0.28, 0.44, 0.26 } },
	{ id = "lanternvine", art = { 0.74, 0.66, 0.32 } },
	{ id = "dewfern", art = { 0.34, 0.56, 0.42 } },
	{ id = "bramblewort", art = { 0.42, 0.26, 0.34 } },
	{ id = "stillreed", art = { 0.46, 0.62, 0.56 } },
}

-- ---- scripted commerce outcomes ---------------------------------------------
-- The rejection FIXTURES (responsibility ledger: "scripted rejection
-- fixtures"). Indexed by attempt ordinal within each command family and cycling,
-- so the played slice reaches every rejection reason through on-screen controls
-- alone and a headless test can pin which attempt produces which verdict.
seed.OUTCOMES = {
	pack = { "confirmed", "declined", "confirmed", "offline" },
	charm = { "confirmed", "owned", "confirmed" },
	restore = { "confirmed", "offline" },
}

-- ---- lookups ----------------------------------------------------------------

local function index(list: { any }): { [string]: any }
	local out: { [string]: any } = {}
	for _, entry in list do
		out[entry.id] = entry
	end
	return out
end

seed.GLADE_BY_ID = index(seed.GLADES)
seed.WISP_BY_ID = index(seed.WISPS)
seed.NECTAR_BY_ID = index(seed.NECTARS)
seed.PACK_BY_ID = index(seed.PACKS)
seed.CHARM_BY_ID = index(seed.CHARM_TIERS)
seed.FLORA_BY_ID = index(seed.FLORA)

-- premium nectars in priority order (highest first): the shop's shelf order
seed.PREMIUM = {}
for _, nectar in seed.NECTARS do
	if nectar.premium then
		table.insert(seed.PREMIUM, nectar)
	end
end
table.sort(seed.PREMIUM, function(a: any, b: any)
	return a.priority > b.priority
end)

seed.STANDARD = {}
for _, nectar in seed.NECTARS do
	if not nectar.premium then
		table.insert(seed.STANDARD, nectar)
	end
end

-- packs of one premium nectar, ascending by quantity
function seed.packsFor(nectarId: string): { any }
	local out: { any } = {}
	for _, pack in seed.PACKS do
		if pack.nectar == nectarId then
			table.insert(out, pack)
		end
	end
	table.sort(out, function(a: any, b: any)
		return a.quantity < b.quantity
	end)
	return out
end

-- phaseAt(offset, now) — which of the five buckets this glade's sky is in.
function seed.phaseAt(offset: number, now: number): string
	local span = seed.DAY_SECONDS / #seed.PHASES
	local t = (now + offset) % seed.DAY_SECONDS
	local bucket = math.floor(t / span) + 1
	if bucket > #seed.PHASES then
		bucket = #seed.PHASES
	end
	return seed.PHASES[bucket]
end

return seed
