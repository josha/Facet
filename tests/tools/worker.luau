--!strict
local Lute = require("../../tools/vendor/verify/src/lute")

local requireDynamic = (require :: unknown) :: (string) -> unknown

Lute.worker({
	load = function(locator: string): unknown
		local module = string.gsub(locator, "%.luau$", "")
		return requireDynamic("../../" .. module)
	end,
}, {
	executor = "facet-lute",
	capabilities = { "local-luau", "lute" },
	environment = { runtime = "lute" },
	caseIdStyle = "bare",
})
