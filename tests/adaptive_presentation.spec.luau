--!strict
local t = require("./lib/testkit")
local F = require("../src") :: any
local world = require("./lib/world")
local function tabFixture(view, input, distance)
	local w = world.new({
		viewport = { x = 0, y = 0, w = view[1], h = view[2] },
		preferredInput = input,
		env = { viewingDistance = distance or "near" },
	})
	local selection = w.core:signal("garage")
	local builds = 0
	local tabs = F.Controls.TabView(w.core, {
		id = "Tabs",
		style = "sidebarAdaptable",
		selection = selection,
		tabs = {
			{
				id = "garage",
				label = "Garage",
				content = function()
					builds += 1
					return F.UI.Button({ id = "Tune", label = "Tune car" })
				end,
			},
			{
				id = "races",
				label = "Races",
				content = function()
					builds += 1
					return F.UI.Button({ id = "Race", label = "Start race" })
				end,
			},
		},
	})
	w.present(F.UI.Screen({ id = "S", children = { tabs.blueprint } }))
	w.settle(2)
	return w, tabs, selection, function()
		return builds
	end
end

t.describe("shared adaptive presentation", function()
	t.it("viewing distance resets the navigation home and keeps TV tabs visible with a mouse", function()
		local w, tabs, selection = tabFixture({ 1280, 800 }, "KeyboardAndMouse")
		tabs.expandSidebar()
		w.settle(3)
		local content = w.controller.rectOf("/S/Tabs/Content")
		local rail
		for _, path in w.adapter.paths() do
			if path:match("/NavigationHome$") then
				rail = w.controller.rectOf(path)
			end
		end
		t.expect(content.x > rail.x + rail.w).toBe(true)
		w.env:set("viewingDistance", "ten-foot")
		w.settle(4)
		t.expect(tabs.placement:get()).toBe("topBar")
		local target
		for _, path in w.adapter.paths() do
			if path:match("/ToggleSidebar$") then
				local r = w.controller.rectOf(path)
				t.expect(r == nil or r.w == 0 or r.h == 0).toBe(true)
			end
			if path:match("/Opt2$") then
				target = path
			end
		end
		t.expect(target ~= nil).toBe(true)
		t.expect(w.controller.rectOf(target).w > 0).toBe(true)
		w.adapter.tap(target)
		w.settle(4)
		t.expect(selection:get()).toBe("races")
		t.expect(tabs.placement:get()).toBe("topBar")
		t.expect(w.controller.rectOf(target).w > 0).toBe(true)
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)

	t.it("expanding ordinary adaptable tabs focuses the selected tab after relocation", function()
		local w, tabs = tabFixture({ 1000, 800 }, "Touch")
		w.pres.focus.focusOn("/S/Tabs/Content/Tab-garage/then/Tune")
		tabs.expandSidebar()
		w.settle(3)
		t.expect(string.match(w.pres.focus.focused:get(), "/Opt1$") ~= nil).toBe(true)
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
	t.it("a resize cancels an obsolete sidebar focus handoff while duplicate requests retain it", function()
		for _, collapse in { false, true } do
			local w, tabs = tabFixture({ 1000, 800 }, "Touch")
			local path = "/S/Tabs/Content/Tab-garage/then/Tune"
			w.pres.focus.focusOn(path)
			tabs.expandSidebar()
			w.env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
			if collapse then
				tabs.collapseSidebar()
			end
			w.settle(3)
			t.expect(w.pres.focus.focused:get()).toBe(path)
			w.pres.dismiss(w.handle)
			tabs.dispose()
		end
		local w, tabs = tabFixture({ 1000, 800 }, "Touch")
		tabs.expandSidebar()
		tabs.expandSidebar()
		w.settle(3)
		t.expect(string.find(w.pres.focus.focused:get(), "/RailHome/", 1, true) ~= nil).toBe(true)
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
	t.it("sidebar commands preserve focus when compact navigation cannot relocate", function()
		local w, tabs = tabFixture({ 390, 844 }, "Gamepad")
		local path = "/S/Tabs/Content/Tab-garage/then/Tune"
		w.pres.focus.focusOn(path)
		tabs.expandSidebar()
		w.settle(3)
		t.expect(tabs.placement:get()).toBe("bottomBar")
		t.expect(w.pres.focus.focused:get()).toBe(path)
		tabs.collapseSidebar()
		w.settle(3)
		t.expect(w.pres.focus.focused:get()).toBe(path)
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
	t.it("image buttons consume focus changes without polling focus on unchanged geometry", function()
		local w = world.new()
		local button = F.Controls.Button(
			w.core,
			{ id = "Card", label = "Car", image = "rbxassetid://0", onActivate = function() end }
		)
		w.present(F.UI.Screen({ id = "S", children = { button.blueprint } }))
		w.settle(2)
		local node = w.handle.root.node.children[1]
		local bundle = require("../src/input/contribution").read(node)
		local signal = w.pres.focus.focused
		local get = signal.get
		local reads = 0
		signal.get = function(self)
			reads += 1
			return get(self)
		end
		for _ = 1, 20 do
			bundle.syncGeometry(w.controller.rectOf, node)
		end
		signal.get = get
		t.expect(reads).toBe(0)
		w.pres.dismiss(w.handle)
		button.dispose()
	end)
	t.it("lets a tablet toggle the same tabs without rebuilding its selected page", function()
		local w, tabs, selection, builds = tabFixture({ 1000, 800 }, "Touch")
		t.expect(tabs.placement:get()).toBe("topBar")
		tabs.expandSidebar()
		w.settle(2)
		t.expect(tabs.placement:get()).toBe("sidebar")
		tabs.collapseSidebar()
		w.settle(2)
		t.expect(tabs.placement:get()).toBe("topBar")
		t.expect(builds()).toBe(1)
		t.expect(selection:get()).toBe("garage")
		tabs.expandSidebar()
		w.env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		w.settle(2)
		t.expect(tabs.placement:get()).toBe("bottomBar")
		w.env:set("viewportRect", { x = 0, y = 0, w = 1000, h = 800 })
		w.settle(2)
		t.expect(tabs.placement:get()).toBe("sidebar")
	end)
	t.it("keeps explicitly expanded distant navigation stable on tab activation", function()
		local w, tabs, selection, builds = tabFixture({ 1920, 1080 }, "Gamepad", "ten-foot")
		t.expect(tabs.placement:get()).toBe("topBar")
		tabs.expandSidebar()
		w.settle(2)
		t.expect(tabs.placement:get()).toBe("sidebar")
		local target
		for _, p in w.adapter.paths() do
			if p:match("/Opt2$") then
				target = p
			end
		end
		t.expect(target ~= nil).toBe(true)
		w.pres.focus.focusOn(target)
		w.press("ButtonA")
		w.settle(3)
		t.expect(selection:get()).toBe("races")
		t.expect(tabs.placement:get()).toBe("sidebar")
		t.expect(builds()).toBe(2)
		t.expect(w.pres.focus.focused:get()).toBe(target)
		t.expect(w.core:lastError()).toBeNil()
	end)
	t.it("defaults to persistent navigation with mouse and offers a visible toggle", function()
		local w, tabs = tabFixture({ 1200, 800 }, "KeyboardAndMouse")
		t.expect(tabs.placement:get()).toBe("sidebar")
		local found = false
		for _, p in w.adapter.paths() do
			if p:match("/ToggleSidebar$") then
				found = true
			end
		end
		t.expect(found).toBe(true)
		tabs.collapseSidebar()
		w.settle(2)
		t.expect(tabs.placement:get()).toBe("topBar")
	end)
	t.it("image buttons keep one focus target and never reflow their caption on focus", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 800 }, preferredInput = "Gamepad", ops = true })
		local calls = 0
		local b = F.Controls.Button(w.core, {
			id = "Card",
			label = "Mountain circuit",
			subtitle = "Time trial",
			image = "rbxassetid://0",
			width = { type = "fixed", px = 240 },
			onActivate = function()
				calls += 1
			end,
		})
		w.present(F.UI.Screen({ id = "S", children = { b.blueprint } }))
		w.settle(2)
		local imagePath = "/S/Card/ImageContent/ImageEnvelope/Artwork"
		local labelPath = "/S/Card/ImageContent/Caption/Label"
		local before = table.clone(w.adapter.node(labelPath).rect)
		w.pres.focus.focusOn("/S/Card")
		w.settle(2)
		t.expect(w.adapter.node(imagePath).props.transform.scale > 1).toBe(true)
		t.expect(w.adapter.node(labelPath).rect.y).toBe(before.y)
		w.press("ButtonA")
		t.expect(calls).toBe(1)
		w.env:set("reducedMotion", true)
		w.settle(2)
		t.expect(w.adapter.node(imagePath).props.transform.scale).toBe(1)
		t.expect(w.adapter.node(imagePath).props.stroke ~= nil).toBe(true)
		w.env:set("preferredInput", "Touch")
		w.settle(2)
		w.adapter.hover("/S/Card")
		w.settle(2)
		t.expect(w.adapter.node(imagePath).props.transform.scale).toBe(1)
	end)

	t.it("image focus lift is continuous on interruption and stays settled", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 1920, h = 1080 },
			preferredInput = "Gamepad",
			env = { viewingDistance = "ten-foot" },
			ops = true,
		})
		local b = F.Controls.Button(w.core, {
			id = "Card",
			label = "Circuit",
			image = "rbxassetid://0",
			width = { type = "fixed", px = 320 },
			onActivate = function() end,
		})
		w.present(F.UI.Screen({ id = "S", children = { b.blueprint, F.UI.Button({ id = "Other", label = "Other" }) } }))
		w.pres.focus.focusOn("/S/Other")
		w.settle(60)
		t.expect(#w.controller.diagnostics()).toBe(0)
		local function scale()
			return w.adapter.node("/S/Card/ImageContent/ImageEnvelope/Artwork").props.transform.scale
		end
		w.pres.focus.focusOn("/S/Card")
		w.pres.refresh()
		t.expect(scale()).toBe(1)
		w.settle(1)
		t.expect(scale() > 1 and scale() < 1.05).toBe(true)
		local mid = scale()
		w.pres.focus.focusOn("/S/Other")
		w.pres.refresh()
		t.expect(scale()).toBe(mid)
		w.settle(60)
		t.expect(scale()).toBe(1)
		w.pres.focus.focusOn("/S/Card")
		w.settle(60)
		t.expect(scale()).toBe(1.05)
		local solved = w.controller.stats().solves
		w.settle(60)
		t.expect(scale()).toBe(1.05)
		t.expect(w.controller.stats().solves).toBe(solved)
		w.env:set("reducedMotion", true)
		w.pres.refresh()
		t.expect(scale()).toBe(1)
		b.dispose()
	end)

	t.it("uses a single panel for gamepad menu hierarchies and keeps mouse cascades", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1280, h = 720 }, preferredInput = "Gamepad" })
		local menu = F.Controls.Menu(w.core, {
			id = "M",
			trigger = F.UI.Button({ id = "Open", label = "Gear" }),
			items = {
				{
					id = "tools",
					label = "Tools",
					children = {
						{ id = "wrench", label = "Wrench", onSelect = function() end },
					},
				},
			},
		})
		t.expect(menu.dump().presentation).toBe("sheet")
		w.env:set("preferredInput", "KeyboardAndMouse")
		t.expect(menu.dump().presentation).toBe("menu")
		menu.dispose()
	end)

	for themeName, themeModule in
		{
			["Pixel Quest"] = require("../examples/themes/pixel_quest"),
			["Fantasy Ornate"] = require("../examples/themes/fantasy_ornate"),
		}
	do
		for _, view in
			{
				{ 390, 844, "Touch" },
				{ 1000, 800, "KeyboardAndMouse" },
				{ 1280, 720, "Gamepad" },
				{ 1920, 1080, "Gamepad" },
			}
		do
			t.it(`keeps image focus and captions clear in {themeName} at {view[1]} px`, function()
				local pkg = themeModule.build(F.themes)
				local metrics = F.themes.resolve(pkg, nil, {})
				local w = world.new({
					viewport = { x = 0, y = 0, w = view[1], h = view[2] },
					preferredInput = view[3],
					themeMetrics = metrics,
					env = { preferredTextOffset = 14, viewingDistance = if view[1] == 1920 then "ten-foot" else "near" },
				})
				local b = F.Controls.Button(w.core, {
					id = "Card",
					label = "A remarkably adventurous driver",
					subtitle = "Choose a racer for mountain trails",
					imageFraming = { width = 420, height = 420, focusY = 0.25 },
					image = "rbxassetid://0",
					onActivate = function() end,
				})
				w.present(F.UI.Screen({
					id = "S",
					padding = "m",
					children = {
						F.UI.ScrollView({
							id = "Scroll",
							width = F.UI.fill(),
							height = F.UI.fill(),
							children = {
								b.blueprint,
							},
						}),
					},
				}))
				w.settle(2)
				local root = "/S/Scroll/Card"
				local before = w.controller.stats().solves
				w.pres.focus.focusOn(root)
				w.settle(2)
				local art = w.adapter.node(root .. "/ImageContent/ImageEnvelope/Artwork")
				local envelope = w.adapter.node(root .. "/ImageContent/ImageEnvelope").rect
				local label = w.adapter.node(root .. "/ImageContent/Caption/Label").rect
				local scale = art.props.transform.scale
				t.expect(art.rect.y + art.rect.h / 2 + art.rect.h * scale / 2 <= envelope.y + envelope.h + 0.1)
					.toBe(true)
				t.expect(envelope.y + envelope.h <= label.y + 0.1).toBe(true)
				t.expect(w.controller.stats().solves).toBe(before)
				w.pres.dismiss(w.handle)
				b.dispose()
			end)
		end
	end

	t.it("ornate sidebar badges reserve space beside their labels", function()
		local pkg = require("../examples/themes/fantasy_ornate").build(F.themes)
		local w = world.new({
			viewport = { x = 0, y = 0, w = 1920, h = 1080 },
			preferredInput = "Gamepad",
			themeMetrics = F.themes.resolve(pkg, nil, {}),
			env = { viewingDistance = "ten-foot", preferredTextOffset = 14 },
		})
		local selected = w.core:signal("pages")
		local tabs = F.Controls.TabView(w.core, {
			id = "Tabs",
			style = "sidebarAdaptable",
			selection = selected,
			tabs = {
				{
					id = "pages",
					label = "Pages",
					content = function()
						return F.UI.Text({ text = "Pages" })
					end,
				},
				{
					id = "inbox",
					label = "Inbox",
					badge = "3",
					content = function()
						return F.UI.Text({ text = "Inbox" })
					end,
				},
			},
		})
		w.present(F.UI.Screen({ id = "S", children = { tabs.blueprint } }))
		tabs.expandSidebar()
		w.settle(60)
		local label, badge
		for _, path in w.adapter.paths() do
			if path:find("Opt2Cell", 1, true) then
				if path:match("/Label$") then
					label = w.adapter.node(path).rect
				end
				if path:match("/Badge$") and w.adapter.node(path).class == "Text" then
					badge = w.adapter.node(path).rect
				end
			end
		end
		t.expect(label ~= nil and badge ~= nil).toBe(true)
		t.expect(label.x + label.w <= badge.x).toBe(true)
		t.expect(#w.controller.diagnostics()).toBe(0)
	end)

	t.it("sidebar round trips retain no branch subscriptions or page rebuilds", function()
		local w, tabs, _, builds = tabFixture({ 1000, 800 }, "Touch")
		tabs.expandSidebar()
		w.settle(2)
		tabs.collapseSidebar()
		w.settle(2)
		local before = w.core:counters()
		for _ = 1, 12 do
			tabs.expandSidebar()
			w.settle(2)
			tabs.collapseSidebar()
			w.settle(2)
		end
		local after = w.core:counters()
		for key, value in before do
			if key == "signals" or key == "memos" or key == "effects" or key == "observers" or key == "scopes" then
				t.expect(after[key]).toBe(value)
			end
		end
		t.expect(builds()).toBe(1)
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
	t.it("coordinates mouse hover, input changes and disabled image feedback", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 800 }, preferredInput = "KeyboardAndMouse" })
		local enabled = w.core:signal(true)
		local b = F.Controls.Button(w.core, {
			id = "Card",
			label = "Driver",
			image = "rbxassetid://0",
			width = { type = "fixed", px = 200 },
			enabled = enabled,
			onActivate = function() end,
		})
		w.present(F.UI.Screen({ id = "S", children = { b.blueprint } }))
		w.settle(60)
		local path = "/S/Card/ImageContent/ImageEnvelope/Artwork"
		w.pres.focus.setFocusOrigin("pointer")
		w.adapter.hover("/S/Card")
		w.settle(60)
		t.expect(w.adapter.node(path).props.transform.scale).toBe(1.05)
		w.adapter.unhover("/S/Card")
		w.settle(60)
		t.expect(w.adapter.node(path).props.transform.scale).toBe(1)
		w.adapter.hover("/S/Card")
		enabled:set(false)
		w.settle(60)
		t.expect(w.adapter.node(path).props.stroke).toBeNil()
		enabled:set(true)
		w.env:set("preferredInput", "Touch")
		w.settle(60)
		t.expect(w.adapter.node(path).props.transform.scale).toBe(1)
		w.pres.dismiss(w.handle)
		b.dispose()
		enabled:dispose()
	end)
	t.it("distance changes release collapsed-caption observers", function()
		local w, tabs = tabFixture({ 1000, 800 }, "Touch")
		local before = w.core:counters().memos
		for _ = 1, 8 do
			w.env:set("viewingDistance", "ten-foot")
			w.settle(2)
			w.env:set("viewingDistance", "near")
			w.settle(2)
		end
		t.expect(w.core:counters().memos).toBe(before)
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
	t.it("Back collapses only sidebar navigation and leaves page Back unclaimed", function()
		local w, tabs = tabFixture({ 1920, 1080 }, "Gamepad", "ten-foot")
		tabs.expandSidebar()
		w.settle(2)
		t.expect(string.find(w.pres.focus.focused:get() or "", "/RailHome/", 1, true) ~= nil).toBe(true)
		w.press("ButtonB")
		w.settle(2)
		t.expect(tabs.placement:get()).toBe("topBar")
		local bundle = require("../src/input/contribution").read(tabs.blueprint)
		t.expect(bundle.handleCancel(w.pres.focus.focused:get())).toBe(false)
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
	t.it("reconnects image hover after the same control is remounted", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 800 }, preferredInput = "KeyboardAndMouse" })
		local shown = w.core:signal(true)
		local b = F.Controls.Button(
			w.core,
			{ id = "Card", label = "Driver", image = "rbxassetid://0", onActivate = function() end }
		)
		w.present(
			F.UI.Screen({
				id = "S",
				children = {
					F.UI.When({
						id = "Show",
						condition = shown,
						thenView = function()
							return b.blueprint
						end,
					}),
				},
			}),
			{ recycleInstances = false }
		)
		w.settle(2)
		shown:set(false)
		w.settle(60)
		t.expect(w.adapter.node("/S/Show/then/Card")).toBeNil()
		shown:set(true)
		w.settle(2)
		w.pres.focus.setFocusOrigin("pointer")
		w.adapter.hover("/S/Show/then/Card")
		w.settle(60)
		t.expect(w.adapter.node("/S/Show/then/Card/ImageContent/ImageEnvelope/Artwork").props.transform.scale)
			.toBe(1.05)
		w.pres.dismiss(w.handle)
		b.dispose()
		shown:dispose()
	end)
	t.it("dismissing a screen after evicting image buttons releases callbacks safely", function()
		local w = world.new()
		local shown = w.core:signal(true)
		w.present(F.UI.Screen({
			id = "S",
			children = {
				F.UI.When({
					id = "Show",
					condition = shown,
					thenView = function(pageScope)
						local b = pageScope:own(
							F.Controls.Button(
								w.core,
								{ id = "Card", label = "Driver", image = "rbxassetid://0", onActivate = function() end }
							)
						)
						return b.blueprint
					end,
				}),
			},
		}))
		w.settle(2)
		shown:set(false)
		w.settle(60)
		t.expect(w.adapter.node("/S/Show/then/Card")).toBeNil()
		w.pres.dismiss(w.handle)
		t.expect(w.core:lastError()).toBeNil()
		shown:dispose()
	end)
	t.it("includes image hover observers in the adapter handler census", function()
		local function count(image)
			local w = world.new({ preferredInput = "KeyboardAndMouse" })
			local b =
				F.Controls.Button(w.core, { id = "B", label = "Driver", image = image, onActivate = function() end })
			w.present(F.UI.Screen({ children = { b.blueprint } }))
			w.settle(2)
			local n = w.adapter.handlerCount()
			w.pres.dismiss(w.handle)
			b.dispose()
			t.expect(w.adapter.handlerCount()).toBe(0)
			return n
		end
		t.expect(count("rbxassetid://0") - count(nil)).toBe(1)
	end)
