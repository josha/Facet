--!strict
-- THE REFERENCE THEME CORPUS (ADR-0019 "Consequences": the packages every
-- future stage restyles against).
--
-- Each package is built the way a game team would build one — through the
-- PUBLIC `Facet.themes` surface and nothing else — so these tests double as
-- the proof that the public surface is sufficient. If a reference package ever
-- needs an internal require to compile, that is a hole in the public API and
-- this spec is where it shows up.
--
-- The coverage matrix is computed by DIFFING each compiled package against
-- Studio Neutral rather than read from a declaration, so a package that claims
-- to change the font and does not fails here instead of in a Studio capture.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local sheet_model = require("../src/tokens/sheet_model")
local themePackage = require("../src/themes/package")
local chromeSlots = require("../src/tokens/chrome_slots")
local themes = Facet.themes

local MODULES = {
	classic_desktop = require("../examples/themes/classic_desktop"),
	glossy_mobile = require("../examples/themes/glossy_mobile"),
	scifi_hud = require("../examples/themes/scifi_hud"),
	fantasy_parchment_stub = require("../examples/themes/fantasy_parchment_stub"),
	fantasy_parchment = require("../examples/themes/fantasy_parchment"),
	-- the rich-skinning-v2 reference packages (ADR-0020, build package P5). They
	-- join the corpus rather than sitting beside it: every claim the five older
	-- packages have to survive — public-API-only construction, a resolvable
	-- snapshot, a stable sheet stamp, honest theme-class declarations — is a
	-- claim these four have to survive too.
	fantasy_ornate = require("../examples/themes/fantasy_ornate"),
	pixel_quest = require("../examples/themes/pixel_quest"),
	glossy_touch = require("../examples/themes/glossy_touch"),
	compact_pointer = require("../examples/themes/compact_pointer"),
}
local ORDER = {
	"classic_desktop",
	"glossy_mobile",
	"scifi_hud",
	"fantasy_parchment_stub",
	"fantasy_parchment",
	"fantasy_ornate",
	"pixel_quest",
	"glossy_touch",
	"compact_pointer",
}
local customControl = require("../examples/themes/custom_control")
-- the rung-3 worked example (ADR-0020 R8): a control with its OWN art and its
-- own namespaced roles, checked from both directions
local ornateGauge = require("../examples/themes/ornate_gauge")

local function built(name: string): any
	local pkg, report = MODULES[name].build(themes)
	if pkg == nil then
		local first = report.errors[1]
		error(`{name} failed its own package gate: {first and first.field} — {first and first.message}`, 2)
	end
	return pkg
end

-- the theme CLASSES a package exercises, computed against Studio Neutral
local function classesOf(pkg: any): { [string]: boolean }
	local neutral = themes.neutralPackage()
	local neutralSnap = themes.neutral()
	local out: { [string]: boolean } = {}
	for _, theme in pkg.style.themes do
		local snap = themes.resolve(pkg, theme.name, {})
		for role, entry in snap.type do
			if entry.fontKey ~= neutralSnap.type[role].fontKey then
				out.font = true
			end
			if entry.size ~= neutralSnap.type[role].size then
				out.metrics = true
			end
		end
		for step, value in snap.space do
			if value ~= neutralSnap.space[step] then
				out.metrics = true
			end
		end
		for size, entry in snap.controlSizes do
			local base = neutralSnap.controlSizes[size]
			if base == nil or base.height ~= entry.height then
				out.metrics = true
			end
		end
		for name, value in snap.radii do
			if value ~= neutralSnap.radii[name] then
				out.metrics = true
			end
		end
		for key, value in theme.colors do
			local base = neutral.style.themes[1].colors[key]
			if base == nil or base.r ~= value.r or base.g ~= value.g or base.b ~= value.b then
				out.palette = true
			end
		end
	end
	for _ in pkg.assets do
		out.assets = true
	end
	return out
end

