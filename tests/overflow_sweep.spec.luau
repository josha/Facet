--!strict
-- THE ALWAYS-ON OVERFLOW SWEEP (device bug round 2026-08-12, Group B).
--
-- WHY THIS EXISTS. `docs/lessons/the-solver-already-told-you.md` records a defect
-- that shipped past a green suite, a green perf gate, a five-view device matrix
-- and four fresh-context reviews, purely because nothing ever called
-- `controller.diagnostics()`. On 2026-08-12 the same class arrived again, from a
-- phone, three times in one sitting: a table entirely below the fold in landscape
-- with nothing to scroll it, a Match-3 button row sliced by the right screen
-- edge, and an all-controls fixture running past its own box. The solver had
-- already said so, in these exact words, on every one of them:
--
--     content overflows this <stack> by <N>px on the main axis; it will paint
--     outside its box (wrap it in a ScrollView, or give it room)
--
-- Section 13 of that lesson is explicit about why "call it in the fixture you are
-- working on" was not enough: *a fixture must FAIL on it, or the list is a log
-- nobody reads*. So this file asks the question of EVERY showcase surface at
-- EVERY swept viewport, on every `./run-tests.sh`, with nobody deciding to run
-- it.
--
-- ...and since 2026-08-13 it asks about EVERY FINDING, not the two sentences
-- somebody remembered to grep for. See "WHAT COUNTS AS A FINDING" below: the
-- filter is gone, because a filter is the same defect one level up.
--
-- WHAT IT COVERS
--   * every engine-free gallery scenario (the demo picker's four fixtures, the
--     eight Sponsor labs, the verification fixtures and the composition/keyboard
--     stages) — the same modules Studio loads;
--   * all seven tutorial examples, through the tutorial build contract;
--   * all five clean-room reference proofs.
--
-- ...at the five canonical device-matrix viewports (the ones
-- `tests/theme_matrix_audit.spec.luau` recorded live, so the headless twin and
-- the Studio drive talk about the same geometry) PLUS the narrowest supported
-- viewport in BOTH orientations. Landscape is not optional: B5 was landscape-only
-- and portrait-clean, which is exactly how it survived a portrait capture set.
--
-- ...at EVERY ACCESSIBILITY TEXT SIZE a player can choose (2026-08-13, below).
--
-- ...under the showcase's OWN chrome reservation. Every one of these surfaces is
-- reached in `LuauUI-Showcase` through the demo picker, which reserves its chip
-- strip by writing `coreSafeInsets.top` (see `examples/gallery/client/init.client`
-- and `demo_picker.barReservation`). A sweep that laid out against the bare
-- viewport would be measuring a screen no player ever sees — 62px taller than the
-- real one, which is the whole margin several of these defects lived in. The
-- number is read from the picker rather than written here, so the two cannot
-- drift.
--
-- ── THE TEXT-SIZE AXIS (accessibility round, 2026-08-13) ─────────────────────
--
-- This sweep varied display SIZE and never varied TEXT SIZE, and that blind spot
-- bit twice in one day, found independently by two agents: the perf lab's
-- virtualized rows overflowed their fixed slot by 11/39/59px at `preferredTextOffset`
-- 4/10/14 (clean at 0, so headless and a default Studio session both saw nothing),
-- and `examples/reference/p4_foyer`'s TopBar was found overflowing its hstack at
-- the same preference — PRE-EXISTING, byte-identical with every edit stashed,
-- invisible for exactly the same reason. `docs/lessons/luauui-fixed-px-heights.md`
-- names the class: a px height fixed against content that is not fixed. The
-- player's text preference is the one input that moves the content and nothing
-- else, so a sweep that holds it at Medium is measuring one quarter of the
-- screens that ship.
--
-- THE FOUR VALUES ARE THE WHOLE DOMAIN. `preferredTextOffset` is an additive px
-- offset the engine applies to every text node, measured live 2026-08-03 as
-- { Medium = 0, Large = 4, Larger = 10, Largest = 14 } (decision LTN-1,
-- artifacts/large-text-accessibility/probe/preference-probe.json). They are read
-- from `tests/lib/large_text.PREFERENCES` rather than written here, so the day a
-- fifth preference is measured this sweep picks it up without an edit.
--
-- WHY THE FULL CROSS PRODUCT, AND WHAT IT COSTS. 42 surfaces x 8 viewports x 4
-- preferences is a 4x multiplier on an always-on check, so the shape was measured
-- before it was chosen (`docs/plans/swiftui-parity-round3.md`, the accessibility
-- section):
--   * re-mounting each surface once per preference: 3339ms (+2.5s on the suite);
--   * MOUNTING ONCE AND SWINGING THE PREFERENCE LIVE: 2126ms (+1.27s, ~+2.7%),
--     which is what this file does. The swing is the same seam a player uses —
--     `PreferredTextSize` changes while the experience runs — and the suite
--     already pins it as equivalent to a fresh mount (`tests/large_text_hot_swap.spec`
--     LTSWAP-BORN, "a screen BORN at Largest matches one swung there live").
--     Measured directly here too: both modes produced the same 304 findings, byte
--     for byte, across the whole cross product.
--
-- WHY NOT A NARROWED SET. Two narrowings looked defensible and both are provably
-- wrong on this corpus, which is why nothing is dropped:
--   * "sweep the extremes, 0 and 14" MISSES `03_settings_sync` /Settings/Page/State,
--     which overflows by 24px at +4 and is clean at +10 and +14 — the preference
--     axis is NOT monotone, because a bigger preference reflows the page and can
--     hand a box more room than a smaller one did (p5_wardrobe's item card is the
--     same story at 640x320: it fires at +4 and +14 and not at +10);
--   * "sweep the full set only at the narrowest viewport" MISSES 5 of the 35
--     findings, four of them p2_cartwheel's, which appear ONLY at tablet-landscape
--     1079x809 — and it would drop 61 of 304 findings at console-ten-foot, where
--     the Large display class multiplies the type scale by 1.5 ON TOP of the
--     preference. Narrow is not where large-text risk lives; it is merely where
--     it is easiest to imagine.
--
-- ── THE THEME AXIS (standing rule 4, 2026-08-14) ─────────────────────────────
--
-- This sweep ran its entire cross product on the flat Studio Neutral resolution
-- and nothing else, while the round-3 brief's standing rule 4 requires every gap
-- closure to be "verified to not overlap or clip ACROSS EVERY SHIPPED THEME —
-- Pixel Quest and Parchment have both broken layouts that Studio Neutral
-- survived". That clause was carried by three hand-written per-file sweeps
-- (theme_matrix_audit, theme_reference_packages, instance_recycling_themed),
-- none of which asks this question of the showcase corpus. It was the house
-- defect class one level up — an instrument claiming more coverage than it has —
-- and it hid two defects that this axis found in its first run:
--
--   O-23  `progress_ring`'s own spinner row overflowed by 40px under Glossy
--         Mobile and Glossy Touch and 6px under Fantasy Ornate and Parchment, at
--         320x640, at the DEFAULT text preference. Round 3's own D2 feature.
--   O-25  every `02_playlist_table` cell painted 4px outside its cell under Pixel
--         Quest, at the default preference, on every viewport: the Table derived
--         its row height without the `chromeInsets.selection` the same control
--         makes its cells SPEND.
--
-- Both are fixed; both are pinned by tests/table_theme_row_box.spec.luau and
-- tests/progress_circular.spec.luau. Neither could be seen from a consumer.
--
-- WHAT A THEME COSTS, AND WHAT THE TIER IS. Naively this is a 9x multiplier on an
-- always-on check (33.5s, +30s on a 62s suite), so the shape was measured over the
-- WHOLE cross product first (43 surfaces x 12 themes x 8 viewports x 4
-- preferences, artifacts/swiftui-parity-round3/theme-sweep-tier.md) and the tier
-- chosen from that data:
--
--   1. A PACKAGE IS THE GEOMETRY AXIS; A THEME IS ITS PALETTE. `classic-desktop`
--      Day vs Night, `fantasy-ornate` Crypt vs Grand Hall and `fantasy-parchment`
--      Candlelight vs Daylight each produced BYTE-IDENTICAL finding sets over the
--      whole cross product — 527 / 3863 / 2202 rows, zero difference — which is
--      ADR-0019's "a swap moves the palette, not the geometry" measured rather
--      than recalled. So the axis is the eight shipped PACKAGES, not the twelve
--      themes, and that costs nothing at all in coverage.
--   2. EVERY VIEWPORT, because a viewport changes the TREE and not just the box.
--      `p4_foyer`'s NavRail is behind a `SideRailWhen` that only exists on
--      desktop, `p3_sipworks`' panes likewise: 16 of the 240 theme-only findings
--      are on nodes a narrow-only pass never BUILDS. That is §13.1's rule again —
--      a sweep only covers the configurations its fixture actually builds.
--   3. THE DEFAULT PREFERENCE for every package at every viewport, plus the
--      LARGEST preference at the two narrowest viewports. A package's own
--      contribution is its metric ladder, which moves content at every
--      preference; the preference axis's own job is already done in full on the
--      same surfaces by the neutral pass above.
--
-- Measured: 3.50x this file's cost (3.0s -> 9.8s, +6.8s on the suite) for 224 of
-- the 240 theme-only findings the full cross product reports — 93%, against 9.00x
-- for the last 16.
--
-- ...AND THE SWING IS THE SAME MOUNT. A package is committed the way the theme
-- picker commits one — `env:set("themeMetrics", snapshot)`, the metric half of
-- ADR-0019 §7's one transaction — so one mount per (surface, viewport) serves
-- every package, exactly as it already serves every preference. Proved rather
-- than assumed, over the whole cross product: swinging and re-mounting produced
-- the SAME 24 963 distinct findings, zero on either side alone.
--
-- WHAT THE THEME AXIS DOES NOT COVER, stated here rather than left to be assumed
-- (see `themeCoverage` at the bottom of this file, which fails if this list and
-- the code disagree):
--   * the six WIDE viewports at any preference above the default — 16 measured
--     findings, listed in artifacts/swiftui-parity-round3/theme-sweep-tier.md;
--   * the two narrow viewports at +4 and +10 under a package — 3 measured
--     findings, and the preference axis is NOT monotone (this file's own header
--     proves that on the neutral pass), so this is a known hole and not a claim
--     that +14 dominates;
--   * the SECOND theme of a package, which the equivalence above makes free —
--     but it is an equivalence about GEOMETRY, and a palette defect (contrast, a
--     tint that eats a label) is not a thing the solver can see at all;
--   * `examples/themes/ornate_gauge` and `custom_control`, which are control
--     contributions rather than packages, and the two `testOnly` fixtures.
--
-- WHAT IT IS NOT. It is not a paint check and it cannot see the engine's own text
-- bounds, so a live surface can still overflow on measurements this suite
-- estimates. Nor does it see the scroll host's WINDOW: the engine's visible box is
-- narrower than the frame by the bar thickness even where the layout reserved
-- nothing, which is a second, independent way for content to be clipped on the
-- right — measured and pinned separately in tests/scroll_window_clip.spec.luau. It
-- sweeps ONE LOCALE (the surfaces' own default copy): the 1.4x pseudo-locale is a
-- second, independent expansion axis, and p4_foyer's TopBar overflows by 33/58px
-- at 390x844 under `xa` where it is clean in English — measured 2026-08-13 and
-- logged as NOT covered here rather than left to be assumed. It is the part of
-- "does this fit on a phone" that a machine can answer every time, and the floor
-- under the Studio device matrix rather than a replacement for it.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local fake_target = require("./lib/fake_target")
local demo_picker = require("../examples/gallery/client/demo_picker") :: any
local device_views = require("./lib/device_views")
local large_text = require("./lib/large_text")

-- The five canonical rows of docs/plans/studio-device-verification.md at the
-- viewports the driver RECORDED, plus the narrowest supported viewport in both
-- orientations. The table itself lives in `tests/lib/device_views.luau` because
-- `tests/example_readouts.spec.luau` sweeps the SAME sizes with a different
-- question, and a viewport only one of them visits is a viewport where one of the
-- two questions is never asked.
local VIEWS = device_views.VIEWS
local CAPABILITIES = device_views.CAPABILITIES

-- ...and the preference axis, derived from the one file that records what the
-- engine measured (see the header). Ascending, because every rule below is about
-- "at a preference at least this large".
local OFFSETS: { number } = {}
for _, preference in large_text.PREFERENCES do
	table.insert(OFFSETS, preference.offset)
end
table.sort(OFFSETS)
assert(OFFSETS[1] == 0, "the sweep's first pass must be the DEFAULT preference (offset 0)")
local LARGEST = OFFSETS[#OFFSETS]

-- ...and the THEME axis (see the header). Every package the showcase's theme
-- picker offers a player, each resolved ONCE at its own default theme, because a
-- package's second theme is its palette and was measured to move no geometry at
-- all. The two `testOnly` fixtures are absent for the same reason the picker
-- hides them, and `ornate_gauge` / `custom_control` are control contributions
-- rather than packages.
local PACKAGE_MODULES: { { id: string, module: any } } = {
	{ id = "classic-desktop", module = require("../examples/themes/classic_desktop") },
	{ id = "compact-pointer", module = require("../examples/themes/compact_pointer") },
	{ id = "fantasy-ornate", module = require("../examples/themes/fantasy_ornate") },
	{ id = "fantasy-parchment", module = require("../examples/themes/fantasy_parchment") },
	{ id = "glossy-mobile", module = require("../examples/themes/glossy_mobile") },
	{ id = "glossy-touch", module = require("../examples/themes/glossy_touch") },
	{ id = "pixel-quest", module = require("../examples/themes/pixel_quest") },
	{ id = "scifi-hud", module = require("../examples/themes/scifi_hud") },
}
local PACKAGES: { { id: string, snapshot: any } } = {}
for _, entry in PACKAGE_MODULES do
	local pkg, report = entry.module.build(LuauUI.themes)
	assert(
		pkg ~= nil,
		`{entry.id} failed its own package gate: {report and report.errors[1] and report.errors[1].message}`
	)
	table.insert(PACKAGES, { id = entry.id, snapshot = LuauUI.themes.resolve(pkg, nil, {}) })
end

-- THE CELLS A PACKAGE IS SWEPT AT (the tier, from the header): every viewport at
-- the default preference — because a viewport changes the TREE — plus the largest
-- preference at the two narrowest viewports, where a package's type ladder and
-- the player's preference compound. Derived from the view table rather than
-- written as ids, so a new viewport joins the structural pass automatically.
local NARROWEST_W = math.huge
for _, view in VIEWS do
	NARROWEST_W = math.min(NARROWEST_W, math.min(view.w, view.h))
end
local function themedOffsets(view: any): { number }
	if math.min(view.w, view.h) == NARROWEST_W then
		return { 0, LARGEST }
	end
	return { 0 }
end

-- The CoreGui topbar inset every matrix row measured, plus the strip the showcase
-- reserves for its two picker chips — `barReservation(coreTop, nil, slack)` is
-- the same call `init.client` makes on the frame before any chip geometry exists,
-- which is the floor it never goes below.
local SHOWCASE_TOP = demo_picker.barReservation(device_views.CORE_TOP, nil, 8)

-- Engine-free gallery scenarios. `examples` and the five `ref_*` scenarios are
-- absent ON PURPOSE: both are thin delegations that resolve their real module
-- through a replicated folder, so this file mounts those modules DIRECTLY below
-- (the same thing the delegation would have built, minus an engine).
local SCENARIOS = {
	"probe",
	"safe_area",
	"scroll_host",
	"path_ring",
	"async_images",
	"selection_bridge",
	"preferred_text",
	"drag_session",
	"virtual_list_native",
	"native_style",
	"authoring",
	"adaptive_controls",
	"theme_authoring",
	"perf_capture",
	"sponsor_motion",
	"sponsor_celebration",
	"sponsor_list",
	"sponsor_drop",
	"sponsor_toast",
	"sponsor_avatars",
	"sponsor_markers",
	"sponsor_billboard",
	"composition",
	"keyboard_navigation",
	"row_actions",
	-- SwiftUI-parity round 2's two new showcase surfaces. Both are reached
	-- through the demo picker, so both are swept under the same chrome
	-- reservation as every other one: `card_rail` derives its rail width from
	-- the live viewport (a constant painted a rail off the right edge of a 320px
	-- phone in the fixture it was modelled on), and `with_animation` puts two
	-- motion columns, a picker and a button in the ~200px a 640x320 landscape
	-- phone has left.
	"card_rail",
	"with_animation",
	-- parity round 3 D2: the circular indicator's showcase surface. Its ring is a
	-- fixed square from a theme metric — the one shape in the family that cannot
	-- shrink with its container — so a swept viewport is exactly where a page that
	-- no longer fits shows up
	"progress_ring",
	-- ...and item A: the flow-wrap showcase. Its tag cloud is the one surface here
	-- whose whole job is to NOT overflow at any width, which makes a swept viewport
	-- the direct test of the feature rather than a check on its packaging
	"flow_wrap",
	-- ...and item D: the lifecycle/`hidden` showcase. Its two panels are the same
	-- content in two states, and the `hidden` one is deliberately the TALLER of
	-- the two in both states — so a package whose chip face outgrows the page is
	-- caught here rather than on somebody's phone
	"lifecycle_hidden",
	-- ...and item C: the per-row opt-out showcase. A Table whose row height the
	-- FRAMEWORK derives (no `rowHeight` declared, deliberately) sitting under a
	-- page that scrolls, with a toolbar that wraps — three things whose whole
	-- failure mode is a viewport, which makes the swept cross product the direct
	-- test of the packaging rather than a check on it
	"row_capabilities",
	-- ...and the director's per-control sensory fixture. Two WRAPPING chip rows
	-- and a four-line sensation table under a page that scrolls: at the Largest
	-- text preference under Parchment the chips are the widest thing on the
	-- surface, so a swept viewport is the direct test of whether the wrap earns
	-- its keep rather than a check on the packaging around it
	"sensory_feedback",
	"text_degrade",
	"variable_extents",
	-- ...and ADR-0025: the screen-anchored HUD. Its whole contract is "the zones
	-- partition the box at every size", so a swept viewport IS the feature's test
	-- rather than a check on its packaging — and the surface carries a switch that
	-- takes 200px of HEIGHT off the box, which is the case a viewport sweep would
	-- otherwise never reach
	"hud",
	-- ...and ADR-0028's alarm fixture. It mounts a SECOND surface at build, which
	-- is the only surface in this corpus that does — so the swept assertion here
	-- is that the declared pair stays quiet at every viewport, preference and
	-- package, and the class is one edit away from reddening this file (which is
	-- how it was proved to be visible at all)
	"surface_overlap",
}

local EXAMPLES = {
	"01_temperature_converter",
	"02_playlist_table",
	"03_settings_sync",
	"04_confirm_dialog",
	"05_word_game",
	"06_tile_game",
	"07_match3",
}

local PROOFS = { "p1_glade", "p2_cartwheel", "p3_sipworks", "p4_foyer", "p5_wardrobe" }

--[[ ── WHAT COUNTS AS A FINDING: EVERYTHING THE SOLVER SAYS ───────────────────

	There is no filter here any more, and its absence is the point.

	This sweep used to grep the findings for the literal `"on the main axis"`, and
	later for `"on the cross axis"` beside it. That is the "check that proves
	nothing" class the gate-integrity sweep exists to catch, one level up: the
	instrument could only ever bite on the defect shapes somebody had remembered to
	spell out in this file, so every diagnostic the solver learned afterwards was
	structurally invisible here on the day it shipped. Two whole classes were, when
	this was measured on 2026-08-13:

	  * the ZSTACK OVERLAP finding ("this child overflows its zstack by NxNpx") —
	    191 findings across eight surfaces, invisible since 2026-08-02;
	  * the LYING `itemExtent` finding ("...than the slot it is windowed into") —
	    184 findings across three surfaces, invisible from the hour it was written,
	    and its own design note says so.

	...plus the collapsed-content-box and composition-fallback lines. 393 of the
	697 findings this corpus produces could not fail this file.

	So the rule is now the one the rest of the repo already holds a surface to —
	RascalRally's fixtures assert an EMPTY `diagnostics()`, and the perf lab refuses
	to mount with one: **a swept surface produces no solver findings at all**,
	except the enumerated waivers below. Nothing has to be added here when the
	solver learns a new sentence, which is the only version of this check that
	cannot rot back into the defect it was built to fix.
]]

-- A finding's CLASS, derived from the message rather than declared beside it: the
-- numbers and quoted names blanked out, cut at a word boundary. It exists so that
-- two DIFFERENT defects at one node cannot share one waiver — `perf_capture`'s
-- Roster row is both too tall for its declared slot and too wide for its zstack,
-- and a single waiver pardoning both would be a ceiling nobody measured. Deriving
-- it (rather than listing classes) is what keeps a new diagnostic covered for free.
local SIG_MAX = 44

local function signature(issue: string): string
	local s = string.gsub(issue, "%d+", "N")
	s = string.gsub(s, "'[^']*'", "'X'")
	if #s <= SIG_MAX then
		return s
	end
	-- cut at a SPACE, never mid-byte: these messages carry em dashes, and slicing a
	-- UTF-8 sequence in half would make the key depend on where the number landed
	return string.match(string.sub(s, 1, SIG_MAX + 1), "^(.*)%s") or string.sub(s, 1, SIG_MAX)
end

-- the MEASUREMENT out of the diagnostic: the largest px figure the message
-- carries. Every shape has one and they mean the same kind of thing — the stack
-- says "by 46px", the wrap-clamp "is 8px wider", the overlap "by 0x29px" (two
-- numbers, one per axis), the slot guard "measures 74px". A finding whose px
-- cannot be read is treated as 0 rather than skipped: it is still a finding, it
-- just cannot be compared against a ceiling.
local function findingPx(issue: string): number
	local best = 0
	for a, b in string.gmatch(issue, "(%d+)x(%d+)px") do
		best = math.max(best, tonumber(a) or 0, tonumber(b) or 0)
	end
	for n in string.gmatch(issue, "(%d+)px") do
		best = math.max(best, tonumber(n) or 0)
	end
	return best
end

-- KEYED SIBLINGS ARE ONE DEFECT, NOT SIXTEEN. p5_wardrobe's catalog renders the
-- same item card sixteen times under `Items/[cinder-hood]/cinder-hood`; card_rail
-- renders seven `W/[c3]/Row/Card`. Waiving each generated path separately would
-- turn one wrong constant into sixteen lines of to-do list and would go stale the
-- moment a fixture's data changed, so a path is normalised: a `[key]` segment
-- becomes `[*]`, and a segment that merely RESTATES the key it sits under becomes
-- `*`. Nothing else is collapsed — the shape of the tree above the item is exact.
--
-- "RESTATES" IS CONTAINMENT, NOT EQUALITY (2026-08-13, when the zstack-overlap
-- class became visible here): a Table row composes its actions wrapper as
-- `[m1@0]/RowActions-m1` and p2_cartwheel names its tiles `[120]/Tile120`, so the
-- equality test collapsed neither and one wrong constant would have arrived as six
-- and four identical waiver lines. The test is the key's leading word, which is
-- the part a composed name borrows; a segment that merely sits under a key it does
-- not mention (`[c1]/Row`) is still exact.
local function normalizePath(path: string): string
	local out: { string } = {}
	local prevKey: string? = nil
	for segment in string.gmatch(path, "[^/]+") do
		local key = string.match(segment, "^%[(.*)%]$")
		local restates = prevKey ~= nil
			and (
				segment == prevKey
				or string.find(segment, string.match(prevKey :: string, "^%w+") or "\0", 1, true) ~= nil
			)
		if key ~= nil then
			table.insert(out, "[*]")
			prevKey = key
		elseif restates then
			table.insert(out, "*")
			prevKey = nil
		else
			table.insert(out, segment)
			prevKey = nil
		end
	end
	return "/" .. table.concat(out, "/")
end

--[[ ── THE WAIVER LIST ────────────────────────────────────────────────────────

	Turning the axis on reddened 35 places across the showcase, in one commit,
	none of them in files this mission could touch. A permanently-red always-on
	check is worse than none — it teaches people to skim past the suite, which is
	precisely how the nine device bugs shipped — so the axis lands GREEN over an
	ENUMERATED list of what it found, and every entry is a to-do with a
	measurement on it rather than a shrug.

	The rules this list is under, all four of which are the reason it cannot rot:

	  1. A WAIVER NAMES THE SMALLEST PREFERENCE THE DEFECT WAS MEASURED AT, and a
	     waiver recorded from +4 or later DOES NOT APPLY AT +0. The pre-axis
	     contract — "this surface is clean at the default preference" — is exactly
	     as strong as it was: a finding at +0 fails unless its own waiver says the
	     defect is there at +0.
	     `since = 0` is that admission, and it is a record, never a pardon. Every
	     one of them belongs to a class this sweep was structurally BLIND to before
	     2026-08-13 (below), so none of them is a contract that was ever green.
	     `DEFAULT_WAIVERS` counts them and the case at the bottom pins the count:
	     a new +0 waiver cannot be slipped in without changing that number on
	     purpose.
	  2. A WAIVER IS A CEILING, NOT A PARDON. `px` is the largest px figure the
	     finding carried anywhere in the cross product on 2026-08-13 and `since` is
	     the smallest preference that reports it. A finding that exceeds the
	     ceiling, or that appears at a SMALLER preference than recorded, fails: the
	     defect got worse, which is a regression even inside a known defect.
	  3. A WAIVER THAT NEVER FIRES FAILS TOO (the case at the bottom of this file).
	     When somebody fixes one of these, the suite tells them to delete the line
	     — so the list can only ever shrink, and "51" is a number that means
	     something rather than a decoration.
	  4. A WAIVER IS KEYED BY THE FINDING'S CLASS AS WELL AS ITS NODE (`sig`, the
	     derived signature above). `perf_capture`'s Roster row and `card_rail`'s
	     card each carry TWO different defects at one path; one line covering both
	     would have been a ceiling measured on the wrong one.

	`kind` is the triage class (docs/plans/swiftui-parity-round3.md carries the
	full list with the per-view/per-preference detail):
	  * fixed-px-vs-text  — a px extent fixed against content that is not fixed
	                        (`docs/lessons/luauui-fixed-px-heights.md`)
	  * row-cannot-shrink — a row of labels/controls wider than the screen with
	                        nothing allowed to shrink. NOTE: not ONE of these
	                        carries the solver's "every shrinkable child is already
	                        at its floor" suffix, so every one of them is still
	                        repairable by authoring (a shrinkWeight, a ViewThatFits
	                        rung, a wrap) rather than blocked on the framework
	  * page-not-scrollable — a whole surface taller than a short canvas, usually
	                        640x320, with no page scroller
	  * wrap-clamp        — a hwrap line clamping a child it could not fit
	  ...and the four the 2026-08-13 widening added, none of which this file could
	  see before it:
	  * layer-overlap     — a ZStack child measured bigger than the stack. Nothing
	                        clips a ZStack, so it paints over its neighbour
	  * lying-itemExtent  — a `newVirtualList` row whose content is taller than the
	                        `itemExtent` the consumer declared. NOTE: the overlap
	                        finding's advice (a `minMax` FLOOR rather than a fixed
	                        CAP) is exactly the WRONG repair here — a windowed row's
	                        extent has to stay ONE number, so the repair is to
	                        recompute that number from the facts the cell reads, or
	                        to cap the cell's content (`lineLimit`)
	  * collapsed-box     — padding won: the content box is 0px on an axis and
	                        nothing inside the node can draw at all
	  ...and the one the degrade cascade adds (ruling 1, recorded 2026-08-14):
	  * cascade-floor     — the OPPOSITE of `row-cannot-shrink`, and the reason the
	                        two are not one class. The row DID run the cascade —
	                        compact form, truncation, ellipsis — every shrinkable
	                        child is at its floor, and the box cropped the residual
	                        at its own edge. The solver says so in the finding's own
	                        suffix. There is no authoring repair left inside the
	                        row: the fix is a wider box, a smaller authored floor,
	                        or content the row does not carry
	...and NOT `declared-fallback` any more (ruling 8, 2026-08-14): a
	`UI.Composition` showing the fallback it declared is the framework doing what
	the author told it to, so the solver marks that finding `designed = true` and
	the collector skips it before it can reach this list at all. It is a permanent
	exclusion, not a waiver: there is no ceiling to breach and no line to delete.
]]
type Waiver = {
	surface: string,
	variant: string,
	node: string,
	sig: string,
	px: number,
	since: number,
	kind: string,
	where: string,
}

