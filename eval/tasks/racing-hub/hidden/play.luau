--!strict

local Play = require("../../../../tools/play/host/play")
local Scenario = require("./scenario")
local Coherence = require("./coherence")

Play.main(Scenario, debug.info(1, "s"))
Coherence.writeScores()
