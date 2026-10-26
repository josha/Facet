--!strict

local process = require("@std/process")
local Loader = require("../../tests/lib/loader")

local run = Loader.new().require("bench/comparison/run.luau") :: typeof(require("../../bench/comparison/run"))
local code = run(process.args)
assert(type(code) == "number")
process.exit(code)
