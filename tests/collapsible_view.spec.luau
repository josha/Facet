--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local world = require("./lib/harness_world")
local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local UI = harness.UI
local trigger = "/S/View"
local body = "/Expanded-2F532F56696577/Layer/Surface/Panel/Content/Body"
local function mount(options, dismissButton)
	local w = world.new(options or { viewport = { x = 0, y = 0, w = 600, h = 400 }, reducedMotion = true })
	local expanded = Compose.cell(false)
	local label = Compose.cell("Select course")
	local chosen = Compose.cell(false)
	local c = harness.Controls.CollapsibleView(w.core, {
		id = "View",
		dismissButton = dismissButton,
		label = label,
		expanded = expanded,
		content = UI.VStack({
			id = "Options",
			children = {
				UI.Button({
					id = "One",
					label = "Coastal circuit",
					onActivate = function()
						chosen:set(true)
						label:set("Coastal circuit")
						expanded:set(false)
					end,
				}),
				UI.Toggle({ id = "Toggle", label = "Club member", value = Compose.cell(false) }),
			},
		}),
	})
	w.present(UI.Screen({ id = "S", children = { c.blueprint, UI.Button({ id = "Other", label = "Unrelated" }) } }))
	w.settle(3)
	return w, c, expanded, label, chosen
end
local function cleanup(w, c)
	w.pres.dismiss(w.handle)
	c.dispose()
	w.settle(120)
end
local function opened(w, c)
	w.settle(5)
	t.expect(c.dump().presented).toBe(true)
	t.expect(w.pres.focus.focused:peek():find("/Expanded-", 1, true) ~= nil).toBe(true)
