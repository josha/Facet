--!strict
-- Edge-floor knob (FIX-4 item 2, director ruling 2026-08-23): "If the user
-- truly specifies edge-to-edge we should do so with no padding. Ensure the
-- user can specify padding; perhaps even default so things don't ride the
-- edge by default but can be made to." This file pins the KNOB half of that
-- ruling — a root-level padding a consumer can opt into, shaped like the
-- `rootPolicy`/`PresentOpts` grammar (`renderer.attach`'s own `edgeFloor` opt,
-- threaded through `presenter.present`/`presentModal`/`presentCritical`). The
-- MEASUREMENT half (the corrected floor-harness numbers) is reported, not
-- pinned here — see task-fix4-report.md item 2. Whether the DEFAULT ever
-- flips is a separate, unshipped ADR-0040 row (director's word, not this
-- round's).
--
-- RED-FIRST: every case below failed before `edgeFloor` existed —
-- `specGuard.assertKnownKeys` refused it as an unknown opts key on both
-- `renderer.attach` and `presenter.present`/`presentModal`/`presentCritical`,
-- and no branch in `solveAndApply` read it.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local themeSnapshot = require("../src/themes/snapshot")
local fake_target = require("./lib/fake_target")

local function world(insets: any, metrics: any?, displaySize: string?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
	env:set("coreSafeInsets", insets)
	-- `themeMetrics` is the AUTHORED base a theme controller commits
	-- (`env/environment.luau`'s own header: "what is set is always the
	-- authored base" — `env:get("themeMetrics")` hands back that base run
	-- through `themeSnapshot.forDisplay(base, displaySize)`, deriving the
	-- ten-foot ladder from the LIVE `displaySize` signal rather than trusting
	-- an already-scaled snapshot handed in directly, which `baseOf` would
	-- just unwind back to near). So the ten-foot cases below set BOTH: the
	-- near/authored snapshot here, and `displaySize` separately.
	env:set("themeMetrics", metrics or themeSnapshot.resolve(Facet.themes.neutralPackage(), nil, {}))
	if displaySize ~= nil then
		env:set("displaySize", displaySize)
		-- ISOLATION, not a claim about the real fact: `Large` also turns on
		-- the ten-foot OVERSCAN margin (a SEPARATE, unrelated composition —
		-- `solveAndApply`'s own `distanceProfile == "ten-foot"` branch, 90px
		-- on this package), which would otherwise dominate the `max()` these
		-- cases test and prove nothing about `edgeFloor` specifically.
		-- `overscanInsets` is the AUTHORED fact `effectiveOverscanInsets`
		-- derives from (that one is derived-only, unsettable) — opted out
		-- with its own "none" sentinel (a zero-valued table reads as
		-- NOTHING AUTHORED, which falls through to the very Large-display
		-- default this case is trying to exclude) so the case measures one
		-- mechanism at a time.
		env:set("overscanInsets", "none")
	end
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
	return presenter, adapter
end

local function fullScreen(id: string)
	return Facet.UI.Screen({
		id = id,
		children = {
			Facet.UI.Spacer({
				id = "Fill",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
			}),
		},
	})
end

describe("renderer/presenter — edgeFloor knob (FIX-4 item 2)", function()
	it("THE PIN: explicit edgeToEdge with no knob stays ZERO padding, unchanged", function()
		local presenter, adapter = world({ top = 40, bottom = 10, left = 5, right = 5 })
		presenter.present(fullScreen("Backdrop"), { rootPolicy = "edgeToEdge" })
		presenter.refresh()
		local rect = adapter.node("/Backdrop/Fill").rect
		expect(rect.x).toBe(0)
		expect(rect.y).toBe(0)
		expect(rect.w).toBe(400)
		expect(rect.h).toBe(300)
	end)

	it("refuses edgeFloor together with rootPolicy = edgeToEdge instead of picking a winner", function()
		local presenter = world({ top = 40, bottom = 0, left = 0, right = 0 })
		local ok, err = pcall(function()
			presenter.present(fullScreen("Bad"), { rootPolicy = "edgeToEdge", edgeFloor = 16 })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "edgeFloor", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "edgeToEdge", 1, true) ~= nil).toBe(true)
	end)

	it("the SAME refusal fires straight off renderer.attach, not just through the presenter", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("themeMetrics", themeSnapshot.resolve(Facet.themes.neutralPackage(), nil, {}))
		local bp = fullScreen("Direct")
		local root = Facet.mount(core, bp)
		local adapter = fake_target.new()
		local renderer = require("../src/render/renderer")
		local ok, err = pcall(function()
			renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge", edgeFloor = 8 })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "edgeFloor", 1, true) ~= nil).toBe(true)
	end)

	it("omitted edgeFloor on coreSafeContent is unchanged behavior (no default flip)", function()
		local presenter, adapter = world({ top = 40, bottom = 10, left = 5, right = 5 })
		presenter.present(fullScreen("Content"))
		presenter.refresh()
		local rect = adapter.node("/Content/Fill").rect
		expect(rect.y).toBe(40)
		expect(rect.x).toBe(5)
		expect(rect.h).toBe(250)
		expect(rect.w).toBe(390)
	end)

	it("a literal-number edgeFloor floors bottom/left/right, never top (ADR-0027)", function()
		local presenter, adapter = world({ top = 40, bottom = 10, left = 5, right = 5 })
		presenter.present(fullScreen("Padded"), { edgeFloor = 24 })
		presenter.refresh()
		local rect = adapter.node("/Padded/Fill").rect
		expect(rect.y).toBe(40) -- top untouched
		expect(rect.x).toBe(24) -- floored up from 5
		expect(rect.w).toBe(400 - 24 - 24)
		expect(rect.h).toBe(300 - 40 - 24)
	end)

	it("an edgeFloor SMALLER than the existing inset is a no-op (max, not override)", function()
		local presenter, adapter = world({ top = 40, bottom = 10, left = 30, right = 30 })
		presenter.present(fullScreen("Roomy"), { edgeFloor = 8 })
		presenter.refresh()
		local rect = adapter.node("/Roomy/Fill").rect
		expect(rect.x).toBe(30) -- the existing 30px inset wins, unchanged
		expect(rect.w).toBe(400 - 30 - 30)
	end)

	it("a metric-name edgeFloor resolves through the live theme snapshot", function()
		local pkg = Facet.themes.neutralPackage()
		local nearSnap = themeSnapshot.resolve(pkg, nil, {})
		local presenter, adapter = world({ top = 40, bottom = 0, left = 0, right = 0 }, nearSnap)
		presenter.present(fullScreen("Metric"), { edgeFloor = "l" })
		presenter.refresh()
		local rect = adapter.node("/Metric/Fill").rect
		local expected = (nearSnap :: any).space.l
		expect(expected > 0).toBe(true)
		expect(rect.x).toBe(expected)
		expect(rect.w).toBe(400 - expected - expected)
	end)

	it("a metric-name edgeFloor rides the ten-foot ladder, like its neighbors (space.gutter, cellPadding)", function()
		local pkg = Facet.themes.neutralPackage()
		local nearSnap = themeSnapshot.resolve(pkg, nil, {})
		local tenFootSnap = themeSnapshot.forDisplay(nearSnap, "Large")
		-- the ladder is real for this metric, or the rest of the case proves nothing
		expect((tenFootSnap :: any).space.l > (nearSnap :: any).space.l).toBe(true)

		-- the AUTHORED (near) snapshot goes in `themeMetrics`; `displaySize`
		-- is the live signal `env:get("themeMetrics")`'s own memo derives the
		-- ladder from (see `world`'s header) — the same two facts a real
		-- console session carries, not a pre-scaled snapshot handed in directly.
		local presenter, adapter = world({ top = 40, bottom = 0, left = 0, right = 0 }, nearSnap, "Large")
		presenter.present(fullScreen("TenFoot"), { edgeFloor = "l" })
		presenter.refresh()
		local rect = adapter.node("/TenFoot/Fill").rect
		expect(rect.x).toBe((tenFootSnap :: any).space.l)
	end)

	it("a literal number does NOT ride the ladder — it is a pixel count at every distance", function()
		local pkg = Facet.themes.neutralPackage()
		local nearSnap = themeSnapshot.resolve(pkg, nil, {})
		local presenter, adapter = world({ top = 40, bottom = 0, left = 0, right = 0 }, nearSnap, "Large")
		presenter.present(fullScreen("Literal"), { edgeFloor = 24 })
		presenter.refresh()
		local rect = adapter.node("/Literal/Fill").rect
		expect(rect.x).toBe(24)
	end)

	it("composes with bandSafeContent's own gutter floor — the larger of the two wins", function()
		local pkg = Facet.themes.neutralPackage()
		local snap = themeSnapshot.resolve(pkg, nil, {})
		local gutter = (snap :: any).space.gutter
		local presenter, adapter = world({ top = 40, bottom = 0, left = 0, right = 0 }, snap)
		presenter.present(fullScreen("Band"), { rootPolicy = "bandSafeContent", edgeFloor = gutter + 40 })
		presenter.refresh()
		local rect = adapter.node("/Band/Fill").rect
		expect(rect.x).toBe(gutter + 40)
	end)

	it("bandSafeContent's own gutter floor still wins when it is the larger of the two", function()
		local pkg = Facet.themes.neutralPackage()
		local snap = themeSnapshot.resolve(pkg, nil, {})
		local gutter = (snap :: any).space.gutter
		local presenter, adapter = world({ top = 40, bottom = 0, left = 0, right = 0 }, snap)
		presenter.present(fullScreen("BandSmall"), { rootPolicy = "bandSafeContent", edgeFloor = 1 })
		presenter.refresh()
		local rect = adapter.node("/BandSmall/Fill").rect
		expect(rect.x).toBe(gutter)
	end)

	it(
		"an unresolvable metric name falls back to no floor (renderer falls back, per resolveNumber's own contract)",
		function()
			local presenter, adapter = world({ top = 40, bottom = 0, left = 5, right = 5 })
			presenter.present(fullScreen("Garbage"), { edgeFloor = "not-a-real-metric" })
			presenter.refresh()
			local rect = adapter.node("/Garbage/Fill").rect
			expect(rect.x).toBe(5) -- unchanged: the garbage name resolved to nil, not a crash
		end
	)
end)
