--!strict
local Play = require("../../../../tools/play/host/play")
local Scenario = require("./scenario")
local Coherence = require("../../racing-hub/hidden/coherence")
local Universal = require("../../racing-hub/hidden/universal")
Play.main(Scenario, debug.info(1, "s"), Universal.scenario("hub-upgrades"))
Coherence.writeScores()
