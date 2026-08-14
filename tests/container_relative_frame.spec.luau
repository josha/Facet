--!strict
--[[
	`containerRelativeFrame` (docs/plans/swiftui-parity-round2.md §2.5).

	THE WHOLE FEATURE IS A DIFFERENT RULER. `percent` has always meant "a fraction
	of what my PARENT offered me" (`solver.luau` `resolveAxis`, the `percent`
	branch). `containerRelativeFrame` means "a fraction of the nearest ancestor
	that owns a VIEWPORT" — a `UI.ScrollView`'s content viewport, else the surface
	root. The two coincide exactly when nothing sits between the view and the
	container, which is why every case below puts something there: a padded stack,
	a second scroller, a scrollbar reservation.

	THE CASE THAT MATTERS MOST IS THE LAST DESCRIBE — the measure memo's cache key.
	`solver.measure` memoizes per solve on `"{maxW}|{maxH}|{scopeKey}"`, where
	`scopeKey` is `hiddenDepth` alone until a `containerRelative` dimension is
	measured and `"{hiddenDepth}|{containerW}|{containerH}"` from then on. The
	container term is what this stage added. Every other term is an input the caller
	handed down; this one is not, so the SAME node at the SAME offer can legitimately
	want two different answers within one solve. Two traps live there and both are
	mechanical:

	  1. THE MEMO IS GATED ON `ctx.hasScroll`. A fixture without a ScrollView runs
	     UNCACHED, so it passes whatever the key says and proves nothing about it.
	     The fixture below therefore has one, and the case comment says which line
	     of the solver makes that necessary.
	  2. A "different container" that is also a different OFFER proves nothing
	     either — the key already carried the offer. The fixture makes the offer
	     byte-identical between the two measures (`maxW = 400`, `maxH = math.huge`
	     in both passes, which is what a y-scroller hands its children) and changes
	     only the container.

	Mutation record, run against this file (2026-08-13):
	  · drop the container from `rebuildScopeKey`'s armed branch
	      -> "the same node at the same offer under two containers gets two answers"
	         FAILS, reporting 200 (the measure-time ruler) where 63 is painted
	  · never arm `hasContainerRelative`, so the key stays container-free
	      -> the same case FAILS the same way, which is what makes the ARM part of
	         the contract rather than an optimisation nobody checks
	  · make the arrange-side scroll branch skip its `pushContainer`
	      -> 8 of the 13 cases FAIL, i.e. these cases observe the mechanism and not
	         merely an arithmetic constant

	Every mounted fixture asks `controller.diagnostics()`
	(docs/lessons/the-solver-already-told-you.md).
]]

local fs = require("@lune/fs")

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local solver = require("../src/layout/solver")
local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

local function fixed(px: number): any
	return { type = "fixed", px = px }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end
local function crf(spec: { [string]: any }): any
	local d: any = { type = "containerRelative" }
	for k, v in spec do
		d[k] = v
	end
	return d
end

local function solve(root: any, w: number, h: number, opts: any?): any
	local o: any = { rootPolicy = "edgeToEdge" }
	for k, v in opts or {} do
		o[k] = v
	end
	return solver.solve(root, { w = w, h = h }, o)
end

local function issues(result: any): string
	local parts = {}
	for _, d in result.diagnostics do
		table.insert(parts, `{d.node}: {d.issue}`)
	end
	return table.concat(parts, " | ")
end

