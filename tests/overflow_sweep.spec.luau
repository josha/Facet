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
-- viewport in BOTH orientations, PLUS the 390x844 modern phone (O-19, added
-- 2026-08-15 — the row the locale defect below was measured on). Landscape is not
-- optional: B5 was landscape-only and portrait-clean, which is exactly how it
-- survived a portrait capture set.
--
-- ...at EVERY ACCESSIBILITY TEXT SIZE a player can choose (2026-08-13, below).
--
-- ...under the showcase's OWN chrome reservation. Every one of these surfaces is
-- reached in `Facet-Showcase` through the demo picker, which reserves its chip
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
-- invisible for exactly the same reason. `docs/lessons/facet-fixed-px-heights.md`
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
-- WHY THE FULL CROSS PRODUCT, AND WHAT IT COSTS. (The shape below is the one
-- measured when the preference axis landed; today it is 46 surfaces x 9 viewports
-- x 4 preferences, plus the themed and locale tiers, and what the whole file costs
-- is measured in `tests/lib/tiers.luau` rather than restated here.) 42 surfaces x
-- 8 viewports x 4
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
-- sweeps TWO LOCALES since 2026-08-15 (O-19, "THE LOCALE AXIS" below) but only on
-- the 21 surfaces that HAVE a second form: a fixture with no `copy` export and no
-- locale fact builds byte-identical text, and the coverage case names every one of
-- them rather than counting them as swept. It is the part of
-- "does this fit on a phone" that a machine can answer every time, and the floor
-- under the Studio device matrix rather than a replacement for it.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
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
	local pkg, report = entry.module.build(Facet.themes)
	assert(
		pkg ~= nil,
		`{entry.id} failed its own package gate: {report and report.errors[1] and report.errors[1].message}`
	)
	table.insert(PACKAGES, { id = entry.id, snapshot = Facet.themes.resolve(pkg, nil, {}) })
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
	-- ...and the level-picker showcase. Every row on it is a WRAPPING pair — a
	-- full-width strip beside a stepper that is a compact unit rather than two
	-- free-floating circles — so the swept cross product is the direct test of
	-- the one layout decision the fixture makes: side by side where there is
	-- room, stacked where there is not, on one declaration.
	"level_picker",
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
	-- ...and the measured-extent fixture. It is the surface with the strongest claim
	-- in this corpus — "no row can overflow its slot, because the slot IS the
	-- measurement" — so a swept cross product is the direct test of that claim
	-- rather than a check on the packaging around it: 8 viewports x 4 text
	-- preferences of rows that WRAP with no `lineLimit`, i.e. rows whose line count
	-- nobody could have declared
	"measured_extents",
	-- ...and the virtualized Table. It is the one surface in this corpus whose
	-- page CANNOT delegate its scrolling — a windowed list is defined against a
	-- viewport, so `scrolls = false` is refused beside `virtualized` — which makes
	-- the swept cross product the direct test of whether its chrome (a title, a
	-- WRAPPING four-button row and two status lines) still leaves the list a box at
	-- every viewport and text preference, rather than a check on the packaging
	"table_virtualized",
	-- ...its headered sibling `table_columns` USED TO SIT HERE, and it was swept for
	-- a real reason: A HEADER BAND IS A `minMax` FLOOR
	-- (`controls.table.headerHeight`) and it is the exact thing `table_virtualized`
	-- had to give up to fit — 77 findings, every one of them that band. That fixture
	-- was retired on 2026-08-16 (navigation-and-menus D8) when the shipped playlist
	-- tutorial gained the resizable header it existed to hold. THE HEADER IS STILL
	-- SWEPT AT EVERY VIEWPORT AND TEXT PREFERENCE — by `tests/example_readouts.spec`,
	-- which walks the tutorial examples across the same device views and the same
	-- four text offsets, and by `tests/playlist_columns.spec`, which pins the band's
	-- own geometry. This sweep's corpus is the SCENARIO registry, and the playlist is
	-- an example, so the coverage moved rather than being dropped.
	-- ...and the lazy grid. Its cells are the one thing in this corpus whose COUNT
	-- across a line is decided by a live signal, so every viewport re-divides the
	-- same offer into a different column width — and a windowed grid's declared
	-- line extent is read by the same lying-slot guard that filed 372 findings on
	-- `variable_extents`, which makes the swept cross product the direct test of
	-- whether one uniform number is genuinely enough for the cell it declares
	"virtual_grid",
	-- ...and the same control on the other axis, where the LANE axis is the HEIGHT.
	-- That is the sharper case for this sweep: on the vertical grid a squeezed lane
	-- squeezes a cell's WIDTH and text answers by truncating, while here it squeezes
	-- the HEIGHT and text has no vertical truncation to answer with — so every
	-- viewport x text-preference cell in the cross product is a direct test of
	-- whether the lane count this fixture offers survives the smallest box it gets
	"virtual_hgrid",
	-- ...and ADR-0025: the screen-anchored HUD. Its whole contract is "the zones
	-- partition the box at every size", so a swept viewport IS the feature's test
	-- rather than a check on its packaging — and the surface carries a switch that
	-- takes 200px of HEIGHT off the box, which is the case a viewport sweep would
	-- otherwise never reach
	"hud",
	-- ...and UI.Foreign (ADR-0034). Its panes are FIXED-PX boxes that cannot
	-- reflow — the framework cannot ask a foreign instance how big it would like
	-- to be, so the box is declared — sitting in a WRAPPING row beside captions
	-- that grow with the text preference. That combination (rigid boxes, growing
	-- labels, a wrap point that moves) is exactly what a swept viewport x text
	-- cross product is for, and it is the only fixture here where an overflow
	-- would be the framework's own contract failing rather than a packaging slip
	"foreign_content",
	-- ...and ADR-0028's alarm fixture. It mounts a SECOND surface at build, which
	-- is the only surface in this corpus that does — so the swept assertion here
	-- is that the declared pair stays quiet at every viewport, preference and
	-- package, and the class is one edit away from reddening this file (which is
	-- how it was proved to be visible at all)
	"surface_overlap",
	-- ...and the branch-scope fixture. Two `surface = "control"` panels stacked
	-- under a five-line readout whose longest line is a whole sentence — a
	-- Largest-preference package is where a readout that has outgrown its page
	-- shows up, and neither panel declares a height, so the sweep is the direct
	-- test of that
	"branch_scope",
	-- ...and the `sortedEntries` fixture: TWO twelve-row columns in one wrapping
	-- HStack. The wrap is what keeps the pair readable at 320px, and a package
	-- whose rows outgrow the fold turns the side-by-side into a stack — which is
	-- fine, and which only a swept viewport confirms actually happens
	"sorted_entries",
	-- ...and the time-curve fixture. Three stacked demonstrations under one page
	-- scroller — two progress bars, four labelled lanes, a growing card and three
	-- status lines whose longest is a whole sentence — which makes the swept cross
	-- product the direct test of whether the page still fits the box it is given
	-- at every viewport and preference. Its motion values are all at rest at
	-- mount, so what is swept is the surface a player first sees
	"time_curves",
	-- ...and the fade-group fixture (round-3 O-30). Two 132px plate stacks side by
	-- side where there is room and stacked where there is not, under a chip row
	-- that wraps and above the framework's own refusal sentence — a paragraph of
	-- prose the surface does not choose the length of, and which grows with every
	-- text preference. That combination (rigid plates, an AdaptiveStack that flips
	-- axis, and a growing block of copy) is what the swept cross product is for
	"canvas_group",
	-- ADR-0035: the Background Transparency fixture. Three swatches and five
	-- setting chips that wrap, plus a fixed 300px dialog card — the two shapes a
	-- 320px phone with the +14 text preference squeezes hardest
	"preferred_transparency",
	-- navigation-and-menus D3: the coach-mark fixture. It is the only surface in
	-- this corpus that presents an ANCHORED plate at build time, so the swept
	-- assertion is that a plate hung off a top-right 44px button — the placement
	-- that has to SHIFT its body left to stay on screen — stays inside the box at
	-- every viewport and preference, beside a page of readouts whose longest line
	-- is a whole paragraph the surface does not choose the length of
	"callout",
	-- navigation-and-menus D2: the five-trigger menu fixture. Five stacked cards
	-- whose subtitles are whole sentences, a segmented Idiom picker, and six
	-- readout plates under them — the shape a raised text preference stretches
	-- hardest, and the only surface in this corpus whose page is entirely prose
	-- the fixture does not choose the length of. What it deliberately does NOT
	-- sweep is an OPEN menu: a presented panel is a separate surface with its own
	-- solver run, and this sweep mounts the screen a player first sees
	"menu",
	-- ...and D5's nested tab fixture, which is here for the opposite reason: it
	-- is the only surface in this corpus with a strip that is MEANT to measure
	-- wider than the band it sits in (eight page tabs at 320px), so the swept
	-- assertion is that a deliberate overflow absorbed by a scroll host files
	-- nothing, at every viewport, preference and package — beside a bottom band
	-- and a top band that both have to fit on a 320px-tall landscape
	"tab_view",
	-- ADR-0032: the nested-instance-tree compositing showcase. Two comparison
	-- rows under one page scroller — a slider-driven fade pair and a
	-- toggle-driven rotate/scale pair, each a fixed-px cluster inside an
	-- AdaptiveStack that stacks to a column on a narrow phone — plus four
	-- caption blocks whose longest line grows with every text preference. The
	-- swept cross product is the direct test of whether that packaging holds at
	-- every viewport, at every preference, mid-turn as well as at rest
	"nested_compositing",
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

	── THE DIRECTOR'S RULING, 2026-08-15: "fix the ones that hide text; waive the
	rest" (O-21), EXECUTED TO THE END ─────────────────────────────────────────

	Answered by measurement rather than by re-reading these rows, because "does it
	paint outside its box" and "can a player still read it" are different questions
	and this list only ever recorded the first. The instrument is
	`tools/lune/triage_overflow_waivers` (run it; it names its three verdicts and
	what it refuses to count), and its output is
	`artifacts/swiftui-parity-round3/waiver-readability.txt`.

	THE LIST WENT 42 -> 31 -> 13, IN TWO ROUNDS OF THE SAME RULING. Round one fixed
	ten and measured fifteen cosmetic, leaving sixteen that still hid copy or a
	labelled control. Round two closed all sixteen: **thirteen FIXED in the fixture,
	two RECLASSIFIED because the instrument was wrong, and one — `p4_foyer`'s tab
	row — fixed a second time when the first repair was measured under the locale
	axis.** EVERY WAIVER LEFT STANDING IS NOW MEASURED COSMETIC, in the neutral pass
	and in the `xa` pass: no character and no labelled control outside the band a
	player can reach, nothing cut without a `disclose` to open it, nothing opaque
	painted over copy. That is the whole ruling discharged; what remains is a bleed
	ledger, not a to-do list.

	THE TWO INSTRUMENT DEFECTS ROUND TWO FOUND, both of which had manufactured
	"hidden text" out of nothing, and both fixed in the probe rather than argued:
	  * PAINT ORDER WAS A PATH SORT. `adapter.paths()` is sorted — alphabetically —
	    and the probe had been reading its index as "painted later". `BellZ/
	    BadgeWhen/.../Count` sorts before its sibling `BellZ/Bell` while the
	    renderer paints the badge ON TOP of the bell, so a notification count was
	    reported covered by the button it decorates. `node.z` (what `syncZOrder`
	    wrote through `adapter.setZOrder`) is the only thing entitled to the word.
	  * `surface = "plain"` WAS COUNTED AS OPAQUE. `chrome_slots.classify` returns
	    nil for it before any class rule ("AN EXPLICIT `plain` PAINTS NOTHING"), so
	    a `plain` Box is a stroke and a shape with no fill — and `sponsor_avatars`'
	    16 "covered" initials were covered by the hairline RIM drawn around them.
	  ...and one more the occlusion pass needed: a victim rect is intersected with
	  its ScrollView ancestors' windows before it is asked whether anything covers
	  it, because a row its own list has already clipped away is not on glass to be
	  covered (`/ScrollHost/List/Row10`, whose list box had collapsed).

	THE THIRTEEN FIXTURE REPAIRS, each with what a player got back:
	  p5_wardrobe        the item card's column hugged its widest LABEL, so it
	                     measured 153px inside a 133px Button content box: `Dusk
	                     Plaza` truncated at the wrong width and the whole card ran
	                     past the catalog scroller on x. `shrinkWeight` on the
	                     column and on the creator line (2 waivers + 4 locale rows)
	  p4_foyer TopBar    `minMax { min = 0 }` under the shrink pair — the one lever
	                     that outranks a one-word label's longest-word floor — so
	                     the wordmark yields instead of the bell. Bell + unread
	                     count were 2px off a 320px screen and 19px off a 390px one
	                     under `xa` (1 waiver + 1 locale row, the latter at +0)
	  sponsor_toast      stage and chrome were both `fill` against a page that was
	                     not: `Press me`, the control the fixture is ABOUT, sat 5px
	                     below the fold. The chrome is a bounded sibling scroller
	                     now (2 waivers)
	  sponsor_billboard  a `Spacer` on `fill` gives its pixels back to nobody; all
	                     four labelled controls were below the fold. The readouts
	                     scroll and take the Spacer's job (1 waiver)
	  perf_capture       the boost count shared the readout band instead of taking
	                     a second pinned line, and the roster NAME shrinks like its
	                     detail. `Boost` — the control this fixture's own injected
	                     input fault is about — was already unreachable with no
	                     fault injected (1 waiver)
	  row_actions        `VirtualList` is 243px of label and `minColumnWidth =
	                     "intrinsic"` reads the widest one, so the mode bar
	                     re-columned to two lines and took 134px of a 184px canvas;
	                     the `From` header ended 33px under the fold. Plus the hint
	                     behind the same `showHeading` the title uses, and the
	                     list's window is the pane with no row-sized floor pushing
	                     it off the bottom edge (3 waivers)
	  card_rail          the rail's cross extent is the plate's own height now —
	                     padding, two line boxes, the theme's `chromeInsets` and
	                     `chromeOutsets`, the scroll gutter — and the PAGE scrolls,
	                     which it may because the rail scrolls x. `Rally` was 61px
	                     inside a clip host on an axis that does not scroll back
	                     (2 waivers + 2 locale rows)
	  variable_extents   a sibling chrome scroller, conditional on `isShort`, and a
	                     `disclose` on the capped status line: the status was 36px
	                     below the fold and cut (1 waiver)
	  scroll_host        the title and the two region labels go where the room does
	                     — 194px of a 168px box put the BELOW-LIST MARKER, the node
	                     this fixture asserts must never move, 10px under the fold
	                     (2 waivers)
	  table_virtualized  the same sibling-scroller shape: its own waiver was right
	                     that the page cannot NEST a scroller, and a sibling is not
	                     a nest. `Last` was 10px under the fold under `xa`
	                     (1 waiver + 1 locale row)
	  sponsor_list       the two-line cap stays (uniform growth is what keeps
	                     `index x height` true) and now carries the other half of a
	                     declared truncation: `disclose` (waiver stays, cosmetic)

	WHY THE THIRTEEN THAT REMAIN ARE COSMETIC, one measured line each, all
	re-measured 2026-08-15 after every repair above:
	  03_settings_sync /Settings/Page/State  24px below a panel edge at +4 only;
	    all four labels stay on screen, uncut and uncovered
	  authoring /AuthoringScreen             the last row of validation PLATES
	    runs 9px past the fold; every label on the page is inside the band
	  drag_session /DragLab                  the draggable CARD is 4px past the
	    fold; no copy leaves the band and the card is still grabbable
	  p4_foyer .../HomeBody                  the feed page's content box collapses
	    on a short landscape, and all 63 of its text nodes still paint inside the
	    band; every cut string carries `disclose`
	  p4_foyer .../FeedPage                  the same page, one node down, the same
	    measurement — and now clean under `xa` too, since the tab row shrinks
	  row_actions .../Cell-from/Value        the cell's own text is taller than
	    the cell it is layered in; it stays in the band and nothing opaque covers it
	  row_actions .../Cell-subject/Value     the twin of the row above, one
	    preference later
	  sponsor_avatars /AvatarLab             the RECLASSIFIED one: its 16 "covered"
	    initials were covered by a `surface = "plain"` rim, which paints no fill at
	    all. Nine text nodes, none cut, none off the band
	  sponsor_drop .../ListZone/Rows         the list zone outgrows the layer it
	    sits in; what it paints over is the chevron affordance, which is not copy
	  sponsor_drop /DropLab/Main             8px at +14 on one view, with no copy
	    and no control outside the band
	  sponsor_list .../Card/Labels           the capped detail line still overruns
	    the plate by a few px; it is cut WITH a `disclose` now, so the string has a
	    way back and nothing else leaves the band
	  sponsor_motion .../WashLabel           a label layered in the wash zstack:
	    nothing leaves the band and nothing is painted over it
	  virtual_list_native /VLNative          the page overruns and all 24 labels
	    stay in the band — the list's own window scrolls to them

	`kind` is the triage class (docs/plans/swiftui-parity-round3.md carries the
	full list with the per-view/per-preference detail):
	  * fixed-px-vs-text  — a px extent fixed against content that is not fixed
	                        (`docs/lessons/facet-fixed-px-heights.md`)
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
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[*]/*/Content/Row/Cells/Cell-subject/Value",
		sig = "this child overflows its zstack by NxNpx and",
		px = 24,
		since = 10,
		kind = "layer-overlap",
		where = "compact-portrait/320x640 @ +10/+14 (six rows, one template) — the same cause as the from-cell above, one preference later",
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
		--[[ RE-RECORDED 2026-08-16 (navigation-and-menus D5). The node MOVED —
			the section nav is one `newTabView` now, so the home body lives in the
			construct's content region rather than in a hand-built `ContentHost` —
			and the ceiling moved 16 -> 19px with it. The defect is the same one:
			a 320px-tall landscape at the largest text preference cannot fit this
			page, and the page does not scroll. The three extra pixels are the
			construct's own band being 46px where the hand-built icon-only row was
			43, which is the tap-target floor the strip inherits from `newPicker`
			and is not free to give back. ]]
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Nav/Content/Tab-home/then/HomeBody",
		sig = "content overflows this vstack by Npx on the",
		px = 19,
		since = 4,
		kind = "page-not-scrollable",
		where = "640x320 ONLY @ +4/+10/+14",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Nav/Content/Tab-home/then/HomeBody/FeedPage",
		sig = "content box collapses to Npx on y: padding N",
		px = 16,
		since = 0,
		kind = "collapsed-box",
		where = '640x320/compact-landscape @ +0/+4/+10/+14 — 8+8 of padding on a 16px height, so nothing inside the feed page can draw. Recorded as owed on 2026-08-12 (device-bug round, "found and NOT fixed") and never re-verified until now',
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
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", view.displaySize)
	env:set("preferredInput", view.input)
	env:set("capabilities", CAPABILITIES[view.input])
	local system = Facet.newActionSystem(core)
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
	local presenter = Facet.newPresenter(core, env, adapter, system)
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

--[[ ── THE LOCALE AXIS (O-19, 2026-08-15) ────────────────────────────────────

	The header above used to end its "WHAT IT IS NOT" paragraph with an admission:
	this file sweeps ONE LOCALE, and `p4_foyer`'s TopBar overflows by 33/58px at
	390x844 under the shipping 1.4x `xa` pseudo-locale where it is clean in
	English. That is now an axis rather than a sentence, and 390x844 is a swept
	viewport (tests/lib/device_views.luau).

	EXPANSION IS NOT THE PREFERENCE AXIS AGAIN. `preferredTextOffset` adds px to a
	line box — every string on the screen gets TALLER by the same amount. A locale
	makes each string LONGER by a factor, and only where there is copy: a row of
	four labels grows four times, a row of four icons not at all. The two axes move
	different geometry, and the corpus proves it — the first run of this pass found
	`p4_foyer`'s bell 19px off the right screen edge at +4, three preference steps
	EARLIER than the English defect it already carried.

	THE TWO MECHANISMS, and there are only two because the corpus only has two:
	  * a fixture that exports a flat `copy` table (17 scenarios today) gets it
	    put through the SHIPPING pseudo-localizer — the same seam and the same
	    function `tests/examples_gallery.spec` uses, so the expansion this sweeps is
	    the expansion that file asserts;
	  * a reference proof takes its locale as a fact — `deps.locale = "xa"` at
	    build, plus its own `steps.locale` where it has one.
	A surface with neither is NOT covered, and is not quietly counted as covered
	either: the coverage case at the bottom of this file DERIVES which surfaces the
	pass actually moved (an English text digest against the expanded one) and
	prints every surface it did not.

	WHY IT IS A SECOND MOUNT. A fixture reads its copy when it BUILDS. The
	preference and the package are `env:set`s on a live tree — measured equivalent
	to a fresh mount — and this one cannot be, so it is the only axis here that
	costs a mount per cell. That is what the tier below is for.

	THE TIER: every viewport at the DEFAULT preference and at the LARGEST, and no
	theme. Both ends, because expansion and preference compound (the O-19 row is at
	+10/+14) and because +0 is where a regression is a plain regression; every
	viewport, because a locale changes the TREE — a longer string flips a
	ViewThatFits rung and moves a wrap point. The two middle preferences are the
	declared hole, and the preference axis is NOT monotone (this file's own header
	proves it on the neutral pass), so that hole is a known one rather than a claim
	that +14 dominates.
]]
local l10n = require("./fixtures/a11y_l10n_fixtures")

local LOCALE = "xa"
local LOCALE_OFFSETS: { number } = { 0, LARGEST }

--[[ THE LOCALE LEDGER. Same four rules as the waiver list above — a ceiling, a
	smallest preference, a line that fires nowhere fails, keyed by class as well as
	node — kept separate for the theme ledger's reason: an English ceiling was
	measured on English copy. Every row is what the first run of this axis found,
	on 2026-08-15, and every one of them is a to-do with a measurement on it. ]]
local LOCALE_WAIVERS: { Waiver } = {
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Nav/Content/Tab-home/then/HomeBody",
		sig = "content overflows this vstack by Npx on the",
		px = 110,
		since = 14,
		kind = "fixed-px-vs-text",
		where = "compact-phone-landscape@+14, narrow-landscape@+14",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/RackSlot/Rack/OpenPotions",
		sig = "content overflows this hstack by Npx on the",
		px = 31,
		since = 14,
		kind = "row-cannot-shrink",
		where = "compact-phone-landscape@+14",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/Recent/RecentBrews/HeroTiles/Tiles/TileGrid/TileRows/[*]/*/Body",
		sig = "this child overflows its zstack by NxNpx and",
		px = 27,
		since = 14,
		kind = "layer-overlap",
		where = "desktop-studio-1320@+14, narrow-landscape@+14",
	},
	{
		-- RE-RECORDED 2026-08-16 with the D5 migration: the node moved into the
		-- TabView's content region and the collapse got SMALLER in absolute terms
		-- (a 9px box rather than a 3px one), which the ledger reads as a worse
		-- ceiling because the number it records is the box that could not draw.
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Nav/Content/Tab-home/then/HomeBody/FeedPage",
		sig = "content box collapses to Npx on y: padding N",
		px = 9,
		since = 0,
		kind = "collapsed-box",
		where = "narrow-landscape@+0",
	},
}

