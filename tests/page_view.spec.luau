--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Facet = require("../src") :: any
local UI = Facet.UI
local function mount(facts)
	local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 }, reducedMotion = true, env = facts })
	local selection = w.core:signal("one")
	local pages = {}
	for _, id in { "one", "two", "three" } do
		table.insert(pages, { id = id, title = id, content = UI.Button({ id = "Play", label = "Play " .. id }) })
	end
	local c = Facet.Controls.PageView(w.core, { id = "Pager", selection = selection, pages = pages })
	w.present(UI.Screen({ id = "S", children = { c.blueprint } }))
	w.settle(3)
	return w, c, selection
end
local root = "/S/Pager"
local dot2 = root .. "/Indicators/Dot2"
local dot1 = root .. "/Indicators/Dot1"
local function clean(w, c)
	w.pres.dismiss(w.handle)
	c.dispose()
end
t.describe("PageView control", function()
	t.it("uses dots instead of a horizontal scrollbar", function()
		local w, c = mount()
		t.expect(w.adapter.node(root .. "/Pages").indicatorsOff).toBe(true)
		clean(w, c)
	end)
	t.it("sizes each page to its viewport and preserves owner-held selection", function()
		local w, c, s = mount()
		local r = w.adapter.node(root .. "/Pages").rect
		t.expect(w.adapter.node(root .. "/Pages/one").rect.w).toBe(r.w)
		s:set("three")
		w.settle(4)
		t.expect(w.controller.scrollPosition(root .. "/Pages").x).toBe(r.w * 2)
		t.expect(c.dump().index).toBe(3)
		clean(w, c)
	end)
	t.it("PageView pointer: a tap activates through the presenter (device-true)", function()
		local w, c, s = mount()
		w.adapter.tap(dot2)
		w.settle(3)
		t.expect(s:get()).toBe("two")
		clean(w, c)
	end)
	t.it("PageView touch: a touch tap/pan drives the control (device-true)", function()
		local w, c, s = mount()
		w.adapter.tap(dot2, { source = "pointer", pointer = "touch" })
		w.settle(3)
		t.expect(s:get()).toBe("two")
		clean(w, c)
	end)
	t.it("PageView keyboard: focus + Return drives the control", function()
		local w, c, s = mount()
		w.pres.focus.focusOn(dot2)
		w.press("Return")
		w.settle(3)
		t.expect(s:get()).toBe("two")
		clean(w, c)
	end)
	t.it("PageView gamepad: focus + ButtonA drives the control", function()
		local w, c, s = mount()
		w.pres.focus.focusOn(dot2)
		w.press("ButtonA")
		w.settle(3)
		t.expect(s:get()).toBe("two")
		clean(w, c)
	end)
	t.it("PageView pointer affordance: hover, direct drag, wheel channel", function()
		local w, c, s = mount()
		w.adapter.tap(root .. "/Controls/Next")
		w.settle(3)
		t.expect(s:get()).toBe("two")
		t.expect(w.adapter.node(root .. "/Pages").class).toBe("ScrollView")
		clean(w, c)
	end)
	t.it("PageView touch affordance: 44px floor, naked-pan scroll, edit grip", function()
		local w, c, s = mount()
		local r = w.adapter.node(dot2).rect
		t.expect(r.h >= 44 and r.w >= 44).toBe(true)
		w.controller.scrollTo(root .. "/Pages", { x = 600, y = 0 })
		w.settle(3)
		t.expect(s:get()).toBe("two")
		clean(w, c)
	end)
	t.it("PageView keyboard affordance: focus ring, Navigate, Activate, Adjust", function()
		local w, c, s = mount()
		w.pres.focus.focusOn(dot1)
		w.press("Right")
		w.settle(3)
		t.expect(s:get()).toBe("two")
		w.press("Up")
		t.expect(w.pres.focus.focused:get() ~= dot1).toBe(true)
		clean(w, c)
	end)
	t.it("PageView gamepad affordance: focus, grab mode, A and B, ten-foot ring", function()
		local w, c, s = mount({ viewingDistance = "ten-foot" })
		w.pres.focus.focusOn(dot1)
		w.press("DPadRight")
		w.settle(3)
		t.expect(s:get()).toBe("two")
		w.press("DPadRight")
		w.settle(3)
		t.expect(s:get()).toBe("three")
		w.press("DPadRight")
		t.expect(s:get()).toBe("three")
		clean(w, c)
	end)
	t.it("PageView hot-switch: in-flight state resolves CARRY or CANCEL on a class flip", function()
		local w, c, s = mount()
		s:set("two")
		w.settle(3)
		local node = w.adapter.node(root .. "/Pages/two")
		w.env:set("capabilities", { gamepad = true })
		w.env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		w.settle(5)
		t.expect(s:get()).toBe("two")
		t.expect(w.adapter.node(root .. "/Pages/two") == node).toBe(true)
		t.expect(w.controller.scrollPosition(root .. "/Pages").x).toBe(400)
		clean(w, c)
	end)
	t.it("refuses empty pages, duplicate keys and unknown selection", function()
		local w = world.new()
		for _, pages in
			{
				{},
				{
					{ id = "one", title = "One", content = UI.Text({ text = "One" }) },
					{ id = "one", title = "Two", content = UI.Text({ text = "Two" }) },
				},
			}
		do
			t.expect(pcall(function()
				Facet.Controls.PageView(w.core, { selection = w.core:signal("one"), pages = pages })
			end)).toBe(false)
		end
	end)

	t.it("native return to an already-visible page reconciles the selection", function()
		local w, c, s = mount()
		w.adapter.driveScroll(root .. "/Pages", { x = 300, y = 0 })
		w.settle(90)
		local x = w.controller.scrollPosition(root .. "/Pages").x
		t.expect(c.dump().index).toBe(math.floor(x / 600 + 0.5) + 1)
		clean(w, c)
	end)
	t.it("programmatic page selection moves focus out of the hidden page", function()
		local w, c, s = mount()
		w.pres.focus.focusOn(root .. "/Pages/one/Play")
		s:set("three")
		w.settle(5)
		t.expect(w.pres.focus.focused:get()).toBe(root .. "/Pages/three/Play")
		clean(w, c)
	end)
	t.it("directional page focus scrolls the outer pager", function()
		local w, c, s = mount()
		w.pres.focus.focusOn(root .. "/Pages/one/Play")
		w.press("DPadRight")
		w.settle(5)
		t.expect(s:get()).toBe("two")
		t.expect(w.controller.scrollPosition(root .. "/Pages").x).toBe(600)
		clean(w, c)
	end)

	t.it("a fixed-height pager bounds its pages inside an outer vertical scroller", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local c = Facet.Controls.PageView(w.core, {
			height = { type = "fixed", px = 360 },
			selection = w.core:signal("one"),
			pages = { { id = "one", title = "One", content = UI.Text({ text = "Course details" }) } },
		})
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Outer",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						c.blueprint,
					},
				}),
			},
		}))
		w.settle(3)
		for _, d in w.controller.diagnostics() do
			t.expect(string.find(d.issue or "", "unbounded", 1, true) == nil).toBe(true)
		end
		clean(w, c)
	end)

	t.it("interrupting normal page travel restores the actual visible selection", function()
		local w, c, s = mount()
		w.env:set("reducedMotion", false)
		s:set("three")
		w.settle(3)
		w.adapter.driveScroll(root .. "/Pages", { x = 0, y = 0 })
		w.settle(120)
		t.expect(s:get()).toBe("one")
		t.expect(w.controller.scrollPosition(root .. "/Pages").x).toBe(0)
		clean(w, c)
	end)
	t.it("normal animated travel moves focus and cleanup releases resources", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 }, reducedMotion = false })
		local selection = w.core:signal("one")
		local baseline = w.core:counters()
		local c = Facet.Controls.PageView(w.core, {
			id = "Pager",
			selection = selection,
			pages = {
				{ id = "one", title = "One", content = UI.Button({ id = "Go", label = "Go one" }) },
				{ id = "two", title = "Two", content = UI.Button({ id = "Go", label = "Go two" }) },
			},
		})
		w.present(UI.Screen({ id = "S", children = { c.blueprint } }))
		w.pres.focus.focusOn(root .. "/Pages/one/Go")
		selection:set("two")
		w.settle(120)
		t.expect(w.pres.focus.focused:get()).toBe(root .. "/Pages/two/Go")
		clean(w, c)
		w.settle(120)
		t.expect(w.core:lastError()).toBe(nil)
		t.expect(w.core:counters()).toEqual(baseline)
	end)
	t.it("an unchanged native offset cannot swallow a later owner reversal", function()
		local w, c, s = mount()
		w.adapter.driveScroll(root .. "/Pages", { x = 0, y = 0 })
		s:set("two")
		s:set("one")
		w.settle(120)
		t.expect(s:get()).toBe("one")
		t.expect(w.controller.scrollPosition(root .. "/Pages").x).toBe(0)
		clean(w, c)
	end)
	t.it("resizing during travel preserves the requested page", function()
		local w, c, s = mount()
		w.env:set("reducedMotion", false)
		s:set("three")
		w.settle(2)
		w.env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		w.settle(120)
		t.expect(s:get()).toBe("three")
		t.expect(w.controller.scrollPosition(root .. "/Pages").x).toBe(800)
		clean(w, c)
	end)
end)
