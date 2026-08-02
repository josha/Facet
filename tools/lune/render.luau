--!strict
-- LuauUI render command: deterministic dumps (design §16.1). See registry_runner.
local runAll = require("./registry_runner")
runAll("render", require("../../tests/fixtures/render_fixtures"), "hint: land the layout spike dump fixtures")