local LOCALE_BY_KEY: { [string]: Waiver } = {}
local LOCALE_MATCHED: { [string]: boolean } = {}
for _, row in LOCALE_WAIVERS do
	local key = waiverKey(row.surface, row.variant, row.node, row.sig)
	assert(LOCALE_BY_KEY[key] == nil, `duplicate locale waiver for {key}`)
	LOCALE_BY_KEY[key] = row
end

-- Every player-visible string a fixture exports, expanded in place. The module
-- table is shared, so this is the real surface rather than a parallel one — and
-- it is restored on every path including a throw (`withPseudoCopy`).
local function withPseudoCopy(module: any, body: () -> any): any
	if type(module.copy) ~= "table" then
		return body()
	end
	local original: { [string]: string } = {}
	for key, value in module.copy do
		if type(value) == "string" then
			original[key] = value
			module.copy[key] = l10n.pseudoLocalize(value)
		end
	end
	local ok, result = pcall(body)
	for key, value in original do
		module.copy[key] = value
	end
	if not ok then
		error(result, 0)
	end
	return result
end

-- THE DIGEST THAT PROVES THE PASS REACHED THE COPY. Length and codepoint sum of
-- every painted string, which an expansion always moves and a re-mount of the
-- same locale never does. It is what makes "this surface has no locale form" a
-- measurement instead of a list somebody maintains.
local function textDigest(built: any): number
	local total = 0
	for path, facts in built.handle.controller.textAt() do
		local text = facts.text
		if type(text) == "string" then
			total += #text + #path
		end
	end
	return total
