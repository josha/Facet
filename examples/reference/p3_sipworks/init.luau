--!strict
-- Reference proof "Sipworks" (RA-P3, reference-app-validation).
--
-- A clean-room Facet reinterpretation of a craft TEA HOUSE: browse house
-- blends, inspect botanicals, order a pour, earn Steam Stamps, unlock the Blend
-- Book. Built to `artifacts/swiftui-reference-app-validation/specs/p3-sipworks.md`;
-- the named approximations in `capability-ledger.md` §A/§D are the ceiling and
-- nothing here claims past them.
--
-- Contract: `build(Facet, core, deps) -> { screen, present, steps, report,
-- dispose }` — the shape the tutorial examples and the gallery scenarios use.
--
-- THIS FILE IS THE ASSEMBLY. The content is in `content/`, the deterministic
-- fake services are in `services/`, the blueprints are in `views/` and
-- `entry_compact.luau`, and every one of them is engine-free: no `os.*`, no
-- `math.random`, no `Instance`, no network — a scenario reset rebuilds from the
-- seed and produces a byte-identical dump.
--
-- HOW THE COMPACT ENTRY IS SELECTED (spec §11). Two ways in, one shell builder:
--   * an initial fact — `deps.entry = "compact-link"` (+ `deps.entryItemId`),
--     also read from `deps.facts` / `deps.flags` under the same two names, so a
--     scenario or the matrix can BOOT straight into the compact link;
--   * a live drive — `steps.enterCompact("<blendId>")` and `steps.enterFull()`,
--     which rebuild the shell in place while every service, favorite, stamp and
--     in-flight order survives.
-- Both paths call the same factories; see `entry_compact.luau`.

local dims = require("@self/content/dims")
local strings = require("@self/content/strings")
local fakeclock = require("@self/services/clock")
local catalogService = require("@self/services/catalog")
local favoritesService = require("@self/services/favorites")
local rewardsService = require("@self/services/rewards")
local unlockService = require("@self/services/recipe_unlock")
local orderService = require("@self/services/order")
local i18nService = require("@self/services/i18n")
local taskService = require("@self/services/task")
local shellView = require("@self/views/shell")
local detailView = require("@self/views/detail")
local bookView = require("@self/views/book")
local rewardsView = require("@self/views/rewards")
local listView = require("@self/views/list")
local entryCompact = require("@self/entry_compact")

local Sipworks = {}
-- THE PLAYER'S NAME FOR THE PLACE, and nothing else. This read "Sipworks
-- (reference proof RA-P3)" while the app was only ever mounted by a validation
-- harness; it is a curated standalone place now, and a stage id is not something
-- a player has any use for.
Sipworks.title = "Sipworks"

local FEEDBACK_LOG_CAP = 48

--[[ THE SEED IS THE DESIGN DECISION (docs/plans/example-games-and-standalones.md,
	"Sipworks: serve a customer and earn a reward").

	`rewards.THRESHOLD` is ten and one confirmed order earns one stamp, so a card
	that starts empty is TEN repetitive orders away from the free pour — and a
	visitor who stops after two never sees the stamp ceremony, the reward or the
	redeem branch, which is the app's best material. The card therefore starts one
	stamp short: a single accepted order completes it, and the whole loop is four
	presses.

	It is a FACT rather than a literal so the suite can pin both halves — the
	seeded start the player gets, and the from-zero accrual arithmetic that seeding
	must not hide. ]]
local START_EARNED = rewardsService.THRESHOLD - 1
-- the batch stepper's range (spec §10). Named, because `min = 1` in a control
-- spec and `min = 1` in a dimension read identically to a lint and only one of
-- them is a layout number.
local BATCH_MIN = 1
local BATCH_MAX = 9