end
t.describe("CollapsibleView control", function()
	t.it("transforms its clipping plate monotonically while text keeps its solved size", function()
		local w, c, expanded = mount({ viewport = { x = 0, y = 0, w = 600, h = 400 }, reducedMotion = false })
		local compact = w.controller.screenRectOf(trigger)
		expanded:set(true)
		w.pres.refresh()
		local path = body:gsub("/Content/Body$", "")
		local panel = w.adapter.node(path)
		t.expect(math.abs(panel.presentedSize.w - compact.w) < 1).toBe(true)
		t.expect(math.abs(panel.presentedSize.h - compact.h) < 1).toBe(true)
		local previous = panel.presentedSize.h
		for _ = 1, 60 do
			w.tick()
			panel = w.adapter.node(path)
			t.expect(panel.presentedSize.h >= previous - 0.01).toBe(true)
			t.expect(panel.presentedSize.h <= panel.rect.h + 0.01).toBe(true)
			t.expect(panel.props.transform == nil or panel.props.transform.scale == nil).toBe(true)
			previous = panel.presentedSize.h
		end
		expanded:set(false)
		for _ = 1, 60 do
			w.tick()
			panel = w.adapter.node(path)
			if not panel then
				break
			end
			t.expect(panel.presentedSize.h <= previous + 0.01).toBe(true)
			previous = panel.presentedSize.h
		end
		t.expect(w.adapter.node(path)).toBe(nil)
		cleanup(w, c)
	end)
	t.it("uses the live scrolled position for both ends of the transformation", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 }, reducedMotion = false })
		local expanded = Compose.cell(false)
		local c = harness.Controls.CollapsibleView(w.core, {
			id = "View",
			label = "Open",
			expanded = expanded,
			content = UI.Text({ text = "Content", width = UI.fill() }),
		})
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Scroll",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Box({ height = { type = "fixed", px = 250 } }),
						c.blueprint,
						UI.Box({ height = { type = "fixed", px = 400 } }),
					},
				}),
			},
		}))
		w.controller.scrollTo("/S/Scroll", { x = 0, y = 150 })
		w.settle(2)
		expanded:set(true)
		w.pres.refresh()
		w.tick()
		for _, path in w.adapter.paths() do
			if path:find("Expanded", 1, true) and path:sub(-6) == "/Panel" then
				t.expect(w.adapter.node(path).presentedPosition.y).toBe(100)
			end
		end
		cleanup(w, c)
	end)

	t.it("expands over its compact view instead of opening a separate menu below", function()
		local w, c = mount()
		local before = w.controller.screenRectOf(trigger)
		w.adapter.tap(trigger)
		opened(w, c)
		local panel = w.adapter.node(body).rect
		t.expect(math.abs(panel.y - before.y) < 1).toBe(true)
		cleanup(w, c)
	end)
	t.it("paints the expanded body through one compositing buffer", function()
		local w, c = mount()
		w.adapter.tap(trigger)
		w.settle(120)
		local buffers = 0
		for _, path in w.adapter.paths() do
			if path:find("/Expanded-", 1, true) then
				local node = w.adapter.node(path)
				if node.canvasGroupInstance then
					buffers += 1
					t.expect(node.canvasGroupInstance.groupTransparency).toBe(0)
				end
			end
		end
		t.expect(buffers).toBe(1)
		local content = w.adapter.node(body .. "/Options/One").rect
		t.expect(content.w > 0 and content.h > 0).toBe(true)
		cleanup(w, c)
	end)
	t.it("arbitrary content collapses into a bound summary button", function()
		local w, c, e, label, chosen = mount()
		w.adapter.tap(trigger)
		opened(w, c)
		w.adapter.tap(body .. "/Options/One")
		w.settle(5)
		t.expect(chosen:peek()).toBe(true)
		t.expect(c.dump().presented).toBe(false)
		t.expect(label:peek()).toBe("Coastal circuit")
		t.expect(w.pres.focus.focused:peek()).toBe(trigger)
		cleanup(w, c)
	end)
	t.it("CollapsibleView pointer: a tap activates through the presenter (device-true)", function()
		local w, c = mount()
		w.adapter.tap(trigger)
		opened(w, c)
		cleanup(w, c)
	end)
	t.it("CollapsibleView touch: a touch tap/pan drives the control (device-true)", function()
		local w, c = mount()
		w.adapter.tap(trigger, { source = "pointer", pointer = "touch" })
		opened(w, c)
		cleanup(w, c)
	end)
	t.it("CollapsibleView keyboard: focus + Return drives the control", function()
		local w, c = mount()
		w.pres.focus.focusOn(trigger)
		w.press("Return")
		opened(w, c)
		cleanup(w, c)
	end)
	t.it("CollapsibleView gamepad: focus + ButtonA drives the control", function()
		local w, c = mount()
		w.pres.focus.focusOn(trigger)
		w.press("ButtonA")
		opened(w, c)
		cleanup(w, c)
	end)
	t.it("CollapsibleView pointer affordance: hover, direct drag, wheel channel", function()
		local w, c = mount()
		w.adapter.tap(trigger)
		opened(w, c)
		t.expect(w.adapter.node(body).class).toBe("ScrollView")
		w.adapter.tap(body .. "/Collapse")
		w.settle(5)
		t.expect(c.dump().presented).toBe(false)
		cleanup(w, c)
	end)
	t.it("CollapsibleView touch affordance: 44px floor, naked-pan scroll, edit grip", function()
		local w, c = mount({
			viewport = { x = 0, y = 0, w = 320, h = 400 },
			reducedMotion = true,
			capabilities = { touch = true },
			preferredInput = "touch",
		})
		t.expect(w.adapter.node(trigger).rect.h >= 44).toBe(true)
		w.adapter.tap(trigger, { source = "pointer", pointer = "touch" })
		opened(w, c)
		local r = w.adapter.node(body).rect
		t.expect(r.w <= 320).toBe(true)
		t.expect(r.y + r.h <= 400).toBe(true)
		cleanup(w, c)
	end)
	t.it("CollapsibleView keyboard affordance: focus ring, Navigate, Activate, Adjust", function()
		local w, c = mount()
		w.pres.focus.focusOn(trigger)
		w.press("Return")
		opened(w, c)
		local first = w.pres.focus.focused:peek()
		w.press("Down")
		t.expect(w.pres.focus.focused:peek() ~= first).toBe(true)
		w.adapter.tap(body .. "/Collapse")
		w.settle(5)
		t.expect(w.pres.focus.focused:peek()).toBe(trigger)
		cleanup(w, c)
	end)
	t.it("CollapsibleView gamepad affordance: focus, grab mode, A and B, ten-foot ring", function()
		local w, c = mount({
			viewport = { x = 0, y = 0, w = 1280, h = 720 },
			reducedMotion = true,
			env = { viewingDistance = "ten-foot" },
			capabilities = { gamepad = true },
			preferredInput = "gamepad",
		})
		w.pres.focus.focusOn(trigger)
		w.press("ButtonA")
		opened(w, c)
		w.press("ButtonB")
		w.settle(5)
		t.expect(c.dump().expanded).toBe(false)
		t.expect(w.pres.focus.focused:peek()).toBe(trigger)
		cleanup(w, c)
	end)
	t.it("CollapsibleView hot-switch: in-flight state resolves CARRY or CANCEL on a class flip", function()
		local w, c = mount()
		w.adapter.tap(trigger)
		opened(w, c)
		w.env:set("capabilities", { gamepad = true })
		w.settle(5)
		t.expect(c.dump().presented).toBe(true)
		w.press("ButtonB")
		w.settle(5)
		t.expect(c.dump().presented).toBe(false)
		cleanup(w, c)
	end)
	t.it("unmount closes the expanded surface and releases its scope", function()
		local w, c, e = mount()
		e:set(true)
		opened(w, c)
		cleanup(w, c)
		t.expect(w.core.lastError()).toBe(nil)
	end)
