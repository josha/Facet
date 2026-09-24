--!strict
local harness = require("./lib/harness")
local scenario_ctx = require("./lib/scenario_ctx")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/harness_world")
local fake = require("./lib/fake_target")
local catalog = require("../examples/gallery/scenarios/all_controls")
local collections = require("../examples/gallery/scenarios/collections")
local motion = require("../examples/gallery/scenarios/motion_layout")
local Compose = require("../src/vendor/compose/core")

local function button(w, label)
	for _, path in w.adapter.paths() do
		local node = w.adapter.node(path)
		local text = w.adapter.node(path .. "/Label")
		if node.class == "Button" and (node.props.label == label or (text and text.props.text == label)) then
			return path
		end
	end
	error("Missing button " .. label)
end
-- a category tab shares its words with an inner tab ("Menus", "Status"), so a
-- category is picked from the category bar alone
local function onBar(path)
	return string.find(path, "/Categories/", 1, true) ~= nil
		and string.find(path, "/Categories/Content/", 1, true) == nil
end
local function pick(w, label, bar)
	for _, path in w.adapter.paths() do
		local node = w.adapter.node(path)
		if node.class == "Button" and node.props.label == label and onBar(path) == bar then
			return path
		end
	end
	error("Missing tab " .. label)
end
local function category(w, label)
	return pick(w, label, true)
end
local function inner(w, label)
	return pick(w, label, false)
end
local function activate(w, label, pick)
	local path = (pick or button)(w, label)
	t.expect(w.pres.focus.focusOn(path)).toBe(true)
	w.press("ButtonA")
	w.settle(4)
end
-- Walk using only directional actions. Entry into a tab restores its bookmark,
-- so probing with focusOn and replaying a path would change the state being tested.
local function navigateTo(w, target)
	local visits = {}
	for _ = 1, 1280 do
		local current = w.pres.focus.focused:peek()
		if current == target then
			return
		end
		assert(current, "navigation lost focus")
		local edges = visits[current] or {}
		visits[current] = edges
		local nextKey, count = nil, math.huge
		for _, key in { "DPadUp", "DPadDown", "DPadLeft", "DPadRight" } do
			if (edges[key] or 0) < count then
				nextKey, count = key, edges[key] or 0
			end
		end
		edges[nextKey] = count + 1
		w.press(nextKey)
	end
	error("No D-pad route to " .. target)
end

local function make(scenario, viewport, options)
	options = options or {}
	local w = world.new({
		viewport = viewport,
		preferredInput = options.preferredInput or "Gamepad",
		themeMetrics = options.themeMetrics,
		env = { preferredTextOffset = options.textOffset or 0 },
		capabilities = { gamepad = true, keyboard = true, mouse = true, touch = false },
		reducedMotion = true,
		presenterOpts = { keyboardNavigation = options.keyboardNavigation == true },
		newAdapter = function()
			local adapter = fake.new()
			adapter.scrollBarThickness = fake.SCROLL_BAR_THICKNESS
			return adapter
		end,
	})
	local built = scenario.build({
		Facet = Facet,
		app = require("./lib/scenario_app").over(w.core, w.pres),
		UI = (harness.libraryOf(w.core)),
		Compose = Facet.Compose,
		Color3 = require("./lib/gui_value_shim").colorValues().Color3,
		core = w.core,
		env = w.env,
		presenter = w.pres,
		actionSystem = w.system,
	})
	if options.toolbar then
		local UI = harness.UI
		w.navigationLayout = Compose.cell(built.navigationLayout)
		local chrome = require("../examples/gallery/client/showcase_chrome").mount({
			Facet = Facet,
			app = scenario_ctx.ofHarness(w).app,
			core = w.core,
			env = w.env,
			actionSystem = w.system,
			coreTop = Compose.cell(0),
			navigationLayout = w.navigationLayout,
			demos = {
				chip = function()
					return UI.Button({ id = "DemoToggle", label = "All controls" })
				end,
				iconChip = function()
					return UI.Button({ id = "DemoToggle", label = "Demos" })
				end,
				rows = function()
					return UI.Box({ id = "Rows" })
				end,
			},
			settings = { sections = {} },
			onChipsBottom = function(bottom)
				w.env:set("appChromeInsets", { top = bottom + 8, bottom = 0, left = 0, right = 0 })
			end,
		})
		local dispose = built.dispose
		built.dispose = function()
			chrome.dispose()
			dispose()
		end
	end
	w.present(built.screen, built.present)
	return w, built