-- entry facts arrive on `deps` directly (a build option), on `deps.facts` (the
-- scenario seam) or on `deps.flags` (the runner's pre-Play attributes). One
-- reader, three spellings, so nothing downstream has to know which one carried it.
local function factOf(deps: any, key: string): any
	if deps == nil then
		return nil
	end
	if deps[key] ~= nil then
		return deps[key]
	end
	if type(deps.facts) == "table" and deps.facts[key] ~= nil then
		return deps.facts[key]
	end
	if type(deps.flags) == "table" and deps.flags[key] ~= nil then
		return deps.flags[key]
	end
	return nil
end

--[[ THE PROOF'S OWN STRUCTURAL NUMBERS (spec §4/§12).

	These lived in `content/metrics.luau` under a comment naming exactly what they
	wanted to be: *"The spec states these as dotted theme-metric names
	(`metrics.sip.rowArt`). They cannot be."* They can now. `themes.declareApp`
	reserves the `app.sip.*` group, so every one of them is a metric NAME at every
	call site — re-resolved on every solve, movable by a package, and carried up
	the ten-foot ladder by the framework.

	THAT LAST HALF IS THE FIX. Exactly ONE of these numbers used to climb the
	ladder: `gatherToggleAt` multiplied the gathered check's column by
	`metricScale` by hand, and its own comment said a name would be better. The row
	thumbnail, the tile art, the card, the header art, the panes and the action
	band stayed where a phone left them, so at three metres a 60px thumbnail sat in
	a row whose every theme-owned neighbour had grown by half. One declaration
	replaces the helper and reaches all of them.

	AND THE TWO THAT ARE NOT LENGTHS SAY SO IN THEIR NAMES. `wispCount` and
	`wispTravelFraction` each end in a segment the ten-foot classification knows is
	not a measure, so a television gets eight wisps drifting 0.16 of the backdrop
	rather than twelve drifting 0.24 — the same open-section vocabulary
	`controls.*` spends.

	DECLARED AT BUILD, BEFORE THE FIRST FORM: a metric name is validated at
	CONSTRUCTION, so the names have to exist before any view builds a blueprint. ]]
local APP_METRICS = {
	-- §4's table, verbatim
	rowArt = 60, -- list-row thumbnail (square)
	tileArt = 96, -- botanical tile art
	cardW = 360, -- botanical card
	cardH = 460,
	headerArtW = 220, -- wide-header image
	headerArtH = 250,
	listPaneMin = 320, -- regular/wide list pane
	listPaneMax = 420,
	seal = 44, -- stamp-seal cell
	sealCompact = 32,
	orderCard = 300, -- order-placed flip disc (1:1)
	ctaBand = 64, -- bottom action band height
	-- ...and its CEILING. A band is a FLOOR, not a fixed height (a theme's
	-- `control` chrome reserves its own content insets, and Fantasy Parchment's
	-- 20px per side left the CTA's label a 12px box at a pinned 64), so the
	-- declaration states a minimum and a cap. Three times the floor, spelled as
	-- its own name because the metric vocabulary sums names and negates them but
	-- does not multiply one — and a cap a theme cannot move is not a theme number.
	ctaBandMax = 192,

	--[[ `headerTextMin` is what makes the wide header candidate LOSE on a phone: a
		`fill` child inside a `ViewThatFits` candidate always fits (the candidate
		takes whatever it is offered), so the wide card states a real width for its
		text column instead. 260 + 220 + two `l` insets measures ~520, which is wider
		than any compact viewport and narrower than a tablet pane. It is a FIXED
		width and not a band on purpose: with a `minMax` the candidate measured its
		height at one width and was arranged at another, and the card ended 96px
		shorter than the text inside it (the solver's overflow diagnostic, desktop). ]]
	headerTextMin = 260,
	--[[ THE ARRANGEMENT FLIP, and why these two numbers are what they are.

		A group's `minWidth` is what makes the sidebar arrangement illegal on a phone
		(rule 2), and the flip therefore lands at `navRailMin + laneGap +
		contentLaneMin`. But a group minWidth is global to the DECLARATION, not to an
		arrangement — so the column fallback is judged against the same numbers, and a
		content minimum wider than the narrowest supported viewport makes even the
		fallback illegal ("no declared arrangement is legal in 320x640", which the
		solver's own diagnostic reported at the first sweep).

		So: `contentLaneMin` stays under the narrowest device row (320) and the rail
		carries the rest of the threshold. 260 + 12 + 300 = 572 — measured, not
		guessed, and close under the framework's own compact/regular boundary. ]]
	contentLaneMin = 300,
	navRailMin = 260,
	-- ...and the rail's CAP. A hug lane is as wide as its content, so at a 1.4x
	-- locale and the largest text preference the rail grew past 400px and squeezed
	-- the two panes beside it until the recipe pane was 114px narrower than its own
	-- row. A rail is a rail: it states its band and the labels adapt inside it.
	navRailMax = 300,
	--[[ THE TWO-PANE THRESHOLD, and why it is not the compact boundary. The list
		pane declares a 320px floor and the detail pane needs a readable column beside
		it, so a two-pane split costs ~640px of CONTENT lane — and in the sidebar
		arrangement the rail has already taken 260 of the window. Below this width the
		section is a single list and the detail is a pushed surface, which is the same
		answer a phone gets. Measured against the solver's own overflow diagnostic at
		600x800 and 640x320, where a split lane overflowed by 28px and 5px. ]]
	twoPaneMin = 900,
	--[[ the gathered check's own column: a `Toggle` draws its label on ONE line, so
		a long localized label ("Gathered: Lemongrass", 1.4x) pushed the recipe row
		92px past its box. The column is capped and the label declares `disclose`,
		which is the framework's own answer for bounded identity text.

		IT USED TO CARRY THE PROOF'S ONE HAND-ROLLED TEN-FOOT TRANSFORM
		(`gatherToggleAt`), because at ten-foot `controls.toggle.trackWidth` and
		`trackInset` grew and the toggle's chrome reserved 108px of a 96px column.
		It is a NAME now, so the ladder reaches it the same way it reaches its
		neighbours — and reaches its neighbours at all. ]]
	gatherToggle = 96,
	--[[ the task strip's trailing progress readout ("9 of 10 stamps"). A floor
		that keeps the count legible and a cap past which it truncates through its
		declared `disclose` — because `lineLimit` caps LINES, never the width a
		text asks for (the same class Glade's supply-row affordance records). At
		320px, the largest text preference and the 1.4x expansion locale the
		readout's natural single-line ask pushed the strip 3px past its box, which
		the solver reported on every solve. ]]
	taskProgressMin = 56,
	taskProgressMax = 140,
	-- the ambient steam backdrop (§12): eight wisps, and how far one drifts
	wispCount = 8,
	wispSize = 18,
	wispTravelFraction = 0.16, -- a fraction of the backdrop's height
}

-- Services and state live under `appOwner`; each presented view lives under its
-- own mount and is released when that mount closes.
local function construct(Facet: any, deps: any, appOwner: any): any
	local host = deps.app
	local UI = host.controls
	local Compose = Facet.Compose
	local function batch(body: () -> ())
		host.runtime:batch(body)
	end
	Facet.themes.declareApp("sip", APP_METRICS)
	local presenter = host.presenter
	local env = host.environment
	local actions = deps.actionSystem
	local adapter = deps.adapter

	local seed = tonumber(factOf(deps, "seed")) or 1
	local startEntry = if factOf(deps, "entry") == "compact-link" then "compact-link" else "full"
	local startItemId = factOf(deps, "entryItemId") or "lantern-oolong"

	-- ---- services ---------------------------------------------------------
	local clock = fakeclock.new(0)
	local catalog = catalogService.new()
	local blendIds: { string } = {}
	for _, blend in catalog.blends do
		table.insert(blendIds, blend.id)
	end
	local favorites = favoritesService.new({ Compose = Compose, batch = batch, seed = seed, ids = blendIds })
	local startEarnedFact = tonumber(factOf(deps, "startEarned"))
	local startEarned = if startEarnedFact ~= nil then math.max(0, math.floor(startEarnedFact)) else START_EARNED
	local startSpent = tonumber(factOf(deps, "startSpent")) or 0
	local rewards =
		rewardsService.new({ Compose = Compose, batch = batch, startEarned = startEarned, startSpent = startSpent })
	local unlock = unlockService.new({ Compose = Compose, batch = batch, clock = clock })
	local order = orderService.new({ Compose = Compose, batch = batch, clock = clock })
	local task = taskService.new({ Compose = Compose, batch = batch, rewards = rewards, order = order })
	local localeFact = if env ~= nil then env:get("locale") else nil
	local i18n = i18nService.new({
		Compose = Compose,
		locale = i18nService.localeOf(if localeFact ~= nil then localeFact:peek() else nil),
	})

	-- ---- semantic state (the shared, server-shaped model) -----------------
	local state = {
		section = Compose.cell("menu"),
		selectedBlendId = Compose.cell(nil :: string?),
		search = Compose.cell(""),
		batch = Compose.cell(1),
		openBotanical = Compose.cell(nil :: string?),
		entry = Compose.cell(startEntry),
		entryItemId = Compose.cell(startItemId),
		sealPops = {} :: { any },
	}

	-- ---- motion -----------------------------------------------------------
	local motionClock = presenter.motionClock
	local cardFlip = motionClock:spring(0, "object")
	local discFlip = motionClock:spring(0, "object")
	Compose.cleanup(function()
		cardFlip:dispose()
		discFlip:dispose()
	end)
	for slot = 1, rewardsService.THRESHOLD do
		local pop = motionClock:spring(1, "reward")
		state.sealPops[slot] = pop
		Compose.cleanup(function()
			pop:dispose()
		end)
	end
	local stampTimeline: any = nil

	-- ---- the app context every view factory is handed ---------------------
	local app: any = {}
	app.UI = UI
	app.Facet = Facet
	app.Compose = Compose
	app.host = host
	app.env = env
	app.presenter = presenter
	app.adapter = adapter
	app.seed = seed
	app.state = state
	app.clock = clock
	app.clockMotion = motionClock
	app.entry = startEntry
	app.services = {
		catalog = catalog,
		favorites = favorites,
		rewards = rewards,
		unlock = unlock,
		order = order,
		i18n = i18n,
		task = task,
	}
	app.cond = Facet.adaptive.conditions(env)
	--[[ AN `app.sip.*` NUMBER, for the four places a Luau NUMBER is what is needed
		rather than a dimension: a comparison, an arithmetic term, a loop bound and a
		spring target. Everywhere else the name is spelled straight into the `px`
		and the framework re-resolves it every solve.

		`use` when there is one, so a reader inside a memo re-derives on a theme swap
		and on a display-class change; a plain read otherwise. The fallback is the
		framework's answer to a snapshot that predates the declaration and never
		fires in practice (`themes.declareApp` runs at the top of `build`) — it is
		here because a metric read that can answer nil is a number that silently
		becomes zero, which is the class this whole channel exists to remove. ]]
	function app.metric(name: string, use: any?): number
		local signal = if env ~= nil then env:get("themeMetrics") else nil
		local snap: any = if signal == nil then nil elseif use ~= nil then use(signal) else signal:peek()
		local sip = if type(snap) == "table" and type(snap.app) == "table" then snap.app.sip else nil
		local value = if type(sip) == "table" then sip[name] else nil
		-- the fallback is the DECLARATION, never a literal beside it: a second copy
		-- of the number is the drift this whole channel exists to remove
		return if type(value) == "number" then value else (APP_METRICS :: any)[name]
	end
	-- "NOT COMPACT", not "isRegular". `isRegular` is the middle class only, so a
	-- desktop (`wide`) reads false on it — the two-pane layout would have been
	-- absent on the widest screen there is. GAP 7b (framework-gaps-phase2 §7)
	-- named the question the shell actually means: `adaptive.conditions` now
	-- owns this memo (scope-owned there, at construction), so there is nothing
	-- left for this file to build or dispose by hand.
	app.notCompact = app.cond.isRegularOrWider
	-- THE TWO-PANE FACT, and it is its own fact rather than a size class. A
	-- sidebar has already taken the rail's width out of the window, so "regular"
	-- is not the same question as "can two panes stand beside each other" — at
	-- 600 and at 640x320 the split overflowed its lane, which the solver's
	-- overflow diagnostic reported before any screenshot could have.
	app.paneSplit = Compose.formula(function(use)
		return use(app.cond.viewportWidth) >= app.metric("twoPaneMin", use)
	end)

	-- A toast owns its body: the component runs inside the toast.
	local function rejectionToast(name: string, textKey: string, key: string)
		local function body()
			return UI.Text(name)({ text = app.text(textKey), surface = "chip", textSize = "body" })
		end
		presenter.presentToast(body, { key = key, duration = 4, position = "bottom" })
	end

	-- A conditional region: `/<id>/then/...` or `/<id>/else/...`.
	function app.when(id: string)
		return function(spec: any)
			return UI.When(id)({
				Compose.show(
					spec.condition,
					function()
						return UI.When("then")({ spec.thenView() })
					end,
					if spec.elseView
						then function()
							return UI.When("else")({ spec.elseView() })
						end
						else nil
				),
			})
		end
	end
	-- A keyed collection: each row lives at `/<id>/[key]/...`.
	function app.forEach(id: string)
		return function(spec: any)
			return UI.ForEach(id)({
				Compose.keyed({
					from = spec.items,
					key = spec.key,
					render = function(item: any, _, key: any)
						local node = spec.row(item:peek())
						node.collectionKey = `[{key}]`
						return node
					end,
				}),
			})
		end
	end
	-- Appends a generated child list to a property table.
	function app.withChildren(props: any, children: { any }): any
		for _, child in children do
			table.insert(props, child)
		end
		return props
	end
	-- Presents a modal component and answers its handle; dismissing the handle
	-- releases the component.
	function app.presentModal(component: () -> any, options: any?): any
		local _, _, handle = host.presentModal(component, options)
		return handle
	end

	-- A value made during a build belongs to that build's owner.
	function app.own(readable: any): any
		return readable
	end

	function app.motionPolicy(): string
		if env == nil then
			return "full"
		end
		return env:get("motionPolicy"):peek()
	end

	-- app.text(key, params?) -> a Readable<string> that re-reads on a locale
	-- flip. `params` may be a table or a `(use) -> table` function, so a
	-- sentence with a live count is still ONE localized template.
	function app.text(key: string, params: any?): any
		return app.own(Compose.formula(function(use)
			local locale = use(i18n.locale)
			local resolved = if type(params) == "function" then params(use) else params
			return i18n.at(locale, key, resolved)
		end))
	end

	-- the section source sets, one memo body for all three
	function app.visibleBlends(use: any, kind: string): { string }
		local query = use(state.search)
		local favoriteSet = use(favorites.set)
		local unlocked = use(unlock.unlocked)
		local locale = use(i18n.locale)
		local function localize(k: string, id: string, text: string): string
			return i18n.nameAt(locale, k, id, text)
		end
		local out: { string } = {}
		for _, blend in catalog.blends do
			local inSection = true
			if kind == "favorites" then
				inSection = favoriteSet[blend.id] == true
			elseif kind == "recipes" then
				-- LOCKED ROWS ARE ABSENT, NOT DISABLED (spec §10)
				inSection = blend.free == true or unlocked
			end
			if inSection and catalog.matches(blend.id, query, localize) then
				table.insert(out, blend.id)
			end
		end
		table.sort(out, function(a: string, b: string): boolean
			return i18n.sortKey(locale, catalog.blend(a).title) < i18n.sortKey(locale, catalog.blend(b).title)
		end)
		return out
	end

	-- the gathered checklist: session-local by design (spec §3), so the signals
	-- live on the app and are cleared when the recipe surface goes away
	local gathered: { [string]: any } = {}
	function app.gatheredSignal(key: string): any
		local hit = gathered[key]
		if hit == nil then
			hit = Compose.cell(false)
			gathered[key] = hit
		end
		return hit
	end
	local function resetGathered()
		for _, signal in gathered do
			signal:set(false)
		end
	end

	-- ---- shared controls: the model owns their values, each build makes the node
	-- true from the first keystroke until the edit commits or cancels
	app.searchEditing = Compose.cell(false)
	function app.searchField(): any
		return UI.TextInput("Search")({
			value = state.search,
			onChange = function()
				app.searchEditing:set(true)
			end,
			onCommit = function()
				app.searchEditing:set(false)
			end,
			onCancel = function()
				app.searchEditing:set(false)
			end,
			placeholder = app.text("search.placeholder"),
			clearButtonMode = "whileEditing",
			env = env,
			actionSystem = actions,
		})
	end
	function app.batchStepper(): any
		return UI.Stepper("Batch")({
			label = "",
			value = state.batch,
			min = BATCH_MIN,
			max = BATCH_MAX,
			step = 1,
			-- INTEGER ONLY, deliberately. `newStepper`'s readout is a memo over the
			-- VALUE, so a formatter that closed over the locale signal would go
			-- stale on a locale flip with nothing to invalidate it (reported as a
			-- framework finding). The localized plural lives beside it on a bound
			-- `UI.Text`, where reactivity is a declared contract.
			format = function(value: number): string
				return tostring(math.floor(value))
			end,
		})
	end

	-- ---- feedback log (evidence, not behavior) -----------------------------
	local feedbackLog: { any } = {}
	local unsubscribeFeedback = presenter.onFeedback(function(event: any)
		table.insert(feedbackLog, { type = event.type, reason = event.reason, path = event.path })
		if #feedbackLog > FEEDBACK_LOG_CAP then
			table.remove(feedbackLog, 1)
		end
	end)

	-- ---- surfaces ---------------------------------------------------------
	local shellHandle: any = nil
	local closeShell: (() -> ())? = nil
	local navigationPath = Compose.cell({})
	local cardHandle: any = nil
	local guardHandle: any = nil
	local placedHandle: any = nil
	local rewardsHandle: any = nil

	local function dismiss(handle: any)
		if handle ~= nil then
			presenter.dismiss(handle)
		end
	end

	local function closeDetailRoute()
		navigationPath:set({})
		resetGathered()
	end

	local function openDetailRoute(kind: string)
		navigationPath:set({
			{ id = if kind == "recipes" then "recipe" else "detail", value = state.selectedBlendId:peek() },
		})
	end

	-- Shared Back/Cancel edits this caller-owned path too. Transient recipe
	-- checkmarks retire on return; selection and service state stay in the model.
	-- Runs `onChange` when `source` changes; the current owner releases it.
	local function observe(source: any, onChange: (any) -> ()): () -> ()
		local first = true
		return Compose.watch(function(use)
			local value = use(source)
			if first then
				first = false
				return
			end
			onChange(value)
		end)
	end
	app.observe = observe
	observe(navigationPath, function(path)
		if #path == 0 then
			resetGathered()
		end
	end)

	-- ---- commands (every on-screen verb lands here) -----------------------
	local commands: any = {}
	app.commands = commands

	-- the seeded reset, forward-declared: "Serve another customer" is an
	-- on-screen verb in the task band, and the band is built long before the
	-- teardown/rebuild pair the reset needs. ONE body serves the button and the
	-- scenario step, so the two can never drift.
	local resetToSeed: () -> ()

	-- ONE authority for "is the detail a pane or a pushed route", and it is the
	-- same memo the shell mounts the pane behind — so a row Activate can never
	-- land in the gap where neither exists.
	local function pushesDetail(): boolean
		return app.paneSplit:peek() ~= true
	end

	function commands.selectSection(section: string)
		if section == "stamps" and not app.cond.isCompact:peek() and app.entry == "full" then
			-- the sidebar POCKET presents the rewards card rather than swapping
			-- the section: on a wide screen the card owns its moment
			commands.openRewards()
			return
		end
		if state.section:peek() == "stamps" and section ~= "stamps" then
			commands.leaveStamps()
		end
		state.section:set(section)
		if section == "stamps" then
			commands.playStampPops()
		end
	end

	function commands.openBlend(blendId: string, kind: string)
		state.selectedBlendId:set(blendId)
		resetGathered()
		state.batch:set(1)
		if pushesDetail() or app.entry == "compact-link" then
			openDetailRoute(kind)
		end
	end

	function commands.closeDetail()
		closeDetailRoute()
	end

	function commands.closeRecipe()
		closeDetailRoute()
	end

	function commands.toggleFavorite(blendId: string)
		favorites.toggle(blendId)
	end

	function commands.acceptSuggestion(botanicalId: string)
		local botanical = catalog.botanical(botanicalId)
		state.search:set(i18n.name("botanical", botanicalId, botanical.name))
	end

	function commands.openBotanical(botanicalId: string)
		local blendId = state.selectedBlendId:peek()
		if blendId == nil then
			return
		end
		if cardHandle ~= nil then
			dismiss(cardHandle)
			cardHandle = nil
		end
		state.openBotanical:set(botanicalId)
		cardFlip:snap(0)
		cardHandle = app.presentModal(function()
			return detailView.botanicalCard(app, blendId, botanicalId, cardFlip)
		end, {
			-- THE DECLARED HERO-CARD APPROXIMATION (ledger §D): the card
			-- MATERIALIZES over a scrim. It does not fly from the tile, and
			-- nothing in this proof calls it a shared-element transition.
			transition = { enter = "materialize" },
			scrim = "scrim",
			outsideTapCancel = true,
			initialFocus = { id = "CardClose" },
			keyboardNavigation = true,
		})
	end

	function commands.closeBotanical()
		if cardHandle ~= nil then
			dismiss(cardHandle)
			cardHandle = nil
		end
		state.openBotanical:set(nil)
		cardFlip:snap(0)
	end

	function commands.flipCard(toBack: boolean)
		cardFlip:setTarget(if toBack then 1 else 0)
	end

	-- Cancel on the card: the facts face flips back FIRST, a second Cancel
	-- dismisses (spec §14). Exposed so the scenario can drive the same rule.
	function commands.cancelCard(): boolean
		if cardHandle == nil then
			return false
		end
		if cardFlip:getTarget() >= 0.5 then
			commands.flipCard(false)
			return true
		end
		commands.closeBotanical()
		return true
	end

	function commands.openGuard(reasonKey: string)
		if guardHandle ~= nil then
			return
		end
		guardHandle = app.presentModal(function()
			return detailView.guardAlert(app, reasonKey)
		end, {
			outsideTapCancel = false,
			scrim = "scrim",
			initialFocus = { id = "GuardOK" },
			keyboardNavigation = true,
		})
	end

	function commands.dismissGuard()
		if guardHandle ~= nil then
			dismiss(guardHandle)
			guardHandle = nil
		end
	end

	function commands.orderCta()
		local blendId = state.selectedBlendId:peek()
		if blendId == nil then
			return
		end
		local guard = order.guard()
		if not guard.allowed then
			commands.openGuard(guard.reasonKey :: string)
			return
		end
		-- the redeem branch does not exist in the compact-link entry: there is
		-- no rewards context there, so the CTA is always pay-shaped (spec §11)
		local canRedeem = app.entry == "full" and rewards.canRedeem()
		local started = order.placeOrder(blendId, if canRedeem then "redeem" else "paid")
		if started.started then
			-- the retry clears the notice it is answering, and nothing else does:
			-- a player who browses away comes back to the same explanation
			task.notePlacing()
		end
	end

	-- THE TASK'S OWN VERB. It does not place the order for the player — it takes
	-- them to the one control that does, on the blend the task line names, through
	-- the same section+open path a row Activate takes.
	function commands.taskAction()
		local blendId = task.ctaBlendId:peek()
		if catalog.blend(blendId) == nil then
			return
		end
		commands.selectSection("menu")
		commands.openBlend(blendId, "menu")
	end

	function commands.serveAnother()
		resetToSeed()
	end

	function commands.dismissOrderPlaced()
		if placedHandle ~= nil then
			dismiss(placedHandle)
			placedHandle = nil
		end
		discFlip:snap(0)
		order.clear()
	end

	function commands.openRewards()
		if rewardsHandle ~= nil then
			return
		end
		rewardsHandle = app.presentModal(function()
			return rewardsView.modal(app)
		end, {
			transition = { enter = "materialize" },
			scrim = "scrim",
			outsideTapCancel = true,
			initialFocus = { id = "Done" },
			keyboardNavigation = true,
		})
		commands.playStampPops()
	end

	function commands.dismissRewards()
		if rewardsHandle ~= nil then
			dismiss(rewardsHandle)
			rewardsHandle = nil
		end
		commands.leaveStamps()
	end

	-- CLEAR-ON-LEAVE (spec §9): the pop plays once per visit, so leaving the
	-- card — the modal dismissing, or the Stamps section being left — is what
	-- retires the "new" marks.
	function commands.leaveStamps()
		rewards.clearUnstamped()
		if stampTimeline ~= nil then
			stampTimeline:interrupt()
			stampTimeline = nil
		end
		for slot = 1, rewardsService.THRESHOLD do
			state.sealPops[slot]:snap(1)
		end
	end

	-- THE STAMP CEREMONY (spec §12): one beat per newly-earned seal at 0.15·k,
	-- in slot order. Under reduced motion the timeline fires every beat
	-- immediately, in order, and the springs place instantly — the same events,
	-- with no travel.
	function commands.playStampPops()
		local fresh = rewards.newSlots()
		for slot = 1, rewardsService.THRESHOLD do
			state.sealPops[slot]:snap(1)
		end
		if #fresh == 0 then
			return
		end
		if stampTimeline ~= nil then
			stampTimeline:interrupt()
			stampTimeline = nil
		end
		local beats: { any } = {}
		for k, slot in fresh do
			local pop = state.sealPops[slot]
			pop:snap(0)
			table.insert(beats, {
				at = 0.15 * k,
				run = function()
					pop:setTarget(1)
				end,
				terminal = function()
					pop:snap(1)
				end,
			})
		end
		stampTimeline = motionClock:timeline({
			beats = beats,
			onDone = function()
				stampTimeline = nil
				presenter.emitFeedback({ type = "celebrate", context = { what = "stamps" } })
			end,
		})
	end

	function commands.buyBlendBook()
		unlock.purchase()
	end

	function commands.setLocale(id: string): boolean
		return i18n.setLocale(id)
	end

	-- ---- service reactions -------------------------------------------------
	local unsubscribeOrder = order.onEvent(function(event: string, info: any)
		if event == "confirmed" then
			presenter.emitFeedback({ type = "commit", context = { what = "order", mode = info.mode } })
			if app.entry == "full" and info.mode == "redeem" then
				rewards.redeem()
			end
			-- the task's two latched facts. A redeem order ENDS the loop, so the
			-- completion beat is emitted here, on the causal frame, rather than
			-- polled by whatever happens to render next.
			if app.entry == "full" then
				task.noteConfirmed(info.mode)
				if info.mode == "redeem" then
					presenter.emitFeedback({ type = "celebrate", context = { what = "task" } })
				end
			end
			-- one stamp per confirmed order (economy fixture, spec §2). In the
			-- compact-link entry it accrues SILENTLY: there is no rewards
			-- surface to celebrate on.
			rewards.earn(1)
			discFlip:snap(0)
			if placedHandle ~= nil then
				dismiss(placedHandle)
				placedHandle = nil
			end
			placedHandle = app.presentModal(function()
				return detailView.orderPlaced(app, info.blendId, discFlip)
			end, {
				transition = { enter = "materialize" },
				scrim = "scrim",
				outsideTapCancel = true,
				initialFocus = { id = "Done" },
				keyboardNavigation = true,
			})
		elseif event == "rejected" then
			presenter.emitFeedback({ type = "reject", reason = info.reason, context = { what = "order" } })
			-- A REJECTION NOW HAS SOMEWHERE TO RETURN THE PLAYER TO. The toast is
			-- transient by contract; the latch below is what keeps the explanation
			-- and the retry on screen — in the CTA band where the press happened,
			-- and in the task band the player comes back to.
			task.noteRejected()
			rejectionToast("OrderRejected", "order.rejected", "order")
			order.acknowledge()
		elseif event == "ready" then
			discFlip:setTarget(1)
			presenter.emitFeedback({ type = "celebrate", context = { what = "pour" } })
		end
	end)

	local unsubscribeUnlock = unlock.onResolved(function(ok: boolean, reason: string?)
		if ok then
			presenter.emitFeedback({ type = "commit", context = { what = "unlock" } })
			presenter.emitFeedback({ type = "celebrate", context = { what = "blendBook" } })
			return
		end
		presenter.emitFeedback({ type = "reject", reason = reason, context = { what = "unlock" } })
		rejectionToast("UnlockRejected", "unlock.rejected", "unlock")
		unlock.acknowledge()
	end)

	-- WIDENING WITH A COMPACT DETAIL UP POPS ITS ROUTE (spec §5): the selection
	-- survives and the regular pane renders it. Narrowing never auto-presents.
	local unsubscribeWidth = observe(app.paneSplit, function(split: boolean)
		if split and #navigationPath:peek() > 0 and app.entry == "full" then
			closeDetailRoute()
		end
	end)

	-- the environment's own locale fact drives the model's, so the device
	-- matrix can flip the locale through `setEnv` as well as through a step
	local unsubscribeLocale: any = nil
	if localeFact ~= nil then
		unsubscribeLocale = observe(localeFact, function(value: any)
			i18n.setLocale(i18nService.localeOf(value))
		end)
	end

	-- ---- the frame source --------------------------------------------------
	-- `presenter.onTick` is the framework's one sanctioned frame hook, so the
	-- injected clock advances from the SAME tick the motion clock does: a
	-- scripted `dt` headlessly, a real frame delta in Studio, and no
	-- `RunService` connection anywhere in the proof.
	local unsubscribeTick = presenter.onTick(function(dt: number)
		clock.advance(dt)
	end)

	-- ---- shell building ----------------------------------------------------
	-- `result` is the table the scenario runner holds. `handle` is kept LIVE on
	-- it through every rebuild, so the runner's own teardown never dismisses a
	-- handle that stopped being the surface three drives ago.
	local result: any = nil

	-- Page-local views own their derived values in the NavigationStack's page
	-- scope. Rebuilding a route never leaves an observer attached to an old page.
	-- Text formulas made during a page build belong to that page.
	local function pageApp(): any
		local scoped = table.clone(app)
		function scoped.text(key: string, params: any?): any
			return scoped.own(Compose.formula(function(use)
				local locale = use(i18n.locale)
				return i18n.at(locale, key, if type(params) == "function" then params(use) else params)
			end))
		end
		return scoped
	end

	local function buildShell()
		local close, node, handle = host.mount(function()
			local navigationFlow = UI.NavigationStack("SipworksFlow")({
				path = navigationPath,
				backLabel = i18n.at(i18n.locale:peek(), "nav.back"),
				env = env,
				transition = {
					enter = "slide-left",
					exit = "slide-right",
					class = "container",
					distance = env:get("viewportRect"):peek().w,
				},
				root = {
					content = function()
						local scoped = pageApp()
						local shell = if app.entry == "compact-link"
							then entryCompact.build(scoped)
							else shellView.build(scoped)
						return UI.VStack("Root")(app.withChildren({
							width = UI.fill(),
							height = UI.fill(),
							gap = 0,
						}, shell.children))
					end,
				},
				destinations = {
					detail = {
						title = app.text("detail.title"),
						content = function()
							return detailView.body(
								pageApp(),
								{ id = "Detail", showBack = false, navigationHosted = true }
							)
						end,
					},
					recipe = {
						title = app.text("recipe.title"),
						content = function()
							return bookView.recipeView(
								pageApp(),
								{ id = "Recipe", showBack = false, navigationHosted = true }
							)
						end,
					},
				},
			})
			return UI.Screen(if app.entry == "compact-link" then "SipworksCompact" else "Sipworks")({
				padding = 0,
				surface = "base",
				navigationFlow,
			})
		end, {
			keyboardNavigation = true,
			initialFocus = "first",
			cancelPolicy = "none",
		})
		closeShell = close
		shellHandle = handle
		if result ~= nil then
			result.screen = node
			result.handle = shellHandle
		end
		return node
	end

	local function teardownSurfaces()
		commands.dismissOrderPlaced()
		commands.closeBotanical()
		commands.dismissGuard()
		if rewardsHandle ~= nil then
			dismiss(rewardsHandle)
			rewardsHandle = nil
		end
		closeDetailRoute()
		if closeShell ~= nil then
			closeShell()
			closeShell = nil
			shellHandle = nil
		end
	end

	-- THE DEEP LINK (spec §11): select the item, bring its row into view, then
	-- open Detail through the same path a row Activate takes — the entry flow
	-- reuses the flow, it does not shortcut past it.
	local function applyDeepLink()
		local target = state.entryItemId:peek()
		if catalog.blend(target) == nil then
			return
		end
		state.selectedBlendId:set(target)
		presenter.refresh()
		local controller = if shellHandle ~= nil then shellHandle.controller else nil
		if controller ~= nil and controller.scrollToVisible ~= nil then
			-- a keyed `ForEach` row carries its key as its own path segment
			for _, entry in shellHandle.focusOrder().traversal do
				if entry.path:sub(-#`/Row-{target}/Line/Open`) == `/Row-{target}/Line/Open` then
					pcall(controller.scrollToVisible, entry.path)
					break
				end
			end
		end
		commands.openBlend(target, "menu")
	end

	local function rebuild(entry: string, itemId: string?)
		teardownSurfaces()
		app.entry = entry
		state.entry:set(entry)
		if itemId ~= nil then
			state.entryItemId:set(itemId)
		end
		buildShell()
		if entry == "compact-link" then
			applyDeepLink()
		else
			state.section:set("menu")
		end
	end

	local screen = buildShell()
	if startEntry == "compact-link" then
		applyDeepLink()
	end

	-- ---- observation -------------------------------------------------------
	-- A HANDLE CAN DIE WITHOUT THIS MODULE ASKING IT TO — Cancel, an outside tap
	-- and `presenter.back()` all dismiss a surface directly. `focusOrder()` on a
	-- dismissed surface answers `present = false` (and is safe to call), so the
	-- proof reconciles against the presenter rather than trusting its own
	-- bookkeeping, and the state a surface owned is released the same way it is
	-- when the proof closes it itself.
	local function alive(handle: any): boolean
		if handle == nil then
			return false
		end
		local ok, map = pcall(handle.focusOrder)
		return ok and map ~= nil and map.present == true
	end

	local function reconcileSurfaces()
		if cardHandle ~= nil and not alive(cardHandle) then
			cardHandle = nil
			state.openBotanical:set(nil)
			cardFlip:snap(0)
		end
		if guardHandle ~= nil and not alive(guardHandle) then
			guardHandle = nil
		end
		if placedHandle ~= nil and not alive(placedHandle) then
			placedHandle = nil
			discFlip:snap(0)
			order.clear()
		end
		if rewardsHandle ~= nil and not alive(rewardsHandle) then
			rewardsHandle = nil
			commands.leaveStamps()
		end
	end

	local function surfaceMap(): any
		reconcileSurfaces()
		return {
			shell = shellHandle ~= nil,
			detail = #navigationPath:peek() > 0,
			card = cardHandle ~= nil,
			guard = guardHandle ~= nil,
			placed = placedHandle ~= nil,
			rewards = rewardsHandle ~= nil,
		}
	end

	local function gatheredMap(): { [string]: boolean }
		local out: { [string]: boolean } = {}
		for key, signal in gathered do
			if signal:peek() then
				out[key] = true
			end
		end
		return out
	end

	local function sortedKeys(map: any): { string }
		local keys: { string } = {}
		for key in map do
			table.insert(keys, tostring(key))
		end
		table.sort(keys)
		return keys
	end

	-- dump(): the deterministic state string the reset pin compares. It carries
	-- SEMANTIC state and nothing presentational — no wall time, no float that a
	-- frame delta could move — so "same seed + same steps" is a byte-identical
	-- claim rather than a hopeful one.
	local function dump(): string
		local parts: { string } = {}
		local function put(key: string, value: any)
			table.insert(parts, key .. "=" .. tostring(value))
		end
		put("entry", app.entry)
		put("entryItemId", state.entryItemId:peek())
		put("seed", seed)
		put("locale", i18n.locale:peek())
		put("section", state.section:peek())
		put("selected", state.selectedBlendId:peek())
		put("search", state.search:peek())
		put("batch", state.batch:peek())
		put("openBotanical", state.openBotanical:peek())
		put("favorites", table.concat(favorites.ids(), ","))
		put("earned", rewards.earned:peek())
		put("spent", rewards.spent:peek())
		put("newSlots", table.concat(rewards.newSlots(), ","))
		put("orderStatus", order.status:peek())
		put("orderMode", order.mode:peek())
		put("orderBlend", order.blendId:peek())
		put("orderReady", order.isReady:peek())
		put("orderAttempts", order.attempts())
		put("payments", order.paymentsEnabled:peek())
		put("unlockAvailability", unlock.availability:peek())
		put("unlockStatus", unlock.status:peek())
		put("unlocked", unlock.unlocked:peek())
		put("unlockAttempts", unlock.attempts())
		put("gathered", table.concat(sortedKeys(gatheredMap()), ","))
		put("task", task.dump())
		local surfaces = surfaceMap()
		for _, key in sortedKeys(surfaces) do
			put("surface." .. key, surfaces[key])
		end
		put("timers", clock.pending())
		return table.concat(parts, ";")
	end

	-- resolvePath(id): the focus map of every live surface, topmost first, is
	-- the proof's own path directory — so a drive can name a control by its id
	-- and reach the REAL activation handler the engine calls.
	-- topmost first, and NAMED — the report publishes each surface's own solver
	-- diagnostics, so "the layout is right" is the solver's verdict rather than a
	-- claim a screenshot might not contradict
	local function liveSurfaces(): { { name: string, handle: any } }
		reconcileSurfaces()
		local out: { { name: string, handle: any } } = {}
		local ordered = {
			{ name = "placed", handle = placedHandle },
			{ name = "guard", handle = guardHandle },
			{ name = "card", handle = cardHandle },
			{ name = "rewards", handle = rewardsHandle },
			{ name = "shell", handle = shellHandle },
		}
		for _, entry in ordered do
			if entry.handle ~= nil then
				table.insert(out, entry)
			end
		end
		return out
	end

	local function liveHandles(): { any }
		local out: { any } = {}
		for _, entry in liveSurfaces() do
			table.insert(out, entry.handle)
		end
		return out
	end

	-- every live surface's solver complaints, flattened and named. An empty list
	-- is the claim; anything in it is a layout defect the suite fails on.
	local function diagnostics(): { any }
		local out: { any } = {}
		for _, entry in liveSurfaces() do
			local controller = entry.handle.controller
			if controller == nil or controller.diagnostics == nil then
				continue
			end
			local ok, issues = pcall(controller.diagnostics)
			if not ok or issues == nil then
				continue
			end
			for _, issue in issues do
				table.insert(out, { surface = entry.name, node = issue.node, issue = issue.issue })
			end
		end
		return out
	end

	local function focusPaths(): { string }
		local out: { string } = {}
		for _, handle in liveHandles() do
			local ok, map = pcall(handle.focusOrder)
			if ok and map ~= nil and map.traversal ~= nil then
				for _, entry in map.traversal do
					table.insert(out, entry.path)
				end
			end
		end
		return out
	end

	local function resolvePath(idOrPath: string): string?
		for _, path in focusPaths() do
			if path == idOrPath or string.sub(path, -(#idOrPath + 1)) == "/" .. idOrPath then
				return path
			end
		end
		return nil
	end

	-- an untracked `use` for the reads a report makes outside the reactive graph
	local function peek(readable: any): any
		return readable:peek()
	end

	local function report(): any
		local unspent = rewards.unspent()
		return {
			proof = "p3_sipworks",
			navigation = { depth = #navigationPath:peek(), path = navigationPath:peek() },
			title = Sipworks.title,
			entry = app.entry,
			entryItemId = state.entryItemId:peek(),
			seed = seed,
			locale = i18n.locale:peek(),
			locales = strings.LOCALES,
			section = state.section:peek(),
			selectedBlendId = state.selectedBlendId:peek(),
			openBotanical = state.openBotanical:peek(),
			search = state.search:peek(),
			sizeClass = app.cond.sizeClass:peek(),
			isCompact = app.cond.isCompact:peek(),
			motionPolicy = app.motionPolicy(),
			visible = {
				menu = #app.visibleBlends(peek, "menu"),
				favorites = #app.visibleBlends(peek, "favorites"),
				recipes = #app.visibleBlends(peek, "recipes"),
			},
			favorites = favorites.ids(),
			rewards = {
				earned = rewards.earned:peek(),
				spent = rewards.spent:peek(),
				unspent = unspent,
				filled = rewards.filled(),
				away = rewards.away(),
				canRedeem = rewards.canRedeem(),
				newSlots = rewards.newSlots(),
			},
			order = {
				status = order.status:peek(),
				mode = order.mode:peek(),
				blendId = order.blendId:peek(),
				ready = order.isReady:peek(),
				attempts = order.attempts(),
				paymentsEnabled = order.paymentsEnabled:peek(),
				price = order.price,
				reason = order.reason:peek(),
			},
			unlock = {
				availability = unlock.availability:peek(),
				status = unlock.status:peek(),
				unlocked = unlock.unlocked:peek(),
				attempts = unlock.attempts(),
				price = unlock.product.price,
			},
			recipe = { batch = state.batch:peek(), gathered = sortedKeys(gatheredMap()) },
			-- the played task, published so a headless drive reads the same phase
			-- the band paints rather than re-deriving it from four services
			task = {
				phase = task.phase:peek(),
				stamps = task.stamps:peek(),
				served = task.served:peek(),
				redeemed = task.redeemed:peek(),
				refused = task.refused:peek(),
				ctaBlendId = task.ctaBlendId:peek(),
				rows = task.rows(),
				startEarned = startEarned,
				startSpent = startSpent,
			},
			surfaces = surfaceMap(),
			flip = { card = cardFlip:peek(), disc = discFlip:peek() },
			clock = { now = clock.now(), timers = clock.pending() },
			feedback = feedbackLog,
			focusPaths = focusPaths(),
			diagnostics = diagnostics(),
			dump = dump(),
		}
	end

	-- ---- the scenario drive ------------------------------------------------
	-- Every step below runs the SAME command an on-screen control runs; none of
	-- them is a private back door into the model. `activate` goes one better and
	-- invokes the adapter's registered activation closure for a node — the one
	-- the engine itself calls — so a drive is evidence of everything downstream
	-- of the engine edge.
	local steps: any = {}

	steps.report = function()
		return report()
	end

	steps.dump = function()
		return { dump = dump() }
	end

	steps.paths = function()
		return focusPaths()
	end

	steps.diagnostics = function()
		return diagnostics()
	end

	steps.activate = function(_built: any, payload: string?)
		local target = tostring(payload)
		local path = resolvePath(target)
		if path == nil then
			return { ok = false, reason = "no focusable named '" .. target .. "'" }
		end
		local ok = if adapter ~= nil and adapter.driveActivate ~= nil then adapter.driveActivate(path) else false
		presenter.refresh()
		return { ok = ok, path = path }
	end

	steps.section = function(_built: any, payload: string?)
		commands.selectSection(tostring(payload))
		return { section = state.section:peek(), surfaces = surfaceMap() }
	end

	steps.search = function(_built: any, payload: string?)
		state.search:set(if payload == nil then "" else tostring(payload))
		local section = state.section:peek()
		local kind = if section == "stamps" then "menu" else section
		return { search = state.search:peek(), visible = #app.visibleBlends(peek, kind) }
	end

	steps.suggest = function()
		local locale = i18n.locale:peek()
		return catalog.suggestions(state.search:peek(), function(kind: string, id: string, text: string)
			return i18n.nameAt(locale, kind, id, text)
		end, 6)
	end

	steps.accept = function(_built: any, payload: string?)
		commands.acceptSuggestion(tostring(payload))
		return { search = state.search:peek() }
	end

	steps.open = function(_built: any, payload: string?)
		commands.openBlend(tostring(payload), state.section:peek())
		return { selected = state.selectedBlendId:peek(), surfaces = surfaceMap() }
	end

	steps.close = function()
		commands.closeDetail()
		return { surfaces = surfaceMap() }
	end

	steps.favorite = function(_built: any, payload: string?)
		commands.toggleFavorite(tostring(payload))
		return { favorites = favorites.ids() }
	end

	steps.unfavoriteAll = function()
		for _, id in favorites.ids() do
			favorites.toggle(id)
		end
		return { favorites = favorites.ids() }
	end

	steps.tile = function(_built: any, payload: string?)
		commands.openBotanical(tostring(payload))
		return { openBotanical = state.openBotanical:peek(), surfaces = surfaceMap() }
	end

	steps.flip = function(_built: any, payload: string?)
		commands.flipCard(payload == "back")
		return { target = cardFlip:getTarget() }
	end

	steps.cancelCard = function()
		local consumed = commands.cancelCard()
		return { consumed = consumed, surfaces = surfaceMap(), flip = cardFlip:getTarget() }
	end

	steps.order = function()
		commands.orderCta()
		return { order = order.status:peek(), surfaces = surfaceMap() }
	end

	steps.guard = function(_built: any, payload: string?)
		order.setPaymentsEnabled(payload ~= "on")
		return { paymentsEnabled = order.paymentsEnabled:peek() }
	end

	steps.guardOk = function()
		commands.dismissGuard()
		return { surfaces = surfaceMap() }
	end

	steps.done = function()
		commands.dismissOrderPlaced()
		return { surfaces = surfaceMap(), order = order.status:peek() }
	end

	steps.stamps = function()
		commands.openRewards()
		return { surfaces = surfaceMap(), rewards = rewards.newSlots() }
	end

	steps.leaveStamps = function()
		commands.dismissRewards()
		return { surfaces = surfaceMap(), rewards = rewards.newSlots() }
	end

	steps.unlockBuy = function()
		commands.buyBlendBook()
		return { unlock = unlock.status:peek() }
	end

	steps.batch = function(_built: any, payload: string?)
		state.batch:set(math.clamp(tonumber(payload) or BATCH_MIN, BATCH_MIN, BATCH_MAX))
		return { batch = state.batch:peek() }
	end

	steps.gather = function(_built: any, payload: string?)
		local blendId = state.selectedBlendId:peek()
		if blendId == nil then
			return { ok = false }
		end
		local key = blendId .. "/" .. tostring(payload)
		local signal = app.gatheredSignal(key)
		signal:set(not signal:peek())
		return { key = key, value = signal:peek() }
	end

	steps.locale = function(_built: any, payload: string?)
		local ok = commands.setLocale(tostring(payload))
		return { ok = ok, locale = i18n.locale:peek() }
	end

	steps.tick = function(_built: any, payload: string?)
		local seconds = tonumber(payload) or 0.1
		local remaining = seconds
		while remaining > 0 do
			local slice = math.min(1 / 30, remaining)
			presenter.tick(slice)
			remaining -= slice
		end
		return { now = clock.now(), timers = clock.pending() }
	end

	steps.enterCompact = function(_built: any, payload: string?)
		local itemId = if payload == nil or payload == "" then state.entryItemId:peek() else tostring(payload)
		rebuild("compact-link", itemId)
		return { entry = app.entry, entryItemId = state.entryItemId:peek(), surfaces = surfaceMap() }
	end

	steps.enterFull = function()
		rebuild("full", nil)
		return { entry = app.entry, surfaces = surfaceMap() }
	end

	-- THE ONE RESET, and the task band's "Serve another customer" button is the
	-- player's own way of calling it (`commands.serveAnother`). Every observable
	-- the report publishes returns to its seeded value, which is what the
	-- determinism pin compares.
	resetToSeed = function()
		teardownSurfaces()
		clock.reset(0)
		batch(function()
			state.section:set("menu")
			state.selectedBlendId:set(nil)
			state.search:set("")
			state.batch:set(1)
			state.openBotanical:set(nil)
			state.entryItemId:set(startItemId)
		end)
		resetGathered()
		favorites.reset()
		rewards.reset()
		unlock.reset()
		order.reset()
		i18n.reset()
		task.reset()
		cardFlip:snap(0)
		discFlip:snap(0)
		for slot = 1, rewardsService.THRESHOLD do
			state.sealPops[slot]:snap(1)
		end
		table.clear(feedbackLog)
		app.entry = startEntry
		state.entry:set(startEntry)
		buildShell()
		if startEntry == "compact-link" then
			applyDeepLink()
		end
	end

	steps.reset = function()
		resetToSeed()
		return { dump = dump() }
	end

	steps.taskAction = function()
		commands.taskAction()
		return { selected = state.selectedBlendId:peek(), phase = task.phase:peek(), surfaces = surfaceMap() }
	end

	steps.serveAnother = function()
		commands.serveAnother()
		return { dump = dump(), phase = task.phase:peek() }
	end

	-- ---- the module contract ----------------------------------------------
	result = {
		title = Sipworks.title,
		-- the shell presents ITSELF (it needs a handle for the deep link and for
		-- the rebuild), so the runner is handed the handle and never mounts a
		-- second copy
		screen = screen,
		handle = shellHandle,
		present = { keyboardNavigation = true, initialFocus = "first", cancelPolicy = "none" },
		steps = steps,
		report = report,

		-- the headless test surface: the same objects the views bind, so a pin
		-- is a pin on the shipped behavior and not on a parallel model
		app = app,
		state = state,
		services = app.services,
		commands = commands,
		dump = dump,
		resolvePath = resolvePath,
		views = {
			shell = shellView,
			list = listView,
			detail = detailView,
			book = bookView,
			rewards = rewardsView,
			compact = entryCompact,
		},

		dispose = function()
			teardownSurfaces()
			unsubscribeFeedback()
			unsubscribeOrder()
			unsubscribeUnlock()
			unsubscribeWidth()
			if unsubscribeLocale ~= nil then
				unsubscribeLocale()
			end
			unsubscribeTick()
			appOwner.dispose()
		end,
	}
	return result
end

-- The proof presents itself; `deps.app` is the application it mounts into.
function Sipworks.build(Facet: any, _core: any, deps: any): any
	local Compose = Facet.Compose
	local appOwner = Compose.createOwner(deps.app.runtime.reactor)
	return Compose.withOwner(appOwner, function()
		return construct(Facet, deps, appOwner)
	end)
end

return Sipworks
