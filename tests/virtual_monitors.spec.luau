--!strict
local t = require("./lib/testkit")
local nativeWorld = require("./lib/native_world")
local Facet = require("../src")
local screens = require("../examples/virtual_monitors/screens")
local Compose = Facet.Compose
local fake_target = require("./lib/fake_target")

t.describe("Virtual Monitors shared presentations", function()
	t.it("crossfades tabs, reclaims an interrupted page, and releases departing owners", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		app.environment:set("reducedMotion", false)
		local selected = Compose.cell("A")
		local builds, alive = { A = 0, B = 0 }, { A = 0, B = 0 }
		local tabs = {}
		for _, name in { "A", "B" } do
			table.insert(tabs, {
				id = name,
				label = name,
				content = function()
					builds[name] += 1
					alive[name] += 1
					Compose.cleanup(function()
						alive[name] -= 1
					end)
					return app.controls.Text({ text = name })
				end,
			})
		end
		app.mount(function()
			return app.controls.Screen("S")({
				app.controls.TabView("Tabs")({
					selection = selected,
					tabs = tabs,
					transition = { fade = true },
				}),
			})
		end)
		settle(15)
		selected:set("B")
		settle(3)
		t.expect(alive.A).toBe(1)
		t.expect(alive.B).toBe(1)
		selected:set("A")
		settle(15)
		t.expect(builds.A).toBe(1)
		t.expect(alive.B).toBe(0)
		selected:set("B")
		settle(15)
		t.expect(alive.A).toBe(0)
		t.expect(alive.B).toBe(1)
		app.dispose()
		t.expect(alive.B).toBe(0)
	end)
	t.it("reflows the avatar split layout without replacing its controls or selection", function()
		local palette = Compose.cell("sage")
		local package = require("../examples/virtual_monitors/theme").create(Facet, "Avatar")
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 1100 }, package.metrics)
		local apps = screens.create(Facet, app, { avatarPalette = palette, spatial = false })
		local _, root = app.mount(function()
			return app.controls.Screen("S")({ apps.Avatar() })
		end)
		settle(3)
		local preview = adapter.node("/S/Avatar/Content/Workspace/Preview")
		local workspace = adapter.node("/S/Avatar/Content/Workspace")
		local function find(node)
			if node.id == "Workspace" then
				return node
			end
			for _, child in node.children do
				local found = find(child)
				if found then
					return found
				end
			end
			return nil
		end
		local layout = assert(find(root))
		t.expect(layout.props.axis).toBe("x")
		palette:set("iris")
		app.environment:set("viewportRect", { x = 0, y = 0, w = 740, h = 1100 })
		settle(3)
		t.expect(adapter.node("/S/Avatar/Content/Workspace")).toBe(workspace)
		t.expect(layout.props.axis).toBe("y")
		t.expect(adapter.node("/S/Avatar/Content/Workspace/Preview")).toBe(preview)
		t.expect(palette:peek()).toBe("iris")
		app.dispose()
	end)

	-- Phone rows carry touch facts and device insets, so the adaptive tab bar
	-- takes its real home beneath the page.
	local avatarViews = {
		{ w = 393, h = 852, touch = true, insets = { top = 58, bottom = 34, left = 0, right = 0 }, scrolls = true },
		{ w = 852, h = 393, touch = true, insets = { top = 58, bottom = 21, left = 59, right = 59 }, scrolls = true },
		{ w = 1920, h = 1080, touch = false, scrolls = false },
	}
	for _, view in avatarViews do
		t.it(`keeps every avatar control reachable at {view.w}x{view.h}`, function()
			local package = require("../examples/virtual_monitors/theme").create(Facet, "Avatar")
			local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = view.w, h = view.h }, package.metrics)
			if view.touch then
				app.environment:set("coreSafeInsets", view.insets)
				app.environment:set("displaySize", "Small")
				app.environment:set("preferredInput", "Touch")
				app.environment:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
			end
			local apps = screens.create(Facet, app, { spatial = false })
			local desktop = require("../examples/virtual_monitors/desktop")
			app.mount(desktop.create(Compose, app, apps, Compose.cell("Screen"), Compose.cell("Avatar")))
			settle(5)
			local workspace = "/Desktop/Presentation/Apps/Content/Tab-Avatar/Avatar/Content/Workspace"
			local function overlaps(a, b)
				return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
			end
			local function within(inner, outer)
				return inner.x >= outer.x
					and inner.y >= outer.y
					and inner.x + inner.w <= outer.x + outer.w
					and inner.y + inner.h <= outer.y + outer.h
			end
			local preview = assert(adapter.node(workspace .. "/Preview"), "preview missing").rect
			local scroll = assert(adapter.node(workspace .. "/Settings"), "settings scroller missing").rect
			local region = assert(adapter.scrollRegionOf(workspace .. "/Settings"))
			local page = assert(adapter.node("/Desktop/Presentation/Apps/Content")).rect
			local canvas = { x = scroll.x, y = scroll.y, w = scroll.w, h = math.max(scroll.h, region.contentH) }
			local tabs, controls = {}, {}
			for _, path in adapter.paths() do
				local node = adapter.node(path)
				local interactive = node.class == "Button" or node.class == "Toggle"
				if interactive and path:sub(1, #workspace + 1) == workspace .. "/" then
					controls[path:sub(#workspace + 2)] = node.rect
				elseif interactive and not path:find("/Apps/Content/", 1, true) then
					table.insert(tabs, node.rect)
				end
			end
			t.expect(#tabs).toBe(3)
			for _, name in { "Opt1", "Opt2", "Opt3" } do
				local found = false
				for path in controls do
					found = found or path:sub(-#name) == name
				end
				t.expect(found).toBe(true)
			end
			t.expect(controls["Settings/Panel/Rotate/TurnLeft"] ~= nil).toBe(true)
			t.expect(controls["Settings/Panel/Rotate/TurnRight"] ~= nil).toBe(true)
			t.expect(within(preview, page)).toBe(true)
			t.expect(within(scroll, page)).toBe(true)
			t.expect(overlaps(preview, scroll)).toBe(false)
			t.expect(preview.h >= 120).toBe(true)
			t.expect(region.contentH > scroll.h).toBe(view.scrolls)
			for path, rect in controls do
				t.expect(rect.w > 0 and rect.h > 0).toBe(true)
				-- The scroller clips its canvas, so a control can only paint inside it.
				t.expect(within(rect, canvas)).toBe(true)
				t.expect(overlaps(rect, preview)).toBe(false)
			end
			for _, tab in tabs do
				t.expect(overlaps(tab, preview)).toBe(false)
				t.expect(overlaps(tab, scroll)).toBe(false)
			end
			-- The far end of the canvas scrolls fully into the viewport.
			adapter.driveScroll(workspace .. "/Settings", { x = 0, y = region.contentH })
			settle(3)
			local offset = adapter.scrollPositionOf(workspace .. "/Settings").y
			t.expect(offset).toBe(math.max(0, region.contentH - scroll.h))
			local last = controls["Settings/Panel/Rotate/TurnRight"]
			t.expect(last.y + last.h - offset <= scroll.y + scroll.h).toBe(true)

			local mounted = adapter.node(workspace .. "/Preview")
			app.environment:set("viewportRect", { x = 0, y = 0, w = view.h, h = view.w })
			settle(5)
			t.expect(adapter.node(workspace .. "/Preview")).toBe(mounted)
			app.dispose()
		end)
	end

	t.it("steps the turn increment and drives the Turn buttons by that amount", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 1100 })
		local angle = Compose.cell(0)
		local apps = screens.create(Facet, app, { avatarAngle = angle, spatial = false })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Avatar() })
		end)
		settle(5)
		local turnRight = "/S/Avatar/Content/Workspace/Settings/Panel/Rotate/TurnRight"
		adapter.driveActivate(turnRight)
		settle(3)
		t.expect(angle:peek()).toBe(30)
		adapter.driveActivate("/S/Avatar/Content/Workspace/Settings/Panel/TurnStep/Inc")
		settle(3)
		adapter.driveActivate(turnRight)
		settle(3)
		t.expect(angle:peek()).toBe(75)
		app.dispose()
	end)

	--[[ THE AVATAR SETTINGS PANEL HOLDS ITS OWN CONTROLS AT EVERY PHONE WIDTH.
		The Turn step row is a Stepper: a label, a readout and two 44px targets, and
		it hugs. At a compact width with a large text preference that row was wider
		than the panel and the "+" painted outside it, so the label takes its own
		line there. Swept at the three narrowest phones the showcase runs at, across
		the text preferences a player can choose. ]]
	t.it("holds every Avatar settings control inside the panel at 393, 360 and 320 wide", function()
		local guard = require("./lib/overflow_guard")
		for _, width in { 393, 360, 320 } do
			for _, offset in { 0, 2, 4, 6 } do
				local package = require("../examples/virtual_monitors/theme").create(Facet, "Avatar")
				local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = width, h = 900 }, package.metrics)
				app.environment:set("preferredTextOffset", offset)
				local apps = screens.create(Facet, app, { spatial = false })
				app.mount(function()
					return app.controls.Screen("S")({ apps.Avatar() })
				end)
				settle(4)
				local reported: { string } = {}
				for _, violation in guard.violations(adapter) do
					table.insert(reported, guard.describe(violation))
				end
				t.expect(`{width}w +{offset}: {table.concat(reported, " | ")}`).toBe(`{width}w +{offset}: `)
				-- ...and the Stepper is still THERE to be contained, so the case
				-- cannot pass by the panel having lost its control.
				t.expect(adapter.node("/S/Avatar/Content/Workspace/Settings/Panel/TurnStep/Inc") ~= nil).toBe(true)
				app.dispose()
			end
		end
	end)

	t.it("auto-spins the preview at the chosen speed and holds still under reduced motion", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 1100 })
		app.environment:set("reducedMotion", false)
		local angle, autoSpin = Compose.cell(0), Compose.cell(0)
		local apps = screens.create(Facet, app, { avatarAngle = angle, avatarAutoSpin = autoSpin, spatial = false })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Avatar() })
		end)
		settle(5)
		t.expect(angle:peek()).toBe(0)
		-- Off: the preview holds still.
		settle(10)
		t.expect(angle:peek()).toBe(0)
		-- Slow, then Fast: the angle advances, faster the higher the level.
		autoSpin:set(1)
		settle(10)
		local slowDelta = angle:peek()
		t.expect(slowDelta > 0).toBe(true)
		angle:set(0)
		autoSpin:set(3)
		settle(10)
		local fastDelta = angle:peek()
		t.expect(fastDelta > slowDelta).toBe(true)
		-- Reduced motion holds the angle where it is, even while spinning.
		app.environment:set("reducedMotion", true)
		local held = angle:peek()
		settle(10)
		t.expect(angle:peek()).toBe(held)
		app.dispose()
	end)

	t.it("presents a Look summary sheet with the live palette, hat, rotation, turn step and auto-spin", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 1100 })
		local palette, hat, angle = Compose.cell("clay"), Compose.cell(false), Compose.cell(30)
		local turnStepIndex, autoSpin = Compose.cell(3), Compose.cell(3)
		local apps = screens.create(Facet, app, {
			avatarPalette = palette,
			avatarHat = hat,
			avatarAngle = angle,
			avatarTurnStepIndex = turnStepIndex,
			avatarAutoSpin = autoSpin,
			spatial = false,
		})
		app.mount(function()
			return app.controls.Screen("S")({ apps.Avatar() })
		end)
		settle(5)
		local function texts()
			local found = {}
			for _, path in adapter.paths() do
				local node = adapter.node(path)
				if node.class == "Text" and node.props.text then
					table.insert(found, node.props.text)
				end
			end
			return found
		end
		local function contains(list, value)
			for _, v in list do
				if v == value then
					return true
				end
			end
			return false
		end
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix and adapter.node(path).class == "Button" then
					return path
				end
			end
			return nil
		end
		t.expect(adapter.node("/S/Avatar/Content/Workspace/Settings/Panel/LookSummary")).toBeNil()
		adapter.driveActivate(assert(suffixed("/Summary"), "the panel offers a Summary button"))
		settle(3)
		local shown = texts()
		t.expect(contains(shown, "Clay")).toBe(true)
		t.expect(contains(shown, "Off")).toBe(true)
		t.expect(contains(shown, "30°")).toBe(true)
		t.expect(contains(shown, "Fast")).toBe(true)
		adapter.driveActivate("/LookSummary/Layer/Panel/Body/Content/Done")
		settle(3)
		t.expect(adapter.node("/LookSummary")).toBeNil()
		app.dispose()
	end)

	t.it("opens and collapses the Advanced Tips disclosure without leaving a mounted overlay", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 1100 })
		local expanded = Compose.cell(false)
		local apps = screens.create(Facet, app, { avatarTipsExpanded = expanded, spatial = false })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Avatar() })
		end)
		settle(5)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local function anyShows(content)
			for _, path in adapter.paths() do
				local node = adapter.node(path)
				if node.class == "Text" and node.props.text == content then
					return true
				end
			end
			return false
		end
		local tip = "Turn step sets both the Turn buttons and the Stepper's ladder — drag Rotation for finer control."
		t.expect(anyShows(tip)).toBe(false)
		adapter.driveActivate(assert(suffixed("/Advanced"), "the panel offers the Tips disclosure"))
		settle(3)
		t.expect(expanded:peek()).toBe(true)
		t.expect(anyShows(tip)).toBe(true)
		adapter.driveActivate(assert(suffixed("/Advanced"), "the disclosure collapses from the same trigger"))
		settle(3)
		t.expect(expanded:peek()).toBe(false)
		t.expect(anyShows(tip)).toBe(false)
		app.dispose()
	end)

	t.it("expands the selected card from measured geometry and reverses without a jump", function()
		local app, adapter, advance = require("./lib/native_motion_world")()
		local selected = Compose.cell(nil)
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local apps = screens.create(Facet, app, { catalog = catalog, selectedGame = selected })
		app.mount(apps.Discover)
		advance(0.05)
		local card
		for _, path in adapter.paths() do
			if path:find("/Games/", 1, true) and path:sub(-5) == "/Card" then
				card = adapter.node(path)
				break
			end
		end
		assert(card, "mounted game card missing")
		local cardWidth = card.rect.w
		-- The panel is LAID OUT at its full size; what grows out of the card's
		-- measured rect is the paint, which is what `presentedSize` records.
		local path = "/Discover/Content/Desktop/Expand/then/Details"
		selected:set(catalog.items:peek()[1])
		advance(1 / 60)
		local opening = assert(adapter.node(path))
		local fullWidth = opening.rect.w
		t.expect(fullWidth > cardWidth).toBe(true)
		t.expect(math.abs(opening.presentedSize.w - cardWidth) < 40).toBe(true)
		advance(0.05)
		local openingWidth = adapter.node(path).presentedSize.w
		t.expect(openingWidth > cardWidth).toBe(true)
		t.expect(openingWidth < fullWidth).toBe(true)
		-- reversing mid-flight continues from the painted rect, never a jump
		selected:set(nil)
		local before = adapter.node(path).presentedSize.w
		advance(1 / 60)
		t.expect(math.abs(adapter.node(path).presentedSize.w - before) < 70).toBe(true)
		selected:set(catalog.items:peek()[1])
		advance(1)
		t.expect(adapter.node(path).presentedSize.w).toBe(fullWidth)
		selected:set(nil)
		advance(1)
		t.expect(adapter.node(path)).toBeNil()
		app.environment:set("reducedMotion", true)
		selected:set(catalog.items:peek()[1])
		advance(1 / 60)
		t.expect(adapter.node(path).presentedSize.w).toBe(fullWidth)
		selected:set(nil)
		advance(1 / 60)
		t.expect(adapter.node(path)).toBeNil()
		app.dispose()
		catalog.dispose()
	end)

	t.it("presents and dismisses the About modal from the shell actions", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local apps = screens.create(Facet, app, {})
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(5)
		t.expect(adapter.node("/About")).toBeNil()
		adapter.driveActivate("/S/Discover/Content/Chrome/NavBar/Actions/Row/About")
		settle(3)
		t.expect(adapter.node("/About") ~= nil).toBe(true)
		adapter.driveActivate("/About/Center/Card/Done")
		settle(3)
		t.expect(adapter.node("/About")).toBeNil()
		app.dispose()
	end)

	t.it("collapses the shell actions into a Menu once the header can't fit the full row", function()
		local toggled = 0
		local narrow, narrowAdapter, narrowSettle = nativeWorld({ x = 0, y = 0, w = 260, h = 640 })
		local narrowApps = screens.create(Facet, narrow, {
			toggleMode = function()
				toggled += 1
			end,
		})
		narrow.mount(function()
			return narrow.controls.Screen("S")({ narrowApps.Discover() })
		end)
		narrowSettle(5)
		local row = "/S/Discover/Content/Chrome/NavBar/Actions/Row"
		local menu = "/S/Discover/Content/Chrome/NavBar/Actions/Compact/Menu"
		t.expect(narrowAdapter.visibleOf(row)).toBe(false)
		t.expect(narrowAdapter.visibleOf(menu)).toBe(true)
		narrowAdapter.driveActivate(menu)
		narrowSettle(3)
		local function suffixed(suffix)
			for _, path in narrowAdapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		narrowAdapter.driveActivate(assert(suffixed("/Item:mode"), "the Menu fallback lists the mode action"))
		narrowSettle(3)
		t.expect(toggled).toBe(1)
		narrow.dispose()

		local wide, wideAdapter, wideSettle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local wideApps = screens.create(Facet, wide, {})
		wide.mount(function()
			return wide.controls.Screen("S")({ wideApps.Discover() })
		end)
		wideSettle(5)
		t.expect(wideAdapter.visibleOf(row)).toBe(true)
		t.expect(wideAdapter.visibleOf(menu)).toBe(false)
		wide.dispose()
	end)

	local function scrollHost(root, id)
		if root.class == "ScrollView" and root.id == id then
			return root
		end
		for _, child in root.children do
			local found = scrollHost(child, id)
			if found then
				return found
			end
		end
		return nil
	end

	t.it("pages the discovery feed as its tail approaches and keeps the mounted window bounded", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local apps = screens.create(Facet, app, { catalog = catalog })
		local _, root = app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local firstPage = #catalog.items:peek()
		local games = assert(scrollHost(root, "Games"))
		local function cards()
			local count = 0
			for _, path in adapter.paths() do
				if path:find("/Games/", 1, true) and path:sub(-4) == "/Hit" then
					count += 1
				end
			end
			return count
		end
		local mounted = cards()
		t.expect(mounted > 0 and mounted < firstPage).toBe(true)
		-- The last cards appear, which asks the feed for its next page.
		adapter.driveScroll(games.path, { x = 0, y = 100000 })
		settle(3)
		catalog.step()
		settle(3)
		t.expect(#catalog.items:peek() > firstPage).toBe(true)
		-- Only data grew: the window is still a screenful.
		t.expect(cards() <= mounted + 12).toBe(true)
		-- A reader in the middle of the feed asks for nothing.
		local grown = #catalog.items:peek()
		adapter.driveScroll(games.path, { x = 0, y = 0 })
		settle(3)
		catalog.step()
		t.expect(#catalog.items:peek()).toBe(grown)
		app.dispose()
		catalog.dispose()
	end)

	t.it("draws a deterministic players-this-week sparkline for the selected game", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local selected = Compose.cell(nil)
		local apps = screens.create(Facet, app, { catalog = catalog, selectedGame = selected })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local function sparkline()
			for _, path in adapter.paths() do
				if path:find("/Sparkline", 1, true) then
					return adapter.node(path)
				end
			end
			return nil
		end
		local first = catalog.items:peek()[1]
		selected:set(first)
		settle(3)
		local points = assert(sparkline()).props.points
		t.expect(#points).toBe(7)
		selected:set(nil)
		settle(3)
		selected:set(first)
		settle(3)
		-- Same game, same trend: no randomness, only `item.index`.
		local repeated = assert(sparkline()).props.points
		for i, point in points do
			t.expect(repeated[i].y).toBe(point.y)
		end
		local second = catalog.items:peek()[2]
		selected:set(second)
		settle(3)
		local other = assert(sparkline()).props.points
		local differs = false
		for i, point in points do
			if other[i].y ~= point.y then
				differs = true
			end
		end
		t.expect(differs).toBe(true)
		app.dispose()
		catalog.dispose()
	end)

	t.it("shows a placeholder creator avatar, then the loaded image, and releases it on selection change", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local selected = Compose.cell(nil)
		local provider
		local apps = screens.create(Facet, app, {
			catalog = catalog,
			selectedGame = selected,
			creatorImagesRef = function(p)
				provider = p
			end,
		})
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		assert(provider, "creator image provider was not handed back through ref")
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local first = catalog.items:peek()[1]
		selected:set(first)
		settle(3)
		t.expect(suffixed("/Avatar/Placeholder/then/Fill") ~= nil).toBe(true)
		t.expect(provider.counters().handles).toBe(1)
		local request = provider.pendingRequests()[1]
		t.expect(request.key).toBe(first.creatorImage)
		t.expect(provider.complete(request.key, request.generation, request.key)).toBe("applied")
		settle(3)
		t.expect(suffixed("/Avatar/Placeholder/then/Fill")).toBe(nil)
		t.expect(adapter.node(suffixed("/Avatar/Content")).props.image).toBe(request.key)
		-- A different game re-leases: the avatar is a fresh, construction-keyed
		-- mount (AsyncImage.key is not reactive), not a live-bound update.
		local second = catalog.items:peek()[2]
		selected:set(second)
		settle(3)
		t.expect(provider.counters().handles).toBe(1)
		local nextRequest = provider.pendingRequests()[1]
		t.expect(nextRequest.key).toBe(second.creatorImage)
		app.dispose()
		t.expect(provider.counters().handles).toBe(0)
		catalog.dispose()
	end)

	t.it("pushes More like this, opens a match, and pops back to the game's own info", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local selected = Compose.cell(nil)
		local apps = screens.create(Facet, app, { catalog = catalog, selectedGame = selected })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local function prefixed(prefix)
			local found = {}
			for _, path in adapter.paths() do
				if path:find(prefix, 1, true) == 1 then
					table.insert(found, path)
				end
			end
			return found
		end
		local first = catalog.items:peek()[1]
		selected:set(first)
		settle(3)
		adapter.driveActivate(assert(suffixed("/MoreLikeThis"), "the info route offers More like this"))
		settle(3)
		local picks = {}
		for _, path in prefixed("/S/Discover") do
			local id = path:match("/Pick%-([^/]+)$")
			if id then
				table.insert(picks, { path = path, id = id })
			end
		end
		t.expect(#picks > 0).toBe(true)
		-- Every listed match shares the selected game's genre and is not itself.
		for _, pick in picks do
			for _, item in catalog.items:peek() do
				if item.id == pick.id then
					t.expect(item.genre).toBe(first.genre)
					t.expect(item.id ~= first.id).toBe(true)
				end
			end
		end
		adapter.driveActivate(picks[1].path)
		settle(3)
		t.expect(selected:peek() ~= nil).toBe(true)
		t.expect(selected:peek().genre).toBe(first.genre)
		t.expect(selected:peek().id ~= first.id).toBe(true)
		-- A fresh selection always opens back on the game's own info, not the list.
		t.expect(suffixed("/MoreLikeThis") ~= nil).toBe(true)
		app.dispose()
		catalog.dispose()
	end)

	t.it("shows a Featured carousel that opens a game, and hides on a short viewport or the Saved shelf", function()
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local firstThree = {}
		for i = 1, 3 do
			table.insert(firstThree, catalog.items:peek()[i])
		end
		local function hasFeatured(adapter)
			for _, item in firstThree do
				for _, path in adapter.paths() do
					if path:sub(-#("/Open-" .. item.id)) == "/Open-" .. item.id then
						return true
					end
				end
			end
			return false
		end
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 1280, h = 800 })
		local selected, shelf = Compose.cell(nil), Compose.cell("browse")
		local apps = screens.create(Facet, app, { catalog = catalog, selectedGame = selected, discoveryShelf = shelf })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		t.expect(hasFeatured(adapter)).toBe(true)
		adapter.driveActivate(
			"/S/Discover/Content/Desktop/Browse/Featured/Pages/" .. firstThree[1].id .. "/Open-" .. firstThree[1].id
		)
		settle(3)
		t.expect(selected:peek() ~= nil).toBe(true)
		t.expect(selected:peek().id).toBe(firstThree[1].id)
		selected:set(nil)
		shelf:set("saved")
		settle(3)
		t.expect(hasFeatured(adapter)).toBe(false)
		shelf:set("browse")
		settle(3)
		t.expect(hasFeatured(adapter)).toBe(true)
		app.environment:set("viewportRect", { x = 0, y = 0, w = 920, h = 260 })
		settle(3)
		t.expect(hasFeatured(adapter)).toBe(false)
		app.dispose()
		catalog.dispose()
	end)

	t.it("saves a game by dragging its card onto the Browse|Saved switch", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local saved = Compose.cell({})
		local apps = screens.create(Facet, app, { catalog = catalog, savedGames = saved })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local cardPath
		local first = catalog.items:peek()[1]
		for _, path in adapter.paths() do
			if path:find(`/[{first.id}]/Cell/Card`, 1, true) and path:sub(-#"/Card") == "/Card" then
				cardPath = path
				break
			end
		end
		local shelfPath
		for _, path in adapter.paths() do
			if path:sub(-#"/Shelf") == "/Shelf" then
				shelfPath = path
				break
			end
		end
		assert(cardPath, "the first game's card is mounted")
		assert(shelfPath, "the Shelf switch is mounted")
		local card = adapter.node(cardPath).rect
		local shelf = adapter.node(shelfPath).rect
		local fromX, fromY = card.x + card.w / 2, card.y + card.h / 2
		local toX, toY = shelf.x + shelf.w / 2, shelf.y + shelf.h / 2
		adapter.driveDragStart(cardPath, { x = fromX, y = fromY })
		adapter.driveDragContinue(cardPath, { x = toX, y = toY }, { x = toX - fromX, y = toY - fromY })
		adapter.driveDragEnd(cardPath, { x = toX, y = toY })
		settle(3)
		t.expect(saved:peek()[first.id]).toBe(true)
		app.dispose()
		catalog.dispose()
	end)

	t.it("filters the feed by genre chip and orders it from the sort menu", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local genre, sort = Compose.cell(nil), Compose.cell("recommended")
		local apps = screens.create(Facet, app, { catalog = catalog, discoveryGenre = genre, discoverySort = sort })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local function firstTitles()
			local titles = {}
			for _, path in adapter.paths() do
				local node = adapter.node(path)
				if path:find("/Games/", 1, true) and path:sub(-6) == "/Title" then
					table.insert(titles, node.props.text)
				end
			end
			return titles
		end
		local racing = assert(suffixed("/Genre-Racing"), "the Racing chip is mounted")
		adapter.driveActivate(racing)
		settle(3)
		t.expect(genre:peek()).toBe("Racing")
		local byTitle = {}
		for _, item in catalog.items:peek() do
			byTitle[item.title] = item
		end
		local shown = firstTitles()
		t.expect(#shown > 0).toBe(true)
		for _, title in shown do
			t.expect(byTitle[title].genre).toBe("Racing")
		end
		-- A second chip replaces the first; the chips stay exclusive.
		adapter.driveActivate(assert(suffixed("/Genre-Building")))
		settle(3)
		t.expect(genre:peek()).toBe("Building")
		adapter.driveActivate(assert(suffixed("/Genre-Building")))
		settle(3)
		t.expect(genre:peek()).toBeNil()
		sort:set("rating")
		settle(3)
		local best = 0
		for _, item in catalog.items:peek() do
			best = math.max(best, item.percent)
		end
		local sorted = {}
		for _, title in firstTitles() do
			sorted[title] = true
		end
		for _, item in catalog.items:peek() do
			if item.percent == best then
				t.expect(sorted[item.title]).toBe(true)
			end
		end
		app.dispose()
		catalog.dispose()
	end)
	t.it("filters the feed by search text, opens the chosen game, and clears back to the full feed", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local genre, sort = Compose.cell("Adventure"), Compose.cell("rating")
		local query, selected = Compose.cell(""), Compose.cell(nil)
		local apps = screens.create(Facet, app, {
			catalog = catalog,
			discoveryGenre = genre,
			discoverySort = sort,
			discoveryQuery = query,
			selectedGame = selected,
		})
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local function titles()
			local list = {}
			for _, path in adapter.paths() do
				if path:find("/Games/", 1, true) and path:sub(-6) == "/Title" then
					table.insert(list, adapter.node(path).props.text)
				end
			end
			return list
		end
		-- Neon Harbor's genre is not Adventure, so composing with the standing
		-- genre chip should empty the feed while the query is active.
		local editor = "/S/Discover/Content/Desktop/Browse/Catalog/Filters/Tools/Search/Row/Editor/Field"
		t.expect(adapter.node(editor) ~= nil).toBe(true)
		adapter.focusText(editor)
		adapter.typeText(editor, "Neon Harbor")
		settle(3)
		t.expect(#titles()).toBe(0)
		-- Clear the standing genre filter; the query composes with an unfiltered feed.
		genre:set(nil)
		settle(3)
		local shown = titles()
		t.expect(#shown > 0).toBe(true)
		for _, title in shown do
			t.expect(title:lower():find("neon harbor", 1, true) ~= nil).toBe(true)
		end
		-- Choosing the exact title commits that option and opens the game.
		adapter.commitText(editor)
		settle(3)
		t.expect(selected:peek() ~= nil).toBe(true)
		t.expect(selected:peek().title).toBe("Neon Harbor")
		-- Clearing the query restores the full feed.
		query:set("")
		settle(3)
		t.expect(#titles() > #shown).toBe(true)
		app.dispose()
		catalog.dispose()
	end)
	t.it("lists saved games in a table and opens one from its row", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local first, second = catalog.items:peek()[1], catalog.items:peek()[2]
		local saved = Compose.cell({ [first.id] = true, [second.id] = true })
		local shelf, selected = Compose.cell("browse"), Compose.cell(nil)
		local apps = screens.create(
			Facet,
			app,
			{ catalog = catalog, savedGames = saved, discoveryShelf = shelf, selectedGame = selected }
		)
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local function texts(under)
			local found = {}
			for _, path in adapter.paths() do
				local node = adapter.node(path)
				if path:find(under, 1, true) and node.class == "Text" and node.props.text then
					found[node.props.text] = path
				end
			end
			return found
		end
		t.expect(next(texts("/Saved/"))).toBeNil()
		shelf:set("saved")
		settle(3)
		local rows = texts("/Saved/")
		t.expect(rows[first.title] ~= nil and rows[second.title] ~= nil).toBe(true)
		t.expect(rows[catalog.items:peek()[3].title]).toBeNil()
		-- Removing a game removes its row.
		saved:set({ [first.id] = true })
		settle(3)
		t.expect(texts("/Saved/")[second.title]).toBeNil()
		app.dispose()
		catalog.dispose()
	end)

	t.it("persists Saved table order across saves and reorders via the table's own move", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local saved, selected, shelf = Compose.cell({}), Compose.cell(nil), Compose.cell("browse")
		local savedOrder = Compose.cell({})
		local tblApi
		local apps = screens.create(Facet, app, {
			catalog = catalog,
			savedGames = saved,
			selectedGame = selected,
			discoveryShelf = shelf,
			savedOrder = savedOrder,
			savedTableRef = function(record)
				tblApi = record.api
			end,
		})
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local g1, g2, g3 = catalog.items:peek()[1], catalog.items:peek()[2], catalog.items:peek()[3]
		local function saveGame(item)
			selected:set(item)
			settle(3)
			adapter.driveActivate(assert(suffixed("/Favorite"), "the detail panel offers Favorite"))
			settle(3)
			selected:set(nil)
			settle(3)
		end
		-- Newly saved games append, in the order they were saved.
		saveGame(g1)
		saveGame(g2)
		saveGame(g3)
		t.expect(savedOrder:peek()).toEqual({ g1.id, g2.id, g3.id })
		shelf:set("saved")
		settle(3)
		t.expect(tblApi ~= nil).toBe(true)
		-- Reordering through the table's own move updates the shared order.
		t.expect(tblApi.moveRow(g3.id, -2)).toBe(true)
		settle(3)
		t.expect(savedOrder:peek()).toEqual({ g3.id, g1.id, g2.id })
		-- The Saved table itself renders in that order.
		local titles = { [g1.title] = true, [g2.title] = true, [g3.title] = true }
		local rows = {}
		for _, path in adapter.paths() do
			local node = adapter.node(path)
			if path:find("/Saved/", 1, true) and node.class == "Text" and titles[node.props.text] then
				table.insert(rows, { y = node.rect.y, text = node.props.text })
			end
		end
		table.sort(rows, function(a, b)
			return a.y < b.y
		end)
		t.expect(#rows).toBe(3)
		t.expect(rows[1].text).toBe(g3.title)
		t.expect(rows[2].text).toBe(g1.title)
		t.expect(rows[3].text).toBe(g2.title)
		-- Dropping a saved game drops its slot too.
		saved:update(function(current)
			local next = table.clone(current)
			next[g1.id] = nil
			return next
		end)
		settle(3)
		t.expect(savedOrder:peek()).toEqual({ g3.id, g2.id })
		app.dispose()
		catalog.dispose()
	end)

	t.it("hosts message row actions and clears the conversation from Send's menu", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local chat = require("../examples/virtual_monitors/chat_model").new(Compose)
		chat.messages:set({
			{ id = 1, role = "user", content = "First question" },
			{ id = 2, role = "assistant", content = "First answer" },
		})
		local apps = screens.create(Facet, app, { chat = chat })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Chat() })
		end)
		settle(6)
		local function find(fragment, suffix)
			for _, path in adapter.paths() do
				if path:find(fragment, 1, true) and path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local function shows(content)
			for _, path in adapter.paths() do
				local node = adapter.node(path)
				if node.class == "Text" and node.props.text == content then
					return true
				end
			end
			return false
		end
		t.expect(shows("First answer")).toBe(true)
		-- Message rows share one hosted action tray; it opens on a swipe or Delete.
		t.expect(find("/History/", "/RowActionsOverlay") ~= nil).toBe(true)
		chat.remove(2)
		settle(6)
		t.expect(shows("First answer")).toBe(false)
		t.expect(shows("First question")).toBe(true)
		-- The Send menu clears what is left.
		adapter.driveActivate(assert(find("/Send/", "/Split/Menu")))
		settle(6)
		local clear = find("/Popup/", "/Item:clear")
		adapter.driveActivate(assert(clear, "the Send menu lists Clear conversation"))
		settle(6)
		t.expect(#chat.messages:peek()).toBe(0)
		app.dispose()
		chat.dispose()
	end)
	t.it("lists Suggest and Clear from the Conversation menu and shows a determinate reply progress", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local chat = require("../examples/virtual_monitors/chat_model").new(Compose)
		local apps = screens.create(Facet, app, { chat = chat })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Chat() })
		end)
		settle(5)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		adapter.driveActivate("/S/Chat/Content/Header/Bar/ConversationMenu")
		settle(3)
		adapter.driveActivate(assert(suffixed("/Item:suggest"), "the menu lists Suggest"))
		settle(3)
		adapter.driveActivate(assert(suffixed("/Item:findGame"), "Suggest lists Find a game"))
		settle(3)
		t.expect(chat.draft:peek()).toBe("What game should I play with friends?")

		-- The reply progress is determinate: it grows with streamed characters.
		chat.draft:set("build me something")
		chat.send()
		settle(1)
		local function fillWidth()
			for _, path in adapter.paths() do
				if path:sub(-#"/ResponseProgress/Bar/Fill") == "/ResponseProgress/Bar/Fill" then
					return adapter.node(path).rect.w
				end
			end
			return nil
		end
		local before = assert(fillWidth())
		for _ = 1, 5 do
			chat.step(0.1)
		end
		settle(1)
		t.expect(assert(fillWidth()) > before).toBe(true)

		-- Clear conversation empties the transcript.
		adapter.driveActivate("/S/Chat/Content/Header/Bar/ConversationMenu")
		settle(3)
		adapter.driveActivate(assert(suffixed("/Item:clear"), "the menu lists Clear conversation"))
		settle(3)
		t.expect(#chat.messages:peek()).toBe(0)
		app.dispose()
		chat.dispose()
	end)

	t.it("follows a streaming chat reply at the tail and leaves a reader who scrolled away alone", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local chat = require("../examples/virtual_monitors/chat_model").new(Compose)
		local history = {}
		for index = 1, 24 do
			table.insert(history, {
				id = index,
				role = if index % 2 == 0 then "assistant" else "user",
				content = `Message {index}: retained conversation history.`,
			})
		end
		chat.messages:set(history)
		local apps = screens.create(Facet, app, { chat = chat })
		local _, root = app.mount(function()
			return app.controls.Screen("S")({ apps.Chat() })
		end)
		settle(6)
		local feed = assert(scrollHost(root, "History"))
		local function offset()
			return adapter.scrollPositionOf(feed.path).y
		end
		local function append(id, content)
			local nextMessages = table.clone(chat.messages:peek())
			table.insert(nextMessages, { id = id, role = "assistant", content = content })
			chat.messages:set(nextMessages)
			settle(6)
		end
		-- The transcript opens on its newest message.
		local tail = offset()
		t.expect(tail > 0).toBe(true)
		append(25, "A streamed reply.")
		local followed = offset()
		t.expect(followed > tail).toBe(true)
		-- The reply grows in place: the tail stays in view.
		local streaming = table.clone(chat.messages:peek())
		streaming[25] = {
			id = 25,
			role = "assistant",
			content = string.rep("A streamed reply that keeps growing. ", 12),
		}
		chat.messages:set(streaming)
		settle(6)
		t.expect(offset() > followed).toBe(true)
		-- A reader who scrolled up keeps their place.
		adapter.driveScroll(feed.path, { x = 0, y = 120 })
		settle(3)
		append(26, "Another reply.")
		t.expect(offset()).toBe(120)
		app.dispose()
		chat.dispose()
	end)

	for _, application in { "Discover", "Chat" } do
		for _, screenWidth in { 640, 1280, 1920 } do
			t.it(`preserves {application} scrolling across presentations at width {screenWidth}`, function()
				local mode = Compose.cell("Spatial")
				local position = Compose.cell(0)
				local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
				local chat = require("../examples/virtual_monitors/chat_model").new(Compose)
				local history = {}
				for index = 1, 24 do
					table.insert(history, {
						id = index,
						role = if index % 2 == 0 then "assistant" else "user",
						content = `Message {index}: retained conversation history.`,
					})
				end
				chat.messages:set(history)
				local function create(presentation)
					local package = require("../examples/virtual_monitors/theme").create(Facet, application)
					local app, adapter, settle = nativeWorld({
						x = 0,
						y = 0,
						w = if presentation == "Screen" then screenWidth else 920,
						h = if presentation == "Screen" then 900 else 640,
					}, package.metrics)
					local apps = screens.create(Facet, app, {
						catalog = catalog,
						chat = chat,
						discoveryScroll = if application == "Discover" then position else Compose.cell(0),
						chatScroll = if application == "Chat" then position else Compose.cell(0),
						scrollActive = function(use)
							return use(mode) == presentation
						end,
					})
					local tab = Compose.cell(application)
					local page = if presentation == "Screen"
						then require("../examples/virtual_monitors/desktop").create(Compose, app, apps, mode, tab)
						else apps[application]
					local _, root = app.mount(if presentation == "Screen"
						then page
						else function()
							return app.controls.Screen("S")({ page() })
						end)
					settle(3)
					local function find(node)
						if
							node.class == "ScrollView"
							and node.id == (if application == "Discover" then "Games" else "History")
						then
							return node.path
						end
						for _, child in node.children do
							local result = find(child)
							if result then
								return result
							end
						end
						return nil
					end
					return { app = app, adapter = adapter, settle = settle },
						function()
							return assert(find(root))
						end,
						tab
				end
				local spatial, spatialPath = create("Spatial")
				local flat, flatPath, tab = create("Screen")

				spatial.adapter.driveScroll(spatialPath(), { x = 0, y = 420 })
				spatial.settle(3)
				t.expect(position:peek()).toBe(420)
				mode:set("Screen")
				spatial.settle(3)
				flat.settle(3)
				t.expect(flat.adapter.scrollPositionOf(flatPath()).y).toBe(420)
				flat.adapter.driveScroll(flatPath(), { x = 0, y = 660 })
				flat.settle(3)
				t.expect(position:peek()).toBe(660)
				-- The desktop uses lazy tabs, so leaving and returning recreates the
				-- page's scroll host. The offset belongs to the application model.
				tab:set(if application == "Discover" then "Chat" else "Discover")
				flat.settle(3)
				tab:set(application)
				flat.settle(3)
				t.expect(flat.adapter.scrollPositionOf(flatPath()).y).toBe(660)
				mode:set("Spatial")
				flat.settle(3)
				spatial.settle(3)
				t.expect(spatial.adapter.scrollPositionOf(spatialPath()).y).toBe(660)
				spatial.app.dispose()
				flat.app.dispose()
				chat.dispose()
				catalog.dispose()
			end)
		end
	end

	--[[ THE TEN-FOOT ARROW BUG (2026-09-20). On a Large display in Screen mode the
		adaptable tab strip answered the first arrow and then stopped: activating a
		tab mounted the Chat page, whose coach mark (`UI.Callout`) is a presented
		surface, and a presented surface's scope owned navigation just by being on
		top. One focusable on the plate, no arrow back to the strip it was pointing
		at, and on a pad there is no other route. The mark is CHROME now
		(`present/callout_queue`, `focus/focus_graph.navigationOwner`): still one
		arrow away, no longer a dead end. ]]
	t.it("the ten-foot tab strip keeps answering arrows after a tab with a coach mark opens", function()
		local adapter, frame, system = fake_target.new(), nil, nil
		adapter.scrollBarThickness = fake_target.SCROLL_BAR_RESERVE
		local app = Facet.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core)
				system = Facet.newActionSystem(core)
				return system
			end,
			bindEnv = function(env)
				env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
				env:set("reducedMotion", true)
				env:set("displaySize", "Large")
				env:set("preferredInput", "Keyboard")
				env:set("capabilities", { touch = false, mouse = true, keyboard = true, gamepad = true })
				return function() end
			end,
			connectFrame = function(fn)
				frame = fn
				return function() end
			end,
		})
		local function settle(n: number?)
			for _ = 1, n or 3 do
				frame(1 / 60)
			end
		end
		local apps = screens.create(Facet, app, { spatial = false })
		local tab = Compose.cell("Avatar")
		app.mount(
			require("../examples/virtual_monitors/desktop").create(Compose, app, apps, Compose.cell("Screen"), tab)
		)
		settle(6)
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			settle(4)
			return tostring(app.presenter.focus.focused:peek())
		end
		local STRIP =
			"/Desktop/Presentation/Apps/RailHome/then/NavigationHome/NavigationCenter/AdaptableBar/StripScroll/Strip/Indicator/Options/"
		t.expect(tostring(app.presenter.focus.focused:peek())).toBe(STRIP .. "Opt1")
		t.expect(press("Right")).toBe(STRIP .. "Opt2")
		t.expect(press("Right")).toBe(STRIP .. "Opt3")
		-- ...activate the third tab, which is the one whose page raises a coach mark
		t.expect(press("Return")).toBe(STRIP .. "Opt3")
		t.expect(tab:peek()).toBe("Chat")
		-- THE BUG: every press from here on left focus exactly where the mark put it
		t.expect(press("Left")).toBe(STRIP .. "Opt2")
		t.expect(press("Left")).toBe(STRIP .. "Opt1")
		t.expect(press("Right")).toBe(STRIP .. "Opt2")
		app.dispose()
	end)

	t.it("opens the Avatar's Quick palette radial menu and sets the shared palette", function()
		local package = require("../examples/virtual_monitors/theme").create(Facet, "Avatar")
		-- The eager preview-measurement path needs a RESOLVED snapshot (`.type`
		-- present), exactly as `tests/native_radial_menu.spec.luau` supplies it —
		-- a raw, authored `package.metrics` has no `.type` table.
		local metrics = Facet.themes.resolve(package, nil, {})
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 1100 }, metrics)
		local palette = Compose.cell("sage")
		local apps = screens.create(Facet, app, { avatarPalette = palette, spatial = false })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Avatar() })
		end)
		settle(5)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		adapter.driveActivate(assert(suffixed("/Launcher"), "the Quick palette launcher is reachable"))
		settle(5)
		local clay
		for _, path in adapter.paths() do
			if path:find("clay", 1, true) and path:sub(-5) == "/Item" then
				clay = path
				break
			end
		end
		assert(clay, "missing clay item in " .. table.concat(adapter.paths(), ","))
		adapter.driveActivate(clay)
		settle(5)
		t.expect(palette:peek()).toBe("clay")
		app.dispose()
	end)

	--[[ THE SAME AFFORDANCE ON A PHONE (2026-09-20). The Quick palette used to be
		hidden below 640px because the radial's LIST form — what a radial falls back
		to when there is no room for a ring — subtracted its launcher gap from the
		box it was given whether or not the box had it. Opened from a 152x33 inline
		launcher, that asked for a list 44px down a 33px area: a 1px scroller hanging
		12px below its own parent. This is the width that found it. ]]
	t.it("the Quick palette's list form stays inside its own box on a 393px phone", function()
		local package = require("../examples/virtual_monitors/theme").create(Facet, "Avatar")
		local metrics = Facet.themes.resolve(package, nil, {})
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 393, h = 852 }, metrics)
		local palette = Compose.cell("sage")
		local apps = screens.create(Facet, app, { avatarPalette = palette, spatial = false })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Avatar() })
		end)
		settle(5)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		-- the affordance is OFFERED at this width: the gate is gone
		local launcher = assert(suffixed("/Launcher"), "the Quick palette launcher is reachable at 393px")
		adapter.driveActivate(launcher)
		settle(8)
		local listPath = assert(suffixed("/ListArea/Content/List"), "the radial fell back to its list form")
		local areaPath = assert(suffixed("/Presentation/Yes/then/ListArea"), "the list form has an area")
		local list, area = adapter.node(listPath).rect, adapter.node(areaPath).rect
		t.expect(`the list starts inside its area: {list.y >= area.y}`).toBe("the list starts inside its area: true")
		t.expect(`the list ends inside its area: {list.y + list.h <= area.y + area.h}`)
			.toBe("the list ends inside its area: true")
		-- ...and it is a usable list, not a one-pixel sliver
		t.expect(`the list has the room its area has: {list.h == area.h}`)
			.toBe(`the list has the room its area has: true`)
		local clay
		for _, path in adapter.paths() do
			if path:find("clay", 1, true) and path:sub(-5) == "/Item" then
				clay = path
				break
			end
		end
		adapter.driveActivate(assert(clay, "the palette's rows are reachable"))
		settle(5)
		t.expect(palette:peek()).toBe("clay")
		app.dispose()
	end)

	t.it("saves a game from More like this via its RowActions Save action", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local selected, saved = Compose.cell(nil), Compose.cell({})
		local apps = screens.create(Facet, app, { catalog = catalog, selectedGame = selected, savedGames = saved })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local first = catalog.items:peek()[1]
		selected:set(first)
		settle(3)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		adapter.driveActivate(assert(suffixed("/MoreLikeThis")))
		settle(3)
		local matchId
		for _, path in adapter.paths() do
			local id = path:match("/Pick%-([^/]+)$")
			if id then
				matchId = id
				break
			end
		end
		assert(matchId, "no match row found")
		local hit
		for _, path in adapter.paths() do
			if path:find("/Row%-" .. matchId .. "/Content/Hit$") then
				hit = path
				break
			end
		end
		assert(hit, "missing the row's Hit surface in " .. table.concat(adapter.paths(), ","))
		-- A full leftward swipe commits the trailing tray's first (non-
		-- destructive) action immediately and springs the row back closed.
		local function fullSwipeLeft()
			adapter.pointerDown(hit, 300, 20, "mouse")
			adapter.pointerMove(150, 20)
			adapter.pointerMove(-400, 20)
			adapter.pointerUp(-400, 20)
			settle(6)
		end
		t.expect(saved:peek()[matchId]).toBeNil()
		fullSwipeLeft()
		t.expect(saved:peek()[matchId]).toBe(true)
		fullSwipeLeft()
		t.expect(saved:peek()[matchId]).toBe(false)
		app.dispose()
		catalog.dispose()
	end)

	t.it("opens an About this rating popover anchored to the rating line and dismisses on an outside tap", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local selected = Compose.cell(nil)
		local apps = screens.create(Facet, app, { catalog = catalog, selectedGame = selected })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		selected:set(catalog.items:peek()[1])
		settle(3)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local function hasPanel()
			return suffixed("/RatingInfo/Layer/Surface") ~= nil
		end
		t.expect(hasPanel()).toBe(false)
		adapter.driveActivate(assert(suffixed("/RatingRow/RatingInfo")))
		settle(3)
		t.expect(hasPanel()).toBe(true)
		adapter.tap(app.presenter.topScrimPath(), { x = 4, y = 4 })
		settle(3)
		t.expect(hasPanel()).toBe(false)
		app.dispose()
		catalog.dispose()
	end)

	t.it("shows a quiet placeholder when a game's Stage content fails, leaving the rest of the page working", function()
		-- Tall enough for the Featured carousel's own Art Stage to be reachable too.
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 1280, h = 800 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local selected = Compose.cell(nil)
		local apps = screens.create(Facet, app, {
			catalog = catalog,
			selectedGame = selected,
			gameContent = function()
				error("scene failed to build")
			end,
		})
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local function suffixed(suffix)
			local found = {}
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					table.insert(found, path)
				end
			end
			return found
		end
		-- Every grid card's WorldSlice quarantines the failing builder instead of
		-- taking the catalog down: the placeholder mounts, and the cards' own
		-- titles are still reachable.
		t.expect(#suffixed("/WorldSlice") > 0).toBe(true)
		t.expect(#suffixed("/Title") > 0).toBe(true)
		local first = catalog.items:peek()[1]
		selected:set(first)
		settle(3)
		t.expect(#suffixed("/Art") > 0).toBe(true)
		t.expect(#suffixed("/World") > 0).toBe(true)
		-- The rest of the page still works: Favorite is reachable and functions.
		t.expect(suffixed("/Favorite")[1] ~= nil).toBe(true)
		app.dispose()
		catalog.dispose()
	end)

	t.it("lands the Label, styleGroup, padding and containerRelativeFrame props on their nodes", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 1100 })
		local apps = screens.create(Facet, app, { spatial = false })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Avatar() })
		end)
		settle(3)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local heading = assert(suffixed("/Panel/Heading"), "Explorer label missing")
		t.expect(adapter.node(heading .. "/Title").props.text).toBe("Explorer")
		app.dispose()
	end)

	t.it("lands the styleGroup stroke on the genre chips and the More like this Label", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local selected = Compose.cell(nil)
		local apps = screens.create(Facet, app, { catalog = catalog, selectedGame = selected })
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local firstGenre = require("../examples/virtual_monitors/catalog").genres[1]
		local chip = assert(suffixed("/Genre-" .. firstGenre), "genre chip missing")
		t.expect(adapter.node(chip).props.stroke ~= nil).toBe(true)
		selected:set(catalog.items:peek()[1])
		settle(3)
		adapter.driveActivate(assert(suffixed("/MoreLikeThis")))
		settle(3)
		local heading = assert(suffixed("/Similar/Heading"), "More like this label missing")
		t.expect(adapter.node(heading .. "/Title").props.text).toBe("More like this")
		app.dispose()
		catalog.dispose()
	end)

	t.it("degrades the Avatar preview HUD's regions under space pressure and expands a reduced one", function()
		local package = require("../examples/virtual_monitors/theme").create(Facet, "Avatar")
		local wide, wideAdapter, wideSettle = nativeWorld({ x = 0, y = 0, w = 1920, h = 1080 }, package.metrics)
		local wideApps = screens.create(Facet, wide, { spatial = false })
		wide.mount(function()
			return wide.controls.Screen("S")({ wideApps.Avatar() })
		end)
		wideSettle(5)
		-- 1920x1080: plenty of room, so every region's RICHEST form is standing.
		for _, id in { "Look", "Rotation", "Spin" } do
			local rich = wideAdapter.node(`/S/Avatar/PreviewHud/{id}/{id}Rich`)
			t.expect(rich and rich.rect.w > 0 and rich.rect.h > 0).toBe(true)
		end
		wide.dispose()

		local narrow, adapter, settle = nativeWorld({ x = 0, y = 0, w = 393, h = 852 }, package.metrics)
		local apps = screens.create(Facet, narrow, { spatial = false })
		narrow.mount(function()
			return narrow.controls.Screen("S")({ apps.Avatar() })
		end)
		settle(5)
		-- 393x852: at least one region has stepped down to a reduced form.
		local reduced = adapter.node("/S/Avatar/PreviewHud/Look/LookRich")
		t.expect(reduced == nil or reduced.rect.w == 0).toBe(true)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local function hasPlate()
			return suffixed("ExpandSheet:Look/Layer/ExpandSheet/ExpandSheetPlate") ~= nil
		end
		t.expect(hasPlate()).toBe(false)
		adapter.driveActivate(assert(suffixed("/PreviewHud/Look/Expand"), "Look's Expand affordance missing"))
		settle(3)
		t.expect(hasPlate()).toBe(true)
		local plateValue = suffixed("ExpandSheetPlate/LookRich/LookRichValue")
		t.expect(plateValue ~= nil).toBe(true)
		t.expect(adapter.node(assert(plateValue)).props.text).toBe("Sage · Hat on")
		adapter.tap(narrow.presenter.topScrimPath(), { x = 4, y = 4 })
		settle(3)
		t.expect(hasPlate()).toBe(false)
		narrow.dispose()
	end)

	t.it("hosts a UI.Foreign shimmer over the creator avatar while it loads, gone once the image resolves", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local selected = Compose.cell(nil)
		local provider
		local apps = screens.create(Facet, app, {
			catalog = catalog,
			selectedGame = selected,
			creatorImagesRef = function(p)
				provider = p
			end,
		})
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local first = catalog.items:peek()[1]
		selected:set(first)
		settle(3)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		-- Pending: the Foreign shimmer host is mounted at the avatar's own slot.
		local shimmerPath = suffixed("/AvatarSlot/Shimmer-" .. first.id)
		t.expect(shimmerPath ~= nil).toBe(true)
		t.expect(adapter.node(assert(shimmerPath)).class).toBe("Foreign")
		local request = provider.pendingRequests()[1]
		t.expect(provider.complete(request.key, request.generation, request.key)).toBe("applied")
		settle(3)
		-- Resolved: the shimmer is gone and the image's own Content shows.
		t.expect(suffixed("/AvatarSlot/Shimmer-" .. first.id)).toBe(nil)
		t.expect(adapter.node(assert(suffixed("/AvatarSlot/Avatar/Content"))).props.image).toBe(request.key)
		app.dispose()
		catalog.dispose()
	end)

	t.it("edits a Saved row's Note inline through UI.TextField, surviving a shelf switch", function()
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 920, h = 640 })
		local catalog = require("../examples/virtual_monitors/catalog").new(Compose)
		local saved, selected, shelf = Compose.cell({}), Compose.cell(nil), Compose.cell("browse")
		local savedNotes = Compose.cell({})
		local apps = screens.create(Facet, app, {
			catalog = catalog,
			savedGames = saved,
			selectedGame = selected,
			discoveryShelf = shelf,
			savedNotes = savedNotes,
		})
		app.mount(function()
			return app.controls.Screen("S")({ apps.Discover() })
		end)
		settle(3)
		local function suffixed(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					return path
				end
			end
			return nil
		end
		local game = catalog.items:peek()[1]
		selected:set(game)
		settle(3)
		adapter.driveActivate(assert(suffixed("/Favorite"), "the detail panel offers Favorite"))
		settle(3)
		selected:set(nil)
		shelf:set("saved")
		settle(3)
		local notePath = assert(suffixed("/Note"), "Saved row's Note field missing")
		t.expect(adapter.node(notePath).props.placeholder).toBe("Add a note")
		adapter.focusText(notePath)
		adapter.typeText(notePath, "Fun with friends")
		adapter.commitText(notePath)
		settle(3)
		t.expect(savedNotes:peek()[game.id]).toBe("Fun with friends")
		-- Switch shelf away and back: the note is still shown, read from the
		-- shared cell rather than row-local state that a remount would lose.
		shelf:set("browse")
		settle(3)
		shelf:set("saved")
		settle(3)
		t.expect(adapter.node(assert(suffixed("/Note"))).props.text).toBe("Fun with friends")
		app.dispose()
		catalog.dispose()
	end)
end)