local WAIVERS: { Waiver } = {
	{
		surface = "row_actions",
		variant = "vlist",
		node = "/MailActions/VListWhen/then/VListPane/VList/Canvas/W/[*]/Row/RowBody",
		sig = "newVirtualList 'X' declares itemExtent = N,",
		px = 249,
		since = 0,
		kind = "lying-itemExtent",
		where = "every view @ +0/+4/+10/+14 (six rows, one template) — `ROW_HEIGHT = 84` is a constant against a three-line cell that wraps: 88px already at +0 on both portrait phones, 99px at ten-foot, 249px at +14 on 320x640",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferBar",
		sig = "content overflows this hstack by Npx on the",
		px = 198,
		since = 4,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +4/+10/+14",
	},
	{
		surface = "virtual_list_native",
		variant = "-",
		node = "/VLNative",
		sig = "content overflows this vstack by Npx on the",
		px = 113,
		since = 4,
		kind = "page-not-scrollable",
		where = "320x640/640x320/compact-portrait/compact-landscape @ +4/+10/+14",
	},
	{
		surface = "row_actions",
		variant = "vlist",
		node = "/MailActions/VListWhen/then/VListPane",
		sig = "content overflows this vstack by Npx on the",
		px = 109,
		since = 4,
		kind = "fixed-px-vs-text",
		where = "320x640/640x320/compact-landscape @ +4/+10/+14",
	},
	{
		surface = "sponsor_list",
		variant = "-",
		node = "/ListLab/Body/Controls",
		sig = "content overflows this hstack by Npx on the",
		px = 95,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +10/+14",
	},
	{
		surface = "adaptive_controls",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/Legend",
		sig = "content overflows this hstack by Npx on the",
		px = 92,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/640x320/compact-portrait/compact-landscape @ +10/+14",
	},
	{
		surface = "theme_authoring",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/Legend",
		sig = "content overflows this hstack by Npx on the",
		px = 92,
		since = 10,
		kind = "row-cannot-shrink",
		where = "the same Hud fixture as adaptive_controls, under the theme package",
	},
	{
		surface = "07_match3",
		variant = "-",
		node = "/Match3/Page/Stats",
		sig = "content overflows this hstack by Npx on the",
		px = 82,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +10/+14 — the device-bug round's own ViewThatFits ladder runs out of rungs at +10",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main/ListZone/Rows",
		sig = "this child overflows its zstack by NxNpx and",
		px = 81,
		since = 0,
		kind = "layer-overlap",
		where = "640x320/compact-landscape @ +0/+4/+10/+14 — the list is taller than the zone it is layered into",
	},
	{
		surface = "variable_extents",
		variant = "-",
		node = "/VariableExtents",
		sig = "content overflows this vstack by Npx on the",
		px = 68,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320 @ +10/+14 and compact-phone-landscape @ +14 — the title, the WRAPPING control row (`UI.Toggle` is a full-width row control, so it takes a wrap line to itself and the four size chips take one or two more) and the two-line status measure 268px of a 200px box at +14, with the list already at ZERO. This surface's two real defects are FIXED rather than waived: the row extents now derive from the live text facts (372 findings) and the window is the solved pane rather than a 210px reserve",
	},
	{
		surface = "card_rail",
		variant = "-",
		node = "/CardRail/RailPane/Rail/Canvas/W/[*]/Row/Card",
		sig = "content overflows this vstack by Npx on the",
		px = 68,
		since = 10,
		kind = "fixed-px-vs-text",
		where = "640x320/compact-landscape @ +10/+14 — the fixed card plate",
	},
	{
		surface = "sponsor_billboard",
		variant = "-",
		node = "/BillboardLab",
		sig = "content overflows this vstack by Npx on the",
		px = 64,
		since = 4,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +4/+10/+14",
	},
	{
		surface = "sponsor_toast",
		variant = "-",
		node = "/ToastLab/Stage/Beneath",
		sig = "this child overflows its zstack by NxNpx and",
		px = 63,
		since = 0,
		kind = "layer-overlap",
		where = "640x320/compact-landscape @ +0/+4/+10/+14 — the stage's beneath layer outgrows the stage",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Middle/ContentHost/HomeWhen/then/HomeBody/FeedPage/Sections/[*]/Body/Header",
		sig = "content overflows this hstack by Npx on the",
		px = 52,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +10/+14 (four sections, one template)",
	},
	{
		surface = "perf_capture",
		variant = "-",
		node = "/PerfCapture/Body/Split/Roster/Canvas/W/[*]/Row/Row",
		sig = "newVirtualList 'X' declares itemExtent = N,",
		px = 50,
		since = 10,
		kind = "lying-itemExtent",
		where = "console-ten-foot @ +10/+14 — declares itemExtent = 44, the row measures 50. Pre-existing and already named in docs/plans/swiftui-parity-round3.md",
	},
	{
		surface = "drag_session",
		variant = "-",
		node = "/DragLab",
		sig = "content overflows this vstack by Npx on the",
		px = 46,
		since = 4,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +4/+10/+14",
	},
	{
		surface = "virtual_list_native",
		variant = "-",
		node = "/VLNative/VL/Canvas/W/[*]/Row/Label",
		sig = "newVirtualList 'X' declares itemExtent = N,",
		px = 46,
		since = 10,
		kind = "lying-itemExtent",
		where = "console-ten-foot @ +10/+14 — declares itemExtent = 36, the row measures 46: the ten-foot type scale is part of the geometry",
	},
	{
		surface = "authoring",
		variant = "-",
		node = "/AuthoringScreen",
		sig = "content overflows this vstack by Npx on the",
		px = 43,
		since = 4,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +4/+10/+14",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Middle/ContentHost/HomeWhen/then/HomeBody/TabRow",
		sig = "content overflows this hstack by Npx on the",
		px = 43,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +10/+14",
	},
	{
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane/MailTable/Main",
		sig = "content overflows this vstack by Npx on the",
		px = 36,
		since = 10,
		kind = "fixed-px-vs-text",
		where = "640x320/compact-landscape @ +10/+14",
	},
	{
		surface = "sponsor_list",
		variant = "-",
		node = "/ListLab/Body/Rows/Canvas/W/[*]/Row/Card/Labels",
		sig = "content overflows this vstack by Npx on the",
		px = 35,
		since = 10,
		kind = "fixed-px-vs-text",
		where = "320x640/compact-portrait @ +10/+14 — the row-height memo caps the detail at TWO caption lines; at +10 the detail needs three",
	},
	{
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[*]/*/Content/Row/Cells/Cell-from/Value",
		sig = "this child overflows its zstack by NxNpx and",
		px = 32,
		since = 0,
		kind = "layer-overlap",
		where = "every view @ +0/+4/+10/+14 (six rows, one template) — the from-cell's own text is taller than the cell it is layered in",
	},
	{
		surface = "sponsor_motion",
		variant = "-",
		node = "/MotionLab/Main/StageColumn/WashRow/WashLabel",
		sig = "this child overflows its zstack by NxNpx and",
		px = 28,
		since = 10,
		kind = "layer-overlap",
		where = "four phone views @ +10/+14",
	},
	{
		surface = "scroll_host",
		variant = "-",
		node = "/ScrollHost",
		sig = "content overflows this vstack by Npx on the",
		px = 26,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +10/+14",
	},
	{
		surface = "async_images",
		variant = "-",
		node = "/AsyncImages",
		sig = "content overflows this vstack by Npx on the",
		px = 25,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +10/+14",
	},
	{
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane",
		sig = "content overflows this vstack by Npx on the",
		px = 25,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +10/+14",
	},
	{
		surface = "03_settings_sync",
		variant = "-",
		node = "/Settings/Page/State",
		sig = "content overflows this vstack by Npx on the",
		px = 24,
		since = 4,
		kind = "fixed-px-vs-text",
		where = "compact-portrait 359x718 @ +4 ONLY — clean at +10 and +14, the non-monotone cell that makes an extremes-only sweep unsafe",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Catalog/CatalogCol/Items/PickedWhen/then/Picked/PickedGrid/Items/[*]/*",
		sig = "content overflows this hstack by Npx on the",
		px = 24,
		since = 4,
		kind = "fixed-px-vs-text",
		where = "six of the eight views @ +4/+10/+14 (non-monotone at 640x320: +4 and +14, not +10)",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Catalog/CatalogCol/Items/PickedWhen/then/Picked/PickedGrid/Items/[*]/*/Col/Meta",
		sig = "content overflows this hstack by Npx on the",
		px = 24,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/console-ten-foot @ +10/+14",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Catalog/CatalogCol/Items/RestWhen/then/Rest/RestGrid/Items/[*]/*",
		sig = "content overflows this hstack by Npx on the",
		px = 24,
		since = 4,
		kind = "fixed-px-vs-text",
		where = "six of the eight views @ +4/+10/+14 (twelve generated cards, one template)",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Catalog/CatalogCol/Items/RestWhen/then/Rest/RestGrid/Items/[*]/*/Col/Meta",
		sig = "content overflows this hstack by Npx on the",
		px = 24,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/console-ten-foot @ +10/+14",
	},
	{
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[*]/*/Content/Row/Cells/Cell-subject/Value",
		sig = "this child overflows its zstack by NxNpx and",
		px = 24,
		since = 10,
		kind = "layer-overlap",
		where = "compact-portrait/320x640 @ +10/+14 (six rows, one template) — the same cause as the from-cell above, one preference later",
	},
	{
		surface = "perf_capture",
		variant = "-",
		node = "/PerfCapture",
		sig = "content overflows this vstack by Npx on the",
		px = 23,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +10/+14",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main/ListZone/Chevrons/ChevBottom/Glyph",
		sig = "this child overflows its zstack by NxNpx and",
		px = 23,
		since = 0,
		kind = "layer-overlap",
		where = "every view @ +0/+4/+10/+14 — a fixed chevron plate holding a glyph whose box is not fixed",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main/ListZone/Chevrons/ChevTop/Glyph",
		sig = "this child overflows its zstack by NxNpx and",
		px = 23,
		since = 0,
		kind = "layer-overlap",
		where = "every view @ +0/+4/+10/+14 — the twin of ChevBottom, same plate",
	},
	{
		surface = "perf_capture",
		variant = "-",
		node = "/PerfCapture/Body/Split/Roster/Canvas/W/[*]/Row/Row",
		sig = "this child overflows its zstack by NxNpx and",
		px = 20,
		since = 14,
		kind = "layer-overlap",
		where = "320x640 @ +14 — 20px on the CROSS axis, which is the axis the slot guard deliberately leaves to this finding",
	},
	-- CLOSED 2026-08-14 by director ruling 1 (the degrade cascade). This entry
	-- recorded `/ProgressRing/Page/Dots` overflowing 20px at +14 on 320x640, kind
	-- `row-cannot-shrink` — and that kind is the ruling's own subject. The spinner
	-- row's label declares `shrinkWeight = 1` (src/controls/progress_view.luau), so
	-- the row runs the cascade; before the ruling its floor stopped at the label's
	-- longest word and the remaining deficit was simply not absorbed. It now
	-- descends to the ellipsis rung, the row fits, and the finding no longer fires
	-- anywhere in the sweep — which is what this list exists to notice.
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Middle/ContentHost/HomeWhen/then/HomeBody",
		sig = "content overflows this vstack by Npx on the",
		px = 16,
		since = 4,
		kind = "page-not-scrollable",
		where = "640x320 ONLY @ +4/+10/+14",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Middle/ContentHost/HomeWhen/then/HomeBody/FeedPage",
		sig = "content box collapses to Npx on y: padding N",
		px = 16,
		since = 0,
		kind = "collapsed-box",
		where = '640x320/compact-landscape @ +0/+4/+10/+14 — 8+8 of padding on a 16px height, so nothing inside the feed page can draw. Recorded as owed on 2026-08-12 (device-bug round, "found and NOT fixed") and never re-verified until now',
	},
	{
		surface = "sponsor_toast",
		variant = "-",
		node = "/ToastLab",
		sig = "content overflows this vstack by Npx on the",
		px = 16,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320 ONLY @ +10/+14",
	},
	{
		surface = "card_rail",
		variant = "-",
		node = "/CardRail/RailPane/Rail/Canvas/W/[*]/Row/Card",
		sig = "content box collapses to Npx on y: padding N",
		px = 15,
		since = 14,
		kind = "collapsed-box",
		where = "640x320 @ +14 (seven cards, one template) — the same fixed card plate as the row above, now with no room left for its own padding",
	},
	{
		surface = "sponsor_avatars",
		variant = "-",
		node = "/AvatarLab",
		sig = "content overflows this vstack by Npx on the",
		px = 12,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320 ONLY @ +10/+14",
	},
	{
		surface = "scroll_host",
		variant = "-",
		node = "/ScrollHost/List",
		sig = "content box collapses to Npx on y: padding N",
		px = 11,
		since = 4,
		kind = "collapsed-box",
		where = "640x320/compact-landscape @ +4/+10 and NOT +14 — another non-monotone cell: the page reflows at +14 and hands the list its padding back",
	},
	{
		-- THE NEGATIVE CONTROL THIS AXIS WAS BUILT AROUND. Reported independently
		-- by the reference agent on 2026-08-13, pre-existing, and reproduced here
		-- the first time the sweep ran with the axis on. English copy at 320x640
		-- is the cell this corpus reaches it in; the same bar overflows by 33/58px
		-- at 390x844 under the 1.4x `xa` locale, which is the locale axis this file
		-- does not sweep.
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/TopBar",
		sig = "content overflows this hstack by Npx on the",
		px = 10,
		since = 14,
		kind = "row-cannot-shrink",
		where = "320x640 ONLY @ +14",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main",
		sig = "content overflows this vstack by Npx on the",
		px = 8,
		since = 14,
		kind = "page-not-scrollable",
		where = "320x640 ONLY @ +14",
	},
}

