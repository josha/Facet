--!strict
-- PIXEL-ART MODE (rich-skinning-v2 package P1).
--
-- `rendering = "pixel"` + `pixelUnit = N` turns on three generation rules, each
-- of which rs-m5 measured a failure for:
--
--   1. every image-bearing rule carries ResampleMode=Pixelated — censused, so a
--      missed rule is a COUNTED defect (`pixelatedRules == imageRules`) instead
--      of a visual hunt through captures;
--   2. SliceScale locks to integers at compile — a fractional scale stays
--      hard-edged but visibly UNEVEN, which is the worst failure mode because it
--      still looks crisp at a glance;
--   3. snapshot metrics snap UP to unit multiples — floors clamp up, so an
--      accessibility floor survives the snap instead of being rounded through.
--
-- ...and a non-pixel package is byte-unaffected by all three.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")

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

local function def(rendering: string?, pixelUnit: number?): any
	local base = snapshot.neutralPackage()
	return {
		identity = {
			id = "pixel-test",
			displayName = "Pixel Test",
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
			rendering = rendering,
			pixelUnit = pixelUnit,
		},
		style = copy(base.style),
		metrics = copy(base.metrics),
		chrome = copy(base.chrome),
		assets = {
			plate = {
				content = "rbxassetid://41",
				sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
				width = 32,
				height = 32,
				sliceScale = 2,
				preload = "install",
				fallback = "native",
			},
			plateHot = {
				content = "rbxassetid://42",
				sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
				width = 32,
				height = 32,
				sliceScale = 2,
				preload = "install",
				fallback = "native",
			},
		},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

local function skinned(rendering: string?, pixelUnit: number?): any
	local d = def(rendering, pixelUnit)
	d.chrome.control = {
		kind = "nineSlice",
		asset = { default = "plate", hover = "plateHot" },
		fallback = "native",
		contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
	}
	return d
end

local function firstOfClass(report: any, class: string): any
	for _, entry in report.errors do
		if entry.class == class then
			return entry
		end
	end
	return nil
end

describe("themes.define: the pixel declaration", function()
	it("compiles rendering + an integer unit, and reports them", function()
		local pkg, report = themes.define(def("pixel", 2))
		expect(report.ok).toBe(true)
		expect(themes.isPixelPackage(pkg)).toBe(true)
		expect(themes.pixelUnitOf(pkg)).toBe(2)
	end)

	it("a package that says nothing is standard, and has no unit at all", function()
		local pkg = themes.define(def())
		expect(themes.isPixelPackage(pkg)).toBe(false)
		-- nil, not 1: a caller skips the whole path rather than snapping to a
		-- unit nobody asked for
		expect(themes.pixelUnitOf(pkg)).toBeNil()
		expect(themes.isPixelPackage(snapshot.neutralPackage())).toBe(false)
	end)

	it("rejects an unknown rendering mode, naming the modes", function()
		local _, report = themes.define(def("retro", nil))
		expect(report.ok).toBe(false)
		local entry: any = nil
		for _, e in report.errors do
			if e.field == "identity.rendering" then
				entry = e
			end
		end
		expect(entry ~= nil).toBe(true)
		expect(string.find(entry.fix, "pixel", 1, true) ~= nil).toBe(true)
	end)

	it("rejects a pixel package with no unit, and a fractional or zero one", function()
		local _, missing = themes.define(def("pixel", nil))
		expect(missing.ok).toBe(false)
		expect(string.find(missing.errors[1].field, "pixelUnit", 1, true) ~= nil).toBe(true)
		for _, bad in { 1.5, 0, -2 } do
			local _, report = themes.define(def("pixel", bad))
			expect(report.ok).toBe(false)
		end
	end)

	it("rejects a unit on a package that is not pixel — it would do nothing", function()
		local _, report = themes.define(def(nil, 4))
		expect(report.ok).toBe(false)
		local entry: any = nil
		for _, e in report.errors do
			if e.field == "identity.pixelUnit" then
				entry = e
			end
		end
		expect(string.find(entry.message, "does nothing", 1, true) ~= nil).toBe(true)
	end)

	it("locks SliceScale to integers, naming the slot that uses the art", function()
		local d = skinned("pixel", 2)
		d.assets.plate.sliceScale = 1.5
		local _, report = themes.define(d)
		expect(report.ok).toBe(false)
		local entry = firstOfClass(report, "pixelSliceScale")
		expect(entry ~= nil).toBe(true)
		expect(entry.field).toBe("assets.plate.sliceScale")
		expect(string.find(entry.message, "chrome.control.asset", 1, true) ~= nil).toBe(true)
		-- the REASON, which is why this is an error and not a warning
		expect(string.find(entry.message, "UNEVEN", 1, true) ~= nil).toBe(true)
		-- ...and the same package in standard rendering compiles: the lock is
		-- the pixel mode's, not a new rule for everyone
		local standard = skinned(nil, nil)
		standard.assets.plate.sliceScale = 1.5
		expect((themes.define(standard))).never().toBeNil()
	end)

	it("requires slice BORDERS on the pixel grid", function()
		local d = skinned("pixel", 4)
		-- 8px borders under a unit of 4 are fine; 6 is off the grid
		d.assets.plate.sliceCenter = { x0 = 6, y0 = 8, x1 = 24, y1 = 24 }
		local _, report = themes.define(d)
		expect(report.ok).toBe(false)
		local entry = firstOfClass(report, "pixelSliceBorder")
		expect(entry ~= nil).toBe(true)
		expect(entry.field).toBe("assets.plate.sliceCenter")
		expect(string.find(entry.message, "pixelUnit", 1, true) ~= nil).toBe(true)
		-- a standard package never sees this rule
		local standard = skinned(nil, nil)
		standard.assets.plate.sliceCenter = { x0 = 6, y0 = 8, x1 = 24, y1 = 24 }
		expect((themes.define(standard))).never().toBeNil()
	end)
end)

describe("themes.snapToPixelUnit: floors clamp UP", function()
	it("snaps up to the next multiple and leaves an exact one alone", function()
		expect(themes.snapToPixelUnit(44, 4)).toBe(44)
		expect(themes.snapToPixelUnit(45, 4)).toBe(48)
		expect(themes.snapToPixelUnit(43, 4)).toBe(44)
		expect(themes.snapToPixelUnit(0, 4)).toBe(0)
		expect(themes.snapToPixelUnit(1, 4)).toBe(4)
	end)

	it("is idempotent, monotone, and never returns less than it was given", function()
		-- property-style: the invariants that make it safe to apply to an
		-- accessibility floor
		for _, unit in { 1, 2, 3, 4, 8 } do
			local previous = -math.huge
			for value = 0, 60 do
				local snapped = themes.snapToPixelUnit(value, unit)
				expect(snapped >= value).toBe(true) -- never rounds a floor DOWN
				expect(snapped % unit).toBe(0) -- lands on the grid
				expect(snapped - value < unit).toBe(true) -- and never overshoots
				expect(themes.snapToPixelUnit(snapped, unit)).toBe(snapped) -- idempotent
				expect(snapped >= previous).toBe(true) -- monotone
				previous = snapped
			end
		end
	end)

	it("a unit of 1 is the identity on integers", function()
		for value = 0, 20 do
			expect(themes.snapToPixelUnit(value, 1)).toBe(value)
		end
		expect(themes.snapToPixelUnit(20.25, 1)).toBe(21)
	end)

	it("float noise cannot bump an exact multiple a whole unit", function()
		-- 44/4 lands at 10.999999999999998 in the wrong arithmetic order, which
		-- would snap a 44px target floor to 48
		for _, pair in { { 44, 4 }, { 48, 8 }, { 36, 3 }, { 120, 12 } } do
			expect(themes.snapToPixelUnit(pair[1], pair[2])).toBe(pair[1])
		end
	end)

	it("refuses a unit that is not an integer >= 1", function()
		for _, unit in { 0, -1, 1.5 } do
			expect(pcall(themes.snapToPixelUnit, 10, unit)).toBe(false)
		end
		expect(pcall(themes.snapToPixelUnit, 0 / 0, 2)).toBe(false)
	end)
end)

describe("buildPackage: the Pixelated stamp is a counted claim", function()
	it("every image-bearing rule carries it, and the census proves it", function()
		local model = sheet_model.buildPackage(themes.define(skinned("pixel", 2)))
		expect(model.census.imageRules > 0).toBe(true)
		expect(model.census.pixelatedRules).toBe(model.census.imageRules)
		local counted = 0
		for _, rule in model.rules do
			-- an ICON rule is image-bearing without carrying an `Image`: the adapter
			-- picks the content id per node, so the rule owns only the tint and the
			-- resample stamp. Count it by its stamp, which is what this test is about.
			if
				rule.props.Image ~= nil
				or (rule.props.ResampleMode ~= nil and string.find(rule.name, "Icon", 1, true) == 1)
			then
				counted += 1
				expect(rule.props.ResampleMode.kind).toBe("enum")
				-- the PROPERTY is ResampleMode; the ENUM is ResamplerMode
				expect(rule.props.ResampleMode.enum).toBe("ResamplerMode")
				expect(rule.props.ResampleMode.item).toBe("Pixelated")
			end
		end
		expect(counted).toBe(model.census.imageRules)
	end)

	it("the per-state art rules carry it too — a hover swap must not go soft", function()
		local model = sheet_model.buildPackage(themes.define(skinned("pixel", 2)))
		local hover: any = nil
		for _, rule in model.rules do
			if rule.name == "Chrome — control hover art" then
				hover = rule
			end
		end
		expect(hover ~= nil).toBe(true)
		expect(hover.props.ResampleMode.item).toBe("Pixelated")
	end)

	it("a standard package carries NO ResampleMode anywhere, and counts zero", function()
		local model = sheet_model.buildPackage(themes.define(skinned(nil, nil)))
		expect(model.census.imageRules > 0).toBe(true)
		expect(model.census.pixelatedRules).toBe(0)
		for _, rule in model.rules do
			expect(rule.props.ResampleMode).toBeNil()
		end
		-- ...and the flat baseline's only image rules are the framework icon tints
		-- (the framework's own icon set (compact-label stage) resolves BELOW a package's map, so a package that declares nothing still DRAWS pictures — and `ImageColor3` is sheet-owned, so each of those names needs its tint rule or the art paints pure white. Found live in the running showcase: Studio Neutral emitted 70 rules and ZERO icon rules while `resolveIcon` returned real art for the same names.), none of which carry a resample stamp on a STANDARD package.
		local flat = sheet_model.buildPackage(snapshot.neutralPackage())
		expect(flat.census.imageRules > 0).toBe(true)
		expect(flat.census.pixelatedRules).toBe(0)
	end)

	it("a pixel LAYER stack is stamped on every layer", function()
		local d = def("pixel", 2)
		d.chrome.panel = {
			kind = "layered",
			fallback = "native",
			contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
			layers = {
				{ kind = "fill", asset = "plate" },
				{ kind = "frame", asset = "plateHot" },
			},
		}
		local model = sheet_model.buildPackage(themes.define(d))
		expect(model.census.layers).toBe(2)
		expect(model.census.pixelatedRules).toBe(model.census.imageRules)
	end)
end)
