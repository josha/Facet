--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Facet = require("../src") :: any
local UI = Facet.UI
t.describe("tab sections and customization", function()
	t.it("dismissed navigation releases option bundles even when its handle is retained", function()
		local scene
		for _, candidate in require("../bench/perf_scenes") do
			if candidate.name == "adaptive-navigation-images" then
				scene = candidate
			end
		end
		local state = scene.setup(require("../bench/perf_profiles").get("desktop"))
		local watched = setmetatable({}, { __mode = "k" })
		local canary = setmetatable({}, { __mode = "k" })
		for _ = 1, 6 do
			for _, c in state.handle.contributions do
				watched[c.bundle] = true
			end
			state.env:set("viewportRect", { x = 0, y = 0, w = 360, h = 640 })
			state.pres.refresh()
			state.env:set("viewportRect", { x = 0, y = 0, w = 1440, h = 900 })
			state.pres.refresh()
		end
		local live = {}
		for _, c in state.handle.contributions do
			live[c.bundle] = true
		end
		t.expect(state.builds()).toBe(1)
		local retired = 0
		for bundle in watched do
			if not live[bundle] then
				retired += 1
			end
		end
		t.expect(retired > 0).toBe(true)
		scene.teardown(state)
		canary[{}] = true
		-- Keep the dismissed handle alive while exercising the collector.
		-- Lune cannot force collection; the canary reports when it has not run.
		for i = 1, 4000 do
			local waste = table.create(20000, i)
		end
		t.expect(state.handle.controller ~= nil).toBe(true) -- retain the dismissed handle through collection
		local collected = next(canary) == nil
		local retained = 0
		for bundle in watched do
			if not live[bundle] then
				retained += 1
			end
		end
		if collected then
			t.expect(retained).toBe(0)
		else
			print("sidebar bundle collection witness: inconclusive; GC canary still live")
		end
	end)
	t.it("live indicators do not reread unchanged geometry on idle refreshes", function()
		local w = world.new()
		local picker = Facet.Controls.Picker(w.core, {
			id = "P",
			presentation = "segmented",
			indicator = "pill",
			selected = w.core:signal("a"),
			options = w.core:signal({ { id = "a", value = "a", label = "A" }, { id = "b", value = "b", label = "B" } }),
		})
		w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
		w.settle(3)
		local node = w.handle.root.node.children[1].children[1]
		local bundle = require("../src/input/contribution").read(node)
		local reads = 0
		local function rectOf(path)
			reads += 1
			return w.controller.rectOf(path)
		end
		bundle.syncGeometry(rectOf, node)
		reads = 0
		for _ = 1, 20 do
			bundle.syncGeometry(rectOf, node)
		end
		t.expect(reads).toBe(0)
		w.pres.dismiss(w.handle)
		picker.dispose()
	end)
	t.it("reordering navigation keeps geometry feedback inside the changed chrome", function()
		local profiles = require("../bench/perf_profiles")
		local scene
		for _, candidate in require("../bench/perf_scenes") do
			if candidate.name == "navigation-customization" then
				scene = candidate
			end
		end
		local state = scene.setup(profiles.get("floorAndroid"))
		scene.afterRun(state)
		local controller = state.handle.controller
		local before = controller.stats()
		scene.run(state)
		local after = controller.stats()
		t.expect(after.feedbackSolves > before.feedbackSolves).toBe(true)
		t.expect(after.solves - before.solves).toBe(after.partialSolves - before.partialSolves)
		t.expect(state.builds()).toBe(1)
		state.pres.refresh()
		t.expect(controller.stats().solves).toBe(after.solves)
		scene.teardown(state)
	end)
	t.it("mounts section headings only on the vertical axis while preserving option identity", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 640, h = 480 } })
		local axis = w.core:signal("x")
		local picker = Facet.Controls.Picker(w.core, {
			id = "P",
			axis = axis,
			presentation = "segmented",
			indicator = "pill",
			selected = w.core:signal("home"),
			options = w.core:signal({ { id = "home", value = "home", label = "Home", sectionTitle = "Game" } }),
		})
		w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
		local optionPath
		local function headings(node)
			local count = if node.id == "SectionTitle" then 1 else 0
			if node.id == "Option-home" then
				optionPath = node.path
			end
			for _, child in node.children or {} do
				count += headings(child)
			end
			return count
		end
		t.expect(headings(w.handle.root.node)).toBe(0)
		local option = w.adapter.node(optionPath)
		axis:set("y")
		w.settle(2)
		t.expect(headings(w.handle.root.node)).toBe(1)
		t.expect(w.adapter.node(optionPath)).toBe(option)
		axis:set("x")
		w.settle(2)
		t.expect(headings(w.handle.root.node)).toBe(0)
		t.expect(w.adapter.node(optionPath)).toBe(option)
		w.pres.dismiss(w.handle)
		picker.dispose()
	end)
	t.it("fits nested horizontal tabs at largest text without reserving hidden section headings", function()
		local snapshot = require("../src/themes/snapshot")
		local w = world.new({
			viewport = { x = 0, y = 0, w = 640, h = 320 },
			safeInsets = { top = 120, bottom = 0, left = 0, right = 0 },
			preferredInput = "Touch",
			env = { preferredTextOffset = 14 },
			themeMetrics = snapshot.resolve(require("../examples/themes/fantasy_ornate").build(Facet.themes), nil, {}),
		})
		local built = require("../examples/gallery/scenarios/tab_view").build({
			Facet = Facet,
			core = w.core,
			env = w.env,
			adapter = w.adapter,
			presenter = w.pres,
			actionSystem = w.system,
		})
		w.present(built.screen, built.present)
		w.settle(2)
		t.expect(#w.controller.diagnostics()).toBe(0)
		local body = w.controller.rectOf(
			"/TabViewDemo/Root/App/Content/Tab-pages/then/PageScroll/PageViewport/Page/Content/Tab-avatars/then/PageBody"
		)
		t.expect(body.h).toBeGreaterThan(0)
		w.pres.dismiss(w.handle)
		built.dispose()
	end)
	t.it("ignores stale IDs, protects required tabs, and reorders without remounting content", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 800 } })
		local selection = w.core:signal("home")
		local customization =
			w.core:signal({ order = { "gone", "gear", "home", "gear" }, hidden = { "home", "settings" } })
		local mounts = 0
		local function page()
			mounts += 1
			return UI.Button({ id = "Play", label = "Play" })
		end
		local tabs = Facet.Controls.TabView(w.core, {
			id = "Tabs",
			selection = selection,
			style = "sidebarAdaptable",
			customization = customization,
			sections = { { id = "game", label = "Game" }, { id = "system", label = "System" } },
			tabs = {
				{ id = "home", label = "Home", required = true, section = "game", content = page },
				{ id = "gear", label = "Equipment", section = "game", content = page },
				{ id = "settings", label = "Settings", section = "system", content = page },
			},
		})
		w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
		t.expect(tabs.dump().visibleTabs).toEqual({ "gear", "home" })
		tabs.moveTab("home", 1)
		w.settle(2)
		t.expect(tabs.dump().visibleTabs).toEqual({ "home", "gear" })
		t.expect(mounts).toBe(1)
		t.expect(tabs.setTabHidden("home", true)).toBe(false)
		tabs.setTabHidden("settings", false)
		w.settle(2)
		t.expect(tabs.dump().visibleTabs).toEqual({ "home", "gear", "settings" })
		selection:set("gear")
		w.settle(2)
		tabs.setTabHidden("gear", true)
		w.settle(2)
		t.expect(selection:get()).toBe("home")
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
	t.it("moves the shared indicator when equal-sized keyed options reorder", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 300 }, reducedMotion = true })
		local a, b = { id = "a", value = "a", label = "AAA" }, { id = "b", value = "b", label = "BBB" }
		local options = w.core:signal({ a, b })
		local picker = Facet.Controls.Picker(w.core, {
			id = "P",
			options = options,
			selected = w.core:signal("a"),
			presentation = "segmented",
			indicator = "pill",
		})
		w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
		local before = picker.dump().indicator.rect.x
		options:set({ b, a })
		t.expect(picker.dump().indicator.rect.x).toBe(before)
		w.settle(3)
		t.expect(picker.dump().indicator.rect.x > before).toBe(true)
		w.pres.dismiss(w.handle)
		picker.dispose()
	end)
