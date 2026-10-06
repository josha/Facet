--!strict
local Lune = require("../tools/vendor/verify/src/lune")
local requireDynamic = require :: (any) -> any

Lune.worker({
	load = function(locator: string): unknown
		return requireDynamic("../" .. string.gsub(locator, "%.luau$", ""))
	end,
}, {
	executor = "facet-lune",
	capabilities = { "local-luau" },
	environment = { runtime = "lune" },
	caseIdStyle = "bare",
})
