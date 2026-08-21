--!strict
-- Reference proof "Cartwheel" (RA-P2, reference-app-validation).
--
-- A clean-room Facet reinterpretation of the BEHAVIOR of a dashboard-shaped
-- operations app: adaptive split navigation, a four-card dashboard, an orders
-- table that becomes a sectioned list, a status machine with a countdown that
-- survives navigation, a completion celebration, a gallery and a live editor,
-- charts, an entitlement gate, a locked history chart, and a sign-up form.
-- Built to `artifacts/swiftui-reference-app-validation/specs/p2-cartwheel.md`.
--
-- WHAT THIS FILE OWNS: wiring. The domain lives in `services/`, the copy in
-- `content/`, and every screen in `screens/`. What is assembled here is the
-- part that has to be in one place — the state signals every screen reads, the
-- ACTIONS that are the only way to change them, and the command lifecycle.
--
-- IT PRESENTS ITSELF. `build` returns a `handle`, which the runner and the test
-- harness both honour (`if screen ~= nil and handle == nil then present`), for
-- one concrete reason: `UI.Stage`'s content seam is reached through
-- `handle.controller`, and the Plaza hero has to know whether the seam answered
-- so it can paint its declared fallback plate when it did not.
local art = require("@self/content/art")
local data = require("@self/content/data")
local metrics = require("@self/content/metrics")
local strings = require("@self/content/strings")

local ambientService = require("@self/services/ambient_service")
local clockLib = require("@self/services/clock")
local commandsLib = require("@self/services/commands")
local entitlementService = require("@self/services/entitlement_service")
local identityService = require("@self/services/identity_service")
local orderService = require("@self/services/order_service")
local statsService = require("@self/services/stats_service")

local brewDetailScreen = require("@self/screens/brew_detail")
local brewsScreen = require("@self/screens/brews")
local celebrationScreen = require("@self/screens/celebration")
local chatterScreen = require("@self/screens/chatter")
local dashboardScreen = require("@self/screens/dashboard")
local galleryScreen = require("@self/screens/gallery")
local ledgerScreen = require("@self/screens/ledger")
local plazaScreen = require("@self/screens/plaza")
local shellScreen = require("@self/screens/shell")
local signupScreen = require("@self/screens/signup")
local topfiveScreen = require("@self/screens/topfive")
local workbenchScreen = require("@self/screens/workbench")

local Cartwheel = {}

local DEFAULT_SEED = 20260808
-- A `UI.When` contributes its own path segment AND a `then` segment for the
-- mounted branch, so every gated node reads `<WhenId>/then/<child>`. The paths
-- below spell that out rather than hiding it: a test that addresses a node is
-- addressing the real tree.
local HOST = "/Cartwheel/Shell/Detail/Lane/Body/then/Host"
local DETAIL = HOST .. "/Sections"
local BREWS_STACK = DETAIL .. "/BrewsWhen/then/BrewsSection/BrewsStack"

-- the paths a test, a scenario step or a device pass addresses. One table, so a
-- structural change is one edit rather than a hunt through string literals.
local PATHS = {
	screen = "/Cartwheel",
	shell = "/Cartwheel/Shell",
	sidebar = "/Cartwheel/Shell/Sidebar",
	sidebarFull = "/Cartwheel/Shell/Sidebar/Full/Body/then/List/Rows",
	sidebarRail = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows",
	detail = "/Cartwheel/Shell/Detail",
	sections = DETAIL,
	back = HOST .. "/HeaderWhen/then/Header/Back",
	cart = DETAIL .. "/CartWhen/then/CartSection/Cart",
	brews = BREWS_STACK .. "/ListWhen/then/Brews",
	brewDetail = BREWS_STACK .. "/DetailWhen/then/BrewDetail",
	chatter = DETAIL .. "/ChatterWhen/then/ChatterSection/Chatter",
	ledger = DETAIL .. "/LedgerWhen/then/LedgerSection/Ledger",
	potions = DETAIL .. "/PotionsWhen/then/PotionsSection/Potions",
	workbench = DETAIL .. "/WorkbenchWhen/then/WorkbenchSection/Workbench",
	topfive = DETAIL .. "/TopFiveWhen/then/TopFiveSection/TopFive",
	plaza = DETAIL .. "/PlazaWhen/then/PlazaSection/Plaza",
	stage = DETAIL .. "/PlazaWhen/then/PlazaSection/Plaza/Hero/Stage",
}