describe("the container is the nearest viewport, not the parent", function()
	it("a fraction ignores the wrappers between the view and the scroller", function()
		local r = solve({
			kind = "scroll",
			id = "S",
			axis = "y",
			width = fixed(400),
			height = fixed(300),
			children = {
				{
					kind = "vstack",
					id = "Inner",
					padding = 40,
					width = fill(),
					children = {
						{ kind = "box", id = "half", width = crf({ fraction = 0.5 }), height = fixed(20) },
						{ kind = "box", id = "pct", width = { type = "percent", fraction = 0.5 }, height = fixed(20) },
					},
				},
			},
		}, 500, 500)
		-- the scroller's viewport is 400 wide, so half of it is 200 — regardless of
		-- the 40px padding the stack in between spent. `percent` reads that same
		-- padded offer (400 - 80 = 320) and answers 160: the two numbers on one line
		-- ARE the feature.
		expect(`crf={r.rects.half.rect.w} percent={r.rects.pct.rect.w}`).toBe("crf=200 percent=160")
		expect(issues(r)).toBe("")
	end)

	it("the NEAREST scroller wins, not the outermost", function()
		local r = solve({
			kind = "scroll",
			id = "Outer",
			axis = "y",
			width = fixed(400),
			height = fixed(300),
			children = {
				{ kind = "box", id = "outerHalf", width = crf({ fraction = 0.5 }), height = fixed(20) },
				{
					kind = "scroll",
					id = "Inner",
					axis = "x",
					width = fixed(200),
					height = fixed(60),
					children = {
						{ kind = "box", id = "innerHalf", width = crf({ fraction = 0.5 }), height = fixed(20) },
					},
				},
			},
		}, 500, 500)
		expect(`outer={r.rects.outerHalf.rect.w} inner={r.rects.innerHalf.rect.w}`).toBe("outer=200 inner=100")
		expect(issues(r)).toBe("")
	end)

	it("with no scroller anywhere, the container is the surface root", function()
		local r = solve({
			kind = "vstack",
			id = "Root",
			width = fill(),
			padding = 30,
			children = {
				{
					kind = "vstack",
					id = "Card",
					padding = 20,
					width = fill(),
					children = { { kind = "box", id = "third", width = crf({ fraction = 1 / 3 }), height = fixed(10) } },
				},
			},
		}, 600, 400)
		-- a third of the SURFACE (600), not a third of the twice-padded 500 the
		-- parent offered
		expect(r.rects.third.rect.w).toBe(200)
		expect(issues(r)).toBe("")
	end)

	it("...and it follows the scrollbar reservation, because that is the viewport too", function()
		-- reserving the bar makes the scroller's cross axis genuinely narrower; a page
		-- sized against the pre-reserve number would sit underneath the bar
		local r = solve({
			kind = "scroll",
			id = "S",
			axis = "y",
			width = fixed(400),
			height = fixed(100),
			children = {
				{ kind = "box", id = "tall", width = fill(), height = fixed(400) },
				{ kind = "box", id = "half", width = crf({ fraction = 0.5 }), height = fixed(20) },
			},
		}, 500, 500, { scrollBarReserve = 12 })
		expect(r.rects.half.rect.w).toBe(194)
	end)
end)

describe("the paging form is SwiftUI's arithmetic", function()
	-- size = (viewport - spacing x (count - 1)) / count x span + spacing x (span - 1)
	local function carousel(pages: { any }): any
		return {
			kind = "scroll",
			id = "S",
			axis = "x",
			width = fixed(300),
			height = fixed(120),
			children = pages,
		}
	end

	it("count + spacing carves the viewport into pages", function()
		local r = solve(
			carousel({
				{ kind = "box", id = "p1", width = crf({ count = 3, span = 1, spacing = 8 }), height = fixed(40) },
				{ kind = "box", id = "p2", width = crf({ count = 3, span = 2, spacing = 8 }), height = fixed(40) },
			}),
			500,
			500
		)
		-- (300 - 8 x 2) / 3 = 94.67 per page: one page rounds to 95, two pages plus
		-- the gutter between them to 197
		expect(`p1={r.rects.p1.rect.w} p2={r.rects.p2.rect.w}`).toBe("p1=95 p2=197")
		expect(issues(r)).toBe("")
	end)

	it("count with no spacing and no span is a clean division", function()
		local r =
			solve(carousel({ { kind = "box", id = "p", width = crf({ count = 4 }), height = fixed(40) } }), 500, 500)
		expect(r.rects.p.rect.w).toBe(75)
	end)

	it("the SCROLL AXIS is where this matters, and the offer there is unbounded", function()
		-- a horizontal scroller offers its children `math.huge` on the scroll axis, so
		-- `percent` cannot express a page at all — it diagnoses and falls back to
		-- content. `containerRelative` never reads the offer, which is the point.
		local r = solve(
			carousel({
				{ kind = "box", id = "page", width = crf({ count = 2 }), height = fixed(40) },
				{ kind = "box", id = "pct", width = { type = "percent", fraction = 0.5 }, height = fixed(40) },
			}),
			500,
			500
		)
		expect(r.rects.page.rect.w).toBe(150)
		expect(r.rects.pct.rect.w).toBe(0)
		expect(string.find(issues(r), "percent size on an unbounded axis", 1, true) ~= nil).toBe(true)
	end)

	it("an unbounded CONTAINER is refused the same way `percent` refuses one", function()
		-- a horizontal scroller inside another horizontal scroller's own axis: the
		-- inner one's viewport on that axis is an offer it never received
		local r = solve({
			kind = "scroll",
			id = "Outer",
			axis = "x",
			width = fixed(400),
			height = fixed(200),
			children = {
				{
					kind = "scroll",
					id = "Inner",
					axis = "x",
					height = fixed(100),
					children = { { kind = "box", id = "page", width = crf({ fraction = 0.5 }), height = fixed(20) } },
				},
			},
		}, 500, 500)
		expect(
			string.find(issues(r), "containerRelativeFrame on an axis whose nearest container is unbounded", 1, true)
				~= nil
		).toBe(true)
	end)
end)

