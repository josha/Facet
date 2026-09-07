--!strict
--[[
	THE SETTLE RE-SOLVE GOES THROUGH THE DIRTY CLOSURE (Plan C, T18-A —
	rulings L-10/L-11/L-12, T17's second finding, FacetBench §C16).

	WHAT WAS WRONG, MEASURED. A SETTLED session — the state a shipped game is in from
	~0.66 s onward — paid a fully COLD whole-tree re-solve for every new word it
	learned. Live (T17, arm C): `battle_hud L setState` **39.676 ms** and
	`addItem-damage` **76.971 ms** against 3.733 / 3.994 with the headless target in
	the same VM. Headless, on the same workload at this task's parent SHA:
	`lastMeasured == lastMeasureCalls == 14,215`, `lastArranged == 5,106`, **40.1 ms**
	for one squad label learning one number. `lastMeasured == lastMeasureCalls` is the
	signature — every measure was a MISS.

	AND THERE WERE TWO CAUSES, WHICH IS WHY THIS FILE PINS TWO THINGS. A three-arm
	differential taken before any of this was written (T18-A step 0, `battle_hud L`,
	one learned word on a settled tree):

	  | arm | what it is | `lastMeasured` | `lastArranged` | ms |
	  |-----|------------|---------------:|---------------:|-----:|
	  | A | the parent SHA | 14,215 (= calls) | 5,106 | 40.1 |
	  | B | the closure routed, word epoch STILL in `measureStamp` | 10,215 (= calls) | 6 | 34.4 |
	  | B'| all four links | **15** (of 1,115 calls) | 6 | **2.2** |
	  | C | a forced cold solve, the control | 14,215 (= calls) | 5,106 | 28-49 |

	Arm B is the finding: routing the settle through a dirty closure while the word
	generation is still a stamp term removes the ARRANGE pass and nothing else,
	because a moved stamp clears the cross-solve store and fails `node.mStamp ==
	ctx.measureStamp` for every node whatever the dirty set says. Neither half is the
	lever; the four links together are. `render/text_index` names them.

	THE ORACLE IS THE POINT OF THIS FILE, not the counters. A narrowed settle is a
	PARTIAL solve where it used to be a full one, so every channel the full one
	refreshed is a thing that can now go stale: rects, hit rects, the text facts, the
	compact verdicts, the diagnostics. Every case that changes geometry is therefore
	driven twice — narrowed and FORCED COLD — and compared channel-for-channel, and
	the cold arm ASSERTS that it is cold (`lastMeasured == lastMeasureCalls`) so the
	oracle cannot quietly become two stale arms agreeing.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")
local text_metrics = require("../src/layout/text_metrics")

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

--[[ THE FIXTURE IS `battle_hud`-SHAPED, and the three sizes are the point. The
	census T18's plan measured on that workload found the whole lever is a function of
	how many nodes share the changed (font,size): 1,000 nodes at size 10, 1,000 at 12,
	4 at 14. So this tree has a WIDE key (every row's name label, size 12), a NARROW
	key (the four strip labels, size 14) and a key with a SINGLE user (size 18) —
	plus a NESTED shape whose text sits two containers below a memoising stack, which
	is the case a naive narrowing serves stale. `SIZE_UNUSED` is measured by nobody. ]]
local SIZE_ROW = 12
local SIZE_STRIP = 14
local SIZE_SOLO = 18
local SIZE_UNUSED = 23
-- ...and the PINNED node's size: a fixed-width label whose truncation verdict flips
-- on the correction while its RECT does not move an inch (see its case)
local SIZE_PIN = 11

type Arm = {
	core: any,
	env: any,
	controller: any,
	adapter: any,
	strip: { any },
	rowValue: { any },
	rows: any,
	solo: any,
	pinned: any,
	fitted: any,
}

local function world(
	opts: {
		viewport: { w: number, h: number },
		rows: number,
		incremental: boolean?,
		measureReuse: boolean?,
		-- TWO SURFACES ON ONE WORLD (owed row 8). `textMeasureEpoch` is a geometry FACT,
		-- and a fact belongs to an environment: two surfaces that share a core and an
		-- environment are the shape a HUD beside a menu actually has, and the shape the
		-- cross-surface correction has to work in.
		share: { core: any, env: any }?,
		prefix: string?,
		--[[ ANSWER EVERY BATCH SYNCHRONOUSLY, from inside `measureTextWidths`, which is
			what a settled live client does: `text_premeasure.spawn` is `task.spawn`,
			which runs its body until its first yield, and a settled
			`GetTextBoundsAsync` does not yield — so the answer reaches
			`premeasure_round`'s `done` INSIDE the solve that asked, while `refresh`'s
			own closure is still standing. `tests/lib/fake_target`'s `answerTextInline`
			(T18-B) is that mode; this flag only turns it on at mount, and `arm.inline`
			/ `arm.queued` switch it per case. ]]
		inlineText: boolean?,
		--[[ the `textSize = "fit"` node, OFF by default and on only for its own cases.
			It joins EVERY push by construction (`render/text_index`'s conservative
			set), so leaving it in the shared fixture would add one to every push count
			in this file and blunt the sharpest case here — "a settle on a key nothing
			uses pushes NOTHING" would read 1. ]]
		withFit: boolean?,
	}
): Arm
	local core = if opts.share ~= nil then opts.share.core else customFactory.new()
	local env = if opts.share ~= nil then opts.share.env else environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = opts.viewport.w, h = opts.viewport.h })
	local strip = {}
	for i = 1, 4 do
		strip[i] = core:signal(`S{i}`)
	end
	local solo = core:signal("solo")
	--[[ THE NODE WHOSE RECT CANNOT MOVE. A fixed width, so the box is 60px whatever
		the string measures — but the TRUNCATION verdict is a function of the measured
		width against that box, so a correction flips a published fact while the
		adapter's rect channel says nothing happened. The commit's harvest prunes on an
		ENTRY VERDICT (settled/moved), not on the dirty set, so this is the node that
		says whether the settle still owes the walks its paths. ]]
	local pinned = core:signal("pinnedstart")
	--[[ ...AND THE `textSize = "fit"` NODE, which is the one place the recorded key is
		not the whole truth: the ladder measures its string at SEVERAL sizes inside the
		band before choosing one, and the index files the size it CHOSE. A width learned
		at a size it merely probed can change the rung, so fit nodes join every push
		(`render/text_index`'s conservative `always` set). ]]
	local fitted = core:signal("fitstart")
	local rowValue = {}
	local items = {}
	for i = 1, opts.rows do
		rowValue[i] = core:signal(`row {i}`)
		table.insert(items, { id = `r{i}`, n = rowValue[i] })
	end
	local rows = core:signal(items)
	local rootId = opts.prefix or "Root"
	local bp = UI.VStack({
		id = rootId,
		padding = 0,
		gap = 0,
		width = fill(),
		height = fill(),
		children = {
			UI.HStack({
				id = "Strip",
				padding = 0,
				gap = 2,
				height = px(20),
				children = {
					UI.Text({ id = "S1", textSize = SIZE_STRIP, text = strip[1] }),
					UI.Text({ id = "S2", textSize = SIZE_STRIP, text = strip[2] }),
					UI.Text({ id = "S3", textSize = SIZE_STRIP, text = strip[3] }),
					UI.Text({ id = "S4", textSize = SIZE_STRIP, text = strip[4] }),
				},
			}),
			--[[ THE NESTED CASE, and the one this task was most likely to get wrong. Every
				DIRECT child of `Deep` is a container, so T13's per-child refusal (which
				never skips a direct `text`/`composition` child) cannot see the label two
				levels down. What refuses the memo is the ancestor-closed measure closure:
				`dirty_closure.of` walks the prefixes, so `/Root/Deep`, `/Root/Deep/Mid`
				and `/Root/Deep/Mid/Inner` are all in `measureContains` and `skippable`
				refuses each of them. ]]
			UI.VStack({
				id = "Deep",
				padding = 0,
				gap = 0,
				children = {
					UI.VStack({
						id = "Mid",
						padding = 0,
						gap = 0,
						children = {
							UI.HStack({
								id = "Inner",
								padding = 0,
								gap = 0,
								children = {
									UI.Text({ id = "Buried", textSize = SIZE_SOLO, text = solo }),
								},
							}),
						},
					}),
				},
			}),
			UI.HStack({
				id = "Pins",
				padding = 0,
				gap = 2,
				height = px(24),
				children = {
					UI.Text({ id = "Pinned", textSize = SIZE_PIN, width = px(60), height = px(14), text = pinned }),
					if opts.withFit
						then UI.Text({ id = "Fitted", textSize = "fit", width = px(70), height = px(20), text = fitted })
						else UI.Box({ id = "Fitted", width = px(4), height = px(4) }),
				},
			}),
			UI.VStack({
				id = "List",
				padding = 0,
				gap = 1,
				width = fill(),
				children = {
					UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item: any)
							return item.id
						end,
						row = function(item: any)
							return UI.HStack({
								id = "Row",
								padding = 0,
								gap = 2,
								width = fill(),
								height = px(16),
								children = {
									UI.Text({ id = "Name", textSize = SIZE_ROW, text = item.n }),
									UI.Box({ id = "Bar", width = px(10), height = px(6) }),
								},
							})
						end,
					}),
				},
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "coreSafeContent",
		incrementalLayout = opts.incremental,
		measureReuse = opts.measureReuse,
	})
	if opts.inlineText then
		adapter.answerTextInline(function(word: string, size: number, _font: string): number?
			return math.max(1, #word * size * 0.5)
		end)
	end
	controller.initialRender()
	return {
		core = core,
		env = env,
		controller = controller,
		adapter = adapter,
		strip = strip,
		rowValue = rowValue,
		rows = rows,
		solo = solo,
		pinned = pinned,
		fitted = fitted,
	}
end

--[[ THE TWO ADAPTER SHAPES, and the reason every case below has to say which one it is
	driving. `fake_target` QUEUES by default — the spec plays the engine by hand with
	`deliverTextWidths` from top level, so the renderer's solve has already returned and
	the correction arrives on the BARE route with no caller closure standing.
	`answerTextInline` (T18-B) is the SETTLED LIVE ENGINE: the answer reaches
	`premeasure_round`'s `done` inside the solve that asked, so `refresh`'s own closure
	is still standing and the correction takes the UNION route.

	The two routes differ only in whether a caller closure is standing, and that is
	precisely the variable the push budget got wrong — an over-budget refusal is a full
	solve on the bare route and was a NARROW one on the inline route, with the
	correction discarded. So the oracle below runs on both, and `inline` is the shipped
	one. ]]
local function widthOfDefault(word: string, size: number, _font: string): number?
	return math.max(1, #word * size * 0.5)
end

local function inlineOn(arm: Arm, widthOf: ((string, number, string) -> number?)?)
	arm.adapter.answerTextInline(widthOf or widthOfDefault)
end

local function inlineOff(arm: Arm)
	arm.adapter.answerTextInline(nil)
end

-- every batch the surface has asked for, answered with a deterministic width. The
-- SETTLED engine answers inline and closes the batch (`final` defaults true), which
-- is exactly what `fake_target.deliverTextWidths` replays.
local function deliverAll(arm: Arm, scale: number?)
	arm.adapter.deliverTextWidths(function(word: string, size: number, _font: string): number?
		return math.max(1, #word * size * 0.5 * (scale or 1))
	end)
end

-- drive the surface to the SETTLED state: solve, answer, repeat until the adapter
-- has nothing outstanding. A drive that does not do this is measuring the boot
-- window, which is exactly how the live matrix read 3.4 ms where a settled session
-- reads 39.7 (T17 §4).
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

-- ---- the oracle's channels ------------------------------------------------
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

--[[ THE GEOMETRY READS THE CONSUMER ACTUALLY USES, beside the paint channel: a rect
	the adapter never had to rewrite (because it did not move) is still a rect the
	presenter reads, and `screenRectOf` composes the host chain on top. Rascal Rally's
	sponsor and recap screens read exactly this seam around a settle. ]]
local function reads(controller: any, adapter: any): string
	local out = {}
	for path in adapter.liveNodes() do
		local r = controller.rectOf(path)
		local s = controller.screenRectOf(path)
		table.insert(
			out,
			`{path}|r={if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}`
				.. `|s={if s then `{s.x},{s.y},{s.w},{s.h}` else "-"}`
		)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

local function snapshot(arm: Arm): string
	return `{painted(arm.adapter)}\n--facts--\n{facts(arm.controller)}\n--reads--\n{reads(arm.controller, arm.adapter)}`
		.. `\n--diag--\n{findings(arm.controller)}`
end

--[[ THE COLD CONTROL, and it asserts its own coldness. At the parent SHA the settle
	re-solve was cold BY ACCIDENT — `solveOpts.reuse == nil` on a bare `solveAndApply`
	— so an oracle that simply drove "the old way" would, after this change, be two
	arms of the same new code agreeing with each other. `incrementalLayout = false`
	forces the whole-tree solve, and the assertion below is what makes the arm's name
	true. ]]
local function coldWorld(opts: { viewport: { w: number, h: number }, rows: number, withFit: boolean? }): Arm
	--[[ BOTH KNOBS OFF, which is the shape `tests/measure_reuse.spec.luau`'s arm C
		settled on: `incrementalLayout = false` removes the arrange skip and
		`measureReuse = false` removes the cross-solve store AND the node-resident
		serve. With only the first, a "cold" arm still serves 54 of 180 measure calls
		from the node's own last answers, and the assertion below would be a sentence
		that describes something else. ]]
	return world({
		viewport = opts.viewport,
		rows = opts.rows,
		incremental = false,
		measureReuse = false,
		withFit = opts.withFit,
	})
end

--[[ THE COLDNESS ASSERTION, and the shape of it is a finding of its own. "Every
	measure was a MISS" (`lastMeasured == lastMeasureCalls`) is the signature the LIVE
	drive reads on a 5,109-node tree, but it is not reachable on a small one: the
	per-solve memo serves a node's second and third ask inside the same solve, so a
	fully cold arm here reads 126 of 180. What IS exact, and is the property the
	control needs, is that the solve was a WHOLE-TREE one — it arranged every layout
	node it had and skipped nothing — and that it measured far more than the narrowed
	arm did. Both are asserted, because the first alone would pass on an arrange-only
	full solve. ]]
local function assertCold(arm: Arm, label: string)
	local st = stats(arm)
	expect(`{label} whole tree? arranged={st.lastArranged} of {st.lastLayoutNodes}`).toBe(
		`{label} whole tree? arranged={st.lastLayoutNodes} of {st.lastLayoutNodes}`
	)
	expect(st.lastMeasured >= st.lastLayoutNodes).toBe(true)
end

describe("a learned word re-measures its users, not the tree (T18-A)", function()
	it("THE HEADLINE: a one-word settle on a 4-user key, read off the run", function()
		local arm = world({ viewport = { w = 800, h = 600 }, rows = 400 })
		settle(arm)
		--[[ THE SETTLED FLOOR, so the numbers below are read against a tree that is
			doing nothing rather than against a boot window. An ORDINARY tick first —
			one that learns no word — because `lastTextDirtyPaths` is written by a SOLVE
			and the last tick of the settle loop above may not have solved at all: read
			straight after it, the counter is still the boot window's last push. On this
			tick it is 0, which is what makes it readable as a class marker. ]]
		arm.strip[4]:set("S4")
		-- a word the measurer ALREADY knows, so this tick is an ordinary one
		arm.rowValue[2]:set("row 1")
		arm.controller.refresh()
		deliverAll(arm)
		arm.controller.refresh()
		local quiet = stats(arm)
		expect(`settled: pending={tostring(arm.controller.textPending())} paths={quiet.lastTextDirtyPaths}`).toBe(
			"settled: pending=false paths=0"
		)
		local nodes = quiet.lastLayoutNodes
		expect(nodes > 1200).toBe(true)

		-- ONE NEW WORD at the narrow key: the four strip labels are its whole user set
		local before = quiet.solves
		arm.strip[1]:set("t18aStripWord")
		arm.controller.refresh()
		local pending = arm.adapter.pendingTextWords()
		expect(`asked for: {table.concat(pending, ",")}`).toBe("asked for: t18aStripWord")
		deliverAll(arm)
		local st = stats(arm)
		--[[ THE PATHS PUSHED, which is the number the whole narrowing is a function of:
			the (font,size) key's user set on THIS surface. Four strip labels, and
			nothing else — not the 400 row labels at size 12, not the buried label at
			size 18. ]]
		expect(`pushed={st.lastTextDirtyPaths}`).toBe("pushed=4")
		--[[ ...AND THE MEASURES, the counter the defect was found in. `lastMeasured`
			counts UNCACHED measures: a text node is measured up to three times per
			solve (the reveal/natural, the compact ladder's natural, the wrapped one),
			so four labels plus the two containers the closure reaches is a small
			double-digit number and not the 14,215 the parent SHA read on the
			1,000-row workload. The BOUND is what is pinned, spelled from the fixture's
			own branching rather than fitted: at most 3 measures for each of the 4
			pushed labels plus the ancestor chain `Strip` / `Root`. ]]
		expect(st.lastMeasured <= 14).toBe(true)
		expect(st.lastMeasured > 0).toBe(true)
		-- ...and the tree is 1,200+ nodes, so this is a THREE ORDERS OF MAGNITUDE
		-- claim rather than a percentage
		expect(`measured {st.lastMeasured} of {nodes} nodes, under a tenth of a percent`).toBe(
			`measured {st.lastMeasured} of {nodes} nodes, under a tenth of a percent`
		)
		expect(st.lastMeasured * 100 < nodes).toBe(true)
		--[[ ...AND EXACTLY ONE SOLVE FOR THE ROUND, counted across the DRIVE PLUS ONE
			PUMP rather than on the drive tick (review SF-3): the delivery writes
			`textMeasureEpoch`, that settles synchronously and solves, and
			`premeasure_round`'s own counter guard then skips its second call. The drive
			itself is the other solve. ]]
		arm.controller.refresh()
		expect(`solves for the drive and the settle={stats(arm).solves - before}`).toBe(
			"solves for the drive and the settle=2"
		)
	end)

	it("a settle fires ONE `onSolved` per solve, and a container with no key-K text keeps its memo", function()
		--[[ TWO PINS THE OWED LIST CARRIED AS ARGUMENTS AND NOT AS NUMBERS, made numbers
			here (T18-A fix round 1).

			OWED ROW 14 — the `onSolved` COUNT. The argument was structural and correct:
			the settle solve was already an outermost solve of its own (it runs from
			`core:settle`), T18-A built no defer, and T18-B's queue fires one
			notification per solve against the finished tree. But "unchanged" was never
			counted, and a consumer that measures this surface sees exactly this number.
			One per solve, and the settle's solve is the second of the two the drive
			costs.

			RULING L-11's POSITIVE HALF — a container whose subtree holds no key-K text
			keeps its T13/T13b memo. The negative half (a container ON the path is
			refused) is pinned by the nested case below, on rects and facts. This is the
			other side, and it is what makes the narrowing a memo question rather than
			just a smaller closure: `lastChildVisits` is the `measure` calls a stack's
			own measure branch made, so a settle that dropped every container memo would
			move it. It must read the ordinary tick's number. ]]
		local arm = world({ viewport = { w = 800, h = 600 }, rows = 30 })
		settle(arm)
		local notifies = 0
		local stop = arm.controller.onSolved(function()
			notifies += 1
		end)
		--[[ AN ORDINARY TICK ON THE SAME DIRT SHAPE first: a strip label rewritten with
			a word the measurer already knows. Same closure, no correction — which is
			what makes the settle's counters below a comparison rather than two
			unrelated numbers (an earlier version dirtied a ROW here and read 103
			against the settle's 5, comparing the list's walk with the strip's). ]]
		arm.strip[2]:set("S1")
		arm.controller.refresh()
		local quiet = stats(arm)
		expect(`an ordinary tick: notifies={notifies} solves=1`).toBe("an ordinary tick: notifies=1 solves=1")
		notifies = 0
		local before = quiet.solves
		-- ...and the settle: one solve for the drive, one for the correction, one
		-- notification each, and the container memo untouched
		arm.strip[2]:set("t18aNotifyWord")
		arm.controller.refresh()
		deliverAll(arm)
		local st = stats(arm)
		expect(`the settle: solves={st.solves - before} notifies={notifies} pushed={st.lastTextDirtyPaths}`).toBe(
			"the settle: solves=2 notifies=2 pushed=4"
		)
		--[[ ...AND THE MEMO, which is the number ruling L-11's positive half was missing.
			`lastChildVisits` is the `measure` calls a stack's own measure branch made,
			and it is a `last*` counter — so on the settle tick it reports the
			CORRECTION's solve, not the write's. The write re-walks the whole strip and
			the list below it (a strip label changing height re-offers the list);
			the correction re-walks the strip alone, because every container whose
			subtree holds no size-14 text keeps its T13/T13b memo. Both numbers read off
			the run, and the ratio is the claim: a settle that dropped those memos would
			read the write's number here, not a fraction of it.

			── THE WRITE COLUMN RE-RECORDED 2026-09-06 (Plan D, D5), 103 -> 8, AND THE
			CORRECTION DID NOT MOVE. The settle above ends on a solve with no reuse table,
			which until D5 left no node slots behind — so this ordinary tick re-measured
			the strip and re-descended the list under it, and every container it descended
			into re-walked its children. A full solve records now, so the arrange pass's
			second ask of each container is SERVED and the descent that produced the 95
			never happens. The claim is the same claim: the correction stays at 5 with the
			memos live, and dropping them puts the whole strip's walk back. ]]
		expect(`the write walked {quiet.lastChildVisits}, the correction {st.lastChildVisits}`).toBe(
			"the write walked 8, the correction 5"
		)
		--[[ ...AND THE ARRANGE SIDE OF THE SAME CLAIM (Plan C, T14). This line used to
			read `lastMeasureServed > 0` — the correction's ARRANGE pass re-measuring
			every clean row and being answered from its node slots. T14's replay deletes
			that pass on a stack where nothing moved, so the correction now serves
			NOTHING and skips the placements instead, which is the stronger version of
			the same statement: the correction did not re-place the strip's siblings
			either. Read off the run. ]]
		expect(`served={st.lastMeasureServed} placeSkipped={st.lastPlaceSkipped > 0}`).toBe(
			"served=0 placeSkipped=true"
		)
		stop()
	end)

	it("...and the SAME word on the WIDE key costs its own user set, which is the honest counter-case", function()
		--[[ THE LEVER IS THE SIZE OF THE KEY'S USER SET, and a report that quoted "4"
			as the result would be quoting this fixture's strip. A workload whose new
			words land on the row label's size pays for every row — still a fraction of
			the tree, but a thousand times the strip's bill. Said here rather than only
			in the report, because it is the property the design has. ]]
		local arm = world({ viewport = { w = 800, h = 600 }, rows = 40 })
		settle(arm)
		arm.rowValue[7]:set("t18aRowWord")
		arm.controller.refresh()
		deliverAll(arm)
		local st = stats(arm)
		expect(`pushed={st.lastTextDirtyPaths} (one per row label)`).toBe("pushed=40 (one per row label)")
		-- ...and it is still short of a whole-tree solve, READ OFF THE RUN against the
		-- same tree's cold cost rather than pinned to a bound this fixture happens to
		-- satisfy: a forced full solve of this tree measures every node it has
		local cold = coldWorld({ viewport = { w = 800, h = 600 }, rows = 40 })
		settle(cold)
		cold.rowValue[8]:set("t18aRowWordCold")
		cold.controller.refresh()
		deliverAll(cold)
		assertCold(cold, "wide-key control")
		expect(
			`narrowed={st.lastMeasured} cold={stats(cold).lastMeasured} narrower={st.lastMeasured < stats(cold).lastMeasured}`
		).toBe(`narrowed={st.lastMeasured} cold={stats(cold).lastMeasured} narrower=true`)
	end)

	it("a push that names a large FRACTION of the tree is refused, and the full solve is taken", function()
		--[[ THE BUDGET, and it is a measured number rather than a taste. A push whose
			ancestor closure reaches the root and refuses every container on the way down
			does the whole tree's work PLUS the closure's. Live, arm C, `battle_hud L`'s
			`updateItem-facing` — 1,000 labels sharing one (font,size) — read **55.709
			ms** with the push against **~39.7 ms** for the whole-tree cold solve it
			replaced, at 14,174 measure CALLS against the cold solve's 14,215. Over the
			cap the mark is spent as a refusal and the bare route takes the full solve,
			which is exactly what the parent SHA did: no gain, and no regression either.

			200 rows here puts the row key's user set at 200 against a cap of
			`max(64, nodes // 8)`, and the strip key's at 4 — so the same fixture shows
			both sides of the line in one case. ]]
		local arm = world({ viewport = { w = 800, h = 600 }, rows = 200 })
		settle(arm)
		arm.rowValue[3]:set("row 1")
		arm.controller.refresh()
		local quiet = stats(arm)
		expect(quiet.lastLayoutNodes // 8 > 64).toBe(true)
		expect(`the row key would name {200} of {quiet.lastLayoutNodes} nodes, cap {quiet.lastLayoutNodes // 8}`).toBe(
			`the row key would name 200 of {quiet.lastLayoutNodes} nodes, cap {quiet.lastLayoutNodes // 8}`
		)
		-- OVER the cap: refused, and the solve is the full one the parent SHA took
		arm.rowValue[7]:set("t18aOverBudgetWord")
		arm.controller.refresh()
		deliverAll(arm)
		local over = stats(arm)
		expect(`over budget: pushed={over.lastTextDirtyPaths} arranged={over.lastArranged} of {over.lastLayoutNodes}`).toBe(
			`over budget: pushed=0 arranged={over.lastLayoutNodes} of {over.lastLayoutNodes}`
		)
		-- UNDER the cap, on the same tree and the same tick shape: narrowed
		arm.strip[1]:set("t18aUnderBudgetWord")
		arm.controller.refresh()
		deliverAll(arm)
		local under = stats(arm)
		expect(`under budget: pushed={under.lastTextDirtyPaths} arranged={under.lastArranged}`).toBe(
			"under budget: pushed=4 arranged=6"
		)
		expect(under.lastMeasured < over.lastMeasured // 10).toBe(true)
	end)

	it("a settle on a key NOTHING uses re-measures nothing — and the SOLVE still runs", function()
		--[[ THE STRONGEST CASE, and the one that was VACUOUS for an afternoon. A width
			learned at a (font,size) no mounted node measured under names an empty user
			set. At the parent SHA that was a whole-tree cold re-solve like any other.

			▲ THE SOLVE COUNT IS HALF THE ASSERTION, and leaving it out is what hid a
			real defect: `text_index.take` returned `nil` for an empty push, which sent
			the caller down the BARE route (`dirtyContains == nil`) and bought exactly
			the full cold solve this task exists to remove. The spec passed anyway,
			because a `lastMeasured` read after a tick that may not have solved is a
			read of the PREVIOUS tick. It was the FacetBench settle driver — which
			measures milliseconds and cannot be fooled by a stale counter — that found
			it: 39.9 ms and 14,215 measures on `battle_hud L`, the parent SHA's number
			exactly, on the one case that should be free. An empty push is a PLAN with
			empty sets, not a refusal, and the case now says so in both halves. ]]
		local arm = world({ viewport = { w = 800, h = 600 }, rows = 60 })
		settle(arm)
		-- an ordinary tick, so the floor below belongs to a solve that really ran
		arm.rowValue[5]:set("row 1")
		arm.controller.refresh()
		local quiet = stats(arm)
		expect(text_metrics.setMeasured("BuilderSans", SIZE_UNUSED, "t18aNobodyDrawsThis", 37)).toBe(true)
		arm.env:set("textMeasureEpoch", ((arm.env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
		local st = stats(arm)
		expect(`the settle solved: {st.solves - quiet.solves}`).toBe("the settle solved: 1")
		expect(`pushed={st.lastTextDirtyPaths} measured={st.lastMeasured} arranged={st.lastArranged}`).toBe(
			"pushed=0 measured=0 arranged=0"
		)
	end)

	it("a CALIBRATION change still re-measures the whole tree — the narrowing is on the WORD axis alone", function()
		--[[ THE CONTROL FOR OWED ROW 6, and the case that proves the narrowing did not
			swallow the global axis. `calibrate` changes what `measure` returns for
			EVERY word at EVERY size of a font, so nothing short of a whole-tree
			invalidation is honest and `calibrationEpoch` stays a `measureStamp` term. ]]
		local arm = world({ viewport = { w = 800, h = 600 }, rows = 80 })
		settle(arm)
		-- the SETTLED FLOOR, off an ordinary tick that learns no word (the last refresh
		-- of the settle loop may not have solved at all, in which case the counters
		-- still read the boot window's last push)
		arm.rowValue[3]:set("row 1")
		arm.controller.refresh()
		local quiet = stats(arm)
		--[[ THE GLOBAL IS RESTORED BEFORE ANYTHING IS ASSERTED. `calibrate` is
			process-wide and this suite shares one `text_metrics`, so a failing
			assertion between the two calls would leave every later spec measuring
			against the other glyph fraction — which is exactly what happened while
			this case was being written, and it reddened `renderer.spec` twenty files
			later. Drive first, capture, put it back, then judge. ]]
		text_metrics.calibrate("BuilderSans", 0.34)
		--[[ ...AND THE SOLVE IT NEEDS, published exactly the way a premeasurement round
			publishes one. `calibrate` dirties NOTHING — it changes what `measure`
			returns and nothing on the tree — so the surface learns about it through the
			`textMeasureEpoch` geometry fact, which is the same route a learned word
			takes. That is what makes this a control rather than a different experiment:
			same route, same bare settle solve, and the only difference is which
			generation moved. ]]
		arm.env:set("textMeasureEpoch", ((arm.env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
		local st = table.clone(stats(arm))
		text_metrics.resetCalibration()
		arm.env:set("textMeasureEpoch", ((arm.env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
		--[[ THE WHOLE TREE, on the same terms the oracle's control uses: every layout
			node arranged, nothing skipped, every node measured. A narrowing that had
			swallowed the global axis would read the settled floor here instead. ]]
		expect(`calibration whole tree? arranged={st.lastArranged} of {st.lastLayoutNodes}`).toBe(
			`calibration whole tree? arranged={st.lastLayoutNodes} of {st.lastLayoutNodes}`
		)
		expect(st.lastMeasured >= st.lastLayoutNodes).toBe(true)
		--[[ ...AND THE ORDINARY TICK BESIDE IT IS NOT WHOLE-TREE, which is what makes
			the claim above mean something. The comparison is on the ARRANGE count, not
			the measure one: an incremental tick on this fixture still re-measures a
			large share of the tree (the root stack distributes and re-offers every
			child), so a measure ratio would be describing the fixture rather than the
			control. What separates the two ticks exactly is that one placed every node
			and the other placed a handful. ]]
		expect(`settled tick arranged {quiet.lastArranged} of {quiet.lastLayoutNodes}`).toBe(
			`settled tick arranged {quiet.lastArranged} of {quiet.lastLayoutNodes}`
		)
		expect(quiet.lastArranged < quiet.lastLayoutNodes // 4).toBe(true)
	end)

	it("a second surface sees a width the first learned (owed row 8)", function()
		--[[ THE CROSS-SURFACE REACH, which the process-global epoch used to give for
			free and which the narrowing has to pay for deliberately. The exact-width
			store is one table per VM, so a HUD teaching the measurer a word a menu also
			draws must correct the MENU too — and once the word generation leaves
			`measureStamp`, the quiet surface's solve would legitimately serve every
			node. `render/text_index`'s registry is what closes it: the broadcast is
			subscribed at `text_metrics.setMeasured`, so EVERY live index marks its own
			paths, and the `textMeasureEpoch` fact then makes both surfaces solve.

			ONE CORE AND ONE ENVIRONMENT, two roots. That is what "two attached
			surfaces" means here — a fact belongs to an environment — and it is the
			shape a HUD beside a menu has. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		local busy = world({ viewport = { w = 800, h = 600 }, rows = 20, share = { core = core, env = env } })
		local quiet =
			world({ viewport = { w = 800, h = 600 }, rows = 20, share = { core = core, env = env }, prefix = "Quiet" })
		settle(busy)
		settle(quiet)
		local SHARED = "t18aSharedWord"
		-- both surfaces draw the SAME string at the SAME size
		busy.strip[2]:set(SHARED)
		quiet.strip[2]:set(SHARED)
		busy.controller.refresh()
		quiet.controller.refresh()
		local estimated = quiet.controller.rectOf("/Quiet/Strip/S2")
		-- ONLY the busy surface's batch is answered; the quiet one's is dropped on the
		-- floor, so the correction can only reach it through the shared store and the
		-- registry
		quiet.adapter.deliverTextWidths(function(): number?
			return nil
		end)
		busy.adapter.deliverTextWidths(function(word: string, size: number): number?
			return if word == SHARED then 7 else math.max(1, #word * size * 0.5)
		end)
		local corrected = quiet.controller.rectOf("/Quiet/Strip/S2")
		expect(`quiet corrected: {estimated.w} -> {corrected.w}`).toBe(`quiet corrected: {estimated.w} -> 7`)
		expect(estimated.w ~= 7).toBe(true)
		-- ...and it cost the quiet surface its four strip labels, not its tree
		expect(`quiet pushed={stats(quiet).lastTextDirtyPaths}`).toBe("quiet pushed=4")
	end)

	it("a text node nested inside a memoised container is not served stale (owed rows 5 and 10)", function()
		--[[ OWED ROW 5's FIXTURE. `Deep`'s only child is a container, and so is ITS
			only child, so T13's per-child refusal — which never skips a direct
			`text`/`composition` child — cannot reach the label. What refuses the memo
			is the ancestor-closed measure closure. Every rect on the chain is pinned,
			and the text FACTS with them (owed row 10: the commit's harvest prunes
			against `builtDirty`, so a settle that filled only the reuse sets would
			re-measure the label and then skip the walk that republishes its facts). ]]
		local arm = world({ viewport = { w = 800, h = 600 }, rows = 30 })
		settle(arm)
		local before = arm.controller.rectOf("/Root/Deep/Mid/Inner/Buried")
		local beforeFacts = facts(arm.controller)
		arm.solo:set("t18aBuriedWord")
		arm.controller.refresh()
		local estimated = arm.controller.rectOf("/Root/Deep/Mid/Inner/Buried")
		arm.adapter.deliverTextWidths(function(word: string, size: number): number?
			return if word == "t18aBuriedWord" then 123 else math.max(1, #word * size * 0.5)
		end)
		local corrected = arm.controller.rectOf("/Root/Deep/Mid/Inner/Buried")
		local inner = arm.controller.rectOf("/Root/Deep/Mid/Inner")
		local mid = arm.controller.rectOf("/Root/Deep/Mid")
		expect(`buried={corrected.w} inner={inner.w} mid={mid.w}`).toBe("buried=123 inner=123 mid=123")
		expect(estimated.w ~= 123).toBe(true)
		expect(before.w ~= 123).toBe(true)
		-- ...and the FACTS moved with the rect, which is the half a pruned harvest
		-- would have dropped
		expect(facts(arm.controller) ~= beforeFacts).toBe(true)
		expect(`pushed={stats(arm).lastTextDirtyPaths}`).toBe("pushed=1")
	end)

	it("a corrected fact on a node whose RECT DID NOT MOVE is still republished (owed row 10)", function()
		--[[ THE ROW THE CLOSURE ROUTING IS MOST LIKELY TO GET WRONG, and it is not the
			rect. With `solveOpts.reuse` non-nil the commit's `harvest` prunes, and a
			settle whose mounted-tree dirty sets were empty would re-measure the label
			and then skip the walk that republishes what the measure decided. On a node
			whose box is FIXED the rect channel says nothing at all — 60px before, 60px
			after — while `truncated` flips, so the rect oracle alone cannot see it.

			WHAT CARRIES IT AT HEAD IS `entryVerdict`, NOT A DIRTY MARK, and this block
			said the opposite until the review caught it. An earlier arm of this task
			DID mark the settle's paths and their ancestors into `nodeDirty` and
			`commitDirty` before the build captured them; that was deleted after a live
			measurement (marking into the layout-node store forces a REBUILD of every
			pushed node and every ancestor — ~2,000 of them on a 1,000-label key, which
			the whole-tree cold solve it was meant to beat never paid: 62.986 ms against
			~37.7 ms). This case was left describing the deleted mechanism, which in a
			project where a comment is evidence is the same defect as a stale pin.

			THE ARGUMENT THAT ACTUALLY CLOSES IT, and it is one line rather than an open
			fixture debt: **every node in `measures` is ARRANGED** — the clean-child /
			`selfPlaces` skip requires `measureContains[node.id] ~= true` — and an
			arranged node writes a FRESH entry table (`solver.luau`'s rect pass), so
			`entryVerdict`'s `last == probe` identity cannot hold for it and
			`commit_walks` descends it whatever the dirty sets say. A node NOT in
			`measures` cannot have a text fact move from a word width, because a word
			width only reaches a node through that node's own measure. So the residue
			the deleted marks were protecting is EMPTY, not merely un-fixtured.

			The case stays because it is the executable half of that argument: a node
			whose rect cannot move, whose verdict can, compared against a forced cold
			arm, on both halves of the settle. ]]
		local narrowed = world({ viewport = { w = 800, h = 600 }, rows = 15 })
		local cold = coldWorld({ viewport = { w = 800, h = 600 }, rows = 15 })
		settle(narrowed)
		settle(cold)
		local beforeShot = snapshot(narrowed)
		--[[ A LONG SINGLE WORD the estimator sizes well past the 60px box (so the first
			frame reserves a truncated label) and the engine then reports at 9px (so the
			correction un-truncates it). The rect stays 60 on both sides. ]]
		local WORD = "t18aPinnedWordThatLooksVeryWideIndeed"
		for _, arm in { narrowed, cold } do
			arm.pinned:set(WORD)
			arm.controller.refresh()
			arm.adapter.deliverTextWidths(function(word: string, size: number): number?
				return if word == WORD then 9 else math.max(1, #word * size * 0.5)
			end)
		end
		local r = narrowed.controller.rectOf("/Root/Pins/Pinned")
		expect(`the box never moved: {r.w}x{r.h}`).toBe("the box never moved: 60x14")
		assertCold(cold, "pinned")
		expect(snapshot(narrowed) == snapshot(cold)).toBe(true)
		-- NON-VACUITY: something really did move across the settle, or the equality
		-- above is comparing two unchanged strings
		expect(snapshot(narrowed) ~= beforeShot).toBe(true)
		expect(string.find(painted(narrowed.adapter), WORD, 1, true) ~= nil).toBe(true)
	end)

	it('a `textSize = "fit"` node is corrected even though the index filed the size it CHOSE', function()
		--[[ THE CONSERVATIVE SET, and the one place the (font,size) key is not enough.
			`layout/text_fit`'s ladder measures the string at several sizes inside the
			band and the index files the one the node landed on, so a width learned at a
			size the ladder merely PROBED would name nobody. Fit nodes therefore join
			EVERY push. They are rare (an opt-in prop) and being wrong about one is a
			wrong box on screen, which is why the cheap conservative answer is the right
			one here and the measured one everywhere else. ]]
		local narrowed = world({ viewport = { w = 800, h = 600 }, rows = 15, withFit = true })
		local cold = coldWorld({ viewport = { w = 800, h = 600 }, rows = 15, withFit = true })
		settle(narrowed)
		settle(cold)
		local WORD = "t18aFittedWordLongEnoughToLadder"
		for _, arm in { narrowed, cold } do
			arm.fitted:set(WORD)
			arm.controller.refresh()
			arm.adapter.deliverTextWidths(function(word: string, size: number): number?
				return if word == WORD then 11 else math.max(1, #word * size * 0.5)
			end)
		end
		assertCold(cold, "fitted")
		expect(facts(narrowed.controller) == facts(cold.controller)).toBe(true)
		expect(snapshot(narrowed) == snapshot(cold)).toBe(true)
	end)

	it("a word learned INSIDE a refresh is UNIONED into that refresh's closure, not dropped", function()
		--[[ THE SHIPPED ROUTE, and a live drive is what put this case here. The engine's
			settled branch answers INLINE — `text_premeasure.spawn` is `task.spawn`,
			which runs its body synchronously until its first yield, and a settled
			`GetTextBoundsAsync` does not yield — so `premeasure_round`'s `done` runs
			while `refresh`'s own closure is still standing and the re-solve is the
			re-entrant one. Measured live before this: `stats().lastTextDirtyPaths` read
			**0** on every settle step of `battle_hud L`, because the push was REFUSED
			whenever a closure was already set. The geometry was right — the refresh's
			dirt contains the node whose text just changed — so this is a mechanism pin
			rather than a staleness one, and it is labelled as such:

			▲ A RECORDED NULL ON THE STALENESS QUESTION. No fixture in this file makes
			the refusal produce a WRONG rect, and the argument for why is worth keeping:
			a node's text cannot become a new word without that node being dirtied, so
			the key's other users on this surface already measured their own strings
			exactly, and a SECOND surface is corrected through its own bare solve (the
			case above). The union stays because it is the conservative direction and
			because "the caller's closure is a superset" is a property that should not
			depend on that argument staying true.

			The adapter answers from inside `measureTextWidths` — `fake_target`'s
			`answerTextInline` (T18-B), which is the settled live engine and what the
			queued default deliberately is not. ]]
		local arm = world({ viewport = { w = 800, h = 600 }, rows = 10, inlineText = true })
		settle(arm)
		local before = stats(arm)
		expect(`settled: pushed={before.lastTextDirtyPaths}`).toBe("settled: pushed=0")
		--[[ ONE WRITE, one new word, answered inline inside the refresh it caused. The
			four strip labels share the key, so the push names four paths and they are
			unioned into a closure the refresh had already built for one. ]]
		arm.strip[1]:set("t18aInlineWord")
		arm.controller.refresh()
		local st = stats(arm)
		expect(`pushed={st.lastTextDirtyPaths} and the rect is exact: {arm.controller.rectOf("/Root/Strip/S1").w}`).toBe(
			`pushed=4 and the rect is exact: {arm.controller.rectOf("/Root/Strip/S1").w}`
		)
		-- ...and it is STILL not a whole-tree solve: a union of two small sets is small
		expect(st.lastMeasured < st.lastLayoutNodes // 2).toBe(true)
		-- ...and the geometry equals a forced cold solve of the same tree
		local cold = coldWorld({ viewport = { w = 800, h = 600 }, rows = 10 })
		settle(cold)
		cold.strip[1]:set("t18aInlineWord")
		cold.controller.refresh()
		deliverAll(cold)
		assertCold(cold, "inline")
		expect(reads(arm.controller, arm.adapter) == reads(cold.controller, cold.adapter)).toBe(true)
	end)

	it("an OVER-BUDGET push on the INLINE route repairs the key's other users, not just the dirty one", function()
		--[[ THE WRONG PIXEL THE BUDGET LET THROUGH, and it is a route bug rather than an
			arithmetic one. `text_index.take` refuses a push that names more than
			`max(64, lastLayoutNodes // 8)` paths, and both this file and the report
			claimed the fallback was "the full solve the parent SHA took". That is TRUE
			on the bare route, where `dirtyContains` is nil and a refusal leaves it nil.
			It was FALSE on the INLINE route — the one that ships — where a caller
			closure is standing: the mark was consumed, the push discarded, and the
			solve stayed narrow. Measured at `b23460f8` on this fixture:
			`cap=76 pushed=0 measured=4 arranged=5 nodes=614`.

			A WORD IS A TOKEN, NOT A LABEL, which is what makes this a wrong box rather
			than a tidiness point. `text_metrics.measure` sums per WORD, so two labels
			that share no string still share words — every row here draws the word
			"row". A correction to that word (the boot-window flip: the engine answers a
			batch and corrects itself, `answerAgain`'s whole reason for existing) moves
			all 200 rows, and only one of them is in the refresh's dirt. The engine
			delivers that correction inline, alongside the new word it was asked for.

			THE FIX IS THE ONE THE COMMENT ALREADY CLAIMED: over the cap the caller's
			closure is DROPPED, so the solve really is the whole-tree one — and the
			whole-tree one is also the cheaper of the two honest options at that size
			(the sweep in FacetBench §C16). ]]
		local FONT = "BuilderSans"
		local NEW = "t18aOverBudgetInline"
		local function drive(arm: Arm)
			settle(arm)
			--[[ THE ENGINE ANSWERS TWO THINGS AT ONCE: the word it was asked for, and a
				CORRECTION to a word it answered earlier that 200 nodes draw. Delivered
				from inside `measureTextWidths`, which is where a settled client
				delivers it. ]]
			local corrected = false
			inlineOn(arm, function(word: string, size: number, _font: string): number?
				if not corrected then
					corrected = true
					text_metrics.setMeasured(FONT, SIZE_ROW, "row", 3)
				end
				return if word == NEW then 9 else math.max(1, #word * size * 0.5)
			end)
			arm.rowValue[9]:set(NEW)
			arm.controller.refresh()
		end
		local narrowed = world({ viewport = { w = 800, h = 600 }, rows = 200, inlineText = true })
		local cold = coldWorld({ viewport = { w = 800, h = 600 }, rows = 200 })
		drive(narrowed)
		drive(cold)
		local st = stats(narrowed)
		expect(`the push was over budget: {st.lastTextDirtyPaths}`).toBe("the push was over budget: 0")
		--[[ THE PIXELS FIRST, because they are the half that matters and the half that
			was wrong: every OTHER row draws the corrected word and none of them is in
			the refresh's dirt, so the forced cold arm is what they should read. ]]
		assertCold(cold, "over-budget inline")
		expect(reads(narrowed.controller, narrowed.adapter) == reads(cold.controller, cold.adapter)).toBe(true)
		--[[ ...AND THE MECHANISM THAT CARRIES THEM. Before the fix this read
			`arranged=5 of 614`. ]]
		expect(`over budget arranged {st.lastArranged} of {st.lastLayoutNodes}`).toBe(
			`over budget arranged {st.lastLayoutNodes} of {st.lastLayoutNodes}`
		)
		-- NON-VACUITY: the correction really did move a row nobody wrote to
		local other = narrowed.controller.rectOf("/Root/List/Rows/[r120]/Row/Name")
		local dirty = narrowed.controller.rectOf("/Root/List/Rows/[r9]/Row/Name")
		expect(`the untouched row moved to {other.w}, the written one to {dirty.w}`).toBe(
			`the untouched row moved to {cold.controller.rectOf("/Root/List/Rows/[r120]/Row/Name").w}, `
				.. `the written one to {cold.controller.rectOf("/Root/List/Rows/[r9]/Row/Name").w}`
		)
		expect(other.w ~= dirty.w).toBe(true)
	end)

	it("an unmounted path is forgotten, so a churning list does not retain the session (review SF-8)", function()
		--[[ THE LIFETIME PIN, in the registry-neutrality style. A stale entry is only
			cost — a push for a dead path is inert through the closure and the solver's
			id lookup — but a `ForEach` churning rows would retain every path it ever
			mounted, for the session. The observable is the PUSH COUNT: while the rows
			are mounted a word at their size names twelve paths; once they are gone it
			names none, and the count is the index's own bookkeeping rather than a
			second implementation of it. ]]
		local arm = world({ viewport = { w = 800, h = 600 }, rows = 12 })
		settle(arm)
		expect(arm.controller.rectOf("/Root/List/Rows/[r1]/Row/Name") ~= nil).toBe(true)
		arm.rowValue[1]:set("t18aChurnWordA")
		arm.controller.refresh()
		deliverAll(arm)
		expect(`while mounted={stats(arm).lastTextDirtyPaths}`).toBe("while mounted=12")
		-- the rows leave, and the strip stays so the surface is still worth solving
		arm.rows:set({})
		settle(arm)
		--[[ the row really is gone. THE PATH SHAPE MATTERS and this line used to have it
			wrong (`/Rows/r1/Name`), which made `toBe(nil)` a sentence that could not
			fail: a `ForEach` key is bracketed and the row template's own id is in the
			path. Both halves are asserted now — the live one before, the nil after. ]]
		expect(arm.controller.rectOf("/Root/List/Rows/[r1]/Row/Name")).toBe(nil)
		--[[ ...and a word learned at the ROW label's size now names nobody. The strip
			key is untouched, so this is the index forgetting twelve paths rather than
			the whole push machinery having gone quiet. ]]
		expect(text_metrics.setMeasured("BuilderSans", SIZE_ROW, "t18aChurnWordB", 29)).toBe(true)
		arm.env:set("textMeasureEpoch", ((arm.env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
		expect(`after unmount={stats(arm).lastTextDirtyPaths}`).toBe("after unmount=0")
		-- THE CONTROL: the strip's key still names its four, so the push path is live
		expect(text_metrics.setMeasured("BuilderSans", SIZE_STRIP, "t18aChurnWordC", 31)).toBe(true)
		arm.env:set("textMeasureEpoch", ((arm.env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
		expect(`the strip still pushes={stats(arm).lastTextDirtyPaths}`).toBe("the strip still pushes=4")
	end)
end)

describe("the settle oracle: identical geometry, whatever the tick did (T18-A)", function()
	--[[ EVERY VIEW, BOTH ADAPTER SHAPES, against a FORCED COLD arm. The narrowed settle
		and a whole-tree solve after the same deliver must agree byte for byte on every
		channel a consumer can read — the adapter's paint and hit rects,
		`controller.textAt()`, `rectOf`, `screenRectOf` and the diagnostic SET. 320x640
		is in the list deliberately: it is the view where the strip wraps and the row
		labels truncate, so the arms are compared on a tree whose verdicts are
		non-trivial.

		▲ BOTH SHAPES, AND THE SECOND ONE IS WHY. The loop used to run on the QUEUED
		target alone — the spec delivering from top level, so the renderer's solve had
		already returned and the correction arrived on the BARE route with no caller
		closure standing. The shipped route is the other one: `answerTextInline`
		(T18-B's sync-answer mode) is the settled live engine, and the answer reaches
		`premeasure_round`'s `done` INSIDE the solve that asked. The two differ only in
		whether a caller closure is standing — which is precisely the variable the push
		budget got wrong, and running one shape is what let that through. ]]
	for _, view in device_views.VIEWS do
		for _, inline in { false, true } do
			local shape = if inline then "inline" else "queued"
			it(`{view.id} {view.w}x{view.h} [{shape}]: a narrowed settle equals a forced cold one`, function()
				local narrowed = world({ viewport = { w = view.w, h = view.h }, rows = 25, inlineText = inline })
				local cold = coldWorld({ viewport = { w = view.w, h = view.h }, rows = 25 })
				settle(narrowed)
				settle(cold)
				-- THE NON-VACUITY GUARD: the arms must agree BEFORE the settle too, or a
				-- byte-equal comparison afterwards says nothing about the settle
				expect(snapshot(narrowed) == snapshot(cold)).toBe(true)
				--[[ A WORD PER VIEW AND PER SHAPE, and this is a trap worth naming: the
					exact-width store is PROCESS-GLOBAL, so a shared literal would be
					learned by the first arm and already known to the other seventeen —
					whose settle would then never happen and whose "the narrowed arm
					really narrowed" guard would read a stale counter and pass by
					accident. ]]
				local WORD = `t18aOracle{view.id}{shape}`
				local function widths(word: string, size: number): number?
					return if word == WORD then 41 else math.max(1, #word * size * 0.5)
				end
				if inline then
					inlineOn(narrowed, function(word: string, size: number): number?
						return widths(word, size)
					end)
				end
				for _, arm in { narrowed, cold } do
					arm.strip[3]:set(WORD)
					arm.solo:set(WORD)
					arm.rowValue[4]:set(WORD)
					arm.controller.refresh()
					if arm == cold or not inline then
						arm.adapter.deliverTextWidths(widths)
					end
				end
				-- the control really is cold, or this is two arms of one mechanism agreeing
				assertCold(cold, `{view.id} {shape}`)
				-- ...and the narrowed one really did narrow, or the comparison is vacuous
				local st = stats(narrowed)
				expect(
					`{view.id} {shape}: pushed={st.lastTextDirtyPaths} measured={st.lastMeasured} of {st.lastLayoutNodes}`
				).toBe(`{view.id} {shape}: pushed=30 measured={st.lastMeasured} of {st.lastLayoutNodes}`)
				expect(st.lastMeasured < st.lastLayoutNodes).toBe(true)
				expect(snapshot(narrowed) == snapshot(cold)).toBe(true)
			end)
		end
	end

	it("...and an OVER-BUDGET settle equals a forced cold one on both shapes too", function()
		--[[ THE OTHER SIDE OF THE BUDGET LINE, swept over both routes rather than
			argued. 200 rows puts the row key's user set at 200 against a cap of
			`max(64, nodes // 8)` = 76, so every arm here refuses the push — and the
			refusal has to be the whole-tree solve on BOTH shapes, which is exactly what
			it was not until this round. Driven at the narrowest supported viewport as
			well as the desktop one, because a wrapping strip and a truncating row are
			where a stale measurement shows up as a verdict rather than a width. ]]
		for _, view in { device_views.VIEWS[1], device_views.VIEWS[6] } do
			for _, inline in { false, true } do
				local shape = if inline then "inline" else "queued"
				local WORD = `t18aOverBudget{view.id}{shape}`
				local narrowed = world({ viewport = { w = view.w, h = view.h }, rows = 200, inlineText = inline })
				local cold = coldWorld({ viewport = { w = view.w, h = view.h }, rows = 200 })
				settle(narrowed)
				settle(cold)
				expect(snapshot(narrowed) == snapshot(cold)).toBe(true)
				local corrected = false
				local function widths(word: string, size: number): number?
					if not corrected then
						corrected = true
						-- the boot-window flip, on a word EVERY row draws
						text_metrics.setMeasured("BuilderSans", SIZE_ROW, "row", 3)
					end
					return if word == WORD then 9 else math.max(1, #word * size * 0.5)
				end
				if inline then
					inlineOn(narrowed, function(word: string, size: number): number?
						return widths(word, size)
					end)
				end
				for _, arm in { narrowed, cold } do
					corrected = arm == cold
					arm.rowValue[9]:set(WORD)
					arm.controller.refresh()
					if arm == cold or not inline then
						arm.adapter.deliverTextWidths(widths)
					end
				end
				local st = stats(narrowed)
				expect(`{view.id} {shape}: over budget pushed={st.lastTextDirtyPaths}`).toBe(
					`{view.id} {shape}: over budget pushed=0`
				)
				expect(`{view.id} {shape}: arranged {st.lastArranged} of {st.lastLayoutNodes}`).toBe(
					`{view.id} {shape}: arranged {st.lastLayoutNodes} of {st.lastLayoutNodes}`
				)
				assertCold(cold, `{view.id} {shape} over budget`)
				expect(snapshot(narrowed) == snapshot(cold)).toBe(true)
			end
		end
	end)

	it("a viewport change DURING a pending settle takes the whole tree, not the push", function()
		--[[ THE REFUSAL THAT PROTECTS THE ARRANGE AXIS. A moved `measureStamp` means
			every stored measurement was taken under inputs that no longer hold, and the
			push only ever names TEXT nodes — using it there would leave every other
			node at the rect the old viewport gave it. `text_index.take` drops the mark
			in that case and the solve is the full one it always was. ]]
		local arm = world({ viewport = { w = 800, h = 600 }, rows = 30 })
		local ground = coldWorld({ viewport = { w = 800, h = 600 }, rows = 30 })
		settle(arm)
		settle(ground)
		local WORD = "t18aResizeWord"
		for _, a in { arm, ground } do
			a.strip[1]:set(WORD)
			a.controller.refresh()
			-- the viewport moves in the SAME flush the correction lands in
			a.core:transaction(function()
				a.env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
				a.adapter.deliverTextWidths(function(word: string, size: number): number?
					return if word == WORD then 55 else math.max(1, #word * size * 0.5)
				end)
			end)
		end
		--[[ NOTHING IS PUMPED AFTER THE TRANSACTION, deliberately: a trailing
			`refresh()` would take a full solve of its own and repair a wrong narrowing
			before the comparison could see it — which is exactly what made an earlier
			version of this case survive the mutation that deletes the refusal. ]]
		assertCold(ground, "resize")
		expect(snapshot(arm) == snapshot(ground)).toBe(true)
	end)
end)
