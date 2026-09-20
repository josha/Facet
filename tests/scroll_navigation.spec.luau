--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local world = require("./lib/harness_world")
local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local UI = harness.UI
t.describe("named scroll navigation", function()
	t.it("shares model-owned offsets between active presentations and across remount", function()
		local Compose = Facet.Compose
		local position, screen = Compose.cell(150), Compose.cell(false)
		local function surface(isScreen)
			local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 300 }, reducedMotion = true })
			w.present(UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Scroll",
						width = UI.fill(),
						height = UI.fill(),
						navigation = {
							targets = {},
							position = position,
							active = function(use)
								return use(screen) == isScreen
							end,
						},
						children = { UI.Box({ height = { type = "fixed", px = 1200 } }) },
					}),
				},
			}))
			w.settle(3)
			return w
		end
		local spatial, flat = surface(false), surface(true)
		t.expect(spatial.controller.scrollPosition("/S/Scroll").y).toBe(150)
		spatial.adapter.driveScroll("/S/Scroll", { x = 0, y = 420 })
		spatial.settle(3)
		t.expect(position:peek()).toBe(420)
		screen:set(true)
		spatial.settle(3)
		flat.settle(3)
		t.expect(flat.controller.scrollPosition("/S/Scroll").y).toBe(420)
		-- A hidden surface's native clamp/echo must not replace the shared state.
		spatial.adapter.driveScroll("/S/Scroll", { x = 0, y = 0 })
		t.expect(position:peek()).toBe(420)
		flat.adapter.driveScroll("/S/Scroll", { x = 0, y = 660 })
		flat.settle(3)
		t.expect(position:peek()).toBe(660)
		flat.pres.dismiss(flat.handle)
		local reopened = surface(true)
		t.expect(reopened.controller.scrollPosition("/S/Scroll").y).toBe(660)
		screen:set(false)
		spatial.settle(3)
		t.expect(spatial.controller.scrollPosition("/S/Scroll").y).toBe(660)
		reopened.pres.dismiss(reopened.handle)
		spatial.pres.dismiss(spatial.handle)
	end)
	t.it("resolves named destinations, publishes visibility crossings and scroll progress", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 300 }, reducedMotion = true })
		local target = Compose.cell(nil)
		local progress = Compose.cell(0)
		local events = {}
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Scroll",
					width = UI.fill(),
					height = UI.fill(),
					navigation = {
						targets = { "Hero", "Shelf", "End" },
						target = target,
						progress = progress,
						onVisibilityChanged = function(id, visible)
							table.insert(events, { id, visible })
						end,
					},
					children = {
						UI.Box({ id = "Hero", width = UI.fill(), height = { type = "fixed", px = 300 } }),
						UI.Box({ id = "Shelf", width = UI.fill(), height = { type = "fixed", px = 300 } }),
						UI.Box({ id = "End", width = UI.fill(), height = { type = "fixed", px = 300 } }),
					},
				}),
			},
		}))
		target:set("Shelf")
		w.settle(3)
		t.expect(w.controller.scrollPosition("/S/Scroll").y).toBe(300)
		t.expect(progress:peek()).toBe(0.5)
		local count = #events
		w.settle(5)
		t.expect(#events).toBe(count)
		local reads = 0
		local readRect = w.controller.screenRectOf
		w.controller.screenRectOf = function(...)
			reads += 1
			return readRect(...)
		end
		w.settle(5)
		t.expect(reads).toBe(0)
		w.controller.screenRectOf = readRect
		target:set("End")
		w.settle(3)
		t.expect(w.controller.scrollPosition("/S/Scroll").y).toBe(600)
		w.pres.dismiss(w.handle)
	end)
	t.it("finishes and settles normal motion target travel with gesture snap disabled", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 300 }, reducedMotion = false })
		local target = Compose.cell(nil)
		local progress = Compose.cell(0)
		local events = {}
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Scroll",
					width = UI.fill(),
					height = UI.fill(),
					navigation = {
						targets = { "Hero", "Shelf", "End" },
						target = target,
						progress = progress,
						onVisibilityChanged = function(id, visible)
							table.insert(events, { id, visible })
						end,
					},
					children = {
						UI.Box({ id = "Hero", width = UI.fill(), height = { type = "fixed", px = 300 } }),
						UI.Box({ id = "Shelf", width = UI.fill(), height = { type = "fixed", px = 300 } }),
						UI.Box({ id = "End", width = UI.fill(), height = { type = "fixed", px = 300 } }),
					},
				}),
			},
		}))
		target:set("Shelf")
		w.settle(90)
		t.expect(w.controller.scrollPosition("/S/Scroll").y).toBe(300)
		t.expect(progress:peek()).toBe(0.5)
		local count = #events
		w.settle(5)
		t.expect(#events).toBe(count)
		local reads = 0
		local readRect = w.controller.screenRectOf
		w.controller.screenRectOf = function(...)
			reads += 1
			return readRect(...)
		end
		w.settle(5)
		t.expect(reads).toBe(0)
		w.controller.screenRectOf = readRect
		target:set("End")
		w.settle(90)
		t.expect(w.controller.scrollPosition("/S/Scroll").y).toBe(600)
		w.pres.dismiss(w.handle)
	end)
	t.it("does not snap a focused descendant out of view", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 300 }, preferredInput = "Gamepad" })
		local function button(id)
			return UI.Button({ id = id, label = id, height = { type = "fixed", px = 50 } })
		end
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Scroll",
					width = UI.fill(),
					height = UI.fill(),
					navigation = { targets = { "Hero", "Shelf" }, snap = true },
					children = {
						UI.VStack({
							id = "Hero",
							height = { type = "fixed", px = 300 },
							children = { UI.Box({ height = { type = "fixed", px = 250 } }), button("HeroButton") },
						}),
						UI.VStack({
							id = "Shelf",
							height = { type = "fixed", px = 300 },
							children = {
								button("ShelfButton"),
							},
						}),
					},
				}),
			},
		}))
		w.pres.focus.focusOn("/S/Scroll/Hero/HeroButton")
		w.press("DPadDown")
		w.settle(100)
		t.expect(w.pres.focus.focused:peek()).toBe("/S/Scroll/Shelf/ShelfButton")
		local rect = w.controller.screenRectOf("/S/Scroll/Shelf/ShelfButton")
		t.expect(rect.y + rect.h <= 300).toBe(true)
		w.pres.dismiss(w.handle)
	end)
	t.it("contains a throwing visibility callback and continues rendering", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 300 } })
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Scroll",
					width = UI.fill(),
					height = UI.fill(),
					navigation = {
						targets = { "A" },
						onVisibilityChanged = function()
							error("consumer callback failed")
						end,
					},
					children = { UI.Box({ id = "A", height = { type = "fixed", px = 300 } }) },
				}),
			},
		}))
		w.settle(3)
		t.expect(w.controller.rectOf("/S/Scroll/A") ~= nil).toBe(true)
		w.pres.dismiss(w.handle)
	end)

	t.it("resolves a late-mounted destination after pending geometry changes", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 300 }, reducedMotion = true })
		local on = Compose.cell(false)
		local height = Compose.cell({ type = "fixed", px = 300 })
		local target = Compose.cell(nil)
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.When({
					id = "When",
					condition = on,
					thenView = function()
						return UI.ScrollView({
							id = "Scroll",
							width = UI.fill(),
							height = UI.fill(),
							navigation = { targets = { "Hero", "Shelf" }, target = target },
							children = {
								UI.Box({ id = "Hero", height = height }),
								UI.Box({ id = "Shelf", height = { type = "fixed", px = 300 } }),
							},
						})
					end,
				}),
			},
		}))
		on:set(true)
		w.settle(3)
		height:set({ type = "fixed", px = 400 })
		target:set("Shelf")
		w.settle(3)
		t.expect(w.controller.scrollPosition("/S/When/then/Scroll").y).toBe(400)
		w.pres.dismiss(w.handle)
	end)
	t.it("announces one visibility exit when a visible target unmounts", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 300 } })
		local shown = Compose.cell(true)
		local exits = 0
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Scroll",
					width = UI.fill(),
					height = UI.fill(),
					navigation = {
						targets = { "A" },
						onVisibilityChanged = function(id, on)
							if id == "A" and not on then
								exits += 1
							end
						end,
					},
					children = {
						UI.When({
							id = "Gate",
							condition = shown,
							thenView = function()
								return UI.Box({ id = "A", height = { type = "fixed", px = 300 } })
							end,
						}),
					},
				}),
			},
		}))
		shown:set(false)
		w.settle(3)
		t.expect(exits).toBe(1)
		w.settle(5)
		t.expect(exits).toBe(1)
		shown:set(true)
		w.settle(3)
		shown:set(false)
		w.settle(3)
		t.expect(exits).toBe(2)
		w.pres.dismiss(w.handle)
	end)
	for _, reduced in { true, false } do
		t.it("hands explicit scroll travel to eligible target focus, reduced " .. tostring(reduced), function()
			local w = world.new({
				viewport = { x = 0, y = 0, w = 600, h = 300 },
				reducedMotion = reduced,
				preferredInput = "Gamepad",
			})
			local target = Compose.cell(nil)
			w.present(UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Scroll",
						width = UI.fill(),
						height = UI.fill(),
						navigation = { targets = { "Shelf" }, target = target, focus = "target" },
						children = {
							UI.Button({ id = "Start", label = "Start", height = { type = "fixed", px = 300 } }),
							UI.VStack({
								id = "Shelf",
								height = { type = "fixed", px = 300 },
								children = {
									UI.Button({ id = "Disabled", label = "Disabled", enabled = false }),
									UI.Button({ id = "Equip", label = "Equip" }),
								},
							}),
						},
					}),
				},
			}))
			w.pres.focus.focusOn("/S/Scroll/Start")
			target:set("Shelf")
			w.settle(90)
			t.expect(w.pres.focus.focused:peek()).toBe("/S/Scroll/Shelf/Equip")
			w.pres.dismiss(w.handle)
		end)
	end
