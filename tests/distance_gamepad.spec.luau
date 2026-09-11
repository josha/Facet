--!strict
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local Facet = require("../src") :: any
local fake = require("./lib/fake_target")
local recipe = require("../src/controls/menu_recipe")
local UI = Facet.UI

describe("distance and controller adaptation", function()
	it("navigates nested columns by their resting geometry", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("preferredInput", "Gamepad")
		local system = Facet.newActionSystem(core)
		local pres = Facet.newPresenter(core, env, fake.new(), system)
		local function button(id)
			return UI.Button({
				id = id,
				label = id,
				width = { type = "fixed", px = 240 },
				height = { type = "fixed", px = 66 },
			})
		end
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "Panes",
					gap = 80,
					children = {
						UI.VStack({ id = "Sidebar", gap = 12, children = { button("A"), button("B") } }),
						UI.VStack({ id = "Detail", gap = 12, children = { button("C"), button("D") } }),
					},
				}),
			},
		}))
		local function press(key)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
		end
		pres.focus.focusOn("/S/Panes/Sidebar/A")
		press("DPadDown")
		expect(pres.focus.focused:get()).toBe("/S/Panes/Sidebar/B")
		press("DPadRight")
		expect(pres.focus.focused:get()).toBe("/S/Panes/Detail/D")
		press("DPadUp")
		expect(pres.focus.focused:get()).toBe("/S/Panes/Detail/C")
		press("DPadLeft")
		expect(pres.focus.focused:get()).toBe("/S/Panes/Sidebar/A")
	end)

	it("uses aligned eligible geometry, live positions, and stable ties", function()
		local graph = Facet.newFocusGraph(Facet.newCore())
		local eligible = true
		local rects = {
			a = { x = 0, y = 0, w = 40, h = 40 },
			b = { x = 120, y = 0, w = 60, h = 80 },
			c = { x = 50, y = 70, w = 40, h = 40 },
			d = { x = 50, y = 70, w = 40, h = 40 },
		}
		local reads = 0
		graph.pushScope({
			name = "S",
			trap = false,
			groups = {
				{
					name = "layout",
					axis = "horizontal",
					order = {
						"a",
						{
							id = "b",
							focusable = function()
								return eligible
							end,
						},
						"c",
						"d",
					},
					rectOf = function(id)
						reads += 1
						return rects[id]
					end,
				},
			},
		})
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("b") -- the aligned beam wins over a nearer diagonal
		expect(reads <= 4).toBe(true) -- one mounted-candidate pass
		graph.focusOn("a")
		eligible = false
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("c") -- ineligible is skipped; document-order tie
		graph.focusOn("a")
		eligible = true
		rects.b.x = -120 -- changed layout/RTL without rebuilding the map
		graph.navigateDirection("left")
		expect(graph.focused:get()).toBe("b")
	end)

	it("keeps an explicitly wrapping group ahead of geometric fallback", function()
		local graph = Facet.newFocusGraph(Facet.newCore())
		graph.pushScope({
			name = "S",
			trap = false,
			groups = {
				{
					name = "commands",
					axis = "horizontal",
					wrap = true,
					order = { "a", "b" },
					rectOf = function()
						error("declared wrapping order must remain authoritative")
					end,
				},
			},
		})
		graph.focusOn("b")
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("a")
	end)

	it("keeps explicit grid topology ahead of a geometry resolver", function()
		local graph = Facet.newFocusGraph(Facet.newCore())
		graph.pushScope({
			name = "S",
			trap = false,
			groups = {
				{
					name = "grid",
					axis = "horizontal",
					columns = 2,
					order = { "a", "b", "c", "d" },
					rectOf = function()
						error("explicit grid must not use geometric fallback")
					end,
				},
			},
		})
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c")
	end)

	it("adapts a mounted stack axis without waiting for a structural change", function()
		local w = require("./lib/world").new({ viewport = { x = 0, y = 0, w = 1280, h = 720 } })
		local axis = w.core:signal("y")
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.AdaptiveStack({
					id = "Run",
					axis = axis,
					children = {
						UI.Button({ id = "A", label = "A" }),
						UI.Button({ id = "B", label = "B" }),
					},
				}),
			},
		}))
		axis:set("x")
		w.settle(1)
		w.pres.focus.focusOn("/S/Run/A")
		w.pres.focus.navigateDirection("down")
		expect(w.pres.focus.focused:get()).toBe("/S/Run/A")
		w.pres.focus.navigateDirection("right")
		expect(w.pres.focus.focused:get()).toBe("/S/Run/B")
	end)

	it("remembers a tab's focus without retaining its content and respects pointer entry", function()
		local w =
			require("./lib/world").new({ viewport = { x = 0, y = 0, w = 1280, h = 720 }, preferredInput = "Gamepad" })
		local selected = w.core:signal("gear")
		local function page()
			return UI.VStack({
				id = "Page",
				children = { UI.Button({ id = "A", label = "A" }), UI.Button({ id = "B", label = "B" }) },
			})
		end
		local tabs = Facet.Controls.TabView(w.core, {
			id = "Tabs",
			selection = selected,
			env = w.env,
			placement = "topBar",
			tabs = {
				{ id = "gear", label = "Gear", content = page },
				{ id = "options", label = "Options", content = page },
			},
		})
		w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
		local function path(id)
			for _, p in w.adapter.paths() do
				if string.find(p, "/Tab-gear/", 1, true) and string.sub(p, -#id - 1) == "/" .. id then
					return p
				end
			end
			error("missing gear " .. id)
		end
		local a, b = path("A"), path("B")
		w.pres.focus.focusOn(b)
		selected:set("options")
		w.settle(1)
		selected:set("gear")
		w.settle(1)
		-- The page was rebuilt, but only its stable path was retained.
		expect(tabs.dump().contentEvictions > 0).toBe(true)
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(b)
		w.pres.focus.setFocusOrigin("pointer")
		w.pres.focus.focusOn(a)
		expect(w.pres.focus.focused:get()).toBe(a)
		tabs.dispose()
	end)

	it("keeps authored distance independent of capabilities and input switches", function()
		local env = Facet.newEnvironment(Facet.newCore())
		env:set("displaySize", "Large")
		env:set("capabilities", { touch = true, gamepad = true })
		env:set("viewingDistance", "ten-foot")
		expect(env:get("distanceProfile"):get()).toBe("ten-foot")
		env:set("preferredInput", "Touch")
		expect(env:get("effectiveDisplaySize"):get()).toBe("Large")
		expect(env:get("distanceProfileSource"):get()).toBe("authored")
		env:set("viewingDistance", "near")
		expect(env:get("effectiveDisplaySize"):get()).toBe("Medium")
		env:set("viewingDistance", "automatic")
		expect(env:get("distanceProfileSource"):get()).toBe("inferred")
		expect(env:get("distanceProfile"):get()).toBe("near")
		expect(env:get("displaySize"):get()).toBe("Large")
	end)

	it("keeps Pixel Quest selection ornaments outside their own label box", function()
		local pkg = require("../examples/themes/pixel_quest").build(Facet.themes)
		local chrome = require("../src/tokens/chrome_slots")
		local snapshot = require("../src/themes/snapshot")
		local w = require("./lib/world").new({ themeMetrics = snapshot.resolve(pkg, nil, {}) })
		w.present(
			UI.Screen({ id = "S", children = { UI.Button({ id = "Choice", label = "Quest", selected = true }) } })
		)
		local rect = w.adapter.node("/S/Choice").rect
		local plan = chrome.layerPlanFor(pkg, "selection")
		local lift = chrome.liftGeometry(plan, rect.w, rect.h, 16, 16)
		local label = {
			x = lift.position.xOffset,
			y = lift.position.yOffset,
			w = rect.w + lift.size.xOffset,
			h = rect.h + lift.size.yOffset,
		}
		for _, layer in plan.layers do
			if layer.kind == "corners" then
				for _, box in chrome.layerBoxes(layer) do
					local width = box.size.xScale * rect.w + box.size.xOffset
					local height = box.size.yScale * rect.h + box.size.yOffset
					local x = box.position.xScale * rect.w + box.position.xOffset - box.anchor.x * width
					local y = box.position.yScale * rect.h + box.position.yOffset - box.anchor.y * height
					local overlap = math.min(label.x + label.w, x + width) > math.max(label.x, x)
						and math.min(label.y + label.h, y + height) > math.max(label.y, y)
					expect(overlap).toBe(false)
				end
			end
		end
	end)

	it("uses the existing sheet for long controller choices, retaining short quick menus", function()
		expect(recipe.resolvePresentation(12, "regular", false, true)).toBe("sheet")
		expect(recipe.resolvePresentation(4, "regular", false, true)).toBe("menu")
		expect(recipe.resolvePresentation(12, "regular", false, false)).toBe("menu")
	end)
end)
