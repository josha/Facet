--!strict
local t = require("./lib/testkit")
local tree = require("../tools/lune/lib/studio_tree")
t.describe("Studio synchronization bootstrap", function()
	t.it("gallery sync uses the same single client-context bootstrap as the built place", function()
		local found = false
		for _, entry in tree.entries("gallery") do
			if entry.path == "ReplicatedStorage.Gallery" then
				found = true
				t.expect(entry.className).toBe("Script")
				t.expect(entry.runContext).toBe("Client")
			end
		end
		t.expect(found).toBe(true)
	end)
end)
