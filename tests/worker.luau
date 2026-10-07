--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local Lune = require("../tools/vendor/verify/src/lune")
local requireDynamic = require :: (any) -> any

local LARGE_HOST_BYTES = 60 * 1024 ^ 3

local function hostMemoryBytes(): number
	if fs.isFile("/proc/meminfo") then
		local kilobytes = string.match(fs.readFile("/proc/meminfo"), "MemTotal:%s*(%d+)")
		return (tonumber(kilobytes) or 0) * 1024
	end
	local ok, result = pcall(process.exec, "sysctl", { "-n", "hw.memsize" })
	return if ok and result.ok then tonumber((string.gsub(result.stdout, "%s", ""))) or 0 else 0
end

local capabilities = { "local-luau" }
if hostMemoryBytes() >= LARGE_HOST_BYTES then
	table.insert(capabilities, "host-memory-64g")
end

Lune.worker({
	load = function(locator: string): unknown
		return requireDynamic("../" .. string.gsub(locator, "%.luau$", ""))
	end,
}, {
	executor = "facet-lune",
	capabilities = capabilities,
	environment = { runtime = "lune" },
	caseIdStyle = "bare",
})
