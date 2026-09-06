--!strict
--[[ ── THE SOLVE TRAMPOLINE ────────────────────────────────────────────────────

	A re-solve asked for WHILE A SOLVE IS ON THE STACK is QUEUED, and the outermost
	solve drains the queue with a LOOP — in the same frame, with no `task.wait` and
	no `task.defer`. Plan C, T18-B (ruling L-13), from T17's third finding.

	WHY IT EXISTS. The text-premeasurement answer is synchronous on a settled
	session: `client/text_premeasure.spawn` is `task.spawn`, which runs its body
	until its first yield, and `measureBatch`'s `GetTextBoundsAsync` does not yield
	once the font is loaded. So

	  `text_premeasure.measure` -> `spawn` -> `deliver` -> `render/premeasure_round`'s
	  `done` -> `solveAndApply` -> the solve -> `premeasure_round.request` -> `measure`

	was ONE C stack, one frame deeper per word the cascade learned. Measured live
	(T17, FacetBench §C15/§C16b): `sync=1` on a one-step drive, `maxNestDepth` 3 on
	the two-workload / 200-sample configuration, and a run printing `C stack
	overflow (when calling anonymous function on line 484 in ...text_premeasure)`
	followed by a script timeout. `textInFlight` bounds ONE surface's ONE vocabulary
	— the same word cannot be asked twice — but not a cycle in which each re-solve
	discovers a DIFFERENT word, and it is per surface, so two attached surfaces
	drive each other through the global text epoch. Headless,
	`tests/text_round_reentry.spec.luau` reads 12 Luau frames for a one-link settle
	against 70 for an eight-link two-workload cycle: a whole solve per link.

	WHAT THIS IS NOT, and it is the whole design. It is NOT a defer. A `wait(0)`
	before the delivery would move the settled rect a FRAME later — a visible text
	pop on every damage number, score and timer readout of a settled session — and
	would make each correction an outermost solve of its own. The loop keeps the
	answer on the frame that asked for it and keeps the solve count exactly what it
	was: one per learned round, `solves = 2` in one frame for the ordinary settle.

	THE TAIL RUNS AFTER THE DRAIN, ONCE PER COMPLETED SOLVE, AND THAT IS THE HALF
	THIS MODULE EXISTS FOR (fix round 1, review Important 2). Under the recursion
	the nested solve COMPLETED INSIDE the outer one, so everything the outer solve
	did after asking — its notification, and the drag bridge's drop-target refresh —
	ran against the CORRECTED rects. `notifySolved` fires once per solve either way
	(the `notifyingSolved` latch guards a listener that publishes back into a solve,
	not this cycle; measured at the parent SHA, `notifies == solves == 5` on a
	four-link chain), so the count was never the risk. THE GEOMETRY EACH CALL SEES
	WAS. A drain placed where the recursion was — inside `render/premeasure_round`,
	after the adapter's answer returns — bounds the stack just as well and breaks
	that: the tail of solve k would run before the chain's next solve, and on the
	ORDINARY one-word settle that is one `refreshTargets` against pre-correction
	rects, which re-runs the hover and fires the PUBLIC `UI.dropTarget`
	`onEnter`/`onLeave`/`onPredict` and republishes the public `verdict`
	(`input/drag_registry.luau` -> `input/drag_session.luau`) for a hover no frame
	ever showed. So the loop counts its completed solves and runs that many tails
	after the last one, all against the finished tree: same count, same geometry,
	same frame.

	AND A DRAINED SOLVE'S THROW IS ABSORBED, because the recursion absorbed it
	(fix round 1, review Important 1). The shipped adapter delivers inside
	`task.spawn` (`client/screen_target.luau` -> `client/text_premeasure.luau`), and
	`task.spawn` runs its body on a NEW THREAD: an error in the nested solve died at
	that boundary, was reported by the scheduler, and the outer solve finished and
	notified. Measured across the two worktrees with a coroutine-delivering adapter
	and an engine write armed to throw on the second solve: base `initialRender()`
	returned normally with ONE `onSolved`; the first form of this module raised out
	of `refresh()` with NONE — for a frame that DID paint, which can leave a
	consumer gated on `onSolved` (the presenter's no-pop text reveal) never
	revealing. So a drained solve's error is reported and the loop carries on; only
	the OUTERMOST solve, which the recursion ran on the caller's own stack, still
	unwinds its caller.

	AND BOTH EXITS PAY WHAT THE DRAIN OWES. The round cap below is a diagnostic
	about the round that would come NEXT; the rounds already finished DID paint, so
	their tails run before it exits. And the outermost solve's error carries the
	stack it was raised on rather than a bare message — see `annotate`.

	AND THE CAP DEFERS RATHER THAN THROWS (ruling C-3, from the live failure in
	FacetBench §8). A cap that RAISED made a slow boot window a hard error out of
	`refresh()`: `battle_hud facet` at 120 samples, in a fresh client VM, mounted and
	driven with no settle wait, took NINE text-measure batches on one `updateItem`
	step and died on a cap of eight. Nothing was wrong with that drain except that it
	was not FINISHED — the cap below records what it actually was, measured word by
	word — and a diagnostic about the round that has not run yet is no reason to
	throw away the frame that did. So the cap stops the loop, leaves the re-solve
	QUEUED, reports once and returns: the frame keeps the rounds it ran, every
	completed solve's tail runs, the surface still reads NOT SETTLED, and nothing
	raises.

	AND THE DEFERRAL OWNS ITS RE-ARMING (fix round 2, review F1/F2). `owed` is the
	round's only carrier and it is PASSIVE — this module cannot schedule anything, it
	has no requires by design — so the round is spent by whatever solves NEXT, and the
	first form of this shipped that as a HOPE about the caller. It was not true of the
	caller that matters. `renderer.initialRender()` drains the dirty queue right after
	its solve ("initial mount noise is not an update"), and with a round deferred that
	dirt IS the build the deferred round never ran: `refresh` then found an empty
	queue, solved nothing, and — because it also marks that dirt CLASSIFIED
	(`nodeDirtySeen = root.dirtySeq()`) — even a forced solve served a stale layout
	node still holding the previous word. Measured at `bec8e935` on a 40-word chain:
	`initialRender()` and then twenty ordinary refreshes ran ZERO further solves and
	ZERO further batches, the epoch frozen at 17, a 24-character word inside the
	138 px box word 17 earned. Silent permanent clipping where the parent commit had a
	loud throw, on every surface a presenter mounts.

	SO THE STATE IS EXPORTED: `trampoline` returns the entry point AND `owed()`, and
	the renderer asks it in the four places a deferral has to survive — the frame
	entry point solves when a round is owed whatever the dirty queue says,
	`controller.textPending()` ORs it in (a surface that owes a round is NOT settled,
	on every adapter shape: the boot window's still-in-flight words are the special
	case, not the general one), `initialRender` does not drain dirt while a round is
	owed, and `refresh` does not MARK dirt classified while one is (below). The first
	two are the ruling; the other two are what the measurements added to it, and they
	are the ones that carry the WORK rather than the intent.

	AND A SOLVE THAT MAKES NO PROGRESS MUST NOT RETIRE THE ROUND (fix round 3, review
	F1-b). Reader 1 above forces a solve; it does not, by itself, force that solve to
	DO anything. `renderer.refresh` writes `nodeDirtySeen = root.dirtySeq()` before it
	scans the queue — the claim "everything dirtied so far is classified into
	`nodeDirty`" — and on an EMPTY queue that claim is a lie whenever anything else
	drained it: nothing is classified, `nodeDirty` stays `{}`, `layout_node.build`
	serves every node from the store, and the forced solve measures a tree still
	holding the PREVIOUS word. The drain nevertheless spends the carried-in round, so
	`owed` clears and `textPending()` flips back to FALSE — F2's defect, restored by
	F1's fix, one frame later. Measured on `tests/text_round_reentry.spec.luau`'s
	48-word chain with the queue drained after the deferral: `solves 20 -> 22`, epoch
	FROZEN at 19, `pending false`, and the box 150 px around a word that needs 324.
	STRICTLY WORSE than not forcing the solve at all, which strands the surface LOUDLY
	with the presenter's reveal deadline as the escape hatch.

	AND THE NARROWING WAS NOT THE CAUSE, which is worth stating because it is the
	obvious remedy and it was measured to do nothing: making that solve UNNARROWED on
	the owed arm (`dirtyContains, measureContains = nil, nil`) left the same drive at
	`solves 22`, epoch 19, `w 150`, byte for byte the stranded reading — the closure
	is not what serves a stale node, and `render/text_index` unions the text-dirty
	paths into an empty one anyway. Withholding the MARK is the fix: `solveAndApply`'s
	own sequence test then takes the full arm and re-marks it, and the owed round runs
	as the drain's own round would have. The empty queue is production's shape, not a
	contrivance — a learned width changes no node's props on a static-text surface, so
	a full premeasure learn moves `root.dirtySeq()` by ZERO there.

	WHAT IT IS STILL NOT is a promise about a surface that trips the cap and then
	never renders again; that one carries its owed round until something solves, and a
	surface no frame reaches has no frame to clip. Measured live: the failing step
	deferred, and the next drive step drained another full cap from where it stopped.

	ONE SOLVE ON THE STACK AT A TIME is the property, and the queue is a BOOLEAN
	rather than a list because the re-solve carries no argument: it is "solve
	again", and two of them asked for during one body are one solve, exactly as
	they were when the second re-entered the first.
	`tests/text_round_reentry.spec.luau` pins the stack, the depth, the solve count,
	the tail count, the public drop-target callbacks' geometry, the absorbed throw,
	the round cap and the rects.

	NO REQUIRES and nothing about the renderer in it. The one module-level name is
	the reporting seam below, which is `client/text_premeasure.spawn`'s idiom for
	exactly this reason: a spec that deliberately drives the absorb must be able to
	ASSERT the report fired instead of printing past the suite's own PASS/FAIL
	lines.
]]

local solve_queue = {}

--[[ THE ROUND CAP, which is the `renderer.luau` `SOLVE_FEEDBACK_ROUND_CAP` IDIOM and
	no longer its reasoning (fix round 2, review F6). That cap still RAISES out of
	`refresh`, which is the failure class ruling C-3 exists to remove; it is a
	different loop with a different cause (a consumer publishing a layout prop derived
	from the rect that prop moves, which is a bug in the consumer and converges or
	does not) and it is BOOKED rather than changed here — see the Plan D goal. What
	the two share is the shape: a loop bounded by a constant because the invariant
	that really terminates it lives three modules away.

	The drain terminates on its own because a surface's vocabulary is
	finite — `render/premeasure_round`'s `textInFlight` refuses a word twice and
	`layout/text_metrics`' `setMeasured`/`markUnmeasurable` are permanent — but
	"terminates because of an invariant three modules away" is exactly the argument
	that used to end in a `C stack overflow`. Without a cap a pathological drain is
	now a NON-YIELDING HANG, which is strictly harder to diagnose than the crash it
	replaced.

	THE NUMBER IS MEASURED, AND THE MEASUREMENT REFUTED WHAT THE CAP WAS FOR
	(ruling C-3). At 8 it was read off the suite alone — the deepest drain in the
	Facet suite, the Rascal Rally suite and the example places is 4 rounds (the
	four-link chain fixture), and every shipped settle is 1. Live, on the workload
	that broke it (FacetBench `battle_hud` size L, 1,000 rows, driven from a cold
	mount with no settle wait), the drain at the failing step does not converge in 8
	rounds, or in 64, or in 192 — and the reason is not an adapter that answers
	badly. Recorded batch by batch at step 118, with the target's own
	`measureTextWidths` wrapped:

	  #1 n=1 "744"  #2 n=1 "724"  #3 n=1 "725"  #4 n=1 "726"  ...  #65 n=1 "786"

	ONE WORD PER ROUND, walking the row numbers in order. This drain is not a cycle;
	it is the surface learning a 1,000-row VOCABULARY one row at a time, because
	each learned width moves the boxes enough to bring the next unmeasured row into
	the measured set. It terminates on the invariant this block already names — the
	vocabulary is finite — but the bound IS THE VOCABULARY, not a small constant, so
	no cap "the boot window cannot reach" exists to be chosen. A cap of 64 on that
	step is a 3.4-SECOND FRAME (measured, 65 solves at ~52 ms) and it is no closer to
	converging at the end of it.

	SO THE CAP IS A FRAME BUDGET, and the deferral above is what makes that sound: a
	trip costs a frame, not a session, and the next frame carries on from here. The
	number is 4x the deepest drain that actually CONVERGES anywhere it has been
	measured — 4 rounds in the Facet suite, 3 on `war_room_inventory` L and 2 on
	`battle_hud` L headless (`FacetBench tools/profile/drain_rounds`, inline
	boot-window answers, 600 steps) — which keeps every converging settle whole and
	keeps the pathological one's frame at ~890 ms (`stepP95`, the live table for this
	ruling) instead of 3.4 s on the most extreme scene in the arena. Bigger buys
	nothing (the walk is not converging at any of these numbers); smaller starts
	costing frames a real settle needs.

	AND THE REAL LEVER IS UPSTREAM, BOOKED (fix round 2, review F4). A cap counted in
	ROUNDS is not a millisecond budget: a round costs ~0.05 ms on a small surface and
	~52 ms on the scene this number was tuned against. A wall-clock budget was
	considered and REFUSED for this round — it would make round counts
	machine-dependent and move the converging-settle observables on an L scene (4
	rounds x ~52 ms) — because the cost is not really the cap's to fix. The walk is one
	word per round BECAUSE each learned width brings the next unmeasured row into the
	measured set; batching the surface's whole unmeasured vocabulary into one round
	removes the walk instead of rationing it, and that is step 2 of the Plan D goal
	(`docs/plans/2026-09-06-facet-parity-D-goal.md`). ]]
