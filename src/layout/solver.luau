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
-- docs/plans/swiftui-parity-round2.md §2.4/§2.6): children are measured, then a
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
--   text/font?, textSize = number | <typography role name>?, lineHeight?,
--   singleLine = boolean? (measure one line, clamp to the offer),
--   axis = "y"|"x"? (scroll), children = { Node }? }
-- Dim = { type = "fixed", px } | { type = "content" } | { type = "hug", min?, max? } |
--       { type = "fill", weight } | { type = "percent", fraction } |
--       { type = "minMax", min, preferred?, max } | { type = "aspect", ratio } |
--       { type = "containerRelative", fraction } |
--       { type = "containerRelative", count, span?, spacing? }
-- solve(root, viewport, opts) -> { rects, diagnostics, contentRect }
-- opts.metrics is the active ThemeSnapshot (ADR-0019 §2); omitted, the solve
-- runs on Studio Neutral, whose values are the framework's historic literals.

local text_metrics = require("./text_metrics")
local profile = require("../core/profile")
local themeSnapshot = require("../themes/snapshot")
-- the PURE declared-content composition decision (ADR-0023). The solver supplies
-- the measurements and consumes the rects; the ranking, the step-down/drop order
-- and the arrangement choice live there, where a headless sweep can drive them
-- with no tree at all.
local compositionLib = require("./composition")
-- the parent-side placement-prop audit (parity round 2 §2.1), re-exported below
-- as `solver.auditPlacement`. It reads no solve state, which is why it is the
-- one block of this file that could become a sibling module unchanged.
local placementAudit = require("./placement_audit")
-- the main-axis shrink pass and its degrade cascade (§2.4 + director ruling 1).
-- It takes `SHRINK_DEPS` below rather than closing over anything of this file's.
local shrinkLib = require("./shrink")
-- UI.Grid's WHOLE arithmetic — both layouts (the flow grid in either flow
-- direction, and the `GridRow` column grid) and both passes. Same discipline as
-- `shrink`: it takes `GRID_DEPS` below, plus the two helpers declared too far down
-- this file to sit in a load-time record, and holds no state of its own.
local gridLib = require("./grid")

export type Dim = {
	type: string,
	px: number?,
	weight: number?,
	fraction: number?,
	offset: number?, -- percent only: pixel adjustment before clamping
	min: number?,
	preferred: number?,
	max: number?,
	ratio: number?,
}
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
	-- ({ scale, offset } — ADR-0022 Decision 6, the marker-overlay shape). The
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
	-- ThemeSnapshot on this solve (ADR-0019 §2)
	textSize: (number | string)?,
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
	-- FULL-VALUE DISCLOSURE (blueprint `Text.disclose`, LTN-4). Carried, never
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
	-- (renderer-set from controls/contract minHitSize clamped up by the theme's
	-- targetSizes.minimum). Diagnostics only — the renderer still owns the hit
	-- expansion — and it is what makes "which nodes are interactive" a fact of the
	-- solve rather than something a pure audit has to guess from a rect.
	hitFloor: number?,
	axis: string?,
	-- the decoration slot whose `contentInsets` are part of this node's padding
	-- (renderer-set; RS-A16-D3). Diagnostics only — the solver spends the padding
	-- identically either way, and naming the source is what makes a collapsed
	-- content box actionable instead of mysterious.
	chromeSlot: string?,
	-- ...and the slot inset the renderer had to GIVE BACK because this node was
	-- too small to afford it (director report 2026-07-28). Diagnostics only, for
	-- the same reason: the geometry is already repaired by the time it gets here,
	-- and what this carries is the fact that it needed repairing. `x`/`y` are the
	-- px that went unspent on that axis; absent = that axis was afforded.
	chromeYield: { slot: string, x: number?, y: number? }?,
	-- DECLARED-CONTENT COMPOSITION (ADR-0023). `composition` marks a screen-level
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

local CONTENT: Dim = { type = "content" }

local function dim(node: Node, axis: string): Dim
	return (if axis == "w" then node.width else node.height) or CONTENT
end

-- Spacer's default (swiftui-parity-next investment 6): a bare Spacer takes the
-- leftover space along its STACK's main axis, exactly like SwiftUI's. Before
-- this, every use needed an explicit `{ type = "fill" }` on the right axis, and
-- writing it on the wrong axis produced a silent zero. An explicit dimension
-- still wins, and a Spacer outside a stack stays inert (a ZStack/Anchor has no
-- main axis to expand along).
local SPACER_FILL: Dim = { type = "fill", weight = 1 }

local function mainDimOf(child: Node, isH: boolean): Dim
	local explicit = if isH then child.width else child.height
	if explicit ~= nil then
		return explicit
	end
	if child.kind == "spacer" then
		return SPACER_FILL
	end
	return CONTENT
end

-- exported below as solver.sides (renderer scroll-region canvas math must use
-- the SAME padding semantics the arrange pass uses — native-substrate NS-A2)
local function sides(margin: any): (number, number, number, number) -- t, r, b, l
	if margin == nil then
		return 0, 0, 0, 0
	end
	if type(margin) == "number" then
		return margin, margin, margin, margin
	end
	return margin.top or 0, margin.right or 0, margin.bottom or 0, margin.left or 0
end

