--!strict
-- ONE SPEC, for the mutation loop. `lune run tests/run_one <spec-name>` requires
-- `tests/<spec-name>.spec` and runs only what it registered.
--
-- WHY IT EXISTS. Every new check in this repo has to be seen to FAIL before it
-- is trusted (a check never seen to fail is decoration), and proving that
-- through the 45-second full suite makes the loop expensive enough that it gets
-- skipped. This is NOT a substitute for `tools/test.sh`: it runs one file, so it
-- can never produce a suite verdict, and nothing reads its output but a human or
-- an agent doing a mutation round.
local process = require("@lune/process")
local testkit = require("./lib/testkit")

local name = process.args[1]
assert(name ~= nil and name ~= "", "usage: lune run tests/run_one <spec-name>  (without the .spec suffix)")
require("./" .. name .. ".spec")
if not testkit.run() then
	process.exit(1)
end
