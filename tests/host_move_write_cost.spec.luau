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

	THE FOUR CASES ARE A CONTROL SET, not one claim. A host move must cost 1; an
	A/A re-apply must cost 0; a child that genuinely moves inside its host must
	still be written; and a node with NO host must still pay per-node, because
	there the absolute position really did change. Without the last two, "never
	write anything" would pass.
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
		local store: { [string]: any } = {}
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
