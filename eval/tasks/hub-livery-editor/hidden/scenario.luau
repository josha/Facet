--!strict
local Shared = require("../../extended/hidden/support")
local Base = require("../../extended/hub-race-scoreboard/hidden/scenario")
local Added = require("./cases")
return Shared.extend(Base, Added)
