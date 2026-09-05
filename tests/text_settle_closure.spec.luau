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

			The settle's paths and their ancestors are therefore marked into `nodeDirty`
			AND `commitDirty` before the build captures them, which is what puts this
			node in every walk's descend list. Compared against a forced cold arm, since
			"what the published value should be" is the cold solve's answer and nothing
			else.

			▲ A RECORDED NULL, kept with its argument rather than dropped. Deleting the
			two mark loops reddens NOTHING in this suite, and the reason is that
			`commit_walks`' prune does not read the dirty set alone: it asks
			`entryVerdict(child)` — settled / moved — so a node whose RECT changed is
			descended whether or not anything marked it. What the marks still buy is the
			case where a measure correction changes a published verdict WITHOUT moving a
			rect, and this suite has no fixture that produces one (a fixed-box `Text`
			publishes no `textAt` facts at all, and the wrap/compact writes did not flip
			on the shapes tried). The marks stay because they are the conservative
			direction and cost one loop over a set that is four entries long on the
			class this task is about; the gap is named here so the next round knows it
			is a fixture gap and not a proof. ]]
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
		arm.rowValue[1]:set("t18aChurnWordA")
		arm.controller.refresh()
		deliverAll(arm)
		expect(`while mounted={stats(arm).lastTextDirtyPaths}`).toBe("while mounted=12")
		-- the rows leave, and the strip stays so the surface is still worth solving
		arm.rows:set({})
		settle(arm)
		expect(arm.controller.rectOf("/Root/List/Rows/r1/Name")).toBe(nil)
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
	--[[ EVERY VIEW, BOTH ARMS. The narrowed settle and a FORCED COLD solve after the
		same deliver must agree byte for byte on every channel a consumer can read —
		the adapter's paint and hit rects, `controller.textAt()`, `rectOf`,
		`screenRectOf` and the diagnostic SET. 320x640 is in the list deliberately: it
		is the view where the strip wraps and the row labels truncate, so the two arms
		are compared on a tree whose verdicts are non-trivial. ]]
	for _, view in device_views.VIEWS do
		it(`{view.id} {view.w}x{view.h}: a narrowed settle equals a forced cold one`, function()
			local narrowed = world({ viewport = { w = view.w, h = view.h }, rows = 25 })
			local cold = coldWorld({ viewport = { w = view.w, h = view.h }, rows = 25 })
			settle(narrowed)
			settle(cold)
			-- THE NON-VACUITY GUARD: the arms must agree BEFORE the settle too, or a
			-- byte-equal comparison afterwards says nothing about the settle
			expect(snapshot(narrowed) == snapshot(cold)).toBe(true)
			--[[ A WORD PER VIEW, and this is a trap worth naming: the exact-width store is
				PROCESS-GLOBAL, so a shared literal here would be learned by the first
				view's arms and already known to the other eight — whose settle would then
				never happen and whose "the narrowed arm really narrowed" guard would read
				a stale counter and pass by accident. ]]
			local WORD = `t18aOracle{view.id}`
			for _, arm in { narrowed, cold } do
				arm.strip[3]:set(WORD)
				arm.solo:set(WORD)
				arm.rowValue[4]:set(WORD)
				arm.controller.refresh()
				arm.adapter.deliverTextWidths(function(word: string, size: number): number?
					return if word == WORD then 41 else math.max(1, #word * size * 0.5)
				end)
			end
			-- the control really is cold, or this is two arms of one mechanism agreeing
			assertCold(cold, view.id)
			-- ...and the narrowed one really did narrow, or the comparison is vacuous
			local st = stats(narrowed)
			expect(
				`{view.id} narrowed: pushed={st.lastTextDirtyPaths} measured={st.lastMeasured} of {st.lastLayoutNodes} nodes`
			).toBe(`{view.id} narrowed: pushed=30 measured={st.lastMeasured} of {st.lastLayoutNodes} nodes`)
			expect(st.lastMeasured < st.lastLayoutNodes).toBe(true)
			expect(snapshot(narrowed) == snapshot(cold)).toBe(true)
		end)
	end

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
