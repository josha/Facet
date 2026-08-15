--!strict
-- THE TWO NAMED LEVERS, GIVEN A WORKLOAD (2026-08-15).
--
-- `artifacts/performance-stress-places/device-capture-2026-08-15.md` §7 ranks two
-- levers and records that NEITHER has a workload aimed at it. This module is those
-- two workloads. Everything else about the lab is unchanged; `perf_lab` declares
-- these two entries beside its own and hands this file the seams it needs.
--
--   LEVER 1 — `arrange` ITSELF. Top cost in all four device captures, 9.1-10.6 ms
--   per occurrence across two sessions, 2-3x `measure`, worst single occurrence
--   298.87 ms. Nothing had been done about it because no analysis could get INSIDE
--   it: `LuauUI/arrange` is one scope wrapping one recursive tree walk, so a dump
--   says "arrange is expensive" and stops.
--
--   LEVER 2 — INCREMENTAL LAYOUT ON A COLLECTION EDIT. L-27 measured incremental
--   layout inert on a RESIZE, which is the case where every constraint changes so
--   nothing can be reused. A collection edit is the opposite: one row moved, the
--   viewport unchanged. `collection-churn` priced it at 26 full solves per frame
--   with ZERO structural change and it has never been investigated.
--
-- WHY THIS IS ITS OWN FILE AND NOT MORE OF `perf_lab.luau`. `perf_lab` is 172,876
-- characters against the 200,000-character `Script.Source` WRITE cap
-- (`tools/check_source_size.py`, `docs/lessons/the-200k-source-cap-is-on-writing-
-- not-loading.md`). A module that crosses it stops live-syncing into an open Studio
-- session SILENTLY, which manufactures false evidence — an agent runs a live check
-- against code the session never loaded. Two workloads at this file's comment
-- density is ~20k characters, which spends three quarters of the remaining headroom
-- on the one module a profiling session must be able to live-patch. It arrives
-- through `ctx.lab.levers` for the same reason `dataset`, `rows`, `capture` and
-- `overlay` do: `perf_lab` must stay `script`-free to run under Lune.
--
-- ENGINE-FREE, like every lab module: no `game`, no `Instance`, no `debug`. Every
-- seam arrives in `deps`.
--
-- THE FOUR RULES EVERY PASS HERE OBEYS, each of which a past capture was lost to:
--
-- 1. ONE LAP FITS A 60-FRAME WINDOW. `extentArms` is 5 arms x 108 frames = 540
--    frames per lap, so the MicroProfiler's 60-frame aggregate could never contain
--    the comparison it was built for. Here **an arm IS a pass**: one lap is one arm
--    at its default reps (24-40 frames), and `profileWindow` loops exactly one pass.
-- 2. THE ARM IDENTITY IS IN `workspace`, NOT IN FORENSICS. `profileWindow` already
--    stamps `LuauUI_ProfilingPass`, so making the arm a pass puts the arm name in a
--    workspace attribute for free. Nothing here has to be identified by counting
--    child instances in a binary blob.
-- 3. EVERY REP YIELDS. `telemetry.step()` inside the rep loop, outside the timed
--    region. A pass that runs its whole ladder in one frame is unmeasurable by
--    construction and has hung the director's phone twice.
-- 4. `lapWork` IS POPULATED HONESTLY. Every pass here provokes real solves per lap,
--    so the phone's status line reads `arrange=24 mount=0` BEFORE a dump is spent.

local levers = {}

