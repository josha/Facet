--!strict
local Shared = require("../../extended/hidden/support")
local Base = require("../../hub-party-invite/hidden/scenario")
local Added = require("./cases")
return Shared.extend(Base, Added)
