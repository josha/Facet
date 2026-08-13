--!strict
--[[
	SILENTLY-INERT PLACEMENT PROPS (docs/plans/swiftui-parity-round2.md §2.1).

	`anchor`, `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign`, `gridSpan`,
	`layoutPriority` and `shrinkWeight` are shared BOX props — legal on every node
	— but not one of them is a fact the
	node has of its own. Each is an instruction addressed to a particular kind of
	PARENT, and every arrange branch reads only the ones it knows. Everywhere else
	the framework ACCEPTED the prop and then IGNORED it, which constitution §4
	forbids: nothing moved, nothing said so, and the author's only evidence was a
	screenshot that looked wrong for no stated reason.

	The child cannot catch this — it does not know its parent at its own
	construction — so the PARENT does, in `solver.auditPlacement`, called from
	`renderer.toLayoutNode` (where the class has already become the layout kind,
	and where `UI.When`/`UI.ForEach` children have already spliced into the real
	parent's flow) and reported by `arrange` (which is what gates it behind
	`hiddenDepth` and replays it through the incremental-layout reuse path).

	WHAT EACH DESCRIBE WOULD CATCH:

	  1. "the inert cell reports"   — a read table that forgets a cell, or an
	     audit that never runs for that parent kind. Every cell of §2.1's table
	     is a case, and each asserts the prop NAME and that NOTHING MOVED.
	  2. "the honoured cell is silent" — an audit that fires on a working prop.
	     This is the expensive failure: a false positive here is a refusal that
	     un-ships a shipped screen. The ZStack self-read (`UI.ZStack{alignH}` is
	     the CONTAINER's default for its own children, not a placement request)
	     is the one that a naive table gets wrong.
	  3. "the message names the way out" — a message that states only the
	     prohibition gets deleted by the next agent who cannot see why it is
	     there. Each asserts the reason AND the working spelling.
	  4. "a spliced child is audited too" — the case a construction-time check
	     structurally cannot see, and the reason this tier exists at all.
	  5. "a hidden subtree does not shout" — the `hiddenDepth` gate.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local FILL = { type = "fill", weight = 1 }
local function px(n: number)
	return { type = "fixed", px = n }
end
local function box(id: string, w: number, h: number, extra: any?): any
	local spec: any = { id = id, width = px(w), height = px(h) }
	for k, v in (extra or {}) :: any do
		spec[k] = v
	end
	return UI.Box(spec)
end

local function mountedWith(core: any, bp: any, w: number, h: number)
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return controller
end

-- ALL NINE, not seven: `layoutPriority`/`shrinkWeight` joined the watched set in
-- the Milestone-1 review (C2) — they shipped in the same parity round as this
-- audit, in the schema paragraph that names `lineAlign`/`gridSpan`, and were left
-- out of the solver's read table and the renderer's fast reject alike.
local ALL_NINE = {
	"anchor",
	"offsetX",
	"offsetY",
	"alignH",
	"alignV",
	"lineAlign",
	"gridSpan",
	"layoutPriority",
	"shrinkWeight",
}

-- a value that is legal for each prop's own type
local function valueFor(prop: string): any
	if prop == "offsetX" or prop == "offsetY" then
		return 17
	elseif prop == "gridSpan" then
		return 2
	elseif prop == "layoutPriority" then
		return 3
	elseif prop == "shrinkWeight" then
		return 2
	elseif prop == "anchor" then
		return "bottomRight"
	end
	return "end"
end

local function mounted(bp: any, w: number, h: number)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return controller
end

-- every finding whose message mentions `prop`, as "<node>" strings
local function findings(controller: any, prop: string): { string }
	local out: { string } = {}
	for _, d in controller.diagnostics() do
		if string.find(d.issue, `\`{prop}\` is a placement prop`, 1, true) ~= nil then
			table.insert(out, d.node)
		end
	end
	table.sort(out)
	return out
end

local function issueFor(controller: any, node: string, prop: string): string
	for _, d in controller.diagnostics() do
		if d.node == node and string.find(d.issue, `\`{prop}\` is a placement prop`, 1, true) ~= nil then
			return d.issue
		end
	end
	return `<no finding for {node}/{prop}>`
end

-- the whole diagnostic channel, so a case can assert SILENCE and not merely the
-- absence of its own finding
local function allIssues(controller: any): string
	local out: { string } = {}
	for _, d in controller.diagnostics() do
		table.insert(out, `{d.node}: {d.issue}`)
	end
	table.sort(out)
	return table.concat(out, " | ")
end

describe("§2.1 the inert cell reports, and nothing moved", function()
	it("`anchor` under a ZStack: reported, and the child is not placed by corner", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ZStack({
						id = "Z",
						width = px(200),
						height = px(100),
						children = { box("K", 40, 40, { anchor = "bottomRight" }) },
					}),
				},
			}),
			400,
			400
		)
		expect(table.concat(findings(c, "anchor"), ",")).toBe("/S/Z/K")
		-- the proof that the report is TRUE: a bottomRight corner would be
		-- (200-40, 100-40) = (160, 60); the zstack put it at its own origin
		local r = c.rectOf("/S/Z/K")
		expect(`{r.x},{r.y}`).toBe("0,0")
	end)

	it("`offsetX`/`offsetY` under an HStack: reported as a pair, and the child does not shift", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.HStack({ id = "H", children = { box("K", 40, 40, { offsetX = 25, offsetY = 35 }) } }),
				},
			}),
			400,
			400
		)
		expect(table.concat(findings(c, "offsetX"), ",")).toBe("/S/H/K")
		expect(table.concat(findings(c, "offsetY"), ",")).toBe("/S/H/K")
		local r = c.rectOf("/S/H/K")
		expect(`{r.x},{r.y}`).toBe("0,0")
	end)

	it("`alignH`/`alignV` under a VStack: reported, and `lineAlign` is the spelling that DOES move it", function()
		local function build(prop: string)
			local extra: any = {}
			extra[prop] = "end"
			return mounted(
				UI.Screen({
					id = "S",
					children = { UI.VStack({ id = "V", width = px(300), children = { box("K", 40, 40, extra) } }) },
				}),
				400,
				400
			)
		end
		local inert = build("alignH")
		expect(table.concat(findings(inert, "alignH"), ",")).toBe("/S/V/K")
		expect(inert.rectOf("/S/V/K").x).toBe(0)
		-- ...and the way out the message names actually works, which is the whole
		-- reason this cell became refusable only once `lineAlign` shipped
		local fixed = build("lineAlign")
		expect(table.concat(findings(fixed, "lineAlign"), ",")).toBe("")
		expect(fixed.rectOf("/S/V/K").x).toBe(260)
	end)

	it("`alignH` under a ViewThatFits candidate: reported (the live Rascal Rally shape)", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ViewThatFits({
						id = "F",
						width = FILL,
						children = { UI.HStack({ id = "Row", alignH = "center", children = { box("K", 40, 40) } }) },
					}),
				},
			}),
			400,
			400
		)
		expect(table.concat(findings(c, "alignH"), ",")).toBe("/S/F/Row")
	end)

	it(
		"`anchor`/`offsetX`/`offsetY` on an Anchor under a Screen: reported (the live row-actions menu shape)",
		function()
			local c = mounted(
				UI.Screen({
					id = "S",
					children = {
						UI.Anchor({
							id = "Menu",
							anchor = "topLeft",
							offsetX = 120,
							offsetY = 200,
							children = { box("K", 60, 40) },
						}),
					},
				}),
				400,
				400
			)
			expect(table.concat(findings(c, "offsetX"), ",")).toBe("/S/Menu")
			expect(table.concat(findings(c, "offsetY"), ",")).toBe("/S/Menu")
			-- the report is TRUE: the menu asked to sit at (120, 200) and sits at the origin
			local r = c.rectOf("/S/Menu")
			expect(`{r.x},{r.y}`).toBe("0,0")
		end
	)

	it("`lineAlign` under a ZStack, and `gridSpan` outside a GridRow: both reported", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ZStack({
						id = "Z",
						width = px(200),
						height = px(100),
						children = { box("K", 40, 40, { lineAlign = "end" }) },
					}),
					UI.Grid({
						id = "G",
						columns = 2,
						width = px(200),
						children = { box("C", 40, 40, { gridSpan = 2 }) },
					}),
				},
			}),
			400,
			400
		)
		expect(table.concat(findings(c, "lineAlign"), ",")).toBe("/S/Z/K")
		expect(table.concat(findings(c, "gridSpan"), ",")).toBe("/S/G/C")
	end)

	it("a UI.GridRow refuses every placement prop at CONSTRUCTION — the schema closes that cell", function()
		-- the one cell of the §2.1 table that needs no audit branch: a row's prop
		-- set is paint-only, so there is no way to author the inert case at all
		for _, prop in ALL_NINE do
			local spec: any = { id = "R", children = { box("A", 40, 40) } }
			spec[prop] = valueFor(prop)
			local ok, err = pcall(function()
				return UI.GridRow(spec)
			end)
			expect(`{prop}:{ok}`).toBe(`{prop}:false`)
			expect(string.find(tostring(err), `unknown property '{prop}'`, 1, true) ~= nil).toBe(true)
		end
	end)
