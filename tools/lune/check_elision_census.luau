--!strict
--[[ THE GuiObject CENSUS — what elision is still buying (ADR-0032 §4, step 6).

	    lune run tools/lune/check_elision_census
	    lune run tools/lune/check_elision_census -- --report   (print, never fail)

	WHY THIS TOOL EXISTS. ADR-0032's headline is that nesting saves writes; its
	counter-headline is that nesting costs instances, because a container has to
	MATERIALISE before it can be a real parent. On a 20-row list surface, elision
	removes 61 of 142 GuiObjects — 43% — and materialising all of them costs
	+75.3%. The migration's whole design is to keep that: register a container
	only where nesting PAYS, so an unregistered container stays invisible to
	parenting and stays elided.

	That makes the elision percentage the number most likely to be given back
	quietly, one step at a time, and it was measured by an ad-hoc live probe
	recorded in one artifact file — nothing on disk could re-derive it. The brief
	asks for the count "at every stage"; a number you have to hand-build a probe
	for is a number that gets reported once. So this is one command.

	IT AGREES WITH THE LIVE PROBE, WHICH IS WHY IT IS ALLOWED TO BE HEADLESS.
	`artifacts/adr-0032-nested-instance-tree/live-probes.md` §4 measured 142
	creates / 61 elided / 81 GuiObjects in a real Studio session. This harness,
	through `FakeTarget`, reports the same three numbers on the same surface —
	so the fake's `FAKE_ELIDABLE` mirror is not merely believed to match the
	adapter's `ELIDABLE_CLASSES`, it is shown to.

	WHY FIXTURE A IS PINNED EXACTLY RATHER THAN TO A FLOOR. A floor answers
	"did elision get worse"; an exact pin also answers "did it get better, and
	does anyone know why". On a fixed synthetic surface every one of the three
	numbers is deterministic, so a change to any of them is a fact somebody
	should have to write down. Fixture B is the same rows inside a `ScrollView`
	— a real instance host today, and the shape the migration is actually about
	— and it is held to a floor, because its node count is a control's business
	and may legitimately move.
]]

local process = require("@lune/process")

local customFactory = require("../../src/core/custom")
local UI = require("../../src/blueprint")
local mountLib = require("../../src/mount")
local environment = require("../../src/env/environment")
local rendererLib = require("../../src/render/renderer")
local fake_target = require("../../tests/lib/fake_target")

-- ADR-0032 §4's surface, verbatim: 20 rows of
-- `HStack[ Box, VStack[Box, Box], Spacer, Box ]` = 142 nodes.
local function rows(rotation: number?): { any }
	local out: { any } = {}
	for i = 1, 20 do
		table.insert(
			out,
			UI.HStack({
				id = `Row{i}`,
				rotation = rotation,
				children = {
					UI.Box({ id = "Lead", surface = "raised" }),
					UI.VStack({
						id = "Text",
						children = {
							UI.Box({ id = "T1", surface = "raised" }),
							UI.Box({ id = "T2", surface = "raised" }),
						},
					}),
					UI.Spacer({ id = "Gap" }),
					UI.Box({ id = "Trail", surface = "raised" }),
				},
			})
		)
	end
	return out
end

local function census(screen: any): { creates: number, elided: number, guiObjects: number, pct: number }
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	local stats = controller.stats()
	local guiObjects = stats.creates - stats.elided
	return {
		creates = stats.creates,
		elided = stats.elided,
		guiObjects = guiObjects,
		pct = if stats.creates > 0 then 100 * stats.elided / stats.creates else 0,
	}
end

local FLAT = census(UI.Screen({
	id = "S",
	padding = 0,
	gap = 0,
	children = { UI.VStack({ id = "List", children = rows() }) },
}))

-- the same rows inside a real instance host. A `ScrollView` defaults
-- `clipChildren = true`, so this is the one shape that is ALREADY nested today.
local SCROLLED = census(UI.Screen({
	id = "S",
	padding = 0,
	gap = 0,
	children = { UI.ScrollView({ id = "List", children = rows() }) },
}))

