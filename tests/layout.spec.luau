--!strict
-- Layout spike tests (design §7, UI-LAYOUT-001): sizing algebra subset,
-- wrapped text, fill distribution with deterministic rounding, safe-area root
-- policies, ScrollView overflow, purity (frozen snapshot, double-solve
-- equality), and diagnostics for undefined combinations.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local solver = require("../src/layout/solver")
local dump = require("../src/layout/dump")
local text_metrics = require("../src/layout/text_metrics")

local function fixed(px: number): solver.Dim
	return { type = "fixed", px = px }
end
local function fill(weight: number?): solver.Dim
	return { type = "fill", weight = weight or 1 }
end

describe("layout: sizing algebra", function()
	it("vstack content height = children + gaps + padding", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "root",
			padding = 10,
			gap = 5,
			children = {
				{ kind = "box", id = "a", width = fixed(50), height = fixed(20) },
				{ kind = "box", id = "b", width = fixed(60), height = fixed(30) },
			},
		}
		local result = solver.solve(root, { w = 400, h = 400 }, { rootPolicy = "edgeToEdge" })
		-- root rect is the content rect; children stacked inside padding
		expect(result.rects.a.rect.y).toBe(10)
		expect(result.rects.b.rect.y).toBe(35) -- 10 + 20 + 5
		expect(result.rects.b.rect.x).toBe(10)
	end)

	it("fill children share remaining space by weight with exact integer total", function()
		local root: solver.Node = {
			kind = "hstack",
			id = "root",
			width = fixed(100),
			height = fixed(20),
			children = {
				{ kind = "box", id = "left", width = fixed(10), height = fixed(20) },
				{ kind = "spacer", id = "s1", width = fill(1) },
				{ kind = "spacer", id = "s2", width = fill(1) },
				{ kind = "spacer", id = "s3", width = fill(1) },
			},
		}
		local result = solver.solve(root, { w = 100, h = 20 }, { rootPolicy = "edgeToEdge" })
		local w1 = result.rects.s1.rect.w
		local w2 = result.rects.s2.rect.w
		local w3 = result.rects.s3.rect.w
		expect(w1 + w2 + w3).toBe(90)
		-- deterministic largest-remainder: earlier index gets the extra pixel
		expect(w1).toBe(30)
		expect(w2).toBe(30)
		expect(w3).toBe(30)
	end)

	it("uneven fill rounding is deterministic and lossless", function()
		local root: solver.Node = {
			kind = "hstack",
			id = "root",
			width = fixed(100),
			height = fixed(10),
			children = {
				{ kind = "spacer", id = "a", width = fill(1) },
				{ kind = "spacer", id = "b", width = fill(1) },
				{ kind = "spacer", id = "c", width = fill(1) },
			},
		}
		local result = solver.solve(root, { w = 100, h = 10 }, { rootPolicy = "edgeToEdge" })
		local total = result.rects.a.rect.w + result.rects.b.rect.w + result.rects.c.rect.w
		expect(total).toBe(100)
		expect(result.rects.a.rect.w).toBe(34) -- largest remainder, lowest index
		expect(result.rects.b.rect.w).toBe(33)
		expect(result.rects.c.rect.w).toBe(33)
	end)
end)

describe("layout: wrapped text", function()
	it("narrower width wraps to more lines and taller height", function()
		local text = "the quick brown fox jumps over the lazy dog and keeps on running"
		local narrow = text_metrics.measure(text, "BuilderSans", 16, 150)
		local wide = text_metrics.measure(text, "BuilderSans", 16, 600)
		expect(narrow.state).toBe("ready")
		expect(narrow.lines > wide.lines).toBe(true)
		expect(narrow.height > wide.height).toBe(true)
		expect(narrow.width <= 150).toBe(true)
	end)

	it("unknown font takes the pending path with a conservative (larger) fallback", function()
		local text = "hello wrapped world"
		local known = text_metrics.measure(text, "BuilderSans", 16, 200)
		local pending = text_metrics.measure(text, "SomeNewFont", 16, 200)
		expect(pending.state).toBe("pending")
		expect(pending.requestKey ~= nil).toBe(true)
		-- conservative: pending reserves at least as much space
		expect(pending.height >= known.height).toBe(true)
	end)

	it("text node height flows into stack layout", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "root",
			children = {
				{
					kind = "text",
					id = "para",
					text = "one two three four five six seven eight nine ten",
					textSize = 16,
				},
				{ kind = "box", id = "under", width = fixed(10), height = fixed(10) },
			},
		}
		local narrowR = solver.solve(root, { w = 120, h = 800 }, { rootPolicy = "edgeToEdge" })
		local wideR = solver.solve(root, { w = 800, h = 800 }, { rootPolicy = "edgeToEdge" })
		expect(narrowR.rects.under.rect.y > wideR.rects.under.rect.y).toBe(true)
		expect(narrowR.rects.para.textState).toBe("ready")
	end)
end)

describe("layout: safe area", function()
	it("coreSafeContent insets the content rect; edgeToEdge does not", function()
		local root: solver.Node = { kind = "box", id = "root", width = fill(1), height = fill(1) }
		local insets = { top = 59, bottom = 34, left = 0, right = 0 }
		local safe = solver.solve(root, { w = 390, h = 844 }, { safeInsets = insets, rootPolicy = "coreSafeContent" })
		local edge = solver.solve(root, { w = 390, h = 844 }, { safeInsets = insets, rootPolicy = "edgeToEdge" })
		expect(safe.contentRect.y).toBe(59)
		expect(safe.contentRect.h).toBe(844 - 59 - 34)
		expect(edge.contentRect.y).toBe(0)
		expect(edge.contentRect.h).toBe(844)
	end)
end)

