--!strict
--[[ O2 — MEASURE DIRT AND ARRANGE DIRT ARE NOT THE SAME SET.

	`renderer.luau`'s ancestor closure (the `else` arm beside `dirtyClosure`)
	closes the dirty set over ancestors for `measure` AND `arrange` entries
	together, and hands the union to the solver as one `dirtyContains`. The solver
	reads it twice for two different questions: the arrange skip (`solver.luau`,
	`arrange`'s `reuse.dirtyContains[node.id] ~= true`) asks "did anything inside
	move?", and the ADOPT GATE (`solver.measure`'s `measureReuse.adopt` call) asks
	"can this node keep the measure slate it filled last solve?".
	`offsetX`/`offsetY`/`anchor` are `dirty = { "arrange" }`
	(`blueprint_schema.luau:754-780`) and measure provably never reads them — the
	audit at the foot of `tests/layout_prop_dirt.spec.luau` MOUNTS each
	arrange-only prop and proves the solve measures nothing — so every offset-only
	step throws away a measure slate it could have kept.

	WHY THE BEFORE NUMBER IS AS BIG AS IT IS, INSTRUMENTED RATHER THAN ASSUMED —
	AND THE PLAN'S OWN GUESS WAS WRONG. `tests/nameplates_baseline.spec.luau` pins
	the steady tick at `MEASURED_STEADY = LAYOUT - PLATES = 1252` and says outright
	that its MECHANISM was not instrumented. T3 Step 2 instrumented it (temporary
	buckets beside `ctx.measured += 1` and beside the `measureReuse.adopt` call,
	keyed by `memoPlan` verdict, by `node.kind`, by the path leaf and by whether
	the node was in `dirtyContains`; reverted before commit). The plan predicted "a
	fresh slate for every `dirtyContains` id, PLUS the PLAN_SKIP leaves under
	them", i.e. a CASCADE of refusals down each dirty subtree. It is not that. The
	measured steady pure tick is:

	  | bucket                                                    | calls |
	  |-----------------------------------------------------------|-------|
	  | PLAN_SKIP `Hp` + `Cast` — 500 boxes, each touched TWICE    |  1000 |
	  | slate REFUSED because the node is in `dirtyContains`:      |       |
	  |   250 `Plate` roots (PLAN_HEIGHT_FREE) + `Canvas` + `S`    |   252 |
	  | slate ADOPTED and HIT: 250 `Row` + 250 `Name` + 250 `Lvl`  |     0 |
	  |                                                     total | 1252 |

	So there is NO cascade: the 750 `Row`/`Name`/`Lvl` nodes below each refused
	plate root already come back `adopted = true` today and cost nothing — the
	fresh-slate write in `measure_reuse.adopt` lands on the named node alone, and a
	descendant that is not named keeps its own slate. The whole 1252 is (a) 1000
	PLAN_SKIP touches, which no dirt set can remove because a PLAN_SKIP node never
	consults a slate at all (`solver.luau:1588-1590` returns straight to
	`measureUncached`), and (b) the 252 refusals this task is about. Two touches
	per PLAN_SKIP box because the plate's own measure pass and its vstack ARRANGE
	pass each call `measure` on it.

	The steady CASTER tick reads the identical 1252 with the identical shape —
	1000 PLAN_SKIP touches (the 50 casters' `Cast` boxes merely move 100 of them
	from `inSet=false` to `inSet=true`) plus the same 252 refusals. That is why
	`nameplates_baseline`'s fourth case observes a pure and a caster tick reading
	the same number before T3: the counter that separates them is `lastNodeBuilds`,
	not `lastMeasured`.

	AND THE AFTER NUMBER IS NOT ZERO AT THIS TASK — IT CANNOT BE, BY CONSTRUCTION.
	The split fixes the ADOPT gate; it does not stop the plate's own arrange from
	descending. At T3 there is no translate arm yet, so a moved plate root is in
	`dirtyContains`, fails the arrange skip, and takes the vstack arrange branch,
	which measures each non-hug child (`solver.luau`'s vstack arrange,
	`local w, h = measure(ctx, child, innerW, innerH)`). `Row` (height px(16)) hits
	its slate and costs nothing; `Hp` and `Cast` are fixed x fixed, hence
	`PLAN_SKIP` (`measure_facts.luau:409-412`), hence sent straight to
	`measureUncached` (`solver.luau:1588-1590`) and counted on EVERY touch. So the
	pure-tick pin here is `PLATES * 2` — ONE touch of `Hp` and one of `Cast` per
	plate, from the plate's ARRANGE pass alone. (Before the split it was two of
	each: the refused plate root re-measured, and its measure pass descended into
	them as well. The split removes the measure descent, not the arrange one.) The
	`== 0` pin belongs to T4's translate arm, where the solver stops re-entering
	the subtree at all; a demonstrator that pinned 0 here would be red for the
	whole of T3 with no fix available, which is the "unreachable green" class.

	THE CASTER NUMBER IS READ OFF THE RUN, and it is not knowable on paper: it is
	the sum of how many ancestors lose their slate when a `Cast` box's MEASURE dirt
	closes over them, how many of those are themselves PLAN_SKIP, and how many
	times the vstack branch touches the PLAN_SKIP leaves under a caster. Step 2 ran
	it with the same buckets and the expression below carries the breakdown. THE
	PROTOCOL: update the EXPRESSION and its comment, never the assertion.

	AND T4 (`14c3459d`) MADE THE `== 0` PIN REACHABLE, WHICH IS THE OTHER HALF OF
	THIS FILE'S STORY. Everything above describes the world in which a moved plate
	root fails the arrange skip and takes the vstack arrange branch. T4's translate
	arm gives `arrange` a THIRD outcome — same size, moved origin, no dirty child,
	and the root's own dirt is dirt its PARENT already spent (`solver.selfPlaces`) —
	which re-bases the subtree by one delta and never enters it. The arrange descent
	is what made every PLAN_SKIP touch, so:
	  * `MEASURED_TICK` 500 -> 0. The T3 floor was `PLATES * 2`, ONE touch of `Hp`
	    and one of `Cast` per plate from the plate's own arrange pass. There is no
	    arrange pass now, so there are no touches, and the pure tick measures
	    nothing at all.
	  * `MEASURED_WITH_CASTS` 652 -> 252. The three terms in the table below are
	    untouched in MEANING; the first one — the 200 quiet plates' `(PLATES -
	    CASTERS) * 2` — simply goes to zero, because those plates translate. The
	    50 caster plate roots still take the ordinary arrange (their `Cast` child is
	    dirty, so `translatable` refuses) and still cost 5 apiece, and `Canvas` and
	    the `Screen` root still lose their slates: `CASTERS * 5 + 2`.
	Both numbers READ OFF THE RUN, same protocol. This is the one pin in the round
	that two tasks move, and the mechanism for both moves is written into this
	header and into `tests/nameplates_baseline.spec.luau`'s schedule table.
	`tests/translate_arm.spec.luau` owns the arm itself. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")

local PLATES = scene.PLATES
local CASTERS = PLATES // scene.CASTER_EVERY -- 50
-- Hp and Cast are fixed x fixed => PLAN_SKIP => `measureUncached` counts them on
-- every touch, and the plate's own ARRANGE used to touch both (its measure pass
-- hits the adopted slate and never descends). That was the T3 floor of
-- `PLATES * 2` = 500, bucketed as `SKIP box Hp = 250` + `SKIP box Cast = 250` and
-- nothing else. T4's translate arm (`14c3459d`) removes the arrange descent as
-- well, so the touches stop: READ OFF THE RUN as 0, the pin T3 said belonged here
-- and could not reach. See the header.
local MEASURED_TICK = 0
--[[ READ OFF THE RUN in Step 2, with the plan-verdict buckets beside it — 652,
	and it is three terms, not one:

	  | term                        | bucket after the split                | n   |
	  |-----------------------------|---------------------------------------|-----|
	  | `(PLATES - CASTERS) * 2`    | `SKIP Hp` + `SKIP Cast`, measureSet   | 400 |
	  |   the 200 quiet plates      | FALSE — their root adopts, so only     |     |
	  |                             | its arrange pass touches the leaves    |     |
	  | `CASTERS * 5`               | `HEIGHT_FREE Plate` measureSet=true 50 | 250 |
	  |   each caster plate root    | + `Hp`/`Cast` twice each (the refused  |     |
	  |   is REFUSED (the `Cast`    | root's measure pass descends, then its |     |
	  |   box's `width` is          | arrange pass descends again) = 200     |     |
	  |   measure-classed dirt)     |                                        |     |
	  | `+ 2`                       | `KEYED Canvas` + `KEYED S`: the two    |   2 |
	  |                             | ancestors every caster's measure dirt  |     |
	  |                             | closes over                            |     |

	`Row`/`Name`/`Lvl` appear in NO bucket at all, under a caster or a quiet
	plate — they adopt and hit.

	T4 (`14c3459d`) ZEROED THE FIRST TERM AND LEFT THE OTHER TWO STANDING, read off
	the run: the 200 quiet plates translate instead of arranging, so their `SKIP Hp`
	/ `SKIP Cast` touches are gone; the 50 casters still refuse (`translatable` sees
	the dirty `Cast` child) and still cost 5 apiece; `Canvas` and `S` still lose
	their slates. 652 -> 252. ]]
local MEASURED_WITH_CASTS = CASTERS * 5 + 2 -- 252

describe("O2: an arrange-only step does not re-measure MORE THAN ITS PLAN_SKIP LEAVES", function()
	it("a pure tick measures nothing at all (T3's floor, taken to 0 by T4's arm)", function()
		local s = scene.new()
		s.tick(3, 2) -- warm: the first tick after initialRender is COLD, not the steady state
		s.tick(3, 2)
		expect(s.stats().lastMeasured).toBe(MEASURED_TICK)
		s.dispose()
	end)

	--[[ THIS PIN IS ALSO WHAT GUARDS THE PER-SET PREFIX TERMINATION. The closure's
		inner walk terminates on `target[cut]` — the set THIS entry is filling — so an
		`arrange` entry that already filled a prefix chain cannot cut a later `measure`
		entry's. Both ways of collapsing that back to one shared set are caught HERE
		and by nothing else in the suite (the pure-tick pin above sees neither, because
		a pure tick has no measure entry to cut): terminating on `contains[cut]` reads
		650 — `Canvas` and the `Screen` keep slates they should have lost — and
		breaking BEFORE the write reads 500, which loses the caster plate roots too.
		The arrange entries run first, so by the time a caster's `Cast` entry walks up,
		every prefix down to its plate root is already in `contains`. ]]
	it("a caster tick measures the cast bars and their ancestors' slates, and nothing else", function()
		local s = scene.new()
		s.tickWithCasts(3, 2) -- warm
		s.tickWithCasts(3, 2)
		expect(s.stats().lastMeasured).toBe(MEASURED_WITH_CASTS)
		s.dispose()
	end)

	it("...at every device view, including 320x640", function()
		for _, view in device_views.VIEWS do
			local s = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
			s.tick(3, 2)
			s.tick(3, 2)
			expect(`{view.id}:{s.stats().lastMeasured}`).toBe(`{view.id}:{MEASURED_TICK}`)
			s.dispose()
		end
	end)
end)

--[[ THE ORACLE'S ARMS. `a` is the shipped configuration (cross-solve measure
	slates ON, incremental arrange ON — the two things the split changes the
	interaction of), `b` keeps incremental arrange but throws the slates away, and
	`c` forces a FULL solve every refresh and is the ground truth. A split that
	adopted a slate it should not have shows up as `a` disagreeing with `c`; a
	split that broke the arrange skip shows up as `b` disagreeing too. The channel
	compared is `scene.snapshot()` — every live node's rect, hit rect, scroll
	region, visibility and adapter props, sorted — not "did it crash". ]]
local function arms(view: any, opts: any): (any, any, any)
	local base = table.clone(opts or {})
	base.viewport = { x = 0, y = 0, w = view.w, h = view.h }
	local a = table.clone(base) -- slates ON, incremental ON
	local b = table.clone(base)
	b.measureReuse = false -- slates OFF, incremental ON
	local c = table.clone(base)
	c.measureReuse = false
	c.incremental = false -- BOTH OFF: a forced full solve, the ground truth
	return scene.new(a), scene.new(b), scene.new(c)
end

--[[ ORACLE_PLATES, AND WHY IT IS NOT `scene.PLATES` (a measured decision, not a
	shortcut). The oracle is 3 fixtures x 9 views x 3 arms x 17 snapshot
	comparisons; at 250 plates each snapshot walks and sorts 1,503 nodes and the
	whole `describe` takes minutes, which is a suite this repo would stop running.
	The tree SHAPE is what the split's correctness depends on — one anchor, N
	identical plate roots each `vstack{ hstack{ text, text }, box, box }`, one in
	five a caster — and that shape is per-plate identical, so 20 plates exercises
	every branch 250 does: casters and non-casters in the same solve (20 // 5 = 4
	casters), the overflow plate (`p1`) beside plates that fit, the ForEach region,
	the `scaleOffset` resolution. The COUNT pins above run at the full 250, which
	is where a per-plate cost would show up; this half of the file is about rect
	equality, where a bigger N adds repetition and no new state. ]]
local ORACLE_PLATES = 20

describe("O2 oracle: byte-equal to a full solve, every view, every step kind", function()
	local FIXTURES: { any } = {
		{ name = "plain", plates = ORACLE_PLATES },
		{ name = "overflow", plates = ORACLE_PLATES, overflow = true },
		{ name = "fractional", plates = ORACLE_PLATES, fractional = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects, visibility, hit rects and text verdicts survive the split`, function()
			for _, view in device_views.VIEWS do
				local a, b, c = arms(view, fixture)
				local label = `{fixture.name}/{view.id}`
				-- (no `expect(label).toBe(label)` line here: an assertion whose two
				-- sides are the same expression proves nothing — the repo's own
				-- "check that proves nothing" class. The mount check is the
				-- snapshot comparison immediately below.)
				if a.snapshot() ~= c.snapshot() then
					error(`{label}: diverged from a FULL solve at mount`, 0)
				end
				for step = 1, 4 do
					local dx, dy = step * 3, step * 2
					a.tick(dx, dy)
					b.tick(dx, dy)
					c.tick(dx, dy)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: tick {step} diverged from a FULL solve`, 0)
					end
					if a.snapshot() ~= b.snapshot() then
						error(`{label}: tick {step} diverged from the memo-less solve`, 0)
					end
					a.tickWithCasts(dx, dy)
					b.tickWithCasts(dx, dy)
					c.tickWithCasts(dx, dy)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: caster tick {step} diverged from a FULL solve`, 0)
					end
					a.hp(7, 0.1 * step)
					b.hp(7, 0.1 * step)
					c.hp(7, 0.1 * step)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: hp {step} diverged from a FULL solve`, 0)
					end
					--[[ ...AND THE STRUCTURAL ARM, WHICH THE THREE DRIVES ABOVE NEVER
						REACH. `add`/`remove` set the ForEach's list signal, so `refresh`
						takes the `needsStructure` branch, where `measureContains` is not
						built by the closure at all — it is ALIASED to `structuralPlan.contains`,
						the set `structural_scope.widen` then MUTATES with every id
						`layout_node.build` constructed. Aliasing two names to one table
						that a later call grows is exactly the kind of thing that reads
						fine and is wrong, so it gets a rect comparison rather than the
						paragraph in `renderer.luau` arguing it is conservative.

						MEASURED, so "this reaches the structural arm" is a fact and not a
						hope: on this fixture `stats().structuralPartialSolves` goes
						0 -> 1 -> 2 across the `add` and the `remove` and
						`lastStructuralBoundary` is `/S`, where a plain tick leaves both
						at 0 and `nil`. ]]
					-- keyed by `step`, not a constant: `scene.add` mints the key
					-- `add{i}`, and a ForEach treats a duplicate key as a HARD error
					a.add(step)
					b.add(step)
					c.add(step)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: add {step} diverged from a FULL solve`, 0)
					end
					-- ...and the tick right after it, because a structural solve's own
					-- rects are only half the claim: the NEXT incremental solve runs
					-- against a store the widen just pruned
					a.tick(dx, dy)
					b.tick(dx, dy)
					c.tick(dx, dy)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: tick-after-add {step} diverged from a FULL solve`, 0)
					end
					-- ...and `remove` takes an INDEX, so removing the row just added
					-- (the last one) is what returns the list to its previous shape
					local added = #a.items
					a.remove(added)
					b.remove(added)
					c.remove(added)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: remove {step} diverged from a FULL solve`, 0)
					end
				end
				a.dispose()
				b.dispose()
				c.dispose()
			end
		end)
	end
