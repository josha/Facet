--!strict

local Play = require("../../../../tools/play/host/play")
local Scenario = require("./scenario")
local Coherence = require("./coherence")

local Universal = require("./universal")
Play.main(Scenario, debug.info(1, "s"), Universal.scenario("racing-hub"))
Coherence.writeScores()
