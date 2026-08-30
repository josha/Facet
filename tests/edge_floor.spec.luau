--!strict
-- Edge-floor knob (FIX-4 item 2, director ruling 2026-08-23): "If
-- the user truly specifies edge-to-edge we should do so with no padding.
-- Ensure the user can specify padding; perhaps even default so things don't
-- ride the edge by default but can be made to." This file pins the KNOB half
-- of that ruling — a root-level padding a consumer can opt into, shaped like
-- the `rootPolicy`/`PresentOpts` grammar (`renderer.attach`'s own `edgeFloor`
-- opt, threaded through `presenter.present`/`presentModal`/`presentCritical`).
-- The MEASUREMENT half (the corrected floor-harness numbers) is reported, not
-- pinned here — see task-fix4-report.md item 2. Whether the DEFAULT ever
-- flips is a separate, unshipped changelog row (director's word, not this
-- round's).
--
-- RED-FIRST: every case below failed before `edgeFloor` existed —
-- `specGuard.assertKnownKeys` refused it as an unknown opts key on both
-- `renderer.attach` and `presenter.present`/`presentModal`/`presentCritical`,
-- and no branch in `solveAndApply` read it.
--
-- Built on `tests/lib/world.luau` (R12's own follow-up trigger, world_substrate
-- .spec.luau's HAND_ROLLED_BUILDERS ratchet: "the next spec file that ADDS a
-- builder migrates its file onto the shared substrate instead") rather than a
-- spec-local presenter builder.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local themeSnapshot = require("../src/themes/snapshot")
local fake_target = require("./lib/fake_target")
local worldLib = require("./lib/world")

-- the 400x300 viewport + insets shape every case below shares, plus the two
-- ten-foot-isolation facts (see the "rides the ten-foot ladder" case): `Large`
-- also turns on this framework's REAL overscan margin
-- (`effectiveOverscanInsets`, 90px on this package) — a SEPARATE, unrelated
-- composition that would otherwise dominate the `max()` these cases test and
-- prove nothing about `edgeFloor` specifically. `overscanInsets = "none"` is
-- the AUTHORED opt-out (a zero-valued table reads as NOTHING AUTHORED, which
-- falls through to the very Large-display default this is trying to exclude).
local function newWorld(insets: any, metrics: any?, displaySize: string?): any
	return worldLib.new({
		viewport = { x = 0, y = 0, w = 400, h = 300 },
		safeInsets = insets,
		themeMetrics = metrics or themeSnapshot.resolve(Facet.themes.neutralPackage(), nil, {}),
		displaySize = displaySize,
		env = if displaySize ~= nil then { overscanInsets = "none" } else nil,
	})
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
		local w = newWorld({ top = 40, bottom = 10, left = 5, right = 5 })
		w.present(fullScreen("Backdrop"), { rootPolicy = "edgeToEdge" })
		local rect = w.adapter.node("/Backdrop/Fill").rect
		expect(rect.x).toBe(0)
		expect(rect.y).toBe(0)
		expect(rect.w).toBe(400)
		expect(rect.h).toBe(300)
	end)

	it("refuses edgeFloor together with rootPolicy = edgeToEdge instead of picking a winner", function()
		local w = newWorld({ top = 40, bottom = 0, left = 0, right = 0 })
		local ok, err = pcall(function()
			w.present(fullScreen("Bad"), { rootPolicy = "edgeToEdge", edgeFloor = 16 })
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
		local w = newWorld({ top = 40, bottom = 10, left = 5, right = 5 })
		w.present(fullScreen("Content"))
		local rect = w.adapter.node("/Content/Fill").rect
		expect(rect.y).toBe(40)
		expect(rect.x).toBe(5)
		expect(rect.h).toBe(250)
		expect(rect.w).toBe(390)
	end)

	it("a literal-number edgeFloor floors bottom/left/right, never top", function()
		local w = newWorld({ top = 40, bottom = 10, left = 5, right = 5 })
		w.present(fullScreen("Padded"), { edgeFloor = 24 })
		local rect = w.adapter.node("/Padded/Fill").rect
		expect(rect.y).toBe(40) -- top untouched
		expect(rect.x).toBe(24) -- floored up from 5
		expect(rect.w).toBe(400 - 24 - 24)
		expect(rect.h).toBe(300 - 40 - 24)
	end)

	it("an edgeFloor SMALLER than the existing inset is a no-op (max, not override)", function()
		local w = newWorld({ top = 40, bottom = 10, left = 30, right = 30 })
		w.present(fullScreen("Roomy"), { edgeFloor = 8 })
		local rect = w.adapter.node("/Roomy/Fill").rect
		expect(rect.x).toBe(30) -- the existing 30px inset wins, unchanged
		expect(rect.w).toBe(400 - 30 - 30)
	end)

	it("a metric-name edgeFloor resolves through the live theme snapshot", function()
		local pkg = Facet.themes.neutralPackage()
		local nearSnap = themeSnapshot.resolve(pkg, nil, {})
		local w = newWorld({ top = 40, bottom = 0, left = 0, right = 0 }, nearSnap)
		w.present(fullScreen("Metric"), { edgeFloor = "l" })
		local rect = w.adapter.node("/Metric/Fill").rect
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

		-- the AUTHORED (near) snapshot goes in `themeMetrics`; `displaySize` is
		-- the live signal `env:get("themeMetrics")`'s own memo derives the
		-- ladder from (see `newWorld`'s header) — the same two facts a real
		-- console session carries, not a pre-scaled snapshot handed in directly.
		local w = newWorld({ top = 40, bottom = 0, left = 0, right = 0 }, nearSnap, "Large")
		w.present(fullScreen("TenFoot"), { edgeFloor = "l" })
		local rect = w.adapter.node("/TenFoot/Fill").rect
		expect(rect.x).toBe((tenFootSnap :: any).space.l)
	end)

	it("a literal number does NOT ride the ladder — it is a pixel count at every distance", function()
		local pkg = Facet.themes.neutralPackage()
		local nearSnap = themeSnapshot.resolve(pkg, nil, {})
		local w = newWorld({ top = 40, bottom = 0, left = 0, right = 0 }, nearSnap, "Large")
		w.present(fullScreen("Literal"), { edgeFloor = 24 })
		local rect = w.adapter.node("/Literal/Fill").rect
		expect(rect.x).toBe(24)
	end)

	it("composes with bandSafeContent's own gutter floor — the larger of the two wins", function()
		local pkg = Facet.themes.neutralPackage()
		local snap = themeSnapshot.resolve(pkg, nil, {})
		local gutter = (snap :: any).space.gutter
		local w = newWorld({ top = 40, bottom = 0, left = 0, right = 0 }, snap)
		w.present(fullScreen("Band"), { rootPolicy = "bandSafeContent", edgeFloor = gutter + 40 })
		local rect = w.adapter.node("/Band/Fill").rect
		expect(rect.x).toBe(gutter + 40)
	end)

	it("bandSafeContent's own gutter floor still wins when it is the larger of the two", function()
		local pkg = Facet.themes.neutralPackage()
		local snap = themeSnapshot.resolve(pkg, nil, {})
		local gutter = (snap :: any).space.gutter
		local w = newWorld({ top = 40, bottom = 0, left = 0, right = 0 }, snap)
		w.present(fullScreen("BandSmall"), { rootPolicy = "bandSafeContent", edgeFloor = 1 })
		local rect = w.adapter.node("/BandSmall/Fill").rect
		expect(rect.x).toBe(gutter)
	end)

	it(
		"an unresolvable metric name falls back to no floor (renderer falls back, per resolveNumber's own contract)",
		function()
			local w = newWorld({ top = 40, bottom = 0, left = 5, right = 5 })
			w.present(fullScreen("Garbage"), { edgeFloor = "not-a-real-metric" })
			local rect = w.adapter.node("/Garbage/Fill").rect
			expect(rect.x).toBe(5) -- unchanged: the garbage name resolved to nil, not a crash
		end
	)
end)
