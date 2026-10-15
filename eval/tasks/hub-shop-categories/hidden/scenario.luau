--!strict
local Play = require("../../../../tools/play/host/play")
local Base = require("../../racing-hub/hidden/scenario")
local Turns = require("../../racing-hub/hidden/turns")
local Coherence = require("../../racing-hub/hidden/coherence")
local scenario: Play.Scenario = { sessions = {} }
for _, session in Base.sessions do
	local cases = table.clone(session.cases)
	for _, case in Turns.cases("hub-shop-categories") do
		table.insert(cases, case)
	end
	table.insert(cases, {
		id = "turn-coherence",
		run = function(qa, context)
			Coherence.check(qa.device.id, context)
		end,
	})
	table.insert(scenario.sessions, { device = session.device, cases = cases })
end
return scenario
