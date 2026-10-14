--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local commands = require("../../tools/facet/commands")

return function(harness: Verify.Harness)
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
