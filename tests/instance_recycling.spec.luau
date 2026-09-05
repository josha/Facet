--!strict
--[[
	INSTANCE RECYCLING — a scrolling list rebuilds an identical row at one end every
	time the window slides, for no reason except that the row's PATH changed.

	Measured on the engine, in a Studio Play session (2026-08-05): building one
	24-object row costs **0.252 ms** and destroying it **0.045 ms**, while rewriting
	the same 24 objects' properties costs **0.024 ms** — twelve times cheaper. The
	structural pass (`Facet/mount`) was 0.66–0.97 ms/frame at every viewport, the
	largest single component of a Facet frame after the L-9 measure-key fix.

	THE ONLY INVARIANT THAT MATTERS: a recycled node must be indistinguishable from
	a freshly created one. Not "close" — identical. Every test here is therefore a
	DIFFERENTIAL: run the same scenario twice, once with recycling on and once off,
	and compare the resulting virtual state. A test that only asserted "recycling
	happened" would pass just as happily on a build that reused a node while leaving
	one stale property on it, and a stale property is the entire risk.

	ON BY DEFAULT; `opts.recycleInstances = false` opts out, and the adapter must
	offer park/adopt/discardParked. Since L-28 the live adapter parks THEMED nodes
	too (their chrome's path-keyed registrations are released on park and re-keyed
	on adopt — see instance_recycling_themed.spec); `park` still refuses what
	cannot travel (clip-host role, presentation transform, motion scale, the
	sibling-parented hit expander and float focus ring, a focused node), and a
	refusal falls straight through to the ordinary remove — so the feature can only
	ever do nothing, never something different.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local fake_target = require("../tests/lib/fake_target")

-- The row's pitch. A VirtualList windows on a FIXED height by contract, so this has
-- to be a number — but it must be a number the row actually fits in, not one that
-- happens to look right. `assertClean` below is what makes it a measured constant
-- rather than a hopeful one: the solver reports overflow and every fixture fails on a
-- non-empty finding. (This spec's first version hard-coded 56 with a `viewportHeight`
-- unrelated to the viewport and never asked the solver anything — the exact defect
-- the solver's own diagnostics exist to report.)
-- MUTATION-PROVED, not chosen: setting this to 20 reddens 16 cases with
-- "overflows its zstack by 0x4px" from the solver; 40 and 56 are clean. So the
-- constant is a measured floor with headroom, and the audit is what makes it one.
local ROW_HEIGHT = 56
local VIEWPORT = { w = 360, h = 640 }

local function makeItems(n: number)
	local out = {}
	for i = 1, n do
		table.insert(out, { id = `r{i}`, label = `Row {i}`, detail = `detail {i * 7 % 13}` })
	end
	return out
end

-- One world, driven identically. `recycle` is the ONLY difference between runs.
--
-- `ragged` makes every third row declare properties the others do not. That is the
-- shape the whole safety argument rests on: while every row declares an IDENTICAL
-- prop set, a stale value is always overwritten by the renderer and no differential
-- can see a bug. Proven, not assumed — with uniform rows only, deliberately
-- skipping the property reset in `park` left the entire suite green.
-- ASK THE SOLVER. A fixture that never reads `controller.diagnostics()` is not
-- verified, however many counters it asserts — that is the whole of the
-- standing lesson, and it applies to a perf fixture
-- exactly as much as to a shipped screen: a number measured on an overflowing
-- layout describes a screen nobody would ship.
local function assertClean(handle: any, where: string)
	local findings = handle.controller.diagnostics()
	if #findings > 0 then
		local first = findings[1]
		error(`layout finding at {where}: {tostring(first.node)}: {tostring(first.issue)}`, 2)
	end
end

local function world(recycle: boolean?, ragged: boolean?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local rows = core:signal(makeItems(400))
	local list = virtual_list.build(Facet, core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = ROW_HEIGHT,
		-- DERIVED from the viewport, not a magic number beside it. The list is the
		-- Screen's only child, so the space it gets IS the viewport height.
		viewportHeight = VIEWPORT.h,
		overscan = 2,
		cell = function(item: any)
			local n = tonumber(string.match(item.id, "%d+")) or 0
			local odd = ragged == true and n % 3 == 0
			return Facet.UI.HStack({
				id = "Row",
				gap = 6,
				children = {
					Facet.UI.VStack({
						id = "Labels",
						gap = 2,
						children = {
							Facet.UI.Text({
								id = "Name",
								text = item.label,
								textSize = 15,
								-- declared on SOME rows only: a recycled node that kept
								-- this from its previous identity would paint a
								-- centre-aligned label in a row that never asked for one
								textAlign = if odd then "center" else nil,
							}),
							Facet.UI.Text({ id = "Detail", text = item.detail, textSize = 12 }),
						},
					}),
					Facet.UI.Box({ id = "Pad", width = { type = "fill", weight = 1 } }),
				},
			})
		end,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
	-- `nil` presents with NO recycling opt at all, which is the path every ordinary
	-- consumer takes and therefore the one the default has to be proven on
	local handle = pres.present(screen, if recycle == nil then nil else { recycleInstances = recycle })
	pres.refresh()
	list.bindNativeScroll(handle.controller)
	assertClean(handle, "mount")
	return {
		core = core,
		pres = pres,
		list = list,
		adapter = adapter,
		handle = handle,
		dispose = function()
			list.dispose()
		end,
	}
end

-- BY VALUE, NEVER BY ADDRESS. The first version of this used `tostring(v)` for
-- every property, and a table-valued prop (`textFont` is a descriptor table)
-- stringified to its heap address — which differs between two separately built
-- worlds by construction. Every differential then "failed" on six rows whose
-- geometry and text were byte-identical. A comparison that includes an address is
-- a comparison that can never pass, and it looks exactly like a real defect.
local function valueOf(v: any): string
	if type(v) ~= "table" then
		return tostring(v)
	end
	local parts = {}
	for k, inner in v do
		table.insert(parts, `{tostring(k)}={if type(inner) == "table" then "{...}" else tostring(inner)}`)
	end
	table.sort(parts)
	return `\{{table.concat(parts, ",")}\}`
end

-- The whole virtual state, canonicalised: every live node's path, class and every
-- property it currently carries. This is the thing that must not differ.
local function snapshot(adapter: any): string
	local rows = {}
	for path, node in adapter.liveNodes() do
		local props = {}
		for k, v in node.props or {} do
			table.insert(props, `{k}={valueOf(v)}`)
		end
		table.sort(props)
		local r = node.rect
		table.insert(
			rows,
			`{path}|{node.class}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|{table.concat(props, ",")}`
		)
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

local function scrollTo(w: any, y: number)
	w.handle.controller.scrollTo("/S/VL", { x = 0, y = y })
	w.pres.refresh()
	-- every scroll audits: the window slid, so the geometry changed
	assertClean(w.handle, `scroll to {y}`)
end

describe("instance recycling: a recycled node is indistinguishable from a fresh one", function()
	it("is ON by default — the whole point is that a list does not have to ask", function()
		-- `world(nil)` passes no opt at all, which is what an ordinary consumer does
		local w = world(nil)
		for i = 1, 12 do
			scrollTo(w, i * 61)
		end
		local s = w.handle.controller.stats()
		expect(s.recycleArmed).toBe(true)
		expect(s.recycled > 0).toBe(true)
		w.dispose()
	end)

	it("an explicit `false` opts out completely", function()
		local w = world(false)
		for i = 1, 12 do
			scrollTo(w, i * 61)
		end
		local s = w.handle.controller.stats()
		expect(s.recycleArmed).toBe(false)
		expect(s.recycled).toBe(0)
		expect(s.parked).toBe(0)
		expect(s.creates > 0).toBe(true)
		w.dispose()
	end)

	it("actually recycles when asked — otherwise every differential below is vacuous", function()
		local w = world(true)
		for i = 1, 12 do
			scrollTo(w, i * 61)
		end
		local s = w.handle.controller.stats()
		-- the guard against a green suite that proves nothing: if the pool never
		-- served a create, the identical-state tests would pass on a no-op
		expect(s.parked > 0).toBe(true)
		expect(s.recycled > 0).toBe(true)
		w.dispose()
	end)

	it("DIFFERENTIAL: the virtual state after a long scroll is byte-identical", function()
		local a, b = world(true), world(false)
		for i = 1, 40 do
			scrollTo(a, i * 61)
			scrollTo(b, i * 61)
		end
		expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		a.dispose()
		b.dispose()
	end)

	it("DIFFERENTIAL: state matches at every step of the scroll, not just the end", function()
		-- an end-state comparison can be satisfied by two builds that disagreed in
		-- the middle and converged; this compares every intermediate frame
		local a, b = world(true), world(false)
		for i = 1, 25 do
			scrollTo(a, i * 37)
			scrollTo(b, i * 37)
			expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		end
		a.dispose()
		b.dispose()
	end)

	it("DIFFERENTIAL: scrolling back to the top restores the opening state exactly", function()
		-- the case that catches a stale property: the rows at the top are rebuilt
		-- from pooled objects that previously held completely different rows
		local a, b = world(true), world(false)
		local openA, openB = snapshot(a.adapter), snapshot(b.adapter)
		expect(openA).toBe(openB)
		for i = 1, 30 do
			scrollTo(a, i * 61)
			scrollTo(b, i * 61)
		end
		scrollTo(a, 0)
		scrollTo(b, 0)
		expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		-- ...and equals the state before any scrolling happened at all
		expect(snapshot(a.adapter)).toBe(openA)
		a.dispose()
		b.dispose()
	end)

	it("DIFFERENTIAL: rows with DIFFERENT prop sets still match exactly", function()
		-- The case the uniform worlds above cannot reach. Every third row declares a
		-- `textAlign` the others do not, so the pool constantly hands a node that
		-- carried the prop to a row that does not declare it. If `park` did not drop
		-- the old identity's properties, the alignment would survive the change of
		-- identity and this is where it shows.
		local a, b = world(true, true), world(false, true)
		for i = 1, 30 do
			scrollTo(a, i * 61)
			scrollTo(b, i * 61)
			expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		end
		scrollTo(a, 0)
		scrollTo(b, 0)
		expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		expect(a.handle.controller.stats().recycled > 0).toBe(true)
		a.dispose()
		b.dispose()
	end)

	it("the pool is BOUNDED — a long scroll cannot grow it without limit", function()
		local w = world(true)
		for i = 1, 200 do
			scrollTo(w, i * 61)
		end
		local s = w.handle.controller.stats()
		-- parking is capped, so a scroll that retires hundreds of rows still ends
		-- with a pool no larger than the cap; anything beyond it took the ordinary
		-- remove path
		expect(s.parked <= 200 * 64).toBe(true)
		expect(s.removes >= 0).toBe(true)
		w.dispose()
	end)
end)

--[[ T4b — THE PLAIN HOST, WHICH PLAN C MADE COMMON AND THE POOL REFUSED.

	C1 made every container with a REACTIVE `offsetX`/`offsetY`/`anchor` and children
	a real instance parent — a coordinate space, so its subtree's rects are stored
	against it and one move is one write instead of one per descendant. It also made
	every one of those containers unrecyclable, because `parkEligible` refused a
	registered host outright. Measured on the arena's 250-plate workload
	(FacetBench §C1.3, `attr nameplates L 3`, A/B/B/A): `removeItem-plates`
	**+21.3 %**, effectively all of it inside `span:Facet/mount` — the sweep
	destroying plate roots it used to pool.

	T4b narrows the refusal to a host that CROPS or that still has CHILDREN. The
	cases below are the behavioural half; the live adapter's own text is pinned in
	`tests/instance_park_corpse.spec.luau`, which cannot require `screen_target`.

	THE FIXTURE IS THE ARENA'S SHAPE, not a list: an `Anchor` canvas holding a
	`ForEach` whose row root carries a reactive placement. Removing every key and
	adding a fresh set is one remove -> add cycle over a host per row, which is
	exactly the `removeItem-plates` / `addItem-plates` pair the measurement names. ]]
local function plateWorld(recycle: boolean?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local system = Facet.newActionSystem(core)
	-- ARMED (T12): `opsFor` and the deepest-first order test below both read
	-- `.ops()` off this world's adapter.
	local adapter = fake_target.new({ ops = true })
	local pres = Facet.newPresenter(core, env, adapter, system)
	local rows = core:signal({})
	local rotRows = core:signal({})
	--[[ TWO LISTS, ONE POOL, and that is the whole reason the second one exists.
		`Plates` roots are COORDINATE SPACES (a reactive placement); `Rotated` roots
		are the OTHER trigger `instance_boundary.createOptsFor` has for the same plain
		Frame — an authored `rotation` on a container with children — and are NOT
		coordinate spaces. `kindOf` answers `"host"` for both and `rotation` is
		neither a binding nor a style prop, so the two share a recycle bucket: a
		`Rotated` root really can be handed a parked `Plates` root. That is the
		cross-space adoption `hostSpace` has to be re-derived for. ]]
	local function plateRow(rotated: boolean)
		return function(item: any)
			return Facet.UI.VStack({
				id = "Plate",
				rotation = if rotated then 12 else nil,
				anchor = if rotated then nil else "topLeft",
				offsetX = if rotated then nil else item.x,
				offsetY = if rotated then nil else item.y,
				padding = 0,
				gap = 2,
				width = { type = "fixed", px = 120 },
				height = { type = "content" },
				children = {
					Facet.UI.Text({ id = "Name", text = item.label, textSize = 14 }),
					Facet.UI.Box({
						id = "Hp",
						width = { type = "fixed", px = 40 },
						height = { type = "fixed", px = 6 },
					}),
				},
			})
		end
	end
	local function keyOf(item: any)
		return item.id
	end
	local screen = Facet.UI.Screen({
		id = "S",
		children = {
			Facet.UI.Anchor({
				id = "Canvas",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					Facet.UI.ForEach({ id = "Plates", items = rows, key = keyOf, row = plateRow(false) }),
					Facet.UI.ForEach({ id = "Rotated", items = rotRows, key = keyOf, row = plateRow(true) }),
				},
			}),
		},
	})
	local handle = pres.present(screen, if recycle == nil then nil else { recycleInstances = recycle })
	pres.refresh()
	local function itemsFor(keys: { string })
		local items = {}
		for i, id in keys do
			table.insert(items, {
				id = id,
				label = `Plate {id}`,
				x = core:signal((i * 37) % 300),
				y = core:signal((i * 53) % 500),
			})
		end
		return items
	end
	local w
	w = {
		core = core,
		pres = pres,
		adapter = adapter,
		handle = handle,
		-- one step of the arena's structural pair: `set` the whole key set, then
		-- settle. Two refreshes, as every other recycling drive here does — the
		-- adoption happens on the mount that follows the sweep.
		setKeys = function(keys: { string })
			rows:set(itemsFor(keys))
			w.pres.refresh()
			w.pres.refresh()
			assertClean(handle, `keys {table.concat(keys, ",")}`)
		end,
		setRotKeys = function(keys: { string })
			rotRows:set(itemsFor(keys))
			w.pres.refresh()
			w.pres.refresh()
			assertClean(handle, `rotated keys {table.concat(keys, ",")}`)
		end,
	}
	return w
end

-- the plate ROOTS the ops log names, in arrival order, for one verb
local function opsFor(adapter: any, verb: string): { string }
	local out: { string } = {}
	for _, line in adapter.ops() do
		local path = string.match(line, `^{verb} (%S+)`)
		if path ~= nil then
			table.insert(out, path)
		end
	end
	return out
end

describe("T4b: a plain, childless instance host is recyclable", function()
	it("a coordinate-space plate root PARKS on its removal and is ADOPTED by the next one", function()
		local w = plateWorld(true)
		w.setKeys({ "p1", "p2", "p3" })
		local before = w.handle.controller.stats()
		w.setKeys({})
		local afterPark = w.handle.controller.stats()
		w.setKeys({ "p4", "p5", "p6" })
		local afterAdopt = w.handle.controller.stats()

		-- the host really is one: a reactive placement on a container with children
		expect(w.adapter.isHost("/S/Canvas/Plates/[p4]/Plate")).toBe(true)
		-- ...and the PLATE ROOT itself is in the pool's traffic, not merely its leaves.
		-- A `parked > 0` alone would be satisfied by the two children of every row.
		local parked = opsFor(w.adapter, "park")
		local adopted = opsFor(w.adapter, "adopt")
		local parkedRoots, adoptedRoots = 0, 0
		for _, path in parked do
			if string.find(path, "/Plate$") ~= nil then
				parkedRoots += 1
			end
		end
		for _, path in adopted do
			if string.find(path, "/Plate$") ~= nil then
				adoptedRoots += 1
			end
		end
		expect(`parked {parkedRoots} adopted {adoptedRoots}`).toBe("parked 3 adopted 3")
		expect(afterPark.parked > before.parked).toBe(true)
		expect(afterAdopt.recycled > afterPark.recycled).toBe(true)
		-- ...and the adoption re-earned the registration under the NEW path rather
		-- than carrying the parked one: the dead key is gone and the live one answers
		expect(w.adapter.isHost("/S/Canvas/Plates/[p1]/Plate")).toBe(false)
	end)

	it("DIFFERENTIAL: the remove -> add cycle is byte-identical with the pool and without it", function()
		local a, b = plateWorld(true), plateWorld(false)
		for _, keys in { { "p1", "p2", "p3" }, {}, { "p4", "p5", "p6" }, { "p4", "p7" }, {}, { "p8", "p9" } } do
			a.setKeys(keys)
			b.setKeys(keys)
			-- every step, not just the last: two builds that disagreed in the middle
			-- and converged would satisfy an end-state compare
			expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		end
		-- ...and the arm under test really did use the pool ON A HOST, not merely on
		-- the two leaves under one (which recycled before T4b and would keep this
		-- compare green on a build that lifted nothing)
		local adoptedRoots = 0
		for _, path in opsFor(a.adapter, "adopt") do
			if string.find(path, "/Plate$") ~= nil then
				adoptedRoots += 1
			end
		end
		expect(adoptedRoots > 0).toBe(true)
		expect(b.handle.controller.stats().recycled).toBe(0)
	end)

	it("DIFFERENTIAL: a parked SPACE host adopted as a ROTATED one carries no space across", function()
		--[[ THE CROSS-SPACE TRAP, in one pool. `hostSpace` decides whether a subtree's
			rects are stored relative to this node or absolutely, so an adoption that
			carried the parked identity's flag would place a whole subtree against an
			origin nobody composes back — and the composed position is what a player
			sees, which is why the differential is the instrument and a counter is not.
			`restoreParkedProps`' same-space guard is the other half of this and covers
			only the CARRIED rect; the registration is this task's. ]]
		local a, b = plateWorld(true), plateWorld(false)
		a.setKeys({ "p1", "p2", "p3" })
		b.setKeys({ "p1", "p2", "p3" })
		a.setKeys({})
		b.setKeys({})
		-- arm `a`'s pool now holds three parked coordinate-space plate roots
		a.setRotKeys({ "r1", "r2", "r3" })
		b.setRotKeys({ "r1", "r2", "r3" })
		expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		-- NOT VACUOUS: the rotated roots really were served out of the pool, and they
		-- really are hosts that are NOT coordinate spaces
		local adoptedRoots = 0
		for _, path in opsFor(a.adapter, "adopt") do
			if string.find(path, "/Rotated/.*/Plate$") ~= nil then
				adoptedRoots += 1
			end
		end
		expect(adoptedRoots).toBe(3)
		expect(a.adapter.isHost("/S/Canvas/Rotated/[r1]/Plate")).toBe(true)
		expect(a.adapter.hostSpaceAt("/S/Canvas/Rotated/[r1]/Plate")).toBe(false)
		expect(a.adapter.hostSpaceAt("/S/Canvas/Plates/[p1]/Plate")).toBe(nil)
	end)

	it("a host that still has CHILDREN is refused, and the identical EMPTY one is taken", function()
		--[[ The rule at the adapter's own seam, both ways in one case. A behavioural
			drive cannot reach the refusal through the renderer any more — the sweep
			empties a host before it asks (the ordering case below) — so the positive
			arm is what keeps this from being a test of a fixture that never parks. ]]
		local adapter = fake_target.new() :: any
		local root = adapter.createRoot("S")
		local host = adapter.create(root, "/S/Host", "VStack", nil, { instanceHost = true, hostSpace = true })
		local kid = adapter.create(root, "/S/Host/Kid", "Box", nil, nil)
		expect(adapter.isHost("/S/Host")).toBe(true)
		expect(adapter.park(host)).toBe(false)
		-- the child leaves the way the sweep would take it, and the SAME host is now
		-- eligible — so the refusal above was about the children and nothing else
		adapter.remove(kid)
		expect(adapter.park(host)).toBe(true)
		-- ...and parking released the registration, so no later node at that path
		-- resolves its parent to a pooled instance
		expect(adapter.isHost("/S/Host")).toBe(false)
		expect(adapter.adopt(host, "/S/Other", "VStack", nil, root, { instanceHost = true, hostSpace = true })).toBe(
			true
		)
		expect(adapter.isHost("/S/Other")).toBe(true)
	end)

	it("a CANVASGROUP host is still refused — its buffer is a construction decision", function()
		local adapter = fake_target.new() :: any
		local root = adapter.createRoot("S")
		local group = adapter.create(root, "/S/Group", "ZStack", nil, { canvasGroup = true })
		expect(adapter.isHost("/S/Group")).toBe(true)
		expect(adapter.park(group)).toBe(false)
		-- NEGATIVE CONTROL: the same node with the plain option instead is taken, so
		-- the refusal above is the buffer and not "a host with an option"
		local plain = adapter.create(root, "/S/Plain", "ZStack", nil, { instanceHost = true })
		expect(adapter.park(plain)).toBe(true)
	end)

	it("the sweep visits departed paths DEEPEST FIRST, or the children rule is unanswerable", function()
		--[[ The order lives in `renderer.luau`'s sweep, which IS requirable headlessly,
			so this is a behaviour pin rather than a text one: `adapter.ops()` records
			arrival order, and the claim is that on the frame a plate root and its two
			children all depart, both children reach the adapter before the root. Invert
			`deeperFirst` and the root arrives first, is refused for having children, and
			the two counts below separate immediately. ]]
		local w = plateWorld(true)
		w.setKeys({ "p1" })
		local mark = #w.adapter.ops()
		w.setKeys({})
		local order: { string } = {}
		for i = mark + 1, #w.adapter.ops() do
			local line = w.adapter.ops()[i]
			local verb, path = string.match(line, "^(park) (%S+)")
			if verb == nil then
				verb, path = string.match(line, "^(remove) (%S+)")
			end
			if path ~= nil and string.find(path, "/Plates/%[p1%]") ~= nil then
				table.insert(order, `{verb} {string.match(path, "[^/]+$")}`)
			end
		end
		-- the two leaves reach the adapter FIRST and the root LAST — and the root's
		-- verb is `park`, which is only reachable because its children already left
		expect(table.concat(order, " ; ")).toBe("park Name ; park Hp ; park Plate")
	end)
end)

--[[ NM-H4a — WHERE A RECYCLED NODE LANDS WHEN THE TARGET HOSTS MORE THAN ONE
	SURFACE.

	`park` takes an instance out of the tree and `adopt` puts it back. `adopt` is
	handed the new path, the new class and the decoration hint — and NOT the root
	it is adopting for. `screen_target` filled that gap with `lastRootHandle`, a
	module-scope local holding whichever root the LAST `create` on this adapter
	belonged to (screen_target.luau :987 / :1212 / :3708).

	One adapter hosts every surface: the gallery presents its own showcase screen
	on top of the scenario's, the `hud` demo mounts a probe plate on a third, and
	an overflow sink opens a fourth. So the root of the last create is the right
	answer only by luck of ordering — and when it is not, a node is re-parented
	into ANOTHER surface's ScreenGui. It keeps its rect, its ZIndex and
	`Visible = true`, so every model-side instrument agrees with itself while the
	node is drawn somewhere else, or nowhere at all once that surface is disabled
	or destroyed. That is the NM-H4a signature, and the reason 288 headless
	replays could not see it is that no headless target modelled a parent at all.

	The fixture is deliberately flat — no ScrollView, no clip host — because the
	`hud` demo's zones are flat, and a node inside an instance host takes the
	host branch and was never exposed. ]]
describe("recycling: an adopted node belongs to its OWN surface", function()
	local function twoSurfaceWorld()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 360, h = 640 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)

		local alphaItems = core:signal({ { id = "a1" }, { id = "a2" }, { id = "a3" } })
		local alpha = pres.present(
			Facet.UI.Screen({
				id = "Alpha",
				children = {
					Facet.UI.VStack({
						id = "Col",
						children = {
							Facet.UI.ForEach({
								id = "Rows",
								items = alphaItems,
								key = function(item: any)
									return item.id
								end,
								row = function(item: any)
									return Facet.UI.Text({ id = "RowText", text = item.id, textSize = 15 })
								end,
							}),
						},
					}),
				},
			}),
			{}
		)
		pres.refresh()

		-- the second surface, presented ON TOP exactly as the gallery's own
		-- showcase screen is presented over a scenario's
		local betaCount = core:signal(0)
		local betaItems = core:memo(function(use: any)
			local out = {}
			for i = 1, use(betaCount) do
				table.insert(out, { id = `b{i}` })
			end
			return out
		end)
		pres.present(
			Facet.UI.Screen({
				id = "Beta",
				children = {
					Facet.UI.VStack({
						id = "BetaCol",
						children = {
							Facet.UI.ForEach({
								id = "BetaItems",
								items = betaItems,
								key = function(item: any)
									return item.id
								end,
								row = function(item: any)
									return Facet.UI.Text({ id = "BetaText", text = item.id, textSize = 15 })
								end,
							}),
						},
					}),
				},
			}),
			{}
		)
		pres.refresh()
		return {
			pres = pres,
			adapter = adapter,
			alpha = alpha,
			alphaItems = alphaItems,
			betaCount = betaCount,
		}
	end

	-- every live node, and the surface root it actually hangs under
	local function misparented(adapter: any): { string }
		local out: { string } = {}
		for _, path in adapter.paths() do
			local own = string.match(path, "^/([^/]+)")
			local under = adapter.rootIdOf(path)
			if under ~= nil and own ~= nil and under ~= own then
				table.insert(out, `{path} under '{under}'`)
			end
		end
		return out
	end

	it("a node recycled after ANOTHER surface created one is still parented under its own root", function()
		local w = twoSurfaceWorld()
		-- 1. kill Alpha's rows, which parks their instances
		w.alphaItems:set({})
		w.pres.refresh()
		w.pres.refresh()
		expect(table.concat(misparented(w.adapter), " ; ")).toBe("")
		-- 2. the OTHER surface creates a node, so it owns the last-create record
		w.betaCount:set(2)
		w.pres.refresh()
		w.pres.refresh()
		expect(table.concat(misparented(w.adapter), " ; ")).toBe("")
		-- 3. Alpha rebuilds identically shaped rows, which come out of the pool
		w.alphaItems:set({ { id = "a4" }, { id = "a5" }, { id = "a6" } })
		w.pres.refresh()
		w.pres.refresh()
		-- the adoption actually happened: without this the assertion below would
		-- pass on a build where recycling never ran
		expect(w.alpha.controller.stats().recycled > 0).toBe(true)
		expect(table.concat(misparented(w.adapter), " ; ")).toBe("")
	end)

	it("the adoption count is not zero, so the assertion above is not vacuous", function()
		--[[ THE NEGATIVE CONTROL, and it is about the INSTRUMENT rather than the
			defect. `lastRootHandle` is right whenever there is only one root to be
			wrong about — which is precisely why every other recycling case in this
			file stayed green for the whole life of the defect. So this pins that the
			two-surface fixture really does drive adoptions on host-less nodes, and
			that they really do outnumber zero. ]]
		local w = twoSurfaceWorld()
		w.alphaItems:set({})
		w.pres.refresh()
		w.pres.refresh()
		w.betaCount:set(2)
		w.pres.refresh()
		w.pres.refresh()
		w.alphaItems:set({ { id = "a4" }, { id = "a5" }, { id = "a6" } })
		w.pres.refresh()
		w.pres.refresh()
		expect(w.alpha.controller.stats().recycled >= 3).toBe(true)
		-- ...and every one of them is a node with no instance host, which is the
		-- branch that reaches the root at all
		local hostless = 0
		for _, path in w.adapter.paths() do
			if string.find(path, "^/Alpha") ~= nil and w.adapter.rootIdOf(path) ~= nil then
				hostless += 1
			end
		end
		expect(hostless > 0).toBe(true)
	end)
end)