end)

describe("§2.1 the honoured cell is SILENT — a false positive here un-ships a screen", function()
	it("a ZStack's own alignH/alignV are the CONTAINER's default, never a placement request", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "H",
						children = {
							UI.ZStack({
								id = "Z",
								alignH = "end",
								alignV = "end",
								width = px(200),
								height = px(100),
								children = { box("K", 40, 40) },
							}),
						},
					}),
				},
			}),
			400,
			400
		)
		expect(allIssues(c)).toBe("")
		-- ...and it really is doing work: the child sits at the far corner
		local r = c.rectOf("/S/H/Z/K")
		expect(`{r.x},{r.y}`).toBe("160,60")
	end)

	it("every honoured cell of the §2.1 table is silent", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					-- Anchor reads anchor + offsetX/offsetY
					UI.Anchor({
						id = "A",
						width = px(200),
						height = px(100),
						children = { box("Ak", 40, 40, { anchor = "bottomRight", offsetX = -5, offsetY = -5 }) },
					}),
					-- ZStack reads alignH/alignV off each child
					UI.ZStack({
						id = "Z",
						width = px(200),
						height = px(100),
						children = { box("Zk", 40, 40, { alignH = "center", alignV = "end" }) },
					}),
					-- stacks read lineAlign
					UI.VStack({ id = "V", width = px(200), children = { box("Vk", 40, 40, { lineAlign = "center" }) } }),
					-- flow Grid reads alignH/alignV per cell
					UI.Grid({
						id = "G",
						columns = 2,
						width = px(200),
						children = { box("Gk", 40, 40, { alignH = "end", alignV = "end" }) },
					}),
					-- a GridRow reads alignH/alignV AND gridSpan off its cells
					UI.Grid({
						id = "RG",
						width = px(300),
						children = {
							UI.GridRow({
								id = "R",
								children = { box("Rk", 40, 40, { alignH = "end", gridSpan = 2 }), box("Rk2", 40, 40) },
							}),
						},
					}),
					-- a scroller reads offsetX/offsetY as its nudge
					UI.ScrollView({
						id = "Sc",
						height = px(80),
						children = { box("Sk", 40, 40, { offsetY = 12 }) },
					}),
				},
			}),
			600,
			900
		)
		expect(allIssues(c)).toBe("")
	end)
