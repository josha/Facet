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
local function surface(opts: {
	chain: number,
	share: { core: any, env: any }?,
	prefix: string?,
	tag: string?,
	stride: number?,
}): Arm
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
	adapter.answerTextInline(widthOf)
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
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
