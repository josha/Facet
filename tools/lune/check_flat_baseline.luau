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
--   lune run tools/lune/check_flat_baseline -- --list  -- prints the allow-list

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
local ALLOWED_RECT_DRIFT: { { fixture: string, prefix: string, why: string } } = {
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
}

local ALLOWED_PROP_DRIFT: { { path: string, why: string } } = {
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
			.. "anchor on the table id, not on the screen root.",
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
local ALLOWED_ADDED_PROPS: { { prop: string, why: string } } = {
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
}

local function addedPropReason(prop: string): string?
	for _, entry in ALLOWED_ADDED_PROPS do
		if entry.prop == prop then
			return entry.why
		end
	end
	return nil
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
		local key = string.match(entry, "^([^=]+)=") or entry
		if had[key] or addedPropReason(key) == nil then
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

if process.args[1] == "--list" then
	print("check_flat_baseline: characterized deltas vs " .. BASELINE_3_5)
	for _, entry in ALLOWED_PROP_DRIFT do
		print(`  prop  {entry.path}\n        {entry.why}`)
	end
	for _, entry in ALLOWED_NEW_NODES do
		print(`  new   {entry.path}\n        {entry.why}`)
	end
	for _, entry in ALLOWED_ADDED_PROPS do
		print(`  added prop {entry.prop} (any node)\n        {entry.why}`)
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

local problems: { string } = {}
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
for key, node in now do
	local was = base[key]
	if was == nil then
		if reasonFor(ALLOWED_NEW_NODES, node.path) == nil and not reshaped(key, node.path) then
			table.insert(problems, `NEW node '{key}' is not in the characterized allow-list`)
		end
		continue
	end
	checked += 1
	local rectDriftAllowed = false
	for _, entry in ALLOWED_RECT_DRIFT do
		if string.find(key, entry.fixture, 1, true) ~= nil and string.find(node.path, entry.prefix, 1, true) == 1 then
			rectDriftAllowed = true
			break
		end
	end
	for _, field in { "class", "rect", "hit" } do
		if was[field] ~= node[field] then
			if (field == "rect" or field == "hit") and rectDriftAllowed then
				continue
			end
			table.insert(problems, `{key}: {field} changed '{was[field]}' -> '{node[field]}' (never allowed)`)
		end
	end
	local nowProps = withoutAddedProps(was.props, node.props)
	if was.props ~= nowProps and reasonFor(ALLOWED_PROP_DRIFT, node.path) == nil then
		table.insert(problems, `{key}: props changed '{was.props}' -> '{node.props}' and is not characterized`)
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
	print("hint: `lune run tools/lune/check_flat_baseline -- --list` prints every characterized delta and why.")
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
		.. `{#ALLOWED_RECT_DRIFT} characterized rect-drift scope(s); no other rect/hit/class change)`
)