end)

describe("§2.1 the message names the REASON and the way out", function()
	it("`alignH` under an HStack points at lineAlign and says why nothing moved", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = { UI.HStack({ id = "H", children = { box("K", 40, 40, { alignV = "center" }) } }) },
			}),
			400,
			400
		)
		local issue = issueFor(c, "/S/H/K", "alignV")
		expect(string.find(issue, "stacking them across a line", 1, true) ~= nil).toBe(true)
		expect(string.find(issue, "accepted and then ignored", 1, true) ~= nil).toBe(true)
		expect(string.find(issue, "`lineAlign`", 1, true) ~= nil).toBe(true)
	end)

	it("`offsetX` under a ZStack points at UI.Anchor", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ZStack({
						id = "Z",
						width = px(200),
						height = px(100),
						children = { box("K", 40, 40, { offsetX = 9 }) },
					}),
				},
			}),
			400,
			400
		)
		expect(string.find(issueFor(c, "/S/Z/K", "offsetX"), "`UI.Anchor`", 1, true) ~= nil).toBe(true)
	end)

	it("`anchor` under a ZStack points at alignH/alignV, not at UI.Anchor", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ZStack({
						id = "Z",
						width = px(200),
						height = px(100),
						children = { box("K", 40, 40, { anchor = "top" }) },
					}),
				},
			}),
			400,
			400
		)
		expect(string.find(issueFor(c, "/S/Z/K", "anchor"), "use `alignH`/`alignV`", 1, true) ~= nil).toBe(true)
	end)
