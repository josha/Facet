--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
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
	end)
end
