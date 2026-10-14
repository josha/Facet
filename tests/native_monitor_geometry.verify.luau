--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local spatial = require("../examples/virtual_monitors/spatial")

	verifyHarness:suite("native monitor geometry", function()
		verifyHarness:case("faces one viewing point with equal distances and equal bezel gaps", {
			id = "native_monitor_geometry::native monitor geometry::faces one viewing point with equal distances and equal bezel gaps",
			run = function()
				local previous: { x: number, z: number }?, firstGap: number?
				for index = 1, 4 do
					local x, z, yaw = spatial.pose(index, 4)
					local dx, dz = -x, spatial.CENTER_Z - z
					local distance = math.sqrt(dx * dx + dz * dz)
					Verify.expect(math.abs(distance - spatial.RADIUS) < 0.0001):toBe(true)
					Verify.expect(math.abs(dx / distance + math.sin(yaw)) < 0.0001):toBe(true)
					Verify.expect(math.abs(dz / distance + math.cos(yaw)) < 0.0001):toBe(true)
					local left = { x = x - 5.52 * math.cos(yaw), z = z + 5.52 * math.sin(yaw) }
					local right = { x = x + 5.52 * math.cos(yaw), z = z - 5.52 * math.sin(yaw) }
					if previous then
						local gap = math.sqrt((previous.x - right.x) ^ 2 + (previous.z - right.z) ^ 2)
						Verify.expect(gap > 0.5):toBe(true)
						if firstGap then
							Verify.expect(math.abs(gap - firstGap) < 0.0001):toBe(true)
						else
							firstGap = gap
						end
					end
					previous = left
				end
			end,
		})
	end)

	return nil
end