end)

t.describe("scroll target focus interruptions", function()
	local function fixture(focus)
		local w = world.new({
			viewport = { x = 0, y = 0, w = 600, h = 300 },
			preferredInput = "Gamepad",
			reducedMotion = false,
		})
		local target = Compose.cell(nil)
		local shown = Compose.cell(true)
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Scroll",
					width = UI.fill(),
					height = UI.fill(),
					navigation = { targets = { "Shelf" }, target = target, focus = focus },
					children = {
						UI.VStack({
							id = "Start",
							height = { type = "fixed", px = 300 },
							children = {
								UI.Button({ id = "First", label = "First" }),
								UI.Button({ id = "Other", label = "Other" }),
							},
						}),
						UI.When({
							id = "Gate",
							condition = shown,
							thenView = function()
								return UI.VStack({
									id = "Shelf",
									height = { type = "fixed", px = 300 },
									children = { UI.Button({ id = "Equip", label = "Equip" }) },
								})
							end,
						}),
						UI.Box({ height = { type = "fixed", px = 300 } }),
					},
				}),
			},
		}))
		w.pres.focus.focusOn("/S/Scroll/Start/First")
		return w, target, shown
	end
	t.it("preserves focus by default after completed travel", function()
		local w, target = fixture(nil)
		target:set("Shelf")
		w.settle(90)
		t.expect(w.controller.scrollPosition("/S/Scroll").y).toBe(300)
		t.expect(w.pres.focus.focused:peek()).toBe("/S/Scroll/Start/First")
		w.pres.dismiss(w.handle)
	end)
	t.it("abandons arrival focus after the user moves focus during travel", function()
		local w, target = fixture("target")
		target:set("Shelf")
		w.settle(3)
		w.pres.focus.focusOn("/S/Scroll/Start/Other")
		w.settle(90)
		t.expect(w.pres.focus.focused:peek()).toBe("/S/Scroll/Start/Other")
		w.pres.dismiss(w.handle)
	end)
	t.it("does not resume arrival focus after an interrupting modal closes", function()
		local w, target = fixture("target")
		target:set("Shelf")
		w.settle(3)
		local modal = w.pres.presentModal(
			UI.Screen({ id = "Modal", children = { UI.Button({ id = "Close", label = "Close" }) } })
		)
		w.pres.refresh()
		w.settle(3)
		t.expect(w.pres.focus.focused:peek()).toBe("/Modal/Close")
		w.pres.dismiss(modal)
		w.settle(90)
		t.expect(w.pres.focus.focused:peek()).toBe("/S/Scroll/Start/First")
		w.pres.dismiss(w.handle)
	end)
	t.it("abandons target motion and arrival focus when native scrolling takes over", function()
		local w, target = fixture("target")
		target:set("Shelf")
		w.settle(3)
		w.adapter.driveScroll("/S/Scroll", { x = 0, y = 180 })
		w.settle(90)
		t.expect(w.controller.scrollPosition("/S/Scroll").y).toBe(180)
		t.expect(w.pres.focus.focused:peek()).toBe("/S/Scroll/Start/First")
		w.pres.dismiss(w.handle)
	end)
	t.it("does not hand focus to a removed and remounted destination", function()
		local w, target, shown = fixture("target")
		target:set("Shelf")
		w.settle(3)
		shown:set(false)
		w.settle(3)
		shown:set(true)
		w.settle(90)
		t.expect(w.pres.focus.focused:peek()).toBe("/S/Scroll/Start/First")
		w.pres.dismiss(w.handle)
	end)
