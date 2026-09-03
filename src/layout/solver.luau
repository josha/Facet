--!strict
-- Pure two-pass layout solver (design §7, UI-LAYOUT-001/002): measure +
-- arrange over an immutable snapshot. Never yields, never reads live signals
-- or Instances; text goes through src/layout/text_metrics (non-yielding).
-- V1 algebra: VStack/HStack/ZStack/Grid/ScrollView/Anchor/Text/Box/Spacer;
-- dims fixed/content/hug/fill/percent/minMax/aspect; padding, uniform-or-per-side
-- margins, cross-axis alignment, overflow annotations, and diagnostics for
-- undefined combinations (percent on an unbounded axis; aspect on both axes).
--
-- A stack's MAIN axis negotiates in three steps, in this order (round-2 parity,
-- docs/plans/parity-round2.md §2.4/§2.6): children are measured, then a
-- DEFICIT is absorbed by the shrink pass (`layoutPriority` tiers x `shrinkWeight`
-- proportions, both inert by default), then a SURPLUS goes to `fill` children,
-- and only what fill did not take is spread by `distribute`. The first two steps
-- run in BOTH passes — measure against the offer (PASS 1.5 / PASS 2), arrange
-- against the real rect — because a child that ends up smaller than its natural
-- size has to be MEASURED at the size it will get or its box under-covers its own
-- wrapped content. `distribute` is arrange-only: it moves boxes, it never resizes
-- one, so it cannot change what anything measures.
--
-- Snapshot node shape (plain immutable tables):
-- { kind = "vstack"|"hstack"|"vwrap"|"hwrap"|"zstack"|"grid"|"gridrow"|"scroll"|
--          "anchor"|"text"|"box"|"spacer",   -- *wrap = the same stack, wrapping
--   id = string, width/height = Dim?, gap = number?,
--   padding = number | {top,right,bottom,left}?,
--   margin = number | {top,right,bottom,left}?,
--   align = "start"|"center"|"end"|"stretch"?          -- cross-axis (stacks)
--   lineAlign = "start"|"center"|"end"|"stretch"?      -- ONE child, in its line
--   distribute = "start".."spaceEvenly"?               -- main-axis leftover (stacks)
--   layoutPriority = number?, shrinkWeight = number?   -- the shrink pass (children)
--   alignH/alignV = "start"|"center"|"end"?            -- zstack children
--   anchor = "topLeft".."bottomRight"?, offsetX/Y?     -- anchor children
--   columns = number?, minColumnWidth = number?,       -- grid (FLOW mode)
--   rowGap = number?,                                  -- grid (defaults to gap)
--   gridSpan = number?,                                -- gridrow cells (ROW mode)
--   overflow = "clip"|"scroll"|"visible"|"intentionalOverlap"?,
--   text/font?, textSize = number | <typography role name>?, textFit?, lineHeight?,
--   singleLine = boolean? (measure one line, clamp to the offer),
--   axis = "y"|"x"? (scroll), children = { Node }? }
-- Dim = { type = "fixed", px } | { type = "content" } | { type = "hug", min?, max? } |
--       { type = "fill", weight } | { type = "percent", fraction } |
--       { type = "minMax", min, preferred?, max } | { type = "aspect", ratio } |
--       { type = "containerRelative", fraction } |
--       { type = "containerRelative", count, span?, spacing? }
-- solve(root, viewport, opts) -> { rects, diagnostics, contentRect }
-- opts.metrics is the active ThemeSnapshot; omitted, the solve
-- runs on Studio Neutral, whose values are the framework's historic literals.

local text_metrics = require("./text_metrics")
-- `text_fit`: the ONE binary search for "what size makes this string fit this
-- box". The public `Facet.text.fit` and the solver's own `textSize = "fit"` are
-- the same call, which is what stops an eighth near-duplicate being written.
local textFitLib = require("./text_fit")
local profile = require("../core/profile")
local themeSnapshot = require("../themes/snapshot")
-- `chrome_slots.spendInset`: the ALL-OR-NOTHING floor `arrange`'s scroll branch
-- borrows for the leading-edge chrome bleed (task SHOWCASE3) — the same
-- contract a themed control's own contentInsets already spend against, here
-- applied to a scroll node's leading padding against its REAL resolved rect
-- (`layout_node.luau`'s pre-solve conversion never has one; see the reserve's
-- own comment in `arrange` below for why that is load-bearing).
local chrome_slots = require("../tokens/chrome_slots")
-- the PURE declared-content composition decision. The solver supplies
-- the measurements and consumes the rects; the ranking, the step-down/drop order
-- and the arrangement choice live there, where a headless sweep can drive them
-- with no tree at all.
local compositionLib = require("./composition")
-- the expand plate's chrome, declared once beside the padding `blueprint` writes
-- on the plate; resolved into the composition's resolve context below
local expandPlate = require("./expand_plate")
-- the composition's own resolution — the block this file used to hold, taken as
-- its own module by the source-cap ledger's named seam. It reads `measure` back,
-- which is why it takes a Deps record rather than closing over anything here.
local compositionResolve = require("./composition_resolve")
-- the parent-side placement-prop audit (parity round 2 §2.1), re-exported below
-- as `solver.auditPlacement`. It reads no solve state, which is why it is the
-- one block of this file that could become a sibling module unchanged.
local placementAudit = require("./placement_audit")
-- `placement`: the arrange pass's pure arithmetic — the anchor factors, the two
-- offset helpers, cross-axis alignment and main-axis distribution. Functions on
-- numbers, so it takes no `Deps` at all.
local placementLib = require("./placement")
-- the main-axis shrink pass and its degrade cascade (§2.4 + director ruling 1).
-- It takes `SHRINK_DEPS` below rather than closing over anything of this file's.
local shrinkLib = require("./shrink")
-- UI.Grid's WHOLE arithmetic — both layouts (the flow grid in either flow
-- direction, and the `GridRow` column grid) and both passes. Same discipline as
-- `shrink`: it takes `GRID_DEPS` below, plus the two helpers declared too far down
-- this file to sit in a load-time record, and holds no state of its own.
local gridLib = require("./grid")
-- `flow`: the wrapping stacks' line partition and the plan both passes share. It
-- takes `FLOW_DEPS` below — the same three helpers `GRID_DEPS` carries.
local flowLib = require("./flow")
-- `boundary_report`: the Stage 1 measurement report, re-exported below. It takes no
-- `Deps` at all — two arguments in, a table of numbers out.
local boundaryReportLib = require("./boundary_report")
-- `candidate`: the `ViewThatFits` fit-candidate ladder, lifted out on 2026-09-02
-- (source-cap ledger). It takes `CANDIDATE_DEPS` below — `measure` and
-- `setFitProbe`, both forward locals here — and holds no state of its own.
local candidate = require("./candidate")
-- `arrange_reports`: the four reports a node makes about its OWN resolved box,
-- lifted out on 2026-09-02 for the Source-write headroom the wicked-fast round
-- needed. No `Deps`: it reads only the values `arrange` hands it.
local arrange_reports = require("./arrange_reports")
local num = require("../num")
-- bound at module scope: `solver.luau` records that a per-call allocation on
-- the measure path is a bench regression this repository has already paid for
local roundPx = num.roundPx

-- THE PURE PER-NODE MEASURE FACTS (`./measure_facts`), lifted out on 2026-08-21
-- when this file was 2,190 characters from the `Script.Source` write cap and the
-- ledger had already named the module: `Dim` and the dimension readers, the ONE
-- resolution of a text node's typography, the measurement facts that resolution
-- publishes, and the memo's per-node `PLAN_*` classification. Every one of them
-- reads only what it is handed — which `SHRINK_DEPS` and `GRID_DEPS` below have
-- been proving by threading four of them as arguments since those splits — so the
-- move took no state with it and cannot require back
-- (`tests/measure_facts_seam.spec.luau` is that property, mechanised).
--
-- BOUND TO LOCALS RATHER THAN CALLED THROUGH THE TABLE: these sit on the
-- per-node measure path, where an extra table index per call is the shape of a
-- bench regression this file has already paid for once.
local measureFacts = require("./measure_facts")
local measureReuse = require("./measure_reuse")
local CONTENT = measureFacts.CONTENT
local MEMO_ARM_DEPTH = measureFacts.MEMO_ARM_DEPTH
local PLAN_HEIGHT_FREE = measureFacts.PLAN_HEIGHT_FREE
local PLAN_SKIP = measureFacts.PLAN_SKIP
local dim = measureFacts.dim
local mainDimOf = measureFacts.mainDimOf
local memoPlan = measureFacts.memoPlan
local recordTextFacts = measureFacts.recordTextFacts
local axisAbsorbs = measureFacts.axisAbsorbs
local sides = measureFacts.sides
local textTypography = measureFacts.textTypography

