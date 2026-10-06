--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local workers = require("./run_each_spec")
local Verify = require("../vendor/verify/src/core")
local input = serde.decode("json", fs.readFile((assert(process.args[1], "worker plan input required"))))
local execution = workers.execute(input)
print(Verify.format(execution.report))
if not workers.accept(execution, input.tier or "one") then
	process.exit(1)
end