--[[ ── WHAT `arrange-shapes` CAN AND CANNOT SEE, stated before the arms ────────

	`arrange` (src/layout/solver.luau) is ONE recursive per-node function with a
	`node.kind` dispatch chain. It has no prologue, no epilogue and no per-solve
	phase structure: every distinguishable phase — the stack fill distribution, the
	shrink pass and its re-measure, the wrap line breaking, the grid track
	consumption, the scroll canvas extent — is the BODY of one invocation, running
	once per node of that kind.

	That fact decides the profile-scope question by itself, and it is why this
	workload exists instead of three new scopes. A `profile.span` around any of
	those phases would open a scope PER NODE — a closure and two pcalls per node
	per frame — which is exactly the per-call-site label set `src/core/profile.luau`
	rule 1 forbids, and it would cost more than it measures. `profile.MAX_SCOPES`
	stays 12.

	But the same fact hands the measurement over for free: **arrange's phases are
	dispatched by node kind, so a tree built of ONE kind isolates that kind's
	phase.** A capture of an arm is a capture of a phase, taken from outside the
	solver, with no new scopes and no edit to a file another agent is live in.

	Every arm carries the SAME leaf count so the arms are comparable, and every arm
	reports `arrangedNodes` (the solver's own `ctx.arranged`, surfaced through
	`controller.stats().lastArranged`) so the headline is **ms per arranged node**
	rather than ms per solve. "arrange is slow" is not actionable; "arrange costs
	4x more per node when the children fill than when they are fixed" is. ]]

-- Held constant across every arm. 240 is enough that the per-node arithmetic
-- dominates the per-solve overhead and small enough that one rep is one frame on
-- a handset rather than four.
local SHAPE_LEAVES = 240
-- the depth arm's nesting; leaves are divided evenly between the levels so the
-- LEAF count matches every other arm and only the depth differs
local SHAPE_DEPTH = 30
local SHAPE_LEAF_H = 10
local SHAPE_LEAF_W = 24

--[[ THE ARMS, and the ONE property each varies against `flat`.

	Every arm is `SHAPE_LEAVES` boxes under one root container. `flat` is the
	control: a plain vstack of fixed-size children, which takes the shortest path
	through arrange's stack branch (no fill distribution, no shrink, no wrap, no
	sort, no second measure).

	| arm        | the one thing that differs from `flat`     | the arrange phase it lights up |
	| flat       | —                                          | the stack placement loop alone |
	| deep       | 30 nested vstacks instead of one           | recursion depth + the measure-from-arrange fan-out |
	| deepScroll | the SAME deep tree, inside a ScrollView    | `deep` with the measure memo turned ON — see below |
	| fill       | every child `height = fill`                | main-axis share distribution, the largest-remainder `table.sort`, and the FILL SECOND MEASURE |
	| zstack     | a ZStack root instead of a VStack          | the overlap branch, which measures every child TWICE |
	| wrap       | `wrap = true` on an HStack root            | flow-line planning + per-line distribution |
	| scroll     | the same flat tree inside a ScrollView     | the canvas-extent branch AND the measure memo |
	| text       | Text leaves instead of Box leaves          | text metrics reached from inside arrange |

	`deepScroll` IS THE ONE WITH A HYPOTHESIS ATTACHED, and it is the reason this
	workload has nine arms instead of eight. `solver.measure`'s memo opens with
	`if not ctx.hasScroll then return measureUncached(...) end` — the cache only
	arms itself when the tree contains a ScrollView. Arrange calls `measure` from a
	dozen sites, so a tree with no scroller pays every one of them uncached, and a
	DEEP tree pays them once per enclosing level. `deep` against `deepScroll` is a
	single-variable test of that gate: same 240 leaves, same 30 levels, same
	provocation, and the only difference is whether the memo is armed. `scroll`
	against `flat` is the same test at depth 1, where there is nothing to re-measure
	and the answer should therefore be "no difference". ]]
local SHAPE_ARMS = { "flat", "flatRepeat", "deep", "deepScroll", "fill", "zstack", "wrap", "scroll", "text" }

--[[ ── LEVER 2's ARMS ──────────────────────────────────────────────────────────

	`collection-churn/insert` performs 25 inserts with no yield between them, so
	one lap is one 557 ms frame and a dump reads 26 solves in a single frame. The
	arms here perform ONE edit per frame, which is what a real collection edit is,
	and time each one — so the question stops being "what does a lap cost" and
	becomes "what does an edit cost, and does the reuse path bite".

	AND THE THING NOBODY HAD NOTICED: the lab's own default is `incremental = false`
	(`perf_lab` settings), and the FRAMEWORK's default is ON
	(`renderer.luau`: `incrementalEnabled = opts == nil or opts.incrementalLayout ~=
	false`). So every number in `optimization-log.md` taken through the lab's shared
	mount — `collection-churn`'s 26 solves at 9.384 ms included — was measured with
	the reuse path DISABLED, in a configuration production does not ship. These arms
	hard-code the flag per arm rather than reading the selector, exactly as
	`extentArms` hard-codes `itemExtent`: an A/B whose two halves read the same
	setting is two identical arms that agree with each other beautifully. ]]
local EDIT_ROWS = 2000
-- the same insertion point `collection-churn/insert` uses: ~25% down a 2 000-row
-- collection, which with the window at the top is ~475 rows below the last
-- mounted row. Nothing the player can see changes.
local EDIT_OFF_WINDOW_FRACTION = 0.25
local EDIT_ARMS = {
	"editOffWindow",
	"editOffWindowRepeat",
	"editOffWindowIncremental",
	"editInWindow",
	"editInWindowIncremental",
}

--[[ EXPORTED SO THE DECLARATION AND THE IMPLEMENTATION CAN BE TIED TOGETHER.

	The two workload DECLARATIONS live in `perf_lab.WORKLOADS` — that table is read
	by the overlay's picker, the sweep, the capture rows and `steps.workloads`, and a
	second source for it would be a second answer to "what workloads exist".
	`perf_lab` cannot `require` this file (it must stay `script`-free to run under
	Lune), so the pass NAMES are written out in both places. These two lists are what
	makes that duplication checkable rather than a drift hazard: `perf_lab`'s build
	asserts every declared pass was actually installed, and `tests/perf_lab.spec`
	asserts the declared lists are exactly these. ]]
levers.SHAPE_ARMS = SHAPE_ARMS
levers.EDIT_ARMS = EDIT_ARMS
levers.SHAPE_LEAVES = SHAPE_LEAVES
levers.EDIT_ROWS = EDIT_ROWS

--[[ install(deps) -> nil

	Writes this file's passes into `deps.passes`. Everything it needs arrives in
	`deps` rather than being re-derived, so an arm here and a pass in `perf_lab`
	can never disagree about what a millisecond, a percentile or a scope count is:

	  LuauUI, core, ctx          the framework, the reactive core, the runner ctx
	  labScope                   the scenario's disposal root (arms take children of it)
	  dataset, rows              the shared deterministic dataset and row spec
	  settings                   the live selector table (read for `recycle`, `seed`, theme)
	  telemetry                  `clock()` and `step()` — the frame-yield seam
	  timed, summarize           the shared pass-record and p50/p95/worst helpers
	  scopeCount                 `LuauUI/<phase>` open counts, for solve accounting
	  framesAndReps              the shared `frames` / `frames/reps` payload parser
	  viewportH                  the derived list height (the same one every pass uses)
	  passes                     the table to install into
]]
function levers.install(deps: any)
	local LuauUI = deps.LuauUI
	local core = deps.core
	local ctx = deps.ctx
	local labScope = deps.labScope
	local dataset = deps.dataset
	local rows = deps.rows
	local settings = deps.settings
	local telemetry = deps.telemetry
	local timed = deps.timed
	local summarize = deps.summarize
	local scopeCount = deps.scopeCount
	local framesAndReps = deps.framesAndReps
	local viewportH = deps.viewportH
	local passes = deps.passes
	local U = LuauUI.UI
	local clock = telemetry.clock

	-- ================================================================
	-- LEVER 1 — arrange, by tree shape
	-- ================================================================

	-- One leaf. Identical in every arm except `text`, so the only difference
	-- between two arms is the container they hang under.
	local function leaf(i: number, kind: string, item: any): any
		if kind == "text" then
			return U.Text({
				id = `L{i}`,
				text = item.name,
				textSize = 12,
				lineLimit = 1,
				height = { type = "fixed", px = SHAPE_LEAF_H },
			})
		end
		return U.Box({
			id = `L{i}`,
			width = { type = "fixed", px = SHAPE_LEAF_W },
			height = if kind == "fill" then { type = "fill", weight = 1 } else { type = "fixed", px = SHAPE_LEAF_H },
		})
	end

	--[[ THE TREE, and the ONE line that differs per arm.

		`pad` is the arm's provocation, bound reactively on the ROOT container:
		`padding` is a reactive prop with dirty class `measure`
		(src/blueprint_schema.luau CONTAINER_LAYOUT), so writing it dirties the root
		and moves every descendant's rect — a full arrange walk, identically
		provoked in every arm, on every container class. Using the root's padding
		rather than a leaf's size is what keeps the provocation constant while the
		SHAPE varies, which is the whole design of the comparison. ]]
	local function shapeTree(kind: string, pad: any, items: { any }): any
		local leaves = table.create(SHAPE_LEAVES)
		for i = 1, SHAPE_LEAVES do
			leaves[i] = leaf(i, kind, items[i])
		end
		-- the scroller `scroll` and `deepScroll` share. It owns the padding so the
		-- provocation stays on the outermost container in every arm.
		local function scroller(child: any): any
			return U.ScrollView({
				id = "Shape",
				axis = "y",
				padding = pad,
				width = { type = "fill", weight = 1 },
				height = { type = "fixed", px = math.max(100, viewportH()) },
				children = { child },
			})
		end
		if kind == "deep" or kind == "deepScroll" then
			-- LEAVES PER LEVEL, not one leaf per level: a chain of 240 single-child
			-- stacks would have 480 nodes against flat's 241 and the arms would no
			-- longer be comparable. 30 levels x 8 leaves is the same 240 leaves with
			-- 30 containers instead of 1, so `arrangedNodes` differs by 29 and depth
			-- differs by 29.
			local perLevel = SHAPE_LEAVES // SHAPE_DEPTH
			local inner: any = nil
			for level = SHAPE_DEPTH, 1, -1 do
				local children = table.create(perLevel + 1)
				for j = 1, perLevel do
					children[j] = leaves[(level - 1) * perLevel + j]
				end
				if inner ~= nil then
					table.insert(children, inner)
				end
				inner = U.VStack({
					id = `D{level}`,
					gap = 0,
					-- the outermost level owns the provocation UNLESS a scroller is
					-- wrapping it, in which case the scroller does
					padding = if level == 1 and kind == "deep" then pad else 0,
					width = { type = "fill", weight = 1 },
					children = children,
				})
			end
			return if kind == "deepScroll" then scroller(inner) else inner
		end
		if kind == "zstack" then
			return U.ZStack({ id = "Shape", padding = pad, children = leaves })
		end
		if kind == "wrap" then
			return U.HStack({
				id = "Shape",
				wrap = true,
				gap = 0,
				padding = pad,
				width = { type = "fill", weight = 1 },
				children = leaves,
			})
		end
		if kind == "scroll" then
			-- the FLAT tree, moved inside a scroller. The vstack below is byte-identical
			-- to the `flat` arm's root except that it no longer owns the padding.
			return scroller(
				U.VStack({ id = "Inner", gap = 0, width = { type = "fill", weight = 1 }, children = leaves })
			)
		end
		return U.VStack({
			id = "Shape",
			gap = 0,
			padding = pad,
			width = { type = "fill", weight = 1 },
			children = leaves,
		})
	end

	local function shapeArm(kind: string, payload: string?): any
		local _, REPS = framesAndReps(payload, 60, 24)
		local armScope = labScope:child(`shape-arm-{kind}`)
		-- OWNED AND DISPOSED. The pass loops under `Profile 1`, so an un-owned signal
		-- per lap is a leak the soak row would eventually report as a framework trend.
		local pad = armScope:own(core:signal(2))
		local items = dataset.build({ count = SHAPE_LEAVES, seed = settings.seed, content = "normal" })
		local handle = ctx.presenter.present(
			U.Screen({
				id = "ShapeArm",
				padding = 0,
				gap = 0,
				children = { shapeTree(kind, pad, items) },
			}),
			{
				recycleInstances = settings.recycle == true,
				-- INCREMENTAL LAYOUT IS OFF IN EVERY LEVER-1 ARM, and not because that is
				-- the lab default (it is). This workload's question is what a FULL arrange
				-- of a given shape costs; with the reuse path on, an arm whose rects happen
				-- not to move measures the skip instead of the walk, and the arms would no
				-- longer be comparing shapes. Lever 2 is where the reuse path is the
				-- subject, and it is hard-coded there too.
				incrementalLayout = false,
			}
		)

		local function finish()
			ctx.presenter.dismiss(handle)
			armScope:dispose()
		end

		local ok, result = pcall(function()
			ctx.presenter.refresh()
			local stats0 = if handle.controller ~= nil and handle.controller.stats ~= nil
				then handle.controller.stats()
				else nil
			--[[ THE ARM BUILT THE TREE IT SAYS IT DID. One typo in the `kind` chain
				above turns this whole workload into eight copies of `flat` that agree
				with each other beautifully — the "check that proves nothing" shape, in
				the workload whose entire subject is the difference between shapes. The
				solver's own arranged-node count is the oracle: every arm must arrange at
				least its leaves plus its root, and `deep` must arrange strictly more
				containers than `flat` does. ]]
			assert(
				stats0 ~= nil and stats0.lastArranged >= SHAPE_LEAVES,
				`[perf lab] shape arm '{kind}' arranged {tostring(if stats0 == nil then "nil" else stats0.lastArranged)} nodes for {SHAPE_LEAVES} leaves — the tree is not the one this arm declares`
			)

			local samples = {}
			local arrangeBefore = scopeCount("arrange")
			local measureBefore = scopeCount("measure")
			for i = 1, REPS do
				-- alternate so consecutive reps never write the same value: a signal
				-- set to what it already holds is not a dirty, and a rep that dirties
				-- nothing is a rep that measures nothing
				local next_ = if i % 2 == 0 then 2 else 3
				local t0 = clock()
				pad:set(next_)
				ctx.presenter.refresh()
				table.insert(samples, (clock() - t0) * 1000)
				-- OUTSIDE the timed region and unconditional: rule 3
				telemetry.step()
			end
			local arranges = scopeCount("arrange") - arrangeBefore
			local measures = scopeCount("measure") - measureBefore
			local stats = if handle.controller ~= nil and handle.controller.stats ~= nil
				then handle.controller.stats()
				else nil
			local arranged = if stats ~= nil then stats.lastArranged else 0
			local solveMs = summarize(samples)
			return {
				shape = kind,
				leaves = SHAPE_LEAVES,
				reps = REPS,
				-- the solver's own per-solve node counts, which are what make the
				-- headline a per-NODE number rather than a per-solve one
				arrangedNodes = arranged,
				measuredNodes = if stats ~= nil then stats.lastMeasured else 0,
				arrangePerRep = arranges / REPS,
				measurePerRep = measures / REPS,
				--[[ THE HEADLINE. Not comparable to a MicroProfiler `LuauUI/arrange`
					ms/occurrence — this is the WHOLE set+refresh round trip, which
					includes measure, commit and the adapter write. It is comparable
					ARM TO ARM, which is the only comparison this workload makes. ]]
				solveMs = solveMs,
				usPerArrangedNode = if solveMs.measured and arranged > 0 then solveMs.p50_ms * 1000 / arranged else 0,
				--[[ AND THE OTHER DENOMINATOR, because the first one is not always the
					right one and pretending otherwise would misread this workload's own
					headline finding. `arranged` counts nodes the arrange walk VISITED;
					`measured` counts calls to `solver.measure`, and arrange calls measure
					from a dozen sites. At depth 1 the two track each other (~3 measures
					per arranged node). At depth 30 they do not: `deep` arranges 271 nodes
					and measures 4 696 times, so a per-ARRANGED-node figure would report a
					17x measure fan-out as if it were expensive placement. Publish both and
					the ratio speaks for itself. ]]
				usPerMeasuredNode = if solveMs.measured
						and stats ~= nil
						and (stats.lastMeasured or 0) > 0
					then solveMs.p50_ms * 1000 / stats.lastMeasured
					else 0,
				measuresPerArrangedNode = if stats ~= nil and arranged > 0
					then (stats.lastMeasured or 0) / arranged
					else 0,
				--[[ REPORTED, AND IT IS NOT THE FLAG'S GUARD — measured, after the
					obvious claim turned out to be vacuous.

					Flipping `incrementalLayout` to `true` above leaves this at 0 anyway,
					because the provocation moves EVERY rect: the reuse path needs a
					byte-identical rect to skip a subtree, and a padding change of 1 px
					gives it none. So the full-arrange guarantee comes from the
					PROVOCATION, not from the flag, and a check reading this as a flag
					guard would be one of the "checks that prove nothing" this lab has
					collected. The flag stays hard-coded because it is free and honest;
					the load-bearing check is `arrangePerRep`, which is the one a mutation
					actually reddens. ]]
				partialSolves = if stats ~= nil then stats.partialSolves else 0,
			}
		end)
		finish()
		if not ok then
			error(result, 0)
		end
		return result
	end

	for _, kind in SHAPE_ARMS do
		-- `flatRepeat` is the A/A CONTROL: byte-identically the same arm as `flat`,
		-- run again. State the spread before any delta — five missions this week
		-- found apparent wins inside the noise band.
		local buildKind = if kind == "flatRepeat" then "flat" else kind
		passes[kind] = function(payload: string?)
			return timed(kind, function()
				local arm = shapeArm(buildKind, payload)
				arm.arm = kind
				arm.note = "One lap = ONE arm, so a 60-frame MicroProfiler window contains it whole. "
					.. "Read `flat` and `flatRepeat` FIRST: their difference is the harness spread, and "
					.. "any arm-to-arm delta smaller than it is noise. `usPerArrangedNode` is the "
					.. "comparable number; `solveMs` is the whole set+refresh round trip and is NOT a "
					.. "MicroProfiler arrange occurrence. Lune = regression signal, this lab under "
					.. "Studio = real engine, device = the only device claim."
				return arm
			end)
		end
	end

	-- ================================================================
	-- LEVER 2 — incremental layout on a collection edit
	-- ================================================================

	local function editArm(where: string, incremental: boolean, payload: string?): any
		local _, REPS = framesAndReps(payload, 60, 24)
		local armScope = labScope:child(`edit-arm-{where}-{tostring(incremental)}`)
		local base = dataset.build({ count = EDIT_ROWS, seed = settings.seed, content = "normal" })
		local armRows = armScope:own(core:signal(base))
		local listH = math.max(100, viewportH())
		local list = LuauUI.newVirtualList(LuauUI, core, {
			id = "EditRows",
			rows = armRows,
			key = function(item: any)
				return item.id
			end,
			itemExtent = 28,
			rowGap = 0,
			viewportHeight = listH,
			overscan = rows.OVERSCAN,
			cell = function(item: any)
				return U.VStack({
					id = "Row",
					padding = 4,
					gap = 2,
					width = { type = "fill", weight = 1 },
					children = {
						U.Text({ id = "N", text = item.name, textSize = 12, lineLimit = 1 }),
					},
				})
			end,
		})
		local handle =
			ctx.presenter.present(U.Screen({ id = "EditArm", padding = 0, gap = 0, children = { list.blueprint } }), {
				recycleInstances = settings.recycle == true,
				-- HARD-CODED PER ARM, not read from the selector. Two arms that both
				-- read `settings.incremental` are one arm measured twice.
				incrementalLayout = incremental,
			})
		local unbind: any = nil
		if list.bindNativeScroll ~= nil and handle.controller ~= nil then
			local okBind, bound = pcall(list.bindNativeScroll, handle.controller)
			if okBind then
				unbind = bound
			end
		end

		local function finish()
			if unbind ~= nil then
				unbind()
			end
			ctx.presenter.dismiss(handle)
			list.dispose()
			armScope:dispose()
		end

		local ok, result = pcall(function()
			ctx.presenter.refresh()
			local stats = function(): any
				if handle.controller == nil or handle.controller.stats == nil then
					return nil
				end
				return handle.controller.stats()
			end
			local s0 = stats()
			assert(s0 ~= nil, `[perf lab] edit arm '{where}' has no controller stats — nothing here is measurable`)

			local windowed = 0
			for _ in list.debugWindow() do
				windowed += 1
			end
			--[[ THE WINDOW MUST NOT HOLD THE COLLECTION. The whole premise of an
				off-window edit is that the edit lands where nothing is mounted; if the
				list ever materialises 2 000 rows this pass is measuring a completely
				different question and would still return a tidy number. ]]
			assert(
				windowed > 0 and windowed < EDIT_ROWS // 4,
				`[perf lab] edit arm '{where}' mounted {windowed} of {EDIT_ROWS} rows — not windowed, `
					.. "so an 'off-window' edit is not off any window"
			)

			local samples = {}
			local arrangeBefore = scopeCount("arrange")
			local mountBefore = scopeCount("mount")
			local measureBefore = scopeCount("measure")
			local partialBefore = s0.partialSolves
			for i = 1, REPS do
				local next_ = table.clone(armRows:get() :: { any })
				if where == "off" then
					-- ONE INSERT, ~475 rows below the last mounted row. The same
					-- arithmetic `collection-churn/insert` uses, at one per FRAME
					-- instead of 25 inside one.
					local added = table.clone(next_[1])
					added.id = `ins{i}`
					table.insert(next_, math.floor(#next_ * EDIT_OFF_WINDOW_FRACTION), added)
				else
					-- ONE MOUNTED ROW's value moves. Same collection length, same
					-- window, same keys — the cheapest real edit there is.
					local at = 1 + (i % math.max(1, windowed))
					local row = table.clone(next_[at])
					row.value = (row.value + 0.01) % 1
					next_[at] = row
				end
				local t0 = clock()
				armRows:set(next_)
				ctx.presenter.refresh()
				table.insert(samples, (clock() - t0) * 1000)
				telemetry.step()
			end
			local s1 = stats()
			local editMs = summarize(samples)
			local partials = (if s1 ~= nil then s1.partialSolves else partialBefore) - partialBefore
			--[[ THE NEGATIVE CONTROL, and it is the mutation tripwire for the whole
				A/B. An arm built with `incrementalLayout = false` cannot skip anything,
				so `partialSolves` MUST NOT move. If the flag stops being threaded
				through, the framework default is ON and this fires — before any number
				from this workload is quoted. The ON arm is deliberately NOT asserted the
				other way: "the reuse path never bit" is the FINDING L-27 recorded on a
				resize, not a failure, and asserting it away would delete the measurement. ]]
			if not incremental then
				assert(
					partials == 0,
					`[perf lab] edit arm '{where}' was built with incrementalLayout = false and still `
						.. `served {partials} partial solve(s) — the flag is not reaching the renderer, so the `
						.. "A/B is one configuration measured twice"
				)
			end
			return {
				edit = where,
				incremental = incremental,
				reps = REPS,
				logicalRows = #(armRows:get() :: { any }),
				mountedRows = windowed,
				editMs = editMs,
				arrangePerEdit = (scopeCount("arrange") - arrangeBefore) / REPS,
				measurePerEdit = (scopeCount("measure") - measureBefore) / REPS,
				--[[ THE OTHER HALF OF L-35's FINDING, kept as a field. `collection-churn`
					measured `LuauUI/mount` at exactly 0 across 29 device frames: 25 inserts
					~475 rows outside the window provoke NO structural sync. That half is
					healthy and this records it holding. ]]
				mountPerEdit = (scopeCount("mount") - mountBefore) / REPS,
				-- how often the reuse path bit, and how much it skipped when it did.
				-- ZERO on an incremental arm is L-27's finding reaching a second case,
				-- not an error.
				partialSolvesPerEdit = partials / REPS,
				lastSkipped = if s1 ~= nil then s1.lastSkipped else 0,
				arrangedNodes = if s1 ~= nil then s1.lastArranged else 0,
				measuredNodes = if s1 ~= nil then s1.lastMeasured else 0,
			}
		end)
		finish()
		if not ok then
			error(result, 0)
		end
		return result
	end

	local EDIT_SPEC: { [string]: { where: string, incremental: boolean } } = {
		editOffWindow = { where = "off", incremental = false },
		-- the A/A CONTROL: byte-identically `editOffWindow`, run again
		editOffWindowRepeat = { where = "off", incremental = false },
		editOffWindowIncremental = { where = "off", incremental = true },
		editInWindow = { where = "in", incremental = false },
		editInWindowIncremental = { where = "in", incremental = true },
	}
	for _, name in EDIT_ARMS do
		local spec = EDIT_SPEC[name]
		passes[name] = function(payload: string?)
			return timed(name, function()
				local arm = editArm(spec.where, spec.incremental, payload)
				arm.arm = name
				arm.note = "One edit per FRAME, not 25 inside one — `collection-churn/insert` priced a lap, "
					.. "this prices an edit. Read `editOffWindow` and `editOffWindowRepeat` FIRST: their "
					.. "difference is the harness spread and any delta smaller than it is noise. "
					.. "`partialSolvesPerEdit` on an incremental arm is the lever: 0 means the reuse path "
					.. "is inert on a collection edit exactly as L-27 found it on a resize, and that is a "
					.. "measurement, not a failure. Lune = regression signal, this lab under Studio = real "
					.. "engine, device = the only device claim."
				return arm
			end)
		end
	end
end

return levers