-- re-exported under the name every caller and every doc uses; the schema lives
-- beside the two functions that read it (`dim`, `mainDimOf`)
export type Dim = measureFacts.Dim
export type Node = {
	kind: string,
	id: string,
	width: Dim?,
	height: Dim?,
	padding: any?, -- number | {top,right,bottom,left} (same shape as margin)
	gap: number?,
	margin: any?,
	-- CROSS-AXIS ALIGNMENT, AND THE TWO JOBS THE ONE WORD USED TO DO (§2.1).
	-- `align` on a stack aligns THIS stack's own children. It is read off a CHILD
	-- too, and that second reading is the ambiguity `lineAlign` exists to end: a
	-- nested `vstack{ align = "center" }` used to centre its own children AND
	-- centre itself in its parent's line, one word meaning two things at once.
	-- `child.align` is still honoured (nothing shipped moves), but `lineAlign` is
	-- the word for the second job and it WINS where both are present.
	align: string?,
	-- PER-CHILD cross-axis alignment inside the parent stack's line — Roblox's
	-- `ItemLineAlignment`, and the only spelling of it that works on a LEAF
	-- (`align` is a container-only prop, so `UI.Text`/`Box`/`Spacer`/`Image`
	-- refuse it). Same four values as `align`; `stretch` fills the line.
	lineAlign: string?,
	alignH: string?,
	alignV: string?,
	anchor: string?,
	-- SILENTLY-INERT PLACEMENT PROPS FOUND ON THIS NODE'S CHILDREN (§2.1),
	-- computed once per tree build by `renderer.toLayoutNode` (which knows the
	-- class->kind mapping and sees `UI.When`/`UI.ForEach` children after they
	-- splice into this node's flow) and reported by `arrange`, so it is gated by
	-- `hiddenDepth` and replayed by the reuse path exactly like the overflow
	-- diagnostic it sits beside. Absent on the overwhelming majority of nodes.
	-- `filedBy` is THIS node's id, stamped at build time. It is the one diagnostic
	-- in the file whose `node` is not the node that files it (the parent files;
	-- the child is named), and the incremental replay gate needs the filer — see
	-- `solve`'s replay loop, and RED-TEAM Milestone 1 HIGH 2.
	inertPlacement: { { node: string, issue: string, filedBy: string } }?,
	-- set by `renderer.toLayoutNode` when this node carries ANY of the nine
	-- placement props; the audit's fast reject (see `auditPlacement`)
	placementProps: boolean?,
	--[[ ONE SLOT OF A FIXED-PITCH WINDOWING LIST (`virtualSlot`, 2026-08-13).
		Stamped by `virtual_list.luau` on each row's ZStack — one shared table for
		the whole list, since every field is a property of the LIST and the row's
		own identity is already its node path. `extent` is the DECLARED
		`itemExtent` (never this row's current box: a row-actions commit collapse
		drives the box down a height ladder on purpose), `axis` is the list's
		scroll axis, and `contentFrom` is the first child index that belongs to the
		consumer's cell rather than the control's own furniture. Read by exactly
		one thing: the declared-slot guard in `arrange`'s zstack branch. ]]
	virtualSlot: { list: string, axis: string?, extent: number, contentFrom: number? }?,
	-- set by `renderer.toLayoutNode` when this node's own width/height is
	-- `containerRelative`, or any descendant's is with no intervening `scroll` node
	-- (a scroller re-establishes the container out of its own rect, so it insulates
	-- what is below it). Read ONLY by `arrange`'s reuse skip, which is unsound for
	-- exactly these subtrees — see the skip. Absent on the overwhelming majority of
	-- nodes.
	containerRelativeInside: boolean?,
	-- px, or a FRACTION of the parent's inner extent plus a px adjustment
	-- ({ scale, offset } — the marker-overlay shape). The
	-- renderer resolves metric names before this; the fraction can only be spent
	-- here, where the extent is known.
	offsetX: (number | { scale: number?, offset: number? })?,
	offsetY: (number | { scale: number?, offset: number? })?,
	-- MAIN-AXIS DISTRIBUTION OF THE LEFTOVER, on a vstack/hstack (§2.6). "start"
	-- (the default, and byte-identical to the hard-anchored cursor this branch
	-- always had) | "center" | "end" | "spaceBetween" | "spaceAround" |
	-- "spaceEvenly" — Roblox's `UIFlexAlignment`, plus whole-group centring.
	--
	-- It acts on what `fill` children did NOT take. When a fill child is present
	-- there is no leftover at all, and a non-"start" `distribute` there is an
	-- authoring conflict that gets a diagnostic rather than a silent no-op.
	distribute: string?,
	-- THE SHRINK PASS'S TWO INPUTS, read off a stack's CHILDREN (§2.4). They are
	-- two levels of one algorithm: `layoutPriority` is the OUTER sort (tiers,
	-- consumed lowest-first, SwiftUI's model) and `shrinkWeight` is the INNER
	-- distribution (proportional to weight x basis inside a tier, CSS's rule).
	--
	-- `shrinkWeight` defaults to 0 — "neither shrinks nor grows", the same default
	-- and the same meaning as Roblox's `Enum.UIFlexMode.None` — so a stack whose
	-- children declare neither is arranged exactly as it always was, deficit and
	-- overflow diagnostic included.
	layoutPriority: number?,
	shrinkWeight: number?,
	-- THE ROW GRID'S ONE CHILD-SIDE INPUT (§2.2): how many of its row's columns
	-- this cell covers. Read by a `gridrow` parent and by nothing else.
	gridSpan: number?,
	columns: number?,
	-- vertical pitch between grid ROWS; absent = `gap` (director finding 14)
	rowGap: number?,
	-- number | "intrinsic" (the widest child's own measured width)
	minColumnWidth: (number | string)?,
	-- "natural" (default) | "uniform" (every cell takes the max measured size)
	itemSizing: string?,
	overflow: string?,
	text: string?,
	font: string?,
	-- a literal px size, or a typography ROLE name resolved from the active
	-- ThemeSnapshot on this solve
	textSize: (number | string)?,
	--[[ ...OR THE BAND THE SOLVER PICKS ONE FROM (`textSize = "fit"`, audit §10).
		`cap`/`floor` are already through the typography scale and `offset` is the
		additive paint offset the engine applies at draw time, kept SEPARATE because
		the measure has to ask about `size + offset` while paint writes `size`. When
		it is present, `textSize` above is the reserved CAP — what a reader that
		knows nothing of this field measures at, i.e. the largest this node can
		paint. `render/layout_node.textOf` is the one writer. ]]
	textFit: { cap: number, floor: number, offset: number }?,
	-- line-height factor from the role; absent = the library's global 1.2
	lineHeight: number?,
	-- measure this text on ONE line and clamp to the offer, because the adapter
	-- draws it on one line (director finding 13; today: a Toggle's label)
	singleLine: boolean?,
	-- THE LINE CAP (blueprint `Text.lineLimit`, 2026-07-27). At most this many
	-- lines are RESERVED, so a node inside a box of a known height cannot measure
	-- itself taller than the box and paint through it. Distinct from `singleLine`,
	-- which answers "how does the ADAPTER draw this string" (one word has no legal
	-- break) — this answers "how much room does the OWNER have", which only the
	-- owner knows. They compose: a capped phrase still wraps, up to the cap.
	--
	-- Absent, nothing changes. Set, the engine's TextTruncate.AtEnd (already on
	-- for every text node) ellipsizes the overflow instead of the text growing its
	-- box — the device defect a fixed-height table row showed.
	lineLimit: number?,
	-- the SHORTER thing this node draws when `text` does not fit the width it is
	-- given (a Button's `compactLabel`, 2026-07-27). Absent = today's behaviour.
	-- Set, it makes the fit a solver decision reported back through `out[id]
	-- .compact`, which is how measure and paint end up reading ONE verdict.
	compactText: string?,
	-- ...and whether that shorter thing is a DEGRADE or this node's DEFAULT
	-- (`compactLabel = { icon = …, prefer = true }`, director 2026-08-12). Set, the
	-- fit test is skipped: the compact form is measured and painted always, so the
	-- box is reserved for exactly what lands in it.
	compactPrefer: boolean?,
	-- FULL-VALUE DISCLOSURE (blueprint `Text.disclose`). Carried, never
	-- spent: it changes no geometry. It rides the layout node so the solve result
	-- — the one place that knows this text TRUNCATED — can say in the same breath
	-- whether the author declared a way back to the whole string. The presenter
	-- and the text audit both read that pair; neither could derive it from a rect.
	disclose: boolean?,
	-- THE AUTO REVEAL (blueprint `Text.reveal`, director 2026-08-04). Carried
	-- exactly as `disclose` is; additionally the measure records the string's
	-- natural one-line width in the facts, because the reveal's travel distance
	-- is that width less the box — a number only the measure pass knows
	reveal: string?,
	-- the EFFECTIVE target floor this node's control class declares, in px
	-- (renderer-set from class_contract minHitSize clamped up by the theme's
	-- targetSizes.minimum). Diagnostics only — the renderer still owns the hit
	-- expansion — and it is what makes "which nodes are interactive" a fact of the
	-- solve rather than something a pure audit has to guess from a rect.
	hitFloor: number?,
	-- wave REVEAL: set by `UI.Region` on the ONE button it synthesizes, and read
	-- only by the region branch of `arrange`. { role = "cover" | "chevron" }
	expandTarget: any?,
	axis: string?,
	-- the decoration slot whose `contentInsets` are part of this node's padding
	-- (renderer-set). Diagnostics only — the solver spends the padding
	-- identically either way, and naming the source is what makes a collapsed
	-- content box actionable instead of mysterious.
	chromeSlot: string?,
	-- ...and the slot inset the renderer had to GIVE BACK because this node was
	-- too small to afford it (director report 2026-07-28). Diagnostics only, for
	-- the same reason: the geometry is already repaired by the time it gets here,
	-- and what this carries is the fact that it needed repairing. `x`/`y` are the
	-- px that went unspent on that axis; absent = that axis was afforded.
	chromeYield: { slot: string, x: number?, y: number? }?,
	--[[ ...AND THE SIZE FLOOR THE RENDERER HAD TO REFUSE, for the same reason and
		on the same terms (task THEME fix round, 2026-08-28).
		`render/layout_node`'s `shape = "circle"` icon floor raises a disc to hold
		its picture at full size; where the host declared what it RESERVED for that
		node (`chrome_slots.Hint.footprint`) the floor stops there instead of
		growing onto whatever sits beside it. Diagnostics only — the geometry is
		already decided by the time this arrives, and what it carries is that the
		package wants a bigger picture than this control has room for. ]]
	sizeRefused: { want: number, reserved: number, icon: string? }?,
	--[[ THE OUTERMOST SCROLL CLIPPER'S LEADING-EDGE CHROME BLEED (task
		SHOWCASE3, 2026-08-29), stamped by `render/layout_node.luau` beside the
		cross-axis reservation it already folds into `padding` unconditionally.
		This one CANNOT fold into `padding` there: the pre-solve conversion sees
		only this node's own AUTHORED extent (`math.huge` for the common
		fill/hug scroll container), so an unconditional reservation has no
		floor — landed once as `9eb095a`, reverted the same day for collapsing
		`overflow_sweep`'s `tab_view`/`p3_sipworks` to a 0px content box under
		Sci-Fi HUD at narrow-landscape. `arrange` spends this floor-aware,
		against the rect it actually resolved. `nil`/`0` on every flat package
		and on every non-outermost clipper, so neither moves. ]]
	leadingBleed: number?,
	-- DECLARED-CONTENT COMPOSITION. `composition` marks a screen-level
	-- container: its children are all `region` nodes and their placement comes
	-- from src/layout/composition.luau rather than from a stack rule. `region`
	-- marks one ranked thing to say; its children are its FORMS, richest first.
	composition: {
		groups: { any },
		arrangements: { any },
		laneGap: number?,
		groupGap: number?,
		maxMeasure: number?,
	}?,
	region: {
		group: string,
		rank: number,
		sizing: string?,
		weight: number?,
		floor: any?,
		mayScroll: boolean?,
		mayDrop: boolean?,
		reserved: boolean?,
		recover: string?,
	}?,
	children: { Node }?,
}
export type Rect = { x: number, y: number, w: number, h: number }

local solver = {}

-- Keep-visible arithmetic (acceptance row A-SV2). ONE implementation of the
-- minimum-distance rule, shared by every caller that brings something into a
-- scrolled band:
--
--   * the renderer's `controller.scrollToVisible`, which reads SOLVED rects;
--   * VirtualList, which must work from its row INDEX because a row outside the
--     window is not mounted at all;
--   * Table, which works from its model row tops because a row can be culled.
--
-- The two controls are NOT duplicating the renderer's substrate — they serve the
-- virtualization case it structurally cannot, since it needs a mounted rect. What
-- they legitimately shared was this clamp, and it used to be written three times.
--
-- keepVisibleOffset(spanStart, spanSize, offset, band, extent) -> number?
--   spanStart/spanSize  the thing to reveal, in CANVAS space
--   offset              the current scroll offset
--   band                the visible extent along the scroll axis
--   extent              the total canvas extent (for the clamp); nil = unclamped
-- Returns the new offset, or nil when no scroll is needed (already visible).
function solver.keepVisibleOffset(
	spanStart: number,
	spanSize: number,
	offset: number,
	band: number,
	extent: number?
): number?
	local wanted = offset
	if spanStart < offset then
		wanted = spanStart -- above the band: scroll up just enough
	elseif spanStart + spanSize > offset + band then
		wanted = spanStart + spanSize - band -- below it: scroll down just enough
	else
		return nil -- already fully visible: never issue a scroll
	end
	if extent ~= nil then
		wanted = math.clamp(wanted, 0, math.max(0, extent - band))
	else
		wanted = math.max(0, wanted)
	end
	if wanted == offset then
		return nil
	end
	return wanted
end

-- `CONTENT`, `MEMO_ARM_DEPTH`, `dim`, `SPACER_FILL`/`mainDimOf` and `sides` are
-- bound from `./measure_facts` at the top of this file. `sides` is re-exported
-- below as `solver.sides` (the renderer's scroll-region canvas math must use the
-- SAME padding semantics the arrange pass uses, or a canvas under-covers the
-- region it is supposed to hold).

type Ctx = {
	-- A FINDING'S `designed` FLAG (ruling 8) marks the ones that report the system
	-- working as declared rather than a defect. Absent on every other finding, so
	-- `d.designed == true` is the whole test; see the composition arrange branch
	-- for the one place that sets it and why the two kinds had to be separable.
	diagnostics: { { node: string, issue: string, designed: boolean? } },
	textStates: { [string]: string },
	-- nodes whose `compactText` won this solve. Recorded during measure and read
	-- out during arrange, so the verdict the box was reserved for is exactly the
	-- verdict the adapter paints.
	compact: { [string]: boolean },
	-- PER-TEXT-NODE MEASUREMENT FACTS, recorded on the same channel and
	-- under the same discipline as `compact`: assigned on EVERY measure of the
	-- node, so the facts published are the ones the reserved box was built from
	-- and a re-solve that made room can never leave a stale "truncated" behind.
	textFacts: { [string]: any },
	-- scrollbar thickness to reserve off a scrolling region's cross axis; the
	-- adapter owns the number (it is engine-specific), the solver only spends it
	scrollBarReserve: number,
	-- depth counter for subtrees that are arranged but never painted (the
	-- unchosen ViewThatFits candidates, which get a deliberate 0x0 rect). A
	-- subtree that does not paint cannot overflow anything, so layout
	-- diagnostics are suppressed inside it — otherwise every ViewThatFits
	-- emits a permanent false positive and the diagnostic becomes noise
	-- people learn to ignore.
	hiddenDepth: number,
	-- TRUE while `chosenCandidate` is asking "does this candidate fit?" (ruling 2).
	-- It suppresses the measure-side shrink so a candidate is judged at the size it
	-- would like — SwiftUI's ideal size — and it is part of `scopeKey`, because the
	-- same node at the same offer answers differently under it.
	fitProbe: boolean,
	--[[ HOW MANY TEXT NODES THE CURRENT PROBE HAS SEEN CUT (DIR wave contract 7).
		A candidate whose label only "fits" because the engine will ellipsize it does
		not fit, and the WIDTH cannot say so: both cutting paths report a width no
		bigger than the offer (a single line is clamped to it; a wrapped one is
		capped by `lineLimit` after wrapping INTO it). The truncation verdict is the
		only signal that distinguishes "this fits" from "this was made to fit", and
		`recordTextFacts` already computes it on every measure — so the probe counts
		it instead of re-deriving a second, disagreeing rule. Monotonic within a
		solve; `chosenCandidate` reads the DELTA across one candidate. ]]
	fitCuts: number,
	-- the active ThemeSnapshot. The ONE place the measure path
	-- learns a typography role's size, font and line height, so a theme swap is
	-- a re-solve with new numbers rather than a rebuild.
	metrics: any,
	-- one composition resolution per node per box, so measure and
	-- arrange can never disagree about which arrangement won — the same
	-- discipline `ctx.compact` carries for the compact-label verdict.
	compositions: { [string]: { key: string, resolution: any } },
	--[[ THE SURFACE'S OWN BOX, AND THE PLATFORM BAND ABOVE IT (§9).
		A `UI.Composition`'s exclusion rects and the topbar band both arrive in
		WINDOW space — that is the space `platformChrome` states them in, and the
		space the solver's own output rects are in — so turning either into a box a
		pure composition can reason about needs the composition's own origin. These
		three are what the conversion is made of, and they are the SURFACE's facts
		rather than any one node's: `rootRect` is the content rect the policy
		resolved, `rootBand` the free strip, `rootBandFullTop` the window y below
		which the platform's whole top reservation ends. All three are nil-safe: a
		surface under any other policy carries no band and every composition in it
		behaves exactly as it did. ]]
	rootRect: Rect,
	rootBand: Rect?,
	rootBandFullTop: number?,
	-- ...and the form index each region resolved to, read by the `region` arrange
	-- branch. 0 means "nothing shows" (dropped, or below its floor).
	regionForm: { [string]: number },
	-- wave REVEAL: per region, whether the composition says a form below the
	-- richest is standing AND a route to the rest exists. The affordance is
	-- arranged only where this is true, which is what makes "the stop exists only
	-- while stepped down" the existing hidden-child mechanism rather than a new one
	regionExpandable: { [string]: boolean },
	-- THE NEAREST CONTAINER'S INNER SIZE (§2.5) — the ruler a `containerRelative`
	-- dimension measures against, which is NOT the parent's offer. It is the
	-- surface root's content rect until a `scroll` node pushes its own viewport,
	-- and it is popped on the way out, exactly the shape `hiddenDepth` has.
	--
	containerW: number,
	containerH: number,
	-- `scopeKey` is the memo's third key field: `"{hiddenDepth}"`, or
	-- `"{hiddenDepth}|{containerW}|{containerH}"` once `hasContainerRelative` is
	-- armed. See the three writers above `contentSize` for why it is one field and
	-- why the container is conditional — both answers were measured.
	scopeKey: string,
	-- armed the first time a `containerRelative` dimension is measured; a tree with
	-- none keeps the exact cache key this memo carried before §2.5
	hasContainerRelative: boolean,
	-- THE GRID'S PLAN, computed once per grid per box and read by both passes — the
	-- same discipline `compositions` carries, and for the same reason: a grid that
	-- measured one set of lanes and arranged another is this file's documented
	-- recurring defect class. ONE cache for both grid layouts, because a grid is
	-- either the row grid (`gridColumnPlan`, §2.2) or the flow grid
	-- (`gridFlowPlan`, either flow direction) and never both at once. Both plans
	-- live in `src/layout/grid.luau`; this field is where they are filed, and the
	-- solve that owns the ctx is what scopes them.
	gridPlan: { [string]: { key: string, value: any } },
	-- FLOW-WRAP LINE PARTITIONS (round 3 item A), computed once per wrapping stack
	-- per box and read by both passes — the same table shape, the same key shape
	-- and the same reason as `gridPlan` one line up. A wrapping stack that
	-- measured one partition and arranged another is the identical defect class,
	-- and this file has fixed it four times already.
	flowLines: { [string]: { key: string, value: any } },
	-- ...and the resolved columns handed DOWN from a grid to the row it is about to
	-- arrange, so the `gridrow` branch places its cells in the columns the grid
	-- derived from every row rather than re-deriving a private answer from its own.
	gridRowPlan: { [string]: any },
	-- PER-SOLVE MEASURE MEMO (roadmap Step 9). node -> "<maxW>|<maxH>|<hidden>" ->
	-- { w, h, textState, compact, textFacts, composition }. The verdicts ride along
	-- because they are REPLAYED on a hit; see `measure` for why that is load-bearing.
	measureCache: { [any]: { [string]: any } },
	-- THE CROSS-SOLVE HALF OF THAT MEMO (P1). The per-surface store the slates above
	-- are adopted from and written through, or `nil` when the caller has none; see
	-- `./measure_reuse` for the four invalidation axes.
	measures: measureReuse.Store?,
	-- node -> its `PLAN_*` verdict, decided once per node per solve by `memoPlan`
	memoPlans: { [any]: number },
	offers: { [string]: number },
	-- HOW MUCH OF THE TREE THIS SOLVE TOUCHED. Published in the result so a test can
	-- ask "did changing one bound value re-lay-out the whole screen?" from the public
	-- surface, instead of a one-off probe that has to patch this file.
	arranged: number,
	measured: number,
	-- ...and its writes into the RECT MAP: `arranged + translated` since O3.
	rectInserts: number,
	-- THE THIRD CLASS (O3): a node an ancestor re-based instead of walking — not
	-- arranged, not skipped, a rect insert. `translatedRoots` is keyed by the node
	-- whose delta it was, `[from, to]` naming its span in the two parallel flat
	-- arrays, which are in document order and exist for the COMMIT to walk (T5).
	translated: number,
	translatedRoots: { [string]: { dx: number, dy: number, from: number, to: number } },
	translatedPaths: { string },
	translatedEntries: { any },
	-- Stage-1 analysis only; nil on an ordinary solve
	analyze: boolean,
	boundary: { [string]: boolean },
	-- INCREMENTAL REUSE (Stage 2 v2). `previous` is the last solve's result and
	-- `dirtyContains` is every node that is dirty or contains a dirty node; a node
	-- absent from it cannot have changed, so its subtree may be replayed instead of
	-- walked. Both nil on an ordinary solve, which then behaves exactly as before.
	-- `measureContains` is the same closure over `measure`-classed dirt ALONE
	-- (wicked-fast O2) and is a subset of `dirtyContains`; the adopt gate in
	-- `measure` reads it and the arrange skip reads `dirtyContains`. REQUIRED
	-- whenever `measures` is also supplied — the renderer passes `dirtyContains`
	-- itself when it has no measure half, never `nil` — and unread by a solve with
	-- no measure store, which is why the three direct `solver.solve` callers in
	-- `tests/` that build a reuse table by hand need not carry it.
	reuse: any,
	skipped: number,
	-- the ids `arrange` WALKED, kept only on a reuse solve, where the walk is the small
	-- half. A previous diagnostic is replayed exactly when its filer is absent here.
	walkedIds: { [string]: boolean },
	-- true once a `scroll` node has been measured in this solve; gates the memo so a
	-- tree with no scroll region pays nothing for it
	hasScroll: boolean,
	-- THE SECOND ARM OF THE SAME GATE (L-37). `mdepth` is the current MEASURE
	-- RECURSION depth (root = 1) and `deepNesting` latches once it reaches
	-- `MEMO_ARM_DEPTH`, because nesting is the other producer of the redundancy the
	-- memo exists to remove: every enclosing container re-measures the subtree below
	-- it, so a node at depth d is measured ~d times. Measured, not assumed — see
	-- `measure`'s gate.
	mdepth: number,
	deepNesting: boolean,
}

-- `textTypography` and `recordTextFacts` are bound from `./measure_facts` at the
-- top of this file: the one resolution of a text node's face and size, and the
-- per-text-node facts that every measure publishes on `ctx.textFacts`.

local measure -- forward
local measureUncached -- forward (the real body; `measure` is the per-solve memo in front of it)
-- forward: `ViewThatFits`'s fit probe (ruling 2) is read by the shrink pass and set
-- by `candidate.choose` (`./candidate`), through `CANDIDATE_DEPS` built before the
-- scope-key writers it belongs with
local setFitProbe: (ctx: Ctx, on: boolean) -> ()
-- WHAT THE SHRINK PASS NEEDS FROM THIS FILE (§2.4). It used to be a forward
-- declaration here — `local shrinkStack: (...) -> (...)`, assigned ~2,300 lines
-- below, because BOTH passes run it and the measure branch's PASS 1.5 calls it
-- long before the arrange helpers are defined. It is now `src/layout/shrink.luau`
-- (see the pointer where its body was), so the name is bound by the require at
-- the top of the file and that forward declaration is gone.
--
-- The three helpers it reads are immutable module-level functions declared above,
-- so this record is built once, here, where all three are already in scope — NOT
-- captured inside the module, which would give it state.
local SHRINK_DEPS: shrinkLib.Deps = { mainDimOf = mainDimOf, sides = sides, textTypography = textTypography }

-- WHAT THE GRID NEEDS FROM THIS FILE, built once here where all three are in
-- scope and threaded as an argument rather than captured — the shape `SHRINK_DEPS`
-- above set, so `src/layout/grid.luau` holds no state and two solves can never see
-- different helpers.
--
-- `measure` IS A FORWARD DECLARATION (line ~528, assigned ~1,500 lines below), so
-- it cannot go into a load-time record BY VALUE: the record would capture nil. The
-- forwarder below reads the local at call time instead, which is the same read
-- `contentSize` makes. `arrange` and `alignOffset` cannot even be forwarded from
-- here — both are declared BELOW this line, so a closure naming them would resolve
-- the nil GLOBAL and die inside a protected boundary. They are passed
-- at the two arrange call sites, where they are genuinely in scope; forward-
-- declaring them to avoid that would add a fourth mutable module local, which is
-- the opposite of what this split is for.
local GRID_DEPS: gridLib.Deps = {
	measure = function(ctx: Ctx, node: Node, maxW: number, maxH: number): (number, number)
		return measure(ctx, node, maxW, maxH)
	end,
	dim = dim,
	sides = sides,
}

-- ...AND WHAT `src/layout/flow.luau` NEEDS, which is the SAME THREE, so it is the
-- same record rather than a second copy of it. Two modules asking the solver for
-- `measure`/`dim`/`sides` is not a coincidence — it is what a pure measure-side
-- helper needs, and building the forwarder twice is how the two ends up reading a
-- different `measure` after someone edits one of them.
local FLOW_DEPS: flowLib.Deps = GRID_DEPS
-- ...and `./composition_resolve` needs exactly one of the three, so it declares
-- its own record rather than borrowing a wider one: a Deps record is a statement
-- about what a module reads, and a spare field in it is a false statement.
local COMPOSITION_DEPS: compositionResolve.Deps = { measure = GRID_DEPS.measure }

-- ...AND WHAT `src/layout/candidate.luau` NEEDS, which is the pair the extraction
-- found and no more. BOTH are forward locals assigned far below this line —
-- `measure` at ~1,675, `setFitProbe` at ~1,024 — so both are read AT CALL TIME,
-- for the reason `GRID_DEPS` above states: a by-value record here captures nil.
-- `measure` borrows `GRID_DEPS`'s forwarder rather than building a second one, so
-- the two records cannot end up reading a different `measure` after an edit.
local CANDIDATE_DEPS: candidate.Deps = {
	measure = GRID_DEPS.measure,
	setFitProbe = function(ctx: Ctx, on: boolean)
		setFitProbe(ctx, on)
	end,
}

-- resolve one axis of `node` given the limit and a content thunk
-- `axisAbsorbs` — the relayout-BOUNDARY predicate, which mirrors `resolveAxis`
-- case for case — is bound from `./measure_facts` at the top of this file. It
-- reads a `Dim` and two limits and nothing else, and it now has two readers:
-- the boundary analysis it was written for, and the containment finding's
-- "can this parent grow?" gate.

-- CONTAINER-RELATIVE SIZING (§2.5). `container` is the nearest ancestor viewport's
-- inner extent on THIS axis — `ctx.containerW`/`ctx.containerH`, pushed at each
-- scroll node — and the caller passes it rather than the resolver reading a global,
-- because `resolveAxis` is called once per axis and only the caller knows which.
--
-- The paging arithmetic is SwiftUI's, verbatim:
--   size = (viewport - spacing x (count - 1)) / count x span + spacing x (span - 1)
-- i.e. carve the viewport into `count` pages with `spacing` between them, then take
-- `span` of them AND the gutters those pages had between themselves.
local function containerRelativeSize(d: Dim, container: number): number
	local count = (d :: any).count
	if count ~= nil then
		local n = math.max(1, math.floor(count))
		local span = math.clamp(math.floor((d :: any).span or 1), 1, n)
		local spacing = (d :: any).spacing or 0
		local page = (container - spacing * (n - 1)) / n
		return math.max(0, roundPx(page * span + spacing * (span - 1)))
	end
	return math.max(0, roundPx(container * ((d :: any).fraction or 1)))
end

--[[ contentTermsPx(ctx, d) -> px — A BOX DECLARES ITS EXTENT IN CONTENT TERMS
	(framework-gaps-phase2 gap 3; audit §3). `UI.Composition` already had this
	vocabulary, LOCKED inside it (`Region` floors, `composition.floorPx`): a
	scroller or panel outside a `Composition` had no way to say "big enough for
	about N lines/rows" and got pinned in px instead, next to content that
	scales with text preference and the ten-foot ladder. This is that same
	arithmetic, published on the ordinary `dim` grammar every class already
	shares.

	TWO SHAPES, TWO UNITS — never confused, because `blueprint_schema` refuses
	both on one dim:

	  `{ type = "content", lines = n, role: string? }` — n lines of a
	  TYPOGRAPHY ROLE (default "body"), through the SAME two calls
	  `Facet.text.lineBox` makes (`text_metrics.reservedSize` then
	  `.lineBoxPx`), so a raised text preference or the ten-foot ladder grows
	  this box exactly as it grows the text it holds.

	  `{ type = "content", rows = n, of = metric }` — n rows of a NAMED THEME
	  METRIC (`"controlSizes.compact.height"`, a space step, a literal px…).
	  `of` already arrived here AS A PLAIN NUMBER: `themeSnapshot.resolveDim`
	  resolves it at prop-normalization time, the same pass that resolves
	  `px`/`min`/`max`/`preferred`, so this is arithmetic on the `Dim` alone —
	  it grows at the ten-foot ladder (theme metrics do) but NOT with the
	  player's accessibility text-size preference (theme metrics never have, and
	  that split is the correct one rather than a gap).

	WHY `lines` DOES NOT SIMPLY CALL `textFitLib.facts({ metrics = ctx.metrics
	})` THE WAY `composition.floorPx` DOES (found while wiring this up, and
	worth stating so it is not re-discovered the hard way): `ctx.metrics` is
	the snapshot `render/renderer.luau`'s `currentMetrics()` last RESOLVED —
	its `preferredText.offset` is whatever the theme was last swapped/re-
	resolved with, NOT necessarily this solve's live `preferredTextOffset`.
	The renderer keeps that fact OUT of `themeMetrics` on purpose (re-resolving
	a whole theme on every accessibility nudge would be wasteful) and instead
	re-reads it fresh every solve as `prefOffset`, threading it straight into
	`toLayoutNode` for every text node's own reservation. `d.scale`/
	`d.textOffset` below are `layout_node.luau`'s `stampContentTermsFacts`
	spending that SAME live pair, at the SAME prop-normalization step —
	`ctx.metrics` is read here only for the ROLE's size/lineHeight, which the
	snapshot always has current (it is rebuilt on every theme swap, unlike the
	fast-changing text preference).

	THE MEASURE-KEY ARGUMENT (this function's whole reason for existing where
	it does rather than being pre-collapsed at prop-normalization time the way
	`rows`'s `of` is): both shapes are PURE functions of `n`, `role`, `ctx.metrics`
	and — for `lines` — the two ALREADY-RESOLVED numbers on the `Dim` itself.
	Neither ever reads `limit` (the offer) or a child. That is exactly
	`measure_facts.memoPlan`'s `PLAN_HEIGHT_FREE` promise, and it holds by
	construction rather than by case analysis — see the comment on `memoPlan`
	beside the `content` branch for the full argument and the C-1 lesson it is
	built from. ]]
local function contentTermsPx(ctx: Ctx, d: Dim): number
	if d.lines ~= nil then
		-- a synthetic `TextFacts` carrying the LIVE scale/offset `layout_node.luau`
		-- stamped, paired with `ctx.metrics` for the role lookup — `text_fit.
		-- lineBox` spends the same two calls `Facet.text.lineBox` publicly does,
		-- so there is one arithmetic for "predict a text box", not a second copy
		-- of it living here
		-- `scale`/`textOffset` default to unscaled/no-offset for a tree built
		-- directly against the solver (the fuzzer, a low-level spec) rather than
		-- through `layout_node.luau`'s stamping — the live pipeline always
		-- supplies both, so the default never masks a real solve
		local facts = { scale = d.scale or 1, offset = d.textOffset or 0, metrics = ctx.metrics }
		return textFitLib.lineBox({
			facts = facts,
			size = d.role or "body",
			lines = d.lines :: number,
			role = d.role,
		})
	end
	-- rows: `of` is already a plain number (see the header above) — n rows of it
	return (d.rows :: number) * (d.of :: number)
end

local function resolveAxis(
	ctx: Ctx,
	node: Node,
	d: Dim,
	limit: number,
	contentFn: () -> number,
	container: number?
): number
	if d.type == "fixed" then
		return d.px :: number
	elseif d.type == "content" and (d.lines ~= nil or d.rows ~= nil) then
		return contentTermsPx(ctx, d)
	elseif d.type == "containerRelative" then
		-- AN UNBOUNDED CONTAINER IS THE SAME REFUSAL `percent` MAKES, and for the
		-- same reason: a fraction of infinity is not a size. It happens when a
		-- scroller is nested inside another scroller's own axis, so the inner one's
		-- viewport on that axis is the offer it never received.
		if container == nil or container == math.huge then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = "containerRelativeFrame on an axis whose nearest container is unbounded (a scroller "
					.. "inside another scroller's own axis?); falling back to content",
			})
			return contentFn()
		end
		return containerRelativeSize(d, container)
	elseif d.type == "percent" then
		if limit == math.huge then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = "percent size on an unbounded axis (inside scroll axis?); falling back to content",
			})
			return contentFn()
		end
		-- optional pixel offset + clamp band: percent(1, offset=-32, max=340)
		-- expresses "full width minus margins, capped" (Settings-panel shape)
		local raw = roundPx(limit * (d.fraction :: number) + (d.offset or 0))
		return math.clamp(raw, d.min or 0, d.max or math.huge)
	elseif d.type == "minMax" then
		local base = d.preferred or contentFn()
		return math.clamp(base, d.min or 0, d.max or math.huge)
	elseif d.type == "hug" then
		-- HUG: the content size, but NEVER larger than the box the parent
		-- offered (director round 10, found live 2026-07-26 on a phone).
		--
		-- The algebra had no way to say this. `content` hugs but is UNCAPPED, so
		-- it overflows the screen; `fill` is capped but never shrinks, so a card
		-- holding ten rows of chips painted a plate down to the bottom of the
		-- viewport with 55% of it empty. Every panel that wants to be "as big as
		-- it needs and no bigger" had to pick which failure it preferred, and the
		-- gallery's theme picker picked `fill` — which is the oversized card.
		--
		-- The cap is what makes this composable with scrolling: a ScrollView
		-- sized `hug` stops growing at the offer, its canvas keeps the true
		-- content extent, and the overflow annotation turns on by itself. So the
		-- SAME declaration hugs a short list and scrolls a long one, which is the
		-- pair of behaviours the two device rounds asked for.
		--[[ ...EXCEPT WHILE A `ViewThatFits` PROBE IS ASKING (framework-gaps-phase2
			§2a). The ladder judges a candidate "at the size it would like, not at the
			size it could be squeezed into" (ruling 2, SwiftUI's ideal-size rule), and
			`ctx.fitProbe` is how every squeezing mechanism is made invisible for the
			duration of the probe. THE CAP BELOW IS ONE OF THEM: a `hug` candidate
			whose content wants 320 in a 200px offer reported 200, so `w <= availW`
			was true whatever the content wanted, the first rung won at every width,
			and the labels the ladder exists to protect truncated anyway. `hug` is the
			instinctive spelling everywhere else in this framework, so that is a
			SILENT wrong answer reached by writing the obvious thing — four consumer
			files independently learned it and defended against it in prose
			(`showcase_chrome.luau` names it "the p4_foyer trap").

			The author's own `min`/`max` stay in force, because those are a
			DECLARATION and not a shortage — the same split `recordTextFacts` draws
			with `authoredWidth`, where a pin that cuts a label is the author's pin
			rather than the box being too small.

			SCOPED TO THE PROBE, and that is what makes it safe: the flag is off again
			by the time the chosen candidate is measured and arranged, so a `hug` rung
			that WINS is capped by its offer exactly as before, and a hugging panel
			outside any ladder never sees this branch. The memo agrees by
			construction — `rebuildScopeKey` already appends `|fit`, so the two
			answers are filed under different keys. ]]
		local base = math.clamp(contentFn(), d.min or 0, d.max or math.huge)
		if ctx.fitProbe then
			return base
		end
		return if limit == math.huge then base else math.min(base, limit)
	elseif d.type == "fill" then
		-- fill resolves at arrange; desired contribution is content
		return contentFn()
	end
	return contentFn()
end

-- THE COMPOSITION RESOLUTION LIVES IN `./composition_resolve` (source-cap-ledger,
-- the solver row's named next seam). It is reached through `COMPOSITION_DEPS`
-- above, and the ONE thing it needs from this file is `measure`.

--[[ THE FIVE WRITERS OF `ctx.scopeKey`.

	A measure has three inputs that are NOT in its argument list — `hiddenDepth` (it
	gates diagnostics), the nearest container (§2.5, it sizes a `containerRelative`
	dimension) and `fitProbe` (ruling 2, it suppresses the measure-side shrink while
	`ViewThatFits` judges a candidate) — and all three must be in the memo's cache key. They
	live here as ONE pre-formatted string, built on the handful of pushes a solve
	makes rather than on the thousands of measures that read it. Going through a
	helper is what keeps the string from drifting from the fields it names, and a
	scopeKey that disagrees with them is a cache that returns a size measured against
	a ruler that is no longer there.

	AND THE CONTAINER ONLY JOINS IT ONCE SOMETHING ACTUALLY READS ONE. `armContainer`
	sets `hasContainerRelative` the first time a `containerRelative` dimension is
	measured; until then the scope is `hiddenDepth` alone, which is byte-identical to
	the key this memo carried before §2.5.

	THAT CONDITION IS NOT A MICRO-OPTIMISATION, IT IS THE DIFFERENCE BETWEEN A LIVE
	CACHE AND A DEAD ONE, and it was measured rather than reasoned. A scroller's
	container is its OFFER's inner size during measure and its RECT's during arrange,
	and those differ whenever the scroller hugs or reserves a scrollbar — which is
	most of them. Unconditionally, every child of every scroller therefore got a
	DIFFERENT key in the arrange pass and the memo missed on all of them, which is
	precisely the second measure it exists to remove: p95 +14.3% on `lab-dense-scroll`,
	+18.9% on `virtual-list-scroll` and +22.8% on `lab-collection-churn`, against a
	same-arm noise floor of 2.9/8.1/11.2%. Conditioned, the same three scenes come
	back to +0.8% / +1.5% / +2.4% against 5.2/5.4/6.0% — inside the noise, and the
	whole-suite median delta is -0.7%. (4 ABBA blocks per arm, 2026-08-13.)

	WHY THE LATE ARM IS SAFE, and it is a real argument rather than a hope. A stale
	hit needs a container-dependent node to be READ under a container-free key. For
	a node's size to depend on the container, its subtree must hold a
	`containerRelative` dimension — and measuring the node measures that dimension,
	which arms the flag. The flag never clears, and an armed scope key carries two
	extra segments, so no key written before the arm can ever be produced again. The
	pre-arm entries are unreachable, not stale: the cost of a late arm is a miss.

	FOUR OF THE FIVE REBUILD; THE FIFTH RESTORES. `pushContainer`, `setHidden`,
	`armContainer` and `setFitProbe` each change a field the key is DERIVED from and
	then re-derive it.
	`restoreScope` puts back a triple that was captured together, so it writes the
	key verbatim rather than rebuilding one — which is correct, and is also why it
	cannot go through the helper the other three share. It is named here because the
	header used to say THREE while two lines wrote the triple directly (the
	Milestone-1 review, C4): the two scroll branches' unwind. They were safe, and a
	header that calls a desync structurally impossible is exactly what would let the
	next edit there make one.
]]
local function rebuildScopeKey(ctx: Ctx)
	-- ...and the FIFTH writer's segment (ruling 2), appended only while a
	-- `ViewThatFits` fit probe is running. A probe measures a candidate with the
	-- shrink pass suppressed, which is a DIFFERENT answer for the same node at the
	-- same offer, so it must be a different cache key — and appending nothing when
	-- the flag is off keeps every key this memo wrote before ruling 2 byte-identical.
	local probe = if ctx.fitProbe then "|fit" else ""
	if ctx.hasContainerRelative then
		ctx.scopeKey = `{ctx.hiddenDepth}|{ctx.containerW}|{ctx.containerH}{probe}`
	else
		ctx.scopeKey = `{ctx.hiddenDepth}{probe}`
	end
end

-- PUSH THE CONTAINER (§2.5). The caller saves and restores the previous triple;
-- there is no stack, because the only pusher is the scroll branch and it pushes
-- around a bounded recursion.
local function pushContainer(ctx: Ctx, w: number, h: number)
	ctx.containerW = w
	ctx.containerH = h
	if ctx.hasContainerRelative then
		rebuildScopeKey(ctx)
	end
end

-- ...and ENTER/LEAVE A `ViewThatFits` FIT PROBE (ruling 2). Same field, same
-- reason: the probe changes what a measure ANSWERS, so it changes the key that
-- answer is filed under. Saved and restored by the caller (`chosenCandidate`)
-- rather than counted, because a nested composition can start a probe inside one.
setFitProbe = function(ctx: Ctx, on: boolean)
	if ctx.fitProbe == on then
		return
	end
	ctx.fitProbe = on
	rebuildScopeKey(ctx)
end

-- ...and ENTER/LEAVE A HIDDEN SUBTREE. Same field, same reason.
local function setHidden(ctx: Ctx, depth: number)
	ctx.hiddenDepth = depth
	rebuildScopeKey(ctx)
end

-- ...and the arm itself, called from `measureUncached` the first time a
-- `containerRelative` dimension is seen.
local function armContainer(ctx: Ctx)
	ctx.hasContainerRelative = true
	rebuildScopeKey(ctx)
end

-- ...and the fourth writer: UNWIND to a triple captured together. The caller saved
-- `containerW`/`containerH`/`scopeKey` in one statement before pushing, so putting
-- all three back in one statement cannot desync them — the key is restored, never
-- rebuilt. Its only callers are the two scroll branches (measure's child loop and
-- arrange's), which push a container around a bounded recursion.
local function restoreScope(ctx: Ctx, w: number, h: number, key: string)
	ctx.containerW, ctx.containerH, ctx.scopeKey = w, h, key
end

-- ===== FLOW-WRAP: THE LINE PARTITION AND THE SHARED PLAN =================
--
-- MOVED to `src/layout/flow.luau` — its header carries the whole of the
-- reasoning that used to live here (the round-3 Phase 0 verdict, the live Studio
-- probe that fixed the three alignment words, and why one `gap` serves both
-- axes), unabridged.
--
-- The short version of why it could leave: `tools/lune/verify/data/source-cap-ledger.md`'s
-- row for this file names it as the next seam, and its trigger is a STATE rather
-- than a number — the extraction PRECEDES a round's own changes. `flowPartition`
-- was already exported as `solver.flowPartition` because it reads no node and no
-- `ctx`, which is the one-way test written down before the split, and `flowPlan`
-- reads only `measure`, `dim` and `sides`, handed over as `FLOW_DEPS` beside
-- `GRID_DEPS` above.
--
-- Re-exported under its own name because that is what `tests/flow_wrap.spec.luau`
-- and every doc call it.
solver.flowPartition = flowLib.partition

-- content sizes per kind (pre-dim resolution), used by measure
local function contentSize(ctx: Ctx, node: Node, maxW: number, maxH: number): (number, number)
	-- padding accepts a number or per-side table, exactly like margins
	local pt, pr, pb, pl = sides(node.padding)
	local gap = node.gap or 0
	local innerMaxW = if maxW == math.huge then math.huge else math.max(0, maxW - pl - pr)
	local innerMaxH = if maxH == math.huge then math.huge else math.max(0, maxH - pt - pb)

	-- A CONTAINER MEASURES ITS CHILDREN IN THE BOX IT WILL OCCUPY, not in the
	-- box its parent offered (director round 9, found live 2026-07-26).
	--
	-- `ViewThatFits` already had exactly this fix (director round 3: "measuring
	-- the candidates at the parent's 1200 picks a row that then has to arrange
	-- inside 620") and so does a fixed-width `text` node; every OTHER container
	-- still measured against the offer. The gallery's theme picker is the case
	-- that shows it: its panel is `percent(1, offset = -16, max = 560)` inside a
	-- 1217 px dock, so its chip Grid was MEASURED with 1201 px available (two
	-- rows) and ARRANGED with 544 (five rows) — the panel's raised plate ended
	-- 65 px above its own last row of chips, which is the "chips outside the
	-- card" the pre-fix captures show. It is a pre-existing defect: with the old
	-- literal `minColumnWidth = 132` the same disagreement put two rows outside
	-- the plate instead of three.
	--
	-- `fixed` and `percent` resolve without consulting content, so asking for
	-- them here cannot recurse (the same argument the `fits` branch makes).
	-- `fill`, `minMax`, `aspect` and `content` are left alone: none of them can
	-- answer without the content this call is measuring.
	if maxW ~= math.huge and node.kind ~= "text" and node.kind ~= "fits" then
		local selfW = dim(node, "w")
		-- `containerRelative` joins the two that could already answer without the
		-- content (§2.5): it reads the container, so asking for it here cannot recurse
		if selfW.type == "fixed" or selfW.type == "percent" or selfW.type == "containerRelative" then
			local resolved = resolveAxis(ctx, node, selfW, maxW, function()
				return innerMaxW
			end, ctx.containerW)
			innerMaxW = math.max(0, math.min(innerMaxW, resolved - pl - pr))
		end
	end

	if node.kind == "text" then
		local widthDim = dim(node, "w")
		-- the width this node will OCCUPY: its own when it declares a fixed one,
		-- otherwise the offer. Captured BEFORE the single-line override below turns
		-- the wrap width into `math.huge`, because the compact ladder still needs
		-- the real number to ask "does the full label fit" — reading `innerMaxW`
		-- there instead was the parent's offer, and a 400px button inside a 600px
		-- screen would have been told it had 600 (caught by measurement, 2026-07-27;
		-- it is the same offer-versus-occupied trap `contentSize` and `fits` above
		-- each had to be fixed for).
		local availW = if widthDim.type == "fixed" then (widthDim.px :: number) - pl - pr else innerMaxW
		-- ...and whether that width was AUTHORED, which is what tells a clamp from a
		-- shortage when `ViewThatFits` judges this node's candidate (M1b, see
		-- `recordTextFacts`)
		local authoredWidth = widthDim.type == "fixed"
		-- typography comes from the active snapshot (see `textTypography` above for
		-- the role ladder and why the descriptor rather than a bare family); the
		-- client premeasure adapter resolves that descriptor to the engine face it
		-- names (src/client/text_premeasure).
		local font, size, lineHeight = textTypography(ctx, node)
		--[[ ...AND `textSize = "fit"` IS RESOLVED RIGHT HERE, BEFORE ANYTHING ELSE
			READS `size` (audit §10, framework-gaps-phase2).

			This is the home the audit named, and the reason is that every other input
			to the question is already in this scope and nowhere else: the box
			(`availW`/`availH`, each the width and height this node will OCCUPY rather
			than the offer it was handed), the face and line height
			(`textTypography`), the typography scale and the additive paint offset
			(both already folded into `node.textFit` by `render/layout_node.textOf`).
			Four separate consumer copies of this arithmetic each had to reconstruct
			those four facts from outside the solve, and three of the four got one of
			them wrong — a `1.25` line-height factor against the library's declared
			`1.2`, and a scale nobody applied at all.

			IT IS `text_fit.fit`, NOT A SECOND SEARCH. The public helper already owns
			the binary search, the conservative-by-inheritance direction and the
			"fit the painted form, return the authored size" split; a private copy here
			is precisely how the seventh near-duplicate gets written. Everything below
			this block then runs on the chosen size — the wrap rule, the compact
			ladder, the truncation verdict — because `size` IS the answer by the time
			they read it.

			LINES: the author's own `lineLimit` when there is one; otherwise
			`math.huge`, which means "wrapping is free, decide on the HEIGHT alone".
			That is the honest question for a label in a box: a phrase is allowed to
			reflow, and only the box it must live in can refuse it. ]]
		if node.textFit ~= nil then
			local band = node.textFit :: { cap: number, floor: number, offset: number }
			local heightDim = dim(node, "h")
			-- the height this node will OCCUPY, derived exactly as `availW` above is
			-- and for the identical reason: for a `fixed`-height node `innerMaxH` is
			-- the PARENT'S offer, and fitting a label to the parent's box is the
			-- offer-versus-occupied trap this branch has had to close twice already
			local availH = if heightDim.type == "fixed" then (heightDim.px :: number) - pt - pb else innerMaxH
			local chosen = textFitLib.fit({
				text = node.text or "",
				font = font,
				cap = band.cap,
				floor = band.floor,
				width = availW,
				height = if availH == math.huge then nil else availH,
				lines = if node.lineLimit ~= nil then node.lineLimit else math.huge,
				lineHeight = lineHeight,
				offset = band.offset,
			})
			-- the RESERVED size, in the units everything downstream already speaks:
			-- what the engine will draw, which is the authored size plus the offset it
			-- adds itself. `textFacts.size` therefore carries it unchanged, and the
			-- paint seam recovers the size to write by subtracting the same offset.
			size = chosen.size + band.offset
		end
		-- SINGLE-LINE TEXT (director finding 13, 2026-07-26). A control whose
		-- adapter draws its label on one line has to be MEASURED on one line, or
		-- the row reserves height for a second line nobody draws — the same
		-- measure-versus-paint disagreement rounds 3 and 9 both landed on. The
		-- text is measured UNBOUNDED and the result is clamped to the offer, so a
		-- row that is free to grow takes the width its one line needs and a row
		-- that is not ellipsizes inside the box it was given.
		--
		-- THE WRAP RULE — WRAPPING IS RIGHT ONLY WHEN THE LONGEST WORD FITS
		-- (director ruling 5, 2026-08-13; docs/handoff/2026-08-13-rulings-needed.md
		-- §5). `node.singleLine` is derived from the STRING alone (the renderer's
		-- `isSingleWord`) and answers "has this string a legal break at all". It
		-- cannot answer "can that break SUCCEED", because that needs the width, and
		-- the width is only known here. A phrase allowed to wrap into a column
		-- narrower than one of its own words does not wrap — the engine BREAKS the
		-- word, and the broken half paints outside the column that was measured for
		-- it (`text_metrics.minWidth`'s own header says so, and until this ruling
		-- only the shrink pass read it).
		--
		-- So the two shapes collapse into ONE rule: a string that cannot legally
		-- break in the room it has is measured on one line and clamped to the offer,
		-- and the engine's TextTruncate.AtEnd (on for every text node) ellipsizes
		-- the rest. An unbounded offer never triggers it — a label free to grow has
		-- no drawable width to fail against.
		--
		-- The verdict is PUBLISHED (`textFacts.wraps`) because the paint seam has to
		-- make the same call and cannot derive it: `screen_target`'s TextWrapped rule
		-- sees the string but not the box. One decision, two seams — the same
		-- discipline `compact` already carries.
		--
		-- A ZERO (or negative) WIDTH IS NOT A WIDTH, and the rule declines to answer
		-- there. A collapsed box — a closed swipe tray, a control mid-yield — is not
		-- a label being cut, and claiming "this truncated" for one would file a
		-- finding about text nobody is being shown (measured 2026-08-13: the
		-- row-actions tray's own action labels, at w=0, in the large-text sweep).
		local singleLine = node.singleLine == true
		if not singleLine and availW ~= math.huge and availW > 0 then
			singleLine = text_metrics.minWidth(node.text or "", font, size) > availW
		end
		local wrapWidth = if singleLine then math.huge else availW
		-- THE COMPACT LADDER (director, 2026-07-27). A node that declared a shorter
		-- representation swaps to it exactly when the full one does not fit the
		-- width this node will OCCUPY — `innerMaxW`, already clamped above to the
		-- node's own fixed/percent dimension, which is the same "its own box, not
		-- its parent's offer" rule ViewThatFits had to be fixed to use twice.
		--
		-- "FITS" IS MEASURED ON ONE LINE, and it has to be. A WORD overflows the
		-- width when it does not fit, but a PHRASE wraps instead — its wrapped
		-- width is never greater than the box, so comparing wrapped widths would
		-- have made a compact form unreachable for every multi-word label. The
		-- honest question is the natural one-line width, which is also exactly the
		-- number the `singleLine` path below already reasons about.
		--
		-- WHY THE SWAP HAPPENS HERE AND NOT AT ARRANGE. Choosing after the rect is
		-- final would be measuring one string and drawing another: the box would
		-- keep the full label's height (two lines for a phrase) while a one-word
		-- compact form drew one. Deciding inside measure means the reserved box IS
		-- the compact form's box.
		--
		-- An UNBOUNDED offer never triggers it: a button free to grow shows its
		-- full label, which is the ladder's first rung and why nothing that fits
		-- today moves by a pixel.
		--
		-- The flag is assigned on EVERY measure of a node that declared one, never
		-- only set: this node is measured repeatedly at different widths (once per
		-- pass, and again by its parent's arrange at the final width), and a
		-- verdict that could only latch true would keep a compact form after a
		-- re-solve made room for the full label.
		-- THE REVEAL'S OTHER NUMBER (director 2026-08-04): a reveal node's facts
		-- carry the natural ONE-LINE width, measured here so the travel distance
		-- comes from the same pass as the truncation verdict it belongs to. Reveal
		-- nodes only — every other text pays nothing.
		local naturalW: number? = nil
		if node.reveal ~= nil then
			naturalW = text_metrics.measure(node.text or "", font, size, math.huge, lineHeight).width
		end
		local compact = node.compactText
		-- `compactPrefer` inverts the ladder: the compact form is this node's
		-- DEFAULT representation, not its degrade, so it is chosen without the fit
		-- test AND on the unbounded (natural-sizing) measure too — which is the
		-- whole point, since the box a preferred form gets must be sized for the
		-- form itself rather than for a label that will never be drawn.
		local prefer = node.compactPrefer == true
		if compact ~= nil and (prefer or availW ~= math.huge) then
			local natural = if prefer
				then nil
				else text_metrics.measure(node.text or "", font, size, math.huge, lineHeight)
			if natural == nil or natural.width > availW then
				-- a compact form is ONE word by construction (`assertCompactLabel`
				-- rejects whitespace), so it measures on one line whatever the full
				-- label's wrap state was — which is what makes `singleLine` agree
				-- across both seams without a second rule.
				local cm = text_metrics.measure(compact, font, size, math.huge, lineHeight)
				ctx.compact[node.id] = true
				recordTextFacts(
					ctx,
					node,
					cm,
					cm.width > availW,
					font,
					size,
					lineHeight,
					authoredWidth,
					naturalW,
					false
				)
				return math.min(cm.width, availW) + pl + pr, cm.height + pt + pb
			end
			ctx.compact[node.id] = false
		end
		local m = text_metrics.measure(node.text or "", font, size, wrapWidth, lineHeight, node.lineLimit)
		-- CLAMPED TO THE WIDTH THIS NODE WILL OCCUPY, not to its parent's offer. This
		-- read `innerMaxW`, which for a `fixed`-width text node is the OFFER (line
		-- 1283 excludes `text` from the self-clamp on purpose) — the exact trap
		-- `availW` was introduced above to close for the compact ladder on
		-- 2026-07-27, one line lower and still open. Measured 2026-08-13: a
		-- `fixed(150)` Button at the largest preference reported `truncated = false`
		-- while its one line wanted 340px in a 150px box, so `clippedEssential` — the
		-- check whose whole job is "this label was cut" — could not see it.
		if singleLine and availW ~= math.huge then
			recordTextFacts(ctx, node, m, m.width > availW, font, size, lineHeight, authoredWidth, naturalW, false)
			return math.min(m.width, availW) + pl + pr, m.height + pt + pb
		end
		recordTextFacts(ctx, node, m, false, font, size, lineHeight, authoredWidth, naturalW, not singleLine)
		return m.width + pl + pr, m.height + pt + pb
	end

	if node.kind == "box" or node.kind == "spacer" then
		return 0, 0
	end

	if node.kind == "scroll" then
		-- the scroll AXIS accumulates; the cross axis takes the widest/tallest
		-- child. Both passes must agree on which axis is which — a horizontal
		-- region that summed heights reported a canvas the engine could not
		-- scroll to (A-SV1).
		local axis = node.axis or "y"
		local childW = if axis == "x" then math.huge else innerMaxW
		local childH = if axis == "y" then math.huge else innerMaxH
		-- THIS SCROLLER IS THE CONTAINER ITS SUBTREE MEASURES AGAINST (§2.5). The
		-- viewport is its INNER box on both axes — including the axis the children
		-- are offered `math.huge` on, which is the whole point: a carousel page asks
		-- for a third of the window it scrolls through, not a third of the canvas.
		--
		-- Measure-time it is the OFFER's inner size; arrange-time it is the rect's.
		-- Those differ for a `hug` scroller, deliberately and visibly: once anything in
		-- the tree asks for a container-relative size the memo's key carries the
		-- container, so the arrange pass re-measures rather than replaying the
		-- offer-time answer, and what the player sees is the arrange one.
		local restoreW, restoreH, restoreKey = ctx.containerW, ctx.containerH, ctx.scopeKey
		pushContainer(ctx, innerMaxW, innerMaxH)
		local mainSum, crossMax, n = 0, 0, 0
		for _, child in node.children or {} do
			local w, h = measure(ctx, child, childW, childH)
			mainSum += (if axis == "x" then w else h)
			crossMax = math.max(crossMax, if axis == "x" then h else w)
			n += 1
		end
		restoreScope(ctx, restoreW, restoreH, restoreKey)
		local gaps = if n > 1 then gap * (n - 1) else 0
		-- THE BAR IS PART OF THE MEASURE (2026-08-08, ref_wardrobe matrix row).
		-- Arrange reserves `scrollBarReserve` off the CROSS axis whenever the
		-- scroll axis overflows — so a hug scroller that did not include the bar
		-- here reported a cross size at which it cannot reproduce itself: the
		-- parent granted content-size, arrange subtracted the bar, and every
		-- child overflowed by exactly its thickness. Same fixed-point rule the
		-- grid measure follows. The condition mirrors arrange's: reserve only
		-- when the scroll-axis content overflows the bounded offer (an unbounded
		-- offer cannot overflow, and a fitting shelf shows no bar).
		--[[ ── A SCROLLER WITH NO VIEWPORT ON ITS OWN AXIS MATERIALIZES EVERYTHING ──
			(booked ruling G5c, framework-gaps-phase2, 2026-08-22.) A scroll node inside
			ANOTHER scroller's own axis is offered `math.huge` there; if its own extent
			on that axis is not definite it resolves to its CONTENT, so viewport ==
			canvas, it scrolls nothing and pays for every child. `newVirtualList
			{ viewportExtent = "auto" }` reports that SYMPTOM but only for a list, and a
			plain ScrollView inside a ScrollView reaches no list at all.

			NARROW ON PURPOSE, and measured: the first draft put this on `resolveAxis`'s
			`fill` branch beside `percent`'s, where the ruling pointed, and it fired on
			twelve shipped scenarios — `height = fill` inside a y-scroller is an ORDINARY
			correct declaration ("as tall as my content") that resolves to exactly that.
			`percent` cannot be computed against infinity; `fill` can. The four cases and
			three negative controls are in `tests/container_relative_frame.spec.luau`. ]]
		local mainDim = dim(node, if axis == "x" then "w" else "h")
		--[[ A CONTENT-TERMS DIM IS DEFINITE TOO (framework-gaps-phase2 gap 3,
			2026-08-23), found by this very diagnostic firing on `preferred_text`'s
			`Form` — a `lines`/`rows` viewport nested inside another scroller's own
			axis, exactly the shape this check exists to police. `mainDim.type ==
			"content"` alone means "unbounded, resolves to the CONTENT" (the
			historic reading, and still true for a BARE `content`); `lines`/`rows`
			present means the opposite — a FORMULA over `ctx.metrics`, never the
			offer, joining `fixed` as a definite extent this scroller can actually
			present a smaller viewport than its canvas at. ]]
		local mainDimIsContentTerms = mainDim.type == "content" and (mainDim.lines ~= nil or mainDim.rows ~= nil)
		if
			(if axis == "x" then innerMaxW else innerMaxH) == math.huge
			and mainDim.type ~= "fixed"
			and not mainDimIsContentTerms
			and ctx.hiddenDepth == 0
		then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = `scroll region on an unbounded {axis} axis (inside another scroller's own axis?): its `
					.. `own {if axis == "x" then "width" else "height"} is '{mainDim.type}', so the viewport `
					.. "resolves to the CONTENT and this region can never scroll — every child is materialized. "
					.. "Give it a definite extent on that axis",
			})
		end
		local reserve = 0
		if ctx.scrollBarReserve > 0 then
			local mainOffer = if axis == "x" then innerMaxW else innerMaxH
			if mainOffer ~= math.huge and mainSum + gaps > mainOffer then
				reserve = ctx.scrollBarReserve
			end
		end
		if axis == "x" then
			return mainSum + gaps + pl + pr, crossMax + reserve + pt + pb
		end
		return crossMax + reserve + pl + pr, mainSum + gaps + pt + pb
	end

	if node.kind == "fits" then
		-- ViewThatFits (A-AL1): measure candidates in declared order against the
		-- space THIS container was proposed and report the first that fits. The
		-- last candidate is the fallback when none does, matching SwiftUI.
		--
		-- "the space THIS container was proposed" has to mean the space it will
		-- actually OCCUPY, not the space its parent offered. When the container's
		-- own width is definite and smaller than the offer — a capped action bar
		-- declared `percent(1, max = 620)` inside a 1200px screen — measuring the
		-- candidates at the parent's 1200 picks a row that then has to arrange
		-- inside 620, where its labels wrap and it no longer fits. Arrange re-runs
		-- the chooser at the real width, so measure and arrange disagreed and the
		-- fallback column won on every wide profile (director review 2026-07-24).
		-- `fixed` and `percent` resolve without consulting content, so asking for
		-- them here cannot recurse.
		local selfW = dim(node, "w")
		local limitW = innerMaxW
		if
			selfW.type == "fixed"
			or selfW.type == "containerRelative"
			or (selfW.type == "percent" and maxW ~= math.huge)
		then
			local resolved = resolveAxis(ctx, node, selfW, maxW, function()
				return innerMaxW
			end, ctx.containerW)
			limitW = math.max(0, resolved - pl - pr)
		end
		local children = node.children or {}
		local idx = candidate.choose(CANDIDATE_DEPS, ctx, node, limitW, innerMaxH)
		local chosen = children[idx]
		if chosen == nil then
			return pl + pr, pt + pb
		end
		local w, h = measure(ctx, chosen, limitW, innerMaxH)
		return w + pl + pr, h + pt + pb
	end

	if node.kind == "composition" then
		local resolution = compositionResolve.resolve(COMPOSITION_DEPS, ctx, node, innerMaxW, innerMaxH)
		if resolution == nil then
			return pl + pr, pt + pb
		end
		return resolution.used.w + pl + pr, resolution.used.h + pt + pb
	end

	if node.kind == "zstack" or node.kind == "anchor" or node.kind == "region" then
		local cw, ch = 0, 0
		for _, child in node.children or {} do
			local mt, mr, mb, ml = sides(child.margin)
			local w, h = measure(ctx, child, innerMaxW, innerMaxH)
			cw = math.max(cw, w + ml + mr)
			ch = math.max(ch, h + mt + mb)
		end
		return cw + pl + pr, ch + pt + pb
	end

	-- THE GRID'S MEASURE IS `src/layout/grid.luau` (both layouts, both flow
	-- directions). It answers in CONTENT extents; the padding is added here, in the
	-- one place this function adds it for every container alike. Its arrange half is
	-- the matching pair of calls in `arrange` below, and the two of them are the
	-- only places the grid's LANE/FLOW words become width and height.
	if node.kind == "gridrow" then
		local w, h = gridLib.measureRow(GRID_DEPS, ctx, node, innerMaxW, innerMaxH)
		return w + pl + pr, h + pt + pb
	end

	if node.kind == "grid" then
		local w, h = gridLib.measure(GRID_DEPS, ctx, node, innerMaxW, innerMaxH, gap)
		return w + pl + pr, h + pt + pb
	end

	-- THE WRAPPING STACKS (round 3 item A). Content is the WIDEST LINE by the SUM
	-- of the line extents, one gap between lines — the whole measure, because the
	-- plan above already owns both the child measurement and the partition.
	--
	-- The report is deliberately NOT clamped to the offer: an item wider than the
	-- line makes `maxMain` exceed it, and reporting the honest larger number lets a
	-- `hug` parent grow to fit rather than silently cropping. `arrange` clamps what
	-- is left over and says so.
	if node.kind == "hwrap" or node.kind == "vwrap" then
		local wrapH = node.kind == "hwrap"
		local plan = flowLib.plan(
			FLOW_DEPS,
			ctx,
			node,
			wrapH,
			if wrapH then innerMaxW else innerMaxH,
			if wrapH then innerMaxH else innerMaxW,
			gap
		)
		if wrapH then
			return plan.maxMain + pl + pr, plan.totalCross + pt + pb
		end
		return plan.totalCross + pl + pr, plan.maxMain + pt + pb
	end

	-- vstack / hstack
	local isH = node.kind == "hstack"
	local children = node.children or {}
	local n = #children
	local gaps = if n > 1 then gap * (n - 1) else 0
	local mainLimit = if isH then innerMaxW else innerMaxH
	local mainSum, fillWeightSum = 0, 0
	local crossOf: { [number]: number } = {}
	local marginMain: { [number]: number } = {}
	-- lazily created, and only ever by a child that declared a shrinkWeight ABOVE
	-- ZERO: a stack that opted into nothing allocates nothing here and PASS 1.5
	-- below never runs. The one cost on the inert path is the field read in PASS 1.
	--
	-- `> 0`, NOT `~= nil` (Milestone-1 review, C6). `shrinkWeight = 0` is the
	-- documented default AND a legal authored value — "never shrinks", Roblox's
	-- `UIFlexMode.None` — so a caller who writes it explicitly means the inert
	-- behaviour. The `~= nil` form allocated `shrinkBasis`, ran PASS 1.5 and called
	-- `shrinkLib.stack` for it, which then filtered it out one level down on exactly
	-- this test. Same filter, one level earlier.
	local shrinkBasis: { [number]: number }? = nil
	-- PASS 1: children with a definite main extent measure against the whole
	-- inner box, and consume it.
	for idx, child in children do
		local mt, mr, mb, ml = sides(child.margin)
		marginMain[idx] = if isH then ml + mr else mt + mb
		local childMainDim = dim(child, if isH then "w" else "h")
		if childMainDim.type == "fill" then
			fillWeightSum += childMainDim.weight or 1
		else
			local cw, ch = measure(ctx, child, innerMaxW, innerMaxH)
			mainSum += (if isH then cw + ml + mr else ch + mt + mb)
			crossOf[idx] = if isH then ch + mt + mb else cw + ml + mr
			if child.shrinkWeight ~= nil and child.shrinkWeight > 0 then
				local basis = shrinkBasis or {}
				basis[idx] = if isH then cw else ch
				shrinkBasis = basis
			end
		end
	end
	-- PASS 1.5: THE MEASURE-SIDE SHRINK (§2.4, added 2026-08-12 — the mirror that
	-- closes the seam this branch used to merely name).
	--
	-- The claim this replaces was that shrinking is an arrange-time negotiation and
	-- measure only reports what a stack would LIKE, so a deficit cannot exist here.
	-- That is true of a `hug`/`content` parent, which offers back exactly what it
	-- measured. It is false the moment the offer is DEFINITE and smaller than the
	-- content — a `fill`-width toolbar in a fixed screen — which is the canonical
	-- use of the feature. There the squeeze is knowable at measure time, and not
	-- doing it reserved the CROSS extent of a wrap that will not happen: a label
	-- squeezed to its floor wrapped to eight lines inside a row that had reserved
	-- one, and painted the other seven outside. That is the "painted at a size
	-- nobody measured" family,
	-- and shipping a new layout feature with a known instance of it inside is
	-- shipping the next one.
	--
	-- It mirrors PASS 2 below, which exists for the identical reason on the `fill`
	-- child: measure at the extent the child will ACTUALLY get, or under-report its
	-- cross size. Order matches arrange's (shrink, then fill): the freed pixels are
	-- part of what fill children share.
	--
	-- ZERO ADDED WORK WHEN NOTHING OPTED IN, deliberately — this is the hot measure
	-- path and it has a live perf budget. `shrinkBasis` is nil unless a child
	-- declared a weight, so the whole block is skipped by one nil test; the two
	-- tables it needs are allocated on the deficit path only, exactly the discipline
	-- arrange's `shrinkLib.EMPTY` was written for.
	--
	-- ...AND IT DOES NOT RUN INSIDE A `ViewThatFits` FIT PROBE (ruling 2). "Does
	-- this candidate fit?" is asked of the size the candidate would LIKE, which is
	-- SwiftUI's ideal size — a candidate that only fits after being squeezed does
	-- not fit, exactly as a Text that only fits after truncating does not fit there.
	-- See `chosenCandidate` for the ruling and the measurement; the probe is off
	-- again before the chosen candidate is measured for real, so the winner still
	-- shrinks.
	if shrinkBasis ~= nil and mainLimit ~= math.huge and not ctx.fitProbe then
		local deficit = mainSum + gaps - mainLimit
		if deficit > 0 then
			local shrunk: { [number]: number } = {}
			local absorbed =
				shrinkLib.stack(SHRINK_DEPS, ctx, children, isH, shrinkBasis :: { [number]: number }, deficit, shrunk)
			if absorbed > 0 then
				-- the report shrinks with the children: a stack that can absorb its own
				-- deficit needs the room it is left with, not the room it started from,
				-- and reporting the larger number would make measure a fixed point of
				-- nothing (the parent hands the report back and the same squeeze happens
				-- again at arrange).
				mainSum -= absorbed
				-- RE-MEASURE AT THE REDUCED OFFER, in document order — the same loop, the
				-- same reason and the same ordering rule as arrange's: last-write-wins
				-- verdict channels (`compact`, `textFacts`) must publish deterministically.
				for idx = 1, n do
					local size = shrunk[idx]
					if size ~= nil then
						local child = children[idx]
						local mt, mr, mb, ml = sides(child.margin)
						local cw, ch =
							measure(ctx, child, if isH then size else innerMaxW, if isH then innerMaxH else size)
						crossOf[idx] = if isH then ch + mt + mb else cw + ml + mr
					end
				end
			end
		end
	end
	-- PASS 2: a FILL child never receives the whole main extent — it receives its
	-- weighted share of what is left, exactly as arrange distributes it.
	--
	-- THIS PASS MIRRORS ARRANGE'S `fill` BLOCK. Arrange's SHRINK pass has its own
	-- mirror at PASS 1.5 above (it used to have none, and the gap between them was
	-- the seam recorded there). Both passes are the same rule applied to the two
	-- ways a child ends up smaller than its natural size — a fill share, or a
	-- squeeze — and both run because the CROSS extent has to be measured at the main
	-- extent the child will actually get.
	--
	-- Measuring
	-- it against the FULL extent under-reports its cross size, because less width
	-- means more wrapped lines and more height. That under-report is what a
	-- ScrollView turns into a canvas that cannot reach its own content: found live
	-- 2026-07-24 on compact-phone-landscape, where the two fill columns measured at
	-- the full 680px reported a 292px canvas for content that actually reached
	-- 443px — the bottom 151px, including the whole tile row, was unreachable by
	-- scrolling. Same root cause as the 27px cross-axis clamp the overflow
	-- diagnostic reports on the wider rows.
	local remaining = if mainLimit == math.huge then math.huge else math.max(0, mainLimit - mainSum - gaps)
	for idx, child in children do
		if crossOf[idx] ~= nil then
			continue
		end
		local mt, mr, mb, ml = sides(child.margin)
		local childMainDim = dim(child, if isH then "w" else "h")
		local share = if remaining == math.huge or fillWeightSum <= 0
			then math.huge
			else remaining * (childMainDim.weight or 1) / fillWeightSum
		-- floor is the conservative direction: a slightly narrower measurement
		-- over-reserves height rather than under-reserving it
		local childMain = if share == math.huge then math.huge else math.max(0, math.floor(share) - marginMain[idx])
		local cw, ch = measure(ctx, child, if isH then childMain else innerMaxW, if isH then innerMaxH else childMain)
		crossOf[idx] = if isH then ch + mt + mb else cw + ml + mr
	end
	local crossMax = 0
	for idx = 1, n do
		crossMax = math.max(crossMax, crossOf[idx] or 0)
	end
	local contentMain = mainSum + gaps + (if isH then pl + pr else pt + pb)
	local contentCross = crossMax + (if isH then pt + pb else pl + pr)
	if isH then
		return contentMain, contentCross
	end
	return contentCross, contentMain
end

-- `memoPlan` and its three `PLAN_*` verdicts are bound from `./measure_facts` at
-- the top of this file — the classification is pure (it reads `dim`, `mainDimOf`
-- and `ctx.memoPlans` and nothing else), and its differential-oracle evidence
-- travels with it.

-- measure pass: desired size within (maxW, maxH); math.huge = unbounded axis
--
-- PER-SOLVE MEMO (roadmap Step 9, found by the performance lab 2026-08-04). A
-- scroll node is measured TWICE by design — once by this pass, and again inside
-- `arrange`, where `measureAll` re-measures every child to decide whether the
-- engine's scrollbar has to be reserved off the cross axis ("measuring twice is
-- the cost of not guessing"). That reasoning is right and the second measure
-- stays; what was wasteful is that the second one recomputed an answer the first
-- had already produced for the SAME node at the SAME limits.
--
-- Measured on the lab's dense-scroll workload (2 000 rows, 11 mounted, steady
-- 40px/frame): `Facet/arrange` ran at 1.51ms mean against `Facet/measure` at
-- 0.23ms — 6.6x, in a pass that is supposed to be the cheap one, and 56% of the
-- whole step. The re-measure was the difference.
--
-- SAFETY. `ctx` is created fresh per `solver.solve`, nothing mutates node content
-- mid-solve, and every side effect `measure` has is an idempotent write into a
-- ctx table keyed by `node.id`. TWO contextual inputs are NOT in the argument
-- list — `ctx.hiddenDepth` (it gates diagnostics) and the nearest container
-- (§2.5, it sizes a `containerRelative` dimension) — so both are part of the key,
-- carried together as `ctx.scopeKey`. A miss recomputes exactly as before.
measure = function(ctx: Ctx, node: Node, maxW: number, maxH: number): (number, number)
	-- SCOPED TO THE SHAPES THAT PAY FOR IT (architecture review, confirmed as a
	-- real gate failure). The memo exists for ONE redundancy: `arrange`'s scroll branch
	-- re-measuring children the measure pass already sized. A tree with no scroll node
	-- has no such redundancy, so the cache can only cost — a string key and a table per
	-- node per solve.
	--
	-- That cost was measurable, not theoretical. `textinput-typing-storm` (a small tree
	-- re-solved per keystroke) crossed the bench's 1.5x regression rule with the memo
	-- unconditional: six interleaved A/B pairs read memo 1.453/1.585/1.530/1.694/1.630/
	-- 1.663 against nomemo 0.817/1.380/1.522/0.668/1.418/1.657 — worse in every pair.
	-- Re-baselining that budget to accept it was never an option; scoping the change is
	-- the fix.
	--
	-- `hasScroll` flips the first time a scroll node is measured, and a scroll node is
	-- always measured before its own children, so it is set before any call that could
	-- benefit. A tree without one never touches the cache at all.
	--
	-- ...AND NESTING IS THE SECOND ARM (L-37). A ScrollView is not the only shape that
	-- measures the same node twice: EVERY enclosing container re-measures the subtree
	-- below it, so a leaf under 30 nested stacks is measured ~16 times and a leaf under
	-- one is measured twice. `deepNesting` latches when the measure recursion first
	-- reaches `MEMO_ARM_DEPTH`, which happens on the way DOWN — before any node below
	-- it can be measured a second time.
	--
	-- WHERE THE 4 COMES FROM, and it is a break-even that was swept rather than
	-- chosen. Same 240 leaves, only the nesting depth varying, interleaved ABBA
	-- against a 2.9% A/A control (tier 1): 1 nested container +0.0%, 2 +2.1% (inside
	-- the band), 3 -12.4%, 4 -20.8%, 6 -34.5%, 10 -49.9%, 20 -69.1%, 30 -77.2%. A
	-- measure recursion of 4 is a root, two containers and a leaf, i.e. the shallowest
	-- tree the memo is measurably worth arming for. Below it the shape arms that pay
	-- nothing (`flat`, `zstack`, `wrap`) stay uncached, which is L-6's ruling intact:
	-- unconditional, the memo ran them +8% to +20% against a 1.5% control.
	--
	-- ...AND THE CROSS-SOLVE STORE ARMS IT FOR EVERY SHAPE (P1). Both arms above are
	-- about a node measured twice within ONE solve — a scroller, deep nesting. The
	-- store's win is the subtree the NEXT solve does not walk, which every shape pays
	-- for, so a surface holding one never takes this early return. `./measure_reuse`.
	local store = ctx.measures
	if store == nil and not ctx.hasScroll and not ctx.deepNesting then
		return measureUncached(ctx, node, maxW, maxH)
	end
	-- A CONSTANT-SIZE NODE IS CHEAPER TO RE-MEASURE THAN TO LOOK UP (see `memoPlan`),
	-- and that holds across solves too: its `content()` is never called, so it walks
	-- no children and there is no subtree for a hit to remove.
	local plan = memoPlan(ctx, node)
	if plan == PLAN_SKIP then
		return measureUncached(ctx, node, maxW, maxH)
	end
	-- THE KEY CARRIES THE INPUTS THE COMPUTATION ACTUALLY READS, AND NO MORE. A key
	-- with a spare field in it is not merely wasteful — it is a cache that cannot hit.
	--
	-- MEASURED (MicroProfiler capture + headless probe, 2026-08-05): the solver made
	-- 5.67 measure calls per text node per solve and this cache served 4.4% of them.
	-- The reason is `maxH`. A container measures a child against the height REMAINING
	-- after its siblings, so the offered height is different on almost every call —
	-- while a text node's answer does not depend on it at all. Its content size comes
	-- from the wrap width, and `contentSize`'s text branch never reads `innerMaxH`.
	--
	-- So for a text leaf whose HEIGHT cannot depend on the offer, `maxH` leaves the
	-- key. The three dimension types that qualify are exactly the ones `resolveAxis`
	-- answers without reading its `limit`: `fixed` (a literal), `content` (the text
	-- metrics) and `minMax` (preferred-or-content, then clamped). `fill`, `percent`
	-- and `hug` all read the limit — `hug` caps at the offer — so they keep it. Either
	-- axis being `aspect` couples the two, so that keeps it too.
	--
	-- Verified by differential fuzz against a build with the drop disabled, not by
	-- reading the code twice: this is the second cache in this function, and the FIRST
	-- one was wrong in a way only a differential oracle could see.
	-- ...AND THE SHRINK PASS NEEDS NOTHING ADDED TO IT — FROM EITHER OF ITS TWO
	-- CALLERS (§2.4, checked rather than assumed, and re-checked when the measure-
	-- side caller was added rather than inherited from the arrange-side check). That
	-- pass re-measures a squeezed child at a REDUCED OFFER and reads no other input
	-- through `measure`, so it is already a distinct `maxW`/`maxH` and already a
	-- distinct key — including when the caller is PASS 1.5, i.e. `measure` itself,
	-- one frame up its own stack.
	--
	-- Both callers are mutation-proved in tests/stack_distribution.spec.luau, and
	-- both proofs sit UNDER A SCROLLVIEW on purpose: this memo is gated on
	-- `ctx.hasScroll` two lines above, so a fixture without one runs uncached and
	-- can say nothing about the key. Dropping `maxW` here reddens "the measure MEMO
	-- tells the two offers apart" (arrange-side) and "...the MEASURE-side pass is
	-- keyed by the memo too" — and reusing the natural measurement instead of the
	-- reduced one reddens "...RE-MEASURED at the reduced offer" and "THE CLOSED
	-- SEAM".
	--
	-- WIDENED FROM TEXT LEAVES TO EVERY NODE WHOSE ANSWER CANNOT READ THE OFFER
	-- (L-37): the rule and its differential proof are in `memoPlan` above, and the
	-- measurement that forced it is that a 30-deep tree's key varied by `maxH` and by
	-- nothing else — 16.33 distinct heights per node against 1.00 distinct width.
	local dropH = plan == PLAN_HEIGHT_FREE
	-- ...AND THE CONTAINER JOINS THE KEY (§2.5, and the concrete case §Phase 0
	-- warned about). Every other term here is an input the CALLER handed down. A
	-- `containerRelative` dimension is the first one that is not: it resolves against
	-- the nearest ancestor viewport, which is not the parent's offer — so the SAME
	-- node, at the SAME `maxW`/`maxH`, legitimately wants a different answer once the
	-- container underneath it changes.
	--
	-- It changes within one solve, not only between solves: a `hug` ScrollView is
	-- MEASURED against the height it was offered and ARRANGED at the height it turned
	-- out to need, and its children are offered `math.huge` on the scroll axis in both
	-- passes. Identical key, different ruler — a silent stale hit, and the box the
	-- player sees is the arrange one. Mutation-proved in
	-- tests/container_relative_frame.spec.luau ("the measure MEMO tells two
	-- containers apart"), and that proof sits UNDER A SCROLLVIEW on purpose: this memo
	-- is gated on `ctx.hasScroll` above, so a fixture without one runs uncached and
	-- can say nothing about the key.
	--
	-- IT RIDES `ctx.scopeKey`, AND ONLY ONCE A `containerRelative` DIMENSION HAS
	-- ACTUALLY BEEN MEASURED. That condition is load-bearing rather than tidy: a
	-- scroller's container is its OFFER's inner size at measure and its RECT's at
	-- arrange, so putting it in the key unconditionally made the arrange pass miss on
	-- every child of every scroller — the exact redundancy this memo was built to
	-- remove. See `rebuildScopeKey` for the numbers and for why arming on first sight
	-- cannot produce a stale hit.
	local cacheKey = if dropH then `{maxW}|*|{ctx.scopeKey}` else `{maxW}|{maxH}|{ctx.scopeKey}`
	local perNode = ctx.measureCache[node]
	--[[ THE SLATE THIS NODE ALREADY FILLED (P1), when this solve can prove nothing
		inside it moved — and the proof is `dirtyContains`, the dirty set closed over
		ancestors, i.e. the same validity the arrange skip beside it already trusts. No
		reuse set means no proof: a full solve adopts nothing and only refills.

		`adopted` is true at most ONCE per node per solve (binding the slate into the
		per-solve memo is what makes that so), which is what makes it a safe gate for
		the diagnostics replay below: a slate THIS solve wrote must not re-file
		findings it has already filed. ]]
	local adopted = false
	if perNode == nil then
		if store ~= nil then
			perNode, adopted = measureReuse.adopt(
				store,
				node,
				-- THE MEASURE HALF OF THE DIRT (wicked-fast O2). The arrange skip
				-- below reads `dirtyContains`; this gate reads `measureContains`,
				-- the closure over `measure`-classed dirt alone, because an
				-- arrange-only prop (`offsetX`, `anchor`, …) provably moves no
				-- measurement — proved by mounting each of them in
				-- `tests/layout_prop_dirt.spec.luau`, not by grepping the schema.
				ctx.reuse ~= nil and ctx.reuse.measureContains[node.id] ~= true,
				ctx.containerW,
				ctx.containerH
			)
		else
			perNode = {}
		end
		ctx.measureCache[node] = perNode
	end
	do
		local hit = perNode[cacheKey]
		if hit ~= nil then
			-- THE PACKED ENTRY: a node that publishes NOTHING is filed as the array
			-- `{ w, h }` and read back in two indexes (L-37). `ctx.textStates`,
			-- `ctx.compact` and `ctx.textFacts` are written only by the `text` branch of
			-- `contentSize` and `ctx.compositions` only by `composition_resolve.resolve`, so
			-- for every other kind the four replay assignments below are provably four
			-- writes of `nil` over `nil`. Measured on the `flat` shape arm: replaying
			-- them anyway cost more than the measure the hit saved (+7.8% against a 1.5%
			-- A/A control); packed, the same arm runs -1.3%.
			local packedW = hit[1]
			if packedW ~= nil then
				--[[ ...AND THE CUT COUNT RIDES THE ENTRY (DIR wave contract 7).
					`ctx.fitCuts` is what `chosenCandidate` reads to refuse a candidate
					that only fits because its label was ellipsized. It is incremented in
					`recordTextFacts`, which a cache hit never calls — and a candidate is
					a WHOLE SUBTREE whose root is usually not a text node, so the packed
					early return above short-circuits every text inside it.

					Measured on the shipped HUD at the Largest preference: the first
					probe of the objective chip counted its cut and refused the rung, the
					second probe of the SAME box hit this line and counted nothing, and
					the rung came back — so the chip swapped at Larger and reverted at
					Largest. A verdict that is only true the first time is not a verdict.
					`hit[3]` is nil on every measure that cut nothing, which is all but a
					handful, so the packed form stays two slots wide in the common case. ]]
				if hit[3] ~= nil then
					ctx.fitCuts += hit[3]
				end
				return packedW, hit[2]
			end
			-- REPLAY THE PUBLISHED VERDICTS, DO NOT MERELY RETURN THE SIZE.
			-- (architecture review 2026-08-04, BLOCKER-1 — caught by a differential
			-- fuzz over 800 seeded trees.)
			--
			-- These three channels are documented as "assigned on EVERY measure of the
			-- node, so the facts published are the ones the reserved box was built
			-- from" (see `ctx.compact` and `recordTextFacts` above). Their published
			-- value is decided by LAST WRITE WINS across boxes — a node is measured
			-- repeatedly at different widths and the final logical measure is the one
			-- `arrange` snapshots.
			--
			-- A cache that returned only `(w, h)` silently changed that rule to "the
			-- first measure of each distinct box wins", which differs whenever the
			-- order is measure(A) -> measure(B) -> measure(A). The fuzz found exactly
			-- that: geometry byte-identical across all 800 trees, but `compact` flipped
			-- on 3 and `textFacts` on 12 — including `truncated` going true -> false,
			-- which is what gates the full-value disclosure path and the reveal. A cut
			-- label reporting `truncated = false` loses its accessible full value: a
			-- Step 8.5 contract regression, geometry unchanged.
			--
			-- Replaying restores last-write-wins exactly while keeping the saving. Note
			-- `nil` is a legitimate replay value (the original call may not have written
			-- the channel at all), so these are plain assignments, not `or` merges.
			ctx.textStates[node.id] = hit.textState
			ctx.compact[node.id] = hit.compact
			ctx.textFacts[node.id] = hit.textFacts
			-- `ctx.compositions` is re-derived by `arrange` from its own box today, so
			-- replaying it changes nothing — it is replayed anyway so that the day an
			-- arrange branch reads the leftover instead, this does not become the same
			-- bug a second time.
			ctx.compositions[node.id] = hit.composition
			-- ...and the cut count, for the reason the packed branch above records
			if hit.cuts ~= nil then
				ctx.fitCuts += hit.cuts
			end
			--[[ ...AND THE FINDINGS RIDE THE ENTRY TOO (P1), for the reason the cut
				count does one branch up. A cross-solve hit removes a whole subtree's
				measure, and the four sites that file from one — percent or
				containerRelative on an unbounded axis, aspect on both, a scroll region
				on an unbounded axis — are inside it. Without this a malformed subtree
				goes QUIET the moment it stops being dirty, silencing the one channel
				every layout defect in this repo was caught by. `nil` on every
				well-formed tree. ]]
			if adopted and hit.diags ~= nil then
				for _, d in hit.diags do
					table.insert(ctx.diagnostics, d)
				end
			end
			return hit.w, hit.h
		end
	end
	-- the cut count this measure produces is part of what it publishes (contract 7)
	local cutsBefore = ctx.fitCuts
	local dBefore = #ctx.diagnostics
	local mw, mh = measureUncached(ctx, node, maxW, maxH)
	local cuts = ctx.fitCuts - cutsBefore
	local dAfter = #ctx.diagnostics
	--[[ FROZEN, BECAUSE THIS ENTRY OUTLIVES THE SOLVE (P1 review, IMPORTANT 3). The
		same finding TABLES are re-inserted on every adopted hit for as long as the
		slate lives, and `controller.diagnostics()` clones the LIST alone — so a
		consumer writing to a finding it was handed would corrupt the store forever.
		Frozen rather than copied on replay: a copy allocates on the hit path this
		exists to keep allocation-free and only narrows the corruption to one solve,
		while a frozen table turns that write into a loud error at its own line.
		Shallow suffices — a finding is flat, and `auditPlacement` stamps `filedBy` at
		BUILD time. ]]
	local diags = if dAfter > dBefore then table.move(ctx.diagnostics, dBefore + 1, dAfter, 1, {}) else nil
	if diags ~= nil then
		-- `isfrozen` first: a finding filed deep in a subtree is captured by EVERY
		-- ancestor whose measure enclosed it, and `table.freeze` raises on a table
		-- that already is.
		for _, d in diags do
			if not table.isfrozen(d) then
				table.freeze(d)
			end
		end
		table.freeze(diags)
	end
	-- one more distinct offer on this node's slate; the cap that keeps a node whose
	-- offers DRIFT from accumulating an entry per frame forever is asked at `adopt`
	if store ~= nil and perNode[cacheKey] == nil then
		measureReuse.note(store, node.id)
	end
	-- ...and the matching write of the packed form, for the kinds that cannot publish
	local kind = node.kind
	if kind ~= "text" and kind ~= "composition" and diags == nil then
		perNode[cacheKey] = if cuts > 0 then { mw, mh, cuts } else { mw, mh }
		return mw, mh
	end
	-- captured AFTER the call, so the entry holds what this measure published
	perNode[cacheKey] = {
		w = mw,
		h = mh,
		cuts = if cuts > 0 then cuts else nil,
		diags = diags,
		textState = ctx.textStates[node.id],
		compact = ctx.compact[node.id],
		textFacts = ctx.textFacts[node.id],
		composition = ctx.compositions[node.id],
	}
	return mw, mh
end

measureUncached = function(ctx: Ctx, node: Node, maxW: number, maxH: number): (number, number)
	ctx.measured += 1
	-- THE NESTING ARM (L-37), counted here because this is the only frame the measure
	-- recursion actually descends through — `measure` returns a cached answer without
	-- entering one. Two integer operations on the uncached path and nothing on the
	-- cached one; see `measure`'s gate for the swept break-even behind the constant.
	local depth = ctx.mdepth + 1
	ctx.mdepth = depth
	if depth >= MEMO_ARM_DEPTH then
		ctx.deepNesting = true
	end
	ctx.offers[node.id .. "|w"] = maxW
	ctx.offers[node.id .. "|h"] = maxH
	-- the gate for the memo above: a scroll node is measured before its children, so
	-- setting this here arms the cache for exactly the subtree that benefits
	if node.kind == "scroll" then
		ctx.hasScroll = true
	end
	local wDim, hDim = dim(node, "w"), dim(node, "h")
	-- ARM THE CONTAINER TERM OF THE CACHE KEY (§2.5), the same shape `hasScroll`
	-- has one branch up: a tree that never asks for a container-relative size keeps
	-- the exact key the memo carried before this stage. See `armContainer` for why
	-- arming on first sight — rather than up front — cannot produce a stale hit.
	if not ctx.hasContainerRelative and (wDim.type == "containerRelative" or hDim.type == "containerRelative") then
		armContainer(ctx)
	end
	if ctx.analyze then
		-- recorded where the OFFER is in hand, because that is what decides it for a
		-- percent or fill dimension. Last write wins, exactly like the other
		-- per-measure verdicts: the final logical measure is the one arrange uses.
		ctx.boundary[node.id] = axisAbsorbs(wDim, maxW, hDim, maxH) and axisAbsorbs(hDim, maxH, wDim, maxW)
	end
	if wDim.type == "aspect" and hDim.type == "aspect" then
		table.insert(ctx.diagnostics, {
			node = node.id,
			issue = "aspect on both axes is undefined; treating both as content",
		})
		wDim, hDim = CONTENT, CONTENT
	end
	local cw: number? = nil
	local chS: number? = nil
	local function content(): (number, number)
		if cw == nil then
			cw, chS = contentSize(ctx, node, maxW, maxH)
		end
		return cw :: number, chS :: number
	end
	-- THE COMPACT LADDER NEEDS A MEASURE EVEN WHEN NOTHING ELSE DOES (found live
	-- 2026-07-30, RascalRally's sponsor table). `content()` is lazy — a node whose
	-- BOTH dimensions are fixed never asks for its content size, because nothing
	-- about its box depends on it. But the compact verdict lives inside that same
	-- measure, so an icon button declared at the target floor
	-- (`width = height = { fixed, "targetSizes.minimum" }` — the shape every spec
	-- writes for a 44px control) never ran the ladder and painted its full label
	-- ellipsized instead of its glyph. The whole point of `compactLabel` is that
	-- the label does not fit, so the case it was built for was the one case that
	-- could not reach it.
	--
	-- Forcing the measure here keeps ONE decision path — the same `availW` rule,
	-- the same "assigned on EVERY measure" contract — and costs one cached text
	-- measure on the bounded set of nodes that declared a compact form.
	--[[ ...AND `textSize = "fit"` NEEDS ONE FOR EXACTLY THE SAME REASON (audit §10).
		A fit node's whole purpose is a label inside a box the AUTHOR pinned — the
		production role-pick CTA is `fixed(240) x fixed(52)` — so both dimensions are
		fixed and nothing about the box depends on the content. Without this the
		lazy `content()` is never asked, the fit is never resolved, and the paint
		seam finds no size to write: the one case the prop exists for would be the
		one case that could not reach it. That is the compact ladder's own defect,
		found live in 2026-07-30 and recorded directly above, which is why the fix
		is the same line rather than a second mechanism. ]]
	if node.compactText ~= nil or node.textFit ~= nil then
		content()
	end

	local w: number
	local h: number
	-- ASPECT PAIRED WITH FILL (found live 2026-07-24). `resolveAxis` can only
	-- report CONTENT for a `fill` axis at measure time, and a Box has no content —
	-- so a 16:9 media box paired with `width = fill` measured 0 x 0 here and only
	-- became 328 x 185 at arrange, where the paired extent is finally known. Every
	-- ancestor therefore under-measured by exactly the aspect height, and a
	-- ScrollView built its canvas from that number: the adaptive_controls canvas
	-- came out 664px for content reaching 849px — 185px short, exactly the media
	-- box — leaving the stat grid and tile row unreachable by scrolling.
	-- `fill` means "take the extent the parent offers", and that extent is the
	-- limit we were handed, so use it rather than pretending the box is empty.
	local function pairedExtent(paired: Dim, limit: number, fallback: number): number
		return if paired.type == "fill" and limit ~= math.huge then limit else fallback
	end
	if wDim.type == "aspect" then
		h = resolveAxis(ctx, node, hDim, maxH, function()
			local _, c = content()
			return c
		end, ctx.containerH)
		h = pairedExtent(hDim, maxH, h)
		w = roundPx(h * (wDim.ratio :: number))
	elseif hDim.type == "aspect" then
		w = resolveAxis(ctx, node, wDim, maxW, function()
			local c, _ = content()
			return c
		end, ctx.containerW)
		w = pairedExtent(wDim, maxW, w)
		h = roundPx(w / (hDim.ratio :: number))
	else
		w = resolveAxis(ctx, node, wDim, maxW, function()
			local c, _ = content()
			return c
		end, ctx.containerW)
		h = resolveAxis(ctx, node, hDim, maxH, function()
			local _, c = content()
			return c
		end, ctx.containerH)
	end
	ctx.mdepth = depth - 1
	return w, h
end

-- ===== THE PLACEMENT-PROP READ TABLE (parity round 2 §2.1) ==================
--
-- MOVED to `src/layout/placement_audit.luau` on 2026-08-14 — its header carries
-- the whole rationale, including the part of the old comment here that still
-- holds ("it lives next to the BRANCHES, never next to its reader"). The short
-- version: this file crossed the 200,000-char `Script.Source` write cap and
-- stopped live-syncing into an open Studio session, and the read table is the
-- one block in it that touches no solve state at all — no `ctx`, no `measure`,
-- no `arrange` local — so it could leave without taking an argument with it.
--
-- Re-exported under its own name because that is what `renderer.toLayoutNode`,
-- `tests/placement_audit.spec.luau` and every doc call it.
solver.auditPlacement = placementAudit.auditPlacement

-- ===== THE ARRANGE PASS'S PURE ARITHMETIC =================================
--
-- MOVED to `src/layout/placement.luau` on 2026-08-22 — `ANCHOR_FACTORS`,
-- `offsetPx`, `offsetFill`, `alignOffset` and `distributionOf` (whose body sat
-- below the shrink pointer). Its header carries the rationale each of them used
-- to state here, unabridged.
--
-- The short version of why they could leave: not one of them reads a node, a
-- `ctx` or a mutable upvalue of this file — they are functions on numbers — and
-- `alignOffset` has been crossing a module boundary BY VALUE since the grid
-- split, because it is declared below `grid.arrange`'s call site and a closure
-- naming it there would resolve the nil global. `tools/lune/verify/data/source-cap-ledger.md`
-- names this block as the seam behind `flowPartition`/`flowPlan`, and its trigger
-- is a STATE: the extraction PRECEDES a round's own changes.
--
-- Bound locally rather than called through the module table because every one of
-- them is on the per-child arrange path, where a table index per call is a bench
-- regression this file has already paid for once.
local ANCHOR_FACTORS = placementLib.ANCHOR_FACTORS
local offsetPx = placementLib.offsetPx
local offsetFill = placementLib.offsetFill
local alignOffset = placementLib.alignOffset
local distributionOf = placementLib.distributionOf

-- a px number as an author would read it back: whole when it is whole (an
-- authored `itemExtent = 56` must not be quoted back as "56.00"), two places
-- when a live extent computed from theme metrics is not
local function formatPx(v: number): string
	if v == math.floor(v) then
		return string.format("%d", v)
	end
	return string.format("%.2f", v)
end

--[[ ── DOES THIS CHILD ABSORB ITS OWN OVERFLOW ON THIS AXIS? ────────────────────
	Read only by the declared-slot guard below (`Node.virtualSlot`), which is the
	one comparison in this file that does NOT excuse a `fill` axis — a virtual
	list row is a declared px CAP, and declaring `height = fill` inside one buys
	the content nothing but a box it will paint straight out of.

	The exception that survives is the one `zstack_fill_diagnostic.spec` was
	written for: a child that SCROLLS or CLIPS its own content honestly measures
	taller than any box and honestly never paints outside it. That is not a lying
	extent, and reporting it would recreate the false positive three reference
	proofs once carried `overflow = "clip"` to silence. ]]
local function absorbsOverflow(child: Node, axisIsX: boolean): boolean
	local declared = child.overflow
	if declared == "clip" or declared == "scroll" then
		return true
	end
	-- a scroller absorbs only along the axis it scrolls: a horizontal shelf in a
	-- vertical row is still as tall as it says it is
	return child.kind == "scroll" and ((child.axis or "y") == "x") == axisIsX
end

-- ===== THE SHRINK PASS (§2.4) AND ITS DEGRADE CASCADE ======================
--
-- MOVED to `src/layout/shrink.luau` on 2026-08-14 — its header carries the whole
-- of the reasoning that used to live here (both block comments moved with the
-- code, unabridged: what the two inputs are, the two rulings Roblox's docs leave
-- undefined, why the pass runs in BOTH passes, and the compact -> truncate ->
-- clip ladder with the measured defect that forced it).
--
-- The short version of why it could leave: this file crossed the 200,000-char
-- `Script.Source` write cap and stopped live-syncing into an open Studio
-- session. `shrinkStack` was the one extracted block that WROTE a mutable upvalue
-- of this file — it was a forward declaration assigned ~2,300 lines below where
-- both callers needed its name — so lifting it out is what makes that upvalue go
-- away rather than something the split had to work around. The three helpers it
-- reads (`mainDimOf`, `sides`, `textTypography`) are immutable module-level
-- functions here and are handed over explicitly as `SHRINK_DEPS`, declared with
-- the forward declarations it replaced.
--
-- ONE function, both callers, exactly as before: the measure branch's PASS 1.5
-- and arrange's own block each call `shrinkLib.stack`. A second copy is the
-- "measured one shape, arranged another" defect this file has fixed four times.

-- arrange pass: assign rects into out[id]
--[[ THE CONTAINMENT CHECK, ON THE ONE AXIS NOTHING ELSE WATCHES.

	Every other overflow finding in this file is derived from a MEASURE against an
	offer. This one is derived from the RECT the child was finally given, which is
	the only instrument that can see a box placed outside its parent by ARITHMETIC
	rather than by size — the class the solver already knew about, and the
	property `tests/lib/overflow_guard.luau` now asserts from the
	adapter side after every settle.

	IT POLICES THE STACK'S CROSS AXIS AND NOTHING ELSE, and the scope was measured
	rather than chosen: `./placement_audit` carries the counts. The main axis is
	already reported by name and by number two lines above the loop; `zstack` and
	`anchor` place children outside their box by design and have their own finding
	and their own opt-out. What is left is the axis a stack's own `min(desired,
	crossAvail)` is supposed to guarantee — so a child outside it means the
	guarantee broke, and until now nothing said so.

	TWO COMPARISONS ON THE COMMON PATH: a contained child never reaches
	`axisAbsorbs`, never reaches the route test and never allocates.
]]
local function noteContainment(
	ctx: Ctx,
	node: Node,
	child: Node,
	rect: Rect,
	innerX: number,
	innerY: number,
	innerW: number,
	innerH: number,
	axisIsX: boolean
)
	if ctx.hiddenDepth ~= 0 then
		return
	end
	local near = if axisIsX then innerX - rect.x else innerY - rect.y
	local far = if axisIsX then (rect.x + rect.w) - (innerX + innerW) else (rect.y + rect.h) - (innerY + innerH)
	if near <= 0.5 and far <= 0.5 then
		return
	end
	if placementAudit.routesOverflow(node) then
		return
	end
	--[[ THE PARENT MUST BE UNABLE TO GROW, and the answer comes from `axisAbsorbs`
		above rather than from a second reading of the resolver — a `hug` or
		`content` parent that ends up too small has a different story (its own
		parent squeezed it) and the measure-side findings already tell it. The
		parent's own rect IS its resolved extent by the time it is placing children,
		so the "bounded" arm of that predicate is answered by the box itself. ]]
	local wD, hD = dim(node, "w"), dim(node, "h")
	local absorbs = if axisIsX then axisAbsorbs(wD, innerW, hD, innerH) else axisAbsorbs(hD, innerH, wD, innerW)
	if not absorbs then
		return
	end
	local found = placementAudit.containment(node, child, rect, innerX, innerY, innerW, innerH, axisIsX)
	if found == nil then
		return
	end
	for _, finding in found do
		table.insert(ctx.diagnostics, finding)
	end
end

--[[ ...AND THE DIRT THAT MOVED A NODE IS NOT THE DIRT THAT MOVES ITS CHILDREN.
	`translatable` answers for the subtree; this answers for the ROOT, and the arm
	was wrong without it (three measured shapes in `tests/translate_arm.spec`, which
	also pins the partition against `schema.propDirty()`): `measureContains` names
	every measure-classed prop this body reads to place children; of the eight
	arrange-classed ones, four are read off the CHILD by its parent and are already
	spent in our `rect`, `hidden` never moves a rect, and `alignH`/`alignV`/
	`distribute` ARE read off the node — recorded and compared BY VALUE, since
	absence is a value (a reactive `distribute` can go back to nil). ]]
local function selfArrangeKey(node: Node): string?
	local d, ah, av = node.distribute, node.alignH, node.alignV
	if d == nil and ah == nil and av == nil then
		return nil -- the overwhelming majority: three field reads, no allocation
	end
	return `{d}|{ah}|{av}`
end

-- A `nil` measure half REFUSES every dirty root: the hand-built `reuse` tables in
-- `tests/` carry none, and a set that cannot answer is not "clean".
local function selfPlaces(reuse: any, node: Node, prev: any): boolean
	local measures = reuse.measureContains
	return measures ~= nil and measures[node.id] ~= true and prev.selfArrange == selfArrangeKey(node)
end

-- NO CHILD IN THE DIRTY SET => NO DESCENDANT IN IT (it is prefix-closed), so one
-- pass over the children answers for the subtree. It also refuses a child the
-- previous solve never recorded, which only a torn `lastResult` reaches.
local function translatable(reuse: any, node: Node): boolean
	local kids = node.children
	if kids == nil then
		return true
	end
	local contains, rects = reuse.dirtyContains, reuse.previous.rects
	for _, child in kids do
		local id = child.id
		if contains[id] == true or rects[id] == nil then
			return false
		end
	end
	return true
end

--[[ RE-BASE EVERY DESCENDANT ONTO THE ROOT'S NEW ORIGIN. Returns false — having
	written some — if a node below has no previous entry; the caller rolls the
	partial run back and takes the ordinary arrange. Not dead code: `translatable`
	inspects DIRECT children only, and the argument that a new GRANDCHILD cannot
	reach here runs through `builtIds` and `structural_scope.widen` in two other
	files. One nil test buys it. ]]
local function translateDescendants(ctx: Ctx, node: Node, base: Rect, was: Rect, out: { [string]: any }): boolean
	local kids = node.children
	if kids == nil then
		return true
	end
	local rects = (ctx.reuse :: any).previous.rects
	local paths, entries = ctx.translatedPaths, ctx.translatedEntries
	for _, child in kids do
		local prevEntry = rects[child.id]
		if prevEntry == nil or prevEntry.rect == nil then
			return false
		end
		local old = prevEntry.rect
		local entry = table.clone(prevEntry)
		-- FROM THE ROOT'S ORIGIN, NOT BY ADDING A DELTA: `old.x + (new - was)` gains a
		-- rounding per solve and `tests/table.spec` read 35.99999999999998 for a row
		-- whose closed x is exactly 36. This form is idempotent.
		entry.rect = table.freeze({ x = base.x + (old.x - was.x), y = base.y + (old.y - was.y), w = old.w, h = old.h })
		entry.moveOnly = true
		entry.prev = prevEntry
		-- THE CHAIN BREAK. `prev` has one reader — the next commit's `skip`, comparing
		-- identity — and the entry superseded above no longer needs its own, or the
		-- node retains its whole history: tick N holds N-1 holds N-2, forever.
		prevEntry.prev = nil
		out[child.id] = entry
		ctx.translated += 1
		ctx.rectInserts += 1
		local n = #paths + 1
		paths[n] = child.id
		entries[n] = entry
		if not translateDescendants(ctx, child, base, was, out) then
			return false
		end
	end
	return true
end

local function arrange(ctx: Ctx, node: Node, rect: Rect, out: { [string]: any })
	-- THE SKIP. Same solve, same ctx, same traversal — this subtree just does not need
	-- walking: no dirty node inside it, and it is landing on the rect it already had.
	local reuse = ctx.reuse
	-- set by the translate arm below, consumed after the entry write. `tprev` is
	-- captured HERE because `out` IS `reuse.previous.rects` (see `solve`): after the
	-- write the map hands back the table it just wrote.
	local tdx: number?, tdy: number?, tprev: any = nil, nil, nil
	if reuse ~= nil then
		local prev = reuse.previous.rects[node.id]
		local pr = if prev ~= nil then prev.rect else nil
		-- ...AND THE CONTAINER IS THE ONE IT ANSWERED AGAINST (§2.5 x incremental
		-- layout — RED-TEAM Milestone 1, HIGH 3, tests/container_relative_incremental).
		--
		-- The rect above is the whole argument for every dimension the solver had
		-- before §2.5: each resolves against the parent's OFFER, and a subtree landing
		-- on the rect it already had was offered what it was already offered. A
		-- `containerRelative` dimension is the first one that is not a function of its
		-- ancestor's rect at all — it reads the nearest scroll VIEWPORT — so a wrapper
		-- whose own rect never moves could replay a descendant sized against a
		-- container that has since narrowed (a scrollbar reserve arming is enough).
		-- The measure memo's key was widened for this; the skip was not, and the skip
		-- is the shipped default.
		--
		-- ONE CHECK AT THE SUBTREE ROOT COVERS THE WHOLE SUBTREE: below this node the
		-- container changes only at a `scroll` node, whose pushed inner size derives
		-- from its own replayed rect, so if the container matches here it matches
		-- everywhere the replay reaches. `containerRelativeInside` is stamped at tree
		-- build time and is absent on the overwhelming majority of nodes, so the
		-- ordinary path pays one field test.
		local containerOk = node.containerRelativeInside ~= true
			or (prev ~= nil and prev.containerW == ctx.containerW and prev.containerH == ctx.containerH)
		-- THE SIZE TEST IS SHARED BY BOTH ARMS (O3): a subtree that resized has to be
		-- re-entered whatever its origin did, so it is asked first and once.
		if pr ~= nil and containerOk and pr.w == rect.w and pr.h == rect.h then
			local clean = reuse.dirtyContains[node.id] ~= true
			if clean and pr.x == rect.x and pr.y == rect.y then
				--[[ ...AND THE SKIP IS THE WHOLE OF IT (P2). It used to call `replaySubtree`,
					which walked the subtree and re-inserted every descendant into a fresh
					map — the O(N) pass incremental layout exists to avoid, paid as the price
					of avoiding it: 5 115 nodes and 3.26 ms of `Facet/arrange` on a zero-dirt
					L solve, copying a map the solve already held. `solve` now starts FROM
					that map (see `out`), so the subtree is already right, table for table.

					NOR ARE THE VERDICT CHANNELS: `ctx.textStates`/`compact`/`textFacts` are
					read only where a WALKED node's entry is built, so the old copies were
					reachable only on the partial-failure path the recursion itself made —
					where they overwrote this solve's fresh verdicts with the last one's. ]]
				return
			end
			--[[ THE TRANSLATE (wicked-fast O3). Same size, moved origin, and nothing
				inside is dirty — `dirtyContains` proves that in one test per CHILD, not per
				descendant, because it is closed over ancestors. So the subtree is its old
				rects re-based onto one new origin: no measure, no arrange, no re-entry. A
				dirty node still qualifies when its own dirt is dirt its parent already
				spent (`selfPlaces`), which is what makes the plate ROOT the translate root.
				IT DOES NOT RETURN HERE: only the ordinary write below records the root's
				own rect, with this solve's offers and verdicts. ]]
			-- the cheap gate first: `translatable` walks the children, `selfPlaces` is
			-- two field reads and only runs at all when the node is itself dirty
			if (clean or selfPlaces(reuse, node, prev)) and translatable(reuse, node) then
				tdx, tdy, tprev = rect.x - pr.x, rect.y - pr.y, prev
			end
		end
	end
	ctx.arranged += 1
	ctx.rectInserts += 1
	local gap = node.gap or 0
	out[node.id] = {
		-- FROZEN: every later skip hands this exact table forward, so the read-only
		-- contract on a solved rect is a fact rather than a convention (P2 review).
		rect = table.freeze(rect),
		-- THE CONTAINER THIS SUBTREE RESOLVED AGAINST (§2.5), recorded only for the
		-- subtrees whose answer depends on it, so a later solve's reuse skip can ask
		-- "is this still the ruler I measured with?" — the question the rect cannot
		-- answer. Both nil everywhere else, which is nearly everywhere.
		containerW = if node.containerRelativeInside then ctx.containerW else nil,
		containerH = if node.containerRelativeInside then ctx.containerH else nil,
		-- the OFFER this node was measured against, so a later solve can ask "is this
		-- the same question I already answered?" — a rect alone cannot say that
		offerW = ctx.offers[node.id .. "|w"],
		offerH = ctx.offers[node.id .. "|h"],
		kind = node.kind,
		overflow = node.overflow,
		textState = ctx.textStates[node.id],
		-- the compact verdict rides the SAME channel as the rect it produced, so
		-- the paint seam cannot read a different answer than the box was reserved
		-- for. `nil` on every node that declared no compact form.
		compact = ctx.compact[node.id],
		-- ...and so do the text facts, for the same reason: "this label was cut"
		-- is only meaningful beside the box it was cut to fit. `nil` on every node
		-- that is not text.
		textFacts = ctx.textFacts[node.id],
		-- the declared target floor of an interactive node, carried through so a
		-- pure audit can tell an interactive rect from a decorative one without a
		-- class table it has no business owning. `nil` = no floor declared.
		hitFloor = node.hitFloor,
		-- the arrange-classed props this body reads about its OWN children, so the O3
		-- arm can ask a dirty node "did the way I place them change?". `nil` on nearly
		-- every node.
		selfArrange = selfArrangeKey(node),
	}
	if tdx ~= nil then
		local entry = out[node.id]
		local dx, dy = tdx :: number, tdy :: number
		-- THE ROOT IS A MOVE TOO, AND SAYS SO — all three proved above. Inert until T5b
		-- takes it out of the commit-side `nodeDirty` set, which `skip` reads first.
		entry.moveOnly = true
		entry.prev = tprev
		tprev.prev = nil
		local from = #ctx.translatedPaths + 1
		if translateDescendants(ctx, node, rect, tprev.rect, out) then
			ctx.translatedRoots[node.id] = { dx = dx, dy = dy, from = from, to = #ctx.translatedPaths }
			-- WHO WALKED: NOT THIS NODE. Its body did not run, so `solve`'s replay must
			-- replay its previous findings as for a skipped subtree. `arranged` and absent
			-- from `walkedIds` is a NEW class — one set before O3 — and marking it walked
			-- would delete the diagnostics of every node that only moved.
			return
		end
		-- REFUSED, AND ROLLED BACK. The dispatch below rewrites every descendant; what
		-- must not survive is the partial run's BOOKKEEPING, or
		-- `rectInserts == arranged + translated` counts the same nodes twice.
		local wrote = #ctx.translatedPaths - from + 1
		if wrote > 0 then
			for i = #ctx.translatedPaths, from, -1 do
				ctx.translatedPaths[i] = nil
				ctx.translatedEntries[i] = nil
			end
			ctx.translated -= wrote
			ctx.rectInserts -= wrote
		end
		entry.moveOnly = nil
		entry.prev = nil
	end
	-- WHO WALKED, for the diagnostic replay in `solve`; on a reuse solve this set is
	-- the touched path, not the tree. BELOW the entry write since O3: a translate root
	-- returned above without running its body, a REFUSED one did run and is here.
	if reuse ~= nil then
		ctx.walkedIds[node.id] = true
	end

	-- THE PADDING FACTS ARE COMPUTED BEFORE THE LEAF RETURN (director report
	-- 2026-07-28). A leaf Button is `kind = "box"`, so it returned here — which
	-- meant the two content-box diagnostics below were structurally unreachable
	-- for the entire class of node whose own TEXT is its content. Defect 3 arrived
	-- in exactly that shape: a Glossy Touch Button with a zero content box, drawing
	-- nothing, reporting nothing. Four lines of arithmetic are cheap; a silent
	-- blank control is not.
	local pt, pr, pb, pl = sides(node.padding)
	local innerX, innerY = rect.x + pl, rect.y + pt
	local innerW = math.max(0, rect.w - pl - pr)
	local innerH = math.max(0, rect.h - pt - pb)

	-- ...AND THE REPORTS THIS NODE'S OWN BOX MAKES, which moved to
	-- `./arrange_reports` on 2026-09-02 for the Source-write headroom the translate
	-- arm needed (`source-cap-ledger.md`). They are reported HERE, before the leaf
	-- return below, and they need nothing from this file but the values on this line.
	arrange_reports.box(ctx, node, rect, innerW, innerH, pt, pr, pb, pl)

	-- a leaf has no children to place, and everything below this line places
	-- children. It reports first (above) and returns here.
	if node.kind == "text" or node.kind == "box" or node.kind == "spacer" then
		return
	end

	if node.kind == "scroll" then
		local axis = node.axis or "y"
		local isX = axis == "x"
		local contentW, contentH = 0, 0
		local childSizes = {}
		-- SCROLLBAR RESERVATION (director review 2026-07-24). The engine draws the
		-- scrollbar INSIDE the region, overlapping whatever the solver put there:
		-- live, a 328px-wide scroll host reported AbsoluteWindowSize 320 while
		-- content was laid out to the full 328, so the right 8px of every control
		-- in the fixture sat underneath the bar. Reserve the bar's thickness off
		-- the CROSS axis whenever the content actually overflows — which is exactly
		-- when the engine shows it. Measuring twice is the cost of not guessing.
		-- The threshold is stable: reserving makes the cross axis narrower, which
		-- can only make the scroll axis longer, so a region that overflowed at the
		-- full width still overflows at the reserved width.
		local function measureAll(crossLimitW: number, crossLimitH: number)
			local cw, ch = 0, 0
			local sizes = {}
			for _, child in node.children or {} do
				local w, h = measure(
					ctx,
					child,
					if isX then math.huge else crossLimitW,
					if axis == "y" then math.huge else crossLimitH
				)
				table.insert(sizes, { w = w, h = h })
				if isX then
					cw += w
					ch = math.max(ch, h)
				else
					cw = math.max(cw, w)
					ch += h
				end
			end
			local g = if #sizes > 1 then gap * (#sizes - 1) else 0
			if isX then
				cw += g
			else
				ch += g
			end
			return sizes, cw, ch
		end
		-- THE CONTAINER THIS SUBTREE SIZES AGAINST (§2.5), pushed around EVERY
		-- measure and every arrange below — and re-pushed after the scrollbar
		-- reservation, because reserving the bar makes the viewport genuinely
		-- narrower and a page sized against the pre-reserve number would sit under
		-- the bar. Same fact the reservation already re-measures for.
		local restoreW, restoreH, restoreKey = ctx.containerW, ctx.containerH, ctx.scopeKey
		local reserve = ctx.scrollBarReserve
		local spentReserve = 0
		pushContainer(ctx, innerW, innerH)
		childSizes, contentW, contentH = measureAll(innerW, innerH)
		if reserve > 0 then
			local overflows = if isX then contentW > innerW else contentH > innerH
			if overflows then
				if isX then
					innerH = math.max(0, innerH - reserve)
				else
					innerW = math.max(0, innerW - reserve)
				end
				spentReserve = reserve
				pushContainer(ctx, innerW, innerH)
				childSizes, contentW, contentH = measureAll(innerW, innerH)
			end
		end
		-- the gaps are already folded into contentW/contentH by measureAll: the
		-- flow cursor advances by gap between children, so the extent must include
		-- them or the native canvas under-covers and the last row's tail is
		-- unreachable (migration-agent finding 2026-07-23, native substrate)
		--
		-- THE CROSS AXIS IS CLAMPED TO THE WINDOW (director live report,
		-- 2026-08-09): this is a SINGLE-axis scroller, so content on the other
		-- axis is unreachable by construction — but a nested cross-axis
		-- carousel MEASURES at its content width (fill measures as content),
		-- and publishing that measure as the canvas made the engine draw a
		-- horizontal scrollbar on a Y scroller, straight through the tab dock
		-- beneath it. The canvas the adapter is given must never exceed the
		-- window on an axis nobody can scroll.
		if isX then
			contentH = math.min(contentH, innerH)
		else
			contentW = math.min(contentW, innerW)
		end

		--[[ THE LEADING EDGE'S OWN CHROME BLEED, SPENT FLOOR-AWARE, AFTER THIS
			NODE'S OWN CHILDREN ARE ALREADY MEASURED (task SHOWCASE3; supersedes
			`9eb095a`, reverted). The cross axis above already reserves
			`chromeBleed` unconditionally, folded into `node.padding` BEFORE any
			of this node's children were measured — safe there because nothing
			has yet measured it collapsing a real box. The leading edge (top for
			a y-axis scroller, left for an x-axis one) is different for the
			reason `layout_node.luau`'s own comment gives: there is no canvas
			before scroll position 0 to grow into, so the only way to show a
			first child's own glow is real padding, and real padding taken from
			a box that cannot afford it is a blank scroller. `rect.h`/`rect.w`
			is the box this node ACTUALLY resolved to — the fact the pre-solve
			conversion never has — so the same all-or-nothing floor a themed
			control's own contentInsets already spend against applies here too:
			afford it only if the box survives.

			SPENT HERE, AFTER `measureAll`, AND THAT IS LOAD-BEARING. Folding it
			into `pl`/`pt` before `pushContainer`/`measureAll` ran shrank
			`ctx.containerW` for THIS node's own children during their own
			measurement — a live fact every descendant already answers against
			— and measured to tip an already-marginal `tab_view` strip into a
			text wrap it did not have, at `desktop-studio-1320` under Sci-Fi HUD
			(a NEW "content overflows this vstack" finding, not the collapse
			`9eb095a` is named for). Every child above is already measured and
			arranged against the UNBLED box; this only moves the CURSOR's start
			and `padding` (below) — NOT `contentSize`, which stays the pure
			content sum `measureAll` already reports (the adapter is the one
			that adds padding to it for the canvas it builds, exactly as it
			already does for the cross-axis reservation folded into `pl`/`pr`
			above) — the same non-interference the trailing edge's own canvas
			allowance (`render/commit_walks.luau`) already keeps. ]]
		local leadingSpend = 0
		if type(node.leadingBleed) == "number" and node.leadingBleed > 0 then
			local extent = if isX then rect.w else rect.h
			local authored = if isX then pl + pr else pt + pb
			leadingSpend = chrome_slots.spendInset(extent, authored, node.leadingBleed)
		end
		out[node.id].contentSize = { w = contentW, h = contentH }
		-- ...and the padding this solve actually SPENT, published so the canvas the
		-- adapter is given is built from the same number the content was measured
		-- inside. The renderer used to re-derive it from the authored prop, which
		-- silently drops whatever a theme's `scrollbar` slot reserved (2026-07-27).
		out[node.id].padding = {
			top = pt + (if not isX then leadingSpend else 0),
			right = pr,
			bottom = pb,
			left = pl + (if isX then leadingSpend else 0),
		}
		--[[ ...AND THE BAR GUTTER THIS HOST ACTUALLY SPENT (director report
			2026-08-14: "the scroll bar always overlaps content", and its follow-up
			"it should apply to both horizontal and vertical ones").

			The reservation above narrows the host's CONTENT BOX, so everything
			inside it stops short of the bar — correct, and invisible to anything
			outside the subtree. A node that has to line up ACROSS that boundary is
			the case it cannot serve: a Table's header is a SIBLING of its scrolling
			body, so the body's columns resolved against `innerW` while the header's
			resolved against the full frame, and every column edge drifted by the
			reserve (worsening left to right, because a `fill` column's share of the
			difference accumulates). Measured live at `table-columns`: body window
			875 against a header laid out to 883, the trailing column 8px under the
			bar.

			So the number is PUBLISHED rather than left implicit, keyed by the side
			it was taken from — `right` for a Y scroller, `bottom` for an X one, so
			a consumer pays it on the correct edge instead of assuming width. Nil
			when nothing was reserved (a host whose content fits shows no bar and
			must not be paid for), which is exactly the conditionality a sibling
			cannot re-derive for itself.

			READ BY: `renderer.controller.scrollBarInsetOf` -> `newTable`'s header
			padding. A fixed box cannot hold a theme's frame, and the general rule
			this is the far end of is: reserving room is only half
			of it, something has to SPEND the reservation — and here the node that
			must spend it lives outside the subtree that made it. ]]
		out[node.id].barInset = if spentReserve > 0
			then { right = if isX then 0 else spentReserve, bottom = if isX then spentReserve else 0 }
			else nil
		out[node.id].overflow = if (axis == "y" and contentH > innerH) or (axis == "x" and contentW > innerW)
			then "scroll"
			else node.overflow
		-- the flow cursor advances along the SCROLL axis; `leadingSpend` (above)
		-- starts it `bleed` further in on the leading edge only — the trailing
		-- edge needs no such nudge, its own canvas allowance already covers it
		local cursor = (if isX then innerX else innerY) + leadingSpend
		for i, child in node.children or {} do
			local size = childSizes[i]
			-- cross-axis fill children stretch to the scroll viewport
			local w = if isX then size.w else math.min(size.w, innerW)
			if not isX and dim(child, "w").type == "fill" then
				w = innerW
			end
			local h = if isX then math.min(size.h, innerH) else size.h
			if isX and dim(child, "h").type == "fill" then
				h = innerH
			end
			-- offsetX/offsetY are arrange-time adjustments (scroll offsetting +
			-- row culling park, Phase 4 touch-scroll design); the flow cursor is
			-- unaffected so siblings keep their slots
			local childRect: Rect = if isX
				then { x = cursor + offsetPx(child.offsetX, innerW), y = innerY, w = w, h = h }
				else { x = innerX, y = cursor + offsetPx(child.offsetY, innerH), w = w, h = h }
			arrange(ctx, child, childRect, out)
			cursor += (if isX then size.w else size.h) + gap
		end
		restoreScope(ctx, restoreW, restoreH, restoreKey)
		return
	end

	if node.kind == "fits" then
		local children = node.children or {}
		local idx = candidate.choose(CANDIDATE_DEPS, ctx, node, innerW, innerH)
		for i, child in children do
			if i == idx then
				local w, h = measure(ctx, child, innerW, innerH)
				local wDim, hDim = dim(child, "w"), dim(child, "h")
				arrange(ctx, child, {
					x = innerX,
					y = innerY,
					w = if wDim.type == "fill" then innerW else w,
					h = if hDim.type == "fill" then innerH else h,
				}, out)
			else
				-- an unchosen candidate keeps its MOUNT (a resize must not rebuild
				-- it) but gets a zero rect and is marked hidden, which is what
				-- removes its focusables from focus order.
				setHidden(ctx, ctx.hiddenDepth + 1)
				arrange(ctx, child, { x = innerX, y = innerY, w = 0, h = 0 }, out)
				setHidden(ctx, ctx.hiddenDepth - 1)
				out[child.id].hidden = true
			end
		end
		return
	end

	if node.kind == "composition" then
		--[[ THE ORIGIN IS WHAT MAKES A WINDOW-SPACE RECT MEAN SOMETHING HERE (§9/§8).
			`arrange` is the one pass that knows where this composition actually is, so
			it is the one that can convert an exclusion rect or the platform band into
			the composition's own box. `measure` has no position and passes none — it
			falls back to the surface's content origin, which is exact for the
			full-bleed case every band-riding surface is and conservative otherwise
			(see the module's own note). ]]
		local resolution = compositionResolve.resolve(COMPOSITION_DEPS, ctx, node, innerW, innerH, innerX, innerY)
		if resolution == nil then
			return
		end
		-- THE DECISION IS PUBLISHED, not inferred from the rects. "Which
		-- arrangement, which form per region, and why every richer candidate lost"
		-- is what makes an adaptive screen debuggable at all: without it the only
		-- evidence is a screenshot, and a screenshot cannot tell you that the
		-- three-lane candidate lost on the field lane's minimum width by 6 px.
		out[node.id].composition = compositionLib.dump(resolution)
		--[[ THE ONE FINDING THAT REPORTS THE SYSTEM WORKING (ruling 8, 2026-08-14).

			Every other sentence this solver files describes something the author did
			not intend and would fix: content painting outside its box, a child over
			its neighbour, a row taller than the slot it was windowed into. This one
			describes the author's own instruction being followed — arrangements are
			declared richest-first, the last is the fallback, and when nothing else
			is legal the fallback is what shows. Nothing is clipped and nothing is
			lost; the composition is saying out loud which rung it landed on.

			`designed = true` is how a reader tells the two apart WITHOUT recognising
			this sentence. Both sides of the consumer lockstep used to do exactly
			that and disagreed about the answer: Facet's sweep carried it as a
			waiver with a px ceiling ("a defect we tolerate"), Rascal Rally excluded
			it by substring ("not a defect"). One field, set in one place, ends that
			— and a new designed-by-contract report is covered the day it is written
			rather than the day somebody remembers to add its wording to two lists.

			IT IS STILL REPORTED. A surface that reaches its fallback at a size its
			author expected to be legal is worth knowing about; it is simply not a
			bug. `docs/reference/api.md` § "Findings that are not defects". ]]
		if resolution.fallback and ctx.hiddenDepth == 0 then
			local why = resolution.rejected[#resolution.rejected]
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"no declared arrangement is legal in %dx%d — showing '%s' as the declared fallback%s",
					roundPx(innerW),
					roundPx(innerH),
					resolution.arrangement,
					if why ~= nil then ` (last rejection: {why.rule} — {why.detail})` else ""
				),
				designed = true,
			})
		end
		--[[ ...AND THE ONE BESIDE IT THAT IS NOT DESIGNED AT ALL.

			A composition's regions PARTITION its box — lanes sit side by side, a lane
			stacks its groups down — so two of them cannot overlap as boxes. What the
			partition cannot stop is a region whose chosen form measures bigger than
			the box it was allotted: nothing clips it, so it paints over whatever is
			next to it, and the composition stays perfectly LEGAL while it happens.
			The fallback finding above never fires and the inner stack's own overflow
			sentence says the content is too big for its box without ever saying whose
			screen it landed on.

			This is the commissioning screenshot's second failure ("the weapon rail
			runs into the fps/ping readout"), and it is filed on the region that is
			doing the painting, so the sweep's per-node waivers can tell two colliding
			pairs apart. The pure module decides it — `resolve` returns the pairs —
			for the same reason it decides everything else: a device matrix is then a
			headless sweep rather than a screenshot review. ]]
		if ctx.hiddenDepth == 0 then
			for _, c in resolution.collisions or {} do
				table.insert(ctx.diagnostics, {
					node = c.a,
					issue = string.format(
						"region '%s' paints over region '%s' by %dx%dpx — a composition's regions partition "
							.. "its box, so a region drawing outside its own is drawing on top of its "
							.. "neighbour (give it a form that fits, let it shrink, or let it drop)",
						c.a,
						c.b,
						c.dx,
						c.dy
					),
				})
			end
		end
		local originX = innerX + resolution.origin.x
		local originY = innerY + resolution.origin.y
		for _, child in node.children or {} do
			local placed = resolution.regionById[child.id]
			if placed ~= nil and placed.mounted and placed.rect ~= nil then
				ctx.regionForm[child.id] = placed.form
				-- wave REVEAL: the composition decided whether this region is showing
				-- less than it has; the region branch below spends that as geometry
				ctx.regionExpandable[child.id] = placed.expandable == true
				arrange(ctx, child, {
					x = originX + placed.rect.x,
					y = originY + placed.rect.y,
					w = placed.rect.w,
					h = placed.rect.h,
				}, out)
			else
				-- dropped, or its content resolved to nothing: it keeps its MOUNT
				-- (an offer change must not rebuild it) and gets a zero rect plus the
				-- hidden mark, which is what takes its focusables out of the ring —
				-- the same bargain a losing ViewThatFits candidate makes.
				ctx.regionForm[child.id] = 0
				ctx.regionExpandable[child.id] = false
				setHidden(ctx, ctx.hiddenDepth + 1)
				arrange(ctx, child, { x = originX, y = originY, w = 0, h = 0 }, out)
				setHidden(ctx, ctx.hiddenDepth - 1)
				out[child.id].hidden = true
			end
		end
		return
	end

	if node.kind == "region" then
		local chosen = ctx.regionForm[node.id]
		if chosen == nil then
			if ctx.hiddenDepth == 0 then
				table.insert(ctx.diagnostics, {
					node = node.id,
					issue = "UI.Region only means something as a direct child of a UI.Composition — "
						.. "outside one nothing ranks it, so its richest form is shown unconditionally",
				})
			end
			chosen = 1
		end
		--[[ ── THE EXPAND AFFORDANCE (wave REVEAL) ──────────────────────────────
			The last child, when it declares `expandTarget`, is the ONE button
			`UI.Region` synthesized for a collapsing region. It is not a form and the
			ladder above never chose it; it is placed here, from the region's own box,
			and only while the composition says a reduced form is standing with
			something left to disclose.

			EVERYTHING ELSE ABOUT IT IS THE MACHINERY THAT WAS ALREADY THERE. Hidden,
			it takes a zero rect and the hidden mark — which is what removes it from
			focus order and from hit routing, exactly as a losing form does. Standing,
			it is an ordinary Button: the 44px target floor, the hit expander, the
			focus stop, the activation dispatch. Nothing in this branch knows what a
			plate is.

			  "cover"    the region's whole box. The compact form carries no focus stop
			             and no semantic action, so covering it takes nothing away and
			             gives the player the target the director's constraint asks for:
			             the WHOLE compact form.
			  "chevron"  the trailing edge, vertically centred, with the form arranged
			             in what is left. The reserve is the same measure the ladder was
			             given (see `./composition_resolve`), so the form was CHOSEN
			             against the width it is now being handed. ]]
		local kids = node.children or {}
		local mark = if #kids > 0 and kids[#kids].expandTarget ~= nil then kids[#kids] else nil
		local markW, markH = 0, 0
		local markStanding = false
		if mark ~= nil then
			markStanding = ctx.regionExpandable[node.id] == true and ctx.hiddenDepth == 0
			if markStanding and mark.expandTarget.role == "chevron" then
				markW, markH = measure(ctx, mark, innerW, innerH)
			end
		end
		local formW = math.max(0, innerW - markW)
		for i, child in kids do
			if child == mark then
				if markStanding then
					local rect = if mark.expandTarget.role == "cover"
						then { x = innerX, y = innerY, w = innerW, h = innerH }
						else {
							x = innerX + innerW - markW,
							y = innerY + math.max(0, (innerH - markH) / 2),
							w = markW,
							h = math.min(markH, innerH),
						}
					arrange(ctx, child, rect, out)
				else
					setHidden(ctx, ctx.hiddenDepth + 1)
					arrange(ctx, child, { x = innerX, y = innerY, w = 0, h = 0 }, out)
					setHidden(ctx, ctx.hiddenDepth - 1)
					out[child.id].hidden = true
				end
			elseif i == chosen then
				-- the chosen form gets the region's box, and spends it exactly the
				-- way a chosen ViewThatFits candidate spends its container's: a
				-- `fill` axis takes the whole box, anything else takes its own
				-- measure clamped to it. A region is an ALLOTMENT, not a stretch.
				local w, h = measure(ctx, child, formW, innerH)
				local wDim, hDim = dim(child, "w"), dim(child, "h")
				arrange(ctx, child, {
					x = innerX,
					y = innerY,
					w = if wDim.type == "fill" then formW else math.min(w, formW),
					h = if hDim.type == "fill" then innerH else math.min(h, innerH),
				}, out)
			else
				setHidden(ctx, ctx.hiddenDepth + 1)
				arrange(ctx, child, { x = innerX, y = innerY, w = 0, h = 0 }, out)
				setHidden(ctx, ctx.hiddenDepth - 1)
				out[child.id].hidden = true
			end
		end
		return
	end

	if node.kind == "zstack" then
		-- THE DECLARED SLOT, hoisted: one field read per ZStack, and `nil` on every
		-- ZStack in the framework except the rows of a fixed-pitch windowing list.
		-- Everything it costs is inside the `slot ~= nil` branch below.
		local slot = node.virtualSlot
		for childIndex, child in node.children or {} do
			-- hoisted above the diagnostic: a FILL axis is granted exactly the
			-- stack's box at arrange (below), so its measure is not its size
			local childFillW = dim(child, "w").type == "fill"
			local childFillH = dim(child, "h").type == "fill"
			--[[ ── A LAYERED CHILD BIGGER THAN ITS BOX (2026-08-02) ─────────────────
				The flow-stack diagnostic above cannot see this one: a ZStack has no
				main axis to overflow, so a child measured taller or wider than the box
				simply paints outside it — "nothing clips a ZStack", as the margin note
				below says. Found live THREE times now, twice fixed as one-off arrange
				bugs and once as a caption a chip painted straight through (a coin pill
				in a 34 px box was 58 px tall and covered its own label). Each time the
				solver already KNEW the number and never said it.

				Reported, never fatal: an honestly cramped offer produces the same
				measure, and stopping a screen to report an authoring mistake is the
				worse trade. `intentionalOverlap` is the opt-out for the layouts whose
				whole job is to stack over one another.

				PER-AXIS, AND ONLY THE AXES THE CHILD SIZES ITSELF ON (2026-08-08,
				reference-app matrix): a `fill` axis resolves at arrange to exactly
				`availW`/`availH` — the child CANNOT paint outside a box it is granted
				— but `measure` answers `fill` with content, so comparing the measure
				here reported a fill-width page scroller as "overflowing" by its own
				content height (plus the bar reserve its measure honestly includes) on
				every screen. Three reference proofs carried `overflow = "clip"` purely
				to silence that false positive; the axis gate is what makes this
				diagnostic trustworthy as an OVERLAP signal across the device matrix. ]]
			if ctx.hiddenDepth == 0 and node.overflow ~= "intentionalOverlap" and node.overflow ~= "clip" then
				local cw, ch = measure(ctx, child, innerW, innerH)
				local overW = if childFillW then 0 else roundPx(cw - innerW)
				local overH = if childFillH then 0 else roundPx(ch - innerH)
				--[[ ── THE LYING `itemExtent` (2026-08-13, game-director approved) ───────
					A fixed-pitch list windows by `index × itemExtent`. That arithmetic is
					O(1) and exact ONLY because the extent is one declared number — and the
					consumer, not the control, is the one who has to predict it, for every
					live fact its own row reads. Nothing checked the prediction.

					THE CASE STUDY is the perf lab's `rows.heightFor`, whose comments record
					it learning each input only after that input broke something: the viewport
					width, then the type scale (+3px on the ten-foot row), then the theme
					insets (+19px under fantasy-ornate), and never the accessibility text
					preference — at `preferredTextOffset` 4/10/14 every row overflowed its
					56px slot by 11/39/59px on a real device. The class is a px height
					fixed against unfixed content.

					IT IS NOT KNOWABLE AT CONSTRUCTION, which is why it is filed here and not
					refused by `virtual_list.luau`'s spec guard: the row's true extent is a
					function of the viewport, the typography scale, the theme metrics and the
					text preference, and the first two of those are not decided until a solve.
					The channel is enforced — `tests/overflow_sweep.spec.luau` fails the suite
					on solver findings and the perf lab refuses to mount with one.

					THREE THINGS MAKE IT DIFFERENT FROM THE OVERLAP FINDING ABOVE:
					  · it compares against the DECLARED extent (`slot.extent`), not this
					    row's box, so a row-actions commit collapse — which drives the box
					    down its own height ladder on purpose — cannot make it shout;
					  · it does NOT excuse a `fill` axis. A slot is a declared px cap, never
					    a grant, so `height = fill` on a cell is a statement about paint and
					    not about fit; only a child that scrolls or clips absorbs its own
					    overflow (`absorbsOverflow`);
					  · it names BOTH NUMBERS. "You declared 56, this row measures 74" is the
					    whole value; the overlap finding's advice ("a `minMax` FLOOR rather
					    than a fixed CAP") is exactly the wrong repair for a windowed row,
					    whose extent has to stay one number.
					Only content TALLER than its slot is the defect — over-reserving is the
					correct direction and stays silent. Cost off this path is one `nil` field
					test per ZStack; on it, no measure this block was not already taking. ]]
				if slot ~= nil and childIndex >= (slot.contentFrom or 1) then
					local axisIsX = slot.axis == "x"
					local measured = if axisIsX then cw else ch
					-- the same round-to-nearest the overlap finding uses: a slot is
					-- authored in whole px and sub-pixel measure noise is not a defect
					local over = roundPx(measured - slot.extent)
					if over > 0 and not absorbsOverflow(child, axisIsX) then
						table.insert(ctx.diagnostics, {
							node = child.id,
							--[[ THE FILER, NOT THE NAMED NODE (2026-08-15; the same defect
								`inertPlacement` was stamped for — RED-TEAM Milestone 1 HIGH 2,
								whose rule is written out at the replay loop in `solve`).

								THIS FINDING IS FILED BY THE ZSTACK AND NAMES ITS CHILD, so the
								incremental replay gate — "was the node that FILES this finding
								skipped?" — was asking about the wrong node. Measured live on a
								`newVirtualList` whose extents re-derived correctly: the row was
								walked and filed nothing, its content child landed on the rect it
								already had and was skipped, and the replay copied the OLD
								"declares itemExtent = 40" forward on every solve FOREVER, while
								its siblings cleared. A stale finding in `controller.diagnostics()`
								is worse than none — the overflow sweep fails the suite on that
								channel, so it reports a defect that has already been fixed. ]]
							filedBy = node.id,
							issue = string.format(
								"newVirtualList '%s' declares itemExtent = %s, but this row's content measures "
									.. "%spx on the list's %s axis — %dpx %s than the slot it is windowed into, so it "
									.. "paints over the next row (`index x itemExtent` is exact only while the declared "
									.. "extent is the TRUE one). Recompute itemExtent from the facts this cell really "
									.. "reads — viewport, typographyScale, themeMetrics, preferredTextOffset — or "
									.. "shorten the cell; a slot a few px too TALL is the safe direction",
								slot.list,
								formatPx(slot.extent),
								formatPx(measured),
								if axisIsX then "x" else "y",
								over,
								if axisIsX then "wider" else "taller"
							),
						})
						-- the main axis has now been reported by name and by number; leave
						-- the overlap finding below the CROSS axis only, so a row that is
						-- ALSO too wide for its list still says so exactly once
						if axisIsX then
							overW = 0
						else
							overH = 0
						end
					end
				end
				if overW > 0 or overH > 0 then
					table.insert(ctx.diagnostics, {
						node = child.id,
						-- filed by the STACK, names the child — the same replay-gate stamp
						-- its sibling finding above carries, and for the same reason
						filedBy = node.id,
						issue = string.format(
							"this child overflows its %s by %dx%dpx and nothing clips a %s, so it paints "
								.. "over whatever sits beside it (give the box room — a `minMax` FLOOR "
								.. 'rather than a fixed CAP — or set overflow = "intentionalOverlap")',
							node.kind,
							math.max(overW, 0),
							math.max(overH, 0),
							node.kind
						),
					})
				end
			end
			local mt, mr, mb, ml = sides(child.margin)
			-- A MARGIN IS ROOM THE CHILD DOES NOT GET, and a `fill` child in a
			-- ZStack used to take the stack's WHOLE inner box and then be displaced
			-- by its own top/left margin — so it hung off the far edge by exactly
			-- that margin, silently, because nothing clips a ZStack. Same defect the
			-- `anchor` branch below already fixed for OFFSETS ("a fill child used to
			-- take the whole anchor box and then get displaced"), on the sibling
			-- nobody had reached for yet: found live 2026-07-31 when a HUD pose
			-- reserved a top band for its chip row and ran 56 px past the safe area
			-- on every phone. The measure pass has always counted margins here
			-- (`cw = max(cw, w + ml + mr)`), so this makes arrange agree with it.
			local availW = math.max(0, innerW - ml - mr)
			local availH = math.max(0, innerH - mt - mb)
			local w, h = measure(ctx, child, availW, availH)
			-- fill children stretch to the stack (overlay scrims/backdrops) MINUS
			-- their own margins, and then sit hard against the near margin: a filled
			-- axis has nothing left to align, so `alignH`/`alignV` are read only for
			-- the axes the child actually sizes itself on.
			local fillW = childFillW
			local fillH = childFillH
			if fillW then
				w = availW
			end
			if fillH then
				h = availH
			end
			--[[ ...AND SO DOES A HUGGING ONE — the alignment runs in `availW`/`availH`,
				the box the child was GIVEN, never `innerW`/`innerH`, the box it was
				denied (2026-08-15). The 2026-07-31 round above subtracted the margins
				from the offer and then aligned in the full box, which for `start` is
				the same answer (x = ml either way) and for the other two is not:
				`end` put the child's far edge ON the stack's inner edge, so a
				`margin.right` bought nothing and a `margin.left` shoved the child
				clean THROUGH that edge by its own width; `center` centred in the full
				box and then displaced by `ml`, so an asymmetric margin moved it by
				half the wrong amount.

				FOUND LIVE (director, Studio 2026-08-14): the Table's header sort mark
				is a hugging `alignH = "end"` glyph carrying the theme's own
				`controls.table.sortMarkMargin` reserve — "keeps the ▲/▼ clear" — and
				every package solved it flush against the column boundary, which under
				a nine-slice header plate is the plate's carved border. See the
				`layout: a HUGGING ZStack child pays for its own margin too` block in
				`tests/layout.spec.luau`: a far margin must buy something.

				Children may inherit the stack's default alignment (a cell that centers
				its content vertically without touching consumer nodes). ]]
			local x = innerX
				+ ml
				+ (if fillW then 0 else alignOffset(child.alignH or node.alignH or "start", availW, w))
			local y = innerY
				+ mt
				+ (if fillH then 0 else alignOffset(child.alignV or node.alignV or "start", availH, h))
			arrange(ctx, child, { x = x, y = y, w = w, h = h }, out)
		end
		return
	end

	if node.kind == "anchor" then
		for _, child in node.children or {} do
			local w, h = measure(ctx, child, innerW, innerH)
			local f = ANCHOR_FACTORS[child.anchor or "topLeft"]
			if f == nil then
				table.insert(ctx.diagnostics, { node = child.id, issue = `unknown anchor '{child.anchor}'` })
				f = ANCHOR_FACTORS.topLeft
			end
			-- fill children stretch to the anchor (content layers under overlays)
			-- MINUS THE ROOM THEIR OWN OFFSET COSTS THEM (director round 10, found
			-- live 2026-07-26). A `fill` child used to take the WHOLE anchor box and
			-- then get displaced by `offsetX`/`offsetY`, so it hung off the far edge
			-- by exactly the offset — silently, because nothing clips an anchor.
			-- The gallery's chrome column is this shape: `anchor = "topLeft"` +
			-- `height = fill` + `offsetY = <CoreGui topbar inset>`, so its bottom
			-- ran off the phone by the topbar's height and the last row of whatever
			-- it held was unreachable. Studio Neutral never showed it because its
			-- content stopped well short of the lost strip; a taller theme's did not.
			--
			-- How much to give back: the child sits at (inner - size) * f + offset.
			-- Staying inside the far edge needs `offset <= (inner - size) * (1 - f)`,
			-- and inside the near edge needs `(inner - size) * f + offset >= 0`. Solve
			-- for the size and the shrink is |offset| over the factor facing the way
			-- the offset pushes — so a centred child gives back TWICE its offset (it
			-- loses room at both ends) and an edge-anchored one gives back exactly it.
			--
			-- Pushing a child OUT past the very edge it is anchored to (right anchor,
			-- positive offsetX) is deliberate — an off-screen drawer, a peeking tab —
			-- and no width can bring it back, so that case is left alone.
			-- resolved ONCE, before either use: a fractional offset is a share of
			-- this anchor's inner box, and the fill give-back below and the placement
			-- itself have to spend the same number
			local ox = offsetPx(child.offsetX, innerW)
			local oy = offsetPx(child.offsetY, innerH)
			if dim(child, "w").type == "fill" then
				w = offsetFill(innerW, ox, f[1])
			end
			if dim(child, "h").type == "fill" then
				h = offsetFill(innerH, oy, f[2])
			end
			local x = innerX + roundPx((innerW - w) * f[1]) + ox
			local y = innerY + roundPx((innerH - h) * f[2]) + oy
			arrange(ctx, child, { x = x, y = y, w = w, h = h }, out)
		end
		return
	end

	-- ---- THE GRID'S TWO ARRANGE BRANCHES (§2.2, and the flow grid's two axes) --
	--
	-- Both are `src/layout/grid.luau`, the same module that MEASURED them: one owner
	-- for the lanes, the lines, the columns and every cell, so the two passes cannot
	-- disagree (the recurring defect class this file has fixed four times). The
	-- module speaks LANE/FLOW; binding those to x/y is its arrange half's job and
	-- happens nowhere else. `arrange` and `alignOffset` are passed rather than
	-- sitting in `GRID_DEPS` because both are declared below where that record is
	-- built — see it for why that distinction is not cosmetic.
	if node.kind == "gridrow" then
		gridLib.arrangeRow(GRID_DEPS, ctx, node, innerX, innerY, innerW, innerH, arrange, alignOffset, out)
		return
	end

	if node.kind == "grid" then
		gridLib.arrange(GRID_DEPS, ctx, node, innerX, innerY, innerW, innerH, gap, arrange, alignOffset, out)
		return
	end

	-- THE WRAPPING STACKS (round 3 item A). This is the flow-`grid` loop above with
	-- a RAGGED advance instead of `i += cols`: form a line, take its cross extent
	-- from its tallest item, place, advance — except that the partition is not
	-- re-derived here. It comes from `flow.plan`, which measure also called, so the
	-- two passes cannot disagree about where the lines break.
	if node.kind == "hwrap" or node.kind == "vwrap" then
		local isH = node.kind == "hwrap"
		local children = node.children or {}
		local innerMain = if isH then innerW else innerH
		local innerCross = if isH then innerH else innerW
		local plan = flowLib.plan(FLOW_DEPS, ctx, node, isH, innerMain, innerCross, gap)

		-- `stretch` IS REFUSED HERE, NOT REINTERPRETED. On a single-line stack the
		-- word has one meaning — "a child fills its line on the cross axis". On a
		-- wrapping one it could equally mean "the LINES grow to fill the container",
		-- and one word meaning two things is the exact ambiguity `lineAlign` was
		-- created to end (§2.1). A literal `align = "stretch"` is a construction
		-- error (`blueprint.luau`); this is the same rule for a value only a solve
		-- can see, because `align` is reactive.
		local blockAlign = node.align
		if blockAlign == "stretch" then
			if ctx.hiddenDepth == 0 then
				table.insert(ctx.diagnostics, {
					node = node.id,
					issue = string.format(
						'align = "stretch" has two readings on a wrapping %s — "each child fills its line" '
							.. 'and "the lines fill the container" — so it is refused and treated as "start". '
							.. 'Put `lineAlign = "stretch"` on the children that should fill their line',
						node.kind
					),
				})
			end
			blockAlign = nil
		end

		-- THE BLOCK OF LINES IS PLACED BY `align`, packed, exactly as the engine
		-- places it (probed 2026-08-13: Top 0, Center 160, Bottom 320 in a 400px box
		-- holding 80px of lines).
		local crossCursor = (if isH then innerY else innerX) + alignOffset(blockAlign, innerCross, plan.totalCross)
		if ctx.hiddenDepth == 0 and plan.totalCross > innerCross then
			-- THE DIRECTION A WRAPPING STACK RUNS OUT OF ROOM IS ITS CROSS AXIS, and
			-- before this nothing looked there: the main-axis diagnostic beside it
			-- cannot fire on a stack whose whole job is to never exceed its main axis.
			-- Same `hiddenDepth` gate and same reuse replay as that one.
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"the wrapped lines overflow this %s by %dpx on the cross axis; they will paint outside "
						.. "its box (wrap it in a ScrollView, or give it room)",
					node.kind,
					plan.totalCross - innerCross
				),
			})
		end

		local mainOrigin = if isH then innerX else innerY
		for _, line in plan.lines do
			local count = line.last - line.first + 1
			local slack = if innerMain == math.huge then 0 else math.max(0, innerMain - line.main)
			-- MAIN-AXIS DISTRIBUTION IS PER LINE (§2.6's `distributionOf`, unchanged).
			-- There is no `fill` conflict to report here the way the plain stack has
			-- one: a `fill` main child takes a whole line, which is the diagnostic
			-- filed below, so a line holding one has no leftover by construction.
			local lead, step = 0, 0
			local mode = node.distribute
			if mode ~= nil and mode ~= "start" then
				lead, step = distributionOf(mode, slack, count)
			end
			local cursor = mainOrigin + math.floor(lead)
			local gapsPlaced, gapExtraApplied = 0, 0
			for i = line.first, line.last do
				local child = children[i]
				local s = plan.sizes[i]
				local mainMargin = if isH then s.ml + s.mr else s.mt + s.mb
				local crossMargin = if isH then s.mt + s.mb else s.ml + s.mr
				-- AN ITEM WIDER THAN ITS LINE IS CLAMPED TO THE LINE, and said so. It
				-- already has a line to itself (the partition gives it one rather than
				-- dropping it); painting it at its full extent would put it outside a
				-- box that reports fitting, which is the "painted at a size nobody
				-- measured" family this repo keeps paying for.
				local natural = plan.mains[i]
				local boxMain = if innerMain == math.huge then natural else math.min(natural, innerMain)
				if ctx.hiddenDepth == 0 and boxMain < natural then
					table.insert(ctx.diagnostics, {
						node = node.id,
						issue = string.format(
							"'%s' is %dpx wider than this %s's line on the main axis and was CLAMPED to it — "
								.. "it is painting at a size it never asked for (give the container room, or let "
								.. "this child shrink)",
							child.id,
							natural - boxMain,
							node.kind
						),
					})
				end
				local mainSize = math.max(0, boxMain - mainMargin)
				if ctx.hiddenDepth == 0 and dim(child, if isH then "w" else "h").type == "fill" then
					table.insert(ctx.diagnostics, {
						node = node.id,
						issue = string.format(
							"'%s' declares `fill` on this %s's MAIN axis, so it takes a whole line to itself — a "
								.. "wrapping stack has no single leftover to share (drop the fill dimension, or "
								.. "drop `wrap`)",
							child.id,
							node.kind
						),
					})
				end
				local crossAvail = math.max(0, line.cross - crossMargin)
				-- the same ladder the plain stack's arrange uses, one line up from the
				-- container's word — which here is the BLOCK's word, exactly as Roblox's
				-- `ItemLineAlignment = Automatic` defers to the container's alignment
				local childAlign = child.lineAlign or child.align or blockAlign
				local crossDim = dim(child, if isH then "h" else "w")
				-- AN ASPECT CHILD KEEPS THE PAIR MEASURE RESOLVED, and that is a rule
				-- rather than an omission: the partition is a function of the measured
				-- MAIN extents, so re-deriving one here from a stretched cross extent
				-- would make arrange disagree with the lines measure already broke.
				-- `measureUncached`'s `pairedExtent` already resolves aspect-with-fill
				-- against the offer, so the pair this reads is a real one.
				local crossSize = if crossDim.type ~= "aspect"
						and (crossDim.type == "fill" or childAlign == "stretch")
					then crossAvail
					else math.min(if isH then s.h else s.w, crossAvail)
				local childRect: Rect
				if isH then
					childRect = {
						x = cursor + s.ml,
						y = crossCursor + s.mt + alignOffset(childAlign, crossAvail, crossSize),
						w = mainSize,
						h = crossSize,
					}
				else
					childRect = {
						x = crossCursor + s.ml + alignOffset(childAlign, crossAvail, crossSize),
						y = cursor + s.mt,
						w = crossSize,
						h = mainSize,
					}
				end
				cursor += mainMargin + mainSize + gap
				-- the same carried fraction as the plain stack's cursor: the k-th gap's
				-- extra is `floor(k x step)`, so the leftover lands as whole pixels
				if step > 0 and i < line.last then
					gapsPlaced += 1
					local extra = math.floor(gapsPlaced * step)
					cursor += extra - gapExtraApplied
					gapExtraApplied = extra
				end
				arrange(ctx, child, childRect, out)
			end
			crossCursor += line.cross + gap
		end
		return
	end

	-- vstack / hstack. Main axis, in order: fixed/content children keep their
	-- desired size unless they declared a `shrinkWeight` and the axis is SHORT (the
	-- shrink pass, §2.4); `fill` children then share any surplus by weight
	-- (largest-remainder rounding); and `distribute` spreads what fill did not take
	-- (§2.6). Cross axis honours `child.lineAlign`, else `child.align`, else this
	-- container's `align` (`stretch` fills the line).
	local isH = node.kind == "hstack"
	local children = node.children or {}
	local desired = {}
	local margins = {}
	local fillWeightSum = 0
	local fixedMain = 0
	local gaps = if #children > 1 then gap * (#children - 1) else 0
	-- A `hug` CHILD'S CEILING IS WHAT ITS SIBLINGS LEFT IT, not the whole stack
	-- (director round 11, reproduced 2026-07-27 against the showcase's own chrome
	-- column). Every child used to be measured against the stack's FULL inner
	-- extent, which is right for the dims that ignore the limit — `fixed`,
	-- `content`, `minMax` — and wrong for the one that clamps to it. The gallery's
	-- theme card is the case: a `hug` ScrollView sitting under a row of chips was
	-- handed the column's entire height as its cap, so it reported its full
	-- natural content height, the cursor placed it after the chips, and it ran off
	-- the bottom of the phone by exactly what the chips had already spent — while
	-- never discovering it should have been scrolling.
	--
	-- So `hug` children are measured in a SECOND pass, in document order, each
	-- against the room actually left. `fill` is deliberately not part of that sum
	-- yet: `hug` means "what I need", `fill` means "whatever is over", so hug
	-- resolves first and fill shares the remainder — which is the order the rest of
	-- this branch assumes. The full order is hug -> SHRINK (only if the axis came out
	-- short) -> fill -> distribute.
	local hugLater: { number } = {}
	for idx, child in children do
		local mt, mr, mb, ml = sides(child.margin)
		margins[idx] = { t = mt, r = mr, b = mb, l = ml }
		local mainDim = mainDimOf(child, isH)
		if mainDim.type == "hug" then
			table.insert(hugLater, idx)
			continue
		end
		local w, h = measure(ctx, child, innerW, innerH)
		desired[idx] = { w = w, h = h }
		if mainDim.type == "fill" then
			fillWeightSum += mainDim.weight or 1
		else
			fixedMain += (if isH then w + ml + mr else h + mt + mb)
		end
	end
	for _, idx in hugLater do
		local child = children[idx]
		local m = margins[idx]
		local ownMargin = if isH then m.l + m.r else m.t + m.b
		local left = math.max(0, (if isH then innerW else innerH) - fixedMain - gaps - ownMargin)
		local w, h = measure(ctx, child, if isH then left else innerW, if isH then innerH else left)
		desired[idx] = { w = w, h = h }
		fixedMain += (if isH then w + m.l + m.r else h + m.t + m.b)
	end
	local availMain = (if isH then innerW else innerH) - fixedMain - gaps
	-- THE SHRINK PASS (§2.4; the algorithm and its two rulings are documented in
	-- `src/layout/shrink.luau`). It runs ONLY on the overflow path and only over
	-- children that declared a `shrinkWeight`, so a stack that opted into nothing
	-- reaches the diagnostic below with `availMain` untouched — which is what makes
	-- "additive and inert" a fact rather than an intention.
	--
	-- IT ALLOCATES NOTHING UNTIL IT HAS SOMETHING TO SAY. `shrunk` starts as the
	-- shared frozen empty table and is only replaced by a real one on the deficit
	-- path: a per-stack table here would be an allocation on the arrange hot loop,
	-- which is a bench regression this branch has already paid for once.
	--
	-- ...AND OVERFLOW IS NOT RARE, which is why the membership test is hoisted in
	-- front of both tables (Milestone-1 review, C5). The comment above was true of
	-- the pass and false of its setup: on ANY `availMain < 0` this block used to
	-- allocate `shrunk` AND `basisMain` and walk every child, only for the pass
	-- to find zero members and return. The overflow diagnostic below exists because
	-- shipped screens reach this branch at rest, and before §2.4 that path allocated
	-- nothing at all. The scan itself is on the overflow path only — a fitting stack
	-- pays nothing for it — and it stops at the first member.
	local shrunk: { [number]: number } = shrinkLib.EMPTY
	local shrinkOrder: string? = nil
	local hasShrink = false
	if availMain < 0 then
		for _, child in children do
			-- the same `> 0` filter `shrinkLib.stack` applies: `shrinkWeight = 0` is the
			-- default AND a legal authored value meaning "never"
			if child.shrinkWeight ~= nil and child.shrinkWeight > 0 then
				hasShrink = true
				break
			end
		end
	end
	if hasShrink then
		local absorbed
		shrunk = {}
		-- the basis map the pass takes is the MAIN extent of what was measured above,
		-- built here rather than carried through the loops: a per-child main-extent
		-- table maintained unconditionally would be an allocation on the arrange hot
		-- path, and this one only exists once a deficit does
		local basisMain: { [number]: number } = {}
		for idx = 1, #children do
			local d = desired[idx]
			if d ~= nil then
				basisMain[idx] = if isH then d.w else d.h
			end
		end
		absorbed, shrinkOrder = shrinkLib.stack(SHRINK_DEPS, ctx, children, isH, basisMain, -availMain, shrunk)
		if absorbed > 0 then
			fixedMain -= absorbed
			availMain += absorbed
			-- RE-MEASURE AT THE REDUCED OFFER, in document order. Same reason the
			-- `fill` block below re-measures: the cross extent was measured against a
			-- width this child no longer has, so a squeezed label would keep the box
			-- of the wrap it is not going to get. Document order, never `pairs`, so
			-- the last-write-wins verdict channels (`compact`, `textFacts`) publish
			-- deterministically.
			for idx = 1, #children do
				local size = shrunk[idx]
				if size ~= nil then
					local w, h = measure(ctx, children[idx], if isH then size else innerW, if isH then innerH else size)
					desired[idx] = { w = w, h = h }
				end
			end
		end
	end
	-- OVERFLOW DIAGNOSTIC (preferred-text sweep, 2026-07-24). Content-sized
	-- children always keep their full desired extent and the flow cursor keeps
	-- advancing, so a stack whose content exceeds its own box silently paints
	-- past its parent and off the viewport — no clip, no compression, no scroll.
	-- Found live: on compact-phone-portrait the adaptive_controls Hud column ran
	-- 185px past its own box, drawing the action row INSIDE the media box and
	-- pushing the stat grid and tile row off an 800px screen — at rest, with the
	-- default text size. This does not change layout for a stack that declared no
	-- `shrinkWeight` (that would be a silent re-flow of shipped screens); it makes
	-- the condition detectable, which is the whole difference between a bug you can
	-- catch and one you cannot.
	--
	-- It fires on what is left AFTER the shrink pass, and when that pass tried and
	-- still could not fit the row it appends the priority order it worked through —
	-- because "everything is already at its floor" is a different repair from
	-- "nothing was allowed to shrink".
	--
	-- CLIP IS THE CASCADE'S FLOOR (director ruling 1, 2026-08-13). A stack that ran
	-- the degrade cascade (compact -> truncate, `shrinkFloorOf` above) and STILL
	-- cannot fit crops what is left at its own edge, so nothing ever paints outside
	-- its parent — the failure class this framework has now fixed five times. The
	-- crop is on the RECT, not on an engine `ClipsDescendants`: a cropped rect is
	-- what every headless sweep, dump and audit in this repo actually reads, and a
	-- clip host would have left them all reporting the same out-of-bounds geometry
	-- while hiding it from the only eyes that can see a device.
	--
	-- SCOPED TO THE CASCADE, deliberately. A stack that declared no `shrinkWeight`
	-- opted into nothing and is untouched — cropping every overflowing stack in the
	-- library would be the silent re-flow of shipped screens the diagnostic below
	-- has always refused to be.
	local clipMain = shrinkOrder ~= nil and availMain < 0
	if availMain < 0 and ctx.hiddenDepth == 0 then
		local issue = string.format(
			"content overflows this %s by %dpx on the main axis; it will paint outside its box "
				.. "(wrap it in a ScrollView, or give it room)",
			node.kind,
			-availMain
		)
		if shrinkOrder ~= nil then
			issue ..= string.format(
				" — every shrinkable child is already at its floor (layoutPriority order tried: %s), "
					.. "so the box CLIPPED the remaining %dpx",
				shrinkOrder,
				-availMain
			)
		end
		table.insert(ctx.diagnostics, { node = node.id, issue = issue })
	end
	local remaining = math.max(0, availMain)
	local fillPx: { [number]: number } = {}
	if fillWeightSum > 0 then
		local acc = 0
		local shares = {}
		for idx, child in children do
			local mainDim = mainDimOf(child, isH)
			if mainDim.type == "fill" then
				local exact = remaining * (mainDim.weight or 1) / fillWeightSum
				table.insert(shares, { i = idx, floor = math.floor(exact), rem = exact - math.floor(exact) })
				acc += math.floor(exact)
			end
		end
		table.sort(shares, function(a, b)
			return if a.rem ~= b.rem then a.rem > b.rem else a.i < b.i
		end)
		local leftover = remaining - acc
		for rank, share in shares do
			fillPx[share.i] = share.floor + (if rank <= leftover then 1 else 0)
		end
	end
	-- A FILL child's CROSS size was measured above against the whole inner extent,
	-- but the loop above just decided the much smaller main extent it actually
	-- gets. Re-measure it at that real size, or its box under-covers its own
	-- content: found live 2026-07-24, a fill column reported 39px of height while
	-- holding 77px of wrapped text, because it was measured at 400px wide and
	-- arranged at 196px. That gap is what the overflow diagnostic was reporting on
	-- the Hud column, and what left a scroll canvas unable to reach its own tail.
	if fillWeightSum > 0 then
		for idx, child in children do
			if mainDimOf(child, isH).type ~= "fill" then
				continue
			end
			local m = margins[idx]
			local mainMargin = if isH then m.l + m.r else m.t + m.b
			local actualMain = math.max(0, (fillPx[idx] or 0) - mainMargin)
			local w, h = measure(ctx, child, if isH then actualMain else innerW, if isH then innerH else actualMain)
			desired[idx] = { w = w, h = h }
		end
	end
	-- MAIN-AXIS DISTRIBUTION (§2.6). The cursor used to be hard-anchored here —
	-- `local cursor = if isH then innerX else innerY` — so SpaceBetween/Around/
	-- Evenly could only be faked with hand-placed `Spacer`s between children, which
	-- a `UI.ForEach` list cannot do at all (its `row` returns exactly ONE
	-- blueprint). A tab bar whose tab count varies was inexpressible.
	--
	-- IT ACTS ON WHAT `fill` DID NOT TAKE. `remaining` is the leftover after the
	-- fill block above, so when `fillWeightSum > 0` there is nothing left and a
	-- non-"start" `distribute` is an authoring conflict — named, not ignored.
	local childCount = #children
	local lead, step = 0, 0
	local mode = node.distribute
	if mode ~= nil and mode ~= "start" then
		if fillWeightSum > 0 then
			if ctx.hiddenDepth == 0 then
				table.insert(ctx.diagnostics, {
					node = node.id,
					issue = string.format(
						'distribute = "%s" has nothing to distribute on this %s: a `fill` child already takes '
							.. 'the whole leftover (drop the fill dimension, or leave distribute at "start")',
						mode,
						node.kind
					),
				})
			end
		else
			lead, step = distributionOf(mode, remaining, childCount)
		end
	end
	-- the fractional part of `lead`/`step` is carried, never dropped per gap: the
	-- k-th gap's extra is `floor(k x step)`, so the whole leftover lands as whole
	-- pixels and the arrangement stays symmetric instead of drifting left
	local cursor = (if isH then innerX else innerY) + math.floor(lead)
	local gapsPlaced, gapExtraApplied = 0, 0
	for idx, child in children do
		local m = margins[idx]
		local mainDim = mainDimOf(child, isH)
		local crossDim = dim(child, if isH then "h" else "w")
		local mainMargin = if isH then m.l + m.r else m.t + m.b
		local mainSize = if mainDim.type == "fill"
			then math.max(0, (fillPx[idx] or 0) - mainMargin)
			elseif shrunk[idx] ~= nil then shrunk[idx]
			else (if isH then desired[idx].w else desired[idx].h)
		-- clamp: margins taller/wider than the stack must not produce negative
		-- cross space (phase-4 layout fuzz, seed 2532671254)
		local crossAvail = math.max(0, (if isH then innerH else innerW) - (if isH then m.t + m.b else m.l + m.r))
		-- THE CROSS-AXIS ALIGNMENT LADDER, AND WHICH WORD DOES WHICH JOB.
		--
		-- `node.align` is CONTAINER-LEVEL (director review 2026-07-24). HStack/VStack
		-- have always accepted an `align` prop, but the solver only ever read
		-- `child.align` — so `UI.HStack({ align = "center" })` was ACCEPTED AND
		-- IGNORED, exactly what Milestone 0's strict authoring exists to prevent.
		-- There was no way to centre a row's children at all: every control row
		-- pinned its short children (a label, a value readout) to the TOP against its
		-- tall ones, which is why the Volume label and its "6" sat 13px above the
		-- midline of the -/+ buttons, and why the Brightness label and value sat
		-- above the slider track.
		--
		-- `child.align` — a stack child that is ITSELF a stack — is the historic
		-- per-child override, and it is where one word came to mean two things at
		-- once (§2.1): a nested `VStack{ align = "center" }` both centres its own
		-- children AND centres itself in this line. It still wins over the
		-- container's word, so nothing shipped moves.
		--
		-- `child.lineAlign` is the word for the SECOND job alone, and it outranks
		-- both. It is a shared BOX prop, so it is the only spelling that works on a
		-- LEAF — `align` is container-only and is refused on `UI.Text`/`Box`/
		-- `Spacer`/`Image`, which is why Facet had no leaf-level route to Roblox's
		-- `ItemLineAlignment` at all until this.
		local childAlign = child.lineAlign or child.align or node.align
		local crossSize = if crossDim.type == "fill" or childAlign == "stretch"
			then crossAvail
			else math.min(if isH then desired[idx].h else desired[idx].w, crossAvail)
		-- ASPECT against a FILL sibling (found live: a 16:9 media box resolved to
		-- ZERO height). `fill` has no measure-time size, so measure could only
		-- compute `0 / ratio`. Here both extents are finally known, so the aspect
		-- axis is derived from the other one — whichever of main/cross it lands on
		-- for this stack's orientation.
		local wDimC, hDimC = dim(child, "w"), dim(child, "h")
		if hDimC.type == "aspect" then
			local ratio = hDimC.ratio :: number
			if isH then -- width is the MAIN axis here
				crossSize = roundPx(mainSize / ratio)
			else
				mainSize = roundPx(crossSize / ratio)
			end
		elseif wDimC.type == "aspect" then
			local ratio = wDimC.ratio :: number
			if isH then
				mainSize = roundPx(crossSize * ratio)
			else
				crossSize = roundPx(mainSize * ratio)
			end
		end
		-- THE CROP (see `clipMain` above). The PAINTED extent stops at the box edge;
		-- the CURSOR still advances by the full one, because cropping is not
		-- re-flowing — pulling the later children back inside would move content the
		-- author placed, which is a different (and silent) change.
		local paintedMain = mainSize
		if clipMain then
			local start = cursor + (if isH then m.l else m.t)
			local edge = if isH then innerX + innerW else innerY + innerH
			paintedMain = math.clamp(edge - start, 0, mainSize)
		end
		local childRect: Rect
		if isH then
			local y = innerY + m.t + alignOffset(childAlign, crossAvail, crossSize)
			childRect = { x = cursor + m.l, y = y, w = paintedMain, h = crossSize }
			cursor += m.l + mainSize + m.r + gap
		else
			local x = innerX + m.l + alignOffset(childAlign, crossAvail, crossSize)
			childRect = { x = x, y = cursor + m.t, w = crossSize, h = paintedMain }
			cursor += m.t + mainSize + m.b + gap
		end
		if step > 0 and idx < childCount then
			gapsPlaced += 1
			local extra = math.floor(gapsPlaced * step)
			cursor += extra - gapExtraApplied
			gapExtraApplied = extra
		end
		noteContainment(ctx, node, child, childRect, innerX, innerY, innerW, innerH, not isH)
		arrange(ctx, child, childRect, out)
	end
end

export type SafeInsets = { top: number, bottom: number, left: number, right: number }

-- solve: entry point. rootPolicy resolves the content rect from the viewport
-- and safe insets (presenter-owned in production, design §8.1).
function solver.solve(
	root: Node,
	viewport: { w: number, h: number },
	opts: {
		safeInsets: SafeInsets?,
		rootPolicy: string?,
		scrollBarReserve: number?,
		metrics: any?,
		-- §9: the platform's free topbar strip in window space, and the window y the
		-- platform's whole top reservation ends at. Both `nil` off `bandSafeContent`.
		band: Rect?,
		bandFullTop: number?,
	}?
): {
	rects: { [string]: any },
	diagnostics: { { node: string, issue: string, designed: boolean? } },
	contentRect: Rect,
}
	local insets = (opts and opts.safeInsets) or { top = 0, bottom = 0, left = 0, right = 0 }
	local policy = (opts and opts.rootPolicy) or "coreSafeContent"
	-- Studio Neutral when the caller supplies none: a solve is never without a
	-- metric authority, and neutral reproduces the pre-theme literals.
	local metrics = (opts and opts.metrics) or themeSnapshot.neutral()
	local contentRect: Rect
	if policy == "edgeToEdge" then
		contentRect = { x = 0, y = 0, w = viewport.w, h = viewport.h }
	else
		-- clamp: insets larger than the viewport (1x1 Studio instrument trap,
		-- foldable posture change) must not go negative (phase-4 layout fuzz,
		-- seed 2384194589).
		--
		-- THE GUTTER FLOOR IS NOT HERE, and that is the audit's own split (§9): the
		-- floor belongs to the POLICY RESOLVER, which is the one place that turns
		-- platform FACTS into insets, and this function is a pure function of the
		-- insets it is handed. A caller that states its own safe insets — `dump`, a
		-- layout unit test, the fuzzer — gets exactly the box it asked for.
		contentRect = {
			x = insets.left,
			y = insets.top,
			w = math.max(0, viewport.w - insets.left - insets.right),
			h = math.max(0, viewport.h - insets.top - insets.bottom),
		}
	end
	local reserve = (opts and opts.scrollBarReserve) or 0
	local ctx: Ctx = {
		rootRect = contentRect,
		rootBand = if opts ~= nil then (opts :: any).band else nil,
		rootBandFullTop = if opts ~= nil then (opts :: any).bandFullTop else nil,
		diagnostics = {},
		textStates = {},
		compact = {},
		textFacts = {},
		compositions = {},
		regionForm = {},
		regionExpandable = {},
		hiddenDepth = 0,
		fitProbe = false,
		fitCuts = 0,
		-- THE OUTERMOST CONTAINER IS THE SURFACE ROOT (§2.5): the content rect, i.e.
		-- the viewport minus whatever safe insets this root policy honours. A tree
		-- with no ScrollView in it therefore still has a container, and it is the one
		-- an author means by "the screen".
		containerW = contentRect.w,
		containerH = contentRect.h,
		scopeKey = "0",
		hasContainerRelative = false,
		gridPlan = {},
		flowLines = {},
		gridRowPlan = {},
		-- per-solve measure memo (see `measure`). Weak keys are unnecessary: the
		-- whole ctx dies with the solve.
		measureCache = {},
		--[[ THE CROSS-SOLVE STORE (P1), and ONLY on a solve that can read it. A solve
			with no reuse set proves nothing clean, so it could only WRITE — and writing
			means arming the per-solve memo for every shape, which is precisely the
			economics L-6 and L-37 measured and scoped away from (`flat`, `zstack` and
			`wrap` ran +8 % to +20 % armed, against a 1.5 % control). Measured again here
			on the pre-fix probe: populating a full solve cost +31 % at M and +40 % at L
			for a store nothing in that solve could use.

			So a full solve is the pre-P1 solver EXACTLY — `nil` here, same arming, same
			counts — and the store is filled by the first incremental solve after it,
			which pays one uncached pass and hits from then on. The renderer clears the
			store on every non-reuse solve, so what that first pass fills is never a
			slate from before the structural change. ]]
		measures = if opts ~= nil and (opts :: any).reuse ~= nil then (opts :: any).measures else nil,
		arranged = 0,
		measured = 0,
		-- the O3 translate class: nodes re-based by an ancestor's delta
		translated = 0,
		translatedRoots = {},
		translatedPaths = {},
		translatedEntries = {},
		analyze = (opts and (opts :: any).analyzeBoundaries) == true,
		boundary = {},
		reuse = opts and (opts :: any).reuse,
		skipped = 0,
		walkedIds = {},
		rectInserts = 0,
		offers = {},
		-- per-node verdict: can this node's measured size depend on the offered
		-- HEIGHT? Computed once per node per solve, read on every measure of it.
		memoPlans = {},
		mdepth = 0,
		deepNesting = false,
		-- armed the first time a scroll node is measured; a tree without one never
		-- pays for the cache
		hasScroll = false,
		scrollBarReserve = if type(reserve) == "number" and reserve == reserve then math.max(0, reserve) else 0,
		-- resolved above, so the content rect and this record are one reading
		metrics = metrics,
	}
	-- MICROPROFILER PHASES (roadmap Step 9). The two passes are named separately
	-- because they answer different questions and regress for different reasons: a
	-- measure regression is text metrics / intrinsic sizing / candidate selection,
	-- an arrange regression is stack distribution and rect derivation. Averaged into
	-- one "solve" bar a capture cannot tell them apart. Both are ONE scope for the
	-- whole tree — never one per node (see src/core/profile.luau rule 1).
	local mw, mh
	profile.span("measure", function()
		mw, mh = measure(ctx, root, contentRect.w, contentRect.h)
	end)
	-- the root honors its own dims: fixed/content use the measured size
	-- (clamped to the content rect); fill stretches to the content rect
	local rootW = if dim(root, "w").type == "fill" then contentRect.w else math.min(mw, contentRect.w)
	local rootH = if dim(root, "h").type == "fill" then contentRect.h else math.min(mh, contentRect.h)
	--[[ THIS SOLVE WRITES INTO THE PREVIOUS SOLVE'S MAP (P2). Nothing is copied and
		nothing is snapshotted: `reuse` hands the map over, this solve overwrites what
		it walks, and the previous result then describes a state that never existed.
		Sound because `reuse` is given only when the tree's SHAPE did not move and the
		ids are mounted paths, one per node. A result that must outlive the next solve
		is solved WITHOUT `reuse` (`controller.analyzeBoundaries`), and a throw
		mid-solve now tears `lastResult`: atomicity went with the copy. ]]
	local out: { [string]: any } = if ctx.reuse ~= nil then ctx.reuse.previous.rects else {}
	profile.span("arrange", function()
		arrange(ctx, root, { x = contentRect.x, y = contentRect.y, w = rootW, h = rootH }, out)
	end)
	--[[ HOW MANY NODES THE SKIP COVERED, BY SUBTRACTION (P2). Every node is walked or
		under something skipped, so `arranged + skipped` is the node count (the probe
		reads it as exactly `layoutNodes`), and `reuse` means the shape has not moved —
		so the previous solve's total is this one's and the skip never counts itself.
		`work.skipped` still means NODES, as four `lastSkipped` cases assert exactly. ]]
	if ctx.reuse ~= nil then
		local pw = ctx.reuse.previous.work
		local total = if pw ~= nil then (pw.arranged or 0) + (pw.translated or 0) + (pw.skipped or 0) else 0
		ctx.skipped = math.max(0, total - ctx.arranged - ctx.translated)
	end
	-- A SKIPPED SUBTREE KEEPS ITS FINDINGS. It was not walked, so it filed nothing this
	-- solve; dropping them would silence `controller.diagnostics()` for exactly the
	-- parts of the screen that did not change, which is the instrument every layout
	-- defect in this repo was caught by.
	if ctx.reuse ~= nil and ctx.skipped > 0 then
		--[[ ONE COPY PER FINDING, AND IT TAKES BOTH REFUSALS BELOW. They answer the same
			question — "was this finding filed this solve?" — about the two passes.

			THE FILER, NOT THE NAMED NODE (RED-TEAM Milestone 1, HIGH 2): `inertPlacement`
			is filed by the parent about the child, so a walked parent beside a skipped
			child filed it fresh AND had it replayed. `filedBy` is stamped at build time
			by `solver.auditPlacement`.

			...AND `walkedIds` IS AN ARRANGE FACT, so it cannot answer for the four
			MEASURE-time filers (RED-TEAM 2026-09-02, HIGH 2). Measure has no skip: a
			subtree `arrange` skipped was still measured — freshly, or replayed from its
			cross-solve slate by the adopted-hit branch of `measure` — so its findings are
			already in the list above and the replay was a SECOND copy, once per frame,
			forever. Measured on a malformed subtree inside a skipped one: 605 findings at
			frame 600 against the full-solve oracle's 3.

			A FINDING IS `(node, issue)`. Two filings of that pair are the same finding
			whatever table they arrived in, which is what makes this cheap: identity
			cannot see the fresh re-file, and the list is empty on every well-formed
			tree, so the loop that builds the set is a loop over nothing. ]]
		local filedNow: { [string]: boolean } = {}
		for _, d in ctx.diagnostics do
			filedNow[`{d.node}\0{d.issue}`] = true
		end
		for _, d in ctx.reuse.previous.diagnostics or {} do
			if ctx.walkedIds[(d :: any).filedBy or d.node] ~= true and not filedNow[`{d.node}\0{d.issue}`] then
				table.insert(ctx.diagnostics, d)
			end
		end
	end
	return {
		rects = out,
		diagnostics = ctx.diagnostics,
		contentRect = contentRect,
		work = {
			arranged = ctx.arranged,
			measured = ctx.measured,
			rectInserts = ctx.rectInserts,
			skipped = ctx.skipped,
			-- the O3 translate class and its two flat arrays, in document order
			translated = ctx.translated,
			translatedRoots = ctx.translatedRoots,
			translatedPaths = ctx.translatedPaths,
			translatedEntries = ctx.translatedEntries,
			-- present only when asked for (Stage 1); an ordinary solve carries nothing
			boundary = if ctx.analyze then ctx.boundary else nil,
		},
	}
end

solver.sides = sides
-- THE LINE PARTITION, EXPORTED (round 3 item A). It is pure — `(mains, innerMain,
-- gap) -> lines`, reading no node and no ctx — so a fuzz can drive it with no tree
-- at all, which is half of why it was written this way. The other half is that
-- measure and arrange both go through it and therefore cannot disagree.

-- ---- THE STAGE 1 REPORT ------------------------------------------------------
--
-- MOVED to `src/layout/boundary_report.luau` on 2026-09-02 — the whole walk and
-- the reasoning that used to sit here, unabridged.
--
-- The short version of why it could leave: it reads no `ctx`, no mutable upvalue
-- and no helper of this file — `(root, result) -> a table of numbers`, three
-- fields deep — which is the one-way test every split in this library is decided
-- by, and it is not on any frame path. `tools/lune/verify/data/source-cap-ledger.md`'s
-- row for this file had a trigger that is a STATE ("take a seam FIRST"), and the
-- two seams it still named had both already been taken on 2026-08-22; this is the
-- one that replaced them.
--
-- Re-exported under its own name because that is what `render/renderer.luau`,
-- `examples/performance/lab` and every doc call it — including the error message,
-- which still blames the CALLER's line for a solve that did not ask for the
-- analysis.
solver.boundaryReport = boundaryReportLib.report

return solver