describe("layout: ScrollView", function()
	it("reports content size and scroll overflow when content exceeds viewport", function()
		local children = {}
		for i = 1, 10 do
			table.insert(
				children,
				{ kind = "box", id = `row{i}`, width = fixed(100), height = fixed(40) } :: solver.Node
			)
		end
		local root: solver.Node = {
			kind = "scroll",
			id = "list",
			width = fixed(120),
			height = fixed(200),
			axis = "y",
			children = children,
		}
		local result = solver.solve(root, { w = 400, h = 400 }, { rootPolicy = "edgeToEdge" })
		expect(result.rects.list.contentSize.h).toBe(400)
		expect(result.rects.list.overflow).toBe("scroll")
		-- children measured against the unbounded axis, arranged sequentially
		expect(result.rects.row10.rect.y).toBe(9 * 40)
	end)

	it("percent height inside the unbounded scroll axis produces a diagnostic, not silence", function()
		local root: solver.Node = {
			kind = "scroll",
			id = "list",
			width = fixed(100),
			height = fixed(100),
			axis = "y",
			children = {
				{ kind = "box", id = "bad", width = fixed(50), height = { type = "percent", fraction = 0.5 } },
			},
		}
		local result = solver.solve(root, { w = 400, h = 400 }, { rootPolicy = "edgeToEdge" })
		expect(#result.diagnostics >= 1).toBe(true)
		expect(result.diagnostics[1].node).toBe("bad")
	end)

	-- preferred-text sweep, 2026-07-24. A stack that cannot hold its content
	-- keeps every content child at full size and keeps advancing the cursor, so
	-- it paints outside its own box with no clip, no compression and no scroll.
	-- Found live on compact-phone-portrait: the Hud column ran 185px past its
	-- box, drawing the action row inside the media box and pushing the stat grid
	-- and tile row off an 800px screen — at rest, at the default text size, and
	-- the solver said nothing at all.
	it("a stack that cannot hold its content reports it instead of painting off-screen", function()
		local kids = {}
		for i = 1, 5 do
			table.insert(kids, { kind = "box", id = "k" .. i, width = fill(), height = fixed(100) })
		end
		local root: solver.Node = {
			kind = "vstack",
			id = "screen",
			width = fill(),
			height = fill(),
			children = {
				{ kind = "vstack", id = "body", width = fill(), children = kids },
				{ kind = "box", id = "footer", width = fill(), height = fixed(46) },
			},
		}
		local result = solver.solve(root, { w = 300, h = 400 }, { rootPolicy = "edgeToEdge" })
		-- the last child and the footer really do land outside the 400px screen
		expect(result.rects.k5.rect.y + result.rects.k5.rect.h > 400).toBe(true)
		expect(result.rects.footer.rect.y >= 400).toBe(true)
		-- ...and that is now reported against the stack that could not hold it
		local overflowed: { string } = {}
		for _, d in result.diagnostics do
			if string.find(d.issue, "content overflows", 1, true) then
				table.insert(overflowed, d.node)
			end
		end
		expect(#overflowed >= 1).toBe(true)
		expect(table.concat(overflowed, ",")).toBe("screen")
	end)

	-- a losing ViewThatFits candidate is arranged at a deliberate 0x0 rect, so it
	-- "overflows" trivially while painting nothing. Reporting it would put a
	-- permanent false positive on every ViewThatFits in the corpus, which is how
	-- a diagnostic becomes noise people learn to ignore.
	it("a ViewThatFits candidate that lost does not report an overflow", function()
		local root: solver.Node = {
			kind = "fits",
			id = "actions",
			width = fixed(120),
			height = fixed(60),
			children = {
				-- both candidates are far too tall for the 60px box, so the
				-- fallback is chosen and the first candidate is hidden
				{
					kind = "vstack",
					id = "wide",
					children = {
						{ kind = "box", id = "w1", width = fixed(100), height = fixed(90) },
					},
				},
				{
					kind = "vstack",
					id = "tall",
					children = {
						{ kind = "box", id = "t1", width = fixed(100), height = fixed(90) },
					},
				},
			},
		}
		local result = solver.solve(root, { w = 300, h = 300 }, { rootPolicy = "edgeToEdge" })
		expect(result.rects.wide.hidden).toBe(true)
		for _, d in result.diagnostics do
			-- the hidden candidate must never appear in a layout diagnostic
			expect(d.node ~= "wide").toBe(true)
		end
	end)

	-- Found live 2026-07-24 on compact-phone-landscape. An hstack measured EVERY
	-- child against its full inner width, including `fill` children that only ever
	-- receive a share of it. Less width means more wrapped lines, so the stack
	-- under-reported its own height — and a ScrollView turned that under-report
	-- into a canvas that could not reach its own content: 292px of canvas for
	-- content reaching 443px, leaving the bottom 151px unscrollable.
	it("a scroll canvas covers content laid out in fill columns that wrap", function()
		local function column(id: string, text: string): solver.Node
			return {
				kind = "vstack",
				id = id,
				width = fill(),
				children = {
					{ kind = "text", id = id .. "T", text = text, textSize = 16, width = fill() },
				},
			}
		end
		local long = "alpha bravo charlie delta echo foxtrot golf hotel india juliet"
		local root: solver.Node = {
			kind = "scroll",
			id = "list",
			axis = "y",
			width = fixed(400),
			height = fixed(120),
			children = {
				{
					kind = "hstack",
					id = "row",
					width = fill(),
					gap = 8,
					children = { column("left", long), column("right", long) },
				},
			},
		}
		local result = solver.solve(root, { w = 400, h = 400 }, { rootPolicy = "edgeToEdge" })
		local top = result.rects.list.rect.y
		local deepest = top
		for id, entry in result.rects do
			-- the scroll viewport itself is not content; everything else is
			if id ~= "list" then
				deepest = math.max(deepest, entry.rect.y + entry.rect.h)
			end
		end
		-- the wrap has to actually happen, or this proves nothing
		expect(deepest - top > 40).toBe(true)
		-- the canvas must reach everything the arrange pass actually placed,
		-- or the tail of the content is unreachable by scrolling
		expect(result.rects.list.contentSize.h >= deepest - top).toBe(true)
		-- and each fill column's box must cover the text inside it
		expect(result.rects.left.rect.h >= result.rects.leftT.rect.h).toBe(true)
		expect(result.rects.right.rect.h >= result.rects.rightT.rect.h).toBe(true)
	end)

	-- Found live 2026-07-24. `fill` reports CONTENT at measure time and a Box has
	-- none, so a 16:9 media box paired with `width = fill` measured 0x0 and only
	-- became its real size at arrange. Every ancestor under-measured by exactly the
	-- aspect height, and a ScrollView canvas built from that number left the tail
	-- of the content unreachable — 185px of it, in the adaptive_controls fixture.
	it("an aspect box paired with fill is measured at the extent it will receive", function()
		local root: solver.Node = {
			kind = "scroll",
			id = "list",
			axis = "y",
			width = fixed(320),
			height = fixed(100),
			children = {
				{
					kind = "vstack",
					id = "col",
					width = fill(),
					children = {
						{ kind = "box", id = "media", width = fill(), height = { type = "aspect", ratio = 16 / 9 } },
						{ kind = "box", id = "after", width = fill(), height = fixed(40) },
					},
				},
			},
		}
		local result = solver.solve(root, { w = 320, h = 320 }, { rootPolicy = "edgeToEdge" })
		-- 320 wide at 16:9 is 180 tall, plus the 40px block below it
		expect(result.rects.media.rect.h).toBe(180)
		local top = result.rects.list.rect.y
		local afterBottom = result.rects.after.rect.y + result.rects.after.rect.h
		-- the canvas has to reach the block that sits BELOW the media box, or that
		-- block cannot be scrolled to
		expect(result.rects.list.contentSize.h >= afterBottom - top).toBe(true)
	end)

	-- director review 2026-07-24. HStack/VStack have always ACCEPTED an `align`
	-- prop, but the solver only read `child.align`, so setting it on the container
	-- did nothing at all — an accepted-and-ignored property, which is the exact
	-- failure Milestone 0's strict authoring exists to remove. It meant a control
	-- row could not centre its children: the Volume label and its "6" readout sat
	-- 13px above the midline of the -/+ buttons because short children pinned to
	-- the top of a row sized by its tallest child.
	it("a stack's own align is the default for its children", function()
		local root: solver.Node = {
			kind = "hstack",
			id = "row",
			width = fixed(300),
			height = fixed(60),
			align = "center",
			children = {
				{ kind = "box", id = "short", width = fixed(50), height = fixed(20) },
				{ kind = "box", id = "tall", width = fixed(50), height = fixed(60) },
			},
		}
		local r = solver.solve(root, { w = 300, h = 300 }, { rootPolicy = "edgeToEdge" })
		local shortMid = r.rects.short.rect.y + r.rects.short.rect.h / 2
		local tallMid = r.rects.tall.rect.y + r.rects.tall.rect.h / 2
		expect(shortMid).toBe(tallMid)
	end)

	it("a child's own align still beats the container's", function()
		local root: solver.Node = {
			kind = "hstack",
			id = "row",
			width = fixed(300),
			height = fixed(60),
			align = "center",
			children = {
				{ kind = "box", id = "pinned", width = fixed(50), height = fixed(20), align = "start" },
				{ kind = "box", id = "tall", width = fixed(50), height = fixed(60) },
			},
		}
		local r = solver.solve(root, { w = 300, h = 300 }, { rootPolicy = "edgeToEdge" })
		expect(r.rects.pinned.rect.y).toBe(0)
	end)

	it("a container align of stretch equalises children that would be ragged", function()
		local root: solver.Node = {
			kind = "hstack",
			id = "row",
			width = fixed(300),
			height = fixed(60),
			align = "stretch",
			children = {
				{ kind = "box", id = "a", width = fixed(50), height = fixed(20) },
				{ kind = "box", id = "b", width = fixed(50), height = fixed(40) },
			},
		}
		local r = solver.solve(root, { w = 300, h = 300 }, { rootPolicy = "edgeToEdge" })
		expect(r.rects.a.rect.h).toBe(60)
		expect(r.rects.b.rect.h).toBe(60)
	end)

	-- director review 2026-07-24: the engine draws the scrollbar INSIDE the
	-- region, over the solver's content. Live, a 328px scroll host reported an
	-- AbsoluteWindowSize of 320 while content was laid out to the full 328, so the
	-- right 8px of every control in the fixture sat under the bar.
	it("a scrolling region lays content inside the scrollbar, not under it", function()
		local function region(reserve: number)
			local kids = {}
			for i = 1, 5 do
				table.insert(kids, { kind = "box", id = "k" .. i, width = fill(), height = fixed(100) })
			end
			local root: solver.Node = {
				kind = "scroll",
				id = "list",
				axis = "y",
				width = fixed(200),
				height = fixed(150),
				children = kids,
			}
			return solver.solve(root, { w = 200, h = 200 }, { rootPolicy = "edgeToEdge", scrollBarReserve = reserve })
		end
		-- content overflows, so the bar shows and its width must come off the cross axis
		expect(region(8).rects.k1.rect.w).toBe(192)
		-- with no bar declared, nothing is reserved
		expect(region(0).rects.k1.rect.w).toBe(200)
	end)

	it("a scrolling region that does not overflow reserves nothing", function()
		local root: solver.Node = {
			kind = "scroll",
			id = "list",
			axis = "y",
			width = fixed(200),
			height = fixed(500),
			children = { { kind = "box", id = "only", width = fill(), height = fixed(50) } },
		}
		local r = solver.solve(root, { w = 200, h = 500 }, { rootPolicy = "edgeToEdge", scrollBarReserve = 8 })
		expect(r.rects.only.rect.w).toBe(200)
	end)

	-- director review 2026-07-24. ViewThatFits chose its candidate against the
	-- space its PARENT offered, then arrange re-ran the chooser at the container's
	-- own (smaller) resolved width. A capped action bar inside a wide screen
	-- therefore measured a row at 1200px, was arranged at 620px where the labels
	-- wrap, and fell back to the stacked column on every wide profile.
	it("ViewThatFits chooses against its own width, not its parent's offer", function()
		-- the labels wrap at the CAPPED width but not at the parent's offer, so the
		-- row is short when measured wrong and tall when arranged right
		local long = "Reset absolutely everything back to the defaults"
		local function candidateRow(id: string)
			local kids = {}
			for i = 1, 3 do
				table.insert(kids, { kind = "text", id = `{id}{i}`, text = long, textSize = 18, width = fill() })
			end
			return { kind = "hstack", id = id, width = fill(), children = kids }
		end
		local root: solver.Node = {
			kind = "vstack",
			id = "screen",
			width = fixed(1800),
			height = fixed(400),
			children = {
				{
					kind = "fits",
					id = "actions",
					width = { type = "percent", fraction = 1, max = 620 },
					children = {
						candidateRow("row"),
						{
							kind = "vstack",
							id = "col",
							width = fill(),
							children = {
								{ kind = "text", id = "c1", text = long, textSize = 18, width = fill() },
							},
						},
					},
				},
			},
		}
		local r = solver.solve(root, { w = 1800, h = 400 }, { rootPolicy = "edgeToEdge" })
		expect(r.rects.actions.rect.w).toBe(620)
		-- the row must be the live candidate and its box must actually hold the
		-- wrapped labels it was chosen with
		expect(r.rects.row.hidden ~= true).toBe(true)
		expect(r.rects.col.hidden).toBe(true)
		expect(r.rects.actions.rect.h >= r.rects.row1.rect.h).toBe(true)
	end)

	it("a stack that exactly fits reports no overflow", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "screen",
			width = fill(),
			height = fill(),
			gap = 10,
			children = {
				{ kind = "box", id = "a", width = fill(), height = fixed(100) },
				{ kind = "box", id = "b", width = fill(), height = fixed(90) },
			},
		}
		local result = solver.solve(root, { w = 300, h = 200 }, { rootPolicy = "edgeToEdge" })
		for _, d in result.diagnostics do
			expect(string.find(d.issue, "content overflows", 1, true) == nil).toBe(true)
		end
	end)
end)

describe("layout: purity and determinism", function()
	local function deepFreeze(node: any): any
		if node.children then
			for _, child in node.children do
				deepFreeze(child)
			end
		end
		return table.freeze(node)
	end

	it("solves a frozen snapshot without mutation and double-solve dumps are identical", function()
		local root = deepFreeze({
			kind = "vstack",
			id = "root",
			padding = 8,
			gap = 4,
			children = {
				{ kind = "text", id = "title", text = "Settings", textSize = 24 },
				{
					kind = "text",
					id = "body",
					text = "a longer wrapping paragraph of settings help text",
					textSize = 16,
				},
				{ kind = "spacer", id = "gap", height = fill(1) },
				{ kind = "box", id = "save", width = fixed(120), height = fixed(44) },
			},
		}) :: solver.Node
		local opts = { safeInsets = { top = 59, bottom = 34, left = 0, right = 0 }, rootPolicy = "coreSafeContent" }
		local d1 = dump.fromSolve(root, { w = 390, h = 844 }, opts)
		local d2 = dump.fromSolve(root, { w = 390, h = 844 }, opts)
		expect(serde.encode("json", d1, true)).toBe(serde.encode("json", d2, true))
		expect(d1.schema).toBe("luauui-dump/2")
	end)
end)

describe("layout: ScrollView fill stretch (phase-3 regression guard)", function()
	it("cross-axis fill children stretch to the scroll viewport", function()
		local root: solver.Node = {
			kind = "scroll",
			id = "list",
			width = fixed(300),
			height = fixed(200),
			axis = "y",
			children = {
				{ kind = "box", id = "card", width = fill(1), height = fixed(72) },
				{ kind = "box", id = "narrow", width = fixed(50), height = fixed(72) },
			},
		}
		local r = solver.solve(root, { w = 800, h = 600 }, { rootPolicy = "edgeToEdge" })
		expect(r.rects.card.rect.w).toBe(300) -- fill stretches to viewport width
		expect(r.rects.narrow.rect.w).toBe(50) -- fixed children keep their size
	end)
end)

-- ===========================================================================
-- DIRECTOR ROUND 9 (2026-07-26): the word-sum's own rounding error
-- ===========================================================================

describe("RS-DIR9: a per-word sum may never reserve LESS than the engine draws", function()
	local text_metrics = require("../src/layout/text_metrics")

	-- MEASURED LIVE (Studio 0.731, stamp 66599d58-1744436). `GetTextBoundsAsync`
	-- reports on a 0.5 px grid, and the engine lays a whole line out in ONE pass.
	-- The space probe (`"x x"` minus `"xx"`, src/client/text_premeasure) returned
	-- 2.50 at BuilderSans@13 while the engine's own inter-word advance in
	-- "Classic Desktop" was 3.00 — exactly one grid step short, reproducibly, on
	-- every 2-word label, and −0.5 PER GAP on a 4-word one ("one two three four":
	-- word-sum 90.00, engine 91.50).
	--
	-- The consequence was visible: the theme picker's chips were sized
	-- `ceil(74.0) + 24 = 98` for a label the engine draws at 74.5 + 24 = 98.5, so
	-- five of the ten chips wrapped a single-line label and clipped it against a
	-- fixed row height. `Classic Desktop` read "Classic"; `Sci-Fi HUD` read
	-- "Sci-Fi HU".
	it("the join slack is added once per inter-word gap when the widths are ENGINE-exact", function()
		text_metrics.resetMeasured()
		local FONT, SIZE = "BuilderSans", 13
		-- the live numbers
		text_metrics.setMeasured(FONT, SIZE, "Classic", 33)
		text_metrics.setMeasured(FONT, SIZE, "Desktop", 38.5)
		text_metrics.setMeasured(FONT, SIZE, " ", 2.5)
		local m = text_metrics.measure("Classic Desktop", FONT, SIZE, math.huge)
		expect(m.exact).toBe(true)
		-- the engine's own answer for the whole string is 74.5
		expect(m.width >= 75).toBe(true)
		text_metrics.resetMeasured()
	end)

	it("three gaps carry three steps: the error accumulates and so does the reservation", function()
		text_metrics.resetMeasured()
		local FONT, SIZE = "BuilderSans", 13
		-- the four word widths that sum to the live wordsum of 90.00 with a 2.5
		-- space: 19 + 20.5 + 27 + 16 = 82.5, plus three 2.5 spaces
		for word, width in { one = 19, two = 20.5, three = 27, four = 16 } do
			text_metrics.setMeasured(FONT, SIZE, word, width)
		end
		text_metrics.setMeasured(FONT, SIZE, " ", 2.5)
		local m = text_metrics.measure("one two three four", FONT, SIZE, math.huge)
		-- word-sum 90.00, engine 91.50 — the reservation must reach the engine
		expect(m.width >= 92).toBe(true)
		text_metrics.resetMeasured()
	end)

	it("a single word carries NO slack: there is no junction to be wrong about", function()
		text_metrics.resetMeasured()
		text_metrics.setMeasured("BuilderSans", 13, "Music", 28)
		local m = text_metrics.measure("Music", "BuilderSans", 13, math.huge)
		expect(m.width).toBe(28)
		text_metrics.resetMeasured()
	end)

	it("an ESTIMATED line is untouched: the estimator already over-reserves", function()
		-- this is what keeps the headless flat baseline byte-identical — no
		-- Lune solve has engine-measured words at all
		text_metrics.resetMeasured()
		local before = text_metrics.measure("hello wide world", "BuilderSans", 16, 1000)
		expect(before.exact).toBe(false)
		local again = text_metrics.measure("hello wide world", "BuilderSans", 16, 1000)
		expect(again.width).toBe(before.width)
	end)

	it("the slack rides the WRAP decision too, so a line breaks before it clips", function()
		text_metrics.resetMeasured()
		local FONT, SIZE = "BuilderSans", 13
		text_metrics.setMeasured(FONT, SIZE, "Classic", 33)
		text_metrics.setMeasured(FONT, SIZE, "Desktop", 38.5)
		text_metrics.setMeasured(FONT, SIZE, " ", 2.5)
		-- 74.0 fits a 74.2 box by the word-sum and does NOT fit by the engine
		local m = text_metrics.measure("Classic Desktop", FONT, SIZE, 74.2)
		expect(m.lines).toBe(2)
		text_metrics.resetMeasured()
	end)
end)

-- ===========================================================================
-- THE LINE CAP (`Text.lineLimit`, device report 2026-07-27)
--
-- A label with no cap measures to its natural wrapped height, the renderer
-- paints a box that tall, and nothing clips — so a three-line name inside a
-- 48px table row painted straight through the rows either side of it. The cap
-- is what gives the engine's TextTruncate.AtEnd something to truncate against.
-- ===========================================================================
describe("A-TXT: lineLimit caps the reserved box", function()
	local FONT, SIZE = "BuilderSans", 15

	it("an uncapped label reserves every line it wraps to", function()
		-- the exact device case: the playlist's name column at 393pt
		local m = text_metrics.measure("Drift City Nights", FONT, SIZE, 60)
		expect(m.lines >= 3).toBe(true)
		expect(m.naturalLines).toBe(m.lines)
		expect(m.truncated).toBe(false)
		-- ...and that box is taller than the row it was supposed to sit in
		expect(m.height > 48).toBe(true)
	end)

	it("a capped label stops at the cap and says it was cut", function()
		local uncapped = text_metrics.measure("Drift City Nights", FONT, SIZE, 60)
		local capped = text_metrics.measure("Drift City Nights", FONT, SIZE, 60, nil, 2)
		expect(capped.lines).toBe(2)
		expect(capped.naturalLines).toBe(uncapped.naturalLines)
		expect(capped.truncated).toBe(true)
		expect(capped.height < uncapped.height).toBe(true)
		-- the invariant the whole mechanism rests on: the reserved height is
		-- exactly the lines that will be DRAWN
		expect(capped.height).toBe(math.ceil(2 * SIZE * 1.2))
	end)

	it("a cap the text does not reach changes nothing", function()
		local plain = text_metrics.measure("Turbo Cascade", FONT, SIZE, 400)
		local capped = text_metrics.measure("Turbo Cascade", FONT, SIZE, 400, nil, 3)
		expect(plain.lines).toBe(1)
		expect(capped.height).toBe(plain.height)
		expect(capped.width).toBe(plain.width)
		expect(capped.truncated).toBe(false)
	end)

	it("a cap below one line still draws one — it is a limit, not an eraser", function()
		local m = text_metrics.measure("Drift City Nights", FONT, SIZE, 60, nil, 0)
		expect(m.lines).toBe(1)
		expect(m.height).toBe(math.ceil(SIZE * 1.2))
	end)

	it("the solver honours a node's lineLimit", function()
		local function heightOf(limit: number?): number
			local out = solver.solve({
				id = "root",
				kind = "vstack",
				width = { type = "fixed", px = 60 },
				height = { type = "content" },
				children = {
					{ id = "label", kind = "text", text = "Drift City Nights", textSize = SIZE, lineLimit = limit },
				},
			}, { w = 60, h = 400 }, { rootPolicy = "edgeToEdge" })
			return out.rects.label.rect.h
		end
		local uncapped, capped = heightOf(nil), heightOf(2)
		expect(uncapped > capped).toBe(true)
		expect(capped).toBe(math.ceil(2 * SIZE * 1.2))
	end)
end)

-- ===========================================================================
-- `hug` — CONTENT SIZE, CAPPED BY THE OFFER (director round 10, 2026-07-26)
--
-- The algebra had `content` (hugs, never capped) and `fill` (capped, never
-- hugs) and nothing that did both. Every panel that wanted to be "as big as it
-- needs and no bigger" had to choose which way to be wrong, and the gallery's
-- theme picker chose `fill`: under a short theme list its raised plate ran to
-- the bottom of a phone with half of it empty, and under a tall one — Fantasy
-- Ornate's taller rows and carved frame — the list ran off the bottom of the
-- viewport and did NOT scroll, because a `fill` box is never smaller than its
-- content so the overflow that turns scrolling on never registered.
-- ===========================================================================
describe("layout: hug (content, capped by the offer)", function()
	local function rows(n: number, h: number): { solver.Node }
		local out: { solver.Node } = {}
		for i = 1, n do
			table.insert(out, { kind = "box", id = `row{i}`, width = fixed(100), height = fixed(h) } :: solver.Node)
		end
		return out
	end

	it("SHORT content: the box stops at the last child instead of filling", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "card",
			width = { type = "hug" },
			height = { type = "hug" },
			children = rows(3, 40),
		}
		local result = solver.solve(root, { w = 400, h = 600 }, { rootPolicy = "edgeToEdge" })
		expect(result.rects.card.rect.h).toBe(120) -- 3 x 40, NOT 600
		expect(result.rects.card.rect.w).toBe(100) -- the widest child, NOT 400
	end)

	it("TALL content: the box stops at the offer instead of running off the screen", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "card",
			height = { type = "hug" },
			children = rows(30, 40), -- 1200 of content in a 600 viewport
		}
		local result = solver.solve(root, { w = 400, h = 600 }, { rootPolicy = "edgeToEdge" })
		expect(result.rects.card.rect.h).toBe(600)
	end)

	it("a hug ScrollView hugs a short list AND scrolls a long one — one declaration", function()
		local function solveWith(n: number)
			local root: solver.Node = {
				kind = "scroll",
				id = "list",
				axis = "y",
				width = fixed(120),
				height = { type = "hug" },
				children = rows(n, 40),
			}
			return solver.solve(root, { w = 400, h = 400 }, { rootPolicy = "edgeToEdge" })
		end
		local short = solveWith(3)
		expect(short.rects.list.rect.h).toBe(120)
		expect(short.rects.list.overflow).never().toBe("scroll") -- nothing to scroll
		local long = solveWith(20)
		expect(long.rects.list.rect.h).toBe(400) -- capped at the offer...
		expect(long.rects.list.contentSize.h).toBe(800) -- ...canvas keeps the truth...
		expect(long.rects.list.overflow).toBe("scroll") -- ...so it scrolls
	end)

	it("a hug child's ceiling is what its SIBLINGS left it, not the whole stack", function()
		-- director round 11, reproduced against the showcase's chrome column: a
		-- `hug` ScrollView under a row of chips was handed the column's ENTIRE
		-- height as its cap, so it reported its full natural content height and ran
		-- off the bottom of the phone by exactly what the chips had spent — while
		-- never discovering it should have been scrolling.
		local root: solver.Node = {
			kind = "vstack",
			id = "column",
			height = fixed(400),
			children = {
				{ kind = "box", id = "chips", width = fixed(100), height = fixed(100) },
				{ kind = "scroll", id = "card", axis = "y", height = { type = "hug" }, children = rows(20, 40) },
			},
		}
		local r = solver.solve(root, { w = 400, h = 400 }, { rootPolicy = "edgeToEdge" })
		expect(r.rects.card.rect.h).toBe(300) -- 400 - the 100 the chips took
		expect(r.rects.card.rect.y + r.rects.card.rect.h).toBe(400) -- flush, not past
		expect(r.rects.card.overflow).toBe("scroll") -- ...and it found its scroll
	end)

	it("two hug siblings each see what the one before it left", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "column",
			height = fixed(300),
			children = {
				{ kind = "vstack", id = "a", height = { type = "hug" }, children = rows(2, 40) },
				{ kind = "vstack", id = "b", height = { type = "hug" }, children = rows(20, 40) },
			},
		}
		local r = solver.solve(root, { w = 400, h = 300 }, { rootPolicy = "edgeToEdge" })
		expect(r.rects.a.rect.h).toBe(80) -- hugs its own short content
		expect(r.rects.b.rect.h).toBe(220) -- capped at what is left, not at 300
		expect(r.rects.b.rect.y + r.rects.b.rect.h).toBe(300)
	end)

	it("a hug child resolves BEFORE fill shares the remainder", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "column",
			height = fixed(400),
			children = {
				{ kind = "vstack", id = "card", height = { type = "hug" }, children = rows(3, 40) },
				{ kind = "box", id = "rest", height = fill() },
			},
		}
		local r = solver.solve(root, { w = 400, h = 400 }, { rootPolicy = "edgeToEdge" })
		expect(r.rects.card.rect.h).toBe(120) -- what it needs...
		expect(r.rects.rest.rect.h).toBe(280) -- ...and fill takes what is over
	end)

	it("min/max clamp the content BEFORE the offer does", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "card",
			height = { type = "hug", min = 200, max = 300 },
			children = rows(1, 40),
		}
		expect(solver.solve(root, { w = 400, h = 600 }, { rootPolicy = "edgeToEdge" }).rects.card.rect.h).toBe(200)
		local tall: solver.Node = {
			kind = "vstack",
			id = "card",
			height = { type = "hug", min = 200, max = 300 },
			children = rows(20, 40),
		}
		expect(solver.solve(tall, { w = 400, h = 600 }, { rootPolicy = "edgeToEdge" }).rects.card.rect.h).toBe(300)
	end)