type Ctx = {
	-- A FINDING'S `designed` FLAG (ruling 8) marks the ones that report the system
	-- working as declared rather than a defect. Absent on every other finding, so
	-- `d.designed == true` is the whole test; see the composition arrange branch
	-- for the one place that sets it and why the two kinds had to be separable.
	diagnostics: { { node: string, issue: string, designed: boolean? } },
	textStates: { [string]: string },
	-- nodes whose `compactText` won this solve. Recorded during measure and read
	-- out during arrange, so the verdict the box was reserved for is exactly the
	-- verdict the adapter paints (docs/lessons/one-word-two-subsystems.md).
	compact: { [string]: boolean },
	-- PER-TEXT-NODE MEASUREMENT FACTS (LTN-4), recorded on the same channel and
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
	-- the active ThemeSnapshot (ADR-0019 §2). The ONE place the measure path
	-- learns a typography role's size, font and line height, so a theme swap is
	-- a re-solve with new numbers rather than a rebuild.
	metrics: any,
	-- ADR-0023: one composition resolution per node per box, so measure and
	-- arrange can never disagree about which arrangement won — the same
	-- discipline `ctx.compact` carries for the compact-label verdict.
	compositions: { [string]: { key: string, resolution: any } },
	-- ...and the form index each region resolved to, read by the `region` arrange
	-- branch. 0 means "nothing shows" (dropped, or below its floor).
	regionForm: { [string]: number },
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
	heightFree: { [any]: boolean },
	offers: { [string]: number },
	-- HOW MUCH OF THE TREE THIS SOLVE TOUCHED. Published in the result so a test can
	-- ask "did changing one bound value re-lay-out the whole screen?" from the public
	-- surface, instead of a one-off probe that has to patch this file.
	arranged: number,
	measured: number,
	-- Stage-1 analysis only; nil on an ordinary solve
	analyze: boolean,
	boundary: { [string]: boolean },
	-- INCREMENTAL REUSE (Stage 2 v2). `previous` is the last solve's result and
	-- `dirtyContains` is every node that is dirty or contains a dirty node; a node
	-- absent from it cannot have changed, so its subtree may be replayed instead of
	-- walked. Both nil on an ordinary solve, which then behaves exactly as before.
	reuse: any,
	skipped: number,
	skippedIds: { [string]: boolean },
	-- true once a `scroll` node has been measured in this solve; gates the memo so a
	-- tree with no scroll region pays nothing for it
	hasScroll: boolean,
}

-- THE ONE RESOLUTION OF A TEXT NODE'S TYPOGRAPHY, so the two seams that need it
-- cannot drift. `measureUncached`'s text branch reads it to measure the string;
-- the shrink pass's floor (`textMinMain`) reads it to ask the SAME face and size
-- for the string's min-content width. A second copy of the role ladder here is
-- exactly how a floor ends up computed at `body` for a label drawn at `caption`.
--
-- Module-level, not a closure: this is on the per-text-node measure path, where a
-- per-call allocation is a bench regression this file has already paid for once.
local function textTypography(ctx: Ctx, node: Node): (string, number, number)
	-- typography comes from the active snapshot: `body` is the default role, and a
	-- string textSize NAMES a role (the renderer normally resolves it, but a direct
	-- solver caller may hand one straight in). The measured font is the role's
	-- canonical DESCRIPTOR ("family#weight#style", ADR-0019 §6), never a bare
	-- family: two weights of one family measure differently.
	local roles = ctx.metrics.type
	local role = if type(node.textSize) == "string" then roles[node.textSize] else nil
	local base = role or roles.body
	local size = if type(node.textSize) == "number"
		then node.textSize
		else (themeSnapshot.resolveSize(ctx.metrics, node.textSize) or base.size)
	return node.font or base.fontKey, size, node.lineHeight or base.lineHeight
end

--[[ THE TRUNCATION FACTS ARE PUBLISHED WHERE THE MEASURE HAPPENS (LTN-4).

	`Metrics` already answers "did this get cut" for the WRAPPED case
	(`naturalLines > lines`, which only a `lineLimit` can produce). It cannot
	answer it for the two CLAMPED cases, where the measure returns
	`min(measured, box)` and the engine's TextTruncate.AtEnd eats the difference:
	a single-line label narrower than its own string, and a compact form still
	wider than the box it won. Both are the shape a long display NAME arrives in,
	so a `truncated` derived from line counts alone would report "fits" on exactly
	the cases disclosure exists for — `clampedWidth` is the caller's verdict on the
	return it is about to make.

	Module-level, not a closure inside `measure`: this runs once per text node per
	measure pass, and a per-call closure allocation in this function is the shape
	of a bench regression this file has already paid for once (2026-07-25).
]]
local function recordTextFacts(
	ctx: Ctx,
	node: Node,
	m: any,
	clampedWidth: boolean,
	font: string,
	size: number,
	naturalWidth: number?,
	wraps: boolean?
)
	ctx.textStates[node.id] = m.state
	local truncated = m.truncated or clampedWidth
	local policy: string
	if not truncated then
		policy = if node.lineLimit ~= nil then "cap" else "wrap"
	else
		-- reveal outranks disclose in the POLICY string (the travel is the
		-- primary path; the plate stays its static alternative either way)
		policy = if node.reveal ~= nil
			then "truncate+reveal"
			elseif node.disclose == true then "truncate+disclose"
			else "truncate"
	end
	ctx.textFacts[node.id] = {
		-- the canonical descriptor and px size this measure actually used, so a
		-- reader never has to re-derive the role ladder to know what was measured
		font = font,
		size = size,
		lines = m.lines,
		naturalLines = m.naturalLines,
		truncated = truncated,
		lineLimit = node.lineLimit,
		disclose = node.disclose == true,
		reveal = node.reveal ~= nil,
		-- reveal nodes only: the one-line width the string WANTS at this size,
		-- from THIS measure pass — the travel distance's other half
		naturalWidth = naturalWidth,
		policy = policy,
		-- THE WRAP VERDICT (director ruling 5, 2026-08-13) — "was this box measured
		-- with wrapping ON". False for a single word (no legal break), for a
		-- compact form (one word by construction), and for a PHRASE whose longest
		-- word does not fit the drawable width, which is the ruling: wrapping into
		-- a column narrower than one of the phrase's own words does not wrap, it
		-- breaks the word. The paint seam writes `TextWrapped` from exactly this,
		-- because it sees the string but not the box (renderer `applyTextVerdicts`).
		wraps = wraps == true,
		-- the string this verdict is about: with a compact form in play it is NOT
		-- the string the node draws, and disclosure hands back the full value
		text = node.text,
	}
end

local measure -- forward
local measureUncached -- forward (the real body; `measure` is the per-solve memo in front of it)
-- forward: `ViewThatFits`'s fit probe (ruling 2) is read by the shrink pass and set
-- by `chosenCandidate`, which is defined before the scope-key writers it belongs with
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
-- the nil GLOBAL and die inside a protected boundary
-- (docs/lessons/a-helper-declared-below-its-caller-is-a-global.md). They are passed
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

