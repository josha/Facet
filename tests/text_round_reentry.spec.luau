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
	-- the vocabulary's own bound (see `mountAt`): `bound:set(chain)` opens it
	bound: any,
	-- the mounted tree, so a case can drain the dirty queue the way a caller does
	root: any,
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
		--[[ answer `final = false`, the way `client/text_premeasure` answers while the
			engine's font metrics have not flipped. Default is the SETTLED adapter
			(`final` absent, i.e. `~= false`), and the two differ in exactly one
			observable this file cares about: on the settled shape the answered word
			leaves `textInFlight`, so `controller.textPending()` reads false between
			rounds. Both shapes are driven wherever a case's claim is about the
			deferral rather than about the boot window. ]]
		bootWindow: boolean?,
		--[[ MOUNT SHORT AND OPEN THE VOCABULARY LATER. The word index is bounded by
			this until `arm.bound:set(chain)`, so the deep drain lands inside a
			`refresh()` rather than inside `initialRender()` — the shape the live
			failure happened in (FacetBench §8, step 118: a mounted surface driven by
			ordinary state writes). Absent, the bound is the chain itself and the memo
			is exactly what it was. ]]
		mountAt: number?,
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
	local bound = core:signal(opts.mountAt or opts.chain)
	local label = core:memo(function(use)
		local epoch = (use(env:get("textMeasureEpoch")) :: number?) or 0
		local index = if stride ~= nil then 1 + (epoch + stride) // 2 else epoch + 1
		return words[math.min(opts.chain, use(bound) :: number, index)]
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
	adapter.answerTextInline(widthOf, if opts.bootWindow then false else nil, opts.ownThread)
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
		bound = bound,
		root = root,
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

--[[ THE DIAGNOSTIC IS CAPTURED, NOT PRINTED. `solve_queue.report` defaults to the
	engine's `warn`, which is why the module has the seam at all: a case that
	deliberately drives a cap trip would otherwise print through the suite's own
	PASS/FAIL lines. The real reporter is restored whether the body returned or threw,
	so one red case cannot leave every later one deaf. ]]
local function withReports(body: ({ string }) -> ())
	local reports: { string } = {}
	local realReport = solve_queue.report
	solve_queue.report = function(message: string)
		table.insert(reports, message)
	end
	local ok, err = pcall(body, reports)
	solve_queue.report = realReport
	if not ok then
		error(err, 0)
	end
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
		withReports(function(reports)
			local solves, tails, defers = 0, 0, 0
			local converge = false
			local run: () -> ()
			local owed: () -> boolean
			run, owed = solve_queue.trampoline({
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
				--[[ THE COUNTER THE RENDERER PUBLISHES AS `stats.drainDeferrals` (fix
					round 2, review F8), driven here at the seam it is written at. It is
					once per TRIP where the line below is once per unconverged STRETCH, and
					the two numbers diverging is exactly what the latch is. ]]
				onDefer = function()
					defers += 1
				end,
			})

			-- IT RETURNS. That is the ruling, and the rest of the case is what it
			-- returned having done.
			run()
			expect(`drain 1: solves {solves} tails {tails} defers {defers} reports {#reports}`).toBe(
				`drain 1: solves {CAP + 1} tails {CAP + 1} defers 1 reports 1`
			)
			-- ...and the round really is owed, which is the fact the renderer reads
			expect(`drain 1: owed {owed()}`).toBe("drain 1: owed true")
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
				more than the thing it reports. THE COUNTER IS THE OTHER HALF: it moves on
				every trip, which is why a rig reads it and not the log. ]]
			expect(`drain 2: defers {defers} reports {#reports}`).toBe("drain 2: defers 2 reports 1")

			--[[ THE DEFERRED ROUND IS REALLY STILL QUEUED: with the cycle broken, this
				call is the caller's own solve PLUS the one the last drain deferred — two,
				not one. That is the deferral proved by subtraction. ]]
			converge = true
			local before = solves
			run()
			expect(`the deferred round ran: solves +{solves - before} tails +{tails - before}`).toBe(
				"the deferred round ran: solves +2 tails +2"
			)
			-- ...and nothing is owed any more, which is what lets the renderer stop
			expect(`converged: owed {owed()} defers {defers}`).toBe("converged: owed false defers 2")

			--[[ ...AND THE ONE-LINE LATCH IS CLEARED BY A DRAIN THAT CONVERGED, so a
				later trip after a healthy stretch is reported rather than swallowed by a
				latch set minutes ago. ]]
			converge = false
			run()
			expect(`after a healthy drain: reports {#reports}`).toBe("after a healthy drain: reports 2")
		end)
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

		THE FIXTURE IS THE CHAIN WITH A SIGNAL FOR ITS BOUND, so this arm mounts SHORT —
		two words, converged, exactly like a real surface's first frame — and only then
		opens the vocabulary, which puts the deep drain inside a `refresh()` the way
		step 118's was. (In fix round 1 that was not a choice: a chain already deep at
		MOUNT deferred inside `initialRender`, whose post-solve drain of the dirty queue
		threw away the very dirt the deferred round was the build for, and the surface
		was stranded for the session. The case below this one is that defect, and it is
		why `initialRender` no longer drains while a round is owed. This arm keeps the
		refresh-shaped drive because it is the one the live failure happened in.) ]]
	it("a refresh defers, keeps textPending, notifies every solve, and drains again next frame", function()
		withReports(function(reports)
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
			--[[ THE COUNTER IS THE WITNESS A LIVE RIG HAS (fix round 2, review F8): the
				`warn` is latched, so a scrape cannot count trips, and scraping warnings is
				how FacetBench §8's failure was found in the first place. The message's
				CONTENT is still asserted below, because the line has its own job — it has
				to name the surface and the mechanism it was measured to be. ]]
			expect(`deferrals {controller.stats().drainDeferrals}`).toBe("deferrals 1")
			expect(#reports).toBe(1)
			expect(string.find(reports[1], "solve-drain round cap", 1, true) ~= nil).toBe(true)
			expect(string.find(reports[1], "deferred", 1, true) ~= nil).toBe(true)
			-- ...and it names THIS surface's root and the walk, not the refuted adapter
			-- hypothesis (review F5)
			expect(string.find(reports[1], "/Deferral", 1, true) ~= nil).toBe(true)
			expect(string.find(reports[1], "one word per round", 1, true) ~= nil).toBe(true)

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
			expect(`deferrals {controller.stats().drainDeferrals} reports {#reports}`).toBe("deferrals 2 reports 1")

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
			--[[ ...and this arm still reads PENDING, which is the BOOT WINDOW and not the
				deferral: `final = false` leaves every answered word in flight until the
				engine's settled re-read, so the surface is legitimately still waiting. The
				case below drives the settled adapter, where pending really does fall with
				the last owed round. ]]
			expect(`converged: pending {controller.textPending()}`).toBe("converged: pending true")
			controller.dispose()
		end)
	end)

	--[[ ── A DEFERRAL THE MOUNT MADE IS STILL A DEFERRAL (C-3 fix round 2, F1) ────────

		WHAT WAS WRONG. `owed` is the deferral's only carrier and it is PASSIVE: this
		module cannot schedule, so the round it declined to run is spent by whatever
		solves NEXT. In production that is `controller.refresh()` — and `refresh` solved
		only if the DIRTY QUEUE said so. `controller.initialRender()` calls
		`root.takeDirty()` immediately after its solve ("initial mount noise is not an
		update"), which throws away the very dirt the deferred round was queued against,
		so a cap tripped AT MOUNT left `needsSolve` false on every later frame. Measured
		at `bec8e935` on this fixture: twenty ordinary refreshes produced ZERO solves and
		ZERO text batches, and the label held a 24-character word inside the 138 px box
		word 17 had earned. A loud throw had become silent, permanent text clipping —
		and every presented surface mounts through that path (`present/presenter`,
		`present/anchored`, `present/catchers`, `present/text_reveal`,
		`client/edit_preview`).

		SO THE DEFERRAL OWNS ITS RE-ARMING: the frame entry point asks the QUEUE whether
		a round is owed, which is a fact about the queue rather than about any caller's
		dirty bookkeeping. WHAT THAT PINS IS THAT A SOLVE RUNS, and this case's first
		claim used to say more than that — "no `takeDirty()` anywhere can strand it",
		which the review falsified (fix round 3, F1-b): whether the forced solve makes
		PROGRESS is a second question, and this arm cannot ask it because the dirt is
		still in the queue when the next frame takes it. The `takeDirty()` case below is
		the one that asks it. Driven on BOTH adapter shapes — the boot window is where the cap trips
		live, and the settled shape is where a reader would assume it cannot. ]]
	it("a cap tripped inside `initialRender` is not stranded: ordinary frames finish the walk", function()
		withReports(function(reports)
			-- deep enough that neither the mount nor the frame after it can finish it
			local CHAIN = CAP * 2 + 8
			for _, bootWindow in { true, false } do
				local name = if bootWindow then "boot" else "settled"
				local arm = surface({ chain = CHAIN, bootWindow = bootWindow })
				arm.controller.initialRender()
				-- the mount itself tripped the cap, which is the whole premise
				expect(`{name}: mount solves {arm.controller.stats().solves}`).toBe(`{name}: mount solves {CAP + 1}`)
				-- ...and now ORDINARY FRAMES, with nothing else dirtying the tree
				for _ = 1, 8 do
					arm.controller.refresh()
				end
				local epoch = (arm.env:get("textMeasureEpoch"):get() :: any) or 0
				expect(`{name}: epoch {epoch}`).toBe(`{name}: epoch {CHAIN}`)
				--[[ ...AND THE BOX IS THE LAST WORD'S OWN WIDTH. The epoch alone would pass
					on a surface that learned every width and never re-laid itself out, which
					is exactly what a player sees as clipped text. ]]
				local r = arm.controller.rectOf("/Root/Chain")
				expect(`{name}: w {if r ~= nil then r.w else -1}`).toBe(`{name}: w {widthOf(arm.words[CHAIN], 12, "")}`)
				arm.controller.dispose()
			end
			-- one line per surface per unconverged stretch, not one a frame
			expect(`reports {#reports}`).toBe("reports 2")
		end)
	end)

	--[[ ── AN OWED ROUND IS "PENDING", ON EVERY ADAPTER SHAPE (C-3 fix round 2, F2) ───

		WHAT WAS WRONG. `controller.textPending()` was "is a word still in flight", and a
		word stays in flight only while the adapter answers `final == false`
		(`render/premeasure_round`: a settled answer clears the key, a boot-window one
		marks it "answered"). The cap trips at the TOP of the drain loop — after the last
		round's answer has already cleared the set — so on a SETTLED session a surface
		deferred a round with `textPending()` reading FALSE. The header, the ruling and
		the commit all claimed it stays true; only an inline comment scoped that to the
		boot window.

		WHAT THAT COSTS is the text-pop class the gate exists to prevent.
		`present/presenter`'s `syncTextReveal` reveals a gated surface the moment
		`pending` reads false and sets `handle.textRevealedExact = true` with it: a
		surface that still owes a round is revealed, CLAIMING EXACTNESS, one solve before
		its geometry is exact. The campaign's live settle oracle ("drive until
		`controller.textPending()` falls") returns early for the same reason and measures
		an unsettled tree.

		So pending is "a word in flight OR a round owed", and this case is the settled
		adapter the boot-window arm above cannot speak for. ]]
	it("a deferred round reads as PENDING on a settled adapter, so the no-pop gate stays shut", function()
		withReports(function(reports)
			local CHAIN = CAP * 3
			--[[ MOUNT SHORT, THEN OPEN THE VOCABULARY UNDER A DRIVE, which is the live
				recipe (a state write, then the frame that serves it) and the one shape that
				isolates this finding from F1's: nothing here is deferred at mount. ]]
			local arm = surface({ chain = CHAIN, mountAt = 2 })
			arm.controller.initialRender()
			expect(`mounted: solves {arm.controller.stats().solves} pending {arm.controller.textPending()}`).toBe(
				"mounted: solves 3 pending false"
			)
			arm.bound:set(CHAIN)
			local before = arm.controller.stats().solves
			arm.controller.refresh()
			expect(`deferred: solves +{arm.controller.stats().solves - before}`).toBe(`deferred: solves +{CAP + 1}`)
			--[[ THE ONE OBSERVABLE THIS CASE EXISTS FOR. `syncTextReveal` is a pure
				function of this answer and its deadline, so a surface that reads NOT pending
				here is a surface the presenter reveals and stamps `textRevealedExact`. ]]
			expect(`deferred: pending {arm.controller.textPending()}`).toBe("deferred: pending true")
			expect(`deferred: reports {#reports}`).toBe("deferred: reports 1")
			-- ...and it falls again once the walk finishes, so the gate really does open
			for _ = 1, 4 do
				arm.controller.refresh()
			end
			expect(`settled: pending {arm.controller.textPending()}`).toBe("settled: pending false")
			arm.controller.dispose()
		end)
	end)

	--[[ ── AN OWED ROUND IS A ROUND THAT MUST STILL DO THE WORK (C-3 fix round 3, F1-b) ─

		WHAT WAS WRONG. Fix round 2 made the frame entry point solve whenever a round is
		owed — and then handed that solve a tree it had just declared CLEAN. `refresh`
		writes `nodeDirtySeen = root.dirtySeq()` before it scans the queue, which is the
		claim "everything dirtied so far is classified into `nodeDirty`". On an EMPTY
		queue that claim is a lie whenever anything else drained it: nothing is
		classified, `nodeDirty` stays `{}`, `layout_node.build` serves every node from
		the store, and the forced solve measures a tree still holding the PREVIOUS word.
		It makes no progress — but the drain still spends the carried-in round, so
		`owed` clears, `controller.textPending()` flips back to FALSE, and
		`present/presenter`'s `syncTextReveal` reveals the surface and stamps
		`handle.textRevealedExact = true` on geometry that is 29 words short. The
		reviewer measured it on this fixture: `solves 20 -> 22`, epoch FROZEN at 19,
		`pending FALSE`, and the box 150 px around a word that needs 324 — which is F2's
		defect restored by F1's own fix, and STRICTLY WORSE than not shipping reader 1
		at all (without it the surface strands LOUDLY, pending true, with the
		presenter's deadline as the escape hatch).

		AND THE NARROWING WAS NOT THE CAUSE, which is why this case exists rather than
		the one-line remedy the review proposed. Making the forced solve UNNARROWED on
		the owed arm (`dirtyContains, measureContains = nil, nil`) was measured on this
		exact drive and changed NOTHING — `solves 22`, epoch 19, `w 150`, byte for byte
		the stranded reading — because `render/text_index` unions the text-dirty paths
		into an empty closure anyway. The cause is one line further back, and it is the
		same line fix round 2 already found on the mount path: the CLASSIFICATION MARK.
		So reader 4 withholds it while a round is owed, `solveAndApply`'s own sequence
		test (`root.dirtySeq() ~= nodeDirtySeen`) then takes the full arm and re-marks
		it, and the owed round runs as the drain's own round would have.

		THE SHAPE IS PRODUCTION'S, not a contrivance. A learned width changes no node's
		props on a real surface — the text is a static string — so a full premeasure
		learn moves `root.dirtySeq()` by ZERO there and the next frame's queue is empty
		by itself. This fixture's label is a memo over `textMeasureEpoch`, so it
		manufactures dirt the walk can ride on; one `root.takeDirty()` is what takes that
		crutch away and asks the question the real surface asks. ]]
	it("a `takeDirty()` between the deferral and the next frame does not strand the walk", function()
		withReports(function()
			local CHAIN = CAP * 3
			--[[ ONE TRANSCRIPT, ONE COMPARISON, because the defect is a TABLE of readings
				and an assert that stops at the first one hides the rest. At `b59a01f3` the
				boot arm's epoch is frozen AND the settled arm reads `pending false`; a
				per-line assert would report the first and never reach the second. ]]
			local seen: { string } = {}
			local want: { string } = {}
			for _, bootWindow in { true, false } do
				local name = if bootWindow then "boot" else "settled"
				--[[ THE F2 SHAPE: mount short, open the vocabulary under a drive, so the
					deferral lands inside `refresh` and `initialRender`'s own guard (reader 2)
					is not what this case is asking about. ]]
				local arm = surface({ chain = CHAIN, mountAt = 2, bootWindow = bootWindow })
				arm.controller.initialRender()
				arm.bound:set(CHAIN)
				local before = arm.controller.stats().solves
				arm.controller.refresh()
				-- the premise: a round really was deferred, and it really is carried
				table.insert(
					seen,
					`{name} deferred: solves +{arm.controller.stats().solves - before} pending {arm.controller.textPending()}`
				)
				table.insert(want, `{name} deferred: solves +{CAP + 1} pending true`)
				--[[ AND NOW THE ONE LINE THIS CASE IS. The dirt the deferred round would have
					ridden is taken by a caller — exactly what `initialRender`'s own drain used
					to do — leaving the owed round with nothing but itself. ]]
				local stolen = #arm.root.takeDirty()
				table.insert(seen, `{name} stole dirt: {stolen > 0}`)
				table.insert(want, `{name} stole dirt: true`)
				--[[ ONE FRAME LATER THE WALK HAS MOVED AND IS NOT FINISHED. At `b59a01f3`
					the epoch is frozen where the deferral left it and the settled arm reads
					`pending false` — the reveal gate open, `textRevealedExact` stamped, 29
					words short of the geometry it claims. ]]
				arm.controller.refresh()
				local mid = (arm.env:get("textMeasureEpoch"):get() :: any) or 0
				table.insert(seen, `{name} one frame on: moved {mid > CAP + 3} pending {arm.controller.textPending()}`)
				table.insert(want, `{name} one frame on: moved true pending true`)
				-- ...and ordinary frames finish it
				for _ = 1, 4 do
					arm.controller.refresh()
				end
				--[[ THE EPOCH IS THE WHOLE VOCABULARY, THE BOX IS THE LAST WORD'S OWN WIDTH
					(the epoch alone would pass on a surface that learned every width and never
					re-laid itself out, which is what the reviewer's 138 px box was), AND THE
					GATE OPENS AGAIN on the settled adapter. The boot-window arm stays pending
					for the reason the mount case states: `final = false` leaves every answered
					word in flight until the engine's settled re-read, which is the boot window
					and not the deferral. ]]
				local r = arm.controller.rectOf("/Root/Chain")
				table.insert(
					seen,
					`{name} converged: epoch {(arm.env:get("textMeasureEpoch"):get() :: any) or 0} `
						.. `w {if r ~= nil then r.w else -1} pending {arm.controller.textPending()}`
				)
				table.insert(
					want,
					`{name} converged: epoch {CHAIN} w {widthOf(arm.words[CHAIN], 12, "")} `
						.. `pending {if bootWindow then "true" else "false"}`
				)
				arm.controller.dispose()
			end
			expect(table.concat(seen, "\n")).toBe(table.concat(want, "\n"))
		end)
	end)

	--[[ ── A THROWING FRAME EATS ONLY WHAT IT QUEUED (C-3 fix round 2, F3) ────────────

		WHAT WAS WRONG. `owed` was cleared unconditionally when the OUTERMOST solve
		threw, under a comment that is true of a re-solve that solve queued ("the state
		it was asked against never landed") and false of one a PREVIOUS frame deferred.
		One throwing frame therefore cancelled a deferral it had nothing to do with, and
		the surface lost the round in silence — the same permanent-clip outcome as F1,
		reached from the other side. So the value at ENTRY is remembered and restored,
		and only what this solve itself queued is discarded with it. ]]
	it("a throwing frame discards its own queued re-solve, not one a previous frame deferred", function()
		withReports(function()
			local solves, tails = 0, 0
			local converge, boom = false, false
			local run: () -> ()
			run = solve_queue.trampoline({
				solve = function()
					solves += 1
					if boom then
						error("OUTER BOOM", 0)
					end
					if not converge then
						run()
					end
				end,
				tail = function()
					tails += 1
				end,
			})
			-- frame 1 trips the cap and defers a round
			run()
			expect(`after defer: solves {solves} tails {tails}`).toBe(`after defer: solves {CAP + 1} tails {CAP + 1}`)
			-- frame 2's outermost solve throws BEFORE it can queue anything of its own
			boom = true
			local threw = not (pcall(run))
			expect(`throwing frame: threw {threw} solves {solves}`).toBe(`throwing frame: threw true solves {CAP + 2}`)
			--[[ frame 3 is healthy, and runs TWO solves: its own, plus the round frame 1
				deferred and frame 2 had no business cancelling. `+1` is the defect. ]]
			boom, converge = false, true
			local before = solves
			run()
			expect(`recovery: solves +{solves - before}`).toBe("recovery: solves +2")
		end)
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
