--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Contracts = require("./lib/live_contracts")

return function(harness: Verify.Harness)
	Contracts.register(harness, 2)
end