-- resolve one axis of `node` given the limit and a content thunk
-- ---- RELAYOUT BOUNDARIES (incremental-layout Stage 1: DETECTION ONLY) -------
--
-- A node is a relayout BOUNDARY when its own size cannot change because something
-- inside it changed. That is the property incremental layout needs: when a leaf's
-- size changes, the effect propagates upward until it reaches a node that absorbs
-- it, and only that node's subtree has to be laid out again.
--
-- The predicate MIRRORS `resolveAxis` deliberately, case for case, because a
-- boundary rule that disagrees with the resolver is worse than none: it would
-- promise that a subtree is isolated when it is not.
--
--   fixed    a literal                                    -> absorbs
--   percent  reads the LIMIT, not the content...          -> absorbs IF bounded
--   fill     ...same                                      -> absorbs IF bounded
--   containerRelative  reads the CONTAINER, not either    -> absorbs
--   minMax   `preferred or contentFn()`                   -> absorbs IFF preferred
--   hug      content, capped at the offer                 -> does NOT absorb
--   content  the content                                  -> does NOT absorb
--   aspect   derived from the other axis                  -> defers to it
--
-- `percent` and `fill` fall back to content on an UNBOUNDED axis (inside a scroll's
-- scroll direction), and `resolveAxis` files a diagnostic when it does — so the
-- limit check here is the same condition, not an approximation of it.
--
-- Stage 1 computes this and NOTHING else: no behaviour changes, and the whole
-- analysis is gated behind an opt-in flag so an ordinary solve does not pay for it.
local function axisAbsorbs(d: Dim, limit: number, other: Dim, otherLimit: number): boolean
	local t = d.type
	if t == "fixed" then
		return true
	elseif t == "containerRelative" then
		-- reads the CONTAINER, never the content: nothing inside it can change its
		-- size, which is exactly what "absorbs" means here (§2.5)
		return true
	elseif t == "percent" or t == "fill" then
		return limit ~= math.huge
	elseif t == "minMax" then
		return d.preferred ~= nil
	elseif t == "aspect" then
		-- one level only: aspect-on-both-axes is already rewritten to content above
		local ot = other.type
		if ot == "fixed" then
			return true
		elseif ot == "percent" or ot == "fill" then
			return otherLimit ~= math.huge
		elseif ot == "minMax" then
			return other.preferred ~= nil
		end
		return false
	end
	return false
end

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
		return math.max(0, math.floor(page * span + spacing * (span - 1) + 0.5))
	end
	return math.max(0, math.floor(container * ((d :: any).fraction or 1) + 0.5))
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
		local raw = math.floor(limit * (d.fraction :: number) + (d.offset or 0) + 0.5)
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
		local base = math.clamp(contentFn(), d.min or 0, d.max or math.huge)
		return if limit == math.huge then base else math.min(base, limit)
	elseif d.type == "fill" then
		-- fill resolves at arrange; desired contribution is content
		return contentFn()
	end
	return contentFn()
end

