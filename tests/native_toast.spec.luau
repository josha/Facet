--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native toast", function()
	t.it("a toast owns its body: the component runs in the toast and is released with it", function()
		local app, adapter, advance = world()
		local UI = app.controls
		local live = 0
		local copy = Compose.cell("Saved")
		local toast = app.presentToast(function()
			live += 1
			Compose.cleanup(function()
				live -= 1
			end)
			return UI.Text("Line")({ text = copy })
		end, { key = "save", duration = 20, readFloor = 0 })
		advance(0.5)
		t.expect(live).toBe(1)
		local path = `/__toast__/Items/[{toast.id}]/Toast/Line`
		t.expect(adapter.node(path)).never().toBeNil()
		-- the body's bindings stay live inside the toast
		copy:set("Saved twice")
		advance(0.1)
		t.expect(adapter.node(path).props.text).toBe("Saved twice")
		t.expect(toast.dismiss()).toBe(true)
		advance(2)
		t.expect(live).toBe(0)
		t.expect(adapter.node(path)).toBeNil()
		app.dispose()
	end)

	t.it("refuses a node: the body is a component", function()
		local app = world()
		local UI = app.controls
		local ok = pcall(function()
			app.mount(function()
				app.presentToast(UI.Text("Line")({ text = "no" }) :: any)
				return UI.Screen("S")({})
			end)
		end)
		t.expect(ok).toBe(false)
		app.dispose()
	end)
end)
