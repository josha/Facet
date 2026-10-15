--!strict
local Shared = require("../../hidden/support")
local Base = require("../../../racing-hub/hidden/scenario")
local Turns = require("../../../racing-hub/hidden/turns")
return Shared.extend(Base, Turns.cases("hub-shop-categories"))
