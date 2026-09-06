--!strict
--[[
	THE PREMEASURE ANSWER STOPS RUNNING ON THE SOLVE THAT ASKED FOR IT
	(Plan C, T18-B — ruling L-13, T17's third finding, FacetBench §C16).

	WHAT IS WRONG, MEASURED LIVE (T17 §3.3). On a SETTLED session the whole answer
	chain is synchronous: `text_premeasure.spawn` is `task.spawn`, which runs its body
	until its first yield, and `measureBatch`'s `GetTextBoundsAsync` does not yield
	once the font is loaded — so

	  `text_premeasure.measure` (:477) -> `spawn` (:484) -> `deliver` ->
	  `premeasure_round`'s `done` (:91) -> `solveAndApply` (:154) -> the solve ->
	  `premeasure_round.request` (:74) -> `measure` (:477)

	is ONE C stack. Probe D read `sync=1` on a one-step drive and `maxNestDepth=3` on
	an ordinary `battle_hud L` mount; T9b's two-workload / 200-sample drive printed
	`C stack overflow (when calling anonymous function on line 484 in
	ReplicatedStorage.ui.Facet.src.client.text_premeasure)` and then `Script timeout`.
	`textInFlight` bounds ONE surface's ONE vocabulary — the same word cannot be asked
	twice — but it does not bound a cycle in which each re-solve discovers a DIFFERENT
	word, and it is per surface, so two attached surfaces drive each other through the
	global text epoch. That is the configuration the overflow appeared in.

	WHAT THIS FILE PINS, AND WHY THE NUMBERS ARE READ OFF THE RUN. The fix is a
	QUEUE-AND-DRAIN, not a defer: a re-solve asked for while a solve is on the stack is
	queued, and the outermost solve drains the queue with a LOOP, in the same frame, no
	`task.wait` and no `task.defer`. So there are three observables that must not move,
	and every case below is one of them:

	  1. THE SETTLED RECT LANDS IN THE SAME FRAME. No `wait`, so `initialRender()` /
	     `refresh()` returns with the exact geometry already applied.
	  2. `onSolved` FIRES THE SAME NUMBER OF TIMES — one per solve — AND EVERY
	     NOTIFICATION SEES FINAL GEOMETRY. The second half is the property that
	     actually holds at HEAD and the reason the drain cannot live in
	     `render/premeasure_round`: today the recursion unwinds only after the whole
	     cascade is done, so all N notifications report the final tree. A drain placed
	     after `adapter.measureTextWidths` returns would fire notification k+1 BEFORE
	     the chain's next solve, showing a listener geometry no listener has ever seen.
	     (The renderer's comment at `renderer.luau:2303` says the inner notify is
	     SUPPRESSED. It is not: `notifyingSolved` is set and cleared around the
	     listener loop only, so it guards a listener that publishes back into a solve.
	     Measured at HEAD `bd6bef89`: `notifies == solves == 5` on the four-link chain
	     below. The count is what it always was; the comment overstated the mechanism.)
	  3. THE RECTS ARE BYTE-EQUAL. `tests/text_settle_closure.spec.luau`'s oracle
	     covers the geometry channels across a settle; this file adds the re-entrant
	     shape it does not drive.

	THE DEPTH AND STACK WITNESSES ARE THE TARGET'S, NOT THE FRAMEWORK'S.
	`fake_target`'s sync-answer mode (`answerTextInline`) is the settled live adapter:
	it answers INSIDE the call, and it records the nesting of its own answer bodies
	(`textAnswerDepth`, probe D's `maxNestDepth`) and the deepest Luau stack one ran on
	(`textAnswerStack`, counted with `debug.info` — an overflow is a consequence of
	that number, and this is the bounded-stack witness that fails at HEAD with a
	COUNTER instead of by overflowing Lune). Without that mode the pin is vacuous: the
	queued arm delivers from top level, so the depth reads 1 at HEAD and the red can
	never be red.

	READ OFF THE RUN AT HEAD `bd6bef89` (the `CHAIN = 4` fixture, one `initialRender`):
	`textAnswerDepth() == 4`, `solves == 5`, `onSolved` notifications `== 5`, all five
	reporting the same final rect. AFTER: `textAnswerDepth() == 1`, `solves == 5`,
	notifications `== 5`, same five rects. A drained settle is honestly `solves = 2` in
	ONE frame for the ordinary one-word case, which is the number it is today.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local solve_queue = require("../src/render/solve_queue")
local Facet = require("../src") :: any

local function fill(): any
	return { type = "fill", weight = 1 }
end

local function widthOf(word: string, size: number, _font: string): number?
	return math.max(1, #word * size * 0.5)
end

type Arm = {
	core: any,
	env: any,
	controller: any,
	adapter: any,
	notifies: number,
	notifyRects: { string },
	words: { string },
}

--[[ EVERY ARM GETS ITS OWN VOCABULARY, AND EVERY VOCABULARY IS THE SAME SHAPE.
	`layout/text_metrics`' measured-width store is PROCESS-GLOBAL by design (the module
	header says why: a width one surface learns must reach a surface that never asked),
	so a second arm reusing the first arm's words finds them already measured, asks for
	nothing, and drives no chain at all — the fixture silently stops being the fixture.
	The tag is therefore unique per arm and FIXED-WIDTH, so two arms measure different
	strings of identical length and their rects stay comparable. ]]
local nextTag = 0
local function claimTag(): string
	nextTag += 1
	return string.format("t%03d", nextTag)
end

--[[ THE FIXTURE IS THE CYCLE, BOUNDED. A label whose word is a function of
	`textMeasureEpoch` is the one-surface form of the two-surface cycle the overflow
	needed: learning a width bumps the epoch, the bump reveals a word nothing has ever
	measured, the next solve asks for it. `math.min` is the bound — without it the
	chain is infinite in BOTH shapes, and a test that hangs proves nothing. Two of
	these on one core and one environment is the two-workload configuration. ]]
local function surface(
	opts: {
		chain: number,
		share: { core: any, env: any }?,
		prefix: string?,
		tag: string?,
		stride: number?,
		-- answer on a FRESH THREAD the way `task.spawn` does, which is the only arm that
		-- can see what a throwing re-solve does (fix round 1, review Important 1)
		ownThread: boolean?,
		-- throw out of an engine write on the Nth solve: the failure the live route
		-- absorbs at its own thread boundary
		throwOnSolve: number?,
	}
): Arm
	local core = if opts.share ~= nil then opts.share.core else customFactory.new()
	local env = if opts.share ~= nil then opts.share.env else environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
	local prefix = opts.prefix or "Root"
	local tag = opts.tag or claimTag()
	local words = {}
	for i = 1, opts.chain do
		words[i] = `{tag}{string.rep("x", i)}{i}`
	end
	--[[ `stride` IS WHAT MAKES THE TWO-WORKLOAD CASE A REAL CYCLE. With no stride a
		surface chains on its OWN epoch bumps and never needs a neighbour. With
		`stride = 0` and `stride = 1` on one shared environment each surface's word
		index advances only on the OTHER one's bump, so neither can chain alone and
		the recursion runs THROUGH the shared `textMeasureEpoch` fact — exactly the
		configuration T9b's two-workload run overflowed in. ]]
	local stride = opts.stride
	local label = core:memo(function(use)
		local epoch = (use(env:get("textMeasureEpoch")) :: number?) or 0
		local index = if stride ~= nil then 1 + (epoch + stride) // 2 else epoch + 1
		return words[math.min(opts.chain, index)]
	end)
	local root = mountLib.mount(
		core,
		UI.VStack({
			id = prefix,
			padding = 0,
			gap = 0,
			width = fill(),
			height = fill(),
			children = {
				UI.Text({ id = "Chain", textSize = 12, text = label }),
				UI.Text({ id = "Static", textSize = 12, text = `{tag} static` }),
			},
		})
	)
	local adapter = fake_target.new()
	adapter.answerTextInline(widthOf, nil, opts.ownThread)
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
	if opts.throwOnSolve ~= nil then
		--[[ AN ENGINE WRITE THAT THROWS, which is the shipped shape of this failure: a
			destroyed instance, a rejected property value, a consumer error reached from
			the solve. Armed on ONE solve so the drain has something to absorb and
			something to carry on with. ]]
		local realSetRect = adapter.setRect
		adapter.setRect = function(...)
			if controller.stats().solves == opts.throwOnSolve then
				error("PROBE BOOM", 0)
			end
			return realSetRect(...)
		end
	end
	local arm: Arm = {
		core = core,
		env = env,
		controller = controller,
		adapter = adapter,
		notifies = 0,
		notifyRects = {},
		words = words,
	}
	controller.onSolved(function()
		arm.notifies += 1
		local r = controller.rectOf(`/{prefix}/Chain`)
		table.insert(arm.notifyRects, if r then `{r.x},{r.y},{r.w},{r.h}` else "-")
	end)
	return arm
end

local function rect(arm: Arm, path: string): string
	local r = arm.controller.rectOf(path)
	return if r then `{r.x},{r.y},{r.w},{r.h}` else "-"
end

-- the geometry channel this task must not move: every mounted node's rect and hit
-- rect, sorted, as one string
local function painted(adapter: any): string
	local out = {}
	for path, node in adapter.liveNodes() do
		local r = node.rect
		local hit = adapter.hitRectOf(path)
		table.insert(
			out,
			`{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}`
				.. `|hit={if hit then `{hit.x},{hit.y},{hit.w},{hit.h}` else "-"}`
		)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

describe("the premeasure answer does not run on the solve that asked", function()
	--[[ THE DEPTH PIN, and the number is the target's own. At HEAD this reads 4 —
		one answer body per link of the chain, all four live on one stack — which is
		the headless reproduction of probe D's live `maxNestDepth=3`. ]]
	it("a chain of four learned words answers at depth 1", function()
		local arm = surface({ chain = 4 })
		arm.controller.initialRender()
		expect(arm.adapter.textAnswerDepth()).toBe(1)
		-- the chain really ran: four words learned, five solves (see the header)
		expect(arm.controller.stats().solves).toBe(5)
		expect((arm.env:get("textMeasureEpoch"):get() :: any) or 0).toBe(4)
	end)

	--[[ THE BOUNDED-STACK WITNESS, AND IT IS T9b's OVERFLOW AS A CASE. Two workloads
		on ONE core and ONE environment, each one's next word revealed only by the
		OTHER one's bump (`stride`) — so neither can chain alone and the recursion
		runs through the shared `textMeasureEpoch` fact, which is the configuration
		the live `C stack overflow` appeared in and the reason one workload never
		reproduced it.

		THE PIN IS THAT THE STACK DOES NOT GROW WITH THE CHAIN, which is the property
		an overflow is the absence of — not an absolute frame count, which would
		measure this suite's own call shape. A two-link cycle and an eight-link cycle
		must answer on the SAME Luau stack. It fails at HEAD by a COUNTER rather than
		by overflowing Lune, which is the only form of this case a headless suite can
		hold, and a counter says WHY where an overflow only says "too deep".

		WHAT THE BOUND IS AFTER THE FIX, stated rather than implied: one solve per
		ATTACHED SURFACE, not one per link. Each controller owns its own queue, so a
		neighbour's settle solve — reached through the shared geometry fact, inside
		this surface's own delivery — still nests once. Two surfaces, two solves, and
		a chain of any length rides on them. ]]
	it("a two-workload cycle's stack does not grow with the chain", function()
		local function cycle(chain: number, tag: string): { a: Arm, b: Arm }
			local core = customFactory.new()
			local env = environment.new(core)
			local a = surface({ chain = chain, share = { core = core, env = env }, prefix = `{tag}A`, stride = 0 })
			local b = surface({ chain = chain, share = { core = core, env = env }, prefix = `{tag}B`, stride = 1 })
			a.controller.initialRender()
			-- A ALONE CANNOT CHAIN — its own bump does not move its own index. This is
			-- the non-vacuity guard: without it the case would pass on a fixture in
			-- which the cross-surface cycle never ran at all.
			expect(a.adapter.textAnswerDepth()).toBe(1)
			b.controller.initialRender()
			for _ = 1, 4 do
				a.controller.refresh()
				b.controller.refresh()
			end
			-- ...and the cycle really did run, through the shared fact and nothing else
			expect((env:get("textMeasureEpoch"):get() :: any) or 0).toBeGreaterThanOrEqual(chain)
			return { a = a, b = b }
		end

		local short = cycle(2, "Two")
		local long = cycle(8, "Eight")
		--[[ READ OFF THE RUN AT HEAD `bd6bef89`: the two-link cycle answers on 34 Luau
			frames and the eight-link one on 70 — a whole solve, ~12 frames, per link,
			with `textAnswerDepth` 7 on the eight-link workload B. After: 34 and 34,
			depth 1 on both, because the only thing still on the stack is the
			neighbour's own solve. ]]
		expect(long.a.adapter.textAnswerStack()).toBe(short.a.adapter.textAnswerStack())
		expect(long.b.adapter.textAnswerStack()).toBe(short.b.adapter.textAnswerStack())
		expect(long.a.adapter.textAnswerDepth()).toBe(1)
		expect(long.b.adapter.textAnswerDepth()).toBe(1)
	end)

	-- OBSERVABLE 1: the settled rect lands in the frame that asked for it. No
	-- `task.wait` anywhere in the drain, so this is true of the call, not of a tick.
	it("the settled rect lands in the same frame", function()
		local arm = surface({ chain = 4 })
		arm.controller.initialRender()
		-- the last word of a four-link chain is `tNNN` + `xxxx` + `4` = 9 characters,
		-- and `widthOf` above is 6px a character at size 12
		expect(rect(arm, "/Root/Chain")).toBe(`0,0,{#arm.words[4] * 6},15`)
		expect(#arm.words[4]).toBe(9)
	end)

	-- OBSERVABLE 2: one notification per solve, and every one of them reports the
	-- FINAL tree (see the header — this is the property, not the suppression).
	it("onSolved fires once per solve and every notification sees final geometry", function()
		local arm = surface({ chain = 4 })
		arm.controller.initialRender()
		expect(arm.notifies).toBe(arm.controller.stats().solves)
		expect(arm.notifies).toBe(5)
		local final = rect(arm, "/Root/Chain")
		expect(final).toBe(`0,0,{#arm.words[4] * 6},15`)
		for _, seen in arm.notifyRects do
			expect(seen).toBe(final)
		end
	end)

	--[[ OBSERVABLE 3: the geometry is the geometry a session that never re-entered
		would have. The oracle arm drives the SAME chain with the queued adapter,
		delivering from top level one batch at a time — the shape that has never had
		a re-entry to remove — and the two trees must be byte-equal. ]]
	it("the rects match a session driven from top level", function()
		local inline = surface({ chain = 4 })
		inline.controller.initialRender()

		local queued = surface({ chain = 4 })
		queued.adapter.answerTextInline(nil)
		expect(#queued.words[4]).toBe(#inline.words[4])
		queued.controller.initialRender()
		for _ = 1, 8 do
			if queued.adapter.textBatchCount() == 0 then
				break
			end
			queued.adapter.deliverTextWidths(widthOf)
			queued.controller.refresh()
		end
		expect(painted(queued.adapter)).toBe(painted(inline.adapter))
	end)

	--[[ ── THE TAIL RUNS AFTER THE DRAIN (fix round 1, review Important 2) ────────

		`notifySolved` was never the risk — the count is one per solve in both shapes.
		THE OTHER POST-SOLVE HOOK WAS. `renderer.luau` used to call the drag bridge's
		drop-target refresh inside the commit, UNDER the premeasurement request, and
		under the recursion that was still safe: the nested solve had already applied
		the corrected rects by the time the outer solve reached it, so every call saw
		final geometry. With the drain it ran on solve 1's rects — and that call is not
		internal. `input/drag_registry.refreshTargets` rebuilds every target rect,
		re-runs the hover through `input/drag_session.retarget`, and `setHover` fires
		the PUBLIC `UI.dropTarget` `onEnter` / `onLeave` / `onPredict`; `publishVerdict`
		then writes the public `verdict` Readable.

		THE SHAPE THIS CATCHES IS A HOVER NO FRAME EVER SHOWED, and it needs no
		calibration. The slot FILLS the row beside the label, so the label's width is
		the slot's left edge. Before the settle the label is short and measured, so the
		pointer near the right edge is over the slot. The new word is 400 characters:
		its ESTIMATE overflows the viewport, which collapses the slot to nothing on
		solve 1, and its exact width is 20, which restores the slot on solve 2. So the
		pointer is over the slot before the frame and over the slot after it, and only
		an intermediate look sees anything else.

		AND IT IS THE ORDINARY ONE-WORD SETTLE (`solves = 2`), not a deep chain — the
		correction IS the second solve. ]]
	it("a live drag's public drop-target callbacks see one set of rects per frame", function()
		local UI2 = Facet.UI
		local SHORT = "rrT18bShort"
		local LONG = string.rep("m", 400)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 400 })
		local adapter = fake_target.new()
		-- the settled engine: every word answered INSIDE the solve that asked. The long
		-- word's exact width is 20 where its estimate is thousands, which is the
		-- over-reserving conservative estimate this whole seam exists to correct.
		adapter.answerTextInline(function(word: string): number?
			return if word == LONG then 20 else math.max(1, #word * 4)
		end)
		local label = core:signal(SHORT)
		local enters: { string } = {}
		local leaves: { string } = {}
		local verdicts: { string } = {}
		local screen = UI2.Screen({
			id = "S",
			padding = 0,
			children = {
				UI2.HStack({
					id = "Row",
					padding = 0,
					gap = 0,
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = 120 },
					children = {
						UI2.Text({ id = "Label", textSize = 20, text = label }),
						UI2.dropTarget(
							UI2.Box({
								id = "Slot",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 100 },
							}),
							{
								onDrop = function() end,
								onEnter = function()
									table.insert(enters, "Slot")
								end,
								onLeave = function()
									table.insert(leaves, "Slot")
								end,
							}
						),
					},
				}),
				UI2.draggable(
					UI2.Box({ id = "Card", width = { type = "fixed", px = 60 }, height = { type = "fixed", px = 60 } }),
					{ payload = "card" }
				),
			},
		})
		local root = mountLib.mount(core, screen)
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
		controller.initialRender()
		local registry = controller.dragRegistry()
		core:observe(registry.verdict, function(v: any)
			table.insert(verdicts, if v == nil then "-" else tostring(v.targetId))
		end)

		local slot = controller.rectOf("/S/Row/Slot")
		expect(slot ~= nil and slot.w > 100).toBe(true)
		local x, y = slot.x + slot.w - 10, slot.y + slot.h / 2
		-- past the mouse promotion token (10 px), landing on that point
		adapter.driveDragStart("/S/Card", { x = x - 30, y = y, pointerType = "mouse" })
		adapter.driveDragContinue("/S/Card", { x = x, y = y, pointerType = "mouse" }, { x = 0, y = 0 })
		expect(registry.isActive()).toBe(true)
		expect(`hovering {tostring(registry.verdict:get().targetId)}`).toBe("hovering /S/Row/Slot")
		local entersBefore, leavesBefore, verdictsBefore = #enters, #leaves, #verdicts

		--[[ ...AND THE SETTLE, IN ONE `refresh()`: the label learns its word, the answer
			arrives inside the solve that asked, and the drain runs the correction. ]]
		--[[ ...and every rect this frame WRITES to the engine, so the intermediate look
			is a recorded fact rather than an inference: the drain applies solve 1's rects
			and then solve 2's, and the case's whole claim is that no public callback was
			taken against the first set. ]]
		local slotWrites: { string } = {}
		local realSetRect = adapter.setRect
		adapter.setRect = function(handle: any, rect: any, ...)
			if handle ~= nil and handle.path == "/S/Row/Slot" then
				table.insert(slotWrites, `{rect.x},{rect.w}`)
			end
			return realSetRect(handle, rect, ...)
		end
		local solvesBefore = controller.stats().solves
		label:set(LONG)
		controller.refresh()
		adapter.setRect = realSetRect
		expect(`solves {controller.stats().solves - solvesBefore}`).toBe("solves 2")
		--[[ NON-VACUITY, BOTH HALVES, and the second is what makes the pin mean anything.
			The corrected slot still holds the pointer — AND the frame really did write an
			intermediate rect that does not, so an intermediate look had something to see. ]]
		local after = controller.rectOf("/S/Row/Slot")
		expect(`still over the slot: {x >= after.x and x < after.x + after.w}`).toBe("still over the slot: true")
		expect(`slot rects written this frame: {#slotWrites}`).toBe("slot rects written this frame: 2")
		local firstX, firstW = string.match(slotWrites[1], "([%-%d%.]+),([%-%d%.]+)")
		local fx, fw = tonumber(firstX) :: number, tonumber(firstW) :: number
		expect(`the estimate took the pointer off the slot: {not (x >= fx and x < fx + fw)}`).toBe(
			"the estimate took the pointer off the slot: true"
		)
		--[[ THE PIN. The pointer was over the slot before this frame and is over the slot
			after it, so a session that only ever sees final rects fires NOTHING. The
			pre-fix drain fired `onLeave` on solve 1's collapsed rects and `onEnter` on
			solve 2's — a hover no frame ever showed. ]]
		expect(`enters {#enters - entersBefore} leaves {#leaves - leavesBefore}`).toBe("enters 0 leaves 0")
		--[[ ...AND THE PUBLIC `verdict` READABLE, whose COUNT was never the question:
			`publishVerdict` writes a fresh table on every refresh, so a tail per solve is
			two publishes in either shape. What must not move is what each one SAYS. ]]
		local said: { string } = {}
		for i = verdictsBefore + 1, #verdicts do
			table.insert(said, verdicts[i])
		end
		expect(table.concat(said, ",")).toBe("/S/Row/Slot,/S/Row/Slot")
		controller.dispose()
	end)

	--[[ ── A DRAINED SOLVE'S THROW IS ABSORBED (fix round 1, review Important 1) ────

		The shipped adapter delivers inside `task.spawn` (`client/screen_target` ->
		`client/text_premeasure`), which runs its body on a NEW THREAD. So an error in
		the nested solve died at that boundary, the scheduler reported it, and the outer
		solve finished and NOTIFIED. Measured across the two worktrees with exactly this
		shape: base `initialRender()` returned normally with ONE `onSolved`; the queue's
		first form raised out of `refresh()` with NONE — for a frame that DID paint,
		which can leave a consumer gated on `onSolved` (the presenter's no-pop text
		reveal is the shipped one) never revealing.

		`ownThread` is what makes this arm real: the same-stack fake cannot see it,
		which is exactly why it was missed. ]]
	it("a drained solve that throws is absorbed, and the completed solve still notifies", function()
		local reports: { string } = {}
		local realReport = solve_queue.report
		solve_queue.report = function(message: string)
			table.insert(reports, message)
		end
		local ok, err = pcall(function()
			local arm = surface({ chain = 1, ownThread = true, throwOnSolve = 2 })
			-- IT RETURNS, which is the whole claim
			arm.controller.initialRender()
			expect(`solves {arm.controller.stats().solves} notifies {arm.notifies}`).toBe("solves 2 notifies 1")
			-- ...and the report was made rather than swallowed
			expect(#reports).toBe(1)
			expect(string.find(reports[1], "absorbed", 1, true) ~= nil).toBe(true)
			-- ...and the surface is not wedged: a later frame solves and notifies
			arm.controller.refresh()
			arm.env:set("viewportRect", { x = 0, y = 0, w = 380, h = 300 })
			expect(arm.notifies > 1).toBe(true)
			arm.controller.dispose()
		end)
		solve_queue.report = realReport
		if not ok then
			error(err, 0)
		end
	end)

	--[[ ── THE DRAIN IS BOUNDED BY A CAP, AND THE CAP DEFERS (ruling C-3) ──────────

		The loop terminates on its own because a surface's vocabulary is finite, but
		that is an invariant three modules away — and without a cap a pathological drain
		is a NON-YIELDING HANG where it used to be a `C stack overflow`, which is
		strictly harder to diagnose than the crash it replaced. So there is a cap.

		WHAT THE CAP MAY NOT DO IS RAISE, and that is what these cases are. Measured
		live (FacetBench §8, the one hard failure of that document): `battle_hud facet`
		at 120 samples, in a FRESH client VM, mounted and driven with no settle wait,
		threw out of `refresh()` — `FAILED at step 118 kind=updateItem field=facing |
		textPending=true batches 56 -> 65`. One ordinary step drove nine text-measure
		batches past a cap of eight, in the boot window, on a wide key (1,000
		`UnitFacing` rows). Nothing was wrong with that drain except that it was not
		FINISHED — and the round that would have finished it is exactly the round the
		next refresh runs anyway, because the queue's own "solve again" flag is what
		the deferral hands forward. A production surface mounted into the first few
		seconds of a session is in that window by construction.

		So: no throw, the remaining round stays queued, `textPending()` stays true, the
		tails every completed solve owes still run, and ONE line says what happened. ]]
	--[[ PINNED AGAINST `SOLVE_DRAIN_ROUND_CAP` (`src/render/solve_queue.luau`). Read
		out of the source instead and the case could not tell a cap of 64 from a cap
		that silently became 6 — the number is the contract, so it is written here. ]]
	local CAP = 16

	--[[ THE DEFERRAL AT THE TRAMPOLINE ITSELF, with no renderer in the way. `solve`
		here is the adapter the ruling names — one whose answer always changes the
		words it asks for, so every solve queues another from inside its own body,
		forever. The module has no requires, so this drives the exact loop. ]]
	it("the cap defers the queued re-solve instead of raising, and says so once", function()
		local reports: { string } = {}
		local realReport = solve_queue.report
		solve_queue.report = function(message: string)
			table.insert(reports, message)
		end
		local ok, err = pcall(function()
			local solves, tails = 0, 0
			local converge = false
			local run: () -> ()
			run = solve_queue.trampoline({
				solve = function()
					solves += 1
					if not converge then
						-- the re-solve a premeasurement answer asks for from INSIDE the
						-- solve that asked for the measurement
						run()
					end
				end,
				tail = function()
					tails += 1
				end,
			})

			-- IT RETURNS. That is the ruling, and the rest of the case is what it
			-- returned having done.
			run()
			expect(`drain 1: solves {solves} tails {tails} reports {#reports}`).toBe(
				`drain 1: solves {CAP + 1} tails {CAP + 1} reports 1`
			)
			expect(string.find(reports[1], "solve-drain round cap", 1, true) ~= nil).toBe(true)
			expect(string.find(reports[1], "deferred", 1, true) ~= nil).toBe(true)

			--[[ ...AND THE NEXT REFRESH PICKS IT UP WHERE THIS ONE STOPPED. The round the
				cap declined to run is still owed, so the next call runs it and drains from
				there — bounded by the same cap. A deferral that dropped the queued re-solve
				would still read `solves` climbing (the caller asked for one), so the honest
				witness is the CONVERGING arm below, where the deferred round is the only
				thing left to run. ]]
			run()
			expect(`drain 2: solves {solves} tails {tails}`).toBe(
				`drain 2: solves {2 * (CAP + 1)} tails {2 * (CAP + 1)}`
			)
			--[[ ...AND IT IS ONE LINE, NOT ONE A FRAME. A surface whose adapter genuinely
				never converges defers on every refresh; at 60 fps a line each would cost
				more than the thing it reports. ]]
			expect(#reports).toBe(1)

			--[[ THE DEFERRED ROUND IS REALLY STILL QUEUED: with the cycle broken, this
				call is the caller's own solve PLUS the one the last drain deferred — two,
				not one. That is the deferral proved by subtraction. ]]
			converge = true
			local before = solves
			run()
			expect(`the deferred round ran: solves +{solves - before} tails +{tails - before}`).toBe(
				"the deferred round ran: solves +2 tails +2"
			)

			--[[ ...AND THE ONE-LINE LATCH IS CLEARED BY A DRAIN THAT CONVERGED, so a
				later trip after a healthy stretch is reported rather than swallowed by a
				latch set minutes ago. ]]
			converge = false
			run()
			expect(`after a healthy drain: reports {#reports}`).toBe("after a healthy drain: reports 2")
		end)
		solve_queue.report = realReport
		if not ok then
			error(err, 0)
		end
	end)

	--[[ ...AND THE SAME THING THROUGH A MOUNTED SURFACE, ON THE SHAPE THE LIVE
		FAILURE HAPPENED IN: a `refresh()` whose own solve starts the cascade, which is
		what step 118 of the `battle_hud` drive was. Two observables live only here —
		`controller.textPending()` and `onSolved`.

		EVERY SOLVE THE CAP PATH COMPLETED IS STILL A FRAME THAT PAINTED, so every one
		of them owes a `tail()` — the "this surface finished solving" notification and
		the drag bridge's drop-target refresh (fix round 1's I-2, kept). And the settle
		is still OPEN: this fixture answers `final = false`, the way
		`client/text_premeasure` answers while the engine's font metrics have not
		flipped, so the words stay in flight, `textPending()` keeps reading true and a
		surface gated on exact text keeps waiting for the frame that finishes the drain
		instead of being handed an error.

		THE FIXTURE IS THE CHAIN WITH A SIGNAL FOR ITS BOUND, and the bound is why it is
		written out here rather than taken from `surface` above: a chain that is already
		deep at MOUNT defers inside `initialRender`, and `initialRender` drains the dirty
		queue after its solve ("initial mount noise is not an update"), which throws away
		the very dirt the deferred round is owed for. So this arm mounts SHORT — two
		words, converged, exactly like a real surface's first frame — and only then opens
		the vocabulary, which puts the deep drain inside a `refresh()`, where the dirt a
		deferred round still owes stays queued for the next one. ]]
	it("a refresh defers, keeps textPending, notifies every solve, and drains again next frame", function()
		local reports: { string } = {}
		local realReport = solve_queue.report
		solve_queue.report = function(message: string)
			table.insert(reports, message)
		end
		local ok, err = pcall(function()
			local CHAIN = CAP * 3
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
			local tag = claimTag()
			local words = {}
			for i = 1, CHAIN do
				words[i] = `{tag}{string.rep("x", i)}{i}`
			end
			local bound = core:signal(2)
			local label = core:memo(function(use)
				local epoch = (use(env:get("textMeasureEpoch")) :: number?) or 0
				return words[math.min(use(bound) :: number, epoch + 1)]
			end)
			local root = mountLib.mount(
				core,
				UI.VStack({
					id = "Deferral",
					padding = 0,
					gap = 0,
					width = fill(),
					height = fill(),
					children = {
						UI.Text({ id = "Chain", textSize = 12, text = label }),
						UI.Text({ id = "Static", textSize = 12, text = `{tag} static` }),
					},
				})
			)
			local adapter = fake_target.new()
			-- the boot window: answered INSIDE the solve that asked, and NOT final
			adapter.answerTextInline(widthOf, false)
			local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
			local notifies = 0
			controller.onSolved(function()
				notifies += 1
			end)
			controller.initialRender()
			-- the ordinary first frame: a two-word chain, drained and converged
			expect(`mounted: solves {controller.stats().solves} reports {#reports}`).toBe("mounted: solves 3 reports 0")

			--[[ ...AND NOW THE VOCABULARY OPENS UNDER A DRIVE, which is the live recipe:
				a state write, then the frame that serves it, and the cascade is inside
				THAT frame. IT RETURNS — that is the ruling — having drained the cap. ]]
			bound:set(CHAIN)
			local before = controller.stats().solves
			controller.refresh()
			local first = controller.stats().solves - before
			expect(`first deferred drain: solves {first}`).toBe(`first deferred drain: solves {CAP + 1}`)
			expect(`notified: {notifies}`).toBe(`notified: {controller.stats().solves}`)
			expect(controller.textPending()).toBe(true)
			expect(#reports).toBe(1)
			expect(string.find(reports[1], "solve-drain round cap", 1, true) ~= nil).toBe(true)
			expect(string.find(reports[1], "deferred", 1, true) ~= nil).toBe(true)

			--[[ THE NEXT FRAME DRAINS AGAIN, FROM WHERE THIS ONE STOPPED. Nothing
				scheduled it and nothing was dropped: the round the cap declined to run left
				its dirt on the tree and its "solve again" in the queue, so the ordinary next
				refresh spends both — bounded by the same cap, and with no second line while
				it is still the same unconverged drain. ]]
			local second = controller.stats().solves
			controller.refresh()
			expect(`second deferred drain: solves {controller.stats().solves - second}`).toBe(
				`second deferred drain: solves {CAP + 1}`
			)
			expect(`notified: {notifies}`).toBe(`notified: {controller.stats().solves}`)
			expect(#reports).toBe(1)

			--[[ ...AND IT FINISHES. A bounded vocabulary drained a cap at a time reaches
				its end, and the surface is left solved rather than wedged by its own
				diagnostic — which is what the raising cap's "not latched" case was really
				claiming, now claimed about a session that survives to make it. ]]
			for _ = 1, 4 do
				controller.refresh()
			end
			local settledAt = controller.stats().solves
			controller.refresh()
			expect(`a converged refresh adds nothing: {controller.stats().solves - settledAt}`).toBe(
				"a converged refresh adds nothing: 0"
			)
			-- ...and the whole vocabulary really was learned, one epoch bump per word
			expect(`epoch {(env:get("textMeasureEpoch"):get() :: any) or 0}`).toBe(`epoch {CHAIN}`)
			expect(`notified: {notifies}`).toBe(`notified: {controller.stats().solves}`)
			expect(#reports).toBe(1)
			controller.dispose()
		end)
		solve_queue.report = realReport
		if not ok then
			error(err, 0)
		end
	end)

	--[[ ...AND THE OUTERMOST SOLVE'S THROW KEEPS ITS TRACEBACK. The recursion this
		trampoline replaced propagated a solve's error NATIVELY, with its stack; a
		`pcall` + `error(err, 0)` re-raise hands the caller a message with no origin,
		so every framework crash report from a shipped surface would name
		`solve_queue` and nothing else. `xpcall` with a traceback handler runs on the
		ERRORING stack, so the annotation is taken where the throw happened rather than
		where it was caught. ]]
	it("an outermost solve's throw arrives with the stack it was raised on", function()
		local arm = surface({ chain = 1, throwOnSolve = 1 })
		local ok, err = pcall(function()
			arm.controller.initialRender()
		end)
		expect(ok).toBe(false)
		local text = tostring(err)
		print(`reentry trace: {string.gsub(text, "\n", " | ")}`)
		-- the message survives...
		expect(string.find(text, "PROBE BOOM", 1, true) ~= nil).toBe(true)
		--[[ ...and so do the frames it was raised in, which is the whole point. The
			pins are FILE names rather than lines: `rect_pass` is the walk that made the
			engine write that threw and `renderer` is the solve above it, and a trace
			that names neither is a trace that lost the origin. (Lune's
			`debug.traceback` prints the frames with no "stack traceback:" banner, so
			the shape is asserted by the frame count.) ]]
		local frames = select(2, string.gsub(text, "\n", "\n"))
		expect(`frames > 4: {frames > 4}`).toBe("frames > 4: true")
		expect(string.find(text, "render/rect_pass", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "render/renderer", 1, true) ~= nil).toBe(true)
		arm.controller.dispose()
	end)

	--[[ THE ORDINARY SETTLE, which is the shape every shipped surface is in: ONE
		round, ONE learned word, and the drain runs exactly one further solve. `solves
		= 2` in one frame is what it is today and what it stays. ]]
	it("an ordinary one-word settle is two solves in one frame", function()
		local arm = surface({ chain = 1 })
		local before = arm.controller.stats().solves
		arm.controller.initialRender()
		expect(arm.controller.stats().solves - before).toBe(2)
		expect(arm.notifies).toBe(2)
		expect(arm.adapter.textAnswerDepth()).toBe(1)
	end)
end)
