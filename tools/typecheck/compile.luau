--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local failed = false
for _, path in process.args do
	local ok, problem = pcall(luau.compile, fs.readFile(path))
	if not ok then
		print(`{path}: {problem}`)
		failed = true
	end
end
process.exit(if failed then 1 else 0)
