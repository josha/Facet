--!strict
-- CHROME MODEL + DECORATION SLOTS (ADR-0019 §5, package 3).
--
-- Three propositions, each of which is only worth anything if it can fail:
--   1. `sheet_model.buildPackage` compiles a package's chrome to rules whose
--      VALUES equal the package data — a rule set that merely exists proves
--      nothing about the skin it paints;
--   2. an inert pseudo selector is a COMPILE error, not a silent no-op, which
--      is the whole reason the m7 probe was run;
--   3. a flat theme creates zero decoration instances, an ornate one creates
--      exactly one per slotted node, and the asset-failure tag flips once in
--      each direction.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local sheet_model = require("../src/tokens/sheet_model")
local chrome_slots = require("../src/tokens/chrome_slots")
local chrome_props = require("../src/tokens/chrome_props")
local fake_target = require("./lib/fake_target")

local themes = LuauUI.themes
local parchmentModule = require("../examples/themes/fantasy_parchment_stub")
local classicModule = require("../examples/themes/classic_desktop")
local scifiModule = require("../examples/themes/scifi_hud")
local fs = require("@lune/fs")
local adapterChromeSource = fs.readFile("src/client/screen_chrome.luau")

local function parchment(): any
	local pkg = parchmentModule.build(themes)
	assert(pkg ~= nil, "fantasy_parchment_stub must compile")
	return pkg
end
local function classic(): any
	local pkg = classicModule.build(themes)
	assert(pkg ~= nil, "classic_desktop must compile")
	return pkg
end
-- the SHIPPING Fantasy Parchment (the stub above is the minimal chrome
-- fixture). The director fix round's new slots — sliderTrack, sliderThumb,
-- badge — and the slot shadows live here, so the assertions about them have to
-- read the package a player would actually get.
local shippingModule = require("../examples/themes/fantasy_parchment")
local function shipping(): any
	local pkg = shippingModule.build(themes)
	assert(pkg ~= nil, "fantasy_parchment must compile")
	return pkg
end

local function ruleNamed(model: any, name: string): any
	for _, rule in model.rules do
		if rule.name == name then
			return rule
		end
	end
	return nil
end

describe("buildPackage: nine-slice chrome rules carry the package's own values", function()
	it("emits all six image properties on the slot tag, value-exact", function()
		local pkg = parchment()
		local model = sheet_model.buildPackage(pkg)
		local rule = ruleNamed(model, "Chrome — panel")
		expect(rule ~= nil).toBe(true)
		expect(rule.selector).toBe(".luau-chrome-panel")
		local asset = pkg.assets.parchment_panel
		expect(rule.props.Image).toBe(asset.contentId)
		expect(rule.props.ScaleType.kind).toBe("enum")
		expect(rule.props.ScaleType.enum).toBe("ScaleType")
		expect(rule.props.ScaleType.item).toBe("Slice")
		expect(rule.props.SliceCenter.kind).toBe("rect")
		expect(rule.props.SliceCenter.x0).toBe(asset.sliceCenter.x0)
		expect(rule.props.SliceCenter.y1).toBe(asset.sliceCenter.y1)
		expect(rule.props.SliceScale.value).toBe(asset.sliceScale)
		expect(rule.props.ImageColor3).toBe("$ChromeTint")
		expect(rule.props.ImageTransparency.value).toBe(0)
	end)

	it("modulates ONE base image per state instead of naming a second asset", function()
		local model = sheet_model.buildPackage(parchment())
		local base = ruleNamed(model, "Chrome — control")
		for _, name in { "Chrome — control hover", "Chrome — control pressed", "Chrome — control selected" } do
			local rule = ruleNamed(model, name)
			expect(rule ~= nil).toBe(true)
			-- the state rules touch tint/alpha ONLY: no Image, no SliceCenter
			expect(rule.props.Image).toBeNil()
			expect(rule.props.SliceCenter).toBeNil()
			expect(rule.props.ImageColor3 ~= nil or rule.props.ImageTransparency ~= nil).toBe(true)
		end
		-- the state selectors read GuiState from the PARENT through the child
		-- combinator; the decoration is Active=false and has no state of its own
		expect(ruleNamed(model, "Chrome — control hover").selector).toBe(
			".luau-interactive.luau-pointer-live:Hover > .luau-chrome-control"
		)
		expect(ruleNamed(model, "Chrome — control pressed").selector).toBe(
			".luau-interactive:Press > .luau-chrome-control"
		)
		expect(ruleNamed(model, "Chrome — control disabled").selector).toBe(":NonInteractable > .luau-chrome-control")
		expect(base.props.Image).toBe(parchment().assets.parchment_button.contentId)
	end)

	it("the declared native fallback paints the slot when the asset fails", function()
		local model = sheet_model.buildPackage(parchment())
		local rule = ruleNamed(model, "Chrome — panel fallback")
		expect(rule.selector).toBe(".luau-chrome-panel.luau-chrome-fallback")
		-- THE FILL AND THE HIDE ARE TWO RULES ON TWO TAGS (RS-A16-D5). The fill
		-- lands on every art instance of a fallen-back slot; the hide lands only on
		-- the ones whose own asset is NOT the failed one, because
		-- `ImageTransparency = 1` is the engine's "do not decode" signal and using
		-- it on the condemned art destroyed the only instrument that could report
		-- its recovery.
		expect(rule.props.ImageTransparency).toBeNil()
		local hide = ruleNamed(model, "Chrome — panel fallback hide")
		expect(hide.selector).toBe(".luau-chrome-panel.luau-chrome-mute")
		expect(hide.props.ImageTransparency.value).toBe(1)
		expect(rule.props.BackgroundColor3).toBe("$SurfaceStrong")
		expect(rule.props.BackgroundTransparency.value).toBe(0)
		expect(ruleNamed(model, "Chrome — panel fallback corner").props.CornerRadius.offset).toBe(
			parchment().metrics.radii.panel
		)
	end)

	it("a flat package emits no chrome rules BUT the framework icon tints", function()
		-- the framework's own icon set (compact-label stage) resolves BELOW a package's map, so a package that declares nothing still DRAWS pictures — and `ImageColor3` is sheet-owned, so each of those names needs its tint rule or the art paints pure white. Found live in the running showcase: Studio Neutral emitted 70 rules and ZERO icon rules while `resolveIcon` returned real art for the same names.
		-- So "flat pays nothing" now has exactly one exception, and naming it here
		-- is what keeps it an exception rather than a leak: any OTHER chrome
		-- selector on a flat package is still a defect.
		local model = sheet_model.buildPackage(classic())
		local icons = 0
		for _, rule in model.rules do
			if string.find(rule.selector, chrome_slots.ICON_TAG_PREFIX, 1, true) ~= nil then
				icons += 1
			else
				expect(string.find(rule.selector, "luau-chrome-", 1, true) == nil).toBe(true)
			end
		end
		expect(icons > 0).toBe(true)
	end)
end)

describe("buildPackage: gradients are phantom rules, not decoration children", function()
	it("emits a ::UIGradient rule per declared slot with per-theme tokens", function()
		local pkg = scifiModule.build(themes)
		local model = sheet_model.buildPackage(pkg)
		local rule = ruleNamed(model, "Gradient — panel")
		expect(rule ~= nil).toBe(true)
		expect(rule.selector).toBe(".luau-surface-raised::UIGradient")
		expect(rule.props.Color).toBe("$GradientPanel")
		expect(rule.props.Rotation).toBe("$GradientPanelRotation")
		expect(rule.props.Transparency).toBe("$GradientPanelAlpha")
		-- and the token it names really exists on the theme, as a sequence
		local theme = model.themes[1]
		expect(theme.tokens.GradientPanel.kind).toBe("colorseq")
		expect(#theme.tokens.GradientPanel.stops).toBe(3)
		expect(theme.tokens.GradientPanelRotation.value).toBe(115)
		expect(theme.tokens.GradientPanelAlpha.kind).toBe("numseq")
		-- a gradient costs ZERO decoration instances
		expect(chrome_slots.planFor(pkg, "panel")).toBeNil()
	end)

	it("every theme carries a token for every gradient slot, so a swap cannot blank a rule", function()
		-- classic declares no gradient; give it one on ONE theme only and check
		-- the other theme still resolves
		local def = classicModule.definition(themes)
		def.style.themes[1].extra = table.clone(def.style.themes[1].extra)
		def.style.themes[1].extra.chromeGradient = {
			control = { rotation = 45, stops = { { t = 0, r = 1, g = 0, b = 0 }, { t = 1, r = 0, g = 0, b = 1 } } },
		}
		local pkg = themes.define(def)
		assert(pkg ~= nil, "the gradient variant must compile")
		local model = sheet_model.buildPackage(pkg)
		expect(model.themes[1].tokens.GradientControl.stops[1].r).toBe(1)
		-- the theme that declared nothing gets an INERT flat-white ramp, never a
		-- missing attribute (a `$Token` that resolves in one theme and not the
		-- other is a rule that stops painting on a swap)
		local silent = model.themes[2].tokens.GradientControl
		expect(silent.kind).toBe("colorseq")
		expect(silent.stops[1].r).toBe(1)
		expect(silent.stops[2].b).toBe(1)
		expect(model.themes[2].tokens.GradientControlRotation.value).toBe(0)
	end)
end)

describe("buildPackage: the pseudo-selector allowlist", function()
	it("accepts the three proven phantom modifiers", function()
		for _, pseudo in { "UICorner", "UIStroke", "UIGradient" } do
			expect(sheet_model.checkSelector(`.x::{pseudo}`, "probe")).toBe(`.x::{pseudo}`)
		end
	end)

	it("rejects ::UIShadow with a message naming the m7 evidence", function()
		local ok, err = pcall(function()
			sheet_model.checkSelector(".panel::UIShadow", "Panel shadow")
		end)
		expect(ok).toBe(false)
		local message = tostring(err)
		expect(string.find(message, "UIShadow", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "paints nothing", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "m7-gradient-shadow-phantoms", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "Panel shadow", 1, true) ~= nil).toBe(true)
	end)

	it("rejects any other pseudo selector, naming it", function()
		local ok, err = pcall(function()
			sheet_model.checkSelector(".panel::UIListLayout", "Panel layout")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "UIListLayout", 1, true) ~= nil).toBe(true)
	end)

	it("an author-supplied rule goes through the same gate", function()
		local ok = pcall(function()
			sheet_model.buildPackage(classic(), {
				rules = { { name = "Custom shadow", selector = ".luau-surface-raised::UIShadow", props = {} } },
			})
		end)
		expect(ok).toBe(false)
		-- ...and through the §4 property linter
		local okProp, errProp = pcall(function()
			sheet_model.buildPackage(classic(), {
				rules = { { name = "Themed size", selector = ".luau-surface-raised", props = { Size = "$Nope" } } },
			})
		end)
		expect(okProp).toBe(false)
		expect(string.find(tostring(errProp), "authority", 1, true) ~= nil).toBe(true)
	end)
end)

