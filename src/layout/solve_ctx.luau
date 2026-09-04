--!strict
--[[ THE PER-SOLVE CONTEXT — what one `solver.solve` carries, and the one place it
	is born.

	`solver.luau` reached 195,714 characters against a 200,000 `Script.Source` WRITE
	cap, and 13,716 of them — 7 % of the file — were this type declaration and its
	documentation. That is the source-cap ledger's own rule applied literally: take
	the room in its own behaviour-neutral commit, BEFORE the change that needs it.

	IT IS ONE SUBJECT, not a documentation dump. The record and the single place it
	is constructed belong together: every field below is a per-solve accumulator, a
	per-solve memo or a per-solve gate, and `new` is where each one's initial value
	is decided. Splitting them would put the answer to "what does this field start
	as" one file away from "what is this field for" — and half the comments here
	already point at the other half.

	THE ONE-WAY TEST, which is what makes this a seam rather than a move. This module
	requires `./measure_reuse` (for `Store`, one field's type) and NOTHING else. It
	declares no function that reads or writes a solver local, holds no module-level
	mutable state, and names no solver symbol: `Rect` moved here WITH the type that
	needs it and `solver.luau` re-exports it, so there is still exactly one
	declaration of a layout rectangle in `src/layout/`. The solver's five mutually
	recursive functions (`measure`/`measureUncached`/`contentSize`/`arrange`/
	`arrangeStack`) are untouched and no Deps record is needed — nothing crosses the
	boundary but a type and a table literal.

	`tests/solve_ctx_seam.spec.luau` mechanises each of those rules with a negative
	control. ]]
local measureReuse = require("./measure_reuse")

local solve_ctx = {}

export type Rect = { x: number, y: number, w: number, h: number }

export type Ctx = {
	-- A FINDING'S `designed` FLAG (ruling 8) marks the ones that report the system
	-- working as declared rather than a defect. Absent on every other finding, so
	-- `d.designed == true` is the whole test; see the composition arrange branch
	-- for the one place that sets it and why the two kinds had to be separable.
	--
	-- `measured` IS AN INTERNAL STAMP, NOT PART OF THE DOCUMENTED FINDING CONTRACT —
	-- the same class as `filedBy` (stamped by `solver.auditPlacement`), and set for
	-- the same kind of reason: the replay and the anchor arm have to tell a
	-- MEASURE-time finding from an ARRANGE-time one, and `walkedIds` can only answer
	-- for the second. It is written in the four measure-time filers' own literals
	-- rather than by a wrapper because `measure` has two early returns that never
	-- reach its capture block, and a stamp that is right on only one of three paths
	-- is worse than none (T9 review, I1 — the probe that found it).
	diagnostics: { { node: string, issue: string, designed: boolean?, measured: boolean? } },
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
	-- would like at its own IDEAL size, and it is part of `scopeKey`, because the
	-- same node at the same offer answers differently under it.
	-- (The comparison this sentence used to draw travelled out of an
	-- extraction-locked file, where it was exempt, into one that is not — an
	-- extraction inherits none of its host's exemptions, which is the rule at the
	-- head of the source-cap ledger and the reason `check_brand_drift` names the
	-- moved line rather than the file it came from.)
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
	--[[ EVERY ENTRY INTO `measure`, AND THE ONES ANSWERED FROM THE NODE'S OWN LAST
		ANSWER (C2). `measured` above cannot stand in for either: it counts UNCACHED
		measures, so a memo hit never moved it and a served call does not either. The
		serve's whole claim is that a clean sibling on a dirty path stops paying for a
		memo lookup, and the only honest instrument for that is the pair — how many
		times the function was asked, and how many of those returned before the memo
		existed. Published in the work record and surfaced as
		`controller.stats().lastMeasureCalls`/`lastMeasureServed`. ]]
	measureCalls: number,
	measureServed: number,
	--[[ THE SOLVE-WIDE INPUTS THE NODE TUPLES WERE RECORDED UNDER — axis 3 of
		`./measure_reuse`'s store, threaded in here because `measure`'s node-resident
		serve is a FOURTH cache with the same four axes and needs its own answer to
		each. Axis 1 (a structural change) is answered by the layout node being a
		fresh literal; axis 2 by `reuse.measureContains`; axis 4 (the container) by
		`node.containerRelativeInside` and the scope key. THIS IS AXIS 3, and it is
		the one no per-node fact can see: the viewport, the safe insets, the root
		policy, the scrollbar reserve, the band, the theme snapshot, the two text
		scales and the TEXT-METRICS EPOCH. That last one is why a string is threaded
		rather than an argument being declared unnecessary — a text settle corrects
		the measured width of a label at an UNCHANGED offer under an UNCHANGED theme,
		clears the measure store, and would otherwise leave a served node reporting
		the width it had before the correction. `nil` for a direct `solver.solve`
		caller, which compares equal to the `nil` such a caller's nodes carry. ]]
	measureStamp: string?,
	-- ...and its writes into the RECT MAP: `arranged + translated` since O3.
	rectInserts: number,
	-- THE THIRD CLASS (O3): a node an ancestor re-based instead of walking — not
	-- arranged, not skipped, a rect insert. `translatedRoots` is keyed by the node
	-- whose delta it was, `[from, to]` naming its span in the two flat arrays, which
	-- are in document order for the COMMIT to walk (T5).
	translated: number,
	-- THE ANCHOR ARRANGE'S TWO HALVES (wicked-fast N2). An anchor re-offers every
	-- child on every arrange of it, so settling ONE dirty child costs a `measure`
	-- per sibling; `anchorReused` counts the children served from their own previous
	-- rect instead and `anchorOffered` the ones that still went to `measure`. They
	-- are the counter this task is measured by — the `measured` counter above cannot
	-- see it, because a sibling's re-offer HITS the memo and never reaches
	-- `measureUncached`.
	anchorReused: number,
	anchorOffered: number,
	translatedRoots: { [string]: { dx: number, dy: number, from: number, to: number } },
	-- THE ABSOLUTE ORIGIN OF THE COORDINATE SPACE THE WALK IS IN (Plan C), pushed and
	-- popped by the `arrange` wrapper, so `rect.x + ctx.spaceOX` is a window-space x.
	-- Two numbers, not a map: the one consumer is the arrange-time
	-- `composition_resolve.resolve` call, which takes origin NUMBERS.
	spaceOX: number,
	spaceOY: number,
	--[[ THE COORDINATE-SPACE HOSTS THE WALK IS INSIDE (outermost first), the set of
		the ones holding a `UI.Composition`, and the suspend depth that set drives.

		A composition's RESOLUTION is a function of its WINDOW origin: author
		`exclusions` are window-space rects converted into its box. Under a coordinate
		space that origin moves when the HOST moves while nothing beneath it moves in
		its own space — so both the SKIP and the arm would leave it resolved at the
		position before last. Measured: a reactive-`offsetY` ZStack holding a
		Composition excluded `{0,0,200,200}` placed its region 7px low after one
		slide. `noSkipDepth` suspends both for such a subtree.

		WHAT THAT COSTS: the wrapper raises it BEFORE `arrangeBody`, so such a host
		cannot skip at its own top either — every solve that reaches it walks its
		whole subtree. Only a host holding a composition pays it.

		The set is carried from the previous solve's work record the way `out` is
		carried from its rect map — a solve that skipped the subtree did not re-observe
		the composition and must not forget it — and EVERY host above one is marked,
		since an outer taking the shortcut would never re-enter the inner. IT IS
		PRUNED WHERE IT IS FILLED: the origin rebind clears a host's own entry as its
		body starts, so a composition that unmounts stops re-marking it. ]]
	spaceStack: { string },
	spaceCompositions: { [string]: boolean },
	noSkipDepth: number,
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
	-- FALSE WHEN THE PREVIOUS SOLVE FILED A MEASURE-TIME FINDING (T9 review, I1) —
	-- computed once in `solve` off the `measured` stamp, read only by the anchor
	-- arrange arm, which cannot serve a child without losing that child's subtree's
	-- findings. True on every well-formed tree, which is what makes it free.
	measureQuiet: boolean,
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

--[[ THE ONE PLACE A CONTEXT IS BUILT. `solver.solve` resolves the three things a
	caller decides — the content rect (its safe-inset policy), the theme metrics and
	the scrollbar reserve — and hands them here; every other field's initial value is
	a property of the solve rather than of the caller, and is decided below.

	It returns a context with `measureQuiet` ALREADY ANSWERED, because that answer is
	read off the previous solve's findings and there is no moment between the literal
	and the loop when a half-built context is worth handing to anyone. ]]
function solve_ctx.new(contentRect: Rect, opts: any, metrics: any): Ctx
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
		-- see `Ctx`: how many times `measure` was asked, and how many of those it
		-- answered from the node's own tuple
		measureCalls = 0,
		measureServed = 0,
		-- the renderer's own axis-3 stamp, or nil; see `Ctx`
		measureStamp = if opts ~= nil then (opts :: any).measureStamp else nil,
		-- the O3 translate class: nodes re-based by an ancestor's delta
		translated = 0,
		-- ...and the N2 anchor pair; see the `Ctx` block for why `measured` cannot
		-- stand in for them
		anchorReused = 0,
		anchorOffered = 0,
		translatedRoots = {},
		spaceOX = 0,
		spaceOY = 0,
		spaceStack = {},
		noSkipDepth = 0,
		-- carried from the previous solve (`Ctx`): a solve that skipped a subtree did
		-- not re-observe the composition inside it
		spaceCompositions = (
			opts
			and (opts :: any).reuse
			and (opts :: any).reuse.previous.work
			and (opts :: any).reuse.previous.work.spaceCompositions
		) or {},
		translatedPaths = {},
		translatedEntries = {},
		analyze = (opts and (opts :: any).analyzeBoundaries) == true,
		boundary = {},
		reuse = opts and (opts :: any).reuse,
		skipped = 0,
		walkedIds = {},
		measureQuiet = true,
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
		-- the caller's reading, resolved once in `solver.solve` beside the content
		-- rect so the two are one reading
		metrics = metrics,
	}
	-- DID THE PREVIOUS SOLVE REPORT A MEASURE-TIME FINDING? Once per solve, off the
	-- stamp `measure` freezes onto each one, and empty on every well-formed tree — so
	-- this is a loop over nothing in the case that matters. The anchor arrange arm is
	-- its only reader; the long form of why is at that arm.
	local prevDiags = if ctx.reuse ~= nil then ctx.reuse.previous.diagnostics else nil
	if prevDiags ~= nil then
		for _, d in prevDiags do
			if (d :: any).measured then
				ctx.measureQuiet = false
				break
			end
		end
	end
	return ctx
end

return solve_ctx