describe("the authoring surface: UI.containerRelativeFrame", function()
	local function render(screen: any, w: number, h: number): (any, any)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return adapter, controller
	end

	it("writes the dimension the solver reads, on the axis the spec named", function()
		local adapter, controller = render(
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Sc",
						axis = "x",
						width = fixed(360),
						height = fixed(120),
						children = {
							UI.containerRelativeFrame(
								UI.Box({ id = "Page", height = fixed(60) }),
								{ axis = "horizontal", count = 3, span = 1, spacing = 12 }
							),
							UI.containerRelativeFrame(
								UI.Box({ id = "Wide", height = fixed(60) }),
								{ axis = "horizontal", fraction = 0.5 }
							),
						},
					}),
				},
			}),
			400,
			300
		)
		-- (360 - 12 x 2) / 3 = 112
		expect(`page={adapter.node("/S/Sc/Page").rect.w}`).toBe("page=112")
		expect(`wide={adapter.node("/S/Sc/Wide").rect.w}`).toBe("wide=180")
		expect(#controller.diagnostics()).toBe(0)
	end)

	it("the vertical axis writes `height`", function()
		local adapter, controller = render(
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Sc",
						axis = "y",
						width = fixed(300),
						height = fixed(400),
						children = {
							UI.containerRelativeFrame(
								UI.Box({ id = "Hero", width = fill() }),
								{ axis = "vertical", fraction = 0.25 }
							),
						},
					}),
				},
			}),
			400,
			500
		)
		expect(`hero={adapter.node("/S/Sc/Hero").rect.h}`).toBe("hero=100")
		expect(#controller.diagnostics()).toBe(0)
	end)

	it("the spec is CLOSED: unknown keys, a bad axis, both forms and a missing form all refuse", function()
		local function refuses(spec: any): string
			local ok, err = pcall(function()
				return UI.containerRelativeFrame(UI.Box({ id = "B" }), spec)
			end)
			if ok then
				return "ACCEPTED"
			end
			return tostring(err)
		end
		expect(
			string.find(refuses({ axis = "horizontal", fractoin = 0.5 }), "unknown field 'fractoin'", 1, true) ~= nil
		).toBe(true)
		expect(string.find(refuses({ axis = "sideways", fraction = 0.5 }), 'axis must be "horizontal"', 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(refuses({ axis = "horizontal", fraction = 0.5, count = 3 }), "not both", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(refuses({ axis = "horizontal" }), "pass either `fraction`", 1, true) ~= nil).toBe(true)
		expect(
			string.find(refuses({ axis = "horizontal", count = 2, span = 3 }), "cannot exceed count", 1, true) ~= nil
		).toBe(true)
		expect(
			string.find(refuses({ axis = "horizontal", count = 2.5 }), "count must be a whole number", 1, true) ~= nil
		).toBe(true)
		expect(refuses({ axis = "horizontal", fraction = 0.5 })).toBe("ACCEPTED")
	end)
end)

describe("the measure memo tells two containers apart", function()
	--[[ THE STALE-HIT CASE, BUILT TO BE UNPROVABLE ANY OTHER WAY.

		The tree is one `hug`-height y-scroller with two children. A y-scroller offers
		its children `(innerW, math.huge)` in BOTH passes — `contentSize`'s scroll
		branch and `arrange`'s `measureAll` — so `maxW` and `maxH` are byte-identical
		across the two measures of `half`, and so is `hiddenDepth`. The only thing that
		differs is the container:

		  MEASURE  the scroller is offered 800px of height, so its viewport is 800 and
		           `half` (a quarter of it) measures 200. The scroller therefore hugs
		           to 50 + 200 = 250 and REPORTS that.
		  ARRANGE  the scroller's rect is that 250, so its viewport is 250 and `half`
		           is 63.

		Two rulers, two answers, one cache key — unless the container is in the key.
		The memo is live here because there is a ScrollView in the tree (it is gated on
		`ctx.hasScroll`, `solver.luau` `measure`), which is exactly the trap: the same
		fixture built out of stacks would run uncached and pass no matter what.

		NOT VACUOUS: both numbers are asserted. `Scroll h = 250` can only come from the
		measure-time ruler (800) and `half h = 63` only from the arrange-time one (250),
		so a build that answered the same in both passes fails one of them whichever
		answer it picked. ]]
	local function stale(): any
		return solve({
			kind = "vstack",
			id = "Root",
			width = fill(),
			height = fill(),
			children = {
				{
					kind = "scroll",
					id = "Scroll",
					axis = "y",
					width = fixed(400),
					height = { type = "hug" },
					children = {
						{ kind = "box", id = "top", width = fixed(400), height = fixed(50) },
						{ kind = "box", id = "half", width = fixed(300), height = crf({ fraction = 0.25 }) },
					},
				},
			},
		}, 400, 800)
	end

	it("the same node at the same offer under two containers gets two answers", function()
		local r = stale()
		expect(`scroll={r.rects.Scroll.rect.h} half={r.rects.half.rect.h}`).toBe("scroll=250 half=63")
		expect(issues(r)).toBe("")
	end)

	it("...and the fixture really is running through the memo, not around it", function()
		-- the guard for trap 1. `hasScroll` arms the cache the first time a scroll node
		-- is measured, and this tree has one — so the case above is a statement about
		-- the KEY. The identical tree with the scroller replaced by a stack has no
		-- container to change and no cache at all, and answers the surface root's
		-- quarter (200) in both passes.
		local r = solve({
			kind = "vstack",
			id = "Root",
			width = fill(),
			height = fill(),
			children = {
				{ kind = "box", id = "top", width = fixed(400), height = fixed(50) },
				{ kind = "box", id = "half", width = fixed(300), height = crf({ fraction = 0.25 }) },
			},
		}, 400, 800)
		expect(r.rects.half.rect.h).toBe(200)
		expect(issues(r)).toBe("")
	end)
end)

--[[ THE WRITERS OF `ctx.scopeKey`, AND THE HEADER THAT NAMES THEM (Milestone-1
	review, C4). `solver.luau`'s block comment declared "THE THREE WRITERS" while
	FIVE places wrote the field: the three that rebuild it from the fields it is
	derived from, plus the two scroll branches' unwind, which put a captured triple
	straight back. Those two were SAFE — the triple is captured and restored
	atomically, so the key cannot disagree with the container fields it names — and
	that is exactly the danger: they are the only lines where a future edit could
	break an invariant the header calls structurally impossible
	(docs/lessons/a-header-comment-describes-the-path-it-was-written-for.md).

	So the unwind is a NAMED writer now, `restoreScope`, and this case keeps the
	header honest: nothing outside the two helpers may assign the field. It is
	structural because there is no behaviour to observe — the whole point of the
	finding is that the old code was correct. ]]
describe("§2.5 the scope key has exactly two assignment sites, and the header says so", function()
	local source = fs.readFile("src/layout/solver.luau")

	it("`ctx.scopeKey` is assigned only inside `rebuildScopeKey` and `restoreScope`", function()
		local sites: { string } = {}
		for line in string.gmatch(source, "[^\n]+") do
			if string.find(line, "ctx.scopeKey =", 1, true) ~= nil then
				table.insert(sites, (string.gsub(line, "^%s+", "")))
			end
		end
		table.sort(sites)
		expect(table.concat(sites, " | ")).toBe(
			"ctx.containerW, ctx.containerH, ctx.scopeKey = w, h, key | "
				.. "ctx.scopeKey = `{ctx.hiddenDepth}{probe}` | "
				.. "ctx.scopeKey = `{ctx.hiddenDepth}|{ctx.containerW}|{ctx.containerH}{probe}`"
		)
	end)

	it("the header counts the writers it actually has", function()
		expect(string.find(source, "THE FIVE WRITERS OF `ctx.scopeKey`", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "THE FOUR WRITERS OF `ctx.scopeKey`", 1, true) == nil).toBe(true)
		expect(string.find(source, "THE THREE WRITERS OF `ctx.scopeKey`", 1, true) == nil).toBe(true)
		-- and the fifth is named in the block that lists them, not merely defined
		expect(string.find(source, "FOUR OF THE FIVE REBUILD; THE FIFTH RESTORES", 1, true) ~= nil).toBe(true)
	end)
end)
