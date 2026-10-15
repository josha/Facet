--!strict
local Shared = require("../../extended/hidden/support")
local Base = require("../../hub-upgrades/hidden/scenario")
local Added = require("./cases")
return Shared.extend(Base, Added)
