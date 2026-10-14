--!strict
local process = require("@std/process")
local Lute = require("../../tools/vendor/verify/src/lute")
local requireDynamic = (require :: unknown) :: (string) -> unknown

local capabilities = { "local-luau", "lute" }
local probed, probe = pcall(function(): process.ProcessResult
	return process.run({ "stylua", "--version" })
end)
if probed and (probe :: process.ProcessResult).ok then
	table.insert(capabilities, "stylua")
end

Lute.worker({
	load = function(locator: string): unknown
		return requireDynamic("../../" .. string.gsub(locator, "%.luau$", ""))
	end,
}, {
	executor = "facet-lute",
	capabilities = capabilities,
	environment = { runtime = "lute" },
	caseIdStyle = "bare",
})
