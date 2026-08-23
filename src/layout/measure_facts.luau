--!strict
--[[ measure_facts — THE PURE PER-NODE FACTS BOTH SOLVER PASSES READ.

	Public interface: `Dim` (the dimension schema), `CONTENT`, `dim`, `mainDimOf`,
	`axisAbsorbs`, `sides`, `textTypography`, `recordTextFacts`, `memoPlan`,
	`MEMO_ARM_DEPTH` and two of the three `PLAN_*` verdicts. Depends on
	`../themes/snapshot` and on nothing else — no solver local, no forward
	declaration, no `require` back.

	`axisAbsorbs` JOINED IT IN THE SAME ROUND it left, and for the reason a pure
	predicate ends up somewhere: it reads a `Dim` and two limits, which is exactly
	what this file is for, and it grew a SECOND reader. It was written for the
	relayout-boundary analysis; the settle-time containment finding asks it the
	same question ("can this parent grow to hold that?") and a second copy of a
	predicate that mirrors `resolveAxis` case for case is how a boundary rule ends
	up disagreeing with the resolver.

	WHY IT IS ITS OWN FILE. `src/layout/solver.luau` crossed the 200,000-character
	`Script.Source` write cap on 2026-08-14 and stopped live-syncing into an open
	Studio session, silently (tools/check_source_size.py). It was back inside
	2,190 characters of that cap on 2026-08-21, and `docs/handoff/SOURCE_CAP_LEDGER.md`
	had already done the analysis and named this module by name: the mutual
	recursion at the heart of that file — `measure` / `measureUncached` /
	`contentSize` / `arrange` / `arrangeStack` — all reads the per-solve `ctx` AND
	calls itself, so none of it is one-way at any size, and the genuinely one-way
	remainder is exactly what is below. THE ARGUMENT LIST WAS ALREADY WRITTEN:
	`SHRINK_DEPS` and `GRID_DEPS` have threaded `mainDimOf`, `sides`,
	`textTypography` and `dim` into `./shrink` and `./grid` as explicit arguments
	since those splits, which is the standing proof that they read nothing of
	their host.

	WHAT MAKES IT ONE-WAY, stated as the property `tests/measure_facts_seam.spec.luau`
	mechanises rather than as a promise:

	  · every fact it reads off the solve arrives on `ctx`, and the fields it reads
	    are declared HERE, in `MeasureCtx` — READ == DECLARED == HOSTED (the
	    solver's own `Ctx` block) as three set comparisons over the live sources;
	  · it WRITES exactly four of them — `fitCuts`, `memoPlans`, `textFacts`,
	    `textStates` — and that set is pinned by name, because a dep this module
	    writes is state two files share while a dep it reads is a fact the solve
	    decided;
	  · it holds NO module-level mutable state. Every module-level `local` here is
	    assigned once, at its declaration, so two solves can never see different
	    helpers — the same discipline `./shrink` and `./grid` state in prose and
	    this one has a test for.

	`ctx` AND `node` ARE TYPED `any` ON PURPOSE, the way `./shrink` types them: the
	solver requires THIS module, so importing `solver.Ctx`/`solver.Node` back would
	be the require cycle the split exists to avoid, and re-declaring either schema
	here is the copy-goes-stale failure that costs more than the annotation is
	worth. `MeasureCtx` below is the exception and is deliberately NOT a re-
	declaration: it names the six fields and nothing else, so it is the seam's
	declared read set rather than a second copy of the solve.

	`Dim` LIVES HERE because `dim` and `mainDimOf` do. It is re-exported as
	`solver.Dim` — the name every caller and every doc uses — so the move is
	invisible to the public surface, and there is one schema rather than two.
]]

local themeSnapshot = require("../themes/snapshot")

local measure_facts = {}

--[[ THE FACTS THIS MODULE READS OFF THE SOLVE, and the whole of them.

	Not a copy of `solver.Ctx` (that record is ~40 fields and grows): this is the
	SEAM'S READ SET, and the spec beside it compares these names against what the
	code below actually touches AND against what the solver's own `Ctx` still
	declares. A field read here and missing there is a rename that would have been
	a runtime `nil`; a field declared here and read nowhere is a fact the solve is
	still computing for nobody.

	Four of the six are WRITTEN through (`fitCuts`, `memoPlans`, `textFacts`,
	`textStates`) — that is the shared write surface, and the spec pins it at
	exactly those four names.
]]
export type MeasureCtx = {
	-- how many text nodes the current `ViewThatFits` probe has seen CLAMPED
	-- (written; `chosenCandidate` reads the delta across one candidate)
	fitCuts: number,
	-- true while a candidate is being asked "do you fit?" (read only)
	fitProbe: boolean,
	-- node -> its `PLAN_*` verdict, decided once per node per solve (written)
	memoPlans: { [any]: number },
	-- the active ThemeSnapshot: the ONE place a typography role's size, font and
	-- line height are learned (read only)
	metrics: any,
	-- node id -> the measurement facts that measure published (written)
	textFacts: { [string]: any },
	-- node id -> the text state the measurer returned (written)
	textStates: { [string]: string },
}

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

local CONTENT: Dim = { type = "content" }

-- The measure-recursion depth at which the per-solve measure memo arms itself on a
-- tree with no ScrollView in it (L-37). Swept, not chosen: `measure`'s gate carries
-- the eleven-point break-even table this number is read off.
local MEMO_ARM_DEPTH = 4

local function dim(node: any, axis: string): Dim
	return (if axis == "w" then node.width else node.height) or CONTENT
end

-- Spacer's default (parity-next investment 6): a bare Spacer takes the
-- leftover space along its STACK's main axis, as the declarative-layout
-- convention it is named for does. Before
-- this, every use needed an explicit `{ type = "fill" }` on the right axis, and
-- writing it on the wrong axis produced a silent zero. An explicit dimension
-- still wins, and a Spacer outside a stack stays inert (a ZStack/Anchor has no
-- main axis to expand along).
local SPACER_FILL: Dim = { type = "fill", weight = 1 }

local function mainDimOf(child: any, isH: boolean): Dim
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
-- the SAME padding semantics the arrange pass uses — ADR-0017's native-substrate rule)
local function sides(margin: any): (number, number, number, number) -- t, r, b, l
	if margin == nil then
		return 0, 0, 0, 0
	end
	if type(margin) == "number" then
		return margin, margin, margin, margin
	end
	return margin.top or 0, margin.right or 0, margin.bottom or 0, margin.left or 0
end

-- THE ONE RESOLUTION OF A TEXT NODE'S TYPOGRAPHY, so the two seams that need it
-- cannot drift. `measureUncached`'s text branch reads it to measure the string;
-- the shrink pass's floor (`textMinMain`) reads it to ask the SAME face and size
-- for the string's min-content width. A second copy of the role ladder here is
-- exactly how a floor ends up computed at `body` for a label drawn at `caption`.
--
-- Module-level, not a closure: this is on the per-text-node measure path, where a
-- per-call allocation is a bench regression this file has already paid for once.
local function textTypography(ctx: MeasureCtx, node: any): (string, number, number)
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

--[[ THE TRUNCATION FACTS ARE PUBLISHED WHERE THE MEASURE HAPPENS: a measure that truncates must SAY so where it truncates, so no consumer re-derives fit from geometry (the large-text rule).

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
	ctx: MeasureCtx,
	node: any,
	m: any,
	clampedWidth: boolean,
	font: string,
	size: number,
	lineHeight: number,
	authoredWidth: boolean,
	naturalWidth: number?,
	wraps: boolean?
)
	ctx.textStates[node.id] = m.state
	local truncated = m.truncated or clampedWidth
	--[[ ...AND THE PROBE COUNTS THE CLAMPED CUT ONLY (DIR wave contract 7). See
		`Ctx.fitCuts`: this is the only place a cut is known and `chosenCandidate` is
		the only reader.

		`clampedWidth` and `m.truncated` are two different events and only one of
		them is a candidate failing to fit. `clampedWidth` is THE BOX BEING TOO
		SMALL FOR ONE LINE — nobody asked for that, and it is the objective chip's
		defect exactly. `m.truncated` is the author's own `lineLimit` biting, which
		is an instruction the candidate is FOLLOWING; refusing a candidate for
		obeying its own declaration was measured on the shipped corpus and it moves
		`adaptive_controls` and `theme_authoring` onto rungs 24-138px taller than
		their page, i.e. it trades a cut label for an overflowing screen. ]]
	--[[ ...AND AN AUTHORED WIDTH IS NOT THE BOX BEING TOO SMALL (M1b, review
		2026-08-18). `clampedWidth` is true whenever the measured line exceeds the
		width this node will occupy — and for a node whose own `width` is
		`{ type = "fixed" }` that width is an INSTRUCTION, not a shortage. Measured
		by the reviewer on a 400px screen with no pressure at all: a rung of
		`HStack{ Box 20, Text(pinned 30) }` was refused and the plain fallback won,
		because the author's own 30px pin read as a cut. `authoredWidth` is passed
		from the one place that knows (`measureUncached`'s text branch computes
		`availW` from that very dimension), so the two cannot drift. The `truncated`
		VERDICT above is unchanged either way — an authored pin that cuts a label is
		still a cut label, and `clippedEssential` still says so. ]]
	if clampedWidth and ctx.fitProbe and not authoredWidth then
		ctx.fitCuts += 1
	end
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
		--[[ ...AND THE LINE-HEIGHT FACTOR (DIR wave contract 5, 2026-08-18).
			Additive, and it is what turns these facts from a description into a
			REPRODUCIBLE MEASURE: `font` and `size` alone cannot rebuild the box,
			because the line box is `ceil(lines * size * lineHeight)` and a package's
			`lineHeight` runs from 1.15 to 1.25 across the eight shipped ones. A
			painted-fits oracle that fell back to the measurer's default factor was
			short by up to 8% per line — enough to report a spill on a box the solver
			had sized exactly right, which is a check that manufactures its own
			findings. Read straight off the same `textTypography` triple the measure
			used, so the two cannot drift. ]]
		lineHeight = lineHeight,
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
		-- because it sees the string but not the box (`render/commit_walks.textVerdicts`).
		wraps = wraps == true,
		-- the string this verdict is about: with a compact form in play it is NOT
		-- the string the node draws, and disclosure hands back the full value
		text = node.text,
	}
end

--[[ WHAT THE MEMO DOES WITH A NODE, DECIDED ONCE PER NODE PER SOLVE (L-37).

	Three verdicts, and each one is an answer to "what does this measure actually
	READ, and what does it cost to recompute?" — the same question L-9 asked of a
	text leaf, asked of every node.

	`PLAN_SKIP` — DO NOT CACHE THIS NODE AT ALL. Both dimensions `fixed` means
	`resolveAxis` returns two literals: `content()` is lazy and is never called, so
	the children are never even walked and nothing is published. Caching a constant
	costs a key string and a table to save two table reads. Measured: with these
	nodes cached, the `zstack` and `wrap` shape arms ran +16.8% and +20.4% against a
	1.5% A/A control; with them skipped, -5.4% and inside the band. (`text` and
	`composition` are excluded from the skip because they publish verdicts through
	`ctx.compact` / `ctx.textFacts` / `ctx.compositions`, and a `compactText` ladder
	forces `content()` even on a fixed box.)

	AND IT HAS NO CORRECTNESS PIN, said plainly rather than left implied: deleting
	the `PLAN_SKIP` branch reddens nothing in the suite, because declining to cache
	is never WRONG — only slower or faster. Its whole evidence is the interleaved A/B
	above and the `scroll` shape arm at -31.7% against a 1.2% A/A control. Do not add
	a test that "covers" it; re-run the measurement.

	`PLAN_HEIGHT_FREE` — CACHE IT, AND LEAVE `maxH` OUT OF THE KEY. This is L-9's
	rule, no longer restricted to text leaves. THE MEASUREMENT THAT FORCED THE
	WIDENING (L-36 -> L-37, and it is the whole reason this exists): on the 30-deep
	`arrange-shapes` tree the solver made 4 696 measure calls over 271 nodes — 17.3
	per node — and an instrumented key showed **1.00 distinct `maxW` and 1.00
	distinct `scopeKey` per node against 16.33 distinct `maxH`**. The key varied by
	`maxH` and by nothing else, on a tree of `fixed`-height boxes whose answer
	cannot depend on it. Dropping it collapses 4 696 uncached measures to 271, one
	per node.

	A node is height-free when its own height cannot read the offer AND its content
	cannot either:
	  * its height type is `fixed`, `content` or `minMax` — exactly the three
	    `resolveAxis` answers without reading its `limit` (`fill`, `percent` and
	    `hug` all read it; `hug` caps at the offer), and neither axis is `aspect`,
	    which couples the two;
	  * ...AND IT IS NOT A `textSize = "fit"` NODE ON ONE OF THE TWO INDEFINITE ONES
	    (2026-08-22). This enumeration used to end at the clause above and the text
	    branch below took it unconditionally, on the fact that a text node's content
	    never reads `innerMaxH`. A FIT reads it — the size is chosen against the box
	    — so `content` and `minMax` stop being height-free for it, and only `fixed`
	    survives (a literal box cannot be offered two heights). The exception is
	    written HERE as well as at its branch because a rule stated in one place and
	    qualified seventy lines below is a rule the next reader will re-derive from
	    the wrong half;
	  * its CONTENT does not read `innerMaxH`. `contentSize` is a closed enumeration
	    and only these kinds read it other than by handing it to a child:
	    `scroll` (it pushes the container AND prices the scrollbar reserve off it),
	    `fits` (the fit test compares against it), `composition` (its resolution is
	    keyed by it), `grid`/`gridrow` (the lane axis), and `vwrap` (it breaks lines
	    on it). Those are `HEIGHT_COUPLED_KINDS` and are never height-free.
	    `hwrap` is NOT in the set: `flowPlan` breaks an `hwrap` on `innerMaxW` and
	    passes `innerMaxH` to the children untouched, exactly like `hstack`;
	  * every child is height-free — and, on a VERTICAL main axis, no child declares
	    a `fill` main dimension or a `shrinkWeight` above zero, because PASS 2 and
	    PASS 1.5 read `mainLimit` (which IS `innerMaxH` there) to size them.

	`PLAN_KEYED` — cache it with the full key. Everything else.

	VERIFIED BY DIFFERENTIAL ORACLE, not by reading the enumeration twice — the
	discipline L-9 set when the FIRST cache in this function turned out to be wrong
	in a way only a differential oracle could see. 800 seeded trees over the whole
	vocabulary (including `fits`, `hwrap`/`vwrap`, `gridrow`, `shrinkWeight`,
	`compactText`, `lineLimit`), solved by a baseline build and this one, comparing
	x/y/w/h AND `compact`, `textState` and `textFacts` per node: 25 961 node
	comparisons, ZERO differences, and the diagnostic SET identical on every tree.
]]
local HEIGHT_COUPLED_KINDS: { [string]: boolean } = {
	scroll = true,
	fits = true,
	composition = true,
	grid = true,
	gridrow = true,
	vwrap = true,
}

local PLAN_SKIP, PLAN_KEYED, PLAN_HEIGHT_FREE = 0, 1, 2

local function memoPlan(ctx: MeasureCtx, node: any): number
	local memo = ctx.memoPlans[node]
	if memo ~= nil then
		return memo
	end
	local kind = node.kind
	local wD, hD = dim(node, "w"), dim(node, "h")
	local plan = PLAN_KEYED
	if wD.type == "fixed" and hD.type == "fixed" and kind ~= "text" and kind ~= "composition" then
		plan = PLAN_SKIP
	else
		local t = hD.type
		if wD.type ~= "aspect" and t ~= "aspect" and (t == "fixed" or t == "content" or t == "minMax") then
			if kind == "text" then
				--[[ ...UNLESS THE SOLVER IS CHOOSING THE SIZE (`textSize = "fit"`,
					2026-08-22). The sentence above — "a text node's answer does not depend
					on [the offered height] at all; its content size comes from the wrap
					width, and `contentSize`'s text branch never reads `innerMaxH`" — was
					measured and true when it was written, and the fit branch made it false:
					a fit is bounded by the BOX, so it reads `innerMaxH` on every height that
					is not a literal.

					Dropping `maxH` there means the same node asked at `inf|700` and then at
					`inf|104` shares the key `inf|*|0`, and the first box's answer serves the
					second. Measured on the pre-fix build: a 41 px `hug` cap painted a 531 px
					line block at the 700 px offer's size. It needed a ScrollView anywhere in
					the tree to show at all (the memo is armed by `ctx.hasScroll`), which is
					how it survived a green suite.

					`fixed` IS still height-free, and genuinely so: a literal box cannot be
					offered two different heights, so the fit's second input is a constant
					and the key does not need it. Everything else keeps `maxH`.

					VERIFIED BY THE DIFFERENTIAL ORACLE, and it could not have been before:
					`tests/lib/fuzzers/layout.luau` spoke only numeric text sizes, so no
					seeded tree contained the shape. It generates `textFit` now. ]]
				plan = if node.textFit ~= nil and t ~= "fixed" then PLAN_KEYED else PLAN_HEIGHT_FREE
			elseif not HEIGHT_COUPLED_KINDS[kind] then
				plan = PLAN_HEIGHT_FREE
				-- the kinds whose main axis is VERTICAL: `vstack` and every kind that
				-- falls through `contentSize` to the stack branch with `isH == false`.
				-- `zstack`/`anchor`/`region` have no main axis and `hstack`/`hwrap`
				-- distribute along the width, so none of them read `innerMaxH` for a
				-- fill share or a squeeze.
				local isV = kind ~= "hstack"
					and kind ~= "hwrap"
					and kind ~= "zstack"
					and kind ~= "anchor"
					and kind ~= "region"
				for _, child in node.children or {} do
					if isV and (mainDimOf(child, false).type == "fill" or (child.shrinkWeight or 0) > 0) then
						plan = PLAN_KEYED
						break
					end
					-- a `PLAN_SKIP` child is height-free BY CONSTRUCTION (its size is two
					-- literals), so only `PLAN_KEYED` disqualifies the parent
					if memoPlan(ctx, child) == PLAN_KEYED then
						plan = PLAN_KEYED
						break
					end
				end
			end
		end
	end
	ctx.memoPlans[node] = plan
	return plan
end

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
--[[ `limit`/`otherLimit` CARRY ONE BIT, AND THAT IS THE CONTRACT.

	The two callers pass two different quantities. The boundary analysis passes
	the OFFER (`maxW`/`maxH`, "what decides it for a percent or fill dimension");
	the containment gate passes the parent's RESOLVED content extent
	(`innerW`/`innerH`), because by arrange time the offer is gone and the box is
	the answer. They agree today for one reason only: every branch below asks
	`~= math.huge` and nothing else, so the argument means "is this axis bounded"
	and both callers are right about that.

	IT IS NOT A COMMENT ASKING TO BE TRUSTED. `tests/measure_facts_seam.spec.luau`
	scans this function and fails if `limit` or `otherLimit` is ever compared to
	anything but `math.huge` — the moment a branch reads the magnitude, the two
	callers stop meaning the same thing and one of them is silently wrong. Widen
	it deliberately and that check tells you to give the second caller its own
	argument. ]]
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

measure_facts.CONTENT = CONTENT
measure_facts.axisAbsorbs = axisAbsorbs
measure_facts.MEMO_ARM_DEPTH = MEMO_ARM_DEPTH
-- `PLAN_KEYED` is deliberately NOT exported: it is the default verdict and its
-- only reader is `memoPlan` itself, so exporting it would be a fact computed
-- for nobody (found by `tests/measure_facts_seam.spec`, not by reading)
measure_facts.PLAN_HEIGHT_FREE = PLAN_HEIGHT_FREE
measure_facts.PLAN_SKIP = PLAN_SKIP
measure_facts.dim = dim
measure_facts.mainDimOf = mainDimOf
measure_facts.memoPlan = memoPlan
measure_facts.recordTextFacts = recordTextFacts
measure_facts.sides = sides
measure_facts.textTypography = textTypography

return measure_facts
