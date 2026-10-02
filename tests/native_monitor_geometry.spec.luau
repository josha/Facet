--!strict
local t = require("./lib/testkit")
local spatial = require("../examples/virtual_monitors/spatial")

t.describe("native monitor geometry", function()
	t.it("faces one viewing point with equal distances and equal bezel gaps", function()
		local previous: { x: number, z: number }?, firstGap: number?
		for index = 1, 4 do
			local x, z, yaw = spatial.pose(index, 4)
			local dx, dz = -x, spatial.CENTER_Z - z
			local distance = math.sqrt(dx * dx + dz * dz)
			t.expect(math.abs(distance - spatial.RADIUS) < 0.0001).toBe(true)
			t.expect(math.abs(dx / distance + math.sin(yaw)) < 0.0001).toBe(true)
			t.expect(math.abs(dz / distance + math.cos(yaw)) < 0.0001).toBe(true)
			local left = { x = x - 5.52 * math.cos(yaw), z = z + 5.52 * math.sin(yaw) }
			local right = { x = x + 5.52 * math.cos(yaw), z = z - 5.52 * math.sin(yaw) }
			if previous then
				local gap = math.sqrt((previous.x - right.x) ^ 2 + (previous.z - right.z) ^ 2)
				t.expect(gap > 0.5).toBe(true)
				if firstGap then
					t.expect(math.abs(gap - firstGap) < 0.0001).toBe(true)
				else
					firstGap = gap
				end
			end
			previous = left
		end
	end)
end)

return t
