--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Facet = require("../src") :: any
local UI = Facet.UI
local function mount(extra, facts)
	local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true, env = facts })
	local detent = w.core:signal("medium")
	local spec = {
		id = "Sheet",
		title = "Race details",
		detent = detent,
		content = UI.Button({
			id = "BodyAction",
			label = "Join race",
		}),
	}
	for k, v in extra or {} do
		spec[k] = v
	end
	local control = Facet.Controls.Sheet(w.core, spec)
	w.present(UI.Screen({ id = "Base", children = { UI.Button({ id = "Open", label = "Open" }) } }))
	local handle = control.present(w.pres)
	w.settle(3)
	return w, control, detent, handle
end
local size = "/Sheet/Layer/Panel/Header/Size"
local drag = "/Sheet/Layer/Panel/Drag/Handle"
local close = "/Sheet/Layer/Panel/Header/Close"
local function dragBy(w, dy, kind)
	local r = w.adapter.node(drag).rect
	w.adapter.pointerDown(drag, r.x + r.w / 2, r.y + r.h / 2, kind)
	w.adapter.pointerMove(r.x + r.w / 2, r.y + r.h / 2 + dy)
	w.adapter.pointerUp(r.x + r.w / 2, r.y + r.h / 2 + dy)
	w.settle(4)