-- THE PLAZA DIORAMA, AS DATA. A proof module is engine-free by contract, so the
-- 3D content it owns travels as plain tables and the runner materializes it
-- through `controller.stageHost`. Camera and lighting are KEYED tables (the seam
-- refuses an array); a part's vectors are arrays. An original low-poly plaza:
-- ground, three awnings, the cart, two lanterns, and a bottle stack.
local function block(
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	r: number,
	g: number,
	b: number,
	shape: string?
)
	return {
		shape = shape or "block",
		size = { sx, sy, sz },
		color = { r, g, b },
		cframe = { pos = { x, y, z } },
	}
end

local STAGE_CONTENT = {
	camera = {
		-- a declared, deterministic framing: the orbit is parked here, which is
		-- also the reduced-motion answer
		position = { x = 14, y = 9, z = 16 },
		lookAt = { x = 0, y = 1.5, z = 0 },
		fov = 42,
	},
	lighting = {
		ambient = { r = 0.38, g = 0.36, b = 0.42 },
		lightColor = { r = 0.95, g = 0.9, b = 0.78 },
		lightDirection = { x = -0.4, y = -1, z = -0.3 },
	},
	parts = {
		block(0, -0.5, 0, 22, 1, 22, 0.42, 0.45, 0.4),
		block(-6, 1.5, -3, 5, 3, 5, 0.62, 0.5, 0.36),
		block(-6, 3.4, -3, 6, 0.4, 6, 0.7, 0.36, 0.3),
		block(5, 1.5, -4, 4, 3, 4, 0.58, 0.48, 0.36),
		block(5, 3.4, -4, 5, 0.4, 5, 0.32, 0.44, 0.5),
		block(0, 1.2, 4, 4, 2.4, 2.4, 0.5, 0.34, 0.24),
		block(-1.4, 0.6, 4, 1.2, 1.2, 0.4, 0.24, 0.22, 0.2, "cylinder"),
		block(1.4, 0.6, 4, 1.2, 1.2, 0.4, 0.24, 0.22, 0.2, "cylinder"),
		block(-3, 2.2, 2, 0.3, 4.4, 0.3, 0.3, 0.28, 0.26),
		block(-3, 4.5, 2, 0.8, 0.8, 0.8, 0.98, 0.86, 0.5, "ball"),
		block(3, 2.2, 2, 0.3, 4.4, 0.3, 0.3, 0.28, 0.26),
		block(3, 4.5, 2, 0.8, 0.8, 0.8, 0.98, 0.86, 0.5, "ball"),
		block(0, 2.6, 4, 0.5, 0.5, 0.5, 0.6, 0.82, 0.9, "ball"),
	},
}

