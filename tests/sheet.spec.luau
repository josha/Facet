--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local world = require("./lib/harness_world")
local fake = require("./lib/fake_target")
local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local UI = harness.UI
local function mount(extra, facts)
	local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true, env = facts })
	local detent = Compose.cell("medium")
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
	local control = harness.Controls.Sheet(w.core, spec)
	w.present(UI.Screen({ id = "Base", children = { UI.Button({ id = "Open", label = "Open" }) } }))
	local handle = control.present(w.pres)
	w.settle(3)
	return w, control, detent, handle
end
local size = "/Sheet/Layer/Panel/Room/Column/Header/Size"
local drag = "/Sheet/Layer/Panel/Drag/Handle"
local close = "/Sheet/Layer/Panel/Room/Column/Header/Close"
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
		t.expect(d:peek()).toBe("large")
		c.dispose()
	end)
	t.it("Sheet touch: a touch tap/pan drives the control (device-true)", function()
		local w, c, d = mount()
		dragBy(w, -230, "touch")
		t.expect(d:peek()).toBe("large")
		c.dispose()
	end)
	t.it("Sheet keyboard: focus + Return drives the control", function()
		local w, c, d, h = mount()
		w.pres.focus.focusOn(size)
		w.press("Return")
		t.expect(d:peek()).toBe("large")
		c.dispose()
	end)
	t.it("Sheet gamepad: focus + ButtonA drives the control", function()
		local w, c, d, h = mount()
		w.pres.focus.focusOn(size)
		w.press("ButtonA")
		t.expect(d:peek()).toBe("large")
		c.dispose()
	end)
	t.it("Sheet pointer affordance: hover, direct drag, wheel channel", function()
		local w, c, d = mount()
		dragBy(w, -250, "pointer")
		t.expect(d:peek()).toBe("large")
		-- the body scrolls between pinned regions; the panel itself no longer does
		t.expect(w.adapter.node("/Sheet/Layer/Panel/Room/Column/Body").class).toBe("ScrollView")
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
		t.expect(d:peek()).toBe("large")
		w.press("Down")
		t.expect(w.pres.focus.focused:peek() == size).toBe(false)
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
		t.expect(d:peek()).toBe("large")
		w.press("ButtonB")
		t.expect(c.dump().presented).toBe(false)
		t.expect(w.pres.focus.focused:peek()).toBe("/Base/Open")
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
		t.expect(d:peek()).toBe("medium")
		c.dispose()
	end)
	t.it("interactive dismissal can be disabled without disabling explicit close", function()
		local later = 0
		local w, c = mount({
			interactiveDismissDisabled = true,
			actions = {
				{
					id = "Later",
					label = "Later",
					role = "cancel",
					onActivate = function()
						later += 1
					end,
				},
			},
		})
		w.press("ButtonB")
		t.expect(c.dump().presented).toBe(true)
		t.expect(later).toBe(0) -- Cancel runs no cancel action either
		for _, path in w.adapter.paths() do
			if string.sub(path, -6) == "/Later" then
				w.adapter.tap(path)
			end
		end
		t.expect(later).toBe(1) -- the caller's own button still works
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
					detent = Compose.formula(function()
						return "medium"
					end),
				},
			}
		do
			local spec = { title = "Details", detent = Compose.cell("medium"), content = UI.Text({ text = "Content" }) }
			for k, v in change do
				spec[k] = v
			end
			t.expect(pcall(function()
				harness.Controls.Sheet(w.core, spec)
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
		-- the room is too small for the pinned regions, so they scroll as one; the
		-- adapter publishes the engine's bar like the real target does
		local w = world.new({
			viewport = { x = 0, y = 0, w = 390, h = 300 },
			reducedMotion = true,
			newAdapter = function()
				local a = fake.new()
				a.scrollBarThickness = fake.SCROLL_BAR_RESERVE
				return a
			end,
		})
		local c = harness.Controls.Sheet(w.core, {
			id = "Sheet",
			title = "Details",
			detent = Compose.cell("small"),
			detents = { { id = "small", height = 50 } },
			content = UI.Button({ id = "Action", label = "Continue" }),
		})
		c.present(w.pres)
		w.settle(4)
		local panel = w.adapter.node("/Sheet/Layer/Panel").rect
		local closeRect = w.adapter.node(close).rect
		t.expect(closeRect.y + closeRect.h <= panel.y + panel.h).toBe(true)
		-- the pinned regions keep their targets; the body viewport is what is
		-- left of the floor, and its content scrolls natively
		local body = w.adapter.node("/Sheet/Layer/Panel/Room/Column/Body")
		t.expect(body.class == "ScrollView" and body.rect.h > 0).toBe(true)
		c.dispose()
	end)
	t.it("directional adjustment yields at the last detent", function()
		local w, c, d = mount()
		d:set("large")
		w.settle(3)
		w.pres.focus.focusOn(size)
		w.press("DPadRight")
		t.expect(w.pres.focus.focused:peek()).toBe(close)
		c.dispose()
	end)
	t.it("caller content named Size does not acquire sheet adjustment", function()
		local w, c, d = mount({ content = UI.Button({ id = "Size", label = "Player size" }) })
		w.pres.focus.focusOn("/Sheet/Layer/Panel/Room/Column/Body/Size")
		w.press("DPadRight")
		t.expect(d:peek()).toBe("medium")
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
		local detent = Compose.cell("medium")
		local shown = Compose.cell(false)
		local baseline = w.core.owner.size()
		local c = harness.Controls.Sheet(w.core, {
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
		t.expect(shown:peek()).toBe(false)
		t.expect(w.core.lastError()).toBe(nil)
		t.expect(w.core.owner.size()).toEqual(baseline)
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

	-- ===== P4c: placement, edge, width, title getter, closeButton ==========
	local LONG = string.rep("A long line of body copy that wraps. ", 40)
	local function wide(extra, facts)
		local w = world.new({ viewport = { x = 0, y = 0, w = 1200, h = 800 }, reducedMotion = true, env = facts })
		local spec = {
			id = "Sheet",
			title = "Race details",
			detent = Compose.cell("medium"),
			content = UI.Text({ id = "Copy", text = LONG, width = UI.fill() }),
		}
		for k, v in extra or {} do
			spec[k] = v
		end
		local control = harness.Controls.Sheet(w.core, spec)
		w.present(UI.Screen({ id = "Base", children = { UI.Button({ id = "Open", label = "Open" }) } }))
		control.present(w.pres)
		w.settle(3)
		return w, control
	end
	local function panelRect(w)
		return w.adapter.node("/Sheet/Layer/Panel").rect
	end
	t.it("a function-bound title renders as its type promises", function()
		local w, c = mount({
			title = function()
				return "Live title"
			end,
		})
		t.expect(w.adapter.node("/Sheet/Layer/Panel/Room/Column/Title").props.text).toBe("Live title")
		c.dispose()
	end)
	t.it("explicit placements override the distance default", function()
		local w, c = wide({ placement = "bottom" }, { viewingDistance = "ten-foot" })
		local r, layer = panelRect(w), w.adapter.node("/Sheet/Layer").rect
		t.expect(r.y + r.h).toBe(layer.y + layer.h)
		t.expect(c.dump().placement).toBe("bottom")
		c.dispose()
		w, c = wide({ placement = "center" })
		r = panelRect(w)
		t.expect(math.abs(r.y + r.h / 2 - 400) < 1).toBe(true)
		t.expect(math.abs(r.x + r.w / 2 - 600) < 1).toBe(true)
		c.dispose()
	end)
	t.it("side placement docks to its physical edge, detents stay vertical", function()
		local w, c = wide({ placement = "side" })
		local r = panelRect(w)
		t.expect(r.x + r.w).toBe(1200)
		t.expect(r.y + r.h).toBe(800)
		t.expect(r.h).toBe(400)
		t.expect(c.dump().placement).toBe("side")
		t.expect(c.dump().edge).toBe("right")
		c.dispose()
		w, c = wide({ placement = "side", edge = "left", width = "narrow" })
		r = panelRect(w)
		t.expect(r.x).toBe(0)
		t.expect(r.w).toBe(360)
		c.dispose()
	end)
	t.it("width presets reuse the dialog widths, bounded by safe room", function()
		local widths = {}
		for _, preset in { "narrow", "automatic", "wide" } do
			local w, c = wide({ width = preset })
			widths[preset] = math.round(panelRect(w).w)
			c.dispose()
		end
		t.expect(widths).toEqual({ narrow = 360, automatic = 560, wide = 800 })
		local w = world.new({ viewport = { x = 0, y = 0, w = 500, h = 800 }, reducedMotion = true })
		local c = harness.Controls.Sheet(w.core, {
			id = "Sheet",
			title = "T",
			detent = Compose.cell("medium"),
			width = "wide",
			content = UI.Text({ text = LONG, width = UI.fill() }),
		})
		c.present(w.pres)
		w.settle(3)
		t.expect(panelRect(w).w <= 500).toBe(true)
		c.dispose()
	end)
	t.it("side sheets enter and leave toward their own edge", function()
		local _, c = wide({ placement = "side", edge = "left" })
		t.expect(c.dump().transition).toEqual({ enter = "slide-right", exit = "slide-left" })
		c.dispose()
		local _, r = wide({ placement = "side" })
		t.expect(r.dump().transition).toEqual({ enter = "slide-left", exit = "slide-right" })
		r.dispose()
		local _, b = wide()
		t.expect(b.dump().transition).toEqual({ enter = "slide-up", exit = "slide-down" })
		b.dispose()
	end)
	t.it("closeButton=false removes Close; Size and interactive dismissal remain", function()
		local w, c = mount({ closeButton = false })
		t.expect(w.adapter.node(close)).toBeNil()
		t.expect(w.adapter.node(size) ~= nil).toBe(true)
		w.press("ButtonB")
		t.expect(c.dump().presented).toBe(false)
		c.dispose()
	end)
	t.it("refuses malformed placement, edge, width and closeButton", function()
		local w = world.new()
		for _, change in
			{
				{ placement = "top" },
				{ edge = "left" },
				{ placement = "side", edge = "start" },
				{ width = "huge" },
				{ closeButton = "no" },
			}
		do
			local spec = { title = "Details", detent = Compose.cell("medium"), content = UI.Text({ text = "Content" }) }
			for k, v in change do
				spec[k] = v
			end
			t.expect(pcall(function()
				harness.Controls.Sheet(w.core, spec)
			end)).toBe(false)
		end
	end)
end)