end

t.describe("Consolidated showcase", function()
	t.it("a category page is the room under its bar: Choices' Vote row is not below the fold", function()
		local w = make(
			catalog,
			{ x = 0, y = 0, w = 1542, h = 1067 },
			{ preferredInput = "MouseKeyboard", toolbar = true }
		)
		w.settle(4)
		activate(w, "Choices")
		local page, scroll
		for _, path in w.adapter.paths() do
			if string.sub(path, -13) == "/PageViewport" then
				page = w.controller.screenRectOf(path)
				scroll = w.controller.screenRectOf(string.sub(path, 1, -14))
			end
		end
		t.expect(page ~= nil and scroll ~= nil).toBe(true)
		t.expect(page.y + page.h <= scroll.y + scroll.h + 0.5).toBe(true)
	end)

	t.it("keeps the keyboard-focused recipe rail tail inside every nested clipping ancestor", function()
		local w, built = make(catalog, { x = 0, y = 0, w = 390, h = 844 }, {
			preferredInput = "MouseKeyboard",
			keyboardNavigation = true,
		})
		activate(w, "Actions")
		activate(w, "Recipes")
		local target = button(w, "Custom Rules")
		for _ = 1, 100 do
			if w.pres.focus.focused:peek() == target then
				break
			end
			w.press("Tab")
			w.settle(1)
		end
		t.expect(w.pres.focus.focused:peek()).toBe(target)
		t.expect(built.report().active).toBe("recipes")
		local clip = { x = 0, y = 0, right = 390, bottom = 844 }
		local path, hosts = "", 0
		for segment in target:gmatch("[^/]+") do
			path ..= "/" .. segment
			local node = w.adapter.node(path)
			if node and node.props.clipChildren == true then
				local rect = w.controller.screenRectOf(path)
				clip.x, clip.y = math.max(clip.x, rect.x), math.max(clip.y, rect.y)
				clip.right, clip.bottom = math.min(clip.right, rect.x + rect.w), math.min(clip.bottom, rect.y + rect.h)
				if node.scrollRegion then
					hosts += 1
				end
			end
		end
		t.expect(hosts).toBe(3)
		local rect = w.controller.screenRectOf(target)
		assert(
			rect.x >= clip.x and rect.y >= clip.y and rect.x + rect.w <= clip.right and rect.y + rect.h <= clip.bottom,
			`focused rail target {rect.x},{rect.y},{rect.w},{rect.h} outside clip {clip.x},{clip.y}..{clip.right},{clip.bottom}`
		)
		w.press("Return")
		w.settle(2)
		t.expect(built.report().example.railSelected["Custom Rules"]).toBe(true)
		w.pres.dismiss(w.handle)
		built.dispose()
		t.expect(#w.adapter.paths()).toBe(0)
	end)

	t.it("widens every inner tab to its engine width when the words arrive after the page mounts", function()
		-- Owner report 2026-09-22 (bugs/topClip.png): the Actions tabs kept the
		-- estimator's box after their exact widths arrived, clipping "Butto…".
		-- The word store is process-global, so it is restored however this ends.
		local text_metrics = require("../src/layout/text_metrics")
		local saved = text_metrics.measuredDump()
		local function widthOf(word: string, size: number): number
			return #word * size * 0.7
		end
		local ok, result = pcall(function()
			local w = make(catalog, { x = 0, y = 0, w = 1542, h = 1067 }, { preferredInput = "MouseKeyboard" })
			local function deliver()
				for _ = 1, 6 do
					w.adapter.deliverTextWidths(widthOf, true)
				end
				w.settle(2)
			end
			deliver()
			activate(w, "Actions")
			deliver()
			local wanted = {}
			for _, label in { "Buttons", "Recipes", "Menus", "Sheets", "Help" } do
				local rect = w.controller.rectOf(button(w, label))
				local need = math.ceil(widthOf(label, 18)) + 24
				table.insert(wanted, `{label} {rect.w >= need}`)
			end
			return table.concat(wanted, ", ")
		end)
		text_metrics.resetMeasured()
		for _, entry in saved do
			if entry.width == false then
				text_metrics.markUnmeasurable(entry.font, entry.size, entry.word)
			else
				text_metrics.setMeasured(entry.font, entry.size, entry.word, entry.width :: number)
			end
		end
		if not ok then
			error(result, 0)
		end
		t.expect(result).toBe("Buttons true, Recipes true, Menus true, Sheets true, Help true")
	end)

	t.it("offers toasts in Indicators and retires them when leaving the page", function()
		local w, built = make(catalog, { x = 0, y = 0, w = 1280, h = 800 })
		activate(w, "Status", category)
		activate(w, "Toasts")
		activate(w, "Show toast")
		t.expect(w.pres.toastCounts().visible).toBe(1)
		activate(w, "Test input: 0")
		local probe = button(w, "Test input: 1")
		t.expect(w.pres.focus.focused:peek()).toBe(probe)
		local rect = w.adapter.node(probe).rect
		w.adapter.tap(
			probe,
			{ source = "pointer", pointer = "mouse", x = rect.x + rect.w / 2, y = rect.y + rect.h / 2 }
		)
		w.settle(4)
		t.expect(button(w, "Test input: 2")).toBe(probe)
		t.expect(w.pres.toastCounts().visible).toBe(1)
		activate(w, "Progress")
		w.settle(8)
		t.expect(w.pres.toastCounts().visible).toBe(0)
		t.expect(w.pres.toastCounts().queued).toBe(0)
		w.pres.dismiss(w.handle)
		built.dispose()
	end)

	t.it("hides the toolbar action for compact, distant, and unrelated demos", function()
		local w, built = make(catalog, { x = 0, y = 0, w = 1280, h = 800 }, {
			toolbar = true,
			preferredInput = "MouseKeyboard",
		})
		local function count()
			local n = 0
			for _, path in w.adapter.paths() do
				local rect = w.adapter.node(path).rect
				if path:match("/ToggleSidebar$") and rect and rect.w > 0 and rect.h > 0 then
					n += 1
				end
			end
			return n
		end
		t.expect(count()).toBe(1)
		w.env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		w.settle(4)
		t.expect(count()).toBe(0)
		w.env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 800 })
		w.env:set("viewingDistance", "ten-foot")
		w.settle(4)
		t.expect(count()).toBe(0)
		w.env:set("viewingDistance", "near")
		w.settle(4)
		t.expect(count()).toBe(1)
		w.navigationLayout:set(nil)
		w.settle(4)
		t.expect(count()).toBe(0)
		w.pres.dismiss(w.handle)
		built.dispose()
	end)

	t.it("shows an unobscured desktop layout choice on first load and after switching homes", function()
		local metrics = {
			Facet.themes.resolve(require("../examples/themes/pixel_quest").build(Facet.themes), nil, {}),
			Facet.themes.resolve(require("../examples/themes/fantasy_ornate").build(Facet.themes), nil, {}),
		}
		for _, theme in { false, metrics[1], metrics[2] } do
			for _, offset in { 0, 14 } do
				local w, built = make(catalog, { x = 0, y = 0, w = 1280, h = 900 }, {
					toolbar = true,
					preferredInput = "MouseKeyboard",
					themeMetrics = theme or nil,
					textOffset = offset,
				})
				local page = button(w, "Basics")
				local pageNode = w.adapter.node(page)
				for _, home in { "sidebar", "topBar" } do
					t.expect(built.report().navigation.placement).toBe(home)
					local toggle
					for _, path in w.adapter.paths() do
						if
							path:match("/ToggleSidebar$")
							and w.adapter.node(path).rect.w > 0
							and w.adapter.node(path).rect.h > 0
						then
							toggle = path
						end
					end
					assert(
						toggle and toggle:find("/ShowcaseChrome/", 1, true),
						"layout choice belongs to the showcase toolbar"
					)
					local rect = w.adapter.node(toggle).rect
					assert(
						rect.w > 0 and rect.h > 0 and rect.h < 120,
						`choice {toggle} size {rect.w}x{rect.h} offset {offset}`
					)
					local bar
					for _, path in w.adapter.paths() do
						if path:match("/AdaptableBar$") then
							bar = w.adapter.node(path).rect
						end
					end
					assert(bar)
					t.expect(rect.y + rect.h <= bar.y).toBe(true)
					t.expect(rect.x >= 0 and rect.x + rect.w <= 1280).toBe(true)
					if home == "sidebar" then
						w.adapter.tap(
							toggle,
							{ source = "pointer", pointer = "mouse", x = rect.x + rect.w / 2, y = rect.y + rect.h / 2 }
						)
					else
						navigateTo(w, toggle)
						w.press("ButtonA")
					end
					w.settle(4)
				end
				t.expect(built.report().navigation.placement).toBe("sidebar")
				t.expect(w.adapter.node(page)).toBe(pageNode)
				w.pres.dismiss(w.handle)
				built.dispose()
			end
		end
	end)

	t.it("switches live display previews without remounting the page and retains gamepad routes", function()
		local w, built = make(catalog, { x = 0, y = 0, w = 1280, h = 800 })
		local preview = require("../src/client/environment_preview").new(w.env)
		local pageTab = button(w, "Basics")
		local node = w.adapter.node(pageTab)
		local mounts = built.report().navigation.contentMounts
		for _, row in
			{
				{ "phone", "bottomBar" },
				{ "tablet", "bottomBar" },
				{ "desktop", "topBar" },
				{ "tv", "topBar" },
			}
		do
			preview.setProfile(row[1])
			preview.setInput("gamepad")
			w.settle(4)
			t.expect(built.report().navigation.placement).toBe(row[2])
			t.expect(w.adapter.node(pageTab)).toBe(node)
			t.expect(built.report().navigation.contentMounts).toBe(mounts)
			t.expect(w.pres.focus.focusOn(pageTab)).toBe(true)
			t.expect(w.pres.focus.focused:peek()).toBe(pageTab)
			w.press("DPadRight")
			t.expect(w.pres.focus.focused:peek()).toBe(button(w, "Writing"))
			local firstCategory = button(w, "Inputs")
			t.expect(w.pres.focus.focusOn(firstCategory)).toBe(true)
			t.expect(w.pres.focus.focused:peek()).toBe(firstCategory)
			w.press("DPadRight")
			t.expect(w.pres.focus.focused:peek()).toBe(button(w, "Actions"))
		end
		preview.dispose()
		built.dispose()
		w.pres.dismiss(w.handle)
		w.settle(4)
	end)

	t.it("adapts category navigation while preserving the page and its inner top tabs", function()
		for _, scenario in { catalog, collections, motion } do
			local w, built = make(scenario, { x = 0, y = 0, w = 1280, h = 800 })
			w.env:set("preferredInput", "MouseKeyboard")
			w.settle(4)
			t.expect(built.report().navigation.placement).toBe("sidebar")
			local pageTab = button(w, scenario.groups[1].tabs[1].label)
			local pageNode = w.adapter.node(pageTab)
			local mounts = built.report().navigation.contentMounts
			w.env:set("capabilities", { touch = true, mouse = true, keyboard = true, gamepad = true })
			w.env:set("preferredInput", "Touch")
			w.settle(4)
			t.expect(built.report().navigation.placement).toBe("topBar")
			for _, placement in { "sidebar", "topBar" } do
				built.navigationLayout.toggle()
				w.settle(4)
				t.expect(built.report().navigation.placement).toBe(placement)
			end
			t.expect(built.report().navigation.contentMounts).toBe(mounts)
			t.expect(w.adapter.node(pageTab)).toBe(pageNode)
			for _, input in { "Gamepad", "MouseKeyboard" } do
				w.env:set("viewingDistance", "ten-foot")
				w.env:set("preferredInput", input)
				w.settle(4)
				t.expect(built.report().navigation.placement).toBe("topBar")
				t.expect(built.report().navigation.contentMounts).toBe(mounts)
				t.expect(w.adapter.node(pageTab)).toBe(pageNode)
				navigateTo(w, pageTab)
			end
			w.env:set("viewingDistance", "near")
			w.env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
			w.env:set("preferredInput", "Touch")
			w.env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
			w.settle(4)
			t.expect(built.report().navigation.placement).toBe("bottomBar")
			local category = w.adapter.node(button(w, scenario.groups[1].label)).rect
			local inner = w.adapter.node(pageTab).rect
			t.expect(inner.y < category.y).toBe(true)
			t.expect(built.report().navigation.contentMounts).toBe(mounts)
			w.pres.dismiss(w.handle)
			w.settle(4)
			built.dispose()
			t.expect(w.core.lastError()).toBe(nil)
		end
	end)

	t.it("mounts and navigates every nested control tab, then releases its resources", function()
		for _, scenario in { catalog, collections, motion } do
			for _, viewport in
				{
					{ x = 0, y = 0, w = 1280, h = 800 },
					{ x = 0, y = 0, w = 390, h = 844 },
					{ x = 0, y = 0, w = 844, h = 390 },
				}
			do
				local w, built = make(scenario, viewport)
				for _, group in scenario.groups do
					activate(w, group.label, category)
					for _, tab in group.tabs do
						activate(w, tab.label, inner)
						t.expect(built.report().active).toBe(tab.id)
						if scenario == motion and tab.id == "automatic" then
							t.expect(built.report().example.balance).toBe(100)
							local buy
							for _, path in w.adapter.paths() do
								if path:sub(-4) == "/Buy" then
									buy = path
								end
							end
							t.expect(buy ~= nil and w.pres.focus.focusOn(buy)).toBe(true)
							w.press("ButtonA")
							w.settle(4)
							t.expect(built.report().example.balance).toBe(60)
						end
						w.press("DPadDown")
						w.settle(2)
						local focused = w.pres.focus.focused:peek()
						t.expect(focused ~= nil and w.adapter.node(focused) ~= nil).toBe(true)
						t.expect(w.core.lastError()).toBe(nil)
					end
				end
				w.pres.dismiss(w.handle)
				w.settle(4)
				built.dispose()
				t.expect(w.core.lastError()).toBe(nil)
			end
		end
	end)

	t.it("keeps every selected tab within its nearest scroll host on a 390px phone at Largest text", function()
		local w, built = make(catalog, { x = 0, y = 0, w = 390, h = 844 }, { textOffset = 14 })
		local visited = 0
		for _, group in catalog.groups do
			activate(w, group.label, category)
			for _, tab in group.tabs do
				activate(w, tab.label, inner)
				t.expect(built.report().active).toBe(tab.id)
				local path = inner(w, tab.label)
				local acc, host = "", nil
				for segment in path:gmatch("[^/]+") do
					acc ..= "/" .. segment
					local node = w.adapter.node(acc)
					if node and node.scrollRegion then
						host = acc
					end
				end
				assert(host, group.id .. "/" .. tab.id .. " has no scroll host")
				local rect, window = w.controller.screenRectOf(path), w.controller.screenRectOf(host)
				assert(rect and window, "selected tab screen geometry missing")
				t.expect(
					rect.x >= window.x - 1
						and rect.y >= window.y - 1
						and rect.x + rect.w <= window.x + window.w + 1
						and rect.y + rect.h <= window.y + window.h + 1
				).toBe(true)
				local findings = {}
				for _, finding in w.controller.diagnostics() do
					if finding.designed ~= true and string.sub(finding.node, 1, #host) == host then
						table.insert(findings, finding.issue)
					end
				end
				t.expect(table.concat(findings, " | ")).toBe("")
				visited += 1
			end
		end
		t.expect(visited).toBe(24)
		w.pres.dismiss(w.handle)
		w.settle(4)
		built.dispose()
		t.expect(w.core.lastError()).toBeNil()
	end)

	t.it("the Basics footer stacks its actions at 320x640 Largest rather than cutting them", function()
		local w, built = make(catalog, { x = 0, y = 0, w = 320, h = 640 }, { textOffset = 14 })
		w.settle(4)
		local column, row
		for _, path in w.adapter.paths() do
			if path:match("/AdaptiveScreen/Actions/ActionsColumn$") then
				column = w.controller.screenRectOf(path)
			elseif path:match("/AdaptiveScreen/Actions/ActionsRow$") then
				row = w.controller.screenRectOf(path)
			end
		end
		-- measure and arrange chose the same rung: the column holds the whole box
		t.expect(`row {row.w}x{row.h}`).toBe("row 0x0")
		t.expect(column.w > 0 and column.h > 0).toBe(true)
		for _, finding in w.controller.diagnostics() do
			t.expect(string.find(finding.node, "/Actions/", 1, true)).toBeNil()
		end
		built.dispose()
	end)

	t.it("the phone bottom bar shrinks its category words to fit before it truncates one", function()
		for _, width in { 320, 389 } do
			local w, built = make(catalog, { x = 0, y = 0, w = width, h = 844 }, { preferredInput = "Touch" })
			w.env:set("capabilities", { gamepad = false, keyboard = false, mouse = false, touch = true })
			w.settle(4)
			local seen = {}
			for _, path in w.adapter.paths() do
				local node = w.adapter.node(path)
				if node.class == "Button" and string.find(path, "/Categories/BottomHome/", 1, true) then
					local facts = w.controller.textAt(path) or {}
					table.insert(seen, `{node.props.label}={if facts.truncated then "cut" else "whole"}`)
				end
			end
			table.sort(seen)
			t.expect(`{width}: {table.concat(seen, " ")}`)
				.toBe(`{width}: Actions=whole Inputs=whole Menus=whole Status=whole`)
			built.dispose()
		end
	end)

	t.it("resets both mounted status and identity recipes through their shared commands", function()
		local w, built = make(catalog, { x = 0, y = 0, w = 1280, h = 800 })
		activate(w, "Status", category)
		activate(w, "Status")
		activate(w, "warning")
		activate(w, "Error")
		t.expect(built.report().example.status.status).toBe("warning")
		t.expect(built.report().example.badge.badge.status).toBe("error")
		activate(w, "Reset status")
		t.expect(built.report().example.status.status).toBe("neutral")
		t.expect(built.report().example.badge.badge.status).toBe("neutral")
		activate(w, "Identity")
		activate(w, "Away")
		activate(w, "Fewer")
		t.expect(built.report().example.avatar.portrait.presence).toBe("away")
		t.expect(#built.report().example.group.group.shown + built.report().example.group.group.hidden).toBe(5)
		activate(w, "Reset identity")
		t.expect(built.report().example.avatar.portrait.presence).toBe("online")
		t.expect(#built.report().example.group.group.shown + built.report().example.group.group.hidden).toBe(6)
		activate(w, "Progress")
		activate(w, "Large")
		activate(w, "Loaded")
		t.expect(built.report().example.controlSize).toBe("large")
		t.expect(built.report().example.loading.loading).toBe(false)
		activate(w, "Reset progress")
		t.expect(built.report().example.controlSize).toBeNil()
		t.expect(built.report().example.loading.loading).toBe(true)
		w.settle(4)
		w.pres.dismiss(w.handle)
		w.settle(4)
		t.expect(built.report().active).toBeNil()
		built.dispose()
		t.expect(w.core.lastError()).toBeNil()
	end)

	t.it("keeps virtualized scrolling and measured pane size working inside a tab", function()
		local w, built = make(collections, { x = 0, y = 0, w = 1280, h = 800 })
		activate(w, "Grids")
		activate(w, "Grid")
		local pane, scroll
		for _, path in w.adapter.paths() do
			if path:sub(-9) == "/GridPane" then
				pane = path
			end
			local node = w.adapter.node(path)
			if node.scrollRegion and path:find("/VirtualGrid/", 1, true) then
				scroll = path
			end
		end
		assert(pane and scroll, "grid pane and native scroll host must mount")
		t.expect(built.report().example.viewportExtent).toBe(math.floor(w.adapter.node(pane).rect.h))
		local before = built.report().example.window[1]
		w.adapter.driveScroll(scroll, { x = 0, y = 1800 })
		w.settle(4)
		t.expect(built.report().example.window[1] ~= before).toBe(true)
		t.expect(built.report().example.mounted < 100).toBe(true)
		w.pres.dismiss(w.handle)
		w.settle(4)
		built.dispose()
		t.expect(w.core.lastError()).toBe(nil)
	end)

	t.it("reaches both tab strips and an alert by D-pad, traps focus, then restores its launcher", function()
		local w, built = make(catalog, { x = 0, y = 0, w = 1280, h = 800 })
		for _, label in { "Actions", "Alerts", "Replace checkpoint…" } do
			if label == "Alerts" then
				-- Traverse the actual strip; the broad exploratory walk spends its
				-- budget in the much larger Buttons page before trying this edge.
				navigateTo(w, button(w, "Buttons"))
				for _, destination in { "Shortcuts", "Recipes", "Menus", "Alerts" } do
					w.press("DPadRight")
					t.expect(w.pres.focus.focused:peek()).toBe(button(w, destination))
				end
			else
				navigateTo(w, button(w, label))
			end
			w.press("ButtonA")
			w.settle(4)
		end
		t.expect(built.report().example.alert.presented).toBe(true)
		for _, key in { "DPadRight", "DPadDown", "ButtonR1", "DPadLeft", "DPadUp" } do
			w.press(key)
			w.settle(2)
			t.expect(w.pres.focus.focused:peek():sub(1, 13)).toBe("/ReplaceSave/")
		end
		w.press("ButtonB")
		w.settle(4)
		t.expect(built.report().example.alert.presented).toBe(false)
		t.expect(w.pres.focus.focused:peek()).toBe(button(w, "Replace checkpoint…"))
		t.expect(built.report().selected.Categories).toBe("actions")
		t.expect(built.report().active).toBe("alerts")
		w.pres.dismiss(w.handle)
		w.settle(4)
		built.dispose()
		t.expect(w.core.lastError()).toBe(nil)
	end)

	t.it("routes shoulders to the inner tabs and Back through the nested journey", function()
		local w, built = make(catalog, { x = 0, y = 0, w = 1280, h = 800 })
		activate(w, "Menus", category)
		activate(w, "Journey")
		activate(w, "Plan details")
		t.expect(built.report().example.navigation.depth).toBe(1)
		w.press("ButtonB")
		w.settle(4)
		t.expect(built.report().example.navigation.depth).toBe(0)
		t.expect(w.pres.focus.focused:peek()).toBe(button(w, "Plan details"))
		w.press("ButtonR1")
		w.settle(4)
		t.expect(built.report().selected.Categories).toBe("navigation")
		t.expect(built.report().active).toBe("pages")
		w.pres.dismiss(w.handle)
		w.settle(4)
		built.dispose()
		t.expect(w.core.lastError()).toBe(nil)
	end)
end)