end)

describe("§2.1 tier 2: the children a construction-time check cannot see", function()
	it("a UI.When child is audited against the parent it SPLICES into, not against the When", function()
		local core = customFactory.new()
		local c = mountedWith(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "H",
						children = {
							UI.When({
								id = "W",
								condition = core:signal(true),
								thenView = function()
									return box("K", 40, 40, { alignH = "end" })
								end,
							}),
						},
					}),
				},
			}),
			400,
			400
		)
		expect(table.concat(findings(c, "alignH"), ",")).toBe("/S/H/W/then/K")
	end)

	it("a UI.ForEach row is audited against the real parent kind", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ZStack({
					id = "Z",
					width = px(200),
					height = px(100),
					children = {
						UI.ForEach({
							id = "F",
							items = core:signal({ "a", "b" }),
							key = function(item: any)
								return item
							end,
							row = function(item: any)
								-- `anchor` is the ZStack's inert cell; alignH is its honoured one
								return box(`Row_{item}`, 20, 20, { anchor = "center", alignH = "center" })
							end,
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local c = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		c.initialRender()
		expect(table.concat(findings(c, "anchor"), ",")).toBe("/S/Z/F/[a]/Row_a,/S/Z/F/[b]/Row_b")
		-- ...and the HONOURED prop on the same spliced rows stays silent
		expect(table.concat(findings(c, "alignH"), ",")).toBe("")
	end)
end)

describe("§2.1 the hiddenDepth gate", function()
	it("a losing ViewThatFits candidate does not shout about its own children", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ViewThatFits({
						id = "F",
						children = {
							-- the winner at 400px: no inert props
							UI.HStack({ id = "Win", children = { box("W", 40, 40) } }),
							UI.HStack({ id = "Lose", children = { box("L", 40, 40, { anchor = "center" }) } }),
						},
					}),
				},
			}),
			400,
			400
		)
		expect(table.concat(findings(c, "anchor"), ",")).toBe("")
	end)
end)

--[[ THE CELLS THE §2.1 TABLE LEFT BLANK, WHICH WERE NEVER EXEMPTIONS.

	That table printed `—` or `n/a` in ten cells — `anchor` under a ScrollView or a
	Grid, `alignH`/`alignV` under an Anchor or a ScrollView — and omitted the three
	rank/region containers (`ViewThatFits`, `Composition`, `Region`) entirely. A
	blank read as "does not apply". It never did: those props are legal on every
	box, so they are AUTHORABLE in every one of those positions, and in every one of
	them the parent's arrange reads nothing. A blank cell and an `inert` cell are
	the same defect; only the documentation differed.

	Each case below is the cell, driven as a matrix so a read table that grows a
	kind cannot quietly leave one out. Every assertion names the NODE, so a check
	that reported the wrong child would fail here rather than pass on a count. ]]
local function withProps(id: string, props: { string }): any
	local extra: any = {}
	for _, prop in props do
		extra[prop] = valueFor(prop)
	end
	return box(id, 40, 40, extra)
end

-- assert EXACTLY the expected prop set is reported for `node`, no more and no
-- fewer: a check that only asserts presence cannot see a false positive, which is
-- the failure mode that un-ships a screen
local function reportedProps(controller: any, node: string): string
	local out: { string } = {}
	for _, d in controller.diagnostics() do
		if d.node == node then
			local prop = string.match(d.issue, "^`([%a]+)` is a placement prop")
			if prop ~= nil then
				table.insert(out, prop)
			end
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function expectCell(controller: any, node: string, expected: { string })
	local want = table.clone(expected)
	table.sort(want)
	expect(`{node}=>{reportedProps(controller, node)}`).toBe(`{node}=>{table.concat(want, ",")}`)
end

