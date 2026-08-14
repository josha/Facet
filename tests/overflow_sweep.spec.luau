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

-- THE AXES A CONTAINER CAN RUN OUT OF ROOM ON — plural since parity round 3 item
-- A. For every container this file swept before, "too much content" is a MAIN-axis
-- fact: the cursor keeps advancing past the box. A WRAPPING stack inverts that. Its
-- main axis cannot overflow at all, by construction — that is what wrapping means —
-- and the direction it runs out of room is the CROSS one, as the lines pile up. A
-- sweep that only greps the main axis is structurally blind to every wrapping stack
-- on every screen, which is the "instrument that cannot bite" class this file was
-- written to end.
--
-- Both phrases are exact and unique: no other diagnostic in `solver.luau` contains
-- either, and the placement-audit advice that talks about "the cross axis" never
-- says "ON the cross axis".
local OVERFLOW_AXES = { "on the main axis", "on the cross axis" }

local function isOverflow(issue: string): boolean
	for _, phrase in OVERFLOW_AXES do
		if string.find(issue, phrase, 1, true) ~= nil then
			return true
		end
	end
	return false
end

-- the MEASUREMENT out of the diagnostic. Both shapes carry one: the stack
-- diagnostic says "by 46px", the wrap-clamp one says "is 8px wider than". A
-- finding whose px cannot be read is treated as 0 rather than skipped — it is
-- still a finding, it just cannot be compared against a ceiling.
local function overflowPx(issue: string): number
	local n = string.match(issue, "by (%d+)px") or string.match(issue, "is (%d+)px wider")
	return tonumber(n) or 0
end

-- KEYED SIBLINGS ARE ONE DEFECT, NOT SIXTEEN. p5_wardrobe's catalog renders the
-- same item card sixteen times under `Items/[cinder-hood]/cinder-hood`; card_rail
-- renders seven `W/[c3]/Row/Card`. Waiving each generated path separately would
-- turn one wrong constant into sixteen lines of to-do list and would go stale the
-- moment a fixture's data changed, so a path is normalised: a `[key]` segment
-- becomes `[*]`, and a segment that merely REPEATS the key it sits under becomes
-- `*`. Nothing else is collapsed — the shape of the tree above the item is exact.
local function normalizePath(path: string): string
	local out: { string } = {}
	local prevKey: string? = nil
	for segment in string.gmatch(path, "[^/]+") do
		local key = string.match(segment, "^%[(.*)%]$")
		if key ~= nil then
			table.insert(out, "[*]")
			prevKey = key
		elseif prevKey ~= nil and segment == prevKey then
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

	The rules this list is under, all three of which are the reason it cannot rot:

	  1. AT THE DEFAULT PREFERENCE (offset 0) NOTHING IS WAIVED. The sweep was
	     green there before the axis existed and stays green there; a finding at
	     offset 0 fails no matter what this table says.
	  2. A WAIVER IS A CEILING, NOT A PARDON. `px` is the largest overflow measured
	     anywhere in the cross product on 2026-08-13 and `since` is the smallest
	     preference that reports it. A finding that exceeds the ceiling, or that
	     appears at a SMALLER preference than recorded, fails: the defect got
	     worse, which is a regression even inside a known defect.
	  3. A WAIVER THAT NEVER FIRES FAILS TOO (the case at the bottom of this file).
	     When somebody fixes one of these, the suite tells them to delete the line
	     — so the list can only ever shrink, and "35" is a number that means
	     something rather than a decoration.

	`kind` is the triage class (docs/plans/swiftui-parity-round3.md carries the
	full list with the per-view/per-preference detail):
	  * fixed-px-vs-text  — a px extent fixed against content that is not fixed
	                        (`docs/lessons/luauui-fixed-px-heights.md`)
	  * row-cannot-shrink — a row of labels/controls wider than the screen with
	                        nothing allowed to shrink. NOTE: not ONE of these 35
	                        carries the solver's "every shrinkable child is already
	                        at its floor" suffix, so every one of them is still
	                        repairable by authoring (a shrinkWeight, a ViewThatFits
	                        rung, a wrap) rather than blocked on the framework
	  * page-not-scrollable — a whole surface taller than a short canvas, usually
	                        640x320, with no page scroller
	  * wrap-clamp        — a hwrap line clamping a child it could not fit
]]
type Waiver = {
	surface: string,
	variant: string,
	node: string,
	px: number,
	since: number,
	kind: string,
	where: string,
}

