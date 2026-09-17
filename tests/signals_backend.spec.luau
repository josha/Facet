--!strict
local t = require("./lib/testkit")
local factory = require("../src/core/signals")
local suite = require("./conformance/suite")

t.describe("Roblox Signals backend preserves the Facet contract", function()
	for _, check in suite do
		t.it(check.name, function()
			local ok, note = check.run(factory.new({ warn = function() end }))
			if not ok then
				print(note)
			end
			t.expect(ok).toBe(true)
		end)
	end
end)
