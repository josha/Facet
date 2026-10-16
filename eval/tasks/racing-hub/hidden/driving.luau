--!strict

local Play = require("../../../../tools/play/host/play")
local Check = require("../../../../tools/play/host/check")

local scenario: Play.Scenario = {
	sessions = {
		{
			device = "desktop",
			cases = {
				{
					id = "native-seat-driving",
					tier = "spec",
					timeoutSeconds = 90,
					run = function(qa, context)
						qa:admin("driving")
						local before = qa:admin("state")
						local result = qa:call("racingDrive")
						Check.that(
							context,
							Check.number(result, "distance") > 30,
							"native seat throttle moves the live kart"
						)
						Check.that(
							context,
							Check.number(result, "steer") > 0.05,
							"native seat steering turns the live kart"
						)
						Check.that(
							context,
							Check.number(result, "progress") > 3 / 16,
							"ordered checkpoints advance on the server"
						)
						Check.that(
							context,
							Check.eventually(3, function()
								local after = qa:admin("state")
								local positions = Check.field(after, "state", "positions")
								local previous = Check.field(before, "state", "positions")
								if type(positions) ~= "table" then
									return false
								end
								local names = positions :: { unknown }
								local earlier = if type(previous) == "table" then previous :: { unknown } else {}
								return #names == 8 and table.find(names, "You") ~= nil and names[1] ~= earlier[1]
							end),
							"live standings update as racers drive"
						)
						qa:dump("native-driving")
						qa:admin("phase", { phase = "Results", seconds = 120 })
					end,
				},
			},
		},
	},
}

Play.main(scenario, debug.info(1, "s"))
