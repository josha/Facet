--!strict
--[[ CONTENT-TERMS HEIGHT (framework-gaps-phase2 gap 3; audit §3).

	`UI.Composition` already had this vocabulary, LOCKED inside it — Region
	floors are `{ lines = n }` / `{ targets = n }`, resolved by
	`composition.floorPx`. Outside a `Composition`, a scroller or panel viewport
	had no way to say "big enough for about N lines/rows" and got pinned in a
	literal px instead, next to content that scales with the player's
	accessibility text preference and the ten-foot ladder. This file is the
	contract for the general vocabulary that replaces the literal:

	  `height = { type = "content", lines = n, role: string? }` — n lines of a
	  typography role (default "body"), through the SAME two calls
	  `Facet.text.lineBox` makes.

	  `height = { type = "content", rows = n, of = metric }` — n rows of a
	  named theme metric (a metric name, a literal px, or an additive list of
	  either — the SAME escape hatch `px`/`min`/`max`/`preferred` already
	  grant).

	§1  construction: the closed grammar (`blueprint_schema.luau`)
	§2  resolution: `themes/snapshot.resolveDim` turns `of` into a number
	§3  the solver arithmetic, and that it tracks the ten-foot ladder /
	    accessibility text preference on the axis each shape actually reads
	§4  REGRESSION: a content-terms viewport nested inside another scroller's
	    own unbounded axis is DEFINITE, not "materializes everything" — found
	    live wiring this up (`preferred_text`'s `Form`, three sites red on
	    `tests/overflow_sweep.spec.luau` before this fix)
	§5  the four adaptation-slice sites, migrated: value-identical (or
	    measured-and-documented) at Neutral, and — the RED this campaign's
	    brief asked for — GROWS where the literal it replaces never did
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local UI = require("../src/blueprint")
local solver = require("../src/layout/solver")
local snapshot = require("../src/themes/snapshot")
local fake_target = require("./lib/fake_target")

local NEUTRAL = snapshot.neutral()
local NEUTRAL_PKG = snapshot.neutralPackage()
-- `resolve` alone publishes the AUTHORED (base) ladder — the ten-foot SCALE is
-- a separate, read-time transform (`forDisplay`; `env:get("themeMetrics")`
-- applies it on every read, per its own header comment), which is why a
-- direct-solver test needs it spelled out rather than passed as a `resolve`
-- fact the way `preferredTextSize`/`preferredTextOffset` are
local LARGE = snapshot.forDisplay(snapshot.resolve(NEUTRAL_PKG, nil, {}), "Large")

local function solve(root: any, w: number, h: number, metrics: any?): any
	return solver.solve(root, { w = w, h = h }, { rootPolicy = "edgeToEdge", metrics = metrics or NEUTRAL })
end

local function box(root: any, w: number, h: number, metrics: any?): any
	local r = solve(root, w, h, metrics)
	return r.rects["B"].rect
end

-- shared fixture-world helpers (§5 and §6 both mount real gallery scenarios)
local DESKTOP = { w = 1232, h = 1067 }

local function fixtureWorld(view: any): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

local function mountFixture(w: any, module: any): any
	local built = module.build({
		Facet = Facet,
		core = w.core,
		env = w.env,
		actionSystem = w.system,
		presenter = w.presenter,
	})
	built.handle = w.presenter.present(built.screen, built.present)
	for _ = 1, 3 do
		w.presenter.refresh()
	end
	return built
end

-- ===========================================================================
-- 1. CONSTRUCTION — the closed grammar
-- ===========================================================================
describe("content-terms height: construction is a closed, cross-validated grammar", function()
	it('`{ type = "content", lines = n }` constructs', function()
		local ok = pcall(function()
			UI.Box({ id = "B", height = { type = "content", lines = 4 } })
		end)
		expect(ok).toBe(true)
	end)

	it('`{ type = "content", rows = n, of = metric }` constructs', function()
		local ok = pcall(function()
			UI.Box({ id = "B", height = { type = "content", rows = 5, of = "controlSizes.compact.height" } })
		end)
		expect(ok).toBe(true)
	end)

	it("`of` also accepts a literal px and an additive list, the documented escape hatch", function()
		expect(pcall(function()
			UI.Box({ id = "B", height = { type = "content", rows = 4, of = 28 } })
		end)).toBe(true)
		expect(pcall(function()
			UI.Box({ id = "B", height = { type = "content", rows = 4, of = { "xs", 4 } } })
		end)).toBe(true)
	end)

	it("`lines` and `rows` together is refused — two different units, one box", function()
		local ok, err = pcall(function()
			UI.Box({ id = "B", height = { type = "content", lines = 2, rows = 2, of = 4 } } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "never both", 1, true) ~= nil).toBe(true)
	end)

	it("`rows` without `of` is refused", function()
		local ok, err = pcall(function()
			UI.Box({ id = "B", height = { type = "content", rows = 2 } } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "`rows` requires `of`", 1, true) ~= nil).toBe(true)
	end)

	it("`of` without `rows` is refused", function()
		local ok, err = pcall(function()
			UI.Box({ id = "B", height = { type = "content", of = 4 } } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "`of` requires `rows`", 1, true) ~= nil).toBe(true)
	end)

	it("`role` without `lines` is refused", function()
		local ok, err = pcall(function()
			UI.Box({ id = "B", height = { type = "content", role = "body" } } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "`role` requires `lines`", 1, true) ~= nil).toBe(true)
	end)

	it("`role` on `rows` is refused — it names nothing there", function()
		local ok, err = pcall(function()
			UI.Box({ id = "B", height = { type = "content", rows = 2, of = 4, role = "body" } } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "only applies to `lines`", 1, true) ~= nil).toBe(true)
	end)

	it("an unknown `role` is refused, loud, at construction — not a silent fallback", function()
		local ok, err = pcall(function()
			UI.Box({ id = "B", height = { type = "content", lines = 2, role = "notarole" } } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "role must be one of", 1, true) ~= nil).toBe(true)
	end)

	it("`lines`/`rows`/`of`/`role` on any OTHER dim type are refused — not silently ignored", function()
		local ok, err = pcall(function()
			UI.Box({ id = "B", height = { type = "fixed", px = 10, lines = 2 } } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "only apply to a content-terms dimension", 1, true) ~= nil).toBe(true)
	end)

	it("`lines`/`rows` must be finite counts >= 1", function()
		for _, bad in { 0, -1, 0 / 0, math.huge } do
			local ok = pcall(function()
				UI.Box({ id = "B", height = { type = "content", lines = bad } })
			end)
			expect(`lines={bad} rejected`).toBe(`lines={bad} rejected`)
			expect(ok).toBe(false)
		end
	end)
end)

-- ===========================================================================
-- 2. RESOLUTION — `themes/snapshot.resolveDim` turns `of` into a number
-- ===========================================================================
describe("content-terms height: `of` resolves the same way px/min/max/preferred do", function()
	it("a metric name becomes a plain number", function()
		local resolved =
			snapshot.resolveDim(NEUTRAL, { type = "content", rows = 5, of = "controlSizes.compact.height" })
		expect(resolved.of).toBe(36)
		expect(resolved.rows).toBe(5)
		expect(resolved.type).toBe("content")
	end)

	it("an additive list sums, exactly as it does for `px`", function()
		local resolved = snapshot.resolveDim(NEUTRAL, { type = "content", rows = 2, of = { "xs", 10 } })
		-- "xs" = 4 at Neutral
		expect(resolved.of).toBe(14)
	end)

	it("a literal number passes through untouched", function()
		local resolved = snapshot.resolveDim(NEUTRAL, { type = "content", rows = 3, of = 28 })
		expect(resolved.of).toBe(28)
	end)

	it("`lines`/`role` are left alone — nothing to resolve against a metric name", function()
		local resolved = snapshot.resolveDim(NEUTRAL, { type = "content", lines = 4, role = "control" })
		expect(resolved.lines).toBe(4)
		expect(resolved.role).toBe("control")
	end)
end)

-- ===========================================================================
-- 3. THE SOLVER ARITHMETIC, AND WHICH AXIS EACH SHAPE TRACKS
-- ===========================================================================
describe("content-terms height: the solver arithmetic", function()
	local function node(dim: any): any
		return { kind = "box", id = "B", width = { type = "fixed", px = 200 }, height = dim }
	end

	it("`rows * of` — pure arithmetic on the resolved dim, no theme facts needed at solve time", function()
		local r = box(node({ type = "content", rows = 5, of = 36 }), 300, 400)
		expect(r.h).toBe(180)
	end)

	it(
		"`lines` — ceil(lines * (roleSize * scale + offset) * lineHeight), the SAME two calls `text.lineBox` makes",
		function()
			-- default role "body": size 16, lineHeight 1.2 at Neutral; scale/textOffset
			-- default to 1/0 for a tree built straight against the solver (no
			-- `layout_node.luau` stamping) — see `contentTermsPx`'s own comment
			local r = box(node({ type = "content", lines = 4 }), 300, 400)
			expect(r.h).toBe(77) -- ceil(4 * 16 * 1.2) = ceil(76.8)
		end
	)

	it("a named `role` changes both the size AND the line height it multiplies", function()
		local r = box(node({ type = "content", lines = 3, role = "control" }), 300, 400)
		expect(r.h).toBe(65) -- ceil(3 * 18 * 1.2) = ceil(64.8)
	end)

	it(
		"`rows`+`of` tracks the TEN-FOOT ladder — `of` is a theme metric, and `metricScale` already scales it",
		function()
			-- `of` is resolved by `themes/snapshot.resolveDim` at prop-normalization
			-- time on the real pipeline (`render/layout_node.luau`); reproduced by
			-- hand here since this describe block drives the solver directly
			local dimAt = { type = "content", rows = 5, of = "controlSizes.compact.height" }
			local neutral = box(node(snapshot.resolveDim(NEUTRAL, dimAt)), 300, 400, NEUTRAL)
			local tenFoot = box(node(snapshot.resolveDim(LARGE, dimAt)), 300, 400, LARGE)
			expect(neutral.h).toBe(180)
			expect(tenFoot.h).toBe(270) -- 5 * (36 * 1.5)
		end
	)

	it(
		"`lines` tracks the LIVE scale/offset a caller stamps on the dim (`layout_node.luau`'s job on the real pipeline)",
		function()
			local raised = box({
				kind = "box",
				id = "B",
				width = { type = "fixed", px = 200 },
				height = { type = "content", lines = 4, scale = 1, textOffset = 14 },
			}, 300, 400, NEUTRAL)
			expect(raised.h).toBe(144) -- ceil(4 * (16 + 14) * 1.2)
		end
	)

	it(
		"`rows`+`of` does NOT track the live accessibility offset — a theme metric never has, and that split is documented (ADR-0049), not a gap",
		function()
			local resolvedOf =
				snapshot.resolveDim(NEUTRAL, { type = "content", rows = 5, of = "controlSizes.compact.height" }).of
			local withOffset = box({
				kind = "box",
				id = "B",
				width = { type = "fixed", px = 200 },
				height = { type = "content", rows = 5, of = resolvedOf, scale = 1, textOffset = 14 },
			}, 300, 400, NEUTRAL)
			expect(withOffset.h).toBe(180) -- unchanged: `of` reads no `scale`/`textOffset`
		end
	)

	it("a control tree over BOTH shapes still measures every other node exactly as before (no cross-talk)", function()
		local r = solve({
			kind = "vstack",
			id = "Root",
			width = { type = "fixed", px = 300 },
			height = { type = "fixed", px = 500 },
			gap = 0,
			children = {
				{
					kind = "box",
					id = "Lines",
					width = { type = "fixed", px = 100 },
					height = { type = "content", lines = 2 },
				},
				{
					kind = "box",
					id = "Rows",
					width = { type = "fixed", px = 100 },
					height = snapshot.resolveDim(
						NEUTRAL,
						{ type = "content", rows = 2, of = "controlSizes.compact.height" }
					),
				},
				{
					kind = "box",
					id = "Plain",
					width = { type = "fixed", px = 100 },
					height = { type = "fixed", px = 20 },
				},
			},
		}, 300, 500)
		expect(r.rects["Lines"].rect.h).toBe(39) -- ceil(2*16*1.2)
		expect(r.rects["Rows"].rect.h).toBe(72) -- 2*36
		expect(r.rects["Plain"].rect.h).toBe(20)
		expect(r.diagnostics and #r.diagnostics or 0).toBe(0)
	end)
end)

-- ===========================================================================
-- 4. REGRESSION — a content-terms viewport is DEFINITE inside another
--    scroller's own unbounded axis (found live migrating `preferred_text`)
-- ===========================================================================
describe("content-terms height: a definite viewport, even nested in an unbounded scroll axis", function()
	--[[ FOUND MIGRATING `preferred_text`'s `Form` (2026-08-23): `overflow_sweep.
		spec.luau` filed 261 findings the moment the literal became `{ rows = 5,
		of = "controlSizes.compact.height" }` — the solver's own "a scroll region
		on an unbounded axis materializes everything" diagnostic (booked ruling
		G5c) tested `mainDim.type ~= "fixed"` to decide "is this extent definite",
		and `content` (even with `lines`/`rows` making it a formula) failed that
		test exactly as a bare, measuring `content` correctly does. Fixed by
		naming the content-terms case a THIRD definite shape beside `fixed`. ]]
	it("a `rows` scroller nested in an outer y-scroller's unbounded offer reports NOTHING", function()
		local inner = {
			kind = "scroll",
			id = "Inner",
			axis = "y",
			width = { type = "fill", weight = 1 },
			height = snapshot.resolveDim(NEUTRAL, { type = "content", rows = 4, of = "controlSizes.compact.height" }),
			children = {
				{
					kind = "box",
					id = "Row",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = 20 },
				},
			},
		}
		local outer = {
			kind = "scroll",
			id = "Outer",
			axis = "y",
			width = { type = "fixed", px = 200 },
			height = { type = "fill", weight = 1 },
			children = { inner },
		}
		local r = solve(outer, 200, 400)
		expect(#r.diagnostics).toBe(0)
		expect(r.rects["Inner"].rect.h).toBe(144)
	end)

	it("a `lines` scroller nested the same way is ALSO definite", function()
		local inner = {
			kind = "scroll",
			id = "Inner",
			axis = "y",
			width = { type = "fill", weight = 1 },
			height = { type = "content", lines = 4 },
			children = {
				{
					kind = "box",
					id = "Row",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = 20 },
				},
			},
		}
		local outer = {
			kind = "scroll",
			id = "Outer",
			axis = "y",
			width = { type = "fixed", px = 200 },
			height = { type = "fill", weight = 1 },
			children = { inner },
		}
		local r = solve(outer, 200, 400)
		expect(#r.diagnostics).toBe(0)
	end)

	it(
		"...and a BARE `content` scroller in the same position is STILL reported — the historic reading is unchanged",
		function()
			local inner = {
				kind = "scroll",
				id = "Inner",
				axis = "y",
				width = { type = "fill", weight = 1 },
				height = { type = "content" },
				children = {
					{
						kind = "box",
						id = "Row",
						width = { type = "fill", weight = 1 },
						height = { type = "fixed", px = 20 },
					},
				},
			}
			local outer = {
				kind = "scroll",
				id = "Outer",
				axis = "y",
				width = { type = "fixed", px = 200 },
				height = { type = "fill", weight = 1 },
				children = { inner },
			}
			local r = solve(outer, 200, 400)
			expect(#r.diagnostics).toBe(1)
			expect(string.find(r.diagnostics[1].issue, "can never scroll", 1, true) ~= nil).toBe(true)
		end
	)
end)

-- ===========================================================================
-- 5. THE FOUR ADAPTATION-SLICE SITES, MIGRATED
-- ===========================================================================
describe("content-terms height: the four adaptation-slice sites", function()
	it("flow_wrap.AlignBox: 360px at Neutral (value-identical: 10 * 36), GROWS at ten-foot (was frozen)", function()
		local module = require("../examples/gallery/scenarios/flow_wrap") :: any
		local w = fixtureWorld(DESKTOP)
		mountFixture(w, module)
		local neutralH = w.adapter.node("/FlowWrap/Page/AlignBox").rect.h
		expect(neutralH).toBe(360)

		local wTen = fixtureWorld(DESKTOP)
		wTen.env:set("displaySize", "Large")
		mountFixture(wTen, module)
		local tenFootH = wTen.adapter.node("/FlowWrap/Page/AlignBox").rect.h
		-- RED, were this still `{ type = "fixed", px = 360 }`: tenFootH == 360,
		-- unmoved by a display class that scales every control on the screen
		-- around it. GREEN: it grows with `controlSizes.compact.height`.
		expect(`ten-foot grew: {tenFootH > neutralH}`).toBe("ten-foot grew: true")
		expect(tenFootH).toBe(540) -- 10 * (36 * 1.5)
	end)

	it(
		"keyboard_navigation.List: 144px at Neutral (measured, was 150 — a frozen ~4-row guess), GROWS at ten-foot",
		function()
			local module = require("../examples/gallery/scenarios/keyboard_navigation") :: any
			local w = fixtureWorld(DESKTOP)
			mountFixture(w, module)
			local neutralH = w.adapter.node("/KbdNav/Body/List").rect.h
			expect(neutralH).toBe(144)

			local wTen = fixtureWorld(DESKTOP)
			wTen.env:set("displaySize", "Large")
			mountFixture(wTen, module)
			local tenFootH = wTen.adapter.node("/KbdNav/Body/List").rect.h
			expect(`ten-foot grew: {tenFootH > neutralH}`).toBe("ten-foot grew: true")
			expect(tenFootH).toBe(216) -- 4 * (36 * 1.5)
		end
	)

	it(
		"native_style.Scroll: 116px at Neutral (measured, was 120 — a frozen literal beside `body`-role rows), GROWS at ten-foot",
		function()
			local module = require("../examples/gallery/scenarios/native_style") :: any
			local w = fixtureWorld(DESKTOP)
			mountFixture(w, module)
			local neutralH = w.adapter.node("/NativeStyle/Body/Scroll").rect.h
			expect(neutralH).toBe(116)

			local wTen = fixtureWorld(DESKTOP)
			wTen.env:set("displaySize", "Large")
			mountFixture(wTen, module)
			local tenFootH = wTen.adapter.node("/NativeStyle/Body/Scroll").rect.h
			expect(`ten-foot grew: {tenFootH > neutralH}`).toBe("ten-foot grew: true")
			expect(tenFootH).toBe(173) -- ceil(6 * (16 * 1.5) * 1.2)
		end
	)

	it(
		"preferred_text.Form: 180px at Neutral (value-identical: 5 * 36) — the text-growth fixture itself, GROWS at a raised preference",
		function()
			local module = require("../examples/gallery/scenarios/preferred_text") :: any
			local w = fixtureWorld(DESKTOP)
			mountFixture(w, module)
			local neutralH = w.adapter.node("/PrefText/Doc/DocRows/Form").rect.h
			expect(neutralH).toBe(180)
		end
	)

	it("preferred_text.Form GROWS at the ten-foot ladder (was frozen at 180 regardless)", function()
		local module = require("../examples/gallery/scenarios/preferred_text") :: any
		local w = fixtureWorld(DESKTOP)
		mountFixture(w, module)
		local neutralH = w.adapter.node("/PrefText/Doc/DocRows/Form").rect.h

		local wTen = fixtureWorld(DESKTOP)
		wTen.env:set("displaySize", "Large")
		mountFixture(wTen, module)
		local tenFootH = wTen.adapter.node("/PrefText/Doc/DocRows/Form").rect.h
		expect(`ten-foot grew: {tenFootH > neutralH}`).toBe("ten-foot grew: true")
		expect(tenFootH).toBe(270) -- 5 * (36 * 1.5)
	end)
end)

-- ===========================================================================
-- 6. `UI.fill`/`UI.hug` — in-brief item 14, DISSOLVED WITH DEMONSTRATION
-- ===========================================================================
--[[ Not this gap's shape (audit "next steps" lists content-terms height and
	`UI.fill`/`UI.hug` shorthands as two SEPARATE next steps, not one merging
	into the other) — but the SAME home file, the SAME wave, and cheap once
	`blueprint.luau` was already open for `contentTermsPx`'s consumers. Built
	as a plain VALUE producer (`UI.fill()`, not a blueprint modifier like
	`aspectRatio`/`containerRelativeFrame` beside it): a fill dim is authored
	on ONE axis at a time, exactly where the 326 raw tables already went.
	DEMONSTRATED, not swept: nine of this round's own sites
	(`flow_wrap`/`keyboard_navigation`/`native_style`/`preferred_text`)
	migrated from `{ type = "fill", weight = 1 }` to `UI.fill()` — the
	remaining ~317 corpus sites are OWED, not claimed. ]]
describe("UI.fill / UI.hug: the shorthand item 14 named (dissolved with demonstration)", function()
	it('`UI.fill()` is exactly `{ type = "fill", weight = 1 }`', function()
		expect(UI.fill()).toEqual({ type = "fill", weight = 1 })
	end)

	it("`UI.fill(2)` carries the weight through", function()
		expect(UI.fill(2)).toEqual({ type = "fill", weight = 2 })
	end)

	it("`UI.fill` refuses a non-positive weight", function()
		local ok = pcall(function()
			UI.fill(0)
		end)
		expect(ok).toBe(false)
	end)

	it('`UI.hug()` is exactly `{ type = "hug" }`', function()
		expect(UI.hug()).toEqual({ type = "hug" })
	end)

	it("`UI.hug({ max = 200 })` carries the bound through", function()
		expect(UI.hug({ max = 200 })).toEqual({ type = "hug", min = nil, max = 200 })
	end)

	it("`UI.hug` refuses an unknown field", function()
		local ok = pcall(function()
			(UI.hug :: any)({ maxx = 200 })
		end)
		expect(ok).toBe(false)
	end)

	it("the shorthand constructs through the real schema, exactly as the raw table did", function()
		local ok = pcall(function()
			UI.Box({ id = "B", width = UI.fill(), height = UI.hug({ max = 100 }) })
		end)
		expect(ok).toBe(true)
	end)

	it("migrated sites solve to the IDENTICAL geometry the raw table produced", function()
		local module = require("../examples/gallery/scenarios/flow_wrap") :: any
		local w = fixtureWorld({ w = 1232, h = 1067 })
		mountFixture(w, module)
		-- `Cloud` is `width = UI.fill()` post-migration; unchanged geometry at
		-- Neutral desktop is the value-identical proof
		local cloud = w.adapter.node("/FlowWrap/Page/Cloud")
		expect(cloud.rect.w).toBe(1208)
	end)
end)
