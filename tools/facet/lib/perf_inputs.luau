--!strict

local Run = require("./run")

local Inputs = {}
local ROOTS = { "src/", "bench/", "examples/", "tests/", "tools/", "eval/" }
local FILES =
	{ ["rokit.toml"] = true, [".luaurc"] = true, ["default.project.json"] = true, [".github/workflows/ci.yml"] = true }

function Inputs.affects(path: string): boolean
	if FILES[path] or string.sub(path, -5) == ".luau" then
		return true
	end
	for _, root in ROOTS do
		if string.sub(path, 1, #root) == root then
			return true
		end
	end
	return false
end

function Inputs.run(base: string?): number
	if base == nil or base == "" then
		print("perf affected: a base commit is required")
		return 2
	end
	local result = Run.capture({ "git", "diff", "--name-only", "--no-renames", "-z", base, "HEAD", "--" })
	if not result.ok then
		print(result.stderr)
		return 2
	end
	local changed: { string } = {}
	for path in string.gmatch(result.stdout, "[^%z]+") do
		if Inputs.affects(path) then
			table.insert(changed, path)
		end
	end
	if #changed == 0 then
		print("perf affected: no paired performance inputs changed")
		return 3
	end
	print(`perf affected: {#changed} paired performance input(s) changed`)
	for _, path in changed do
		print("  " .. path)
	end
	return 0
end

return table.freeze(Inputs)
