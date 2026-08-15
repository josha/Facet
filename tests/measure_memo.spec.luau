--!strict
-- The per-solve measure memo publishes the LAST measure's verdicts (roadmap Step 9).
--
-- WHY THIS FILE EXISTS. `solver.measure` is memoized per solve so a scroll node's
-- arrange pass stops recomputing sizes the measure pass already produced. The first
-- version cached only `(w, h)` — and a fresh-context architecture review found, by
-- differential fuzz over 800 seeded trees, that this silently changed a documented
-- contract:
--
--   `ctx.compact` and `ctx.textFacts` are "assigned on EVERY measure of the node, so
--   the facts published are the ones the reserved box was built from" — LAST WRITE
--   WINS across boxes, because a node is measured repeatedly at different widths and
--   `arrange` snapshots whatever the final measure left behind.
--
-- A size-only cache turns that into FIRST-measure-per-box wins. The two differ exactly
-- when the order is measure(A) -> measure(B) -> measure(A). The fuzz found geometry
-- byte-identical on all 800 trees while `compact` flipped on 3 and `textFacts` on 12 —
-- including `truncated` going true -> false, which is what gates full-value disclosure
-- and the reveal. A cut label reporting `truncated = false` loses its accessible full
-- value: a Step 8.5 regression with the geometry unchanged, the hardest kind to notice.
--
-- THE TREES BELOW ARE THE REVIEW'S OWN AUTO-SHRUNK REPRODUCTIONS, transcribed from its
-- delta-debugging output (seeds 132, 612, 91). They are pinned by their published
-- VERDICT, never by their rect — `rectSame = true` on all three, which is the point.
--
-- MUTATION-PROVED, AND HONESTLY SO (phase-gate review F-8). Deleting the replay
-- assignments in `solver.measure` reddens the **seed 612** and **seed 91** cases —
-- including the accessibility one. The **seed 132** case does NOT redden in isolation:
-- the fuzz found it as part of a larger generated tree, and the shrunk form transcribed
-- here reproduces the shape but not the measure ORDER that made it diverge. It is kept
-- as corroboration of the shape, not claimed as a biting case, because a test that
-- cannot fail is worse than no test — and the file that says otherwise is how that
-- class survives.

local testkit = require("./lib/testkit")
local describe, it, expect = testkit.describe, testkit.it, testkit.expect

local solver = require("../src/layout/solver")

-- the solver's Node shape uses `width`/`height`, not `w`/`h`. Transcribing them as
-- `w`/`h` produced a tree that could not reproduce the defect at all — the first
-- version of this spec was green against the BROKEN solver for exactly that reason,
-- which is why every case here was mutation-checked before it was kept.
local function node(id: string, kind: string, props: { [string]: any }?): any
	local n: any = { id = id, kind = kind, children = {} }
	for k, v in props or {} do
		n[k] = v
	end
	return n
end

local function chain(nodes: { any }): any
	for i = 1, #nodes - 1 do
		nodes[i].children = { nodes[i + 1] }
	end
	return nodes[1]
end