end

-- which surfaces the locale pass actually MOVED, keyed by surface name; read by
-- the coverage case at the bottom of this file
local localeReached: { [string]: boolean } = {}

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
local function sweep(kind: string, name: string, mount: (any) -> any, localeMount: ((any) -> any)?)
	local label = `{kind} '{name}'`
	it(`{label}: the solver reports NOTHING at any swept viewport, at any text size`, function()
		local variant = VARIANTS[name]
		local problems: { string } = {}
		for _, view in VIEWS do
			local w = world(view)
			local built = mount(w)
			settle(w.presenter)
			local englishDigest = textDigest(built)
			-- `package` is nil on the neutral pass and the package's id on a themed
			-- one, and it selects WHICH list the finding is matched against — see
			-- "THE THEME LEDGER" above for why a neutral ceiling may not pardon a
			-- themed finding.
			local function collect(
				w: any,
				built: any,
				offset: number,
				variantValue: string,
				suffix: string,
				package: string?,
				locale: string?
			)
				if package ~= nil then
					suffix ..= `\n      [theme package = {package}]`
				end
				if locale ~= nil then
					suffix ..= `\n      [locale = {locale}]`
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
					if locale ~= nil then
						-- ── THE LOCALE PASS ─────────────────────────────────────────
						-- Its own list, for the theme ledger's reason: an English ceiling
						-- was measured on English copy, and letting it pardon a 1.4x
						-- string would be a ceiling nobody measured.
						local row = LOCALE_BY_KEY[key]
						if row ~= nil and offset == 0 and row.since > 0 then
							row = nil
						end
						if row == nil then
							table.insert(problems, describeFinding(w, view, offset, finding) .. suffix)
							continue
						end
						local localePx = findingPx(finding.issue)
						if localePx > row.px then
							table.insert(
								problems,
								describeFinding(w, view, offset, finding)
									.. suffix
									.. `\n      ^ WORSE than the recorded locale waiver: {localePx}px against a {row.px}px ceiling`
							)
						elseif offset < row.since then
							table.insert(
								problems,
								describeFinding(w, view, offset, finding)
									.. suffix
									.. `\n      ^ EARLIER than the recorded locale waiver: reported at +{offset}, recorded from +{row.since}`
							)
						else
							LOCALE_MATCHED[key] = true
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
			local function atOffset(w: any, built: any, offset: number, package: string?, locale: string?)
				w.env:set("preferredTextOffset", offset)
				settle(w.presenter)
				if variant == nil then
					collect(w, built, offset, "-", "", package, locale)
				else
					for _, value in variant.values do
						built.steps[variant.step](built, value)
						settle(w.presenter)
						collect(w, built, offset, value, `\n      [{variant.step} = {value}]`, package, locale)
					end
				end
			end
			for _, offset in OFFSETS do
				atOffset(w, built, offset, nil, nil)
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
					atOffset(w, built, offset, package.id, nil)
				end
			end
			-- ...AND THE LOCALE PASS, which is the one axis that CANNOT be swung on
			-- this tree: a fixture reads its copy when it builds, so the expanded form
			-- is a second mount rather than an `env:set`. It is therefore the axis with
			-- a real per-cell cost, and the tier is chosen accordingly (LOCALE_OFFSETS).
			if localeMount == nil then
				localeReached[name] = false
			else
				local lw = world(view)
				local lbuilt = localeMount(lw)
				settle(lw.presenter)
				localeReached[name] = textDigest(lbuilt) ~= englishDigest
				for _, offset in LOCALE_OFFSETS do
					atOffset(lw, lbuilt, offset, nil, LOCALE)
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
		Facet = Facet,
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
		-- A SURFACE WITH NO `copy` TABLE HAS NO LOCALE FORM, and mounting it a
		-- second time to prove that costs nine mounts to learn nothing. The pass is
		-- not offered at all for those; the coverage case still names them.
		local expandable = type(module.copy) == "table"
		sweep(
			"scenario",
			name,
			function(w)
				return present(w, module.build(scenarioCtx(w)))
			end,
			if not expandable
				then nil
				else function(w)
					-- the expansion is live only while the fixture BUILDS: the copy goes
					-- back before the mount is swept, so nothing else can read an expanded
					-- string out of a shared module table
					return withPseudoCopy(module, function()
						return present(w, module.build(scenarioCtx(w)))
					end)
				end
		)
	end
end)

