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
	replaced. MEASURED rather than guessed: the deepest drain in the Facet suite,
	the Rascal Rally suite and the example places is 4 rounds (the four-link chain
	fixture); every shipped settle is 1. ]]
local SOLVE_DRAIN_ROUND_CAP = 8

--[[ WHERE AN ABSORBED SOLVE'S ERROR GOES. Default is the engine's own `warn`,
	which is the channel `core/custom.luau`'s `fail` already uses for every
	quarantined write in this framework ("a silent quarantine heals the STATE and
	tells nobody"). Replaceable for the reason `client/text_premeasure`'s scheduler
	seam is: a spec driving this path asserts the report rather than printing
	through the suite. ]]
function solve_queue.report(message: string)
	warn(message)
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

	return function()
		if draining then
			owed = true
			return
		end
		draining = true
		-- solves that RAN TO COMPLETION, which is how many tails are owed: a solve
		-- that threw never reached its own tail under the recursion either
		local done = 0
		--[[ THE OUTERMOST SOLVE IS NOT ABSORBED. The recursion ran it on the caller's
			own stack, so its throw unwound `refresh()` then and must now. The flags are
			cleared before the error is re-raised — a drain that dies must not leave the
			surface refusing every later solve. ]]
		local ok, err = pcall(solve)
		if ok then
			done += 1
			local rounds = 0
			while owed do
				owed = false
				rounds += 1
				if rounds > SOLVE_DRAIN_ROUND_CAP then
					draining = false
					owed = false
					error(
						`Facet renderer: a solve's text-measurement drain did not converge in {SOLVE_DRAIN_ROUND_CAP} rounds `
							.. `(an adapter answering a premeasurement batch with a width that changes the words it asks for?); solve-drain round cap`,
						0
					)
				end
				local rok, rerr = pcall(solve)
				if rok then
					done += 1
				else
					solve_queue.report(`Facet renderer: a text-measurement re-solve failed and was absorbed - {rerr}`)
				end
			end
		end
		draining = false
		owed = false
		if not ok then
			error(err, 0)
		end
		for _ = 1, done do
			tail()
		end
	end
end

return solve_queue
