--!strict
-- Pure two-pass layout solver (design §7, UI-LAYOUT-001/002): measure +
-- arrange over an immutable snapshot. Never yields, never reads live signals
-- or Instances; text goes through src/layout/text_metrics (non-yielding).
-- V1 algebra: VStack/HStack/ZStack/Grid/ScrollView/Anchor/Text/Box/Spacer;
-- dims fixed/content/hug/fill/percent/minMax/aspect; padding, uniform-or-per-side
-- margins, cross-axis alignment, overflow annotations, and diagnostics for
-- undefined combinations (percent on an unbounded axis; aspect on both axes).
--
-- Snapshot node shape (plain immutable tables):
-- { kind = "vstack"|"hstack"|"zstack"|"grid"|"scroll"|"anchor"|"text"|"box"|"spacer",
--   id = string, width/height = Dim?, gap = number?,
--   padding = number | {top,right,bottom,left}?,
--   margin = number | {top,right,bottom,left}?,
--   align = "start"|"center"|"end"|"stretch"?          -- cross-axis (stacks)
--   alignH/alignV = "start"|"center"|"end"?            -- zstack children
--   anchor = "topLeft".."bottomRight"?, offsetX/Y?     -- anchor children
--   columns = number?, minColumnWidth = number?,       -- grid
--   rowGap = number?,                                  -- grid (defaults to gap)
--   overflow = "clip"|"scroll"|"visible"|"intentionalOverlap"?,
--   text/font?, textSize = number | <typography role name>?, lineHeight?,
--   singleLine = boolean? (measure one line, clamp to the offer),
--   axis = "y"|"x"? (scroll), children = { Node }? }
-- Dim = { type = "fixed", px } | { type = "content" } | { type = "hug", min?, max? } |
--       { type = "fill", weight } | { type = "percent", fraction } |
--       { type = "minMax", min, preferred?, max } | { type = "aspect", ratio }
-- solve(root, viewport, opts) -> { rects, diagnostics, contentRect }
-- opts.metrics is the active ThemeSnapshot (ADR-0019 §2); omitted, the solve
-- runs on Studio Neutral, whose values are the framework's historic literals.

local text_metrics = require("./text_metrics")
local themeSnapshot = require("../themes/snapshot")
-- the PURE declared-content composition decision (ADR-0023). The solver supplies
-- the measurements and consumes the rects; the ranking, the step-down/drop order
-- and the arrangement choice live there, where a headless sweep can drive them
-- with no tree at all.
local compositionLib = require("./composition")

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
	align: string?,
	alignH: string?,
	alignV: string?,
	anchor: string?,
	-- px, or a FRACTION of the parent's inner extent plus a px adjustment
	-- ({ scale, offset } — ADR-0022 Decision 6, the marker-overlay shape). The
	-- renderer resolves metric names before this; the fraction can only be spent
	-- here, where the extent is known.
	offsetX: (number | { scale: number?, offset: number? })?,
	offsetY: (number | { scale: number?, offset: number? })?,
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
	diagnostics: { { node: string, issue: string } },
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
}

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
	naturalWidth: number?
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
		-- the string this verdict is about: with a compact form in play it is NOT
		-- the string the node draws, and disclosure hands back the full value
		text = node.text,
	}
end

local measure -- forward

-- INTRINSIC COLUMNS (director round 9, 2026-07-26). `minColumnWidth` used to be
-- a literal, which is a guess about a FONT: the gallery's theme picker asked for
-- 132 device px, and under classic-desktop (13 px BuilderSans) that is far too
-- wide while under sci-fi (14 px Michroma, a display face) it is far too narrow
-- — so the same picker over-wrapped in one theme and under-wrapped in the other,
-- and long names clipped against a fixed row height.
--
-- `minColumnWidth = "intrinsic"` asks for the number the solver already has: the
-- widest child's own measured width under the ACTIVE theme's font and metrics.
-- It is recomputed on every solve, so a theme swap re-lays the grid out with no
-- author involvement. A `fill`-width child cannot express an intrinsic minimum
-- (it measures to whatever it is offered), so those are skipped; a grid of only
-- fill children falls back to the one-column default, exactly as an undeclared
-- minColumnWidth does.
local INTRINSIC = "intrinsic"
local function gridColumnMin(ctx: Ctx, node: Node): number?
	local declared = node.minColumnWidth
	if type(declared) == "number" then
		return declared
	end
	if declared ~= INTRINSIC then
		return nil
	end
	local widest = 0
	for _, child in node.children or {} do
		if dim(child, "w").type == "fill" then
			continue
		end
		-- horizontal margins only: this is an intrinsic COLUMN width
		local _, mr, _, ml = sides(child.margin)
		local w = measure(ctx, child, math.huge, math.huge)
		widest = math.max(widest, w + ml + mr)
	end
	return if widest > 0 then widest else nil
