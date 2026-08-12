--!strict
--[[ THE MOUNT-IDENTITY DIFFERENTIAL (row-actions perf mission, Task 5 — design
	doc §"What must be proven before ship": a `rowActions` list must mount a tree
	"identical to an unwrapped list except the one overlay node").

	THE CHARTER THIS FILE ANSWERS. Table's `rowActions` wraps every actionable row
	in a composite — five extra instances per row, mounted whether the row is ever
	touched or not. Hosting the feature is only worth doing if a closed hosted row
	costs NOTHING structural, and "nothing" is a claim about a mounted tree, so it
	is proven the way the incremental-layout work proved its own claims: build the
	SAME world twice, once plain and once hosted, and diff them.

	WHY A FILE OF ITS OWN rather than another case in
	tests/virtual_list_row_actions.spec.luau (whose (d)/(d2) assert the same
	property from the feature side, and which this deliberately does not restate):
	  * it is the SHIPPING PROOF the design charter names — a reader looking for
	    "is hosting actually free?" should find one file that answers it, not a
	    case buried in a 1500-line behavior suite;
	  * it is a DIFFERENTIAL, so its world builder takes the plain/hosted switch as
	    its only argument and everything else is held identical by construction —
	    the same items, the same viewport, the same clock, the same env;
	  * it proves the property over the WHOLE LIFECYCLE (closed -> engaged ->
	    closed, five times over), which is where a leak would actually show up,
	    and it counts adapter-held nodes and handlers rather than reading a
	    control's own bookkeeping.

	WHAT IT DOES NOT CLAIM. A hosted engine is KEPT once built (the row comes back;
	rebuilding it on every gesture would be the wrong trade) — so `engineCount`
	stays 1 after a row has been swiped, deliberately. The claim is about
	INSTANCES: nothing the player can see, hit, or pay a Roblox instance for may
	survive a disengage. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local row_actions_state = require("../src/input/row_actions_state")
local fake_target = require("../tests/lib/fake_target")

local LOCK = row_actions_state.AXIS_LOCK_PX
local FRAME = 1 / 60
local OVERLAY = "/S/VL/Canvas/RowActionsOverlay"

local function makeRows(n: number): { { id: string, label: string } }
	local rows = {}
	for i = 1, n do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	return rows
end

local function rowHit(key: string): string
	return `/S/VL/Canvas/W/[{key}]/Row/Hit`
end

--[[ THE TWO WORLDS, from ONE builder. `hosted` is the only difference there is:
	same 100 items, same 400px viewport over 40px rows, same overscan, same cell,
	same scripted clock, same env — so any difference the diff below finds is
	`rowActions` and can be nothing else. ]]
local function world(hosted: boolean): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local clockTime = 0
	local pres = LuauUI.newPresenter(core, env, adapter, system, {
		now = function()
			return clockTime
		end,
	})
	local fired: { string } = {}
	local spec: any = {
		id = "VL",
		rows = core:signal(makeRows(100)),
		key = function(item: any)
			return item.id
		end,
		rowHeight = 40,
		viewportHeight = 400,
		overscan = 2,
		cell = function(item: any)
			return LuauUI.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
		onActivate = function() end,
		env = env,
	}
	if hosted then
		spec.rowActions = function(item: any): any
			return {
				trailing = {
					{
						id = "delete",
						label = "Delete",
						onAction = function()
							table.insert(fired, item.id)
						end,
					},
				},
			}
		end
	end
	local list = virtual_list.build(LuauUI, core, spec)
	local screen = LuauUI.UI.Screen({ id = "S", children = { list.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	list.bindNativeScroll(handle.controller)

	local w: any = { core = core, adapter = adapter, pres = pres, list = list, handle = handle, fired = fired }
	function w.tick(dt: number)
		clockTime += dt
		pres.tick(dt)
		pres.refresh()
	end
	function w.settle(frames: number?)
		for _ = 1, frames or 90 do
			w.tick(FRAME)
		end
	end
	-- open `key` by a real swipe through the device seam, and let it settle
	function w.engage(key: string)
		local hit = rowHit(key)
		local rect = adapter.node(hit).rect
		local originX = rect.x + rect.w - 20
		local y = rect.y + rect.h / 2
		adapter.pointerDown(hit, originX, y, "mouse")
		w.tick(FRAME)
		adapter.pointerMove(originX - (LOCK + 2), y)
		w.tick(FRAME)
		adapter.pointerMove(originX - 80, y)
		w.tick(FRAME)
		adapter.pointerUp(originX - 80, y)
		w.settle()
	end
	--[[ ...and close it the way case (e) proves works: a one-pixel scroll through
		the shared coordinator. The coordinator closes on MOVEMENT, so each call
		scrolls one pixel FURTHER (re-driving the same position is not a scroll and
		would silently close nothing — the trap that makes a repeated-cycle test
		vacuous). Five pixels total never crosses the 40px pitch, so the mounted
		window — and therefore the path SET — is untouched by the scrolling. ]]
	local scrolled = 0
	function w.disengage()
		scrolled += 1
		adapter.driveScroll("/S/VL", { x = 0, y = scrolled })
		pres.refresh()
		w.settle()
	end
	function w.pathSet(): { [string]: boolean }
		local set: { [string]: boolean } = {}
		for _, path in adapter.paths() do
			set[path] = true
		end
		return set
	end
	return w
end

-- the paths in `b` that are not in `a`, sorted
local function extraPaths(a: { [string]: boolean }, b: { [string]: boolean }): { string }
	local out: { string } = {}
	for path in b do
		if a[path] == nil then
			table.insert(out, path)
		end
	end
	table.sort(out)
	return out
end

-- =============================================================================
describe("VirtualList rowActions: mount identity (the shipping differential)", function()
	it("a hosted list's mounted paths are the plain list's PLUS exactly the one overlay node", function()
		local plain, hosted = world(false), world(true)
		local a, b = plain.pathSet(), hosted.pathSet()
		-- nothing the plain list mounts is missing from the hosted one: hosting
		-- adds, it never rearranges (a rearranged row subtree would break every
		-- path a consumer, a theme selector or a test already depends on)
		expect(extraPaths(b, a)).toEqual({})
		-- ...and the hosted list adds ONE node for the WHOLE LIST — not one per
		-- row, which is the entire point of hosting the feature. At this window
		-- (12 mounted rows) that is ~0.08 nodes/row, and it does not grow with
		-- the list.
		expect(extraPaths(a, b)).toEqual({ OVERLAY })
		expect(hosted.adapter.liveCount() - plain.adapter.liveCount()).toBe(1)
	end)

	it("every shared path is the same CLASS at the same solved RECT", function()
		--[[ A path set can match while the tree still differs in the way that
			matters: one extra modifier, one different container class, one row
			solved a pixel narrower because a sibling took space. The identity claim
			is geometric, so it is checked geometrically — node for node, over every
			path the two worlds share. ]]
		local plain, hosted = world(false), world(true)
		local shared = 0
		for path in plain.pathSet() do
			local pn, hn = plain.adapter.node(path), hosted.adapter.node(path)
			expect(hn).never().toBeNil()
			expect(hn.class).toBe(pn.class)
			if pn.rect ~= nil then
				expect(hn.rect).never().toBeNil()
				expect(hn.rect.x).toBe(pn.rect.x)
				expect(hn.rect.y).toBe(pn.rect.y)
				expect(hn.rect.w).toBe(pn.rect.w)
				expect(hn.rect.h).toBe(pn.rect.h)
			end
			shared += 1
		end
		-- a real tree was compared, and ALL of it: every node the plain world holds
		expect(shared).toBe(plain.adapter.liveCount())
		expect(shared > 30).toBe(true)
		--[[ THE ONE DIFFERENCE INSIDE A ROW is behavioral, not structural: the
			shared four-function dispatcher rides the row `Hit` that already mounts.
			(The count that difference costs is the next case's business.) ]]
		expect(plain.adapter.node(rowHit("r1")).pointer).toBeNil()
		expect(hosted.adapter.node(rowHit("r1")).pointer).never().toBeNil()
	end)

	it("engaging and disengaging returns the tree to the closed shape, with zero instance leaks", function()
		--[[ THE LIFECYCLE HALF. A tray, its buttons, the presenter's synthesized
			outside-tap catcher and the row's presentation transform all come up on
			an engage; every one of them has to go away again. Five cycles, because
			a leak of one node per open is invisible in one. ]]
		local plain = world(false)
		local hosted = world(true)
		local closed = hosted.pathSet()
		local closedCount = hosted.adapter.liveCount()
		local closedHandlers = hosted.adapter.handlerCount()
		local closedRoots = hosted.adapter.rootCount()
		expect(extraPaths(plain.pathSet(), closed)).toEqual({ OVERLAY })

		for _ = 1, 5 do
			hosted.engage("r2")
			expect(hosted.list.engagedOffset:get() < 0).toBe(true)
			-- OPEN: the tray really is mounted (a closed-shape proof over a world
			-- where nothing ever opened would be vacuous)
			expect(hosted.adapter.liveCount() > closedCount).toBe(true)
			expect(hosted.adapter.node(`{OVERLAY}/[r2]/RowActionsTray`)).never().toBeNil()

			hosted.disengage()
			expect(hosted.list.engagedOffset:get()).toBe(0)
			-- CLOSED AGAIN, and the tree is the closed tree — path for path, not
			-- merely count for count (a leak that swapped one node for another
			-- would keep the count)
			local now = hosted.pathSet()
			expect(extraPaths(closed, now)).toEqual({})
			expect(extraPaths(now, closed)).toEqual({})
			expect(hosted.adapter.liveCount()).toBe(closedCount)
			-- ...and nothing the adapter HOLDS accumulated either: no orphaned
			-- pointer/activate handler (the census is the honest headless stand-in
			-- for engine connections), no leftover synthesized catcher root
			expect(hosted.adapter.handlerCount()).toBe(closedHandlers)
			expect(hosted.adapter.rootCount()).toBe(closedRoots)
			-- the row is untransformed again, exactly like one that never slid
			expect(hosted.adapter.node("/S/VL/Canvas/W/[r2]/Row").presentationOffset.x).toBe(0)
		end

		-- THE ENGINE IS KEPT — deliberately, and this is the line that says so:
		-- the claim of this file is about INSTANCES, and one cached engine for the
		-- one row the player actually swiped is the design (see the header).
		expect(hosted.list._hostedDebug().engineCount).toBe(1)
		expect(hosted.list._hostedDebug().engagedKey).toBeNil()
		-- ...and the closed hosted tree is STILL the plain tree plus the one node
		expect(extraPaths(plain.pathSet(), hosted.pathSet())).toEqual({ OVERLAY })
		expect(hosted.fired).toEqual({}) -- nothing committed through any of it
	end)

	it("the plain list is untouched by the feature existing (the control's own control)", function()
		--[[ The negative half of the differential, and the one a future change is
			most likely to break quietly: a plain list must mount NO overlay, no
			pointer handlers on its row hits, and no hosted bookkeeping. Asserted by
			SWEEPING the tree for the feature's own node name rather than at one
			expected path, so a rename cannot make it vacuously pass. ]]
		local plain = world(false)
		for _, path in plain.adapter.paths() do
			expect(string.find(path, "RowActions", 1, true)).toBeNil()
		end
		expect(plain.adapter.node(rowHit("r1")).pointer).toBeNil()
		expect(plain.list._hostedDebug().engineCount).toBe(0)
		expect(plain.list._hostedDebug().engagedKey).toBeNil()
		-- and it still scrolls and mounts its window like any other list
		plain.adapter.driveScroll("/S/VL", { x = 0, y = 400 })
		plain.pres.refresh()
		expect(plain.list.debugWindow().r11).toBe(true)
	end)
end)
