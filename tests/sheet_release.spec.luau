--!strict
-- The Sheet's pure release and resistance policy: every sign and tie.
local t = require("./lib/testkit")
local release = require("../src/controls/sheet_release")

local STOPS = {
	{ id = "medium", height = 300, index = 1 },
	{ id = "large", height = 600, index = 2 },
}

t.describe("Sheet release policy", function()
	t.it("projects the release by the height velocity", function()
		t.expect(release.choose(STOPS, 400, 0, "medium", true)).toBe("medium")
		t.expect(release.choose(STOPS, 400, 1500, "medium", true)).toBe("large") -- 400 + 225
		t.expect(release.choose(STOPS, 500, -1500, "large", true)).toBe("medium") -- downward flick
		t.expect(release.choose(STOPS, 500, 0, "medium", true)).toBe("large")
	end)
	t.it("dismisses only where the sheet actually is", function()
		t.expect(release.choose(STOPS, 200, 0, "medium", true)).toBe("dismiss") -- below 70% of 300
		t.expect(release.choose(STOPS, 200, 0, "medium", false)).toBe("medium")
		-- a hard downward flick from barely below the detent does not dismiss
		t.expect(release.choose(STOPS, 290, -5000, "medium", true)).toBe("medium")
		-- flicked back up from below the threshold: kept
		t.expect(release.choose(STOPS, 200, 800, "medium", true)).toBe("medium") -- projected 320
	end)
	t.it("a tie keeps the current id, then the authored order", function()
		local tied = {
			{ id = "a", height = 300, index = 1 },
			{ id = "b", height = 300, index = 2 },
			{ id = "c", height = 500, index = 3 },
		}
		t.expect(release.choose(tied, 300, 0, "b", true)).toBe("b")
		t.expect(release.choose(tied, 300, 0, "c", true)).toBe("a")
		t.expect(release.choose(tied, 400, 0, "c", true)).toBe("c") -- equidistant: current
		t.expect(release.choose(tied, 400, 0, "b", true)).toBe("b")
	end)
	t.it("resistance is 1:1 inside, bounded outside, with no jump at the edge", function()
		t.expect(release.resist(450, 300, 600, 800, true, 44)).toBe(450)
		local above = release.resist(1000, 300, 600, 800, true, 44)
		t.expect(above > 600 and above < 800).toBe(true)
		t.expect(release.resist(1e9, 300, 600, 800, true, 44) <= 800).toBe(true)
		t.expect(release.resist(700, 300, 600, 600, true, 44)).toBe(600) -- no room above
		t.expect(release.resist(100, 300, 600, 800, true, 44)).toBe(100) -- free toward dismissal
		t.expect(release.resist(-50, 300, 600, 800, true, 44)).toBe(1)
		local below = release.resist(100, 300, 600, 800, false, 44)
		t.expect(below < 300 and below > 256).toBe(true)
		t.expect(release.resist(-1e9, 300, 600, 800, false, 44) >= 256).toBe(true)
		local edge = release.resist(299, 300, 600, 800, false, 44)
		t.expect(math.abs(edge - 299) < 0.05).toBe(true)
		-- monotonic
		local last = -math.huge
		for raw = -200, 1200, 25 do
			local h = release.resist(raw, 300, 600, 800, false, 44)
			t.expect(h >= last).toBe(true)
			last = h
		end
	end)
end)