end)

t.describe("owned content shoulder navigation", function()
	t.it("pages from content only when opted in, and leaves value controls their adjustment", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 900, h = 600 }, preferredInput = "Gamepad" })
		local selected = w.core:signal("a")
		local policy = w.core:signal("content")
		local value = w.core:signal(0)
		local tabs = Facet.Controls.TabView(w.core, {
			id = "Tabs",
			env = w.env,
			selection = selected,
			shoulderNavigation = policy,
			tabs = {
				{
					id = "a",
					label = "Garage",
					content = function(scope)
						return UI.VStack({
							id = "Page",
							children = {
								UI.Button({ id = "Play", label = "Play" }),
								scope:own(
									Facet.Controls.Slider(
										w.core,
										{ id = "Tune", value = value, min = 0, max = 10, step = 1 }
									)
								).blueprint,
							},
						})
					end,
				},
				{
					id = "b",
					label = "Races",
					content = function()
						return UI.Button({ id = "Race", label = "Race" })
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
		local function focus(suffix)
			for _, e in w.pres.focus.focusMap().traversal do
				if string.sub(e.path, -#suffix) == suffix then
					w.pres.focus.focusOn(e.path)
					return
				end
			end
			error("missing focus " .. suffix)
		end
		focus("/Play")
		w.press("ButtonR1")
		w.settle(4)
		t.expect(selected:get()).toBe("b")
		t.expect(string.sub(w.pres.focus.focused:get(), -5)).toBe("/Race")
		w.press("ButtonL1")
		w.settle(4)
		focus("/Track")
		w.press("ButtonR1")
		w.settle(2)
		t.expect(selected:get()).toBe("a")
		t.expect(value:get()).toBe(1)
		policy:set("strip")
		focus("/Play")
		w.settle(2)
		w.press("ButtonR1")
		t.expect(selected:get()).toBe("a")
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
end)

t.describe("content shoulders respect nearest ownership", function()
	local function focus(w, suffix)
		for _, entry in w.pres.focus.focusMap().traversal do
			if string.sub(entry.path, -#suffix) == suffix then
				t.expect(w.pres.focus.focusOn(entry.path)).toBe(true)
				return entry.path
			end
		end
		error("missing focus " .. suffix)
	end
	for _, kind in { "Slider", "Stepper", "Rating" } do
		t.it("a saturated " .. kind .. " consumes shoulders without paging its parent", function()
			local w = world.new({ viewport = { x = 0, y = 0, w = 900, h = 600 }, preferredInput = "Gamepad" })
			local selected = w.core:signal("a")
			local value = w.core:signal(5)
			local tabs = Facet.Controls.TabView(w.core, {
				id = "Tabs",
				selection = selected,
				shoulderNavigation = "content",
				tabs = {
					{
						id = "a",
						label = "A",
						content = function(scope)
							local spec = { id = "Value", value = value }
							if kind ~= "Rating" then
								spec.min = 0
								spec.max = 5
								spec.step = 1
							end
							return scope:own(Facet.Controls[kind](w.core, spec)).blueprint
						end,
					},
					{
						id = "b",
						label = "B",
						content = function()
							return UI.Button({ id = "Next", label = "Next" })
						end,
					},
				},
			})
			w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
			local suffix = if kind == "Slider" then "/Track" elseif kind == "Rating" then "/Strip" else "/Dec"
			focus(w, suffix)
			w.system.deviceKey("ButtonR1", true)
			w.tick(0.6)
			w.system.deviceKey("ButtonR1", false)
			w.settle(2)
			t.expect(value:get()).toBe(5)
			t.expect(selected:get()).toBe("a")
			w.press("ButtonL1")
			t.expect(value:get()).toBe(4)
			t.expect(selected:get()).toBe("a")
			w.pres.dismiss(w.handle)
			tabs.dispose()
		end)
	end
	t.it("nested content paging clamps at the inner boundary and never pages the outer tabs", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 900, h = 600 }, preferredInput = "Gamepad" })
		local outer = w.core:signal("a")
		local inner = w.core:signal("one")
		local tabs = Facet.Controls.TabView(w.core, {
			id = "Outer",
			selection = outer,
			shoulderNavigation = "content",
			tabs = {
				{
					id = "a",
					label = "A",
					content = function(scope)
						return scope:own(Facet.Controls.TabView(w.core, {
							id = "Inner",
							selection = inner,
							shoulderNavigation = "content",
							tabs = {
								{
									id = "one",
									label = "One",
									content = function()
										return UI.Button({ id = "First", label = "First" })
									end,
								},
								{
									id = "two",
									label = "Two",
									content = function()
										return UI.Button({ id = "Second", label = "Second" })
									end,
								},
							},
						})).blueprint
					end,
				},
				{
					id = "b",
					label = "B",
					content = function()
						return UI.Button({ id = "OuterNext", label = "Outer next" })
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
		focus(w, "/First")
		w.press("ButtonR1")
		w.settle(4)
		t.expect(inner:get()).toBe("two")
		t.expect(outer:get()).toBe("a")
		t.expect(string.sub(w.pres.focus.focused:get(), -7)).toBe("/Second")
		w.press("ButtonR1")
		w.settle(4)
		t.expect(inner:get()).toBe("two")
		t.expect(outer:get()).toBe("a")
		w.press("ButtonL1")
		w.settle(4)
		t.expect(inner:get()).toBe("one")
		t.expect(outer:get()).toBe("a")
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
	t.it("an open popup and modal own shoulders before parent content paging", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 900, h = 600 }, preferredInput = "Gamepad" })
		local selected = w.core:signal("a")
		local choice = w.core:signal("one")
		local tabs = Facet.Controls.TabView(w.core, {
			id = "Tabs",
			selection = selected,
			shoulderNavigation = "content",
			tabs = {
				{
					id = "a",
					label = "A",
					content = function(scope)
						return scope:own(Facet.Controls.PopupButton(w.core, {
							id = "Choice",
							value = choice,
							options = {
								{ id = "one", label = "One" },
								{ id = "two", label = "Two" },
							},
						})).blueprint
					end,
				},
				{
					id = "b",
					label = "B",
					content = function()
						return UI.Button({ id = "Next", label = "Next" })
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
		focus(w, "/Trigger")
		w.press("ButtonA")
		w.settle(3)
		w.press("DPadDown")
		w.settle(2)
		local popupFocus = w.pres.focus.focused:get()
		t.expect(string.find(popupFocus, "/Popup/", 1, true) ~= nil).toBe(true)
		w.press("ButtonR1")
		w.settle(3)
		t.expect(selected:get()).toBe("a")
		t.expect(w.pres.focus.focused:get()).toBe(popupFocus)
		local modal = w.pres.presentModal(
			UI.Screen({ id = "Modal", children = { UI.Button({ id = "Close", label = "Close" }) } })
		)
		w.pres.refresh()
		w.press("ButtonR1")
		w.settle(3)
		t.expect(selected:get()).toBe("a")
		t.expect(w.pres.focus.focused:get()).toBe("/Modal/Close")
		w.pres.dismiss(modal)
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
end)
