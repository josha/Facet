--!strict
local Play = require("../../../../../tools/play/host/play")
local Scenario = require("./scenario")
local Coherence = require("../../../racing-hub/hidden/coherence")
Play.main(Scenario, debug.info(1, "s"))
Coherence.writeScores()