end)

-- ===========================================================================
-- AN ANCHOR CHILD PAYS FOR ITS OWN OFFSET (director round 10, 2026-07-26)
--
-- A `fill` child used to take the whole anchor box and THEN get displaced, so
-- it hung off the far edge by exactly the offset — silently, because nothing
-- clips an anchor. The gallery's chrome column is this shape (`topLeft` +
-- `height = fill` + `offsetY = the CoreGui topbar inset`), so on a phone its
-- bottom ran off the screen by the topbar's height and whatever sat in that
-- strip was unreachable.
-- ===========================================================================
describe("layout: a fill anchor child pays for its own offset", function()
	local function anchored(anchor: string, offsetX: number?, offsetY: number?): any
		local root: solver.Node = {
			kind = "anchor",
			id = "dock",
			width = fixed(200),
			height = fixed(200),
			children = {
				{
					kind = "box",
					id = "bar",
					anchor = anchor,
					offsetX = offsetX,
					offsetY = offsetY,
					width = fill(),
					height = fill(),
				},
			},
		}
		return solver.solve(root, { w = 200, h = 200 }, { rootPolicy = "edgeToEdge" }).rects.bar.rect
	end

	it("a leading-anchored bar pushed down loses exactly that much height", function()
		local r = anchored("topLeft", nil, 30)
		expect(r.y).toBe(30)
		expect(r.h).toBe(170) -- 200 - 30: the bottom edge lands ON the dock's
		expect(r.y + r.h).toBe(200)
	end)

	it("a trailing-anchored bar pulled in loses exactly that much width", function()
		local r = anchored("topRight", -24, nil)
		expect(r.w).toBe(176)
		expect(r.x).toBe(0) -- (200-176)*1 - 24 = 0: flush at the leading edge
		expect(r.x + r.w).toBe(176)
	end)

	it("a CENTRED bar gives back twice its offset — it loses room at both ends", function()
		local r = anchored("center", 20, nil)
		expect(r.w).toBe(160) -- 200 - 2*20
		expect(r.x).toBe(40)
		expect(r.x + r.w).toBe(200)
	end)

	it("no offset is still the whole box — the common case does not move", function()
		local r = anchored("topLeft")
		expect(r.x).toBe(0)
		expect(r.y).toBe(0)
		expect(r.w).toBe(200)
		expect(r.h).toBe(200)
	end)

	it("pushed OUT past its own anchored edge is left alone — that is deliberate", function()
		-- an off-screen drawer / a peeking tab: no width brings it back, because
		-- the overflow is the offset itself, so shrinking would only make it smaller
		-- AND still outside.
		local r = anchored("topRight", 40, nil)
		expect(r.w).toBe(200)
		expect(r.x).toBe(40)
	end)
end)

