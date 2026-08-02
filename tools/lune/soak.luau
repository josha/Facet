--!strict
-- LuauUI soak command: churn + registry neutrality (design §16.1). See registry_runner.
local runAll = require("./registry_runner")
runAll("soak", require("../../tests/fixtures/soak_fixtures"), "hint: land the core churn fixtures")
