--!strict
--[[ WHAT ONE VISITED NODE COSTS THE Z WALK (Facet Plan D, D4b).

	`z_order.sync` is O(n - insertion point) BY DESIGN — the module's own header
	measures it and says why one monotone counter cannot do better ("a reorder
	renumbers FROM THE INSERTION POINT TO THE END OF THE PARENT"). D4 therefore
	attacks the CONSTANT and not the count: `stats.zVisits` is pinned UNMOVED in every
	case here, and what falls is what each of those visits does.

	THREE READINGS PER VISIT, AND TWO OF THEM WERE ANSWERABLE ONCE:

	1. `effectiveHitFloor(node.class, zMetrics)` decides whether the node RESERVES the
	   `z - 1` its expander is painted at. It is a pure function of the class and the
	   theme snapshot — `class_contract.forClass(class)` and
	   `metrics.targetSizes.minimum` — and `zMetrics` is read ONCE at the top of the
	   walk (the module already relies on that: a snapshot it has not seen forces a
	   whole-tree pass). So the answer is a function of the CLASS alone for the length
	   of one walk, and a surface with 7,505 nodes has six classes.

	2. `hitLift.touches(children)` returns `false` immediately when the lift set is
	   empty, and the lift set is empty on every surface with no hit expander — which
	   is every arena workload. The call was made once per container with two or more
	   children (1,465 on `war_room_inventory L`) to be told the same thing each time.

	3. `node.path` was re-read up to eleven times inside one visit. It is a string
	   field on an immutable node.

	None of this changes a number the engine is handed, which is why the LAST case here
	is a byte-equality of the WHOLE z assignment against a hand-written expectation
	rather than a count: the walk may get cheaper, it may not get different.

	MEASURED (FacetBench `attr war_room_inventory L`, arms paired, `zVisits` and
	`zPasses` identical on every arm): `st.ssZOrder` on `reorder` 3.05 -> 2.71 ms. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local z_order = require("../src/render/z_order")
-- `any` deliberately: the first case REPLACES `forClass` for one walk (and puts it
-- back), which is the only way to count the readings the walk makes — `z_order` binds
-- `effectiveHitFloor` itself at MODULE SCOPE, so patching THAT name proves nothing
-- (Plan D's own §D1 lesson about a wrap on a load-bound seam)
local contract: any = require("../src/class_contract")

type Node = { class: string, path: string, children: { Node } }

local function node(class: string, path: string, children: { any }?): any
	return { class = class, path = path, children = children or {} }
end

-- root
--   /S/a  HStack   -> Text /S/a/1, Text /S/a/2
--   /S/b  HStack   -> Button /S/b/1, Text /S/b/2
--   /S/c  Text
local function scene(): any
	return node("Screen", "/S", {
		node("HStack", "/S/a", { node("Text", "/S/a/1"), node("Text", "/S/a/2") }),
		node("HStack", "/S/b", { node("Button", "/S/b/1"), node("Text", "/S/b/2") }),
		node("Text", "/S/c"),
	})
end

local function paths(root: any): { string }
	local out: { string } = {}
	local function walk(n: any)
		table.insert(out, n.path)
		for _, k in n.children do
			walk(k)
		end
	end
	walk(root)
	return out
end

local function newHarness(liftAny: boolean)
	local root = scene()
	local handles: { [string]: any } = {}
	for _, p in paths(root) do
		handles[p] = { path = p }
	end
	local writes: { string } = {}
	local touchCalls = 0
	local orderCalls = 0
	local stats = { zPasses = 0, zVisits = 0, zMemoEntries = 0 }
	local deps = {
		adapter = {
			setZOrder = function(handle: any, z: number)
				table.insert(writes, `{handle.path}={z}`)
			end,
		},
		root = { node = root },
		handles = handles,
		lastZ = {},
		hitLift = {
			any = liftAny,
			touches = function(children: { any }): boolean
				touchCalls += 1
				return false
			end,
			order = function(children: { any }): { any }
				orderCalls += 1
				return children
			end,
		},
		metrics = function(): any
			return { targetSizes = { minimum = 44 } }
		end,
		stats = stats,
	}
	return {
		z = z_order.new(deps :: any),
		writes = writes,
		stats = stats,
		root = root,
		touches = function(): number
			return touchCalls
		end,
		orders = function(): number
			return orderCalls
		end,
	}
end

describe("z order: the per-visit constant (Plan D, D4b)", function()
	it("ASKS THE CONTRACT ONCE PER CLASS, NOT ONCE PER NODE", function()
		local h = newHarness(false)
		local real = contract.forClass
		local calls = 0
		contract.forClass = function(class: string): any
			calls += 1
			return real(class)
		end
		h.z.sync(nil)
		contract.forClass = real
		-- eight nodes, four classes (Screen, HStack, Text, Button), read off the run.
		-- Before D4 this read `forClass=8`.
		expect(`forClass={calls} visits={h.stats.zVisits} passes={h.stats.zPasses}`).toBe(
			"forClass=4 visits=8 passes=1"
		)
	end)

	it("DOES NOT ASK AN EMPTY LIFT SET WHETHER IT TOUCHES ANYTHING", function()
		local h = newHarness(false)
		h.z.sync(nil)
		-- three containers have two children each, so the old shape asked three times
		-- to be told `false` three times. Before D4 this read `touches=3`.
		expect(`touches={h.touches()} orders={h.orders()} visits={h.stats.zVisits}`).toBe("touches=0 orders=0 visits=8")
	end)

	it("...AND STILL ASKS IT WHEN THERE IS ONE — the skip is the empty set, not the question", function()
		local h = newHarness(true)
		h.z.sync(nil)
		expect(`touches={h.touches()} visits={h.stats.zVisits}`).toBe("touches=3 visits=8")
	end)

	it("...AND THE MEMO IT KEEPS IS THE SAME MEMO: the emptied container still gives its entry back", function()
		--[[ THE HOIST'S OWN REDDEN. The three `zIn[node.path]` reads in the tail became
			one `wasIn`, and `wasIn` is what decides whether a parent's entry is minted,
			left alone, or GIVEN BACK. The give-back is a correctness clause and not
			bookkeeping (this module's header: a container that empties keeps an entry
			from the last walk that saw its children and is later "skipped back onto a
			number it has not held for two walks"), so it is driven here as well as in
			`zorder_bounded.spec`, where the same mutation reddens two more cases. ]]
		local h = newHarness(false)
		h.z.sync(nil)
		-- three parents on this tree: /S, /S/a, /S/b. Leaves earn no entry.
		expect(`memo={h.stats.zMemoEntries}`).toBe("memo=3")
		h.root.children[1].children = {}
		h.z.sync(nil)
		expect(`memo={h.stats.zMemoEntries} visits={h.stats.zVisits}`).toBe("memo=2 visits=14")
	end)

	it("THE NUMBERS THE ENGINE IS HANDED ARE UNCHANGED, floor reservation included", function()
		local h = newHarness(false)
		h.z.sync(nil)
		--[[ Written out rather than derived, because a derivation would share the
			walk's own arithmetic. Document order, strictly increasing, and the ONE
			`Button` reserves the slot below itself for its expander — which is the
			memo's exactness claim: a per-class answer must still give `Button` a
			different one from the `Text` beside it. ]]
		expect(table.concat(h.writes, " ")).toBe("/S=1 /S/a=2 /S/a/1=3 /S/a/2=4 /S/b=5 /S/b/1=7 /S/b/2=8 /S/c=9")
	end)
end)