local WAIVER_BY_KEY: { [string]: Waiver } = {}
local WAIVER_MATCHED: { [string]: boolean } = {}

local function waiverKey(surface: string, variant: string, node: string, sig: string): string
	return `{surface}|{variant}|{node}|{sig}`
end

-- ...and the count of waivers that admit a defect at the DEFAULT preference (rule
-- 1). Every one is a finding class this sweep was blind to until 2026-08-13, so
-- none of them is a green contract being surrendered; the number is pinned at the
-- bottom of the file so a new one is a decision rather than a slipped line.
local DEFAULT_WAIVERS = 0

for _, waiver in WAIVERS do
	local key = waiverKey(waiver.surface, waiver.variant, waiver.node, waiver.sig)
	assert(WAIVER_BY_KEY[key] == nil, `duplicate waiver for {key}`)
	WAIVER_BY_KEY[key] = waiver
	if waiver.since == 0 then
		DEFAULT_WAIVERS += 1
	end
end

--[[ ── THE THEME LEDGER ───────────────────────────────────────────────────────

	The themed passes are matched against their OWN list, never against the neutral
	one above, and that separation is deliberate rather than tidy: a neutral
	waiver's `px` is a ceiling MEASURED ON STUDIO NEUTRAL, and letting it pardon the
	same node under Pixel Quest would be a ceiling nobody measured — the exact
	mistake rule 4 of the list above exists to prevent, one axis over. So a themed
	finding needs a themed row, even where the neutral list already names its node.

	The rules are the same three, plus one the theme axis needs:
	  * `px` is a CEILING — a themed finding above it fails;
	  * `since` is the smallest preference it was measured at — earlier fails;
	  * a row that fires NOWHERE fails, so the ledger can only shrink;
	  * `packages` names every package that reports it. A finding under a package
	    NOT on that list fails, because "Parchment does this too now" is a
	    regression even inside a known defect.

	`node` may carry a `*` inside a segment (`key_*`, `Row_*`). A run of siblings
	that carry one defect is one row — the same judgement `normalizePath` already
	makes for `[key]` children, made explicitly for fixtures that name their
	children by hand (05_word_game's 26 keyboard keys, p2_cartwheel's 11 rail rows).
	A segment that IS `[*]` or `*` stays literal: those two are normalizePath's own
	output, not a wildcard somebody wrote.
]]
local theme_ledger = require("./lib/theme_sweep_ledger")

