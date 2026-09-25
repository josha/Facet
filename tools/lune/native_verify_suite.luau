--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local testkit = require("../../tests/lib/testkit")
local specs = serde.decode("json", fs.readFile("artifacts/verify/native/specs.json"))
assert(#specs > 0, "native verification selected no specs")
local loadFailures = {}
for _, name in specs do
	print(`LOAD {name}`)
	local ending = if fs.isFile("tests/" .. name .. ".spec.luau") then ".spec" else "_spec"
	local ok, err = pcall(require, "../../tests/" .. name .. ending)
	if not ok then
		loadFailures[name] = tostring(err)
	end
end
if next(loadFailures) ~= nil then
	testkit.describe("native suite loading", function()
		for name, message in loadFailures do
			testkit.it(name, function()
				error(message, 0)
			end)
		end
	end)
end
if
	not testkit.run({
		jsonOut = "artifacts/verify/native/suite.json",
		tier = process.args[1] or "full",
		registeredSpecs = #specs,
	})
then
	process.exit(1)
end