end)

t.describe("scroll arrival input paradigms", function()
	for _, case in
		{
			{ "pointer", "requests and hands off named scroll focus through pointer" },
			{ "touch", "requests and hands off named scroll focus through touch" },
			{ "keyboard", "requests and hands off named scroll focus through keyboard" },
			{ "gamepad", "requests and hands off named scroll focus through gamepad" },
		}
	do
		local class = case[1]
		t.it(case[2], function()
			local w = world.new({
				viewport = { x = 0, y = 0, w = 600, h = 400 },
				reducedMotion = true,
				preferredInput = if class == "gamepad"
					then "Gamepad"
					elseif class == "touch" then "Touch"
					else "MouseKeyboard",
			})
			local target = Compose.cell(nil)
			w.present(UI.Screen({
				id = "S",
				children = {
					UI.Button({
						id = "Jump",
						label = "Settings",
						onActivate = function()
							target:set("Settings")
						end,
					}),
					UI.ScrollView({
						id = "Scroll",
						width = UI.fill(),
						height = UI.fill(),
						navigation = { targets = { "Settings" }, target = target, focus = "target" },
						children = {
							UI.Box({ id = "Hero", height = { type = "fixed", px = 400 } }),
							UI.VStack({
								id = "Settings",
								height = { type = "fixed", px = 400 },
								children = { UI.Button({ id = "Tune", label = "Tune" }) },
							}),
						},
					}),
				},
			}))
			w.pres.focus.focusOn("/S/Jump")
			if class == "pointer" then
				w.adapter.tap("/S/Jump")
			elseif class == "touch" then
				w.adapter.touchTap("/S/Jump")
			else
				w.press(if class == "keyboard" then "Return" else "ButtonA")
			end
			w.settle(4)
			t.expect(w.pres.focus.focused:peek()).toBe("/S/Scroll/Settings/Tune")
			local rect = w.controller.screenRectOf("/S/Scroll/Settings/Tune")
			t.expect(rect.y >= 0 and rect.y + rect.h <= 400).toBe(true)
			w.pres.dismiss(w.handle)
		end)
	end
end)

