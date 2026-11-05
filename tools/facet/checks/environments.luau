--!strict
local Verify = require("../../vendor/verify/src/core")
local Files = require("../lib/files")
local Rule = require("../lib/rule")

local function check(context: Rule.Context): { string }
	local findings: { string } = {}
	for _, relative in Files.walk(context.path("src")) do
		local path = "src/" .. relative
		local extension = Files.extension(path)
		if Files.vendored(path) or (extension ~= ".luau" and extension ~= ".lua") then
			continue
		end
		local source = Files.read(context.path(path))
		for _, name in { "getfenv", "setfenv" } do
			local offset = string.find(source, "%f[%w_]" .. name .. "%f[^%w_]")
			if offset ~= nil then
				local _, breaks = string.gsub(string.sub(source, 1, offset - 1), "\n", "")
				table.insert(
					findings,
					("%s:%d: production code must preserve safe environments"):format(path, breaks + 1)
				)
			end
		end
	end
	return findings
end

local function register(harness: Verify.Harness, prefix: string)
	harness:case(prefix .. "calls and aliases fail outside vendor", function(test)
		Rule.within(test, {
			["src/direct.luau"] = "return getfenv(0)",
			["src/nested/alias.lua"] = "local change = setfenv; return change",
			["src/vendor/dependency.luau"] = "return getfenv(0)",
		}, function(context)
			local findings = check(context)
			Verify.expect(#findings):toBe(2)
			Verify.expect(Rule.contains(findings, "src/direct.luau:1:")):toBe(true)
			Verify.expect(Rule.contains(findings, "src/nested/alias.lua:1:")):toBe(true)
		end)
	end)
	harness:case(prefix .. "direct globals and longer identifiers pass", function(test)
		Rule.within(test, {
			["src/ambient.luau"] = "local getfenvFree = game; return getfenvFree",
			["tests/probe.luau"] = "return setfenv(1, {})",
		}, function(context)
			Verify.expect(check(context)):toEqual({})
		end)
	end)
end

local rule: Rule.Rule = {
	name = "environments",
	summary = "Production source outside vendor never reads getfenv or setfenv.",
	check = check,
	register = register,
}

return rule
