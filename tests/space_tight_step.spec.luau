--!strict
-- THE MISSING SPACING STEP (task G-SPACE, ADR-0047; the declarative-purity
-- audit's `gap = 6` finding). `xs` (4) and `s` (8) are the ladder's two
-- smallest REQUIRED rungs and nothing named the value halfway between them —
-- see `src/themes/package.luau`'s `DERIVED_SPACE_STEPS` comment for the full
-- naming-doctrine argument and `src/themes/snapshot.luau`'s resolve-time
-- derivation (beside `space.gutter`, the sibling this step follows the same
-- shape as).
--
-- What this file proves that `tests/ten_foot_metrics.spec.luau` (the ladder
-- proportion sweep) and `tools/lune/check_theme_drift.luau` (the sweep census)
-- do not: the token resolves at NEUTRAL to exactly 6, AUTHORED BEATS DERIVED
-- exactly as `space.gutter` already does, the derivation TRACKS a package's
-- own `xs`/`s` rather than hard-coding Studio Neutral's 6, and the token is
-- legal in the CHANNELS the brief named — a blueprint `gap` prop and the
-- VirtualList/VirtualGrid `gap_metric` channel G5 built.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local gap_metric = require("../src/controls/gap_metric")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")
local environment = require("../src/env/environment")
local customFactory = require("../src/core/custom")

local function derive(metrics: any, id: string?): any
	local pkg, report = themes.define({
		base = snapshot.neutralPackage(),
		identity = {
			id = id or "derived",
			displayName = "Derived",
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		metrics = metrics,
	})
	assert(pkg ~= nil, "derive: " .. (if report.errors[1] then report.errors[1].message else "?"))
	return pkg
end

describe("space.tight — the missing spacing step (ADR-0047)", function()
	it("resolves to 6 at Studio Neutral (xs=4, s=8)", function()
		local neutral = snapshot.neutral()
		expect(neutral.space.tight).toBe(6)
	end)

	it("is a recognized space step, resolvable by name", function()
		local neutral = snapshot.neutral()
		expect(snapshot.isSpaceStep("tight")).toBeTruthy()
		expect(snapshot.resolveNumber(neutral, "tight")).toBe(6)
		expect(snapshot.resolveNumber(neutral, "-tight")).toBe(-6)
	end)

	-- AUTHORED BEATS DERIVED, the rule `space.gutter` already spends (ten_foot_
	-- metrics.spec.luau's package-authority describe carries the tenFoot-channel
	-- half of this rule; this is the space-step half).
	it("an authored space.tight wins outright", function()
		local pkg = derive({ space = { tight = 99 } }, "tight-authored")
		local snap = snapshot.resolve(pkg)
		expect(snap.space.tight).toBe(99)
	end)

	-- THE FORMULA TRACKS THE PACKAGE'S OWN LADDER, not a Studio-Neutral literal:
	-- a package that re-ladders xs/s moves the derived midpoint with them, which
	-- is what makes this step correct for every package rather than a constant
	-- that happens to equal 6 today.
	it("an unauthored space.tight derives as the midpoint of the package's own xs/s", function()
		local pkg = derive({ space = { xs = 6, s = 10 } }, "tight-derived-custom")
		local snap = snapshot.resolve(pkg)
		expect(snap.space.tight).toBe(8)
	end)

	it("rides the ten-foot ladder like its neighbors (non-1.0 rung)", function()
		local neutral = snapshot.neutral()
		local tenFoot = snapshot.forDisplay(neutral, "Large")
		expect(tenFoot.metricScale).toBe(1.5)
		expect(tenFoot.space.tight).toBe(9)
		expect(snapshot.densityClassOf("space.tight")).toBe("scale")
	end)

	-- THE gap/rowGap/padding/px= CHANNELS, and the VirtualList/VirtualGrid
	-- token channel G5 built (`src/controls/gap_metric.luau`) — the four the
	-- brief names as "every channel its neighbors are valid in".
	it("resolves through a blueprint gap prop", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "R",
					gap = "tight",
					children = {
						UI.Box({ id = "a", width = { type = "fixed", px = 20 }, height = { type = "fixed", px = 20 } }),
						UI.Box({ id = "b", width = { type = "fixed", px = 20 }, height = { type = "fixed", px = 20 } }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		local aRect = adapter.node("/S/R/a").rect
		local bRect = adapter.node("/S/R/b").rect
		expect(bRect.x - (aRect.x + 20)).toBe(6)
	end)

	it("resolves through the VirtualList/VirtualGrid gap_metric channel", function()
		local neutral = snapshot.neutral()
		local reader = gap_metric.reader({
			env = nil,
			label = "Test.gap",
			value = "tight",
			default = 0,
			what = "space_tight_step.spec test",
		})
		expect(reader.Now()).toBe(6)
		expect(reader.live).toBeTruthy()
		local numberReader = gap_metric.reader({
			env = nil,
			label = "Test.gap",
			value = neutral.space.tight,
			default = 0,
			what = "space_tight_step.spec test",
		})
		expect(numberReader.Now()).toBe(6)
	end)
end)
