--!strict
-- LuauUI interact command: action/focus traces (design §16.1). See registry_runner.
local runAll = require("./registry_runner")
runAll("interact", require("../../tests/fixtures/interact_fixtures"), "hint: land the input adapter trace fixtures")
