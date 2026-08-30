--!strict
-- PER-STATE ASSET VARIANTS (rich-skinning-v2 package P1).
--
-- "Selection changes the whole style" — a different picture, not a tint. The
-- propositions:
--
--   1. ONE normalizer, exported from the schema, consumed verbatim by both
--      customization rungs: a bare string and a per-state map come back in the
--      SAME shape, so the prop schema can never fork from the recipe schema;
--   2. every rejection class exists and names the slot, the state and the fix:
--      an unknown state key, a missing `default`, a malformed entry, and the
--      no-reflow rule (contentInsets identical across states per axis);
--   3. rule emission turns a map into GuiState-pseudo + tag-family rules
--      carrying `Image`, with the per-state TINT rules still applying on top —
--      so an unstated state falls back to the default art WITH its treatment;
--   4. the census counts the extra art, and a bare-string package emits and
--      stamps exactly what it did before this stage.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")
local chrome_slots = require("../src/tokens/chrome_slots")

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out: any = {}
	for k, inner in v do
		out[k] = copy(inner)
	end
	return out
end

local function def(): any
	local base = snapshot.neutralPackage()
	return {
		identity = {
			id = "variant-test",
			displayName = "Variant Test",
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = copy(base.style),
		metrics = copy(base.metrics),
		chrome = copy(base.chrome),
		assets = {
			plate = {
				content = "rbxassetid://21",
				sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
				preload = "install",
				fallback = "native",
			},
			plateHot = {
				content = "rbxassetid://22",
				sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
				preload = "install",
				fallback = "native",
			},
			plateDown = {
				content = "rbxassetid://23",
				sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
				preload = "lazy",
				fallback = "native",
			},
			plateChosen = {
				content = "rbxassetid://24",
				sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
				preload = "install",
				fallback = "native",
			},
		},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

local function withControl(asset: any): any
	local d = def()
	d.chrome.control = {
		kind = "nineSlice",
		asset = asset,
		fallback = "native",
		contentInsets = { top = 6, right = 10, bottom = 6, left = 10 },
	}
	return d
end

local function ruleNamed(model: any, name: string): any
	for _, rule in model.rules do
		if rule.name == name then
			return rule
		end
	end
	return nil
end

local FULL_MAP = {
	default = "plate",
	hover = "plateHot",
	pressed = "plateDown",
	selected = "plateChosen",
}

describe("themes.normalizeVariant: one grammar for both rungs", function()
	it("a bare string and a map come back in the SAME shape", function()
		local bare = themes.normalizeVariant("plate", "chrome.control.asset")
		expect(bare.default.asset).toBe("plate")
		expect(themes.variantStates(bare)[1]).toBe("default")
		expect(#themes.variantStates(bare)).toBe(1)

		local map = themes.normalizeVariant(FULL_MAP, "chrome.control.asset")
		expect(map.default.asset).toBe("plate")
		expect(map.hover.asset).toBe("plateHot")
		expect(table.concat(themes.variantStates(map), ",")).toBe("default,hover,pressed,selected")
	end)

	it("is the SAME function a rung-2 view prop calls, on a raw content URI", function()
		-- rung 2 names art directly rather than a package asset; the normalizer
		-- validates SHAPE, so the two rungs cannot drift apart
		local prop = themes.normalizeVariant(
			{ default = "rbxassetid://90", disabled = { asset = "rbxassetid://91" } },
			"Slider.thumbImage"
		)
		expect(prop.default.asset).toBe("rbxassetid://90")
		expect(prop.disabled.asset).toBe("rbxassetid://91")
		expect(themes.variantAsset(prop, "disabled")).toBe("rbxassetid://91")
	end)

	it("unstated states fall back to default, which is what lets an author ship less art", function()
		local map = themes.normalizeVariant({ default = "plate", hover = "plateHot" }, "chrome.control.asset")
		expect(themes.variantAsset(map, "hover")).toBe("plateHot")
		expect(themes.variantAsset(map, "pressed")).toBe("plate")
		expect(themes.variantAsset(map, "disabled")).toBe("plate")
		expect(themes.variantAsset(map, nil)).toBe("plate")
	end)

	it("rejects an unknown state key, naming the legal set", function()
		local variant, errors =
			themes.normalizeVariant({ default = "plate", focus = "plateHot" }, "chrome.control.asset")
		expect(variant).toBeNil()
		expect(#errors > 0).toBe(true)
		expect(errors[1].field).toBe("chrome.control.asset")
		expect(string.find(errors[1].message, "focus", 1, true) ~= nil).toBe(true)
		-- and it says WHY focus is not a state
		local fix = errors[1].fix
		expect(string.find(fix, "default | hover | pressed | selected | disabled | error", 1, true) ~= nil).toBe(true)
		expect(string.find(fix, "chrome.focus", 1, true) ~= nil).toBe(true)
	end)

	it("requires `default` in map form", function()
		local variant, errors = themes.normalizeVariant({ hover = "plateHot" }, "chrome.control.asset")
		expect(variant).toBeNil()
		expect(string.find(errors[1].message, "default", 1, true) ~= nil).toBe(true)
	end)

	it("rejects a malformed reference and a malformed state entry", function()
		local _, notARef = themes.normalizeVariant(7, "chrome.control.asset")
		expect(#notARef).toBe(1)
		local _, empty = themes.normalizeVariant("", "chrome.control.asset")
		expect(#empty).toBe(1)
		local _, badEntry = themes.normalizeVariant({ default = 7 }, "chrome.control.asset")
		expect(#badEntry > 0).toBe(true)
		local _, badField =
			themes.normalizeVariant({ default = { asset = "plate", sliceScale = 2 } }, "chrome.control.asset")
		expect(string.find(badField[1].message, "sliceScale", 1, true) ~= nil).toBe(true)
	end)
end)

describe("themes.normalizeVariant: a state change may never RELAYOUT the tree", function()
	it("accepts insets that are identical across every declared state", function()
		local variant, errors = themes.normalizeVariant({
			default = { asset = "plate", contentInsets = { top = 6, right = 10, bottom = 6, left = 10 } },
			hover = { asset = "plateHot", contentInsets = { top = 6, right = 10, bottom = 6, left = 10 } },
		}, "chrome.control.asset")
		expect(#errors).toBe(0)
		expect(variant.hover.contentInsets.left).toBe(10)
	end)

	it("rejects a per-axis difference, naming the slot, the state and the axis", function()
		local variant, errors = themes.normalizeVariant({
			default = { asset = "plate", contentInsets = { top = 6, right = 10, bottom = 6, left = 10 } },
			pressed = { asset = "plateDown", contentInsets = { top = 8, right = 10, bottom = 6, left = 10 } },
		}, "chrome.control.asset")
		expect(variant).toBeNil()
		local entry = errors[1]
		expect(entry.field).toBe("chrome.control.asset") -- the slot
		expect(string.find(entry.message, "pressed", 1, true) ~= nil).toBe(true) -- the state
		expect(string.find(entry.message, "axis 'y'", 1, true) ~= nil).toBe(true) -- the axis
		expect(string.find(entry.message, "RELAYOUT", 1, true) ~= nil).toBe(true) -- the reason
	end)

	it("rejects insets declared on ONE state only — the same reservation change", function()
		local variant, errors = themes.normalizeVariant({
			default = "plate",
			hover = { asset = "plateHot", contentInsets = { top = 4, right = 4, bottom = 4, left = 4 } },
		}, "chrome.control.asset")
		expect(variant).toBeNil()
		expect(#errors > 0).toBe(true)
	end)

	it("rejects a negative or non-table inset before it can corrupt a solve", function()
		local _, negative = themes.normalizeVariant(
			{ default = { asset = "plate", contentInsets = { top = -1, right = 0, bottom = 0, left = 0 } } },
			"chrome.control.asset"
		)
		expect(#negative > 0).toBe(true)
		local _, wrongType =
			themes.normalizeVariant({ default = { asset = "plate", contentInsets = 4 } }, "chrome.control.asset")
		expect(#wrongType > 0).toBe(true)
	end)
end)

describe("themes.define: a recipe takes the same grammar", function()
	it("compiles a per-state recipe and normalizes it to one canonical map", function()
		local pkg, report = themes.define(withControl(FULL_MAP))
		expect(report.ok).toBe(true)
		expect(pkg.chrome.control.assetVariants.hover.asset).toBe("plateHot")
		-- the AUTHORED value is preserved verbatim, so an export stays what the
		-- author wrote
		expect(pkg.chrome.control.asset.hover).toBe("plateHot")
		-- and the plan resolves the resting art from the canonical map, so every
		-- existing reader keeps working
		local plan = chrome_slots.planFor(pkg, "control")
		expect(plan.contentId).toBe(pkg.assets.plate.contentId)
		expect(plan.variants.selected.contentId).toBe(pkg.assets.plateChosen.contentId)
	end)

	it("a bare string carries NO canonical sibling, so nothing about it moves", function()
		local bare = themes.define(withControl("plate"))
		expect(bare.chrome.control.assetVariants).toBeNil()
		expect(chrome_slots.planFor(bare, "control").variants).toBeNil()
	end)

	it("rejects a state naming art the package never declared, naming the state", function()
		local _, report = themes.define(withControl({ default = "plate", hover = "ghost" }))
		expect(report.ok).toBe(false)
		local entry: any = nil
		for _, e in report.errors do
			if e.class == "nineSliceFallback" and e.field == "chrome.control.asset" then
				entry = e
			end
		end
		expect(entry ~= nil).toBe(true)
		expect(string.find(entry.message, "hover", 1, true) ~= nil).toBe(true)
		expect(string.find(entry.message, "ghost", 1, true) ~= nil).toBe(true)
	end)

	it("every state's art joins the preload seam, by its own policy", function()
		local pkg = themes.define(withControl(FULL_MAP))
		local install: { [string]: boolean } = {}
		for _, entry in chrome_slots.assetsToPreload(pkg, "install") do
			install[entry.name] = true
		end
		expect(install.plate).toBe(true)
		expect(install.plateHot).toBe(true)
		expect(install.plateChosen).toBe(true)
		-- the one declared lazy stays lazy: preload policy is the asset's, not
		-- the variant map's
		expect(install.plateDown).toBeNil()
		local lazy: { [string]: boolean } = {}
		for _, entry in chrome_slots.assetsToPreload(pkg, "lazy") do
			lazy[entry.name] = true
		end
		expect(lazy.plateDown).toBe(true)
	end)

	it("a derived package inherits the states, and an override cannot leave a stale one", function()
		-- the canonical sibling is GENERATOR-written, so a package derived from a
		-- compiled base inherits it — and re-deriving it from the authored
		-- reference on every compile is what stops "asset says X, variants say Y"
		local base = themes.define(withControl(FULL_MAP))
		local derived = themes.define({
			identity = { id = "derived", displayName = "Derived", schemaVersion = themes.SCHEMA, version = "1.0.0" },
			base = base,
		})
		expect(derived.chrome.control.assetVariants.hover.asset).toBe("plateHot")
		expect(chrome_slots.planFor(derived, "control").variants.hover ~= nil).toBe(true)

		local overridden = themes.define({
			identity = { id = "plainer", displayName = "Plainer", schemaVersion = themes.SCHEMA, version = "1.0.0" },
			base = base,
			chrome = {
				control = {
					kind = "nineSlice",
					asset = "plate",
					fallback = "native",
					contentInsets = { top = 6, right = 10, bottom = 6, left = 10 },
				},
			},
		})
		expect(overridden.chrome.control.assetVariants).toBeNil()
		expect(chrome_slots.planFor(overridden, "control").variants).toBeNil()
	end)

	it("a layer takes the same grammar as a recipe", function()
		local d = def()
		d.chrome.panel = {
			kind = "layered",
			fallback = "native",
			contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
			layers = { { kind = "fill", asset = { default = "plate", hover = "plateHot" } } },
		}
		local pkg, report = themes.define(d)
		expect(report.ok).toBe(true)
		local stack = chrome_slots.layerPlanFor(pkg, "panel")
		expect(stack.layers[1].variants.hover.contentId).toBe(pkg.assets.plateHot.contentId)
	end)
end)

describe("buildPackage: a state map becomes GuiState-pseudo and tag-family rules", function()
	it("emits one Image rule per declared state, read from the PARENT's state", function()
		local pkg = themes.define(withControl(FULL_MAP))
		local model = sheet_model.buildPackage(pkg)
		local cases = {
			{
				name = "Chrome — control hover art",
				selector = ".facet-interactive.facet-pointer-live:Hover > .facet-chrome-control",
				asset = "plateHot",
			},
			{
				name = "Chrome — control pressed art",
				selector = ".facet-interactive:Press > .facet-chrome-control",
				asset = "plateDown",
			},
			{
				name = "Chrome — control selected art",
				selector = ".facet-selected > .facet-chrome-control",
				asset = "plateChosen",
			},
		}
		for _, case in cases do
			local rule = ruleNamed(model, case.name)
			expect(rule ~= nil).toBe(true)
			expect(rule.selector).toBe(case.selector)
			expect(rule.props.Image).toBe(pkg.assets[case.asset].contentId)
			-- ART ONLY. Geometry is the solver's and the tint is another rule's;
			-- a state rule that touched slice geometry would reflow on hover.
			expect(rule.props.SliceCenter).toBeNil()
			expect(rule.props.ScaleType).toBeNil()
		end
		-- `default` is the resting rule, not a fourth state rule
		expect(ruleNamed(model, "Chrome — control default art")).toBeNil()
		expect(ruleNamed(model, "Chrome — control").props.Image).toBe(pkg.assets.plate.contentId)
	end)

	it("the per-state TINT rules still apply on top of the swapped art", function()
		local model = sheet_model.buildPackage(themes.define(withControl(FULL_MAP)))
		-- the art rule and the tint rule are separate rules on separate props, so
		-- a defaulted state keeps its treatment and a stated one gets both
		expect(ruleNamed(model, "Chrome — control hover").props.ImageColor3).toBe("$ChromeTintHover")
		expect(ruleNamed(model, "Chrome — control hover").props.Image).toBeNil()
		expect(ruleNamed(model, "Chrome — control hover art").props.ImageColor3).toBeNil()
	end)

	it("a supplied `disabled` art does NOT remove the disabled treatment", function()
		-- the accessibility floor is not a variant's to opt out of
		local pkg = themes.define(withControl({ default = "plate", disabled = "plateDown" }))
		local model = sheet_model.buildPackage(pkg)
		expect(ruleNamed(model, "Chrome — control disabled art").selector).toBe(
			":NonInteractable > .facet-chrome-control"
		)
		expect(ruleNamed(model, "Chrome — control disabled").props.ImageTransparency ~= nil).toBe(true)
	end)

	it("the `error` state keys on a tag, because the engine has no error GuiState", function()
		local pkg = themes.define(withControl({ default = "plate", error = "plateDown" }))
		local model = sheet_model.buildPackage(pkg)
		expect(ruleNamed(model, "Chrome — control error art").selector).toBe(
			".facet-state-error > .facet-chrome-control"
		)
		-- and the tag is one classifyTags emits, so the rule has a way to match
		expect(sheet_model.classifyTags({ errorState = true })["facet-state-error"]).toBe(true)
		expect(sheet_model.classifyTags({})["facet-state-error"]).toBeNil()
	end)

	it("counts the extra art it costs, and a bare-string package costs nothing", function()
		local mapped = sheet_model.buildPackage(themes.define(withControl(FULL_MAP)))
		expect(mapped.census.variantRules).toBe(3)
		expect(mapped.census.variantAssets).toBe(3)
		local bare = sheet_model.buildPackage(themes.define(withControl("plate")))
		expect(bare.census.variantRules).toBe(0)
		expect(bare.census.variantAssets).toBe(0)
		expect(sheet_model.buildPackage(snapshot.neutralPackage()).census.variantAssets).toBe(0)
	end)

	it("a bare-string package compiles to exactly what it did before variants existed", function()
		-- the back-compatibility proposition, at the level that would catch a
		-- regression: same stamp, same rule set
		local bare = sheet_model.buildPackage(themes.define(withControl("plate")))
		local names: { string } = {}
		for _, rule in bare.rules do
			table.insert(names, rule.name)
		end
		for _, name in names do
			expect(string.find(name, " art", 1, true)).toBeNil()
		end
		expect(themes.define(withControl("plate")).stamp).toBe(themes.define(withControl("plate")).stamp)
	end)
end)
