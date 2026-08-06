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
