--!strict
local process = require("@std/process")
local Loader = require("../../tests/lib/loader")

local script = process.args[2]
if script == nil then
	print("usage: lute run tools/engine/headless.luau SCRIPT.luau")
	process.exit(2)
end
Loader.new().require(script :: string)
