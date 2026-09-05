--!strict
--[[ T12 (Plan C levers) — THE HEADLESS TARGET STOPS BEING THE MEASUREMENT.

	Two charges, measured (T9b §2.4, §2.6): (1) `fake_target.setRect` built a
	formatted op-log string on EVERY write, whether or not any spec ever reads it
	back — 1.40 us/write, 10.28 of `war_room_inventory L reorder`'s 30.9 ms; (2) a
	coordinate-space host's move found its subtree by scanning the WHOLE `nodes`
	map with a `string.sub` prefix test — O(hosts x nodes), 21.3 of `nameplates L
	updateItems-plates`'s 24.0 ms, against a LIVE cost of 2.876 ms. Neither charge
	is a Facet defect: this file is a TEST DOUBLE, not shipped, and the instrument
	was billing the framework for its own bookkeeping.

	This spec is the oracle for both fixes: `ops` is opt-in
	(`fake_target.new({ ops = true })`, `adapter.ops()` refuses when unarmed), and
	the host-move recompose walks a parent->children index instead of the map.
	Every OTHER standing suite that runs on this adapter (`host_space_oracle`,
	`translate_arm`, `commit_scope`, `structural_scope`, `nested_tree_pins`, …) is
	this task's differential oracle for "did the composed rects change" — this
	file's own job is narrower: pin the SET the old scan recomposed (three
	fixtures), pin that the index reproduces it, and pin that the log really
	costs nothing when nobody asked for it. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fake_target = require("./lib/fake_target")
local scene = require("./lib/nameplates_scene")
local fs = require("@lune/fs")

-- ===== STEP 1/2: THE OP LOG IS OPT-IN =====================================

describe("T12: the op log is opt-in", function()
	it("a target built without ops refuses adapter.ops rather than answering empty", function()
		-- RED at HEAD: `ops()` used to return `{}` unconditionally, so a spec that
		-- forgot to arm a fixture would read a silently-empty log rather than
		-- learning it built the wrong adapter.
		local adapter = fake_target.new()
		expect(function()
			(adapter :: any).ops()
		end).toThrow()
	end)

	it("an armed target answers the log; an unarmed one still refuses after writes", function()
		local armed = fake_target.new({ ops = true })
		local root = armed.createRoot("S")
		armed.create(root, "/S/A", "Box", nil, nil)
		expect(#armed.ops() > 0).toBe(true)

		local unarmed = fake_target.new()
		local root2 = unarmed.createRoot("S")
		unarmed.create(root2, "/S/A", "Box", nil, nil)
		expect(function()
			(unarmed :: any).ops()
		end).toThrow()
	end)

	--[[ SOURCE SCAN, not behaviour: the cost this task closes is CPU spent
		building a string nobody reads, which only a read of the source can prove
		is gone from every one of the 22 sites and not just the two this file's
		other cases happen to exercise. ]]
	it("SOURCE SCAN: every note() write is opt-in, and note() itself is the only table.insert(ops", function()
		local source = fs.readFile("tests/lib/fake_target.luau")
		local lines = string.split(source, "\n")

		local rawInserts = 0
		local guardedNotes = 0
		-- track whole-line `--[[ ... ]]` block comments (this file's header/rulings
		-- prose mentions `note(` by name several times) so prose is never mistaken
		-- for a call site
		local inBlockComment = false
		for i, line in lines do
			-- a line that OPENS a block comment is itself prose (this file's own
			-- header opens on the exact line that names `table.insert(ops, …)` as
			-- an example), so the exclusion covers both the open and the inside
			local opensBlockComment = not inBlockComment
				and string.find(line, "%-%-%[%[") ~= nil
				and string.find(line, "%]%]") == nil
			local isInComment = inBlockComment or opensBlockComment
			if opensBlockComment then
				inBlockComment = true
			elseif inBlockComment and string.find(line, "%]%]") ~= nil then
				inBlockComment = false
			end
			local isLineComment = string.match(line, "^%s*%-%-") ~= nil
			isInComment = isInComment or isLineComment
			if not isInComment and string.match(line, "table%.insert%(ops,") ~= nil then
				rawInserts += 1
				-- the ONLY legal raw insert is `note`'s own body, immediately under
				-- its declaration — every call SITE must go through the guard instead
				expect(string.find(lines[i - 1] or "", "local function note", 1, true) ~= nil).toBe(true)
			elseif
				not isInComment
				and string.match(line, "note%(") ~= nil
				and string.find(line, "local function note", 1, true) == nil
			then
				guardedNotes += 1
				--[[ THE INTERPOLATION IS INSIDE THE GUARD: a `note(...)` call that is
					not lexically nested in `if recordOps then ... end` would still pay
					to build the string before throwing it away. stylua reflows every
					one of these 22 sites to its own three-line shape — a single-line
					`if recordOps then note(...) end` does not survive `--check` at this
					width — so the pin reads the call's OWN line plus its immediate
					neighbours rather than demanding one physical line.

					AND THE ARGUMENT ITSELF MUST BE THE LITERAL, not a local built one
					line earlier: `note(mutation4Line)` would satisfy a bare
					`note%(.*%)` shape while the string it hands over was interpolated
					OUTSIDE the guard, on the very line above `if recordOps then` — the
					cost this task closes, back again through a one-line hoist. So the
					argument must itself start with a backtick or a quote. ]]
				expect(
					string.match(line, "^%s*note%(`.*`%)%s*$") ~= nil
						or string.match(line, '^%s*note%("[^"]*"%)%s*$') ~= nil
				).toBe(true)
				expect(string.match(lines[i - 1] or "", "^%s*if recordOps then%s*$") ~= nil).toBe(true)
				expect(string.match(lines[i + 1] or "", "^%s*end%s*$") ~= nil).toBe(true)
			end
		end
		expect(rawInserts).toBe(1)
		expect(guardedNotes).toBe(22)
	end)

	--[[ THE INDEX SITES, enumerated rather than merely counted (review MUST-FIX
		1 — a bare count equality is false by construction here: 2 index sites for
		2 `nodes[x] = v` writes MINUS the adopt exception, 3 unindex sites for the
		3 deletes). Sliced by function body so a call landing in the WRONG
		function cannot hide behind a whole-file total. ]]
	it("SOURCE SCAN: indexNode/unindexNode sit exactly where the ruling puts them", function()
		local source = fs.readFile("tests/lib/fake_target.luau")

		local function sliceFunction(startPat: string, endPat: string): string
			local a = string.find(source, startPat, 1, true)
			assert(a ~= nil, `function start not found: {startPat}`)
			local b = string.find(source, endPat, (a :: number) + 1, true)
			assert(b ~= nil, `function end not found: {endPat}`)
			return string.sub(source, a :: number, (b :: number) - 1)
		end
		local function countOf(hay: string, needle: string): number
			local n = 0
			local at = 1
			while true do
				local found = string.find(hay, needle, at, true)
				if found == nil then
					break
				end
				n += 1
				at = found + 1
			end
			return n
		end
		-- `"indexNode("` is a SUBSTRING of `"unindexNode("`, so a raw count of the
		-- former also counts every occurrence of the latter — subtract them out.
		local function indexNodeCount(hay: string): number
			return countOf(hay, "indexNode(") - countOf(hay, "unindexNode(")
		end
		local function unindexNodeCount(hay: string): number
			return countOf(hay, "unindexNode(")
		end

		local createBody = sliceFunction("function adapter.create(", "function adapter._composePresentation(")
		local adoptBody = sliceFunction("function adapter.adopt(", "function adapter.discardParked(")
		local removeBody = sliceFunction("function adapter.remove(", "-- ---- instance recycling")
		local parkBody = sliceFunction("function adapter.park(", "function adapter.adopt(")
		local destroyRootBody = sliceFunction("function adapter.destroyRoot(", "function adapter.setActivateHandler(")

		-- CREATE: indexes the new key, unindexes nothing
		expect(indexNodeCount(createBody)).toBe(1)
		expect(unindexNodeCount(createBody)).toBe(0)
		-- ADOPT: indexes the NEW key; the OLD key is left in place on purpose
		-- (ruling: match today's behaviour, which never deletes it here either)
		expect(indexNodeCount(adoptBody)).toBe(1)
		expect(unindexNodeCount(adoptBody)).toBe(0)
		-- REMOVE, PARK, DESTROYROOT: the three real deletes, each unindexed
		expect(unindexNodeCount(removeBody)).toBe(1)
		expect(indexNodeCount(removeBody)).toBe(0)
		expect(unindexNodeCount(parkBody)).toBe(1)
		expect(indexNodeCount(parkBody)).toBe(0)
		expect(unindexNodeCount(destroyRootBody)).toBe(1)
		expect(indexNodeCount(destroyRootBody)).toBe(0)
	end)
end)

-- ===== STEP 1/3: THE CHARACTERISATION PIN ==================================
--[[ A pin labelled as such (review SHOULD-FIX 6): it passes at HEAD because the
	prefix walk IS the implementation, and it exists to freeze the set before
	that walk is re-derived off an index. Three fixtures, built with the raw
	adapter (no renderer, no mount) so the host chain and the path strings can be
	pulled apart on purpose the way `instance_recycling.spec`'s own low-level
	cases do. ]]

describe("T12: a coordinate-space host move recomposes exactly the descendants the prefix scan did", function()
	it("fixture (a): a 3-deep host chain recomposes every level, offsets accumulating", function()
		local adapter = fake_target.new() :: any
		local root = adapter.createRoot("S")
		local hostA = adapter.create(root, "/S/A", "VStack", nil, { instanceHost = true, hostSpace = true })
		adapter.setRect(hostA, { x = 5, y = 5, w = 300, h = 300 })
		local hostB = adapter.create(root, "/S/A/B", "VStack", nil, { instanceHost = true, hostSpace = true })
		adapter.setRect(hostB, { x = 10, y = 10, w = 100, h = 100 })
		local leaf = adapter.create(root, "/S/A/B/Leaf", "Box", nil, nil)
		adapter.setRect(leaf, { x = 2, y = 2, w = 10, h = 10 })

		-- BEFORE the move: B composes at hostA's origin, Leaf at both origins
		expect(adapter.composedRect("/S/A/B")).toEqual({ x = 15, y = 15, w = 100, h = 100 })
		expect(adapter.composedRect("/S/A/B/Leaf")).toEqual({ x = 17, y = 17, w = 10, h = 10 })

		adapter.setRect(hostA, { x = 50, y = 60, w = 300, h = 300 })

		-- AFTER: both descendants re-based off hostA's NEW rect, without either
		-- one taking its own `setRect` call — the whole point of the lane
		expect(adapter.composedRect("/S/A/B")).toEqual({ x = 60, y = 70, w = 100, h = 100 })
		expect(adapter.composedRect("/S/A/B/Leaf")).toEqual({ x = 62, y = 72, w = 10, h = 10 })
	end)

	it("fixture (b): a path-prefix sibling that is NOT a child is never touched", function()
		--[[ `/S/Host2/Leaf` carries `/S/Host` as a bare STRING prefix but is not
			beneath it — the trailing `/` is the whole of the semantics
			(`/S/Host` vs `/S/Host2/`). A bare-prefix index would silently widen
			the rule and recompose a sibling subtree it has no business touching.

			THE VALUE ALONE CANNOT CATCH THIS (measured: a bare-prefix mutation
			here left the composed rect byte-equal, because `spaceOriginOf` reads
			`handle.instanceHost` — an object reference built by `hostFor`, which
			is untouched by `childrenOf` — never the index this fixture pins. A
			sibling wrongly swept into the walk still recomposes to the SAME
			number it already had. So this counts VISITS, the fact a widened
			index actually changes, via the same `_composePresentation` wrap the
			bound case below uses. ]]
		local adapter = fake_target.new() :: any
		local root = adapter.createRoot("S")
		local host = adapter.create(root, "/S/Host", "VStack", nil, { instanceHost = true, hostSpace = true })
		adapter.setRect(host, { x = 0, y = 0, w = 100, h = 100 })
		local other = adapter.create(root, "/S/Host2", "VStack", nil, nil)
		adapter.setRect(other, { x = 1, y = 1, w = 50, h = 50 })
		local leaf = adapter.create(root, "/S/Host2/Leaf", "Box", nil, nil)
		adapter.setRect(leaf, { x = 1, y = 1, w = 5, h = 5 })

		expect(adapter.composedRect("/S/Host2/Leaf")).toEqual({ x = 1, y = 1, w = 5, h = 5 })

		local visited: { [string]: boolean } = {}
		local original = adapter._composePresentation
		adapter._composePresentation = function(node: any)
			visited[node.path] = true
			return original(node)
		end

		adapter.setRect(host, { x = 99, y = 99, w = 100, h = 100 })

		-- unaffected: neither today's prefix walk nor the index has any business
		-- reaching a node whose real parent is `/S/Host2`, not `/S/Host`
		expect(adapter.composedRect("/S/Host2/Leaf")).toEqual({ x = 1, y = 1, w = 5, h = 5 })
		expect(visited["/S/Host2"] == true).toBe(false)
		expect(visited["/S/Host2/Leaf"] == true).toBe(false)
		expect(visited["/S/Host"] == true).toBe(true) -- non-vacuous: the host itself DID recompose
	end)

	--[[ fixture (c): AN ADOPT RE-KEY (review MUST-FIX 2/3, and the T12
		correction that overrides the brief's self-contradicting `:271-275`
		region): `adopt` indexes the NEW key and leaves the OLD one exactly as
		today's `nodes` map does — neither is deleted here. A recycled node that
		lands under the SAME coordinate-space host, at a path the index has never
		seen before, must still be found by the NEXT host move — which only
		happens because `indexNode` runs at adopt's new-key site. Removing that
		call (mutation 3, Step 5) reddens this case: the node would silently stop
		moving with its host, the exact "instrument reading an unreal surface"
		trap this whole task exists to close. ]]
	it("fixture (c): a node PARKED and ADOPTED to a new path stays reachable through its host's move", function()
		local adapter = fake_target.new() :: any
		local root = adapter.createRoot("S")
		local host = adapter.create(root, "/S/Host", "VStack", nil, { instanceHost = true, hostSpace = true })
		adapter.setRect(host, { x = 0, y = 0, w = 300, h = 300 })
		local leaf1 = adapter.create(root, "/S/Host/Leaf1", "Box", nil, nil)
		adapter.setRect(leaf1, { x = 10, y = 10, w = 20, h = 20 })

		expect(adapter.park(leaf1)).toBe(true)
		-- the OLD key answers nothing: `park` really did delete it (the
		-- correction is about `adopt`'s OWN code never deleting anything, not
		-- about a reachable stale `nodes` entry surviving the ordinary
		-- park -> adopt flow)
		expect(adapter.node("/S/Host/Leaf1")).toBeNil()

		expect(adapter.adopt(leaf1, "/S/Host/Leaf2", "Box", nil, root, nil)).toBe(true)
		adapter.setRect(leaf1, { x = 15, y = 25, w = 12, h = 12 })
		expect(adapter.composedRect("/S/Host/Leaf2")).toEqual({ x = 15, y = 25, w = 12, h = 12 })

		adapter.setRect(host, { x = 100, y = 50, w = 300, h = 300 })

		-- reachable ONLY because `indexNode` ran at adopt's new-key site
		expect(adapter.composedRect("/S/Host/Leaf2")).toEqual({ x = 115, y = 75, w = 12, h = 12 })
	end)
end)

-- ===== STEP 4: THE INDEX BOUNDS THE RECOMPOSE TO THE HOST'S OWN SUBTREE ====

describe("T12: a host move recomposes the host's own subtree, not the mounted tree", function()
	it("counters: solves=1 on mount, solves=0 + lastLaneTranslates=1 on the lane-served move", function()
		local s = scene.new()
		expect(s.stats().solves).toBe(1)

		local before = s.stats()
		s.setOffsetX(1, (s.items[1].x:get() :: number) + 7)
		local after = s.stats()

		expect(after.solves - before.solves).toBe(0)
		expect(after.lastLaneTranslates).toBe(1)
		s.dispose()
	end)

	--[[ THE HEADLINE, as a spec-local count rather than a `src/`-side counter
		(this file never touches `src/`): wrap the adapter's OWN composition
		entry point for the span of one host move and count how many nodes it
		actually re-derives. Measured (T9b §2.6): the old prefix scan visited the
		WHOLE mounted tree for every host move — on this fixture 1,503 nodes for
		one of 250 hosts. The index bounds it to that host's own subtree (`PER`
		= 6 nodes/plate: the plate root plus its five descendants), independent
		of how many OTHER plates are mounted beside it. ]]
	it("recompose visits are bounded to the moved host's subtree, not the mounted census", function()
		local PER = scene.NODES_PER_PLATE
		local s = scene.new()
		s.tick(0, 0) -- warm: pay the cold solve before the instrumented move

		local visits = 0
		local original = (s.adapter :: any)._composePresentation;
		(s.adapter :: any)._composePresentation = function(node: any)
			visits += 1
			return original(node)
		end

		s.setOffsetX(1, (s.items[1].x:get() :: number) + 11)

		expect(visits <= PER).toBe(true)
		expect(visits > 0).toBe(true) -- non-vacuous: the moved host really did recompose something
		s.dispose()
	end)
end)
