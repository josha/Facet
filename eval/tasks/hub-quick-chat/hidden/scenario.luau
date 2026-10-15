--!strict
local Shared = require("../../extended/hidden/support")
local Base = require("../../hub-track-vote/hidden/scenario")
local Added = require("./cases")
return Shared.extend(Base, Added)
