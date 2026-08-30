--!strict
-- PIXEL MODE + CONTENT ADOPTION (rich-skinning-v2 package P4).
--
-- P1 shipped the two pure pieces — `snapToPixelUnit` and the `content`/
-- `contentId` normalizer — and neither had a caller. This file is the
-- INTEGRATION, which is where both could still be wrong:
--
--   R5. `rendering = "pixel"` gives the package an integer coordinate system,
--       and the SNAPSHOT is where that has to land: every length snaps UP to a
--       multiple of the unit (up, so an accessibility floor survives), durations
--       and ratios are untouched, and a NON-pixel package never enters the path
--       at all. The other two generation rules (Pixelated on every image rule,
--       integer SliceScale) are counted rather than hunted.
--   R6. `content` is the canonical field and `contentId` is the alias, and the
--       proposition is that they are ONE resolution path: two packages differing
--       only in which name they used must compile to the same bytes, emit the
--       same rules, and export the same plain strings.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local serde = require("@lune/serde")

local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")
local token_sync = require("../src/themes/token_sync")

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

local function def(id: string): any
	local base = snapshot.neutralPackage()
	return {
		identity = { id = id, displayName = id, schemaVersion = themes.SCHEMA, version = "1.0.0" },
		style = copy(base.style),
		metrics = copy(base.metrics),
		chrome = copy(base.chrome),
		assets = {},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

local function compile(d: any): any
	local pkg, report = themes.define(d)
	assert(pkg ~= nil, `fixture failed to compile: {report.errors[1] and report.errors[1].message or "?"}`)
	return pkg
end

-- ===== R5: the snapshot IS where pixel mode lands ==========================

describe("a pixel package's snapshot is an integer coordinate system", function()
	local function pixelPackage(unit: number, mutate: ((d: any) -> ())?): any
		local d = def(`pixel-snap-{unit}`)
		d.identity.rendering = "pixel"
		d.identity.pixelUnit = unit
		if mutate ~= nil then
			mutate(d)
		end
		return compile(d)
	end

	it("every LENGTH snaps up to a multiple of the unit", function()
		local snap = snapshot.resolve(pixelPackage(4), nil, {})
		for _, section in { "space", "radii", "strokes", "targetSizes", "iconSizes" } do
			for name, value in (snap :: any)[section] do
				expect(`{section}.{name}={value % 4}`).toBe(`{section}.{name}=0`)
			end
		end
		-- the neutral hairline is 1px; in a 4x pixel world the thinnest line that
		-- can exist IS 4 image pixels, and pretending otherwise is the blur
		expect(snap.strokes.hairline).toBe(4)
		expect(snap.space.m).toBe(16) -- already on grid: unchanged, not bumped
		expect(snap.controls.slider.thumbSize).toBe(20)
		expect(snap.controls.label.gap).toBe(8) -- 6 -> 8
		expect(snap.insets.control.left).toBe(12)
		expect(snap.type.body.size).toBe(16)
		expect(snap.pixelUnit).toBe(4)
	end)

	it("it snaps UP, so the accessibility floor survives the rendering flag", function()
		local snap = snapshot.resolve(pixelPackage(6), nil, {})
		-- 44 is the hit-target floor; the nearest multiple of 6 BELOW is 42, and
		-- rounding there would defeat an accessibility guarantee with a paint
		-- setting. It goes to 48.
		expect(snap.targetSizes.minimum).toBe(48)
		expect(snap.targetSizes.minimum >= themes.MIN_TARGET_SIZE).toBe(true)
	end)

	it("a value already ON the grid is not bumped by float noise", function()
		-- 44/4 in the wrong arithmetic order is 10.999999999999998, which would
		-- ceil to 11 and hand back 48 for a value that was already exact
		expect(themes.snapToPixelUnit(44, 4)).toBe(44)
		expect(themes.snapToPixelUnit(45, 4)).toBe(48)
		expect(themes.snapToPixelUnit(0, 4)).toBe(0)
		local snap = snapshot.resolve(pixelPackage(4), nil, {})
		expect(snap.targetSizes.minimum).toBe(44)
	end)

	it("DURATIONS and RATIOS are not lengths and are left alone", function()
		local snap = snapshot.resolve(pixelPackage(4), nil, {})
		local neutral = snapshot.neutral()
		for name, value in snap.motion do
			expect(`motion.{name}={value}`).toBe(`motion.{name}={(neutral.motion :: any)[name]}`)
		end
		expect(snap.type.body.lineHeight).toBe(neutral.type.body.lineHeight)
	end)

	it("an explicit OVERRIDE stays the exact number the caller asked for", function()
		-- an override is documented as marking that value theme-independent; a
		-- rendering flag silently moving it would be the opposite of that
		local snap = snapshot.resolve(pixelPackage(4), nil, {}, { ["space.m"] = 18 })
		expect(snap.space.m).toBe(18)
	end)

	it("a NON-pixel package never enters the path — no key, no movement", function()
		local plain = snapshot.resolve(compile(def("plain-snap")), nil, {})
		local neutral = snapshot.neutral()
		expect(plain.pixelUnit).toBeNil()
		expect(plain.strokes.hairline).toBe(neutral.strokes.hairline)
		expect(plain.controls.label.gap).toBe(6)
		-- every section, value for value, against the package's own authored
		-- metrics: the pixel branch cannot have touched one of them
		local authored = compile(def("plain-snap")).metrics
		for _, section in { "space", "radii", "strokes", "targetSizes" } do
			for name, value in (plain :: any)[section] do
				local source = (authored :: any)[section][name]
				if source ~= nil and name ~= "minimum" then
					expect(`{section}.{name}={value}`).toBe(`{section}.{name}={source}`)
				end
			end
		end
	end)

	it("pixelUnit without the rendering mode is an authoring error, not a no-op", function()
		local d = def("pixel-unit-only")
		d.identity.pixelUnit = 4
		local pkg, report = themes.define(d)
		expect(pkg).toBeNil()
		local named = false
		for _, err in report.errors do
			named = named or err.field == "identity.pixelUnit"
		end
		expect(named).toBe(true)
	end)

	it("generation rule 1 is COUNTED: every image rule carries Pixelated", function()
		local d = def("pixel-rules")
		d.identity.rendering = "pixel"
		d.identity.pixelUnit = 4
		d.assets = {
			plate = {
				content = "rbxassetid://501",
				sliceCenter = { x0 = 16, y0 = 16, x1 = 20, y1 = 20 },
				sliceScale = 1,
				preload = "install",
				fallback = "native",
			},
			knob = { content = "rbxassetid://502", preload = "install", fallback = "native" },
		}
		d.chrome.control = {
			kind = "nineSlice",
			asset = "plate",
			fallback = "native",
			contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
		}
		d.chrome.sliderThumb = { kind = "nineSlice", asset = "knob", sliced = false, fallback = "native" }
		d.icons = { increment = "knob" }
		local model = sheet_model.buildPackage(compile(d))
		expect(model.census.imageRules > 0).toBe(true)
		expect(model.census.pixelatedRules).toBe(model.census.imageRules)
		-- ...and a NON-pixel package stamps none of them
		local plainD = def("plain-rules")
		plainD.assets = copy(d.assets)
		plainD.chrome.control = copy(d.chrome.control)
		local plainModel = sheet_model.buildPackage(compile(plainD))
		expect(plainModel.census.imageRules > 0).toBe(true)
		expect(plainModel.census.pixelatedRules).toBe(0)
	end)

	it("generation rule 2: a fractional SliceScale is a compile error naming the slot", function()
		local d = def("pixel-frac-slice")
		d.identity.rendering = "pixel"
		d.identity.pixelUnit = 4
		d.assets = {
			plate = {
				content = "rbxassetid://503",
				sliceCenter = { x0 = 16, y0 = 16, x1 = 20, y1 = 20 },
				sliceScale = 3.5,
				preload = "install",
				fallback = "native",
			},
		}
		d.chrome.control = {
			kind = "nineSlice",
			asset = "plate",
			fallback = "native",
			contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
		}
		local pkg, report = themes.define(d)
		expect(pkg).toBeNil()
		local named = false
		for _, err in report.errors do
			named = named or (err.class == "pixelSliceScale" and err.field == "assets.plate.sliceScale")
		end
		expect(named).toBe(true)
	end)
end)

-- ===== R6: one field, two names, ONE resolution path =======================

describe("content adoption: `contentId` is an alias, never a second path", function()
	local function withAssets(id: string, field: string): any
		local d = def(id)
		d.assets = {
			plate = {
				[field] = "rbxassetid://601",
				sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
				sliceScale = 1,
				preload = "install",
				fallback = "native",
				tintRole = "accent",
			},
			knob = { [field] = "rbxassetid://602", preload = "lazy", fallback = "native" },
		}
		d.chrome.control = {
			kind = "nineSlice",
			asset = "plate",
			fallback = "native",
			contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
		}
		d.chrome.sliderThumb = { kind = "nineSlice", asset = "knob", sliced = false, fallback = "native" }
		d.icons = { increment = "knob" }
		return compile(d)
	end

	it("both spellings compile to the same bytes — same assets, same STAMP", function()
		local canonical = withAssets("content-ab", "content")
		local alias = withAssets("content-ab", "contentId")
		expect(serde.encode("json", alias.assets)).toBe(serde.encode("json", canonical.assets))
		-- the stamp is a content hash over identity/style/metrics/chrome/assets/
		-- icons, so equal stamps IS the byte-equality claim
		expect(alias.stamp).toBe(canonical.stamp)
	end)

	it("both emit the same rules, carrying the same plain strings", function()
		local canonical = sheet_model.buildPackage(withAssets("content-ab", "content"))
		local alias = sheet_model.buildPackage(withAssets("content-ab", "contentId"))
		expect(alias.stamp).toBe(canonical.stamp)
		expect(#alias.rules).toBe(#canonical.rules)
		for index, rule in canonical.rules do
			expect(alias.rules[index].name).toBe(rule.name)
			expect(alias.rules[index].selector).toBe(rule.selector)
			expect(serde.encode("json", alias.rules[index].props)).toBe(serde.encode("json", rule.props))
		end
	end)

	it("the compiled value is a plain STRING on one field, both ways round", function()
		for _, field in { "content", "contentId" } do
			local pkg = withAssets("content-ab", field)
			expect(type(pkg.assets.plate.contentId)).toBe("string")
			expect(pkg.assets.plate.contentId).toBe("rbxassetid://601")
			expect(pkg.assets.plate.content).toBeNil() -- ONE field survives, not two
		end
	end)

	it("declaring BOTH is an authoring error, because they are one field", function()
		local d = def("content-both")
		d.assets = {
			plate = {
				content = "rbxassetid://601",
				contentId = "rbxassetid://601",
				preload = "install",
				fallback = "native",
			},
		}
		local pkg, report = themes.define(d)
		expect(pkg).toBeNil()
		local named = false
		for _, err in report.errors do
			named = named or string.find(err.message, "both `content` and `contentId`", 1, true) ~= nil
		end
		expect(named).toBe(true)
	end)

	it("the EXPORT round-trip stays plain strings (the theme_sync path)", function()
		-- packages must stay serializable: a Content-typed value anywhere in
		-- authored or exported data breaks that, and rs-m7 measured that the
		-- engine coerces strings on ImageContent rules anyway
		for _, field in { "content", "contentId" } do
			local pkg = withAssets("content-ab", field)
			local encoded = serde.encode("json", pkg.assets)
			expect(string.find(encoded, "rbxassetid://601", 1, true) ~= nil).toBe(true)
			local decoded: any = serde.decode("json", encoded)
			expect(decoded.plate.contentId).toBe("rbxassetid://601")
			-- and the metric export the CLI consumes is unaffected either way
			local records = token_sync.records(pkg)
			expect(#records > 0).toBe(true)
		end
	end)
end)