end)

t.describe("persistent adaptive navigation", function()
	t.it("keeps tab controls and the scroller mounted across top/sidebar round trips", function()
		local w, tabs = tabFixture({ 1000, 800 }, "Touch")
		local path
		local function find(n)
			if n.id == "StripScroll" then
				path = n.path
			end
			for _, child in n.children or {} do
				find(child)
			end
		end
		find(w.handle.root.node)
		local host = w.adapter.node(path)
		local creates = w.controller.stats().creates
		for _ = 1, 4 do
			tabs.expandSidebar()
			w.settle(3)
			t.expect(w.adapter.node(path)).toBe(host)
			tabs.collapseSidebar()
			w.settle(3)
			t.expect(w.adapter.node(path)).toBe(host)
		end
		t.expect(w.controller.stats().creates).toBe(creates)
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
	t.it("centers the top capsule beside a tall accessory and anchors rail accessories", function()
		local UI = F.UI
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 600 } })
		local tabs = F.Controls.TabView(w.core, {
			id = "Tabs",
			selection = w.core:signal("a"),
			conditions = { navPlacement = w.core:signal("topBar") },
			style = "sidebarAdaptable",
			accessories = {
				trailing = function()
					return UI.Box({
						id = "Trailing",
						width = { type = "fixed", px = 80 },
						height = {
							type = "fixed",
							px = 120,
						},
					})
				end,
				head = function()
					return UI.Box({ id = "Head", height = { type = "fixed", px = 80 } })
				end,
				foot = function()
					return UI.Box({ id = "Foot", height = { type = "fixed", px = 100 } })
				end,
			},
			tabs = {
				{
					id = "a",
					label = "A",
					content = function()
						return UI.Text({ text = "A" })
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
		local function rects()
			local out = {}
			local function walk(n)
				if
					n.id == "AdaptableBar"
					or n.id == "Trailing"
					or n.id == "Head"
					or n.id == "Foot"
					or n.id == "NavigationHome"
				then
					out[n.id] = w.controller.rectOf(n.path)
				end
				for _, child in n.children or {} do
					walk(child)
				end
			end
			walk(w.handle.root.node)
			return out
		end
		for _ = 1, 2 do
			local r = rects()
			t.expect(math.abs(r.AdaptableBar.y + r.AdaptableBar.h / 2 - r.Trailing.y - r.Trailing.h / 2) < 0.001)
				.toBe(true)
			t.expect(r.AdaptableBar.x + r.AdaptableBar.w <= r.Trailing.x).toBe(true)
			tabs.expandSidebar()
			w.settle(3)
			r = rects()
			t.expect(r.Head.y).toBe(r.NavigationHome.y)
			t.expect(r.Foot.y + r.Foot.h).toBe(r.NavigationHome.y + r.NavigationHome.h)
			tabs.collapseSidebar()
			w.settle(3)
		end
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
end)