describe("§2.1 the blank cells: every prop is authorable everywhere, so every parent is policed", function()
	it(
		"under an Anchor: the two aligns and `lineAlign` and `gridSpan` are inert; the three it reads are not",
		function()
			local c = mounted(
				UI.Screen({
					id = "S",
					children = {
						UI.Anchor({
							id = "A",
							width = px(200),
							height = px(100),
							children = { withProps("K", ALL_NINE) },
						}),
					},
				}),
				400,
				400
			)
			expectCell(c, "/S/A/K", { "alignH", "alignV", "lineAlign", "gridSpan", "layoutPriority", "shrinkWeight" })
			-- ...and the three it DOES read really did place the child, which is what
			-- makes their absence from the report a fact rather than a gap
			local r = c.rectOf("/S/A/K")
			expect(`{r.x},{r.y}`).toBe(`{200 - 40 + 17},{100 - 40 + 17}`)
		end
	)

	it("under a ScrollView: `anchor`, both aligns, `lineAlign` and `gridSpan` are inert", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({ id = "Sc", height = px(80), children = { withProps("K", ALL_NINE) } }),
				},
			}),
			400,
			400
		)
		expectCell(
			c,
			"/S/Sc/K",
			{ "anchor", "alignH", "alignV", "lineAlign", "gridSpan", "layoutPriority", "shrinkWeight" }
		)
	end)

	it("under a flow Grid: `anchor`, both offsets, `lineAlign` and `gridSpan` are inert", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.Grid({ id = "G", columns = 2, width = px(200), children = { withProps("K", ALL_NINE) } }),
				},
			}),
			400,
			400
		)
		expectCell(
			c,
			"/S/G/K",
			{ "anchor", "offsetX", "offsetY", "lineAlign", "gridSpan", "layoutPriority", "shrinkWeight" }
		)
	end)

	it("under a stack: everything but `lineAlign` and the shrink pair is inert, on BOTH axes", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({ id = "V", width = px(300), children = { withProps("Vk", ALL_NINE) } }),
					UI.HStack({ id = "H", width = px(300), children = { withProps("Hk", ALL_NINE) } }),
				},
			}),
			400,
			400
		)
		-- `lineAlign` AND the shrink pair are the three a stack reads off a child
		local rest = { "anchor", "offsetX", "offsetY", "alignH", "alignV", "gridSpan" }
		expectCell(c, "/S/V/Vk", rest)
		expectCell(c, "/S/H/Hk", rest)
	end)

	it("under a ZStack: everything but the two aligns is inert", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ZStack({ id = "Z", width = px(200), height = px(100), children = { withProps("K", ALL_NINE) } }),
				},
			}),
			400,
			400
		)
		expectCell(
			c,
			"/S/Z/K",
			{ "anchor", "offsetX", "offsetY", "lineAlign", "gridSpan", "layoutPriority", "shrinkWeight" }
		)
	end)

	it("under a ViewThatFits candidate: ALL NINE are inert — a candidate is placed by rank", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = { UI.ViewThatFits({ id = "F", width = FILL, children = { withProps("K", ALL_NINE) } }) },
			}),
			400,
			400
		)
		expectCell(c, "/S/F/K", ALL_NINE)
	end)

	it("a UI.Region refuses every placement prop at CONSTRUCTION — the schema closes that cell too", function()
		-- FOUND BY WRITING THIS CASE, not by reading the table: `UI.Region`'s prop
		-- set is as closed as `UI.GridRow`'s (`floor`/`group`/`mayDrop`/`mayScroll`/
		-- `rank`/`reserved`/`sizing`/`weight` and nothing else), and a Composition
		-- refuses any child that is not a Region. So the `composition` cell cannot be
		-- authored at all, and the read table carries no branch for it — the same
		-- call the row-grid cell already made. This case is what keeps that removal
		-- honest: loosen Region's schema and this goes red.
		for _, prop in ALL_NINE do
			local spec: any = { id = "R", group = "g", rank = 1, children = { box("A", 40, 40) } }
			spec[prop] = valueFor(prop)
			local ok, err = pcall(function()
				return UI.Region(spec)
			end)
			expect(`{prop}:{ok}`).toBe(`{prop}:false`)
			expect(string.find(tostring(err), `unknown property '{prop}'`, 1, true) ~= nil).toBe(true)
		end
	end)

	it("under a Region (its chosen form): ALL NINE are inert", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				width = FILL,
				height = FILL,
				children = {
					UI.Composition({
						id = "C",
						arrangements = { "threeLane" },
						laneGap = 12,
						width = FILL,
						height = FILL,
						groups = { { id = "field", lane = "main", sizing = "fill" } },
						children = {
							UI.Region({
								id = "R",
								group = "field",
								rank = 1,
								sizing = "fill",
								children = { withProps("Form", ALL_NINE) },
							}),
						},
					}),
				},
			}),
			600,
			400
		)
		expectCell(c, "/S/C/R/Form", ALL_NINE)
	end)
end)

