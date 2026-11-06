--!strict
local Verify = require("../../vendor/verify/src/core")
local Files = require("../lib/files")
local Rule = require("../lib/rule")

local SEAM = "src/ui/host_selection.luau"
local OWNERS: { [string]: string } = {
	[SEAM] = "the host seam reads and writes the native selection",
	["src/ui/context_observe.luau"] = "the shared selection observation installs the seam",
	["src/ui/engine_types.luau"] = "the generated engine types declare the observation",
}
local NAMES = { "SelectedObject", "SelectedCoreObject" }

local function check(context: Rule.Context): { string }
	local findings: { string } = {}
	for _, relative in Files.walk(context.path("src")) do
		local path = "src/" .. relative
		local extension = Files.extension(path)
		if Files.vendored(path) or OWNERS[path] ~= nil or (extension ~= ".luau" and extension ~= ".lua") then
			continue
		end
		local source = Files.read(context.path(path))
		local line = 0
		for text in string.gmatch(source .. "\n", "([^\n]*)\n") do
			line += 1
			for _, name in NAMES do
				if string.find(text, "%f[%w_]" .. name .. "%f[^%w_]") ~= nil then
					table.insert(
						findings,
						("%s:%d: %s bypasses the host selection seam; use ctx.selection.get, set, changed or observe (%s)"):format(
							path,
							line,
							name,
							SEAM
						)
					)
				end
			end
		end
	end
	return findings
end

local function register(harness: Verify.Harness, prefix: string)
	harness:case(prefix .. "direct selection reads, writes and observations fail outside the seam", function(test)
		Rule.within(test, {
			["src/ui/write.luau"] = "gui.SelectedObject = node\n",
			["src/ui/read.luau"] = "local a = 1\nlocal current = gui.SelectedObject\n",
			["src/ui/observe.luau"] = "return ctx.observe.SelectedObject(gui)\n",
			["src/ui/core.luau"] = "service.SelectedCoreObject = node\n",
			["src/ui/named.luau"] = 'return observation.readProperty(gui, "SelectedObject")\n',
		}, function(context)
			local findings = check(context)
			Verify.expect(#findings):toBe(5)
			Verify.expect(Rule.contains(findings, "src/ui/write.luau:1:")):toBe(true)
			Verify.expect(Rule.contains(findings, "src/ui/read.luau:2:")):toBe(true)
			Verify.expect(Rule.contains(findings, "src/ui/observe.luau:1:")):toBe(true)
			Verify.expect(Rule.contains(findings, "src/ui/core.luau:1: SelectedCoreObject")):toBe(true)
			Verify.expect(Rule.contains(findings, "src/ui/named.luau:1:")):toBe(true)
		end)
	end)
	harness:case(prefix .. "the seam, its owners, vendor, other trees and longer names pass", function(test)
		Rule.within(test, {
			[SEAM] = "service.SelectedObject = target\n",
			["src/ui/context_observe.luau"] = 'local selection = property == "SelectedObject"\n',
			["src/ui/engine_types.luau"] = "SelectedObject: (GuiService) -> Value,\n",
			["src/vendor/compose/host.luau"] = "gui.SelectedObject = node\n",
			["src/ui/seamed.luau"] = "ctx.selection.set(node)\nlocal SelectedObjectCount = 1\n",
			["tests/probe.luau"] = "gui.SelectedObject = node\n",
			["examples/game.luau"] = "gui.SelectedObject = node\n",
		}, function(context)
			Verify.expect(check(context)):toEqual({})
		end)
	end)
end

local rule: Rule.Rule = {
	name = "selection-seam",
	summary = "Facet source reads and writes the native selection only through the host selection seam.",
	check = check,
	register = register,
}

return rule
