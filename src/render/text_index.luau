--!strict
--[[ ── WHICH NODES A LEARNED WORD ACTUALLY MOVES ────────────────────────────────

	Plan C, T18-A (ruling L-10, L-11, L-12; T17's second finding; FacetBench §C16).

	THE DEFECT THIS FILE EXISTS FOR, measured rather than reasoned. A SETTLED session
	— the state a shipped game is in from ~0.66 s onward — paid a fully COLD
	whole-tree re-solve for every new word it learned. Live (T17, arm C, Studio Play
	with the production adapter): `battle_hud L setState` **39.676 ms** and
	`addItem-damage` **76.971 ms** against 3.733 / 3.994 with the headless target in
	the same VM, with `lastMeasured == lastMeasureCalls == 14,2xx` on 5,109 nodes.
	`lastMeasured == lastMeasureCalls` is the signature: every measure was a MISS.
	Reproduced HEADLESS at 14,215 on the same workload, so the pin needs no Studio.

	THERE WERE TWO CAUSES AND THE OBVIOUS ONE WAS THE SMALLER, which is why this file
	is a dirty-set producer and not an epoch:

	  1. `text_metrics`' generation was ONE process-global counter folded into
	     `measureStamp`, so one learned word dropped the measure memo of every node of
	     every attached surface. That is the cause the investigation named.
	  2. AND THE SETTLE RE-SOLVE HAD NO DIRTY SET AT ALL. `premeasure_round.luau`'s
	     `solveAndApply` and the `textMeasureEpoch` geometry fact's settle callback
	     (`renderer.luau:2704-2719`) both call the renderer's solve BARE, and
	     `dirtyContains`/`measureContains` are set only inside `refresh`. So
	     `solveOpts.reuse == nil`, and with no reuse set the cross-solve store is
	     CLEARED, the leaf serve is dead at its first term (`solver.luau:1609-1611`)
	     and the container memo is dead at its second (`stack_measure.luau:131-133`).
	     The renderer says so in its own words: "a feedback re-solve is not the
	     refresh that built them and takes a full solve, exactly as the re-entrant
	     text-measurement solve does".

	Removing (1) alone is worth NOTHING — no memo is consulted on a path where the
	store was just cleared. Measured, arm B of T18-A's step-0 differential. The lever
	is (2), and (1) is its necessary companion: with the word generation still in the
	stamp, `measure_reuse.restamp` clears the store and `node.mStamp ==
	ctx.measureStamp` fails for every node whatever the dirty set says.

	THE FOUR LINKS, ALL OR NOTHING.
	  (i)   a per-surface `(font,size) -> mounted text paths` index, populated at
	        MEASURE time and cleared at unmount — this file;
	  (ii)  on a learned word, each indexed path pushed as `class == "measure"` dirt.
	        The class is load-bearing: `dirty_closure.of` builds its measure half from
	        `entry.class == "measure"` ALONE (`render/dirty_closure.luau`), and an
	        `arrange`-class push would produce an EMPTY measure closure and serve
	        stale everywhere;
	  (iii) the re-solve routed through a path that COMPUTES and PASSES the two
	        closures — `renderer.luau`'s `solveAndApply` takes the plan from here;
	  (iv)  the word generation out of `measureStamp` (`render/measure_stamp`).

	WHY AT MEASURE TIME AND NOT AT MOUNT. The `(font,size)` a node measures under is
	not known at mount: it is resolved inside `solver`'s text branch from the theme
	snapshot, the typography role, `measureScale`, `prefOffset` and — for
	`textSize = "fit"` — the box itself. `render/layout_node`'s `textOf` cannot answer
	it either, and a node SERVED from the node store never re-runs `textOf` at all, so
	an index rebuilt per build would lose every entry under a served subtree. The
	entries here persist across served solves and are refreshed only when a node is
	actually re-measured under a different key, which is exactly right: a served node
	measured under the key it is still filed under.

	WHY PER SURFACE. Paths are per-surface — two attached surfaces have identical
	`/Root/...` strings — and the dirty push has to reach THAT controller's tree. So
	each `renderer.attach` owns one index and they are held in a module-level registry
	that `learned()` broadcasts to. That registry is what preserves the cross-surface
	reach the process-global epoch used to give for free: a busy screen teaching the
	measurer a width a quiet one draws still corrects the quiet one, because the quiet
	one's own index names its own paths. Once the word generation leaves the stamp,
	the `textMeasureEpoch` env fact alone no longer suffices — that surface's solve
	would legitimately serve — so this broadcast is not an optimisation, it is the
	correctness half.

	A STALE ENTRY IS COST; A MISSING ONE IS STALENESS. An entry for a path that has
	been unmounted pushes dirt for a node the tree no longer has, which is inert. A
	MISSING entry means a live node is never re-measured and keeps the estimator's
	box. The failure direction is therefore safe, and `forget` is still called from
	the renderer's one per-path removal sweep so a `ForEach` churning rows does not
	retain paths for the session.

	WHAT THE RENDERER DOES WITH `take`, since the argument does not fit in that file.
	The plan is spent in `renderer.attach`'s solve, ABOVE the layout build, and it does
	three things there:

	  * it fills `dirtyContains`/`measureContains`, which is the reuse set the solver
	    reads — link (iii);
	  * it does NOT touch `nodeDirty`. That was tried and MEASURED, and it is the one
	    place where the conservative direction was the wrong one: marking the push into
	    the layout-node store's dirty set forces a REBUILD of every pushed node and
	    every ancestor, and on the wide key (`battle_hud`'s 1,000 facing labels at size
	    10) that is ~2,000 rebuilds the parent SHA's cold solve never paid — its
	    `nodeDirty` was empty and every node was served. Live, arm C: the
	    `updateItem-facing` settle class read **62.986 ms** with the marks against
	    39.7 ms for the whole-tree cold solve they were meant to be cheaper than. What
	    the marks were protecting is `commit_walks`' prune, and that prune does not read
	    the dirty set alone — it asks `entryVerdict(child)` (settled / moved), so a node
	    whose rect moved is descended whether or not anything marked it. The residue is
	    a published VERDICT that changes without moving a rect; no fixture in the suite
	    produces one, deleting the marks reddened nothing, and the measurement is what
	    decided it.
	  * it CLEARS the pair afterwards. `refresh` and `resolveForFeedback` each clear it
	    in their own tails; a settle solve has no tail, so a push left standing would be
	    spent again by the next bare solve as a stale set. Two `textMeasureEpoch` writes
	    in a row is what found that.

	THE REFUSALS, and every one of them is a SUPERSET of the push rather than a
	weakening of it. `take(false)` DROPS the mark, because the solve that follows covers
	everything the push could have named:

	  * a MOVED STAMP — a viewport, inset, scale, theme or calibration change — has
	    already dropped the whole store, and nothing narrower than everything is honest
	    there. The push only ever names TEXT nodes, so spending it would leave every
	    other node at the rect the old viewport gave it.
	  * no `lastResult`, or incremental layout off, means there is nothing to reuse.
	  * ...and the push that names more than `cap` paths is NOT one of these: it comes
	    back as `full`, and the caller drops whatever closure it was holding. See THE
	    BUDGET at `take` for the route where returning `nil` there was a wrong box.

	A CLOSURE ALREADY SET IS A UNION, NOT A REFUSAL, and this is the one the live drive
	corrected. On the SHIPPED route the engine's settled branch answers INLINE, from
	inside the solve that asked, so `premeasure_round`'s `done` runs while `refresh`'s
	own closure is still standing and the re-solve is the re-entrant one. Refusing there
	looked safe — the refresh's dirt contains the node whose text just changed — but the
	(font,size)'s OTHER users are not in it, and they are exactly the nodes still
	showing the estimator's box. The push is therefore unioned into the caller's two
	sets: strictly wider than what the caller asked for, never narrower, and the caller
	still owns the tables (they are cleared by its own tail, not by this one).

	AN EMPTY PUSH IS A PLAN, NOT A REFUSAL, and the distinction is worth 39.9 ms. A
	width learned at a key no mounted node measured under names nobody; returning `nil`
	there would send the caller down the bare route and buy the full cold solve this
	file exists to remove. Measured while it did exactly that on `battle_hud L`: 39.865
	ms and 14,215 measures, the parent SHA's number to the digit, on the one case that
	should be free. With an empty closure it is **0.046 ms and 0 measures**.

	`textSize = "fit"` IS FILED CONSERVATIVELY, and this is the one place the key is
	not enough. A fit node's ladder measures its string at SEVERAL sizes inside the
	band (`layout/text_fit`) before choosing one, so a width learned at a size it
	merely PROBED can change which rung it lands on — while the key recorded here is
	the size it chose. Those nodes go into `always`, which joins every push. They are
	rare (an opt-in prop), and being wrong about them would be a wrong box on screen.

	── AND OVER THE CAP, THE LEAVES ARE PROBED BEFORE THE ANSWER IS `full` ─────────
	(Plan D, D3c; scout S2 §4b.)

	THE MISS THIS EXISTS FOR, live, settled, in a fresh client VM at D2/D3a:
	`battle_hud updateItem-facing [S]` **47.5 ms**, `war_room updateItem-power [S]`
	**70.4 ms** and `addItem-items [S]` **75.6 ms**, each with `lastMeasured ==
	lastMeasureCalls` (14,263 and 20,505) — the signature of a whole-tree COLD solve.
	A settled step that learns ONE new word at a key ~1,000 mounted labels share is
	over the cap above, `take` answers `full`, and the caller drops its closure. It is
	50 of `war_room`'s 600 settled steps.

	AND THE CAP IS RIGHT: D3b re-swept the crossover after D1 and D2 and the band did
	not move (~13-21 % of the tree). A push that names a third of the tree really is
	slower than the cold solve it replaces. So the lever is not the cap — it is the
	SIZE OF THE PUSH, and the observation that a token correction usually moves almost
	none of the labels filed under its key. `battle_hud`'s 1,000 facing labels draw
	360 distinct values; `war_room`'s 1,500 power labels draw 999. One learned word
	moves the two or three labels that draw it and provably nothing else.

	SO: BETWEEN `take` AND THE CLOSURE BUILD, EACH PUSHED LEAF IS RE-MEASURED, and
	only the ones whose box MOVED reach `dirty_closure.of`. It is right AND fast in
	the Plan D sense — every label drawing a corrected token is still re-solved,
	because a word is a TOKEN shared across labels and the probe asks each label
	itself, not the string that was written.

	WHAT MAKES THE DROP EXACT, and it is a restriction rather than an argument. The
	probe answers with `text_metrics.measure` at an UNBOUNDED offer, and compares
	against `node.mTextW` — the number the solver's own text branch cached from its
	last measure. That comparison is only sound when the offer cannot enter the
	answer, so it is taken ONLY for a node the renderer classified as one word
	(`node.singleLine == true`, `render/layout_node`'s `isSingleWord`):

	  * `wrapWidth` is `math.huge` for such a node, so the measure the solver took IS
	    the unbounded one and the probe reproduces it exactly, at every offer the node
	    was measured at this solve or any other — the two-offers-per-node problem
	    (`ctx.offers`) cannot arise;
	  * `lines` is 1 whatever `lineLimit` says and the line box is a function of
	    `size`/`lineHeight` alone, so the HEIGHT cannot move while the width does not;
	  * the published `truncated` verdict is `m.width > availW`, and the compact
	    ladder's rung is `natural.width > availW`, both with `availW` unchanged by a
	    word delivery — so an unchanged `m.width` cannot flip either. This is the
	    truncation-boundary case the brief asks for by name: a label sitting exactly
	    on the boundary has a CHANGED width (that is what put it there), so it is
	    pushed. The verdict cannot move while the width stands still;
	  * `m.width` is `ceil(widest)`, so a sub-pixel correction that the ceiling
	    absorbs moves nothing at all — no rect, no fact, no verdict.

	SO THE GATE IS A POSITIVE LIST, NOT A LIST OF REFUSALS (RED-TEAM C-1). The probe
	answers for a leaf the index has seen measured, that is not in the conservative
	`always` set, that the renderer classified as ONE WORD, and that declares NO
	COMPACT FORM. Everything else is pushed unconditionally, which is the same failure
	direction this file takes everywhere: `always` (the `fit` nodes), a wrapping or
	multi-word label (its measure is against a box its parent chose, and
	reconstructing that box outside the solve is the offer-versus-occupied trap the
	solver has had to be fixed for twice), ANY node carrying `compactText` — the
	ordinary ladder as well as `compactPrefer` — and any path whose node the index has
	not seen measured. A leaf the probe cannot answer for is a leaf that stays in the
	push.

	AND THE COMPACT RUNG IS THE ONE THAT WAS MISSING, which is worth naming because
	the enumeration used to name only its harmless half. `compactPrefer` returns before
	the cached measure at EVERY offer, so `mTextW` is never written and a nil kept the
	leaf. The ORDINARY ladder returns at the same place, but only once the box has
	shrunk — leaving `mTextW` holding the FULL label's width from an earlier measure at
	a width the full label fitted. The probe reproduces that stale number exactly, and
	D6c's word set (`wordsOf(node.text)`, the full label's tokens) never names the
	compact form's token either: a correction to the string the button is ACTUALLY
	DRAWING dropped it from both directions and left a published `truncated` verdict
	stale behind it.

	AN EMPTY MOVED SET IS AN EMPTY CLOSURE, not a refusal — the same plan a push at an
	unused key already produces, and worth 39.9 ms for the same reason. And a moved
	set that is STILL over the cap falls back to `full`, unchanged.

	THE COLLECTOR IS SUSPENDED ACROSS THE PROBE (`text_metrics.suspendCollect`). The
	probe measures labels the solve is about to SERVE; collecting their unknown words
	would make the surface ask the engine for widths it will not use, and
	`textRequests` is a published observable.
]]

local dirty_closure = require("./dirty_closure")
local text_metrics = require("../layout/text_metrics")

local text_index = {}

export type Plan = {
	--[[ TRUE when the push was over budget and the caller must take the WHOLE-TREE
		solve instead. `contains`/`measures` are nil there, and the caller has to DROP
		any closure it was already holding — see THE BUDGET at `take` for why a
		refusal that merely returns `nil` is not a superset on every route. ]]
	full: boolean,
	-- the arrange-and-measure closure and the measure half, exactly as
	-- `dirty_closure.of` builds them for a refresh. Nil when `full`.
	contains: { [string]: boolean }?,
	measures: { [string]: boolean }?,
	-- how many PATHS were pushed (not the closure size): the counter
	-- `stats.lastTextDirtyPaths` publishes, and the number this whole task is about.
	-- Over the cap it is the MOVED set, not the key's whole bucket (D3c).
	n: number,
	-- ...and how many leaves the probe re-measured to get there (`stats.lastTextProbe
	-- Measures`). 0 on every under-cap push, which is every push this file's first
	-- round was written for.
	probed: number,
	-- ...and the leaves the WORD INDEX answered for without one (Plan D, D6c). The
	-- pair sums to the population the probe serves, which is what says the narrowing
	-- answered the same question rather than a smaller one.
	skipped: number,
}

export type Index = {
	--[[ file `path` under the (font,size) it was just measured with. Called from the
		solver's text branch, on every measure of a text node, so the unchanged case
		is two hash reads and two comparisons and nothing else.

		`node` is the LAYOUT NODE LITERAL, held so the over-cap probe can re-measure
		this label without walking a tree to find it. Held by reference and replaced
		on every measure, so it is never the stale one: `render/layout_node.build`
		constructs a FRESH literal for every node in the ancestor-closed dirty set
		(the invariant D1's `mPlan` cache rests on), and a node that was not rebuilt
		was not written to. `forget` and `dispose` drop it with everything else. ]]
	record: (path: string, font: string, size: number, always: boolean, node: any) -> (),
	-- a path left the tree (the renderer's per-path removal sweep)
	forget: (path: string) -> (),
	-- take the pending push, or drop it. `narrow` false means the caller is about to
	-- take a FULL solve anyway, which covers everything a push would have named
	take: (narrow: boolean, cap: number) -> Plan?,
	--[[ ...AND SPEND IT ON THE CALLER'S TWO CLOSURES, which is `take` plus the whole
		own/union/full decision in one call. Returns `(contains, measures, owns, pushed)`:
		the two sets the solve should use, whether THIS call created them (so the caller
		knows to clear them — a settle solve has no tail of its own, and a caller's
		closure belongs to the caller), and how many paths were pushed.

		IT LIVES HERE RATHER THAN AT THE CALL SITE for a reason this repository states
		in its own ledger: `render/renderer.luau` is the capped file, 56 characters under
		the campaign's STOP when this round opened, and an argument this long cannot be
		paid for there. The decision is three lines of code and a page of why. ]]
	apply: (
		contains: { [string]: boolean }?,
		measures: { [string]: boolean }?,
		narrow: boolean,
		cap: number
	) -> ({ [string]: boolean }?, { [string]: boolean }?, boolean, number, number),
	-- INTERNAL, and named in the type only so the registry broadcast above can call
	-- it without an `any` cast: mark one `metricKey` as changed. Nothing outside this
	-- module calls it — `text_index.learned` is the seam.
	mark: (key: string) -> (),
	-- is anything waiting? (read before a solve decides how to spend it)
	pending: () -> boolean,
	--[[ INTERNAL, and named in the type for the same reason `mark` is: the leak
		instrument. It counts every per-path entry this index holds, across all six
		maps plus the key buckets, so "dispose gave everything back" is one number
		rather than six assertions that can each be forgotten separately — which is
		exactly how D6c's two new maps were left out of `dispose` (RED-TEAM C-5).
		Nothing in `src/` reads it. ]]
	census: () -> number,
	-- leave the registry: a surface that detaches must stop receiving broadcasts
	dispose: () -> (),
}

-- every attached surface's index. A LIST rather than a set so the broadcast order is
-- the attach order, which makes a two-surface spec deterministic.
local live: { Index } = {}

--[[ A word's exact width MOVED at this (font,size). Every live surface marks its own
	paths — see WHY PER SURFACE above.

	SUBSCRIBED AT THE SEAM, NOT AT THE CALLER. `text_metrics.setMeasured` is the one
	function that can change an exact width, and until this round every writer of it
	invalidated every surface's geometry for free through the process-global epoch.
	Registering here keeps that property for every writer — the premeasurement round,
	a Studio tool reloading a design system, a spec driving the store — rather than
	narrowing it to the one caller that happened to be in the Files list.

	IT RUNS BEFORE THE `textMeasureEpoch` WRITE that makes those surfaces solve
	(`render/premeasure_round`'s `learned` branch calls `setMeasured` first, then
	publishes), so the mark is already standing when their solves ask for it. ]]
text_metrics.onWordChanged(function(font: string, size: number, word: string)
	if #live == 0 then
		return
	end
	local key = text_metrics.metricKey(font, size)
	for _, index in live do
		index.mark(key, word)
	end
end)

-- how many surfaces are registered. The leak instrument: `attach`/`dispose` pairs
-- have to balance, and a spec that presents and dismisses a hundred screens can say
-- so in one number.
function text_index.liveCount(): number
	return #live
end

function text_index.new(): Index
	-- `path -> the (font,size) it is currently filed under`, split into two maps so
	-- the unchanged case allocates nothing and builds no key string
	local pathFont: { [string]: string } = {}
	local pathSize: { [string]: number } = {}
	-- ...and the layout node literal each path was last measured as, which is what
	-- the over-cap probe re-measures (see the header). Written on every measure,
	-- never read on the unchanged path.
	local pathNode: { [string]: any } = {}
	-- `metricKey -> { path: true }`
	local byKey: { [string]: { [string]: boolean } } = {}
	-- the conservative set: `textSize = "fit"` nodes, which join every push
	local always: { [string]: boolean } = {}
	--[[ ...AND THE WORDS EACH PATH DRAWS (Plan D, D6c), beside the string they were
		derived from so the unchanged case is one hash read and one compare — the same
		shape the (font,size) pair above already has, and the same reason: `record`
		runs once per text node per solve and the answer almost never moves.

		WHAT IT IS FOR. Over the cap, D3c re-measures every leaf filed under the
		corrected key to find the ones that MOVED — 1,000 measures on `battle_hud`'s
		facing labels, 1,464 on `war_room`'s. But a label can only move if it draws a
		word whose width changed, and that is a set membership rather than a measure.
		`nil` here means "this path's drawn string is not indexed" (a node with no
		`text`), and a nil is always a candidate: the narrowing may never turn a label
		the probe would have kept into one it drops. ]]
	local pathText: { [string]: string } = {}
	local pathWords: { [string]: { [string]: boolean } } = {}
	--[[ keys marked since the last `take`, each with the WORDS that moved under it
		(Plan D, D6c; keys alone before). A delivery that learns forty damage numbers
		at one size still costs ONE key entry here — the words are what the probe
		spends, and the paths are still expanded once, at the solve that spends them. ]]
	local marked: { [string]: { [string]: boolean } } = {}
	local anyMarked = false

	local index: any = {}

	local function detach(path: string)
		local font = pathFont[path]
		if font == nil then
			return
		end
		local bucket = byKey[text_metrics.metricKey(font, pathSize[path])]
		if bucket ~= nil then
			bucket[path] = nil
		end
	end

	--[[ THE DRAWN-WORD SET, RE-DERIVED ONLY WHEN THE STRING MOVES (D6c). `record`'s
		own guard returns on an unchanged (font,size), and a text change with the SAME
		pair is exactly the case that guard lets through — see its header — so this is
		asked on the unconditional side of it and compares the literal itself. ]]
	local function noteWords(path: string, node: any)
		local raw = if node ~= nil then node.text else nil
		--[[ A NUMBER IS TEXT TOO (Plan D, D6c live drive, 2026-09-07). Every HUD number
			— `battle_hud`'s 1,000 facing labels, `war_room`'s 1,500 power labels — reaches
			the solver as a NUMBER prop, and `text_metrics.measure` coerces it the way the
			engine draws it. The first draft accepted only strings, so on the arena every
			path fell through to the measure: live `probes=1000 skips=0` with ONE label
			drawing the announced word, while the string-text spec read `skips=991`.

			...AND THE GUARD COMPARES THE COERCED FORM, NOT THE RAW ONE (RED-TEAM C-9).
			It compared `node.text` and stored `node.text`, and `==` on Luau numbers is
			not injective with respect to `tostring`: `-0 == 0` is true while
			`tostring(-0)` is `"-0"`. A numeric label moving between `0` and `-0` kept a
			`pathWords` naming the token it no longer draws, and the over-cap probe then
			word-skipped it for a correction that DID move it. The derived set is
			`tostring`-based, so the key that guards it has to be too.

			IT COSTS ONE `tostring` PER NUMERIC LABEL PER MEASURE, stated rather than
			hidden: the unchanged case for a STRING label is still one hash read and one
			compare, and for a numeric one it is a coercion the solve is about to make
			anyway inside `text_metrics.measure`. Against the measure it replaces (D6c
			priced 1,000 probe measures at 0.439 ms and 1,000 lookups at 0.0186 ms) it is
			not a term. ]]
		local text = if type(raw) == "number" then tostring(raw) else raw
		if type(text) ~= "string" then
			pathText[path] = nil
			pathWords[path] = nil
			return
		end
		if pathText[path] == text then
			return
		end
		pathText[path] = text
		pathWords[path] = text_metrics.wordsOf(text)
	end

	--[[ THE PROBE LOOP, HOISTED SO ITS FAILURE GUARD COSTS NOTHING (RED-TEAM C-7).
		`take` suspends the word collector across this loop and hands it back after —
		and a THROW inside `text_metrics.measure` (a `node.text` that is a table, a
		torn `pathFont` entry) skipped the hand-back and left `collecting` nil for the
		REST OF THE SOLVE. Every word that solve would have collected was then dropped
		in silence with no counter moving, which is the exact failure mode this
		module's own doctrine ("the collector's own silence, made loud") exists to
		refuse.

		IT IS A NAMED UPVALUE RATHER THAN A CLOSURE PER PUSH so the `pcall` at the
		call site allocates nothing: one function per index, not one per correction.
		Returns the two counters rather than writing them, because a `pcall`'d call
		cannot assign to the caller's locals. ]]
	local function probeEntries(
		entries: { { path: string, class: string } },
		markedWords: { [string]: { [string]: boolean } },
		moved: { { path: string, class: string } }
	): (number, number)
		local probed = 0
		local skipped = 0
		for _, entry in entries do
			local path = entry.path
			local keep = true
			--[[ THE GATE IS A POSITIVE LIST OF WHAT THE PROBE CAN ANSWER (RED-TEAM
				C-1), rather than a growing list of refusals, and it had to become one
				because the ordinary COMPACT LADDER was missing from the list.

				`mTextW` is "the number the solver's own text branch cached from its
				last measure", and for a node DRAWING ITS COMPACT FORM that is false:
				the ladder returns (`layout/solver.luau`, the `compact ~= nil` arm)
				BEFORE `node.mTextW = m.width`, so the cache still holds the FULL
				label's width from an earlier measure at a width the full label fitted.
				The probe measures `node.text` — the full label again — reproduces the
				stale number exactly, and drops a leaf that is drawing something else
				entirely. D6c's word check drops it one step earlier and for the same
				reason: `pathWords` is `wordsOf(node.text)` and never names the compact
				form's token, so a correction to the COMPACT string could not reach it
				from either direction.

				`compactPrefer` was always safe, which is what hid it: a preferred form
				takes the branch at EVERY offer, so `mTextW` is never written and `was
				== nil` kept the leaf. `compactText ~= nil` refuses both rungs and needs
				no second test.

				THE `singleLine` TERM IS BELT AND IS RECORDED AS ONE (mutation M2, a
				kept null). `mTextW` is written only under that classification and a
				text change rebuilds the literal, so no node in the tree carries a
				cached width it no longer qualifies for and dropping the term reddens
				nothing. It is stated anyway because the probe's whole
				offer-independence argument is about the classification — asking for it
				costs one field read and makes the list say what it means. ]]
			local held = pathNode[path]
			local node = if held ~= nil
					and always[path] == nil
					and held.singleLine == true
					and held.compactText == nil
				then held
				else nil
			local was = if node ~= nil then node.mTextW else nil
			--[[ ...AND THE WORD ANSWERS IT WITHOUT A MEASURE, WHERE IT CAN (Plan D,
				D6c). A label's width is the sum of its own words' widths, so a label
				that draws NONE of the words this delivery corrected cannot have
				moved — and that is a set membership against the marked words, not a
				re-measure. It is asked HERE, inside the `was ~= nil` arm, and that
				placement is the whole safety argument: every node the probe already
				refused to answer for (a `fit` node, a wrapping or multi-word label, a
				node with a compact form, a path the index has never seen measured) is
				refused by the gate above or has no `mTextW`, and is kept exactly as
				before. This narrowing only
				ever replaces a MEASURE with a lookup on the population the measure
				already served, and it never turns a kept leaf into a dropped one on
				any other ground.

				`words` is the marked set of THIS path's key (usually one word — a
				delivery corrects one token at a time) and `drawn` is what the label
				asks about, so the loop is over the smaller side by construction. A
				path with no `drawn` set (no `text` on the node) or no `words` (it
				joined through `always`) falls through to the measure. ]]
			if was ~= nil then
				local words = markedWords[path]
				local drawn = pathWords[path]
				if words ~= nil and drawn ~= nil then
					local draws = false
					for word in words do
						if drawn[word] then
							draws = true
							break
						end
					end
					if not draws then
						was = nil
						keep = false
						skipped += 1
					end
				end
			end
			if was ~= nil then
				probed += 1
				-- UNBOUNDED, and with no `lineHeight` or `lineLimit`: neither can
				-- reach `width` (the line box is a function of the size, and a
				-- one-word string wraps to one line at any cap), and this node is
				-- one word or it would have no cached width to compare against.
				local now = text_metrics.measure(node.text or "", pathFont[path], pathSize[path], math.huge)
				keep = now.width ~= was
			end
			if keep then
				table.insert(moved, entry)
			end
		end
		return probed, skipped
	end

	function index.record(path: string, font: string, size: number, alwaysDirty: boolean, node: any)
		-- BEFORE the unchanged guard, and unconditionally: the (font,size) can stand
		-- still across a rebuild while the literal underneath it is replaced, and the
		-- probe re-measures THIS solve's node or nothing. A bare write, not a
		-- compare-then-write — one hash store against one hash load plus a branch.
		pathNode[path] = node
		-- ...and so is the drawn-word set, for the same reason and on the same side of
		-- the guard: the pair can stand still while the literal under it is replaced
		noteWords(path, node)
		if pathFont[path] == font and pathSize[path] == size and always[path] == (alwaysDirty or nil) then
			return
		end
		detach(path)
		pathFont[path] = font
		pathSize[path] = size
		always[path] = if alwaysDirty then true else nil
		local key = text_metrics.metricKey(font, size)
		local bucket = byKey[key]
		if bucket == nil then
			bucket = {}
			byKey[key] = bucket
		end
		bucket[path] = true
	end

	function index.forget(path: string)
		detach(path)
		pathFont[path] = nil
		pathSize[path] = nil
		pathNode[path] = nil
		always[path] = nil
		pathText[path] = nil
		pathWords[path] = nil
	end

	function index.mark(key: string, word: string)
		local words = marked[key]
		if words == nil then
			words = {}
			marked[key] = words
		end
		words[word] = true
		anyMarked = true
	end

	function index.pending(): boolean
		return anyMarked
	end

	-- see the type: every per-path entry this index is holding, as ONE number
	function index.census(): number
		local n = 0
		for _, map in { pathFont, pathSize, pathNode, pathText, pathWords, always, byKey } do
			for _ in map :: any do
				n += 1
			end
		end
		return n
	end

	function index.take(narrow: boolean, cap: number): Plan?
		if not anyMarked then
			return nil
		end
		--[[ DROPPED, NOT KEPT, when the caller is not narrowing. Every route into this
			function is a solve that is about to happen: if it is a FULL one it
			re-measures everything a push could have named, and holding the mark would
			buy a second solve for work already done; if it is an incremental one the
			caller refused to narrow because something WIDER is already in play (a
			moved stamp drops the whole store; a refresh's own closure is the dirt this
			frame, and the settle write that produced this mark is inside it). Both are
			supersets on the measure axis, which is the only axis this push carries. ]]
		local keys = marked
		marked = {}
		anyMarked = false
		if not narrow then
			return nil
		end
		--[[ ONE ENTRY PER PATH, `class = "measure"`. The class is the whole contract
			with `dirty_closure.of`: it fills the measure half from measure entries
			ALONE, and an `arrange` push here would hand the solver an empty measure
			closure — every container above the corrected label serving its stale
			slate while the arrange pass dutifully re-placed it at the old size. ]]
		local entries: { { path: string, class: string } } = {}
		local pushed: { [string]: boolean } = {}
		local function push(path: string)
			if not pushed[path] then
				pushed[path] = true
				table.insert(entries, { path = path, class = "measure" })
			end
		end
		--[[ ...AND EACH PUSHED PATH REMEMBERS THE WORDS ITS OWN KEY MARKED (Plan D,
			D6c). One path belongs to one key, so this is a write per push and not a
			join; the probe below reads it to ask "does this label draw any of them"
			before it re-measures anything. A path that reaches `entries` any OTHER way
			(the `always` set) has no entry here, and a nil is a candidate. ]]
		local markedWords: { [string]: { [string]: boolean } } = {}
		for key, words in keys do
			local bucket = byKey[key]
			if bucket ~= nil then
				for path in bucket do
					push(path)
					markedWords[path] = words
				end
			end
		end
		-- ...AND THE CONSERVATIVE SET, on every push: a `textSize = "fit"` node
		-- measured its string at sizes it merely PROBED (see the header)
		for path in always do
			push(path)
		end
		--[[ AN EMPTY PUSH IS A PLAN, NOT A REFUSAL, and this is the difference between
			"the narrowing works" and "the narrowing works when it has something to
			say". A width learned at a (font,size) NO MOUNTED NODE MEASURED UNDER names
			nobody — and returning `nil` here would send the caller down the bare route,
			where `dirtyContains == nil` buys the full cold solve this whole task exists
			to remove. Measured on `battle_hud L` while this returned `nil`: a word at
			an unused key still cost 39.9 ms and 14,215 measures, the parent SHA's
			number exactly, on the one case that should be free.

			An EMPTY closure is the honest answer: nothing is dirty, so the solve
			replays every subtree and re-publishes every channel from the previous
			result. The env fact still bumps, so a consumer memo that read
			`Facet.text.measure` still re-derives. ]]
		--[[ ...AND A BUDGET, MEASURED RATHER THAN ASSUMED. A push that names a large
			FRACTION of the tree is not a narrowing: its ancestor closure reaches the
			root, every container on the way down refuses its memo, and the solve ends
			up doing the whole tree's work PLUS the closure's. Live, arm C,
			`battle_hud L`'s `updateItem-facing` — 1,000 labels sharing one
			(font,size) — read **55.709 ms** with the push against **~39.7 ms** for the
			whole-tree cold solve it replaced, at 14,174 measure CALLS against the cold
			solve's 14,215.

			THE CUTOFF IS NOW SWEPT RATHER THAN BRACKETED (fix round 1, FacetBench §C16).
			A scene that holds the tree still — 3,002 nodes, always — and moves only how
			many text nodes share the changed key, push arm against forced-full arm, two
			runs of 5 and 7 reps:

			    users   % of tree   PUSH ms        FULL ms        verdict
			       50        1.7    7.9 /  8.2    21.0 / 22.6    push wins ~2.7x
			      200        6.7   10.6 / 14.6    20.8 / 20.9    push wins 1.4-2.0x
			      400       13.3   13.5 / 17.5    17.2 / 21.7    a coin flip
			      638       21.3   19.0 / 23.3    18.5 / 20.5    full wins
			    1,000       33.3   30.1 / 31.9    16.9 / 17.2    full wins ~1.9x

			The crossover is a BAND between roughly 7 % and 13 % of the tree, not a
			point, and `lastLayoutNodes // 8` is 12.5 % — the top of that band, where a
			refusal costs at worst a wash and never the 1.9x the far end costs. That is
			why the cap stayed where it was: the sweep vindicated the fraction rather
			than replacing it. `battle_hud`'s own wide key cannot answer this question at
			all — its 1,000 labels are always ~20 % of its 5,106 nodes, so scaling the
			workload scales both together and the ratio never moves.

			IT READS THE PREVIOUS SOLVE'S `lastLayoutNodes`, which is 0 on a first solve
			and therefore the `max(64, ...)` floor. Benign by construction: a surface
			with no previous solve has `lastResult == nil`, so `narrow` is false and no
			push is built for the cap to judge.

			▲ AND OVER THE CAP THE ANSWER IS `full`, NOT `nil`, WHICH IS A CORRECTION.
			This returned `nil` and both this file and T18-A's report claimed the
			fallback was "the full solve the parent SHA took". That is true on the BARE
			route, where `dirtyContains` is already nil. It was FALSE on the INLINE
			route — the one that ships, where a caller closure is standing — and there
			the mark was consumed, the push discarded, and the solve stayed NARROW:
			measured `cap=76 pushed=0 measured=4 arranged=5 nodes=614`, with the key's
			other users left on the estimator's box and nothing to repair them later.
			A word is a TOKEN, not a label — `text_metrics.measure` sums per word — so
			two labels sharing no string still share words, and a correction to one of
			them moves every node that draws it while only the written node is in the
			refresh's dirt. `full` makes the caller drop its closure, which is what the
			claim always said. `tests/text_settle_closure.spec.luau`'s over-budget
			inline case is the witness, and it reddens on both halves.

			The classes this task exists for are nowhere near the cap: 4 paths of 5,106
			nodes on `setState` and 45 on `addItem-damage`, against a cap of 638. ]]
		local probed = 0
		local skipped = 0
		if #entries > cap then
			--[[ ...AND OVER THE CAP, THE LEAVES ARE ASKED BEFORE THE TREE IS (Plan D,
				D3c). The header owns the whole argument — which leaves can be asked,
				why an unchanged unbounded width is EXACT rather than likely, and why a
				leaf the probe cannot answer for stays in the push. Three shapes come out
				of this loop: a MOVED set under the cap (the point — a narrow push where
				there was a whole-tree cold solve), an EMPTY one (already a plan, not a
				refusal), and a moved set still over the cap, which falls back to `full`
				exactly as before.

				THE COLLECTOR IS HANDED OVER AND HANDED BACK across the loop rather than
				re-begun: `beginCollect` discards, and the solve that called us has words
				in it. ]]
			local held = text_metrics.suspendCollect()
			local moved: { { path: string, class: string } } = {}
			--[[ ...AND THE COLLECTOR IS HANDED BACK WHATEVER HAPPENS (RED-TEAM C-7). See
				`probeEntries` for why a throw here is not this loop's to swallow: the error is
				re-raised at level 0 so the message is the measure's own, and the only thing
				this adds is that the solve still has a collector when it unwinds. ]]
			local ok, a, b = pcall(probeEntries, entries, markedWords, moved)
			text_metrics.resumeCollect(held)
			if not ok then
				error(a, 0)
			end
			probed = a :: number
			skipped = b :: number
			if #moved > cap then
				return { full = true, contains = nil, measures = nil, n = 0, probed = probed, skipped = skipped }
			end
			entries = moved
		end
		local contains, measures = dirty_closure.of(entries)
		return {
			full = false,
			contains = contains,
			measures = measures,
			n = #entries,
			probed = probed,
			skipped = skipped,
		}
	end

	--[[ THE THREE OUTCOMES, and every one of them is a SUPERSET of the push rather than
		a weakening of it.

		  * NO CLOSURE STANDING (a bare settle solve — `premeasure_round`'s own
		    `solveAndApply`, or the `textMeasureEpoch` geometry fact's settle callback):
		    the push IS the closure, and the caller is told it owns it.
		  * A CLOSURE STANDING (a `refresh` whose INLINE delivery produced the mark —
		    the route that ships): the push is UNIONED in. The delivery's users are not
		    all inside the dirt that produced them; a word is a TOKEN, not a label, so
		    two rows sharing no string still share words.
		  * OVER BUDGET: the caller's closure is DROPPED and the solve is the whole-tree
		    one. See THE BUDGET at `take` for the wrong box that came of returning `nil`
		    here instead. ]]
	function index.apply(
		contains: { [string]: boolean }?,
		measures: { [string]: boolean }?,
		narrow: boolean,
		cap: number
	): ({ [string]: boolean }?, { [string]: boolean }?, boolean, number, number, number)
		local plan = index.take(narrow, cap)
		if plan == nil then
			return contains, measures, false, 0, 0, 0
		end
		if plan.full then
			return nil, nil, false, 0, plan.probed, plan.skipped
		end
		local pushC = plan.contains :: { [string]: boolean }
		local pushM = plan.measures :: { [string]: boolean }
		if contains == nil then
			return pushC, pushM, true, plan.n, plan.probed, plan.skipped
		end
		local intoM = (measures or contains) :: { [string]: boolean }
		for path in pushM do
			intoM[path] = true
		end
		for path in pushC do
			(contains :: { [string]: boolean })[path] = true
		end
		return contains, measures, false, plan.n, plan.probed, plan.skipped
	end

	table.insert(live, index)

	function index.dispose()
		for i, other in live do
			if other == index then
				table.remove(live, i)
				break
			end
		end
		table.clear(byKey)
		table.clear(pathFont)
		table.clear(pathSize)
		table.clear(pathNode)
		table.clear(always)
		-- ...AND D6c'S TWO MAPS (RED-TEAM C-5). `forget` was updated for both when they
		-- landed and `dispose` was not, so a disposed controller still referenced from
		-- anywhere — a presenter holding a torn-down surface, a Studio module reload —
		-- retained one string and one word set per text path it had ever measured.
		table.clear(pathText)
		table.clear(pathWords)
		marked = {}
		anyMarked = false
	end

	return index :: Index
end

return text_index