--[[ ViewThatFits candidate choice (A-AL1). Pure and side-effect free apart from
	the measure cache, so measure and arrange always agree on the winner.

	A CANDIDATE IS JUDGED AT THE SIZE IT WOULD LIKE, NOT AT THE SIZE IT COULD BE
	SQUEEZED INTO (ruling 2, 2026-08-14, director: "follow swiftui's behavior").
	Apple's reference sentence for `ViewThatFits` is "it selects the first child
	whose IDEAL SIZE on the constrained axes fits within the proposed size", and an
	ideal size is what a view reports when nothing is proposed to it — so every
	mechanism that makes a view smaller than that ideal (truncation, `lineLimit`,
	`minimumScaleFactor`) is invisible to the choice. `shrinkWeight` is this
	framework's member of that family, and `ctx.fitProbe` is how it is made
	invisible: the flag suppresses the measure-side shrink for the duration of the
	probe, and nothing else.

	WHAT IT REPLACES: PASS 1.5 made a candidate REPORT its squeezed extent, so a
	candidate that could not fit "fit" and won. Swept 150-420px that flipped the
	winner at 10 of 28 widths (docs/lessons/a-candidate-is-judged-at-its-ideal-size.md,
	which carries the SwiftUI citations this was decided on).

	THE WINNER IS STILL SHRUNK — the flag is off again by the time the chosen
	candidate is measured and arranged, which is SwiftUI's other half: the winner
	receives its parent's real proposal. Picking is unshrunk; showing is not. ]]
local function chosenCandidate(ctx: Ctx, node: Node, availW: number, availH: number): number
	local children = node.children or {}
	if #children == 0 then
		return 0
	end
	local wasProbing = ctx.fitProbe
	setFitProbe(ctx, true)
	local chosen = #children -- the last candidate is the declared fallback
	for i = 1, #children - 1 do
		local w, h = measure(ctx, children[i], availW, availH)
		local fitsW = availW == math.huge or w <= availW
		local fitsH = availH == math.huge or h <= availH
		if fitsW and fitsH then
			chosen = i
			break
		end
	end
	setFitProbe(ctx, wasProbing)
	return chosen
end

-- THE COMPOSITION RESOLUTION, COMPUTED ONCE PER BOX (ADR-0023).
--
-- Measure and arrange both need it, and they must never get different answers —
-- reserving a box for `threeLane` and then arranging `column` inside it is the
-- exact measure-versus-paint disagreement this solver has had to fix four times
-- (ViewThatFits' candidate, the compact ladder, the uniform Grid cell, the
-- container offer). So it is cached on the CONTEXT, keyed by the box, and the
-- cache dies with the solve.
--
-- An UNBOUNDED axis (a composition inside a scrolling region) cannot adapt on
-- that axis — there is no offer to be short of. It is resolved twice: once
-- against a large finite box to learn the natural extent, then against that
-- extent, which is what `hug` means everywhere else in this file.
local COMPOSITION_UNBOUNDED = 1e6
local function compositionResolution(ctx: Ctx, node: Node, innerW: number, innerH: number): any?
	local declared = node.composition
	if declared == nil then
		return nil
	end
	local key = `{innerW}|{innerH}`
	local cached = ctx.compositions[node.id]
	if cached ~= nil and cached.key == key then
		return cached.resolution
	end

	local byId: { [string]: Node } = {}
	local regions = {}
	for _, child in node.children or {} do
		local r = child.region
		if r == nil then
			if ctx.hiddenDepth == 0 then
				table.insert(ctx.diagnostics, {
					node = child.id,
					issue = "every child of a Composition must be a UI.Region — this one is not, so it "
						.. "carries no rank, no forms and no floor, and the composition cannot place it",
				})
			end
			continue
		end
		byId[child.id] = child
		table.insert(regions, {
			id = child.id,
			group = r.group,
			rank = r.rank,
			forms = math.max(1, #(child.children or {})),
			sizing = r.sizing,
			weight = r.weight,
			floor = r.floor,
			mayScroll = r.mayScroll,
			mayDrop = r.mayDrop,
			reserved = r.reserved,
		})
	end

	--[[ A LIVE `eligible` is resolved HERE, once per solve, exactly as a live
		`reserved` reaches the region list above already resolved. The gate answers
		"is this candidate offered on THIS offer?", which is a per-solve question by
		construction — a size class changes when the window does. ]]
	local arrangements = declared.arrangements
	local anyLive = false
	for _, a in arrangements do
		if type(a) == "table" and type((a :: any).eligible) == "table" then
			anyLive = true
			break
		end
	end
	if anyLive then
		local resolved = {}
		for _, a in arrangements do
			local gate = if type(a) == "table" then (a :: any).eligible else nil
			if type(gate) == "table" and type((gate :: any).get) == "function" then
				local copy = table.clone(a :: any)
				copy.eligible = (gate :: any):get() == true
				table.insert(resolved, copy)
			else
				table.insert(resolved, a)
			end
		end
		arrangements = resolved
	end

	local decl = {
		id = node.id,
		groups = declared.groups,
		arrangements = arrangements,
		regions = regions,
		laneGap = declared.laneGap,
		groupGap = declared.groupGap,
		maxMeasure = declared.maxMeasure,
	}
	local resolveCtx = {
		measure = function(id: string, form: number, availW: number, availH: number): (number, number)
			local regionNode = byId[id]
			local forms = (if regionNode ~= nil then regionNode.children else nil) or {}
			local child = forms[math.min(form, #forms)]
			if child == nil then
				return 0, 0
			end
			return measure(ctx, child, availW, availH)
		end,
		floorOf = function(r: any): number?
			return compositionLib.floorPx(r.floor, ctx.metrics)
		end,
	}
	local offerW = if innerW == math.huge then COMPOSITION_UNBOUNDED else innerW
	local offerH = if innerH == math.huge then COMPOSITION_UNBOUNDED else innerH
	local resolution = compositionLib.resolve(decl, { w = offerW, h = offerH }, resolveCtx)
	if innerW == math.huge or innerH == math.huge then
		resolution = compositionLib.resolve(decl, {
			w = if innerW == math.huge then resolution.used.w else offerW,
			h = if innerH == math.huge then resolution.used.h else offerH,
		}, resolveCtx)
	end
	ctx.compositions[node.id] = { key = key, resolution = resolution }
	return resolution
end

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
	next edit there make one (docs/lessons/a-header-comment-describes-the-path-it-was-written-for.md).
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

--[[ ===== FLOW-WRAP (docs/plans/swiftui-parity-round3.md, item A) =============

	`UI.HStack{ wrap = true }` / `UI.VStack{ wrap = true }` reach this file as the
	kinds `hwrap` / `vwrap`: Roblox's `UIListLayout.Wraps`, which LuauUI had no
	spelling for at all. It is a NATIVE branch and deliberately not a public
	`Layout` protocol — the round-3 Phase 0 verdict, whose one carrying reason is
	that this file's three newest correctness mechanisms (the measure memo's cache
	key, the incremental-arrange reuse skip, the placement-prop audit) are each
	sound only as an ENUMERATION over a closed file, and consumer code inside the
	solve makes all three unenumerable at once.

	IT ADDS ONE PROP AND NO ALIGNMENT VOCABULARY, and that is a measurement rather
	than a preference. Probed live in Studio on 2026-08-13 (300x400 box, six 100x40
	items, so 80px of lines in 400px of container): wrapped lines are packed with
	NO extra space between them, and the whole BLOCK is placed on the cross axis by
	the container's existing alignment property — `Top` 0, `Center` 160, `Bottom`
	320, exactly. A ragged line put line 2 at y=90, its tallest item, not at 40. So

	    the block of lines  -> `align`      (Roblox VerticalAlignment/Horizontal…)
	    an item in its line -> `lineAlign`  (Roblox ItemLineAlignment)
	    along the main axis -> `distribute` (Roblox HorizontalFlex/VerticalFlex)

	map one-to-one onto words that already ship, and CSS's `align-content` (space
	between LINES) has no native counterpart to be parity with.

	ONE `gap`, BOTH AXES, for the same reason: `UIListLayout` has a single
	`Padding`, and a `rowGap` on `UI.HStack`/`UI.VStack` would be accepted and
	ignored on every stack that does not wrap — the §4 violation the placement
	audit exists to end. (`UI.Grid` has `rowGap` because its two pitches are
	genuinely different arithmetic; here they are the same number.)
]]

-- THE LINE PARTITION, AND IT IS A PURE FUNCTION ON PURPOSE.
--
-- `(childMainExtents, innerMain, gap) -> lines`, reading nothing else — no node,
-- no ctx, no clock. Two properties fall out of that and both are load-bearing:
-- measure and arrange cannot derive different partitions for the same numbers
-- (this library's four-times-fixed defect class, see `gridColumnPlan` in
-- `src/layout/grid.luau`), and the
-- partition is drivable by a headless fuzz with no tree at all
-- (`tests/flow_wrap.spec.luau`).
--
-- GREEDY, which is what the engine does and what CSS does: an item joins the
-- current line if it still fits with a gap in front of it, and starts a new one if
-- it does not. An item that fits on NO line still gets a line — of its own —
-- because the alternative is dropping it; `arrange` clamps it to the line and
-- files the diagnostic. An UNBOUNDED offer (`math.huge`, reachable from measure
-- and from a sideways scroller) yields exactly one line, which is the honest
-- answer: infinity cannot be wrapped.
local function flowPartition(
	mains: { number },
	innerMain: number,
	gap: number
): { { first: number, last: number, main: number, cross: number } }
	local lines: { { first: number, last: number, main: number, cross: number } } = {}
	local first, used = 1, 0
	for i = 1, #mains do
		local m = mains[i]
		if i == first then
			used = m
		elseif used + gap + m <= innerMain then
			used += gap + m
		else
			table.insert(lines, { first = first, last = i - 1, main = used, cross = 0 })
			first = i
			used = m
		end
	end
	if #mains > 0 then
		table.insert(lines, { first = first, last = #mains, main = used, cross = 0 })
	end
	return lines
end

-- ...AND THE PLAN THE TWO PASSES SHARE, cached on the context and keyed by the
-- box, exactly as `src/layout/grid.luau`'s `gridColumnPlan` is and for the
-- identical reason.
--
-- It owns the measurement as well as the partition: the child extents ARE the
-- partition's input, so deriving them in one pass and the lines in the other is
-- the disagreement this shape exists to make impossible. Every extent here
-- INCLUDES the child's margins, because a margin occupies line space.
local function flowPlan(ctx: Ctx, node: Node, isH: boolean, innerMain: number, innerCross: number, gap: number): any
	local key = `{innerMain}|{innerCross}|{gap}`
	local cached = ctx.flowLines[node.id]
	if cached ~= nil and cached.key == key then
		return cached.value
	end
	local children = node.children or {}
	local mains: { number } = {}
	local crosses: { number } = {}
	local sizes: { any } = {}
	for idx, child in children do
		local mt, mr, mb, ml = sides(child.margin)
		local w, h = measure(ctx, child, if isH then innerMain else innerCross, if isH then innerCross else innerMain)
		sizes[idx] = { w = w, h = h, mt = mt, mr = mr, mb = mb, ml = ml }
		-- A `fill` MAIN DIMENSION TAKES THE WHOLE LINE, and it has to be said here
		-- rather than left to `measure`. `resolveAxis` can only report CONTENT for a
		-- `fill` axis (the same fact the aspect-with-fill repair above `measure`
		-- documents), so a `fill`-width Box would enter the partition at ZERO and
		-- three of them would share one line at zero pixels each — a row of invisible
		-- children with nothing to say. "Fill" means "take the extent the parent
		-- offers", and on a wrapping stack the extent it offers IS the line, so it
		-- takes the line. `arrange` files the diagnostic that says so.
		local mainDim = dim(child, if isH then "w" else "h")
		local ownMain = if isH then w + ml + mr else h + mt + mb
		mains[idx] = if mainDim.type == "fill" and innerMain ~= math.huge then innerMain else ownMain
		crosses[idx] = if isH then h + mt + mb else w + ml + mr
	end
	local lines = flowPartition(mains, innerMain, gap)
	local totalCross, maxMain = 0, 0
	for li, line in lines do
		local lineCross = 0
		for i = line.first, line.last do
			lineCross = math.max(lineCross, crosses[i])
		end
		line.cross = lineCross
		-- the lines are PACKED (the probe): one gap between them and nothing else
		totalCross += lineCross + (if li > 1 then gap else 0)
		maxMain = math.max(maxMain, line.main)
	end
	local value = { lines = lines, sizes = sizes, mains = mains, totalCross = totalCross, maxMain = maxMain }
	ctx.flowLines[node.id] = { key = key, value = value }
	return value
end

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
		-- typography comes from the active snapshot (see `textTypography` above for
		-- the role ladder and why the descriptor rather than a bare family); the
		-- client premeasure adapter resolves that descriptor to the engine face it
		-- names (src/client/text_premeasure).
		local font, size, lineHeight = textTypography(ctx, node)
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
		-- row-actions tray's own action labels, at w=0, in the LT-8 sweep).
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
				recordTextFacts(ctx, node, cm, cm.width > availW, font, size, naturalW, false)
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
			recordTextFacts(ctx, node, m, m.width > availW, font, size, naturalW, false)
			return math.min(m.width, availW) + pl + pr, m.height + pt + pb
		end
		recordTextFacts(ctx, node, m, false, font, size, naturalW, not singleLine)
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
		local idx = chosenCandidate(ctx, node, limitW, innerMaxH)
		local chosen = children[idx]
		if chosen == nil then
			return pl + pr, pt + pb
		end
		local w, h = measure(ctx, chosen, limitW, innerMaxH)
		return w + pl + pr, h + pt + pb
	end

	if node.kind == "composition" then
		local resolution = compositionResolution(ctx, node, innerMaxW, innerMaxH)
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
		local plan = flowPlan(
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
	-- nobody measured" family (docs/lessons/measure-the-requirement-not-the-render.md),
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
-- 40px/frame): `LuauUI/arrange` ran at 1.51ms mean against `LuauUI/measure` at
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
	-- SCOPED TO THE SHAPES THAT PAY FOR IT (architecture review MINOR-8, confirmed as a
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
	if not ctx.hasScroll then
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
	local dropH = ctx.heightFree[node]
	if dropH == nil then
		dropH = false
		if node.kind == "text" then
			local wD, hD = dim(node, "w"), dim(node, "h")
			local t = hD.type
			dropH = wD.type ~= "aspect" and t ~= "aspect" and (t == "fixed" or t == "content" or t == "minMax")
		end
		ctx.heightFree[node] = dropH
	end
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
	if perNode ~= nil then
		local hit = perNode[cacheKey]
		if hit ~= nil then
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
			return hit.w, hit.h
		end
	else
		perNode = {}
		ctx.measureCache[node] = perNode
	end
	local mw, mh = measureUncached(ctx, node, maxW, maxH)
	-- captured AFTER the call, so the entry holds what this measure published
	perNode[cacheKey] = {
		w = mw,
		h = mh,
		textState = ctx.textStates[node.id],
		compact = ctx.compact[node.id],
		textFacts = ctx.textFacts[node.id],
		composition = ctx.compositions[node.id],
	}
	return mw, mh
end

measureUncached = function(ctx: Ctx, node: Node, maxW: number, maxH: number): (number, number)
	ctx.measured += 1
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
	if node.compactText ~= nil then
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
		w = math.floor(h * (wDim.ratio :: number) + 0.5)
	elseif hDim.type == "aspect" then
		w = resolveAxis(ctx, node, wDim, maxW, function()
			local c, _ = content()
			return c
		end, ctx.containerW)
		w = pairedExtent(wDim, maxW, w)
		h = math.floor(w / (hDim.ratio :: number) + 0.5)
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

local ANCHOR_FACTORS: { [string]: { number } } = {
	topLeft = { 0, 0 },
	top = { 0.5, 0 },
	topRight = { 1, 0 },
	left = { 0, 0.5 },
	center = { 0.5, 0.5 },
	right = { 1, 0.5 },
	bottomLeft = { 0, 1 },
	bottom = { 0.5, 1 },
	bottomRight = { 1, 1 },
}

-- offsetPx(value, extent): an offset in pixels. A number passes through; the
-- `{ scale, offset }` form is a FRACTION OF THE PARENT'S INNER EXTENT plus a px
-- adjustment (ADR-0022 Decision 6, row SF-P5) — the shape a marker overlay needs,
-- because a minimap dot's position is a share of the map and not a pixel count.
-- Rounded, because every other placement in this solver is: a marker on a
-- half-pixel is a marker the engine antialiases into a smudge.
local function offsetPx(value: any, extent: number): number
	if type(value) == "number" then
		return value
	end
	if type(value) ~= "table" then
		return 0
	end
	local scale = if type(value.scale) == "number" then value.scale else 0
	local offset = if type(value.offset) == "number" then value.offset else 0
	return math.floor(scale * extent + offset + 0.5)
end

-- The extent a `fill` anchor child may take once its own offset is paid for.
-- Hoisted out of the arrange loop: the solver is perf-pinned, and this used to be
-- a closure allocated per anchor child per solve.
local function offsetFill(available: number, offset: number, factor: number): number
	if offset == 0 then
		return available
	end
	local facing = if offset > 0 then 1 - factor else factor
	if facing <= 0 then
		return available -- anchored to the edge it is being pushed past
	end
	return math.max(0, available - math.abs(offset) / facing)
end

local function alignOffset(align: string?, avail: number, size: number): number
	if align == "center" then
		return math.floor((avail - size) / 2)
	elseif align == "end" then
		return avail - size
	end
	return 0
end

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

-- MAIN-AXIS DISTRIBUTION (§2.6). Returns (lead, step): the pixels before the
-- first child, and the pixels added to every gap between children. Both 0 for
-- `"start"`, which is why the default is byte-identical to the hard-anchored
-- cursor this branch always had.
--
-- One child is not a special case in the arithmetic, and the answers it falls out
-- with are CSS's: `spaceBetween` pins it at the start (there is no gap to fill),
-- `spaceAround` and `spaceEvenly` centre it.
local function distributionOf(mode: string, slack: number, count: number): (number, number)
	if slack <= 0 or count <= 0 then
		return 0, 0
	elseif mode == "center" then
		return slack / 2, 0
	elseif mode == "end" then
		return slack, 0
	elseif mode == "spaceBetween" then
		return 0, if count > 1 then slack / (count - 1) else 0
	elseif mode == "spaceAround" then
		return slack / count / 2, slack / count
	elseif mode == "spaceEvenly" then
		return slack / (count + 1), slack / (count + 1)
	end
	return 0, 0
end

-- arrange pass: assign rects into out[id]
-- Copy a whole subtree's previous entries forward, unchanged. Used only when the
-- subtree is provably unaffected: nothing inside it is dirty and it is being placed at
-- exactly the rect it already had, so every descendant's absolute geometry — and every
-- verdict that geometry produced — is the answer it already gave.
local function replaySubtree(ctx: Ctx, node: Node, previous: any, out: { [string]: any })
	local entry = previous.rects[node.id]
	if entry == nil then
		return false
	end
	out[node.id] = entry
	ctx.skippedIds[node.id] = true
	ctx.skipped += 1
	-- the published channels the rest of the framework reads off `ctx`, replayed for
	-- the same reason `solver.measure`'s memo replays them: a cache that returns
	-- geometry and drops the verdicts changes `compact` and `truncated` while every
	-- rect stays byte-identical (the BLOCKER a differential fuzz caught on that memo)
	ctx.textStates[node.id] = entry.textState
	ctx.compact[node.id] = entry.compact
	ctx.textFacts[node.id] = entry.textFacts
	for _, child in node.children or {} do
		if not replaySubtree(ctx, child, previous, out) then
			return false
		end
	end
	return true
end

local function arrange(ctx: Ctx, node: Node, rect: Rect, out: { [string]: any })
	-- THE SKIP. Same solve, same ctx, same traversal — this subtree just does not need
	-- walking: no dirty node inside it, and it is landing on the rect it already had.
	local reuse = ctx.reuse
	if reuse ~= nil and reuse.dirtyContains[node.id] ~= true then
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
		if
			pr ~= nil
			and containerOk
			and pr.x == rect.x
			and pr.y == rect.y
			and pr.w == rect.w
			and pr.h == rect.h
			and replaySubtree(ctx, node, reuse.previous, out)
		then
			return
		end
	end
	ctx.arranged += 1
	local gap = node.gap or 0
	out[node.id] = {
		rect = rect,
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
		-- that is not text (LTN-4).
		textFacts = ctx.textFacts[node.id],
		-- the declared target floor of an interactive node, carried through so a
		-- pure audit can tell an interactive rect from a decorative one without a
		-- class table it has no business owning. `nil` = no floor declared.
		hitFloor = node.hitFloor,
	}

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

	-- ZERO CONTENT BOX (RS-A16-D3, found live under pixel-quest: `barTrack`
	-- contentInsets of 8 on all four sides over a track the package resolved to
	-- 8px tall, so the fill solved to max(0, 8 - 16) = 0 and the download bar
	-- showed a trough, two heart caps and no value — with zero diagnostics). A
	-- node that has children and no room to put them cannot draw them: the
	-- padding won and the content is invisible. Reported, never repaired —
	-- silently clamping the padding would move shipped geometry, and the whole
	-- point is that this condition stops being invisible.
	--
	-- `rect.w > 0` is the guard that keeps it a diagnosis: a host that was already
	-- zero (a hidden ViewThatFits candidate, a 0-percent fill) is a different
	-- condition and its padding is not what emptied it. `chromeSlot` is set by the
	-- renderer wherever a slot's `contentInsets` became this padding, so the
	-- message names where the numbers came from.
	-- THE CHROME INSET THAT COULD NOT BE SPENT (director report 2026-07-28). The
	-- renderer already repaired the geometry — this is the report that it had to,
	-- which is what an author needs to know: the control is smaller than the theme
	-- it is wearing. It is a SEPARATE message from the collapse below because it
	-- describes the opposite outcome (repaired, not broken) and pointing an author
	-- at "nothing can draw" for a control that now draws fine would be a lie.
	if ctx.hiddenDepth == 0 and node.chromeYield ~= nil then
		local yield_ = node.chromeYield
		if yield_.x ~= nil then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"the '%s' chrome contentInsets could not be spent on x: %dpx of border on a %dpx "
						.. "width already holding %dpx of padding — the inset was given back so the "
						.. "content still draws, but this control is smaller than its theme expects",
					yield_.slot,
					yield_.x,
					rect.w,
					pl + pr
				),
			})
		end
		if yield_.y ~= nil then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"the '%s' chrome contentInsets could not be spent on y: %dpx of border on a %dpx "
						.. "height already holding %dpx of padding — the inset was given back so the "
						.. "content still draws, but this control is smaller than its theme expects",
					yield_.slot,
					yield_.y,
					rect.h,
					pt + pb
				),
			})
		end
	end

	-- A LEAF'S TEXT IS CONTENT TOO (director report 2026-07-28). This was guarded
	-- on `#children > 0`, so a Button whose own label IS its content — every leaf
	-- Button in the library — could collapse to a zero content box and report
	-- nothing at all. That is exactly the shape defect 3 arrived in.
	local hasContent = (node.children ~= nil and #node.children > 0) or (node.text ~= nil and node.text ~= "")
	if ctx.hiddenDepth == 0 and hasContent then
		local from = if node.chromeSlot ~= nil then ` (the '{node.chromeSlot}' chrome contentInsets)` else ""
		if innerW <= 0 and rect.w > 0 then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"content box collapses to 0px on x: padding %d + %d on a %dpx width%s — "
						.. "nothing inside this %s can draw",
					pl,
					pr,
					rect.w,
					from,
					node.kind
				),
			})
		end
		if innerH <= 0 and rect.h > 0 then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"content box collapses to 0px on y: padding %d + %d on a %dpx height%s — "
						.. "nothing inside this %s can draw",
					pt,
					pb,
					rect.h,
					from,
					node.kind
				),
			})
		end
	end

	-- ...and the OTHER thing this node's own box cannot show you: a child holding
	-- a placement prop this node's arrange will never read (§2.1). The finding is
	-- computed at tree-build time; reporting it HERE is what buys it the
	-- `hiddenDepth` gate (a losing ViewThatFits candidate does not shout) and the
	-- reuse replay, the same two properties the overflow diagnostic above has.
	if node.inertPlacement ~= nil and ctx.hiddenDepth == 0 then
		for _, finding in node.inertPlacement do
			table.insert(ctx.diagnostics, finding)
		end
	end

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
		-- unreachable (migration-agent finding 2026-07-23, native-substrate NS-A3)
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
		out[node.id].contentSize = { w = contentW, h = contentH }
		-- ...and the padding this solve actually SPENT, published so the canvas the
		-- adapter is given is built from the same number the content was measured
		-- inside. The renderer used to re-derive it from the authored prop, which
		-- silently drops whatever a theme's `scrollbar` slot reserved (2026-07-27).
		out[node.id].padding = { top = pt, right = pr, bottom = pb, left = pl }
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
			padding. `docs/lessons/a-fixed-box-cannot-hold-a-themes-frame.md` closes
			on the general rule this is the far end of: reserving room is only half
			of it, something has to SPEND the reservation — and here the node that
			must spend it lives outside the subtree that made it. ]]
		out[node.id].barInset = if spentReserve > 0
			then { right = if isX then 0 else spentReserve, bottom = if isX then spentReserve else 0 }
			else nil
		out[node.id].overflow = if (axis == "y" and contentH > innerH) or (axis == "x" and contentW > innerW)
			then "scroll"
			else node.overflow
		-- the flow cursor advances along the SCROLL axis
		local cursor = if isX then innerX else innerY
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
		local idx = chosenCandidate(ctx, node, innerW, innerH)
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
		local resolution = compositionResolution(ctx, node, innerW, innerH)
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
			that and disagreed about the answer: LuauUI's sweep carried it as a
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
					math.floor(innerW + 0.5),
					math.floor(innerH + 0.5),
					resolution.arrangement,
					if why ~= nil then ` (last rejection: {why.rule} — {why.detail})` else ""
				),
				designed = true,
			})
		end
		--[[ ...AND THE ONE BESIDE IT THAT IS NOT DESIGNED AT ALL (ADR-0025 Decision 3).

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
		for i, child in node.children or {} do
			if i == chosen then
				-- the chosen form gets the region's box, and spends it exactly the
				-- way a chosen ViewThatFits candidate spends its container's: a
				-- `fill` axis takes the whole box, anything else takes its own
				-- measure clamped to it. A region is an ALLOTMENT, not a stretch.
				local w, h = measure(ctx, child, innerW, innerH)
				local wDim, hDim = dim(child, "w"), dim(child, "h")
				arrange(ctx, child, {
					x = innerX,
					y = innerY,
					w = if wDim.type == "fill" then innerW else math.min(w, innerW),
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
				local overW = if childFillW then 0 else math.floor(cw - innerW + 0.5)
				local overH = if childFillH then 0 else math.floor(ch - innerH + 0.5)
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
					56px slot by 11/39/59px on a real device. `docs/lessons/luauui-fixed-px-
					heights.md` names the class: a px height fixed against unfixed content.

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
					local over = math.floor(measured - slot.extent + 0.5)
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
			-- children may inherit the stack's default alignment (a cell that
			-- centers its content vertically without touching consumer nodes)
			local x = innerX
				+ ml
				+ (if fillW then 0 else alignOffset(child.alignH or node.alignH or "start", innerW, w))
			local y = innerY
				+ mt
				+ (if fillH then 0 else alignOffset(child.alignV or node.alignV or "start", innerH, h))
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
			local x = innerX + math.floor((innerW - w) * f[1] + 0.5) + ox
			local y = innerY + math.floor((innerH - h) * f[2] + 0.5) + oy
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
	-- re-derived here. It comes from `flowPlan`, which measure also called, so the
	-- two passes cannot disagree about where the lines break.
	if node.kind == "hwrap" or node.kind == "vwrap" then
		local isH = node.kind == "hwrap"
		local children = node.children or {}
		local innerMain = if isH then innerW else innerH
		local innerCross = if isH then innerH else innerW
		local plan = flowPlan(ctx, node, isH, innerMain, innerCross, gap)

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
		-- `Spacer`/`Image`, which is why LuauUI had no leaf-level route to Roblox's
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
				crossSize = math.floor(mainSize / ratio + 0.5)
			else
				mainSize = math.floor(crossSize / ratio + 0.5)
			end
		elseif wDimC.type == "aspect" then
			local ratio = wDimC.ratio :: number
			if isH then
				mainSize = math.floor(crossSize * ratio + 0.5)
			else
				crossSize = math.floor(mainSize * ratio + 0.5)
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
		arrange(ctx, child, childRect, out)
	end
end

export type SafeInsets = { top: number, bottom: number, left: number, right: number }

-- solve: entry point. rootPolicy resolves the content rect from the viewport
-- and safe insets (presenter-owned in production, design §8.1).
function solver.solve(
	root: Node,
	viewport: { w: number, h: number },
	opts: { safeInsets: SafeInsets?, rootPolicy: string?, scrollBarReserve: number?, metrics: any? }?
): {
	rects: { [string]: any },
	diagnostics: { { node: string, issue: string, designed: boolean? } },
	contentRect: Rect,
}
	local insets = (opts and opts.safeInsets) or { top = 0, bottom = 0, left = 0, right = 0 }
	local policy = (opts and opts.rootPolicy) or "coreSafeContent"
	local contentRect: Rect
	if policy == "edgeToEdge" then
		contentRect = { x = 0, y = 0, w = viewport.w, h = viewport.h }
	else -- coreSafeContent / deviceSafeContent collapse for now
		-- clamp: insets larger than the viewport (1x1 Studio instrument trap,
		-- foldable posture change) must not go negative (phase-4 layout fuzz,
		-- seed 2384194589)
		contentRect = {
			x = insets.left,
			y = insets.top,
			w = math.max(0, viewport.w - insets.left - insets.right),
			h = math.max(0, viewport.h - insets.top - insets.bottom),
		}
	end
	local reserve = (opts and opts.scrollBarReserve) or 0
	local ctx: Ctx = {
		diagnostics = {},
		textStates = {},
		compact = {},
		textFacts = {},
		compositions = {},
		regionForm = {},
		hiddenDepth = 0,
		fitProbe = false,
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
		arranged = 0,
		measured = 0,
		analyze = (opts and (opts :: any).analyzeBoundaries) == true,
		boundary = {},
		reuse = opts and (opts :: any).reuse,
		skipped = 0,
		skippedIds = {},
		offers = {},
		-- per-node verdict: can this node's measured size depend on the offered
		-- HEIGHT? Computed once per node per solve, read on every measure of it.
		heightFree = {},
		-- armed the first time a scroll node is measured; a tree without one never
		-- pays for the cache
		hasScroll = false,
		scrollBarReserve = if type(reserve) == "number" and reserve == reserve then math.max(0, reserve) else 0,
		-- Studio Neutral when the caller supplies none: a solve is never without
		-- a metric authority, and neutral reproduces the pre-theme literals
		metrics = (opts and opts.metrics) or themeSnapshot.neutral(),
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
	local out: { [string]: any } = {}
	profile.span("arrange", function()
		arrange(ctx, root, { x = contentRect.x, y = contentRect.y, w = rootW, h = rootH }, out)
	end)
	-- A SKIPPED SUBTREE KEEPS ITS FINDINGS. It was not walked, so it filed nothing this
	-- solve; dropping them would silence `controller.diagnostics()` for exactly the
	-- parts of the screen that did not change, which is the instrument every layout
	-- defect in this repo was caught by.
	if ctx.reuse ~= nil and ctx.skipped > 0 then
		for _, d in ctx.reuse.previous.diagnostics or {} do
			-- THE FILER DECIDES, NOT THE NAMED NODE (RED-TEAM Milestone 1, HIGH 2).
			-- "Was this finding filed this solve?" is a question about the node whose
			-- `arrange` files it, and for every diagnostic here but one that is the
			-- node it names. The exception is `inertPlacement`: the parent files, the
			-- child is named, so a walked parent beside a skipped child filed the
			-- finding fresh AND had it replayed — one extra copy per layout-dirty
			-- frame, unbounded, with the whole list copied forward each solve.
			-- `filedBy` is stamped at build time by `solver.auditPlacement`.
			if ctx.skippedIds[(d :: any).filedBy or d.node] == true then
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
			skipped = ctx.skipped,
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
solver.flowPartition = flowPartition

-- ---- THE STAGE-1 REPORT -----------------------------------------------------
--
-- Answers one question, for the tree as solved: **if any single node changed size,
-- how much of the tree would a boundary-aware layout have to redo?**
--
-- For each node it walks upward to the nearest ancestor that ABSORBS a size change
-- (inclusive of the node itself — a fixed-size node absorbs its own content's
-- change) and counts that ancestor's subtree. With no absorbing ancestor the answer
-- is the whole tree, which is what LuauUI does today for every node.
--
-- Reported as a distribution rather than one number because the interesting fact is
-- the SHAPE: if the median node is isolated to a handful of nodes but the mean is
-- the whole tree, the win is real but uneven, and that changes what Stage 2 should
-- do first.
function solver.boundaryReport(root: Node, result: any): any
	local boundary = result and result.work and result.work.boundary
	if boundary == nil then
		error("solver.boundaryReport: solve with { analyzeBoundaries = true } first", 2)
	end
	local parentOf: { [string]: string } = {}
	local subtree: { [string]: number } = {}
	local order: { Node } = {}

	local function walk(node: Node, parent: Node?)
		if parent ~= nil then
			parentOf[node.id] = parent.id
		end
		table.insert(order, node)
		for _, child in node.children or {} do
			walk(child, node)
		end
	end
	walk(root, nil)

	-- subtree sizes, bottom-up over the same order
	for i = #order, 1, -1 do
		local node = order[i]
		local n = 1
		for _, child in node.children or {} do
			n += subtree[child.id] or 1
		end
		subtree[node.id] = n
	end

	local total = #order
	local affected: { number } = {}
	local absorbed = 0
	for _, node in order do
		if boundary[node.id] == true then
			absorbed += 1
		end
		-- nearest absorbing ancestor, INCLUSIVE
		local at: string? = node.id
		local hops = 0
		while at ~= nil and boundary[at] ~= true and hops <= total do
			at = parentOf[at]
			hops += 1
		end
		table.insert(affected, if at ~= nil and boundary[at] == true then (subtree[at] or total) else total)
	end
	table.sort(affected)
	local sum = 0
	for _, v in affected do
		sum += v
	end
	local function pct(p: number): number
		return affected[math.max(1, math.min(#affected, math.floor(#affected * p)))]
	end
	return {
		nodes = total,
		absorbingNodes = absorbed,
		-- how many nodes a single change would re-lay-out, if boundaries were honoured
		meanAffected = if #affected > 0 then sum / #affected else 0,
		medianAffected = pct(0.5),
		p95Affected = pct(0.95),
		worstAffected = affected[#affected],
		-- what LuauUI does today for every single change
		todayAffected = total,
		-- 1.0 = boundaries would buy nothing; 0.1 = a change touches a tenth of the tree
		meanShareOfTree = if total > 0 and #affected > 0 then (sum / #affected) / total else 1,
	}
end

return solver
