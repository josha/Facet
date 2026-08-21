--!strict
--[[ TEN-FOOT METRICS — THE WHOLE LADDER SCALES, BY THE TYPE'S OWN FACTOR.

	THE DIRECTOR'S RULING (2026-08-20, ADAPT-8). The framework's ten-foot policy
	was four rows — the 1.5x TYPE floor, the sizeClass density cap, the focus
	strengthening and the overscan margins — and metric spacing was never one of
	them, so control heights, paddings, icon sizes and the 44 px hit floor on a
	television were byte-identical to a phone's. The audit recorded that as a
	SCOPE question rather than a defect (`adapt-audit/matrix.md` ADAPT-8) and put
	it to the director, who ruled AGAINST type-only: on ten-foot the whole metric
	ladder scales with the type, tvOS-style.

	THE FACTOR IS NOT A SECOND CONSTANT. It is `tenFootFloor` — the type floor's
	own 1.5 — read through `snapshot.metricScale`, which is `typographyPaintScale`
	spelled for metrics. That is what makes the acceptance below FALSIFIABLE
	rather than eyeballed:

	  EVERY TEXT-TO-CONTROL PROPORTION AT TEN-FOOT EQUALS ITS NEAR PROPORTION.

	A 16 px label in a 44 px control at near is a 24 px label in a 66 px control
	at three metres. Nothing outgrows its chrome, and the claim is checkable on
	every metric of every shipped configuration rather than on a screenshot.

	WHERE IT IS APPLIED, AND WHY THERE (ADAPT-L1, the Part-2 layout audit's top
	finding). The type floor is applied in the ENVIRONMENT — `typographyScale` and
	`typographyPaintScale` are derived memos over the live `displaySize` fact — so
	it reaches a television with no theme package installed. The DENSITY half did
	not: it rode `snapshot.resolve`'s recorded `density`, and the environment's
	default snapshot is `themes.neutral()`, resolved with no facts at all, so a TV
	measured 10 lanes against a desktop's 9 while painting 1.5x type into them.
	The metric floor is therefore applied at the SAME SEAM the type floor uses —
	one derived memo, over the same fact, calling the same function — and the
	snapshot goes on carrying the AUTHORED ladder. `snapshot.resolve` still
	records `density` and still re-applies nothing.

	WHAT THIS FILE IS. The standing guard for the ruling: the proportion sweep,
	the package-authority rule, the compose-not-double overscan case, the
	single-owner hit floor, and the classification's own completeness — a numeric
	metric nobody classified is a metric that silently stops scaling, so the sweep
	fails on it rather than skipping it. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local layoutNode = require("../src/render/layout_node")
local adaptive = require("../src/layout/adaptive")
local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot") :: any
local fake_target = require("./lib/fake_target")

-- the eight shipped reference packages plus the flat theme = the nine
-- configurations every geometry claim in this repo is measured against
local PACKAGES = {
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"fantasy_ornate",
	"scifi_hud",
	"compact_pointer",
	"classic_desktop",
	"fantasy_parchment",
}

local function packageNamed(name: string?): any
	if name == nil then
		return snapshot.neutralPackage()
	end
	return (require)(`../examples/themes/{name}`).build(Facet.themes)
end

local function configurations(): { { name: string, package: any } }
	local out = { { name = "studio_neutral", package = snapshot.neutralPackage() } }
	for _, name in PACKAGES do
		table.insert(out, { name = name, package = packageNamed(name) })
	end
	return out
end

-- every numeric leaf of a snapshot, as `dotted.path -> number`
local function numericLeaves(node: any, prefix: string, out: { [string]: number })
	for key, value in node do
		local path = if prefix == "" then tostring(key) else `{prefix}.{tostring(key)}`
		if type(value) == "number" then
			out[path] = value
		elseif type(value) == "table" then
			numericLeaves(value, path, out)
		end
	end
end

local function leavesOf(snap: any): { [string]: number }
	local out: { [string]: number } = {}
	numericLeaves(snap, "", out)
	return out
end

-- the near/ten-foot pair for one package, taken through the SEAM rather than by
-- calling the transform with a hand-made argument
local function pair(package: any): (any, any)
	local base = snapshot.resolve(package, nil, {})
	return snapshot.forDisplay(base, "Medium"), snapshot.forDisplay(base, "Large")
end

--[[ A BARE DEFAULT-PATH SURFACE: a core, an environment, a viewport and a
	display class, and NOTHING else — no theme controller, no resolved snapshot,
	no facts handed to anything. This is what `Facet.newPresenter` gives a
	consumer who installs no theme package, and it is the shape ADAPT-L1 measured
	as broken. ]]
local function bareSurface(w: number, h: number, displaySize: string): (any, any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", displaySize)
	return core, env
end

local function rectOf(adapter: any, path: string): any
	local node = adapter.node(path)
	return if node ~= nil then node.rect else nil
end

describe("ten-foot metrics — the factor", function()
	--[[ ONE constant, two ladders. If these ever disagree the type outgrows its
		chrome, which is the exact failure the director's proportion-equality
		acceptance exists to make impossible. ]]
	it("the metric factor IS the type floor's factor", function()
		expect(snapshot.metricScale("Large")).toBe(1.5)
		expect(snapshot.metricScale("Large")).toBe(snapshot.typographyPaintScale("Large"))
		expect(snapshot.metricScale("Medium")).toBe(1)
		expect(snapshot.metricScale("Small")).toBe(1)
		expect(snapshot.metricScale(nil)).toBe(1)
		expect(snapshot.metricScale("Medium")).toBe(snapshot.typographyPaintScale("Medium"))
	end)
end)

describe("ten-foot metrics — proportion equality across the control set", function()
	--[[ THE ACCEPTANCE. Asserted over every scaled metric of every shipped
		configuration, not over a chosen handful: a factor applied to the metrics
		somebody remembered is the defect this sweep exists to catch. ]]
	it("every scaled metric moves by exactly the factor, in all nine configurations", function()
		local checked = 0
		for _, cfg in configurations() do
			local near, tenFoot = pair(cfg.package)
			local unit = near.pixelUnit
			local nearLeaves, tenLeaves = leavesOf(near), leavesOf(tenFoot)
			for path, nearValue in nearLeaves do
				local class = snapshot.densityClassOf(path)
				if class ~= "scale" and class ~= "scaleDown" then
					continue
				end
				local want = nearValue * 1.5

				if type(unit) == "number" then
					want = if class == "scaleDown"
						then math.max(unit, math.floor(want / unit) * unit)
						else themes.snapToPixelUnit(want, unit)
				end
				expect(`{cfg.name}:{path}={tenLeaves[path]}`).toBe(`{cfg.name}:{path}={want}`)
				checked += 1
			end
		end
		-- a sweep that swept nothing passes vacuously
		expect(checked > 350).toBeTruthy()
	end)

	--[[ …AND THE COMPOSITE ARM. A slot inset is the package's authored padding
		PLUS the art's own border, summed once in `resolve`; the authored half
		scales and the art half stays the thickness the engine draws. For the five
		flat packages the art half is zero and this is the plain product, which is
		what makes the ornate arm a real control rather than a restatement. ]]
	it("a slot inset scales its authored half and leaves its art half alone", function()
		local flat, ornate = 0, 0
		for _, cfg in configurations() do
			local base = snapshot.resolve(cfg.package, nil, {})
			local near, tenFoot = pair(cfg.package)
			local unit = near.pixelUnit
			for slot, sides in near.insets do
				for side, px in sides do
					local art = base.chromeInsets[slot][side]
					local want = (px - art) * 1.5 + art
					if type(unit) == "number" then
						want = themes.snapToPixelUnit(want, unit)
					end
					expect(`{cfg.name}.{slot}.{side}={tenFoot.insets[slot][side]}`).toBe(
						`{cfg.name}.{slot}.{side}={want}`
					)
					if art > 0 then
						ornate += 1
					else
						flat += 1
					end
				end
			end
			-- the art half itself never moves
			for slot, sides in base.chromeInsets do
				for side, px in sides do
					expect(`{cfg.name}.art.{slot}.{side}={tenFoot.chromeInsets[slot][side]}`).toBe(
						`{cfg.name}.art.{slot}.{side}={px}`
					)
				end
			end
			expect(tenFoot.chromeBleed).toBe(base.chromeBleed)
		end
		-- both arms are real: some package carves a border and some do not
		expect(flat > 0).toBeTruthy()
		expect(ornate > 0).toBeTruthy()
	end)

	--[[ …AND THE PROPORTION ITSELF, spelled the way the director asked for it: a
		painted text size over a control box, at both distances, equal. The pixel
		package is measured separately below because its own grid is allowed to
		move a length by less than one unit. ]]
	it("the text-to-control proportion at ten-foot equals its near proportion", function()
		local CONTROLS = {
			"controlSizes.compact.height",
			"controlSizes.regular.height",
			"controlSizes.large.height",
			"targetSizes.minimum",
			"controls.button.height",
			"controls.popup.triggerHeight",
			"controls.textInput.fieldHeight",
			"controls.toggle.minHeight",
			"controls.slider.thumbSize",
			"iconSizes.small",
			"iconSizes.medium",
			"iconSizes.large",
			"space.m",
			"space.gutter",
		}
		local ROLES = { "caption", "label", "body", "heading", "title", "control" }
		local compared = 0
		for _, cfg in configurations() do
			local near, tenFoot = pair(cfg.package)
			if type(near.pixelUnit) == "number" then
				continue -- the grid case, asserted above and below
			end
			local nearLeaves, tenLeaves = leavesOf(near), leavesOf(tenFoot)
			for _, role in ROLES do
				local nearText = near.type[role].size * snapshot.typographyPaintScale("Medium")
				local tenText = tenFoot.type[role].size * snapshot.typographyPaintScale("Large")
				for _, path in CONTROLS do
					local nearBox, tenBox = nearLeaves[path], tenLeaves[path]
					expect(nearBox).toBeGreaterThan(0)
					expect(tenBox).toBeGreaterThan(0)
					expect(`{cfg.name} {role}/{path}`).toBe(`{cfg.name} {role}/{path}`)
					expect(tenText / tenBox).toBeCloseTo(nearText / nearBox, 1e-9)
					compared += 1
				end
			end
		end
		expect(compared).toBe(8 * #ROLES * #CONTROLS)
	end)

	--[[ THE PIXEL PACKAGE KEEPS ITS GRID. `pixel_quest` declares an integer
		coordinate system and the resolved snapshot's lengths are multiples of it —
		that is the package's identity, not a rounding preference — so its ten-foot
		ladder snaps onto the same grid and its proportions are equal WITHIN one
		unit rather than exactly. Both halves are asserted: on the grid, and off the
		exact product by less than a unit. ]]
	it("a pixel package's ten-foot ladder stays on its own grid", function()
		local near, tenFoot = pair(packageNamed("pixel_quest"))
		local unit = near.pixelUnit
		expect(type(unit)).toBe("number")
		local nearLeaves, tenLeaves = leavesOf(near), leavesOf(tenFoot)
		local checked = 0
		for path, nearValue in nearLeaves do
			if snapshot.densityClassOf(path) ~= "scale" then
				continue
			end
			local got = tenLeaves[path]
			expect(`{path}: {got % unit}`).toBe(`{path}: 0`)
			expect(math.abs(got - nearValue * 1.5) < unit).toBeTruthy()
			checked += 1
		end
		expect(checked > 60).toBeTruthy()
	end)
end)

describe("ten-foot metrics — ADAPT-L1: the default path carries the density fact", function()
	--[[ THE ADDENDUM'S OWN CELL. Reproduced from the audit: a bare surface, a
		Large display class, no theme controller anywhere. At HEAD before this wave
		the snapshot read `near` forever and the television measured MORE lanes than
		a desktop. ]]
	it("a bare ten-foot mount reads ten-foot density with no theme controller", function()
		local _, env = bareSurface(1920, 1080, "Large")
		expect(env:get("themeMetrics"):get().density).toBe("ten-foot")
		expect(env:get("themeMetrics"):get().metricScale).toBe(1.5)

		local _, near = bareSurface(1600, 900, "Medium")
		expect(near:get("themeMetrics"):get().density).toBe("near")
		expect(near:get("themeMetrics"):get().metricScale).toBe(1)
	end)

	it("…and its metric ladder is scaled, with no theme controller", function()
		local _, env = bareSurface(1920, 1080, "Large")
		local m = env:get("themeMetrics"):get()
		expect(m.targetSizes.minimum).toBe(66)
		expect(m.space.m).toBe(24)
		expect(m.controlSizes.regular.height).toBe(
			snapshot.resolve(snapshot.neutralPackage(), nil, {}).controlSizes.regular.height * 1.5
		)
	end)

	--[[ …AND THE LANE CAP FIRES FROM THE SAME FACT (ADAPT-23, made live). The
		audit's probe 11 numbers: 14 cards, `minColumnWidth = 160`, `gap = 12`, and
		a television getting 10 lanes against a desktop's 9. ]]
	it("…and its grid measures CAPPED lanes, fewer than the same grid at desktop", function()
		local function lanesAt(w: number, h: number, displaySize: string): number
			local core, env = bareSurface(w, h, displaySize)
			local children = {}
			for i = 1, 14 do
				table.insert(
					children,
					UI.Box({
						id = "c" .. i,
						width = { type = "fixed", px = 20 },
						height = { type = "fixed", px = 20 },
					})
				)
			end
			local screen = UI.Screen({
				id = "S",
				children = { UI.Grid({ id = "G", minColumnWidth = 160, gap = 12, children = children }) },
			})
			local root = mountLib.mount(core, screen)
			local adapter = fake_target.new()
			local controller = rendererLib.attach(core, root, env, adapter, {})
			controller.initialRender()
			local firstY = rectOf(adapter, "/S/G/c1").y
			local lanes = 0
			for i = 1, 14 do
				if rectOf(adapter, "/S/G/c" .. i).y == firstY then
					lanes += 1
				end
			end
			return lanes
		end
		local desktop = lanesAt(1600, 900, "Medium")
		local tv = lanesAt(1920, 1080, "Large")
		expect(desktop).toBe(9)
		expect(tv).toBeLessThan(desktop)
		-- the cap the pure predictor names, against the inner extent the overscan
		-- leaves (1920 - 90 - 90)
		expect(tv).toBe(adaptive.columnsFor(1740, 160, 12, { distanceProfile = "ten-foot" }))
	end)

	--[[ ADAPT-L9, the specific missing rung the layout audit measured: spacing
		tokens were byte-identical at every combo, so a television laid out on a
		390 px phone's 16 px gutter while its type was already 1.5x. ]]
	it("…and a metric NAME spent as a gap resolves to the scaled step", function()
		local function gapAt(w: number, h: number, displaySize: string): number
			local core, env = bareSurface(w, h, displaySize)
			local screen = UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "R",
						gap = "m",
						children = {
							UI.Box({
								id = "a",
								width = { type = "fixed", px = 40 },
								height = { type = "fixed", px = 40 },
							}),
							UI.Box({
								id = "b",
								width = { type = "fixed", px = 40 },
								height = { type = "fixed", px = 40 },
							}),
						},
					}),
				},
			})
			local root = mountLib.mount(core, screen)
			local adapter = fake_target.new()
			local controller = rendererLib.attach(core, root, env, adapter, {})
			controller.initialRender()
			return rectOf(adapter, "/S/R/b").x - (rectOf(adapter, "/S/R/a").x + 40)
		end
		expect(gapAt(1600, 900, "Medium")).toBe(16)
		expect(gapAt(1920, 1080, "Large")).toBe(24)
	end)
end)

describe("ten-foot metrics — package authority", function()
	--[[ AUTHORED BEATS DERIVED, the rule `space.gutter` already spends: the
		derived ladder slots in where a package is SILENT, and a package that wants
		a bespoke television ladder declares it and owns it. ]]
	it("a package's own ten-foot declaration wins over the derived scale", function()
		local built = themes.define({
			base = snapshot.neutralPackage(),
			identity = {
				id = "tenfoot-authority",
				displayName = "Ten-Foot Authority",
				version = "1.0.0",
				schemaVersion = themes.SCHEMA,
			},
			metrics = { tenFoot = { ["space.m"] = 40, ["targetSizes.minimum"] = 80 } },
		})
		expect(built).never().toBeNil()
		local near, tenFoot = pair(built)
		expect(near.space.m).toBe(16)
		expect(near.targetSizes.minimum).toBe(44)
		expect(tenFoot.space.m).toBe(40) -- NOT the derived 24
		expect(tenFoot.targetSizes.minimum).toBe(80) -- NOT the derived 66
		-- …and everything it did NOT declare still takes the derived scale
		expect(tenFoot.space.l).toBe(near.space.l * 1.5)
	end)

	it("a ten-foot declaration that names no metric is refused", function()
		local built = themes.define({
			base = snapshot.neutralPackage(),
			identity = {
				id = "tenfoot-typo",
				displayName = "Ten-Foot Typo",
				version = "1.0.0",
				schemaVersion = themes.SCHEMA,
			},
			metrics = { tenFoot = { ["space.enormous"] = 40 } },
		})
		expect(function()
			snapshot.resolve(built, nil, {})
		end).toThrow()
	end)
end)

describe("ten-foot metrics — what does NOT scale", function()
	--[[ THE OVERSCAN COMPOSES, IT DOES NOT DOUBLE. The TV margins are their own
		ten-foot row and they are an ENVIRONMENT fact, not a theme metric — the
		renderer adds them to the safe insets while the display class is Large. If
		the metric ladder ever reached them a television would inset 90 -> 135 px
		and the two rows would multiply. ]]
	it("the overscan margins compose with the safe insets and are not scaled", function()
		local core, env = bareSurface(1920, 1080, "Large")
		local screen = UI.Screen({
			id = "S",
			children = { UI.Box({ id = "b", width = { type = "fill" }, height = { type = "fill" } }) },
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
		controller.initialRender()
		local r = rectOf(adapter, "/S/b")
		-- the console-profile defaults: 60 top/bottom, 90 left/right, ONCE
		expect(r.x).toBe(90)
		expect(r.y).toBe(60)
		expect(r.w).toBe(1920 - 180)
		expect(r.h).toBe(1080 - 120)
		expect(env:get("effectiveOverscanInsets"):get().left).toBe(90)
	end)

	it("durations stay time-true", function()
		local near, tenFoot = pair(snapshot.neutralPackage())
		for key, value in near.motion do
			expect(`motion.{key}={tenFoot.motion[key]}`).toBe(`motion.{key}={value}`)
		end
	end)

	--[[ THE TYPE FLOOR IS APPLIED ONCE, AND NOT HERE. A type size is a length and
		would scale under any "every number" rule — and the renderer's measure seam
		already multiplies it by `typographyPaintScale`, so scaling it here is the
		2.25x double-application defect. `controls.table.cellTextSize` is the trap:
		a TYPE size living inside a CONTROL family. ]]
	it("type sizes are scaled once, by the type floor, never twice", function()
		for _, cfg in configurations() do
			local near, tenFoot = pair(cfg.package)
			for role, entry in near.type do
				expect(`{cfg.name}.{role}.size={tenFoot.type[role].size}`).toBe(`{cfg.name}.{role}.size={entry.size}`)
				expect(`{cfg.name}.{role}.lh={tenFoot.type[role].lineHeight}`).toBe(
					`{cfg.name}.{role}.lh={entry.lineHeight}`
				)
			end
			expect(tenFoot.controls.table.cellTextSize).toBe(near.controls.table.cellTextSize)
			expect(tenFoot.controls.table.sortMarkTextSize).toBe(near.controls.table.sortMarkTextSize)
			-- …while the row that HOLDS the text does scale
			local unit = near.pixelUnit
			local wantHeader = near.controls.table.headerHeight * 1.5
			if type(unit) == "number" then
				wantHeader = themes.snapToPixelUnit(wantHeader, unit)
			end
			expect(tenFoot.controls.table.headerHeight).toBe(wantHeader)
		end
	end)

	it("line counts are counts, not lengths", function()
		local near, tenFoot = pair(snapshot.neutralPackage())
		expect(tenFoot.controls.table.rowLines.pointer).toBe(near.controls.table.rowLines.pointer)
		expect(tenFoot.controls.table.rowLines.touch).toBe(near.controls.table.rowLines.touch)
		expect(tenFoot.controls.table.rowLines.tenFoot).toBe(near.controls.table.rowLines.tenFoot)
	end)

	--[[ VIEWPORT-RELATIVE LAYOUT IS THE VIEWPORT'S, NOT THE THEME'S. A fraction of
		the screen is the same fraction at every distance; scaling it would mean a
		half-width panel covering three quarters of a television. ]]
	it("a percentage width is untouched at ten-foot", function()
		local function halfAt(w: number, displaySize: string): number
			local core, env = bareSurface(w, 1080, displaySize)
			local screen = UI.Screen({
				id = "S",
				children = {
					UI.Box({
						id = "b",
						width = { type = "percent", fraction = 0.5 },
						height = { type = "fixed", px = 40 },
					}),
				},
			})
			local root = mountLib.mount(core, screen)
			local adapter = fake_target.new()
			local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
			controller.initialRender()
			return rectOf(adapter, "/S/b").w
		end
		expect(halfAt(1920, "Medium")).toBe(960)
		expect(halfAt(1920, "Large")).toBe(960)
	end)
end)

describe("ten-foot metrics — the hit floor has one owner", function()
	--[[ 44 -> 66, AND THE EXPANDER SPENDS THE SAME NUMBER. `effectiveHitFloor` is
		already the framework's single reading of the floor — the solve carries it
		so a result can name its interactive rects, and `pushHitRects` spends it as
		real hit geometry. It reads `metrics.targetSizes.minimum`, so the floor
		follows the ladder by construction and there is nothing to keep in sync. ]]
	it("the effective focus-target floor is 66 at ten-foot", function()
		local near, tenFoot = pair(snapshot.neutralPackage())
		expect(layoutNode.effectiveHitFloor("Button", near)).toBe(44)
		expect(layoutNode.effectiveHitFloor("Button", tenFoot)).toBe(66)
		expect(layoutNode.effectiveHitFloor("Box", tenFoot)).toBeNil()
	end)

	it("a sub-floor control's hit rect is expanded to the ten-foot floor", function()
		local core, env = bareSurface(1920, 1080, "Large")
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Button({
					id = "b",
					label = "x",
					width = { type = "fixed", px = 24 },
					height = { type = "fixed", px = 24 },
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local node = adapter.node("/S/b")
		expect(node).never().toBeNil()
		expect(node.hitRect).never().toBeNil()
		expect(node.hitRect.w).toBe(66)
		expect(node.hitRect.h).toBe(66)
	end)
end)

--[[ ═══ INTERPLAY (contract 6) ═══════════════════════════════════════════════
	The three paradigms that landed in the same stage share this wave's fact, and
	each of them decides something with a number the ladder now moves. These are
	the three joins, measured rather than reasoned about. ]]

describe("ten-foot metrics — interplay: the expand plate and its Close", function()
	local worldLib = require("./lib/world")

	local function hudScreen(): any
		return UI.Screen({
			id = "S",
			children = {
				UI.Composition({
					id = "C",
					arrangements = { "column" },
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					groups = { { id = "body", lane = "main", sizing = "fill" } },
					children = {
						UI.Region({
							id = "Clock",
							group = "body",
							rank = 1,
							recover = "overflow",
							children = {
								UI.VStack({
									id = "Full",
									children = {
										UI.Text({ id = "Timer", text = "2:14", textSize = 16 }),
										UI.Text({ id = "Scores", text = "12 - 9", textSize = 16 }),
									},
								}),
								UI.Text({ id = "TimerOnly", text = "2:14", textSize = 16 }),
							},
						}),
					},
				}),
			},
		})
	end

	--[[ THE PLATE IS A PRESENTED SURFACE, so it inherits the ladder like any other
		— and its keyboard Close is a CONTROL, so its focus target is the ten-foot
		floor rather than the near one. The director's reveal feature and the
		director's ten-foot ruling meet exactly here: on a television the plate must
		open, carry the richest form, and be closable from the sofa. ]]
	it("the plate opens at ten-foot and its Close is a 66px focus target", function()
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 1920, h = 46 },
			displaySize = "Large",
		})
		w.present(hudScreen(), { initialFocus = "none" })
		expect(w.env:get("themeMetrics"):get().metricScale).toBe(1.5)
		-- the region stepped down, so there is something to expand to
		expect(w.controller.compositionAt("/S/C").regions[1].activeForm).toBe(2)
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		-- the richest form travelled to the plate, by identity
		expect(w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel/Full/Scores")).never().toBeNil()
		-- ...and the keyboard Close is there, at the DISTANCE floor
		local close = w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandClose")
		expect(close).never().toBeNil()
		expect(math.max(close.rect.h, if close.hitRect ~= nil then close.hitRect.h else 0)).toBeGreaterThanOrEqual(66)
	end)
end)

describe("ten-foot metrics — interplay: the table's collapse at distance", function()
	local table_control = require("../src/controls/table")

	local function tableWorld(displaySize: string, w: number, h: number): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("displaySize", displaySize)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local rows = {}
		for i = 1, 3 do
			table.insert(rows, { id = `r{i}`, name = `Racer {i}`, laps = i })
		end
		local tbl = table_control.build(Facet, core, {
			id = "T",
			rows = core:signal(rows),
			key = function(r: any)
				return r.id
			end,
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 200,
					value = function(r: any)
						return r.name
					end,
				},
				{
					id = "artist",
					title = "Artist",
					width = { type = "fill", weight = 1 },
					minWidth = 160,
					value = function(r: any)
						return `Artist {r.laps}`
					end,
				},
				{
					id = "rating",
					title = "Rating",
					width = { type = "fixed", px = 96 },
					value = function(r: any)
						return tostring(r.laps)
					end,
				},
			},
			env = env,
		})
		pres.present(UI.Screen({ id = "S", children = { tbl.blueprint } }))
		for _ = 1, 6 do
			pres.refresh()
		end
		return { env = env, adapter = adapter, pres = pres, tbl = tbl }
	end

	--[[ THE ROW TAKES THE DISTANCE RUNG, AND THE RUNG IS SCALED. `rowHeight.tenFoot`
		is derived in `snapshot.resolve` from `controlSizes.large.height` — the box
		of a control you operate from a sofa — and the ladder moves that rung with
		everything else, so the row a television gets is 1.5x the near answer for the
		same reason its label is. ]]
	it("a ten-foot table takes the scaled distance rung for its rows", function()
		local near = tableWorld("Medium", 900, 500)
		local tv = tableWorld("Large", 1920, 1080)
		local nearRow = near.adapter.node("/S/T/Main/Body/Rows/[r1@0]/Row").rect.h
		local tvRow = tv.adapter.node("/S/T/Main/Body/Rows/[r1@0]/Row").rect.h
		expect(tvRow).toBeGreaterThan(nearRow)
		local tvMetrics = tv.env:get("themeMetrics"):get()
		expect(tvRow).toBeGreaterThanOrEqual(tvMetrics.controlSizes.large.height)
		expect(tvMetrics.controlSizes.large.height).toBe(
			near.env:get("themeMetrics"):get().controlSizes.large.height * 1.5
		)
	end)

	--[[ …AND THE COLLAPSE LADDER STILL FIRES, WITH NO DEAD END. The column floors
		are AUTHORED literals — a declared `minWidth` is the author's word about
		their own content and this wave does not move it — so the interesting claim
		is the join: at distance the rows are taller, the header is taller, and the
		priority-collapse rule still removes the lowest-priority column and still
		says so through its disclosure rather than clipping. ]]
	it("…and the priority-collapse ladder still fires at distance, and discloses", function()
		local wide = tableWorld("Large", 1920, 1080)
		expect(wide.tbl.dump().hiddenColumns).toEqual({})
		--[[ 420 px of console glass: the ladder removes the two lowest-priority
			columns IN ORDER and never the first one, exactly as it does at near — the
			collapse rule reads declared floors and priorities, which this wave does
			not move, so the paradigm is unchanged and only the box it runs in grew. ]]
		local narrow = tableWorld("Large", 420, 1080)
		expect(narrow.tbl.dump().hiddenColumns).toEqual({ "artist", "rating" })
		expect(narrow.tbl.dump().hiddenColumns[1]).never().toBe("name")
		-- the collapsed columns are HIDDEN, not merely narrow — no dead band
		expect(narrow.adapter.node("/S/T/Main/Header/Head-rating").rect.w).toBe(0)
		expect(narrow.adapter.node("/S/T/Main/Header/Head-artist").rect.w).toBe(0)
		-- ...and the disclosure exists, so nothing is unreachable
		expect(narrow.adapter.node("/S/T/Main/MoreWhen/then/MoreBar/MoreChip")).never().toBeNil()
	end)
end)

describe("ten-foot metrics — interplay: carousel snap with scaled cards", function()
	local card_rail = require("../src/controls/card_rail")
	local scroll_snap = require("../src/controls/scroll_snap")
	local virtual_extents = require("../src/virtual_extents")

	local function railExtent(displaySize: string): number
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1200, h = 400 })
		env:set("displaySize", displaySize)
		local metrics: any = env:get("themeMetrics"):get()
		local rail = card_rail.new({
			control = "newVirtualList",
			options = { perView = 3, peek = 0 },
			interactionClasses = env:get("interactionClasses"),
			distanceProfile = env:get("distanceProfile"),
			viewportIn = function()
				return 1200
			end,
			viewportNow = function()
				return 1200
			end,
			-- the rail's gutter is a THEME step (`space.s`), which is exactly the
			-- kind of number this wave moves
			gapIn = function()
				return metrics.space.s
			end,
			gapNow = function()
				return metrics.space.s
			end,
		})
		return rail.extent(nil)
	end

	--[[ A CARD IS SIZED BY THE RAIL AND ITS GUTTER, and the gutter is a theme step.
		So a television's cards are not the same cards: the same three-up rail in the
		same 1200px gives a narrower card, because the gaps between them grew with
		the ladder. That is the ladder reaching the carousel. ]]
	it("the scaled gutter changes the card's own extent", function()
		local near = railExtent("Medium")
		local tv = railExtent("Large")
		expect(near).toBeGreaterThan(tv)
		-- three cards and two gutters fill the rail at both distances (the card is
		-- floored onto a whole pixel, so up to one pixel per lane goes unspent)
		expect(near * 3 + 8 * 2).toBeLessThanOrEqual(1200)
		expect(near * 3 + 8 * 2).toBeGreaterThan(1200 - 3)
		expect(tv * 3 + 12 * 2).toBeLessThanOrEqual(1200)
		expect(tv * 3 + 12 * 2).toBeGreaterThan(1200 - 3)
	end)

	--[[ …AND THE SETTLE STILL LANDS ON A CARD EDGE. Snap and arrangement read ONE
		extents index, so a scaled card is still a whole card to the snap machine —
		which is the property that would break first if the two ever derived the
		gutter separately. ]]
	it("a fling settles exactly on a card boundary at the scaled extents", function()
		local extent = railExtent("Large")
		local gap = 12 -- space.s at ten-foot
		local ix = virtual_extents.uniform(12, extent, gap)
		local pitch = extent + gap
		for _, drift in { 0.1, 0.35, 0.6, 0.9 } do
			local landed = scroll_snap.resolve({
				index = ix,
				viewport = 1200,
				offset = pitch * (3 + drift),
				origin = 0,
				peak = 0,
			})
			expect(landed).never().toBeNil()
			expect((landed :: number) % pitch).toBeCloseTo(0, 1e-6)
		end
	end)
end)

describe("ten-foot metrics — the transform is total", function()
	it("the near path is the identity — the same table, not a copy", function()
		for _, cfg in configurations() do
			local base = snapshot.resolve(cfg.package, nil, {})
			expect(rawequal(snapshot.forDisplay(base, "Medium"), base)).toBeTruthy()
			expect(rawequal(snapshot.forDisplay(base, "Small"), base)).toBeTruthy()
			expect(rawequal(snapshot.forDisplay(base, nil), base)).toBeTruthy()
		end
	end)

	--[[ APPLIED FROM THE BASE, ALWAYS — never composed onto an already-scaled
		snapshot. That is what makes a display-class change reversible without
		drift: the theme controller reads the fact, holds it and writes it back on
		uninstall, and a package's own pixel grid means a ratio-composed transform
		would land somewhere else on the way home. ]]
	it("is idempotent and reversible", function()
		for _, cfg in configurations() do
			local base = snapshot.resolve(cfg.package, nil, {})
			local tenFoot = snapshot.forDisplay(base, "Large")
			expect(rawequal(snapshot.forDisplay(tenFoot, "Large"), tenFoot)).toBeTruthy()
			expect(rawequal(snapshot.forDisplay(tenFoot, "Medium"), base)).toBeTruthy()
			expect(rawequal(snapshot.baseOf(tenFoot), base)).toBeTruthy()
			expect(rawequal(snapshot.baseOf(base), base)).toBeTruthy()
		end
	end)

	--[[ THE COMPLETENESS RULE. A numeric metric nobody classified does not scale,
		silently — which is how a ladder ends up with one rung missing on a
		television and no test to say so. Unclassified is EXEMPT at runtime (the
		safe direction: a new duration must never be multiplied) and a FAILURE
		here, so the gap is loud exactly once, in the suite, at the commit that
		introduces it. ]]
	it("every numeric leaf of every configuration is classified", function()
		local unclassified: { string } = {}
		for _, cfg in configurations() do
			local base = snapshot.resolve(cfg.package, nil, {})
			for path in leavesOf(base) do
				if snapshot.densityClassOf(path) == nil then
					table.insert(unclassified, `{cfg.name}:{path}`)
				end
			end
		end
		table.sort(unclassified)
		expect(table.concat(unclassified, ", ")).toBe("")
	end)

	--[[ …AND IT NEVER THROWS. This function runs inside the environment's memo, so
		an error in it does not surface as an error: the key reads `nil` and every
		seam that reads `themeMetrics` silently takes its neutral fallback — a
		mounted surface going deaf, which is the §8.2 failure this framework guards
		at every fact seam. Found while writing this wave: the slot-inset composite
		step indexed `insets` unconditionally and a hand-built metrics table (which
		`tests/geometry_solve_coalescing.spec` sets on purpose) made the whole key
		nil. ]]
	it("a garbage metrics fact is passed through, never thrown on", function()
		local _, env = bareSurface(1920, 1080, "Large")
		for _, garbage in { { nested = { a = 1 }, density = 1 }, { insets = 7 }, {}, { targetSizes = "no" } } do
			env:set("themeMetrics", garbage)
			local read = env:get("themeMetrics"):get()
			expect(type(read)).toBe("table")
			expect(read.density).toBe("ten-foot")
		end
	end)

	it("the environment publishes exactly one distance-adapted metric authority", function()
		local _, env = bareSurface(1920, 1080, "Large")
		local seen: { [string]: number } = {}
		for _, key in env:keys() do
			seen[key] = (seen[key] or 0) + 1
		end
		expect(seen.themeMetrics).toBe(1)
		-- what is SET is the authored base; what is READ is the distance-adapted
		-- form, and the round trip is exact
		local authored = snapshot.resolve(packageNamed("classic_desktop"), nil, {})
		env:set("themeMetrics", authored)
		expect(env:get("themeMetrics"):get().space.m).toBe(authored.space.m * 1.5)
		expect(rawequal(snapshot.baseOf(env:get("themeMetrics"):get()), authored)).toBeTruthy()
		env:set("displaySize", "Medium")
		expect(rawequal(env:get("themeMetrics"):get(), authored)).toBeTruthy()
	end)
end)
