--!strict
--[[ THE SETTLE-TIME CONTAINMENT FINDING — the solver saying the thing it knew.

	`docs/lessons/the-solver-already-told-you.md` is the standing lesson: the
	solver already knows every overflow, every collapsed content box and every
	inert prop, and names the node, the number and the fix — on a channel someone
	has to ask. There was one thing it did NOT know how to say. Every overflow
	finding in `layout/solver.luau` is derived from a MEASURE compared against an
	offer; not one is derived from the RECT the child was finally given. So a box
	placed outside its parent by ARITHMETIC rather than by size was invisible, and
	that is precisely the shape the region-expand plate shipped in — content
	painting past its own panel edge, at every viewport, under a green suite.

	THE CASE BELOW IS THE MINIMAL REACHABLE ONE, and it is not synthetic. A stack
	sizes its children to its content box (`crossSize = min(desired, crossAvail)`)
	— except on the one path that bypasses that clamp, the ASPECT axis, which is
	derived from the other extent after the clamp has already been applied. A
	2:1 box 80px tall inside a 100px-wide column resolves to 160px wide and is
	placed at the column's own left edge: 60px of it paints outside the parent,
	over whatever sits beyond, and before this the whole diagnostics channel was
	empty for that tree.

	SCOPE, MEASURED RATHER THAN CHOSEN (the counts are in `layout/placement_audit.luau`):
	the first draft policed every parent that places a child and produced 21,916
	findings on a green library — `anchor` and `zstack` place children outside
	their box BY DESIGN, and the main axis of a stack is already reported by name
	and by number. What is left is the cross axis, where 41 occurrences fired
	suite-wide and not one of them on a shipped fixture.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local solver = require("../src/layout/solver")

-- a declared-width column with one child; `extra` decorates the column
local function column(extra: { [string]: any }?): any
	local node: any = {
		kind = "vstack",
		id = "Col",
		width = { type = "fixed", px = 100 },
		height = { type = "fixed", px = 200 },
		children = {
			{
				kind = "box",
				id = "Wide",
				height = { type = "fixed", px = 80 },
				-- the one path that bypasses the cross-axis clamp
				width = { type = "aspect", ratio = 2 },
			},
		},
	}
	for key, value in extra or {} do
		node[key] = value
	end
	return node
end

local function findings(root: any): { any }
	local result = solver.solve(root, { w = 400, h = 300 }, { scrollBarReserve = 0 })
	local out: { any } = {}
	for _, d in result.diagnostics do
		if (d :: any).edge ~= nil then
			table.insert(out, d)
		end
	end
	return out
end

describe("containment: a stack child placed outside its own cross axis says so", function()
	it("names the child, the edge and the overhang in px", function()
		local found = findings(column())
		expect(#found).toBe(1)
		local d = found[1]
		expect(d.node).toBe("Wide")
		-- FILED BY THE PARENT, naming the child — the stamp the incremental replay
		-- gate reads, exactly as the zstack overlap finding beside it carries
		expect(d.filedBy).toBe("Col")
		--[[ FIRST-CLASS FIELDS, not a substring of the sentence. A harness — the
			adapter-side containment invariant, a dev-build assertion, a device
			capture — has to be able to sort findings by how far outside they are
			without parsing English, and an `edge` spelled into prose is a field
			that has to be re-derived by everyone who wants it. ]]
		expect(d.edge).toBe("right")
		expect(d.overhang).toBe(60)
		expect(d.designed).toBe(nil)
	end)

	it("...and the sentence carries the same three facts a reader needs", function()
		local d = findings(column())[1]
		expect(string.find(d.issue, "'Wide' is placed 60px past the right edge", 1, true) ~= nil).toBe(true)
		expect(string.find(d.issue, "vstack", 1, true) ~= nil).toBe(true)
		expect(string.find(d.issue, "CROSS axis", 1, true) ~= nil).toBe(true)
	end)

	it("a contained tree reports NOTHING — the finding is not a permanent fixture", function()
		--[[ The trap every always-on diagnostic invites and the reason three
			reference proofs once carried `overflow = "clip"`: a finding that fires on
			a correct tree is a channel people learn to mute. Same column, same
			aspect child, a ratio that fits. ]]
		local fits: any = column()
		fits.children[1].width = { type = "aspect", ratio = 1 }
		expect(#findings(fits)).toBe(0)
	end)

	it("a DECLARED ROUTE is a decision, not a defect", function()
		-- each of the three spellings the solver already understands
		for _, route in { "clip", "scroll", "intentionalOverlap" } do
			expect(`{route}: {#findings(column({ overflow = route }))}`).toBe(`{route}: 0`)
		end
	end)

	it("a parent that does not DECLARE its width is not policed, even when it is squeezed", function()
		--[[ THE GATE IS `axisAbsorbs`, the solver's own resolver-mirroring predicate,
			so this rule cannot disagree with the resolver about what "declared" means
			— and `hug` does not absorb. The case has to be one where the hug column is
			genuinely too small, or the check proves nothing: a bare hug column simply
			GROWS to 160 and there is no overflow to report at all, which is how the
			first version of this case passed with the gate deleted (mutation B2-M5).

			So the column hugs INSIDE a 100px parent: `hug` is content capped at the
			offer, so it resolves to 100, the 2:1 child still resolves to 160, and 60px
			lands outside a parent that cannot grow either.

			IT IS DELIBERATELY SILENT, and the limit is worth stating where it is felt:
			a hug box too small for its content was squeezed by ITS parent, and that is
			the story the outer box's own findings tell. Widening the rule to "resolved
			smaller than the child needs" would need the offer carried into arrange,
			which is state this check does not have and does not want. ]]
		local squeezed: any = {
			kind = "vstack",
			id = "Outer",
			width = { type = "fixed", px = 100 },
			height = { type = "fixed", px = 200 },
			children = { column({ width = { type = "hug" } }) },
		}
		expect(#findings(squeezed)).toBe(0)
		local content: any = column()
		content.width = nil
		expect(#findings(content)).toBe(0)
	end)

	it("the MAIN axis is not reported twice", function()
		--[[ `content overflows this vstack by Npx on the main axis` fires two lines
			above the placement loop and has since the first release. A containment
			finding on the same axis would be a second telling of one defect, which is
			how a channel goes from a diagnosis to a noise floor — the identical rule
			the windowed-slot finding already states one branch over ("the main axis
			has now been reported by name and by number"). ]]
		local tall: any = {
			kind = "vstack",
			id = "Col",
			width = { type = "fixed", px = 100 },
			height = { type = "fixed", px = 40 },
			children = {
				{ kind = "box", id = "A", width = { type = "fixed", px = 20 }, height = { type = "fixed", px = 90 } },
			},
		}
		local result = solver.solve(tall, { w = 400, h = 300 }, { scrollBarReserve = 0 })
		local main, contained = 0, 0
		for _, d in result.diagnostics do
			if (d :: any).edge ~= nil then
				contained += 1
			elseif string.find(d.issue, "on the main axis", 1, true) ~= nil then
				main += 1
			end
		end
		expect(`main={main} contained={contained}`).toBe("main=1 contained=0")
	end)

	it("the three exclusions the census bought are pinned, not merely absent", function()
		--[[ THE SCOPE WAS A MEASURED DECISION AND IT HAD NO REGRESSION PIN.
			Three families are excluded by there being no CALL SITE, which is
			a fact about `solver.luau` that a future round can undo by adding one
			line — and the measurement that rejected them (21,916 findings on a green
			library; `anchor` 13,851 and `zstack` 3,609 of it) lives in prose. So the
			decision is asserted here instead:

			  · an ANCHOR places a child exactly where the author says. A badge on a
			    corner and a thumb at the end of a groove are the paradigm, not a
			    defect, and there is no way to tell them apart from a rect;
			  · a ZSTACK layers by definition, and it ALREADY reports — with its own
			    measure-side overlap finding, its own `fill`-axis exemption and its
			    own `intentionalOverlap` opt-out. A second telling is noise.

			EACH CASE CARRIES ITS OWN PROOF THAT THE TREE REALLY OVERFLOWS, because
			"no finding" is also what a contained tree answers, and a pin that cannot
			tell those apart is the trap this file's other cases already name. ]]
		local function outsideBy(root: any, childId: string): number
			local result = solver.solve(root, { w = 400, h = 300 }, { scrollBarReserve = 0 })
			local parent = result.rects[root.id].rect
			local kid = result.rects[childId].rect
			return math.max(parent.x - kid.x, (kid.x + kid.w) - (parent.x + parent.w))
		end
		local function layered(childWidth: any): any
			return {
				kind = "zstack",
				id = "Z",
				width = { type = "fixed", px = 100 },
				height = { type = "fixed", px = 200 },
				children = { { kind = "box", id = "Kid", height = { type = "fixed", px = 80 }, width = childWidth } },
			}
		end
		local function anchored(extra: { [string]: any }): any
			local kid: any =
				{ kind = "box", id = "Kid", width = { type = "fixed", px = 40 }, height = { type = "fixed", px = 40 } }
			for key, value in extra do
				kid[key] = value
			end
			return {
				kind = "anchor",
				id = "A",
				width = { type = "fixed", px = 100 },
				height = { type = "fixed", px = 200 },
				children = { kid },
			}
		end

		-- a ZSTACK: outside on the right, silent here, and STILL REPORTED by the
		-- finding that owns it — which is what makes this an exclusion rather than
		-- a hole
		local zFixed = layered({ type = "fixed", px = 160 })
		expect(outsideBy(zFixed, "Kid")).toBe(60)
		expect(#findings(zFixed)).toBe(0)
		local zResult = solver.solve(zFixed, { w = 400, h = 300 }, { scrollBarReserve = 0 })
		expect(#zResult.diagnostics).toBe(1)
		expect(string.find(zResult.diagnostics[1].issue, "overflows its zstack", 1, true) ~= nil).toBe(true)
		-- ...and the aspect shape that IS a finding inside a stack is not one here
		expect(#findings(layered({ type = "aspect", ratio = 2 }))).toBe(0)

		-- an ANCHOR: outside on either side, by offset or by anchor, and nothing
		-- else reports it either. That is the accepted cost, named where it is felt
		expect(outsideBy(anchored({ offsetX = 90 }), "Kid")).toBe(30)
		expect(#findings(anchored({ offsetX = 90 }))).toBe(0)
		local wide = anchored({ anchor = "topRight", width = { type = "fixed", px = 160 } })
		expect(outsideBy(wide, "Kid")).toBe(60)
		expect(#findings(wide)).toBe(0)
	end)

	it("a subtree that never paints files nothing", function()
		--[[ `hiddenDepth` — the losing `ViewThatFits` candidate, the dropped
			composition region. A subtree arranged against a 0x0 box produces
			meaningless rects, and reporting them would put a permanent false positive
			on every `fits` in the library. ]]
		local fits: any = {
			kind = "fits",
			id = "F",
			width = { type = "fixed", px = 100 },
			height = { type = "fixed", px = 200 },
			children = { column(), column() },
		}
		local found = findings(fits)
		-- the CHOSEN candidate still reports; the unchosen one is silent, so the
		-- count is one rather than two
		expect(#found).toBe(1)
	end)
end)
