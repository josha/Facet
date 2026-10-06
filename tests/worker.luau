--!strict
local process = require("@lune/process")
local Lune = require("../tools/vendor/verify/src/lune")
local Verify = require("../tools/vendor/verify/src/core")
local requireDynamic = require :: (any) -> any

local tier = process.env.FACET_TIER or "one"

Lune.worker({
	load = function(locator: string): unknown
		local register = requireDynamic("../" .. string.gsub(locator, "%.luau$", ""))
		assert(type(register) == "function", "a spec must return a Verify registration function")
		return function(harness: Verify.Harness)
			register(harness, tier)
		end
	end,
}, {
	executor = "facet-lune",
	capabilities = { "local-luau" },
	environment = { runtime = "lune", tier = tier },
	caseIdStyle = "bare",
})
