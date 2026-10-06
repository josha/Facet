--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	local release = require("../src/ui/sheet_release")

	local STOPS = {
		{ id = "medium", height = 300, index = 1 },
		{ id = "large", height = 600, index = 2 },
	}

	verifyHarness:suite("Sheet release policy", function()
		verifyHarness:case("projects the release by the height velocity", {
			id = "sheet_release::Sheet release policy::projects the release by the height velocity",
			run = function()
				Verify.expect((release.choose(STOPS, 400, 0, "medium", true))):toBe("medium")
				Verify.expect((release.choose(STOPS, 400, 1500, "medium", true))):toBe("large")
				Verify.expect((release.choose(STOPS, 500, -1500, "large", true))):toBe("medium")
				Verify.expect((release.choose(STOPS, 500, 0, "medium", true))):toBe("large")
			end,
		})
		verifyHarness:case("dismisses only where the sheet actually is", {
			id = "sheet_release::Sheet release policy::dismisses only where the sheet actually is",
			run = function()
				Verify.expect((release.choose(STOPS, 200, 0, "medium", true))):toBe("dismiss")
				Verify.expect((release.choose(STOPS, 200, 0, "medium", false))):toBe("medium")
				Verify.expect((release.choose(STOPS, 290, -5000, "medium", true))):toBe("medium")
				Verify.expect((release.choose(STOPS, 200, 800, "medium", true))):toBe("medium")
			end,
		})
		verifyHarness:case("a tie keeps the current id, then the authored order", {
			id = "sheet_release::Sheet release policy::a tie keeps the current id, then the authored order",
			run = function()
				local tied = {
					{ id = "a", height = 300, index = 1 },
					{ id = "b", height = 300, index = 2 },
					{ id = "c", height = 500, index = 3 },
				}
				Verify.expect((release.choose(tied, 300, 0, "b", true))):toBe("b")
				Verify.expect((release.choose(tied, 300, 0, "c", true))):toBe("a")
				Verify.expect((release.choose(tied, 400, 0, "c", true))):toBe("c")
				Verify.expect((release.choose(tied, 400, 0, "b", true))):toBe("b")
			end,
		})
		verifyHarness:case("resistance is 1:1 inside, bounded outside, with no jump at the edge", {
			id = "sheet_release::Sheet release policy::resistance is 1:1 inside, bounded outside, with no jump at the edge",
			run = function()
				Verify.expect((release.resist(450, 300, 600, 800, true, 44))):toBe(450)
				local above = release.resist(1000, 300, 600, 800, true, 44)
				Verify.expect(above > 600 and above < 800):toBe(true)
				Verify.expect(release.resist(1e9, 300, 600, 800, true, 44) <= 800):toBe(true)
				Verify.expect((release.resist(700, 300, 600, 600, true, 44))):toBe(600)
				Verify.expect((release.resist(100, 300, 600, 800, true, 44))):toBe(100)
				Verify.expect((release.resist(-50, 300, 600, 800, true, 44))):toBe(1)
				local below = release.resist(100, 300, 600, 800, false, 44)
				Verify.expect(below < 300 and below > 256):toBe(true)
				Verify.expect(release.resist(-1e9, 300, 600, 800, false, 44) >= 256):toBe(true)
				local edge = release.resist(299, 300, 600, 800, false, 44)
				Verify.expect(math.abs(edge - 299) < 0.05):toBe(true)
				local last = -math.huge
				for raw = -200, 1200, 25 do
					local height = release.resist(raw, 300, 600, 800, false, 44)
					Verify.expect(height >= last):toBe(true)
					last = height
				end
			end,
		})
	end)
end