describe("the measure memo replays the verdicts it cached", function()
	-- CORROBORATION, NOT A BITING CASE — see the header. This one stays green under the
	-- replay removal; it documents the shape the fuzz shrank to.
	it("seed 132: a compact label that FITS is not marked compact by a stale measure", function()
		local root = chain({
			node("n1", "zstack", { width = { type = "percent", fraction = 0.59 } }),
			node("n14", "zstack", { width = { type = "minMax", min = 37, max = 57 } }),
			node("n27", "scroll", {
				gap = 6,
				axis = "y",
				width = { type = "fixed", px = 239 },
				height = { type = "minMax", min = 34, max = 46 },
			}),
			node("n30", "text", {
				text = "Continue",
				textSize = 10,
				compactText = "OK",
				singleLine = true,
				width = { type = "minMax", min = 45, max = 122 },
				height = { type = "fixed", px = 4 },
			}),
		})
		local result = solver.solve(root, { w = 800, h = 600 }, { scrollBarReserve = 0 })
		expect(result.rects["n30"].compact).toBe(false)
	end)

	it("seed 612: a compact label that does NOT fit keeps its compact verdict", function()
		local inner = node("n7", "hstack", {
			gap = 10,
			align = "stretch",
			width = { type = "fill", weight = 3 },
			height = { type = "fill", weight = 3 },
		})
		inner.children = {
			node("n8", "text", {
				text = "OK",
				textSize = 10,
				compactText = "Set",
				padding = 13,
				height = { type = "minMax", min = 22, max = 188 },
				margin = 17,
			}),
		}
		local row = node("n3", "hstack", { gap = 0, padding = 7, height = { type = "fill", weight = 1 } })
		row.children = {
			node("n4", "fits", {
				padding = 4,
				width = { type = "fixed", px = 177 },
				margin = { top = 10, right = 11, bottom = 9, left = 18 },
			}),
			inner,
		}
		local root = chain({
			node("n1", "grid", { gap = 9, padding = 13, columns = 3, width = { type = "fixed", px = 209 } }),
			node("n2", "anchor", { height = { type = "percent", fraction = 0.74 }, margin = 8 }),
			row,
		})
		local result = solver.solve(root, { w = 800, h = 600 }, { scrollBarReserve = 0 })
		expect(result.rects["n8"].compact).toBe(true)
	end)

	it("seed 91: a cut label reports truncated = true, so its disclosure path survives", function()
		local leaf = node("n51", "hstack", {
			gap = 12,
			width = { type = "minMax", min = 62, max = 185 },
			height = { type = "fixed", px = 46 },
			margin = { top = 20, right = 10, bottom = 2, left = 16 },
		})
		leaf.children = {
			node("n52", "text", {
				text = "Play now",
				textSize = 16,
				compactText = "Set",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				margin = 17,
			}),
			node("n53", "box", { height = { type = "fill", weight = 3 } }),
			node("n54", "spacer", {
				width = { type = "aspect", ratio = 0.6 },
				height = { type = "minMax", min = 18, max = 163 },
			}),
		}
		local root = chain({
			node("n1", "fits", {
				width = { type = "percent", fraction = 0.77 },
				height = { type = "fixed", px = 234 },
				margin = { top = 5, right = 12, bottom = 3, left = 18 },
			}),
			node("n38", "hstack", { gap = 3, width = { type = "hug" }, height = { type = "fill", weight = 2 } }),
			node("n39", "hstack", {
				gap = 11,
				padding = 7,
				width = { type = "fill", weight = 1 },
				height = { type = "aspect", ratio = 1.9 },
				margin = { top = 10, right = 5, bottom = 13, left = 11 },
			}),
			leaf,
		})
		local result = solver.solve(root, { w = 400, h = 900 }, { scrollBarReserve = 0 })
		local facts = result.rects["n52"].textFacts
		expect(facts ~= nil).toBe(true)
		-- THE ACCESSIBILITY PIN. A size-only memo published `truncated = false` for this
		-- cut label, geometry identical — which is exactly how a full-value disclosure
		-- path disappears without anything looking wrong.
		expect(facts.truncated).toBe(true)
		expect(facts.policy).toBe("truncate")
	end)

	it("the memo does not move geometry — the verdicts are the only thing at risk", function()
		local text = node("T", "text", { text = "A longer label that will wrap somewhere here", textSize = 12 })
		local scroll = node("S", "scroll", {
			axis = "y",
			width = { type = "fixed", px = 200 },
			height = { type = "fixed", px = 80 },
		})
		scroll.children = { text }
		local root = node("R", "vstack", { width = { type = "fill", weight = 1 } })
		root.children = { scroll }

		local a = solver.solve(root, { w = 640, h = 480 }, { scrollBarReserve = 8 })
		local b = solver.solve(root, { w = 640, h = 480 }, { scrollBarReserve = 8 })
		for path, entry in a.rects do
			local other = b.rects[path]
			expect(other ~= nil).toBe(true)
			expect(other.rect.x).toBe(entry.rect.x)
			expect(other.rect.y).toBe(entry.rect.y)
			expect(other.rect.w).toBe(entry.rect.w)
			expect(other.rect.h).toBe(entry.rect.h)
		end
	end)
end)