end

-- UNIFORM ITEM SIZING (director ruling, 2026-07-26). `itemSizing = "uniform"`
-- measures every child in the column it will occupy, takes the MAX measured size
-- across ALL of them, and hands that back as every cell's size — so a set of
-- ragged, variable-width chips becomes a clean grid of equal plates and a wide
-- display face grows all of them together on the next solve.
--
-- OPT-IN, and `natural` is the default framework-wide: content sizing is what
-- every existing grid was authored against, and a layout that silently equalised
-- its cells would move geometry nobody asked to move.
--
-- Both passes call this, so measure and arrange cannot disagree about the row
-- height (a grid that measured ragged rows and arranged uniform ones is exactly
-- the class of defect this round spent its time on).
-- THE ROW GAP IS ITS OWN AXIS (director finding 14, measured live 2026-07-26).
--
-- A grid's `gap` was doing two jobs whose consequences are not comparable. The
-- COLUMN pitch is `innerW / cols` — a gap change moves the cells inside a
-- column, and (through `minColumnWidth`) can re-column the whole grid, which in
-- the theme picker is a director ruling. The ROW pitch IS the gap. So the
-- picker's grid ran with rows 4 px apart and columns 78 px apart and read
-- cramped, and there was no way to open the rows without risking the columns.
--
-- `rowGap` defaults to `gap`, so every grid in the library, the examples and the
-- fixtures is byte-unchanged and no baseline moves; a caller that wants air
-- between rows says so in one word and the column arithmetic never sees it.
-- HOW MANY COLUMNS THIS GRID GETS, decided once (Step 5.5 cleanup ledger C-04).
-- Measure and arrange both need it and used to derive it separately; a grid whose
-- two passes disagree is this file's documented recurring defect class, so the
-- arithmetic gets one owner rather than two copies that happen to match today.
-- An unbounded offer (`math.huge`, only reachable from measure) yields one column:
-- a column count derived from an infinite width is not a number anyone can use.
local function gridColumnCount(node: Node, inner: number, gap: number, minCol: number?): number
	if node.columns ~= nil then
		return node.columns :: number
	end
	if minCol ~= nil and inner ~= math.huge then
		return math.max(1, math.floor((inner + gap) / (minCol + gap)))
	end
	return 1
end

local function gridRowGap(node: Node): number
	local declared = (node :: any).rowGap
	if type(declared) == "number" then
		return declared
	end
	return node.gap or 0
end

local UNIFORM = "uniform"
local function gridUniformCell(ctx: Ctx, node: Node, colW: number, innerH: number): (number?, number?)
	if node.itemSizing ~= UNIFORM then
		return nil, nil
	end
	local uw, uh = 0, 0
	for _, child in node.children or {} do
		local w, h = measure(ctx, child, colW, innerH)
		uw = math.max(uw, if colW == math.huge then w else math.min(w, colW))
		uh = math.max(uh, h)
	end
	return uw, uh
end

-- resolve one axis of `node` given the limit and a content thunk
local function resolveAxis(ctx: Ctx, node: Node, d: Dim, limit: number, contentFn: () -> number): number
	if d.type == "fixed" then
		return d.px :: number
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