t.describe("reactive scroll axes", function()
	t.it("retains the native host and children while updating gamepad directions", function()
		for _, initial in { "x", "y" } do
			local w = world.new({ viewport = { x = 0, y = 0, w = 300, h = 300 }, preferredInput = "Gamepad" })
			local axis = Compose.cell(initial)
			local children = {}
			for _, id in { "A", "B", "C" } do
				table.insert(
					children,
					UI.Button({
						id = id,
						label = id,
						width = { type = "fixed", px = 100 },
						height = {
							type = "fixed",
							px = 100,
						},
					})
				)
			end
			w.present(UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Scroll",
						axis = axis,
						width = UI.fill(),
						height = UI.fill(),
						children = children,
					}),
				},
			}))
			local host, child = w.adapter.node("/S/Scroll"), w.adapter.node("/S/Scroll/A")
			w.pres.focus.focusOn("/S/Scroll/A")
			axis:set(if initial == "y" then "x" else "y")
			w.settle(2)
			w.press(if initial == "y" then "DPadRight" else "DPadDown")
			t.expect(w.pres.focus.focused:peek()).toBe("/S/Scroll/B")
			t.expect(w.adapter.node("/S/Scroll")).toBe(host)
			t.expect(w.adapter.node("/S/Scroll/A")).toBe(child)
			w.pres.dismiss(w.handle)
		end
	end)
	t.it("retargets an in-flight destination on an axis change without reviving cancelled focus", function()
		for _, cancel in { false, true } do
			local w = world.new({ viewport = { x = 0, y = 0, w = 300, h = 300 }, reducedMotion = false })
			local axis, target = Compose.cell("y"), Compose.cell(nil)
			local children = {}
			for _, id in { "A", "B", "C" } do
				table.insert(
					children,
					UI.VStack({
						id = id,
						width = { type = "fixed", px = 500 },
						height = { type = "fixed", px = 400 },
						children = {
							UI.Button({ id = "First", label = "First" }),
							UI.Button({
								id = "Other",
								label = "Other",
							}),
						},
					})
				)
			end
			w.present(UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Scroll",
						axis = axis,
						width = UI.fill(),
						height = UI.fill(),
						navigation = { targets = { "A", "B", "C" }, target = target, focus = "target" },
						children = children,
					}),
				},
			}))
			w.pres.focus.focusOn("/S/Scroll/A/First")
			target:set("C")
			w.settle(3)
			if cancel then
				w.pres.focus.focusOn("/S/Scroll/A/Other")
			end
			axis:set("x")
			w.settle(100)
			t.expect(w.controller.scrollPosition("/S/Scroll").y).toBe(0)
			if not cancel then
				t.expect(w.controller.scrollPosition("/S/Scroll").x).toBe(1000)
			end
			t.expect(w.pres.focus.focused:peek()).toBe(if cancel then "/S/Scroll/A/Other" else "/S/Scroll/C/First")
			w.pres.dismiss(w.handle)
		end
	end)
end)
