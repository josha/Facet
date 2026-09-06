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
	completed solve's tail runs, `controller.textPending()` still reads true (the
	words are in flight and the settle is still open), and nothing raises.

	THE DEFERRED ROUND IS SPENT BY THE NEXT SOLVE, NOT SCHEDULED FOR ONE, and the
	distinction is worth stating because this module cannot schedule anything (it has
	no requires, by design). `owed` survives the exit, so the next call — the next
	`controller.refresh()` that solves, the next settle-phase solve, the next
	premeasurement answer — runs it first and drains from there, bounded by the cap
	again. In the window this trips in that is the very next frame: the boot window's
	own second answer for every outstanding batch bumps the geometry epoch, and a
	surface deep enough in a drain to trip a cap is a surface with dozens of those
	still owed to it. What it is NOT is a promise about a surface that trips the cap
	and then goes completely quiet; that one carries its owed round until something
	solves. Measured live: the failing step deferred, and the next drive step drained
	another full cap from where it stopped.

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

--[[ THE ROUND CAP, the `renderer.luau` `SOLVE_FEEDBACK_ROUND_CAP` idiom and for the
	same reason. The drain terminates on its own because a surface's vocabulary is
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
	keeps the pathological one's frame at ~830 ms instead of 3.4 s on the most
	extreme scene in the arena. Bigger buys nothing (the walk is not converging at
	any of these numbers); smaller starts costing frames a real settle needs. ]]
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
}

function solve_queue.trampoline(deps: Deps): () -> ()
	local solve = deps.solve
	local tail = deps.tail
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

	return function()
		if draining then
			owed = true
			return
		end
		draining = true
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
						going to take anyway is what spends it. In the window this cap trips
						in — the boot window — the engine answers `final = false`, so the words
						are still in flight, `controller.textPending()` still reads true, and a
						surface gated on exact text is still waiting for the frame that pays. ]]
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
			-- a re-solve queued by a solve that then threw is discarded with it: the
			-- state it was asked against never landed
			owed = false
			error(err, 0)
		end
		if deferred then
			if not capReported then
				capReported = true
				solve_queue.report(
					`Facet renderer: a solve's text-measurement drain did not converge in {SOLVE_DRAIN_ROUND_CAP} rounds `
						.. `(an adapter answering a premeasurement batch with a width that changes the words it asks for?); `
						.. `the remaining re-solve is deferred to the next refresh; solve-drain round cap`
				)
			end
		else
			capReported = false
		end
		runTails()
	end
end

return solve_queue