local WAIVERS: { Waiver } = {
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferBar",
		px = 198,
		since = 4,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +4/+10/+14",
	},
	{
		surface = "virtual_list_native",
		variant = "-",
		node = "/VLNative",
		px = 113,
		since = 4,
		kind = "page-not-scrollable",
		where = "320x640/640x320/compact-portrait/compact-landscape @ +4/+10/+14",
	},
	{
		surface = "row_actions",
		variant = "vlist",
		node = "/MailActions/VListWhen/then/VListPane",
		px = 109,
		since = 4,
		kind = "fixed-px-vs-text",
		where = "320x640/640x320/compact-landscape @ +4/+10/+14",
	},
	{
		surface = "sponsor_list",
		variant = "-",
		node = "/ListLab/Body/Controls",
		px = 95,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +10/+14",
	},
	{
		surface = "adaptive_controls",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/Legend",
		px = 92,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/640x320/compact-portrait/compact-landscape @ +10/+14",
	},
	{
		surface = "theme_authoring",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/Legend",
		px = 92,
		since = 10,
		kind = "row-cannot-shrink",
		where = "the same Hud fixture as adaptive_controls, under the theme package",
	},
	{
		surface = "07_match3",
		variant = "-",
		node = "/Match3/Page/Stats",
		px = 82,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +10/+14 — the device-bug round's own ViewThatFits ladder runs out of rungs at +10",
	},
	{
		surface = "card_rail",
		variant = "-",
		node = "/CardRail/RailPane/Rail/Canvas/W/[*]/Row/Card",
		px = 68,
		since = 10,
		kind = "fixed-px-vs-text",
		where = "640x320/compact-landscape @ +10/+14 — the fixed card plate",
	},
	{
		surface = "sponsor_billboard",
		variant = "-",
		node = "/BillboardLab",
		px = 64,
		since = 4,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +4/+10/+14",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Actions/ActionsRow",
		px = 59,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +10/+14",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Middle/ContentHost/HomeWhen/then/HomeBody/FeedPage/Sections/[*]/Body/Header",
		px = 52,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +10/+14 (four sections, one template)",
	},
	{
		surface = "drag_session",
		variant = "-",
		node = "/DragLab",
		px = 46,
		since = 4,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +4/+10/+14",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Middle/ContentHost/HomeWhen/then/HomeBody/TabRow",
		px = 43,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/compact-portrait @ +10/+14",
	},
	{
		surface = "authoring",
		variant = "-",
		node = "/AuthoringScreen",
		px = 43,
		since = 4,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +4/+10/+14",
	},
	{
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane/MailTable/Main",
		px = 36,
		since = 10,
		kind = "fixed-px-vs-text",
		where = "640x320/compact-landscape @ +10/+14",
	},
	{
		surface = "sponsor_list",
		variant = "-",
		node = "/ListLab/Body/Rows/Canvas/W/[*]/Row/Card/Labels",
		px = 35,
		since = 10,
		kind = "fixed-px-vs-text",
		where = "320x640/compact-portrait @ +10/+14 — the row-height memo caps the detail at TWO caption lines; at +10 the detail needs three",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/Sky/Skyglow/Axis",
		px = 30,
		since = 14,
		kind = "row-cannot-shrink",
		where = "tablet-landscape 1079x809 ONLY @ +14",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/ChatterSlot/ChatterCard/OpenChatter",
		px = 26,
		since = 14,
		kind = "row-cannot-shrink",
		where = "tablet-landscape 1079x809 ONLY @ +14",
	},
	{
		surface = "scroll_host",
		variant = "-",
		node = "/ScrollHost",
		px = 26,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +10/+14",
	},
	{
		surface = "async_images",
		variant = "-",
		node = "/AsyncImages",
		px = 25,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +10/+14",
	},
	{
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane",
		px = 25,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +10/+14",
	},
	{
		surface = "03_settings_sync",
		variant = "-",
		node = "/Settings/Page/State",
		px = 24,
		since = 4,
		kind = "fixed-px-vs-text",
		where = "compact-portrait 359x718 @ +4 ONLY — clean at +10 and +14, the non-monotone cell that makes an extremes-only sweep unsafe",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Catalog/CatalogCol/Items/PickedWhen/then/Picked/PickedGrid/Items/[*]/*",
		px = 24,
		since = 4,
		kind = "fixed-px-vs-text",
		where = "six of the eight views @ +4/+10/+14 (non-monotone at 640x320: +4 and +14, not +10)",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Catalog/CatalogCol/Items/PickedWhen/then/Picked/PickedGrid/Items/[*]/*/Col/Meta",
		px = 24,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/console-ten-foot @ +10/+14",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Catalog/CatalogCol/Items/RestWhen/then/Rest/RestGrid/Items/[*]/*",
		px = 24,
		since = 4,
		kind = "fixed-px-vs-text",
		where = "six of the eight views @ +4/+10/+14 (twelve generated cards, one template)",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Catalog/CatalogCol/Items/RestWhen/then/Rest/RestGrid/Items/[*]/*/Col/Meta",
		px = 24,
		since = 10,
		kind = "row-cannot-shrink",
		where = "320x640/console-ten-foot @ +10/+14",
	},
	{
		surface = "perf_capture",
		variant = "-",
		node = "/PerfCapture",
		px = 23,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320/compact-landscape @ +10/+14",
	},
	{
		surface = "progress_ring",
		variant = "-",
		node = "/ProgressRing/Page/Dots",
		px = 20,
		since = 14,
		kind = "row-cannot-shrink",
		where = "320x640 ONLY @ +14",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Middle/ContentHost/HomeWhen/then/HomeBody",
		px = 16,
		since = 4,
		kind = "page-not-scrollable",
		where = "640x320 ONLY @ +4/+10/+14",
	},
	{
		surface = "sponsor_toast",
		variant = "-",
		node = "/ToastLab",
		px = 16,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320 ONLY @ +10/+14",
	},
	{
		surface = "sponsor_avatars",
		variant = "-",
		node = "/AvatarLab",
		px = 12,
		since = 10,
		kind = "page-not-scrollable",
		where = "640x320 ONLY @ +10/+14",
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
		px = 10,
		since = 14,
		kind = "row-cannot-shrink",
		where = "320x640 ONLY @ +14",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main",
		px = 8,
		since = 14,
		kind = "page-not-scrollable",
		where = "320x640 ONLY @ +14",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/RackSlot/Rack/OpenPotions",
		px = 5,
		since = 14,
		kind = "row-cannot-shrink",
		where = "tablet-landscape 1079x809 ONLY @ +14",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/ChatterSlot/ChatterCard/Cloud",
		px = 0,
		since = 14,
		kind = "wrap-clamp",
		where = "tablet-landscape 1079x809 ONLY @ +14 — Tag3 clamped by 0px, the degenerate end of the wrap-clamp class",
	},
}

local WAIVER_BY_KEY: { [string]: Waiver } = {}
local WAIVER_MATCHED: { [string]: boolean } = {}

local function waiverKey(surface: string, variant: string, node: string): string
	return `{surface}|{variant}|{node}`
end

for _, waiver in WAIVERS do
	local key = waiverKey(waiver.surface, waiver.variant, waiver.node)
	assert(WAIVER_BY_KEY[key] == nil, `duplicate waiver for {key}`)
	WAIVER_BY_KEY[key] = waiver
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
	it(`{label}: no overflow on EITHER axis at any swept viewport, at any text size`, function()
		local variant = VARIANTS[name]
		local problems: { string } = {}
		for _, view in VIEWS do
			local w = world(view)
			local built = mount(w)
			settle(w.presenter)
			local function collect(offset: number, variantValue: string, suffix: string)
				for _, finding in built.handle.controller.diagnostics() do
					if not isOverflow(finding.issue) then
						continue
					end
					local key = waiverKey(name, variantValue, normalizePath(finding.node))
					local waiver = if offset > 0 then WAIVER_BY_KEY[key] else nil
					if waiver == nil then
						table.insert(problems, describeFinding(w, view, offset, finding) .. suffix)
						continue
					end
					local px = overflowPx(finding.issue)
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
			for _, offset in OFFSETS do
				w.env:set("preferredTextOffset", offset)
				settle(w.presenter)
				if variant == nil then
					collect(offset, "-", "")
				else
					for _, value in variant.values do
						built.steps[variant.step](built, value)
						settle(w.presenter)
						collect(offset, value, `\n      [{variant.step} = {value}]`)
					end
				end
			end
		end
		if #problems > 0 then
			error(
				`{label}: the solver reports {#problems} unwaived overflow(s) — content wider or taller `
					.. `than its own box with nothing to scroll it. A finding at +0 is a plain regression; `
					.. `a finding above +0 is either new, worse than its waiver, or now fires at a smaller `
					.. `text preference than the waiver records (tests/overflow_sweep.spec.luau, WAIVERS):\n{table.concat(
						problems,
						"\n"
					)}`,
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
	three lines — mounted through the same world, settled the same way and read
	through the same `isOverflow` collector the surfaces above use.

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
				if isOverflow(finding.issue) then
					table.insert(out, finding)
				end
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
		expect(overflowPx(largest[1].issue)).toBe(6)
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
	it("every waived large-text overflow still fires — a stale waiver is a fixed defect, delete the line", function()
		local stale: { string } = {}
		for _, waiver in WAIVERS do
			local key = waiverKey(waiver.surface, waiver.variant, waiver.node)
			if WAIVER_MATCHED[key] ~= true then
				table.insert(
					stale,
					`  {waiver.surface} [{waiver.variant}] {waiver.node}\n`
						.. `      recorded {waiver.px}px from +{waiver.since} ({waiver.kind}; {waiver.where})`
				)
			end
		end
		if #stale > 0 then
			error(
				`{#stale} waiver(s) no longer fire anywhere in the sweep. If the surface was fixed, `
					.. `delete the entry (that is the point of the list); if the node moved, re-record it:\n{table.concat(
						stale,
						"\n"
					)}`,
				0
			)
		end
		-- ...and the list is not allowed to quietly grow without anybody noticing
		-- either: 35 is what turning the axis on found on 2026-08-13, and every
		-- addition to it is a decision somebody has to make on purpose.
		expect(#WAIVERS <= 35).toBe(true)
	end)
end)
