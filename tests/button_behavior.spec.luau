--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/world")
t.describe("Button behavior", function()
	t.it("ordinary buttons allocate no inactive progress region", function()
		local w = world.new()
		local button = Facet.Controls.Button(w.core, { id = "B", label = "Race", onActivate = function() end })
		w.present(Facet.UI.Screen({ id = "S", children = { button.blueprint } }))
		t.expect(w.adapter.node("/S/B/Busy")).toBeNil()
		t.expect(button.dump().busy).toBe(false)
		w.pres.dismiss(w.handle)
		button.dispose()
	end)
	for _, theme in { "neutral", "glossy_touch", "pixel_quest", "fantasy_ornate" } do
		t.it(`busy label and all spinner dots stay inside the {theme} button plate`, function()
			local metrics = if theme == "neutral"
				then nil
				else Facet.themes.resolve((require)(`../examples/themes/{theme}`).build(Facet.themes), nil, {})
			local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 }, themeMetrics = metrics })
			local busy = w.core:signal(false)
			local button = Facet.Controls.Button(w.core, {
				id = "B",
				label = "Prepare race",
				busy = busy,
				onActivate = function() end,
			})
			w.present(Facet.UI.Screen({ id = "S", children = { button.blueprint } }))
			w.tick(0)
			local label
			for _, path in w.adapter.paths() do
				if string.sub(path, -6) == "/Label" then
					label = w.adapter.node(path)
				end
			end
			assert(label, "button label must be mounted")
			busy:set(true)
			w.pres.refresh()
			local plate = w.adapter.node("/S/B").rect
			local insets = if metrics
				then metrics.chromeInsets.control
				else { left = 0, right = 0, top = 0, bottom = 0 }
			assert(
				label.rect.x >= plate.x + insets.left
					and label.rect.x + label.rect.w <= plate.x + plate.w - insets.right,
				"label escapes the button's horizontal content box"
			)
			local dots = 0
			for _, path in w.adapter.paths() do
				if string.match(path, "/Dot%d$") then
					dots += 1
					local r = w.adapter.node(path).rect
					assert(
						r.x >= plate.x + insets.left and r.x + r.w <= plate.x + plate.w - insets.right,
						"busy dot escapes the button's horizontal content box"
					)
					assert(
						r.y >= plate.y + insets.top and r.y + r.h <= plate.y + plate.h - insets.bottom,
						"busy dot escapes the button's vertical content box"
					)
					assert(
						r.x - (label.rect.x + label.rect.w)
							>= (metrics or require("../src/themes/snapshot").neutral()).space.s,
						"busy indicator needs a theme gap after its label"
					)
					assert(
						math.abs((label.rect.y + label.rect.h / 2) - (r.y + r.h / 2)) <= 1,
						"busy indicator and label must share a vertical center"
					)
				end
			end
			t.expect(dots).toBe(5)
			t.expect(w.adapter.node(label.path)).toBe(label)
			busy:set(false)
			w.pres.refresh()
			t.expect(w.adapter.node(label.path)).toBe(label)
			w.pres.dismiss(w.handle)
			button.dispose()
		end)
	end
	t.it("a pending modal immediately blocks underlying repeat and shortcut activation", function()
		local w = world.new()
		local calls = 0
		local button = Facet.Controls.Button(w.core, {
			id = "B",
			label = "Repeat",
			repeatDelay = 0.4,
			shortcut = { keyCode = "F6" },
			onActivate = function()
				calls += 1
			end,
		})
		w.present(Facet.UI.Screen({ id = "S", children = { button.blueprint } }))
		w.tick(0)
		w.press("Return")
		t.expect(calls).toBe(1)
		local modal = w.pres.presentModal(
			Facet.UI.Screen({
				id = "Modal",
				children = { Facet.UI.Button({ id = "Confirm", label = "Confirm pending modal" }) },
			}),
			{ revealWhenTextExact = true }
		)
		t.expect(w.adapter.rootVisibleOf("Modal")).toBe(false)
		-- No refresh or tick: the modal owns input from the moment it is presented.
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.system.deviceKey("F6", true)
		w.system.deviceKey("F6", false)
		t.expect(calls).toBe(1)
		w.pres.dismiss(modal)
		w.tick(0)
		w.press("F6")
		t.expect(calls).toBe(2)
		w.pres.dismiss(w.handle)
		button.dispose()
	end)
	t.it("hold repeat stops on release busy and disposal and shortcuts respect active text entry", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local busy = w.core:signal(false)
		local enabled = w.core:signal(true)
		local calls = 0
		local button = Facet.Controls.Button(w.core, {
			id = "B",
			label = "Increase",
			busy = busy,
			enabled = enabled,
			repeatDelay = 0.4,
			repeatInterval = 0.1,
			shortcut = { keyCode = "F6" },
			onActivate = function()
				calls += 1
			end,
		})
		local editor = Facet.Controls.TextInput(w.core, { id = "E", value = w.core:signal(""), multiline = true })
		w.present(Facet.UI.Screen({ id = "S", children = { button.blueprint, editor.blueprint } }))
		w.tick(0)
		w.system.deviceKey("ButtonA", true)
		w.tick(0.4)
		t.expect(calls).toBe(2)
		w.system.deviceKey("ButtonA", false)
		w.tick(1)
		t.expect(calls).toBe(2)
		busy:set(true)
		w.tick(0)
		w.system.deviceKey("F6", true)
		w.system.deviceKey("F6", false)
		t.expect(calls).toBe(2)
		busy:set(false)
		w.tick(0)
		w.system.deviceKey("F6", true)
		w.system.deviceKey("F6", false)
		t.expect(calls).toBe(3)
		w.adapter.tap("/S/E/Viewport/Field")
		w.adapter.focusText("/S/E/Viewport/Field")
		w.tick(0)
		w.system.deviceKey("F6", true)
		w.system.deviceKey("F6", false)
		t.expect(calls).toBe(3)
		button.dispose()
		w.tick(1)
		t.expect(calls).toBe(3)
		w.pres.dismiss(w.handle)
		editor.dispose()
	end)

	t.it("plain buttons do not accumulate frame work when geometry is refreshed", function()
		local w = world.new()
		local registrations = 0
		local onTick = w.pres.onTick
		w.pres.onTick = function(fn)
			registrations += 1
			return onTick(fn)
		end
		local button = Facet.Controls.Button(w.core, { label = "Plain", onActivate = function() end })
		w.present(Facet.UI.Screen({ id = "S", children = { button.blueprint } }))
		local mounted = registrations
		for _ = 1, 5 do
			w.pres.refresh()
		end
		t.expect(registrations).toBe(mounted)
		w.pres.dismiss(w.handle)
		button.dispose()
	end)

	t.it("leaving a repeated pointer hold does not consume the next shortcut", function()
		local w = world.new()
		local calls = 0
		local button = Facet.Controls.Button(w.core, {
			id = "B",
			label = "Repeat",
			repeatDelay = 0.4,
			shortcut = { keyCode = "F6" },
			onActivate = function()
				calls += 1
			end,
		})
		w.present(Facet.UI.Screen({ id = "S", children = { button.blueprint } }))
		w.tick(0)
		local r = w.controller.rectOf("/S/B")
		w.adapter.pointerDown("/S/B", r.x + 2, r.y + 2, "mouse")
		w.tick(0.4)
		t.expect(calls).toBe(1)
		w.adapter.pointerMove(r.x + r.w + 20, r.y + r.h + 20)
		w.adapter.pointerUp(r.x + r.w + 20, r.y + r.h + 20)
		w.press("F6")
		t.expect(calls).toBe(2)
		w.pres.dismiss(w.handle)
		button.dispose()
	end)

	t.it("dismissing a surface releases its button keys before the control is disposed", function()
		local w = world.new()
		local button = Facet.Controls.Button(w.core, {
			id = "Old",
			label = "Old",
			repeatDelay = 0.4,
			onActivate = function() end,
		})
		local handle = w.present(Facet.UI.Screen({ id = "OldScreen", children = { button.blueprint } }))
		w.tick(0)
		w.pres.dismiss(handle)
		local calls = 0
		w.present(Facet.UI.Screen({
			id = "NewScreen",
			children = {
				Facet.UI.Button({
					id = "New",
					label = "New",
					onActivate = function()
						calls += 1
					end,
				}),
			},
		}))
		w.tick(0)
		w.press("Return")
		t.expect(calls).toBe(1)
		w.pres.dismiss(w.handle)
		button.dispose()
	end)

	t.it("an initially busy button starts its spinner and releases it when busy ends", function()
		local w = world.new()
		local busy = w.core:signal(true)
		local button = Facet.Controls.Button(w.core, {
			label = "Loading",
			busy = busy,
			onActivate = function() end,
		})
		w.present(Facet.UI.Screen({ id = "S", children = { button.blueprint } }))
		w.tick(1)
		t.expect(w.pres.motionClock:activeCount()).toBe(1)
		busy:set(false)
		w.tick(1)
		t.expect(w.pres.motionClock:activeCount()).toBe(0)
		busy:set(true)
		w.tick(1)
		t.expect(w.pres.motionClock:activeCount()).toBe(1)
		w.pres.dismiss(w.handle)
		button.dispose()
		t.expect(w.pres.motionClock:activeCount()).toBe(0)
	end)

	for _, device in { { key = "ButtonA", pointer = "gamepad" }, { key = "Return", pointer = "keyboard" } } do
		t.it(`a held {device.pointer} release cannot add a native activation after the repeat`, function()
			local now = 0
			local w = world.new({ presenterOpts = {
				now = function()
					return now
				end,
			} })
			local calls = 0
			local button = Facet.Controls.Button(w.core, {
				id = "B",
				label = "Repeat",
				repeatDelay = 0.4,
				repeatInterval = 0.1,
				onActivate = function()
					calls += 1
				end,
			})
			w.present(Facet.UI.Screen({ id = "S", children = { button.blueprint } }))
			w.tick(0)
			w.system.deviceKey(device.key, true)
			now = 0.4
			w.tick(0.4)
			t.expect(calls).toBe(2)
			-- A real held release can arrive outside the presenter's short echo window.
			now = 0.48
			w.system.deviceKey(device.key, false)
			w.adapter.tap("/S/B", { source = "pointer", pointer = device.pointer })
			t.expect(calls).toBe(2)
			now = 0.6
			w.press(device.key)
			t.expect(calls).toBe(3)
			w.pres.dismiss(w.handle)
			button.dispose()
		end)
	end

	t.it("overlapping shortcut and default bindings activate one button once", function()
		local w = world.new()
		local calls = 0
		local button = Facet.Controls.Button(w.core, {
			label = "Default",
			shortcut = { keyCode = "Return" },
			dialogAction = "default",
			onActivate = function()
				calls += 1
			end,
		})
		w.present(Facet.UI.Screen({ id = "S", children = { button.blueprint } }))
		w.tick(0)
		w.press("Return")
		t.expect(calls).toBe(1)
		w.pres.dismiss(w.handle)
		button.dispose()
	end)

	t.it("the first eligible default in document order wins and yields while hidden or disabled", function()
		local w = world.new()
		local hidden = w.core:signal(false)
		local enabled = w.core:signal(true)
		local chosen = ""
		-- Construction and lexical order deliberately differ from document order.
		local later = Facet.Controls.Button(w.core, {
			id = "A",
			label = "Later",
			dialogAction = "default",
			onActivate = function()
				chosen ..= "A"
			end,
		})
		local first = Facet.Controls.Button(w.core, {
			id = "Z",
			label = "First",
			dialogAction = "default",
			enabled = enabled,
			onActivate = function()
				chosen ..= "Z"
			end,
		})
		w.present(Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.VStack({ id = "First", hidden = hidden, children = { first.blueprint } }),
				later.blueprint,
			},
		}))
		w.tick(0)
		w.press("Return")
		t.expect(chosen).toBe("Z")
		hidden:set(true)
		w.pres.refresh()
		w.tick(0)
		w.press("Return")
		t.expect(chosen).toBe("ZA")
		hidden:set(false)
		enabled:set(false)
		w.pres.refresh()
		w.tick(0)
		w.press("Return")
		t.expect(chosen).toBe("ZAA")
		enabled:set(true)
		w.pres.refresh()
		w.tick(0)
		w.press("Return")
		t.expect(chosen).toBe("ZAAZ")
		w.pres.dismiss(w.handle)
		first.dispose()
		later.dispose()
	end)

	for _, pointer in { "mouse", "touch" } do
		for _, order in { "before", "after" } do
			t.it(
				`{pointer} repeat suppresses native Activated {order} pointer release, then accepts a fresh tap`,
				function()
					local w = world.new()
					local calls = 0
					local button = Facet.Controls.Button(w.core, {
						id = "B",
						label = "Repeat",
						repeatDelay = 0.4,
						onActivate = function()
							calls += 1
						end,
					})
					w.present(Facet.UI.Screen({ id = "S", children = { button.blueprint } }))
					w.tick(0)
					local r = w.controller.rectOf("/S/B")
					local x, y = r.x + 2, r.y + 2
					w.adapter.pointerDown("/S/B", x, y, pointer)
					w.tick(0.4)
					t.expect(calls).toBe(1)
					w.adapter.pointerUpActivating(x, y, order)
					t.expect(calls).toBe(1)
					w.adapter.pointerDown("/S/B", x, y, pointer)
					w.adapter.pointerUpActivating(x, y, order)
					t.expect(calls).toBe(2)
					w.pres.dismiss(w.handle)
					button.dispose()
				end
			)
		end
	end
end)