end)

--[[ THE OTHER DIRECTION, AND THE ORACLE ABOVE PROVABLY CANNOT SEE IT. Mutating
	the closure to `measureContains = {}` — an over-aggressive split that never
	refuses a slate — leaves the oracle GREEN on all three fixtures. The reason is
	the nameplates tree, not the oracle's channels: the only measure-classed drives
	it has are the `Hp` and `Cast` widths, both `PLAN_SKIP` boxes that never
	consult a slate, and the plate root above them is `width = px(180)` with a
	content height summing three FIXED child heights — so no measure change in that
	fixture can reach an ancestor's measured size, and a stale slate has nothing to
	be stale about. (The mutation is caught elsewhere in the suite —
	`measure_reuse` 2 cases, `rect_cow` 2, `incremental_layout` 1 — but a
	demonstrator that leans on other files for its own failure mode is a
	demonstrator that stops biting the day those files move.)

	So this is the shape the fixture lacks: a content-sized ancestor over a text
	leaf, with an arrange-only offset on the SAME node, driven in ONE tick. The
	measure half must refuse `Wrap`'s slate (its text moved) while the arrange half
	moves it; a split that refuses neither paints the old width. Three arms, same
	comparison as the oracle. ]]
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local function refusalWorld(measureReuse: boolean, incremental: boolean, view: any): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	local label = core:signal("ab")
	local dx = core:signal(0)
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.Anchor({
				id = "Canvas",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.VStack({
						id = "Wrap",
						anchor = "topLeft",
						offsetX = dx,
						width = { type = "content" },
						height = { type = "content" },
						children = { UI.Text({ id = "T", text = label, textSize = 14 }) },
					}),
				},
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = incremental,
		measureReuse = measureReuse,
		layoutNodeReuse = true,
		commitScope = true,
	})
	controller.initialRender()
	local w: any = { controller = controller }
	function w.drive(text: string, offset: number)
		label:set(text)
		dx:set(offset)
		controller.refresh()
	end
	function w.rects(): string
		local out = {}
		for path, node in adapter.liveNodes() do
			local r = node.rect
			table.insert(out, `{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}`)
		end
		table.sort(out)
		return table.concat(out, "\n")
	end
	function w.dispose()
		controller.dispose()
		root.dispose()
	end
	return w
end

describe("O2: the measure half still REFUSES when the measure really moved", function()
	it("a text change under a content-sized ancestor is not served a stale slate", function()
		for _, view in device_views.VIEWS do
			local a = refusalWorld(true, true, view)
			local b = refusalWorld(false, true, view)
			local c = refusalWorld(false, false, view)
			for step, text in { "abcdefghijklmnop", "x", "abcdefghijklmnopqrstuvwxyz", "ab" } do
				-- BOTH dirt kinds in ONE tick: the text is measure-classed and the
				-- offset is arrange-only, so the closure must build two different sets
				-- for the same refresh
				a.drive(text, step * 4)
				b.drive(text, step * 4)
				c.drive(text, step * 4)
				local label = `{view.id}/step{step}`
				if a.rects() ~= c.rects() then
					error(`{label}: a stale measure slate survived a real text change`, 0)
				end
				if a.rects() ~= b.rects() then
					error(`{label}: diverged from the memo-less solve`, 0)
				end
			end
			a.dispose()
			b.dispose()
			c.dispose()
		end
	end)
end)
