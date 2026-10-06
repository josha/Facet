--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local runner = require("../../tests/runner")
local tier = process.args[2] or "full"
local plan = serde.decode("json", fs.readFile((assert(process.args[1], "Verify plan path required"))))
local execution = runner.execute(plan, tier, process.args[3])
if not runner.accept(execution, tier) then
	process.exit(1)
end