describe("reference theme packages compile and resolve through the public API only", function()
	for _, name in ORDER do
		it(`{name}: define() accepts it and resolve() produces a usable snapshot`, function()
			local pkg = built(name)
			expect(pkg.schema).toBe(themes.SCHEMA)
			expect(pkg.identity.id).toBe(MODULES[name].id)
			expect(table.isfrozen(pkg)).toBe(true)
			for _, theme in pkg.style.themes do
				local snap = themes.resolve(pkg, theme.name, {})
				expect(snap.identity.packageId).toBe(pkg.identity.id)
				expect(snap.identity.themeName).toBe(theme.name)
				-- every role the framework resolves on a solve must be present
				for _, role in { "caption", "label", "body", "control", "heading", "title" } do
					expect(snap.type[role].size).toBeGreaterThan(0)
				end
				expect(snap.controlSizes.regular.height).toBeGreaterThan(0)
				expect(snap.controls.slider.thumbSize).toBeGreaterThan(0)
				-- the accessibility floor clamps UP and can never be lowered
				expect(snap.targetSizes.minimum).toBeGreaterThanOrEqual(44)
			end
		end)

		it(`{name}: compiles to a sheet model with a stable stamp`, function()
			local pkg = built(name)
			local model = sheet_model.buildPackage(pkg)
			expect(model.schema).toBe("facet-native-sheet/1")
			expect(#model.rules).toBeGreaterThan(30)
			expect(model.defaultTheme).toBe(pkg.style.defaultTheme)
			expect(model.stamp).toBe(sheet_model.buildPackage(pkg).stamp)
			expect(#model.themes).toBe(#pkg.style.themes)
		end)

		it(`{name}: declares the theme classes it actually exercises`, function()
			local actual = classesOf(built(name))
			for _, declared in MODULES[name].themeClasses do
				expect(actual[declared]).toBe(true)
			end
		end)
	end
end)

describe("the corpus covers all four theme classes", function()
	it("palette-only, metric-changing, font-changing and asset-backed are all represented", function()
		local union: { [string]: string } = {}
		for _, name in ORDER do
			for class in classesOf(built(name)) do
				union[class] = union[class] or name
			end
		end
		expect(union.palette ~= nil).toBe(true)
		expect(union.metrics ~= nil).toBe(true)
		expect(union.font ~= nil).toBe(true)
		expect(union.assets).toBe("fantasy_parchment_stub")
	end)

	it("PALETTE-ONLY is the two-theme package: a swap moves colour and no geometry at all", function()
		local pkg = built("classic_desktop")
		expect(#pkg.style.themes).toBe(2)
		local day = themes.resolve(pkg, "Day", {})
		local night = themes.resolve(pkg, "Night", {})
		-- every measurable value is identical...
		expect(day.type.body.size).toBe(night.type.body.size)
		expect(day.type.body.fontKey).toBe(night.type.body.fontKey)
		expect(day.space.m).toBe(night.space.m)
		expect(day.controlSizes.regular.height).toBe(night.controlSizes.regular.height)
		expect(day.radii.control).toBe(night.radii.control)
		-- ...and the paint is not
		local model = sheet_model.buildPackage(pkg)
		expect(model.themes[1].tokens.Surface.r ~= model.themes[2].tokens.Surface.r).toBe(true)
	end)

	it("METRIC-CHANGING moves the numbers a control resolves on every solve", function()
		local dense = themes.resolve(built("classic_desktop"), nil, {})
		local roomy = themes.resolve(built("glossy_mobile"), nil, {})
		expect(dense.controlSizes.regular.height).toBeLessThan(roomy.controlSizes.regular.height)
		expect(dense.space.m).toBeLessThan(roomy.space.m)
		expect(dense.radii.panel).toBeLessThan(roomy.radii.panel)
		expect(themes.resolve(built("scifi_hud"), nil, {}).radii.control).toBe(0)
	end)

	it("FONT-CHANGING keys measurement on the effective descriptor, not a short name", function()
		local neutral = themes.neutral()
		local scifi = themes.resolve(built("scifi_hud"), nil, {})
		local glossy = themes.resolve(built("glossy_mobile"), nil, {})
		expect(scifi.type.body.fontKey ~= neutral.type.body.fontKey).toBe(true)
		expect(string.find(scifi.type.body.fontKey, "Michroma", 1, true) ~= nil).toBe(true)
		-- two weights of ONE family must not share a key (ADR-0019 §6)
		expect(glossy.type.title.fontKey ~= glossy.type.body.fontKey).toBe(true)
		expect(string.find(glossy.type.title.fontKey, "#Bold#", 1, true) ~= nil).toBe(true)
		-- and the rules paint what the solver measured
		local model = sheet_model.buildPackage(built("scifi_hud"))
		for _, rule in model.rules do
			if rule.name == "Text default" then
				expect(rule.props.FontFace.family).toBe("rbxasset://fonts/families/Michroma.json")
			end
		end
	end)

	it("ASSET-BACKED declares content IDs only inside package data", function()
		local pkg = built("fantasy_parchment_stub")
		local declared: { [string]: boolean } = {}
		for _, asset in pkg.assets do
			expect(string.sub(asset.contentId, 1, 12)).toBe("rbxassetid:/")
			declared[asset.contentId] = true
		end
		for _, recipe in pkg.chrome do
			if recipe.kind == "nineSlice" then
				-- a recipe names an ASSET, never an ID
				expect(pkg.assets[recipe.asset] ~= nil).toBe(true)
				expect(recipe.fallback).toBe("native")
			end
		end
		-- the IDs are the ones the upload manifest recorded
		expect(declared["rbxassetid://78012779616687"]).toBe(true)
	end)
end)

describe("the failure fixtures fail the way the scenario needs them to", function()
	it("a bogus content ID still COMPILES — asset failure is a runtime fact, not a compile one", function()
		local pkg = MODULES.fantasy_parchment_stub.buildBadAsset(themes)
		expect(pkg ~= nil).toBe(true)
		expect(pkg.assets.parchment_panel.contentId).toBe(MODULES.fantasy_parchment_stub.BOGUS_CONTENT_ID)
		-- and it still produces a complete rule set: the style resolves, the
		-- image does not load (feasibility m2)
		local model = sheet_model.buildPackage(pkg)
		for _, rule in model.rules do
			if rule.name == "Chrome — panel" then
				expect(rule.props.Image).toBe(MODULES.fantasy_parchment_stub.BOGUS_CONTENT_ID)
			end
		end
	end)

	it("an unknown font family compiles and RESERVES conservatively rather than clipping", function()
		local text_metrics = require("../src/layout/text_metrics")
		local pkg = MODULES.fantasy_parchment_stub.buildBadFont(themes)
		expect(pkg ~= nil).toBe(true)
		local snap = themes.resolve(pkg, nil, {})
		local unknown = snap.type.body.fontKey
		expect(string.find(unknown, "NotAShippedFamily", 1, true) ~= nil).toBe(true)
		-- the unknown family measures WIDER than a known one at the same size,
		-- which is the whole point: over-reserving never clips
		local known = text_metrics.measure("Brightness", "BuilderSans", 16, 1000)
		local degraded = text_metrics.measure("Brightness", unknown, 16, 1000)
		expect(degraded.width).toBeGreaterThanOrEqual(known.width)
		expect(degraded.state).toBe("pending") -- conservative, and honestly labelled
	end)

	it("an incompatible schema is REJECTED with the offending field and the fix", function()
		local pkg, report = MODULES.fantasy_parchment_stub.buildIncompatible(themes)
		expect(pkg).toBeNil()
		expect(report.ok).toBe(false)
		local found = nil
		for _, entry in report.errors do
			if entry.class == "schemaVersion" then
				found = entry
			end
		end
		expect(found ~= nil).toBe(true)
		expect(string.find(found.message, MODULES.fantasy_parchment_stub.INCOMPATIBLE_SCHEMA, 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(found.message, themes.SCHEMA, 1, true) ~= nil).toBe(true)
		expect(#found.fix > 0).toBe(true)
	end)
end)

describe("namespaced custom-control conformance (ns:role)", function()
	it("declares its needs with type, fallback, authority and capability", function()
		expect(#customControl.needs).toBe(2)
		for _, need in customControl.needs do
			expect(string.find(need.name, ":", 1, true) ~= nil).toBe(true)
			expect(need.authority == "layout" or need.authority == "paint").toBe(true)
			expect(need.fallback ~= nil).toBe(true)
			expect(need.capability).toBe("none")
		end
	end)

	it("a COVERING package satisfies every need and the control follows the theme", function()
		local pkg = built("glossy_mobile")
		local result = customControl.check(pkg)
		expect(result.ok).toBe(true)
		expect(#result.missing).toBe(0)
		expect(#result.covered).toBe(2)
		local snap = themes.resolve(pkg, nil, {})
		local resolved = customControl.resolve(snap, pkg)
		expect(resolved.usedFallback.size).toBe(false)
		expect(resolved.usedFallback.tint).toBe(false)
		expect(resolved.height).toBe(pkg.metrics.controlSizes["demo:gauge"].height)
	end)

	it("an UNCOVERING package produces a useful pre-play error, not a crash", function()
		local pkg = built("classic_desktop")
		local result = customControl.check(pkg)
		expect(result.ok).toBe(false)
		expect(#result.missing).toBe(2)
		for _, entry in result.missing do
			-- the message names the package, the role and the consequence; the
			-- fix names where the role goes
			expect(string.find(entry.message, pkg.identity.id, 1, true) ~= nil).toBe(true)
			expect(string.find(entry.message, entry.name, 1, true) ~= nil).toBe(true)
			expect(#entry.fix > 0).toBe(true)
		end
		-- and the control still RUNS, on its declared fallbacks
		local resolved = customControl.resolve(themes.resolve(pkg, nil, {}), pkg)
		expect(resolved.usedFallback.size).toBe(true)
		expect(resolved.height).toBe(customControl.needs[1].fallback.height)
	end)

	it("the compiler itself accepts the namespaced entries SILENTLY — which is why the fixture checks", function()
		-- recorded as a test so the finding cannot rot: `define` reports no
		-- error, no warning and no missing entry for either namespaced role, in
		-- EITHER direction. The pre-play gate is therefore the control's own.
		local covering, coveringReport = MODULES.glossy_mobile.build(themes)
		expect(covering ~= nil).toBe(true)
		expect(coveringReport.ok).toBe(true)
		expect(#coveringReport.errors).toBe(0)
		local uncovering, uncoveringReport = MODULES.classic_desktop.build(themes)
		expect(uncovering ~= nil).toBe(true)
		expect(uncoveringReport.ok).toBe(true)
		expect(#uncoveringReport.errors).toBe(0)
		-- the namespaced size survives into the snapshot untouched
		expect(themes.resolve(covering, nil, {}).controlSizes["demo:gauge"].height).toBe(28)
	end)
end)

-- ===== REVIEW-FIX round: gradient readability (D18b) ========================

describe("the gradient-carrying packages stay READABLE", function()
	-- UIGradient.Transparency fades the parent's whole rendering, text included:
	-- the stored captures showed the 0.72–0.96 ramps ghosting entire screens.
	-- The compiler caps a stop at 0.9; these two are the packages that have to
	-- live well inside it, because they are the corpus's gradient proof.
	local SUBTLE_MAX = 0.35

	local function maxAlphaStop(pkg: any): number
		local worst = 0
		for _, theme in pkg.style.themes do
			local gradients = (theme.extra or {}).chromeGradient
			if type(gradients) == "table" then
				for _, entry in gradients do
					for _, stop in (entry.alpha or {}) :: any do
						worst = math.max(worst, stop.v)
					end
				end
			end
		end
		return worst
	end

	for _, name in { "glossy_mobile", "scifi_hud" } do
		it(`{name}: compiles and every gradient alpha stop is subtle`, function()
			local pkg = built(name)
			local worst = maxAlphaStop(pkg)
			expect(worst > 0).toBe(true) -- it really does declare gradients
			expect(worst <= SUBTLE_MAX).toBe(true)
			expect(worst <= themePackage.GRADIENT_ALPHA_MAX).toBe(true)
		end)
	end

	it("the gradients still reach the compiled sheet as ::UIGradient rules", function()
		local model = sheet_model.buildPackage(built("scifi_hud"))
		local found = 0
		for _, rule in model.rules do
			if string.find(rule.selector, "::UIGradient", 1, true) ~= nil then
				found += 1
			end
		end
		expect(found >= 3).toBe(true)
	end)
end)

-- ===== REVIEW-FIX round: the worked example IS the sync workflow (E26) ======

describe("fantasy_parchment carries its metrics in the theme_sync region", function()
	-- The guide teaches the sync command against this file, and the repository
	-- runs it as a gate. Before the fix the command FAILED on the guide's own
	-- worked example: the file had no marker region, so the CLI treated the whole
	-- hand-authored package as generator-owned.
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local token_sync = require("../src/themes/token_sync")

	local PATH = "examples/themes/fantasy_parchment.luau"

	it("the region is a loadable, self-contained metrics chunk", function()
		local source = fs.readFile(PATH)
		expect(string.find(source, token_sync.BEGIN_MARKER, 1, true) ~= nil).toBe(true)
		expect(string.find(source, token_sync.END_MARKER, 1, true) ~= nil).toBe(true)
		local chunk = token_sync.extractMetricsChunk(source)
		expect(chunk ~= nil).toBe(true)
		-- loadable ON ITS OWN: `--check` must be able to read the committed
		-- metrics without evaluating a file that may require other modules
		local loaded: any = (luau.load(chunk :: string, { debugName = PATH }))()
		expect(type(loaded.metrics)).toBe("table")
		expect(type(loaded.metrics.space.m)).toBe("number")
		expect(type(loaded.metrics.typography.body.font.family)).toBe("string")
	end)

	it("the region's data is exactly what the compiled package resolves — zero drift", function()
		local pkg = built("fantasy_parchment")
		local committed: any = (luau.load(
			token_sync.extractMetricsChunk(fs.readFile(PATH)) :: string,
			{ debugName = PATH }
		))()
		local drift = token_sync.diff(token_sync.records(pkg), token_sync.recordsFromMetrics(committed.metrics))
		expect(#drift).toBe(0)
	end)

	it("consuming the region left the package value-identical (the stored captures stay honest)", function()
		-- the stamp the live Studio dump was taken against. Re-pinned in the
		-- 2026-08-10 row-actions Task 2 round: Studio Neutral (and therefore
		-- every package deriving from it) grew `controls.rowActions.*`
		-- (buttonMinWidth/buttonPad/editAffordance), so the stored captures are
		-- re-taken against THIS stamp.
		--
		-- Re-pinned again 2026-08-14 (director round: the circular indicator and the
		-- dot spinner are theme-sized shapes and every shipped package now AUTHORS
		-- them). This package's own `controls.progress` grew `circularSize` 30,
		-- `circularThickness` 3 and `spinnerDotSize` 9 — three numbers it used to
		-- inherit from its space scale, which is exactly the change a stamp is
		-- supposed to notice.
		--
		-- Re-pinned again 2026-08-17 by the Facet rename: the package's schema
		-- string moved from the pre-rename `luauui-theme/1` to `facet-theme/1`,
		-- so the compiled value really is different and the stamp is doing its
		-- job. Measured, not guessed: 538b2cb8 -> 9a3b8dd8.
		expect(built("fantasy_parchment").stamp).toBe("9a3b8dd8")
	end)

	it("a hand edit inside the region is detectable as drift, naming the token", function()
		local pkg = built("fantasy_parchment")
		local committed: any = (luau.load(
			token_sync.extractMetricsChunk(fs.readFile(PATH)) :: string,
			{ debugName = PATH }
		))()
		committed.metrics.space.m = committed.metrics.space.m + 1
		local drift = token_sync.diff(token_sync.records(pkg), token_sync.recordsFromMetrics(committed.metrics))
		expect(#drift).toBe(1)
		expect(drift[1].path).toBe("space.m")
	end)
end)

-- ===== rich-skinning-v2: THE REFERENCE PACKAGES (build package P5) ==========
--
-- Rows RS-A12 (Fantasy Ornate, the centerpiece), RS-A13 (the pixel package) and
-- RS-A14 (the platform pair). What is pinned HEADLESSLY here is everything a
-- Studio session cannot falsify cheaply: that the packages are built through the
-- public surface only, that the capability map they claim is the capability map
-- they DECLARE, and that the pair's two metric snapshots really are two
-- snapshots. What they LOOK like, and whether the art applies on a live node, is
-- the E3 half in `artifacts/rich-skinning-v2/rs-a12..a14`.

local fs = require("@lune/fs")

local P5 = { "fantasy_ornate", "pixel_quest", "glossy_touch", "compact_pointer" }

describe("the P5 reference packages are CONSUMER code", function()
	for _, name in P5 do
		it(`{name}: reaches the framework only through the public surface`, function()
			-- the acceptance claim these files exist to make: a game team with the
			-- public docs can write them. An internal require would mean the public
			-- API is insufficient, and this is where that shows up rather than in a
			-- capture nobody diffs.
			local source = fs.readFile(`examples/themes/{name}.luau`)
			expect(string.find(source, 'require("../../src', 1, true)).toBeNil()
			expect(string.find(source, "src/tokens", 1, true)).toBeNil()
			expect(string.find(source, "src/themes", 1, true)).toBeNil()
			-- and it is not a fixture pretending to be a package
			expect((MODULES[name] :: any).testOnly).toBeNil()
		end)

		it(`{name}: names an asset, never an id, in every recipe`, function()
			local pkg = built(name)
			local ids = 0
			for _, asset in pkg.assets do
				expect(string.sub(asset.contentId, 1, 12)).toBe("rbxassetid:/")
				ids += 1
			end
			expect(ids > 0).toBe(true)
			local function checkRef(ref: any)
				if type(ref) == "string" then
					expect(pkg.assets[ref] ~= nil).toBe(true)
				elseif type(ref) == "table" then
					for _, entry in ref do
						checkRef(entry)
					end
				end
			end
			for slot, recipe in pkg.chrome do
				if slot == "focus" or recipe.kind == "native" then
					continue
				end
				checkRef(recipe.asset)
				for _, layer in (recipe.layers or {}) :: any do
					checkRef(layer.asset)
					for _, corner in { "topLeft", "topRight", "bottomLeft", "bottomRight" } do
						checkRef(layer[corner])
					end
				end
			end
			for _, ref in (pkg.icons or {}) :: any do
				checkRef(ref)
			end
		end)
	end
end)

describe("RS-A12 Fantasy Ornate exercises every v2 capability it claims", function()
	local function ornate(): any
		return built("fantasy_ornate")
	end

	it("R1: the panel declares the WHOLE layer vocabulary in one stack", function()
		local panel = ornate().chrome.panel
		expect(panel.kind).toBe("layered")
		local kinds: { [string]: boolean } = {}
		for _, layer in panel.layers do
			kinds[layer.kind] = true
		end
		-- every kind ADR-0020 R1 defines, in one slot: a vocabulary no reference
		-- package exercises is a vocabulary nobody has proved
		for _, kind in chromeSlots.LAYER_KINDS do
			expect(kinds[kind]).toBe(true)
		end
		expect(#panel.layers <= chromeSlots.MAX_LAYERS).toBe(true)
		-- per-CORNER art, not one ornament repeated four times
		local corners = nil
		for _, layer in panel.layers do
			if layer.kind == "corners" then
				corners = layer
			end
		end
		expect(corners.topLeft ~= corners.bottomRight).toBe(true)
		-- the rail TILES rather than stretching (a repeating pattern that is
		-- nine-sliced becomes one smeared centre run)
		for _, layer in panel.layers do
			if layer.kind == "edges" then
				expect(layer.tile).toBe(64)
			end
		end
	end)

	it("R2: per-state art on five slots, and no variant moves a reservation", function()
		local pkg = ornate()
		local function statesOf(variants: any): number
			local n = 0
			for _ in variants do
				n += 1
			end
			return n
		end
		-- the control's fill carries four states INCLUDING `error`, which has no
		-- engine GuiState and rides the adapter's tag
		local fill = pkg.chrome.control.layers[1]
		expect(fill.assetVariants.default ~= nil).toBe(true)
		expect(fill.assetVariants.hover ~= nil).toBe(true)
		expect(fill.assetVariants.pressed ~= nil).toBe(true)
		expect(fill.assetVariants.error ~= nil).toBe(true)
		expect(statesOf(fill.assetVariants)).toBe(4)
		expect(statesOf(pkg.chrome.selection.layers[1].assetVariants)).toBe(2)
		expect(statesOf(pkg.chrome.toggleTrack.assetVariants)).toBe(2)
		expect(statesOf(pkg.chrome.toggleKnob.assetVariants)).toBe(2)
		expect(statesOf(pkg.chrome.stepperPlate.assetVariants)).toBe(2)
		-- a variant may change its art, never its box: `contentInsets` is ONE
		-- table per recipe, so the no-reflow rule holds structurally
		expect(pkg.chrome.control.contentInsets.left).toBe(14)
	end)

	it("R3: the bar family is complete, with an ornament at BOTH ends", function()
		local chrome = ornate().chrome
		for _, slot in { "barTrack", "barFill", "barCap", "barCenter", "stepperPlate", "toggleTrack", "toggleKnob" } do
			expect(chrome[slot] ~= nil).toBe(true)
		end
		expect(chrome.barFill.direction).toBe("ltr")
		expect(chrome.barCap.startAsset ~= chrome.barCap.endAsset).toBe(true)
		-- the rail is ART, so the theme owns a height it can actually draw at:
		-- 28px of source with a 12px border cannot render in the neutral 6
		local snap = themes.resolve(ornate(), nil, {})
		expect(snap.controls.progress.trackHeight >= 28).toBe(true)
		expect(snap.controls.slider.railHeight >= 20).toBe(true)
	end)

	it("R4: six framework icons, one NAMESPACED, and two left to the glyph", function()
		local pkg = ornate()
		for _, name in { "increment", "decrement", "chevron.trailing", "chevron.down", "checkmark", "close" } do
			local resolved = themePackage.resolveIcon(pkg, name)
			expect(resolved.source).toBe("asset")
			expect(string.sub(resolved.contentId, 1, 12)).toBe("rbxassetid:/")
		end
		-- a meaning the framework never heard of, shipped by the package
		local gear = themePackage.resolveIcon(pkg, "ornate:settings")
		expect(gear.source).toBe("asset")
		-- ...and the two the package deliberately does NOT map. Since the
		-- compact-label stage those fall to the FRAMEWORK's own art, which
		-- resolves below a package's and above the ASCII glyph — so this
		-- centerpiece shows every rung of the ladder at once: six names it drew
		-- itself, one it invented, two it left to the library. It does not opt out
		-- of the set; the pair that does is where the ASCII floor is proved.
		for _, name in { "menu", "more" } do
			local resolved = themePackage.resolveIcon(pkg, name)
			expect(resolved.source).toBe("asset")
			-- the library's art, not this package's: it names no asset the package
			-- declares, and it is tinted by a role rather than shipping a colour
			expect(pkg.assets[resolved.assetName]).toBeNil()
			expect(resolved.tintRole).toBe("content")
		end
		-- and the ASCII floor is still there underneath, for a package that
		-- declines the set entirely
		expect(themePackage.isSafeGlyph(themePackage.iconGlyph("menu"))).toBe(true)
		-- icon size rides the SNAPSHOT (a metric package resizes icons)
		expect(themes.resolve(pkg, nil, {}).iconSizes.medium).toBe(32)
	end)

	it("R6: authored as `content`, compiled to one plain string", function()
		local source = fs.readFile("examples/themes/fantasy_ornate.luau")
		expect(string.find(source, 'content = "rbxassetid://', 1, true) ~= nil).toBe(true)
		expect(string.find(source, 'contentId = "rbxassetid://', 1, true)).toBeNil()
		for _, asset in ornate().assets do
			expect(type(asset.contentId)).toBe("string")
			expect((asset :: any).content).toBeNil()
		end
	end)

	it("two contrast-gated themes, each with its own focus glow", function()
		local pkg, report = MODULES.fantasy_ornate.build(themes)
		expect(#pkg.style.themes).toBe(2)
		expect(#report.contrast > 0).toBe(true)
		for _, entry in report.contrast do
			expect(entry.ok).toBe(true)
			expect(entry.ratio >= 4.5).toBe(true)
		end
		-- the glow token has to resolve in BOTH themes: one that resolves in
		-- Grand Hall and not in Crypt is a halo that vanishes on a swap
		expect(pkg.chrome.focus.kind).toBe("glow")
		for _, theme in pkg.style.themes do
			local color = chromeSlots.resolveFocusColor(pkg.chrome.focus, theme)
			expect(color ~= nil).toBe(true)
		end
		-- and the two are genuinely different light
		local hall = chromeSlots.resolveFocusColor(pkg.chrome.focus, pkg.style.themes[1])
		local crypt = chromeSlots.resolveFocusColor(pkg.chrome.focus, pkg.style.themes[2])
		expect(hall.b ~= crypt.b).toBe(true)
	end)

	it("the census counts what the skin COSTS (RS-A17 reads exactly this)", function()
		local model = sheet_model.buildPackage(ornate())
		local census = model.census
		expect(census.layers > 0).toBe(true)
		expect(census.layerRules > 0).toBe(true)
		expect(census.suppressionRules > 0).toBe(true)
		expect(census.variantRules > 0).toBe(true)
		-- NOT a pixel package: every image rule, and no Pixelated stamp anywhere
		expect(census.imageRules > 0).toBe(true)
		expect(census.pixelatedRules).toBe(0)
		-- the plaque's overhang is published, because an ancestor that clips has
		-- to know the panel paints outside its own rect
		expect(census.overhang.panel.top > 0).toBe(true)
	end)

	it("the failure fixture breaks ONE middle layer and still compiles", function()
		local pkg = MODULES.fantasy_ornate.buildBadLayer(themes)
		expect(pkg ~= nil).toBe(true)
		expect(pkg.assets[MODULES.fantasy_ornate.BROKEN_ASSET].contentId).toBe(MODULES.fantasy_ornate.BOGUS_CONTENT_ID)
		-- asset failure is a RUNTIME fact; the package still produces a full stack
		expect(#pkg.chrome.panel.layers).toBe(6)
	end)
end)

describe("RS-A13 Pixel Quest is a real pixel package", function()
	local function quest(): any
		return built("pixel_quest")
	end

	it("declares pixel mode and keeps every SliceScale an integer", function()
		local pkg = quest()
		expect(pkg.identity.rendering).toBe("pixel")
		expect(pkg.identity.pixelUnit).toBe(4)
		for name, asset in pkg.assets do
			if asset.sliceCenter ~= nil then
				expect(asset.sliceScale).toBe(math.floor(asset.sliceScale))
				expect(asset.sliceScale >= 1).toBe(true)
			end
			expect(#name > 0).toBe(true)
		end
	end)

	it("every emitted image rule is nearest-neighbour", function()
		local model = sheet_model.buildPackage(quest())
		expect(model.census.imageRules > 0).toBe(true)
		expect(model.census.pixelatedRules).toBe(model.census.imageRules)
	end)

	it("every resolved LENGTH lands on the 4px grid", function()
		local snap = themes.resolve(quest(), nil, {})
		local offGrid: { string } = {}
		for _, section in { "space", "radii", "strokes", "targetSizes", "iconSizes" } do
			for key, value in (snap :: any)[section] do
				if type(value) == "number" and value % 4 ~= 0 then
					table.insert(offGrid, `{section}.{key}={value}`)
				end
			end
		end
		expect(table.concat(offGrid, ", ")).toBe("")
		-- the floor snaps UP, never down: 44 is already on the grid, and a
		-- package at unit 6 would get 48 rather than 42
		expect(snap.targetSizes.minimum >= 44).toBe(true)
	end)

	it("SELECTION CHANGES THE WHOLE STYLE: a different plate AND ornaments", function()
		local pkg = quest()
		local selection = pkg.chrome.selection
		expect(selection.kind).toBe("layered")
		expect(#selection.layers).toBe(2)
		local plate, ornament = selection.layers[1], selection.layers[2]
		expect(plate.kind).toBe("fill")
		expect(plate.assetVariants.default.asset ~= plate.assetVariants.selected.asset).toBe(true)
		-- the ornaments exist ONLY when selected, said explicitly: the grammar
		-- requires a `default`, so the package names 24x24 of pure transparency
		-- rather than shipping a dimmed jewel and hoping the tint hides it
		expect(ornament.kind).toBe("corners")
		expect(ornament.assetVariants.default.asset).toBe("pixel_blank")
		expect(ornament.assetVariants.selected.asset).toBe("pixel_plate_ornament")
		-- and the swap does not move the row: one reservation, both states
		expect(selection.contentInsets.left).toBe(16)
		expect(selection.contentInsets.top).toBe(16)
	end)
end)

describe("RS-A14 the platform pair is two snapshots, not two palettes", function()
	local function pair(): (any, any)
		return built("glossy_touch"), built("compact_pointer")
	end

	it("declares its two halves as data", function()
		expect(MODULES.glossy_touch.pairRole).toBe("touch")
		expect(MODULES.compact_pointer.pairRole).toBe("pointer")
		local touch, pointer = pair()
		expect(touch.identity.id ~= pointer.identity.id).toBe(true)
	end)

	it("METRICS move geometry on the swap: 44px rows against ~22px ones", function()
		local touch, pointer = pair()
		local t = themes.resolve(touch, nil, {})
		local p = themes.resolve(pointer, nil, {})
		expect(t.controlSizes.regular.height).toBe(44)
		expect(p.controlSizes.regular.height).toBe(24)
		expect(p.controlSizes.compact.height).toBe(22)
		-- everything a row is made of moves, not only its height
		expect(p.space.m < t.space.m).toBe(true)
		expect(p.type.body.size < t.type.body.size).toBe(true)
		expect(p.radii.panel < t.radii.panel).toBe(true)
		-- ...and the ACCESSIBILITY floor does not: a 22px pointer button is still
		-- a 44px hit target, because the framework clamps that up whatever a
		-- package asks for
		expect(p.targetSizes.minimum).toBe(44)
		expect(t.targetSizes.minimum).toBe(44)
	end)

	it("the compact half respects its art's minimum rendered sizes", function()
		-- provenance floors: 2*border must fit inside the rendered control, or the
		-- sliced centre rect is empty and the hairline identity is gone
		local _, pointer = pair()
		local snap = themes.resolve(pointer, nil, {})
		expect(snap.controls.progress.trackHeight >= 10).toBe(true) -- barTrack border 4
		expect(snap.controlSizes.compact.height >= 22).toBe(true) -- button border 8
		expect(snap.strokes.hairline).toBe(1) -- the identity: one physical pixel
		for _, asset in pointer.assets do
			expect(asset.sliceScale == nil or asset.sliceScale == 1).toBe(true)
		end
	end)

	it("hover art exists on the pointer half and NOT on the touch half", function()
		local touch, pointer = pair()
		expect(pointer.chrome.control.assetVariants.hover ~= nil).toBe(true)
		expect(touch.chrome.control.assetVariants.hover).toBeNil()
		-- a finger cannot hover, so the touch half falls back to `default` with
		-- the theme's tint rather than shipping art its platform can never show
		expect(touch.chrome.control.assetVariants.default ~= nil).toBe(true)
		expect(touch.chrome.control.assetVariants.pressed ~= nil).toBe(true)
	end)

	it("the STRIPE is a tile layer, and only the touch half has one", function()
		local touch, pointer = pair()
		local stack = touch.chrome.barTrack
		expect(stack.kind).toBe("layered")
		local tile = stack.layers[2]
		expect(tile.kind).toBe("tile")
		expect(tile.tileSize.w).toBe(24)
		expect(tile.tileSize.h).toBe(24)
		-- px offsets are the canonical authoring form (rs-m1 measured scale
		-- components as a fraction of the LABEL, which changes meaning on resize)
		local model = sheet_model.buildPackage(touch)
		expect(model.census.layersPerKind.tile).toBe(1)
		expect(sheet_model.buildPackage(pointer).census.layers).toBe(0)
	end)

	it("focus disagrees on purpose: a halo for the finger, a ring for the pointer", function()
		local touch, pointer = pair()
		expect(touch.chrome.focus.kind).toBe("glow")
		expect(pointer.chrome.focus.kind).toBe("ring")
	end)

	it("neither half maps an icon, so both draw the framework's ASCII glyph", function()
		local touch, pointer = pair()
		for _, pkg in { touch, pointer } do
			expect(pkg.icons).toBeNil()
			for _, name in { "increment", "decrement", "chevron.trailing" } do
				local resolved = themePackage.resolveIcon(pkg, name)
				expect(resolved.source).toBe("glyph")
				expect(themePackage.isSafeGlyph(resolved.glyph)).toBe(true)
			end
		end
	end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- RUNG 3: A CUSTOM SKINNED CONTROL (ADR-0020 R8, ledger row RS-A15)
--
-- `examples/themes/ornate_gauge.luau` is the worked example the customization
-- ladder ends on: a control the framework knows nothing about, which brings its
-- own three pictures and contributes three NAMESPACED theme roles — one of each
-- `checkCoverage` kind. The propositions worth testing are the ones that would
-- otherwise only be discovered on a device:
--
--   1. the declaration is complete and namespaced, and its `check` is the
--      framework gate rather than a second implementation that can drift;
--   2. a covering package makes the gauge follow the theme, and TWO different
--      packages give it two different answers (one package proves nothing);
--   3. an uncovering package produces a useful pre-play error AND a control that
--      still runs on its declared fallbacks;
--   4. the control reaches nothing private: it builds through `UI.*` only.
-- ─────────────────────────────────────────────────────────────────────────────
describe("rung 3: the OrnateGauge contributes namespaced roles and ships its own art", function()
	it("declares one need per contribution kind, all namespaced, all with fallbacks", function()
		expect(#ornateGauge.needs).toBe(3)
		local kinds: { [string]: boolean } = {}
		for _, need in ornateGauge.needs do
			expect(string.find(need.name, "gauge:", 1, true)).toBe(1)
			expect(need.authority == "layout" or need.authority == "paint").toBe(true)
			expect(need.capability).toBe("none")
			expect(need.fallback ~= nil).toBe(true)
			kinds[need.kind] = true
		end
		-- the whole vocabulary in one control, which is what makes it the example
		expect(kinds.controlSize).toBe(true)
		expect(kinds.color).toBe(true)
		expect(kinds.number).toBe(true)
	end)

	it("its `check` IS themes.checkCoverage — one gate, so the two cannot drift", function()
		for _, name in { "fantasy_ornate", "pixel_quest", "classic_desktop", "glossy_touch" } do
			local pkg = built(name)
			local own = ornateGauge.check(themes, pkg)
			local framework = themes.checkCoverage(pkg, ornateGauge.needs)
			expect(own.ok).toBe(framework.ok)
			expect(#own.covered).toBe(#framework.covered)
			expect(#own.missing).toBe(#framework.missing)
		end
	end)

	it("TWO covering packages give the gauge two different answers", function()
		local ornate, pixel = built("fantasy_ornate"), built("pixel_quest")
		for _, pkg in { ornate, pixel } do
			local result = ornateGauge.check(themes, pkg)
			expect(result.ok).toBe(true)
			expect(#result.covered).toBe(3)
			expect(#result.missing).toBe(0)
		end
		local a = ornateGauge.resolve(themes.resolve(ornate, nil, {}), ornate)
		local b = ornateGauge.resolve(themes.resolve(pixel, nil, {}), pixel)
		expect(a.usedFallback.size).toBe(false)
		expect(a.usedFallback.needle).toBe(false)
		expect(a.usedFallback.ring).toBe(false)
		expect(b.usedFallback.size).toBe(false)
		-- the point of re-theming: the SAME control resolves differently
		expect(a.height).toBe(ornate.metrics.controlSizes["gauge:dial"].height)
		expect(b.height).toBe(pixel.metrics.controlSizes["gauge:dial"].height)
		expect(a.height ~= b.height).toBe(true)
		expect(a.ring ~= b.ring).toBe(true)
		expect(a.needle.r ~= b.needle.r).toBe(true)
		-- ...and a per-THEME role is per theme, not per package
		local crypt = ornateGauge.resolve(themes.resolve(ornate, "Crypt", {}), ornate, "Crypt")
		expect(crypt.needle.r ~= a.needle.r).toBe(true)
	end)

	it("an UNCOVERING package produces a useful pre-play error, and the gauge still runs", function()
		local pkg = built("classic_desktop")
		local result = ornateGauge.check(themes, pkg)
		expect(result.ok).toBe(false)
		expect(#result.missing).toBe(3)
		for _, entry in result.missing do
			expect(string.find(entry.message, pkg.identity.id, 1, true) ~= nil).toBe(true)
			expect(string.find(entry.message, entry.name, 1, true) ~= nil).toBe(true)
			expect(#entry.fix > 0).toBe(true)
		end
		local resolved = ornateGauge.resolve(themes.resolve(pkg, nil, {}), pkg)
		expect(resolved.usedFallback.size).toBe(true)
		expect(resolved.usedFallback.needle).toBe(true)
		expect(resolved.usedFallback.ring).toBe(true)
		expect(resolved.height).toBe(ornateGauge.needs[1].fallback.height)
		expect(resolved.ring).toBe(ornateGauge.needs[3].fallback)
	end)

	it("its art is the control's own, published, and never a theme's asset", function()
		for _, id in ornateGauge.ART do
			expect(string.find(id, "rbxassetid://", 1, true)).toBe(1)
		end
		-- the packages that COVER the gauge cover its roles, not its pictures: a
		-- theme never names an asset of the control's
		for _, name in { "fantasy_ornate", "pixel_quest" } do
			local pkg = built(name)
			for _, id in ornateGauge.ART do
				for assetName, asset in pkg.assets do
					expect(asset.contentId == id).never().toBe(true)
					expect(type(assetName)).toBe("string")
				end
			end
		end
	end)
end)

-- ===========================================================================
-- DIRECTOR FINDING 12 (2026-07-26): a palette that lies about its own ART
-- ===========================================================================

describe("RS-DIR12: a package's selected palette colour is what its selected ART paints", function()
	-- THE DEFECT, reported as "the selected row is a dark plum plate with gold
	-- corners and the label is invisible against it" and root-caused live.
	--
	-- `sheet_model.selectedContentColor` resolves the SELECTED label's colour by
	-- contrast against `extra.controlSelected` — the colour the framework paints
	-- for a selected row when it has no art. A package that skins selection with
	-- a PICTURE makes that number a claim about the picture, and nothing checked
	-- it: fantasy-ornate declared a burnished gold `rgb(118, 90, 44)` while
	-- `ornate_selection_selected.png` paints a dark emerald field. Four of the
	-- five packages with image selection art were making a claim that was not
	-- true; only glossy-touch was honest, because round 8b measured it live.
	--
	-- No runtime check can see a PNG, so the truth is sampled at BUILD time by
	-- `tools/sample_plates.py` (the art lane's own precedent) into
	-- `assets/themes/plate-samples.json`, and re-hashed here so a re-cut texture
	-- that was never re-sampled fails as a test rather than drifting silently.
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local tokens = require("../src/tokens/tokens")

	local doc = serde.decode("json", fs.readFile("assets/themes/plate-samples.json"))

	local function rgb01(entry: any)
		return { r = entry.r / 255, g = entry.g / 255, b = entry.b / 255 }
	end
	local function n255(c: any): string
		return string.format(
			"rgb(%d, %d, %d)",
			math.floor(c.r * 255 + 0.5),
			math.floor(c.g * 255 + 0.5),
			math.floor(c.b * 255 + 0.5)
		)
	end
	local function lerp(a: any, b: any, t: number)
		return { r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t }
	end
	local function multiply(a: any, b: any)
		return { r = a.r * b.r, g = a.g * b.g, b = a.b * b.b }
	end
	local function distance(a: any, b: any): number
		return math.sqrt((a.r - b.r) ^ 2 + (a.g - b.g) ^ 2 + (a.b - b.b) ^ 2)
	end

	-- THE BAND. The declared colour is what the framework paints INSTEAD of the
	-- art (the `Selected row` rule, and the declared `fallback = "native"` when
	-- an asset fails), so the comparison is against what a player actually sees:
	-- the sample MULTIPLIED by `$ChromeTintSelected`, which is the tint every
	-- selected skinned plate carries. 0.12 in unit RGB is ~31/255 of Euclidean
	-- distance — close enough that the fallback reads as the same plate, wide
	-- enough that a re-cut texture does not have to be chased to the last bit.
	local BAND = 0.12
	local FLOOR = 4.5

	local function chromeTintSelected(theme: any)
		return lerp({ r = 1, g = 1, b = 1 }, theme.colors.accent, 0.35)
	end

	local WITH_SELECTION_ART = { "fantasy_ornate", "glossy_touch", "pixel_quest", "compact_pointer" }

	it("re-hashes every sampled PNG, so a stale sample is a failure and not a drift", function()
		local seen = 0
		for _, bySlot in doc.samples do
			for _, entry in bySlot do
				local actual = serde.hash("sha256", fs.readFile(entry.file))
				if actual ~= entry.sha256 then
					error(
						`plate sample for '{entry.asset}' is STALE: {entry.file} hashes {actual}, `
							.. `the sample records {entry.sha256}. Re-run tools/sample_plates.py.`,
						0
					)
				end
				expect(entry.alpha >= 0.9).toBe(true) -- an opaque plate, or the sample means nothing
				seen += 1
			end
		end
		expect(seen).toBe(9)
	end)

	it("every package whose SELECTION slot is image art declares that art's colour", function()
		for _, name in WITH_SELECTION_ART do
			local pkg = built(name)
			local sample = doc.samples[pkg.identity.id].selected
			expect(sample ~= nil).toBe(true)
			for _, theme in pkg.style.themes do
				local declared = sheet_model.selectedSurfaceOf({ colors = theme.colors, extra = theme.extra })
				local painted = multiply(rgb01(sample), chromeTintSelected(theme))
				local d = distance(declared, painted)
				if d > BAND then
					error(
						`{pkg.identity.id} / {theme.name}: extra.controlSelected is {n255(declared)} but `
							.. `'{sample.asset}' paints {n255(painted)} under this theme's $ChromeTintSelected `
							.. `(distance {string.format("%.3f", d)} > {BAND}). The selected label's colour is `
							.. "resolved against the declaration, so a declaration the art does not match "
							.. "pairs the label with a plate nobody sees.",
						0
					)
				end
			end
		end
	end)

	it("...and the label the resolver picks CLEARS the floor against the art, not just the token", function()
		-- the point of the whole check: `$OnSelected` is chosen against the
		-- declaration, so it is only a real legibility guarantee once the
		-- declaration is true. Assert it against the sampled plate.
		local pinned: { string } = {}
		for _, name in WITH_SELECTION_ART do
			local pkg = built(name)
			local sample = doc.samples[pkg.identity.id].selected
			for _, theme in pkg.style.themes do
				local styleLike = { colors = theme.colors, extra = theme.extra }
				local picked = sheet_model.selectedContentColor(styleLike)
				local painted = multiply(rgb01(sample), chromeTintSelected(theme))
				local ratio = tokens.contrastRatio(picked, painted)
				expect(ratio >= FLOOR).toBe(true)
				local isContent = picked.r == theme.colors.content.r and picked.g == theme.colors.content.g
				table.insert(
					pinned,
					`{pkg.identity.id}/{theme.name}={if isContent then "content" else "onAccent"}@{string.format(
						"%.1f",
						ratio
					)}`
				)
			end
		end
		table.sort(pinned)
		-- PINNED, so a silent flip shows up in a diff rather than only in a capture
		expect(table.concat(pinned, " ")).toBe(
			"compact-pointer/Aqua=content@8.9 fantasy-ornate/Crypt=content@7.8 "
				.. "fantasy-ornate/Grand Hall=content@8.3 glossy-touch/Sky=onAccent@6.3 "
				.. "pixel-quest/Quest=onAccent@6.0"
		)
	end)

	it("censuses the OTHER art-backed pairing — a primary label over a skinned control", function()
		-- THE CLASS THIS ROUND ALSO MEASURED, recorded rather than assumed.
		-- `surface = "accent"` promises the theme's accent FILL under `$OnAccent`
		-- text. On a skinned control the fill is replaced by ART that
		-- `Chrome role — accent` only MULTIPLIES toward the accent — and a
		-- multiply can never lighten — so the plate is not the accent and
		-- `$OnAccent` is not its partner. Measured live under fantasy-ornate: the
		-- lifted label resolved `$OnAccent` = rgb(32, 22, 8) over a plum plate,
		-- which is the director's invisible label.
		--
		-- Nothing in the library or the examples pairs `surface = "accent"` with a
		-- skinned control any more (the gallery picker's active chip declares
		-- `selected`, the framework's own state for "this is the chosen row"), so
		-- this is a census with pinned numbers rather than a gate: it is the
		-- instrument that would catch a package or an example re-entering the
		-- combination, and every number in it is a measurement.
		local rows: { string } = {}
		for _, name in { "fantasy_ornate", "glossy_touch", "pixel_quest", "compact_pointer", "fantasy_parchment" } do
			local pkg = built(name)
			local sample = doc.samples[pkg.identity.id].control
			for _, theme in pkg.style.themes do
				local plate = multiply(rgb01(sample), lerp(theme.colors.accent, { r = 1, g = 1, b = 1 }, 0.3))
				local onAccent = tokens.contrastRatio(theme.colors.onAccent, plate)
				local content = tokens.contrastRatio(theme.colors.content, plate)
				table.insert(
					rows,
					`{pkg.identity.id}/{theme.name} onAccent={string.format("%.2f", onAccent)} content={string.format(
						"%.2f",
						content
					)}`
				)
				-- SOME content role must be able to read on the accent-tinted art,
				-- or the package has published a primary action nobody could read
				expect(math.max(onAccent, content) >= FLOOR).toBe(true)
			end
		end
		table.sort(rows)
		expect(#rows).toBe(7)
		expect(table.concat(rows, " | ")).toBe(
			"compact-pointer/Aqua onAccent=3.64 content=4.60 | "
				.. "fantasy-ornate/Crypt onAccent=1.09 content=13.84 | "
				.. "fantasy-ornate/Grand Hall onAccent=1.06 content=14.09 | "
				.. "fantasy-parchment/Candlelight onAccent=5.28 content=2.68 | "
				.. "fantasy-parchment/Daylight onAccent=5.29 content=2.47 | "
				.. "glossy-touch/Sky onAccent=4.57 content=3.65 | "
				.. "pixel-quest/Quest onAccent=2.43 content=6.11"
		)
	end)
end)

describe("RS-DIR12: the picker's active row is a SELECTION, not a borrowed fill", function()
	local fs = require("@lune/fs")
	local source = fs.readFile("examples/gallery/client/theme_picker.luau")

	it("declares `selected`, the framework's own state, and keeps one surface", function()
		-- `surface = "accent"` is a promise about a FILL. Under a skinned package
		-- the fill is replaced by chrome art, so the promise is void while its
		-- `$OnAccent` label colour is still applied — measured live under
		-- fantasy-ornate as near-black text on a dark plum plate.
		--
		-- `selected` is the state the framework already models end to end: it
		-- routes the node to the package's own `selection` chrome slot (so ornate
		-- paints the plate it cut for exactly this), tints it with
		-- `$ChromeTintSelected`, and pairs its label with `$OnSelected`, which the
		-- sweep above holds to the art.
		expect(string.find(source, "selected = ", 1, true) ~= nil).toBe(true)
		expect(string.find(source, 'return if use(isActive) then "accent" else "chip"', 1, true)).toBeNil()
	end)
end)
