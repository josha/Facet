--!strict
local Shared = require("../../hidden/support")
local Base = require("../../hub-shop-categories/hidden/scenario")
local Turns = require("../../../racing-hub/hidden/turns")
return Shared.extend(Base, Turns.cases("hub-garage-sort"))
