--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Lute = require("../tools/vendor/verify/src/lute")
local Engine = require("./lib/native_engine")

return function(harness: Verify.Harness)
	harness:case("the seeded circuit closes with a continuous tangent and correct progress", function(t)
		local globals: { [string]: unknown } = { Vector3 = Engine.types.Vector3, CFrame = Engine.types.CFrame }
		local loader = Lute.loader.new({ globals = globals })
		local track =
			loader.require("eval/tasks/racing-hub/starter/src/shared/RaceTrack.luau") :: typeof(require("../eval/tasks/racing-hub/starter/src/shared/RaceTrack"))
		t:expect((track.point(0) - track.point(1)).Magnitude < 0.0001):toBe(true)
		local before = (track.point(0) - track.point(-0.0001)).Unit
		local after = (track.point(0.0001) - track.point(0)).Unit
		t:expect(before:Dot(after) > 0.999):toBe(true)
		for index = 0, 79 do
			local progress = index / 80
			t:expect(math.abs(track.progress(track.point(progress)) - progress) < 0.001):toBe(true)
		end
	end)
end
