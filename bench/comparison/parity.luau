--!strict

local NativeApp = require("../native_app")
local Types = require("./types")

return function(workload: Types.Workload)
	local snapshots: { string } = {}
	local lanes: { Types.Lane } = { "bare", "facet" }
	for _, lane in lanes do
		assert(lane == "bare" or lane == "facet")
		local world = NativeApp({ textService = true })
		local before = world.engine.census()
		local scene = workload.prepare(world, lane)
		local ok, problem = pcall(function()
			for checkpoint = 0, workload.iterations do
				if checkpoint > 0 then
					scene.step(checkpoint)
				end
				local snapshot = scene.snapshot()
				if lane == "bare" then
					snapshots[checkpoint + 1] = snapshot
				else
					local reference = snapshots[checkpoint + 1]
					local difference = 1
					while
						difference <= math.min(#reference, #snapshot)
						and string.byte(reference, difference) == string.byte(snapshot, difference)
					do
						difference += 1
					end
					assert(
						snapshot == reference,
						`{workload.id} differs at checkpoint {checkpoint}, byte {difference}\nBARE: {string.sub(
							reference,
							difference,
							difference + 300
						)}\nFACET: {string.sub(snapshot, difference, difference + 300)}`
					)
				end
			end
		end)
		scene.stop()
		world.dispose()
		local after = world.engine.census()
		assert(after.live <= before.live, workload.id .. " leaked instances")
		assert(after.connections <= before.connections, workload.id .. " leaked connections")
		assert(ok, tostring(problem))
	end
end
