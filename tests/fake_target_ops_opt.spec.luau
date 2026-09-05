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
	file's own job is narrower: pin the SET the old scan recomposed (five
	fixtures, (d) and (e) added in fix round 1 for the two cases where the index
	and that set really can disagree), pin that the index reproduces it, and pin
	that the log really costs nothing when nobody asked for it. ]]

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

	it("takeOps refuses when unarmed too — it drains the very log ops() guards", function()
		--[[ RED at `a77cc101` (fix round 1, review Important 4): only `ops()`
			asserted. `takeOps` reads and CLEARS the same table and has ~2.5x the
			call sites (74 across 30 spec files), so an unarmed caller looking for a
			forbidden op in an empty log passes vacuously. ]]
		local unarmed = fake_target.new()
		local root = unarmed.createRoot("S")
		unarmed.create(root, "/S/A", "Box", nil, nil)
		expect(function()
			(unarmed :: any).takeOps()
		end).toThrow()

		local armed = fake_target.new({ ops = true })
		local root2 = armed.createRoot("S")
		armed.create(root2, "/S/A", "Box", nil, nil)
		expect(#armed.takeOps() > 0).toBe(true)
		expect(#armed.takeOps()).toBe(0) -- and the drain really did drain
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
	that walk is re-derived off an index. Five fixtures, built with the raw
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
		-- a real child of the moved host, so the guard below proves the index walk
		-- DESCENDED rather than merely that the wrap is installed (fix round 1,
		-- review Minor 2: `setRect` composes the moved host itself unconditionally)
		local kid = adapter.create(root, "/S/Host/Kid", "Box", nil, nil)
		adapter.setRect(kid, { x = 3, y = 4, w = 8, h = 8 })
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
		-- ...and the walk really did run: `/S/Host/Kid` is reached only BY the index,
		-- unlike `/S/Host`, which `setRect` composes on its own line either way
		expect(visited["/S/Host/Kid"] == true).toBe(true)
		expect(adapter.composedRect("/S/Host/Kid")).toEqual({ x = 102, y = 103, w = 8, h = 8 })
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

	--[[ fixture (d): A RECONCILER-ONLY PATH SEGMENT (fix round 1, review Important
		2). The one BEHAVIOURAL fix in T12 — `nearestExistingAncestor` — shipped with
		no Facet-side test: replacing its body with `return parentPathOf(path)`, i.e.
		re-introducing the exact regression, left the whole suite green, and only
		RascalRally's `facet_sponsor_table.spec` said otherwise. `mount.luau` splices
		`UI.When`'s `then`/`else` branch and `UI.ForEach`'s `[key]` item into the
		enclosing flow WITHOUT creating a node at that segment (`nameplates_scene`'s
		own header: "a path string with nothing mounted at it"), so a leaf really does
		sit at `/S/Host/then/Leaf` while `/S/Host/then` is not, and never will be, a
		node. A last-`/` cut keys that leaf under a parent nobody ever inserts and it
		silently stops following its host. ]]
	it("fixture (d): a leaf born under a never-created path segment still follows its host", function()
		local adapter = fake_target.new() :: any
		local root = adapter.createRoot("S")
		local host = adapter.create(root, "/S/Host", "VStack", nil, { instanceHost = true, hostSpace = true })
		adapter.setRect(host, { x = 0, y = 0, w = 300, h = 300 })
		-- `/S/Host/then` is NEVER created — that is the whole fixture
		local leaf = adapter.create(root, "/S/Host/then/Leaf", "Box", nil, nil)
		adapter.setRect(leaf, { x = 10, y = 10, w = 20, h = 20 })
		expect(adapter.node("/S/Host/then")).toBeNil()
		expect(adapter.composedRect("/S/Host/then/Leaf")).toEqual({ x = 10, y = 10, w = 20, h = 20 })

		adapter.setRect(host, { x = 100, y = 50, w = 300, h = 300 })

		-- with the gap walk: `110,60`. With a bare last-`/` cut: `10,10`, stale
		-- forever (mutation bite 2, fix round 1)
		expect(adapter.composedRect("/S/Host/then/Leaf")).toEqual({ x = 110, y = 60, w = 20, h = 20 })
	end)

	--[[ fixture (e): A PARKED PLAIN INTERMEDIATE (fix round 1, review Important 3).
		`park` refuses a HOST that still has children, but a plain node with
		path-children is parkable and removable — and the old prefix scan reached its
		descendants regardless, because it selected on the path STRING. The first
		draft of `unindexNode` ended `childrenOf[path] = nil`, throwing the whole
		bucket away and freezing that subtree at its pre-move rect (measured: `2,2`
		against the old scan's `72,82`). The guarantee that this "cannot happen" rested
		entirely on the renderer's deepest-first sweep discipline, unwritten and
		unpinned; `unindexNode` now re-homes the orphans to the nearest ancestor that
		is still a node instead. ]]
	it("fixture (e): parking a plain intermediate does not orphan its children from the host's move", function()
		local adapter = fake_target.new() :: any
		local root = adapter.createRoot("S")
		local host = adapter.create(root, "/S/H", "VStack", nil, { instanceHost = true, hostSpace = true })
		adapter.setRect(host, { x = 0, y = 0, w = 300, h = 300 })
		local mid = adapter.create(root, "/S/H/M", "Box", nil, nil)
		adapter.setRect(mid, { x = 1, y = 1, w = 50, h = 50 })
		local leaf = adapter.create(root, "/S/H/M/L", "Box", nil, nil)
		adapter.setRect(leaf, { x = 2, y = 2, w = 10, h = 10 })

		expect(adapter.park(mid)).toBe(true)
		expect(adapter.node("/S/H/M")).toBeNil()
		-- the leaf is untouched by the park: it is still live, still stored at 2,2
		expect(adapter.composedRect("/S/H/M/L")).toEqual({ x = 2, y = 2, w = 10, h = 10 })

		adapter.setRect(host, { x = 70, y = 80, w = 300, h = 300 })

		-- the old scan re-based it to `72,82` and so does the index; a bucket
		-- cleared on the park leaves it at `2,2` (mutation bite 3, fix round 1)
		expect(adapter.composedRect("/S/H/M/L")).toEqual({ x = 72, y = 82, w = 10, h = 10 })
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

	--[[ THE HEADLINE, RE-DERIVED (fix round 1, review Important 1). The first draft
		counted `_composePresentation` calls and asserted `visits <= PER` — and it did
		NOT fail with the pre-T12 prefix scan restored (measured: 9 passed / 0 failed),
		because the old walk ITERATED all 1,503 mounted nodes while COMPOSING only the
		6 that carried the prefix. Composition was never the cost; the iteration was
		(T9b §2.6: 248 hosts x 1,503 nodes, 21.3 of the class's 24.0 ms). So this pin
		counts what the old walk actually spent: entries pulled out of the target's own
		node map for the span of ONE host move.

		THE INSTRUMENT IS `__iter` ON THAT MAP, which is what generalized iteration
		(`for path, node in nodes`) goes through — the old scan included — so the pin
		sees any future re-derivation off a full-map walk without reaching into the
		target's locals. It is SELF-PROVED below rather than trusted: a wrap the VM
		ignored would report 0 probes and pass this case vacuously forever. Measured,
		one host move on this fixture: **1,503 probes** with the old scan restored by
		hand, **0** with the index. The composed set is pinned beside it because a walk
		that probes nothing AND composes nothing would satisfy the bound emptily, and
		`solves` beside that because a re-solve would recompose the tree by a different
		route and this pin would have measured the wrong lane. ]]
	it("a host move probes the host's own subtree, not every node in the mounted map", function()
		local PER = scene.NODES_PER_PLATE
		local s = scene.new()
		s.tick(0, 0) -- warm: pay the cold solve before the instrumented move

		local liveNodes = (s.adapter :: any).liveNodes()
		local mounted = 0
		for _ in liveNodes do
			mounted += 1
		end
		-- the census the old scan paid ONCE PER HOST MOVE, and the reason a bound of
		-- `PER` is a claim rather than a coincidence
		expect(mounted > 250).toBe(true)

		local probes = 0
		setmetatable(liveNodes, {
			__iter = function(t: any)
				return function(tbl: any, key: any)
					local k, v = next(tbl, key)
					if k ~= nil then
						probes += 1
					end
					return k, v
				end,
					t,
					nil
			end,
		})
		for _ in liveNodes do
		end
		expect(probes).toBe(mounted) -- the wrap really is what iteration goes through

		local visits = 0
		local original = (s.adapter :: any)._composePresentation;
		(s.adapter :: any)._composePresentation = function(node: any)
			visits += 1
			return original(node)
		end

		local before = s.stats()
		probes = 0
		s.setOffsetX(1, (s.items[1].x:get() :: number) + 11)
		local moveProbes = probes
		local after = s.stats()

		expect(after.solves - before.solves).toBe(0) -- lane-served: no re-solve to hide behind
		expect(after.lastLaneTranslates).toBe(1)
		expect(moveProbes <= PER).toBe(true) -- 1,503 with the old prefix scan restored
		expect(visits <= PER).toBe(true)
		expect(visits > 0).toBe(true) -- non-vacuous: the moved host really did recompose something
		setmetatable(liveNodes, nil)
		s.dispose()
	end)
end)
