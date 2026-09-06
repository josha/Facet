--!strict
--[[ C3 — A CLEAN, SAME-OFFER ANCHOR CHILD IS NOT PLACED AT ALL.

	The anchor arrange branch already had a MEASURE arm (N2, `tests/anchor_arrange.spec`):
	a child with nothing measure-classed dirty inside it and the identical offer takes
	its w/h from its own previous rect instead of a `measure` call, and is then placed
	and handed to `arrange` — which, if the child is also ARRANGE-clean and lands on the
	rect it already had, returns at its own skip having written nothing.

	THIS ARM REMOVES THE ROUND TRIP. When the anchor's own box did not move, the child
	is `dirtyContains`-clean, the offer pair is identical and the container is unmoved,
	`out[child.id]` ALREADY holds the entry the placement would have reproduced —
	`out` is `reuse.previous.rects`, mutated in place — so the branch does not compute
	the placement, does not call `arrange`, and counts `ctx.anchorSkipped`.

	WHY THAT IS SOUND AND NOT MERELY LIKELY. An anchor child's rect is
	`anchorPlace(innerX, innerY, innerW, innerH, w, h, fillW, fillH, child.anchor,
	child.offsetX, child.offsetY)` and no sibling appears in it. `dirtyContains`-clean
	fixes every `child.*` term. `prev.offerW == innerW and prev.offerH == innerH` fixes
	the two extents — the offer recorded on the entry IS the previous solve's `innerW`.
	`measureContains ⊆ dirtyContains`, the same offer and `containerUnmoved` fix `w, h`.
	The inner ORIGIN is the fourth term and the one the plan's gate did not carry; see
	the padding case below.

	THE GATE IS A STRICT SUPERSET OF `arrangeBody`'S OWN SKIP, which is what makes the
	owed list short (the campaign ledger, "### Task 7 — the owed list", 15 rows). If
	this arm fires, `arrange(ctx, child, …)` would have returned at that skip BEFORE
	the entry write, before `ctx.walkedIds`, before `ctx.arranged`/`rectInserts` and
	before every branch. So the arm is the same skip taken one frame up the stack,
	without computing the placement that proves it — and `lastArranged`,
	`lastRectInserts` and `work.skipped` do not move, which is asserted below.

	AND IT NEEDS NO `measureQuiet` GATE, unlike the N2 arm beside it. That gate exists
	(T9, I1) because the N2 arm's own `arrange` call puts the served subtree into
	`ctx.walkedIds`, where `solve`'s diagnostic replay refuses it — so a measure-time
	finding about the subtree was filed by nobody and replayed for nobody. A SKIPPED
	child is not walked at all, so the replay keeps every finding it had. That is the
	"a finding about a skipped child survives" case below, and it is the one place
	where this arm is strictly safer than the one it sits above.

	THE TWO CHANNELS THE FIRST DRAFT OF THE OWED LIST DID NOT NAME (T7 review, Minor
	2). `measure_facts.luau` lists four channels `measure` writes through, and rows
	3-4 of the ledger's list gave verdicts for two of them. The other two are inert,
	and a list whose whole value is completeness owes the two lines:

	  `ctx.fitCuts`  is only ever read as a DELTA, bracketing the reader's own
	    `measure` call (`candidate.choose`, `composition_resolve`), so a bump this
	    arm does not make on an unrelated sibling cannot change any decision. The N2
	    arm does not publish it either, and for the same reason.
	  `node.mPlan` (Plan D, D1; was `ctx.memoPlans[node]`) is a cache of a PURE
	    function of a built node (`memoPlan`'s `PLAN_*` verdict), for the literal's
	    life. A colder cache is slower, never wrong; any later slow-path call on
	    that node recomputes the same answer. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local solver = require("../src/layout/solver")
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local PLATES = scene.PLATES -- 250
local CASTERS = PLATES // scene.CASTER_EVERY -- 50

--[[ THE INSTRUMENT, the same one `anchor_arrange.spec` uses and for the same reason:
	the solver's `work` block is read by wrapping the module function for the duration
	of one case and putting it back, and the wrapper COUNTS INVOCATIONS so a drive that
	solved zero times reports a zero rather than the previous step's numbers. ]]
local capture = { result = nil :: any, opts = nil :: any, solves = 0 }
local function withWorkCapture(fn: () -> ())
	local real = solver.solve
	solver.solve = function(...)
		local r = real(...)
		capture.solves += 1
		capture.result = r
		capture.opts = (select(3, ...))
		return r
	end
	local ok, err = pcall(fn)
	solver.solve = real
	if not ok then
		capture.result = nil
		capture.opts = nil
		error(err, 0)
	end
end

-- ONE DRIVE AND WHAT IT COST. All three anchor counters, because the claim of this
-- task is a MIGRATION between two of them and a sum that does not move: a "win" that
-- simply stopped visiting children reads as a sum smaller than the child count.
local function drove(fn: () -> ()): string
	local before = capture.solves
	capture.result = nil
	fn()
	local n = capture.solves - before
	if n == 0 or capture.result == nil then
		return `solves={n}`
	end
	local w = capture.result.work
	return `solves={n} skipped={w.anchorSkipped} reused={w.anchorReused} offered={w.anchorOffered}`
end

local function lastSolveWasIncremental(): string
	local opts = capture.opts
	return `reuse={tostring(opts ~= nil and (opts :: any).reuse ~= nil)}`
end

local function resize(w: any, width: number, height: number)
	w.env:set("viewportRect", { x = 0, y = 0, w = width, h = height })
	w.controller.refresh()
end

--[[ READ OFF THE RUN at `e7d48f47` + this arm, warm-up discarded, every pin carrying
	`solves=N`.

	`SKIPPED_CAST` — a caster tick moves all 250 plates and advances the Cast bar of
	the deterministic one-in-five subset. On the SHIPPED mount every plate root is a
	coordinate-space host, so the 200 whose only dirt is placement are taken by
	`render/translate_lane` and never reach the solver's dirty set at all; the 50 with
	a MEASURE write on their Cast bar are handed back as the remainder. So the anchor
	sees 200 clean children and 50 dirty ones, and the 200 are exactly this arm's
	subject. Before this task all 200 read `reused`. ]]
local SKIPPED_CAST = PLATES - CASTERS -- 200
local SKIPPED_HP = PLATES - 1 -- 249: every plate but the one whose Hp width changed

describe("C3: a clean, same-offer anchor child is not placed at all", function()
	it("a caster tick SKIPS the 200 clean plates and offers only the 50 that resized", function()
		--[[ THE HEADLINE, and a number that is neither 0 nor 250. An arm that had
			collapsed to "always skip" reads 250/0/0 here and fails on the very frame
			where 50 plates really did resize. ]]
		withWorkCapture(function()
			local s = scene.new()
			s.tickWithCasts(3, 2)
			s.tickWithCasts(3, 2)
			expect(drove(function()
				s.tickWithCasts(3, 2)
			end)).toBe(`solves=1 skipped={SKIPPED_CAST} reused=0 offered={CASTERS}`)
			local w = capture.result.work
			-- the three halves account for every child of the one anchor this fixture has
			expect(w.anchorSkipped + w.anchorReused + w.anchorOffered).toBe(PLATES)
			s.dispose()
		end)
	end)

	it("...and the walk did NOT grow: arranged, rect inserts and the skip count stand still", function()
		--[[ THE INVARIANT HALF. This arm removes an `arrange` call that already
			returned at its own skip, so nothing it touches can move — and if any of
			these three DID move, the arm would be skipping a child the solver was
			really doing work for. Read off the run at the base commit and asserted
			against the same drive with the arm live. ]]
		local s = scene.new()
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2)
		local st = s.stats()
		expect(
			`arranged={st.lastArranged} inserts={st.lastRectInserts} skipped={st.lastSolveSkipped} layout={st.lastLayoutNodes}`
		).toBe(`arranged=102 inserts=102 skipped=1400 layout=1502`)
		expect(st.lastArranged + st.lastTranslated + st.lastSolveSkipped).toBe(st.lastLayoutNodes)
		s.dispose()
	end)

	it("an hp step skips 249 siblings and offers exactly the plate that changed", function()
		withWorkCapture(function()
			local s = scene.new()
			s.tick(3, 2)
			expect(drove(function()
				s.hp(7, 0.9)
			end)).toBe(`solves=1 skipped={SKIPPED_HP} reused=0 offered=1`)
			expect(lastSolveWasIncremental()).toBe("reuse=true")
			s.dispose()
		end)
	end)

	it("...at every device view", function()
		withWorkCapture(function()
			for _, view in device_views.VIEWS do
				local s = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
				s.tick(3, 2)
				expect(`{view.id}:{drove(function()
					s.hp(7, 0.9)
				end)}`).toBe(`{view.id}:solves=1 skipped={SKIPPED_HP} reused=0 offered=1`)
				s.dispose()
			end
		end)
	end)

	it("A VIEWPORT CHANGE IS A FULL SOLVE, so nothing is skipped", function()
		--[[ `viewportRect` is a GEOMETRY key: the renderer's geometry memo defers to
			`core:settle`, which solves from OUTSIDE `refresh` where the controller-level
			dirty closure is still nil, so `solveOpts.reuse` is never set. With no reuse
			table there is no previous-rect map to consult and the arm is structurally
			unreachable rather than declining — `reuse=false` is what separates those two,
			and the counters alone cannot say which happened. ]]
		withWorkCapture(function()
			local s = scene.new({ viewport = { x = 0, y = 0, w = 1280, h = 720 } })
			s.tick(3, 2)
			expect(drove(function()
				resize(s, 1000, 700)
			end)).toBe(`solves=1 skipped=0 reused=0 offered={PLATES}`)
			expect(lastSolveWasIncremental()).toBe("reuse=false")
			-- ...and the very next step at the settled viewport arms again, so the full
			-- solve is the geometry fact's and not a latch
			expect(drove(function()
				s.hp(7, 0.4)
			end)).toBe(`solves=1 skipped={SKIPPED_HP} reused=0 offered=1`)
			s.dispose()
		end)
	end)

	it("...and the geometry a skipping solve produces is byte-equal to a full one, at EVERY view", function()
		--[[ THE COUNTERS SAY THE ARM FIRED; THIS SAYS THE ANSWER IS RIGHT. `b` re-solves
			in full on every refresh and is the ground truth; `scene.snapshot()` is every
			live node's stored rect, hit rect, scroll region, visibility, adapter props and
			both public readers, so a child left at a stale x shows up as a diff.

			SWEPT ACROSS `device_views.VIEWS` since fix round 1 (T7 review, Minor 1), to
			match what the N2 sibling next door already does: a single viewport is one
			geometry, and the campaign's constraint on a differential is the whole matrix
			including 320x640. The compare is per STEP rather than only at the end, so the
			failure names the drive that produced it. ]]
		for _, view in device_views.VIEWS do
			local a = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
			local b = scene.new({
				viewport = { x = 0, y = 0, w = view.w, h = view.h },
				incremental = false,
				measureReuse = false,
			})
			local function step(what: string, drive: (any) -> ())
				drive(a)
				drive(b)
				if a.snapshot() ~= b.snapshot() then
					error(`{view.id}: snapshot diverged after {what}`, 0)
				end
			end
			step("warm", function(s)
				s.tickWithCasts(3, 2)
			end)
			step("caster tick", function(s)
				s.tickWithCasts(3, 2)
			end)
			step("hp", function(s)
				s.hp(7, 0.9)
			end)
			step("add", function(s)
				s.add(9001)
			end)
			step("remove", function(s)
				s.remove(1)
			end)
			step("caster tick again", function(s)
				s.tickWithCasts(1, 1)
			end)
			expect(`{view.id}:{a.snapshot() == b.snapshot()}`).toBe(`{view.id}:true`)
			a.dispose()
			b.dispose()
		end
	end)
end)

--[[ THE INNER ORIGIN — the fourth term of the placement, and the one the plan's gate
	did not carry.

	`innerX = rect.x + paddingLeft`. `boxUnchanged` fixes `rect.x`; NOTHING in the
	brief's gate fixed `paddingLeft`. `padding` is MEASURE-classed, so a padding write
	on the anchor puts the anchor and its ancestors in the dirt sets and leaves every
	child out of both — and a REDISTRIBUTION that keeps the total (`{left=0,right=20}`
	→ `{left=20,right=0}`) leaves the anchor's rect AND `innerW` identical while moving
	`innerX` by 20 px. Every child would have kept a stale x behind a green suite,
	because the offer comparison the arm inherits is an EXTENT comparison and cannot
	see an origin.

	The anchor's own entry now carries `innerDX`/`innerDY` — the two insets, written
	for `kind == "anchor"` alone — and the arm compares them. Deleting that comparison
	makes the counter row below read `skipped=12` and the differential row diverge. ]]
local NESTED_KIDS = 12

local function paddedAnchorWorld(incremental: boolean, view: any): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	local pad = core:signal({ top = 0, right = 20, bottom = 0, left = 0 } :: any)
	local nudge = core:signal(0)
	--[[ THE OTHER TWO LEVERS, and why the anchor is no longer the root's only child.
		`spacer` moves the anchor's BOX without touching its size; `ov` is an `overflow`
		write, MEASURE-classed dirt on the anchor itself, which is what keeps the moved
		box out of the translate arm (`selfPlaces` refuses a measure-dirty node) and
		therefore reaches the anchor branch at all. Driven together they are the only
		shape in the suite where an anchor's ORIGIN moves under clean children, which is
		the case `boxUnchanged` is the only refusal for. ]]
	local spacer = core:signal({ type = "fixed", px = 10 } :: any)
	local ov = core:signal("visible")
	local kids = {}
	for i = 1, NESTED_KIDS do
		if i % 3 == 0 then
			-- a third are WRAPPING text, so a child served a stale box would keep the
			-- height of a wrap it is not going to get — a wrong box, not a slow one
			table.insert(
				kids,
				UI.Text({
					id = `T{i}`,
					text = "a wrapping label whose measured height depends on the width it is offered, repeatedly",
					anchor = "topLeft",
					offsetX = if i == 3 then nudge else 0,
					offsetY = i * 3,
				})
			)
		else
			table.insert(
				kids,
				UI.Box({
					id = `B{i}`,
					width = { type = "fixed", px = 40 },
					height = { type = "fixed", px = 20 },
					anchor = "topLeft",
					offsetY = i * 3,
				})
			)
		end
	end
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Col",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Box({ id = "Sp", width = { type = "fixed", px = 10 }, height = spacer }),
						UI.Anchor({
							id = "A",
							width = { type = "fill", weight = 1 },
							-- FIXED, so the spacer above moves this box without resizing it
							height = { type = "fixed", px = 400 },
							-- the lever: the anchor's OWN padding, redistributed left/right
							padding = pad,
							overflow = ov,
							children = kids,
						}),
					},
				}),
			},
		})
	)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = incremental,
		measureReuse = incremental,
		layoutNodeReuse = true,
		commitScope = true,
	})
	controller.initialRender()
	return {
		controller = controller,
		redistribute = function(left: number, right: number)
			pad:set({ top = 0, right = right, bottom = 0, left = left } :: any)
			controller.refresh()
		end,
		-- MOVE the anchor's box without resizing it, and dirty it in a way the
		-- translate arm refuses, so the anchor branch really runs
		move = function(px: number, overflow: string)
			spacer:set({ type = "fixed", px = px } :: any)
			ov:set(overflow)
			controller.refresh()
		end,
		-- ...and the SAME move with the anchor left CLEAN, which is the drive the
		-- translate arm takes: `Sp` is a sibling, so the closure marks it and its
		-- ancestors and never reaches into the anchor
		moveClean = function(px: number)
			spacer:set({ type = "fixed", px = px } :: any)
			controller.refresh()
		end,
		nudge = function(v: number)
			nudge:set(v)
			controller.refresh()
		end,
		dump = function(): string
			local out = {}
			for path, node in adapter.liveNodes() do
				local r = node.rect
				table.insert(out, `{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|vis={tostring(node.visible)}`)
			end
			table.sort(out)
			return table.concat(out, "\n")
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

--[[ THE PADDED FIXTURE'S DIFFERENTIAL, ONE VIEW, lifted into a function so the sweep
	above reads as a sweep. `b` re-solves in full on every refresh and is the ground
	truth; the compare is per STEP so a failure names the drive that produced it. ]]
local function runPaddedOracle(view: any)
	local a = paddedAnchorWorld(true, view)
	local b = paddedAnchorWorld(false, view)
	local function step(what: string, drive: (any) -> ())
		drive(a)
		drive(b)
		if a.dump() ~= b.dump() then
			error(`{view.id}: {what}\nINCREMENTAL:\n{a.dump()}\nFULL:\n{b.dump()}`, 0)
		end
	end
	step("nudge", function(w)
		w.nudge(1)
	end)
	step("nudge again", function(w)
		w.nudge(2)
	end)
	-- THE ROW THAT FAILS WITHOUT THE GUARD: the incremental arm keeps every child
	-- 20px to the left of where the full solve puts it
	step("redistribute", function(w)
		w.redistribute(20, 0)
	end)
	step("nudge after", function(w)
		w.nudge(3)
	end)
	step("redistribute back", function(w)
		w.redistribute(0, 20)
	end)
	-- THE ROW THAT FAILS WITHOUT THE OFFER PAIR: the extent moves, so a served
	-- wrapping label keeps the height of a wrap it is not going to get
	step("right edge", function(w)
		w.redistribute(0, 40)
	end)
	-- ...AND THE ROW THAT FAILS WITHOUT `boxUnchanged`: the anchor's origin moves
	-- and every child would keep the y it had
	step("move the box", function(w)
		w.move(60, "hidden")
	end)
	step("move it back", function(w)
		w.move(10, "visible")
	end)
	-- ...and the CLEAN move, which is the translate arm's drive: the carry that
	-- keeps the arm armed across it must not change a pixel either
	step("clean move", function(w)
		w.moveClean(80)
	end)
	step("nudge after a clean move", function(w)
		w.nudge(9)
	end)
	step("clean move back", function(w)
		w.moveClean(10)
	end)
	expect(`{view.id}:{a.dump() == b.dump()}`).toBe(`{view.id}:true`)
	a.dispose()
	b.dispose()
end

describe("C3: the guards", function()
	it("A PADDING REDISTRIBUTION moves the inner box while the rect stands still", function()
		withWorkCapture(function()
			local w = paddedAnchorWorld(true, { w = 800, h = 600 })
			-- warm: `initialRender` is not a reuse solve
			w.nudge(1)
			--[[ THE CONTROL. Arrange-classed dirt on ONE child, inner box untouched: the
				other eleven are skipped and the nudged one is placed. Without it the row
				below could be green because the arm never fires on this fixture at all. ]]
			expect(drove(function()
				w.nudge(2)
			end)).toBe(`solves=1 skipped={NESTED_KIDS - 1} reused=1 offered=0`)
			expect(lastSolveWasIncremental()).toBe("reuse=true")
			--[[ THE CASE THE GUARD EXISTS FOR. The anchor's rect and `innerW` are both
				unchanged — only the split moved — so every gate the plan's own table named
				passes and `innerDX` is the only one that refuses.

				AND WHAT THE TWELVE FALL THROUGH TO IS THE N2 ARM, NOT `measure`, which is
				the right answer and worth saying: their SIZES really did not change (the
				offer is identical), so `reused=12` serves those, and the placement each one
				needed is recomputed against the moved `innerX`. `offered` stays 0. The
				skip and the serve are different questions and this row is where they
				visibly separate. ]]
			expect(drove(function()
				w.redistribute(20, 0)
			end)).toBe(`solves=1 skipped=0 reused={NESTED_KIDS} offered=0`)
			expect(lastSolveWasIncremental()).toBe("reuse=true")
			-- ...and it re-arms at the settled padding, so the fall-through is the
			-- origin's and not a latch
			expect(drove(function()
				w.nudge(3)
			end)).toBe(`solves=1 skipped={NESTED_KIDS - 1} reused=1 offered=0`)
			w.dispose()
		end)
	end)

	it("A RIGHT-EDGE padding write moves the EXTENT, and the offer comparison is what refuses", function()
		--[[ THE SAME FIXTURE, THE OTHER HALF OF `padding`. `redistribute(0, 40)` from
			`(0, 20)` leaves the anchor's rect AND its `innerDX` untouched and shrinks
			`innerW` by 20 — so this is the one drive where `held.offerW == innerW` is
			the only term that refuses, and deleting the offer pair from the gate reads
			`skipped=12 reused=0`. It also falls through to `measure` rather than to the
			N2 serve, which the previous case does not: a child whose OFFER moved may
			genuinely have a different size, and a third of these are wrapping labels
			whose height is a function of the width they are given. ]]
		withWorkCapture(function()
			local w = paddedAnchorWorld(true, { w = 800, h = 600 })
			w.nudge(1)
			expect(drove(function()
				w.redistribute(0, 40)
			end)).toBe(`solves=1 skipped=0 reused=0 offered={NESTED_KIDS}`)
			expect(lastSolveWasIncremental()).toBe("reuse=true")
			--[[ ...AND IT DOES NOT RE-ARM, WHICH IS A PRE-EXISTING PROPERTY OF THE ENTRY
				CHANNEL AND IS RECORDED RATHER THAN ASSERTED AWAY (found by this case,
				2026-09-04). `offerW` is written only when a child's ENTRY LITERAL is
				rebuilt, and a `topLeft` child whose offer shrank from the RIGHT lands on
				exactly the rect it had — so `arrange` takes its own skip, the entry is
				never rewritten, and the offer it carries stays the pre-padding one for
				the life of the surface. Both anchor arms are then permanently disarmed
				for that child: every later frame re-measures it.

				IT IS CONSERVATIVE, NOT WRONG — a stale offer can only REFUSE an arm, and
				the refusal path re-measures — so it is a cache that stops firing, not a
				stale rect. It belongs to the N2 arm's `ctx.offers` channel, which
				predates this task, and is booked in the campaign ledger rather than
				fixed here. `nudge` moves ONE child, and that one child's entry IS
				rebuilt, which is why the third solve reads `reused=1`. ]]
			expect(drove(function()
				w.nudge(2)
			end)).toBe(`solves=1 skipped=0 reused=0 offered={NESTED_KIDS}`)
			expect(drove(function()
				w.nudge(3)
			end)).toBe(`solves=1 skipped=0 reused=1 offered={NESTED_KIDS - 1}`)
			w.dispose()
		end)
	end)

	it("THE ANCHOR'S OWN BOX MOVES, and `boxUnchanged` is the only term that refuses", function()
		--[[ THE HARDEST CASE TO REACH, AND THE ONE WITH THE WORST FAILURE. An anchor
			whose ORIGIN moved must re-place every child — its children's rects are
			absolute, not relative to it — and nothing else in the gate can see that: the
			offer pair is an EXTENT comparison, `innerDX` is an INSET, and both are
			unchanged by a pure move.

			GETTING THERE TAKES TWO WRITES, and that is the fact this case exists to
			record. A clean anchor that only moved is taken by the TRANSLATE ARM and
			never reaches its own branch; a dirty one reaches it only if the arm refuses,
			and the arm refuses a node that is MEASURE-dirty (`selfPlaces`). So the drive
			moves the spacer above the anchor (the box) and writes the anchor's own
			`overflow` (measure-classed dirt that changes no geometry at all) in the same
			refresh. Deleting `boxUnchanged` from `skipHeld` reads `skipped=12 reused=0`
			here and every child stays at the y it had — which the differential below is
			what proves. ]]
		withWorkCapture(function()
			local w = paddedAnchorWorld(true, { w = 800, h = 600 })
			w.nudge(1)
			expect(drove(function()
				w.move(60, "hidden")
			end)).toBe(`solves=1 skipped=0 reused={NESTED_KIDS} offered=0`)
			expect(lastSolveWasIncremental()).toBe("reuse=true")
			-- ...and it re-arms once the box settles
			expect(drove(function()
				w.nudge(2)
			end)).toBe(`solves=1 skipped={NESTED_KIDS - 1} reused=1 offered=0`)
			w.dispose()
		end)
	end)

	it("A TRANSLATED ANCHOR STAYS ARMED: the frame after a move skips like any other", function()
		--[[ THE ENTRY A TRANSLATE ROOT PUBLISHES IS THE LITERAL AND NOTHING ELSE
			(`literalIsWholeEntry`, `solver.luau`) — it returns above the padding block, so
			the `innerDX`/`innerDY` this arm reads would be absent on a node that MOVED,
			and every child of it would fall through for one whole frame after the anchor
			settled. Found by the T7 review; the anchor of the campaign's own 250-plate
			fixture never moves, so nothing in the suite or on the arena could see it.

			THE DRIVE IS A CLEAN MOVE. `Sp` is the anchor's SIBLING, so the dirty closure
			marks it and its ancestors and never reaches into the anchor — the anchor is
			clean, its rect moved, and it takes the translate arm (`moveOnly`, and its
			twelve children re-based rather than walked). The frame after that is an
			ordinary nudge, and it is the one that used to read `skipped=0`.

			CARRYING THE TWO NUMBERS ACROSS THE ROOT IS EXACT, not optimistic:
			`translatable` fires only for a node that is `clean` or `selfPlaces`, and
			`selfPlaces` requires `measureContains[node.id] ~= true` — `padding` is
			MEASURE-classed, so the insets cannot have changed on a node that got here. ]]
		withWorkCapture(function()
			local w = paddedAnchorWorld(true, { w = 800, h = 600 })
			w.nudge(1)
			-- ARMED before the move, so the row below is a loss and not a cold start
			expect(drove(function()
				w.nudge(2)
			end)).toBe(`solves=1 skipped={NESTED_KIDS - 1} reused=1 offered=0`)
			--[[ THE MOVE ITSELF. The anchor is clean and only its origin changed, so its
				body never runs: no child is placed, offered or skipped, and its whole
				subtree is re-based by the translate arm instead. ]]
			expect(drove(function()
				w.moveClean(60)
			end)).toBe("solves=1 skipped=0 reused=0 offered=0")
			-- THE FRAME THE REVIEW FOUND: `skipped=0 reused=12` without the carry
			expect(drove(function()
				w.nudge(3)
			end)).toBe(`solves=1 skipped={NESTED_KIDS - 1} reused=1 offered=0`)
			-- ...and a move BACK, so the carry is not a one-direction accident
			expect(drove(function()
				w.moveClean(10)
			end)).toBe("solves=1 skipped=0 reused=0 offered=0")
			expect(drove(function()
				w.nudge(4)
			end)).toBe(`solves=1 skipped={NESTED_KIDS - 1} reused=1 offered=0`)
			w.dispose()
		end)
	end)

	it("...and the geometry it produces is byte-equal to a forced FULL solve, at EVERY view", function()
		--[[ SWEPT ACROSS `device_views.VIEWS` since fix round 1 (T7 review, Minor 1).
			The three shapes this fixture owns — a padding REDISTRIBUTION, a right-edge
			EXTENT move and a moved BOX — exist nowhere else in the suite, so a single
			800x600 reading was the only ground truth they had. A third of the children
			are wrapping labels whose measured height is a function of the width they are
			offered, which is what makes a narrow view a different question rather than a
			smaller one. ]]
		for _, view in device_views.VIEWS do
			runPaddedOracle(view)
		end
	end)
end)

--[[ THE TWO PROPERTIES THE COUNTERS CANNOT SEE, driven on a small hand-built world:
	what a skipped child's ENTRY is (the same table), and what happens to a finding
	filed about it. Both are why the owed list is thirteen rows and not thirty. ]]
local function findingWorld(): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local nudge = core:signal(0)
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "A",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						-- THE FINDING: a container whose padding empties its own content box
						-- (`arrange_reports.box`'s zero-content-box report), filed about
						-- ITSELF while it is walked, and about nobody once it is skipped
						UI.VStack({
							id = "Squeezed",
							width = { type = "fixed", px = 20 },
							height = { type = "fixed", px = 20 },
							padding = 30,
							anchor = "topLeft",
							children = { UI.Box({ id = "Inner", width = { type = "fixed", px = 4 } }) },
						}),
						-- ...and an ordinary neighbour carrying the reactive placement prop, so
						-- a drive can make the anchor arrange without touching `Squeezed`
						UI.Box({
							id = "Mover",
							width = { type = "fixed", px = 30 },
							height = { type = "fixed", px = 30 },
							anchor = "topLeft",
							offsetX = nudge,
						}),
					},
				}),
			},
		})
	)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = true,
	})
	controller.initialRender()
	return {
		controller = controller,
		nudge = function(v: number)
			nudge:set(v)
			controller.refresh()
		end,
		findings = function(): string
			local out = {}
			for _, d in controller.diagnostics() do
				table.insert(out, d.node)
			end
			table.sort(out)
			return table.concat(out, ",")
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

--[[ READ OFF THE RUN: `arrange_reports.box` files TWO messages about `Squeezed` (the
	zero content box, and the chrome/placement report beside it), both naming the same
	node. The pin is the whole list rather than a count, so a finding that went missing
	AND one that duplicated both read as a diff. ]]
local SQUEEZED_FINDINGS = "/S/A/Squeezed,/S/A/Squeezed"

--[[ THE ONE CHILD `arrange` WOULD NOT HAVE SKIPPED, and therefore the one this arm
	refuses by name. A coordinate-space host that HOLDS a composition has its own skip
	suspended by the `arrange` wrapper (`ctx.noSkipDepth`, T3's finding: a host's move
	re-bases nothing below it, so a composition under one must re-resolve against its
	window origin). This arm fires only where the host did NOT move, so skipping it is
	arguably sound — but the superset claim in this file's header is worth more than
	one child a frame, and one field read on hosts alone keeps it true by construction
	rather than by argument. Shape borrowed from `tests/translate_host.spec.luau`'s
	"a Composition inside a moved host". ]]
local function compositionHostWorld(): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	local nudge = core:signal(0)
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "A",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						-- the host that holds a composition: a REACTIVE placement prop on a
						-- container is the coordinate-space trigger
						UI.ZStack({
							id = "Wrap",
							anchor = "topLeft",
							offsetX = core:signal(0),
							offsetY = core:signal(0),
							width = { type = "fixed", px = 400 },
							height = { type = "fixed", px = 300 },
							children = {
								UI.Composition({
									id = "Comp",
									arrangements = { "column" },
									laneGap = 12,
									groupGap = 8,
									width = { type = "fixed", px = 400 },
									height = { type = "fixed", px = 300 },
									groups = { { id = "main", lane = "main", sizing = "fill", minWidth = 120 } },
									children = {
										UI.Region({
											id = "R1",
											group = "main",
											rank = 1,
											children = {
												UI.Box({
													id = "r1a",
													width = { type = "fixed", px = 100 },
													height = { type = "fixed", px = 40 },
												}),
											},
										}),
									},
								}),
							},
						}),
						-- ...and an ordinary sibling, which IS skipped on the same frame
						UI.Box({
							id = "Plain",
							width = { type = "fixed", px = 30 },
							height = { type = "fixed", px = 30 },
							anchor = "bottomRight",
						}),
						-- the lever: one child with a reactive placement prop, so the anchor
						-- arranges without either of the two above being dirty
						UI.Box({
							id = "Mover",
							width = { type = "fixed", px = 30 },
							height = { type = "fixed", px = 30 },
							anchor = "topLeft",
							offsetX = nudge,
						}),
					},
				}),
			},
		})
	)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = true,
	})
	controller.initialRender()
	return {
		controller = controller,
		isHost = function(): string
			return `host={tostring(adapter.isHost("/S/A/Wrap"))}`
		end,
		nudge = function(v: number)
			nudge:set(v)
			controller.refresh()
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

describe("C3: a skipped child keeps what nobody re-published for it", function()
	it("a `hostSpace` child that HOLDS a composition is never skipped", function()
		withWorkCapture(function()
			local w = compositionHostWorld()
			-- the fixture is only a test of the gate while the host really IS one
			expect(w.isHost()).toBe("host=true")
			w.nudge(1)
			--[[ THREE children, all clean but `Mover`. `Plain` is SKIPPED; `Wrap` is
				refused BY NAME and falls back to the N2 serve, which places it; `Mover`
				really moved and is served its size and placed. So `reused` counts two and
				`skipped` counts one, and deleting the `hostSpace`/`spaceCompositions`
				term reads `skipped=2 reused=1` — measured, not predicted. ]]
			expect(drove(function()
				w.nudge(2)
			end)).toBe("solves=1 skipped=1 reused=2 offered=0")
			expect(drove(function()
				w.nudge(3)
			end)).toBe("solves=1 skipped=1 reused=2 offered=0")
			w.dispose()
		end)
	end)

	it("a finding about a skipped child survives the solve that skipped it", function()
		--[[ AND THIS IS WHY THE ARM NEEDS NO `measureQuiet` GATE. A skipped child never
			reaches `ctx.walkedIds` — `arrangeBody`'s own skip also returns above that
			write — so `solve`'s replay, which refuses only what THIS solve walked, copies
			every finding about the subtree forward. The N2 arm beside it cannot do that:
			its `arrange` call puts the served subtree into `walkedIds`, which is the
			whole reason that arm is gated on a quiet predecessor. ]]
		withWorkCapture(function()
			local w = findingWorld()
			w.nudge(1)
			expect(w.findings()).toBe(SQUEEZED_FINDINGS)
			expect(drove(function()
				w.nudge(2)
			end)).toBe("solves=1 skipped=1 reused=1 offered=0")
			expect(w.findings()).toBe(SQUEEZED_FINDINGS)
			expect(drove(function()
				w.nudge(3)
			end)).toBe("solves=1 skipped=1 reused=1 offered=0")
			expect(w.findings()).toBe(SQUEEZED_FINDINGS)
			w.dispose()
		end)
	end)

	it("the skipped child's entry is the SAME TABLE — nothing rebuilt it", function()
		--[[ THE PROPERTY THAT MAKES ROWS 3 AND 5 OF THE OWED LIST TRUE. `out` IS
			`reuse.previous.rects`, mutated in place, so "the entry already holds the right
			values" is an identity claim and is asserted as one. It is also what makes the
			republished channels (`ctx.offers`, the three verdicts) INERT under this arm:
			the only in-solve reader of `ctx.offers` is the entry literal, and no entry
			literal runs for a skipped child.

			AND THE SKIP IS ASSERTED WITH IT, which is the correction fix round 1 made
			(T7 review, Minor 3). Identity ALONE cannot fail on this arm: at the base
			commit the same child goes N2-serve -> `arrange` -> `arrangeBody`'s own skip,
			which also returns above the entry write, so `rawequal` is true with or
			without C3 and the case read the same on a commit where the arm did not
			exist. The counter is what makes the two tables the SKIPPED child's rather
			than merely the same child's — `skipped=1` on both captured solves, from the
			same drive, and the mutation that deletes the arm now reddens this case with
			the others. ]]
		local entryOf: { [string]: any } = {}
		local skips: { number } = {}
		local real = solver.solve
		local w
		local ok, err = pcall(function()
			w = findingWorld()
			w.nudge(1)
			solver.solve = function(...)
				local r = real(...)
				entryOf[if entryOf.first == nil then "first" else "second"] = r.rects["/S/A/Squeezed"]
				table.insert(skips, r.work.anchorSkipped)
				return r
			end
			w.nudge(2)
			w.nudge(3)
		end)
		solver.solve = real
		if not ok then
			error(err, 0)
		end
		expect(
			`same={tostring(rawequal(entryOf.first, entryOf.second))} rect={tostring(
				rawequal(entryOf.first.rect, entryOf.second.rect)
			)} skipped={table.concat(skips, ",")}`
		).toBe("same=true rect=true skipped=1,1")
		w.dispose()
	end)
end)
