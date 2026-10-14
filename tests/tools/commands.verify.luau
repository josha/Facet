--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local commands = require("../../tools/facet/commands")
local Loader = require("../lib/loader")

return function(harness: Verify.Harness)
	harness:case("module loader resolves an explicit Luau file before directory candidates", {
		id = "tools/commands::loader::explicit Luau file",
		run = function()
			local loader = Loader.new()
			local explicit = loader.require("src/ui/rich_text.luau")
			Verify.expect(loader.require("src/ui/rich_text")):toBe(explicit)
			Verify.expect(type(explicit)):toBe("table")
		end,
	})
	harness:case("module loader reports a missing explicit Luau file", {
		id = "tools/commands::loader::missing Luau file",
		run = function()
			local ok, failure = pcall(Loader.new().require, "tests/lib/missing-macos-loader-fixture.luau")
			Verify.expect(ok):toBe(false)
			Verify.expect(string.find(tostring(failure), "no module at ", 1, true) ~= nil):toBe(true)
		end,
	})
	for _, command in commands do
		local build = command.cases
		if build == nil then
			continue
		end
		harness:suite(command.name, function()
			for _, case in build() do
				harness:case(case.name, {
					id = ("tools/commands::%s::%s"):format(command.name, case.name),
					tags = case.tags,
					run = function()
						Verify.expect(case.run()):toBe(nil)
					end,
				})
			end
		end)
	end
end
