--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/world")

local function buildControl(build)
	local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, ops = true })
	local core, env = w.core, w.env
	local enabled = core:signal(true)
	local value = core:signal(false)
	local control = build(core, enabled, value)
	local adapter = w.adapter
	local pres = w.pres
	local handle = pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
	pres.refresh()
	return core, enabled, value, control, adapter, pres, handle
end

t.describe("Control enabled interruption", function()
	t.it("ancestor disable ends native editing and closes popup without late mutation", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local core, env = w.core, w.env
		local enabled = core:signal(true)
		local value = core:signal("")
		local commits = 0
		local input = Facet.Controls.TextInput(core, {
			id = "T",
			value = value,
			onCommit = function()
				commits += 1
			end,
		})
		local selected = core:signal("a")
		local popup = Facet.Controls.PopupButton(core, {
			id = "P",
			value = selected,
			presentation = "menu",
			options = { { id = "a", label = "A" }, {
				id = "b",
				label = "B",
			} },
		})
		local adapter = w.adapter
		local pres = w.pres
		pres.present(Facet.UI.Screen({ id = "S", enabled = enabled, children = { input.blueprint, popup.blueprint } }))
		pres.refresh()
		adapter.tap("/S/T/Field")
		adapter.typeText("/S/T/Field", "accepted")
		popup.api.open()
		pres.refresh()
		enabled:set(false)
		pres.refresh()
		t.expect(input.dump().editing).toBe(false)
		t.expect(popup.dump().open).toBe(false)
		adapter.typeText("/S/T/Field", "late")
		adapter.blurText("/S/T/Field")
		t.expect(value:get()).toBe("accepted")
		t.expect(commits).toBe(0)
		popup.api.select("b")
		t.expect(selected:get()).toBe("a")
	end)

	t.it("Chip paints and enforces live enabled through mounted activation", function()
		local _, enabled, value, _, adapter, pres = buildControl(function(core, e, v)
			return Facet.Controls.Chip(core, { id = "C", label = "Filter", selected = v, enabled = e })
		end)
		adapter.tap("/S/C")
		t.expect(value:get()).toBe(true)
		enabled:set(false)
		pres.refresh()
		adapter.tap("/S/C")
		t.expect(value:get()).toBe(true)
		t.expect(adapter.node("/S/C").props.enabled).toBe(false)
	end)

	t.it("Popup closes when disabled and refuses unavailable choices", function()
		local _, enabled, value, control, adapter, pres = buildControl(function(core, e, v)
			v:set("a")
			return Facet.Controls.PopupButton(core, {
				id = "C",
				value = v,
				enabled = e,
				presentation = "menu",
				options = {
					{ id = "a", label = "Available" },
					{ id = "b", label = "Unavailable", enabled = false },
				},
			})
		end)
		adapter.tap("/S/C/Trigger")
		pres.refresh()
		adapter.tap("/S/C/PopupWhen/then/Popup/Opt-b")
		t.expect(value:get()).toBe("a")
		t.expect(control.dump().open).toBe(true)
		enabled:set(false)
		pres.refresh()
		t.expect(control.dump().open).toBe(false)
		control.api.open()
		control.api.select("b")
		t.expect(control.dump().open).toBe(false)
		t.expect(value:get()).toBe("a")
	end)

	t.it("TextInput disable preserves accepted text and blocks late edits and commits", function()
		local commits = 0
		local _, enabled, value, control, adapter, pres = buildControl(function(core, e, v)
			v:set("")
			return Facet.Controls.TextInput(core, {
				id = "C",
				value = v,
				enabled = e,
				onCommit = function()
					commits += 1
				end,
			})
		end)
		adapter.tap("/S/C/Field")
		adapter.typeText("/S/C/Field", "accepted")
		enabled:set(false)
		adapter.typeText("/S/C/Field", "late")
		pres.refresh()
		adapter.blurText("/S/C/Field")
		t.expect(value:get()).toBe("accepted")
		t.expect(control.dump().editing).toBe(false)
		t.expect(commits).toBe(0)
	end)

	t.it("TextInput refuses both enabled and disabled even when consistent", function()
		local core = Facet.newCore()
		Facet.newEnvironment(core)
		local ok, err = pcall(function()
			Facet.Controls.TextInput(core, { value = core:signal(""), enabled = true, disabled = false })
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "both", 1, true) ~= nil).toBe(true)
	end)
end)
