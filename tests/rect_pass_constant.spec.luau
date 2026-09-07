--!strict
--[[ WHAT ONE APPLIED RECT COSTS BESIDES THE WRITE (Facet Plan D, D4).

	`rect_pass.applyOne` runs once per rect the commit applies, and on
	`war_room_inventory L reorder` that is 7,335 times for one gesture. Everything in
	its body that is not the adapter call is therefore multiplied by 7,335, and D4's
	measurement said what the multiplier is worth: with the arena's fake target split
	out of the span (FacetBench `target.setRect`, §D4a), Facet's OWN share of
	`rectPass.apply` is 2.63 ms of a 12.4 ms span — and the `authority.assertWrite`
	call alone was 0.24 of that.

	THE ASSERT IS NOT REMOVED, IT IS ASKED ONCE. `authority.assertWrite("common",
	"size", "layout")` takes three STRING LITERALS. Its answer is
	`MANIFEST.common.size`, a table built at module load and never written after it,
	so the call cannot give two answers inside one `apply` — or inside one session.
	Hoisting it to the top of `apply` keeps the claim ("the layout writer owns
	`common.size`, and this pass is the layout writer") and stops paying for it per
	row.

	IT ALSO BECOMES STRICTLY MORE EAGER, which is the direction that costs nothing:
	before, a commit that applied no rect at all asserted nothing; now every `apply`
	asserts, whether or not a write follows. A manifest that stopped granting the
	layout writer `common.size` used to throw on the first commit that MOVED
	something and now throws on the first commit.

	THE TWO CASES ARE A PAIR AND NEITHER IS THE OTHER'S CONTROL. The first drives a
	WRONG-OWNER manifest through `apply` and demands the throw — it is red if the
	assert is deleted rather than moved, and it does not care where the call sits. The
	second counts the calls and is red if the call goes back inside the loop. Before
	this file the tree had NO case that drove the write authority through this module
	at all: `tests/foreign.spec` pins `assertWrite` for `Foreign.Parent`, and the
	`authorityFor` pins elsewhere read the manifest without ever entering `rect_pass`.
 ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local rect_pass = require("../src/render/rect_pass")
-- `any` deliberately: these cases REPLACE `authorityFor` for the length of one
-- `apply` (and put it back), which is the only way to drive a wrong-owner manifest
-- through the shipped assert without a second manifest
local authority: any = require("../src/render/authority")

type Rect = { x: number, y: number, w: number, h: number }

-- the smallest ctx `rect_pass.new` documents, with every seam a recorder
local function newHarness(nodes: { string })
	local root: any = { path = "/S", children = {} }
	local rects: { [string]: any } = { ["/S"] = { rect = { x = 0, y = 0, w = 100, h = 100 } } }
	for i, p in nodes do
		local child: any = { path = p, children = {} }
		table.insert(root.children, child)
		rects[p] = { rect = { x = 0, y = i * 10, w = 100, h = 10 } }
	end
	local handles: { [string]: any } = { ["/S"] = { path = "/S" } }
	for _, p in nodes do
		handles[p] = { path = p }
	end
	local written: { string } = {}
	local lastRects: { [string]: any } = {}
	local lastBarInsets: { [string]: any } = {}
	local stats = { rectWrites = 0, lastCommitVisits = 0, lastCommitVisitsByWalk = {} }
	local ctx = {
		adapter = {
			setRect = function(handle: any, rect: Rect)
				table.insert(written, handle.path)
			end,
		},
		handles = handles,
		lastRects = lastRects,
		lastBarInsets = lastBarInsets,
		stats = stats,
		rectsEqual = function(a: any, b: any): boolean
			if a == nil or b == nil then
				return a == b
			end
			return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
		end,
		scope = {
			armed = function(): boolean
				return false
			end,
			records = function(): boolean
				return false
			end,
			skip = function(): boolean
				return false
			end,
			note = function() end,
			noteEntry = function() end,
			descendOf = function(node: any): { any }
				return node.children
			end,
			publishVisits = function() end,
		},
	}
	return {
		pass = rect_pass.new(ctx),
		root = root,
		rects = rects,
		written = written,
		lastRects = lastRects,
		lastBarInsets = lastBarInsets,
		stats = stats,
	}
end

describe("rect pass: the per-row constant (Plan D, D4)", function()
	it("STILL ASSERTS THE WRITE AUTHORITY: a wrong-owner manifest throws out of `apply`", function()
		local h = newHarness({ "/S/a", "/S/b" })
		-- a WRONG OWNER for the one pair this pass claims, and nothing else. The
		-- patch is on the module member `assertWrite` itself looks up, so it is the
		-- SHIPPED assert that reads it.
		local real = authority.authorityFor
		authority.authorityFor = function(class: string, prop: string): any
			if class == "common" and prop == "size" then
				return "style"
			end
			return real(class, prop)
		end
		local ok, err = pcall(function()
			h.pass.apply(h.root, h.rects, nil)
		end)
		authority.authorityFor = real
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "owned by style") ~= nil).toBe(true)
		-- ...and nothing reached the adapter behind the refusal. This case is the
		-- SAFETY half and shares no switch with the hoist: it is red only if the
		-- claim is DELETED rather than moved, and it read the same before D4.
		expect(`written={#h.written}`).toBe("written=0")
	end)

	it("ASKS ONCE PER `apply`, NOT ONCE PER ROW: four rects, one authority lookup", function()
		local h = newHarness({ "/S/a", "/S/b", "/S/c" })
		local real = authority.authorityFor
		local calls = 0
		authority.authorityFor = function(class: string, prop: string): any
			if class == "common" and prop == "size" then
				calls += 1
			end
			return real(class, prop)
		end
		h.pass.apply(h.root, h.rects, nil)
		authority.authorityFor = real
		-- read off the run: four rects land (the root and its three children) and the
		-- claim is asked once. Before D4 this read `lookups=4`.
		expect(`lookups={calls} written={#h.written}`).toBe("lookups=1 written=4")
	end)
end)