describe("layout: a fill ZStack child pays for its own MARGIN", function()
	local function stacked(margin: any, alignH: string?, alignV: string?): any
		local root: solver.Node = {
			kind = "zstack",
			id = "stack",
			width = fixed(200),
			height = fixed(200),
			children = {
				{
					kind = "box",
					id = "layer",
					margin = margin,
					alignH = alignH,
					alignV = alignV,
					width = fill(),
					height = fill(),
				},
			},
		}
		return solver.solve(root, { w = 200, h = 200 }, { rootPolicy = "edgeToEdge" }).rects.layer.rect
	end

	-- Found live 2026-07-31 (RascalRally's parallel Sponsor HUD): a pose region
	-- reserved a top band for its chip row with `margin = { top = 56 }` and ran 56
	-- px PAST the safe area on every phone. Arrange displaced the child by the
	-- margin and then handed it the stack's whole inner box — the same shape the
	-- `anchor` branch above already fixed for OFFSETS, on the sibling nobody had
	-- reached for. Measure has always counted margins here (`cw = max(cw, w+ml+mr)`),
	-- so this is arrange catching up with measure.
	it("a top margin is room the child does not get, not a displacement", function()
		local r = stacked({ top = 56 })
		expect(r.y).toBe(56)
		expect(r.h).toBe(144) -- 200 - 56: the bottom edge lands ON the stack's
		expect(r.y + r.h).toBe(200)
	end)

	it("margins on both sides of an axis both come out of the fill", function()
		local r = stacked({ left = 10, right = 30, top = 4, bottom = 6 })
		expect(`{r.x},{r.w}`).toBe("10,160")
		expect(`{r.y},{r.h}`).toBe("4,190")
	end)

	it("a number margin applies to all four sides", function()
		local r = stacked(8)
		expect(`{r.x},{r.y},{r.w},{r.h}`).toBe("8,8,184,184")
	end)

	it("a filled axis ignores alignment — there is nothing left to align", function()
		-- a fill child spans its whole (post-margin) box, so `alignH`/`alignV`
		-- cannot move it; asserting it keeps a centred fill from drifting by half
		-- its own margin the way an align-on-the-full-box computation would
		expect(`{stacked({ top = 56 }, "center", "center").y}`).toBe("56")
		expect(`{stacked({ left = 20 }, "end", "end").x}`).toBe("20")
	end)

	it("a NON-fill child keeps the alignment it always had (no silent re-flow)", function()
		local root: solver.Node = {
			kind = "zstack",
			id = "stack",
			width = fixed(200),
			height = fixed(200),
			alignH = "center",
			alignV = "center",
			children = {
				{ kind = "box", id = "chip", margin = { top = 2, left = 2 }, width = fixed(20), height = fixed(20) },
			},
		}
		local r = solver.solve(root, { w = 200, h = 200 }, { rootPolicy = "edgeToEdge" }).rects.chip.rect
		--[[ RE-AIMED 2026-08-15, and this is not a weakened pin — it is a pin whose
			stated reason was never true.

			It asserted 92: centred in the FULL box, then displaced by the margin.
			The justification given was "the table control's ghost chip stack is
			exactly this shape and its 2 px stagger has to stay 2 px", and the ghost
			stack is NOT this shape — `DragGhost` sets no `alignH`/`alignV`, so its
			chips were placed `start` on X and stepped a clean 2 px there all along.
			(The vertical axis WAS centred, by a different route: each chip carried
			`alignV = "center"` meaning "center my label", which its parent read as
			placement — `docs/lessons/one-word-two-subsystems.md`. That is fixed at
			the chip, and `tests/table.spec.luau`'s drag-ghost spec now asserts the
			2 px step on BOTH axes, so the consumer claim above is finally a checked
			one rather than a sentence.)

			What the number becomes: the child is offered 198 (200 minus its 2 px
			left margin), centres in THAT, and sits at 2 + (198-20)/2 = 91. The
			`no silent re-flow` promise in the title survives where it was aimed —
			an unmargined child does not move at all — so that is what the second
			assertion is for. ]]
		expect(`{r.x},{r.y}`).toBe("91,91")
		local plain: solver.Node = {
			kind = "zstack",
			id = "plain",
			width = fixed(200),
			height = fixed(200),
			alignH = "center",
			alignV = "center",
			children = { { kind = "box", id = "chip", width = fixed(20), height = fixed(20) } },
		}
		local p = solver.solve(plain, { w = 200, h = 200 }, { rootPolicy = "edgeToEdge" }).rects.chip.rect
		expect(`{p.x},{p.y}`).toBe("90,90")
	end)

	it("margins wider than the stack clamp to zero rather than going negative", function()
		local r = stacked({ left = 150, right = 150 })
		expect(r.w).toBe(0)
	end)
end)

--[[ =============================================================== 2026-08-15
	A HUGGING ZStack CHILD PAYS FOR ITS OWN MARGIN TOO — the other half of the
	2026-07-31 fix above, and the half that was left undone.

	That round taught `arrange` to shrink a FILL child by its margins so it stops
	hanging off the far edge. A child that sizes ITSELF (a glyph, a chip, a badge)
	got the deficit subtracted from its offer — `availW = innerW - ml - mr`, right
	there in the same loop — and was then placed with `alignOffset(align, innerW,
	w)`: aligned inside the box it was NOT given. For `start` that is harmless
	(x = ml either way), which is why it survived. For `end` and `center` it is a
	silent lie:

	  · `end`   x = ml + innerW - w, so the child's FAR edge lands on the stack's
	            inner edge and `margin.right` buys nothing at all — a reserve the
	            author declared, that the solver simply drops;
	  · `center` the child centres in the full box and is then displaced by `ml`,
	            so an asymmetric margin moves it by the wrong amount.

	FOUND LIVE (director, Studio, 2026-08-14, showcase `table_columns` — retired
	2026-08-16 into the playlist tutorial — under Pixel
	Quest and Glossy Touch): "the triangle table header sort indicator appears
	outside when themed". The Table's sort mark is exactly this shape — a hugging
	`alignH = "end"` Text carrying `margin = { right = controls.table.sortMarkMargin }`,
	the theme's own written reserve "keeps the ▲/▼ clear" — and every package
	solved it flush against the column boundary, 0 px of the 14-16 it asked for.
	Under a flat package that boundary is invisible; under a package that paints a
	nine-slice plate on the header cell it is the plate's carved border, so the
	glyph sat outside the box. Default theme fine, five of eight packages wrong:
	the same "painted at a size nobody measured" family, with the measurement
	itself correct and the PLACEMENT spending a box that was never granted.

	`docs/lessons/a-far-margin-must-buy-something.md`. ]]
describe("layout: a HUGGING ZStack child pays for its own margin too", function()
	local function hugged(margin: any, alignH: string?, alignV: string?): any
		local root: solver.Node = {
			kind = "zstack",
			id = "stack",
			width = fixed(200),
			height = fixed(200),
			children = {
				{
					kind = "box",
					id = "mark",
					margin = margin,
					alignH = alignH,
					alignV = alignV,
					width = fixed(20),
					height = fixed(20),
				},
			},
		}
		return solver.solve(root, { w = 200, h = 200 }, { rootPolicy = "edgeToEdge" }).rects.mark.rect
	end

	it("an END-aligned child stops a FAR margin short of the edge", function()
		local r = hugged({ right = 14 }, "end")
		-- the whole defect in one number: the far edge is 14 px inside the stack,
		-- not on it. Before the fix this was 200.
		expect(r.x + r.w).toBe(186)
		expect(r.x).toBe(166)
	end)

	it("...on the vertical axis too", function()
		local r = hugged({ bottom = 14 }, nil, "end")
		expect(r.y + r.h).toBe(186)
	end)

	it("a NEAR margin still pushes an end-aligned child AWAY from its own edge", function()
		-- `margin.left` on an end-aligned child is room the child does not get, so
		-- it cannot push the child THROUGH the far edge: it shrinks the box the
		-- alignment runs in, and a hugging child is already at that box's end.
		expect(hugged({ left = 20 }, "end").x + 20).toBe(200)
	end)

	it("a CENTRED child centres in the box it was GIVEN, not the box it was denied", function()
		-- (200 - 10 - 30 - 20) / 2 = 70, plus the 10 left margin = 80. The old
		-- arithmetic answered 100: centred in the full box, then displaced by ml.
		expect(hugged({ left = 10, right = 30 }, "center").x).toBe(80)
		-- a symmetric margin is the case that cannot tell the two apart, so it
		-- pins that the fix did not move it
		expect(hugged({ left = 10, right = 10 }, "center").x).toBe(90)
	end)

	it("a START-aligned child is unmoved — it always sat at its near margin", function()
		expect(hugged({ left = 12, right = 40 }, "start").x).toBe(12)
		expect(hugged({ left = 12, right = 40 }, nil).x).toBe(12)
	end)
end)

--[[ ================================================================ 2026-08-02
	A LAYERED CHILD BIGGER THAN ITS BOX.

	The flow-stack overflow diagnostic above cannot see this one: a ZStack has no
	main axis to overflow, so a child measured bigger than the box simply paints
	outside it — nothing clips a ZStack. Found live three times; the last was a
	coin pill in a 34 px box that was 58 px tall and painted straight through the
	label above it, on two devices, before anyone noticed. The solver knew the
	number every time and never said it.
============================================================================ ]]
describe("solver — a ZStack child that overflows its box is reported", function()
	local function stack(boxH: number, childH: number, overflow: string?): any
		return {
			kind = "zstack",
			id = "body",
			width = fixed(200),
			height = fixed(boxH),
			overflow = overflow,
			children = {
				{ kind = "box", id = "pill", width = fixed(120), height = fixed(childH) },
			},
		}
	end

	it("names the CHILD and states the overrun", function()
		local result = solver.solve(stack(34, 58), { w = 400, h = 400 }, { rootPolicy = "edgeToEdge" })
		local found = nil
		for _, d in result.diagnostics do
			if d.node == "pill" then
				found = d
			end
		end
		expect(`named={found ~= nil}`).toBe("named=true")
		expect(`states={string.find(tostring((found :: any).issue), "24", 1, true) ~= nil}`).toBe("states=true")
	end)

	it("a child that FITS reports nothing — the check is not noise", function()
		local result = solver.solve(stack(60, 58), { w = 400, h = 400 }, { rootPolicy = "edgeToEdge" })
		for _, d in result.diagnostics do
			expect(`quiet={d.node}`).toBe("quiet=")
		end
	end)

	it("`intentionalOverlap` is the opt-out for layouts whose job IS to stack over", function()
		local result = solver.solve(
			stack(34, 58, "intentionalOverlap"),
			{ w = 400, h = 400 },
			{ rootPolicy = "edgeToEdge" }
		)
		for _, d in result.diagnostics do
			expect(`quiet={d.node}`).toBe("quiet=")
		end
	end)

	it("it is a REPORT, not a failure: the layout still resolves", function()
		--[[ An honestly cramped offer produces the same measure, so stopping a
			screen to report an authoring mistake is the worse trade. ]]
		local result = solver.solve(stack(34, 58), { w = 400, h = 400 }, { rootPolicy = "edgeToEdge" })
		expect(`resolved={result.rects.pill ~= nil}`).toBe("resolved=true")
	end)
end)
