--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native PageView", function()
	t.it("shares selection with page buttons and native scroll without a Facet scope", function()
		local app, adapter, advance, core = world()
		local UI, selected = app.controls, Compose.cell("one")
		local before = core.owner.size()
		local close = app.mount(function()
			local pages = {}
			for _, key in { "one", "two", "three" } do
				table.insert(pages, {
					id = key,
					title = key,
					content = UI.Button("Play")({ label = "Play " .. key, onActivate = function() end }),
				})
			end
			local count = core.owner.size()
			local pager = UI.PageView("Pager")({ pages = pages, selection = selected })
			t.expect(core.owner.size()).toBe(count)
			return UI.Screen("S")({ pager })
		end)
		advance(0.1)
		local path = "/S/Pager/Pages"
		local width = adapter.node(path).rect.w
		t.expect(adapter.node(path .. "/one").rect.w).toBe(width)
		adapter.driveActivate("/S/Pager/Indicators/Dot2")
		advance(1)
		t.expect(selected:peek()).toBe("two")
		t.expect(adapter.node("/S/Pager/Summary").props.text).toBe("Page 2 of 3: two")
		selected:set("three")
		advance(1)
		t.expect(adapter.node("/S/Pager/Summary").props.text).toBe("Page 3 of 3: three")
		adapter.driveScroll(path, { x = 0, y = 0, dragging = true })
		advance(0.1)
		adapter.driveScroll(path, { x = 0, y = 0, dragging = false })
		advance(1)
		t.expect(selected:peek()).toBe("one")
		close()
		advance(0.1)
		t.expect(core.owner.size()).toBe(before)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