-- ViewThatFits candidate choice (A-AL1). Pure and side-effect free apart from the
-- measure cache, so measure and arrange always agree on the winner.
local function chosenCandidate(ctx: Ctx, node: Node, availW: number, availH: number): number
	local children = node.children or {}
	if #children == 0 then
		return 0
	end
	for i = 1, #children - 1 do
		local w, h = measure(ctx, children[i], availW, availH)
		local fitsW = availW == math.huge or w <= availW
		local fitsH = availH == math.huge or h <= availH
		if fitsW and fitsH then
			return i
		end
	end
	return #children -- the last candidate is the declared fallback
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
		if selfW.type == "fixed" or selfW.type == "percent" then
			local resolved = resolveAxis(ctx, node, selfW, maxW, function()
				return innerMaxW
			end)
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
		local wrapWidth = availW
		-- SINGLE-LINE TEXT (director finding 13, 2026-07-26). A control whose
		-- adapter draws its label on one line has to be MEASURED on one line, or
		-- the row reserves height for a second line nobody draws — the same
		-- measure-versus-paint disagreement rounds 3 and 9 both landed on. The
		-- text is measured UNBOUNDED and the result is clamped to the offer, so a
		-- row that is free to grow takes the width its one line needs and a row
		-- that is not ellipsizes inside the box it was given.
		if node.singleLine == true then
			wrapWidth = math.huge
		end
		-- typography comes from the active snapshot: `body` is the default role,
		-- and a string textSize NAMES a role (the renderer normally resolves it,
		-- but a direct solver caller may hand one straight in).
		-- the measured font is the role's canonical DESCRIPTOR ("family#weight#
		-- style", ADR-0019 §6), never a bare family: two weights of one family
		-- measure differently, and the client premeasure adapter resolves the
		-- descriptor to the engine face it names (src/client/text_premeasure).
		local roles = ctx.metrics.type
		local role = if type(node.textSize) == "string" then roles[node.textSize] else nil
		local base = role or roles.body
		local size = if type(node.textSize) == "number"
			then node.textSize
			else (themeSnapshot.resolveSize(ctx.metrics, node.textSize) or base.size)
		local font = node.font or base.fontKey
		local lineHeight = node.lineHeight or base.lineHeight
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
		if compact ~= nil and availW ~= math.huge then
			local natural = text_metrics.measure(node.text or "", font, size, math.huge, lineHeight)
			if natural.width > availW then
				-- a compact form is ONE word by construction (`assertCompactLabel`
				-- rejects whitespace), so it measures on one line whatever the full
				-- label's wrap state was — which is what makes `singleLine` agree
				-- across both seams without a second rule.
				local cm = text_metrics.measure(compact, font, size, math.huge, lineHeight)
				ctx.compact[node.id] = true
				recordTextFacts(ctx, node, cm, cm.width > availW, font, size, naturalW)
				return math.min(cm.width, availW) + pl + pr, cm.height + pt + pb
			end
			ctx.compact[node.id] = false
		end
		local m = text_metrics.measure(node.text or "", font, size, wrapWidth, lineHeight, node.lineLimit)
		if node.singleLine == true and innerMaxW ~= math.huge then
			recordTextFacts(ctx, node, m, m.width > innerMaxW, font, size, naturalW)
			return math.min(m.width, innerMaxW) + pl + pr, m.height + pt + pb
		end
		recordTextFacts(ctx, node, m, false, font, size, naturalW)
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
		local mainSum, crossMax, n = 0, 0, 0
		for _, child in node.children or {} do
			local w, h = measure(ctx, child, childW, childH)
			mainSum += (if axis == "x" then w else h)
			crossMax = math.max(crossMax, if axis == "x" then h else w)
			n += 1
		end
		local gaps = if n > 1 then gap * (n - 1) else 0
		if axis == "x" then
			return mainSum + gaps + pl + pr, crossMax + pt + pb
		end
		return crossMax + pl + pr, mainSum + gaps + pt + pb
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
		if selfW.type == "fixed" or (selfW.type == "percent" and maxW ~= math.huge) then
			local resolved = resolveAxis(ctx, node, selfW, maxW, function()
				return innerMaxW
			end)
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

	if node.kind == "grid" then
		local children = node.children or {}
		local rowGap = gridRowGap(node)
		local cols = gridColumnCount(node, innerMaxW, gap, gridColumnMin(ctx, node))
		-- clamp: a gap/column combination wider than the container must not
		-- go negative (phase-4 layout fuzz, seed 206612356)
		local colW = if innerMaxW == math.huge then math.huge else math.max(0, (innerMaxW - gap * (cols - 1)) / cols)
		local uniformW, uniformH = gridUniformCell(ctx, node, colW, innerMaxH)
		local totalH = 0
		local rowH = 0
		local rowW = 0
		local maxRowW = 0
		for i, child in children do
			local w, h = measure(ctx, child, colW, innerMaxH)
			rowH = math.max(rowH, if uniformH ~= nil then uniformH else h)
			-- A `uniform` GRID MEASURES THE CELL IT WILL ACTUALLY DRAW (director
			-- round 10, found live 2026-07-26). `itemSizing = "uniform"` makes
			-- arrange draw every cell at the max MEASURED size and no wider, which
			-- is exactly the case where the column and the cell come apart — so
			-- accumulating the COLUMN width here reported "I need the whole offer"
			-- for a grid that then drew something narrower inside it.
			--
			-- Nothing noticed while every grid sat in a `fill` parent, which does
			-- not consult content. The theme picker's card is `hug` and inherited
			-- the lie directly: a full-width phone card with a 130px column of
			-- chips inside it — "the width is too wide".
			--
			-- Deliberately NOT extended to the natural-sizing case. There, `columns
			-- = N` means "N equal columns across what I was given" and a small cell
			-- ALIGNS inside its column; the column width is the honest answer and
			-- `layout_vocabulary.spec` pins it. A `fill` cell takes its column in
			-- both modes.
			local cellW = if colW == math.huge
				then w
				elseif uniformW ~= nil and dim(child, "w").type ~= "fill" then math.min(uniformW :: number, colW)
				else colW
			rowW += cellW + (if (i - 1) % cols == cols - 1 then 0 else gap)
			if i % cols == 0 or i == #children then
				totalH += rowH + (if i == #children then 0 else rowGap)
				maxRowW = math.max(maxRowW, rowW)
				rowH = 0
				rowW = 0
			end
		end
		return maxRowW + pl + pr, totalH + pt + pb
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
		end
	end
	-- PASS 2: a FILL child never receives the whole main extent — it receives its
	-- weighted share of what is left, exactly as arrange distributes it. Measuring
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
measure = function(ctx: Ctx, node: Node, maxW: number, maxH: number): (number, number)
	local wDim, hDim = dim(node, "w"), dim(node, "h")
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
		end)
		h = pairedExtent(hDim, maxH, h)
		w = math.floor(h * (wDim.ratio :: number) + 0.5)
	elseif hDim.type == "aspect" then
		w = resolveAxis(ctx, node, wDim, maxW, function()
			local c, _ = content()
			return c
		end)
		w = pairedExtent(wDim, maxW, w)
		h = math.floor(w / (hDim.ratio :: number) + 0.5)
	else
		w = resolveAxis(ctx, node, wDim, maxW, function()
			local c, _ = content()
			return c
		end)
		h = resolveAxis(ctx, node, hDim, maxH, function()
			local _, c = content()
			return c
		end)
	end
	return w, h
