--!strict
-- The five-view selection policy (roadmap Step 4, ledger row XP-B1).
--
-- The claim under test is "no catalog id is hard-coded". That is only checkable
-- if the policy is pure and can be shown a catalog, so these cases feed it a
-- RECORDED snapshot of the live Studio catalog (42 entries, read from
-- StudioDeviceSimulatorService on 2026-07-26) and assert what it picks, why,
-- and — more usefully — what it refuses to pick.
--
-- Two of those refusals are the reason the policy exists at all:
--   * Roblox classifies its Android TV entry as a **Tablet** (1920×1080 at 44
--     dpi), so a tablet row that filtered on form alone would measure a
--     television;
--   * it classifies handheld consoles as **Console** (1920×1080 at 411 dpi), so
--     a ten-foot row that filtered on form alone would measure a device held at
--     arm's length.
-- Density is the fact that separates them, and both directions are asserted.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local matrix_rows = require("../src/preview/matrix_rows")

-- A faithful subset of the live catalog (2026-07-26), including the two
-- misleading entries above. Fields are the normalized shape the driver builds
-- from GetDeviceInfoAsync.
local CATALOG = {
	{ id = "xbox", name = "Xbox One", form = "Console", w = 1920, h = 1080, scale = 1, dpi = 96 },
	{ id = "ps4", name = "PS4", form = "Console", w = 1920, h = 1080, scale = 1, dpi = 96 },
	{ id = "ps5", name = "PS5", form = "Console", w = 1920, h = 1080, scale = 1, dpi = 96 },
	-- a HANDHELD console: same form, same resolution, four times the density
	{
		id = "generic_handheld_1080",
		name = "Generic Handheld HD 1080",
		form = "Console",
		w = 1920,
		h = 1080,
		scale = 1.5,
		dpi = 411,
	},
	-- a TELEVISION that the catalog calls a Tablet
	{ id = "android_tv_1080", name = "Android TV 1080p", form = "Tablet", w = 1920, h = 1080, scale = 1, dpi = 44 },
	{ id = "average_laptop", name = "Average Laptop", form = "Desktop", w = 1366, h = 768, scale = 1, dpi = 96 },
	{ id = "hd_720", name = "HD 720", form = "Desktop", w = 1280, h = 720, scale = 1, dpi = 96 },
	{ id = "hd_1080", name = "HD 1080", form = "Desktop", w = 1920, h = 1080, scale = 1, dpi = 96 },
	{ id = "vga", name = "VGA", form = "Desktop", w = 640, h = 480, scale = 1, dpi = 96 },
	{ id = "meta_quest_3", name = "Meta Quest 3", form = "VR", w = 688, h = 736, scale = 3, dpi = 1218 },
	{ id = "iphone_7", name = "iPhone 7", form = "Phone", w = 667, h = 375, scale = 2, dpi = 326 },
	{ id = "iphone_13_pro", name = "iPhone 13 Pro", form = "Phone", w = 844, h = 390, scale = 3, dpi = 460 },
	{ id = "samsung_galaxy_a06", name = "Samsung Galaxy A06", form = "Phone", w = 800, h = 360, scale = 2, dpi = 262 },
	{ id = "samsung_galaxy_a16", name = "Samsung Galaxy A16", form = "Phone", w = 780, h = 360, scale = 3, dpi = 385 },
	{
		id = "samsung_galaxy_s22_ultra",
		name = "Samsung Galaxy S22 Ultra",
		form = "Phone",
		w = 772,
		h = 360,
		scale = 4,
		dpi = 501,
	},
	{
		id = "ipad_6th_generation",
		name = "iPad 6th Generation",
		form = "Tablet",
		w = 1024,
		h = 768,
		scale = 2,
		dpi = 264,
	},
	{
		id = "ipad_9th_generation",
		name = "iPad 9th Generation",
		form = "Tablet",
		w = 1080,
		h = 810,
		scale = 2,
		dpi = 264,
	},
	{ id = "ipad_pro_M5_13in", name = "iPad Pro M5 (13in)", form = "Tablet", w = 1376, h = 1032, scale = 2, dpi = 264 },
	{
		id = "samsung_galaxy_tab_a8",
		name = "Samsung Galaxy Tab A8",
		form = "Tablet",
		w = 960,
		h = 600,
		scale = 2,
		dpi = 216,
	},
}

local function ids(candidates): { string }
	local out = {}
	for _, c in candidates do
		table.insert(out, c.entry.id)
	end
	return out
