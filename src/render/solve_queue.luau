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
	(T17, FacetBench §C15): `sync=1` on a one-step drive, `maxNestDepth=3` on an
	ordinary mount, and a two-workload run printing `C stack overflow (when calling
	anonymous function on line 484 in ...text_premeasure)` followed by a script
	timeout. `textInFlight` bounds ONE surface's ONE vocabulary — the same word
	cannot be asked twice — but not a cycle in which each re-solve discovers a
	DIFFERENT word, and it is per surface, so two attached surfaces drive each other
	through the global text epoch. Headless, `tests/text_round_reentry.spec.luau`
	reads 12 Luau frames for a one-link settle against 70 for an eight-link
	two-workload cycle: a whole solve on the stack per link.

	WHAT THIS IS NOT, and it is the whole design. It is NOT a defer. A `wait(0)`
	before the delivery would move the settled rect a FRAME later — a visible text
	pop on every damage number, score and timer readout of a settled session — and
	would make each correction an outermost solve of its own. The loop keeps the
	answer on the frame that asked for it and keeps the solve count exactly what it
	was: one per learned round, `solves = 2` in one frame for the ordinary settle.

	WHY THE NOTIFICATIONS ARE FIRED AFTER THE DRAIN, WHICH IS THE SUBTLE HALF.
	`renderer.luau`'s `notifySolved` runs at the tail of every solve — the count is
	one per solve, and that is true of the recursion too (measured at the parent SHA:
	`notifies == solves == 5` on a four-link chain; the `notifyingSolved` latch there
	guards a LISTENER that publishes back into a solve, not this cycle). What the
	recursion also gave, by unwinding only after the whole cascade was done, is that
	EVERY notification saw the FINAL geometry. A drain placed where the recursion
	was — inside `premeasure_round`, after the adapter's answer returns — bounds the
	stack just as well and breaks that: notification k+1 would fire before the
	chain's next solve, showing a consumer a rect no consumer has ever seen. So the
	loop counts its solves and fires that many notifications after the last one, all
	against the finished tree. Same count, same geometry, same frame.

	ONE SOLVE ON THE STACK AT A TIME is the property, and the queue is a BOOLEAN
	rather than a list because the re-solve carries no argument: it is "solve again",
	and two of them asked for during one body are one solve, exactly as they were
	when the second re-entered the first. `tests/text_round_reentry.spec.luau` pins
	the stack, the depth, the solve count, the notification count and the rects.

	NO REQUIRES, no state outside the closure it returns, and nothing about the
	renderer in it.
]]

local solve_queue = {}

export type Deps = {
	-- one solve: the renderer's whole solve-and-apply body, minus its notification
	solve: () -> (),
	-- "this surface finished solving", fired once per solve AFTER the drain
	notify: () -> (),
}

function solve_queue.trampoline(deps: Deps): () -> ()
	local solve = deps.solve
	local notify = deps.notify
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
		local solves = 0
		--[[ THE PCALL IS THE UNWIND, and it keeps the recursion's failure shape: a
			throwing inner solve used to abort the outer one too, so neither notified.
			The flags are cleared before the error is re-raised — a drain that dies
			must not leave the surface refusing every later solve — and the queued
			re-solve dies with it, exactly as the cascade did. ]]
		local ok, err = pcall(function()
			solve()
			solves += 1
			while owed do
				owed = false
				solve()
				solves += 1
			end
		end)
		draining = false
		owed = false
		if not ok then
			error(err, 0)
		end
		for _ = 1, solves do
			notify()
		end
	end
end

return solve_queue
