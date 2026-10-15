--!strict
local Shared = require("../../hidden/support")
local Base = require("../../hub-garage-sort/hidden/scenario")
local Turns = require("../../../racing-hub/hidden/turns")
return Shared.extend(Base, Turns.cases("hub-settings-reset"))