end
t.describe("Sheet control", function()
	t.it("resolves detents inside the available safe height", function()
		local w, c, d = mount()
		t.expect(c.dump().height).toBe(300)
		d:set("large")
		w.settle(3)
		t.expect(c.dump().height).toBe(600)
		c.dispose()
	end)
	t.it("Sheet pointer: a tap activates through the presenter (device-true)", function()
		local w, c, d = mount()
		w.adapter.tap(size)
		w.settle(3)
		t.expect(d:get()).toBe("large")
		c.dispose()
	end)
	t.it("Sheet touch: a touch tap/pan drives the control (device-true)", function()
		local w, c, d = mount()
		dragBy(w, -230, "touch")
		t.expect(d:get()).toBe("large")
		c.dispose()
	end)
	t.it("Sheet keyboard: focus + Return drives the control", function()
		local w, c, d, h = mount()
		w.pres.focus.focusOn(size)
		w.press("Return")
		t.expect(d:get()).toBe("large")
		c.dispose()
	end)
	t.it("Sheet gamepad: focus + ButtonA drives the control", function()
		local w, c, d, h = mount()
		w.pres.focus.focusOn(size)
		w.press("ButtonA")
		t.expect(d:get()).toBe("large")
		c.dispose()
	end)
	t.it("Sheet pointer affordance: hover, direct drag, wheel channel", function()
		local w, c, d = mount()
		dragBy(w, -250, "pointer")
		t.expect(d:get()).toBe("large")
		t.expect(w.adapter.node("/Sheet/Layer/Panel").class).toBe("ScrollView")
		c.dispose()
	end)
	t.it("Sheet touch affordance: 44px floor, naked-pan scroll, edit grip", function()
		local w, c = mount()
		t.expect(w.adapter.node(drag).rect.h >= 44).toBe(true)
		t.expect(w.adapter.node(close).rect.h >= 44).toBe(true)
		dragBy(w, 180, "touch")
		t.expect(c.dump().presented).toBe(false)
		c.dispose()
	end)
	t.it("Sheet keyboard affordance: focus ring, Navigate, Activate, Adjust", function()
		local w, c, d, h = mount()
		w.pres.focus.focusOn(size)
		w.press("Right")
		t.expect(d:get()).toBe("large")
		w.press("Down")
		t.expect(w.pres.focus.focused:get() == size).toBe(false)
		w.pres.focus.focusOn(close)
		w.press("Return")
		t.expect(c.dump().presented).toBe(false)
		c.dispose()
	end)
	t.it("Sheet gamepad affordance: focus, grab mode, A and B, ten-foot ring", function()
		local w, c, d, h = mount(nil, { viewingDistance = "ten-foot" })
		t.expect(c.dump().placement).toBe("center")
		w.pres.focus.focusOn(size)
		w.press("DPadRight")
		t.expect(d:get()).toBe("large")
		w.press("ButtonB")
		t.expect(c.dump().presented).toBe(false)
		t.expect(w.pres.focus.focused:get()).toBe("/Base/Open")
		c.dispose()
	end)
	t.it("Sheet hot-switch: in-flight state resolves CARRY or CANCEL on a class flip", function()
		local w, c, d = mount()
		local r = w.adapter.node(drag).rect
		w.adapter.pointerDown(drag, r.x + 10, r.y + 10, "touch")
		w.adapter.pointerMove(r.x + 10, r.y - 100)
		w.env:set("capabilities", { gamepad = true })
		w.settle(3)
		t.expect(c.dump().dragging).toBe(false)
		t.expect(d:get()).toBe("medium")
		c.dispose()
	end)
	t.it("interactive dismissal can be disabled without disabling explicit close", function()
		local w, c = mount({ interactiveDismissDisabled = true })
		w.press("ButtonB")
		t.expect(c.dump().presented).toBe(true)
		w.adapter.tap(close)
		w.settle(3)
		t.expect(c.dump().presented).toBe(false)
		c.dispose()
	end)
	t.it("rejects unknown detents, duplicate IDs and a read-only selection", function()
		local w = world.new()
		for _, change in
			{
				{ detents = { "tiny" } },
				{ detents = { "medium", "medium" } },
				{
					detent = w.core:memo(function()
						return "medium"
					end),
				},
			}
		do
			local spec =
				{ title = "Details", detent = w.core:signal("medium"), content = UI.Text({ text = "Content" }) }
			for k, v in change do
				spec[k] = v
			end
			t.expect(pcall(function()
				Facet.Controls.Sheet(w.core, spec)
			end)).toBe(false)
		end
	end)

	t.it("places the real panel at the bottom nearby and centered at a distance", function()
		local w, c = mount()
		local r = w.adapter.node("/Sheet/Layer/Panel").rect
		t.expect(r.y + r.h).toBe(600)
		t.expect(r.x > 0).toBe(true)
		c.dispose()
		local tv, ctl = mount(nil, { viewingDistance = "ten-foot" })
		local p = tv.adapter.node("/Sheet/Layer/Panel").rect
		t.expect(math.abs(p.y + p.h / 2 - 300) < 1).toBe(true)
		ctl.dispose()
	end)
	t.it("small detents retain usable content and reachable dismissal", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 390, h = 300 }, reducedMotion = true })
		local c = Facet.Controls.Sheet(w.core, {
			title = "Details",
			detent = w.core:signal("small"),
			detents = { { id = "small", height = 50 } },
			content = UI.Button({ id = "Action", label = "Continue" }),
		})
		c.present(w.pres)
		w.settle(4)
		local panel = w.adapter.node("/Sheet/Layer/Panel").rect
		local closeRect = w.adapter.node(close).rect
		t.expect(closeRect.y + closeRect.h <= panel.y + panel.h).toBe(true)
		t.expect(w.adapter.node("/Sheet/Layer/Panel/Body").rect.h >= 44).toBe(true)
		c.dispose()
	end)
	t.it("directional adjustment yields at the last detent", function()
		local w, c, d = mount()
		d:set("large")
		w.settle(3)
		w.pres.focus.focusOn(size)
		w.press("DPadRight")
		t.expect(w.pres.focus.focused:get()).toBe(close)
		c.dispose()
	end)
	t.it("caller content named Size does not acquire sheet adjustment", function()
		local w, c, d = mount({ content = UI.Button({ id = "Size", label = "Player size" }) })
		w.pres.focus.focusOn("/Sheet/Layer/Panel/Body/Size")
		w.press("DPadRight")
		t.expect(d:get()).toBe("medium")
		c.dispose()
	end)

	t.it("grabbing during resize continues from the painted height", function()
		local w, c, d = mount()
		w.env:set("reducedMotion", false)
		d:set("large")
		w.tick()
		w.pres.refresh()
		local before = w.adapter.node("/Sheet/Layer/Panel").rect.h
		local r = w.adapter.node(drag).rect
		w.adapter.pointerDown(drag, r.x + 10, r.y + 10, "touch")
		w.adapter.pointerMove(r.x + 10, r.y + 11)
		w.pres.refresh()
		t.expect(math.abs(w.adapter.node("/Sheet/Layer/Panel").rect.h - (before - 1)) < 1).toBe(true)
		w.adapter.pointerUp(r.x + 10, r.y + 11)
		c.dispose()
	end)
	t.it("bound presentation reopens and cleanup returns to its baseline", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 600 }, reducedMotion = false })
		local detent = w.core:signal("medium")
		local shown = w.core:signal(false)
		local baseline = w.core:counters()
		local c = Facet.Controls.Sheet(w.core, {
			title = "Details",
			detent = detent,
			isPresented = shown,
			presenter = w.pres,
			content = UI.Text({
				text = "Briefing",
			}),
		})
		shown:set(true)
		w.settle(90)
		t.expect(c.dump().presented).toBe(true)
		c.dismiss()
		w.settle(90)
		shown:set(true)
		w.settle(90)
		t.expect(c.dump().presented).toBe(true)
		c.dispose()
		w.settle(90)
		t.expect(shown:get()).toBe(false)
		t.expect(w.core:lastError()).toBe(nil)
		t.expect(w.core:counters()).toEqual(baseline)
	end)
	t.it("canceling a stationary grab resumes the interrupted detent motion", function()
		local w, c, d = mount()
		w.env:set("reducedMotion", false)
		d:set("large")
		w.settle(1)
		local r = w.adapter.node(drag).rect
		w.adapter.pointerDown(drag, r.x + 10, r.y + 10, "touch")
		w.env:set("capabilities", { gamepad = true })
		w.settle(120)
		t.expect(w.adapter.node("/Sheet/Layer/Panel").rect.h).toBe(600)
		c.dispose()
	end)
end)
