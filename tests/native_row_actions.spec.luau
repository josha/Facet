--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native RowActions", function()
	t.it("releases mounted-row observers on repeated branch removal without Facet scopes", function()
		local app, adapter, advance, core = world()
		local UI = app.controls
		local shown = Compose.cell(false)
		local close = app.mount(function()
			return UI.Screen("S")({
				Compose.show(shown, function()
					local before = core.owner.size()
					local node = UI.RowActions("Row")({
						width = UI.fill(),
						content = UI.Text({ text = "Message", height = { type = "fixed", px = 48 } }),
						trailing = { { id = "delete", label = "Delete", onAction = function() end } },
					})
					t.expect(core.owner.size()).toBe(before)
					return node
				end),
			})
		end)
		advance(0.1)
		local baseline = core.owner.size()
		for _ = 1, 4 do
			shown:set(true)
			advance(0.1)
			t.expect(adapter.node("/S/Row") ~= nil).toBe(true)
			shown:set(false)
			advance(0.1)
			t.expect(adapter.node("/S/Row")).toBeNil()
			local after = core.owner.size()
			t.expect(after).toBe(baseline)
		end
		close()
		advance(0.1)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
