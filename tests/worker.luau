--!strict
local system = require("@std/system")
local Lute = require("../tools/vendor/verify/src/lute")
local Loader = require("./lib/loader")

local LARGE_HOST_BYTES = 60 * 1024 ^ 3

local capabilities = { "local-luau", "lute" }
if system.totalMemory() >= LARGE_HOST_BYTES then
	table.insert(capabilities, "host-memory-64g")
end

local loader = Loader.new()

Lute.worker({
	load = loader.require,
}, {
	executor = "facet-lute",
	capabilities = capabilities,
	environment = { runtime = "lute" },
	caseIdStyle = "bare",
})
