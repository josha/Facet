--!strict
--[[
	CROSS-SOLVE MEASURE REUSE (perf campaign P1) — the demonstrator and its oracle.

	WHAT THE PROFILE FOUND (FacetBench, headless Lune, 2026-09-01, `battle_hud` at
	5115 layout nodes). `solver.solve` consulted `opts.reuse` only in `arrange`; the
	measure pass in front of it had no reuse arm at all. So a refresh with NOTHING
	dirty still measured every node exactly once (`measured = 1.00 N`, 16.1 ms) and a
	refresh with ONE dirty leaf measured every node TWICE (`measured = 2.00 N`,
	24.7 ms) — the ancestor closure always reaches the root, and distributing the root
	stack re-measures every child subtree. 44 % of a step.

	THE DEMONSTRATOR (D-P1) is `result.work.measured` after a one-leaf update on a
	1000-row list. It is a COUNTER, not a clock: `measureUncached` increments it, so a
	served slate does not, and the assertion is the SHAPE of the win rather than its
	speed. Measured on the fixture below, 5010 layout nodes: **5012 at pre-fix HEAD,
	12 with the store** — and the bound is pinned from the fixture's own branching,
	spelled out at the case rather than fitted to the number.

	THE ORACLE, and it is the reason this file is longer than the fix. This memo
	family has shipped wrong twice — the per-solve memo returned geometry without the
	verdicts it published (found only by a differential fuzz over 800 trees), and the
	`textSize = "fit"` key dropped `maxH` on a node whose fit reads it. A cross-solve
	memo adds a THIRD class of failure that no single solve can see: an answer that
	was right when it was stored and is wrong now. So every case below is driven
	THREE ways over the same script and compared channel-for-channel at every step:

	  A  cache ON,  incremental ON   — the shipped default
	  B  cache OFF, incremental ON   — isolates the memo from the arrange skip
	  C  cache OFF, incremental OFF  — a forced FULL SOLVE, i.e. ground truth

	`renderer.attach`'s `measureReuse` opt exists for arm B alone. Comparing A to C
	proves the answer; comparing A to B proves WHICH mechanism moved it.

	THE AXES, each with its own step in the script (`SCRIPT` below names them):
	  · explicit dirty  — a bound value on one row
	  · offer change    — a bound width that re-offers every row
	  · structure       — a row added and removed (`ForEach` over a list signal)
	  · viewport        — the whole device matrix, incl. 320x640, plus a live resize
	  · theme           — a second real theme package swapped in mid-life
	  · text metrics    — `calibrate` moves EVERY estimated word width and dirties
	                      NOTHING; this is the boot-window font-flip class, where the
	                      engine answers a batch, corrects itself ~12 s later, and a
	                      memo that froze the pre-flip measurement paints the old box.

	THE FIXTURE MUST CONTAIN THE SHAPES THE RISK LIVES IN (the lesson
	`incremental_layout.spec` states at length): a truncating `disclose` label, a
	`compactLabel` ladder, a ScrollView, a `containerRelative` dimension inside a
	fixed-width wrapper, a `ViewThatFits` (so `fitProbe` and a hidden candidate are in
	play), and one deliberately malformed box whose measure FILES A DIAGNOSTIC — a
	cross-solve hit removes a subtree's measure, so a finding that stops being filed
	is the quiet failure this file exists to catch.
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
local large_text = require("./lib/large_text")
local text_metrics = require("../src/layout/text_metrics")

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

type Arm = { core: any, env: any, controller: any, adapter: any, rows: any, value: any, wide: any }

-- `cache`/`incremental` are the two knobs the three arms differ by; everything else
-- about the world is identical, which is what makes the comparison mean anything.
local function world(cache: boolean, incremental: boolean, viewport: { w: number, h: number }, rowCount: number): Arm
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
	local rows = core:signal({})
	local items = {}
	for i = 1, rowCount do
		table.insert(items, { id = `r{i}`, n = core:signal(i) })
	end
	rows:set(items)
	-- ONE bound width, read by every row: the OFFER axis. Changing it dirties the
	-- wrapper alone, and every row below it is offered a different width.
	local wide = core:signal(false)
	local wrapWidth = core:memo(function(use: any)
		return px(if use(wide) then 300 else 220)
	end)
	local bp = UI.ScrollView({
		id = "Scroll",
		axis = "y",
		padding = 0,
		gap = 0,
		width = fill(),
		height = fill(),
		children = {
			-- the containerRelative arm: `Bar` sizes against the SCROLLER's viewport,
			-- not against `Wrap`'s offer, and `Wrap`'s own rect never moves
			UI.VStack({
				id = "Wrap",
				padding = 0,
				gap = 0,
				width = px(200),
				height = px(30),
				children = {
					UI.Box({
						id = "Bar",
						width = { type = "containerRelative", fraction = 0.5 },
						height = px(10),
					}),
				},
			}),
			--[[ THE MALFORMED BOX, on purpose. `percent` on the scroller's own
				(unbounded) axis is one of the four measure-time diagnostics, so this is
				the node that proves a cross-solve hit still files what the measure it
				replaced filed. Its subtree is clean on every step but the first. ]]
			UI.Box({ id = "Bad", width = px(40), height = { type = "percent", fraction = 0.5 } }),
			-- a ViewThatFits, so `fitProbe` and a hidden losing candidate are in play
			UI.ViewThatFits({
				id = "Fits",
				width = px(120),
				height = px(24),
				children = {
					UI.Text({ id = "Long", textSize = 12, text = "A rather long candidate label" }),
					UI.Text({ id = "Short", textSize = 12, text = "Short" }),
				},
			}),
			UI.VStack({
				id = "List",
				padding = 0,
				gap = 2,
				width = wrapWidth,
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
								gap = 4,
								width = fill(),
								height = px(28),
								children = {
									UI.Text({
										id = "V",
										textSize = 14,
										text = core:memo(function(use: any)
											return tostring(use(item.n))
										end),
									}),
									-- the truncating label: `textFacts.truncated` lives here
									UI.Text({
										id = "L",
										textSize = 12,
										disclose = true,
										width = px(40),
										text = core:memo(function(use: any)
											return `Extraordinarily Long Identity {use(item.n)}`
										end),
									}),
									-- ...and the compact ladder, the other published verdict
									UI.Button({
										id = "B",
										label = "Configure this row",
										compactLabel = "C",
										width = px(44),
									}),
									UI.Box({ id = "P", width = fill(), height = px(10) }),
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
	adapter.scrollBarThickness = 8
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = incremental,
		measureReuse = cache,
	})
	controller.initialRender()
	return {
		core = core,
		env = env,
		controller = controller,
		adapter = adapter,
		rows = rows,
		value = items,
		wide = wide,
	}
end

-- every live node's rect and every property it carries (the shape
-- `incremental_layout.spec` settled on: an adapter-only comparison is blind to most
-- of what a solve publishes, so the three readers below are all compared)
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
		table.insert(out, `{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|{table.concat(props, ",")}`)
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

--[[ THE DIAGNOSTIC SET, NOT ITS MULTIPLICITY, and the reason is measured rather
	than assumed: a measure-time finding is filed once per measure CALL that reaches
	it, so the same malformed tree already reports 3 copies under a ScrollView and a
	different count without one. The count has never been a contract; the SET is what
	`controller.diagnostics()` is read for, and losing a member of it is the failure
	this channel is in the oracle to catch. ]]
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

local function snapshot(arm: Arm): string
	return `{painted(arm.adapter)}\n--facts--\n{facts(arm.controller)}\n--diag--\n{findings(arm.controller)}`
end

--[[ THE SCRIPT. One ordered list, applied identically to all three arms, so the
	comparison after every step is over the same history rather than the same state —
	a cross-solve memo can only be wrong about a SEQUENCE. Each step names the
	invalidation axis it exercises. ]]
local SCRIPT: { { name: string, run: (Arm, number) -> () } } = {
	{
		name = "explicit dirty: one row's bound value",
		run = function(arm: Arm)
			arm.value[3].n:set(4242)
		end,
	},
	{
		name = "explicit dirty: a second, different row",
		run = function(arm: Arm)
			arm.value[1].n:set(7)
		end,
	},
	{
		name = "offer change: the list wrapper re-offers every row",
		run = function(arm: Arm)
			arm.wide:set(true)
		end,
	},
	{
		name = "explicit dirty under the new offer",
		run = function(arm: Arm)
			arm.value[2].n:set(99)
		end,
	},
	{
		name = "structure: a row is appended",
		run = function(arm: Arm)
			local next_ = table.clone(arm.value)
			table.insert(next_, { id = "rNew", n = arm.core:signal(1234) })
			arm.value[#arm.value + 1] = next_[#next_]
			arm.rows:set(next_)
		end,
	},
	{
		name = "explicit dirty after the structural change",
		run = function(arm: Arm)
			arm.value[#arm.value].n:set(5150)
		end,
	},
	{
		name = "structure: the first row is removed",
		run = function(arm: Arm)
			local next_ = table.clone(arm.value)
			table.remove(next_, 1)
			arm.rows:set(next_)
		end,
	},
	{
		name = "viewport: a live resize",
		run = function(arm: Arm)
			arm.env:set("viewportRect", { x = 0, y = 0, w = 300, h = 500 })
		end,
	},
	{
		name = "explicit dirty at the new viewport",
		run = function(arm: Arm)
			arm.value[2].n:set(31337)
		end,
	},
	{
		name = "theme: a second real package swapped in",
		run = function(arm: Arm)
			arm.env:set("themeMetrics", large_text.THEMES[2].metrics)
		end,
	},
	{
		name = "explicit dirty under the new theme",
		run = function(arm: Arm)
			arm.value[2].n:set(8)
		end,
	},
	{
		name = "text preference: the reservation scale moves with nothing dirty",
		run = function(arm: Arm)
			arm.env:set("preferredTextOffset", 10)
		end,
	},
	{
		name = "offer change back",
		run = function(arm: Arm)
			arm.wide:set(false)
		end,
	},
	--[[ THE FONT FLIP. `calibrate` retightens the per-font average-glyph fraction, so
		EVERY estimated word width moves — and it dirties nothing, publishes no signal
		and moves no rect on its own. It is the headless stand-in for the boot-window
		correction the Roblox adapter delivers ~12 s after the first answer. The step
		after it is what makes it observable: a re-solve the memo must not serve
		pre-flip measurements into. ]]
	{
		name = "text metrics: the font calibration flips",
		run = function(_arm: Arm)
			text_metrics.calibrate("BuilderSans", 0.34)
			text_metrics.calibrate("GothamSSm", 0.34)
			text_metrics.calibrate("SourceSans", 0.34)
		end,
	},
	{
		name = "explicit dirty after the font flip",
		run = function(arm: Arm)
			arm.value[2].n:set(1)
		end,
	},
}

local function drive(arm: Arm, step: number)
	SCRIPT[step].run(arm, step)
	arm.controller.refresh()
end

describe("cross-solve measure reuse (P1)", function()
	it("DEMONSTRATOR D-P1: a one-leaf update at N=1000 measures O(depth), not O(N)", function()
		--[[ THE BOUND, PINNED FROM THE FIXTURE'S OWN BRANCHING RATHER THAN CHOSEN.
			1000 rows of 5 nodes plus the fixed head (Scroll, Wrap, Bar, Bad, Fits and
			its two candidates, List, Rows) is 5 010 layout nodes. The honest closure
			of a one-value update is: the dirty text, its row, the ForEach host, the
			list, the scroller and the root — 6 nodes — each of which is genuinely
			re-measured, some of them twice (the measure pass, then the root's arrange
			distributing the stack). Every one of their clean SIBLINGS is served from
			its slate, and a served slate does not recurse, so nothing under a clean
			sibling is measured at all.

			`8 * depth` with depth 6 is 48: about four times the honest closure, which
			leaves room for an ordinary layout edit to move the constant without
			reddening this, and is three orders of magnitude below the 10 007 the
			pre-fix build measured. The mid-band assertion is deliberate — pinning the
			exact number would make this a change-detector rather than a claim. ]]
		local arm = world(true, true, { w = 400, h = 800 }, 1000)
		--[[ TWO UPDATES, AND THE FIRST ONE IS NOT THE MEASUREMENT. Mount is a full
			solve, which fills nothing (see `solver.solve`: a solve that cannot READ the
			store does not arm the memo to WRITE it either, because that arming is the
			+31 %/+40 % the profile measured on a full solve). The first incremental
			solve after it pays one uncached pass and fills the slates; the second is
			the steady state, which is every frame of a live surface. ]]
		arm.value[500].n:set(4242)
		arm.controller.refresh()
		local filling = arm.controller.stats().lastMeasured
		arm.value[500].n:set(4243)
		arm.controller.refresh()
		local measured = arm.controller.stats().lastMeasured
		expect(filling > 2000).toBe(true)
		expect(measured > 0).toBe(true)
		expect(measured <= 8 * 6).toBe(true)
	end)

	it("...and the same update WITHOUT the memo measures the whole tree twice over", function()
		-- the negative control the demonstrator is meaningless without: this is what
		-- the assertion above reads at pre-fix HEAD, and it is the number the profile
		-- attributed 44 % of a step to.
		local arm = world(false, true, { w = 400, h = 800 }, 1000)
		for i, v in { 4242, 4243 } do
			arm.value[500].n:set(v)
			arm.controller.refresh()
			-- BOTH solves, not just the first: without the store the steady state never
			-- arrives, which is the whole claim
			expect(arm.controller.stats().lastMeasured > 2000).toBe(true)
			local _ = i
		end
	end)

	it("ORACLE: every axis, every step, against BOTH a memo-less and a full solve", function()
		for _, view in device_views.VIEWS do
			local vp = { w = view.w, h = view.h }
			local a = world(true, true, vp, 12)
			local b = world(false, true, vp, 12)
			local c = world(false, false, vp, 12)
			expect(snapshot(a)).toBe(snapshot(c))
			expect(snapshot(a)).toBe(snapshot(b))
			--[[ AFTER EVERY AXIS STEP, TWO PLAIN UPDATES — and the second is where
				engagement is asserted (P1 review, IMPORTANT 4). Every axis step either
				wipes the store (viewport, theme, text scale, text metrics) or forces a
				full solve (structure), and the step right after it is therefore the FILL
				pass, which measures exactly what the memo-less arm does. Asserting
				engagement anywhere in that alternation measures the wipe, not the memo:
				instrumented over the 15 script steps, only 2, 3 and 4 ever ran warm.
				A wipe, a fill, then a hit is the real cycle, so the probe drives it and
				compares the answer at every point of it. ]]
			local engaged, eligible = 0, 0
			local probe = 0
			--[[ what each row was last written, so BOTH rounds are guaranteed to be a
				real change. `set(7)` on a row already holding 7 enqueues nothing, the
				refresh is a no-op, and `lastMeasured` still reports the previous solve —
				which is what made this assertion read 73/73 after a structural step and
				look like a store that never warmed. ]]
			local written: { [number]: number } = {}
			local function warmProbe(label: string)
				probe += 1
				-- THE SAME ROW BOTH ROUNDS. A different row per round makes round 2 a
				-- fresh width change of its own, so nothing is ever warm.
				local row = (probe % 5) + 1
				local first = if written[row] == 7 then 8 else 7
				for round = 1, 3 do
					--[[ TWO SINGLE-DIGIT VALUES, ALTERNATING, and the width is the point.
						A probe that wrote an ever-increasing number changed the value
						label's measured WIDTH every round, which re-offered its siblings
						at a new size every round — twelve distinct offers later each
						slate hit `measure_reuse.KEY_CAP` and wiped itself, and the probe
						then measured its own churn instead of the memo (observed: six
						rounds engaging at on=10/off=68, then a wipe reporting 68/68).
						`7` and `8` dirty the node without moving one offer, which is what
						a live surface's per-frame updates mostly do. ]]
					-- 7 and 8 are both one glyph wide, so a round dirties the node
					-- without moving a single offer — which is what a live surface's
					-- per-frame updates mostly do, and what keeps the slates off
					-- `measure_reuse.KEY_CAP`. An ever-increasing probe value re-offered
					-- every sibling each round and wiped the slates twelve rounds later.
					local value = if round % 2 == 1 then first else (if first == 7 then 8 else 7)
					written[row] = value
					for _, arm in { a, b, c } do
						arm.value[row].n:set(value)
						arm.controller.refresh()
					end
					if snapshot(a) ~= snapshot(c) then
						error(`measure reuse diverged from a FULL solve at {label} probe {round}`, 0)
					end
					if snapshot(a) ~= snapshot(b) then
						error(`measure reuse diverged from the memo-less solve at {label} probe {round}`, 0)
					end
				end
				--[[ THREE ROUNDS, and the count is measured rather than chosen. A
					structural step defers its sync to the NEXT refresh, so round 1 is
					still structural (153 measured on this fixture), round 2 is the FILL
					pass (73) and only round 3 runs warm: a wipe, a fill, then a hit.

					ENGAGEMENT IS ONLY ASKED WHERE AN INCREMENTAL SOLVE HAPPENED, and
					`mb < mc` is the honest test for that. Arm B is the pre-P1 renderer
					exactly, so when it cannot beat a forced full solve, nothing on this
					fixture solved incrementally and the store had nothing it was allowed
					to serve. Measured: from the theme swap onward this fixture solves in
					full every refresh — both arms report 142 against arm C's 142 — which
					is a property of the ornate package's chrome and not of the memo, since
					arm B carries no store at all and behaves identically. `engaged`
					below is what stops that exemption from swallowing the check. ]]
				local ma, mb, mc =
					a.controller.stats().lastMeasured,
					b.controller.stats().lastMeasured,
					c.controller.stats().lastMeasured
				if mb < mc then
					eligible += 1
					if ma < mb then
						engaged += 1
					else
						error(`measure reuse did not engage after {label}: on={ma} off={mb} full={mc}`, 0)
					end
				end
			end

			for step = 1, #SCRIPT do
				drive(a, step)
				drive(b, step)
				drive(c, step)
				local label = `{view.id} step {step} ({SCRIPT[step].name})`
				if snapshot(a) ~= snapshot(c) then
					error(`measure reuse diverged from a FULL solve at {label}`, 0)
				end
				if snapshot(a) ~= snapshot(b) then
					error(`measure reuse diverged from the memo-less incremental solve at {label}`, 0)
				end
				warmProbe(label)
			end
			--[[ `warmProbe` asserted `on < off` — the memo and ONLY the memo, because
				arms A and B differ by nothing else — after every one of the 15 axis
				steps. What stood here was `on < full`, which the ARRANGE SKIP alone
				satisfies: arm C is a forced full solve, so a cache-off incremental arm
				beats it too, and this spec would have stayed green with a store that
				never hit once (P1 review, IMPORTANT 4). Kept as the weaker sibling
				claim, below the strong one. ]]
			expect(eligible >= 7).toBe(true)
			expect(engaged).toBe(eligible)
			expect(a.controller.stats().lastMeasured < c.controller.stats().lastMeasured).toBe(true)
			text_metrics.resetCalibration()
		end
	end)

	it("the malformed subtree keeps FILING while it is clean, not only while it is dirty", function()
		-- the diagnostics channel, on its own, because the oracle above compares it as
		-- a set beside everything else and a set comparison of an empty set passes for
		-- the wrong reason. `Bad` is never dirtied by the script.
		local arm = world(true, true, { w = 400, h = 800 }, 6)
		expect(string.find(findings(arm.controller), "/Scroll/Bad") ~= nil).toBe(true)
		for i = 1, 4 do
			arm.value[i].n:set(i * 13)
			arm.controller.refresh()
			expect(string.find(findings(arm.controller), "/Scroll/Bad") ~= nil).toBe(true)
		end
	end)

	it("a paint-classed prop that layout_node reads as a SIZE input (review CRITICAL 1)", function()
		--[[ THE THIRD-TIME-WRONG BUG, as a regression pin. `surface` was declared
			`dirty = { "paint" }` while `layout_node:822` reads `surface = "badge"` as an
			intrinsic 20px minimum. Paint dirt never sets `needsSolve`
			(`renderer.luau:2878-2884`), so the geometry always landed LATE — on the next
			unrelated solve. The cross-solve store turned late into NEVER: the node is
			absent from `dirtyContains`, its slate is adopted, and the pre-flip
			measurement is served forever.

			MEASURED before the schema fix, driving five solves after the flip:
			cache on `0,0,0,0` every time; cache off `0,0,20,20` from the first. The
			ORDER below is what makes it bite — the store must be FILLED while `surface`
			is still nil, which is why two refreshes precede the flip. `surface` now
			carries `measure`, and `tests/layout_prop_dirt.spec.luau` mechanises the
			whole class so the next one is caught by a check rather than by a review. ]]
		local function badge(cache: boolean): { string }
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
			local surf = core:signal(nil :: string?)
			local tall = core:signal(false)
			local bp = UI.VStack({
				id = "S",
				padding = 0,
				gap = 0,
				children = {
					-- no authored dims: the badge minimum is the ONLY thing that can size it
					UI.Box({
						id = "X",
						surface = core:memo(function(use: any)
							return use(surf)
						end),
					}),
					-- the neighbour whose measure dirt provokes the solve
					UI.Box({
						id = "N",
						width = px(10),
						height = core:memo(function(use: any)
							return px(if use(tall) then 90 else 30)
						end),
					}),
				},
			})
			local root = mountLib.mount(core, bp)
			local adapter = fake_target.new()
			local controller = renderer.attach(core, root, env, adapter, {
				rootPolicy = "edgeToEdge",
				incrementalLayout = true,
				measureReuse = cache,
			})
			controller.initialRender()
			-- FILL THE STORE FIRST, with `surface` still nil
			for i = 1, 2 do
				tall:set(i % 2 == 0)
				controller.refresh()
			end
			surf:set("badge")
			local seen = {}
			for i = 1, 5 do
				tall:set(i % 2 == 0)
				controller.refresh()
				local rect = "-"
				for path, node in adapter.liveNodes() do
					if path == "/S/X" and node.rect ~= nil then
						rect = `{node.rect.w}x{node.rect.h}`
					end
				end
				table.insert(seen, rect)
			end
			return seen
		end
		local on, off = badge(true), badge(false)
		-- converges IMMEDIATELY, and stays converged
		expect(table.concat(on, " ")).toBe("20x20 20x20 20x20 20x20 20x20")
		expect(table.concat(on, " ")).toBe(table.concat(off, " "))
	end)

	it("the boundary analysis is a FULL solve — no reuse, no store (review IMPORTANT 2)", function()
		--[[ `controller.analyzeBoundaries` re-solves through `table.clone` of the LIVE
			`solveOpts` table, so it inherited both `reuse` and `measures`. `ctx.boundary`
			is written in `measureUncached`, so a solve served from slates records almost
			nothing and every unrecorded node reads as "does not absorb" — the report's
			whole subject, inverted. Measured on this shape: **6 absorbing nodes reported
			against the true 11**, and the analysis also wrote into the store the next
			real solve reads. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local v = core:signal(1)
		local kids = {}
		for i = 1, 5 do
			table.insert(
				kids,
				UI.VStack({
					id = `F{i}`,
					padding = 0,
					gap = 0,
					width = px(40),
					height = px(20),
					children = { UI.Box({ id = "In", width = px(10), height = px(10) }) },
				})
			)
		end
		table.insert(
			kids,
			UI.Box({
				id = "D",
				width = px(30),
				height = core:memo(function(use: any)
					return px(10 + use(v))
				end),
			})
		)
		local root = mountLib.mount(core, UI.VStack({ id = "S", padding = 0, gap = 0, children = kids }))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			incrementalLayout = true,
		})
		controller.initialRender()
		-- drive real incremental solves, so a live store and a stale `dirtyContains`
		-- both exist to be wrongly inherited
		for i = 1, 3 do
			v:set(i + 1)
			controller.refresh()
			expect(controller.analyzeBoundaries().absorbingNodes).toBe(11)
		end
		-- ...and the analysis did not disturb the surface it measured
		v:set(99)
		controller.refresh()
		expect(controller.analyzeBoundaries().absorbingNodes).toBe(11)
	end)

	it("a stored finding cannot be corrupted by whoever was handed it (review IMPORTANT 3)", function()
		-- `controller.diagnostics()` clones the LIST, not the entries, and an adopted
		-- slate re-inserts the same tables for as many solves as it survives. Frozen at
		-- capture, so a consumer's write raises at its own line instead of poisoning
		-- every later solve's diagnostics.
		local arm = world(true, true, { w = 400, h = 800 }, 6)
		arm.value[1].n:set(11)
		arm.controller.refresh()
		local before = findings(arm.controller)
		expect(string.find(before, "/Scroll/Bad") ~= nil).toBe(true)
		local target = nil
		for _, d in arm.controller.diagnostics() do
			if d.node == "/Scroll/Bad" then
				target = d
			end
		end
		expect(target ~= nil).toBe(true)
		expect(table.isfrozen(target :: any)).toBe(true)
		local ok = pcall(function()
			(target :: any).issue = "corrupted"
		end)
		expect(ok).toBe(false)
		-- and the next solves are unaffected
		for i = 2, 4 do
			arm.value[i].n:set(i * 7)
			arm.controller.refresh()
			expect(findings(arm.controller)).toBe(before)
		end
	end)

	it("the text-measure epoch sees a width OVERWRITTEN, which `measuredCount` cannot", function()
		--[[ THE BOOT-WINDOW FONT FLIP, at the seam. The Roblox adapter answers the same
			batch twice, up to ~12 s apart, and the second answer CORRECTS the first —
			same font, same size, same word, different width. `measuredCount` counts
			distinct words and does not move for that, and the renderer's
			`textMeasureEpoch` env fact (renderer.luau, the `learned` branch) sees it but
			is not bumped by `calibrate` at all. This counter is what the measure store's
			stamp reads, so it has to see both. ]]
		local before = text_metrics.epoch()
		local words = text_metrics.measuredCount()
		expect(text_metrics.setMeasured("BuilderSans", 21, "facet-p1-probe", 40)).toBe(true)
		local afterFirst = text_metrics.epoch()
		expect(afterFirst > before).toBe(true)
		-- the CORRECTION: a distinct word count that did not move, and an epoch that did
		expect(text_metrics.setMeasured("BuilderSans", 21, "facet-p1-probe", 57)).toBe(true)
		expect(text_metrics.measuredCount()).toBe(words + 1)
		expect(text_metrics.epoch() > afterFirst).toBe(true)
		-- ...and re-asserting the SAME width is not a change
		local settled = text_metrics.epoch()
		expect(text_metrics.setMeasured("BuilderSans", 21, "facet-p1-probe", 57)).toBe(true)
		expect(text_metrics.epoch()).toBe(settled)
		-- calibration is the other producer, and the one `textMeasureEpoch` misses
		text_metrics.calibrate("BuilderSans", 0.33)
		expect(text_metrics.epoch() > settled).toBe(true)
		-- the calibration is global and MUST be put back; the probe word is not (it
		-- names a size and a spelling no fixture in this suite measures, and wiping
		-- the whole exact-width store would take other specs' measurements with it)
		text_metrics.resetCalibration()
	end)
end)