end

local function contains(list: { string }, value: string): boolean
	for _, v in list do
		if v == value then
			return true
		end
	end
	return false
end

describe("the canonical five rows (XP-B1)", function()
	it("declares exactly the five views the plan names, in order", function()
		expect(matrix_rows.list()).toEqual({
			"compact-phone-portrait",
			"compact-phone-landscape",
			"tablet-landscape",
			"desktop-standard",
			"console-ten-foot",
		})
	end)

	it("every row states what it cannot prove, where its result is read", function()
		for _, id in matrix_rows.list() do
			local row = matrix_rows.get(id)
			expect(#row.cannotProve >= 1).toBe(true)
			expect(#row.role > 0).toBe(true)
			expect(#row.risk > 0).toBe(true)
		end
	end)

	it("hard-codes no catalog id", function()
		local source = require("@lune/fs").readFile("src/preview/matrix_rows.luau")
		for _, id in { "xbox", "ps4", "ps5", "hd_1080", "hd_720", "iphone", "ipad_", "samsung_", "android_tv" } do
			expect(string.find(source, id, 1, true)).toBe(nil)
		end
	end)
end)

describe("phone rows: narrowest, and the SAME device twice (XP-B1)", function()
	it("ranks phones narrowest-then-smallest-canvas", function()
		local res = matrix_rows.resolve(CATALOG, "compact-phone-portrait")
		-- three phones tie at a 360px minor axis; the smallest canvas wins
		expect(ids(res.candidates)[1]).toBe("samsung_galaxy_s22_ultra")
		expect(ids(res.candidates)[2]).toBe("samsung_galaxy_a16")
		expect(ids(res.candidates)[3]).toBe("samsung_galaxy_a06")
		-- the wider phones come after, never before
		expect(ids(res.candidates)[4]).toBe("iphone_7")
		expect(string.find(res.candidates[1].why, "minor axis 360px", 1, true) ~= nil).toBe(true)
	end)

	it("selects by CANVAS, and says so — the weakest-hardware question is a physical row", function()
		local source = require("@lune/fs").readFile("src/preview/matrix_rows.luau")
		expect(string.find(source, "not by how weak the hardware is", 1, true) ~= nil).toBe(true)
	end)

	it("the landscape row cannot resolve on its own — it must reuse the portrait device", function()
		local unpinned = matrix_rows.resolve(CATALOG, "compact-phone-landscape")
		expect(#unpinned.candidates).toBe(0)
		expect(unpinned.sameDeviceAs).toBe("compact-phone-portrait")

		local phone = matrix_rows.resolve(CATALOG, "compact-phone-portrait").candidates[1].entry
		local pinnedRes = matrix_rows.resolve(CATALOG, "compact-phone-landscape", phone)
		expect(#pinnedRes.candidates).toBe(1)
		expect(pinnedRes.candidates[1].entry.id).toBe(phone.id)
		-- and it says why, because two different phones would silently turn an
		-- orientation test into a comparison of two layouts
		expect(string.find(pinnedRes.candidates[1].why, "SAME device", 1, true) ~= nil).toBe(true)
	end)
end)

describe("tablet row: representative, and not a television (XP-B1)", function()
	it("excludes the low-density panel the catalog calls a Tablet", function()
		local res = matrix_rows.resolve(CATALOG, "tablet-landscape")
		expect(contains(ids(res.candidates), "android_tv_1080")).toBe(false)
		local reasons = {}
		for _, e in res.excluded do
			reasons[e.id] = e.reason
		end
		expect(reasons.android_tv_1080 ~= nil).toBe(true)
		expect(string.find(reasons.android_tv_1080, "television", 1, true) ~= nil).toBe(true)
	end)

	it("picks the median tablet by canvas area, not an extreme", function()
		local res = matrix_rows.resolve(CATALOG, "tablet-landscape")
		-- areas: tab_a8 576000, ipad6 786432, ipad9 874800, proM5 1420032 -> median rank 2
		expect(res.candidates[1].entry.id).toBe("ipad_6th_generation")
		expect(string.find(res.candidates[1].why, "median", 1, true) ~= nil).toBe(true)
		-- the extremes are still offered as fallbacks, just not first
		expect(contains(ids(res.candidates), "ipad_pro_M5_13in")).toBe(true)
		expect(contains(ids(res.candidates), "samsung_galaxy_tab_a8")).toBe(true)
	end)
end)

describe("desktop row: the project's standard viewport (XP-B1)", function()
	it("prefers the preset that is exactly the standard development viewport", function()
		local res = matrix_rows.resolve(CATALOG, "desktop-standard")
		expect(res.candidates[1].entry.id).toBe("hd_720")
		expect(string.find(res.candidates[1].why, "1280x720", 1, true) ~= nil).toBe(true)
		-- then the smallest preset at or above it, never the biggest monitor first
		expect(res.candidates[2].entry.id).toBe("average_laptop")
	end)
end)

describe("console row: a television, not a handheld (XP-B1)", function()
	it("excludes the high-density handheld the catalog calls a Console", function()
		local res = matrix_rows.resolve(CATALOG, "console-ten-foot")
		expect(contains(ids(res.candidates), "generic_handheld_1080")).toBe(false)
		local reasons = {}
		for _, e in res.excluded do
			reasons[e.id] = e.reason
		end
		expect(string.find(reasons.generic_handheld_1080, "arm's length", 1, true) ~= nil).toBe(true)
	end)

	it("offers every 1920x1080 television-density console, deterministically ordered", function()
		local res = matrix_rows.resolve(CATALOG, "console-ten-foot")
		expect(ids(res.candidates)).toEqual({ "ps4", "ps5", "xbox" })
		-- the ORDER is the point: a matrix that silently changed which device it
		-- measured would not be a regression gate
		local again = matrix_rows.resolve(CATALOG, "console-ten-foot")
		expect(ids(again.candidates)).toEqual(ids(res.candidates))
	end)
end)

describe("requirements are checked against the RUNNING session (XP-B1)", function()
	it("passes a healthy console observation", function()
		local row = matrix_rows.get("console-ten-foot")
		local result = matrix_rows.checkRequirements(row, {
			form = "Console",
			viewport = { w = 1920, h = 1078 },
			dpi = 96,
			displaySize = "Large",
		})
		expect(result.ok).toBe(true)
	end)

	it("fails a console preset that never entered the ten-foot presentation", function()
		local row = matrix_rows.get("console-ten-foot")
		local result = matrix_rows.checkRequirements(row, {
			form = "Console",
			viewport = { w = 1920, h = 1078 },
			dpi = 96,
			displaySize = "Medium", -- the fact that drives the whole ten-foot path
		})
		expect(result.ok).toBe(false)
		expect(string.find(result.problems[1], "large desktop and call it a console", 1, true) ~= nil).toBe(true)
	end)

	it("accepts the emulator's fitted viewport, but not a different one", function()
		local row = matrix_rows.get("desktop-standard")
		-- SetResolutionAsync(1280, 720) reports back 1280x719 on Studio 0.731;
		-- rejecting that made the desktop row unpassable, which is strictness
		-- that proves nothing
		expect(matrix_rows.checkRequirements(row, { form = "Desktop", viewport = { w = 1280, h = 719 } }).ok).toBe(true)
		expect(matrix_rows.checkRequirements(row, { form = "Desktop", viewport = { w = 1280, h = 720 } }).ok).toBe(true)
		-- a genuinely different viewport is still a failure
		local wrong = matrix_rows.checkRequirements(row, { form = "Desktop", viewport = { w = 1920, h = 1080 } })
		expect(wrong.ok).toBe(false)
		expect(string.find(wrong.problems[1], "not the standard", 1, true) ~= nil).toBe(true)
	end)

	it("fails a blind 1x1 viewport rather than reporting a layout", function()
		local row = matrix_rows.get("desktop-standard")
		local result = matrix_rows.checkRequirements(row, { form = "Desktop", viewport = { w = 1, h = 1 } })
		expect(result.ok).toBe(false)
		expect(string.find(result.problems[1], "blind instrument", 1, true) ~= nil).toBe(true)
	end)

	it("fails when the compact phone row is not compact", function()
		local row = matrix_rows.get("compact-phone-portrait")
		local ok = matrix_rows.checkRequirements(row, { form = "Phone", viewport = { w = 359, h = 718 } })
		expect(ok.ok).toBe(true)
		local bad = matrix_rows.checkRequirements(row, { form = "Phone", viewport = { w = 820, h = 1180 } })
		expect(bad.ok).toBe(false)
		expect(string.find(bad.problems[1], "compact ceiling", 1, true) ~= nil).toBe(true)
	end)
end)
