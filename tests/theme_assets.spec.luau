--!strict
-- THE ASSET ENTRY: content adoption + slice geometry (ADR-0020 R6 and the
-- art-lane finding, rich-skinning-v2 package P1).
--
--   1. `content` is the canonical field and `contentId` is the kept alias; both
--      normalize to ONE plain string at define time, so downstream has exactly
--      one resolution path and an export stays serializable (rs-m7 measured that
--      even a Content.fromUri RULE round-trips as a string, which is why this
--      stage ships no materialization machinery at all);
--   2. rule emission REJECTS object-sourced Content: `SetProperties` accepts it,
--      reports nothing and paints nothing — the fourth accepted-but-inert engine
--      trap this project has catalogued;
--   3. a slice centre with no extent is a compile error. The art lane hit it
--      twice: at `2*border == the sliced dimension` the centre rect is EMPTY and
--      the engine paints a silent blank middle.

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

local function def(asset: any): any
	local base = snapshot.neutralPackage()
	return {
		identity = {
			id = "asset-test",
			displayName = "Asset Test",
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = copy(base.style),
		metrics = copy(base.metrics),
		chrome = copy(base.chrome),
		assets = { plate = asset },
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

local function skinned(asset: any): any
	local d = def(asset)
	d.chrome.panel = {
		kind = "nineSlice",
		asset = "plate",
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

local SLICED = {
	sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
	width = 32,
	height = 32,
	preload = "install",
	fallback = "native",
}

local function sliced(extra: any): any
	local out: any = copy(SLICED)
	for k, v in extra do
		out[k] = v
	end
	return out
end

describe("themes.define: `content` is canonical and `contentId` is the alias", function()
	it("both spell the same package — same data, same stamp", function()
		local viaContent = themes.define(skinned(sliced({ content = "rbxassetid://51" })))
		local viaContentId = themes.define(skinned(sliced({ contentId = "rbxassetid://51" })))
		expect(viaContent ~= nil).toBe(true)
		expect(viaContentId ~= nil).toBe(true)
		-- ONE resolution path: the compiled package carries the string under the
		-- field every existing reader already resolves
		expect(viaContent.assets.plate.contentId).toBe("rbxassetid://51")
		expect(viaContent.assets.plate.content).toBeNil()
		-- ...and the two are indistinguishable afterwards, stamp included
		expect(viaContent.stamp).toBe(viaContentId.stamp)
		expect(chrome_slots.planFor(viaContent, "panel").contentId).toBe(
			chrome_slots.planFor(viaContentId, "panel").contentId
		)
	end)

	it("the exported data stays a plain string, so a package stays serializable", function()
		local pkg = themes.define(skinned(sliced({ content = "rbxassetid://51" })))
		expect(type(pkg.assets.plate.contentId)).toBe("string")
		local model = sheet_model.buildPackage(pkg)
		local rule: any = nil
		for _, entry in model.rules do
			if entry.name == "Chrome — panel" then
				rule = entry
			end
		end
		-- the rule carries the string VERBATIM: the engine coerces it onto
		-- Image or ImageContent alike (rs-m7), so no shim exists to go wrong
		expect(rule.props.Image).toBe("rbxassetid://51")
	end)

	it("rejects declaring both, because that is two sources for one string", function()
		local _, report = themes.define(skinned(sliced({ content = "rbxassetid://51", contentId = "rbxassetid://52" })))
		expect(report.ok).toBe(false)
		local entry: any = nil
		for _, e in report.errors do
			if e.field == "assets.plate.content" then
				entry = e
			end
		end
		expect(entry ~= nil).toBe(true)
		expect(string.find(entry.fix, "delete", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an asset with neither", function()
		local _, report = themes.define(def(sliced({})))
		expect(report.ok).toBe(false)
	end)
end)

describe("sheet_model: object-sourced Content is a COMPILE error, not a silent blank", function()
	it("refuses a Content-shaped value on Image or ImageContent, citing the trap", function()
		for _, prop in { "Image", "ImageContent" } do
			local ok, err = pcall(function()
				sheet_model.checkContentValue("Chrome — panel", prop, { kind = "content", source = "object" })
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), prop, 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "paints NOTHING", 1, true) ~= nil).toBe(true)
			-- and it names the ONE legal escape hatch, so nobody invents another
			expect(string.find(tostring(err), "adapter instance write", 1, true) ~= nil).toBe(true)
		end
	end)

	it("an author-supplied rule goes through the same gate", function()
		local pkg = themes.define(skinned(sliced({ content = "rbxassetid://51" })))
		local ok, err = pcall(function()
			sheet_model.buildPackage(pkg, {
				rules = {
					{
						name = "Editable skin",
						selector = ".facet-chrome-panel",
						props = { ImageContent = { kind = "content", source = "object" } },
					},
				},
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Editable skin", 1, true) ~= nil).toBe(true)
	end)

	it("a plain string passes, and every other property is left alone", function()
		expect(pcall(sheet_model.checkContentValue, "r", "Image", "rbxassetid://1")).toBe(true)
		expect(pcall(sheet_model.checkContentValue, "r", "ImageContent", "rbxassetid://1")).toBe(true)
		expect(pcall(sheet_model.checkContentValue, "r", "ImageColor3", { kind = "color", r = 1, g = 1, b = 1 })).toBe(
			true
		)
	end)
end)

describe("themes.define: a slice centre that paints a silent blank middle", function()
	it("accepts art whose borders leave a real centre", function()
		local pkg, report = themes.define(skinned(sliced({ content = "rbxassetid://51" })))
		expect(report.ok).toBe(true)
		expect(pkg.assets.plate.width).toBe(32)
	end)

	it("rejects 2*border == the dimension, which is an EMPTY centre", function()
		-- the art lane's defect, twice: a 32px source sliced with a 16px border
		local _, report = themes.define(skinned({
			content = "rbxassetid://51",
			sliceCenter = { x0 = 16, y0 = 8, x1 = 16, y1 = 24 },
			width = 32,
			height = 32,
			preload = "install",
			fallback = "native",
		}))
		expect(report.ok).toBe(false)
		local entry = firstOfClass(report, "invalidSlice")
		expect(entry ~= nil).toBe(true)
		expect(entry.field).toBe("assets.plate.sliceCenter")
		expect(string.find(entry.message, "blank", 1, true) ~= nil).toBe(true)
		expect(string.find(entry.fix, "reduce the border", 1, true) ~= nil).toBe(true)
	end)

	it("rejects borders that sum past the source even when the rect is not inverted", function()
		-- x borders 20 + 20 on a 32px source: the rect reads fine in isolation
		-- and is impossible against the art
		local _, report = themes.define(skinned({
			content = "rbxassetid://51",
			sliceCenter = { x0 = 20, y0 = 8, x1 = 12, y1 = 24 },
			width = 32,
			height = 32,
			preload = "install",
			fallback = "native",
		}))
		expect(report.ok).toBe(false)
		expect(firstOfClass(report, "invalidSlice") ~= nil).toBe(true)
	end)

	it("rejects a centre that falls outside the declared source", function()
		local _, report = themes.define(skinned(sliced({
			content = "rbxassetid://51",
			sliceCenter = { x0 = 8, y0 = 8, x1 = 40, y1 = 24 },
		})))
		expect(report.ok).toBe(false)
		local entry = firstOfClass(report, "invalidSlice")
		expect(string.find(entry.message, "outside", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an inverted or malformed centre WITHOUT a declared source size", function()
		-- the guard is not conditional on width/height: an inverted rect is
		-- wrong on any art, and it used to reach an assert deep in the plan
		local _, inverted = themes.define(skinned({
			content = "rbxassetid://51",
			sliceCenter = { x0 = 24, y0 = 8, x1 = 8, y1 = 24 },
			preload = "install",
			fallback = "native",
		}))
		expect(inverted.ok).toBe(false)
		expect(string.find(firstOfClass(inverted, "invalidSlice").message, "no extent", 1, true) ~= nil).toBe(true)

		local _, positional = themes.define(skinned({
			content = "rbxassetid://51",
			sliceCenter = { 8, 8, 24, 24 },
			preload = "install",
			fallback = "native",
		}))
		expect(positional.ok).toBe(false)
		expect(firstOfClass(positional, "invalidSlice") ~= nil).toBe(true)
	end)

	it("rejects a non-positive declared source size", function()
		local _, report = themes.define(skinned(sliced({ content = "rbxassetid://51", width = 0 })))
		expect(report.ok).toBe(false)
		expect(firstOfClass(report, "invalidSlice").field).toBe("assets.plate.width")
	end)

	it("art with no declared size still compiles — the sizes are optional", function()
		local pkg, report = themes.define(skinned({
			content = "rbxassetid://51",
			sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
			preload = "install",
			fallback = "native",
		}))
		expect(report.ok).toBe(true)
		expect(pkg.assets.plate.width).toBeNil()
	end)
end)