-- ...and the same rows with an authored `rotation` on each one, which ADR-0032
-- Decision 4 turns into a real instance parent so the engine carries the term
-- down the subtree. THIS FIXTURE EXISTS TO CHARGE THE STEP FOR ITS INSTANCES.
-- Registering a host means materialising it, so the 20 row containers leave the
-- elidable set; publishing that delta beside the flat number is the difference
-- between a priced trade and a quiet retreat.
local ROTATED = census(UI.Screen({
	id = "S",
	padding = 0,
	gap = 0,
	children = { UI.VStack({ id = "List", children = rows(30) }) },
}))

-- ADR-0032 §4, live Studio probe. Exact, not a floor — see the header.
local EXPECT_FLAT = { creates = 142, elided = 61, guiObjects = 81 }
-- Decision 4's price, pinned exactly for the same reason fixture A is: 20 row
-- HStacks stop being elidable, so 61 - 20 = 41 and the surface carries 20 more
-- GuiObjects. If that number moves, the boundary predicate changed.
local EXPECT_ROTATED = { creates = 142, elided = 41, guiObjects = 101 }
-- fixture B's floor: elision must keep removing at least this share. Set two
-- points below the measured value so an ordinary control-side node change does
-- not cry wolf, and any real retreat does.
local SCROLLED_FLOOR_PCT = 40.0

local problems: { string } = {}
if FLAT.creates ~= EXPECT_FLAT.creates or FLAT.elided ~= EXPECT_FLAT.elided then
	table.insert(
		problems,
		`flat 20-row list: expected {EXPECT_FLAT.creates} creates / {EXPECT_FLAT.elided} elided `
			.. `({EXPECT_FLAT.guiObjects} GuiObjects, the ADR-0032 §4 live baseline), got `
			.. `{FLAT.creates} / {FLAT.elided} ({FLAT.guiObjects} GuiObjects). If a migration step `
			.. "registered a host here, that is the instance cost arriving — record it in the ADR "
			.. "and re-pin these numbers deliberately."
	)
end
if ROTATED.creates ~= EXPECT_ROTATED.creates or ROTATED.elided ~= EXPECT_ROTATED.elided then
	table.insert(
		problems,
		`rotated 20-row list: expected {EXPECT_ROTATED.creates} creates / {EXPECT_ROTATED.elided} elided `
			.. `({EXPECT_ROTATED.guiObjects} GuiObjects — ADR-0032 Decision 4's priced cost, 20 row `
			.. `containers materialising to become real parents), got {ROTATED.creates} / {ROTATED.elided} `
			.. `({ROTATED.guiObjects} GuiObjects). The boundary predicate moved: either more containers `
			.. "are earning a host than the rule says, or fewer, and both are worth writing down."
	)
end
if SCROLLED.pct < SCROLLED_FLOOR_PCT then
	table.insert(
		problems,
		string.format(
			"scrolled 20-row list: elision fell to %.1f%% (floor %.1f%%) — %d of %d containers "
				.. "materialised. A host must earn its instance; check what started registering.",
			SCROLLED.pct,
			SCROLLED_FLOOR_PCT,
			SCROLLED.guiObjects,
			SCROLLED.creates
		)
	)
end

local report = process.args[1] == "--report" or process.args[2] == "--report"

print(
	string.format(
		"elision census — flat 20-row list: %d creates, %d elided, %d GuiObjects (%.1f%% elided)",
		FLAT.creates,
		FLAT.elided,
		FLAT.guiObjects,
		FLAT.pct
	)
)
print(
	string.format(
		"                 in a ScrollView: %d creates, %d elided, %d GuiObjects (%.1f%% elided)",
		SCROLLED.creates,
		SCROLLED.elided,
		SCROLLED.guiObjects,
		SCROLLED.pct
	)
)

print(
	string.format(
		"                 rotated rows (D4): %d creates, %d elided, %d GuiObjects (%.1f%% elided) "
			.. "— +%d instances against the flat arm, the priced cost of 20 move boundaries",
		ROTATED.creates,
		ROTATED.elided,
		ROTATED.guiObjects,
		ROTATED.pct,
		ROTATED.guiObjects - FLAT.guiObjects
	)
)

if #problems > 0 and not report then
	print(`check_elision_census: FAIL — {#problems} problem(s):`)
	for _, p in problems do
		print(`  - {p}`)
	end
	process.exit(1)
end
print("check_elision_census: PASS — the 43% the flat tree bought is still bought.")
