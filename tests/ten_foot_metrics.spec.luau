--!strict
--[[ TEN-FOOT METRICS — THE WHOLE LADDER SCALES, BY THE TYPE'S OWN FACTOR.

	THE DIRECTOR'S RULING (2026-08-20, ADAPT-8). The framework's ten-foot policy
	was four rows — the 1.5x TYPE floor, the sizeClass density cap, the focus
	strengthening and the overscan margins — and metric spacing was never one of
	them, so control heights, paddings, icon sizes and the 44 px hit floor on a
	television were byte-identical to a phone's. The audit recorded that as a
	SCOPE question rather than a defect (`adapt-audit/matrix.md` ADAPT-8) and put
	it to the director, who ruled AGAINST type-only: on ten-foot the whole metric
	ladder scales with the type, ten-foot style.

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
local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style") :: any
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
		acceptance exists to make impossible.

		WHAT THIS ASSERTS, SAID EXACTLY (fix round 1, review §3). It is VALUE
		AGREEMENT over the WHOLE DOMAIN of the fact, not function identity — and it
		cannot be function identity, because the two names are deliberately two
		functions: `metricScale` and `typographyPaintScale` are different DECISIONS
		that happen to share a factor, and a caller reading the type seam's answer to
		size a button would be spending the wrong one. `rawequal` on the two values is
		therefore false by design.

		The strength comes from EXHAUSTION instead. `displaySize` is a closed engine
		fact (`GuiService.ViewportDisplaySize` — Small | Medium | Large), so the three
		legal values plus absence plus garbage IS the entire domain, and the loop below
		covers all of it rather than sampling it. A one-sided drift is caught wherever
		it could occur.

		The reviewer measured the residual honestly and it stands: giving `metricScale`
		its own `1.5` literal keeps this green, because at that instant the two still
		agree. What that mutation breaks is the FUTURE, and the compound mutation
		proves the future is guarded — tune `tenFootFloor` to 1.6 while `metricScale`
		holds its own literal and this case goes red along with the proportion sweep,
		which is the divergence the design exists to prevent. ]]
	it("the metric factor agrees with the type floor's factor on every display class", function()
		-- the closed domain of the fact, plus the two shapes a broken adapter can push
		local DOMAIN = { "Small", "Medium", "Large", nil :: any, 42 :: any, "Enormous" :: any }
		local checked = 0
		for i = 1, 6 do
			local value = DOMAIN[i]
			expect(`ds={tostring(value)} metric={snapshot.metricScale(value)}`).toBe(
				`ds={tostring(value)} metric={snapshot.typographyPaintScale(value)}`
			)
			checked += 1
		end
		expect(`checked:{checked}`).toBe("checked:6")
		-- ...and the factor itself is the director's 1.5, on the one class that earns it
		expect(snapshot.metricScale("Large")).toBe(1.5)
		expect(snapshot.metricScale("Medium")).toBe(1)
		expect(snapshot.metricScale(nil)).toBe(1)
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
				if class ~= "scale" and class ~= "scaleDown" and class ~= "scaleWhole" then
					continue
				end
				local want = nearValue * 1.5

				if type(unit) == "number" then
					want = if class == "scaleDown"
						then math.max(unit, math.floor(want / unit) * unit)
						else themes.snapToPixelUnit(want, unit)
				elseif class == "scaleWhole" then
					-- a whole-pixel class lands on a whole pixel off the grid too
					want = math.round(want)
				end
				expect(`{cfg.name}:{path}={tenLeaves[path]}`).toBe(`{cfg.name}:{path}={want}`)
				checked += 1
			end
		end
		--[[ A SWEEP THAT SWEPT NOTHING PASSES VACUOUSLY, and the floor is RE-PINNED
			AGAIN (paint-family lockstep, director ruling 2026-08-21): `radii.*` and
			`strokes.*` came BACK into the scaled class — 38 leaves, true count 641 —
			so the floor moves up WITH them instead of staying where a whole family
			could quietly leave it. 630 is above the 603 this sweep counted while the
			paint family was exempt, so the exemption coming back cannot pass here. ]]
		expect(`checked:{checked > 630}`).toBe("checked:true")
	end)

	--[[ …AND THE PAINT FAMILY MOVES WITH THEM, in lockstep (DIRECTOR RULING,
		2026-08-21, on the live A/B capture: TV corner rounding scales by the SAME
		factor as everything else and stays DERIVED from it).

		THIS ARM RE-VERDICTS. It used to assert the opposite — "a radius and a
		stroke are painted by another authority, so they do not scale" — and the
		doctrine behind that sentence is untouched: A METRIC MAY ONLY SCALE WHERE
		THE FRAMEWORK OWNS THE PAINT. What changed is that the framework now takes
		the paint: `snapshot.paintForDisplay` is the one derivation, and both
		authorities call it — the sheet builder for the literal it bakes into
		`::UICorner`/`::UIStroke`, and the render target for `ctx.style`. The
		12-measured-against-18-painted disagreement the old arm was written to
		close is closed by AGREEMENT now instead of by exemption, and the arm that
		proves it is "the painted number and the measured number are ONE
		derivation" below.

		TWO CLASSES, because the two engine properties are different types:
		`UICorner.CornerRadius` is a `UDim`, whose Offset is an INTEGER, so a
		radius scales to a WHOLE pixel (`scaleWhole`) — handing the engine 10.5
		would be a number nobody measured, the same defect one step smaller.
		`UIStroke.Thickness` is a float, so a hairline scales exactly: 1 -> 1.5. ]]
	it("a radius and a stroke are the PAINT family, and they scale in lockstep", function()
		local checked = 0
		for _, cfg in configurations() do
			local near, tenFoot = pair(cfg.package)
			local unit = near.pixelUnit
			for _, section in { "radii", "strokes" } do
				for key, value in (near :: any)[section] do
					local want = value * 1.5
					if type(unit) == "number" then
						want = themes.snapToPixelUnit(want, unit)
					elseif section == "radii" then
						want = math.round(want)
					end
					expect(`{cfg.name}.{section}.{key}={(tenFoot :: any)[section][key]}`).toBe(
						`{cfg.name}.{section}.{key}={want}`
					)
					expect(snapshot.densityClassOf(`{section}.{key}`)).toBe(
						if section == "radii" then "scaleWhole" else "scale"
					)
					checked += 1
				end
			end
		end
		expect(`checked:{checked}`).toBe("checked:38")
		-- …and the numbers the director actually looked at, said out loud
		local nearNeutral, tvNeutral = pair(snapshot.neutralPackage())
		expect(`{nearNeutral.radii.panel}/{nearNeutral.radii.control}/{nearNeutral.strokes.hairline}`).toBe("12/8/1")
		expect(`{tvNeutral.radii.panel}/{tvNeutral.radii.control}/{tvNeutral.strokes.hairline}`).toBe("18/12/1.5")
	end)

	--[[ DERIVED, NEVER LITERAL. The ruling's second half is that a FUTURE scale
		tweak moves the paint family with it and with zero further edits, so this
		arm resolves at a scale that is NOT 1.5 and asserts the lockstep there.

		It drives the factor at its source — `snapshot.metricScale`, the one
		function `forDisplay` and `paintForDisplay` both read — rather than
		mutating a value after the fact, which is what makes it a test of the
		DERIVATION rather than of an arithmetic. A `radii.panel = 12 * factor`
		written anywhere would pass at 1.5 and fail here. ]]
	it("a future scale tweak moves the whole family, measure and paint together", function()
		local realScale = snapshot.metricScale
		local checked = 0
		local ok, err = pcall(function()
			for _, factor in { 2, 1.25, 3 } do
				snapshot.metricScale = function(displaySize: any): number
					return if displaySize == "Large" then factor else 1
				end
				for _, cfg in configurations() do
					local near, tenFoot = pair(cfg.package)
					local unit = near.pixelUnit
					local paint = snapshot.paintForDisplay(cfg.package.metrics, "Large", unit)
					for key, value in near.radii do
						local want = if type(unit) == "number"
							then themes.snapToPixelUnit(value * factor, unit)
							else math.round(value * factor)
						expect(`{cfg.name}@{factor} radii.{key}={tenFoot.radii[key]}`).toBe(
							`{cfg.name}@{factor} radii.{key}={want}`
						)
						-- the PAINT side, from the same one factor
						expect(`{cfg.name}@{factor} paint.{key}={paint.radii[key]}`).toBe(
							`{cfg.name}@{factor} paint.{key}={want}`
						)
						checked += 1
					end
					for key, value in near.strokes do
						local want = if type(unit) == "number"
							then themes.snapToPixelUnit(value * factor, unit)
							else value * factor
						expect(`{cfg.name}@{factor} strokes.{key}={tenFoot.strokes[key]}`).toBe(
							`{cfg.name}@{factor} strokes.{key}={want}`
						)
						expect(`{cfg.name}@{factor} paint.{key}={paint.strokes[key]}`).toBe(
							`{cfg.name}@{factor} paint.{key}={want}`
						)
						checked += 1
					end
					-- …and the ladder it is in lockstep WITH moved by the same factor
					expect(`{cfg.name}@{factor} space.m={tenFoot.space.m}`).toBe(
						`{cfg.name}@{factor} space.m={if type(unit) == "number"
							then themes.snapToPixelUnit(near.space.m * factor, unit)
							else near.space.m * factor}`
					)
				end
			end
		end)
		snapshot.metricScale = realScale
		expect(if ok then "ok" else `threw: {tostring(err)}`).toBe("ok")
		expect(`checked:{checked}`).toBe("checked:114")
		-- the stub is gone: the shipped factor is back
		expect(snapshot.metricScale("Large")).toBe(1.5)
	end)

	--[[ THE WHOLE-PIXEL RULE, on the one shape no shipped package produces.
		Every authored radius in the nine configurations happens to scale to an
		integer at 1.5, so the rounding rule would be untested by the sweep alone —
		this arm authors the half-pixel case deliberately. ]]
	it("a scaled radius lands on a whole pixel, because a UDim offset is an integer", function()
		local base = snapshot.resolve(snapshot.neutralPackage(), nil, {}, { ["radii.panel"] = 7 })
		local tv = snapshot.forDisplay(base, "Large")
		expect(`7 * 1.5 = {tv.radii.panel}`).toBe("7 * 1.5 = 11")
		-- …and the paint authority rounds it the same way, from the same rule
		local paint = snapshot.paintForDisplay({ radii = { panel = 7 }, strokes = { hairline = 1 } }, "Large")
		expect(`paint {paint.radii.panel}`).toBe("paint 11")
		-- a STROKE is a float property and keeps its fraction: 1 -> 1.5, not 2
		expect(`hairline {paint.strokes.hairline}`).toBe("hairline 1.5")
	end)

	--[[ THE CAPSULE SENTINEL, decided rather than special-cased (`radii.pill =
		999` in Studio Neutral and in five of the eight packages).

		THE DECISION: IT SCALES LIKE EVERY OTHER RADIUS. A sentinel scaled is still
		a sentinel, and exempting it would mean a threshold constant — a second
		place to maintain, and a number nobody can derive — for a value the engine
		never paints as written anyway. `UICorner` clamps `CornerRadius` to half
		the box's SHORTER side, so 999 and 1499 are the same pixel on every box a
		ten-foot surface can present: the identity holds for every box up to 1998 px
		on its shorter side, which is every element on a 1080p or 1440p television
		(the bound is stated rather than hidden — a box shorter-side taller than
		1998 px would paint 999 and 1499 differently, and nothing in this framework
		draws a pill that large).

		This arm re-verdicts the live-Studio row that read "authored capsule radius
		passes through unscaled (999, not 1498)": the capsule now reads 1499, and
		what makes that safe is the clamp, measured below rather than asserted. ]]
	it("the capsule sentinel scales too, and the engine's clamp makes it the same pixel", function()
		local near, tv = pair(snapshot.neutralPackage())
		expect(`{near.radii.pill} -> {tv.radii.pill}`).toBe("999 -> 1499")
		-- the clamp, over every box a ten-foot surface can present
		local sizes = { 1, 2, 8, 44, 66, 120, 400, 1080, 1440, 1998 }
		local checked = 0
		for _, side in sizes do
			local painted = math.min(near.radii.pill, side / 2)
			local paintedTv = math.min(tv.radii.pill, side / 2)
			expect(`box {side}: {painted} vs {paintedTv}`).toBe(`box {side}: {painted} vs {painted}`)
			checked += 1
		end
		expect(`checked:{checked}`).toBe("checked:10")
	end)

	--[[ THE LOCKSTEP ITSELF, mechanised across every shipped package: what the
		framework MEASURES and what it PAINTS are one derivation, not two that
		agree today. `forDisplay` is the measure authority (the environment's
		`themeMetrics` memo) and `paintForDisplay` is the paint one (the sheet
		builder's literal and `ctx.style`), and this arm compares their answers
		leaf by leaf — including the pixel-package grid, where the two used to
		disagree by construction because the sheet read the package's UNSNAPPED
		authored number. ]]
	it("the painted number and the measured number are ONE derivation, on every package", function()
		local checked = 0
		for _, cfg in configurations() do
			local base = snapshot.resolve(cfg.package, nil, {})
			local unit = base.pixelUnit
			for _, displaySize in { "Medium", "Large" } do
				local measured = snapshot.forDisplay(base, displaySize)
				local painted = snapshot.paintForDisplay(cfg.package.metrics, displaySize, unit)
				for _, section in { "radii", "strokes" } do
					for key in (measured :: any)[section] do
						expect(`{cfg.name}@{displaySize} {section}.{key} paint={(painted :: any)[section][key]}`).toBe(
							`{cfg.name}@{displaySize} {section}.{key} paint={(measured :: any)[section][key]}`
						)
						checked += 1
					end
				end
			end
		end
		expect(`checked:{checked}`).toBe("checked:76")
		--[[ …INCLUDING THE CASE NO SHIPPED PACKAGE PRODUCES. Every reference
			package authors radii already on its own grid, so the resolver's snap
			would be invisible here: this pixel package authors a radius BETWEEN two
			grid lines, which is where a paint authority reading the unsnapped
			authored number drifts from the measure (5 -> snap 8 -> 12, not
			5 * 1.5 = 7.5 -> snap 8). ]]
		local offGrid = themes.define({
			base = packageNamed("pixel_quest"),
			identity = {
				id = "offgrid-pixel",
				displayName = "Off-Grid Pixel",
				version = "1.0.0",
				schemaVersion = themes.SCHEMA,
				rendering = "pixel",
				pixelUnit = 4,
			},
			metrics = { radii = { control = 5, panel = 10, pill = 999 }, strokes = { hairline = 5 } },
		})
		expect(offGrid).never().toBeNil()
		local unit = snapshot.resolve(offGrid, nil, {}).pixelUnit
		local measured = snapshot.forDisplay(snapshot.resolve(offGrid, nil, {}), "Large")
		local painted = snapshot.paintForDisplay(offGrid.metrics, "Large", unit)
		expect(`off-grid unit={unit} radii.control paint={painted.radii.control}`).toBe(
			`off-grid unit=4 radii.control paint={measured.radii.control}`
		)
		expect(`off-grid radii.panel paint={painted.radii.panel}`).toBe(
			`off-grid radii.panel paint={measured.radii.panel}`
		)
		expect(`off-grid strokes.hairline paint={painted.strokes.hairline}`).toBe(
			`off-grid strokes.hairline paint={measured.strokes.hairline}`
		)
		-- and the numbers themselves, so a "both nil" pass is impossible
		-- 5 -> grid 8 -> 12, 10 -> grid 12 -> 18 -> grid 20, 5 -> grid 8 -> 12
		expect(`{measured.radii.control}/{measured.radii.panel}/{measured.strokes.hairline}`).toBe("12/20/12")
	end)

	--[[ AUTHORED WINS, ON BOTH SIDES. A package may declare ABSOLUTE ten-foot
		pixels (`metrics.tenFoot`), and until this round that channel could name
		`radii.panel` with nothing to stop it — which moved the MEASURE and left
		the PAINT on the authored literal, the very defect the exemption existed to
		prevent. Now the paint authority reads the same declaration, so a package
		that wants a bespoke television corner gets one and is never double-scaled:
		20 means 20, not 20 * 1.5 and not 12 * 1.5. ]]
	it("a package's own ten-foot radius declaration wins for the paint too, and is not double-scaled", function()
		local built = themes.define({
			base = snapshot.neutralPackage(),
			identity = {
				id = "tenfoot-paint-authority",
				displayName = "Ten-Foot Paint Authority",
				version = "1.0.0",
				schemaVersion = themes.SCHEMA,
			},
			metrics = { tenFoot = { ["radii.panel"] = 20, ["strokes.hairline"] = 3 } },
		})
		expect(built).never().toBeNil()
		local base = snapshot.resolve(built, nil, {})
		local tv = snapshot.forDisplay(base, "Large")
		local paint = snapshot.paintForDisplay(built.metrics, "Large")
		expect(`measured {tv.radii.panel}/{tv.strokes.hairline}`).toBe("measured 20/3")
		expect(`painted {paint.radii.panel}/{paint.strokes.hairline}`).toBe("painted 20/3")
		-- the family the declaration did NOT name still takes the derived scale
		expect(`{tv.radii.control} {paint.radii.control}`).toBe("12 12")
	end)

	--[[ NEAR IS THE IDENTITY, and this is what keeps every phone, tablet and
		desktop byte-identical through a change to the paint family: the near call
		returns the SAME TABLE, so the built-in-sheet identity check in
		`screen_target` (`style == defaultStyle`, which decides whether the Light
		theme ships) still holds, and no near-density token moves. ]]
	it("the near paint derivation is the identity — the same table, not a copy", function()
		local style = require("../src/tokens/default_style") :: any
		expect(rawequal(snapshot.paintForDisplay(style, "Medium"), style)).toBe(true)
		expect(rawequal(snapshot.paintForDisplay(style, "Small"), style)).toBe(true)
		expect(rawequal(snapshot.paintForDisplay(style, nil), style)).toBe(true)
		expect(rawequal(snapshot.paintForDisplay(style, "Large"), style)).toBe(false)
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
			"space.tight",
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
		expect(w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandPlate/Full/Scores")).never().toBeNil()
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
		--[[ EVERY CASE CARRIES A MARKER, AND THE MARKER IS THE ASSERTION (fix round 1,
			review NEW-3). The first cut of this case pushed four garbage tables through
			ONE environment and asserted only `type(read) == "table"` and
			`read.density == "ten-foot"` — which is exactly what a STALE read satisfies.
			The reviewer reverted the §8.2 type guard, measured the memo throwing, saw
			the surface read back the FIRST case's output forever, and the whole suite
			stayed green: the wave's own headline defect, guarded by a case that could
			not see it.

			A stale read is indistinguishable from a fresh one when you only assert the
			shape, so each case now carries a value nothing else in the loop has and the
			assertion is that THAT value came back. A fresh environment per case would
			work too; the marker is cheaper and it also proves the memo re-derived
			rather than merely not-crashing. ]]
		local CASES = {
			{ marker = "nested-table-and-a-numeric-density", nested = { a = 1 }, density = 1 },
			{ marker = "insets-is-a-number", insets = 7 },
			{ marker = "empty" },
			{ marker = "targetSizes-is-a-string", targetSizes = "no" },
			{ marker = "chromeInsets-is-a-string", insets = { panel = { top = 4 } }, chromeInsets = "no" },
			{ marker = "insets-slot-is-a-number", insets = { panel = 3 } },
			{ marker = "inset-side-is-a-string", insets = { panel = { top = "x" } }, chromeInsets = {} },
		}
		local _, env = bareSurface(1920, 1080, "Large")
		for _, garbage in CASES do
			env:set("themeMetrics", garbage)
			local read = env:get("themeMetrics"):get()
			expect(type(read)).toBe("table")
			-- THE FRESHNESS ASSERTION: a memo that threw on this value would leave the
			-- previous case's output standing, and this is what says so
			expect(`{garbage.marker} -> {tostring((read :: any).marker)}`).toBe(`{garbage.marker} -> {garbage.marker}`)
			expect(read.density).toBe("ten-foot")
		end
	end)

	--[[ A DERIVATIVE OF A DISTANCE-ADAPTED READ IS NOT A BASE, AND THE WRITE SAYS SO
		(fix round 1, review NEW-2 / Residual A).

		`baseOf` recovers the authored ladder from a weak-keyed IDENTITY map, so it
		answers for the exact table `forDisplay` produced and for nothing else. A
		caller that reads the metric authority, COPIES it, and writes the copy back
		therefore handed the transform its own output: the reviewer measured
		`targetSizes.minimum` 44 -> 66 -> **99** and `space.m` 16 -> 24 -> **36**.

		The information to catch it was already on the table and unread: an adapted
		snapshot carries `metricScale ~= 1`. So the write recovers the base when it
		can and REFUSES when it cannot — the fact keeps its last real value and warns
		once, exactly as the viewport refusal above it does, because there is no third
		answer the framework can compute: writing it as a base double-applies, and
		un-scaling it by division is lossy on any package with a pixel grid.

		THE REFUSAL IS ALSO WHAT MAKES THE RECOVERY LOAD-BEARING. Deleting the
		`baseOf` line now reddens the round-trip case below rather than being
		invisible: a legitimate exact round trip would fall through to the refusal. ]]
	it("a derivative of a distance-adapted read is refused, never applied twice", function()
		local _, env = bareSurface(1920, 1080, "Large")
		local authored = snapshot.resolve(snapshot.neutralPackage(), nil, {})
		env:set("themeMetrics", authored)
		local read1 = env:get("themeMetrics"):get()
		expect(read1.targetSizes.minimum).toBe(66)
		expect(read1.space.m).toBe(24)

		-- a shallow clone: the same numbers, none of the identity
		local copy: any = {}
		for k, v in read1 do
			copy[k] = v
		end
		expect(rawequal(snapshot.baseOf(copy), copy)).toBeTruthy() -- the link IS gone
		env:set("themeMetrics", copy)

		local read2 = env:get("themeMetrics"):get()
		expect(read2.targetSizes.minimum).toBe(66) -- NOT 99
		expect(read2.space.m).toBe(24) -- NOT 36
		expect(read2.metricScale).toBe(1.5)
		-- the fact kept its last real value, so the authored ladder is still there
		env:set("displaySize", "Medium")
		expect(rawequal(env:get("themeMetrics"):get(), authored)).toBeTruthy()
	end)

	--[[ …AND A SNAPSHOT NOBODY ADAPTED IS STILL WRITABLE. The refusal keys on the
		one fact only `forDisplay` writes (`metricScale ~= 1`), so an authored ladder,
		a hand-built table and a garbage fact all pass through it untouched — the
		refusal must not become a general gate on the metric fact. ]]
	it("…and the refusal keys on the adapted shape alone", function()
		local authored = snapshot.resolve(packageNamed("classic_desktop"), nil, {})
		local _, env = bareSurface(1600, 900, "Medium")
		-- an authored ladder at a near display is the IDENTITY, refusal or no refusal
		env:set("themeMetrics", authored)
		expect(rawequal(env:get("themeMetrics"):get(), authored)).toBeTruthy()
		-- ...and a table nobody adapted still lands, whatever else is wrong with it
		for _, value in
			{
				{ marker = "hand-built", space = { m = 3 } } :: any,
				{ marker = "claims-a-neutral-scale", metricScale = 1, space = { m = 5 } } :: any,
			}
		do
			env:set("themeMetrics", value)
			local read = env:get("themeMetrics"):get()
			expect(`{value.marker} -> {tostring(read.marker)}`).toBe(`{value.marker} -> {value.marker}`)
			-- it reached the read UNSCALED: the refusal is not a general gate
			expect(read.space.m).toBe(value.space.m)
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

	--[[ THE PRODUCTION ROUND TRIP, AND THE ONE SHAPE THAT MAKES THE WRITE-SIDE
		RECOVERY LOAD-BEARING (fix round 1).

		`theme_controller` reads the pre-install snapshot, holds it across an install
		that commits a DIFFERENT package, and writes it back on uninstall. That is the
		only shape in which recovering the base and refusing an adapted write DIVERGE:
		refusing keeps whatever the fact holds now (package B), recovering restores
		what the caller actually asked for (package A). Every simpler round trip
		converges on the same value, which is precisely why the reviewer could delete
		the recovery line and watch both suites stay green. ]]
	it("a read held across a theme swap restores ITS package, not the incumbent", function()
		local _, env = bareSurface(1920, 1080, "Large")
		local packageA = snapshot.resolve(packageNamed("classic_desktop"), nil, {})
		local packageB = snapshot.resolve(packageNamed("glossy_touch"), nil, {})
		expect(packageA.space.m).never().toBe(packageB.space.m)

		env:set("themeMetrics", packageA)
		local heldFromA = env:get("themeMetrics"):get() -- the ADAPTED form, as a reader gets it
		expect(heldFromA.metricScale).toBe(1.5)

		env:set("themeMetrics", packageB)
		expect(env:get("themeMetrics"):get().space.m).toBe(packageB.space.m * 1.5)

		-- uninstall: write the held value back. It is adapted, and its base must win
		env:set("themeMetrics", heldFromA)
		expect(env:get("themeMetrics"):get().space.m).toBe(packageA.space.m * 1.5)
		env:set("displaySize", "Medium")
		expect(rawequal(env:get("themeMetrics"):get(), packageA)).toBeTruthy()
	end)
end)

--[[ THE PAINT HALF OF THE LOCKSTEP. Everything above measures; this asserts that
	what the engine will DRAW carries the same number, on both paint paths — the
	native StyleSheet (the default since the 2026-08-21 flip) and the bespoke
	`ctx.style` writes the fallback path makes. The old exemption existed exactly
	because these two authorities could not agree; these are the arms that make
	the agreement checkable instead of claimed. ]]
describe("ten-foot metrics — the paint family reaches the paint", function()
	-- every rule prop of a sheet model, flattened to comparable lines
	local function propLines(model: any): { string }
		local out: { string } = {}
		for _, rule in model.rules do
			local keys: { string } = {}
			for prop in rule.props do
				table.insert(keys, prop)
			end
			table.sort(keys)
			for _, prop in keys do
				local v: any = rule.props[prop]
				local shown = if type(v) == "table"
					then (if v.kind == "udim"
						then `udim({v.scale},{v.offset})`
						else (if v.kind == "number" then tostring(v.value) else tostring(v.kind)))
					else tostring(v)
				table.insert(out, `{rule.name}/{prop}={shown}`)
			end
		end
		return out
	end

	local function builtIn(displaySize: string?): any
		return sheet_model.build({
			themes = { { name = "Dark", style = default_style } },
			displaySize = displaySize,
		})
	end

	--[[ THE DIRECTOR'S OWN A/B, AS A TEST. The live capture was made by typing
		18 and 12 into the sheet's corner rules by hand; this is the generator
		producing the same numbers from the factor, and — the other half of the
		claim — producing NOTHING ELSE new. Every rule prop that differs between
		the near sheet and the ten-foot one must be a corner or a thickness, and
		must be exactly the scaled value: a sheet that also moved a colour, a
		transparency or a font at distance would fail here. ]]
	it("the built-in sheet bakes the ten-foot corner, and moves nothing else", function()
		local near, tv = builtIn(nil), builtIn("Large")
		local nearLines, tvLines = propLines(near), propLines(tv)
		expect(#nearLines).toBe(#tvLines)
		local moved = 0
		for i, line in nearLines do
			if line == tvLines[i] then
				continue
			end
			moved += 1
			local prop = string.match(line, "/([^/=]+)=")
			expect(`{line} -> {tvLines[i]}`).toBe(
				if prop == "CornerRadius" or prop == "Thickness"
					then `{line} -> {tvLines[i]}`
					else `NOT A PAINT-FAMILY PROP: {line}`
			)
			-- …and the number it moved to is the derived one
			local was = tonumber(string.match(line, "([%d%.]+)%)?$") :: any)
			local now = tonumber(string.match(tvLines[i], "([%d%.]+)%)?$") :: any)
			local want = if prop == "CornerRadius" then math.round((was :: number) * 1.5) else (was :: number) * 1.5
			expect(`{line}: {now}`).toBe(`{line}: {want}`)
		end
		expect(`moved:{moved > 0}`).toBe("moved:true")
		-- the two the director looked at, by name
		local function lineFor(model: any, want: string): string
			for _, line in propLines(model) do
				if string.sub(line, 1, #want) == want then
					return line
				end
			end
			return `MISSING: {want}`
		end
		expect(lineFor(near, "Raised panel — corner/")).toBe("Raised panel — corner/CornerRadius=udim(0,12)")
		expect(lineFor(tv, "Raised panel — corner/")).toBe("Raised panel — corner/CornerRadius=udim(0,18)")
		expect(lineFor(near, "Control — corner/")).toBe("Control — corner/CornerRadius=udim(0,8)")
		expect(lineFor(tv, "Control — corner/")).toBe("Control — corner/CornerRadius=udim(0,12)")
		expect(lineFor(tv, "Raised panel — hairline/Thickness")).toBe("Raised panel — hairline/Thickness=1.5")
	end)

	--[[ …AND THE SAME CLAIM FOR A PACKAGE SHEET, mechanised off the generator's
		OWN map of metric-derived rule props rather than a list of rule names a
		refactor could leave behind. Every entry in `metricRuleProps` names the
		path it was baked from; the value in the rule must equal what
		`paintForDisplay` derives for that path at that distance, on all nine
		configurations — which is the same function the measured snapshot uses. ]]
	it("every metric-derived rule of every package sheet carries the derived number", function()
		local checked = 0
		for _, cfg in configurations() do
			local unit = snapshot.resolve(cfg.package, nil, {}).pixelUnit
			for _, displaySize in { "Medium", "Large" } do
				local model = sheet_model.buildPackage(cfg.package, { displaySize = displaySize })
				local paint = snapshot.paintForDisplay(cfg.package.metrics, displaySize, unit)
				for _, entry in model.metricRuleProps do
					if entry.form == "font" then
						continue
					end
					local want: any = paint
					for part in string.gmatch(entry.path, "[^%.]+") do
						want = if type(want) == "table" then want[part] else nil
					end
					local rule: any = nil
					for _, r in model.rules do
						if r.name == entry.rule then
							rule = r
						end
					end
					expect(`{cfg.name}@{displaySize} {entry.rule} exists`).toBe(
						`{cfg.name}@{displaySize} {rule ~= nil and entry.rule or "MISSING"} exists`
					)
					local prop = rule.props[entry.prop]
					local got = if entry.form == "udimOffset" then prop.offset else prop.value
					expect(`{cfg.name}@{displaySize} {entry.rule}.{entry.prop}={got}`).toBe(
						`{cfg.name}@{displaySize} {entry.rule}.{entry.prop}={want}`
					)
					checked += 1
				end
			end
		end
		expect(`checked:{checked > 190}`).toBe("checked:true")
	end)

	--[[ THE NEAR SHEET DOES NOT MOVE — the guard on every phone, tablet and
		desktop that is not what this ruling was about, and on the built theme
		artifacts and the style-editor token dump, which are near-density data. ]]
	it("the near sheet is byte-identical to the one built with no display class", function()
		for _, displaySize in { "Small", "Medium" } do
			expect(builtIn(displaySize).stamp).toBe(builtIn(nil).stamp)
			expect(table.concat(propLines(builtIn(displaySize)), "|")).toBe(table.concat(propLines(builtIn(nil)), "|"))
		end
		-- …and a package's near sheet, tokens and mirrors included
		for _, cfg in configurations() do
			local plain = sheet_model.buildPackage(cfg.package)
			local near = sheet_model.buildPackage(cfg.package, { displaySize = "Medium" })
			expect(`{cfg.name}:{near.stamp}`).toBe(`{cfg.name}:{plain.stamp}`)
			expect(`{cfg.name}:{table.concat(propLines(near), "|")}`).toBe(
				`{cfg.name}:{table.concat(propLines(plain), "|")}`
			)
		end
		-- the ten-foot sheet is a DIFFERENT sheet, and says so in its stamp, so a
		-- re-ensure at a new distance regenerates instead of preserving stale corners
		expect(sheet_model.buildPackage(snapshot.neutralPackage(), { displaySize = "Large" }).stamp)
			.never()
			.toBe(sheet_model.buildPackage(snapshot.neutralPackage()).stamp)
	end)

	--[[ THE BESPOKE HALF, BEHAVIOURALLY. `theme_controller.styleFor` is the
		compiled style a target that grows the `setThemeStyle` seam is handed, and
		it is the shape the fallback (explicit-write) paint path spends: if it kept
		the authored radius while the sheet moved, the rollback flag would paint a
		phone's corners on a television. Pinned per distance rather than by source,
		because this one is a pure function a headless world can call. ]]
	it("the compiled style a themed target is handed carries the same paint family", function()
		local theme_controller = require("../src/client/theme_controller") :: any
		for _, cfg in configurations() do
			local unit = snapshot.resolve(cfg.package, nil, {}).pixelUnit
			for _, displaySize in { "Medium", "Large" } do
				local style = theme_controller.styleFor(cfg.package, nil, displaySize)
				local paint = snapshot.paintForDisplay(cfg.package.metrics, displaySize, unit)
				expect(`{cfg.name}@{displaySize} style.radii.panel={style.radii.panel}`).toBe(
					`{cfg.name}@{displaySize} style.radii.panel={paint.radii.panel}`
				)
				expect(`{cfg.name}@{displaySize} style.strokes.hairline={style.strokes.hairline}`).toBe(
					`{cfg.name}@{displaySize} style.strokes.hairline={paint.strokes.hairline}`
				)
			end
		end
		-- the numbers, so an all-nil agreement is impossible
		local near = theme_controller.styleFor(snapshot.neutralPackage(), nil, "Medium")
		local tv = theme_controller.styleFor(snapshot.neutralPackage(), nil, "Large")
		expect(`{near.radii.panel}/{near.strokes.hairline} -> {tv.radii.panel}/{tv.strokes.hairline}`).toBe(
			"12/1 -> 18/1.5"
		)
	end)

	--[[ THE CONSTRUCTOR CENSUS — the CLASS, not the instance (fix round,
		2026-08-21, after a live console verify at stamp e0d6afd5).

		THE DEFECT THIS EXISTS FOR. A render target takes its display class as a
		CONSTRUCTOR ARGUMENT, so "does this surface paint at the right distance" is
		decided once per call site — and a call site that omits it is silently near
		while its own solver measures at three metres. The round that introduced the
		argument wired `client.host` and proved the derivation, and the live check
		found the framework's OWN gallery painting a 999 capsule where the
		derivation says 1499: `examples/gallery/client/init.client.luau` builds its
		target by hand. One consumer had already been caught the same way
		(Rascal Rally's `FacetSponsor`, which builds its own core, environment and
		target). Two instances of one class is a class.

		SO THIS ARM ENUMERATES EVERY CONSTRUCTOR IN THE REPOSITORY instead of the
		ones somebody remembered. It walks `src`, `examples` and `tools` for
		`screen_target.new(`, reads the call's OWN argument list — anchored with
		`%b{}` from the call, the technique `native_style_default.spec` established
		after a reviewer deleted an argument and left a comment claiming it — and
		requires each to either state `displaySize` or carry a written exemption
		here. A new bare constructor is red on the commit that adds it.

		THERE ARE NO EXEMPTIONS TODAY, and the two candidates are worth naming.
		`billboard_target` builds a screen target for a WORLD surface, where the
		viewer's distance is a world distance rather than a screen class — but its
		solver reads the same environment-wide `themeMetrics`, so painting near
		while measuring far would re-open exactly the disagreement this ladder
		closes; it forwards the class from its own `Opts`, verbatim, like `style`.
		`edit_preview` looked near-only and is not: `preview/device_profiles` has a
		`console` profile whose facts carry `displaySize = "Large"`, and the preview
		applies a profile BEFORE it builds its target, so the class it is previewing
		is the class it must paint. (A LIVE `setProfile` across the near/ten-foot
		boundary still moves measure and not paint — a target takes its class at
		construction, like its palette — and that is the same growth seam
		the ladder books, not an exemption from this census.) ]]
	it("every render-target constructor in this repository states the distance it paints at", function()
		local fs = require("@lune/fs")
		--[[ path -> the reason its context genuinely has no distance. A constructor
			may only be listed here with a written reason; the empty table is the
			claim that nothing is waived. ]]
		local EXEMPT: { [string]: string } = {}
		local found: { string } = {}
		local bare: { string } = {}
		local function walk(dir: string)
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if fs.isDir(path) then
					walk(path)
				elseif string.sub(entry, -5) == ".luau" or string.sub(entry, -4) == ".lua" then
					local source = fs.readFile(path)
					--[[ A CALL, NOT A SENTENCE ABOUT ONE. This repository's comments
						quote `screen_target.new({})` in prose all over the client and
						the renderer, and a scan that counted those would report five
						bare constructors that do not exist — a census nobody would
						trust twice. The positive rule is the one shape a real call
						takes here: the value of an assignment or of a return. It also
						excludes the DECLARATION (`function screen_target.new(`) for
						free. ]]
					local i = 1
					while true do
						local a, b = string.find(source, "screen_target.new(", i, true)
						if a == nil then
							break
						end
						i = (b :: number) + 1
						local before = string.sub(source, math.max(1, (a :: number) - 12), (a :: number) - 1)
						if string.match(before, "=%s*$") == nil and string.match(before, "return%s*$") == nil then
							continue
						end
						local call = string.match(source, "%s*(%b{})", b :: number)
						table.insert(found, path)
						if
							call == nil
							or (string.find(call :: string, "displaySize", 1, true) == nil and EXEMPT[path] == nil)
						then
							table.insert(bare, path)
						end
					end
				end
			end
		end
		walk("src")
		walk("examples")
		walk("tools")
		table.sort(found)
		table.sort(bare)
		expect(`bare constructors: {table.concat(bare, ", ")}`).toBe("bare constructors: ")
		--[[ …AND THE SCAN REALLY SCANNED. A walker that stopped finding files would
			pass the arm above with an empty census, which is the shape of check that
			proves nothing this framework already names. The five known call sites are
			listed positively; a sixth is welcome and needs no edit here. ]]
		local census = table.concat(found, ", ")
		for _, known in
			{
				"src/client/billboard_target.luau",
				"src/client/edit_preview.luau",
				"src/client/host.luau",
				"examples/gallery/client/init.client.luau",
				"examples/performance/client/init.client.luau",
			}
		do
			expect(`census has {known}: {string.find(census, known, 1, true) ~= nil}`).toBe(`census has {known}: true`)
		end
		expect(`census size: {#found >= 5}`).toBe("census size: true")
	end)

	--[[ AND THE WIRE ITSELF. The two paint authorities are engine files no
		headless world can mount, so the seam is asserted at the source: the target
		derives its `ctx.style` through the one function and hands the same class to
		the sheet builder, and the host is where the environment's fact crosses over
		(it is the only place that holds both). Without these two lines the whole
		lockstep is a snapshot that agrees with nothing. ]]
	it("the render target and the host wire the display class through to the paint", function()
		local fs = require("@lune/fs")
		local target = fs.readFile("src/client/screen_target.luau")
		expect(string.find(target, "themeSnapshot.paintForDisplay(baseStyle, displaySize)", 1, true) ~= nil).toBe(true)
		expect(string.find(target, "sheet_model.build({ themes = themes, displaySize = displaySize })", 1, true) ~= nil).toBe(
			true
		)
		local host = fs.readFile("src/client/host.luau")
		-- effectiveDisplaySize, not the raw fact, since director item 5:
		-- the live client's real paint decision must be the touch-corrected class
		expect(string.find(host, 'displaySize = env:get("effectiveDisplaySize"):get()', 1, true) ~= nil).toBe(true)
		local controller = fs.readFile("src/client/theme_controller.luau")
		expect(string.find(controller, "sheetModelFor(pkg, displaySizeFact())", 1, true) ~= nil).toBe(true)
		-- …and the live-edit repaint answers a designer's edit at the SAME distance
		expect(string.find(controller, "snapshotLib.forDisplay(base_, displaySizeFact())", 1, true) ~= nil).toBe(true)
		expect(string.find(controller, "styleFor(activePackage, themeName, displaySizeFact())", 1, true) ~= nil).toBe(
			true
		)
	end)
end)

--[[ THE SECOND DOOR — an authored radius TOKEN (fix round 2, 2026-08-21, after
	a second live console verify at stamp b62ac109).

	WHAT THE GLASS SAID. With the constructor census green and the gallery wired,
	the sheet rule `.facet-surface-raised::UICorner` carried the derived `0, 18` —
	and three live `UICorner` instances on the same screen still read `0, 999`.
	They are the segmented picker's decoration (`/S/View/Indicator/Layer/Bar`),
	and they are painted from the node's own `corners` prop rather than from a
	sheet rule or a surface role.

	THE MECHANISM. `UI.corners(bp, "pill")` resolves the token AT AUTHORING TIME:
	`styling.normalizeCorners` falls back to `tokens/default_style` when no style
	is handed to it — which is every call in `src/controls`, in `present/`, and in
	any consumer's code — and freezes the near number (999) into the blueprint.
	The render target's `ctx.style` was derived correctly; this number never asked
	it. So the paint family had TWO doors and round one closed one of them.

	THE FIX IS THE FRAMEWORK'S OWN IDIOM: a NAME reaches paint as a name. It is
	what `gap = "m"` already does (the solver resolves it against the live
	`themeMetrics`) and what `Divider.thickness` already does (a metric name the
	renderer resolves). So the normalized data now CARRIES the token beside the
	number, and the painter resolves it against the style it was built with —
	which, since round one, is the derived one. The authored number stays as the
	fallback for any consumer that cannot resolve a name (a dump, a lint, a
	fake target), so nothing that reads `corners.radius` today changes shape.

	AND IT IS RESOLVED BY A PURE FUNCTION, `styling.paintCorners`/`paintStroke`,
	for the reason `native_style.paintPlan` was extracted three days ago: the
	painter is an engine file no headless world can mount, so the decision it
	spends has to live where a test can call it. ]]
describe("ten-foot metrics — the second door: an authored token", function()
	local styling = require("../src/tokens/styling") :: any

	local function styleAt(displaySize: string?): any
		return snapshot.paintForDisplay(default_style, displaySize)
	end

	--[[ THE DOOR CENSUS. Round one enumerated the CONSTRUCTORS; this enumerates
		the STYLE SOURCES — every module that can turn a paint-family token into a
		number. There are exactly two kinds and both are named here: the modules
		that read `tokens/default_style` at all, and the two appliers that write the
		engine property. A new reader of the raw token module is the shape of this
		defect, so it must be added here with a reason before it can be green. ]]
	it("every module that can turn a paint token into a number is named, and both doors derive", function()
		local fs = require("@lune/fs")
		--[[ path -> why this module may read the AUTHORED token module directly.
			`default_style` is the near ladder, always: a module that reads it and
			paints from it without passing `paintForDisplay` is the defect this
			census exists to catch. ]]
		local ALLOWED: { [string]: string } = {
			["src/tokens/styling.luau"] = "the authoring-time fallback — it now CARRIES the token so paint re-derives",
			["src/themes/snapshot.luau"] = "the neutral package's own authored base, and the thing that derives",
			["src/client/screen_target.luau"] = "the identity check that decides whether the built-in Light theme ships",
			["src/client/theme_controller.luau"] = "the `extra` merge a partial package theme fills from",
		}
		local unnamed: { string } = {}
		local seen = 0
		local function walk(dir: string)
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if fs.isDir(path) then
					walk(path)
				elseif string.sub(entry, -5) == ".luau" then
					local source = fs.readFile(path)
					if
						string.find(source, 'require("./default_style")', 1, true) ~= nil
						or string.find(source, 'require("../tokens/default_style")', 1, true) ~= nil
					then
						seen += 1
						if ALLOWED[path] == nil then
							table.insert(unnamed, path)
						end
					end
				end
			end
		end
		walk("src")
		table.sort(unnamed)
		expect(`unnamed readers of the authored token module: {table.concat(unnamed, ", ")}`).toBe(
			"unnamed readers of the authored token module: "
		)
		expect(`readers found: {seen}`).toBe("readers found: 4")

		-- …and the second door's painter really goes through the shared resolver
		local paint = fs.readFile("src/client/screen_paint.luau")
		expect(string.find(paint, "styling.paintCorners(", 1, true) ~= nil).toBe(true)
		expect(string.find(paint, "styling.paintStroke(", 1, true) ~= nil).toBe(true)
	end)

	--[[ A NAME SURVIVES AUTHORING. The number beside it is the near value, and it
		stays — a lint, a dump and a fake target all read it — but the NAME is what
		the painter spends. ]]
	it("normalized corner and stroke data carry the token they were authored with", function()
		local pill = UI.cornersData("pill")
		expect(`{pill.form}/{pill.radius}/{pill.tokens.radius}`).toBe("uniform/999/pill")
		-- a literal is a literal: nothing to re-derive, and no token carried
		local literal = UI.cornersData(6)
		expect(`{literal.radius}/{tostring(literal.tokens)}`).toBe("6/nil")
		-- per corner, token by token
		local mixed = UI.cornersData({ topLeft = "panel", topRight = 4, bottomLeft = "control", bottomRight = 0 })
		expect(`{mixed.topLeft}/{mixed.topRight}/{mixed.bottomLeft}`).toBe("12/4/8")
		expect(`{mixed.tokens.topLeft}/{tostring(mixed.tokens.topRight)}/{mixed.tokens.bottomLeft}`).toBe(
			"panel/nil/control"
		)
		--[[ AN ABSENT STROKE THICKNESS IS A TOKEN TOO, and this is the case a
			reviewer would miss: `UI.stroke(bp, {})` documents its default as "the
			theme's `strokes.hairline`", so the number it froze was a theme number
			nobody named. It is named now. ]]
		expect(`{UI.strokeData({}).thickness}/{UI.strokeData({}).tokens.thickness}`).toBe("1/hairline")
		expect(`{UI.strokeData({ thickness = "hairline" }).tokens.thickness}`).toBe("hairline")
		expect(`{tostring(UI.strokeData({ thickness = 3 }).tokens)}`).toBe("nil")
	end)

	--[[ THE RESOLVERS, PURE, AT BOTH DISTANCES. This is what the painter spends,
		so this is where the ten-foot number is actually decided. ]]
	it("the paint resolver re-derives a token against the style it paints with", function()
		local near, tv = styleAt("Medium"), styleAt("Large")
		local pill = UI.cornersData("pill")
		expect(`near {styling.paintCorners(pill, near).radius}`).toBe("near 999")
		expect(`ten-foot {styling.paintCorners(pill, tv).radius}`).toBe("ten-foot 1499")
		local panel = UI.cornersData("panel")
		expect(`{styling.paintCorners(panel, near).radius} -> {styling.paintCorners(panel, tv).radius}`).toBe(
			"12 -> 18"
		)
		-- a LITERAL never moves: an author who wrote 6 px meant 6 px at every distance
		local literal = UI.cornersData(6)
		expect(`{styling.paintCorners(literal, tv).radius}`).toBe("6")
		-- per-corner, mixed: the two tokens move and the two literals do not
		local mixed = UI.cornersData({ topLeft = "panel", topRight = 4, bottomLeft = "control", bottomRight = 0 })
		local painted = styling.paintCorners(mixed, tv)
		expect(`{painted.topLeft}/{painted.topRight}/{painted.bottomLeft}/{painted.bottomRight}`).toBe("18/4/12/0")
		-- …and the stroke half: a hairline is 1.5 px at three metres
		expect(`{styling.paintStroke(UI.strokeData({}), tv).thickness}`).toBe("1.5")
		expect(`{styling.paintStroke(UI.strokeData({}), near).thickness}`).toBe("1")
		expect(`{styling.paintStroke(UI.strokeData({ thickness = 3 }), tv).thickness}`).toBe("3")
		-- the resolvers are TOTAL: garbage in is the authored number back, never a throw
		expect(`{styling.paintCorners(pill, nil).radius}`).toBe("999")
		expect(`{styling.paintCorners(pill, { radii = {} }).radius}`).toBe("999")
	end)

	--[[ THE SURFACE THE LIVE ROW READ, MOUNTED AT LARGE — the arm that answers
		"which framework surface is actually exercised at ten-foot by a test".
		The segmented picker's sliding indicator is the control whose three
		`UICorner`s read `0, 999` on the console; this mounts THAT control at
		`displaySize = "Large"` and follows its `corners` prop all the way to the
		number the painter would write. ]]
	it("the segmented picker's indicator paints the ten-foot capsule at Large", function()
		local function pickerWorld(displaySize: string): any
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			env:set("displaySize", displaySize)
			local system = Facet.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = Facet.newPresenter(core, env, adapter, system)
			local picker = Facet.Controls.Picker(core, {
				id = "View",
				selected = core:signal("grid"),
				options = { { value = "grid", label = "Grid" }, { value = "list", label = "Listing" } },
				presentation = "segmented",
				indicator = "pill",
				env = env,
			})
			pres.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
			pres.refresh()
			return adapter
		end
		for _, case in { { size = "Medium", want = 999 }, { size = "Large", want = 1499 } } do
			local adapter = pickerWorld(case.size :: string)
			local bar = adapter.node("/S/View/Indicator/Layer/Bar")
			expect(`{case.size}: bar mounted {bar ~= nil}`).toBe(`{case.size}: bar mounted true`)
			local corners = (bar :: any).props.corners
			-- the AUTHORING number is the near one at both distances — that is the
			-- defect's own fingerprint, and it is why the token has to survive
			expect(`{case.size}: authored {corners.radius}`).toBe(`{case.size}: authored 999`)
			expect(`{case.size}: token {corners.tokens.radius}`).toBe(`{case.size}: token pill`)
			-- …and what the painter writes, through the style the target derives
			local painted = styling.paintCorners(corners, styleAt(case.size :: string)).radius
			expect(`{case.size}: painted {painted}`).toBe(`{case.size}: painted {case.want}`)
		end
	end)
end)
