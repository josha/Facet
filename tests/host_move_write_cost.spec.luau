--!strict
--[[ THE WRITE A HOST MAKES UNNECESSARY (the arrange half).

	THE BILL, AND WHERE IT IS ACTUALLY PAID. The nested tree's headline is that moving a
	container with 120 descendants costs 123 rect writes and 120 engine `Position`
	writes, with incremental layout skipping ZERO — "structurally defeated by the
	commonest layout event". Reproduced headlessly this round: grow a 20px header
	above a 120-node list and the renderer emits 142 rect writes, `lastSkipped = 0`.

	AND HERE IS THE FACT THAT MAKES THOSE WRITES WASTE. A `GuiObject.Position` is
	PARENT-RELATIVE. Measured on the same surface: when the list moves, 120 of 120
	descendants' ABSOLUTE positions change and 0 of 120 change relative to the
	list. So every one of those 120 engine writes stores the number that was
	already there.

	SO THE MECHANISM IS NOT "WRITE LESS", IT IS "KNOW WHAT YOU WROTE". `applyRect`
	already computes the exact pair it is about to write; it just never compared it
	to the pair it wrote last time. With no host above a node that comparison
	almost always differs and costs two number compares. Under a host that MOVED it
	always matches, and the 120-write bill becomes one write on the host.

	This is why the first arrange win needs no new instance, no new registration,
	and no elision cost: `ScrollView` is already a host on every list surface in
	the framework, so the saving lands on shipped code the day the compare lands.

	WHY THIS SPEC DRIVES THE REAL `applyRect` INSTEAD OF A MIRROR. `screen_target`
	cannot load headlessly, so its pins read it as text — but `screen_presentation`
	can (it reaches `UDim2` only inside functions), and `tests/lib/gui_value_shim`
	supplies the one constructor it needs. A mirror in the fake target could agree
	with itself while the shipped adapter did something else; this counts writes to
	the instances the shipped function actually assigns.

	THE SIX CONTROL CASES ARE A SET, not one claim. A host move must cost 1; an
	A/A re-apply must cost 0; a child that genuinely moves inside its host must
	still be written; a node with NO host must still pay per-node, because there
	the absolute position really did change; and a resize must still write Size.
	Without the last three, "never write anything" would pass.

	AND PLAN C's C1 ADDS THE OTHER HALF, ON THE SAME REAL `applyRect` (the second
	block below). The six above are the ABSOLUTE scheme: every rect the adapter is
	handed is in window space and `applyRect` subtracts the host origin itself. A
	COORDINATE-SPACE host is the one kind whose children arrive ALREADY relative —
	the solver stored them that way — so `applyRect` must subtract NOTHING, and the
	registry entry's `hostSpace` flag is the only thing that tells the two apart. A
	flag lost on a second `registerHost` call would land every child at
	`rect - host`, which is why the reuse-path OR has a case of its own. This is
	also the only spec in the tree that drives the SHIPPED `applyRect`; the fake
	target's mirror cannot see a divergence in it, which is exactly the lesson the
	fake's own subtree-recompose defect taught.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

require("./lib/gui_value_shim").install()
local screen_presentation = require("../src/client/screen_presentation")

-- an instance that counts the two properties `applyRect` claims, and nothing
-- else — the engine writes are the whole measurement
type Counter = { position: number, size: number }

local function newHarness()
	local handlesByPath: { [string]: any } = {}
	local region = screen_presentation.new({
		handlesByPath = handlesByPath,
		refitIconArt = function() end,
		ensureScale = function()
			return nil
		end,
	})
	local counts: Counter = { position = 0, size = 0 }
	local function node(path: string, rect: any): any
		-- A PROXY WITH ITS STORAGE OUTSIDE IT, and that detail is the instrument.
		-- The obvious spelling — `__newindex` plus `rawset(tbl, ...)` — counts a
		-- property exactly ONCE and then goes silent forever, because `__newindex`
		-- only fires for a key the table does not have yet. Written that way first,
		-- it reported 21 writes for the initial placement and 0 for every later
		-- pass, which is the answer this spec is trying to earn and would have
		-- passed the headline case while measuring nothing. Keeping the proxy empty
		-- keeps the hook live.
		local store: { [string]: any } = {
			IsA = function(_, class: string)
				return class == "GuiObject"
			end,
		}
		local instance = setmetatable({}, {
			__index = function(_, key)
				return store[key]
			end,
			__newindex = function(_, key, value)
				if key == "Position" then
					counts.position += 1
				elseif key == "Size" then
					counts.size += 1
				end
				store[key] = value
			end,
		})
		local handle = { path = path, instance = instance, windowRect = rect }
		handlesByPath[path] = handle
		return handle
	end
	return region, counts, node
end

-- 20 rows inside one host, laid out the way the solver lays them out: every rect
-- is in WINDOW space, which is the renderer's contract and the reason the naive
-- write looks necessary.
local function listInHost(region: any, node: any, hostY: number)
	local host = node("/S/List", { x = 0, y = hostY, w = 400, h = 800 })
	-- the entry is the ORIGIN every child re-bases against, and it is a record of
	-- its own — `adapter.setRect` re-points `entry.rect` when a host moves, before
	-- re-applying the children, and a test that forgot to would be measuring a
	-- subtree hanging off a stale origin
	host.hostEntry = region.registerHost("/S/List", host.instance, host.windowRect)
	local kids: { any } = {}
	for i = 1, 20 do
		local kid = node(`/S/List/Row{i}`, { x = 0, y = hostY + (i - 1) * 40, w = 400, h = 40 })
		kid.instanceHost = region.hostFor(kid.path)
		table.insert(kids, kid)
	end
	return host, kids
end

-- what the solver does when everything above the list grows by `dy`: every rect
-- in the subtree is re-issued in WINDOW space, the host's included
local function shiftAll(host: any, kids: { any }, dy: number)
	host.windowRect = { x = host.windowRect.x, y = host.windowRect.y + dy, w = 400, h = 800 }
	host.hostEntry.rect = host.windowRect
	for _, kid in kids do
		kid.windowRect = { x = kid.windowRect.x, y = kid.windowRect.y + dy, w = 400, h = 40 }
	end
end

describe("a host that moves costs ONE engine write, not one per descendant", function()
	it("a subpixel animation tail reaches the resting pixel before its transform clears", function()
		local region, counts, node = newHarness()
		local handle = node("/S/Puck", { x = 341, y = 40, w = 40, h = 76 })
		for _, direction in { -1, 1 } do
			region.setTransform(handle, { x = 1.6 * direction, y = 1.6 * direction, w = -1.6, h = -1.6 })
			expect(handle.instance.Position.x).toBe(341 + 2 * direction)
			expect(handle.instance.Size.y).toBe(74)
			region.setTransform(handle, { x = 0.01 * direction, y = 0.01 * direction, w = -0.01, h = -0.01 })
			expect(handle.instance.Position.x).toBe(341)
			expect(handle.instance.Position.y).toBe(40)
			expect(handle.instance.Size.x).toBe(40)
			expect(handle.instance.Size.y).toBe(76)
			counts.position, counts.size = 0, 0
			region.setTransform(handle, nil)
			expect(counts.position).toBe(0)
			expect(counts.size).toBe(0)
		end
	end)

	it("the control: placing the surface writes every node exactly once", function()
		local region, counts, node = newHarness()
		local host, kids = listInHost(region, node, 20)
		region.applyRect(host)
		for _, kid in kids do
			region.applyRect(kid)
		end
		expect(counts.position).toBe(21)
		-- and the geometry is right: a child re-based against its host, not the window
		expect((kids[1].instance :: any).Position.y).toBe(0)
		expect((kids[3].instance :: any).Position.y).toBe(80)
	end)

	it("A/A: re-applying the SAME rects writes nothing at all", function()
		local region, counts, node = newHarness()
		local host, kids = listInHost(region, node, 20)
		region.applyRect(host)
		for _, kid in kids do
			region.applyRect(kid)
		end
		counts.position, counts.size = 0, 0
		region.applyRect(host)
		for _, kid in kids do
			region.applyRect(kid)
		end
		-- nothing moved, so nothing is stored again. This is the control that says
		-- the compare is a compare and not a coincidence of the move case.
		expect(counts.position).toBe(0)
		expect(counts.size).toBe(0)
	end)

	it("THE BILL: the whole list moves 40px and ONE Position is written", function()
		local region, counts, node = newHarness()
		local host, kids = listInHost(region, node, 20)
		region.applyRect(host)
		for _, kid in kids do
			region.applyRect(kid)
		end
		counts.position, counts.size = 0, 0

		shiftAll(host, kids, 40)
		region.applyRect(host)
		for _, kid in kids do
			region.applyRect(kid)
		end

		-- the host's own instance moved; its 20 descendants did not, because a
		-- Position is parent-relative and the engine carries them
		expect(counts.position).toBe(1)
		expect(counts.size).toBe(0)
		-- ...and they are still in the right place
		expect((host.instance :: any).Position.y).toBe(60)
		expect((kids[3].instance :: any).Position.y).toBe(80)
	end)

	it("NEGATIVE CONTROL: a child that really moves inside its host is still written", function()
		local region, counts, node = newHarness()
		local host, kids = listInHost(region, node, 20)
		region.applyRect(host)
		for _, kid in kids do
			region.applyRect(kid)
		end
		counts.position = 0

		-- row 5 alone slides right: relative to the host that IS a change
		kids[5].windowRect = { x = 12, y = kids[5].windowRect.y, w = 400, h = 40 }
		for _, kid in kids do
			region.applyRect(kid)
		end
		expect(counts.position).toBe(1)
		expect((kids[5].instance :: any).Position.x).toBe(12)
	end)

	it("NEGATIVE CONTROL: with no host above them, moving nodes pays per node", function()
		local region, counts, node = newHarness()
		-- same 20 nodes, no registration: they are flat under the root, so their
		-- absolute positions really did change and every write is necessary
		local kids: { any } = {}
		for i = 1, 20 do
			table.insert(kids, node(`/S/List/Row{i}`, { x = 0, y = (i - 1) * 40, w = 400, h = 40 }))
		end
		for _, kid in kids do
			region.applyRect(kid)
		end
		counts.position = 0
		for _, kid in kids do
			kid.windowRect = { x = 0, y = kid.windowRect.y + 40, w = 400, h = 40 }
			region.applyRect(kid)
		end
		expect(counts.position).toBe(20)
	end)

	it("a RESIZE still writes Size, and only Size", function()
		local region, counts, node = newHarness()
		local host, kids = listInHost(region, node, 20)
		region.applyRect(host)
		for _, kid in kids do
			region.applyRect(kid)
		end
		counts.position, counts.size = 0, 0
		kids[2].windowRect = { x = 0, y = kids[2].windowRect.y, w = 400, h = 64 }
		region.applyRect(kids[2])
		expect(counts.size).toBe(1)
		expect(counts.position).toBe(0)
	end)
end)

--[[ THE COORDINATE-SPACE SCHEME (Plan C, C1), on the same shipped `applyRect`.

	Three fixtures, each pinning the per-node engine `Position` the real adapter
	writes and the T0 write counter beside it:
	  1. a space host whose 20 children carry HOST-RELATIVE rects — a move is one
	     write, and every child's engine Position is its stored rect UNCHANGED
	     (nothing is subtracted, because the solver already did);
	  2. a space host inside a space host — the inner host's own rect is relative
	     to the outer, so moving the outer is still ONE write;
	  3. the mixed pair: a space host inside a SCROLL host (whose children are
	     absolute in the scroll host's space) and a scroll host inside a space host.
	     This is where a rule that treated all hosts alike goes wrong in both
	     directions at once. ]]
local function spaceHost(region: any, node: any, path: string, rect: any, parent: any?): any
	local host = node(path, rect)
	host.instanceHost = if parent ~= nil then region.hostFor(path) else nil
	host.hostEntry = region.registerHost(path, host.instance, host.windowRect, false, true)
	return host
end

describe("Plan C: a COORDINATE-SPACE host subtracts nothing, and the flag is what says so", function()
	it("fixture 1: the children's stored rects ARE their engine positions, and a move writes one", function()
		local region, counts, node = newHarness()
		local host = spaceHost(region, node, "/S/List", { x = 30, y = 20, w = 400, h = 800 })
		local kids: { any } = {}
		for i = 1, 20 do
			-- HOST-RELATIVE, which is the whole difference from `listInHost` above
			local kid = node(`/S/List/Row{i}`, { x = 0, y = (i - 1) * 40, w = 400, h = 40 })
			kid.instanceHost = region.hostFor(kid.path)
			table.insert(kids, kid)
		end
		region.applyRect(host)
		for _, kid in kids do
			region.applyRect(kid)
		end
		expect(counts.position).toBe(21)
		-- NOTHING SUBTRACTED: row 3's engine Position is its stored rect
		expect(`{(kids[3].instance :: any).Position.x},{(kids[3].instance :: any).Position.y}`).toBe("0,80")
		expect(`{(host.instance :: any).Position.x},{(host.instance :: any).Position.y}`).toBe("30,20")

		-- ...and the move: only the host's rect changes, because nothing beneath it
		-- moved in its own space
		counts.position, counts.size = 0, 0
		host.windowRect = { x = 30, y = 260, w = 400, h = 800 }
		host.hostEntry.rect = host.windowRect
		region.applyRect(host)
		for _, kid in kids do
			region.applyRect(kid)
		end
		expect(`position={counts.position} size={counts.size}`).toBe("position=1 size=0")
		expect((kids[3].instance :: any).Position.y).toBe(80)
	end)

	it("fixture 2: a space host inside a space host is still one write", function()
		local region, counts, node = newHarness()
		local outer = spaceHost(region, node, "/S/Outer", { x = 10, y = 10, w = 400, h = 800 })
		-- the inner host's own rect is relative to the OUTER, which is what makes
		-- the chain compose rather than accumulate twice
		local inner = spaceHost(region, node, "/S/Outer/Inner", { x = 5, y = 50, w = 300, h = 200 }, outer)
		local kid = node("/S/Outer/Inner/Leaf", { x = 2, y = 4, w = 100, h = 20 })
		kid.instanceHost = region.hostFor(kid.path)
		region.applyRect(outer)
		region.applyRect(inner)
		region.applyRect(kid)
		expect(`outer={(outer.instance :: any).Position.x},{(outer.instance :: any).Position.y}`).toBe("outer=10,10")
		expect(`inner={(inner.instance :: any).Position.x},{(inner.instance :: any).Position.y}`).toBe("inner=5,50")
		expect(`leaf={(kid.instance :: any).Position.x},{(kid.instance :: any).Position.y}`).toBe("leaf=2,4")

		counts.position = 0
		outer.windowRect = { x = 90, y = 10, w = 400, h = 800 }
		outer.hostEntry.rect = outer.windowRect
		region.applyRect(outer)
		region.applyRect(inner)
		region.applyRect(kid)
		expect(counts.position).toBe(1)
	end)

	it("fixture 3: a space host under a scroll host, and a scroll host under a space host", function()
		local region, counts, node = newHarness()
		-- (a) an ABSOLUTE-scheme host (a scroll/clip host) holding a space host
		local scroll = node("/S/Scroll", { x = 0, y = 100, w = 400, h = 300 })
		scroll.hostEntry = region.registerHost("/S/Scroll", scroll.instance, scroll.windowRect, true)
		local moving = node("/S/Scroll/Moving", { x = 40, y = 160, w = 200, h = 100 })
		moving.instanceHost = region.hostFor(moving.path)
		moving.hostEntry = region.registerHost("/S/Scroll/Moving", moving.instance, moving.windowRect, false, true)
		local inMoving = node("/S/Scroll/Moving/Leaf", { x = 3, y = 6, w = 50, h = 20 })
		inMoving.instanceHost = region.hostFor(inMoving.path)
		-- (b) a space host holding a scroll host, whose own children are absolute in
		-- the SCROLL host's space
		local space = node("/S/Space", { x = 8, y = 12, w = 400, h = 300 })
		space.hostEntry = region.registerHost("/S/Space", space.instance, space.windowRect, false, true)
		local innerScroll = node("/S/Space/List", { x = 0, y = 30, w = 400, h = 200 })
		innerScroll.instanceHost = region.hostFor(innerScroll.path)
		innerScroll.hostEntry = region.registerHost("/S/Space/List", innerScroll.instance, innerScroll.windowRect, true)
		local row = node("/S/Space/List/Row", { x = 0, y = 90, w = 400, h = 40 })
		row.instanceHost = region.hostFor(row.path)
		for _, h in { scroll, moving, inMoving, space, innerScroll, row } do
			region.applyRect(h)
		end
		-- (a) `moving` is a child of an ABSOLUTE host, so its own rect IS re-based;
		-- its own child is not, because `moving` is a coordinate space
		expect(`moving={(moving.instance :: any).Position.x},{(moving.instance :: any).Position.y}`).toBe(
			"moving=40,60"
		)
		expect(`leaf={(inMoving.instance :: any).Position.x},{(inMoving.instance :: any).Position.y}`).toBe("leaf=3,6")
		-- (b) the scroll host under a space host takes its rect as given, and ITS
		-- child is re-based against it in the ordinary way
		expect(`list={(innerScroll.instance :: any).Position.x},{(innerScroll.instance :: any).Position.y}`).toBe(
			"list=0,30"
		)
		expect(`row={(row.instance :: any).Position.x},{(row.instance :: any).Position.y}`).toBe("row=0,60")

		-- ...and moving the space host writes ONE, while moving the scroll host
		-- writes one per child it re-bases (its children are absolute)
		counts.position = 0
		space.windowRect = { x = 8, y = 212, w = 400, h = 300 }
		space.hostEntry.rect = space.windowRect
		region.applyRect(space)
		region.applyRect(innerScroll)
		region.applyRect(row)
		expect(`spaceMove={counts.position}`).toBe("spaceMove=1")
	end)

	it("a DOUBLE registerHost keeps hostSpace, in either order", function()
		--[[ `registerHost` is create-or-REUSE and the reuse path returns early. A path
			can be registered twice — the adapter's own ScrollView/`clipChildren`
			trigger, then `createOpts.instanceHost` — and if the flag were lost on the
			second call `applyRect` would subtract the host rect from children whose
			rects are already relative, landing every one at `rect - host`. ]]
		local region, _counts, node = newHarness()
		local a = node("/S/A", { x = 0, y = 0, w = 10, h = 10 })
		local first = region.registerHost("/S/A", a.instance, a.windowRect, false, true)
		local second = region.registerHost("/S/A", a.instance, a.windowRect, true, nil)
		expect(`same={first == second} space={tostring(second.hostSpace)} crops={tostring(second.crops)}`).toBe(
			"same=true space=true crops=true"
		)
		local b = node("/S/B", { x = 0, y = 0, w = 10, h = 10 })
		local one = region.registerHost("/S/B", b.instance, b.windowRect, true, nil)
		local two = region.registerHost("/S/B", b.instance, b.windowRect, false, true)
		expect(`same={one == two} space={tostring(two.hostSpace)} crops={tostring(two.crops)}`).toBe(
			"same=true space=true crops=true"
		)
	end)
end)
