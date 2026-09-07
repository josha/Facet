--!strict
--[[
	OVER THE CAP, THE LEAVES ARE ASKED BEFORE THE TREE IS (Plan D, D3c; scout S2 §4b).

	THE MISS THIS FILE EXISTS FOR, live, settled, in a fresh client VM at D2/D3a:
	`battle_hud updateItem-facing [S]` **47.5 ms**, `war_room updateItem-power [S]`
	**70.4 ms**, `war_room addItem-items [S]` **75.6 ms** — each with `lastMeasured ==
	lastMeasureCalls` (14,263 and 20,505), the signature of a whole-tree COLD solve. A
	settled step that learns ONE word at a (font,size) ~1,000 mounted labels share is
	over `render/text_index`'s push cap, `take` answers `full`, and the caller drops
	its closure. It is 50 of `war_room`'s 600 settled steps.

	AND THE CAP IS NOT THE LEVER. D3b re-swept the crossover after D1 and D2 and the
	band did not move (~13-21 % of the tree): a push naming a third of the tree really
	is slower than the cold solve it replaces, because its ancestor closure reaches the
	root and every container pays a reuse protocol that then fails. What IS the lever
	is the observation the push never made: a token correction moves almost none of the
	labels filed under its key. `battle_hud`'s 1,000 facing labels draw 360 distinct
	values; `war_room`'s 1,500 power labels draw 999. One learned word moves the two or
	three labels that draw it.

	SO THE PROBE RE-MEASURES EACH PUSHED LEAF and only the MOVED ones reach
	`dirty_closure.of`. It stays right — every label drawing a corrected token is still
	re-solved, because the probe asks each LABEL rather than trusting the string that
	was written (a word is a TOKEN shared across labels; that is the fix-round-1
	correction this file's cap paragraph carries).

	WHAT IS PINNED HERE, and the four numbers are the whole claim:

	  | drive                                    | probes | paths | route |
	  |------------------------------------------|-------:|------:|-------|
	  | a word at the key that NOBODY draws      |  1,001 |     0 | empty closure |
	  | a word TEN of 1,001 labels draw          |  1,001 |    10 | narrow push |
	  | a word EVERY label draws                 |  1,001 |     — | still over cap -> `full` |
	  | anything UNDER the cap                   |      0 |     n | unchanged |

	THE ORACLE DOES NOT SHARE THE SWITCH. Every geometry case is driven twice — through
	the probe and through a FORCED COLD arm (`incrementalLayout = false` AND
	`measureReuse = false`, the shape `tests/text_settle_closure.spec.luau` settled on)
	— and compared channel for channel: rects and scalar props, `textFacts`, `compact`,
	`textStates`, the adapter's writes and `controller.diagnostics()`. The cold arm
	asserts its own coldness so the oracle cannot quietly become two stale arms
	agreeing.

	AND THE CASE THE BRIEF NAMES BY HAND: a fixed-width label whose BOX cannot move and
	whose `truncated` verdict flips on the correction. If the probe dropped that leaf
	it would be wrong, and it does not — the verdict is `m.width > availW` and the
	probe's whole question is whether `m.width` moved.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local text_metrics = require("../src/layout/text_metrics")

local FONT = "BuilderSans"
-- the WIDE key: every row label and the pinned label sit at this size, so one
-- learned word names 1,001 paths of a 3,003-node tree — 33 %, the far end of D3b's
-- band and the shape `full` was the only answer for
local SIZE_ROW = 12
-- ...and a key with ONE user, for the under-cap control
local SIZE_SOLO = 18

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

type Arm = {
	core: any,
	env: any,
	controller: any,
	adapter: any,
	rowValue: { any },
	solo: any,
	pinned: any,
	rows: number,
}

--[[ THE FIXTURE, and its two shapes matter. `words(i)` decides how many labels draw
	the SAME string, which is the only variable this file moves: the tree, the key and
	the node count are identical across every case, so a difference in the counters is
	a difference in what the correction actually moved and nothing else.

	`PINNED` is the fixed-width label — 60px whatever it measures — whose truncation
	verdict is a function of the measured width against that box. It shares the wide
	key on purpose: it is inside every push, and it is the one node in the tree whose
	published fact can move while its rect stands still. ]]
local function world(
	opts: {
		rows: number,
		words: (i: number) -> string,
		-- the fixed-width label's own string, per case: the exact-width store is
		-- PROCESS-GLOBAL, so a shared literal would be corrected by the first case and
		-- already known to every later one, whose settle would then never happen
		pin: string?,
		incremental: boolean?,
		measureReuse: boolean?,
		fit: boolean?,
	}
): Arm
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 600 })
	local rowValue = {}
	local rowChildren = {}
	for i = 1, opts.rows do
		rowValue[i] = core:signal(if i <= (opts.phrases or 0) then `phrase {i} here` else opts.words(i))
		rowChildren[i] = UI.HStack({
			id = `R{i}`,
			padding = 0,
			gap = 2,
			width = fill(),
			height = px(16),
			children = {
				UI.Text({ id = "A", textSize = SIZE_ROW, text = rowValue[i] }),
				UI.Box({ id = "B", width = px(10), height = px(6) }),
			},
		})
	end
	local pinned = core:signal(opts.pin or "pin")
	local solo = core:signal("solo")
	table.insert(rowChildren, UI.Text({ id = "Pinned", textSize = SIZE_ROW, width = px(60), text = pinned }))
	table.insert(
		rowChildren,
		if opts.fit
			then UI.Text({ id = "Fitted", textSize = "fit", width = px(70), height = px(20), text = solo })
			else UI.Text({ id = "Solo", textSize = SIZE_SOLO, text = solo })
	)
	local bp = UI.VStack({
		id = "Root",
		padding = 0,
		gap = 0,
		width = fill(),
		height = fill(),
		children = {
			UI.VStack({ id = "List", padding = 0, gap = 1, width = fill(), children = rowChildren }),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "coreSafeContent",
		incrementalLayout = opts.incremental,
		measureReuse = opts.measureReuse,
	})
	controller.initialRender()
	return {
		core = core,
		env = env,
		controller = controller,
		adapter = adapter,
		rowValue = rowValue,
		solo = solo,
		pinned = pinned,
		rows = opts.rows,
	}
end

-- one width per word, deterministic and shared by every arm: an arm that answered
-- differently would be a different experiment, not a control
local function widthOf(word: string, size: number, _font: string): number?
	return math.max(1, #word * size * 0.5)
end

local function deliverAll(arm: Arm)
	arm.adapter.deliverTextWidths(widthOf)
end

-- drive to SETTLED — solve, answer, repeat until nothing is outstanding. A drive that
-- does not do this measures the boot window, which is how the campaign's live matrix
-- read 3.4 ms on a class a settled session pays 39.7 ms for.
local function settle(arm: Arm)
	for _ = 1, 8 do
		arm.controller.refresh()
		if arm.adapter.textBatchCount() == 0 then
			break
		end
		deliverAll(arm)
	end
	arm.controller.refresh()
end

local function stats(arm: Arm): any
	return arm.controller.stats()
end

--[[ THE SETTLED FLOOR, and it has to be an ORDINARY INCREMENTAL TICK rather than a
	no-op refresh. Two reasons, and the second one cost a red run to find:

	  * the counters below belong to a SOLVE, and the last refresh of the settle loop
	    may not have solved at all — a read straight after it is the boot window's last
	    push (`text_settle_closure.spec` learned that half);
	  * and a solve that follows a FULL one serves nothing. `renderer.solveOnce` calls
	    `measure_reuse.clear` whenever the solve it is about to run has no reuse set, so
	    the cross-solve store is empty for exactly one solve afterwards (T6's known
	    cost, booked as Plan D's D5). Measured here: a settle taken straight off the
	    mount reads `measured=3004` on a 3,004-node tree with an EMPTY closure —
	    everything refused, nothing stale, and a number that says nothing about the
	    narrowing. One ordinary incremental tick first, and the same settle reads 0.

	It moves the SOLO label, which sits at its own key with one user: a tick that
	cannot disturb the wide key the cases below measure. ]]
local function quiesce(arm: Arm): any
	arm.solo:set("t18dQuiesce")
	arm.controller.refresh()
	deliverAll(arm)
	arm.controller.refresh()
	return table.clone(stats(arm))
end

-- the settle a learned word actually takes: the width lands in the store, the store
-- announces the (font,size), and the surface hears about it through the
-- `textMeasureEpoch` geometry fact — the BARE route, no caller closure standing
local function learn(arm: Arm, word: string, width: number)
	expect(text_metrics.setMeasured(FONT, SIZE_ROW, word, width)).toBe(true)
	arm.env:set("textMeasureEpoch", ((arm.env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
end

-- ---- the oracle's channels ------------------------------------------------
-- the same four `tests/text_settle_closure.spec.luau` settled on, and deliberately
-- the same four: this file is asking that spec's question at a push size it could
-- not reach, so an answer written against different channels would not be comparable.
local function painted(adapter: any): string
	local out = {}
	for path, node in adapter.liveNodes() do
		local props = {}
		for k, v in node.props or {} do
			if type(v) == "table" then
				local inner = {}
				for k2, v2 in v do
					table.insert(inner, `{tostring(k2)}={tostring(v2)}`)
				end
				table.sort(inner)
				table.insert(props, `{k}=\{{table.concat(inner, ",")}\}`)
			else
				table.insert(props, `{k}={tostring(v)}`)
			end
		end
		table.sort(props)
		local r = node.rect
		local hit = adapter.hitRectOf(path)
		table.insert(
			out,
			`{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}`
				.. `|hit={if hit then `{hit.x},{hit.y},{hit.w},{hit.h}` else "-"}`
				.. `|{table.concat(props, ",")}`
		)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

-- `textAt` is the published `textFacts` channel — `truncated`, `lines`, `policy`,
-- `wraps`, `compact`'s companion `size` — which is where a dropped leaf would go
-- stale without its rect ever saying so
local function facts(controller: any): string
	local out = {}
	for path, f in controller.textAt() do
		local parts = {}
		for k, v in f do
			table.insert(parts, `{tostring(k)}={tostring(v)}`)
		end
		table.sort(parts)
		table.insert(out, `{path}|{table.concat(parts, ",")}`)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

local function findings(controller: any): string
	local seen: { [string]: boolean } = {}
	local out = {}
	for _, d in controller.diagnostics() do
		local key = `{tostring(d.node)}: {tostring(d.issue)}`
		if not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
	end
	table.sort(out)
	return table.concat(out, "\n")
end

local function reads(controller: any, adapter: any): string
	local out = {}
	for path in adapter.liveNodes() do
		local r = controller.rectOf(path)
		local sr = controller.screenRectOf(path)
		table.insert(
			out,
			`{path}|r={if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}`
				.. `|s={if sr then `{sr.x},{sr.y},{sr.w},{sr.h}` else "-"}`
		)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

local function snapshot(arm: Arm): string
	return `{painted(arm.adapter)}\n--facts--\n{facts(arm.controller)}\n--reads--\n{reads(arm.controller, arm.adapter)}`
		.. `\n--diag--\n{findings(arm.controller)}`
end

--[[ THE COLD CONTROL, and it asserts its own coldness. The settle re-solve was cold
	BY ACCIDENT before Plan C routed it, so an oracle that merely drove "the old way"
	would after this change be two arms of the same new code agreeing with each other.
	Both knobs off: `incrementalLayout = false` removes the arrange skip and
	`measureReuse = false` removes the cross-solve store AND the node-resident serve.
	`measureReuse = false` also means the solver's own `mTextW` cache is beside the
	point on this arm — it takes the whole tree whatever the probe would have said. ]]
local function coldArm(opts: { rows: number, words: (i: number) -> string, pin: string?, fit: boolean? }): Arm
	return world({
		rows = opts.rows,
		words = opts.words,
		pin = opts.pin,
		incremental = false,
		measureReuse = false,
		fit = opts.fit,
	})
end

local function assertCold(arm: Arm, label: string)
	local st = stats(arm)
	expect(`{label} whole tree? arranged={st.lastArranged} of {st.lastLayoutNodes}`).toBe(
		`{label} whole tree? arranged={st.lastLayoutNodes} of {st.lastLayoutNodes}`
	)
	expect(st.lastMeasured >= st.lastLayoutNodes).toBe(true)
end

local ROWS = 1000
local function distinct(i: number): string
	return `w{i}`
end

describe("the over-cap push probes its leaves (Plan D, D3c)", function()
	it("THE HEADLINE: a word at the wide key that NOBODY draws costs 1,001 probes and 0 paths", function()
		local arm = world({ rows = ROWS, words = distinct, pin = "pinA" })
		settle(arm)
		local quiet = quiesce(arm)
		--[[ THE TREE AND THE CAP, read off the run rather than assumed: 1,001 labels
			share the wide key on a 3,003-node tree, so the push is 33 % of it — the far
			end of D3b's band, where the cold solve genuinely wins and `full` was the
			only answer. ]]
		expect(`nodes={quiet.lastLayoutNodes} cap={math.max(64, quiet.lastLayoutNodes // 8)}`).toBe(
			"nodes=3004 cap=375"
		)
		local before = quiet.solves

		learn(arm, "t18dNobodyDrawsThis", 41)
		local st = stats(arm)
		--[[ THE FOUR NUMBERS. `probes` is what the narrowing COST — one unbounded
			measure per single-word leaf, with no solver protocol around it — and
			`paths` what it BOUGHT. Every one of the 1,001 labels was asked and none of
			them moved, because none of them draws the corrected token. ]]
		expect(
			`solves={st.solves - before} probes={st.lastTextProbeMeasures} paths={st.lastTextDirtyPaths} `
				.. `measured={st.lastMeasured} arranged={st.lastArranged}`
		).toBe("solves=1 probes=1001 paths=0 measured=0 arranged=0")
	end)

	it("...and a word TEN of them draw pushes exactly those ten, on the same tree", function()
		local arm = world({
			rows = ROWS,
			pin = "pinTen",
			words = function(i: number): string
				return if i <= 10 then "t18dTenShare" else distinct(i)
			end,
		})
		settle(arm)
		local quiet = quiesce(arm)
		local before = quiet.solves
		--[[ A WIDTH THE ESTIMATOR DID NOT GIVE IT. `settle` answered "t18dShared" at
			`widthOf` already, so this is a CORRECTION of a known word rather than a
			first sighting — which is the shape a settled session actually produces
			(a re-measure after a preference or font swap) and the one that proves the
			probe is comparing against the last SOLVE's answer, not against "is this
			word known". ]]
		learn(arm, "t18dTenShare", widthOf("t18dTenShare", SIZE_ROW, FONT) :: number + 9)
		local st = stats(arm)
		expect(`solves={st.solves - before} probes={st.lastTextProbeMeasures} paths={st.lastTextDirtyPaths}`).toBe(
			"solves=1 probes=1001 paths=10"
		)
		--[[ ...AND THE MEASURES, which is the counter the defect was found in: ten
			labels plus the ancestor chain the closure reaches, against the 3,003-node
			whole-tree solve this route used to take. `lastMeasured == lastMeasureCalls`
			is the cold-solve signature; here they are three orders of magnitude apart. ]]
		expect(st.lastMeasured < 100).toBe(true)
		expect(st.lastMeasured > 0).toBe(true)
		expect(st.lastArranged < 200).toBe(true)
	end)

	it("...and a word EVERY label draws is still over the cap, so the answer is still `full`", function()
		local arm = world({
			rows = ROWS,
			pin = "pinAll",
			words = function(_i: number): string
				return "t18dAllOfThem"
			end,
		})
		settle(arm)
		local quiet = quiesce(arm)
		local before = quiet.solves
		learn(arm, "t18dAllOfThem", widthOf("t18dAllOfThem", SIZE_ROW, FONT) :: number + 7)
		local st = stats(arm)
		--[[ THE PROBE IS NOT A LICENCE TO NARROW. 1,000 of the 1,001 leaves moved,
			which is over the cap, and over the cap the answer is the whole-tree solve
			exactly as it was — `paths=0` is `full`'s own signature (the caller drops
			its closure), and the solve is cold. The probe's cost is paid and refunded
			nothing here, which is the honest worst case and the reason the ABBA has a
			control arm. ]]
		expect(`solves={st.solves - before} probes={st.lastTextProbeMeasures} paths={st.lastTextDirtyPaths}`).toBe(
			"solves=1 probes=1001 paths=0"
		)
		--[[ AND IT REALLY IS THE WHOLE TREE: every layout node arranged, which is the
			property `assertCold` uses and the one that survives the per-solve memo
			(a fully cold solve on a small tree serves a node's second ask from its
			first, so `lastMeasured == lastMeasureCalls` is a LIVE signature and not a
			headless one — `text_settle_closure.spec`'s own coldness note). ]]
		expect(`arranged={st.lastArranged} of {st.lastLayoutNodes}`).toBe(
			`arranged={st.lastLayoutNodes} of {st.lastLayoutNodes}`
		)
		expect(st.lastMeasured > st.lastLayoutNodes).toBe(true)
	end)

	it("UNDER the cap nothing is probed at all — the route this file does not touch", function()
		local arm = world({ rows = ROWS, words = distinct, pin = "pinUnder" })
		settle(arm)
		local quiet = quiesce(arm)
		local before = quiet.solves
		--[[ THE SOLO LABEL'S KEY has one user, which is under the 375 cap by three
			orders of magnitude, so `take` builds the closure straight from the push and
			the probe never runs. That is the whole under-cap contract: byte-identical
			to the parent SHA, which is what keeps the differential md5 still. ]]
		expect(text_metrics.setMeasured(FONT, SIZE_SOLO, "t18dSoloWord", 44)).toBe(true)
		arm.env:set("textMeasureEpoch", ((arm.env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
		local st = stats(arm)
		expect(`solves={st.solves - before} probes={st.lastTextProbeMeasures} paths={st.lastTextDirtyPaths}`).toBe(
			"solves=1 probes=0 paths=1"
		)
	end)

	it("a MULTI-WORD label is never probed, and is pushed because it could not be", function()
		--[[ THE RESTRICTION, DRIVEN. A phrase is measured against a box its PARENT
			chose (`availW`), and reconstructing that number outside the solve is the
			offer-versus-occupied trap the solver has had to be fixed for twice — so a
			phrase has no cached width for the probe to compare against and stays in the
			push. Five of the 1,001 leaves are phrases here: `probes` counts 996, and
			`paths` is 5 even though the correction moved nothing any of them draws.

			The failure direction is the one this file takes everywhere: a leaf the
			probe cannot answer for is a leaf that stays in the push. ]]
		local arm = world({ rows = ROWS, words = distinct, pin = "pinPhrase", phrases = 5 })
		settle(arm)
		local quiet = quiesce(arm)
		local before = quiet.solves
		learn(arm, "t18dNobodyDrawsThisThird", 39)
		local st = stats(arm)
		expect(`solves={st.solves - before} probes={st.lastTextProbeMeasures} paths={st.lastTextDirtyPaths}`).toBe(
			"solves=1 probes=996 paths=5"
		)
	end)

	it("the probe does not ASK for the words it measures", function()
		--[[ TRAP 1 OF THE BRIEF. The probe re-measures labels the solve is about to
			SERVE, and `text_metrics.measure` COLLECTS when a collector is open — so a
			probe taken inside the solve's own bracket would file those labels' unknown
			words as engine REQUESTS, and the surface would ask for widths it is not
			going to draw a different box for. `textMeasureBatches` is a published
			observable, so that is a correctness question and not a cost one. This case
			pins the contract: one row draws a word the target has been asked about and
			never answered, and the settle that probes it produces NO batch.

			▲ AND THE MUTATION THAT SHOULD REDDEN IT DOES NOT — a KEPT NULL, recorded
			here because it is a design fact about two OTHER mechanisms rather than a
			gap in this one. Leaving the collector open across the probe changes nothing
			observable, and the reason is that a word this surface has already asked
			about cannot be re-asked and cannot be collected either way:

			  * an ANSWERED word is a number in the store, so `wordWidth` never reaches
			    its collect branch;
			  * a REFUSED one is `false` in the store (`markUnmeasurable`), which is
			    also not `nil`, so the collect branch is not reached;
			  * an IN-FLIGHT one is collected but `render/premeasure_round.request`
			    refuses to dispatch a key its own `textInFlight` set already holds
			    (line 95), so no batch leaves;
			  * and a word answered with `final = false` is parked as `"answered"`,
			    which is still in flight, so the same refusal applies.

			The one window left is a word this surface has NEVER asked about, which
			after D3a means only a collector that hit `COLLECT_CAP` — a vocabulary over
			1,024 distinct words at one key, which is `tests/text_collect_inflight.spec
			.luau`'s fixture and not this one. The suspension is kept because that
			window is real and because a probe that can silently widen a published
			request set is not a probe anyone should have to reason about at the call
			site; it is recorded as a null rather than claimed as a covered reader. ]]
		local arm = world({ rows = ROWS, words = distinct, pin = "pinAsk" })
		settle(arm)
		quiesce(arm)
		arm.rowValue[5]:set("t18dNeverAnswered")
		arm.controller.refresh()
		local batches = stats(arm).textMeasureBatches
		expect(arm.adapter.textBatchCount() > 0).toBe(true)

		local before = stats(arm).solves
		learn(arm, "t18dNobodyDrawsThisToo", 42)
		local st = stats(arm)
		expect(
			`solves={st.solves - before} probes={st.lastTextProbeMeasures} batches={st.textMeasureBatches - batches}`
		).toBe("solves=1 probes=1001 batches=0")
	end)

	it("a label RELABELLED since the last push is probed as it is NOW, not as it was", function()
		--[[ THE STALENESS THIS CANNOT HAVE. The probe holds the layout node LITERAL,
			and `render/layout_node.build` constructs a fresh literal for every node in
			the ancestor-closed dirty set — so a node whose text changed is never the
			table the index was holding. `record` writes the literal BEFORE its
			unchanged-(font,size) guard for exactly this reason: the key can stand still
			across a rebuild while the table underneath it is replaced.

			Driven end to end: one row is relabelled to a word the estimator has never
			seen, the target answers it with a width the estimate did not give it, and
			the resulting push must name THAT row. Holding the pre-relabel literal would
			measure the OLD string, find it unchanged and drop the row — leaving it on
			the estimator's box, which the cold arm's rects would then disagree with. ]]
		local hot = world({ rows = 200, words = distinct, pin = "t18dRelabelPin" })
		local cold = coldArm({ rows = 200, words = distinct, pin = "t18dRelabelPin" })
		settle(hot)
		settle(cold)
		expect(painted(hot.adapter)).toBe(painted(cold.adapter))
		quiesce(hot)
		quiesce(cold)
		for _, arm in { hot, cold } do
			arm.rowValue[5]:set("t18dRelabel")
			arm.controller.refresh()
			arm.adapter.deliverTextWidths(function(word: string, size: number, font: string): number?
				return if word == "t18dRelabel" then 137 else widthOf(word, size, font)
			end)
		end
		local st = stats(hot)
		expect(`probes={st.lastTextProbeMeasures} paths={st.lastTextDirtyPaths}`).toBe("probes=201 paths=1")
		expect(painted(hot.adapter)).toBe(painted(cold.adapter))
		expect(facts(hot.controller)).toBe(facts(cold.controller))
	end)

	it('a `textSize = "fit"` node bypasses the probe and is pushed with nothing to compare', function()
		--[[ THE CONSERVATIVE SET SURVIVES THE NARROWING. A fit node's ladder measures
			its string at SEVERAL sizes inside the band before choosing one, so a width
			learned at a size it merely PROBED can change its rung — the index files the
			size it CHOSE, and that key is not the whole truth. Those nodes are in
			`always`, which joins every push, and the probe must not ask them a question
			whose answer would be about the wrong size.

			So on a drive where NOTHING moved, `paths` is 1 rather than 0 and `probes`
			counts 1,001 rather than 1,002: the fit node was pushed without being
			measured. ]]
		local arm = world({ rows = ROWS, words = distinct, pin = "pinFit", fit = true })
		settle(arm)
		local quiet = quiesce(arm)
		local before = quiet.solves
		learn(arm, "t18dNobodyDrawsThisEither", 43)
		local st = stats(arm)
		expect(`solves={st.solves - before} probes={st.lastTextProbeMeasures} paths={st.lastTextDirtyPaths}`).toBe(
			"solves=1 probes=1001 paths=1"
		)
	end)
end)

describe("the probe's oracle: identical channels, whatever the push did (D3c)", function()
	--[[ BOTH ARMS ARE SETTLED BEFORE ANYTHING IS CORRECTED, and they are compared
		BEFORE the correction too. The exact-width store is process-global, so an arm
		settled AFTER the other one had already learned the corrected width would never
		see the correction at all — and a byte-equal comparison afterwards would say
		nothing about the settle. `text_settle_closure.spec` names that trap; this is
		the same discipline at a push size it cannot reach. ]]
	local function share10(i: number): string
		return if i <= 10 then "t18dOracleShare" else distinct(i)
	end

	-- one correction, applied to the store once and seen by both arms; each arm is
	-- then told about it the way a premeasurement round tells one — the geometry fact
	local function announceTo(arm: Arm)
		arm.env:set("textMeasureEpoch", ((arm.env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
	end

	it("a narrowed over-cap settle equals a forced cold one, channel for channel", function()
		--[[ 200 ROWS PUTS THE PUSH AT 201 AGAINST A CAP OF 75, so this drive is over
			the cap on both counts and the probe really runs; eleven of the 201 leaves
			move (the ten sharing a word, and the pinned label whose own word is
			corrected), which is under the cap, so the hot arm takes a NARROW push where
			it used to take the whole tree. ]]
		local hot = world({ rows = 200, words = share10, pin = "t18dOraclePin" })
		local cold = coldArm({ rows = 200, words = share10, pin = "t18dOraclePin" })
		settle(hot)
		settle(cold)
		-- THE NON-VACUITY GUARD: the arms must already agree, or the comparison after
		-- the correction is a comparison of two things that were never the same
		expect(snapshot(hot) == snapshot(cold)).toBe(true)
		quiesce(hot)
		quiesce(cold)

		expect(
			text_metrics.setMeasured(
				FONT,
				SIZE_ROW,
				"t18dOracleShare",
				widthOf("t18dOracleShare", SIZE_ROW, FONT) :: number + 9
			)
		).toBe(true)
		expect(text_metrics.setMeasured(FONT, SIZE_ROW, "t18dOraclePin", 61)).toBe(true)
		announceTo(hot)
		announceTo(cold)

		assertCold(cold, "cold arm")
		local st = stats(hot)
		--[[ ...AND THE HOT ARM REALLY NARROWED, or the equality below is two whole-tree
			solves agreeing. Eleven paths of 201 probed, on a 604-node tree. ]]
		expect(`probes={st.lastTextProbeMeasures} paths={st.lastTextDirtyPaths}`).toBe("probes=201 paths=11")
		expect(st.lastMeasured < st.lastLayoutNodes).toBe(true)
		expect(snapshot(hot) == snapshot(cold)).toBe(true)
	end)

	it("...and the PINNED label's truncation verdict flips while its rect does not move", function()
		--[[ THE CASE THE BRIEF NAMES BY HAND, and the one that would prove the probe
			WRONG if it dropped that leaf. `Pinned` is 60px wide whatever it measures,
			so the adapter's rect channel says nothing happened — but `truncated` is
			`m.width > availW`, so a correction carrying the measured width across 60
			flips a PUBLISHED fact with no geometry behind it. The fuzz that found
			BLOCKER-1 in this family found exactly this class before.

			The probe cannot miss it, and the reason is structural rather than lucky:
			its whole question is whether `m.width` moved, and a verdict that is a
			function of `m.width` against an unchanged box cannot move while `m.width`
			stands still. A label sitting exactly on the boundary got there BY the
			correction, so the width did move and the leaf is pushed. ]]
		local hot = world({ rows = 200, words = distinct, pin = "t18dFlip" })
		local cold = coldArm({ rows = 200, words = distinct, pin = "t18dFlip" })
		settle(hot)
		settle(cold)
		expect(snapshot(hot) == snapshot(cold)).toBe(true)
		quiesce(hot)
		quiesce(cold)
		local was = facts(hot.controller):match("/Root/List/Pinned|[^\n]*") :: string
		expect(`before: {if was:find("truncated=false") then "not cut" else "cut"}`).toBe("before: not cut")

		expect(text_metrics.setMeasured(FONT, SIZE_ROW, "t18dFlip", 61)).toBe(true)
		announceTo(hot)
		announceTo(cold)

		local st = stats(hot)
		-- ONE leaf of 201 moved, and it is the one whose rect cannot
		expect(`probes={st.lastTextProbeMeasures} paths={st.lastTextDirtyPaths}`).toBe("probes=201 paths=1")
		local now = facts(hot.controller):match("/Root/List/Pinned|[^\n]*") :: string
		expect(`after: {if now:find("truncated=true") then "cut" else "not cut"}`).toBe("after: cut")
		local rect = hot.adapter.liveNodes()["/Root/List/Pinned"].rect
		expect(`pinned box {rect.w}`).toBe("pinned box 60")
		assertCold(cold, "cold arm")
		expect(snapshot(hot) == snapshot(cold)).toBe(true)
	end)

	it("a CEILING-ABSORBED correction moves nothing, and the probe says so", function()
		--[[ THE SUB-PIXEL CASE, which is the sharpest statement of what `mTextW` is.
			`text_metrics.measure` returns `ceil(widest)`, so a word whose exact width
			moves from 48.0 to 47.6 produces the identical box, the identical
			`truncated` verdict and the identical published facts. There is nothing to
			re-solve, and the probe drops all 201 leaves — the same answer the
			forced-cold arm arrives at by re-measuring the whole tree, which is what
			makes this an oracle rather than a restatement of the mechanism. ]]
		local function shareCeil(i: number): string
			return if i <= 10 then "t18dCeil" else distinct(i)
		end
		local hot = world({ rows = 200, words = shareCeil, pin = "t18dCeilPin" })
		local cold = coldArm({ rows = 200, words = shareCeil, pin = "t18dCeilPin" })
		settle(hot)
		settle(cold)
		expect(snapshot(hot) == snapshot(cold)).toBe(true)
		quiesce(hot)
		quiesce(cold)
		local base = widthOf("t18dCeil", SIZE_ROW, FONT) :: number
		expect(text_metrics.setMeasured(FONT, SIZE_ROW, "t18dCeil", base - 0.4)).toBe(true)
		announceTo(hot)
		announceTo(cold)
		local st = stats(hot)
		expect(
			`probes={st.lastTextProbeMeasures} paths={st.lastTextDirtyPaths} measured={st.lastMeasured} arranged={st.lastArranged}`
		).toBe("probes=201 paths=0 measured=0 arranged=0")
		assertCold(cold, "cold arm")
		expect(snapshot(hot) == snapshot(cold)).toBe(true)
	end)
end)