describe("buildPackage: cascade discipline", function()
	it("priority is index * 10 and the groups run base -> ... -> disabled", function()
		local model = sheet_model.buildPackage(parchment())
		local seen: { string } = {}
		for index, rule in model.rules do
			expect(rule.priority).toBe(index * 10)
			if seen[#seen] ~= rule.group then
				table.insert(seen, rule.group)
			end
		end
		expect(table.concat(seen, ",")).toBe("base,surfaces,roles,chrome,hover,press,disabled")
	end)

	it("chrome resting paint sits after the roles it must not lose to, and before the states", function()
		local model = sheet_model.buildPackage(parchment())
		local index: { [string]: number } = {}
		for i, rule in model.rules do
			index[rule.name] = i
		end
		expect(index["Chrome — control"] > index["Selected row"]).toBe(true)
		expect(index["Chrome — control"] < index["Chrome — control hover"]).toBe(true)
		expect(index["Chrome — control hover"] < index["Chrome — control pressed"]).toBe(true)
		expect(index["Chrome — control pressed"] < index["Chrome — control disabled"]).toBe(true)
		-- the fallback overrides the resting image; the selected tint overrides both
		expect(index["Chrome — control fallback"] > index["Chrome — control"]).toBe(true)
		expect(index["Chrome — control selected"] > index["Chrome — control fallback"]).toBe(true)
	end)

	it("the stamp moves with the package and is deterministic", function()
		local a = sheet_model.buildPackage(parchment())
		local b = sheet_model.buildPackage(parchment())
		expect(a.stamp).toBe(b.stamp)
		local bad = parchmentModule.buildBadAsset(themes)
		expect(sheet_model.buildPackage(bad).stamp ~= a.stamp).toBe(true)
	end)

	it("the legacy build() path is untouched by the package path", function()
		local defaultStyle = require("../src/tokens/default_style")
		local legacy = sheet_model.build({ themes = { { name = "Dark", style = defaultStyle } } })
		expect(legacy.rules[1].priority).toBeNil()
		expect(legacy.rules[1].group).toBeNil()
	end)
end)

-- ===== RS-DIR6-F1 (director round 6, live-found) ===========================
--
-- A node in the asset-FALLBACK state still took the `:NonInteractable`
-- `ImageTransparency = 0.4` rule, which re-revealed the broken art the fallback
-- had hidden — at 60% opacity, over the native fill and rounded phantom corner
-- that had replaced it. The two rules write the SAME property and the cascade is
-- Priority first, then insertion order, with no selector specificity: the
-- fallback rule rode the `chrome` group and the disabled rule rides `disabled`,
-- so the dim won.
describe("a fallback node stays hidden in EVERY state (RS-DIR6-F1)", function()
	local function index(model: any): { [string]: number }
		local out: { [string]: number } = {}
		for i, rule in model.rules do
			out[rule.name] = i
		end
		return out
	end

	it("the hide is re-asserted ABOVE the disabled dim, on the same property", function()
		local model = sheet_model.buildPackage(parchment())
		local i = index(model)
		-- the defect, stated as an ordering: this used to be false
		expect(i["Chrome — control fallback over states"] > i["Chrome — control disabled"]).toBe(true)
		-- ...and the pinned Priority says the same thing, which is what the engine
		-- actually reads (ADR-0018 syncPriorities)
		local hide = ruleNamed(model, "Chrome — control fallback over states")
		local dim = ruleNamed(model, "Chrome — control disabled")
		expect(hide.priority > dim.priority).toBe(true)
		-- on the MUTE tag since RS-A16-D5: a disabled node must not re-reveal art a
		-- healthy-sibling mute is hiding, and art whose own asset failed is not
		-- hidden in the first place
		expect(hide.selector).toBe(".luau-chrome-control.luau-chrome-mute")
		expect(hide.props.ImageTransparency.value).toBe(1)
		expect(dim.props.ImageTransparency.value ~= 1).toBe(true)
	end)

	it("it carries the HIDE and nothing else — the fill and corner stay the chrome rule's", function()
		local model = sheet_model.buildPackage(parchment())
		local hide = ruleNamed(model, "Chrome — panel fallback over states")
		local props: { string } = {}
		for prop in hide.props do
			table.insert(props, prop)
		end
		expect(#props).toBe(1)
		expect(props[1]).toBe("ImageTransparency")
		-- the native fill the fallback paints is untouched and still readable
		local base = ruleNamed(model, "Chrome — panel fallback")
		expect(base.props.BackgroundColor3).toBe("$SurfaceStrong")
		expect(base.props.BackgroundTransparency.value).toBe(0)
		expect(ruleNamed(model, "Chrome — panel fallback corner") ~= nil).toBe(true)
	end)

	it("every skinned slot gets it, and a flat package still emits none of it", function()
		local model = sheet_model.buildPackage(shipping())
		local covered = 0
		for _, rule in model.rules do
			if string.find(rule.name, " fallback over states", 1, true) ~= nil then
				covered += 1
				expect(rule.props.ImageTransparency.value).toBe(1)
				expect(string.find(rule.selector, chrome_slots.TAGS.mute, 1, true) ~= nil).toBe(true)
			end
		end
		-- one per tag that has a disabled dim, i.e. every decoration the package
		-- actually skins
		local dims = 0
		for _, rule in model.rules do
			if string.find(rule.name, " disabled", 1, true) ~= nil and rule.props.ImageTransparency ~= nil then
				dims += 1
			end
		end
		expect(covered > 0).toBe(true)
		expect(covered).toBe(dims)
		local flat = sheet_model.buildPackage(classic())
		for _, rule in flat.rules do
			expect(string.find(rule.name, " fallback over states", 1, true) == nil).toBe(true)
		end
	end)
end)

describe("chrome_props: the kinds the Step 2 vocabulary lacked", function()
	it("rects and sequences describe canonically and sort their stops", function()
		local rect = chrome_props.rect(4, 6, 20, 22)
		expect(chrome_props.describe(rect)).toBe("rect(4.0000,6.0000,20.0000,22.0000)")
		local seq = chrome_props.colorSeq({ { t = 1, r = 0, g = 0, b = 1 }, { t = 0, r = 1, g = 0, b = 0 } })
		expect(seq.stops[1].t).toBe(0)
		expect(seq.stops[2].t).toBe(1)
		expect(chrome_props.isChromeKind(seq)).toBe(true)
		expect(chrome_props.isChromeKind({ kind = "color", r = 1, g = 1, b = 1 })).toBe(false)
	end)

	it("rejects a degenerate slice centre rather than shipping a skin that is wrong at every other size", function()
		expect(function()
			chrome_props.rect(10, 10, 10, 20)
		end).toThrow()
	end)

	it("materialize reports 'not handled' headlessly instead of crashing", function()
		local handled = chrome_props.materialize(chrome_props.rect(1, 1, 2, 2))
		expect(handled).toBe(false) -- no engine here: the MODEL is what a headless test asserts
		expect((chrome_props.materialize({ kind = "color", r = 1, g = 1, b = 1 }))).toBe(false)
	end)
end)

describe("chrome_slots: classification", function()
	it("maps the renderer's existing hints to the ADR-0019 slot vocabulary", function()
		local cases = {
			{ input = { class = "Divider" }, slot = "divider" },
			{ input = { class = "ScrollView" }, slot = "scrollbar" },
			{ input = { class = "TextField", surface = "control" }, slot = "field" },
			{ input = { class = "Button", hasSelection = true }, slot = "selection" },
			{ input = { class = "Box", surface = "raised" }, slot = "panel" },
			{ input = { class = "Box", surface = "control" }, slot = "control" },
			{ input = { class = "Box", surface = "chip" }, slot = "control" },
			{ input = { class = "Button" }, slot = "control" },
			{ input = { class = "Toggle" }, slot = "control" },
		}
		for _, case in cases do
			expect(chrome_slots.classify(case.input)).toBe(case.slot)
		end
	end)

	it("the backdrop, the scrim and chrome-less nodes get NO decoration", function()
		for _, surface in { "base", "scrim", "plain" } do
			expect(chrome_slots.classify({ class = "Box", surface = surface })).toBeNil()
		end
		expect(chrome_slots.classify({ class = "Text" })).toBeNil()
		expect(chrome_slots.classify({})).toBeNil()
	end)

	it("a badge classifies into the badge slot, and costs nothing until a package skins it", function()
		-- director fix round: "values like '3' unreadable". A badge is now a
		-- decoration slot — but classification alone creates NOTHING: a package
		-- with no badge recipe keeps the native circle exactly as before.
		expect(chrome_slots.classify({ class = "Text", surface = "badge" })).toBe("badge")
		-- ...but an IMAGE badge (an avatar headshot) is excluded: it already IS
		-- art, and the decoration would draw a seal on top of the face
		expect(chrome_slots.classify({ class = "Image", surface = "badge" })).toBeNil()
		expect(chrome_slots.planFor(classic(), "badge")).toBeNil()
		expect(chrome_slots.planFor(themes.neutralPackage(), "badge")).toBeNil()
		expect(chrome_slots.planFor(parchment(), "badge")).toBeNil() -- the stub skins no badge
		expect(chrome_slots.planFor(shipping(), "badge") ~= nil).toBe(true)
	end)

	it("an explicit slot HINT beats every generic classification, and a bad one is an error", function()
		-- a Slider's rail declares surface="control" for its flat paint; without
		-- the hint it would take the BUTTON skin, i.e. a button plate stretched
		-- into a groove
		expect(chrome_slots.classify({ class = "Box", surface = "control" })).toBe("control")
		expect(chrome_slots.classify({ class = "Box", surface = "control", hint = "sliderTrack" })).toBe("sliderTrack")
		expect(chrome_slots.classify({ class = "Box", surface = "raised", hint = "sliderThumb" })).toBe("sliderThumb")
		expect(function()
			chrome_slots.classify({ class = "Box", hint = "notASlot" })
		end).toThrow()
		-- and a control can say "NOT a decoration surface" explicitly: the
		-- Slider's accent FILL classified as `control`, so an ornate package
		-- painted a stretched button plate over the filled portion of the bar
		expect(chrome_slots.classify({ class = "Box", surface = "accent", hint = chrome_slots.NO_SLOT })).toBeNil()
	end)

	it("the hint round-trips through the blueprint's internal meta channel", function()
		local UI = LuauUI.UI
		local box = UI.Box({ id = "Rail", surface = "control" })
		expect(chrome_slots.readHint(box)).toBeNil()
		local hinted = chrome_slots.attachHint(box, { slot = "sliderTrack", image = "rbxassetid://1" })
		-- the ORIGINAL blueprint is untouched (blueprints are immutable)
		expect(chrome_slots.readHint(box)).toBeNil()
		expect(chrome_slots.readHint(hinted).slot).toBe("sliderTrack")
		expect(chrome_slots.readHint(hinted).image).toBe("rbxassetid://1")
		expect(hinted.props).toBe(box.props) -- and it is NOT a public prop
		-- a non-table under the reserved key reads as "no hint", never a fault
		expect(chrome_slots.readHint({ meta = { decoration = "nope" } })).toBeNil()
		expect(function()
			chrome_slots.attachHint(box, { slot = "notASlot" })
		end).toThrow()
	end)

	it("a field stays a field even when it declares a selection binding", function()
		expect(chrome_slots.classify({ class = "TextField", hasSelection = true })).toBe("field")
	end)
end)

describe("chrome_slots: the plan and the preload policy", function()
	it("a native recipe plans NOTHING; a nineSlice recipe plans exactly one image", function()
		local pkg = parchment()
		expect(chrome_slots.planFor(pkg, "selection")).toBeNil()
		expect(chrome_slots.planFor(pkg, "divider")).toBeNil()
		local plan = chrome_slots.planFor(pkg, "field")
		expect(plan.tag).toBe("luau-chrome-field")
		expect(plan.contentId).toBe(pkg.assets.parchment_field.contentId)
		expect(plan.contentInsets.left).toBe(pkg.chrome.field.contentInsets.left)
		expect(plan.preload).toBe("lazy")
	end)

	it("splits the preload set by declared policy", function()
		local pkg = parchment()
		local install = chrome_slots.assetsToPreload(pkg, "install")
		local lazy = chrome_slots.assetsToPreload(pkg, "lazy")
		expect(#install).toBe(2)
		expect(#lazy).toBe(1)
		expect(lazy[1].name).toBe("parchment_field")
		expect(#chrome_slots.assetsToPreload(classic(), "install")).toBe(0)
	end)

	it("a nineSlice recipe whose asset declares no sliceCenter is an authoring error", function()
		local def = parchmentModule.definition(themes)
		def.assets.parchment_panel.sliceCenter = nil
		local pkg = themes.define(def)
		assert(pkg ~= nil, "the package still compiles: sliceCenter shape is the chrome compiler's rule")
		expect(function()
			chrome_slots.planFor(pkg, "panel")
		end).toThrow()
	end)
end)

describe("chrome_slots: the census and the fallback ledger", function()
	local function fixtureNodes(): { any }
		-- the REAL all-controls fixture, mounted headlessly: the census below is
		-- over what the framework actually renders, not a hand-written list
		local scenario = require("../examples/gallery/scenarios/adaptive_controls") :: any
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, system)
		local built = scenario.build({
			LuauUI = LuauUI,
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			actionSystem = system,
		})
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		local nodes: { any } = {}
		for _, path in adapter.paths() do
			local node = adapter.node(path)
			table.insert(nodes, {
				class = node.class,
				surface = node.props.surface,
				hasSelection = node.props.selected ~= nil,
			})
		end
		presenter.dismiss(handle)
		built.dispose()
		return nodes
	end

	it("a flat theme costs zero decoration instances over the whole fixture", function()
		local nodes = fixtureNodes()
		expect(#nodes).toBeGreaterThan(40)
		expect(chrome_slots.censusOf(classic(), nodes).total).toBe(0)
		expect(chrome_slots.censusOf(scifiModule.build(themes), nodes).total).toBe(0)
		expect(chrome_slots.censusOf(themes.neutralPackage(), nodes).total).toBe(0)
	end)

	it("an ornate theme costs exactly one instance per slotted node, and only for slotted slots", function()
		local nodes = fixtureNodes()
		local census = chrome_slots.censusOf(parchment(), nodes)
		expect(census.total).toBeGreaterThan(0)
		-- parchment skins panel/control/field only
		expect(census.perSlot.selection).toBeNil()
		expect(census.perSlot.divider).toBeNil()
		expect(census.perSlot.scrollbar).toBeNil()
		local summed = 0
		for _, n in census.perSlot do
			summed += n
		end
		expect(summed).toBe(census.total)
		-- and it equals the number of nodes the classifier put in a skinned slot
		local expected = 0
		for _, node in nodes do
			local slot = chrome_slots.classify(node)
			if slot == "panel" or slot == "control" or slot == "field" then
				expected += 1
			end
		end
		expect(census.total).toBe(expected)
	end)

	it("the badge slot is reachable from the PUBLIC API and lands on the real fixture", function()
		-- The seam this proves: `UI.Text{ surface = "badge" }` is constructible at
		-- all (it was not — the slot shipped with no authoring path, so the
		-- director's unreadable "3" could not be fixed by authoring), it survives
		-- the mount into the adapter's node props, and it classifies into the slot
		-- the shipping package skins.
		local nodes = fixtureNodes()
		local badges = 0
		for _, node in nodes do
			if node.surface == "badge" then
				badges += 1
				expect(node.class).toBe("Text")
			end
		end
		expect(badges).toBe(4) -- the four badged tiles
		-- the SHIPPING package declares a badge recipe, so each one costs exactly
		-- one decoration...
		local ornate = chrome_slots.censusOf(shipping(), nodes)
		expect(ornate.perSlot.badge).toBe(badges)
		-- ...and every flat package still costs nothing at all for them
		expect(chrome_slots.censusOf(classic(), nodes).perSlot.badge).toBeNil()
		expect(chrome_slots.censusOf(themes.neutralPackage(), nodes).perSlot.badge).toBeNil()
		-- the stub skins no badge either, which is why the counts above it hold
		expect(chrome_slots.censusOf(parchment(), nodes).perSlot.badge).toBeNil()
	end)

	it("the fallback tag flips once on failure and once on recovery, and never twice", function()
		local state = chrome_slots.newState(parchment())
		expect(state.isFallback("panel")).toBe(false)
		expect(state.setAssetLoaded("parchment_panel", false)).toBe(true)
		expect(state.isFallback("panel")).toBe(true)
		-- the same failure reported again is NOT a second flip
		expect(state.setAssetLoaded("parchment_panel", false)).toBe(false)
		expect(state.setAssetLoaded("parchment_panel", true)).toBe(true)
		expect(state.isFallback("panel")).toBe(false)
		expect(state.setAssetLoaded("parchment_panel", true)).toBe(false)
	end)

	it("a failure is per ASSET, so only the slots that use it fall back", function()
		local state = chrome_slots.newState(parchment())
		state.setAssetLoaded("parchment_panel", false)
		expect(state.isFallback("panel")).toBe(true)
		expect(state.isFallback("control")).toBe(false)
		expect(state.census().failedAssets[1]).toBe("parchment_panel")
		expect(state.census().fallbackSlots[1]).toBe("panel")
	end)

	it("the census counts creations and destructions, so a leak is visible", function()
		local state = chrome_slots.newState(parchment())
		state.noteCreated("panel")
		state.noteCreated("panel")
		state.noteCreated("control")
		state.noteDestroyed("panel")
		local census = state.census()
		expect(census.created).toBe(3)
		expect(census.destroyed).toBe(1)
		expect(census.live).toBe(2)
		expect(census.perSlot.panel.live).toBe(1)
	end)

	it("a palette-only swap reports NO chrome change, so no instance churns", function()
		local state = chrome_slots.newState(classic())
		-- the same package, a different theme: identical recipes
		expect(state.setPackage(classic())).toBe(false)
		expect(state.setPackage(parchment())).toBe(true)
		expect(state.setPackage(parchment())).toBe(false)
		expect(state.setPackage(nil)).toBe(true)
	end)

	it("swapping packages clears a stale failure ledger", function()
		local state = chrome_slots.newState(parchment())
		state.setAssetLoaded("parchment_panel", false)
		expect(state.isFallback("panel")).toBe(true)
		state.setPackage(classic())
		expect(#state.census().failedAssets).toBe(0)
	end)
end)

describe("decoration content insets reach the solver", function()
	it("a nineSlice recipe's insets ride the snapshot separately from the slot's own padding", function()
		local pkg = parchment()
		local snap = themes.resolve(pkg, nil, {})
		-- the SUM is what the slot reserves...
		expect(snap.insets.panel.top).toBe(pkg.metrics.insets.panel.top + pkg.chrome.panel.contentInsets.top)
		-- ...and the chrome-only portion is what the renderer adds to padding
		expect(snap.chromeInsets.panel.top).toBe(pkg.chrome.panel.contentInsets.top)
		-- a native slot ANSWERS, and its answer is zero. (It used to be absent;
		-- every slot now publishes an inset so a control can read one as a theme
		-- metric — see snapshot.resolve. "Reserves nothing" is the number, not the
		-- key's absence, which is the stronger claim anyway.)
		expect(snap.chromeInsets.selection.top).toBe(0)
		expect(snap.chromeInsets.selection.left).toBe(0)
	end)

	it("a flat package reserves ZERO on every slot, so existing geometry is untouched", function()
		-- and it says so in one word, which is what the renderer's per-node cheap
		-- exit reads: a table full of zeros is not distinguishable from a table
		-- full of insets by SHAPE any more.
		for _, snap in { themes.neutral(), themes.resolve(classic(), nil, {}) } do
			expect(snap.hasChromeInsets).toBe(false)
			local slots = 0
			for _, sides in snap.chromeInsets do
				slots += 1
				expect(sides.top).toBe(0)
				expect(sides.right).toBe(0)
				expect(sides.bottom).toBe(0)
				expect(sides.left).toBe(0)
			end
			expect(slots > 0).toBe(true) -- every slot answers, none is missing
		end
	end)

	it("the renderer adds the chrome insets to a slotted node's padding, and nothing else", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, system)
		local UI = LuauUI.UI
		local screen = UI.Screen({
			id = "InsetProbe",
			children = {
				UI.VStack({
					id = "Panel",
					surface = "raised",
					width = { type = "fixed", px = 300 },
					children = { UI.Text({ id = "Inner", text = "x" }) },
				}),
			},
		})
		local handle = presenter.present(screen)
		presenter.refresh()
		local flatInner = adapter.node("/InsetProbe/Panel/Inner").rect
		-- swap in the ornate package: the panel's content moves in by exactly
		-- the recipe's left inset, with no rebuild
		env:set("themeMetrics", themes.resolve(parchment(), nil, {}))
		presenter.refresh()
		local ornateInner = adapter.node("/InsetProbe/Panel/Inner").rect
		expect(ornateInner.x - flatInner.x).toBe(parchment().chrome.panel.contentInsets.left)
		expect(adapter.node("/InsetProbe/Panel").rect.w).toBe(300) -- the box itself is unchanged
		presenter.dismiss(handle)
	end)
end)

-- ===== A LAYERED RECIPE RESERVES ITS INSETS TOO (director round 7) =========
--
-- THE DEFECT. `snapshot.resolve` published `chromeInsets` for `kind ==
-- "nineSlice"` only, while the ADAPTER boxes a decorated node's lifted label by
-- `contentInsets` for a LAYERED recipe as well (`chrome_slots.liftGeometry`, fed
-- the stack plan). So a layered package's insets were applied at PAINT and
-- reserved by NOBODY.
--
-- Measured live under fantasy-ornate, whose `control` is a two-layer stack with
-- `contentInsets = { top = 10, right = 14, bottom = 10, left = 14 }`: the
-- toolbar's content-sized "Play" button solved to **48x47** while the adapter's
-- UIPadding (12 each side) plus those insets (14 each side) come to 52 — so the
-- lift resolved to **-4 x 27**, a NEGATIVE box, and the label was not clipped
-- but absent. The wide buttons in the same package were the same defect with a
-- survivable sign: a lift 28px narrower than the box the solver measured for.
--
-- It surfaced now because of the zero-slack property the round-5 packet
-- recorded: once a content button measures exactly its engine bounds, an inset
-- applied at paint and not at measure has nowhere left to hide.
describe("a LAYERED recipe's content insets reach the solver too", function()
	local ornateModule = require("../examples/themes/fantasy_ornate")
	local function ornate(): any
		local pkg = ornateModule.build(themes)
		assert(pkg ~= nil, "fantasy_ornate must compile")
		return pkg
	end

	it("the snapshot publishes them for a layered slot, not only a nineSlice one", function()
		local pkg = ornate()
		local snap = themes.resolve(pkg, nil, {})
		expect(pkg.chrome.control.kind).toBe("layered")
		local declared = pkg.chrome.control.contentInsets
		expect(snap.chromeInsets.control ~= nil).toBe(true)
		for _, side in { "top", "right", "bottom", "left" } do
			expect(snap.chromeInsets.control[side]).toBe(declared[side])
			-- ...and the slot's own reservation grows by the same number, exactly
			-- as it does for a nine-slice recipe
			expect(snap.insets.control[side]).toBe(pkg.metrics.insets.control[side] + declared[side])
		end
	end)

	it("the measure seam and the PAINT seam read the same table", function()
		-- the adapter boxes the lift from the plan's `contentInsets`; the snapshot
		-- publishes the same field. One number, two consumers.
		local stack = chrome_slots.layerPlanFor(ornate(), "control")
		local box = chrome_slots.liftGeometry(stack)
		expect(box.size.xOffset).toBe(-(stack.contentInsets.left + stack.contentInsets.right))
		expect(box.size.yOffset).toBe(-(stack.contentInsets.top + stack.contentInsets.bottom))
		local snap = themes.resolve(ornate(), nil, {})
		expect(-box.size.xOffset).toBe(snap.chromeInsets.control.left + snap.chromeInsets.control.right)
	end)

	it("a content-sized button under the layered skin reserves the room its label is painted in", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 400 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, system)
		local UI = LuauUI.UI
		-- the reported node: a plain label button in a row that lets it size to
		-- its own content (the fixture's toolbar shape)
		local handle = presenter.present(UI.Screen({
			id = "LiftProbe",
			children = {
				UI.HStack({
					id = "Row",
					width = { type = "fill", weight = 1 },
					children = { UI.Button({ id = "TbPlay", label = "Play" }), UI.Spacer({}) },
				}),
			},
		}))
		presenter.refresh()
		local flat = adapter.node("/LiftProbe/Row/TbPlay").rect.w
		local pkg = ornate()
		env:set("themeMetrics", themes.resolve(pkg, nil, {}))
		presenter.refresh()
		local skinned = adapter.node("/LiftProbe/Row/TbPlay").rect.w
		local insets = pkg.chrome.control.contentInsets
		-- THE INVARIANT, stated the way the engine resolves it: the lifted label
		-- is a child of the button, so its box is the solved width less the
		-- adapter's own UIPadding and less the recipe's insets. It must be
		-- POSITIVE — a negative box draws nothing, which is what "missing" was.
		local adapterPadding = 2 * (pkg.metrics.space.s + 4)
		local liftWidth = skinned - adapterPadding - (insets.left + insets.right)
		expect(liftWidth > 0).toBe(true)
		-- and the growth is exactly the reservation, nothing more
		expect(skinned - flat >= insets.left + insets.right).toBe(true)
		presenter.dismiss(handle)
	end)

	it("a flat package still reserves NOTHING, so flat geometry is untouched", function()
		expect(themes.neutral().hasChromeInsets).toBe(false)
		expect(themes.neutral().chromeInsets.control.left).toBe(0)
		expect(themes.resolve(classic(), nil, {}).hasChromeInsets).toBe(false)
		expect(themes.resolve(classic(), nil, {}).chromeInsets.selection.left).toBe(0)
	end)
end)

describe("theme chrome: metric-derived rule props are mapped for live repaint", function()
	-- integration (2026-07-25): radii/stroke rule props are LITERALS (a number
	-- attribute cannot be a UDim $Token), so buildPackage records their
	-- provenance and the controller pushes fresh values on a live metric edit.
	it("buildPackage records every radii/stroke-derived rule prop", function()
		local pkg = parchmentModule.build(themes)
		local model = sheet_model.buildPackage(pkg)
		expect(model.metricRuleProps ~= nil).toBe(true)
		local byRule: { [string]: any } = {}
		local rulesByName: { [string]: boolean } = {}
		for _, rule in model.rules do
			rulesByName[rule.name] = true
		end
		for _, entry in model.metricRuleProps :: any do
			-- every mapped rule must actually exist in the emitted set, and the
			-- path must be a radii/strokes/font metric with the matching form
			expect(rulesByName[entry.rule]).toBe(true)
			local isRadius = string.sub(entry.path, 1, 6) == "radii."
			local isStroke = string.sub(entry.path, 1, 8) == "strokes."
			-- FONTS are metric-derived rule literals too (review-fix A9/C1): a
			-- Type_*_font sheet edit re-keys measurement, and without provenance
			-- the paint kept the seeded face while the solver moved
			local isFont = string.match(entry.path, "^type%.[^%.]+%.font$") ~= nil
			expect(isRadius or isStroke or isFont).toBe(true)
			expect(entry.form).toBe(if isRadius then "udimOffset" elseif isFont then "font" else "number")
			if isFont then
				expect(entry.prop).toBe("FontFace")
			end
			byRule[entry.rule] = entry
		end
		-- the six legacy-vocabulary geometry sites plus the three font sites are
		-- always present
		for _, name in
			{
				"Raised panel — corner",
				"Control — corner",
				"Chip — corner",
				"Raised panel — hairline",
				"Field — outline",
				"Chip — outline",
				"Text default",
				"Button text default",
				"Field text default",
			}
		do
			expect(byRule[name] ~= nil).toBe(true)
		end
	end)

	it("a flat package maps the same sites and nothing chrome-specific", function()
		local model = sheet_model.buildPackage(themes.neutralPackage())
		local count = 0
		local slotSites = 0
		for _, entry in model.metricRuleProps :: any do
			count += 1
			expect(string.sub(entry.rule, 1, 8) ~= "Chrome —").toBe(true)
			-- byte-safe prefix: the rule names use an EM DASH, which is three
			-- bytes, so a `string.sub(name, 1, n)` comparison against a literal
			-- silently never matches
			if string.find(entry.rule, "Slot ", 1, true) == 1 then
				slotSites += 1
			end
		end
		-- 6 radii/stroke literals + 3 FontFace literals (Text/Button/Field
		-- default) + the value-control chrome's own hairline/corner literals.
		-- The value-control rules are emitted for EVERY package including the
		-- flat ones: a slider still has to be visible under Studio Neutral, and
		-- it no longer borrows a public surface to get there.
		--
		-- The count tracks OWN_PAINT_SLOTS, which ADR-0020 R9 extended from the
		-- slider's rail and thumb to the bar family: one outline site per
		-- own-paint slot, plus one corner site for each that is not round.
		expect(slotSites).toBe(7) -- 4 outlines + 3 corners (sliderThumb is round)
		-- +1 since director round 11: `Primary button — corner` bakes
		-- `radii.control` like every other surface corner, so a live metric edit
		-- repaints the accent surface too instead of leaving it square.
		-- +1 since the circle-button feature round: `Circle button — hairline`
		-- bakes `strokes.hairline` for the same reason every other hairline does —
		-- a designer thickening the theme's hairline must thicken the disc's rim
		-- too, or a circle stops matching the buttons beside it.
		expect(count).toBe(11 + slotSites)
	end)
end)

-- ===========================================================================
-- DIRECTOR FIX ROUND, 2026-07-25. Six live defects, each asserted at the level
-- it was actually wrong at: the compiled rule set (what the sheet paints), the
-- pure plan (what the adapter is told to build), or the pure geometry (where
-- the lifted value lands).
-- ===========================================================================

describe("the image IS the button: a skinned node's native plate is suppressed", function()
	it("emits fill/corner/stroke suppression per SKINNED slot, and only for skinned slots", function()
		-- director: "there should not be extra button border around it". The
		-- parchment art was sitting inside a rounded Studio-Neutral slab with a
		-- hairline, because every surface rule still applied underneath it.
		local model = sheet_model.buildPackage(parchment())
		local plate = ruleNamed(model, "Skinned — control")
		expect(plate.selector).toBe(".luau-skinned-control")
		expect(plate.props.BackgroundTransparency.value).toBe(1)
		local corner = ruleNamed(model, "Skinned — control corner")
		expect(corner.selector).toBe(".luau-skinned-control::UICorner")
		expect(corner.props.CornerRadius.offset).toBe(0)
		expect(corner.props.CornerRadius.scale).toBe(0)
		local outline = ruleNamed(model, "Skinned — control outline")
		expect(outline.selector).toBe(".luau-skinned-control::UIStroke")
		expect(outline.props.Thickness.value).toBe(0)
		expect(outline.props.Transparency.value).toBe(1)
		-- the stub skins panel/control/field; a NATIVE slot keeps every bit of
		-- its Studio-Neutral chrome
		expect(ruleNamed(model, "Skinned — panel") ~= nil).toBe(true)
		expect(ruleNamed(model, "Skinned — field") ~= nil).toBe(true)
		expect(ruleNamed(model, "Skinned — selection")).toBeNil()
		expect(ruleNamed(model, "Skinned — divider")).toBeNil()
	end)

	it("a flat package suppresses only the VALUE slots, and nothing decorative", function()
		-- director round 5: the value family's suppression is PRE-ARMED on every
		-- package (a rung-2 override can skin one of those four slots on a package
		-- that declares no recipe for it — see the value-display specs). Every
		-- other slot stays recipe-driven, so a flat package still emits nothing
		-- for panel/control/field/badge/selection.
		local model = sheet_model.buildPackage(classic())
		local skinnedSlots: { [string]: boolean } = {}
		for _, rule in model.rules do
			local slot = string.match(rule.selector, "^%.luau%-skinned%-([%a]+)")
			if slot ~= nil then
				skinnedSlots[slot] = true
			end
			-- and NOTHING but a bare `.luau-skinned-<slot>` selector: no skinned
			-- rule may ride a decoration/state selector on a flat package
			if string.find(rule.selector, "luau-skinned-", 1, true) ~= nil then
				expect(slot ~= nil).toBe(true)
			end
		end
		expect(chrome_slots.hasOwnPaint("sliderThumb")).toBe(true)
		for slot in skinnedSlots do
			expect(chrome_slots.hasOwnPaint(slot)).toBe(true)
		end
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			expect(skinnedSlots[slot]).toBe(true)
		end
		expect(ruleNamed(model, "Skinned — panel")).toBeNil()
		expect(ruleNamed(model, "Skinned — control")).toBeNil()
		expect(ruleNamed(model, "Skinned — badge")).toBeNil()
	end)

	it("suppression beats every surface rule and loses to nothing that matters", function()
		local model = sheet_model.buildPackage(parchment())
		local index: { [string]: number } = {}
		for i, rule in model.rules do
			index[rule.name] = i
		end
		-- after the fills it must beat...
		expect(index["Skinned — control"] > index["Control fill"]).toBe(true)
		expect(index["Skinned — panel"] > index["Raised panel"]).toBe(true)
		expect(index["Skinned — control corner"] > index["Control — corner"]).toBe(true)
		-- ...and before the interaction states, which only change COLOUR — an
		-- invisible plate stays invisible through hover and press
		expect(index["Skinned — control"] < index["Control — hover"]).toBe(true)
		expect(index["Skinned — control"] < index["Control — pressed"]).toBe(true)
	end)

	it("the skinned tag round-trips through classifyTags, so the adapter's diff keeps it", function()
		-- the tag has to be in the DESIRED set the adapter computes: syncTags
		-- removes every luau-* tag that is not, so a tag added outside it would
		-- be stripped on the next classification pass
		local tags = sheet_model.classifyTags({ surface = "control", interactive = true, skinnedSlot = "control" })
		expect(tags["luau-skinned-control"]).toBe(true)
		expect(tags["luau-surface-control"]).toBe(true)
		expect(chrome_slots.skinnedTagFor("badge")).toBe("luau-skinned-badge")
		-- an unskinned node carries none of it
		expect(sheet_model.classifyTags({ surface = "control", interactive = true })["luau-skinned-control"]).toBeNil()
	end)

	it("the interaction tints are the only feedback left, so they are clearly separated", function()
		-- with the plate invisible the ImageColor3 ladder IS the affordance; the
		-- old 0.92/1.00/0.78 spread read as almost nothing on parchment
		expect(chrome_slots.TINT.hover > chrome_slots.TINT.rest).toBe(true)
		expect(chrome_slots.TINT.rest > chrome_slots.TINT.pressed).toBe(true)
		expect(chrome_slots.TINT.hover - chrome_slots.TINT.rest >= 0.09).toBe(true)
		expect(chrome_slots.TINT.rest - chrome_slots.TINT.pressed >= 0.2).toBe(true)
		local model = sheet_model.buildPackage(parchment())
		local theme = model.themes[1]
		expect(theme.tokens.ChromeTint.r).toBe(chrome_slots.TINT.rest)
		expect(theme.tokens.ChromeTintHover.r).toBe(chrome_slots.TINT.hover)
		expect(theme.tokens.ChromeTintPressed.r).toBe(chrome_slots.TINT.pressed)
		-- and the hover/press rules really do reach a skinned control
		expect(ruleNamed(model, "Chrome — control hover").props.ImageColor3).toBe("$ChromeTintHover")
		expect(ruleNamed(model, "Chrome — control pressed").props.ImageColor3).toBe("$ChromeTintPressed")
	end)
end)

describe("role tints paint the ART, not a slab behind it", function()
	it("every theme carries the role tint tokens, lerped from its own palette", function()
		-- the SHIPPING package: two themes, so "every theme" can actually fail
		local model = sheet_model.buildPackage(shipping())
		expect(#model.themes >= 2).toBe(true)
		for _, theme in model.themes do
			for _, name in
				{
					"ChromeTintDanger",
					"ChromeTintDangerHover",
					"ChromeTintDangerPressed",
					"ChromeTintCancel",
					"ChromeTintAccent",
				}
			do
				local token = theme.tokens[name]
				expect(token ~= nil).toBe(true)
				expect(token.kind).toBe("color")
			end
			-- lifted toward white before it multiplies: a raw danger colour
			-- multiplied into mid-tone parchment lands almost black
			local danger = theme.tokens.Danger
			expect(theme.tokens.ChromeTintDanger.r > danger.r).toBe(true)
			-- ...and it is still recognisably the DANGER hue, not a neutral
			expect(theme.tokens.ChromeTintDanger.r > theme.tokens.ChromeTintDanger.b).toBe(true)
			-- the state pair brackets the resting tint, like every other ramp
			expect(theme.tokens.ChromeTintDangerHover.r > theme.tokens.ChromeTintDanger.r).toBe(true)
			expect(theme.tokens.ChromeTintDangerPressed.r < theme.tokens.ChromeTintDanger.r).toBe(true)
		end
	end)

	it("compiles a child-combinator tint rule per role on the control decoration", function()
		local model = sheet_model.buildPackage(parchment())
		local cases = {
			{
				name = "Chrome role — destructive",
				selector = ".luau-role-destructive > .luau-chrome-control",
				token = "$ChromeTintDanger",
			},
			{
				name = "Chrome role — cancel",
				selector = ".luau-role-cancel > .luau-chrome-control",
				token = "$ChromeTintCancel",
			},
			{
				name = "Chrome role — accent",
				selector = ".luau-surface-accent > .luau-chrome-control",
				token = "$ChromeTintAccent",
			},
		}
		for _, case in cases do
			local rule = ruleNamed(model, case.name)
			expect(rule ~= nil).toBe(true)
			expect(rule.selector).toBe(case.selector)
			expect(rule.props.ImageColor3).toBe(case.token)
			-- a role paints the IMAGE and nothing else: no fill, no second asset
			expect(rule.props.BackgroundColor3).toBeNil()
			expect(rule.props.Image).toBeNil()
		end
		expect(ruleNamed(model, "Chrome role — destructive hover").props.ImageColor3).toBe("$ChromeTintDangerHover")
		expect(ruleNamed(model, "Chrome role — destructive pressed").props.ImageColor3).toBe(
			"$ChromeTintDangerPressed"
		)
	end)

	it("the role tint owns the resting look and the role STATE beats the generic one", function()
		local model = sheet_model.buildPackage(parchment())
		local index: { [string]: number } = {}
		for i, rule in model.rules do
			index[rule.name] = i
		end
		expect(index["Chrome role — destructive"] > index["Chrome — control"]).toBe(true)
		-- V14 one level down: the generic chrome hover keys on the INTERACTIVE
		-- tag, not on the role, so without the ordering a hovered destructive
		-- slab repainted itself neutral at the moment of the click
		expect(index["Chrome role — destructive hover"] > index["Chrome — control hover"]).toBe(true)
		expect(index["Chrome role — destructive pressed"] > index["Chrome — control pressed"]).toBe(true)
	end)

	it("the lifted label keeps its role TEXT colours (already shipped, not regressed)", function()
		local model = sheet_model.buildPackage(parchment())
		expect(ruleNamed(model, "Chrome text — destructive").props.TextColor3).toBe("$OnDanger")
		expect(ruleNamed(model, "Chrome text — cancel").props.TextColor3).toBe("$ContentSecondary")
		expect(ruleNamed(model, "Chrome text — accent").props.TextColor3).toBe("$OnAccent")
	end)

	it("a flat package emits no role tint rules (there is no art to tint)", function()
		local model = sheet_model.buildPackage(classic())
		expect(ruleNamed(model, "Chrome role — destructive")).toBeNil()
	end)
end)

describe("slider chrome: a rail and a thumb are their own slots", function()
	it("Fantasy Parchment resolves both, with the rail sliced and the thumb whole", function()
		local pkg = shipping()
		local rail = chrome_slots.planFor(pkg, "sliderTrack")
		expect(rail.tag).toBe("luau-chrome-sliderTrack")
		expect(rail.contentId).toBe(pkg.assets.parchment_slider_track.contentId)
		expect(rail.sliced).toBe(true)
		expect(rail.sliceCenter ~= nil).toBe(true)
		local thumb = chrome_slots.planFor(pkg, "sliderThumb")
		expect(thumb.tag).toBe("luau-chrome-sliderThumb")
		expect(thumb.contentId).toBe(pkg.assets.parchment_slider_thumb.contentId)
		-- WHOLE image: slicing a 28px token smears its centre pixel
		expect(thumb.sliced).toBe(false)
		expect(thumb.sliceCenter).toBeNil()
	end)

	it("a whole-image recipe compiles four image props and never a slice centre", function()
		local model = sheet_model.buildPackage(shipping())
		local rail = ruleNamed(model, "Chrome — sliderTrack")
		expect(rail.props.ScaleType.item).toBe("Slice")
		expect(rail.props.SliceCenter ~= nil).toBe(true)
		local thumb = ruleNamed(model, "Chrome — sliderThumb")
		expect(thumb.props.ScaleType.item).toBe("Stretch")
		expect(thumb.props.SliceCenter).toBeNil()
		expect(thumb.props.SliceScale).toBeNil()
		expect(thumb.props.Image).toBe(shipping().assets.parchment_slider_thumb.contentId)
		expect(thumb.props.ImageColor3).toBe("$ChromeTint")
		-- a round token's fallback is a CIRCLE, not a square
		expect(ruleNamed(model, "Chrome — sliderThumb fallback corner").props.CornerRadius.scale).toBe(0.5)
	end)

	it("a whole-image slot is the DEFAULT for a thumb and a seal, explicit for the rest", function()
		-- the `sliced` field is available on any recipe, but an author should not
		-- have to remember it for slots whose art is a fixed-size token
		local def = shippingModule.definition(themes)
		def.chrome.sliderThumb = table.clone(def.chrome.sliderThumb)
		def.chrome.sliderThumb.sliced = nil
		local pkg = themes.define(def)
		assert(pkg ~= nil, "the inferred-slicing variant must compile")
		expect(chrome_slots.planFor(pkg, "sliderThumb").sliced).toBe(false)
		expect(chrome_slots.planFor(pkg, "sliderTrack").sliced).toBe(true)
	end)

	it("a flat theme leaves the slider exactly as it was: no plan, no ART rules", function()
		expect(chrome_slots.planFor(classic(), "sliderTrack")).toBeNil()
		expect(chrome_slots.planFor(themes.neutralPackage(), "sliderThumb")).toBeNil()
		local model = sheet_model.buildPackage(themes.neutralPackage())
		expect(ruleNamed(model, "Chrome — sliderTrack")).toBeNil()
		expect(ruleNamed(model, "Chrome — sliderThumb")).toBeNil()
		-- the suppression rule IS emitted (director round 5) and matches NOTHING
		-- on a flat screen: the node never earns `luau-skinned-sliderThumb`, so
		-- its solid `Slot — sliderThumb` paint is byte-identical to before
		expect(ruleNamed(model, "Skinned — sliderThumb").props.BackgroundTransparency.value).toBe(1)
		expect(next(sheet_model.classifyTags({ slotHint = "sliderThumb" }))).toBe("luau-slot-sliderThumb")
		expect(sheet_model.classifyTags({ slotHint = "sliderThumb" })["luau-skinned-sliderThumb"]).toBeNil()
	end)
end)

describe("rung 2 of the ladder: a per-view image beats the theme for ONE node", function()
	it("a local override plans an UNTAGGED, whole-image decoration", function()
		local pkg = shipping()
		local plan = chrome_slots.planFor(pkg, "sliderThumb", { image = "rbxassetid://999" })
		expect(plan.contentId).toBe("rbxassetid://999")
		expect(plan.localOverride).toBe(true)
		-- NO SLOT TAG: a tagged decoration would keep taking the package's Image
		-- rule and the local value would lose on the next swap. Untagged means
		-- the adapter explicit-writes it — the standing opt-out rule, visible.
		expect(plan.tag).toBeNil()
		-- a bare URI carries no slice geometry, so it is painted whole
		expect(plan.sliced).toBe(false)
		expect(plan.sliceCenter).toBeNil()
	end)

	it("works on a FLAT theme too — the rung is independent of the package", function()
		-- the theme has no sliderThumb recipe at all; the view still gets its art
		local plan = chrome_slots.planFor(themes.neutralPackage(), "sliderThumb", { image = "rbxassetid://7" })
		expect(plan ~= nil).toBe(true)
		expect(plan.contentId).toBe("rbxassetid://7")
		expect(plan.localOverride).toBe(true)
	end)

	it("an absent or empty override falls straight back to the theme", function()
		local pkg = shipping()
		expect(chrome_slots.planFor(pkg, "sliderThumb", nil).localOverride).toBe(false)
		expect(chrome_slots.planFor(pkg, "sliderThumb", { image = "" }).localOverride).toBe(false)
		expect(chrome_slots.planFor(pkg, "sliderThumb", {}).contentId).toBe(pkg.assets.parchment_slider_thumb.contentId)
	end)

	it("the overridden node keeps the theme's INSETS — only the image leaves", function()
		local pkg = shipping()
		local themed = chrome_slots.planFor(pkg, "badge")
		local overridden = chrome_slots.planFor(pkg, "badge", { image = "rbxassetid://5" })
		expect(overridden.contentInsets.top).toBe(themed.contentInsets.top)
		expect(overridden.contentInsets.left).toBe(themed.contentInsets.left)
	end)
end)

describe("readable badges: the seal, the lift, and the inset the value sits in", function()
	it("Fantasy Parchment skins the badge as a whole image with a real inset", function()
		local plan = chrome_slots.planFor(shipping(), "badge")
		expect(plan.tag).toBe("luau-chrome-badge")
		expect(plan.sliced).toBe(false)
		expect(plan.contentInsets.top > 0).toBe(true)
	end)

	it('`UI.Text{ surface = "badge" }` is the public authoring path, and it is NARROW', function()
		local UI = LuauUI.UI
		-- the two READ-ONLY surfaces a label may wear...
		for _, surface in { "badge", "chip" } do
			local bp = UI.Text({ id = "B", text = "3", surface = surface })
			expect(bp.props.surface).toBe(surface)
		end
		-- ...and the six it may not. A Text is not interactive, so an affordance
		-- surface on one is a lie the affordance matrix exists to prevent.
		for _, surface in { "control", "accent", "raised", "base", "scrim", "plain" } do
			local ok, err = pcall(function()
				UI.Text({ id = "B", text = "3", surface = surface })
			end)
			expect(ok).toBe(false)
			-- the rejection names the allowed set rather than merely refusing
			expect(string.find(tostring(err), "badge", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "chip", 1, true) ~= nil).toBe(true)
		end
		-- Box keeps the FULL vocabulary — the narrowing is Text's alone
		expect(UI.Box({ id = "P", surface = "raised" }).props.surface).toBe("raised")
	end)

	it("a TextLabel is a lift class, which is what puts the count ABOVE the seal", function()
		local found = false
		for _, className in chrome_slots.LIFTED_TEXT_CLASSES do
			found = found or className == "TextLabel"
		end
		expect(found).toBe(true)
		expect(#chrome_slots.LIFTED_TEXT_CLASSES).toBe(3)
	end)

	it("the badge's lifted label centres both axes; every other slot keeps its alignment", function()
		expect(chrome_slots.centresLiftedText("badge")).toBe(true)
		expect(chrome_slots.centresLiftedText("control")).toBe(false)
		expect(chrome_slots.centresLiftedText(nil)).toBe(false)
	end)

	it("the lift is INSET by the recipe's contentInsets, not full-bleed", function()
		-- the fix for values sitting on the art's border: the solver had already
		-- reserved this inset for the parent's content, and the lift ignored it
		local plan = chrome_slots.planFor(shipping(), "control")
		local box = chrome_slots.liftGeometry(plan)
		local ci = plan.contentInsets
		expect(box.position.xOffset).toBe(ci.left)
		expect(box.position.yOffset).toBe(ci.top)
		expect(box.position.xScale).toBe(0)
		expect(box.size.xScale).toBe(1)
		expect(box.size.xOffset).toBe(-(ci.left + ci.right))
		expect(box.size.yOffset).toBe(-(ci.top + ci.bottom))
	end)

	it("a zero-inset recipe still lifts full-bleed, byte-identical to the old behaviour", function()
		local box = chrome_slots.liftGeometry({ contentInsets = { top = 0, right = 0, bottom = 0, left = 0 } })
		expect(box.position.xOffset).toBe(0)
		expect(box.size.xOffset).toBe(0)
		expect(box.size.yScale).toBe(1)
		-- and a plan with no insets at all does not throw
		expect(chrome_slots.liftGeometry({}).size.xOffset).toBe(0)
	end)

	it("a skinned badge gets the lifted-label rules; a flat one gets none", function()
		local model = sheet_model.buildPackage(shipping())
		expect(ruleNamed(model, "Chrome text — strong") ~= nil).toBe(true)
		expect(ruleNamed(model, "Chrome text — secondary") ~= nil).toBe(true)
		expect(ruleNamed(model, "Chrome — badge") ~= nil).toBe(true)
		expect(ruleNamed(sheet_model.buildPackage(classic()), "Chrome text — strong")).toBeNil()
	end)
end)

describe("slot shadows: adapter-owned depth the sheet cannot express", function()
	it("`themes.define` validates a shadow against the bespoke contract", function()
		local styling = require("../src/tokens/styling")
		-- the two presets the library ships resolve
		expect(styling.normalizeShadow("raised").zIndex < 0).toBe(true)
		local def = classicModule.definition(themes)
		def.chrome = table.clone(def.chrome)
		def.chrome.control = { kind = "native", shadow = "raised" }
		expect(themes.define(def) ~= nil).toBe(true)
		-- a POSITIVE zIndex is an engine error (a shadow renders below its
		-- parent); it must fail at compile, not inside the render path on a device
		local bad = classicModule.definition(themes)
		bad.chrome = table.clone(bad.chrome)
		bad.chrome.control = {
			kind = "native",
			shadow = { blurRadius = { offset = 8 }, zIndex = 1 },
		}
		local pkg, report = themes.define(bad)
		expect(pkg).toBeNil()
		local named = false
		for _, err in report.errors do
			named = named or err.field == "chrome.control.shadow"
		end
		expect(named).toBe(true)
		-- and an unknown preset name too
		local unknown = classicModule.definition(themes)
		unknown.chrome = table.clone(unknown.chrome)
		unknown.chrome.panel = { kind = "native", shadow = "floaty" }
		expect(themes.define(unknown)).toBeNil()
	end)

	it("the reference packages declare the shadows the director asked for", function()
		local parch = shipping()
		expect(chrome_slots.shadowFor(parch, "panel")).toBe("raised")
		expect(chrome_slots.shadowFor(parch, "control")).toBe("raised")
		local glossy = require("../examples/themes/glossy_mobile").build(themes)
		expect(chrome_slots.shadowFor(glossy, "panel")).toBe("raised")
		expect(chrome_slots.shadowFor(glossy, "control")).toBe("raised")
		-- sci-fi wants a COOL glow, so it states parameters rather than a preset
		local scifi = scifiModule.build(themes)
		local hud = chrome_slots.shadowFor(scifi, "panel")
		expect(type(hud)).toBe("table")
		expect(hud.color.b > hud.color.r).toBe(true)
		expect(hud.zIndex < 0).toBe(true)
		-- FLAT packages: zero shadows, still
		expect(chrome_slots.shadowFor(classic(), "panel")).toBeNil()
		expect(chrome_slots.shadowFor(themes.neutralPackage(), "control")).toBeNil()
	end)

	it("a shadow rides a NATIVE recipe too, so a flat-but-deep theme costs no instances", function()
		local glossy = require("../examples/themes/glossy_mobile").build(themes)
		expect(chrome_slots.planFor(glossy, "control")).toBeNil() -- no decoration...
		expect(chrome_slots.shadowFor(glossy, "control") ~= nil).toBe(true) -- ...but depth
	end)

	it("the census counts shadows, so a flat package's zero is a measurement", function()
		local state = chrome_slots.newState(shipping())
		expect(state.census().shadows).toBe(0)
		state.noteShadow("control", true)
		state.noteShadow("control", true)
		state.noteShadow("panel", true)
		local census = state.census()
		expect(census.shadows).toBe(3)
		expect(census.shadowsPerSlot.control).toBe(2)
		state.noteShadow("control", false)
		expect(state.census().shadows).toBe(2)
		-- it can never go negative, so a double-teardown cannot fake a leak
		state.noteShadow("panel", false)
		state.noteShadow("panel", false)
		expect(state.census().shadowsPerSlot.panel).toBeNil()
	end)

	it("a shadow change is part of the chrome signature, so the adapter re-materializes", function()
		local state = chrome_slots.newState(classic())
		expect(state.setPackage(classic())).toBe(false)
		local def = classicModule.definition(themes)
		def.chrome = table.clone(def.chrome)
		def.chrome.control = { kind = "native", shadow = "raised" }
		local shadowed = themes.define(def)
		assert(shadowed ~= nil, "the shadowed variant must compile")
		expect(state.setPackage(shadowed)).toBe(true)
	end)

	it("`::UIShadow` is STILL rejected as a rule — the shadow is adapter-owned on purpose", function()
		expect(function()
			sheet_model.checkSelector(".luau-surface-raised::UIShadow", "Panel shadow")
		end).toThrow()
	end)
end)

describe("the new slots keep the contract backward-compatible", function()
	it("their insets are OPTIONAL and default to zero", function()
		-- A package published against the EARLIER slot vocabulary declares six
		-- insets and knows nothing about the three added here. It must still
		-- compile — the whole reason REQUIRED_INSET_SLOTS is a narrower list than
		-- SLOTS — and resolve those slots to a zero reservation.
		local function deepCopy(t: any): any
			if type(t) ~= "table" then
				return t
			end
			local out: any = {}
			for k, v in t do
				out[k] = deepCopy(v)
			end
			return out
		end
		local neutral = themes.neutralPackage()
		local metrics = deepCopy(neutral.metrics)
		metrics.insets.sliderTrack, metrics.insets.sliderThumb, metrics.insets.badge = nil, nil, nil
		local pkg = themes.define({
			identity = {
				id = "legacy-vocabulary",
				displayName = "Legacy Vocabulary",
				schemaVersion = themes.SCHEMA,
				version = "1.0.0",
			},
			style = deepCopy(neutral.style),
			metrics = metrics,
			chrome = {
				panel = { kind = "native" },
				control = { kind = "native" },
				field = { kind = "native" },
				selection = { kind = "native" },
				divider = { kind = "native" },
				scrollbar = { kind = "native" },
			},
			assets = {},
			compatibility = { requiresSchema = themes.SCHEMA },
		})
		assert(pkg ~= nil, "a package that never heard of the new slots still compiles")
		expect(pkg.metrics.insets.badge).toBeNil()
		local snap = themes.resolve(pkg, nil, {})
		expect(snap.insets.sliderTrack.top).toBe(0)
		expect(snap.insets.badge.left).toBe(0)
		expect(snap.hasChromeInsets).toBe(false) -- flat: nothing reserved
		expect(snap.chromeInsets.badge.top).toBe(0) -- ...and the new slots answer too
	end)

	it("the shipping package's chrome insets reach the solver for the new slots", function()
		local pkg = shipping()
		-- the slot declares no inset of its own (it is one of the optional
		-- three), so the reservation is exactly the RECIPE's contentInsets
		expect(pkg.metrics.insets.badge).toBeNil()
		local snap = themes.resolve(pkg, nil, {})
		expect(snap.chromeInsets.badge.top).toBe(pkg.chrome.badge.contentInsets.top)
		expect(snap.insets.badge.top).toBe(pkg.chrome.badge.contentInsets.top)
		expect(snap.insets.sliderTrack.top).toBe(0)
	end)

	it("an unknown slot is still rejected by name", function()
		local def = classicModule.definition(themes)
		def.chrome = table.clone(def.chrome)
		def.chrome.sliderKnob = { kind = "native" }
		expect(themes.define(def)).toBeNil()
	end)
end)

describe("the focus treatment: a themed ring, or a glow", function()
	local styling = require("../src/tokens/styling")

	it("defaults to the ring, so every package that says nothing is unchanged", function()
		-- byte-identical to what shipped: no package, a flat package, and a
		-- package with an ornate chrome table but no focus opinion all ring
		expect(chrome_slots.focusRecipeOf(nil).kind).toBe("ring")
		expect(chrome_slots.focusRecipeOf(classic()).kind).toBe("ring")
		expect(chrome_slots.focusRecipeOf(themes.neutralPackage()).kind).toBe("ring")
		expect(chrome_slots.focusRecipeOf(parchment()).kind).toBe("ring")
		expect(chrome_slots.focusRecipeOf({ chrome = {} }).kind).toBe("ring")
	end)

	it("the reference packages ask for the glows the director asked for", function()
		-- parchment: a per-theme warm gold, so Daylight and Candlelight differ
		local parch = shipping()
		local recipe = chrome_slots.focusRecipeOf(parch)
		expect(recipe.kind).toBe("glow")
		expect(recipe.color).toBe("$FocusGlow")
		local byTheme: { [string]: any } = {}
		for _, theme in parch.style.themes do
			local rgb = chrome_slots.resolveFocusColor(recipe, theme)
			expect(rgb ~= nil).toBe(true)
			-- WARM, never blue: this is the exact complaint being fixed
			expect(rgb.r > rgb.b).toBe(true)
			expect(rgb.g > rgb.b).toBe(true)
			byTheme[theme.name] = rgb
		end
		-- and the two themes really did pick different values
		expect(byTheme.Daylight.r ~= byTheme.Candlelight.r).toBe(true)
		-- sci-fi: its own accent, through the token, so it follows the palette
		local scifi = scifiModule.build(themes)
		local hud = chrome_slots.focusRecipeOf(scifi)
		expect(hud.kind).toBe("glow")
		expect(hud.color).toBe("$Accent")
		local cyan = chrome_slots.resolveFocusColor(hud, scifi.style.themes[1])
		expect(cyan.b > cyan.r).toBe(true)
		-- the flat families keep the ring
		expect(chrome_slots.focusRecipeOf(require("../examples/themes/glossy_mobile").build(themes)).kind).toBe("ring")
	end)

	it("the glow parameters are a legal shadow at BOTH distance profiles", function()
		local recipe = chrome_slots.focusRecipeOf(shipping())
		local near = styling.normalizeShadow(chrome_slots.focusShadowSpec(recipe, false))
		local far = styling.normalizeShadow(chrome_slots.focusShadowSpec(recipe, true))
		-- a glow is CENTRED: a halo that leans reads as depth, not as focus
		expect(near.offset.x.offset).toBe(0)
		expect(near.offset.y.offset).toBe(0)
		expect(near.zIndex < 0).toBe(true)
		-- §8.4 across a room: MORE blur, LESS transparency — the glow's answer to
		-- the same requirement the ring answers by thickening
		expect(far.blurRadius.offset > near.blurRadius.offset).toBe(true)
		expect(far.transparency < near.transparency).toBe(true)
		expect(far.blurRadius.offset).toBe(near.blurRadius.offset * chrome_slots.FOCUS_TEN_FOOT.blurScale)
		expect(far.transparency).toBe(near.transparency * chrome_slots.FOCUS_TEN_FOOT.transparencyScale)
	end)

	it("a colour token resolves per THEME, and a missing one is a compile error", function()
		local def = shippingModule.definition(themes)
		def.chrome = table.clone(def.chrome)
		def.chrome.focus = { kind = "glow", color = "$NoSuchRole", blurRadius = { offset = 20 } }
		local pkg, report = themes.define(def)
		-- a token that resolves to nothing paints NOTHING, and that is invisible
		-- in review and obvious only on a device
		expect(pkg).toBeNil()
		local named = false
		for _, err in report.errors do
			named = named or err.field == "chrome.focus.color"
		end
		expect(named).toBe(true)
		-- ...and a token that covers only SOME themes fails too, naming them
		local partial = shippingModule.definition(themes)
		partial.style = table.clone(partial.style)
		partial.style.themes = { table.clone(partial.style.themes[1]), table.clone(partial.style.themes[2]) }
		partial.style.themes[2].extra = table.clone(partial.style.themes[2].extra)
		partial.style.themes[2].extra.focusGlow = nil
		local half, halfReport = themes.define(partial)
		expect(half).toBeNil()
		local message = ""
		for _, err in halfReport.errors do
			if err.field == "chrome.focus.color" then
				message = err.message
			end
		end
		expect(string.find(message, "Candlelight", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an unknown kind, an unknown field and an illegal shadow", function()
		local function withFocus(focus: any): (any, any)
			local def = classicModule.definition(themes)
			def.chrome = table.clone(def.chrome)
			def.chrome.focus = focus
			return themes.define(def)
		end
		expect((withFocus({ kind = "sparkle" }))).toBeNil()
		expect((withFocus({ kind = "glow", halo = 3 }))).toBeNil()
		-- a POSITIVE zIndex is an engine error: a shadow renders below its parent
		expect((withFocus({ kind = "glow", blurRadius = { offset = 20 }, zIndex = 2 }))).toBeNil()
		-- a colour that is neither a token nor an { r, g, b }
		expect((withFocus({ kind = "glow", blurRadius = { offset = 20 }, color = 7 }))).toBeNil()
		expect((withFocus({ kind = "glow", blurRadius = { offset = 20 }, color = "Accent" }))).toBeNil()
		-- ...and the two legal shapes DO compile
		expect((withFocus({ kind = "ring" })) ~= nil).toBe(true)
		expect((withFocus({ kind = "glow", blurRadius = { offset = 20 }, color = { r = 1, g = 0.8, b = 0.2 } })) ~= nil).toBe(
			true
		)
	end)

	it("a literal colour needs no theme, and an absent colour falls back to the accent", function()
		local literal = { kind = "glow", color = { r = 1, g = 0.5, b = 0 } }
		expect(chrome_slots.resolveFocusColor(literal, {}).r).toBe(1)
		-- no colour declared at all: nil, and the ADAPTER substitutes the active
		-- theme's own accent (never Studio Neutral's blue — the theme-blindness fix)
		expect(chrome_slots.resolveFocusColor({ kind = "glow" }, shipping().style.themes[1])).toBeNil()
	end)

	it("the census counts live glows, so a stuck one and a leaked one both show", function()
		local state = chrome_slots.newState(shipping())
		expect(state.census().focusGlows).toBe(0)
		state.noteFocusGlow(true)
		expect(state.census().focusGlows).toBe(1)
		state.noteFocusGlow(false)
		expect(state.census().focusGlows).toBe(0)
		-- never negative: a double teardown cannot fake a clean census
		state.noteFocusGlow(false)
		expect(state.census().focusGlows).toBe(0)
	end)

	it("focus is chrome vocabulary but NOT a decoration slot", function()
		-- it applies to whichever node has focus, so it has no plan, no census of
		-- decoration instances and no skinned tag
		expect(chrome_slots.isSlot("focus")).toBe(false)
		expect(chrome_slots.planFor(shipping(), "focus")).toBeNil()
		expect(chrome_slots.censusOf(shipping(), { { class = "Button" } }).perSlot.focus).toBeNil()
	end)
end)

describe("a value control's chrome is SOLID, and its own", function()
	local glossyModule = require("../examples/themes/glossy_mobile")

	it("the thumb and the rail paint from the slot tag, opaquely", function()
		-- director: "in glossy_shadows, the slider button should be solid. when
		-- it's transparent, [the fill reads through it]."
		local model = sheet_model.buildPackage(glossyModule.build(themes))
		for _, case in
			{
				{ slot = "sliderThumb", token = "$SurfaceStrong", round = true },
				{ slot = "sliderTrack", token = "$Control", round = false },
			}
		do
			local rule = ruleNamed(model, `Slot — {case.slot}`)
			expect(rule ~= nil).toBe(true)
			expect(rule.selector).toBe(`.luau-slot-{case.slot}`)
			expect(rule.props.BackgroundColor3).toBe(case.token)
			-- SOLID. This single number is the whole defect.
			expect(rule.props.BackgroundTransparency.value).toBe(0)
			local corner = ruleNamed(model, `Slot — {case.slot} corner`)
			expect(corner.props.CornerRadius.scale).toBe(if case.round then 0.5 else 0)
			-- the hairline speaks the package's OWN stroke vocabulary
			local outline = ruleNamed(model, `Slot — {case.slot} outline`)
			expect(outline.props.Color).toBe("$Hairline")
			expect(outline.props.Thickness.value).toBe(glossyModule.build(themes).metrics.strokes.hairline)
		end
	end)

	it("colour comes from the SAME map the asset-failure fallback uses", function()
		-- one decision about what a flat slot looks like, not two that drift
		local model = sheet_model.buildPackage(shipping())
		expect(ruleNamed(model, "Slot — sliderThumb").props.BackgroundColor3).toBe(
			ruleNamed(model, "Chrome — sliderThumb fallback").props.BackgroundColor3
		)
		expect(ruleNamed(model, "Slot — sliderTrack").props.BackgroundColor3).toBe(
			ruleNamed(model, "Chrome — sliderTrack fallback").props.BackgroundColor3
		)
	end)

	it("every package emits them — a flat theme's slider still has to be visible", function()
		for _, pkg in { themes.neutralPackage(), classic(), glossyModule.build(themes), shipping() } do
			local model = sheet_model.buildPackage(pkg)
			expect(ruleNamed(model, "Slot — sliderThumb") ~= nil).toBe(true)
			expect(ruleNamed(model, "Slot — sliderTrack") ~= nil).toBe(true)
		end
	end)

	it("NO GRADIENT can reach them — not through a surface, not through a slot", function()
		-- THE REGRESSION. Glossy declares an ALPHA'd gradient on `panel`, and the
		-- thumb used to wear `surface = "raised"` to get a fill, which is exactly
		-- how the panel wash reached it.
		local glossy = glossyModule.build(themes)
		local gradient = (glossy.style.themes[1].extra or {}).chromeGradient
		expect(gradient.panel ~= nil).toBe(true)
		local hasAlpha = false
		for _, stop in gradient.panel.alpha or {} do
			hasAlpha = hasAlpha or stop.v > 0
		end
		expect(hasAlpha).toBe(true) -- the package really is the hazard case
		local model = sheet_model.buildPackage(glossy)
		-- ...and NOTHING gradient-shaped selects a value control's chrome
		for _, rule in model.rules do
			if string.find(rule.selector, "luau-slot-", 1, true) ~= nil then
				expect(string.find(rule.selector, "::UIGradient", 1, true)).toBeNil()
			end
			if string.find(rule.selector, "UIGradient", 1, true) ~= nil then
				expect(string.find(rule.selector, "sliderThumb", 1, true)).toBeNil()
				expect(string.find(rule.selector, "sliderTrack", 1, true)).toBeNil()
			end
		end
		expect(chrome_slots.isGradientable("panel")).toBe(true)
		expect(chrome_slots.isGradientable("badge")).toBe(true)
		expect(chrome_slots.isGradientable("sliderThumb")).toBe(false)
		expect(chrome_slots.isGradientable("sliderTrack")).toBe(false)
	end)

	it("declaring a gradient on one is a COMPILE error, not a silently dropped rule", function()
		local def = glossyModule.definition(themes)
		def.style = table.clone(def.style)
		def.style.themes = { table.clone(def.style.themes[1]) }
		def.style.themes[1].extra = table.clone(def.style.themes[1].extra)
		def.style.themes[1].extra.chromeGradient = table.clone(def.style.themes[1].extra.chromeGradient)
		def.style.themes[1].extra.chromeGradient.sliderThumb = {
			rotation = 90,
			stops = { { t = 0, r = 1, g = 1, b = 1 }, { t = 1, r = 0.5, g = 0.5, b = 0.5 } },
			alpha = { { t = 0, v = 0.4 }, { t = 1, v = 0.1 } },
		}
		local pkg, report = themes.define(def)
		expect(pkg).toBeNil()
		local named = false
		for _, err in report.errors do
			named = named or string.find(err.field, "chromeGradient.sliderThumb", 1, true) ~= nil
		end
		expect(named).toBe(true)
	end)

	it("the hint tag is emitted for the value family and for nothing else", function()
		-- a value control's chrome is reached ONLY through the hint, so it needs
		-- its own paint; a node that reached a slot through a public surface (a
		-- badge, a raised panel) already has that surface's rules
		local thumb = sheet_model.classifyTags({ slotHint = "sliderThumb" })
		expect(thumb["luau-slot-sliderThumb"]).toBe(true)
		expect(sheet_model.classifyTags({ slotHint = "sliderTrack" })["luau-slot-sliderTrack"]).toBe(true)
		expect(next(sheet_model.classifyTags({ slotHint = "badge" }))).toBeNil()
		expect(next(sheet_model.classifyTags({ slotHint = "panel" }))).toBeNil()
		expect(chrome_slots.slotTagFor("sliderThumb")).toBe("luau-slot-sliderThumb")
		-- and it does NOT depend on the package skinning anything: the tag is the
		-- node's identity, the skinned tag is the art's presence
		expect(thumb["luau-skinned-sliderThumb"]).toBeNil()
	end)

	it("a skinned thumb still hides its own plate — paint first, then suppress", function()
		local model = sheet_model.buildPackage(shipping())
		local index: { [string]: number } = {}
		for i, rule in model.rules do
			index[rule.name] = i
		end
		expect(index["Skinned — sliderThumb"] > index["Slot — sliderThumb"]).toBe(true)
		expect(index["Skinned — sliderThumb corner"] > index["Slot — sliderThumb corner"]).toBe(true)
		expect(index["Skinned — sliderThumb outline"] > index["Slot — sliderThumb outline"]).toBe(true)
	end)

	it("the OTHER value nodes: badge solid, accent fill solid, toggle untagged", function()
		-- swept for the same leakage class. A badge is a PUBLIC surface, so it
		-- keeps its surface rules — but those rules are opaque, and no reference
		-- package washes them.
		for _, pkg in { glossyModule.build(themes), scifiModule.build(themes), shipping() } do
			local model = sheet_model.buildPackage(pkg)
			expect(ruleNamed(model, "Badge").props.BackgroundTransparency.value).toBe(0)
			expect(ruleNamed(model, "Primary button").props.BackgroundTransparency.value).toBe(0)
			expect(ruleNamed(model, "Gradient — badge")).toBeNil()
			-- the toggle's knob/track carry no surface tag at all, so no wash can
			-- reach them either; their one rule is opacity
			expect(ruleNamed(model, "Toggle chrome").props.BackgroundTransparency.value).toBe(0)
		end
	end)
end)

describe("the toggle is palette-true, in every theme", function()
	local tokens = require("../src/tokens/tokens")
	local glossyModule = require("../examples/themes/glossy_mobile")

	-- every reference theme in the corpus, as (label, theme-entry) pairs
	local function corpus(): { { label: string, theme: any } }
		local out: { { label: string, theme: any } } = {}
		for _, entry in
			{
				{ "neutral", themes.neutralPackage() },
				{ "classic", classicModule.build(themes) },
				{ "glossy", glossyModule.build(themes) },
				{ "scifi", scifiModule.build(themes) },
				{ "parchment", shippingModule.build(themes) },
			}
		do
			for _, theme in (entry[2] :: any).style.themes do
				table.insert(out, { label = `{entry[1]}/{theme.name}`, theme = theme })
			end
		end
		return out
	end

	it("the ON track is THAT theme's accent — never Studio Neutral's blue", function()
		-- director screenshot: the parchment toggle rendered a Studio-Neutral BLUE
		-- pill, because the track colour was a constant captured when the adapter
		-- was constructed
		local neutralAccent = themes.neutralPackage().style.themes[1].colors.accent
		local sawDifferent = false
		for _, entry in corpus() do
			local palette = sheet_model.togglePalette(entry.theme)
			local accent = entry.theme.colors.accent
			expect(palette.trackOn.r).toBe(accent.r)
			expect(palette.trackOn.g).toBe(accent.g)
			expect(palette.trackOn.b).toBe(accent.b)
			-- ...and the knob is the palette's own guaranteed partner
			expect(palette.knobOn.r).toBe(entry.theme.colors.onAccent.r)
			if accent.r ~= neutralAccent.r or accent.b ~= neutralAccent.b then
				sawDifferent = true
			end
		end
		-- the corpus really does contain themes whose accent differs from
		-- Neutral's, or the assertion above proves nothing
		expect(sawDifferent).toBe(true)
	end)

	it("the OFF track is a RECESSED control surface, in light themes as well as dark", function()
		for _, entry in corpus() do
			local palette = sheet_model.togglePalette(entry.theme)
			-- darker than the control row it sits in, BY CONSTRUCTION, whichever
			-- way the palette leans. `colors.surface` — what this used to paint —
			-- does not hold this property: on Parchment Daylight it is LIGHTER
			-- than the row, so an off track would read as a raised bump there and
			-- a recessed well everywhere else.
			local control = (entry.theme.extra or {}).control or entry.theme.colors.surfaceStrong
			local function luminance(c: any): number
				return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			end
			expect(luminance(palette.trackOff) < luminance(control) + 1e-9).toBe(true)
		end
	end)

	it("knob vs track clears the 3:1 non-text floor in BOTH states, every theme", function()
		for _, entry in corpus() do
			local palette = sheet_model.togglePalette(entry.theme)
			local on = tokens.contrastRatio(palette.knobOn, palette.trackOn)
			local off = tokens.contrastRatio(palette.knobOff, palette.trackOff)
			-- the state of a switch is communicated by the knob against its
			-- track; if that pair fails, the control does not say what it is
			expect(on >= 3).toBe(true)
			expect(off >= 3).toBe(true)
		end
	end)

	it("derives the off track for a theme that never declared one", function()
		-- a third-party package should not have to restate the interaction ramp
		local bare = {
			colors = shippingModule.build(themes).style.themes[1].colors,
			extra = nil,
		}
		local palette = sheet_model.togglePalette(bare)
		expect(palette.trackOff ~= nil).toBe(true)
		expect(tokens.contrastRatio(palette.knobOff, palette.trackOff) >= 3).toBe(true)
	end)
end)

-- ===========================================================================
-- AN EXPLICIT `plain` PAINTS NOTHING — INCLUDING CHROME
-- (director round 10, found live 2026-07-26 on a phone)
--
-- `surface = "plain"` already meant "no plate" to the native paint path, and
-- meant nothing at all to the decoration classifier, which routed by CLASS —
-- and every Button is a control. So a package's `control` recipe was still
-- materialized on a node whose author had explicitly asked for no surface.
--
-- The playlist demo's five star buttons declare `plain` precisely so a rating
-- reads as five glyphs. Under Glossy Touch they came out as five glossy PILLS;
-- under Glossy Mobile, whose `control` is `{ kind = "native", shadow =
-- "raised" }`, each star grew a drop shadow and the five overlapped into a
-- smeared dark band behind the row. Neither theme was wrong.
-- ===========================================================================
describe("surface = plain opts out of decoration, not just of native paint", function()
	local chrome_slots = require("../src/tokens/chrome_slots")

	it("a plain Button classifies to NO slot, where a bare Button classifies to control", function()
		expect(chrome_slots.classify({ class = "Button" })).toBe("control")
		expect(chrome_slots.classify({ class = "Button", surface = "plain" })).toBeNil()
	end)

	it("...and that holds for the classes that route by class, not by surface", function()
		expect(chrome_slots.classify({ class = "TextField" })).toBe("field")
		expect(chrome_slots.classify({ class = "TextField", surface = "plain" })).toBeNil()
		expect(chrome_slots.classify({ class = "Divider" })).toBe("divider")
		expect(chrome_slots.classify({ class = "Divider", surface = "plain" })).toBeNil()
		expect(chrome_slots.classify({ class = "ScrollView" })).toBe("scrollbar")
		expect(chrome_slots.classify({ class = "ScrollView", surface = "plain" })).toBeNil()
	end)

	it("a plain SELECTED button takes no selection card either", function()
		expect(chrome_slots.classify({ class = "Button", hasSelection = true })).toBe("selection")
		expect(chrome_slots.classify({ class = "Button", hasSelection = true, surface = "plain" })).toBeNil()
	end)

	it("but a control's own HINT still wins — that is the control's considered decision", function()
		-- `plain` is the caller saying "no surface"; a hint is a control saying
		-- "this node IS a slider rail". A rail declares `plain` for its native
		-- paint and must still be skinnable.
		expect(chrome_slots.classify({ class = "Box", surface = "plain", hint = "sliderTrack" })).toBe("sliderTrack")
	end)
end)

-- ===========================================================================
-- A DEPTH CUE PAINTS OUTSIDE ITS RECT, SO THE SCROLL CANVAS HAS TO REACH IT
-- (director round 11, root-caused 2026-07-27 from a landscape capture)
--
-- A scroll canvas is built from the content's RECTS and stops exactly at the
-- last child's rect — measured doing so to the pixel in seven configurations.
-- A `shadow` recipe paints OUTSIDE that rect, so under Sci-Fi HUD (a centred
-- 24px glow on `panel`) the bottom of the last element was unreachable:
-- scrollbar at the end of its track, content still cut off.
-- ===========================================================================
describe("the scroll canvas reaches a theme's decoration bleed", function()
	local scifi = require("../examples/themes/scifi_hud")

	it("a package's deepest shadow reach is published as ONE number", function()
		local snap = themes.resolve(scifi.build(themes), nil, {})
		-- scifi_hud declares a centred 24px glow on `panel` and 16px on `control`
		expect(snap.chromeBleed).toBe(24)
	end)

	it("a package with no depth at all publishes zero, so nothing without it moves", function()
		expect(themes.neutral().chromeBleed).toBe(0)
		expect(themes.resolve(classic(), nil, {}).chromeBleed).toBe(0)
	end)

	it("the canvas a scrolling region declares grows by exactly that much", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 200 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		local UI = LuauUI.UI
		local rows = {}
		for i = 1, 10 do
			table.insert(rows, UI.Box({ id = `r{i}`, surface = "raised", height = { type = "fixed", px = 40 } }))
		end
		presenter.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "List",
					axis = "y",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = rows,
				}),
			},
		}))
		presenter.refresh()
		local flat = adapter.node("/S/List").scrollRegion.contentH
		env:set("themeMetrics", themes.resolve(scifi.build(themes), nil, {}))
		presenter.refresh()
		local glowing = adapter.node("/S/List").scrollRegion.contentH
		-- the ONLY thing that may differ here is the allowance: this package
		-- declares no metric that would change a fixed-height row's geometry
		expect(glowing - flat).toBe(24)
	end)
end)

-- ===========================================================================
-- A DECORATION COVERS ITS HOST'S BOX, NOT ITS CONTENT BOX (director report
-- 2026-07-27, Compact Pointer: "text overflowing each row on the left").
--
-- The plate is created at `Size = fromScale(1, 1)` under a comment that says
-- "the skin IS the node" — but a scale size resolves against the parent's
-- CONTENT box, and `UIPadding` shrinks that. Measured live on a playlist row:
-- host x=16 w=357 with a 12px padding, so the plate drew at x=28 while the
-- first cell's text sat at x=26 — the text hanging 2px off the left edge of its
-- own plate. Measure-versus-paint again, with the paint side moved by an engine
-- object the solver never sees.
-- ===========================================================================
describe("chrome full bleed: the plate covers the host's own box", function()
	it("pushes the padding back out on both axes", function()
		local box = chrome_slots.fullBleedBox(12, 12, 4, 6)
		expect(box.x).toBe(-12)
		expect(box.y).toBe(-4)
		expect(box.w).toBe(24)
		expect(box.h).toBe(10)
	end)

	it("is the IDENTITY when the host carries no padding, so nothing unpadded moves", function()
		local box = chrome_slots.fullBleedBox(0, 0, 0, 0)
		expect(box.x).toBe(0)
		expect(box.y).toBe(0)
		expect(box.w).toBe(0)
		expect(box.h).toBe(0)
	end)

	it("reproduces the reported row exactly: a 357px host lands its plate at the host's edge", function()
		-- host x=16 w=357, UIPadding 12 a side. Before: plate x=28 w=333, text
		-- x=26 -> 2px OUTSIDE. After: plate x=16 w=357, text x=26 -> 10px inside.
		local box = chrome_slots.fullBleedBox(12, 12, 0, 0)
		local plateX = 16 + 12 + box.x -- the padded origin, pushed back out
		local plateW = (357 - 24) + box.w
		expect(plateX).toBe(16)
		expect(plateW).toBe(357)
		expect(26 - plateX).toBe(10) -- the text is now INSIDE its own plate
	end)

	it("the adapter applies it on EVERY sync, not only at creation", function()
		-- the host's padding is rewritten per solve (`applyPadding` re-derives a
		-- Button's inset from the live theme), so a theme swap changes the number
		-- this compensates for
		expect(string.find(adapterChromeSource, "applyFullBleed(instance, deco", 1, true) ~= nil).toBe(true)
		expect(string.find(adapterChromeSource, "chrome_slots.fullBleedBox(l, r, t, b)", 1, true) ~= nil).toBe(true)
	end)
end)