describe("§2.1 the FOUR props this same phase shipped are in the watched set", function()
	-- `lineAlign` (§2.1) and `gridSpan` (§2.2) landed WITH the defect class they
	-- belong to, and `gridSpan`'s inertness was written into `blueprint_schema.luau`
	-- as though it were part of the feature. Both are policed like the older five.
	it("`lineAlign` is reported under every parent that is not a stack", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ZStack({
						id = "Z",
						width = px(200),
						height = px(80),
						children = { box("Zk", 40, 40, { lineAlign = "end" }) },
					}),
					UI.Anchor({
						id = "A",
						width = px(200),
						height = px(80),
						children = { box("Ak", 40, 40, { lineAlign = "end" }) },
					}),
					UI.Grid({
						id = "G",
						columns = 2,
						width = px(200),
						children = { box("Gk", 40, 40, { lineAlign = "end" }) },
					}),
					UI.ScrollView({
						id = "Sc",
						height = px(80),
						children = { box("Sk", 40, 40, { lineAlign = "end" }) },
					}),
					UI.ViewThatFits({
						id = "F",
						width = px(200),
						children = { box("Fk", 40, 40, { lineAlign = "end" }) },
					}),
					-- ...and the one parent that DOES read it stays silent
					UI.VStack({ id = "V", width = px(200), children = { box("Vk", 40, 40, { lineAlign = "end" }) } }),
				},
			}),
			600,
			900
		)
		expect(table.concat(findings(c, "lineAlign"), ",")).toBe("/S/A/Ak,/S/F/Fk,/S/G/Gk,/S/Sc/Sk,/S/Z/Zk")
		-- and it really works where it is silent
		expect(c.rectOf("/S/V/Vk").x).toBe(160)
	end)

	it("`gridSpan` is reported under every parent that is not a GridRow", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({ id = "V", width = px(200), children = { box("Vk", 40, 40, { gridSpan = 2 }) } }),
					UI.HStack({ id = "H", width = px(200), children = { box("Hk", 40, 40, { gridSpan = 2 }) } }),
					UI.ZStack({
						id = "Z",
						width = px(200),
						height = px(80),
						children = { box("Zk", 40, 40, { gridSpan = 2 }) },
					}),
					UI.Anchor({
						id = "A",
						width = px(200),
						height = px(80),
						children = { box("Ak", 40, 40, { gridSpan = 2 }) },
					}),
					UI.Grid({
						id = "G",
						columns = 2,
						width = px(200),
						children = { box("Gk", 40, 40, { gridSpan = 2 }) },
					}),
					UI.ScrollView({ id = "Sc", height = px(80), children = { box("Sk", 40, 40, { gridSpan = 2 }) } }),
					-- ...and the one parent that DOES read it stays silent, and spans
					UI.Grid({
						id = "RG",
						width = px(300),
						gap = 10,
						children = {
							UI.GridRow({ id = "R1", children = { box("A", 40, 20), box("B", 60, 20) } }),
							UI.GridRow({
								id = "R2",
								children = {
									UI.Box({ id = "Span", width = FILL, height = px(20), gridSpan = 2 }),
								},
							}),
						},
					}),
				},
			}),
			600,
			1200
		)
		expect(table.concat(findings(c, "gridSpan"), ",")).toBe("/S/A/Ak,/S/G/Gk,/S/H/Hk,/S/Sc/Sk,/S/V/Vk,/S/Z/Zk")
		-- ...and on the row it really spans: column 1 is 40 wide (cell A), column 2
		-- is 60 (cell B), the gap between them is 10, and the spanning cell is
		-- fitted to all three — 110, never one column and never the whole row
		expect(`{c.rectOf("/S/RG/R1/A").w}`).toBe("40")
		expect(`{c.rectOf("/S/RG/R1/B").w}`).toBe("60")
		expect(`{c.rectOf("/S/RG/R2/Span").w}`).toBe("110")
	end)
	--[[ THE SHRINK PAIR (Milestone-1 architecture review, C2). `layoutPriority` and
		`shrinkWeight` were declared in the same schema paragraph as `lineAlign` and
		`gridSpan` — "placement facts a stack parent reads off its children, exactly
		as `anchor`, `alignH`, `alignV`, `offsetX` and `offsetY` already are" — and
		then left out of the read table, so the mission that built the audit
		re-committed the §4 defect the audit exists to remove. Both halves are pinned
		here: the inert parents report, and the ONE parent kind that reads them stays
		silent AND really shrinks. ]]
	it("`shrinkWeight` is reported under every parent that is not a stack, and still shrinks under one", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ZStack({
						id = "Z",
						width = px(200),
						height = px(80),
						children = { box("Zk", 40, 40, { shrinkWeight = 1 }) },
					}),
					UI.Anchor({
						id = "A",
						width = px(200),
						height = px(80),
						children = { box("Ak", 40, 40, { shrinkWeight = 1 }) },
					}),
					UI.Grid({
						id = "G",
						columns = 2,
						width = px(200),
						children = { box("Gk", 40, 40, { shrinkWeight = 1 }) },
					}),
					UI.ScrollView({
						id = "Sc",
						height = px(80),
						children = { box("Sk", 40, 40, { shrinkWeight = 1 }) },
					}),
					UI.ViewThatFits({
						id = "F",
						width = px(200),
						children = { box("Fk", 40, 40, { shrinkWeight = 1 }) },
					}),
					-- ...and the two parents that DO read it stay silent
					UI.VStack({ id = "V", width = px(200), children = { box("Vk", 40, 40, { shrinkWeight = 1 }) } }),
					UI.HStack({
						id = "H",
						width = px(100),
						children = { box("Ha", 80, 20, { shrinkWeight = 1 }), box("Hb", 80, 20) },
					}),
				},
			}),
			600,
			900
		)
		expect(table.concat(findings(c, "shrinkWeight"), ",")).toBe("/S/A/Ak,/S/F/Fk,/S/G/Gk,/S/Sc/Sk,/S/Z/Zk")
		-- and it really works where it is silent: 160px of content in a 100px row,
		-- and the ONE child that opted in gives up all 60 of the deficit
		expect(`{c.rectOf("/S/H/Ha").w},{c.rectOf("/S/H/Hb").w}`).toBe("20,80")
	end)

	it("`layoutPriority` is reported under every parent that is not a stack, and still tiers under one", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ZStack({
						id = "Z",
						width = px(200),
						height = px(80),
						children = { box("Zk", 40, 40, { layoutPriority = 2 }) },
					}),
					UI.Anchor({
						id = "A",
						width = px(200),
						height = px(80),
						children = { box("Ak", 40, 40, { layoutPriority = 2 }) },
					}),
					UI.Grid({
						id = "G",
						columns = 2,
						width = px(200),
						children = { box("Gk", 40, 40, { layoutPriority = 2 }) },
					}),
					UI.ScrollView({
						id = "Sc",
						height = px(80),
						children = { box("Sk", 40, 40, { layoutPriority = 2 }) },
					}),
					UI.ViewThatFits({
						id = "F",
						width = px(200),
						children = { box("Fk", 40, 40, { layoutPriority = 2 }) },
					}),
					-- ...and the stack that DOES read it: two equal-weight children in
					-- different tiers, so the LOWER tier gives way first
					UI.HStack({
						id = "H",
						width = px(100),
						children = {
							box("Ha", 80, 20, { shrinkWeight = 1, layoutPriority = 0 }),
							box("Hb", 80, 20, { shrinkWeight = 1, layoutPriority = 5 }),
						},
					}),
				},
			}),
			600,
			900
		)
		expect(table.concat(findings(c, "layoutPriority"), ",")).toBe("/S/A/Ak,/S/F/Fk,/S/G/Gk,/S/Sc/Sk,/S/Z/Zk")
		expect(`{c.rectOf("/S/H/Ha").w},{c.rectOf("/S/H/Hb").w}`).toBe("20,80")
	end)

	it("the shrink pair's message names the reason AND the way out", function()
		local c = mounted(
			UI.Screen({
				id = "S",
				children = {
					UI.ZStack({
						id = "Z",
						width = px(200),
						height = px(80),
						children = { box("Zk", 40, 40, { shrinkWeight = 2 }) },
					}),
				},
			}),
			400,
			400
		)
		local issue = issueFor(c, "/S/Z/Zk", "shrinkWeight")
		expect(string.find(issue, "accepted and then ignored", 1, true) ~= nil).toBe(true)
		expect(string.find(issue, "layering them over its whole box", 1, true) ~= nil).toBe(true)
		expect(string.find(issue, "`UI.VStack`/`UI.HStack`", 1, true) ~= nil).toBe(true)
	end)
end)