end

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

-- arrange pass: assign rects into out[id]
local function arrange(ctx: Ctx, node: Node, rect: Rect, out: { [string]: any })
	local gap = node.gap or 0
	out[node.id] = {
		rect = rect,
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
		local reserve = ctx.scrollBarReserve
		childSizes, contentW, contentH = measureAll(innerW, innerH)
		if reserve > 0 then
			local overflows = if isX then contentW > innerW else contentH > innerH
			if overflows then
				if isX then
					innerH = math.max(0, innerH - reserve)
				else
					innerW = math.max(0, innerW - reserve)
				end
				childSizes, contentW, contentH = measureAll(innerW, innerH)
			end
		end
		-- the gaps are already folded into contentW/contentH by measureAll: the
		-- flow cursor advances by gap between children, so the extent must include
		-- them or the native canvas under-covers and the last row's tail is
		-- unreachable (migration-agent finding 2026-07-23, native-substrate NS-A3)
		out[node.id].contentSize = { w = contentW, h = contentH }
		-- ...and the padding this solve actually SPENT, published so the canvas the
		-- adapter is given is built from the same number the content was measured
		-- inside. The renderer used to re-derive it from the authored prop, which
		-- silently drops whatever a theme's `scrollbar` slot reserved (2026-07-27).
		out[node.id].padding = { top = pt, right = pr, bottom = pb, left = pl }
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
				ctx.hiddenDepth += 1
				arrange(ctx, child, { x = innerX, y = innerY, w = 0, h = 0 }, out)
				ctx.hiddenDepth -= 1
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
			})
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
				ctx.hiddenDepth += 1
				arrange(ctx, child, { x = originX, y = originY, w = 0, h = 0 }, out)
				ctx.hiddenDepth -= 1
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
				ctx.hiddenDepth += 1
				arrange(ctx, child, { x = innerX, y = innerY, w = 0, h = 0 }, out)
				ctx.hiddenDepth -= 1
				out[child.id].hidden = true
			end
		end
		return
	end

	if node.kind == "zstack" then
		for _, child in node.children or {} do
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
				whole job is to stack over one another. ]]
			if ctx.hiddenDepth == 0 and node.overflow ~= "intentionalOverlap" and node.overflow ~= "clip" then
				local cw, ch = measure(ctx, child, innerW, innerH)
				local overW = math.floor(cw - innerW + 0.5)
				local overH = math.floor(ch - innerH + 0.5)
				if overW > 0 or overH > 0 then
					table.insert(ctx.diagnostics, {
						node = child.id,
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
			local fillW = dim(child, "w").type == "fill"
			local fillH = dim(child, "h").type == "fill"
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

	if node.kind == "grid" then
		local children = node.children or {}
		local rowGap = gridRowGap(node)
		local cols = gridColumnCount(node, innerW, gap, gridColumnMin(ctx, node))
		local colW = math.max(0, math.floor((innerW - gap * (cols - 1)) / cols))
		local uniformW, uniformH = gridUniformCell(ctx, node, colW, innerH)
		local y = innerY
		local i = 1
		while i <= #children do
			local rowH = 0
			local rowSizes = {}
			for c = 0, cols - 1 do
				local child = children[i + c]
				if child == nil then
					break
				end
				local w, h = measure(ctx, child, colW, innerH)
				rowSizes[c + 1] = { w = w, h = h }
				rowH = math.max(rowH, if uniformH ~= nil then uniformH else h)
			end
			for c = 0, cols - 1 do
				local child = children[i + c]
				if child == nil then
					break
				end
				local size = rowSizes[c + 1]
				-- A cell with a FILL dimension occupies its column / row rather
				-- than collapsing to content (swiftui-parity-next investment 6;
				-- found live in Studio as a grid of correctly-positioned, 0px-wide
				-- cells). A non-fill cell keeps content sizing and ALIGNS inside
				-- the cell, so alignH/alignV stop being accepted-and-ignored here.
				local cellW = if dim(child, "w").type == "fill"
					then colW
					elseif uniformW ~= nil then math.min(uniformW :: number, colW)
					else math.min(size.w, colW)
				local cellH = if dim(child, "h").type == "fill"
					then rowH
					elseif uniformH ~= nil then math.min(uniformH :: number, rowH)
					else math.min(size.h, rowH)
				-- aspect against the resolved column width (same reason as in the
				-- stack arrange: a fill sibling has no measure-time size)
				local hDimCell = dim(child, "h")
				if hDimCell.type == "aspect" and cellW > 0 then
					cellH = math.floor(cellW / (hDimCell.ratio :: number) + 0.5)
				end
				arrange(ctx, child, {
					x = innerX + c * (colW + gap) + alignOffset(child.alignH, colW, cellW),
					y = y + alignOffset(child.alignV, rowH, cellH),
					w = cellW,
					h = cellH,
				}, out)
			end
			y += rowH + rowGap
			i += cols
		end
		return
	end

	-- vstack / hstack: fixed/content children keep desired size; fill children
	-- share remaining main-axis space by weight (largest-remainder rounding);
	-- cross axis honors child.align (stretch fills)
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
	-- resolves first and fill shares the remainder — which is the order the
	-- distribution below already assumes.
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
	-- OVERFLOW DIAGNOSTIC (preferred-text sweep, 2026-07-24). Content-sized
	-- children always keep their full desired extent and the flow cursor keeps
	-- advancing, so a stack whose content exceeds its own box silently paints
	-- past its parent and off the viewport — no clip, no compression, no scroll.
	-- Found live: on compact-phone-portrait the adaptive_controls Hud column ran
	-- 185px past its own box, drawing the action row INSIDE the media box and
	-- pushing the stat grid and tile row off an 800px screen — at rest, with the
	-- default text size. This does not change layout (that would be a silent
	-- re-flow of shipped screens); it makes the condition detectable, which is
	-- the whole difference between a bug you can catch and one you cannot.
	if availMain < 0 and ctx.hiddenDepth == 0 then
		table.insert(ctx.diagnostics, {
			node = node.id,
			issue = string.format(
				"content overflows this %s by %dpx on the main axis; it will paint outside its box "
					.. "(wrap it in a ScrollView, or give it room)",
				node.kind,
				-availMain
			),
		})
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
	local cursor = if isH then innerX else innerY
	for idx, child in children do
		local m = margins[idx]
		local mainDim = mainDimOf(child, isH)
		local crossDim = dim(child, if isH then "h" else "w")
		local mainMargin = if isH then m.l + m.r else m.t + m.b
		local mainSize = if mainDim.type == "fill"
			then math.max(0, (fillPx[idx] or 0) - mainMargin)
			else (if isH then desired[idx].w else desired[idx].h)
		-- clamp: margins taller/wider than the stack must not produce negative
		-- cross space (phase-4 layout fuzz, seed 2532671254)
		local crossAvail = math.max(0, (if isH then innerH else innerW) - (if isH then m.t + m.b else m.l + m.r))
		-- CONTAINER-LEVEL align (director review 2026-07-24). HStack/VStack have
		-- always accepted an `align` prop, but the solver only ever read
		-- `child.align` — so `UI.HStack({ align = "center" })` was
		-- ACCEPTED AND IGNORED, exactly what Milestone 0's strict authoring exists
		-- to prevent. There was no way to centre a row's children at all: every
		-- control row pinned its short children (a label, a value readout) to the
		-- TOP against its tall ones, which is why the Volume label and its "6" sat
		-- 13px above the midline of the -/+ buttons, and why the Brightness label
		-- and value sat above the slider track. A child's own align still wins.
		local childAlign = child.align or node.align
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
		local childRect: Rect
		if isH then
			local y = innerY + m.t + alignOffset(childAlign, crossAvail, crossSize)
			childRect = { x = cursor + m.l, y = y, w = mainSize, h = crossSize }
			cursor += m.l + mainSize + m.r + gap
		else
			local x = innerX + m.l + alignOffset(childAlign, crossAvail, crossSize)
			childRect = { x = x, y = cursor + m.t, w = crossSize, h = mainSize }
			cursor += m.t + mainSize + m.b + gap
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
): { rects: { [string]: any }, diagnostics: { { node: string, issue: string } }, contentRect: Rect }
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
		scrollBarReserve = if type(reserve) == "number" and reserve == reserve then math.max(0, reserve) else 0,
		-- Studio Neutral when the caller supplies none: a solve is never without
		-- a metric authority, and neutral reproduces the pre-theme literals
		metrics = (opts and opts.metrics) or themeSnapshot.neutral(),
	}
	local mw, mh = measure(ctx, root, contentRect.w, contentRect.h)
	-- the root honors its own dims: fixed/content use the measured size
	-- (clamped to the content rect); fill stretches to the content rect
	local rootW = if dim(root, "w").type == "fill" then contentRect.w else math.min(mw, contentRect.w)
	local rootH = if dim(root, "h").type == "fill" then contentRect.h else math.min(mh, contentRect.h)
	local out: { [string]: any } = {}
	arrange(ctx, root, { x = contentRect.x, y = contentRect.y, w = rootW, h = rootH }, out)
	return { rects = out, diagnostics = ctx.diagnostics, contentRect = contentRect }
end

solver.sides = sides

return solver