local SOLVE_DRAIN_ROUND_CAP = 16

--[[ WHERE AN ABSORBED SOLVE'S ERROR GOES. Default is the engine's own `warn`,
	which is the channel `core/custom.luau`'s `fail` already uses for every
	quarantined write in this framework ("a silent quarantine heals the STATE and
	tells nobody"). Replaceable for the reason `client/text_premeasure`'s scheduler
	seam is: a spec driving this path asserts the report rather than printing
	through the suite. ]]
function solve_queue.report(message: string)
	warn(message)
end

--[[ THE STACK IS THE ERROR'S ONLY WITNESS, and a `pcall` throws it away. Under the
	recursion this trampoline replaced, an error inside `solveAndApply` propagated
	NATIVELY and the caller's crash report named the line that raised it; catching
	it here and re-raising the message alone would make every framework crash from
	a shipped surface point at this file and nowhere else. A message handler runs
	on the ERRORING stack, before it unwinds, which is the one place the frames
	still exist — `level = 2` starts the trace at the frame that raised rather than
	at this function.

	A NON-STRING ERROR IS PASSED THROUGH UNTOUCHED: `error({ ... })` is a value a
	consumer may be catching and matching on, and `debug.traceback` takes a string
	message. Annotating it would change what the caller receives; losing the trace
	for that case is the smaller harm and the one this framework's own
	`core/custom` quarantine already accepts. ]]
local function annotate(err: any): any
	if type(err) == "string" then
		return debug.traceback(err, 2)
	end
	return err
end

export type Deps = {
	-- one solve: the renderer's whole solve-and-apply body, minus its tail
	solve: () -> (),
	-- what the recursion ran after a solve COMPLETED — the drop-target refresh and
	-- "this surface finished solving". Fired once per completed solve, after the
	-- drain, so every one of them sees the final tree
	tail: () -> (),
	--[[ WHICH SURFACE THIS IS, for the one line a cap trip prints (fix round 2, review
		F5). The latch below is per surface and correctly so, which means N surfaces in
		trouble print N identical lines; without a name in them the count is
		uninformative and a live rig cannot tell which tree to look at. ]]
	id: string?,
	--[[ ...AND THE SAME FACT AS A NUMBER (fix round 2, review F8). The line is a
		diagnostic for a human; this is the one an arena runner or a spec reads, and
		the renderer's hook publishes it as `stats.drainDeferrals`. Called once per
		TRIP, where the line is once per unconverged stretch — the two are different
		questions and the latch is exactly the difference. ]]
	onDefer: (() -> ())?,
}

--[[ THE ENTRY POINT AND THE ONE FACT ABOUT IT A CALLER HAS TO SEE. `owed()` is "does
	this surface still owe the round the cap declined to run" — see AND THE DEFERRAL
	OWNS ITS RE-ARMING above for the three places the renderer asks it and what each
	one was losing without it. It is a reader, never a setter: nothing outside this
	closure can queue or cancel a solve. ]]
function solve_queue.trampoline(deps: Deps): (() -> (), () -> boolean)
	local solve = deps.solve
	local tail = deps.tail
	local onDefer = deps.onDefer
	local id = deps.id or "?"
	-- is a drain running? (the re-entry test, and the only state that decides)
	local draining = false
	-- has a re-solve been asked for from inside the drain?
	local owed = false
	--[[ has the cap already been reported since the last drain that CONVERGED? The
		diagnostic is worth one line, not one line a frame: a surface whose adapter
		genuinely never converges deferred a round on every refresh, and at 60 fps
		that is a log flood that costs more than the thing it is reporting. Cleared
		by a drain that finished on its own, so a LATER trip after a healthy stretch
		is reported again rather than swallowed by a latch set minutes ago. ]]
	local capReported = false

	local function run()
		if draining then
			owed = true
			return
		end
		draining = true
		--[[ WHAT THIS FRAME INHERITED, held so the throw path below can tell it apart
			from what this frame's own solve queues (fix round 2, review F3). ]]
		local owedAtEntry = owed
		-- solves that RAN TO COMPLETION, which is how many tails are owed: a solve
		-- that threw never reached its own tail under the recursion either
		local done = 0
		--[[ ...AND THE TAILS ARE OWED BY THE SOLVES THAT COMPLETED, on EVERY exit from
			this function — the ordinary one and the cap's. A solve that ran to
			completion applied its rects, so the frame painted; the cap is a diagnostic
			about the round that would come NEXT and says nothing about the rounds that
			already finished. Exiting past them would leave a consumer gated on
			`onSolved` never notified for a frame it can see, which is the failure the
			absorb above exists to prevent — reintroduced by the guard that bounds the
			loop. A `tail` that throws unwinds the caller from here exactly as it does
			on the ordinary path. ]]
		local function runTails()
			local owedTails = done
			done = 0
			for _ = 1, owedTails do
				tail()
			end
		end
		--[[ THE OUTERMOST SOLVE IS NOT ABSORBED. The recursion ran it on the caller's
			own stack, so its throw unwound `refresh()` then and must now. The flags are
			cleared before the error is re-raised — a drain that dies must not leave the
			surface refusing every later solve. ]]
		local ok, err = xpcall(solve, annotate)
		-- did this drain stop at the cap with a round still owed?
		local deferred = false
		if ok then
			done += 1
			local rounds = 0
			while owed do
				if rounds >= SOLVE_DRAIN_ROUND_CAP then
					--[[ THE DEFERRAL, AND `owed` IS DELIBERATELY LEFT SET. It is the whole
						mechanism: the flag says "a solve is owed", the next entry to this
						function runs one and then drains the rest of the queue, so the round
						this drain declined to run is the round the next refresh starts from.
						Nothing is dropped and nothing is scheduled: the frame the settle was
						going to take anyway is what spends it — and `owed()` below is how the
						renderer knows to make that frame solve, and to keep reading NOT
						SETTLED until it has. ]]
					deferred = true
					break
				end
				owed = false
				rounds += 1
				local rok, rerr = xpcall(solve, annotate)
				if rok then
					done += 1
				else
					solve_queue.report(`Facet renderer: a text-measurement re-solve failed and was absorbed - {rerr}`)
				end
			end
		end
		draining = false
		if not ok then
			--[[ A RE-SOLVE THIS SOLVE QUEUED IS DISCARDED WITH IT — the state it was
				asked against never landed — AND ONE A PREVIOUS FRAME DEFERRED IS NOT
				(fix round 2, review F3). `owed = false` said both, and the second half was
				false: a throwing frame silently cancelled a round it had nothing to do
				with, which is F1's permanent clip reached from the other side. Restoring
				the entry value is the whole distinction. ]]
			owed = owedAtEntry
			error(err, 0)
		end
		if deferred then
			-- the number an arena runner or a spec reads, once per TRIP
			if onDefer ~= nil then
				onDefer()
			end
			if not capReported then
				capReported = true
				--[[ WHAT THE LINE SAYS IS WHAT WAS MEASURED (fix round 2, review F5). It
					used to blame "an adapter answering a batch with a width that changes the
					words it asks for" — the hypothesis this ruling's own measurement REFUTED
					150 lines up, which would send the next debugger at the adapter seam
					instead of at the vocabulary walk. It also named no surface, so N surfaces
					in trouble produced N identical unattributable lines. ]]
				solve_queue.report(
					`Facet renderer: {id}: a solve's text-measurement drain did not converge in `
						.. `{SOLVE_DRAIN_ROUND_CAP} rounds (a wide text key learning its vocabulary one word per round, `
						.. `because each learned width brings the next unmeasured row into the measured set — or an `
						.. `adapter whose answer changes the words it asks for); the remaining re-solve is deferred to `
						.. `the next solve this surface makes; solve-drain round cap`
				)
			end
		else
			capReported = false
		end
		runTails()
	end

	--[[ READ FROM OUTSIDE A DRAIN, which is the only place it means anything and the
		only place the renderer asks it: after `run` returns, `owed` is true exactly
		when the cap deferred a round. Inside a drain the flag is the loop's own
		bookkeeping — cleared before each round, set by the re-entry — and a reader
		would be sampling that. ]]
	return run, function(): boolean
		return owed
	end
end

return solve_queue