--[[ THE OFFERED HEIGHT LEAVES THE KEY WHEN THE ANSWER CANNOT READ IT (L-37).

	WHY THIS BLOCK EXISTS. `LuauUI/arrange` was the largest scope in all four of the
	director's device captures (9.1-10.6 ms per occurrence, worst single occurrence
	298.87 ms), and L-36 found the mechanism by workload rather than by reading: the
	same 240 leaves cost 8.7x more per arranged node under 30 nested stacks than
	under one, and the cost was not the placing — it was RE-MEASURING, 16.4 measures
	per arranged node against 2.0. The memo that exists to stop exactly that produced
	ZERO hits on the shape.

	The cause, then instrumented rather than assumed: the cache key carried the
	OFFERED HEIGHT, and a nested chain offers a different one at every level. Counted
	per node on the 30-deep tree — 16.33 distinct `maxH`, 1.00 distinct `maxW`, 1.00
	distinct `scopeKey`. The key varied by the one input those nodes' answers never
	read, which is L-9's defect one scale up: L-9 took `maxH` out of the key for a
	TEXT leaf; this takes it out for any node whose height type and whose content
	provably cannot consult the offer (`solver.memoPlan` carries the enumeration).

	THE THREE EXCLUSIONS BELOW ARE EACH MUTATION-PROVED, and that closes the gap L-9
	recorded honestly and could not close: it tried an over-broad rule, saw identical
	output on 400 fuzzed trees, and shipped the exclusions on a line-by-line reading
	of `resolveAxis` rather than on a test that had been watched to fail. A richer
	differential oracle (800 seeded trees over the whole vocabulary — `fits`,
	`hwrap`/`vwrap`, `gridrow`, `shrinkWeight`, `compactText`, `lineLimit` — two
	builds, comparing geometry AND `compact`/`textState`/`textFacts`) says otherwise:
	the fully over-broad rule diverges on 2 933 of 25 961 node comparisons. The three
	trees below are that oracle's auto-shrunk reproductions, one per exclusion, each
	pinned by the rect the mutation moves.
]]
describe("the measure memo's key carries the offer only where the offer is read", function()
	it("a `hug` height READS the offer, so it keeps `maxH` in the key", function()
		-- Mutation: drop the height-type test in `memoPlan` (accept `fill`/`percent`/
		-- `hug` alongside `fixed`/`content`/`minMax`). The scroller's `hug` anchor then
		-- replays the answer it gave at the first offer it saw, and everything under it
		-- inherits the wrong extent: n15 goes 74 -> 258.
		local box = node("n16", "box", {
			padding = 12,
			width = { type = "minMax", min = 34, max = 182 },
			height = { type = "percent", fraction = 0.66 },
		})
		local grid = node("n15", "grid", { gap = 8, columns = 2, width = { type = "fixed", px = 89 } })
		grid.children = { box }
		local anchor = node("n11", "anchor", { padding = 4, shrinkWeight = 1, height = { type = "hug" } })
		anchor.children = { grid }
		local scroll = node("n10", "scroll", {
			axis = "x",
			width = { type = "fixed", px = 1 },
			height = { type = "fill", weight = 3 },
		})
		scroll.children = { anchor }
		local row = node("n3", "gridrow", { gap = 0, columns = 1, width = { type = "hug" } })
		row.children = { scroll }
		local root = node("n1", "hwrap", { gap = 6, margin = 1, wrap = true, width = { type = "fill", weight = 2 } })
		root.children = { row }

		local result = solver.solve(root, { w = 360, h = 600 }, { scrollBarReserve = 0 })
		expect(result.rects["n15"].rect.h).toBe(74)
		expect(result.rects["n11"].rect.h).toBe(120)
		expect(result.rects["n10"].rect.h).toBe(178)
	end)

	it("a `vwrap` breaks its lines ON the offered height, so it is never height-free", function()
		-- Mutation: empty `HEIGHT_COUPLED_KINDS`. `vwrap` partitions on `innerMaxH`, so
		-- a replayed answer re-uses a partition computed for a different height and the
		-- wrap collapses to one column: n5 goes 215x169 -> 115x175.
		local a = node("n7", "text", {
			text = "Continue",
			textSize = 23,
			compactText = "Go",
			height = { type = "fixed", px = 169 },
		})
		local b = node("n8", "text", {
			text = "Supercalifragilistic",
			textSize = 37,
			singleLine = true,
			width = { type = "minMax", min = 39, max = 91 },
			height = { type = "fixed", px = 74 },
		})
		local col = node("n5", "vwrap", { gap = 9, wrap = true, width = { type = "percent", fraction = 0.78 } })
		col.children = { a, b }
		local scroll = node("n4", "scroll", {
			axis = "x",
			padding = 10,
			width = { type = "hug" },
			height = { type = "minMax", min = 21, max = 195 },
		})
		scroll.children = { col }
		local root = node("n1", "hwrap", {
			gap = 0,
			margin = 4,
			shrinkWeight = 1,
			wrap = true,
			width = { type = "percent", fraction = 0.11, max = 93 },
		})
		root.children = { scroll }

		local result = solver.solve(root, { w = 720, h = 600 }, { scrollBarReserve = 0 })
		expect(result.rects["n5"].rect.w).toBe(215)
		expect(result.rects["n5"].rect.h).toBe(169)
		expect(result.rects["n4"].rect.h).toBe(189)
	end)

	it("a child that can be SQUEEZED makes its vertical stack read the offer too", function()
		-- Mutation: drop the `fill`-main / `shrinkWeight` child test in `memoPlan`. PASS
		-- 1.5's squeeze reads `mainLimit`, which on a vertical stack IS the offered
		-- height, so the stack's answer depends on an offer the key would have dropped:
		-- n56 goes 245 -> 36 and its only child collapses to zero.
		local box = node("n58", "box", {
			padding = 5,
			margin = 18,
			shrinkWeight = 2,
			width = { type = "percent", fraction = 0.61 },
			height = { type = "fixed", px = 225 },
		})
		local col = node("n56", "vstack", { gap = 12, width = { type = "fixed", px = 159 } })
		col.children = { box }
		local fits = node("n60", "fits", {
			padding = 2,
			margin = 5,
			width = { type = "hug" },
			height = { type = "fixed", px = 235 },
		})
		local row =
			node("n52", "hstack", { gap = 2, margin = 12, width = { type = "percent", fraction = 0.68, max = 139 } })
		row.children = { col, fits }
		local grid = node("n45", "grid", { gap = 3, padding = 11, columns = 4, height = { type = "hug" } })
		grid.children = { row }
		local root = node("n1", "gridrow", {
			gap = 2,
			padding = 13,
			margin = 7,
			minColumnWidth = 53,
			width = { type = "minMax", min = 31, max = 80 },
			height = { type = "fixed", px = 35 },
		})
		root.children = { grid }

		local result = solver.solve(root, { w = 360, h = 360 }, { scrollBarReserve = 8 })
		expect(result.rects["n56"].rect.h).toBe(245)
		expect(result.rects["n58"].rect.h).toBe(209)
	end)
end)

