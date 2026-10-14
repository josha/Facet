--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local rules = require("../../tools/facet/checks")

return function(harness: Verify.Harness)
	for _, rule in rules do
		harness:suite(rule.name, function()
			local build = rule.cases
			harness:case("declares selftest cases", {
				id = ("tools/rules::%s::declares selftest cases"):format(rule.name),
				run = function()
					Verify.expect(build ~= nil):toBe(true)
					if build ~= nil then
						Verify.expect(#build() > 0):toBe(true)
					end
				end,
			})
			if build == nil then
				return
			end
			for _, case in build() do
				harness:case(case.name, {
					id = ("tools/rules::%s::%s"):format(rule.name, case.name),
					run = function()
						Verify.expect(case.run()):toBe(nil)
					end,
				})
			end
		end)
	end
end
