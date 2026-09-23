--!strict
local process = require("@lune/process")
local result = process.exec("bash", { "tools/verify.sh", "fast" })
print(result.stdout)
if result.stderr ~= "" then
	print(result.stderr)
end
process.exit(result.code)