function Cartwheel.build(Facet: any, core: any, deps: any): any
	local UI = Facet.UI
	local env = deps.env
	local presenter = deps.presenter
	local scope = core:scope("cartwheel")

	-- ---- locale --------------------------------------------------------------
	-- `ctx.locale` wins, then the env fact; anything that is not a declared
	-- locale falls back to `en` (strings.new does the falling).
	local localeFact = "en"
	if type(deps.locale) == "string" then
		localeFact = deps.locale
	elseif env ~= nil then
		local ok, value = pcall(function()
			return env:get("locale"):get()
		end)
		if ok and type(value) == "string" then
			localeFact = value
		end
	end
	local locale = if string.sub(string.lower(localeFact), 1, 2) == "xa" then "xa" else "en"
	local S = strings.new(locale)

	-- ---- services ------------------------------------------------------------
	local seed: number = if type(deps.seed) == "number" then deps.seed else DEFAULT_SEED
	local clock = clockLib.new(core, { start = 0 })
	local orders = orderService.new({ core = core, clock = clock, seed = seed })
	local stats = statsService.new({ core = core, seed = seed })
	local ambient = ambientService.new({ seed = seed })
	local entitlement = entitlementService.new({ core = core })
	local identity = identityService.new({ core = core })
	local commands = commandsLib.new({
		core = core,
		clock = clock,
		presenter = presenter,
		Facet = Facet,
		strings = S,
		latency = 0.25,
	})

	-- the loop closes here: a collected brew is bottles StatsService counts, so
	-- Top Five and the Ledger reflect what the player just did
	orders.onCompleted(function(brew)
		stats.recordCompletion(brew)
	end)

	-- ---- presentation state --------------------------------------------------
	local conditions = Facet.adaptive.conditions(core, env, { scope = scope })
	-- THE OPENING SECTION IS AN INPUT, and it exists for one measured reason: the
	-- scenario runner materializes `stageContent` ONCE, immediately after
	-- `present`, through `controller.stageHost(path)` — and a Stage inside a
	-- section that is not mounted yet has no host, so the diorama is skipped.
	-- Opening straight on a plaza is how a live pass sees the scene; every
	-- headless run and the default keep the dashboard (`deps.section` absent).
	local section = core:signal(if type(deps.section) == "string" then deps.section else "cart")
	local openBrew = core:signal(0)
	local openPotion = core:signal("")
	local compactOpen = core:signal(false)
	local isTableMode = core:memo(function(use)
		return not use(conditions.isCompact)
	end)
	local reducedMotion = core:memo(function(use)
		return use(env:get("motionPolicy")) == "reduced"
	end)

	local state = {
		section = section,
		openBrew = openBrew,
		openPotion = openPotion,
		compactOpen = compactOpen,
		isCompact = conditions.isCompact,
		sizeClass = conditions.sizeClass,
		isTableMode = isTableMode,
	}

	-- ---- the app context every screen is handed -----------------------------
	local controllerRef: any = nil
	local modalControllerRef: any = nil
	local tickHooks: { (dt: number) -> () } = {}

	local app: any = {
		Facet = Facet,
		UI = UI,
		core = core,
		scope = scope,
		env = env,
		actionSystem = deps.actionSystem,
		presenter = presenter,
		motionClock = presenter.motionClock,
		clock = clock,
		commands = commands,
		S = S,
		art = art,
		metrics = metrics,
		paths = PATHS,
		reducedMotion = reducedMotion,
		state = state,
		services = {
			orders = orders,
			stats = stats,
			ambient = ambient,
			entitlement = entitlement,
			identity = identity,
		},
		screens = {},
		actions = {},
	}

	function app.controller(): any
		return controllerRef
	end
	function app.modalController(): any
		return modalControllerRef
	end
	function app.setModalController(controller: any)
		modalControllerRef = controller
	end
	-- ONE frame source. Every per-frame reader in this proof (the pulse, the
	-- celebration's dip, the stage probe) registers here, and this registers
	-- exactly one presenter hook — a second RunService connection in a consumer
	-- is the bug class the presenter's own tick exists to prevent.
	function app.onTick(fn: (dt: number) -> ())
		table.insert(tickHooks, fn)
	end
	function app.toast(message: string)
		if presenter == nil or presenter.presentToast == nil then
			return
		end
		presenter.presentToast(
			UI.ZStack({
				id = "CartwheelNotice",
				canvasGroup = true,
				children = {
					UI.Box({
						id = "Plate",
						surface = "raised",
						width = { type = "fill", weight = 1 },
						height = { type = "content" },
					}),
					UI.Text({ id = "Body", text = message, textSize = "label", padding = "s" }),
				},
			}),
			{ key = "notice", position = "bottom" }
		)
	end

	-- ---- the actions: the ONLY way state changes ----------------------------

	local screens = app.screens

	-- SELECTION RESETS PUSHED DETAIL (spec §4): changing the section clears that
	-- section's sub-detail, so a sidebar row always lands on a section ROOT.
	function app.actions.selectSection(id: string)
		core:transaction(function()
			section:set(id)
			openBrew:set(0)
			openPotion:set("")
			compactOpen:set(true)
		end)
	end

	function app.actions.openBrew(id: number)
		core:transaction(function()
			section:set("brews")
			openBrew:set(id)
			compactOpen:set(true)
		end)
	end

	function app.actions.openPotion(id: string)
		core:transaction(function()
			section:set("workbench")
			openPotion:set(id)
			compactOpen:set(true)
		end)
	end

	function app.actions.openScratch()
		core:transaction(function()
			section:set("workbench")
			openPotion:set("")
			compactOpen:set(true)
		end)
	end

	function app.actions.openGuildCard()
		if identity.signedIn:get() then
			screens.signup.openSignOut()
		else
			screens.signup.open()
		end
	end

	-- BACK / CANCEL: one verb, one level per press, and a no-op at the root.
	function app.actions.back(): boolean
		if screens.brews ~= nil and screens.brews.handleCancel() then
			return true
		end
		if openBrew:get() ~= 0 then
			openBrew:set(0)
			return true
		end
		if openPotion:get() ~= "" then
			openPotion:set("")
			return true
		end
		if conditions.isCompact:get() and compactOpen:get() then
			compactOpen:set(false)
			return true
		end
		return false
	end

	-- START A BREW: optimistic, then decided, and the countdown fact begins on
	-- the confirming frame.
	function app.actions.startBrew(id: number)
		local before = orders.snapshotOf(id)
		commands.submit({
			id = "brew:" .. tostring(id),
			apply = function()
				orders.applyStart(id)
			end,
			decide = function()
				return orders.canStart(before.status)
			end,
			revert = function()
				orders.restore(id, before.status, before.endsAt, before.startedAt)
			end,
		})
	end

	-- COLLECT: the same command whatever drove it — the detail's primary button,
	-- a row menu, or bulk complete over a selection. The celebration opens for
	-- the FIRST id, on the frame it is confirmed.
	function app.actions.collectBrews(ids: { number })
		for index, id in ids do
			local before = orders.snapshotOf(id)
			commands.submit({
				id = "brew:" .. tostring(id),
				apply = function()
					orders.applyFinish(id)
				end,
				decide = function()
					return orders.canFinish(before.status)
				end,
				revert = function()
					orders.restore(id, before.status, before.endsAt, before.startedAt)
				end,
				confirm = function()
					orders.notifyCompleted(id)
				end,
				after = function(ok: boolean)
					if ok and index == 1 then
						screens.celebration.open(id)
					end
				end,
			})
		end
	end

	-- A PURCHASE-SHAPED COMMAND. Both outcomes are one button apart: the first
	-- attempt on a product declines with copy, the second confirms.
	function app.actions.purchase(product: string, onConfirmed: (() -> ())?)
		commands.submit({
			id = "purchase:" .. product,
			decide = function()
				return entitlement.decide(product)
			end,
			confirm = function()
				entitlement.grant(product)
				if onConfirmed ~= nil then
					onConfirmed()
				end
			end,
		})
	end

	-- ---- the screens ---------------------------------------------------------

	screens.dashboard = dashboardScreen.new(app)
	screens.brews = brewsScreen.new(app)
	screens.brewDetail = brewDetailScreen.new(app)
	screens.gallery = galleryScreen.new(app)
	screens.workbench = workbenchScreen.new(app)
	screens.topfive = topfiveScreen.new(app)
	screens.chatter = chatterScreen.new(app)
	screens.ledger = ledgerScreen.new(app)
	screens.plaza = plazaScreen.new(app)
	screens.celebration = celebrationScreen.new(app)
	screens.signup = signupScreen.new(app)
	local shell = shellScreen.new(app)
	screens.shell = shell

	-- ---- present -------------------------------------------------------------

	local handle = presenter.present(shell.screen, {
		keyboardNavigation = true,
		cancelPolicy = "none",
		initialFocus = "first",
	})
	controllerRef = handle.controller

	local unbindTick = presenter.onTick(function(dt: number)
		-- the domain clock advances with presenter time in a live place, and only
		-- through the `advance` step headlessly — so a scripted run is exactly
		-- reproducible and a played one still counts down in real seconds
		clock.advance(dt)
		for _, hook in tickHooks do
			hook(dt)
		end
	end)

	-- ---- the scenario drive surface -----------------------------------------
	-- Every step is a STATE/ACTION driver over the same public API an on-screen
	-- control uses; none of them is a shortcut past a control that exists.

	local steps: { [string]: (any, string?) -> any } = {}

	-- ONE TIME PATH. `presenter.tick(dt)` is what advances the domain clock — the
	-- proof's own tick hook does it — so a step must never also call
	-- `clock.advance`, or scripted time runs at twice the rate a played session
	-- does (found by a countdown that lost ten seconds in five, 2026-08-08).
	local function advanceTime(dt: number)
		presenter.tick(dt)
		presenter.refresh()
	end

	steps.advance = function(_built: any, payload: string?): any
		advanceTime(tonumber(payload or "1") or 1)
		return { now = clock.now(), brews = orders.count() }
	end

	steps.section = function(_built: any, payload: string?): any
		app.actions.selectSection(payload or "cart")
		presenter.refresh()
		return shell.dump()
	end

	steps.back = function(): any
		local consumed = app.actions.back()
		presenter.refresh()
		return { consumed = consumed, shell = shell.dump() }
	end

	steps.open_brew = function(_built: any, payload: string?): any
		local id = tonumber(payload or "") or (orders.brews:get() :: any)[1].id
		app.actions.openBrew(id)
		presenter.refresh()
		return screens.brewDetail.dump()
	end

	steps.advance_status = function(): any
		local id = openBrew:get()
		if id == 0 then
			return { error = "no brew is open" }
		end
		if orders.statusOf(id) == "new" then
			app.actions.startBrew(id)
		else
			app.actions.collectBrews({ id })
		end
		advanceTime(0.3)
		return screens.brewDetail.dump()
	end

	steps.collect_selected = function(): any
		local ids = screens.brews.selectedIds()
		app.actions.collectBrews(ids)
		advanceTime(0.3)
		return { collected = ids, celebration = screens.celebration.dump() }
	end

	steps.dismiss_celebration = function(): any
		screens.celebration.dismiss()
		presenter.refresh()
		return screens.celebration.dump()
	end

	steps.search = function(_built: any, payload: string?): any
		screens.brews.query:set(payload or "")
		presenter.refresh()
		return screens.brews.dump()
	end

	steps.sort = function(_built: any, payload: string?): any
		local column = payload or "status"
		local order = screens.brews.sortOrder:get() :: any
		screens.brews.sortOrder:set({
			column = column,
			ascending = if order.column == column then not order.ascending else true,
		})
		presenter.refresh()
		return screens.brews.dump()
	end

	steps.gallery_sort = function(_built: any, payload: string?): any
		screens.gallery.sortKey:set(payload or "popularity")
		presenter.refresh()
		return screens.gallery.dump()
	end

	steps.gallery_layout = function(_built: any, payload: string?): any
		screens.gallery.layout:set(payload or "icons")
		presenter.refresh()
		return screens.gallery.dump()
	end

	steps.bench_pick = function(_built: any, payload: string?): any
		-- "slot:id", driven through the picker's own `select` verb
		local slot, id = string.match(payload or "", "^(%w+):(.*)$")
		if slot == nil then
			return { error = "expected slot:id" }
		end
		local picker = (screens.workbench.pickers :: any)[slot]
		if picker == nil then
			return { error = "no picker '" .. slot .. "'" }
		end
		picker.api.select(id)
		presenter.refresh()
		return screens.workbench.dump()
	end

	steps.ledger_timeframe = function(_built: any, payload: string?): any
		screens.ledger.timeframe:set(payload or "month")
		presenter.refresh()
		return screens.ledger.dump()
	end

	steps.purchase = function(_built: any, payload: string?): any
		app.actions.purchase(payload or "ledger")
		advanceTime(0.3)
		return { entitlement = entitlement.dump(), ledger = screens.ledger.dump() }
	end

	steps.subscribe_open = function(): any
		screens.chatter.openSubscribe()
		presenter.refresh()
		return screens.chatter.dump()
	end

	steps.guild_open = function(): any
		app.actions.openGuildCard()
		presenter.refresh()
		return screens.signup.dump()
	end

	steps.guild_submit = function(_built: any, payload: string?): any
		if payload ~= nil and payload ~= "" then
			screens.signup.guildName:set(payload)
		end
		if screens.signup.watchword:get() == "" then
			screens.signup.watchword:set("thistle")
		end
		screens.signup.submit()
		advanceTime(0.3)
		return screens.signup.dump()
	end

	steps.stage_probe = function(): any
		return {
			stage = screens.plaza.dump(),
			host = if controllerRef ~= nil and controllerRef.stageHost ~= nil
				then controllerRef.stageHost(PATHS.stage) ~= nil
				else false,
		}
	end

	local function report(): any
		return {
			proof = "p2_cartwheel",
			ledgerRows = { "RA-P2" },
			locale = locale,
			seed = seed,
			now = clock.now(),
			shell = shell.dump(),
			brews = screens.brews.dump(),
			detail = screens.brewDetail.dump(),
			celebration = screens.celebration.dump(),
			gallery = screens.gallery.dump(),
			workbench = screens.workbench.dump(),
			topfive = screens.topfive.dump(),
			chatter = screens.chatter.dump(),
			ledger = screens.ledger.dump(),
			plaza = screens.plaza.dump(),
			guild = screens.signup.dump(),
			orders = orders.dump(),
			stats = stats.dump(),
			ambient = ambient.dump(),
			entitlement = entitlement.dump(),
			commands = commands.dump(),
		}
	end

	local function dispose()
		unbindTick()
		-- UNMOUNT BEFORE DISPOSING WHAT THE TREE READS. The surface is dismissed
		-- first so no bound prop is still observing a signal a screen is about to
		-- dispose; the scenario runner also dismisses this handle after calling
		-- us, and `presenter.dismiss` on a handle already off the stack is a
		-- documented no-op, so the pair is safe in either order.
		presenter.dismiss(handle)
		for _, name in
			{
				"signup",
				"celebration",
				"plaza",
				"ledger",
				"chatter",
				"topfive",
				"workbench",
				"gallery",
				"brewDetail",
				"brews",
				"dashboard",
				"shell",
			}
		do
			local screenModule = screens[name]
			if screenModule ~= nil and screenModule.dispose ~= nil then
				screenModule.dispose()
			end
		end
		commands.dispose()
		identity.dispose()
		entitlement.dispose()
		stats.dispose()
		orders.dispose()
		reducedMotion:dispose()
		isTableMode:dispose()
		compactOpen:dispose()
		openPotion:dispose()
		openBrew:dispose()
		section:dispose()
		clock.dispose()
		scope:dispose()
	end

	return {
		screen = shell.screen,
		handle = handle,
		present = { keyboardNavigation = true, cancelPolicy = "none", initialFocus = "first" },
		steps = steps,
		report = report,
		dispose = dispose,
		-- the Plaza hero's engine content, keyed by the Stage node's full path
		stageContent = { [PATHS.stage] = STAGE_CONTENT },
		-- handles the suite and a live pass reach for
		app = app,
		paths = PATHS,
		services = app.services,
		screens = screens,
		clock = clock,
		commands = commands,
		strings = S,
		data = data,
	}
end

return Cartwheel