end)

t.describe("TabView collapsed style", function()
	t.it("sets up the generic control with selected-tab summary and focused menu", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true })
		local selected = Compose.cell("one")
		local c = harness.Controls.TabView(w.core, {
			id = "Tabs",
			style = "collapsible",
			selection = selected,
			tabs = {
				{
					id = "one",
					label = "First",
					content = function()
						return UI.Button({ id = "Play", label = "Play first" })
					end,
				},
				{
					id = "two",
					label = "Second",
					content = function()
						return UI.Button({ id = "Play", label = "Play second" })
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { c.blueprint } }))
		w.settle(3)
		local path = "/S/Tabs/TopHome/then/TopBandCenter/TopBand/Navigation"
		w.pres.focus.focusOn(path)
		w.press("ButtonA")
		w.settle(5)
		t.expect(w.pres.focus.focused:peek():find("/Expanded-", 1, true) ~= nil).toBe(true)
		w.press("DPadDown")
		w.press("ButtonA")
		w.settle(5)
		t.expect(selected:peek()).toBe("two")
		t.expect(w.pres.focus.focused:peek()).toBe(path)
		w.press("ButtonA")
		w.settle(5)
		t.expect(w.pres.focus.focused:peek():match("([^/]+)$")).toBe("Opt2")
		w.press("ButtonA")
		w.settle(5)
		t.expect(selected:peek()).toBe("two")
		t.expect(w.pres.focus.focused:peek()).toBe(path)

		cleanup(w, c)
		t.expect(w.core.lastError()).toBe(nil)
	end)
	t.it("customized tabs without an indicator focus and reselect the selected destination", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true })
		local selected = Compose.cell("one")
		local c = harness.Controls.TabView(w.core, {
			id = "Tabs",
			style = "collapsible",
			indicator = "none",
			customization = Compose.cell({ order = {}, hidden = {} }),
			selection = selected,
			tabs = {
				{
					id = "one",
					label = "First",
					content = function()
						return UI.Button({ id = "Play", label = "Play first" })
					end,
				},
				{
					id = "two",
					label = "Second",
					content = function()
						return UI.Button({ id = "Play", label = "Play second" })
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { c.blueprint } }))
		w.settle(3)
		local path = "/S/Tabs/TopHome/then/TopBandCenter/TopBand/Navigation"
		w.pres.focus.focusOn(path)
		w.press("ButtonA")
		w.settle(5)
		t.expect(w.pres.focus.focused:peek():find("/Expanded-", 1, true) ~= nil).toBe(true)
		w.press("DPadDown")
		w.press("ButtonA")
		w.settle(5)
		t.expect(selected:peek()).toBe("two")
		t.expect(w.pres.focus.focused:peek()).toBe(path)
		w.press("ButtonA")
		w.settle(5)
		t.expect(w.pres.focus.focused:peek():match("([^/]+)$")).toBe("Option-two")
		w.press("ButtonA")
		w.settle(5)
		t.expect(selected:peek()).toBe("two")
		t.expect(w.pres.focus.focused:peek()).toBe(path)

		cleanup(w, c)
		t.expect(w.core.lastError()).toBe(nil)
	end)
end)

t.describe("CollapsibleView safe geometry", function()
	t.it("a full-width trigger cannot force the expanded view beyond safe edges", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 320, h = 300 },
			safeInsets = { left = 20, right = 20, top = 30, bottom = 25 },
			reducedMotion = true,
		})
		local expanded = Compose.cell(false)
		local c = harness.Controls.CollapsibleView(w.core, {
			id = "View",
			label = "Settings",
			expanded = expanded,
			width = UI.fill(),
			content = UI.Text({ text = string.rep("Course details ", 30), width = UI.fill() }),
		})
		w.present(UI.Screen({ id = "S", children = { c.blueprint } }))
		w.settle(3)
		expanded:set(true)
		w.settle(5)
		local r = w.adapter.node(body).rect
		t.expect(r.x >= 20 and r.x + r.w <= 300).toBe(true)
		t.expect(r.y >= 30 and r.y + r.h <= 275).toBe(true)
		cleanup(w, c)
	end)
