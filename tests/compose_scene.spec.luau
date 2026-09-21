--!strict
local coreLib = require("../src/core/services")
local presenterLib = require("../src/present/presenter")
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local scene = require("../src/render/compose_scene")
local Facet = require("../src")
local fake = require("./lib/fake_target")

t.describe("Compose UI domain host", function()
	for _, width in { 320, 1280 } do
		for _, offset in { 220, 660, 1320 } do
			t.it(`restores a measured feed at {offset}px in a {width}px viewport`, function()
				local app, adapter, settle = require("./lib/native_world")({ x = 0, y = 0, w = width, h = 900 })
				local rows = {}
				for index = 1, 24 do
					table.insert(rows, { id = index, text = `Message {index}: retained conversation history.` })
				end
				local items, position = Compose.cell(rows), Compose.cell(0)
				local function Feed()
					return app.controls.Screen("S")({
						app.controls.VirtualList("Feed")({
							rows = items,
							key = "id",
							itemExtent = "measured",
							estimatedItemExtent = 100,
							viewportExtent = 573,
							rowGap = "m",
							overscan = 2,
							scrollNavigation = { position = position },
							cell = function(_, ctx)
								local item = Compose.formula(ctx.current)
								return app.controls.VStack({
									width = { type = "fill" },
									padding = "m",
									gap = "s",
									app.controls.Text({ text = "Assistant", textSize = "label" }),
									app.controls.Text({
										text = function(use)
											return use(item).text
										end,
										textSize = "body",
									}),
								})
							end,
						}),
					})
				end
				local close = app.mount(Feed)
				settle(3)
				adapter.driveScroll("/S/Feed", { x = 0, y = offset })
				settle(3)
				local saved = position:peek()
				-- Initial scrolling can anchor-correct newly measured rows. Remount must
				-- preserve the resulting visible position, including that correction.
				t.expect(saved > 0).toBe(true)
				if offset == 660 then
					t.expect(saved).toBe(660)
				end
				close()
				app.mount(Feed)
				settle(3)
				t.expect(adapter.scrollPositionOf("/S/Feed").y).toBe(saved)
				app.dispose()
			end)
		end
	end

	t.it("native disclosure uses Compose state and releases each collapsed branch", function()
		local app, adapter, settle = require("./lib/native_world")({ x = 0, y = 0, w = 480, h = 400 })
		local expanded = Compose.cell(false)
		local built, released = 0, 0
		app.mount(function()
			return app.controls.Screen("S")({
				app.controls.DisclosureGroup("Details")({
					label = "Appearance",
					expanded = expanded,
					content = function()
						built += 1
						Compose.cleanup(function()
							released += 1
						end)
						return app.controls.Button({ label = "Choose", onActivate = function() end })
					end,
				}),
			})
		end)
		settle(3)
		for index = 1, 3 do
			adapter.driveActivate("/S/Details/Header")
			settle(3)
			t.expect(expanded:peek()).toBe(true)
			t.expect(built).toBe(index)
			adapter.driveActivate("/S/Details/Header")
			settle(3)
			t.expect(expanded:peek()).toBe(false)
			t.expect(released).toBe(index)
		end
		app.dispose()
		t.expect(adapter.rootCount()).toBe(0)
	end)
	t.it("noninteractive native feeds window rows and add only each row's own focus hit", function()
		local app, adapter, settle = require("./lib/native_world")({ x = 0, y = 0, w = 480, h = 400 })
		local items = {}
		for index = 1, 1000 do
			table.insert(items, { id = index, text = "Message " .. index })
		end
		local alive = 0
		local _, root = app.mount(function()
			return app.controls.Screen("S")({
				app.controls.VirtualList("Feed")({
					rows = Compose.cell(items),
					key = "id",
					itemExtent = 60,
					viewportExtent = 240,
					cell = function(_, ctx)
						local item = Compose.formula(ctx.current)
						alive += 1
						Compose.cleanup(function()
							alive -= 1
						end)
						return app.controls.Text({
							text = function(use)
								return use(item).text
							end,
						})
					end,
				}),
			})
		end)
		settle(3)
		t.expect(alive > 0 and alive < 12).toBe(true)
		local function inspect(node)
			-- A row stays keyboard reachable through the list's one `Hit`; the feed
			-- adds no other button.
			t.expect(node.class == "Button" and node.id ~= "Hit").toBe(false)
			for _, child in node.children do
				inspect(child)
			end
		end
		inspect(root)
		adapter.driveScroll("/S/Feed", { x = 0, y = 12000 })
		settle(3)
		t.expect(alive > 0 and alive < 12).toBe(true)
		app.dispose()
		t.expect(alive).toBe(0)
	end)
	for _, style in { "automatic", "sidebarAdaptable" } do
		t.it(`native {style} tabs preserve page ownership across placement changes`, function()
			local adapter, tick = fake.new(), nil
			local app = Facet.new({
				newInputSystem = function(core)
					return Facet.newActionSystem(core)
				end,
				bindEnv = function(env)
					env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
					return function() end
				end,
				newAdapter = function()
					return adapter
				end,
				connectFrame = function(fn)
					tick = fn
					return function() end
				end,
			})
			local UI, selected = app.controls, Compose.cell("games")
			local placement = Compose.cell("topBar")
			local mounted, released = {}, {}
			local function page(id)
				return function()
					mounted[id] = (mounted[id] or 0) + 1
					Compose.cleanup(function()
						released[id] = (released[id] or 0) + 1
					end)
					return UI.Text("Page")({ text = id })
				end
			end
			app.mount(function()
				return UI.Screen("Main")({
					UI.TabView("Tabs")({
						selection = selected,
						style = style,
						conditions = { navPlacement = placement },
						tabs = {
							{ id = "games", label = "Games", content = page("games") },
							{ id = "avatar", label = "Avatar", content = page("avatar") },
						},
					}),
				})
			end)
			tick(1 / 60)
			t.expect(mounted.games).toBe(1)
			t.expect(mounted.avatar).toBeNil()
			for _, home in { "sidebar", "bottomBar", "topBar" } do
				placement:set(home)
				tick(1 / 60)
				t.expect(mounted.games).toBe(1)
				t.expect(released.games).toBeNil()
				local button
				for _, path in adapter.paths() do
					local node = adapter.node(path)
					if node.class == "Button" and node.props.label == "Avatar" then
						button = path
					end
				end
				assert(button, "tab strip missing after placement " .. home)
				if home == "topBar" then
					adapter.driveActivate(button)
					t.expect(selected:peek()).toBe("avatar")
				end
			end
			selected:set("avatar")
			tick(1 / 60)
			t.expect(released.games).toBe(1)
			t.expect(mounted.avatar).toBe(1)
			t.expect(adapter.node("/Main/Tabs/Content/Tab-avatar/Page").props.text).toBe("avatar")
			selected:set("games")
			tick(1 / 60)
			t.expect(released.avatar).toBe(1)
			t.expect(mounted.games).toBe(2)
			app.dispose()
			t.expect(released.games).toBe(2)
			t.expect(adapter.rootCount()).toBe(0)
		end)
	end

	t.it("native collapsible images can disappear and remount without reusing retired nodes", function()
		local app, adapter, settle = require("./lib/native_world")({ x = 0, y = 0, w = 800, h = 600 })
		local image = Compose.cell("")
		app.mount(function()
			return app.controls.Screen("S")({
				app.controls.CollapsibleView("Details")({
					label = "Details",
					expanded = Compose.cell(false),
					image = image,
					content = function()
						return app.controls.Text({ text = "Details" })
					end,
				}),
			})
		end)
		local function countImages()
			local count = 0
			for _, path in adapter.paths() do
				if path:sub(-6) == "/Image" then
					count += 1
				end
			end
			return count
		end
		settle(3)
		t.expect(countImages()).toBe(0)
		for _ = 1, 3 do
			image:set("rbxassetid://1")
			settle(3)
			t.expect(countImages()).toBe(1)
			image:set("")
			settle(3)
			t.expect(countImages()).toBe(0)
		end
		app.dispose()
		t.expect(adapter.rootCount()).toBe(0)
	end)
	t.it("native collapsible content opens repeatedly with fresh Compose ownership", function()
		local adapter, tick, now = fake.new(), nil, 0
		local app = Facet.new({
			now = function()
				return now
			end,
			newInputSystem = function(core)
				return Facet.newActionSystem(core)
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
				return function() end
			end,
			newAdapter = function()
				return adapter
			end,
			connectFrame = function(fn)
				tick = fn
				return function() end
			end,
		})
		local UI, expanded = app.controls, Compose.cell(false)
		local built, released = 0, 0
		app.mount(function()
			return UI.Screen("Main")({
				UI.CollapsibleView("Navigation")({
					label = Compose.cell("Navigation"),
					expanded = expanded,
					content = function()
						built += 1
						Compose.cleanup(function()
							released += 1
						end)
						return UI.Button("Close")({
							label = "Close",
							onActivate = function()
								expanded:set(false)
							end,
						})
					end,
				}),
			})
		end)
		now += 1 / 60
		tick(1 / 60)
		for i = 1, 3 do
			adapter.driveActivate("/Main/Navigation")
			for _ = 1, 60 do
				now += 1 / 60
				tick(1 / 60)
			end
			t.expect(expanded:peek()).toBe(true)
			t.expect(built).toBe(i)
			local close
			for _, path in adapter.paths() do
				if path:sub(-6) == "/Close" then
					close = path
				end
			end
			adapter.driveActivate(assert(close, table.concat(adapter.paths(), "\n")))
			for _ = 1, 60 do
				now += 1 / 60
				tick(1 / 60)
			end
			t.expect(expanded:peek()).toBe(false)
			t.expect(released).toBe(i)
		end
		app.dispose()
		t.expect(adapter.rootCount()).toBe(0)
	end)

	t.it("retires native tab accessories through Compose ownership across placement changes", function()
		local app, adapter, advance, core = require("./lib/native_motion_world")()
		local UI = app.controls
		local placement = Compose.cell("sidebar")
		local selected = Compose.cell("home")
		local live = {}
		local built, released = 0, 0
		local function accessory(home, owner)
			t.expect(owner).toBe(Compose.currentOwner())
			built += 1
			live[home] = (live[home] or 0) + 1
			owner.own(function()
				released += 1
				live[home] -= 1
			end)
			return UI.Text({ text = home })
		end
		local baseline = core.owner.size()
		local close = app.mount(function()
			return UI.TabView("Tabs")({
				style = "sidebarAdaptable",
				conditions = { navPlacement = placement },
				selection = selected,
				accessories = { head = accessory, trailing = accessory, aboveBar = accessory },
				tabs = {
					{
						id = "home",
						label = "Home",
						content = function(owner)
							t.expect(owner).toBe(Compose.currentOwner())
							return UI.Text({ text = "Home" })
						end,
					},
				},
			})
		end)
		for _, home in { "sidebar", "topBar", "bottomBar", "bottomBarCompact", "sidebar" } do
			placement:set(home)
			advance(0.1)
			t.expect(live[home]).toBe(1)
			for other, count in live do
				if other ~= home then
					t.expect(count).toBe(0)
				end
			end
		end
		close()
		advance(0.1)
		t.expect(released).toBe(built)
		t.expect(core.owner.size()).toBe(baseline)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)

	t.it("native collapsed tabs reopen and select through their popup", function()
		local adapter, tick, now = fake.new(), nil, 0
		local app = Facet.new({
			now = function()
				return now
			end,
			newInputSystem = function(core)
				return Facet.newActionSystem(core)
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
				return function() end
			end,
			newAdapter = function()
				return adapter
			end,
			connectFrame = function(fn)
				tick = fn
				return function() end
			end,
		})
		local UI, selected = app.controls, Compose.cell("games")
		app.mount(function()
			return UI.Screen("Main")({
				UI.TabView("Tabs")({
					style = "collapsible",
					selection = selected,
					tabs = {
						{
							id = "games",
							label = "Games",
							content = function()
								return UI.Text({ text = "Games" })
							end,
						},
						{
							id = "avatar",
							label = "Avatar",
							content = function()
								return UI.Text({ text = "Avatar" })
							end,
						},
					},
				}),
			})
		end)
		now += 1 / 60
		tick(1 / 60)
		for _, destination in { "avatar", "games", "avatar" } do
			local trigger
			for _, path in adapter.paths() do
				if path:sub(-11) == "/Navigation" then
					trigger = path
				end
			end
			adapter.driveActivate(assert(trigger))
			for _ = 1, 60 do
				now += 1 / 60
				tick(1 / 60)
			end
			local button
			for _, path in adapter.paths() do
				local node = adapter.node(path)
				if
					node.props.label == (if destination == "avatar" then "Avatar" else "Games")
					and node.class == "Button"
				then
					button = path
				end
			end
			adapter.driveActivate(assert(button, table.concat(adapter.paths(), "\n")))
			for _ = 1, 60 do
				now += 1 / 60
				tick(1 / 60)
			end
			t.expect(selected:peek()).toBe(destination)
		end
		app.dispose()
		t.expect(adapter.rootCount()).toBe(0)
	end)

	t.it("native Stage content follows Compose lifetime without path polling", function()
		local adapter, tick = fake.new(), nil
		local app = Facet.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core)
				return Facet.newActionSystem(core)
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
				return function() end
			end,
			connectFrame = function(fn)
				tick = fn
				return function() end
			end,
		})
		local originalMetrics = app.environment:get("themeMetrics"):peek()
		local package = require("../examples/virtual_monitors/theme").create(Facet, "Avatar")
		local controller = app.installTheme(package, { forceFallback = true })
		controller.swap("Light")
		t.expect(controller.current()).toBe("Light")
		local UI, visible, size = app.controls, Compose.cell(true), Compose.cell(200)
		local builds, released, watched = 0, 0, 0
		app.mount(function()
			return UI.Screen("Main")({
				Compose.show(visible, function()
					return UI.Stage("Preview")({
						width = { type = "fixed", px = 240 },
						height = { type = "fixed", px = 240 },
						content = function(host)
							builds += 1
							host.setCamera({ position = { x = 0, y = 3, z = 8 }, lookAt = { x = 0, y = 1, z = 0 } })
							assert(host.contentRoot())
							Compose.watch(function(use)
								watched = use(size)
							end)
							return function()
								released += 1
							end
						end,
					})
				end),
			})
		end)
		tick(1 / 60)
		t.expect(builds).toBe(1)
		size:set(250)
		t.expect(watched).toBe(250)
		visible:set(false)
		tick(1 / 60)
		t.expect(released).toBe(1)
		size:set(300)
		t.expect(watched).toBe(250)
		visible:set(true)
		tick(1 / 60)
		t.expect(builds).toBe(2)
		t.expect(watched).toBe(300)
		local failedRead = 0
		local ok = pcall(app.presentModal, function()
			return UI.Screen("Failed")({
				UI.Stage({
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 200 },
					content = function()
						Compose.watch(function(use)
							failedRead = use(size)
						end)
						error("content setup failed")
					end,
				}),
			})
		end)
		t.expect(ok).toBe(false)
		size:set(350)
		t.expect(failedRead).toBe(300)
		controller.uninstall()
		t.expect(app.environment:get("themeMetrics"):peek()).toBe(originalMetrics)
		app.dispose()
		t.expect(released).toBe(2)
	end)

	t.it("journals native property and structural writes for layout-cache invalidation", function()
		local host = scene.new()
		local runtime, target = host.runtime, host.target()
		local UI = runtime.constructors
		local label, open = Compose.cell("Before"), Compose.cell(false)
		local stop, node = runtime.mount(function()
			return UI.VStack("Root")({
				UI.Text("Label")({ text = label }),
				Compose.show(open, function()
					return UI.Text("Detail")({ text = "Detail" })
				end),
			})
		end, target)
		local root = host.root(target, stop)
		root.takeDirty()
		local sequence = root.dirtySeq()
		label:set("After")
		local classes = {}
		for _, entry in root.takeDirty() do
			if entry.path == "/Root/Label" then
				classes[entry.class] = true
			end
		end
		t.expect(classes.paint).toBe(true)
		t.expect(classes.measure).toBe(true)
		t.expect(root.dirtySeq() > sequence).toBe(true)
		for _, value in { true, false } do
			local version = node.childrenVersion
			open:set(value)
			local structural = false
			for _, entry in root.takeDirty() do
				if entry.path == "/Root" and entry.class == "structure" then
					structural = true
				end
			end
			t.expect(structural).toBe(true)
			t.expect(node.childrenVersion > version).toBe(true)
			t.expect(#node.children).toBe(if value then 2 else 1)
		end
		stop()
		runtime.dispose()
	end)

	t.it("runs the getting-started headless snippet without a second authoring API", function()
		local fs, luau = require("@lune/fs"), require("@lune/luau")
		local guide = fs.readFile("docs/guide/03-getting-started.md")
		local source = assert(string.match(guide, "```luau\n(.-)\n```"))
		source = string.gsub(source, "local Facet = require%b()", "")
		source = string.gsub(source, "local fake = require%b()", "")
		luau.load("return function(Facet, fake)\n" .. source .. "\nend")()(Facet, fake)
	end)

	t.it("executes the component guide counter and Compose motion snippets through the application", function()
		local fs, luau = require("@lune/fs"), require("@lune/luau")
		local guide = fs.readFile("docs/guide/15-components.md")
		local snippets = {}
		for code in string.gmatch(guide, "```luau\n(.-)\n```") do
			table.insert(snippets, code)
		end
		local adapter, tick = fake.new(), nil
		local app = Facet.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core)
				return Facet.newActionSystem(core)
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
				return function() end
			end,
			connectFrame = function(fn)
				tick = fn
				return function()
					tick = nil
				end
			end,
		})
		local counter = snippets[1]
		counter = string.gsub(counter, "local Facet = require%b()", "")
		counter = string.gsub(counter, "local app = Facet.new%b()", "")
		counter = string.gsub(counter, "local close = app.mount%(Counter%)", "return app.mount(Counter)")
		local run = luau.load("return function(Facet, app)\n" .. counter .. "\nend")()
		local close, node = run(Facet, app)
		tick(1 / 60)
		adapter.driveActivate(node.children[2].path)
		tick(1 / 60)
		t.expect(node.children[1].props.text).toBe("Count: 1")
		t.expect(node.children[3].props.enabled).toBe(true)
		adapter.driveActivate(node.children[3].path)
		tick(1 / 60)
		t.expect(node.children[1].props.text).toBe("Count: 0")
		t.expect(node.children[3].props.enabled).toBe(false)
		close()
		local motion
		for _, code in snippets do
			if string.find(code, "local displayed = app.runtime.spring", 1, true) then
				motion = code
			end
		end
		assert(motion, "guide motion snippet missing")
		motion = string.gsub(motion, "\nUI.ZStack", "\nreturn UI.ZStack")
		local make = luau.load("return function(app, UI, selected)\n" .. motion .. "\nend")()
		local selected = Compose.cell(false)
		local stop, animated = app.mount(function()
			return make(app, app.controls, selected)
		end)
		tick(1 / 60)
		selected:set(true)
		tick(1 / 60)
		t.expect(animated.props.scale > 1 and animated.props.scale < 1.04).toBe(true)
		app.environment:set("reducedMotion", true)
		tick(1 / 60)
		t.expect(animated.props.scale).toBe(1)
		stop()
		app.dispose()
		t.expect(tick).toBeNil()
	end)

	t.it("native application modals own content and return input to the underlying screen", function()
		local adapter = fake.new()
		local tick, input
		local app = Facet.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core)
				input = Facet.newActionSystem(core)
				return input
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
				return function() end
			end,
			connectFrame = function(fn)
				tick = fn
				return function() end
			end,
		})
		local UI = app.controls
		local rootReleased, modalReleased, activated = 0, 0, 0
		local closeRoot = app.mount(function()
			Compose.cleanup(function()
				rootReleased += 1
			end)
			return UI.Screen("Main")({
				UI.Button({
					label = "Main action",
					onActivate = function()
						activated += 1
					end,
				}),
			})
		end)
		local function Modal()
			Compose.cleanup(function()
				modalReleased += 1
			end)
			return UI.Screen("Dialog")({
				UI.Button({
					label = "Dialog action",
					onActivate = function()
						activated += 100
					end,
				}),
			})
		end
		local closeModal = app.presentModal(Modal)
		tick(1 / 60)
		input.deviceKey("Return", true)
		input.deviceKey("Return", false)
		t.expect(activated).toBe(100)
		input.deviceKey("ButtonB", true)
		input.deviceKey("ButtonB", false)
		tick(1 / 60)
		t.expect(modalReleased).toBe(1)
		t.expect(rootReleased).toBe(0)
		closeModal()
		t.expect(modalReleased).toBe(1)
		input.deviceKey("Return", true)
		input.deviceKey("Return", false)
		t.expect(activated).toBe(101)
		app.presentModal(Modal)
		app.dispose()
		t.expect(modalReleased).toBe(2)
		t.expect(rootReleased).toBe(1)
		closeRoot()
	end)

	t.it("native anchored components follow their source and release modal and chrome content", function()
		local adapter, tick, input = fake.new(), nil, nil
		local app = Facet.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core)
				input = Facet.newActionSystem(core)
				return input
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
				return function() end
			end,
			connectFrame = function(fn)
				tick = fn
				return function() end
			end,
		})
		local UI, x, label = app.controls, Compose.cell(100), Compose.cell("Details")
		local mainActions, released = 0, 0
		app.mount(function()
			return UI.Screen("Main")({
				UI.Anchor("Position")({
					width = UI.fill(),
					height = UI.fill(),
					UI.offset(
						UI.Button("Source")({
							label = "Open",
							width = { type = "fixed", px = 100 },
							height = { type = "fixed", px = 40 },
							onActivate = function()
								mainActions += 1
							end,
						}),
						x,
						100
					),
				}),
			})
		end)
		tick(1 / 60)
		local sourcePath = "/Main/Position/Source"
		local function Panel()
			Compose.cleanup(function()
				released += 1
			end)
			return UI.VStack("Panel")({
				width = { type = "fixed", px = 160 },
				height = { type = "fixed", px = 80 },
				UI.Text("Title")({ text = label }),
			})
		end
		local function options(chrome)
			return {
				id = "Popover",
				modal = not chrome,
				chrome = chrome,
				anchor = { source = { path = sourcePath }, edge = "bottom", align = "start", gap = 8, tail = true },
			}
		end
		local close = app.presentAnchored(Panel, options(false))
		for _ = 1, 3 do
			tick(1 / 60)
		end
		local path = "/Popover/Layer/Surface/Panel"
		local before = adapter.node(path).rect.x
		x:set(240)
		label:set("Updated")
		for _ = 1, 3 do
			tick(1 / 60)
		end
		t.expect(adapter.node(path).rect.x > before + 100).toBe(true)
		t.expect(adapter.node(path .. "/Title").props.text).toBe("Updated")
		input.deviceKey("ButtonB", true)
		input.deviceKey("ButtonB", false)
		tick(1 / 60)
		t.expect(released).toBe(1)
		close()
		t.expect(released).toBe(1)
		local closeChrome = app.presentAnchored(Panel, options(true))
		tick(1 / 60)
		input.deviceKey("Return", true)
		input.deviceKey("Return", false)
		t.expect(mainActions).toBe(1)
		closeChrome()
		t.expect(released).toBe(2)
		app.presentAnchored(Panel, options(true))
		app.dispose()
		t.expect(released).toBe(3)
	end)

	for _, style in { "menu", "navigationLink", "search" } do
		t.it(`native {style} picker opens fresh owned content and commits a selection`, function()
			local core, adapter, tick = coreLib.new(), fake.new(), nil
			local app = Facet.new({
				newCore = function()
					return core
				end,
				newAdapter = function()
					return adapter
				end,
				newInputSystem = function()
					return Facet.newActionSystem(core)
				end,
				bindEnv = function(env)
					env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
					return function() end
				end,
				connectFrame = function(fn)
					tick = fn
					return function() end
				end,
			})
			local selected = Compose.cell("a")
			local query = if style == "search" then Compose.cell("") else nil
			local options = { { value = "a", label = "First" }, { value = "b", label = "Second" } }
			if query then
				for index = 3, 400 do
					options[index] = { value = tostring(index), label = `Other {index}` }
				end
			end
			app.mount(function()
				local before = core.owner.size()
				local node = app.controls.Screen("Main")({
					app.controls.Picker("Choice")({
						style = if query then "navigationLink" else style,
						query = query,
						selected = selected,
						options = options,
					}),
				})
				t.expect(core.owner.size()).toBe(before)
				return node
			end)
			tick(1 / 60)
			local resting = core.owner.size()
			for iteration = 1, 3 do
				local triggerPath
				for _, path in adapter.paths() do
					if string.sub(path, -8) == "/Trigger" then
						triggerPath = path
					end
				end
				assert(triggerPath, table.concat(adapter.paths(), "\n"))
				adapter.driveActivate(triggerPath)
				for _ = 1, 3 do
					tick(1 / 60)
				end
				if query then
					local field, hits = nil, 0
					for _, path in adapter.paths() do
						local node = adapter.node(path)
						if node.class == "TextField" then
							field = path
						end
						if string.sub(path, -4) == "/Hit" then
							hits += 1
						end
					end
					t.expect(hits > 0 and hits < 20).toBe(true)
					adapter.focusText(assert(field))
					adapter.typeText(field, "Second")
					t.expect(query:peek()).toBe("Second")
					for _ = 1, 5 do
						tick(1 / 60)
					end
				end
				local optionPath
				for _, path in adapter.paths() do
					local node = adapter.node(path)
					if
						node.class == "Button"
						and (if query then string.sub(path, -4) == "/Hit" else string.sub(path, -6) == "/Opt-b")
					then
						optionPath = path
					end
				end
				assert(optionPath, "picker did not mount its option: " .. table.concat(adapter.paths(), "\n"))
				adapter.driveActivate(optionPath)
				for _ = 1, 30 do
					tick(1 / 60)
				end
				t.expect(selected:peek()).toBe("b")
				t.expect(core.owner.size()).toBe(resting)
				selected:set("a")
				if query then
					query:set("")
				end
			end
			app.dispose()
		end)
	end

	t.it("native layered layout follows bound dimensions through the renderer", function()
		local adapter, tick = fake.new(), nil
		local app = Facet.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core)
				return Facet.newActionSystem(core)
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
				return function() end
			end,
			connectFrame = function(fn)
				tick = fn
				return function() end
			end,
		})
		local UI, width = app.controls, Compose.cell({ type = "fixed", px = 120 })
		local base, background
		app.mount(function()
			base = UI.VStack("Content")({
				width = width,
				height = { type = "fixed", px = 80 },
				UI.Text({ text = "Card" }),
			})
			background = UI.Box("Paint")({ tint = { role = "accent", blend = 1 } })
			return UI.Screen({ UI.overlay(UI.background(base, background), UI.Text({ text = "Badge" }), "end") })
		end)
		for _, size in { 120, 240, 160 } do
			width:set({ type = "fixed", px = size })
			tick(1 / 60)
			local contentRect, backgroundRect = adapter.node(base.path).rect, adapter.node(background.path).rect
			t.expect(contentRect.w).toBe(size)
			t.expect(backgroundRect.w).toBe(size)
			t.expect(backgroundRect.h).toBe(contentRect.h)
			t.expect(backgroundRect.x).toBe(contentRect.x)
			t.expect(backgroundRect.y).toBe(contentRect.y)
		end
		app.dispose()
	end)

	t.it("hands an anchored builder the same app.controls vocabulary app.mount closes over", function()
		local app, adapter, settle = require("./lib/native_world")({ x = 0, y = 0, w = 640, h = 480 })
		local seen = nil
		local close = app.presentAnchored(function(ui)
			seen = ui
			-- the public spelling: a constructor name, then a property table
			return ui.VStack("Panel")({
				width = { type = "fixed", px = 160 },
				height = { type = "fixed", px = 80 },
				ui.Text("Title")({ text = "Anchored" }),
			})
		end, { id = "Popover", anchor = { source = { rect = { x = 100, y = 100, w = 40, h = 40 } } } })
		settle(3)
		t.expect(seen).toBe(app.controls)
		t.expect(adapter.node("/Popover/Layer/Surface/Panel/Title").props.text).toBe("Anchored")
		close()
		app.dispose()
	end)

	t.it("failed native anchored construction releases resources and permits a later presentation", function()
		local core, adapter = coreLib.new(), fake.new()
		local app = Facet.new({
			newCore = function()
				return core
			end,
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function()
				return Facet.newActionSystem(core)
			end,
			bindEnv = function()
				return function() end
			end,
			connectFrame = function()
				return function() end
			end,
		})
		local before, released = core.owner.size(), 0
		local opts = { anchor = { source = { rect = { x = 100, y = 100, w = 40, h = 40 } } } }
		local ok = pcall(function()
			app.presentAnchored(function()
				Compose.cleanup(function()
					released += 1
				end)
				app.controls.Text({ text = "Partial" })
				error("panel failed")
			end, opts)
		end)
		t.expect(ok).toBe(false)
		t.expect(released).toBe(1)
		t.expect(core.owner.size()).toBe(before)
		t.expect(adapter.rootCount()).toBe(0)
		local close = app.presentAnchored(function()
			return app.controls.Text({ text = "Valid" })
		end, opts)
		close()
		t.expect(core.owner.size()).toBe(before)
		app.dispose()
	end)

	t.it("native background and overlay preserve reactive size and explicit wrapper overrides", function()
		local core = coreLib.new()
		Facet.newEnvironment(core)
		local host = scene.new()
		local UI = require("../src/render/compose_controls").new(host.runtime, core, {})
		local width = Compose.cell({ type = "fixed", px = 100 })
		local owner
		local target, base, plate, layered = host.target(), nil, nil, nil
		local stop, node = host.runtime.mount(function()
			owner = Compose.currentOwner()
			base = UI.VStack({ width = width, height = { type = "fixed", px = 80 }, UI.Text({ text = "Card" }) })
			plate = UI.Box({ surface = "raised" })
			layered = UI.background(base, plate)
			return UI.overlay(layered, UI.Text({ text = "Badge" }), "end")
		end, target)
		t.expect(layered.children[1]).toBe(plate)
		t.expect(layered.children[2]).toBe(base)
		t.expect(plate.props.width.type).toBe("fill")
		t.expect(node.props.width.px).toBe(100)
		width:set(nil)
		t.expect(layered.props.width).toBeNil()
		t.expect(node.props.width).toBeNil()
		width:set({ type = "fixed", px = 180 })
		t.expect(base.props.width.px).toBe(180)
		t.expect(layered.props.width.px).toBe(180)
		t.expect(node.props.width.px).toBe(180)
		Compose.withOwner(owner, function()
			host.runtime.decorate(layered, { width = { type = "fixed", px = 240 } })
		end)
		width:set({ type = "fixed", px = 200 })
		t.expect(layered.props.width.px).toBe(240)
		t.expect(node.props.width.px).toBe(240)
		stop()
		t.expect(base.dimensionFollowers).toBeNil()
		t.expect(layered.dimensionSource).toBeNil()
		host.runtime.dispose()
	end)

	t.it("an equal-valued native modifier replaces only the property binding it writes", function()
		local core = coreLib.new()
		Facet.newEnvironment(core)
		local host = scene.new()
		local UI = require("../src/render/compose_controls").new(host.runtime, core, {})
		local x, y = Compose.cell(12), Compose.cell(24)
		local stop, node = host.runtime.mount(function()
			return UI.offset(UI.Box({ offsetX = x, offsetY = y }), 12)
		end, host.target())
		x:set(100)
		y:set(200)
		t.expect(node.props.offsetX).toBe(12)
		t.expect(node.props.offsetY).toBe(200)
		stop()
		host.runtime.dispose()
	end)

	t.it("native measured lists resize from rendered content and skip disabled rows", function()
		local adapter, tick, input = fake.new(), nil, nil
		local app = Facet.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core)
				input = Facet.newActionSystem(core)
				return input
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
				return function() end
			end,
			connectFrame = function(fn)
				tick = fn
				return function() end
			end,
		})
		local UI, selected = app.controls, nil
		local items =
			Compose.cell({ { id = "a", height = 80, enabled = false }, { id = "b", height = 96, enabled = true } })
		local list
		app.mount(function()
			list = UI.VirtualList("Measured")({
				rows = items,
				key = "id",
				itemExtent = "measured",
				estimatedItemExtent = 48,
				viewportExtent = 300,
				rowFocusable = function(item)
					return item.enabled
				end,
				onActivate = function(item)
					selected = item.id
				end,
				cell = function(_, ctx)
					local item = Compose.formula(ctx.current)
					return UI.VStack({
						width = UI.fill(),
						height = function(use)
							return { type = "fixed", px = use(item).height }
						end,
						UI.Text({
							text = function(use)
								return use(item).id
							end,
						}),
					})
				end,
			})
			return UI.Screen({ list })
		end)
		local function settle()
			for _ = 1, 5 do
				tick(1 / 60)
			end
		end
		settle()
		t.expect(list.children[1].props.height.px).toBe(176)
		input.deviceKey("Return", true)
		input.deviceKey("Return", false)
		t.expect(selected).toBe("b")
		items:set({ { id = "a", height = 160, enabled = false }, { id = "b", height = 96, enabled = true } })
		settle()
		t.expect(list.children[1].props.height.px).toBe(256)
		items:set({ { id = "b", height = 96, enabled = true } })
		settle()
		t.expect(list.children[1].props.height.px).toBe(96)
		app.dispose()
	end)

	t.it("native layout and paint modifiers preserve the node and its existing bindings", function()
		local core = coreLib.new()
		Facet.newEnvironment(core)
		local host = scene.new()
		local UI = require("../src/render/compose_controls").new(host.runtime, core, {})
		local enabled = Compose.cell(true)
		local target = host.target()
		local decorated
		local stop, node = host.runtime.mount(function()
			local panel = UI.VStack({ enabled = enabled, UI.Text({ text = "Panel" }) })
			decorated = UI.stroke(UI.corners(UI.padding(UI.frame(panel, { maxWidth = "infinity" }), "m"), 8), {})
			t.expect(decorated).toBe(panel)
			return UI.offset(UI.alignment(decorated, "center", "start"), 12, 24)
		end, target)
		t.expect(node).toBe(decorated)
		t.expect(node.props.width.type).toBe("fill")
		t.expect(node.props.padding).toBe("m")
		t.expect(node.props.offsetX).toBe(12)
		t.expect(node.props.offsetY).toBe(24)
		enabled:set(false)
		t.expect(node.props.enabled).toBe(false)
		t.expect(#node.children).toBe(1)
		stop()
		host.runtime.dispose()
	end)

	t.it("native picker retains options across Compose keyed replacement and reorder", function()
		local core = coreLib.new()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake.new()
		local presenter = presenterLib.new(core, env, adapter, Facet.newActionSystem(core))
		local host = scene.new()
		local UI = require("../src/render/compose_controls").new(host.runtime, core, presenter)
		local selected = Compose.cell("a")
		local options = Compose.cell({ { value = "a", label = "First" }, { value = "b", label = "Second" } })
		local before = core.owner.size()
		local target = host.target()
		local stop, node = host.runtime.mount(function()
			return UI.Picker("Choice")({ selected = selected, style = "segmented", options = options })
		end, target)
		local handle = presenter.present(host.root(target, stop))
		local function find(label)
			local function walk(n)
				if n.class == "Button" and n.props.label == label then
					return n
				end
				for _, child in n.children do
					local found = walk(child)
					if found then
						return found
					end
				end
				return nil
			end
			return walk(node)
		end
		local retained = assert(find("Second"))
		options:set({ { value = "b", label = "Updated" }, { value = "a", label = "First" } })
		presenter.refresh()
		t.expect(find("Updated")).toBe(retained)
		adapter.driveActivate(retained.path)
		t.expect(selected:peek()).toBe("b")
		options:set({ { value = "a", label = "First" } })
		presenter.refresh()
		t.expect(find("Updated")).toBeNil()
		presenter.dismiss(handle)
		t.expect(core.owner.size()).toBe(before)
		host.runtime.dispose()
	end)

	t.it("native automatic picker adapts between menu and strip without losing its selection", function()
		local core = coreLib.new()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake.new()
		local presenter = presenterLib.new(core, env, adapter, Facet.newActionSystem(core))
		local host = scene.new()
		local UI = require("../src/render/compose_controls").new(host.runtime, core, presenter)
		local selected = Compose.cell("a")
		local before = core.owner.size()
		local target = host.target()
		local stop, node = host.runtime.mount(function()
			return UI.Picker("Choice")({
				selected = selected,
				options = { { value = "a", label = "First" }, { value = "b", label = "Second" } },
			})
		end, target)
		local handle = presenter.present(host.root(target, stop))
		local function has(label)
			local function walk(n)
				if n.class == "Button" and n.props.label == label then
					return true
				end
				for _, child in n.children do
					if walk(child) then
						return true
					end
				end
				return false
			end
			return walk(node)
		end
		selected:set("b")
		env:set("displaySize", "Large")
		presenter.refresh()
		t.expect(selected:peek()).toBe("b")
		t.expect(has("First")).toBe(true)
		t.expect(has("Second")).toBe(true)
		env:set("displaySize", "Medium")
		presenter.refresh()
		presenter.dismiss(handle)
		t.expect(core.owner.size()).toBe(before)
		host.runtime.dispose()
	end)

	for _, style in { "segmented", "inline", "radioGroup" } do
		t.it(`native {style} picker reads and writes Compose selection cells`, function()
			local core = coreLib.new()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			local adapter = fake.new()
			local presenter = presenterLib.new(core, env, adapter, Facet.newActionSystem(core))
			local host = scene.new()
			local UI = require("../src/render/compose_controls").new(host.runtime, core, presenter)
			local selected = Compose.cell("a")
			local baseline = core.owner.size()
			local target = host.target()
			local stop, node = host.runtime.mount(function()
				return UI.Picker("Choice")({
					selected = selected,
					style = style,
					options = { { value = "a", label = "First" }, { value = "b", label = "Second" } },
				})
			end, target)
			local handle = presenter.present(host.root(target, stop))
			local button
			local function walk(n)
				if n.class == "Button" and n.props.label == "Second" then
					button = n
				end
				for _, child in n.children do
					walk(child)
				end
			end
			walk(node)
			assert(button, "second option missing")
			adapter.driveActivate(button.path)
			presenter.refresh()
			t.expect(selected:peek()).toBe("b")
			selected:set("a")
			presenter.dismiss(handle)
			t.expect(core.owner.size()).toBe(baseline)
			host.runtime.dispose()
		end)
	end

	t.it("uses Compose's optional constructor names for composite controls", function()
		local host = scene.new()
		local core = coreLib.new()
		Facet.newEnvironment(core)
		local UI = require("../src/render/compose_controls").new(host.runtime, core, {})
		local target = host.target()
		local before = core.owner.size()
		local stop, node = host.runtime.mount(function()
			return UI.VStack("Form")({
				UI.Button("Submit")({ label = "Send", onActivate = function() end }),
				UI.Toggle("Enabled")({ label = "Enabled", value = Compose.cell(true) }),
				UI.TextInput("Draft")({ value = Compose.cell("Draft") }),
				UI.ProgressView("Progress")({ value = 0.5 }),
			})
		end, target)
		for index, name in { "Submit", "Enabled", "Draft", "Progress" } do
			t.expect(node.children[index].path).toBe("/Form/" .. name)
		end
		stop()
		t.expect(core.owner.size()).toBe(before)
		host.runtime.dispose()
	end)

	t.it("runs named native scroll navigation with Compose target and progress cells", function()
		local core = coreLib.new()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 300 })
		env:set("reducedMotion", true)
		local adapter = fake.new()
		local presenter = presenterLib.new(core, env, adapter, Facet.newActionSystem(core))
		local host = scene.new()
		local UI = require("../src/render/compose_controls").new(host.runtime, core, presenter)
		local target, progress = Compose.cell(nil), Compose.cell(0)
		local before = core.owner.size()
		local mountTarget = host.target()
		local stop = host.runtime.mount(function()
			return UI.Screen("S")({
				UI.ScrollView("Scroll")({
					width = { type = "fill" },
					height = { type = "fill" },
					navigation = { targets = { "Hero", "Shelf", "End" }, target = target, progress = progress },
					UI.Box("Hero")({ height = { type = "fixed", px = 300 } }),
					UI.Box("Shelf")({ height = { type = "fixed", px = 300 } }),
					UI.Box("End")({ height = { type = "fixed", px = 300 } }),
				}),
			})
		end, mountTarget)
		t.expect(core.owner.size()).toBe(before)
		local handle = presenter.present(host.root(mountTarget, stop))
		local function settle()
			for _ = 1, 90 do
				presenter.tick(1 / 60)
				presenter.refresh()
			end
		end
		target:set("Shelf")
		settle()
		t.expect(handle.controller.scrollPosition("/S/Scroll").y).toBe(300)
		t.expect(progress:peek()).toBe(0.5)
		target:set("End")
		settle()
		t.expect(handle.controller.scrollPosition("/S/Scroll").y).toBe(600)
		t.expect(progress:peek()).toBe(1)
		presenter.dismiss(handle)
		t.expect(core.owner.size()).toBe(before)
		host.runtime.dispose()
	end)

	t.it("unwinds an invalid application root and remains usable after the error", function()
		local core = coreLib.new()
		local app = Facet.new({
			newCore = function()
				return core
			end,
			newAdapter = function()
				return fake.new()
			end,
			newInputSystem = function(c)
				return Facet.newActionSystem(c)
			end,
			bindEnv = function()
				return function() end
			end,
			connectFrame = function()
				return function() end
			end,
		})
		local before = core.owner.size()
		local cleaned = 0
		local ok = pcall(app.mount, function()
			Compose.cleanup(function()
				cleaned += 1
			end)
			return Compose.fragment({
				app.controls.Button({ label = "First", onActivate = function() end }),
				app.controls.Button({ label = "Second", onActivate = function() end }),
			})
		end)
		t.expect(ok).toBe(false)
		t.expect(cleaned).toBe(1)
		t.expect(core.owner.size()).toBe(before)
		local close = app.mount(function()
			return app.controls.Screen({ app.controls.Text({ text = "Recovered" }) })
		end)
		close()
		t.expect(core.owner.size()).toBe(before)
		app.dispose()
	end)

	t.it("binds native model cells through value controls and preserves input semantics", function()
		local core = coreLib.new()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 800 })
		local adapter = fake.new()
		local presenter = presenterLib.new(core, env, adapter, Facet.newActionSystem(core))
		local host = scene.new()
		local UI = require("../src/render/compose_controls").new(host.runtime, core, presenter)
		local number, selected, enabled = Compose.cell(2), Compose.cell(false), Compose.cell(true)
		local before = core.owner.size()
		local target = host.target()
		local stop = host.runtime.mount(function()
			return UI.Screen("Form")({
				UI.Label("Heading")({ title = "Preferences" }),
				UI.Stepper("Count")({ value = number, min = 0, max = 5, enabled = enabled }),
				UI.Slider("Amount")({ value = number, min = 0, max = 5, enabled = enabled }),
				UI.Rating("Rating")({ value = number, enabled = enabled }),
				UI.LevelPicker("Level")({ value = number, count = 5, enabled = enabled }),
				UI.Chip("Saved")({ label = "Saved", selected = selected, enabled = enabled }),
			})
		end, target)
		local handle = presenter.present(host.root(target, stop))
		presenter.refresh()
		adapter.driveActivate("/Form/Count/Inc")
		presenter.refresh()
		t.expect(number:peek()).toBe(3)
		adapter.driveActivate("/Form/Saved+target/Saved")
		presenter.refresh()
		t.expect(selected:peek()).toBe(true)
		t.expect(adapter.node("/Form/Saved+target/Saved").props.selected).toBe(true)
		-- A caller write reaches all four numeric presentations through their
		-- existing readouts and paint bindings without recreating the control.
		local star = adapter.node("/Form/Rating/Stars/Star3")
		number:set(1)
		presenter.refresh()
		t.expect(adapter.node("/Form/Rating/Stars/Star3")).toBe(star)
		t.expect(star.props.text).toBe("☆")
		enabled:set(false)
		presenter.refresh()
		adapter.driveActivate("/Form/Count/Inc")
		adapter.driveActivate("/Form/Saved+target/Saved")
		t.expect(number:peek()).toBe(1)
		t.expect(selected:peek()).toBe(true)
		presenter.dismiss(handle)
		t.expect(core.owner.size()).toBe(before)
		host.runtime.dispose()
	end)

	t.it("rejects invalid native value controls without retaining a scope", function()
		local core = coreLib.new()
		Facet.newEnvironment(core)
		local host = scene.new()
		local UI = require("../src/render/compose_controls").new(host.runtime, core, {})
		local before = core.owner.size()
		for _, name in { "Stepper", "Slider", "Rating", "LevelPicker", "Chip", "Label" } do
			local target = host.target()
			local ok = pcall(host.runtime.mount, function()
				return UI[name]({})
			end, target)
			t.expect(ok).toBe(false)
			t.expect(core.owner.size()).toBe(before)
			t.expect(#target.children).toBe(0)
		end
		host.runtime.dispose()
	end)

	for _, retention in { "all", "top" } do
		t.it(`uses Compose LayerStack {retention} retention with Facet nodes`, function()
			local host = scene.new()
			local r, UI, target = host.runtime, host.runtime.constructors, host.target()
			local layers = Compose.cell({ { id = "home", title = "Home" } })
			local disposed = {}
			local stop, node = r.mount(function()
				return UI.ZStack({
					Compose.LayerStack({
						from = layers,
						key = function(item)
							return item.id
						end,
						retention = retention,
						render = function(item, state, key)
							Compose.cleanup(function()
								disposed[key] = (disposed[key] or 0) + 1
							end)
							return UI.Button({
								label = function(use)
									return use(item).title
								end,
								enabled = function(use)
									return use(state).top
								end,
							})
						end,
					}),
				})
			end, target)
			local home = node.children[1]
			layers:set({ { id = "home", title = "Updated home" }, { id = "detail", title = "Detail" } })
			t.expect(#node.children).toBe(if retention == "all" then 2 else 1)
			local detail = node.children[#node.children]
			t.expect(detail.props.label).toBe("Detail")
			t.expect(detail.props.enabled).toBe(true)
			if retention == "all" then
				t.expect(node.children[1]).toBe(home)
				t.expect(home.props.label).toBe("Updated home")
				t.expect(home.props.enabled).toBe(false)
			else
				t.expect(disposed.home).toBe(1)
			end
			layers:set({ { id = "home", title = "Restored" } })
			t.expect(disposed.detail).toBe(1)
			t.expect(node.children[1].props.enabled).toBe(true)
			if retention == "all" then
				t.expect(node.children[1]).toBe(home)
			end
			stop()
			t.expect(disposed.home).toBe(if retention == "all" then 1 else 2)
			r.dispose()
		end)
	end

	t.it("uses Compose OrderedCollection windowing and preserves overlapping Facet rows", function()
		local host = scene.new()
		local r, UI, target = host.runtime, host.runtime.constructors, host.target()
		local data = {}
		for index = 1, 1000 do
			data[index] = { id = index, title = `Game {index}` }
		end
		local items = Compose.cell(data)
		local viewport = Compose.cell({ offset = 0, size = 100 })
		local status = Compose.cell(nil)
		local controls = {}
		local created, released = 0, 0
		local stop, node = r.mount(function()
			return UI.VStack({
				Compose.OrderedCollection({
					from = items,
					key = function(item)
						return item.id
					end,
					mode = "windowed",
					viewport = viewport,
					layout = { kind = "list", itemSize = 20 },
					overscan = 0,
					status = status,
					controls = controls,
					render = function(item, placement)
						created += 1
						Compose.cleanup(function()
							released += 1
						end)
						return UI.Text({
							text = function(use)
								return `{use(item).title} at {use(placement).offset}`
							end,
						})
					end,
				}),
			})
		end, target)
		t.expect(#node.children < 10).toBe(true)
		t.expect(status:peek().total).toBe(1000)
		t.expect(status:peek().extent).toBe(20000)
		local overlapping = node.children[3]
		viewport:set({ offset = 40, size = 100 })
		t.expect(node.children[1]).toBe(overlapping)
		t.expect(node.children[1].props.text).toBe("Game 3 at 40")
		local replacement = table.clone(data)
		replacement[3] = { id = 3, title = "Updated game" }
		items:set(replacement)
		t.expect(node.children[1]).toBe(overlapping)
		t.expect(node.children[1].props.text).toBe("Updated game at 40")
		t.expect(controls.indexOfKey(3)).toBe(3)
		t.expect(controls.offsetOf(3)).toBe(40)
		viewport:set({ offset = 19000, size = 100 })
		t.expect(#node.children < 10).toBe(true)
		t.expect(created - released).toBe(#node.children)
		stop()
		t.expect(released).toBe(created)
		r.dispose()
	end)

	t.it("virtualizes the native Facet grid with Compose and retains rows on responsive reflow", function()
		local core = coreLib.new()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 300 })
		local adapter = fake.new()
		adapter.scrollBarThickness = fake.SCROLL_BAR_RESERVE
		local presenter = presenterLib.new(core, env, adapter, Facet.newActionSystem(core))
		local host = scene.new()
		local UI = require("../src/render/compose_controls").new(host.runtime, core, presenter)
		local data = {}
		for index = 1, 1000 do
			table.insert(data, { id = index, title = `Game {index}` })
		end
		local items, columns = Compose.cell(data), Compose.cell(3)
		local gap = Compose.cell("s")
		local created, released, activated = 0, 0, nil
		local target = host.target()
		local stop, node = host.runtime.mount(function()
			return UI.Screen("S")({
				UI.VirtualGrid("Games")({
					items = items,
					key = "id",
					columns = columns,
					itemExtent = 40,
					viewportExtent = "auto",
					gap = gap,
					rowGap = "xs",
					onActivate = function(item)
						activated = item.id
					end,
					cell = function(_, ctx)
						local item = Compose.formula(ctx.current)
						created += 1
						Compose.cleanup(function()
							released += 1
						end)
						return UI.Text({
							text = function(use)
								return use(item).title
							end,
						})
					end,
				}),
			})
		end, target)
		local handle = presenter.present(host.root(target, stop))
		local function settle()
			for _ = 1, 6 do
				presenter.tick(1 / 60)
				presenter.refresh()
			end
		end
		local function find(n, title)
			if n.class == "Text" and n.props.text == title then
				return n
			end
			for _, child in n.children do
				local hit = find(child, title)
				if hit then
					return hit
				end
			end
			return nil
		end
		settle()
		t.expect(created - released < 40).toBe(true)
		local retained = assert(find(node, "Game 3"))
		local function contained(n)
			if n.class == "Button" and n.id == "Hit" then
				local rect = adapter.node(n.path).rect
				local window = adapter.node("/S/Games").windowRect
				t.expect(rect.x >= window.x and rect.x + rect.w <= window.x + window.w).toBe(true)
			end
			for _, child in n.children do
				contained(child)
			end
		end
		contained(node)
		gap:set("m")
		columns:set(2)
		settle()
		t.expect(find(node, "Game 3")).toBe(retained)
		contained(node)
		local nextItems = table.clone(data)
		nextItems[3] = { id = 3, title = "Updated game" }
		items:set(nextItems)
		settle()
		t.expect(find(node, "Updated game")).toBe(retained)
		local row = retained.parent
		adapter.driveActivate(row.children[1].path)
		t.expect(activated).toBe(3)
		adapter.driveScroll("/S/Games", { x = 0, y = 660 })
		settle()
		t.expect(find(node, "Updated game")).toBeNil()
		t.expect(created - released < 40).toBe(true)
		local anchor = assert(find(node, "Game 31"))
		columns:set(3)
		settle()
		t.expect(find(node, "Game 31")).toBe(anchor)
		t.expect(handle.controller.scrollPosition("/S/Games").y).toBe(440)
		contained(node)
		presenter.dismiss(handle)
		t.expect(released).toBe(created)
		host.runtime.dispose()
	end)

	t.it("native lists preserve scroll anchors and follow appended or resized rows only at the end", function()
		local core = coreLib.new()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 200 })
		local adapter = fake.new()
		adapter.scrollBarThickness = fake.SCROLL_BAR_RESERVE
		local presenter = presenterLib.new(core, env, adapter, Facet.newActionSystem(core))
		local host = scene.new()
		local UI = require("../src/render/compose_controls").new(host.runtime, core, presenter)
		local data = {}
		for index = 1, 40 do
			data[index] = { id = index }
		end
		local items, measured = Compose.cell(data), Compose.cell({})
		local created, released = 0, 0
		local target = host.target()
		local stop = host.runtime.mount(function()
			return UI.Screen("S")({
				UI.VirtualList("History")({
					rows = items,
					key = "id",
					itemExtent = function(item, _, use)
						return use(measured)[item.id] or 48
					end,
					viewportExtent = "auto",
					follow = "end",
					followThreshold = 8,
					cell = function(_, ctx)
						local item = Compose.formula(ctx.current)
						created += 1
						Compose.cleanup(function()
							released += 1
						end)
						return UI.Text({
							text = function(use)
								return tostring(use(item).id)
							end,
						})
					end,
				}),
			})
		end, target)
		local handle = presenter.present(host.root(target, stop))
		local function settle()
			for _ = 1, 6 do
				presenter.tick(1 / 60)
				presenter.refresh()
			end
		end
		local function offset()
			return handle.controller.scrollPosition("/S/History").y
		end
		local function scroll(y)
			adapter.driveScroll("/S/History", { x = 0, y = y })
			settle()
		end
		settle()
		t.expect(created - released < 12).toBe(true)
		scroll(1720)
		local appended = table.clone(data)
		for index = 41, 43 do
			appended[index] = { id = index }
		end
		items:set(appended)
		settle()
		t.expect(offset()).toBe(1864)
		measured:set({ [43] = 96 })
		settle()
		t.expect(offset()).toBe(1912)
		scroll(480)
		local more = table.clone(appended)
		more[44] = { id = 44 }
		items:set(more)
		settle()
		t.expect(offset()).toBe(480)
		-- A resized row above the viewport preserves the visible item's position.
		measured:set({ [1] = 96, [43] = 96 })
		settle()
		t.expect(offset()).toBe(528)
		t.expect(created - released < 12).toBe(true)
		presenter.dismiss(handle)
		t.expect(released).toBe(created)
		host.runtime.dispose()
	end)

	t.it("reflows a Compose grid without remounting retained Facet cells", function()
		local host = scene.new()
		local UI, runtime, target = host.runtime.constructors, host.runtime, host.target()
		local layout = Compose.cell({ kind = "grid", columns = 2, itemSize = 30, crossSize = 60 })
		local status, state = Compose.cell({}), {}
		local released = 0
		local stop, node = runtime.mount(function()
			return UI.Anchor({
				Compose.OrderedCollection({
					from = Compose.cell({ 1, 2, 3, 4, 5, 6 }),
					layout = layout,
					status = status,
					render = function(_, placement, key)
						state[key] = Compose.cell(0)
						Compose.cleanup(function()
							released += 1
						end)
						return UI.Text({
							text = function(use)
								return tostring(use(state[key]))
							end,
							offsetX = function(use)
								return use(placement).crossOffset
							end,
							offsetY = function(use)
								return use(placement).offset
							end,
							width = function(use)
								return { type = "fixed", px = use(placement).crossSize }
							end,
							height = function(use)
								return { type = "fixed", px = use(placement).size }
							end,
						})
					end,
				}),
			})
		end, target)
		local before = table.clone(node.children)
		state[4]:set(7)
		layout:set({ kind = "grid", columns = 3, itemSize = 40, gap = 4, crossSize = 80, crossGap = 5 })
		for index, child in before do
			t.expect(node.children[index]).toBe(child)
		end
		t.expect(released).toBe(0)
		t.expect(node.children[4].props.text).toBe("7")
		t.expect(node.children[5].props.offsetX).toBe(85)
		t.expect(node.children[5].props.offsetY).toBe(44)
		t.expect(node.children[5].props.width.px).toBe(80)
		t.expect(status:peek().extent).toBe(84)
		stop()
		t.expect(released).toBe(6)
		runtime.dispose()
	end)

	t.it("keeps surface diagnostics isolated when a runtime mounts multiple roots", function()
		local host = scene.new()
		local r, UI = host.runtime, host.runtime.constructors
		local a, b = host.target(), host.target()
		local stopA = r.mount(function()
			return UI.Screen({ UI.Text({ text = "A" }) })
		end, a)
		local stopB = r.mount(function()
			return UI.Screen({ UI.Text({ text = "B" }), UI.Text({ text = "C" }) })
		end, b)
		local first, second = host.root(a, stopA), host.root(b, stopB)
		t.expect(first.counters().mounted).toBe(2)
		t.expect(second.counters().mounted).toBe(3)
		stopA()
		t.expect(first.counters().mounted).toBe(0)
		t.expect(second.counters().mounted).toBe(3)
		stopB()
		t.expect(second.counters().mounted).toBe(0)
		r.dispose()
	end)
	t.it("edits and commits a native text cell through the presenter", function()
		local core, adapter = coreLib.new(), fake.new()
		local tick
		local app = Facet.new({
			newCore = function()
				return core
			end,
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(c)
				return Facet.newActionSystem(c)
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
				return function() end
			end,
			connectFrame = function(fn)
				tick = fn
				return function() end
			end,
		})
		local value, enabled = Compose.cell(""), Compose.cell(true)
		local committed
		local before = core.owner.size()
		local UI = app.controls
		local close, node = app.mount(function()
			return UI.Screen({
				UI.TextInput({
					value = value,
					enabled = function(use)
						return use(enabled)
					end,
					onCommit = function(text)
						committed = text
					end,
				}),
				UI.Text({ text = value }),
			})
		end)
		tick(1 / 60)
		local field = node.children[1].path .. "/Field"
		adapter.focusText(field)
		adapter.typeText(field, "Native Compose text")
		tick(1 / 60)
		t.expect(value:peek()).toBe("Native Compose text")
		t.expect(node.children[2].props.text).toBe("Native Compose text")
		adapter.commitText(field)
		t.expect(committed).toBe("Native Compose text")
		enabled:set(false)
		tick(1 / 60)
		adapter.typeText(field, "Blocked")
		t.expect(value:peek()).toBe("Native Compose text")
		close()
		t.expect(core.owner.size()).toBe(before)
		app.dispose()
	end)
	for _, presentation in { "switch", "checkbox", "button" } do
		t.it(`uses native cells for {presentation} controls and releases their scopes`, function()
			local core = coreLib.new()
			local adapter = fake.new()
			local tick
			local app = Facet.new({
				newCore = function()
					return core
				end,
				newAdapter = function()
					return adapter
				end,
				newInputSystem = function(c)
					return Facet.newActionSystem(c)
				end,
				bindEnv = function(env)
					env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
					return function() end
				end,
				connectFrame = function(fn)
					tick = fn
					return function() end
				end,
			})
			local value = Compose.cell(false)
			local enabled = Compose.cell(true)
			local UI = app.controls
			local scopesBefore = core.owner.size()
			local close, node = app.mount(function()
				return UI.Screen({
					UI.Toggle({
						label = "First",
						value = value,
						presentation = presentation,
						enabled = function(use)
							return use(enabled)
						end,
					}),
					UI.Toggle({ label = "Second", value = Compose.cell(false), presentation = presentation }),
				})
			end)
			tick(1 / 60)
			t.expect(node.children[1].path ~= node.children[2].path).toBe(true)
			adapter.driveActivate(node.children[1].path)
			tick(1 / 60)
			t.expect(value:peek()).toBe(true)
			enabled:set(false)
			tick(1 / 60)
			adapter.driveActivate(node.children[1].path)
			t.expect(value:peek()).toBe(true)
			close()
			t.expect(core.owner.size()).toBe(scopesBefore)
			app.dispose()
		end)
	end
	t.it("keeps Facet cross-property validation and clipping normalization", function()
		local host = scene.new()
		local r, target = host.runtime, host.target()
		local UI = r.constructors
		local ok = pcall(r.mount, function()
			return UI.Button({ label = "Outer", UI.Button({ label = "Nested" }) })
		end, target)
		t.expect(ok).toBe(false)
		local stop, node = r.mount(function()
			return UI.VStack({ overflow = "clip" })
		end, target)
		t.expect(node.props.clipChildren).toBe(true)
		stop()
		r:dispose()
	end)

	t.it("runs the public README counter with one host and closes its resources", function()
		local adapter = fake.new()
		local tick
		local disconnected = false
		local app = Facet.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core)
				return Facet.newActionSystem(core)
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
				return function() end
			end,
			connectFrame = function(fn)
				tick = fn
				return function()
					disconnected = true
				end
			end,
		})
		local UI = app.controls
		local disposed = 0
		local function Counter()
			local count = Facet.Compose.cell(0)
			Facet.Compose.cleanup(function()
				disposed += 1
			end)
			return UI.Screen({
				padding = "m",
				gap = "s",
				UI.Text({
					text = function(use)
						return `Clicked {use(count)} times`
					end,
				}),
				UI.Button({
					label = "Add one",
					onActivate = function()
						count:update(function(n)
							return n + 1
						end)
					end,
				}),
			})
		end
		local close, node = app.mount(Counter)
		tick(1 / 60)
		t.expect(adapter.driveActivate(node.children[2].path)).toBe(true)
		tick(1 / 60)
		t.expect(node.children[1].props.text).toBe("Clicked 1 times")
		close()
		close()
		t.expect(disposed).toBe(1)
		app.dispose()
		app.dispose()
		t.expect(disconnected).toBe(true)
	end)

	t.it("routes presenter input into native cells and disposes the composed surface", function()
		local host = scene.new()
		local runtime, target = host.runtime, host.target()
		local UI = runtime.constructors
		local count = Compose.cell(0)
		local stop, node = runtime.mount(function()
			return UI.Screen({
				UI.Text({
					text = function(use)
						return tostring(use(count))
					end,
				}),
				UI.Button({
					label = "Add one",
					onActivate = function()
						count:update(function(n)
							return n + 1
						end)
					end,
				}),
			})
		end, target)
		local root = host.root(target, stop)
		local core = coreLib.new()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake.new()
		local presenter = presenterLib.new(core, env, adapter, Facet.newActionSystem(core))
		local handle = presenter.present(root)
		presenter.refresh()
		t.expect(adapter.driveActivate(node.children[2].path)).toBe(true)
		runtime:settle()
		presenter.refresh()
		t.expect(count:peek()).toBe(1)
		t.expect(node.children[1].props.text).toBe("1")
		presenter.dismiss(handle)
		t.expect(root.counters().mounted).toBe(0)
		runtime.dispose()
	end)

	t.it("renders anonymous native nodes and changes only the bound property", function()
		local host = scene.new()
		local runtime, target = host.runtime, host.target()
		local UI = runtime.constructors
		local value = Compose.cell("Before")
		local disposed = 0
		local stop, node = runtime.mount(function()
			Compose.cleanup(function()
				disposed += 1
			end)
			return UI.Screen({ padding = "m", UI.Text({ text = value }), UI.Text({ text = "Still" }) })
		end, target)
		local root = host.root(target, stop)
		local core = coreLib.new()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local controller = Facet.renderer.attach(core, root, env, fake.new(), {})
		controller.initialRender()
		local first = node.children[1]
		value:set("After")
		runtime:settle()
		controller.refresh()
		t.expect(node.children[1]).toBe(first)
		t.expect(first.props.text).toBe("After")
		t.expect(node.children[2].props.text).toBe("Still")
		t.expect(root.counters().factoryRuns).toBe(3)
		controller.dispose()
		stop()
		stop()
		runtime.dispose()
		t.expect(disposed).toBe(1)
		t.expect(root.counters().mounted).toBe(0)
	end)
	t.it("preserves anonymous row identity across native keyed reorder and replacement", function()
		local host = scene.new()
		local r, target = host.runtime, host.target()
		local UI = r.constructors
		local rows = Compose.cell({ { id = "a", label = "Alpha" }, { id = "b", label = "Beta" } })
		local stop, node = r.mount(function()
			return UI.VStack({
				Compose.keyed({
					from = rows,
					key = function(item)
						return item.id
					end,
					render = function(item)
						return UI.Text({
							text = function(use)
								return use(item).label
							end,
						})
					end,
				}),
			})
		end, target)
		local first, second = node.children[1], node.children[2]
		rows:set({ { id = "b", label = "B2" }, { id = "a", label = "A2" } })
		r:settle()
		t.expect(node.children[1]).toBe(second)
		t.expect(node.children[2]).toBe(first)
		t.expect(first.props.text).toBe("A2")
		rows:set({})
		r:settle()
		t.expect(#node.children).toBe(0)
		stop()
		r.dispose()
	end)
	t.it("inherits disabled state and tint through native property bindings", function()
		local host = scene.new()
		local r, target = host.runtime, host.target()
		local UI = r.constructors
		local enabled = Compose.cell(false)
		local stop, node = r.mount(function()
			return UI.VStack({ enabled = enabled, UI.Text({ text = "Inside" }) })
		end, target)
		t.expect(node.children[1].disabled).toBe(true)
		enabled:set(true)
		r:settle()
		t.expect(node.children[1].disabled).toBeNil()
		stop()
		r.dispose()
	end)
	t.it("refuses malformed initial properties and releases partially built nodes", function()
		local host = scene.new()
		local r, target = host.runtime, host.target()
		local ok = pcall(r.mount, function()
			return r.constructors.Text({ text = false })
		end, target)
		t.expect(ok).toBe(false)
		t.expect(#target.children).toBe(0)
		local stop = r.mount(function()
			return r.constructors.Text({ text = "Valid" })
		end, target)
		local root = host.root(target, stop)
		t.expect(root.counters().mounted).toBe(1)
		stop()
		t.expect(root.counters().mounted).toBe(0)
		r.dispose()
	end)
	t.it("preserves Compose labels as optional names without requiring an id property", function()
		local host = scene.new()
		local r, target = host.runtime, host.target()
		local stop, node = r.mount(function()
			return r.constructors.Text("Title")({ text = "Named" })
		end, target)
		t.expect(node.path).toBe("/Title")
		stop()
		r.dispose()
	end)
end)