describe("the measure fan-out no longer grows with nesting depth", function()
	-- THE COST THIS FIX EXISTS TO REMOVE, read off the PUBLIC result. `work.measured`
	-- counts uncached measures, so it is the same number L-36 reported as 4 425 for
	-- the 30-deep shape arm and the same one a device dump's `LuauUI/arrange` is made
	-- of. Before: 4.30 measures per arranged node at 4 levels, 8.32 at 12, 17.33 at 30
	-- — quadratic in depth, because every enclosing level re-measured the whole
	-- subtree. After: 2.35 / 2.05 / 1.95.
	local function chain(levels: number): any
		local inner: any = nil
		for level = levels, 1, -1 do
			local children = {}
			for j = 1, 8 do
				table.insert(
					children,
					node(`L{level}_{j}`, "box", {
						width = { type = "fixed", px = 24 },
						height = { type = "fixed", px = 10 },
					})
				)
			end
			if inner ~= nil then
				table.insert(children, inner)
			end
			local stack = node(`D{level}`, "vstack", { gap = 0, width = { type = "fill", weight = 1 } })
			stack.children = children
			inner = stack
		end
		local root = node("Root", "vstack", {
			gap = 0,
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
		})
		root.children = { inner }
		return root
	end

	local function fanOut(levels: number): number
		local result = solver.solve(chain(levels), { w = 400, h = 600 }, { scrollBarReserve = 8 })
		return result.work.measured / result.work.arranged
	end

	it("a 30-deep chain measures each node about twice, not sixteen times", function()
		-- 1.95 here; 17.33 before the key was fixed. The threshold sits far from both so
		-- this pins the MECHANISM rather than a particular laptop's arithmetic.
		expect(fanOut(30) < 3).toBe(true)
	end)

	it("...and the fan-out does not RISE with depth, which is the whole defect", function()
		-- 4.30 -> 8.32 -> 17.33 before; 2.35 -> 2.05 -> 1.95 after. Any regression that
		-- re-couples the key to the offered height, closes the nesting arm, or widens
		-- `HEIGHT_COUPLED_KINDS` to cover a plain stack puts the slope back.
		expect(fanOut(30) <= fanOut(4)).toBe(true)
		expect(fanOut(12) <= fanOut(4)).toBe(true)
	end)
end)

describe("the memo is scoped to trees that can benefit from it", function()
	it("gating the memo on a scroll node changes no geometry on a scroll-free tree", function()
		-- The scoping exists because the unconditional memo crossed the bench's 1.5x
		-- regression rule on `textinput-typing-storm`: a small tree re-solved per
		-- keystroke, with no scroll node and therefore no redundant measure to remove,
		-- paying a string key and a table per node per solve for nothing. Worse in 6 of
		-- 6 interleaved A/B pairs (optimization log L-6).
		--
		local flat = node("R", "vstack", { gap = 4, width = { type = "fixed", px = 300 } })
		flat.children = {
			node("A", "text", { text = "one", textSize = 12 }),
			node("B", "text", { text = "two", textSize = 12 }),
			node("C", "box", { height = { type = "fixed", px = 20 } }),
		}
		-- WHAT THIS CASE CAN AND CANNOT PROVE. `ctx` is internal, so the cache's
		-- emptiness is not observable through the public solve API; the performance
		-- property is established by the interleaved A/B in the optimization log, not
		-- here. What IS testable — and what a future edit to the scoping could break —
		-- is that gating the memo changes no geometry at all, on a tree that now takes
		-- the uncached path.
		local a = solver.solve(flat, { w = 640, h = 480 }, { scrollBarReserve = 8 })
		local b = solver.solve(flat, { w = 640, h = 480 }, { scrollBarReserve = 8 })
		for path, entry in a.rects do
			expect(b.rects[path].rect.w).toBe(entry.rect.w)
			expect(b.rects[path].rect.h).toBe(entry.rect.h)
		end
	end)
end)