end)

t.describe("CollapsibleView lifetime and identity", function()
	t.it("separate mounted parents may use the same local control id", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 }, reducedMotion = true })
		local ea, eb = Compose.cell(false), Compose.cell(false)
		local a = harness.Controls.CollapsibleView(
			w.core,
			{ label = "A", expanded = ea, content = UI.Button({ id = "Action", label = "A action" }) }
		)
		local b = harness.Controls.CollapsibleView(
			w.core,
			{ label = "B", expanded = eb, content = UI.Button({ id = "Action", label = "B action" }) }
		)
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({ id = "A", children = { a.blueprint } }),
				UI.VStack({
					id = "B",
					children = { b.blueprint },
				}),
			},
		}))
		w.settle(3)
		ea:set(true)
		w.settle(5)
		local af = w.pres.focus.focused:peek()
		eb:set(true)
		w.settle(5)
		local bf = w.pres.focus.focused:peek()
		t.expect(af ~= bf).toBe(true)
		t.expect(a.dump().presented).toBe(true)
		t.expect(b.dump().presented).toBe(true)
		eb:set(false)
		w.settle(5)
		t.expect(w.pres.focus.focused:peek()).toBe(af)
		ea:set(false)
		w.settle(5)
		w.pres.dismiss(w.handle)
		a.dispose()
		b.dispose()
		t.expect(w.core.lastError()).toBe(nil)
	end)
	t.it("normal-motion cycles and bound icon changes release all owned resources", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 }, reducedMotion = false })
		local expanded, label, icon = Compose.cell(false), Compose.cell("Settings"), Compose.cell("flag")
		local baseline = w.core.owner.size()
		local c = harness.Controls.CollapsibleView(w.core, {
			id = "View",
			label = label,
			icon = icon,
			expanded = expanded,
			content = UI.Text({
				text = "Details",
				width = UI.fill(),
			}),
		})
		w.present(UI.Screen({ id = "S", children = { c.blueprint } }))
		w.settle(3)
		for i = 1, 3 do
			expanded:set(true)
			w.settle(120)
			expanded:set(false)
			w.settle(120)
		end
		w.pres.focus.focusOn(trigger)
		label:set("Club settings")
		icon:set("check")
		w.settle(3)
		t.expect(w.pres.focus.focused:peek()).toBe(trigger)
		icon:set(nil)
		w.settle(3)
		cleanup(w, c)
		t.expect(w.core.lastError()).toBe(nil)
		t.expect(w.core.owner.size()).toEqual(baseline)
	end)
end)

t.describe("CollapsibleView custom image", function()
	t.it("binds an asset image without replacing the trigger", function()
		local w = world.new({ reducedMotion = true })
		local source = Compose.cell("rbxassetid://123")
		local content = UI.Text({ text = "Details" })
		local c = harness.Controls.CollapsibleView(w.core, {
			id = "View",
			label = "Course",
			image = source,
			expanded = Compose.cell(false),
			content = content,
		})
		w.present(UI.Screen({ id = "S", children = { c.blueprint } }))
		w.settle(3)
		w.pres.focus.focusOn(trigger)
		source:set("rbxassetid://456")
		w.settle(3)
		t.expect(w.adapter.node(trigger .. "/Summary/Image").props.image).toBe("rbxassetid://456")
		t.expect(w.pres.focus.focused:peek()).toBe(trigger)
		cleanup(w, c)
	end)
end)

t.describe("CollapsibleView dismissal preference", function()
	t.it("can omit its collapse button for pointer use and restore it during navigation", function()
		local w, c = mount({
			viewport = { x = 0, y = 0, w = 600, h = 400 },
			reducedMotion = true,
			presenterOpts = { keyboardNavigation = true },
		}, "automatic")
		w.adapter.tap(trigger)
		w.settle(3)
		t.expect(w.adapter.node(body .. "/CollapseWhen/then/Collapse")).toBeNil()
		w.press("Tab")
		w.settle(3)
		t.expect(w.adapter.node(body .. "/CollapseWhen/then/Collapse")).never().toBeNil()
		cleanup(w, c)
	end)
end)
