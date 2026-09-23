--!strict

local process = require("@lune/process")
local testkit = require("./lib/testkit")

local name = process.args[1]
assert(name ~= nil and name ~= "", "usage: lune run tests/run_one <spec-name>  (without the .spec suffix)")
require("./" .. name .. ".spec")

if not testkit.run({
	jsonOut = process.env.FACET_SUITE_JSON,
	tier = "one",
	registeredSpecs = 1,
}) then
	process.exit(1)
end
