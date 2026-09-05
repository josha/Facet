--!strict
--[[ THE COMMIT'S SIBLING SCAN, PAID ONCE INSTEAD OF EIGHT TIMES (Plan C, C4).

	WHAT THE PROFILE FOUND, and it is not the number P4 left behind. On
	`battle_hud L updateItem-hp` at `e74b17fd` the eight commit walks are
	**0.599 ms of a 2.290 ms class — 26.2 %**, and 0.599 of the 0.611 ms
	`Facet/commit` span: the walks ARE the commit. But every one of them visits SIX
	nodes. P4's prune already took the VISITS to the dirty chain; what is left is the
	QUESTION — `skip(child)` asked of all 1,000 siblings under the list node, once per
	walk, eight times over, to be told "skip" 8,000 times.

	SO THE COUNT THIS FILE PINS IS `lastCommitScans`, not `lastCommitVisits`. The
	visit counters do not move here AT ALL, and that is the claim rather than an
	aside: this change does not prune one extra node. `descendOf(node)` computes the
	list of children worth asking about ONCE per node per commit and all eight walks
	iterate the one for their own shape and do NOT ask again. Measured on
	`deep_stack_scene`, one leaf's text: **8,032 scans -> 1,011**, with `harvest=4
	visible=4 hitRects=5 rectPass=5` and `rectWrites`, `propWrites`, `engineWrites`
	identical on both sides. The full-solve drive, which prunes nothing and could
	never be helped, goes **18,012 -> 6**: the eight root guards and not one
	per-child question.

	THREE LISTS, ONE PASS, AND THE CALLER DOES NOT RE-ASK. `skip` is called in three
	shapes here — flagless (`hitRects`, `rect_pass`), `moveBlind` (`harvest`,
	`visible`) and `moveBlind + arrangeBlind` (the four narrow walks) — and one pass
	over the children answers all three, sharing the `entryVerdict` that costs
	something. Each walk iterates the list for its own shape, so its per-node guard
	is redundant and it says so with `chosen`; the ROOT, which no parent selected,
	keeps the guard. A first version cached ONE list and made every walk re-ask its
	own question of every member — which is a whole extra pass on a commit that
	prunes nothing, and it MEASURED as one: `war_room_inventory reorder` +4.7 %,
	`killfeed_nameplates addItem-feed` +4.2 %.

	AND THE CACHE CANNOT GO STALE THE UNSAFE WAY: the one input that moves
	mid-commit, `lastCommitEntry`, is written by `rect_pass`'s `note`/`noteEntry`,
	which can only turn `skip` from false to TRUE, so a list built by an earlier walk
	is at worst a SUPERSET of what a later one would compute — an extra descent,
	never a missed one.

	WHAT THIS FILE REFUSES, and it is the mechanism the task was dispatched with. The
	plan proposed a DIRTY-CHILD INDEX: `dirtyScan` records `dirtyChildren[parent] =
	{ child, … }` beside `markDirtyIn`, and a walk at a dirty node descends only
	those. **It is unsound.** The entry-identity half of `skip` is closed UPWARD only
	— "a child with a new entry has a parent with one", which is what makes pruning a
	SUBTREE legal — and it says nothing downward. A dirty parent's CLEAN child gets a
	new entry whenever the solve re-arranged it, which is every `fill` or `content`
	child of any container whose offer moved. "A CLEAN CHILD OF A DIRTY PARENT" below
	is that shape driven: a `width` write on a row is dirt on the ROW alone, the row's
	`fill` child is in no dirty set, and its rect goes 300 -> 220. Under the index the
	walk stops at the row and the box paints 300 px forever, behind a green suite. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local deep = require("./lib/deep_stack_scene")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local function byWalk(st: any): string
	local keys = {}
	for k in st.lastCommitVisitsByWalk do
		table.insert(keys, k)
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		table.insert(parts, `{k}={st.lastCommitVisitsByWalk[k]}`)
	end
	return table.concat(parts, " ")
end

--[[ A ROW WHOSE WIDTH IS A SIGNAL AND WHOSE ONLY CHILD FILLS IT. Small on purpose:
	the claim is about ONE parent-child pair and a 20-row list makes the numbers
	readable. `commitScope` is the arm switch, so the same builder produces the
	pruned build and the pre-P4 control the oracle compares against. ]]
local function fillScene(commitScope: boolean)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
	local width = core:signal(300)
	local rows: { any } = {}
	for i = 1, 20 do
		rows[i] = UI.HStack({
			id = `R{i}`,
			padding = 0,
			gap = 0,
			width = if i == 5
				then core:memo(function(use: any)
					return { type = "fixed", px = use(width) :: number }
				end)
				else { type = "fixed", px = 300 },
			height = { type = "fixed", px = 18 },
			children = {
				UI.Box({ id = "Fill", width = { type = "fill", weight = 1 }, height = { type = "fixed", px = 10 } }),
			},
		})
	end
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "List",
					padding = 0,
					gap = 2,
					width = { type = "fill", weight = 1 },
					height = { type = "content" },
					children = rows,
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
		commitScope = commitScope,
		translateHosts = true,
	})
	controller.initialRender()
	return {
		controller = controller,
		adapter = adapter,
		setWidth = function(px: number)
			width:set(px)
			controller.refresh()
		end,
		rectOf = function(path: string): string
			local r = controller.rectOf(path)
			return if r == nil then "-" else `{r.x},{r.y},{r.w},{r.h}`
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

describe("C4: the commit's sibling scan is paid once, not once per walk", function()
	it("one leaf's text on a 1,000-row list asks 1,011 questions, not 8,032", function()
		--[[ READ OFF THE RUN at `e74b17fd` + this file's counter, with the cache
			disabled (`descendOf` returning `node.children`): 8,032. With it: 1,011 —
			the 1,000 rows classified ONCE at `/S/List`, plus each visited node's own
			children and the eight root guards. The first drive is a warm-up: the
			fixture's first refresh after `initialRender` is a structural one and
			cannot prune. ]]
		local s = deep.new({})
		s.text(500, "warm")
		s.text(500, "Row 500 changed")
		local st = s.stats() :: any
		expect(`scans={st.lastCommitScans}`).toBe("scans=1011")
		-- ...AND NOT ONE VISIT MOVED. This is the whole safety claim, pinned rather
		-- than argued: the cache decides which children are CONSIDERED and never
		-- which are descended.
		expect(`visits={st.lastCommitVisits} {byWalk(st)}`).toBe(
			"visits=34 harvest=4 hitRects=5 padding=4 rectPass=5 scrollRegions=4 textScale=4 textVerdicts=4 visible=4"
		)
		expect(`rects={st.rectWrites} props={st.propWrites} engine={st.engineWrites}`).toBe(
			"rects=3006 props=7004 engine=6008"
		)
		s.dispose()
	end)

	it("...and a width write on the ROW itself asks 1,011 too", function()
		local s = deep.new({})
		s.width(500, 280)
		s.width(500, 260)
		local st = s.stats() :: any
		expect(`scans={st.lastCommitScans} visits={st.lastCommitVisits}`).toBe("scans=1011 visits=24")
		s.dispose()
	end)

	it("an UNARMED commit takes the live child list and asks NOTHING", function()
		--[[ `skip` answers false for everything when the prune is off, so a cache
			there would hold a copy of `node.children` for every node in the tree — a
			second tree, on the commit that is already the expensive one, and on the
			arm the differential oracle uses as its pre-P4 control. `descendOf` returns
			before any of that, and because the walks no longer re-ask their own guard
			on a child their parent handed them, the 18,012 questions this commit used
			to ask — every one of them answered "descend" by the first line of `skip` —
			are gone: 6, the root guard of each walk that runs. ]]
		local s = deep.new({})
		s.text(500, "warm")
		s.viewport(1000, 700)
		local st = s.stats() :: any
		expect(`scans={st.lastCommitScans} visits={st.lastCommitVisits}`).toBe("scans=6 visits=21014")
		s.dispose()
	end)
end)

describe("C4: A CLEAN CHILD OF A DIRTY PARENT is still descended", function()
	it("a `fill` child re-lays out when its row's width moves, and is in no dirty set", function()
		--[[ THE CASE THAT REFUSES THE DIRTY-CHILD INDEX (see this file's header). The
			signal is bound to `/S/List/R5`'s `width`, so `markDirtyIn` marks
			`/S/List/R5`, `/S/List` and `/S` and nothing below — yet the child's rect
			changes, because the solve re-arranged it against the row's new inner box. ]]
		local s = fillScene(true)
		expect(s.rectOf("/S/List/R5/Fill")).toBe("0,80,300,10")
		s.setWidth(220)
		expect(s.rectOf("/S/List/R5/Fill")).toBe("0,80,220,10")
		-- and the ADAPTER has it, not just the solver: a rect nobody wrote is the
		-- exact defect the index would have shipped
		local live = s.adapter.liveNodes()["/S/List/R5/Fill"]
		local stored = (live :: any).storedRect
		expect(`w={stored.w}`).toBe("w=220")
		local st = s.controller.stats() :: any
		expect(`scans={st.lastCommitScans} {byWalk(st)}`).toBe(
			"scans=30 harvest=4 hitRects=4 padding=4 rectPass=4 scrollRegions=4 textScale=4 textVerdicts=4 visible=4"
		)
		s.dispose()
	end)

	it("...and the pruned arm agrees with a full-walk arm rect for rect", function()
		local a = fillScene(true)
		local b = fillScene(false)
		for _, px in { 220, 300, 180, 180, 420 } do
			a.setWidth(px)
			b.setWidth(px)
			for i = 1, 20 do
				expect(`{px} R{i} {a.rectOf(`/S/List/R{i}`)}`).toBe(`{px} R{i} {b.rectOf(`/S/List/R{i}`)}`)
				expect(`{px} R{i}/Fill {a.rectOf(`/S/List/R{i}/Fill`)}`).toBe(
					`{px} R{i}/Fill {b.rectOf(`/S/List/R{i}/Fill`)}`
				)
			end
		end
		a.dispose()
		b.dispose()
	end)
end)

describe("C4: the differential oracle over the deep stack", function()
	it("every drive leaves the pruned arm and the full-walk arm byte-identical", function()
		--[[ THE SAME QUESTION `commit_scope.spec` asks of P4, asked again of the
			cache and on the fixture whose sibling scan the cache exists to cut: four
			drive kinds — a leaf's text, a row's own width, a coupled row's HEIGHT
			(which moves a CLEAN child's offer without dirtying it, the shape the
			index would have broken) and a viewport change, which is a full solve with
			no reuse table at all and must be structurally identical on both arms. ]]
		for _, arm in { "plain", "coupled", "hug" } do
			local a = deep.new({
				rows = 60,
				coupled = arm == "coupled",
				hug = arm == "hug",
			})
			local b = deep.new({
				rows = 60,
				coupled = arm == "coupled",
				hug = arm == "hug",
				commitScope = false,
			})
			local step = 0
			local function agree()
				step += 1
				expect(`{arm} step {step}\n{a.snapshot()}`).toBe(`{arm} step {step}\n{b.snapshot()}`)
			end
			for _, drive in
				{
					function(s: any)
						s.text(deep.GATE_ROW, "changed")
					end,
					function(s: any)
						s.width(deep.GATE_ROW, 240)
					end,
					function(s: any)
						s.height(deep.GATE_ROW, 40)
					end,
					function(s: any)
						s.text(7, "another")
					end,
					function(s: any)
						s.viewport(900, 620)
					end,
					function(s: any)
						s.width(7, 200)
					end,
				}
			do
				drive(a)
				drive(b)
				agree()
			end
			a.dispose()
			b.dispose()
		end
	end)
end)

describe("C4: the two walks that are exempt from the cache stay exempt", function()
	it("a hide FLIP still reaches every descendant of the flipped node", function()
		--[[ `visible` takes the LIVE child list whenever this node's verdict flipped,
			because a flip is inherited and forces every descendant whatever `skip`
			would have said. The subtree below is otherwise clean — nothing in it is in
			any dirty set — so a cache consulted here would hide every one of them. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
		local hidden = core:signal(false)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Group",
						hidden = hidden,
						children = {
							UI.VStack({
								id = "Inner",
								children = {
									UI.Box({
										id = "A",
										width = { type = "fixed", px = 10 },
										height = { type = "fixed", px = 10 },
									}),
									UI.Box({
										id = "B",
										width = { type = "fixed", px = 10 },
										height = { type = "fixed", px = 10 },
									}),
								},
							}),
						},
					}),
					UI.Box({ id = "Other", width = { type = "fixed", px = 10 }, height = { type = "fixed", px = 10 } }),
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
			translateHosts = true,
		})
		controller.initialRender()
		local function visibility(): string
			local out = {}
			for _, path in { "/S/Group", "/S/Group/Inner", "/S/Group/Inner/A", "/S/Group/Inner/B" } do
				local node = adapter.liveNodes()[path]
				table.insert(out, `{path}={tostring((node :: any).visible)}`)
			end
			return table.concat(out, " ")
		end
		hidden:set(true)
		controller.refresh()
		expect(visibility()).toBe("/S/Group=false /S/Group/Inner=false /S/Group/Inner/A=false /S/Group/Inner/B=false")
		hidden:set(false)
		controller.refresh()
		expect(visibility()).toBe("/S/Group=true /S/Group/Inner=true /S/Group/Inner/A=true /S/Group/Inner/B=true")
		controller.dispose()
		root.dispose()
	end)
end)