describe("overflow sweep: tutorial examples", function()
	for _, name in EXAMPLES do
		local module = require(`../examples/gallery/examples/{name}`) :: any
		sweep("example", name, function(w)
			return present(
				w,
				module.build(
					Facet,
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
					Facet,
					w.core,
					{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
				)
			)
		end, function(w)
			-- a proof takes its locale as a BUILD FACT, and drives its own step too
			-- where it has one (p3/p4/p5); p2 reads the fact alone. p1 has neither,
			-- which the coverage case reports rather than assumes.
			local built = present(
				w,
				module.build(Facet, w.core, {
					env = w.env,
					actionSystem = w.system,
					presenter = w.presenter,
					adapter = w.adapter,
					locale = LOCALE,
				})
			)
			if built.steps ~= nil and built.steps.locale ~= nil then
				built.steps.locale(built, LOCALE)
			end
			return built
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
		local list = Facet.Controls.VirtualList(w.core, {
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
		-- either: 35 is what turning the TEXT-SIZE axis on found on 2026-08-13, 51 is
		-- what removing the message filter found the same day (the four classes this
		-- file could never see), and 13 is what is left after the director's ruling
		-- was carried to the end on 2026-08-15 (header). Every addition is a decision
		-- somebody has to make on purpose, and the cap moves DOWN with the list so a
		-- fixed defect cannot be quietly replaced by a new one.
		expect(#WAIVERS <= 13).toBe(true)
		--[[ ...and rule 1's own guard: the waivers that admit a defect at the DEFAULT
			preference, every one of them in a class this file was blind to. A new one
			means a +0 contract was surrendered, which is never a number to nudge.

			IT WENT 7 -> 6 -> 4 -> 3 ON 2026-08-15, downward three times, which is the
			only direction that needs no argument. The last to leave was
			`sponsor_toast`'s `Stage/Beneath`, whose stage now shares the canvas with a
			bounded chrome scroller instead of both lanes claiming `fill`. The first to leave was `row_actions`'
			`ROW_HEIGHT = 84` against a wrapping three-line cell measuring 88 at +0 —
			the worst of the three lying extents, and the only one that lied at the
			default preference; the row does not predict any more (`itemExtent =
			"measured"`, docs/plans/variable-item-extents.md). The other two were
			`sponsor_drop`'s twin chevron plates, `fixed` boxes holding a text glyph:
			the plate is a `minMax` FLOOR now, so it grows with the glyph instead of
			cutting it. ]]
		expect(DEFAULT_WAIVERS).toBe(3)
	end)
end)

--[[ ── THE LOCALE LEDGER IS A TO-DO LIST, AND ITS REACH IS DERIVED ────────────

	The same two cases the theme axis is under, for the same two ways a ledger
	rots, plus the one this axis needs.

	A row that fires NOWHERE is a defect somebody fixed (or a node that moved), so
	the ledger can only shrink. And REACH is not assumed: a fixture with no `copy`
	table and no locale fact builds byte-identical copy under this pass, and a
	pass that mounted it again would be pure cost claiming coverage it does not
	have. `localeReached` is the measured answer — the expanded text digest against
	the English one, taken on the same view — so "this surface has no locale form"
	is a MEASUREMENT printed on every run rather than a list nobody re-checks.
]]
describe("overflow sweep: the locale ledger", function()
	it("every locale row still fires — a stale row is a fixed defect, delete the line", function()
		local stale: { string } = {}
		for _, row in LOCALE_WAIVERS do
			local key = waiverKey(row.surface, row.variant, row.node, row.sig)
			if LOCALE_MATCHED[key] ~= true then
				table.insert(
					stale,
					`  {row.surface} [{row.variant}] {row.node}\n`
						.. `      "{row.sig}"\n`
						.. `      recorded {row.px}px from +{row.since} ({row.kind}; {row.where})`
				)
			end
		end
		if #stale > 0 then
			error(
				`{#stale} locale row(s) no longer fire anywhere in the `
					.. `{LOCALE} passes. If the surface was fixed, delete the entry (that is the point of the `
					.. `ledger); if the node moved or the solver reworded the finding, re-record it:\n`
					.. `{table.concat(stale, "\n")}`,
				0
			)
		end
		--[[ ...and the ledger may not quietly grow either. 12 is what turning the axis
			on found on 2026-08-15, over 9 viewports x 2 preferences on the 21 surfaces
			that HAVE a locale form. Every addition is a decision somebody makes.

			IT WAS 31 FOR ONE RUN, and the 19 that left are worth recording: they came
			from surfaces the pass MOUNTED but could not move — no `copy` export, no
			locale fact — so every one of them was an English finding wearing a locale
			label. The pass is not offered to those surfaces now, and the rows went
			with it. A ledger that records a defect the axis cannot actually see is the
			"check that proves nothing" class one level up. ]]
		expect(#LOCALE_WAIVERS <= 4).toBe(true)
	end)

	it("REACH: the pass moved the copy it claims to, and names every surface it did not", function()
		local reached: { string } = {}
		local inert: { string } = {}
		for name, moved in localeReached do
			if moved then
				table.insert(reached, name)
			else
				table.insert(inert, name)
			end
		end
		table.sort(reached)
		table.sort(inert)
		-- THE MEASUREMENT, not a list: a surface counts as covered only where the
		-- expanded mount really produced different text from the English one.
		print(
			`\n  [locale axis] {#reached} of {#reached + #inert} swept surfaces have a locale form this pass `
				.. `could move under '{LOCALE}' — {#LOCALE_OFFSETS} preferences x {#VIEWS} viewports each, no `
				.. `theme package.`
		)
		print(
			`  [locale axis] NOT COVERED — {#inert} surface(s): no \`copy\` export and no locale fact, so an `
				.. `expanded mount would build byte-identical text`
		)
		for _, name in inert do
			print(`      {name}`)
		end
		print(
			"  [locale axis] NOT COVERED — the tutorial examples (no `copy` export and no locale fact), "
				.. "the two middle text preferences, and the theme packages: expansion x package is a "
				.. "cross product this file does not pay for, and neither axis is monotone."
		)
		-- the pass has to reach SOMETHING, or an empty ledger would look like a
		-- clean corpus rather than an inert instrument
		expect(#reached >= 20).toBe(true)
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

--[[ ── THE APP-CHROME AXIS, AND THE ORACLE THAT CAN SEE PAINT (DIR wave contract
	5, 2026-08-18) ─────────────────────────────────────────────────────────────

	WHAT THIS FILE WAS BLIND TO, in the words of the report that found it
	(`artifacts/release-candidate-review/rename/dir-reproductions.md`): *"the themed
	overflow sweep is blind because it runs the hud fixture without the showcase
	chrome (no appChromeRects) and its oracle has no painted-text-fits / zero-box
	check."* Two independent holes, and the director's phone walked through both.

	HOLE 1 — A RESERVATION IS NOT THE CHROME. Every surface above is swept under
	`SHOWCASE_TOP`, which is `coreSafeInsets.top`: a BOUNDING BOX saying "the top
	120px of this screen are spoken for". The thing a screen actually collides with
	is a ROW at one end of that band, and `appChromeRects` is the fact the live host
	declares it through. A sweep that never declares it cannot see a HUD painting on
	the app's own chips — 164 painted nodes across 21 (viewport, package) cells,
	when the axis was first turned on.

	THE ROW IS DERIVED, NEVER WRITTEN DOWN. `tests/lib/showcase_chips` mounts the
	REAL `showcase_chrome` with the real composed pickers and reads its rect back
	through `onChipsRect` — the same callback the shipped host reads it through. A
	chip is a themed control, so its width decides which rung of the chrome's own
	`ViewThatFits` ladder wins: the same package produces a 128px row on a 359px
	phone and 452px on a 705px one, and classic_desktop produces 312 where
	pixel_quest produces 440. A literal would have been wrong on 79 of the 81 cells.

	HOLE 2 — THE SOLVER CANNOT SEE PAINT. Every assertion above reads
	`controller.diagnostics()`, and the defects the director photographed file NO
	diagnostic at all: a label truncating inside a box the ladder squeezed to 4px, a
	`"Tasks 1/3"` painting inside a 48x0 box. Both are legal layouts by the solver's
	own rules and both are unreadable.

	SO THE ORACLE IS THE MEASURE, RERUN. For every visible text node it takes the
	facts the solve PUBLISHED — the canonical font descriptor, the px size and (new
	in this wave) the lineHeight factor — and rebuilds the box:

	  * a zero-extent box with live text in it is a violation outright;
	  * the DRAWN line box (`lines x size x lineHeight`, the solver's own
	    arithmetic through `text_metrics.lineBoxPx`) must fit the box's height;
	  * and where the solve says the string was NOT truncated, the styled bounds at
	    the box's own width must fit it.

	IT IS THE STYLED TYPOGRAPHY AND NOTHING ELSE. The instrument trap this round
	fell into first is recorded in the reproductions file: a plain `FontFace` read
	reports LegacyArial while `GetStyled("FontFace")` reports the package's
	Fondamento, so an oracle that measured "the font" would have measured a face
	nothing paints. `textFacts.font` is the descriptor the MEASURE used, which is
	the descriptor the paint path resolves.

	WHY `lineHeight` HAD TO JOIN THE FACTS. `font` and `size` alone cannot rebuild
	the box: the shipped packages run from 1.15 to 1.25, so an oracle falling back
	to the measurer's default factor is short by up to 8% per line — enough to
	report a spill on a box the solver sized exactly right, which is a check that
	manufactures its own findings. Calibrated over the whole cross product at +0 and
	+14 before it was trusted: ZERO false positives.

	NEGATIVE CONTROL. `artifacts/release-candidate-review/rename/dir-sweep-negative-control.md`
	records this block run against the PRE-FIX tree in a temporary worktree, and
	what it found there. ]]
describe("overflow sweep: the HUD under the showcase's OWN chrome", function()
	local hud = require("../examples/gallery/scenarios/hud") :: any
	local showcase_chips = require("./lib/showcase_chips")
	local text_metrics = require("../src/layout/text_metrics")

	-- the neutral pass plus the eight packages, in the same order the themed tier
	-- above walks them
	local CELLS: { { id: string?, snapshot: any } } = { { id = nil, snapshot = nil } }
	for _, entry in PACKAGES do
		table.insert(CELLS, { id = entry.id, snapshot = entry.snapshot })
	end

	local function hudWorld(view: any, snapshot: any?, offset: number, chips: any?, top: number): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
		env:set("coreSafeInsets", { top = top, bottom = 0, left = 0, right = 0 })
		env:set("displaySize", view.displaySize)
		env:set("preferredInput", view.input)
		env:set("capabilities", CAPABILITIES[view.input])
		env:set("preferredTextOffset", offset)
		if chips ~= nil then
			env:set("appChromeRects", { chips })
		end
		if snapshot ~= nil then
			env:set("themeMetrics", snapshot)
		end
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new();
		(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
		local presenter = Facet.newPresenter(core, env, adapter, system)
		local handle: any = nil
		local built = hud.build({
			Facet = Facet,
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			actionSystem = system,
			record = function() end,
			flags = {},
			composition = function(path: string)
				return if handle ~= nil then handle.controller.compositionAt(path) else nil
			end,
			bindResourceTransport = function()
				return function() end
			end,
		})
		handle = presenter.present(built.screen, built.present)
		built.handle = handle
		-- twice the usual settle: the give-way pass reads its own solved rects
		-- through `onGeometry`, so the tree needs the frame that reacts to the frame
		-- that measured (examples/gallery/scenarios/hud.luau, `chromeReach`)
		for _ = 1, SETTLE_FRAMES * 2 do
			presenter.refresh()
		end
		return { core = core, env = env, adapter = adapter, presenter = presenter, built = built }
	end

	-- every node the adapter would PAINT under the HUD, against the declared row
	local function chromeCollisions(w: any, chip: any): { string }
		local out: { string } = {}
		for _, path in w.adapter.paths() do
			if string.find(path, "/HudScreen/Hud/", 1, true) ~= 1 then
				continue
			end
			local node = w.adapter.node(path)
			local rect = if node ~= nil then node.rect else nil
			if rect == nil or node.elided == true or rect.w <= 0 or rect.h <= 0 then
				continue
			end
			if w.adapter.visibleOf(path) == false then
				continue
			end
			local dx = math.min(rect.x + rect.w, chip.x + chip.w) - math.max(rect.x, chip.x)
			local dy = math.min(rect.y + rect.h, chip.y + chip.h) - math.max(rect.y, chip.y)
			if dx > 0.5 and dy > 0.5 then
				table.insert(
					out,
					string.format(
						"%s [%.0fx%.0f at %.0f,%.0f] paints %.0fx%.0fpx into the app's chrome",
						path,
						rect.w,
						rect.h,
						rect.x,
						rect.y,
						dx,
						dy
					)
				)
			end
		end
		return out
	end

	--[[ WHAT A ZONE THAT GAVE WAY OWES (DIR wave contract 3). Three guarantees, and
		each of them is a thing the director photographed the absence of:

		  1. NO REGION IS GRANTED LESS THAN ITS FLOOR. A floor is content-expressed
		     ("one line", "one target") and resolved against the LIVE package, so a
		     box under it is a box the theme's own type ladder cannot be drawn in.
		     This is the O-25 shape stated as an invariant rather than as a fix.
		  2. NO DROPPED OR ELIDED SUBTREE STILL PAINTS LIVE TEXT. A dropped region
		     keeps its mount and its subtree keeps solved rects, so "gone from the
		     ladder" and "gone from the screen" are two different facts — and the
		     `"Tasks 1/3"` in a 48x0 box is what it looks like when they disagree.
		  3. EVERY UNSHOWN REGION CARRIES A ROUTE. D7.1's whole contract: adaptation
		     may change how much of something is shown and what it costs to reach it,
		     never whether it can be reached at all. ]]
	--[[ ── NO DEAD-END COMPACT (wave REVEAL) ─────────────────────────────────────
		THE GUARANTEE: over the whole swept matrix, a region standing on a form below
		its richest can always be asked for the rest FROM WHERE IT STANDS. It is the
		other half of D7.1's "adaptation may change what it costs to reach something;
		it may not change whether it can be reached at all" — D7.1 made the ROUTE a
		declaration, and this asserts the route is on the screen.

		THE ESCAPE IS AUTHORED AND EXEMPT, deliberately: `expand = "none"` is a
		statement that there is nothing to disclose, or that the author is disclosing
		it themselves, and a mechanism with no way to say that is a mechanism authors
		route around. Every other stepped-down region must carry a STANDING affordance
		— mounted, visible, non-zero, and at the target floor its own contract
		declares, because a route the thumb cannot land on is a route on paper.

		The rect it checks is the HIT rect, not the painted one: a chevron is a mark
		and the 44px band around it is the shipped hit-expander's, so reading the
		painted box would report every correct chevron as too small. ]]
	local function deadEndViolations(w: any): { string }
		local out: { string } = {}
		local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
		if dump == nil then
			return out
		end
		for _, r in dump.regions do
			if (r.activeForm or 0) <= 1 then
				continue -- at its richest, or dropped: neither is a stepped-down region
			end
			if r.expand == "none" then
				continue -- the authored escape
			end
			if not r.expandable then
				table.insert(
					out,
					string.format(
						"%s is standing on form %d of its ladder with no route to the rest — a dead end",
						r.id,
						r.activeForm
					)
				)
				continue
			end
			local path = `{r.id}/Expand`
			local node = w.adapter.node(path)
			local hit = w.adapter.hitRectOf(path)
			local box = if hit ~= nil then hit else (if node ~= nil then node.rect else nil)
			if node == nil or box == nil or w.adapter.visibleOf(path) == false then
				table.insert(out, string.format("%s reports a route, and %s is not on the screen", r.id, path))
			elseif box.w < 24 or box.h < 24 then
				table.insert(
					out,
					string.format("%s's route is %.0fx%.0fpx — under the thumb's floor", r.id, box.w, box.h)
				)
			end
		end
		return out
	end

	local function giveWayViolations(w: any): { string }
		local out: { string } = {}
		local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
		if dump == nil then
			return out
		end
		for _, r in dump.regions do
			if r.mounted and not r.dropped and r.rect ~= nil and type(r.floor) == "number" and r.floor > 0 then
				if r.rect.h + 0.5 < r.floor then
					table.insert(
						out,
						string.format("%s: granted %.0fpx against its own %.0fpx floor", r.id, r.rect.h, r.floor)
					)
				end
			end
			--[[ TWO CORRECTIONS, BOTH FOUND BY A REVIEWER MUTATING THIS BLOCK (M2,
				2026-08-18), and the second one is the more interesting.

				IT READ THE WRONG FIELD. `node.text` is not a thing the target adapter
				has: text lands in `node.props.text` (tests/lib/fake_target.luau:310,
				`handle.props[prop] = value`). Probed over the whole HUD tree: ZERO
				nodes carry a non-empty `node.text`, at any cell — so this guarantee
				could not fire on any tree ever, and the wave reported its zero as a
				measurement when it was a silence. Reading the field the adapter
				actually populates is the fix.

				AND IT ASKED THE WRONG QUESTION. Re-fielded and left as-is, it reports
				THREE findings at 640x320 — `Clock` painting "2:14", `Rail` painting
				"Rifle", `Tasks` painting "Win a round" — all from regions the
				composition marks `elided`. In this vocabulary `elided` means "showing a
				REDUCED FORM", not "removed" (composition.luau's D7.1 note: an elided
				region declares a `recover` route precisely because it is still on
				screen showing less). An elided region painting text is the ladder
				working. `dropped` is the flag that means "there is no form standing",
				and text under a dropped region is the corpse the director photographed.

				So the guarantee is DROPPED-ONLY, and it is measured rather than
				assumed: over the swept cells, regions genuinely go `dropped` (Feed and
				Readout among them) and none of their subtrees paints a character. ]]
			if r.dropped then
				for _, path in w.adapter.paths() do
					if string.find(path, r.id .. "/", 1, true) ~= 1 then
						continue
					end
					if w.adapter.visibleOf(path) == false then
						continue
					end
					local node = w.adapter.node(path)
					local text = if node ~= nil and type(node.props) == "table" then node.props.text else nil
					if type(text) == "string" and text ~= "" then
						table.insert(out, string.format("%s: %s is DROPPED but still paints '%s'", path, r.id, text))
					end
				end
			end
		end
		for _, unshown in dump.unshown or {} do
			if type(unshown.route) ~= "string" or unshown.route == "" then
				table.insert(
					out,
					string.format("%s: %s with no route back to it", unshown.id, tostring(unshown.reason))
				)
			end
		end
		table.sort(out)
		return out
	end

	--[[ ── A VALUE MAY NOT BE ELLIPSIZED (controller ruling R9, 2026-08-18) ─────

		The standing localization rule is "wrap or auto-fit, never clip", and a HUD
		forces a distinction it does not itself make: a NAME may degrade, a NUMBER
		may not. `2:1…` is not a shortened round timer and `24/9…` is not a shortened
		magazine — the ellipsis changes the reading rather than abbreviating it, and
		there is nothing a player can infer through it.

		The classification is the FIXTURE's (`hud.valueText`), read from the module
		rather than restated here, so a new value readout joins this check by being
		declared once. Entries are node ids matched as the last segment of a solver
		path, because everything above them is the ladder's business.

		This is deliberately STRICTER than `paintedTextViolations` below: that asks
		whether a box can hold what it draws, and a truncating box legitimately can.
		This asks whether the string was allowed to be cut at all. ]]
	local VALUE_TEXT: { [string]: boolean } = {}
	for _, id in (hud :: any).valueText do
		VALUE_TEXT[id] = true
	end

	local function valueTextViolations(w: any): { string }
		local out: { string } = {}
		for path, facts in w.built.handle.controller.textAt() do
			if w.adapter.visibleOf(path) == false then
				continue
			end
			if string.find(path, "/HudScreen/Hud/", 1, true) ~= 1 then
				continue
			end
			local id = string.match(path, "([^/]+)$")
			if id == nil or not VALUE_TEXT[id] then
				continue
			end
			if facts.truncated == true then
				table.insert(
					out,
					string.format(
						"%s: the VALUE '%s' was cut — a value reformats, elides or gets its box, it never ellipsizes (R9)",
						path,
						tostring(facts.text)
					)
				)
			end
		end
		table.sort(out)
		return out
	end

	--[[ THE PAINTED-FITS ORACLE (see the header). Reruns the solve's own text
		measure from the facts it published, and reports the three ways a box can be
		one a player cannot read out of. ]]
	local function paintedTextViolations(w: any): { string }
		local out: { string } = {}
		for path, facts in w.built.handle.controller.textAt() do
			if w.adapter.visibleOf(path) == false then
				continue
			end
			local node = w.adapter.node(path)
			local rect = if node ~= nil then node.rect else nil
			if rect == nil then
				continue
			end
			local text = facts.text
			if type(text) ~= "string" or text == "" then
				continue
			end
			if rect.w <= 0.5 or rect.h <= 0.5 then
				table.insert(
					out,
					string.format(
						"%s: live text '%s' in a %.0fx%.0f box — nothing can be read out of it",
						path,
						text,
						rect.w,
						rect.h
					)
				)
				continue
			end
			local drawn = text_metrics.lineBoxPx(facts.size, facts.lines or 1, facts.lineHeight)
			if drawn > rect.h + 0.5 then
				table.insert(
					out,
					string.format(
						"%s: %d styled line(s) of '%s' need %.0fpx and the box is %.0fpx tall",
						path,
						facts.lines or 1,
						text,
						drawn,
						rect.h
					)
				)
			end
			if facts.truncated ~= true then
				local m = text_metrics.measure(text, facts.font, facts.size, rect.w, facts.lineHeight, facts.lineLimit)
				if m.width > rect.w + 0.5 then
					table.insert(
						out,
						string.format(
							"%s: the styled bounds of '%s' are %.0fpx wide in a %.0fpx box, and the solve did not truncate it",
							path,
							text,
							m.width,
							rect.w
						)
					)
				end
			end
		end
		table.sort(out)
		return out
	end

	for _, view in VIEWS do
		it(
			`{view.id} ({view.w}x{view.h}): the HUD clears the showcase's chip row and every box holds its own text`,
			function()
				local problems: { string } = {}
				local sawChrome = false
				for _, cell in CELLS do
					for _, offset in themedOffsets(view) do
						local chips = showcase_chips.rectFor(Facet, view, cell.id, cell.snapshot, offset)
						local top = showcase_chips.reservationFor(chips)
						if chips ~= nil then
							sawChrome = true
						end
						--[[ BOTH STRIP STATES. `ride` decides whether the HUD's topbar row
							sits IN the platform's free band or below the whole reservation,
							which moves every zone in the composition — and the director's
							report was taken with the strip ON, the state this sweep had
							never separated from the other. ]]
						for _, riding in { true, false } do
							local w = hudWorld(view, cell.snapshot, offset, chips, top)
							if riding then
								w.built.steps.rideStrip()
							else
								w.built.steps.leaveStrip()
							end
							for _ = 1, SETTLE_FRAMES * 2 do
								w.presenter.refresh()
							end
							local suffix =
								`\n      [package = {tostring(cell.id)}] [+{offset}] [strip = {tostring(riding)}]`
							if chips ~= nil then
								for _, hit in chromeCollisions(w, chips) do
									table.insert(problems, `  {hit}{suffix}`)
								end
							end
							for _, hit in paintedTextViolations(w) do
								table.insert(problems, `  {hit}{suffix}`)
							end
							for _, hit in giveWayViolations(w) do
								table.insert(problems, `  {hit}{suffix}`)
							end
							for _, hit in deadEndViolations(w) do
								table.insert(problems, `  {hit}{suffix}`)
							end
							for _, hit in valueTextViolations(w) do
								table.insert(problems, `  {hit}{suffix}`)
							end
							--[[ ...AND THE SOLVER'S OWN FINDINGS, on the axis it was never
								asked on. The generic sweep above runs this surface without the
								chrome declared; declaring it changes the composition's whole
								input, so a finding here is a finding nothing else could see. ]]
							for _, finding in w.built.handle.controller.diagnostics() do
								if finding.designed == true then
									continue
								end
								table.insert(problems, `  {finding.node}: {finding.issue}{suffix}`)
							end
						end
					end
				end
				--[[ THE AXIS HAS SOMETHING TO SAY. If the chrome never mounted, every
					collision assertion above passed on a geometry with no chrome in it —
					the "check that proves nothing" class one level up. ]]
				expect(`{view.id}: the showcase chrome measured a row: {sawChrome}`).toBe(
					`{view.id}: the showcase chrome measured a row: true`
				)
				if #problems > 0 then
					error(
						`{view.id} ({view.w}x{view.h}): {#problems} finding(s) under the showcase's own declared `
							.. `chrome — the HUD painting on the app's chips, or text in a box that cannot hold `
							.. `it (tests/overflow_sweep.spec.luau, "the HUD under the showcase's OWN `
							.. `chrome"):\n{table.concat(problems, "\n")}`,
						0
					)
				end
			end
		)
	end

	--[[ THE DEAD-END GUARANTEE BITES, and it is checked the only way a guarantee
		that currently reports ZERO can be: by breaking the thing it watches. A pass
		over a matrix where nothing is wrong is indistinguishable from a pass over a
		matrix nothing is looking at.

		THREE PROBES, and the third is the one that matters. A stepped-down region
		whose affordance is taken off the screen must be REPORTED (the route is on
		paper). A stepped-down region whose resolution says there is no route at all
		must be REPORTED (the mechanism was suppressed). And the SAME region, with
		the authored escape declared, must be SILENT — because `expand = "none"` is a
		statement and not an oversight, and a sweep that cannot tell those apart
		would force every author to route around it. ]]
	it("DEAD-END CONTROL: a suppressed route is reported, and the AUTHORED escape is not", function()
		local view = VIEWS[1]
		local chips = showcase_chips.rectFor(Facet, view, nil, nil, LARGEST)
		local w = hudWorld(view, nil, LARGEST, chips, showcase_chips.reservationFor(chips))
		expect(#deadEndViolations(w)).toBe(0)

		local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
		local stepped: any = nil
		for _, r in dump.regions do
			if (r.activeForm or 0) > 1 and r.expandable and stepped == nil then
				stepped = r
			end
		end
		--[[ THE PREMISE, stated the way the give-way control states its own: without a
			genuinely stepped-down region carrying a route, all three probes below are
			assertions about an empty set. ]]
		expect(`a region is genuinely stepped down with a route here: {stepped ~= nil}`).toBe(
			"a region is genuinely stepped down with a route here: true"
		)

		-- (1) THE ROUTE IS ON PAPER: the affordance exists and is not on the screen
		local affordance = w.adapter.node(`{stepped.id}/Expand`)
		local wasVisible = affordance.visible
		affordance.visible = false
		local reported = false
		for _, hit in deadEndViolations(w) do
			if string.find(hit, "is not on the screen", 1, true) ~= nil then
				reported = true
			end
		end
		expect(`an affordance off the screen is reported: {reported}`).toBe(
			"an affordance off the screen is reported: true"
		)
		affordance.visible = wasVisible
		expect(`...and the untouched tree is silent again: {#deadEndViolations(w)}`).toBe(
			"...and the untouched tree is silent again: 0"
		)

		-- (2) THE MECHANISM IS SUPPRESSED: the resolution reports no route at all
		stepped.expandable = false
		local suppressed = false
		for _, hit in deadEndViolations(w) do
			if string.find(hit, "with no route to the rest", 1, true) ~= nil then
				suppressed = true
			end
		end
		expect(`a stepped-down region with no route is reported: {suppressed}`).toBe(
			"a stepped-down region with no route is reported: true"
		)

		-- (3) ...AND THE SAME STATE, DECLARED, IS EXEMPT. One field apart from the
		-- case above, and it is the field that says a human decided.
		stepped.expand = "none"
		expect(`the authored escape is exempt: {#deadEndViolations(w)}`).toBe("the authored escape is exempt: 0")
	end)

	--[[ THE VALUE ORACLE BITES, and it is checked for the two ways it could be
		decoration: a classification that names nothing on screen, and a check that
		would stay silent on a cut value. ]]
	it("VALUE CONTROL: the R9 classification reaches real nodes, and a cut value is reported", function()
		local view = VIEWS[1]
		local cell: any = nil
		for _, entry in CELLS do
			if entry.id == "fantasy-ornate" then
				cell = entry
			end
		end
		local chips = showcase_chips.rectFor(Facet, view, cell.id, cell.snapshot, 0)
		local w = hudWorld(view, cell.snapshot, 0, chips, showcase_chips.reservationFor(chips))
		expect(#valueTextViolations(w)).toBe(0)

		--[[ THE CLASSIFICATION IS NOT A LIST OF NAMES NOBODY USES. Count the value
			nodes this tree actually paints; a table whose ids match nothing would make
			every assertion above pass on a check that looks at zero nodes. ]]
		local seen = 0
		local victim: string? = nil
		for path in w.built.handle.controller.textAt() do
			local id = string.match(path, "([^/]+)$")
			if id ~= nil and VALUE_TEXT[id] and w.adapter.visibleOf(path) ~= false then
				seen += 1
				victim = victim or path
			end
		end
		expect(`value nodes on screen: {seen > 0}`).toBe("value nodes on screen: true")

		-- ...and a cut one is reported
		local facts = w.built.handle.controller.textAt(victim :: string)
		local was = facts.truncated
		facts.truncated = true
		local reported = false
		for _, hit in valueTextViolations(w) do
			if string.find(hit, "never ellipsizes (R9)", 1, true) ~= nil then
				reported = true
			end
		end
		expect(`a cut value is reported: {reported}`).toBe("a cut value is reported: true")
		facts.truncated = was
		expect(`...and the settled tree is silent again: {#valueTextViolations(w)}`).toBe(
			"...and the settled tree is silent again: 0"
		)
	end)

	--[[ THE GIVE-WAY ORACLE BITES TOO, and this case exists because the version of
		it that shipped in the first DIR commit did NOT (M2). It read `node.text`, a
		field the target adapter never writes, so it could not fire on any tree at
		any cell and its zero was a silence reported as a measurement. A guarantee
		with no control is the class this whole file was built to remove, one level
		up — so the control is now permanent rather than a reviewer's one-off. ]]
	it("GIVE-WAY CONTROL: a DROPPED region that paints a character is reported, and the settled tree is not", function()
		--[[ THE CELL IS CHOSEN BECAUSE REGIONS GENUINELY DROP THERE, and which cells
			those are is a measurement rather than a guess: over the whole swept cross
			product, the narrow phone portrait at the Largest preference is where the
			left column's ladder runs out — under glossy-mobile it drops Tasks, Health,
			Feed and Readout, and the dropped subtree still carries 33 nodes with
			solved rects. That is the corpse's habitat. ]]
		local view = VIEWS[1]
		local cell: any = nil
		for _, entry in CELLS do
			if entry.id == "glossy-mobile" then
				cell = entry
			end
		end
		expect(`the control's package is in the sweep: {cell ~= nil}`).toBe(
			"the control's package is in the sweep: true"
		)
		local chips = showcase_chips.rectFor(Facet, view, cell.id, cell.snapshot, LARGEST)
		local w = hudWorld(view, cell.snapshot, LARGEST, chips, showcase_chips.reservationFor(chips))
		expect(#giveWayViolations(w)).toBe(0)

		local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
		local droppedId: string? = nil
		for _, r in dump.regions do
			if r.dropped and droppedId == nil then
				droppedId = r.id
			end
		end
		--[[ THE PREMISE. Without a genuinely dropped region this control proves
			nothing — and "nothing drops anywhere in this corpus" would itself be worth
			knowing, because the dropped guarantee would then be asserted over a set of
			trees that can never exercise it. ]]
		expect(`a region is genuinely dropped at this cell: {droppedId ~= nil}`).toBe(
			"a region is genuinely dropped at this cell: true"
		)

		--[[ MAKE IT PAINT. A dropped region keeps its mount and its subtree keeps its
			solved rects, so the shape the director photographed is exactly this: a
			node under a dropped region, visible, with a character in it. BOTH halves
			are forced — the visibility and the text — because the guarantee is about
			their conjunction and forcing one alone leaves the other unproven. ]]
		local victim: string? = nil
		local child: any = nil
		for _, path in w.adapter.paths() do
			if string.find(path, (droppedId :: string) .. "/", 1, true) == 1 then
				child = w.adapter.node(path)
				if child ~= nil then
					victim = path
					break
				end
			end
		end
		expect(`...and a descendant to paint through: {child ~= nil}`).toBe(
			"...and a descendant to paint through: true"
		)
		local wasVisible, wasText = child.visible, child.props.text
		child.visible, child.props.text = true, "Tasks 1/3"
		local reported = false
		for _, hit in giveWayViolations(w) do
			if string.find(hit, "DROPPED but still paints 'Tasks 1/3'", 1, true) ~= nil then
				reported = true
			end
		end
		expect(`{victim} painting a character under a dropped region is reported: {reported}`).toBe(
			`{victim} painting a character under a dropped region is reported: true`
		)
		child.visible, child.props.text = wasVisible, wasText
		expect(`...and the untouched tree is silent again: {#giveWayViolations(w)}`).toBe(
			"...and the untouched tree is silent again: 0"
		)
	end)

	--[[ THE ORACLE BITES, proved by breaking the thing it watches rather than by
		reading it. A box squeezed under one styled line of its own text has to be
		REPORTED, and a box that holds its line has to be silent — otherwise the
		nine cases above are nine ways of asserting nothing. ]]
	it(
		"ORACLE CONTROL: a plate squeezed under its own styled line is reported, and a plate that holds it is not",
		function()
			local view = VIEWS[1]
			local chips = showcase_chips.rectFor(Facet, view, nil, nil, 0)
			local w = hudWorld(view, nil, 0, chips, showcase_chips.reservationFor(chips))
			expect(#paintedTextViolations(w)).toBe(0)

			-- one real text node, squeezed to a box a styled line cannot be drawn in
			local victim: string? = nil
			for path, facts in w.built.handle.controller.textAt() do
				if type(facts.text) == "string" and facts.text ~= "" and w.adapter.visibleOf(path) ~= false then
					local node = w.adapter.node(path)
					if node ~= nil and node.rect ~= nil and node.rect.h > 1 then
						victim = path
						break
					end
				end
			end
			expect(`the control found a text node to squeeze: {victim ~= nil}`).toBe(
				"the control found a text node to squeeze: true"
			)
			local node = w.adapter.node(victim :: string)
			local was = node.rect
			node.rect = { x = was.x, y = was.y, w = was.w, h = 0 }
			local zeroBox = paintedTextViolations(w)
			expect(`a zero-height box with live text is reported: {#zeroBox > 0}`).toBe(
				"a zero-height box with live text is reported: true"
			)
			node.rect = { x = was.x, y = was.y, w = was.w, h = 1 }
			expect(`...and so is a box one pixel under its own line: {#paintedTextViolations(w) > 0}`).toBe(
				"...and so is a box one pixel under its own line: true"
			)
			node.rect = was
			expect(`...and the untouched tree is silent again: {#paintedTextViolations(w)}`).toBe(
				"...and the untouched tree is silent again: 0"
			)
		end
	)
end)
