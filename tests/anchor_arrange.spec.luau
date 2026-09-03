--!strict
--[[ N2 — THE SINGLE-UPDATE FLOOR IS THE CONTAINER, NOT THE CHANGE.

	There is no "list" layout node: `ForEach` splices its children into the parent
	(`layout_node.luau`'s ForEach region), so the canvas is ONE `anchor` with 250
	direct children and the solver's anchor arrange branch re-offers and re-places
	every one of them to settle a single dirty child. Per child, unconditionally: one
	`measure()` (a memo HIT still allocates the interpolated `{maxW}|{maxH}|{scopeKey}`
	cacheKey), one rect table, two `dim()` and two `offsetPx()` calls. That is the
	146 KB a step this fixture measures for a 3-node change — and the same floor sits
	under every add and every remove.

	WHY A PER-CHILD SKIP IS SOUND HERE AND NOWHERE ELSE: an anchor child's rect is a
	pure function of (innerX, innerY, innerW, innerH, child.anchor, child.offsetX/Y,
	measure(child, innerW, innerH)) — NO SIBLING APPEARS IN IT. A stack's does (every
	child feeds `fixedMain` / `fillWeightSum` and then the cursor, now
	`src/layout/stack.luau`), which is why this task touches the anchor branch only.

	AND THE COUNTER HAD TO BE A NEW ONE, which is the correction this file carries
	against the task brief. The brief expected `lastMeasured` to show the 250 and it
	CANNOT: `ctx.measured` is incremented inside `measureUncached`, and a sibling's
	re-offer is a memo HIT that returns before reaching it. Measured at the base of
	this task, an `hp` step on 250 plates read `arranged=4 measured=7` ALREADY — the
	dirty chain and nothing else — while the anchor branch was calling `measure` 250
	times and allocating 146 KB doing it. A demonstrator built on `measured` would
	have been green before the change and green after it, which is the "check that
	proves nothing" class this repository has a gate for. `work.anchorOffered` /
	`work.anchorReused` are the two halves of the loop this task changes and their sum
	is every child of every anchor the solve arranged, so a regression cannot hide in
	the split. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local solver = require("../src/layout/solver")
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")

local PLATES = scene.PLATES -- 250

--[[ THE VIEWPORT STEP THE FIXTURE HAS NO VERB FOR. `nameplates_scene` drives
	signals (`tick`, `hp`, `add`, `remove`) and the viewport is not one — it is an
	ENV fact, set at construction. Driving it is `env:set` + `controller.refresh()`,
	the idiom `tests/adaptive_defaults.spec.luau` uses on its own scene, reaching for
	the two handles the fixture already publishes rather than growing a verb on a
	shared fixture for one spec's sake. ]]
local function resize(w: any, width: number, height: number)
	w.env:set("viewportRect", { x = 0, y = 0, w = width, h = height })
	w.controller.refresh()
end

--[[ READ OFF THE RUN (2026-09-02, at the T6 base `93fcd06e`), both of them, with
	the node names beside them. They are NOT knowable on paper, and the protocol here
	is the round's: correct the EXPRESSION and this comment, never the assertion.

	`arranged = 4` — the dirty chain is Screen + Canvas + Plate + Hp. The Canvas is in
	`dirtyContains` (a prefix of the Hp write) so it arranges; the plate's Row and
	Cast do not, because the plate's content height did not move when Hp's width
	changed, so both land on the rect they already had and take the skip.

	`measured = 7` — bucketed by node id with a temporary counter inside
	`measureUncached` (reverted before commit): `/S` x1 and `/S/Canvas` x1 and the
	plate root x1, all three slate refusals because they are dirty, plus `Hp` x2 and
	`Cast` x2 — both are fixed x fixed, hence PLAN_SKIP, hence counted on EVERY touch
	with no memo, and the plate's vstack touches them once in its measure pass and
	once in its arrange pass. 3 + 2 + 2 = 7.

	NEITHER MOVES IN THIS TASK, and that is stated here rather than discovered by the
	next reader: both are already the dirty chain alone. They are pinned as the
	INVARIANT half — the thing the anchor arm must not break — while
	`anchorReused`/`anchorOffered` and the KB are the half that moves. ]]
local ARRANGED_HP = 4 -- Screen + Canvas + Plate + Hp
local MEASURED_HP = 7 -- (Screen + Canvas + Plate) + Hp x2 + Cast x2, all PLAN_SKIP or dirty

--[[ ...AND THE HALF THAT MOVES, read off the run for every step kind the fixture
	drives. Before this task every one of them was `reused = 0, offered = 250`.

	THE GATE IS THE *MEASURE* HALF OF THE DIRT, not the whole closure, and these
	numbers are what that decision is worth. The arm reuses one thing — the child's
	SIZE — so the question is the one `measure`'s own cross-solve adopt gate asks: did
	anything change inside this subtree that a MEASUREMENT could read? A `tick` writes
	`offsetX`/`offsetY` on all 250 plates, which is ARRANGE-classed dirt: every plate
	is in `dirtyContains` and none of them is in `measureContains`, so the arm serves
	all 250 and `offered` is ZERO. On `dirtyContains` it would have been the reverse,
	and the same reversal was measured on Rascal Rally's shipped minimap, where a
	one-dot move re-runs every dot's family-hue memo (see
	`RascalRally/code/tests/facet_anchor_arrange.spec.luau`).

	`tickWithCasts` IS THE NEGATIVE CONTROL, and it is a real one rather than a
	drill: it moves every plate AND advances the Cast bar of the deterministic
	one-in-five subset with `{ type = "fixed", px = cast * 100 }` — a MEASURE-class
	write. Exactly those 50 plate roots go to `measure` and exactly the other 200 do
	not, so a gate that had collapsed to "always reuse" reads 250/0 here and fails. ]]
local REUSED_HP = PLATES - 1 -- 249: every plate but the one whose Hp width changed
local OFFERED_HP = 1 -- the dirty plate root alone
local CASTERS = PLATES // scene.CASTER_EVERY -- 50

--[[ The solver's `work` block is not on the controller's public surface and this
	task adds nothing to it, so the counters are read the way
	`tests/translate_arm.spec.luau` reads the entry map: wrap the module function for
	the duration of one case and put it back. `renderer.luau` calls `solver.solve(...)`
	as a field lookup, so the wrapper is on the shipped path; it is restored even when
	the body throws. ]]
local capturedResult: any = nil
local function withWorkCapture(fn: () -> ())
	local real = solver.solve
	solver.solve = function(...)
		local r = real(...)
		capturedResult = r
		return r
	end
	local ok, err = pcall(fn)
	solver.solve = real
	if not ok then
		capturedResult = nil
		error(err, 0)
	end
end

local function anchorKey(): string
	local w = capturedResult.work
	return `reused={w.anchorReused} offered={w.anchorOffered}`
end

describe("N2: one changed plate does not re-offer 250 siblings", function()
	it("an hp step re-offers ONE anchor child and serves the other 249 from their own rect", function()
		withWorkCapture(function()
			local s = scene.new()
			s.tick(3, 2)
			s.hp(7, 0.9)
			--[[ The two halves sum to every child of the one anchor this fixture has, so
				a "win" that simply stopped visiting children shows up here as a sum that
				is no longer 250 rather than as a smaller `offered`. ]]
			expect(anchorKey()).toBe(`reused={REUSED_HP} offered={OFFERED_HP}`)
			local w = capturedResult.work
			expect(w.anchorReused + w.anchorOffered).toBe(PLATES)
			s.dispose()
		end)
	end)

	it("...and an ADD offers only the new plate, a REMOVE none at all", function()
		--[[ THE STRUCTURAL STEPS, which is where the arena measures the win (see the
			allocation case below). A structural solve rebuilds the ForEach's children,
			so the anchor re-offers all 251 — but only the NEW plate is dirty, so 250
			take the arm and one goes to `measure`. A REMOVE adds no node at all, so it
			offers NOTHING and every surviving sibling is served from its own rect. ]]
		withWorkCapture(function()
			local s = scene.new()
			s.tick(3, 2)
			s.add(9001)
			expect(`add:{anchorKey()}`).toBe(`add:reused={PLATES} offered=1`)
			s.remove(1)
			expect(`remove:{anchorKey()}`).toBe(`remove:reused={PLATES} offered=0`)
			s.dispose()
		end)
	end)

	it("...and a TICK, which moves all 250 and resizes none, offers NOTHING", function()
		--[[ THE HEADLINE STEP. `offsetX`/`offsetY` are arrange-classed, so a tick puts
			every plate in `dirtyContains` and NONE of them in `measureContains` — their
			sizes cannot have moved. The anchor therefore re-places all 250 and measures
			none of them. This is the case the `measureContains` gate exists for. ]]
		withWorkCapture(function()
			local s = scene.new()
			s.tick(3, 2)
			expect(`tick:{anchorKey()}`).toBe(`tick:reused={PLATES} offered=0`)
			s.tick(3, 2)
			expect(`tick again:{anchorKey()}`).toBe(`tick again:reused={PLATES} offered=0`)
			s.dispose()
		end)
	end)

	it("NEGATIVE CONTROL: a caster tick resizes 50 plates, and exactly those 50 are measured", function()
		--[[ THE ARM IS NOT A BLANKET SKIP, and this is the case that says so with a
			number that is neither 0 nor 250. `tickWithCasts` moves every plate and
			advances the Cast bar of the one-in-five subset — a `{ type = "fixed", px =
			cast * 100 }` write, which IS measure-classed — so the 50 caster roots are in
			`measureContains` and go to `measure`, and the other 200 do not. A gate that
			collapsed to "always reuse" would serve a stale size to a plate that really
			did resize; it reads 250/0 here and this fails. ]]
		withWorkCapture(function()
			local s = scene.new()
			s.tick(3, 2)
			s.tickWithCasts(3, 2)
			expect(`casts:{anchorKey()}`).toBe(`casts:reused={PLATES - CASTERS} offered={CASTERS}`)
			s.tickWithCasts(3, 2)
			expect(`casts again:{anchorKey()}`).toBe(`casts again:reused={PLATES - CASTERS} offered={CASTERS}`)
			s.dispose()
		end)
	end)

	it("...and the dirty chain is untouched: the same arranged and measured as before", function()
		local s = scene.new()
		s.tick(3, 2)
		s.hp(7, 0.9)
		local st = s.stats()
		-- the dirty chain, and nothing else. What makes this a real assertion is the
		-- number's SIZE, not its exact value: 250 re-offered siblings cannot fit in it
		-- under any reading.
		expect(`arranged={st.lastArranged} measured={st.lastMeasured}`).toBe(
			`arranged={ARRANGED_HP} measured={MEASURED_HP}`
		)
		expect(`arrangedUnder10={st.lastArranged < 10} measuredUnder10={st.lastMeasured < 10}`).toBe(
			"arrangedUnder10=true measuredUnder10=true"
		)
		s.dispose()
	end)

	it("...and the ALLOCATION RECORD, which is not the one the brief predicted", function()
		--[[ THE HEAP IS READ, NEVER COLLECTED. `collectgarbage("collect")` is not
			available under Lune 0.10.4 (it raises "collectgarbage called with invalid
			option"); `"count"` is. So a window is a plain delta over ten identical steps
			after a warm-up, which measures ALLOCATION RATE rather than retention — and a
			collection landing inside a window can only make the number SMALLER.

			WHICH IS WHY ONLY THE hp NUMBER IS ASSERTED HERE. The structural window
			allocates ~3 MB and the collector reliably runs inside it: interleaved
			BASE/T6/T6/BASE through this very case, the add+remove medians read -38.68,
			202.16, 285.00 and 326.27 — a BASE arm produced the smallest number of the
			four, so a "<300" ceiling on it would have been a false green on the code it
			was written to reject. The hp window allocates ~1.6 MB and does not trip a
			collection: 146.41, 159.08, 159.08, 146.33 on the same four runs, split
			exactly by arm. A pin is only worth having where the instrument separates the
			arms, so the structural claim is the COUNTER case above and the arena row in
			the ledger, not a number from here.

			WHAT THE BRIEF EXPECTED: 125 KB a step on the hp step, dominated by the 250
			`measure()` calls the anchor loop makes, coming down under 20 KB. MEASURED, it
			is none of that. Four arms, medians of five, one process per arm:

			  | arm                                        | hp KB/step |
			  | base: no arm, no memo-hit offer recording  |     146.41 |
			  | arm only, and its own offer writes removed |     143.66 |
			  | memo-hit offer recording only, no arm      |     159.16 |
			  | SHIPPED: both                              |     159.16 |

			The 250 memo-HIT `measure()` calls the arm removes are worth 2.75 KB on this
			step, not 125 — a hit builds an interpolated cacheKey that is IDENTICAL for
			all 250 children (same offer, same scope) and Luau interns it, so 250 builds
			are one allocation. And recording the offer on the memo-hit path (the ruling
			that makes the arm reachable at all — see `tests/translate_arm.spec.luau`)
			costs +15.5 KB, because `ctx.offers` is fresh per solve and now holds two
			entries for every node the solve measured: ~500 hash slots at 32 bytes is
			16 KB, which is the number. THE hp STEP THEREFORE ENDS UP 12.75 KB WORSE ON
			THIS FIXTURE (+8.7 %), and it is written down here rather than left to be
			found. Its cause is the offer CHANNEL, not the arm — and the arena, where the
			same channel is paid on far more nodes, comes out 6.3 % AHEAD on the tick's
			allocation, so the trade is favourable everywhere it has been measured except
			this one step of this one fixture.

			WHERE THE WIN IS: the structural steps, whose anchor children are not already
			measured by the measure side. FacetBench `nameplates L`, ABBA n=4 per arm,
			arms DISJOINT — add gcKb 280.3 -> 203.0 (-27.6 %) and p50 1.317 -> 1.095 ms
			(-16.9 %); remove gcKb 227.4 -> 155.3 (-31.7 %) and p50 1.296 -> 1.025 ms
			(-20.9 %); the tick's gcKb 3212.6 -> 3071.6 (-4.4 %) with its p50 unmoved.

			The ceiling below is loose on purpose: 159 measured, a doubling caught, a
			10 % machine difference tolerated. The EXACT claims of this task are the
			counters above. ]]
		local vals: { number } = {}
		for _ = 1, 5 do
			local s = scene.new()
			s.tick(3, 2)
			for i = 1, 4 do
				s.hp(7, 0.3 + i * 0.01)
			end
			local k0 = collectgarbage("count") :: number
			for i = 1, 10 do
				s.hp(7, 0.5 + i * 0.01)
			end
			local k1 = collectgarbage("count") :: number
			table.insert(vals, (k1 - k0) / 10)
			s.dispose()
		end
		table.sort(vals)
		local hpKb = vals[3]
		print(`anchor_arrange hp kbPerStep={string.format("%.2f", hpKb)}`)
		expect(`hpKb<250={tostring(hpKb < 250)}`).toBe("hpKb<250=true")
	end)

	it("...at every device view", function()
		withWorkCapture(function()
			for _, view in device_views.VIEWS do
				local s = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
				s.tick(3, 2)
				s.hp(7, 0.9)
				expect(`{view.id}:{anchorKey()}:{s.stats().lastArranged}`).toBe(
					`{view.id}:reused={REUSED_HP} offered={OFFERED_HP}:{ARRANGED_HP}`
				)
				s.dispose()
			end
		end)
	end)

	it("A VIEWPORT CHANGE FALLS THROUGH: a new offer re-measures every child", function()
		--[[ THE ARM'S PRECONDITION IS THE OFFER, NOT THE DIRT, and this is the case
			that proves the difference is real rather than decorative. Re-attaching at a
			different viewport changes the anchor's inner extent, so `prev.offerW` no
			longer equals `innerW` for ANY child and all 250 go to `measure` — which is
			also what makes the 320x640 row of the oracle below meaningful instead of
			vacuous. ]]
		withWorkCapture(function()
			local s = scene.new({ viewport = { x = 0, y = 0, w = 1280, h = 720 } })
			s.tick(3, 2)
			s.hp(7, 0.9)
			expect(anchorKey()).toBe(`reused={REUSED_HP} offered={OFFERED_HP}`)
			resize(s, 1000, 700)
			expect(anchorKey()).toBe(`reused=0 offered={PLATES}`)
			-- ...and the very next step at the SETTLED viewport arms again, so the arm
			-- is not one-shot
			s.hp(7, 0.4)
			expect(anchorKey()).toBe(`reused={REUSED_HP} offered={OFFERED_HP}`)
			s.dispose()
		end)
	end)
end)

--[[ THE ORACLE — the same three arms `tests/translate_arm.spec.luau` and
	`tests/measure_split.spec.luau` use, because the risk of a per-child skip is
	exactly the risk of a per-subtree one: an arm that serves a stale size produces a
	green counter and a wrong screen. `a` is the shipped configuration, `b` keeps
	incremental arrange but throws the measure slates away, and `c` forces a FULL
	solve every refresh and is the ground truth. The channel is `scene.snapshot()` —
	every live node's rect, hit rect, scroll region, visibility and adapter props,
	sorted — plus the diagnostics.

	THE OVERFLOW FIXTURE MATTERS MOST HERE: a plate 2,000px wide changes what the
	anchor's own hug path would compute, and the arm must not serve a stale size to
	it. ]]
local function arms(view: any, opts: any): (any, any, any)
	local base = table.clone(opts or {})
	base.viewport = { x = 0, y = 0, w = view.w, h = view.h }
	local a = table.clone(base)
	local b = table.clone(base)
	b.measureReuse = false
	local c = table.clone(base)
	c.measureReuse = false
	c.incremental = false
	return scene.new(a), scene.new(b), scene.new(c)
end

-- see `measure_split`'s note: the tree SHAPE is what correctness depends on and it
-- is per-plate identical, so 20 plates exercises every branch 250 does. The COUNT
-- pins above run at the full 250.
local ORACLE_PLATES = 20

local function diagKey(w: any): string
	local out = {}
	for _, d in w.controller.diagnostics() do
		table.insert(out, `{d.node}|{string.sub(d.issue, 1, 32)}`)
	end
	table.sort(out)
	return `{#out}: ` .. table.concat(out, " ")
end

describe("N2 oracle: byte-equal to a full solve, every view, every step kind", function()
	local FIXTURES: { any } = {
		{ name = "plain", plates = ORACLE_PLATES },
		{ name = "overflow", plates = ORACLE_PLATES, overflow = true },
		{ name = "fractional", plates = ORACLE_PLATES, fractional = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects, visibility, hit rects, scroll regions and findings survive`, function()
			for _, view in device_views.VIEWS do
				local a, b, c = arms(view, fixture)
				local label = `{fixture.name}/{view.id}`
				local function step(what: string, compareB: boolean, drive: (any) -> ())
					drive(a)
					drive(b)
					drive(c)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: {what} diverged from a FULL solve`, 0)
					end
					if compareB and a.snapshot() ~= b.snapshot() then
						error(`{label}: {what} diverged from the memo-less solve`, 0)
					end
					if diagKey(a) ~= diagKey(c) then
						error(`{label}: {what} diagnostics diverged from a FULL solve`, 0)
					end
				end
				if a.snapshot() ~= c.snapshot() then
					error(`{label}: diverged from a FULL solve at mount`, 0)
				end
				for round = 1, 4 do
					local dx, dy = round * 3, round * 2
					step(`tick {round}`, true, function(w)
						w.tick(dx, dy)
					end)
					step(`caster tick {round}`, false, function(w)
						w.tickWithCasts(dx, dy)
					end)
					step(`hp {round}`, false, function(w)
						w.hp(7, 0.1 * round)
					end)
					step(`add {round}`, false, function(w)
						w.add(round)
					end)
					step(`tick-after-add {round}`, false, function(w)
						w.tick(dx, dy)
					end)
					step(`remove {round}`, false, function(w)
						w.remove(round)
					end)
					--[[ ...AND THE THREE DRIVES THE SIBLING ORACLES DO NOT TAKE, added
						because the `measureContains` gate widened what this arm serves:
						`hide` is arrange-classed (the plate keeps its size), `align` is a
						container-level word this anchor's children carry, and `nudgeLabel`
						rewrites a plate's NAME — a text write, the measure-classed dirt the
						gate must let through. A child served a stale size after any of the
						three would show up here as a rect diverging from a full solve. ]]
					step(`hide {round}`, false, function(w)
						w.hide(2, round % 2 == 1)
					end)
					step(`align {round}`, false, function(w)
						w.align(if round % 2 == 1 then "center" else "start")
					end)
					step(`nudgeLabel {round}`, false, function(w)
						w.nudgeLabel(4, `Renamed {round}`)
					end)
					--[[ ...AND A VIEWPORT CHANGE, which is the step the other two oracles
						in this repository do not take and the one this arm is most exposed
						to: it changes `innerW`/`innerH`, so every recorded offer stops
						matching and the arm must fall through for all of them. A stale
						`prev.rect` served here is a wrong screen. ]]
					step(`resize {round}`, false, function(w)
						resize(w, view.w - round, view.h - round)
					end)
					step(`resize-back {round}`, false, function(w)
						resize(w, view.w, view.h)
					end)
				end
				a.dispose()
				b.dispose()
				c.dispose()
			end
		end)
	end
end)