local THEME_MATCHED: { [number]: boolean } = {}
-- exact rows by key, and the globbed ones as a list (there are few, and they are
-- only consulted when the exact lookup misses)
local THEME_BY_KEY: { [string]: number } = {}
local THEME_GLOBS: { number } = {}

local function isGlob(node: string): boolean
	for segment in string.gmatch(node, "[^/]+") do
		if segment ~= "[*]" and segment ~= "*" and string.find(segment, "*", 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function globMatches(pattern: string, node: string): boolean
	local p: { string } = {}
	for segment in string.gmatch(pattern, "[^/]+") do
		table.insert(p, segment)
	end
	local n: { string } = {}
	for segment in string.gmatch(node, "[^/]+") do
		table.insert(n, segment)
	end
	if #p ~= #n then
		return false
	end
	for i, segment in p do
		if segment == "[*]" or segment == "*" or string.find(segment, "*", 1, true) == nil then
			if segment ~= n[i] then
				return false
			end
		else
			-- escape every Lua pattern magic character, then let `*` mean "any run
			-- of characters inside this segment"
			local escaped = string.gsub(segment, "([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
			if string.match(n[i], "^" .. string.gsub(escaped, "%*", ".*") .. "$") == nil then
				return false
			end
		end
	end
	return true
end

for index, row in theme_ledger.ROWS do
	if isGlob(row.node) then
		table.insert(THEME_GLOBS, index)
	else
		local key = waiverKey(row.surface, row.variant, row.node, row.sig)
		assert(THEME_BY_KEY[key] == nil, `duplicate theme-ledger row for {key}`)
		THEME_BY_KEY[key] = index
	end
end

-- the ledger row covering this finding, or nil. Exact first, then the globs.
local function themeRowFor(surface: string, variant: string, node: string, sig: string): number?
	local exact = THEME_BY_KEY[waiverKey(surface, variant, node, sig)]
	if exact ~= nil then
		return exact
	end
	for _, index in THEME_GLOBS do
		local row = theme_ledger.ROWS[index]
		if row.surface == surface and row.variant == variant and row.sig == sig and globMatches(row.node, node) then
			return index
		end
	end
	return nil
end

-- A SURFACE MAY PUBLISH ITS OWN MEASURED GEOMETRY BACK INTO ITS TREE, and the
-- frame that does it is not the frame that shows it. The showcase's picker strip
-- writes `coreSafeInsets` from `onGeometry`; the row-actions fixture's hosted list
-- takes its window from its own solved pane the same way. Both are fixed points —
-- the published value never depends on what it feeds — so a bounded settle is the
-- frame a player sees, and a screen that does NOT converge still fails here,
-- because it is still overflowing at the end of the loop.
local SETTLE_FRAMES = 3

local function settle(presenter: any)
	for _ = 1, SETTLE_FRAMES do
		presenter.refresh()
	end
end

local function world(view: any): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", view.displaySize)
	env:set("preferredInput", view.input)
	env:set("capabilities", CAPABILITIES[view.input])
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new();
	-- THE LIVE BAR THICKNESS, OPTED INTO. The fake publishes none by default —
	-- "which is WHY no headless sweep ever saw this class" (scroll_bar_measure.spec)
	-- — while the live adapter publishes `SCROLL_BAR_THICKNESS` under EVERY
	-- indicator policy (the 2026-08-12 reversal; it briefly published zero for an
	-- overlay/touch session, which is the defect in bugs/IMG_3691.jpeg, and
	-- tests/scroll_indicators.spec.luau now pins the live line itself). A sweep laid
	-- out without it is 8px wider than the device it claims to model — on every
	-- input class, not just the pointer views. See tests/scroll_window_clip.spec.luau
	-- for the half of this the reserve does NOT cover.
	(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

-- The report names the BOX as well as the overflow (lesson §11: "overflows by
-- 104px" is a symptom; the box it overflowed is what identifies the wrong
-- constant), so one failure is one measurement rather than a guessing loop — and
-- the PREFERENCE, because "only at +14" and "already at +4" are different bugs.
local function describeFinding(w: any, view: any, offset: number, finding: any): string
	local node = w.adapter.node(finding.node)
	local rect = if node ~= nil and node.rect ~= nil
		then string.format(" [box %dx%d at %d,%d]", node.rect.w, node.rect.h, node.rect.x, node.rect.y)
		else ""
	return `  {view.id} ({view.w}x{view.h}) @ preferredTextOffset +{offset}: {finding.node}{rect}\n      {finding.issue}`
end

-- A SWEEP ONLY COVERS THE CONFIGURATIONS ITS FIXTURE ACTUALLY BUILDS
-- (`the-solver-already-told-you.md` §13.1 — an LT-8 sweep mounted a Table without
-- `reorderable`, so the toolbar the header collided with did not exist in a single
-- swept row). `row_actions` is ONE screen with three surfaces behind a mode
-- signal, and the two the default mount does not build are exactly where a
-- hard-coded 336px VirtualList window was painting 245px past its pane. Any
-- fixture whose shape is chosen by a step belongs here.
local VARIANTS: { [string]: { step: string, values: { string } } } = {
	row_actions = { step = "mode", values = { "list", "table", "vlist" } },
}

-- one surface, every view, every preference (and every declared variant): collect
-- instead of stopping at the first, because the set of views a screen fails at is
-- what tells an author whether it is a width problem or a height problem — and the
-- set of PREFERENCES tells them whether it is a text problem at all.
local function sweep(kind: string, name: string, mount: (any) -> any)
	local label = `{kind} '{name}'`
	it(`{label}: the solver reports NOTHING at any swept viewport, at any text size`, function()
		local variant = VARIANTS[name]
		local problems: { string } = {}
		for _, view in VIEWS do
			local w = world(view)
			local built = mount(w)
			settle(w.presenter)
			-- `package` is nil on the neutral pass and the package's id on a themed
			-- one, and it selects WHICH list the finding is matched against — see
			-- "THE THEME LEDGER" above for why a neutral ceiling may not pardon a
			-- themed finding.
			local function collect(offset: number, variantValue: string, suffix: string, package: string?)
				if package ~= nil then
					suffix ..= `\n      [theme package = {package}]`
				end
				for _, finding in built.handle.controller.diagnostics() do
					-- A FINDING THE FRAMEWORK MARKS AS DESIGNED IS NOT A DEFECT AND IS
					-- NOT SWEPT (ruling 8, 2026-08-14). The solver files two kinds of
					-- sentence: most report something the author did not intend, and a
					-- few report the author's own instruction being followed — today
					-- exactly one, `UI.Composition` showing the fallback it declared
					-- when nothing richer is legal. That one used to sit in the waiver
					-- list below with a px ceiling, which said "a defect we tolerate,
					-- and it must not get worse" about behaviour that is simply
					-- correct; the consumer (Rascal Rally) had already excluded the
					-- identical note from its own check, so the two halves of the
					-- lockstep rule disagreed. They now read the same field, set in
					-- one place: `src/layout/solver.luau`'s composition arrange
					-- branch. This is a PERMANENT exclusion with no ceiling and no
					-- expiry — see `docs/reference/api.md` § "Findings that are not
					-- defects" for the plain-language version.
					if finding.designed == true then
						continue
					end
					local node = normalizePath(finding.node)
					local sig = signature(finding.issue)
					local key = waiverKey(name, variantValue, node, sig)
					if package ~= nil then
						-- ── THE THEMED PASS ─────────────────────────────────────────
						local index = themeRowFor(name, variantValue, node, sig)
						local row = if index ~= nil then theme_ledger.ROWS[index] else nil
						if row ~= nil and offset == 0 and row.since > 0 then
							row = nil
						end
						if row == nil then
							table.insert(problems, describeFinding(w, view, offset, finding) .. suffix)
							continue
						end
						local themedPx = findingPx(finding.issue)
						if themedPx > row.px then
							table.insert(
								problems,
								describeFinding(w, view, offset, finding)
									.. suffix
									.. `\n      ^ WORSE than the recorded ledger row: {themedPx}px against a {row.px}px ceiling`
							)
						elseif offset < row.since then
							table.insert(
								problems,
								describeFinding(w, view, offset, finding)
									.. suffix
									.. `\n      ^ EARLIER than the recorded ledger row: reported at +{offset}, recorded from +{row.since}`
							)
						elseif string.find(`,{row.packages},`, `,{package},`, 1, true) == nil then
							table.insert(
								problems,
								describeFinding(w, view, offset, finding)
									.. suffix
									.. `\n      ^ A PACKAGE THE LEDGER DOES NOT RECORD: '{package}' against '{row.packages}'`
							)
						else
							THEME_MATCHED[index :: number] = true
						end
						continue
					end
					local waiver = WAIVER_BY_KEY[key]
					-- RULE 1: a waiver recorded from +4 or later does not apply at the
					-- default preference. Only a waiver that ADMITS the defect is there at
					-- +0 (`since = 0`) covers a +0 finding.
					if waiver ~= nil and offset == 0 and waiver.since > 0 then
						waiver = nil
					end
					if waiver == nil then
						table.insert(problems, describeFinding(w, view, offset, finding) .. suffix)
						continue
					end
					local px = findingPx(finding.issue)
					if px > waiver.px then
						table.insert(
							problems,
							describeFinding(w, view, offset, finding)
								.. suffix
								.. `\n      ^ WORSE than the recorded waiver: {px}px against a {waiver.px}px ceiling`
						)
					elseif offset < waiver.since then
						table.insert(
							problems,
							describeFinding(w, view, offset, finding)
								.. suffix
								.. `\n      ^ EARLIER than the recorded waiver: reported at +{offset}, recorded from +{waiver.since}`
						)
					else
						WAIVER_MATCHED[key] = true
					end
				end
			end
			-- THE PREFERENCE IS SWUNG, NOT REMOUNTED (see the header): one mount per
			-- view, then the same live seam a player's Settings change travels
			-- through. Offset 0 is the first pass, so the pre-axis contract — "this
			-- surface is clean at the default preference, mounted fresh" — is
			-- evaluated on exactly the tree it was evaluated on before.
			local function atOffset(offset: number, package: string?)
				w.env:set("preferredTextOffset", offset)
				settle(w.presenter)
				if variant == nil then
					collect(offset, "-", "", package)
				else
					for _, value in variant.values do
						built.steps[variant.step](built, value)
						settle(w.presenter)
						collect(offset, value, `\n      [{variant.step} = {value}]`, package)
					end
				end
			end
			for _, offset in OFFSETS do
				atOffset(offset, nil)
			end
			-- ...AND THE PACKAGE IS SWUNG THE SAME WAY (see the header's theme-axis
			-- section). `themeMetrics` is the metric half of ADR-0019 §7's one
			-- transaction and the seam the theme picker itself drives, so a package
			-- lands on this already-mounted tree exactly as a player's swap would —
			-- proved equivalent to a fresh mount over the whole cross product. The
			-- neutral passes run FIRST and to completion, so the pre-theme contract is
			-- still evaluated on a tree no package has touched.
			for _, package in PACKAGES do
				w.env:set("themeMetrics", package.snapshot)
				for _, offset in themedOffsets(view) do
					atOffset(offset, package.id)
				end
			end
		end
		if #problems > 0 then
			error(
				`{label}: the solver files {#problems} unwaived finding(s) on this surface — content painting `
					.. `outside its own box, layered over its neighbour, taller than the slot it is windowed `
					.. `into, or unable to draw at all. A finding at +0 is a plain regression unless its own `
					.. `waiver records the defect from +0; a finding above +0 is either new, worse than its `
					.. `waiver, or now fires at a smaller text preference than the waiver records `
					.. `(tests/overflow_sweep.spec.luau, WAIVERS):\n{table.concat(problems, "\n")}`,
				0
			)
		end
	end)
end

local function scenarioCtx(w: any): any
	return {
		LuauUI = LuauUI,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.presenter,
		actionSystem = w.system,
		record = function() end,
		flags = {},
		geometry = function(paths: { string }): { [string]: any }
			local out: { [string]: any } = {}
			for _, path in paths do
				local node = w.adapter.node(path)
				if node ~= nil and node.rect ~= nil then
					out[path] = node.rect
				end
			end
			return out
		end,
		-- the one runner-owned seam a scenario in this list actually calls
		-- (async_images); every other engine seam is deliberately absent so the
		-- scenario takes its "degrade honestly" branch
		bindResourceTransport = function()
			return function() end
		end,
	}
end

local function present(w: any, built: any): any
	if built.handle == nil and built.screen ~= nil then
		built.handle = w.presenter.present(built.screen, built.present)
	end
	assert(built.handle ~= nil, "surface presented no screen")
	return built
end

describe("overflow sweep: gallery scenarios", function()
	for _, name in SCENARIOS do
		local module = require(`../examples/gallery/scenarios/{name}`) :: any
		sweep("scenario", name, function(w)
			return present(w, module.build(scenarioCtx(w)))
		end)
	end
end)

describe("overflow sweep: tutorial examples", function()
	for _, name in EXAMPLES do
		local module = require(`../examples/gallery/examples/{name}`) :: any
		sweep("example", name, function(w)
			return present(
				w,
				module.build(
					LuauUI,
					w.core,
					{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
				)
			)
		end)
	end
end)

describe("overflow sweep: reference proofs", function()
	for _, name in PROOFS do
		local module = require(`../examples/reference/{name}`) :: any
		sweep("proof", name, function(w)
			return present(
				w,
				module.build(
					LuauUI,
					w.core,
					{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
				)
			)
		end)
	end
end)

--[[ ── THE AXIS'S OWN CONTROL ─────────────────────────────────────────────────

	A sweep that cannot bite is worse than no sweep, and "it went green" is
	indistinguishable from "it asked nothing". This case is the axis's permanent
	mutation proof: a slot whose px height was chosen to hold its content at
	Medium, Large and Larger and NOT at Largest — the fixed-px-vs-text class in
	three lines — mounted through the same world and settled the same way as the
	surfaces above.

	THE ARITHMETIC IS THE POINT. Studio Neutral's `body` role is 16px at a 1.2
	line-height, and the preference is ADDITIVE, so one line box is 20px at +0,
	24px at +4, 32px at +10 and 36px at +14. Three lines: 60 / 72 / 96 / 108.
	A 102px slot therefore has 6px to spare at Larger and is 6px short at Largest,
	and the two negative controls are both real:
	  * at +0 the collector finds NOTHING — which is exactly what the pre-axis
	    sweep did on all 35 real findings above, and is why they survived;
	  * at +14 it finds this slot, by 6px.
]]
describe("overflow sweep: the text-size axis bites", function()
	it("AXIS CONTROL: a slot sized for Larger is SILENT at +0/+4/+10 and REPORTED at +14", function()
		local view = { id = "control", w = 400, h = 800, displaySize = "Medium", input = "KeyboardAndMouse" }
		local w = world(view)
		local screen = UI.Screen({
			id = "AxisControl",
			children = {
				UI.VStack({
					id = "Slot",
					height = { type = "fixed", px = 102 },
					gap = 0,
					children = {
						UI.Text({ id = "L1", text = "Ready", textSize = "body" }),
						UI.Text({ id = "L2", text = "Steady", textSize = "body" }),
						UI.Text({ id = "L3", text = "Go", textSize = "body" }),
					},
				}),
			},
		})
		local handle = w.presenter.present(screen)
		local function findings(): { any }
			local out: { any } = {}
			for _, finding in handle.controller.diagnostics() do
				table.insert(out, finding)
			end
			return out
		end

		local reported: { [number]: { any } } = {}
		for _, offset in OFFSETS do
			w.env:set("preferredTextOffset", offset)
			settle(w.presenter)
			reported[offset] = findings()
		end

		-- the NEGATIVE control: every preference the slot was sized for is silent,
		-- and +0 is the one the pre-axis sweep ran
		for _, offset in { 0, 4, 10 } do
			if #reported[offset] > 0 then
				error(
					`the axis control reported at +{offset}, where it must be silent: `
						.. `{reported[offset][1].node} — {reported[offset][1].issue}`,
					0
				)
			end
		end

		-- ...and the mutation itself: the largest preference does not fit
		local largest = reported[OFFSETS[#OFFSETS]]
		expect(#largest).toBe(1)
		expect(largest[1].node).toBe("/AxisControl/Slot")
		expect(findingPx(largest[1].issue)).toBe(6)
	end)
end)

--[[ ── THE BREADTH'S OWN CONTROL ──────────────────────────────────────────────

	The axis control above proves this file can see a MAIN-AXIS overflow at a large
	text size. It could see nothing else until 2026-08-13, and "it went green" is
	indistinguishable from "it asked nothing" — so the two classes the widening let
	in get a permanent control of their own, mounted through the same world and read
	the same way the surfaces are.

	THE THIRD ASSERTION IS THE NEGATIVE CONTROL, and it is the whole point: neither
	message contains "on the main axis" or "on the cross axis", so the filter this
	file used to carry would have passed BOTH of these screens green. If somebody
	ever puts a phrase list back, this case says so on that run.
]]
describe("overflow sweep: the widened breadth bites", function()
	it("BREADTH CONTROL: a layered overlap and a lying itemExtent both reach the collector", function()
		local view = { id = "control", w = 400, h = 800, displaySize = "Medium", input = "KeyboardAndMouse" }
		local w = world(view)
		-- a fixed 40px slot holding a 60px child: nothing clips a ZStack, so the
		-- child paints 20px over whatever sits beside it
		local overlap = UI.ZStack({
			id = "Overlap",
			width = { type = "fixed", px = 40 },
			height = { type = "fixed", px = 40 },
			children = {
				UI.Box({
					id = "Big",
					width = { type = "fixed", px = 60 },
					height = { type = "fixed", px = 60 },
					surface = "accent",
				}),
			},
		})
		-- ...and a windowed list whose consumer declared an extent its own row does
		-- not honour: the row content is two 20px body lines in a 24px slot
		local rows = {}
		for i = 1, 4 do
			table.insert(rows, { id = `r{i}` })
		end
		local list = LuauUI.newVirtualList(LuauUI, w.core, {
			id = "Lying",
			rows = w.core:signal(rows),
			key = function(item: any)
				return item.id
			end,
			itemExtent = 24,
			viewportExtent = 200,
			cell = function(item: any)
				return UI.VStack({
					id = "Cell",
					gap = 0,
					children = {
						UI.Text({ id = "A", text = `row {item.id}`, textSize = "body" }),
						UI.Text({ id = "B", text = "and its second line", textSize = "body" }),
					},
				})
			end,
			env = w.env,
		})
		local handle = w.presenter.present(UI.Screen({
			id = "BreadthControl",
			children = { overlap, list.blueprint },
		}))
		settle(w.presenter)

		local byNode: { [string]: string } = {}
		for _, finding in handle.controller.diagnostics() do
			byNode[finding.node] = finding.issue
		end

		local layered = byNode["/BreadthControl/Overlap/Big"]
		assert(layered ~= nil, "the layered overlap filed no finding at all — the control is not exercising it")
		expect(string.find(layered, "overflows its zstack", 1, true) ~= nil).toBe(true)
		expect(findingPx(layered)).toBe(20)

		local lying: string? = nil
		for node, issue in byNode do
			if string.find(issue, "than the slot it is windowed into", 1, true) ~= nil then
				lying = issue
				expect(string.find(node, "/Lying/", 1, true) ~= nil).toBe(true)
			end
		end
		assert(lying ~= nil, "the lying itemExtent filed no finding at all — the control is not exercising it")

		-- THE NEGATIVE CONTROL: the phrase list this file used to grep for appears in
		-- NEITHER message, so the old filter passed both of these green
		for _, issue in { layered, lying :: string } do
			expect(string.find(issue, "on the main axis", 1, true) == nil).toBe(true)
			expect(string.find(issue, "on the cross axis", 1, true) == nil).toBe(true)
		end
	end)
end)

--[[ ── THE WAIVER LIST IS A TO-DO LIST ────────────────────────────────────────

	Registered last on purpose: it reads what the sweep above matched. A waiver
	that fired nowhere means somebody fixed that surface (or moved the node, or
	renamed the fixture) and the line is now fiction — the one failure mode a
	baseline file has, and the reason baselines rot into "known failures we no
	longer read". The suite says so on the same run that fixes it.
]]
describe("overflow sweep: the accessibility waiver list", function()
	it("every waived finding still fires — a stale waiver is a fixed defect, delete the line", function()
		local stale: { string } = {}
		for _, waiver in WAIVERS do
			local key = waiverKey(waiver.surface, waiver.variant, waiver.node, waiver.sig)
			if WAIVER_MATCHED[key] ~= true then
				table.insert(
					stale,
					`  {waiver.surface} [{waiver.variant}] {waiver.node}\n`
						.. `      "{waiver.sig}"\n`
						.. `      recorded {waiver.px}px from +{waiver.since} ({waiver.kind}; {waiver.where})`
				)
			end
		end
		if #stale > 0 then
			error(
				`{#stale} waiver(s) no longer fire anywhere in the sweep. If the surface was fixed, `
					.. `delete the entry (that is the point of the list); if the node moved or the solver `
					.. `reworded the finding, re-record it:\n{table.concat(stale, "\n")}`,
				0
			)
		end
		-- ...and the list is not allowed to quietly grow without anybody noticing
		-- either: 35 is what turning the TEXT-SIZE axis on found on 2026-08-13, and
		-- 51 is what removing the message filter found the same day (the four classes
		-- this file could never see). Every addition is a decision somebody has to
		-- make on purpose.
		expect(#WAIVERS <= 51).toBe(true)
		-- ...and rule 1's own guard: seven of the 51 admit a defect at the DEFAULT
		-- preference, every one of them in a class this file was blind to. A new one
		-- means a +0 contract was surrendered, which is never a number to nudge.
		expect(DEFAULT_WAIVERS).toBe(7)
	end)
end)

--[[ ── THE THEME AXIS'S OWN CONTROL ────────────────────────────────────────────

	The same discipline the two controls above are under, for the axis added on
	2026-08-14: "it went green" is indistinguishable from "it asked nothing", and a
	theme axis that cannot see a theme-only defect is the instrument defect it was
	built to remove, one level up.

	THE SCREEN IS THE O-23 SHAPE, REDUCED TO ARITHMETIC. A 120px row holding five
	4px boxes with the theme's own `l` step between them — the shape every one of
	this framework's indicators has, where the pieces are fixed and the SPACING
	comes from the package. Studio Neutral's `l` is 24, so the row needs 20 + 4x24 =
	116 and fits with 4px to spare; Glossy Touch's is 28, so the same row needs 132
	and is 12px over. Nothing about the screen changes between the two passes except
	the one `env:set` the sweep above makes.

	The boxes carry no `surface`, deliberately: a surfaced box is a chrome slot, and
	under a skinning package it files a `contentInsets could not be spent` finding
	of its own — which would make this control pass for a reason that has nothing to
	do with the arithmetic it is testing.

	THE FIRST ASSERTION IS THE NEGATIVE CONTROL and it is the whole point: the
	neutral pass must be SILENT. A control that fires under both themes would prove
	the sweep can see an overflow, which the axis control above already proves, and
	would say nothing at all about whether the package ever reached the solver.
]]
--[[ ── STANDING RULE 4, ASKED OF EVERY SURFACE RATHER THAN ONE AT A TIME ───────

	Round 3's standing rule 4: "every gap closure ships its showcase demo,
	registered in `scenarios/init.luau` ORDER **and** `demo_picker.DEMOS`, swept by
	`tests/overflow_sweep.spec.luau` at all viewports, and verified across every
	shipped theme". Three of those four halves were enforced by HAND, once per
	capability: `tests/row_capabilities_scenario.spec.luau` reads this file's source
	and asserts its own name is in it, and the `row-capability-optouts` gate row
	carries twelve suite greps, not one of which asks whether the surface exists.

	That is rule 2 of the same brief — general mechanism, never a special case — and
	the special case has the failure mode you would expect: it protects the ONE
	capability whose author remembered to write it, and the next gap closure ships
	with no such line and nothing notices. A surface absent from `SCENARIOS`
	produces no case at all, and a missing case is indistinguishable from a passing
	one on any transcript.

	So the question is asked of the REGISTRY: every scenario a player can pick must
	be swept, and everything swept must be pickable. The two deliberate absences are
	DERIVED from what they are rather than listed by name — `examples` and the five
	`ref_*` scenarios are thin delegations that resolve their real module through a
	replicated folder, so this file mounts those modules directly (see the header) —
	and the check states that reasoning where it can be re-read.

	The theme half is no longer anybody's to remember: it is the axis above.
]]
describe("overflow sweep: every registered showcase surface is swept", function()
	local fs = require("@lune/fs")

	it("RULE 4: the sweep list and the scenario registry are the same set", function()
		local source = fs.readFile("examples/gallery/scenarios/init.luau")
		local orderBlock = string.match(source, "local ORDER = (%b{})")
		assert(orderBlock ~= nil, "scenarios/init.luau no longer has a `local ORDER = { ... }` block")

		local swept: { [string]: boolean } = {}
		for _, name in SCENARIOS do
			swept[name] = true
		end

		-- the delegations, derived from their own shape: `examples` mounts one of
		-- the seven tutorial examples (all seven are swept below in their own
		-- describe) and each `ref_*` mounts one of the five proofs (likewise). A
		-- sweep of the delegation would mount the same module through an engine seam
		-- this file does not have.
		local function isDelegation(name: string): boolean
			return name == "examples" or string.sub(name, 1, 4) == "ref_"
		end

		local problems: { string } = {}
		local registered: { [string]: boolean } = {}
		-- ENTRIES, NOT EVERY QUOTED STRING IN THE BLOCK. The ORDER table is heavily
		-- commented and those comments quote surface names in prose ("wrapping off"),
		-- so a bare gmatch over the block reads a sentence as a registration.
		for line in string.gmatch(orderBlock :: string, "[^\n]+") do
			local entry = string.match(line, '^%s*"([^"]+)",%s*$')
			if entry == nil then
				continue
			end
			local name = entry
			registered[name] = true
			if isDelegation(name) then
				if swept[name] then
					table.insert(
						problems,
						`'{name}' is a delegation (it resolves its real module through a replicated `
							.. `folder) and cannot be mounted here — the module it delegates to is swept directly`
					)
				end
				continue
			end
			if not swept[name] then
				table.insert(
					problems,
					`scenarios/init.luau registers '{name}' and this file's SCENARIOS does not sweep it — `
						.. `a surface with no case is indistinguishable from a passing one (standing rule 4)`
				)
			end
		end
		for _, name in SCENARIOS do
			if not registered[name] then
				table.insert(
					problems,
					`this file sweeps '{name}' and scenarios/init.luau does not register it — a surface `
						.. `no player can reach is a demo that does not exist (standing rule 4)`
				)
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)
end)

describe("overflow sweep: the theme axis bites", function()
	it("THEME CONTROL: a row that fits under Studio Neutral is REPORTED under a package", function()
		local view = { id = "control", w = 400, h = 800, displaySize = "Medium", input = "KeyboardAndMouse" }
		local w = world(view)
		local screen = UI.Screen({
			id = "ThemeControl",
			padding = 0,
			children = {
				UI.HStack({
					id = "Row",
					width = { type = "fixed", px = 120 },
					gap = "l",
					children = {
						UI.Box({ id = "B1", width = { type = "fixed", px = 4 }, height = { type = "fixed", px = 8 } }),
						UI.Box({ id = "B2", width = { type = "fixed", px = 4 }, height = { type = "fixed", px = 8 } }),
						UI.Box({ id = "B3", width = { type = "fixed", px = 4 }, height = { type = "fixed", px = 8 } }),
						UI.Box({ id = "B4", width = { type = "fixed", px = 4 }, height = { type = "fixed", px = 8 } }),
						UI.Box({ id = "B5", width = { type = "fixed", px = 4 }, height = { type = "fixed", px = 8 } }),
					},
				}),
			},
		})
		local handle = w.presenter.present(screen)
		settle(w.presenter)

		local function findings(): { any }
			local out: { any } = {}
			for _, finding in handle.controller.diagnostics() do
				table.insert(out, finding)
			end
			return out
		end

		-- the NEGATIVE control: 5x4 + 4 x a 24px `l` step = 116 in 120
		local neutral = findings()
		if #neutral > 0 then
			error(
				`the theme control reported under Studio Neutral, where it must be silent: `
					.. `{neutral[1].node} — {neutral[1].issue}`,
				0
			)
		end

		-- ...and the mutation: a package whose `m` step is wider does not fit, and
		-- the SWEEP'S OWN SEAM is what delivers it
		local glossy: any = nil
		for _, package in PACKAGES do
			if package.id == "glossy-touch" then
				glossy = package
			end
		end
		assert(glossy ~= nil, "glossy-touch is not in PACKAGES — the theme axis is not sweeping what it says")
		w.env:set("themeMetrics", glossy.snapshot)
		settle(w.presenter)

		local themed = findings()
		expect(#themed).toBe(1)
		expect(themed[1].node).toBe("/ThemeControl/Row")
		expect(findingPx(themed[1].issue)).toBe(12)
	end)
end)

--[[ ── THE THEME LEDGER IS A TO-DO LIST, AND ITS COVERAGE IS DECLARED ──────────

	Two cases, for the two ways a ledger rots.

	The first is the same rule the waiver list above is under: a row that fires
	NOWHERE is a defect somebody fixed (or a node that moved), and the suite says so
	on the run that fixes it. That is what makes 157 a number rather than a
	decoration.

	The second is the one this axis needs and the waiver list does not. A tier is a
	CHOICE about what not to look at, and the failure mode of a choice like that is
	that it stops being written down — the sweep then reads as "covered every
	theme", which is exactly the claim that was false before this axis existed. So
	the coverage is DERIVED from the code that does the sweeping, compared against
	what the header says, and PRINTED on every run. If somebody narrows the tier,
	this case fails rather than the sweep quietly asking less.
]]
describe("overflow sweep: the theme ledger", function()
	it("every ledger row still fires — a stale row is a fixed defect, delete the line", function()
		local stale: { string } = {}
		for index, row in theme_ledger.ROWS do
			if THEME_MATCHED[index] ~= true then
				table.insert(
					stale,
					`  {row.surface} [{row.variant}] {row.node}\n`
						.. `      "{row.sig}"\n`
						.. `      recorded {row.px}px from +{row.since} ({row.kind}; {row.packages})`
				)
			end
		end
		if #stale > 0 then
			error(
				`{#stale} theme-ledger row(s) no longer fire anywhere in the themed passes. If the surface `
					.. `was fixed, delete the entry (that is the point of the ledger); if the node moved or the `
					.. `solver reworded the finding, re-record it:\n{table.concat(stale, "\n")}`,
				0
			)
		end
		-- ...and the ledger is not allowed to quietly grow either. 157 is what
		-- turning the theme axis on found on 2026-08-14, over eight packages and
		-- 44 surfaces, none of it in files that mission could touch. Every addition
		-- is a decision somebody makes on purpose.
		--
		-- 146 -> 148 -> 139 ON 2026-08-14, in that order, and both moves were
		-- decisions. UP by two because the CORPUS grew: `text_degrade` and
		-- `variable_extents` were registered by two in-flight missions and swept by
		-- neither, which is what the registry case below now makes impossible, and
		-- adopting them added two surfaces to a ledger sized for 44. Then DOWN by
		-- nine, because ten of these rows were ONE package metric: Pixel Quest carved
		-- a 16px field border and left `controls.textInput.fieldHeight` at the
		-- inherited 44, so every TextField in the corpus had a zero content box under
		-- it. The ratchet is re-set to what is actually there.
		expect(#theme_ledger.ROWS <= 139).toBe(true)
	end)

	it("COVERAGE: the themed tier is what the header says it is, and says what it skips", function()
		-- what the code really sweeps, derived from the same two functions the sweep
		-- calls — never restated, or this case would pass against a narrower tier
		local sweptCells: { [string]: boolean } = {}
		local swept, skipped = 0, 0
		local skippedRows: { string } = {}
		for _, view in VIEWS do
			local offsets: { [number]: boolean } = {}
			for _, offset in themedOffsets(view) do
				offsets[offset] = true
				sweptCells[`{view.id}@{offset}`] = true
				swept += 1
			end
			for _, offset in OFFSETS do
				if not offsets[offset] then
					skipped += 1
					table.insert(skippedRows, `{view.id} ({view.w}x{view.h}) @ +{offset}`)
				end
			end
		end

		-- THE DECLARATION, and the header's claim in one place: every viewport at the
		-- default preference, plus the largest preference at the two narrowest.
		for _, view in VIEWS do
			assert(
				sweptCells[`{view.id}@0`] == true,
				`the themed tier skips {view.id} at the DEFAULT preference — a viewport changes the TREE `
					.. `(p4_foyer's NavRail exists only on desktop), so the structural pass may not be narrowed`
			)
		end
		local narrow = 0
		for _, view in VIEWS do
			if sweptCells[`{view.id}@{LARGEST}`] == true then
				narrow += 1
			end
		end
		expect(narrow).toBe(2)
		expect(#PACKAGES).toBe(8)
		expect(swept).toBe(#VIEWS + 2)

		-- ...and the part nobody is allowed to forget, printed on every run rather
		-- than left in a comment somebody stops reading (the round-3 brief's "an
		-- instrument nobody runs is a comment"). Measured on 2026-08-14 over the FULL
		-- cross product: these cells carry 16 findings this tier does not see.
		print(
			`\n  [theme axis] {#PACKAGES} packages x {swept} (viewport, preference) cells = `
				.. `{#PACKAGES * swept} themed passes per surface; 3.50x this file's cost, 224 of the 240 `
				.. `theme-only findings the full cross product reports.`
		)
		print(`  [theme axis] NOT COVERED — {skipped} (viewport, preference) cells carry no themed pass:`)
		for _, row in skippedRows do
			print(`      {row}`)
		end
		print(
			"  [theme axis] NOT COVERED — a package's SECOND theme (measured to move no geometry at all, "
				.. "so this is free on the solver and blind to every palette defect), the two `testOnly` "
				.. "packages, `ornate_gauge`/`custom_control` (control contributions, not packages), and the "
				.. "1.4x pseudo-locale, which is a second expansion axis this whole file already skips."
		)
	end)
end)
