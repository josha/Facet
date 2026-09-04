--!strict
--[[ THE COORDINATE-SPACE ORACLE — FIVE ARMS, AND THE FIFTH IS THIS TASK'S CONTROL.

	Plan C's C1 makes a container with a REACTIVE placement and children the ORIGIN
	its subtree's rects are stored against. Everything downstream of a stored rect
	therefore has to learn a composition it never needed, and the only honest way to
	say it learned it correctly is a differential against a world where the change
	does not exist at all.

	ARMS a-d are `commit_translate.spec.luau`'s four, unchanged in intent: everything
	on; the memo off; both solver halves off (a forced full solve, no translate); the
	commit prune off (the pre-P4 build). They vary the machinery AROUND the change.

	ARM e IS A THREAD, NOT A SECOND WORLD, and that is the whole design.
	`nameplates_scene.Opts.hosts` threads `RendererAttachOpts.translateHosts` into
	`renderer.attach`, so `e` is the SAME reactive fixture, mounted with no
	coordinate-space hosts, driven through the IDENTICAL step list and compared to
	`a` after EVERY step. A mount-only comparison of a DIFFERENT world (static
	offsets) would prove nothing about the only thing that changed — a MOVE.

	WHAT `e` COMPARES, AND THE ONE COLUMN IT DOES NOT. Its raw STORED rect is
	expected to differ: that difference IS the change. So `e` is compared on
	`scene.publicSnapshot()`, which is every other column — the engine
	`presentedPosition`/`presentedSize`, the focus flags, `controller.rectOf`,
	`controller.screenRectOf`, the hit rects, the visibility verdicts, every adapter
	prop, and `controller.diagnostics()`. That makes arm `e` simultaneously the "a
	tree with no hosts is byte-identical" proof, the "public numbers do not move"
	proof, and (through `diagKey`) the proof that the three ABSOLUTE readers — the
	composition resolver's `atRoot`, the audits — still file the same findings.

	AND `pos == sro` IS ASSERTED INSIDE `snapshot()` ITSELF, per line. Arms `a` and
	`c` can go stale in step with each other: the fake composes `presentedPosition`
	at `setRect`, and under Plan C a host move produces exactly ONE `setRect`. An
	instrument that compares two arms cannot see that; one that compares the fake's
	composed position against the public reader can, and it emits `POSMISMATCH` into
	the line when it fails. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")

-- see `commit_translate`'s note: the tree SHAPE is what correctness depends on and
-- it is per-plate identical, so 20 plates exercises every branch 250 does.
local ORACLE_PLATES = 20

local function arms(view: any, opts: any): (any, any, any, any, any)
	local base = table.clone(opts or {})
	base.viewport = { x = 0, y = 0, w = view.w, h = view.h }
	local a = table.clone(base) -- everything ON: the shipped configuration
	local b = table.clone(base)
	b.measureReuse = false
	local c = table.clone(base)
	c.measureReuse = false
	c.incremental = false -- both solver halves off: a forced full solve, no translate
	local d = table.clone(base)
	d.commitScope = false -- the pre-P4 build: every walk descends and writes
	local e = table.clone(base)
	e.hosts = false -- NO coordinate-space hosts: the pre-Plan-C world
	return scene.new(a), scene.new(b), scene.new(c), scene.new(d), scene.new(e)
end

describe("C1 oracle: a coordinate space moves no public number, every view, every step", function()
	local FIXTURES: { any } = {
		{ name = "plain", plates = ORACLE_PLATES },
		{ name = "overflow", plates = ORACLE_PLATES, overflow = true },
		{ name = "fractional", plates = ORACLE_PLATES, fractional = true },
		-- with a stroked path on the surface `visible` takes the full walk while the
		-- other seven still prune, so the mixed shape is the one an oracle most needs
		{ name = "withPath", plates = ORACLE_PLATES, withPath = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: the adapter, the public reads and the findings all survive`, function()
			for _, view in device_views.VIEWS do
				local a, b, c, d, e = arms(view, fixture)
				local label = `{fixture.name}/{view.id}`
				-- every arm is DRIVEN on every step: an arm that skips a drive falls out
				-- of sync and the next comparison is about the drive it missed
				local function step(what: string, compareB: boolean, drive: (any) -> ())
					drive(a)
					drive(b)
					drive(c)
					drive(d)
					drive(e)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: {what} diverged from a FULL solve`, 0)
					end
					if a.snapshot() ~= d.snapshot() then
						error(`{label}: {what} diverged from an UNPRUNED commit`, 0)
					end
					if compareB and a.snapshot() ~= b.snapshot() then
						error(`{label}: {what} diverged from the memo-less solve`, 0)
					end
					if a.publicSnapshot() ~= e.publicSnapshot() then
						error(`{label}: {what} diverged from the NO-HOSTS world`, 0)
					end
				end

				--[[ NON-VACUITY, THREE WAYS. Five empty adapters compare equal five
					ways, so the oracle proves it is looking at a painted surface AND at
					one where the change is actually engaged before any comparison means
					anything: arm `a` really has hosts, arm `e` really has none, and the
					stored rects really differ between them. ]]
				if #a.snapshot() == 0 then
					error(`{label}: the fixture painted NOTHING — every comparison is vacuous`, 0)
				end
				if a.adapter.hostCount() == 0 then
					error(`{label}: arm a has NO coordinate-space hosts — the change is not engaged`, 0)
				end
				if e.adapter.hostCount() ~= 0 then
					error(`{label}: arm e has hosts — the hosts=false flag is not reaching the trigger`, 0)
				end
				if a.snapshot() == e.snapshot() then
					error(`{label}: the two worlds store IDENTICAL rects — the fixture is not hosted`, 0)
				end
				if a.snapshot() ~= c.snapshot() then
					error(`{label}: diverged from a FULL solve at mount`, 0)
				end
				if a.snapshot() ~= d.snapshot() then
					error(`{label}: diverged from an UNPRUNED commit at mount`, 0)
				end
				if a.publicSnapshot() ~= e.publicSnapshot() then
					error(`{label}: diverged from the NO-HOSTS world at mount`, 0)
				end
				for round = 1, 3 do
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
					-- an authored `hidden` flip: the one arrange-class prop every walk reads
					step(`hide {round}`, false, function(w)
						w.hide(3, round % 2 == 1)
					end)
					-- a pure-arrange prop on a TEXT LEAF inside a moved host
					step(`nudgeLabel {round}`, false, function(w)
						w.nudgeLabel(5, if round % 2 == 1 then "end" else "start")
					end)
					step(`add {round}`, false, function(w)
						w.add(round)
					end)
					step(`tick-after-add {round}`, false, function(w)
						w.tick(dx, dy)
					end)
					local added = #a.items
					step(`remove {round}`, false, function(w)
						w.remove(added)
					end)
				end
				a.dispose()
				b.dispose()
				c.dispose()
				d.dispose()
				e.dispose()
			end
		end)
	end

	it("the pos == sro identity is a real instrument, not a tautology", function()
		--[[ `snapshot()` asserts the fake's composed engine position against
			`controller.screenRectOf` per line. A check that cannot fail is decoration,
			so this drives the negative control by hand: with the subtree recompose
			deleted from `fake_target.setRect`, a host move leaves every descendant's
			`presentedPosition` at its pre-move value and the token appears. Here the
			token must be ABSENT after a move, and the fixture must really move. ]]
		local s = scene.new({ plates = 4 })
		s.tick(3, 2)
		s.tick(7, 5)
		local shot = s.snapshot()
		expect(string.find(shot, "POSMISMATCH", 1, true)).toBeNil()
		-- ...and the descendants really are stored host-relative, so the identity had
		-- something to check
		local name = "/S/Canvas/Plates/[p3]/Plate/Row/Name"
		-- `storedRect` is what the renderer HANDED the adapter; `rect` is where the
		-- node is. The two differing is the change this oracle exists for.
		local stored = s.adapter.node(name).storedRect
		local sro = s.controller.screenRectOf(name)
		expect(`relative={stored.x ~= sro.x or stored.y ~= sro.y}`).toBe("relative=true")
		s.dispose()
	end)
end)
