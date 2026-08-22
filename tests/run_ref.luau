--!strict
-- ONE REFERENCE SPEC, for the mutation loop (`tests/run_one` cannot reach the
-- `reference/` subfolder: it appends `.spec` to the name it is given, and these
-- files are named `<proof>_spec.luau`).
local process = require("@lune/process")
local testkit = require("./lib/testkit")

local name = process.args[1]
assert(name ~= nil and name ~= "", "usage: lune run tests/run_ref <proof>  (e.g. cartwheel)")
require("./reference/" .. name .. "_spec")
if not testkit.run() then
	process.exit(1)
end
