--!strict
-- FLAT-THEME BYTE-COMPATIBILITY CHECK (ADR-0020 R9, "cmp-enforced at gate").
--
-- WHY THIS EXISTS. R9 says "flat themes remain byte-identical to the 0.6.0
-- baseline (cmp-enforced at gate)", and the gate's `layered-slots-and-posture`
-- step enforced nothing of the kind: it ran `test -f` on two artifacts and a
-- grep on the test runner. The phase-gate verifier reproduced the consequence —
-- the stored dump was no longer reproducible, the tree had drifted three times
-- further than the artifact said, and the whole claim rested on a number nobody
-- recomputed (phase-gate verifier F1/F2).
--
-- WHAT IT DOES. Regenerates the neutral (unskinned Studio Neutral) render dump
-- to a temp path through the real mount -> renderer -> FakeTarget stack, and
-- compares it node-by-node against the STORED baseline. Any difference outside
-- the allow-list below fails, naming the path and both values.
--
-- WHY AN ALLOW-LIST AND NOT BYTE EQUALITY. The stored 3.5 baseline
-- (`artifacts/theme-packages-and-skinning/final-neutral-dump.json`) is what
-- "byte-identical" is measured against, and this stage genuinely, deliberately
-- changed six node descriptions in it. Asserting byte equality would mean either
-- reverting real decisions or re-pinning the baseline every time — and a
-- baseline that moves whenever it disagrees with the tree proves nothing. So
-- every difference is enumerated here WITH its reason, and anything else is a
-- regression. Adding an entry is a deliberate act with a name on it.
--
--   lune run tools/lune/check_flat_baseline          -- checks; exits 1 on drift
--   lune run tools/lune/check_flat_baseline --list     -- prints the allow-list
--
-- (`-- --list` was documented here and in the hint below until 2026-08-15 and
-- has never worked on this toolchain: lune 0.10.4 does not forward the args
-- after a bare `--`, so `process.args[1]` was nil and the form silently ran the
-- full check instead of listing. Measured both ways.)
--
-- THE BASELINE HAS TWO HALVES, AND ONLY ONE OF THEM IS THE COMPATIBILITY CLAIM
-- (2026-08-06, example-quality-pass). The stored dump renders EIGHT fixtures:
-- `control-vocabulary` — the framework's own controls, which is what R9 is about
-- — and the seven TUTORIAL EXAMPLES, which are content this repo is chartered to
-- rewrite. Roadmap Step 10 rewrote six of the seven (05, 06 and 07 down to their
-- board structure), and the check went red with 1920 findings, every one of them
-- an example node and not one of them on `control-vocabulary`.
--
-- Re-pinning the whole file would have thrown away the framework claim to make an
-- example change quiet, which is exactly the failure this header warns about. So
-- the SEVEN EXAMPLE FIXTURES were re-baselined at that stage's final source and
-- `control-vocabulary` was left byte-untouched — asserted, not assumed: the
-- sha256 of its fixtures is identical before and after (`c38aa648…`). The
-- framework surface is still measured against 0.6.0 through the characterized
-- allow-list below, and the examples are still measured node-for-node, so an
-- ACCIDENTAL change to either one still fails here.
--
-- Record: artifacts/example-quality-pass/flat-baseline-rebaseline.json.
--
-- ...AND THE BASELINE WAS NOT MOVED AGAIN (2026-08-13, swiftui-parity round 2).
-- That round left 379 example deltas here, and the temptation was to re-pin the
-- example fixtures a second time on the same reasoning. It was declined: 357 of
-- the 379 are ONE inserted line's worth of translation in `02_playlist_table`, 22
-- are two containers that changed shape, and every one of them is now a written
-- entry below. Re-pinning would have bought quiet at the price of the only
-- node-for-node record the examples have, and this round is exactly the argument
-- against that — the six findings that mattered were `06_tile_game`'s two readouts
-- leaving `/Stats/Score` and `/Stats/Progress`, and a re-pin would have swallowed
-- them along with the noise.
--
-- TWO WAIVER KINDS WERE ADDED INSTEAD, both narrower than the rect-prefix one:
--   * ALLOWED_Y_SHIFT forgives a subtree that moved DOWN BY ONE NUMBER and did
--     nothing else — the shape of "a line was inserted above it" — and fails if
--     the subtree disagrees with itself or if any x/w/h moved. It reports the
--     shift it forgave on the PASS line.
--   * ALLOWED_CLASS_DRIFT forgives one named node changing from one named class
--     to another named class. Class is otherwise never allowed to differ, which
--     is how a control being quietly swapped for something else shows up here.
--
-- THIS FILE RUNS TWO INSTRUMENTS, AND ONLY ONE OF THEM IS A FROZEN DUMP
-- (2026-08-15, O-22 — the row had been closed on 2026-08-13 and was re-broken the
-- next day by an unrelated correct change, which is the question worth answering
-- once rather than re-pinning every time).
--
--   1. THE REPRODUCIBILITY PIN. `CURRENT` — the stored dump — must byte-equal a
--      fresh regenerate. It carries NO claim about the framework and it has no
--      allow-list: its only job is that the artifact a reader may CITE is current,
--      which is what ADR-0032's migration step 1 needs when it names "the flat
--      baseline is unchanged" as its proof. It is SUPPOSED to go red on every
--      legitimate change to the render, and its red is a chore ("refresh the
--      artifact"), not an accusation. It is not a candidate for an invariant,
--      because "is this file current" has no rule to compare against.
--
--   2. THE COMPATIBILITY CLAIM. `BASELINE_3_5` is frozen at 0.6.0 and is NOT
--      re-pinned — twice declined already, for the reasons above. This is where a
--      difference means something, and it is here that the dump-versus-rule
--      question actually bites.
--
-- THE ANSWER FOR (2) IS BOTH, PICKED PER FACT, and this file already contained the
-- rule form before it had a name: `ALLOWED_ADDED_PROPS` compares a PROPERTY
-- against a RULE ("this key may newly appear, for this reason") rather than
-- against a stored value, which is why the two seam-level corrections that
-- preceded this one (`textSize`, `textFont`) each cost one entry instead of
-- hundreds. A per-path list is right when a decision moves ONE node; a rule is
-- right when a seam-level correction lands on every node of a kind at once —
-- and the third such correction, ruling 5's `textWrapped`, is a rule entry for
-- exactly that reason. The re-pin that keeps getting declined is a THIRD thing:
-- moving `BASELINE_3_5` itself, which would make every future difference agree
-- with whatever the tree does. None of that changed here.
--
-- What DID change is that a rule with no value was too weak: see the `value`
-- paragraph on ALLOWED_ADDED_PROPS.
--
-- DISAPPEARANCE IS STILL THE ONE THING WITH NO WAIVER AT ALL (outside a declared
-- RESHAPED_SUBTREES), and it earned that this round: it was the only instrument in
-- the repo that noticed the tile game's two readouts had left their published
-- paths. `tests/example_readouts.spec.luau` now asks the same question of every
-- tutorial example on every `./run-tests.sh`, because this check is not in the
-- suite and only speaks when somebody runs it.

local process = require("@lune/process")
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local CURRENT = "artifacts/rich-skinning-v2/rows/neutral-render-dump.json"
local BASELINE_3_5 = "artifacts/theme-packages-and-skinning/final-neutral-dump.json"
local GENERATOR = "tools/lune/_theme_baseline"

-- THE CHARACTERIZED DELTAS vs the 0.6.0 (Step 3.5) baseline. Each entry is one
-- node path; `props` means only the prop string may differ. Rects, hit rects and
-- classes may never differ anywhere — the flat solve is unchanged, and that is
-- the substance of the compatibility claim.
-- THE CHARACTERIZED GEOMETRY DELTAS. Rects are the substance of the
-- compatibility claim, so this list is deliberately harder to earn than the prop
-- one: an entry names a FIXTURE and a path prefix, and it exists only when a
-- product decision outside this stage deliberately moved the flat solve. Any
-- rect change outside these prefixes is still a regression, everywhere.
--
-- AN ENTRY MAY NAME ONE EXACT `path` INSTEAD OF A `prefix`, and should whenever
-- the fact it forgives is about one node (2026-08-15, O-22). A prefix waives the
-- whole subtree under it, which is right when a decision reshapes a block and
-- wrong when a CONTAINER's own reported size changed and its children did not —
-- there the prefix would spend the children's rect coverage to buy nothing. The
-- rack entry below is exactly that shape: seven tiles byte-identical, one
-- container 5px narrower.
local ALLOWED_RECT_DRIFT: { { fixture: string, prefix: string?, path: string?, why: string } } = {
	{
		fixture = "06_tile_game",
		path = "/TileGame/Page/rack",
		why = "THE RACK REPORTED A WIDTH IT NEVER DREW, and `02b9df1` (the column-major Grid refactor, "
			.. "2026-08-15) stopped it: 358 -> 353 at 390x844, and nowhere else. `UI.Grid`'s measure summed the "
			.. "UNROUNDED lane share while arrange painted the FLOORED one, so a grid offered a width that does "
			.. "not divide evenly reported up to `lanes - 1` px more than it put on screen. This rack is 7 "
			.. "uniform lanes in 358px with six 4px gaps: (358 - 24) / 7 = 47.71 each, arranged at 47, so the "
			.. "last tile's right edge has always been at 353 and the container claimed 358. The 5px is that "
			.. "over-report to the pixel (at most lanes - 1 = 6). "
			.. "NOTHING MOVED ON SCREEN, and that is the load-bearing half of this entry rather than a "
			.. "reassurance: all seven tiles are byte-identical at all three viewports (x = 16/67/118/169/220/"
			.. "271/322, 47x56 each on the phone), and the desktop and tablet racks are unmoved at 416 because "
			.. "416 divides evenly into 7 lanes of 56 and there was no remainder to lose. So this is the measure "
			.. "side coming into agreement with a paint that never changed — the same measure-versus-paint "
			.. "disagreement this file's 02_playlist_table row-height entry is about, one container class over. "
			.. "IT IS PINNED AS AN EXACT PATH so the seven tiles under it keep their rect coverage. Recorded "
			.. "here because `02b9df1`'s own message says `No baseline moved` — it did, by one node, and this "
			.. "check was the only instrument in the repo that said so.",
	},
	{
		fixture = "02_playlist_table",
		prefix = "/Playlist/Tracks/Main/Body/Rows/",
		why = "the row height is no longer a number this example picks at all (2026-07-27). It was 34, then 48 "
			.. "from a device finding — and a device pass then caught the shape of that answer being wrong "
			.. "rather than the value: a pixel count guessed once, on one device, at one text size, so on a "
			.. "phone with a raised text preference a track title wrapped to THREE lines and painted through "
			.. "the rows either side of it. `UI.Table` derives it now, from the theme's per-paradigm row "
			.. "description and the live text scale, and caps its cells to whatever height wins. This flat "
			.. "solve has no touch capability, so it takes the POINTER row — the dense one-line row a desktop "
			.. "table has always had — which is why every row is 36 here and the table is 72px shorter. Two "
			.. "consequences ride under this same prefix: the rows above the change move up by the "
			.. "difference, and each row hit gains an explicit 44px `hit` rect, because a 36px row is below "
			.. "the target floor the Button contract enforces and the framework expands the target without "
			.. "inflating the plate. Nothing about skinning changed, which is what this file protects.",
	},
	{
		fixture = "02_playlist_table",
		prefix = "/Playlist/Tracks/Main/Header",
		why = "the rating column 132 -> 144, from the director's 2026-07-27 spacing report. The star run is "
			.. "now spaced for the INPUT PARADIGM — a fingertip needs more room between marks than a cursor "
			.. "— and the gap is derived from each package's own `iconSizes` rather than borrowed from its "
			.. "spacing ladder, because the two disagree wildly (Compact Pointer's `xs` is 2px against a "
			.. "12px star, a 17% gap, which is what 'too tight' looked like). Measured, the widest touch run "
			.. "is 136px under Glossy Touch and Fantasy Ornate, so the column is 144 to clear every package "
			.. "with slack instead of by luck. The `fill` Name column absorbs the 12px and every column to "
			.. "its right shifts by exactly that, which is why this covers the whole header rather than one "
			.. "cell. Nothing about skinning changes, which is what this file protects.",
	},
	{
		fixture = "control-vocabulary",
		prefix = "/Vocabulary/More/Header",
		why = "the disclosure caret reserves the PICTURE drawn on it: 12x22 -> 20x22, and the label beside "
			.. "it starts 8px later and is 8px narrower (director report 2026-07-28, defect 2). A semantic "
			.. "icon is painted at the theme's `iconSizes` rung and centred on its node, and the node was "
			.. "measured as the ASCII character the control draws underneath it — a `>` is 12px here and "
			.. "Studio Neutral's `medium` rung is 20, so the picture overhung its own node by 4px on EVERY "
			.. "side and painted into the frame on one side and the label on the other. Measured live under "
			.. "all nine reference configurations, SEVEN overhang and Studio Neutral is one of them, which "
			.. "is exactly why this is a FLAT-baseline delta and not a package one: the flat theme paints "
			.. "the framework's own art too. THE MOVE IS THE FIX. What has NOT moved is any package that "
			.. "declines the icon set (glossy-touch, compact-pointer): the reservation is conditional on "
			.. "the snapshot's derived `iconArt` set, so a theme that draws only the character reserves "
			.. "only the character, and both were re-measured live at their original sizes.",
	},
	{
		fixture = "06_tile_game",
		prefix = "/TileGame/Page/Stats",
		why = "THE STATS LINE WRAPS (2026-08-13). The two readouts need 307px of row and a 320x640 phone's "
			.. "padded page width is 280, so as a plain HStack the line painted outside its own box — the "
			.. "always-on overflow sweep reported +19px there. It is a `UI.Grid` with `minColumnWidth = "
			.. '"intrinsic"` now, the same answer 07_match3\'s artwork row takes: the column count is derived '
			.. "from the widest child's own measured width every solve, so the readouts ride side by side "
			.. "wherever two columns fit and stack where they do not, with no viewport arithmetic to keep in "
			.. "sync. TWO NODES MOVE AND NO CONTENT DOES. The `Stats` container goes from a hug 307 to the "
			.. "page's full `fill` width (a Grid's columns are a fact about the offered box), and `Progress` "
			.. "starts at its own column rather than one `m` gap after `Score`. `Score`'s rect is "
			.. "byte-identical at all three flat viewports — every one of which is wide enough for two columns "
			.. "— so the line is still 22px tall and NOTHING below `Stats` moves. "
			.. "THE ALTERNATIVE THIS REPLACED was a `UI.ViewThatFits` candidate ladder, which needed each "
			.. "readout written twice and left the losing copy mounted at a deliberate zero rect: the two "
			.. "readouts left `/Stats/Score` and `/Stats/Progress` for a whole mission, the suite could not "
			.. "tell (a losing candidate answers `adapter.node(path)` with the right `text` too), and THIS "
			.. "CHECK was the only thing that said so. tests/example_readouts.spec.luau now asks the same "
			.. "question of every tutorial example inside `./run-tests.sh`.",
	},
	{
		fixture = "07_match3",
		prefix = "/Match3/Page/Art",
		why = 'THE ARTWORK CONTROLS WRAP (device report 2026-08-12, IMG_3690: "Fail a load" sliced by the '
			.. "right screen edge on a portrait phone). Three buttons carrying full sentences need ~580px of "
			.. "row and a 359px phone has 327; as an HStack the row painted past its own box, and the solver "
			.. 'said so on every phone viewport ("content overflows this hstack by 253px on the main axis") '
			.. 'with nothing reading it. It is a `UI.Grid` with `minColumnWidth = "intrinsic"` now: one '
			.. "column on a phone, one row on a desktop. The three buttons stay DIRECT children, so every "
			.. "path this example publishes is unchanged — `Reload`'s rect is byte-identical everywhere (it "
			.. "is the first cell) and only `Deliver` and `Break` move to their column starts. Recorded in "
			.. "docs/plans/device-bug-round-2026-08-12.md, Group B.",
	},
	{
		fixture = "02_playlist_table",
		prefix = "/Playlist/Page/Tracks/Main/Header/Head-name",
		why = "the LENGTH COLUMN IS GONE and the `fill` Name column absorbed its 70px, header included -- "
			.. "574 -> 644 on tablet, 1034 -> 1104 on desktop, 144 -> 214 on the phone, which is the removed "
			.. "column's own fixed width to the pixel at every viewport. Removed on 2026-08-13 because a "
			.. "THIRD fixed column plus edit mode's TWO leading gutters (Table's 32px reorder \u{2261} and, "
			.. "new this round, the theme's `editAffordance` gutter for `rowActions`' red minus) solved the "
			.. 'Name cell to 6px and its text to 0px at 320x640 -- six "content box collapses to 0px on x" '
			.. "diagnostics. The shipped example was already spending the name down to 26px there with no "
			.. "diagnostic and nobody looking. Narrowing the rating column to 120 was measured as the "
			.. "alternative and rejected: it silenced the solver and still left 14px of name. Only "
			.. "`Head-name` moves -- `Head-rating` is byte-identical, because a fill column absorbs leftover "
			.. "at its own end. The example's own columns list carries the full measurement.",
	},
	{
		fixture = "02_playlist_table",
		prefix = "/Playlist/Page/Hint",
		why = 'THE HINT NAMES THE SWIPE NOW (director device round 2026-08-13, finding 2: "on iOS with touch '
			.. "you can swipe a row (either side) to get the edit controls even if the table isn't in edit "
			.. 'mode -- we lost that"). The example gained `rowActions` on BOTH edges, so the one line of '
			.. "on-screen teaching this page has had to say so; it used to name only the drag-reorder. "
			.. 'A LONGER STRING IS THE WHOLE DELTA AND NOTHING REFLOWS: the label is `policy = "none"` '
			.. "text in a fill column, so its WIDTH follows the string (495 -> 651 on desktop and tablet, "
			.. "356 -> 330 on the phone, where it already wrapped to two lines and the second line is now "
			.. "shorter) while its HEIGHT is byte-identical at all three viewports -- 17, 17, 34 before and "
			.. "after. Nothing below it moves, which is why this needs no y-shift waiver to go with it. The "
			.. "rows themselves are wrapped in a `RowActions-<key>/Content/` segment by the same change, and "
			.. "that is already covered by this fixture's `/Playlist/` RESHAPED_SUBTREES entry below.",
	},
	{
		fixture = "07_match3",
		prefix = "/Match3/Page/Reset",
		why = "the one consequence of the entry above, on the one viewport where the artwork Grid takes three "
			.. "rows instead of one: at 390x844 the block grows 46 -> 154 and the New-board button below it "
			.. "moves down by exactly that 108. Unmoved on tablet and desktop, where the Grid is still a row.",
	},
}

-- A PURE VERTICAL TRANSLATION, WHICH IS NOT THE SAME WAIVER AS "rects may drift
-- here". Inserting one line into a page moves every node below it and changes
-- nothing else about any of them — hundreds of deltas, one fact. `ALLOWED_RECT_DRIFT`
-- could absorb that with a prefix, but it would then be blind to a REAL regression
-- under the same prefix forever, which is too much to spend on a paragraph of text.
--
-- So this list waives a shift instead of a scope. A rect or hit rect under one of
-- these prefixes is forgiven only if x, width and height are byte-identical and
-- the y delta is the SAME NUMBER for every waived node in that fixture and
-- viewport. Two different shifts under one entry, or any change to x/w/h, is still
-- a failure — and the shift that WAS observed is printed on the PASS line, so the
-- waiver reports its own size rather than hiding behind a prefix.
local ALLOWED_Y_SHIFT: { { fixture: string, prefix: string, why: string } } = {
	{
		fixture = "02_playlist_table",
		prefix = "/Playlist/Page/Tracks",
		why = "the example gained a NOW-PLAYING line above the table (swiftui-parity round 2, Phase 3: the "
			.. 'Table primary action had no visible result, so the tutorial\'s "open a row" gesture proved '
			.. "nothing on screen). It is one `label`-sized secondary Text between the hint and the table, and "
			.. "every node in the page ScrollView below it moves down by exactly its height plus the page gap "
			.. "— 42px at 390x844, where the sentence wraps to two lines in 348px, and 25px on the tablet and "
			.. "desktop rows, where it fits on one. Nothing changes width, height or x: this entry FAILS if "
			.. "any of the 357 nodes it covers does anything but move down by that one number.",
	},
	{
		fixture = "02_playlist_table",
		prefix = "/Playlist/Page/Restore",
		why = "the same single insertion, one sibling further down the page (see the entry above).",
	},
}

-- A CLASS CHANGE ON ONE NAMED NODE, spelled out both ways. Class is otherwise
-- never allowed to differ anywhere, and it should not be: it is how a control
-- being quietly replaced by something else would show up. An entry here names the
-- fixture, the EXACT path (not a prefix), and both the old and the new class, so
-- it waives one substitution and nothing else — a third class on the same node
-- still fails.
local ALLOWED_CLASS_DRIFT: { { fixture: string, path: string, from: string, to: string, why: string } } = {
	{
		fixture = "06_tile_game",
		path = "/TileGame/Page/Stats",
		from = "HStack",
		to = "Grid",
		why = "the stats line wraps — see the ALLOWED_RECT_DRIFT entry of the same name for the whole "
			.. "reasoning. The container changes; its two children do not, and they are still its DIRECT "
			.. "children at the paths this example has always published.",
	},
	{
		fixture = "07_match3",
		path = "/Match3/Page/Art",
		from = "HStack",
		to = "Grid",
		why = "the artwork controls wrap — see the ALLOWED_RECT_DRIFT entry of the same name. Same shape of "
			.. "change, same mission, three buttons still direct children.",
	},
}

local ALLOWED_PROP_DRIFT: { { path: string, why: string } } = {
	{
		path = "/__popupcatcher__/catcher",
		why = 'surface="" -> "plain", plus the resolved control textFont/textSize that any SURFACED Button '
			.. "records in this dump. From the 2026-08-13 popup-catcher fix (`7fb325f`): this node is the "
			.. "presenter's own full-viewport tap catcher, mounted whenever a contribution publishes "
			.. "`outsideDismiss.active` -- which a swipe tray does for as long as it is open. It declared NO "
			.. "surface, and absent is not invisible: `chrome_slots.classify` falls every Button through to "
			.. "the `control` slot, so every installed theme painted its solid control plate across the whole "
			.. "screen. The director photographed it as a band over the demo picker (topscreen.mov). "
			.. '`surface="plain"` is the declaration that it is invisible, the same one `mountScrim` already '
			.. "carried and which its later-written sibling never inherited. "
			.. "WHAT ROUND 3 ACTUALLY CHANGED IS `surface` ALONE. This entry is checked against the 0.6.0 "
			.. "baseline, where the node read `label=;padding=12`, so the diff shown here also carries "
			.. "`textFont`/`textSize` -- but those were ALREADY on the node in the immediately-prior neutral "
			.. "dump, with NO surface declared, so they are older drift and not caused by this fix. Verified "
			.. "by diffing the regenerated dump against its predecessor: exactly 3 nodes changed, at the three "
			.. "viewports, and the only added token is `surface=plain`. "
			.. "They are inert either way -- this node's `label` is empty in the same dump row, so nothing "
			.. "draws them. Class, rect and hit are byte-identical at all three viewports.",
	},
	{
		path = "/Playlist/Page/Hint",
		why = 'the same 2026-08-13 swipe-actions change as the rect entry above: `text` only. "Type to filter '
			.. '\u{b7} tap stars to rate \u{b7} drag rows to reorder" -> "Type to filter \u{b7} tap stars to '
			.. 'rate \u{b7} swipe a row either way for its actions". Every other prop on the node -- role, '
			.. "textSize, textFont -- is byte-identical, which is the point of listing the path rather than "
			.. "waiving a prefix.",
	},
	{
		path = "/Vocabulary/Name/ClearWhen/then/Clear",
		why = 'surface="" -> chip: from the same iPhone 15 Pro pass. With the default control surface the '
			.. "clear button was a plate the same shade as the field it sits inside, and the reporter could "
			.. "not find the clear affordance at all while a filter was active. A chip is the smallest "
			.. "surface that reads as a separate thing on top of a field. "
			.. "AND padding 12 -> 0 (director round 10, 2026-07-26): a Button's default text inset exists to "
			.. "keep a WORD off a plate's edge, and spent on a 28px box it left 4px for the ×, which then "
			.. "drew at its natural size OUTSIDE its own plate — photographed on two themes. The box is now "
			.. "`minMax` with 28 as the FLOOR, so this node's RECT is unchanged under every flat package and "
			.. "only grows where a package's own frame reserves room inside it.",
	},
	{
		path = "/Vocabulary/Volume/TrackHost/Groove/Rail",
		why = 'surface=control -> "": the ADR-0019 fix round removed the public `surface` from the slider '
			.. "rail so a theme's gradient could not make a value control see-through (src/controls/slider.luau: "
			.. '"NO PUBLIC surface ON EITHER"). Predates this stage; the rail still paints, through luau-slot-*.',
	},
	{
		path = "/Vocabulary/Volume/TrackHost/Groove/Thumb",
		why = 'surface=raised -> "": the same ADR-0019 ruling, same file, same reason.',
	},
	{
		path = "/Vocabulary/Load/Bar",
		why = 'surface=control -> "": ADR-0020 R3 gave the bar family its OWN native paint through the '
			.. "`luau-slot-barTrack` rule, exactly as the slider's rail has. Borrowing a public surface would "
			.. "have taken that surface's gradient (and its alpha) with it. SANCTIONED, this stage.",
	},
	{
		path = "/Vocabulary/Load/Bar/Fill",
		why = 'surface=accent -> "": the same R3 ruling for `luau-slot-barFill`. SANCTIONED, this stage.',
	},
	{
		path = "/Vocabulary/Count/Dec",
		why = "label U+2212 -> '-': R4's fallback-glyph table is ASCII by construction, because a package may "
			.. "name any font and the framework cannot know which characters that font contains. Decision "
			.. "packet in artifacts/rich-skinning-v2/review-packet.md; RS-P1 capture 9b.",
	},
	{
		path = "/Vocabulary/More/Header",
		why = 'label "▾ More" -> "": the disclosure header became a CONTENT button so its caret could REQUEST '
			.. "the semantic chevron icon (phase-gate verifier F3 — the reference packages' caret art was dead). "
			.. "`label` stays the semantic label on the mounted node; the visible text moved into the children "
			.. "below. Same rect, same hit rect, same height.",
	},
}

-- Nodes the current tree has and the 3.5 baseline does not. Additions are as
-- much of a compatibility statement as changes, so they are enumerated too.
local ALLOWED_NEW_NODES: { { path: string, why: string } } = {
	{ path = "/Vocabulary/More/Header/CaretOpen", why = "the expanded caret's structural region (F3)" },
	{
		path = "/Vocabulary/More/Header/CaretOpen/then/Caret",
		why = 'the caret node itself: draws the ASCII glyph and carries `icon = "chevron.down"` (F3)',
	},
	{ path = "/Vocabulary/More/Header/CaretShut", why = "the collapsed caret's structural region (F3)" },
	{
		path = "/Vocabulary/More/Header/Label",
		why = "the header's visible text, split out so the caret's glyph suppression cannot reach it (F3)",
	},
	{
		path = "/Playlist/Page/NowPlaying",
		why = "the table's primary action had no VISIBLE RESULT (swiftui-parity round 2, Phase 3). The "
			.. 'tutorial tells the reader to "open a row", and opening one changed a signal nothing on screen '
			.. "read — so the gesture proved nothing to a player and nothing to a screenshot. One `label`-sized "
			.. "secondary Text between the hint and the table now says what is playing. Its only geometric "
			.. "consequence is that everything below it in the page ScrollView moves down by one line, which "
			.. "is pinned as a uniform shift in ALLOWED_Y_SHIFT rather than waived as free rect drift.",
	},
}

-- A SUBTREE THAT WAS DELIBERATELY RE-SHAPED. The two lists above are per-NODE,
-- which is right when a decision moves a node; it is the wrong instrument when a
-- decision replaces a hand-rolled composite with a framework CONTROL, because
-- then every node under one path is new and every old one is gone, and a
-- per-node list would be three hundred identical sentences.
--
-- An entry names a fixture, a path prefix, and the reason — and it waives ONLY
-- the appearance and disappearance of nodes strictly under that prefix. Rect,
-- hit-rect and prop drift on every node that still exists elsewhere is checked
-- exactly as before, so this cannot be used to hide a regression next door.
local RESHAPED_SUBTREES: { { fixture: string, prefix: string, why: string } } = {
	{
		fixture = "02_playlist_table",
		prefix = "/Playlist/",
		why = "THE PAGE SCROLLS, NOT JUST THE ROWS (director report 2026-07-27, this example in landscape: "
			.. "\"just the table scrolls. really the whole view should scroll, as it's unusable having just "
			.. 'the table scroll"). The title, filter and hint were a fixed block above the table, so on a '
			.. "short landscape viewport they took 45-55% of the screen and the only thing that could move "
			.. "was the rows inside what was left — measured, a 144px row window on a 320px-tall screen. The "
			.. "example now wraps its content in a page `UI.ScrollView` and the table is a BLOCK "
			.. "(`scrolls = false`), so every node gains one `/Page` path segment. That segment is the whole "
			.. "delta: no control changed, and the table's own `$`-anchored matchers still match because they "
			.. "anchor on the table id, not on the screen root. "
			.. "A SECOND SEGMENT, AND WHAT IT COSTS (2026-08-13, swipe actions). The example now declares "
			.. "`rowActions` on both edges, and `Table` wraps every row that has them, so a row's path gains "
			.. "`RowActions-<key>/Content/` between its `[key@v]` ForEach slot and its own `Row/...` tree. "
			.. "This entry therefore forgives 306 more node paths than it did, and that is a REAL loss of "
			.. "node-for-node coverage against 0.6.0 rather than a formality -- the compared count drops "
			.. "1773 -> 1467. It is recorded here rather than hidden because the alternative was re-pinning "
			.. "the example fixtures a third time, which this file's header argues against for exactly this "
			.. "reason. What replaces the lost record inside `./run-tests.sh`: "
			.. "tests/example_readouts.spec.luau (every published readout path still resolves) and the six "
			.. "device-round cases in tests/examples_gallery.spec.luau, which drive the wrapped rows' own "
			.. "paths on a phone class set end to end.",
	},
	{
		fixture = "02_playlist_table",
		prefix = "/Tracks/ToggleWhen",
		why = "the table's auto Edit/Done affordance moved from an ANCHOR child of the table root — pinned "
			.. "top-right and consuming no height — into a TOOLBAR ROW inside /Main (director round 12, "
			.. "2026-07-27). It was invisible as an overlay only while it was 24px tall and the header band "
			.. "it covered was 28; once round 10 let it grow for a theme's own frame it became 34-68px and "
			.. "sat on the header AND the first row in every package. The node therefore moves from "
			.. "/Tracks/ToggleWhen to /Tracks/Main/ToggleWhen (+ a Toolbar row). NOTHING else moves in the "
			.. "flat render: the toggle is a TOUCH affordance and these fixtures are pointer, so it is not "
			.. "shown and reserves no height here.",
	},
	{
		fixture = "02_playlist_table",
		prefix = "/Main/ToggleWhen",
		why = "the other end of the same move (see the entry above).",
	},
	{
		fixture = "02_playlist_table",
		prefix = "/Row/Cells/Cell-rating/",
		why = "the rating cell became `LuauUI.newRating` (director round 10, 2026-07-26). It was five "
			.. "`UI.Button`s under a Grip, hand-rolled in the example, and a physical-device pass showed why "
			.. "that shape is wrong: a Button is a `control` to every theme, so under Glossy Touch a rating "
			.. "rendered as five glossy PILLS and under Glossy Mobile — whose control recipe is a raised "
			.. "SHADOW — the five shadows overlapped into a smeared dark band behind the row. It was also "
			.. "five focus stops for one number. The replacement is glyph Texts under ONE Grip: "
			.. "`Cell-rating/Cell/Stars/StarN` (Buttons) became `Cell-rating/Rating/Stars/StarN` (Texts) plus "
			.. "`Cell-rating/Rating/Strip`. NOTHING outside this cell moved.",
	},
}

-- A PROP KEY THAT MAY NEWLY APPEAR anywhere, with its reason. This is a
-- narrower waiver than it looks: the key is stripped only where the baseline did
-- NOT have it, and the rest of the prop string must still match byte for byte —
-- so a changed value, a removed prop or any other new key still fails, on every
-- node. It exists because a seam-level correction lands on hundreds of nodes at
-- once and a per-path list would then be a wall of identical sentences rather
-- than a characterization anybody reads.
--
-- AN ENTRY MAY ALSO PIN THE VALUE (`value`), and when it can, it must (2026-08-15,
-- O-22). Without one this list says only "this key may appear", which is the
-- weakest sentence a baseline can hold: it forgives the key arriving with ANY
-- value, forever, on every node. `textSize` and `textFont` genuinely cannot be
-- pinned — their whole content is that each node resolved to its OWN role — but
-- `textWrapped` can, and the value IS the invariant there rather than a detail
-- (see its entry). A pinned entry forgives that one value and fails on any other,
-- so the rule survives a legitimate new prop without going blind to a wrong one.
local ALLOWED_ADDED_PROPS: { { prop: string, value: string?, why: string } } = {
	{
		prop = "textSize",
		why = "the class's INTRINSIC typography role now reaches PAINT (director fix round 2026-07-25). It used "
			.. "to reach only the MEASURE seam while the adapter drew a hardcoded 16, so a package that moved "
			.. "`type.control.size` was reserved for at one size and drawn at another — compact-pointer's 13px "
			.. 'control role wrapped a one-line "Play" into "Pla"/"y" inside a box the solver had sized '
			.. "correctly for 13. Studio Neutral's own roles are body=16 / control=18, and the solver ALREADY "
			.. "measured those, so every rect and hit rect below is unchanged: what moves is the size the engine "
			.. "draws a Button/TextField label at (16 -> 18) and nothing else. SANCTIONED, this stage.",
	},
	{
		prop = "textFont",
		why = "the typography role's FACE now reaches PAINT beside its size (F2, 2026-08-02) — the exact "
			.. "correction the `textSize` entry above describes, one property later. A role has always carried a "
			.. "font DESCRIPTOR and the solver has always measured with it; the adapter drew whatever face it "
			.. "hardcoded at creation, so a package that gave a role its own weight was reserved for one family "
			.. "and drawn in another. THE INVARIANT THIS ENTRY PINS: under Studio Neutral every one of the six "
			.. "pre-existing roles resolves to `BuilderSans#Regular#Normal`, which is byte-identical to the face "
			.. "the adapter hardcoded — so no glyph on any flat node moves, and every rect, hit rect and other "
			.. "prop below still matches byte for byte. What the value records is WHICH role each node resolved "
			.. "to, which is new information rather than a new appearance.",
	},
	{
		prop = "textWrapped",
		value = "false",
		why = "the WRAP VERDICT reaches paint (`fb76787`, director ruling 5, 2026-08-13) — the third and last "
			.. "member of the same family as the two entries above: a fact the solver has always known, arriving "
			.. "at the seam that draws it. `screen_target`'s own TextWrapped rule sees the STRING and not the "
			.. "box, so it cannot answer \"does this phrase's longest word fit the width this node ended up "
			.. 'with"; the solver can, publishes it as `textFacts.wraps`, and `applyTextVerdicts` writes it '
			.. "(src/layout/solver.luau:1184-1205, src/render/renderer.luau:1739-1751). "
			.. "WHY THE VALUE IS PINNED TO `false` AND WHAT THAT PIN IS FOR. The seam is minimal-write and `nil` "
			.. 'means "never written", which is the adapter\'s own default (wrap on whitespace) — so a node the '
			.. "solver rules WRAPPABLE costs zero writes and appears in this dump with no `textWrapped` key at "
			.. "all. `false` is therefore the only value a fresh node can carry, and a `true` in this dump would "
			.. "mean the renderer had spent a write restoring the engine default: the zero-write contract broken, "
			.. "on hundreds of nodes, silently. Pinning the value makes that a failure HERE rather than a "
			.. "performance regression nobody measures. Measured on the regenerated dump: 312 nodes carry the "
			.. "key, every one of them `false`, and the wrapping nodes carry nothing — 02_playlist_table's Hint "
			.. "wraps to two lines on the phone (34px tall) and has no `textWrapped` key, while its one-word "
			.. "Title beside it does. "
			.. "NO GEOMETRY MOVES WITH IT: the solver already MEASURED every one of these boxes with the same "
			.. "verdict, so the write only tells the engine what the box was reserved for. Asserted, not "
			.. "assumed — the regeneration that added these 312 keys moved exactly ONE rect in the whole flat "
			.. "render, and that one has its own entry and a different cause (the rack; see ALLOWED_RECT_DRIFT).",
	},
}

-- is this key's APPEARANCE characterized, at this value? An entry with no `value`
-- forgives the key whatever it carries; an entry WITH one forgives that value and
-- nothing else, so a wrong value stays a failure on the node it landed on.
local function addedPropAllowed(prop: string, value: string): boolean
	for _, entry in ALLOWED_ADDED_PROPS do
		if entry.prop == prop then
			return entry.value == nil or entry.value == value
		end
	end
	return false
end

-- the prop string with every CHARACTERIZED-ADDITION key the baseline did not
-- carry removed, so the remainder can be compared byte for byte
local function withoutAddedProps(was: string?, now: string?): string?
	if now == nil or now == "" then
		return now
	end
	local had: { [string]: boolean } = {}
	for entry in string.gmatch(was or "", "[^;]+") do
		had[string.match(entry, "^([^=]+)=") or entry] = true
	end
	local kept: { string } = {}
	for entry in string.gmatch(now, "[^;]+") do
		local key, value = string.match(entry, "^([^=]+)=(.*)$")
		if key == nil then
			key, value = entry, ""
		end
		if had[key :: string] or not addedPropAllowed(key :: string, value :: string) then
			table.insert(kept, entry)
		end
	end
	return table.concat(kept, ";")
end

local function index(path: string): { [string]: any }
	local decoded: any = serde.decode("json", fs.readFile(path))
	local out: { [string]: any } = {}
	for _, fixture in decoded.fixtures do
		for _, which in { "nodes", "opened" } do
			for _, node in (fixture :: any)[which] or {} do
				out[`{fixture.fixture}|{fixture.viewport}|{which}|{node.path}`] = node
			end
		end
	end
	return out
end

local function reshaped(key: string, path: string): boolean
	for _, entry in RESHAPED_SUBTREES do
		if string.find(key, entry.fixture, 1, true) ~= nil and string.find(path, entry.prefix, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function reasonFor(list: { { path: string, why: string } }, path: string): string?
	for _, entry in list do
		if entry.path == path then
			return entry.why
		end
	end
	return nil
end

-- "<x>,<y> <w>x<h>" -> four numbers, or nil for anything else (the dump writes the
-- string "nil" for a node with no hit rect, and a rect that appears on one side
-- only is a change this must NOT quietly call a translation).
local function parseRect(text: string?): { x: number, y: number, w: number, h: number }?
	if text == nil then
		return nil
	end
	local x, y, w, h = string.match(text, "^(-?%d+),(-?%d+) (%d+)x(%d+)$")
	if x == nil then
		return nil
	end
	return { x = tonumber(x) :: number, y = tonumber(y) :: number, w = tonumber(w) :: number, h = tonumber(h) :: number }
end

-- the ALLOWED_Y_SHIFT entry covering this node, or nil
local function yShiftScope(fixture: string, path: string): number?
	for i, entry in ALLOWED_Y_SHIFT do
		if entry.fixture == fixture and string.find(path, entry.prefix, 1, true) == 1 then
			return i
		end
	end
	return nil
end

local function classDriftAllowed(fixture: string, path: string, from: string?, to: string?): boolean
	for _, entry in ALLOWED_CLASS_DRIFT do
		if entry.fixture == fixture and entry.path == path and entry.from == from and entry.to == to then
			return true
		end
	end
	return false
end

if process.args[1] == "--list" then
	print("check_flat_baseline: characterized deltas vs " .. BASELINE_3_5)
	for _, entry in ALLOWED_PROP_DRIFT do
		print(`  prop  {entry.path}\n        {entry.why}`)
	end
	for _, entry in ALLOWED_NEW_NODES do
		print(`  new   {entry.path}\n        {entry.why}`)
	end
	for _, entry in ALLOWED_ADDED_PROPS do
		local scope = if entry.value ~= nil then `(any node, ONLY as "{entry.value}")` else "(any node, any value)"
		print(`  added prop {entry.prop} {scope}\n        {entry.why}`)
	end
	for _, entry in ALLOWED_RECT_DRIFT do
		print(
			`  rect  {entry.fixture} {entry.path or entry.prefix}{if entry.path ~= nil then " (this node only)" else ""}\n        {entry.why}`
		)
	end
	for _, entry in ALLOWED_Y_SHIFT do
		print(`  y-shift {entry.fixture} {entry.prefix} (one uniform dy, x/w/h byte-identical)\n        {entry.why}`)
	end
	for _, entry in ALLOWED_CLASS_DRIFT do
		print(`  class {entry.fixture} {entry.path} {entry.from} -> {entry.to}\n        {entry.why}`)
	end
	for _, entry in RESHAPED_SUBTREES do
		print(`  reshaped {entry.fixture} {entry.prefix}\n        {entry.why}`)
	end
	return
end

-- 1. REGENERATE. A stored dump nobody recomputes is exactly the failure this
-- exists to catch, so the check never trusts the checked-in file's content
-- without reproducing it first.
local temp = `/tmp/luauui-flat-baseline-{os.time()}.json`
local regen = process.exec("lune", { "run", GENERATOR, "--", temp })
if not regen.ok then
	print("check_flat_baseline: FAIL — could not regenerate the neutral dump")
	print(regen.stderr)
	process.exit(1)
end

-- AN ABSENT INPUT IS A NAMED PROBLEM, NOT A STACK TRACE (2026-08-15). Both of
-- this check's stored inputs used to be read with a bare `fs.readFile`, so a
-- missing one died with `No such file or directory` and a Lune stack — which is
-- what a fresh clone got, every time, because `artifacts/**/*.json` is gitignored.
-- The exit code was always 1, so no gate ever passed on it; what was lost was the
-- one sentence that says which file and what to do about it. BASELINE_3_5 is now
-- tracked (see .gitignore) and CURRENT is still not, deliberately, so this is the
-- message a clone reads before its first regenerate.
local problems: { string } = {}
if not fs.isFile(BASELINE_3_5) then
	print(`check_flat_baseline: FAIL — the 0.6.0 baseline {BASELINE_3_5} is missing.`)
	print("This file is NOT regenerable: it is a frozen snapshot of the 0.6.0 tree and the only")
	print("input to R9's byte-compatibility claim. Restore it from git rather than re-rendering one.")
	process.exit(1)
end
if not fs.isFile(CURRENT) then
	print(`check_flat_baseline: FAIL — the stored dump {CURRENT} is missing.`)
	print(`It is gitignored and regenerable: \`lune run {GENERATOR} -- {CURRENT}\`.`)
	process.exit(1)
end
local stored = fs.readFile(CURRENT)
local fresh = fs.readFile(temp)
if stored ~= fresh then
	table.insert(
		problems,
		`the stored dump {CURRENT} is not reproducible from the current tree — regenerate it `
			.. `(\`lune run {GENERATOR}\`) and re-characterize the diff in `
			.. "artifacts/rich-skinning-v2/rs-a1-image-is-element.json"
	)
end

-- 2. COMPARE against the 0.6.0 baseline, allow-list in hand.
local base = index(BASELINE_3_5)
local now = index(temp)
local checked = 0
-- Every y-translation an ALLOWED_Y_SHIFT entry forgave, bucketed per entry and per
-- (fixture, viewport). The waiver is only granted once the whole bucket agrees on
-- one number, which is decided after the loop.
local shifts: { [string]: { [number]: boolean } } = {}
for key, node in now do
	local was = base[key]
	if was == nil then
		if reasonFor(ALLOWED_NEW_NODES, node.path) == nil and not reshaped(key, node.path) then
			table.insert(problems, `NEW node '{key}' is not in the characterized allow-list`)
		end
		continue
	end
	checked += 1
	local fixture = string.match(key, "^([^|]+)|") or ""
	local viewport = string.match(key, "^[^|]+|([^|]+)|") or ""
	local rectDriftAllowed = false
	for _, entry in ALLOWED_RECT_DRIFT do
		-- an entry names ONE node (`path`) or a subtree (`prefix`); see the list's header
		local scoped = if entry.path ~= nil
			then node.path == entry.path
			else string.find(node.path, entry.prefix :: string, 1, true) == 1
		if string.find(key, entry.fixture, 1, true) ~= nil and scoped then
			rectDriftAllowed = true
			break
		end
	end
	local shiftEntry = yShiftScope(fixture, node.path)
	for _, field in { "class", "rect", "hit" } do
		if was[field] ~= node[field] then
			if field == "class" and classDriftAllowed(fixture, node.path, was.class, node.class) then
				continue
			end
			if (field == "rect" or field == "hit") and rectDriftAllowed then
				continue
			end
			if (field == "rect" or field == "hit") and shiftEntry ~= nil then
				local a, b = parseRect(was[field]), parseRect(node[field])
				-- a translation and only a translation: everything but y identical
				if a ~= nil and b ~= nil and a.x == b.x and a.w == b.w and a.h == b.h then
					local bucket = `{shiftEntry}|{fixture}|{viewport}`
					local seen = shifts[bucket]
					if seen == nil then
						seen = {}
						shifts[bucket] = seen
					end
					seen[b.y - a.y] = true
					continue
				end
			end
			table.insert(problems, `{key}: {field} changed '{was[field]}' -> '{node[field]}' (never allowed)`)
		end
	end
	local nowProps = withoutAddedProps(was.props, node.props)
	if was.props ~= nowProps and reasonFor(ALLOWED_PROP_DRIFT, node.path) == nil then
		table.insert(problems, `{key}: props changed '{was.props}' -> '{node.props}' and is not characterized`)
	end
end
-- THE SHIFT HAS TO BE ONE NUMBER. An entry says "a line was inserted above this
-- subtree"; if two nodes under it moved by different amounts then something else
-- moved too, and that is a finding rather than a translation.
local shiftReport: { string } = {}
local shiftBuckets: { string } = {}
for bucket in shifts do
	table.insert(shiftBuckets, bucket)
end
table.sort(shiftBuckets)
for _, bucket in shiftBuckets do
	local values: { number } = {}
	for dy in shifts[bucket] do
		table.insert(values, dy)
	end
	table.sort(values)
	local entryIndex = tonumber(string.match(bucket, "^(%d+)|")) :: number
	local entry = ALLOWED_Y_SHIFT[entryIndex]
	local where = string.match(bucket, "^%d+|(.+)$") or bucket
	if #values ~= 1 then
		local list: { string } = {}
		for _, dy in values do
			table.insert(list, tostring(dy))
		end
		table.insert(
			problems,
			`{where} {entry.prefix}: ALLOWED_Y_SHIFT forgives ONE uniform vertical shift and this subtree `
				.. `moved by {#values} different amounts ({table.concat(list, ", ")}) — that is not an insertion `
				.. "above it, so it is not characterized"
		)
	else
		table.insert(shiftReport, `{where} {entry.prefix} +{values[1]}px`)
	end
end
for key, node in base do
	if now[key] == nil and not reshaped(key, node.path) then
		table.insert(problems, `node '{key}' DISAPPEARED from the flat render (never allowed)`)
	end
end
fs.removeFile(temp)

if #problems > 0 then
	print(`check_flat_baseline: FAIL [UI-STYLE-001] — {#problems} problem(s):`)
	for _, entry in problems do
		print(`  - {entry}`)
	end
	print("hint: `lune run tools/lune/check_flat_baseline --list` prints every characterized delta and why.")
	process.exit(1)
end
print(
	`check_flat_baseline: PASS ({checked} flat nodes byte-compared against {BASELINE_3_5}; `
		.. `{#ALLOWED_PROP_DRIFT} characterized prop deltas, {#ALLOWED_NEW_NODES} characterized new nodes, `
		.. `{#ALLOWED_ADDED_PROPS} characterized added prop keys, `
		-- SAY WHAT WAS ALLOWED, NOT WHAT IS EXPECTED. This line read "0
		-- rect/hit/class changes" unconditionally, which would have gone on
		-- saying so beside a characterized rect delta — a true-sounding sentence
		-- about a check that did not happen.
		.. `{#ALLOWED_RECT_DRIFT} characterized rect-drift scope(s), `
		.. `{#ALLOWED_CLASS_DRIFT} characterized class substitution(s); no other rect/hit/class change)`
)
-- THE WAIVER REPORTS ITS OWN SIZE. A y-shift entry is only as trustworthy as the
-- number it turned out to forgive, so the number is printed rather than implied —
-- a shift that silently doubled would otherwise pass with the same sentence.
if #shiftReport > 0 then
	table.sort(shiftReport)
	print(`  uniform vertical shifts forgiven: {table.concat(shiftReport, "; ")}`)
end
