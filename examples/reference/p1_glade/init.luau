--!strict
-- ============================================================================
-- Reference proof "Glade" (RA-P1, reference-app-validation).
-- ============================================================================
--
-- A clean-room reinterpretation of the behavioral reference as an original
-- Facet product, built to `artifacts/swiftui-reference-app-validation/specs/
-- p1-glade.md`. Keepers tend moss gardens — GLADES — that glowing sprites —
-- WISPS — visit while the supplies are kept up. Two supplies per glade: Dew
-- (instant refill) and Nectar (chosen from varieties, some premium).
--
-- WHAT THIS PROOF IS FOR. It is the whole RA-P1 loop, drivable end to end
-- through on-screen controls on every input class: an overview of five glades
-- with visibly draining supply rings → a glade's detail → an instant dew refill
-- → the nectar picker (Use 1 / Shop / Choose) → the provision shop with a real
-- purchase command (idle → pending → confirmed | rejected, with the rejection's
-- copy at the point of action) → the Keeper's Charm tiers with upgrade-only mode
-- → wisp info → the keeper screen, its edit form, and a Fresh Start that reseeds
-- the world byte-identically.
--
-- WHAT IT OWNS AND WHAT IT DOES NOT. Facet owns layout, adaptation, focus,
-- presentation, motion, text and theming. This proof owns its content, its
-- domain signals, and three deterministic fake services (SupplyService,
-- CommerceService, VisitScheduler). It reads no wall clock, calls no
-- `math.random`, touches no network and writes no player data: the ONLY time in
-- the proof is an injected `now` signal, advanced by the presenter's own tick in
-- Studio and by a scripted step headlessly, which is what makes "same seed +
-- same steps ⇒ identical dump" mechanical.
--
-- DELIVERED SUBSTITUTIONS (each recorded, none silent):
--   * the spec proposes two `extra.*` glow tokens for supply identity. No theme
--     tokens land this stage, so nectar takes the `accent` role and dew takes
--     `contentStrong` through the public `tint` channel — themable and
--     contrast-checkable at both ends, which is what the proposal was for.
--   * the spec names PALETTE roles where `surface` takes the framework's
--     eight-value SURFACE vocabulary: `surfaceStrong` reads as `"raised"` here.
--   * three compact-label icons the spec names ("check", "cart", "hourglass")
--     are not in the framework's semantic icon vocabulary; the proof uses
--     "checkmark" and one-word compact text instead of inventing icon names that
--     would resolve to nothing.
--   * scene layers are tinted shapes rather than uploaded art (no assets ship
--     this stage); the structure — ZStack, anchors, fractional offsets, per-layer
--     identity tints — is the spec's, and each layer is one prop away from art.

local seedData = require("@self/content/seed")
local strings = require("@self/content/strings")
local supplyService = require("@self/services/supply")
local commerceService = require("@self/services/commerce")
local visitService = require("@self/services/visits")
local overviewUI = require("@self/ui/overview")
local detailUI = require("@self/ui/detail")
local shopUI = require("@self/ui/shop")
local keeperUI = require("@self/ui/keeper")
local parts = require("@self/ui/parts")

local Glade = {}

local SECTIONS = { "glades", "wisps", "flora", "keeper" }
local METRICS = seedData.METRICS

-- the wisp's rest perch and its entry point at the trailing edge, as fractions
-- of the scene's inner box (spec §11's beats)
local WISP_REST = { x = 0.46, y = 0.44 }
local WISP_ENTRY = { x = 0.92, y = 0.24 }
local GLOW_REST = 0.45
local GLOW_SWELL = 0.12

-- ---- a deterministic serializer for the proof's own dump --------------------
-- Sorted keys, stable number formatting, no addresses: two runs that reached the
-- same state produce the same bytes, which is what the reset pin compares.
local function serialize(value: any): string
	local kind = type(value)
	if kind == "table" then
		local isArray = #value > 0
		local out: { string } = {}
		if isArray then
			for _, item in value do
				table.insert(out, serialize(item))
			end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys: { string } = {}
		for key in value do
			table.insert(keys, tostring(key))
		end
		table.sort(keys)
		for _, key in keys do
			table.insert(out, key .. "=" .. serialize((value :: any)[key]))
		end
		return "{" .. table.concat(out, ",") .. "}"
	elseif kind == "number" then
		return string.format("%.4f", value)
	elseif kind == "nil" then
		return "nil"
	end
	return tostring(value)
end

function Glade.build(Facet: any, core: any, deps: any): any
	local UI = Facet.UI
	local env = deps.env
	local presenter = deps.presenter
	local actionSystem = deps.actionSystem

	local scope = core:scope("ref-p1-glade")
	local conditions = Facet.adaptive.conditions(core, env, { scope = scope })
	local clock = presenter.motionClock

	-- ---- injected time ------------------------------------------------------
	local now = scope:own(core:signal(0))
	local commerce: any

	local function advance(dt: number)
		if dt <= 0 then
			return
		end
		now:set(now:get() + dt)
		commerce.update(now:get())
	end

	-- ---- locale + copy ------------------------------------------------------
	local locale = scope:own(core:signal(strings.DEFAULT_LOCALE))
	local copyMemos: { [string]: any } = {}
	local function L(key: string): any
		local memo = copyMemos[key]
		if memo == nil then
			memo = scope:own(core:memo(function(use)
				return strings.get(use(locale), key)
			end))
			copyMemos[key] = memo
		end
		return memo
	end
	local function Lnow(key: string, subs: { [string]: string }?): string
		return strings.get(locale:get(), key, subs)
	end

	-- ---- proof-owned formatting (the framework has no date/locale formatter) --
	local fmt = {}
	function fmt.duration(seconds: number): string
		if seconds >= 3600 then
			return Lnow("time.hour", { n = tostring(math.floor(seconds / 3600)) })
		elseif seconds >= 60 then
			return Lnow("time.minute", { n = tostring(math.floor(seconds / 60)) })
		end
		return Lnow("time.second", { n = tostring(math.max(0, math.floor(seconds))) })
	end
	function fmt.relative(secondsAgo: number): string
		if secondsAgo < 45 then
			return Lnow("time.now")
		end
		return Lnow("time.ago", { when = fmt.duration(secondsAgo) })
	end

	-- ---- colour helpers -----------------------------------------------------
	local function rgb(triple: { number }): any
		return { r = triple[1], g = triple[2], b = triple[3] }
	end
	-- scene art rides the tint channel's DECLARED theming-exempt form: a species'
	-- hue and a nectar's jar are game data, the same class the `direct` form
	-- exists for. Every UI surface, state and affordance in this proof is a role.
	local function tint(triple: { number }, transparency: number?): any
		if transparency ~= nil then
			return { direct = rgb(triple), transparency = transparency }
		end
		return { direct = rgb(triple) }
	end
	-- THE TOKEN SUBSTITUTION (package brief): the spec's `extra.nectarGlow` /
	-- `extra.dewGlow` become the nearest existing palette roles, so both stay
	-- themable and contrast-gated and a package swap moves them.
	local SUPPLY_ROLE = { nectar = "accent", dew = "contentStrong" }
	local function supplyTint(kind: string): any
		return { role = SUPPLY_ROLE[kind], blend = 1 }
	end

	-- ---- services -----------------------------------------------------------
	local supply = supplyService.new({ core = core, now = now, scope = scope })
	commerce = commerceService.new({ core = core, now = now, scope = scope })
	local visits = visitService.new({
		core = core,
		now = now,
		charmTier = commerce.charmTier(),
		scope = scope,
	})

	-- ---- semantic + presentation state --------------------------------------
	local state = {
		locale = locale,
		section = scope:own(core:signal("glades")),
		selectedGlade = scope:own(core:signal(nil :: string?)),
		search = scope:own(core:signal("")),
		offerDismissed = scope:own(core:signal(false)),
		keeperName = scope:own(core:signal(seedData.KEEPER.displayName)),
		keeperContact = scope:own(core:signal(seedData.KEEPER.contact)),
		draftName = scope:own(core:signal(seedData.KEEPER.displayName)),
		draftContact = scope:own(core:signal(seedData.KEEPER.contact)),
		favourites = {} :: { [string]: any },
	}
	for _, glade in seedData.GLADES do
		state.favourites[glade.id] = scope:own(core:signal(glade.favourite == true))
	end
	state.filtered = scope:own(core:memo(function(use)
		local term = string.lower(use(state.search))
		local loc = use(state.locale)
		local out: { any } = {}
		for _, glade in seedData.GLADES do
			if term == "" then
				table.insert(out, glade)
			else
				local name = string.lower(strings.get(loc, "glade." .. glade.id))
				if string.find(name, term, 1, true) ~= nil then
					table.insert(out, glade)
				end
			end
		end
		return out
	end))

	-- ---- wisp motion --------------------------------------------------------
	-- Two scalar springs for the flight (never one spring on a 2-D distance) plus
	-- a scale spring and the decay-class delight glow. One record per scene form,
	-- created on demand and shared by the scene that binds it and the timeline
	-- that drives it.
	local wispRecords: { [string]: any } = {}
	local function wispMotion(gladeId: string, form: string): any
		local key = gladeId .. "/" .. form
		local record = wispRecords[key]
		if record == nil then
			record = {
				x = scope:own(clock:spring(WISP_REST.x, "object")),
				y = scope:own(clock:spring(WISP_REST.y, "object")),
				scale = scope:own(clock:spring(1, "reward")),
				glow = scope:own(clock:spring(GLOW_REST, "decay")),
				timeline = nil :: any,
			}
			wispRecords[key] = record
		end
		return record
	end

	-- ---- feedback log (the bus is the game's seam; the proof plays nothing) ---
	local feedbackLog: { string } = {}
	scope:own(presenter.onFeedback(function(event: any)
		table.insert(feedbackLog, tostring(event.type))
		if #feedbackLog > 64 then
			table.remove(feedbackLog, 1)
		end
	end))

	-- ---- the context every surface module reads -----------------------------
	local nav = {}
	local ctx = {
		Facet = Facet,
		UI = UI,
		core = core,
		scope = scope,
		env = env,
		actionSystem = actionSystem,
		presenter = presenter,
		conditions = conditions,
		clock = clock,
		now = now,
		L = L,
		Lnow = Lnow,
		fmt = fmt,
		rgb = rgb,
		tint = tint,
		supplyTint = supplyTint,
		supply = supply,
		commerce = commerce,
		visits = visits,
		state = state,
		nav = nav,
		wispMotion = wispMotion,
	}

	-- ---- toasts -------------------------------------------------------------
	local toastLog: { string } = {}
	local function toast(key: string, copy: any)
		table.insert(toastLog, key)
		if #toastLog > 16 then
			table.remove(toastLog, 1)
		end
		presenter.presentToast(
			UI.VStack({
				id = "GladeToast",
				surface = "raised",
				padding = "m",
				children = { UI.Text({ id = "Line", text = copy, textSize = "label" }) },
			}),
			{ key = key, duration = 4, position = "top" }
		)
	end

	-- ---- the modal stack ----------------------------------------------------
	-- One list, one dismiss verb. A dismissed surface's scope is retired rather
	-- than disposed on the spot: the exit transition is still painting the tree
	-- that reads it, so the scope dies when the next surface opens (or at
	-- teardown), which bounds the retirement to exactly one surface.
	local stack: { any } = {}
	local retired: { any } = {}

	local function reapRetired()
		for _, dead in retired do
			pcall(function()
				dead:dispose()
			end)
		end
		retired = {}
	end

	local function pushSurface(kind: string, build: (any) -> any, opts: any)
		reapRetired()
		local surfaceScope = scope:child("surface-" .. kind)
		local blueprint = build(surfaceScope)
		local handle = presenter.presentModal(blueprint, opts)
		table.insert(stack, { kind = kind, handle = handle, scope = surfaceScope })
	end

	function nav.dismissTop(): boolean
		local top = table.remove(stack)
		if top == nil then
			return false
		end
		presenter.dismiss(top.handle)
		table.insert(retired, top.scope)
		if top.kind == "detail" then
			state.selectedGlade:set(nil)
		end
		if top.kind == "shop" or top.kind == "charm" then
			commerce.clearAll()
		end
		return true
	end

	local function topKind(): string?
		local top = stack[#stack]
		return if top ~= nil then top.kind else nil
	end

	local function dismissAll()
		while #stack > 0 do
			nav.dismissTop()
		end
	end

	-- ---- the wisp fly-in ceremony -------------------------------------------
	local flyInLog: { string } = {}
	local function startFlyIn(gladeId: string)
		local visit = visits.needsPresent(gladeId)
		if visit == nil then
			return
		end
		visits.markPresented(visit.id)
		table.insert(flyInLog, visit.id)
		local motion = wispMotion(gladeId, "hero")
		if motion.timeline ~= nil then
			motion.timeline:interrupt()
			motion.timeline = nil
		end
		local function rest()
			motion.x:snap(WISP_REST.x)
			motion.y:snap(WISP_REST.y)
			motion.scale:snap(1)
		end
		motion.x:snap(WISP_ENTRY.x)
		motion.y:snap(WISP_ENTRY.y)
		motion.scale:snap(0.35)
		motion.timeline = clock:timeline({
			beats = {
				-- 0s: appear at the trailing edge, small
				{ at = 0, run = function() end, terminal = rest },
				-- 0.15s: glide toward the basin
				{
					at = 0.15,
					run = function()
						motion.x:setTarget(WISP_REST.x)
						motion.y:setTarget(WISP_REST.y + 0.08)
					end,
					terminal = rest,
				},
				-- 1.1s: overshoot hover, scale to natural (the one `reward` beat)
				{
					at = 1.1,
					run = function()
						motion.scale:setTarget(1.08)
					end,
					terminal = rest,
				},
				-- 1.8s: settle above the dewstone
				{
					at = 1.8,
					run = function()
						motion.y:setTarget(WISP_REST.y)
						motion.scale:setTarget(1)
					end,
					terminal = rest,
				},
				-- ~2.8s: done
				{ at = 2.8, run = function() end, terminal = rest },
			},
			onDone = function(reason: string)
				table.insert(flyInLog, tostring(reason))
				if #flyInLog > 32 then
					table.remove(flyInLog, 1)
				end
			end,
		})
	end

	local function interruptFlyIns()
		for _, record in wispRecords do
			if record.timeline ~= nil then
				record.timeline:interrupt()
				record.timeline = nil
			end
		end
	end

	-- the post-refill delight glow: one swell, then back (class `decay`).
	-- Decorative — the toast carries the information, which is what lets reduced
	-- motion skip it entirely.
	local function delight(gladeId: string)
		for _, form in { "card", "hero" } do
			local motion = wispMotion(gladeId, form)
			motion.glow:setTarget(GLOW_SWELL)
			motion.glow:onSettle(function()
				motion.glow:setTarget(GLOW_REST)
			end)
		end
	end

	-- ---- the verbs ----------------------------------------------------------

	function nav.selectSection(id: string)
		for _, known in SECTIONS do
			if known == id then
				state.section:set(id)
				return
			end
		end
	end

	function nav.search(term: string)
		state.search:set(term)
	end

	function nav.toggleFavourite(gladeId: string)
		local signal = state.favourites[gladeId]
		if signal == nil then
			return
		end
		signal:set(not signal:get())
		presenter.emitFeedback({ type = "select", context = { verb = "favourite", glade = gladeId } })
	end

	function nav.openGlade(gladeId: string)
		state.selectedGlade:set(gladeId)
		if conditions.isCompact:get() then
			pushSurface("detail", function(surfaceScope)
				return shopUI.sheet(ctx, "GladeDetail", {
					detailUI.body(ctx, {
						id = "DetailBody",
						glade = gladeId,
						scope = surfaceScope,
						compact = true,
					}),
				})
			end, {
				outsideTapCancel = false,
				scrim = "none",
				transition = { enter = "slide-left", class = "container" },
				initialFocus = "SupplyRow_nectar",
			})
		end
		startFlyIn(gladeId)
	end

	function nav.closeDetail()
		if topKind() == "detail" then
			nav.dismissTop()
		else
			state.selectedGlade:set(nil)
		end
		interruptFlyIns()
	end

	function nav.refillDew(gladeId: string)
		supply.refill(gladeId, "dew")
		presenter.emitFeedback({ type = "commit", context = { verb = "refillDew", glade = gladeId } })
		delight(gladeId)
		toast(
			"refill:" .. gladeId,
			core:memo(function(use)
				local _ = use(state.locale)
				return Lnow("toast.refill", { glade = Lnow("glade." .. gladeId) })
			end)
		)
	end

	function nav.openPicker(gladeId: string)
		pushSurface("picker", function(surfaceScope)
			return shopUI.picker(ctx, gladeId, surfaceScope)
		end, {
			scrim = "scrim",
			outsideTapCancel = true,
			transition = { enter = "slide-up", fade = true, class = "container" },
			initialFocus = "Act_starlight",
		})
	end

	function nav.chooseNectar(gladeId: string, nectarId: string)
		local nectar = seedData.NECTAR_BY_ID[nectarId]
		if nectar == nil then
			return
		end
		if nectar.premium then
			local held = commerce.satchelOf(nectarId)
			if held:get() <= 0 then
				nav.openShop()
				return
			end
			-- the proof FIXES the reference's untracked consumption: using a
			-- premium jar decrements the satchel. A design decision, recorded.
			held:set(held:get() - 1)
		end
		supply.assign(gladeId, nectarId)
		presenter.emitFeedback({ type = "commit", context = { verb = "chooseNectar", nectar = nectarId } })
		if topKind() == "picker" then
			nav.dismissTop()
		end
		delight(gladeId)
		toast(
			"refill:" .. gladeId,
			core:memo(function(use)
				local _ = use(state.locale)
				return Lnow("toast.refill", { glade = Lnow("glade." .. gladeId) })
			end)
		)
	end

	function nav.openShop()
		pushSurface("shop", function(surfaceScope)
			return shopUI.provisions(ctx, surfaceScope)
		end, {
			scrim = "scrim",
			outsideTapCancel = true,
			transition = { enter = "slide-up", fade = true, class = "container" },
			initialFocus = "Buy_starlightBundle",
		})
	end

	function nav.buyPack(packId: string)
		commerce.buyPack(packId)
	end

	function nav.openCharm()
		-- the recommended tier is the lowest one still on offer, which is what
		-- upgrade-only mode leaves at the top of the list. It is computed rather
		-- than named because a fixed id would be refused at present time the
		-- moment that tier is owned and its card stops rendering.
		local recommended: string? = nil
		local held = commerce.charmRank()
		for _, tier in seedData.CHARM_TIERS do
			if recommended == nil and tier.rank > held then
				recommended = "BuyCharm_" .. tier.id
			end
		end
		pushSurface("charm", function(surfaceScope)
			return shopUI.charm(ctx, surfaceScope)
		end, {
			scrim = "scrim",
			outsideTapCancel = true,
			transition = { enter = "materialize", class = "container" },
			initialFocus = recommended or "first",
		})
	end

	function nav.buyCharm(tierId: string)
		commerce.buyCharm(tierId)
	end

	function nav.openWisp(wispId: string)
		pushSurface("wisp", function(surfaceScope)
			return shopUI.wisp(ctx, wispId, surfaceScope)
		end, {
			scrim = "scrim",
			outsideTapCancel = true,
			transition = { enter = "materialize", class = "container" },
			initialFocus = "Close",
		})
	end

	function nav.restore()
		commerce.restore()
	end

	function nav.openEdit()
		state.draftName:set(state.keeperName:get())
		state.draftContact:set(state.keeperContact:get())
		pushSurface("edit", function(surfaceScope)
			return keeperUI.editForm(ctx, surfaceScope)
		end, {
			scrim = "scrim",
			outsideTapCancel = true,
			transition = { enter = "slide-up", fade = true, class = "container" },
			-- "first" IS the display-name field: both text inputs name their inner
			-- focusable `Field`, so an id would be ambiguous and is refused.
			initialFocus = "first",
		})
	end

	function nav.saveKeeper()
		state.keeperName:set(state.draftName:get())
		state.keeperContact:set(state.draftContact:get())
		presenter.emitFeedback({ type = "commit", context = { verb = "saveKeeper" } })
		if topKind() == "edit" then
			nav.dismissTop()
		end
	end

	function nav.openFreshStart()
		pushSurface("freshStart", function()
			return keeperUI.confirmReset(ctx)
		end, {
			scrim = "scrim",
			outsideTapCancel = false,
			transition = { enter = "materialize", class = "container" },
			initialFocus = "KeepGlades",
		})
	end

	-- THE RESET. Every service reseeds from the same seed the session started
	-- from and every surface dismisses to S1, so a dump taken after it is the
	-- dump taken before anything happened.
	local function resetWorld()
		dismissAll()
		reapRetired()
		interruptFlyIns()
		supply.reset()
		commerce.reset()
		visits.reset()
		now:set(0)
		state.section:set("glades")
		state.selectedGlade:set(nil)
		state.search:set("")
		state.offerDismissed:set(false)
		state.keeperName:set(seedData.KEEPER.displayName)
		state.keeperContact:set(seedData.KEEPER.contact)
		state.draftName:set(seedData.KEEPER.displayName)
		state.draftContact:set(seedData.KEEPER.contact)
		for _, glade in seedData.GLADES do
			state.favourites[glade.id]:set(glade.favourite == true)
		end
		for _, record in wispRecords do
			record.x:snap(WISP_REST.x)
			record.y:snap(WISP_REST.y)
			record.scale:snap(1)
			record.glow:snap(GLOW_REST)
		end
		table.clear(toastLog)
		table.clear(flyInLog)
		table.clear(feedbackLog)
	end

	function nav.confirmFreshStart()
		presenter.emitFeedback({ type = "commit", context = { verb = "freshStart" } })
		resetWorld()
	end

	-- ---- toasts the services owe (purchase + restore) ------------------------
	-- Confirmed commands announce themselves once, on the frame they resolve —
	-- an observer on the command's own status, so there is one causal moment and
	-- no polling.
	for _, pack in seedData.PACKS do
		scope:own(core:observe(commerce.status(pack.id), function(status: string)
			if status ~= "confirmed" then
				if status == "rejected" then
					presenter.emitFeedback({ type = "reject", context = { verb = "buyPack", pack = pack.id } })
				end
				return
			end
			presenter.emitFeedback({ type = "celebrate", context = { verb = "buyPack", pack = pack.id } })
			toast(
				"purchase",
				core:memo(function(use)
					local _ = use(state.locale)
					return Lnow("toast.purchase", {
						count = tostring(pack.quantity),
						nectar = Lnow("nectar." .. pack.nectar),
					})
				end)
			)
		end))
	end
	for _, tier in seedData.CHARM_TIERS do
		scope:own(core:observe(commerce.status(tier.id), function(status: string)
			if status == "rejected" then
				presenter.emitFeedback({ type = "reject", context = { verb = "buyCharm", tier = tier.id } })
				return
			end
			if status ~= "confirmed" then
				return
			end
			presenter.emitFeedback({ type = "celebrate", context = { verb = "buyCharm", tier = tier.id } })
			toast(
				"purchase",
				core:memo(function(use)
					local _ = use(state.locale)
					return Lnow("charm.toast", { tier = Lnow("charm.tier." .. tier.id) })
				end)
			)
		end))
	end
	scope:own(core:observe(commerce.status("restore"), function(status: string)
		if status == "rejected" then
			presenter.emitFeedback({ type = "reject", context = { verb = "restore" } })
			return
		end
		if status ~= "confirmed" then
			return
		end
		toast("restore", L("keeper.restoreToast"))
	end))

	-- ---- the shell ----------------------------------------------------------
	-- ONE construct, and it is the framework's. `Facet.Controls.TabView` owns the
	-- four homes `adaptive.navPlacement` chooses between (director ruling
	-- 2026-08-09, the same policy the Sipworks proof adopts):
	--
	--   sidebar          desktop shape — the vertical rail, WORDMARK AT ITS HEAD
	--   topBar           tablet / ten-foot shape — centre-aligned, hugging its tabs
	--   bottomBar        phone portrait — the thumb-zone band
	--   bottomBarCompact phone landscape — the same band, centred and tighter
	--
	-- WHAT THIS PROOF STOPPED CARRYING (framework-gaps-phase2 §6). The wordmark was
	-- the reason this file could not adopt the construct: four placement memos,
	-- four hand-built bars, two `ViewThatFits` ladders and a per-section selection
	-- memo, all so one brand mark could sit at the top of ONE of the four homes.
	-- `accessories.head` is that slot, and everything else here became the
	-- control's own policy — which is the point of migrating. A ruling about a tab
	-- bar now lands in one place instead of five, and the examples directory stops
	-- teaching the same thing two contradictory ways.
	--
	-- THE TERSE VOCABULARY SURVIVES AS A BOUND LABEL rather than a second bar
	-- (director refinement 2026-08-09: "I see a lot of cutoff text"). A thumb-zone
	-- tab takes the short localized string and every roomier home takes the full
	-- one; because `Option.label` is a Readable, the flip follows a live rotation
	-- and a live locale change alike, which a construction-time `compactLabel`
	-- could not.
	-- GAP 7a (framework-gaps-phase2 §7): the two thumb-zone homes, off the
	-- promoted predicates rather than a hand-rolled `== "bottomBar"` string
	-- compare.
	local terse = scope:own(core:memo(function(use)
		return use(conditions.navBottomBar) or use(conditions.navBottomBarCompact)
	end))
	--[[ ...AND THE TERSE FORM COMES WITH THE TERSE TREATMENT, which is the other
		half of the same director call: a thumb-zone tab is caption-sized, which is
		what a tab bar is everywhere and what keeps four names off the ellipsis on a
		320px phone. MEASURED, not assumed — at body size the band truncated three of
		its four tabs at 320px, which is the very report ("I see a lot of cutoff
		text") this vocabulary answers. The sidebar and the top bar keep the body
		size, so this rides the same `terse` fact the words do. ]]
	local navTextSize = scope:own(core:memo(function(use)
		return if use(terse) then "caption" else "body"
	end))

	--[[ THE TWO CONTENT PANES still adapt by MEASUREMENT, which is what a
		Composition is for: the detail lane sits beside the section when both clear
		their floors, folds under it when they do not, and drops entirely when even
		that will not fit. It is now the SELECTED TAB's content rather than a ZStack
		of four `When`s, so exactly one section subtree exists at a time.

		THE LANE IS BUILT ONCE AND CAPTURED, never rebuilt per tab: `detail.lane`
		owns a memo on this screen's scope, and a factory that rebuilt it would hand
		that scope a fresh one on every switch (the wings' disposer lesson). The
		section BODY is still built per entry, exactly as the old `When` built it. ]]
	local detailLane = detailUI.lane(ctx)

	local function sectionPane(id: string, build: (any) -> any): any
		--[[ THE PANE IS THE TAB'S FADE GROUP, and it is the SAME canvasGroup budget
			this proof always spent — it moved OUT of the section plate rather than
			joining it. A fade is `GroupTransparency`, which needs a group at the node
			the transition applies to, and under the construct that node is the tab's
			whole content rather than one section body. The plate below keeps its
			clip through `overflow = "clip"`, which is a clip host in its own right
			(blueprint F-19) and costs no second buffer. ]]
		local pane = UI.Composition({
			id = "Panes",
			arrangements = {
				{ name = "detailBeside", lanes = { { "main" }, { "trail" } } },
				{ name = "detailBelow", lanes = { { "main", "trail" } } },
			},
			laneGap = "m",
			groupGap = "m",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			groups = {
				{ id = "content", lane = "main", sizing = "fill", minWidth = METRICS.shellContentMin },
				{ id = "detail", lane = "trail", sizing = "hug" },
			},
			-- DECLARATION ORDER IS FOCUS ORDER, and it is the same in every
			-- arrangement: search → cards → detail (spec §4's tab order). The nav is
			-- not one of these regions, so it reads in the ring where it is PAINTED —
			-- the leading rail before the content, the bottom bar after it — and that
			-- rule is now the construct's rather than this file's.
			children = {
				UI.Region({
					id = "Section",
					group = "content",
					rank = 1,
					sizing = "fill",
					mayScroll = true,
					floor = { lines = 3 },
					children = {
						UI.ZStack({
							id = "Body_" .. id,
							-- A SECTION PLATE CLIPS, AND SAYS SO — and `overflow = "clip"` is
							-- itself a clip host, so the plate keeps clipping while the one
							-- canvasGroup this pane spends sits where the fade needs it.
							overflow = "clip",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							children = { build(ctx) },
						}),
					},
				}),
				UI.Region({
					id = "Detail",
					group = "detail",
					rank = 2,
					children = { detailLane },
				}),
			},
		})
		return UI.ZStack({
			id = "Pane_" .. id,
			canvasGroup = true,
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = { pane },
		})
	end

	local SECTION_BUILD: { [string]: (any) -> any } = {
		glades = overviewUI.glades,
		wisps = overviewUI.wisps,
		flora = overviewUI.flora,
		keeper = keeperUI.section,
	}
	local navTabs: { any } = {}
	for _, id in SECTIONS do
		local section = id
		table.insert(navTabs, {
			id = section,
			label = scope:own(core:memo(function(use)
				local _ = use(locale)
				return Lnow("section." .. section .. (if use(terse) then ".short" else ""))
			end)),
			content = function()
				return sectionPane(section, SECTION_BUILD[section])
			end,
		})
	end

	local navBar = scope:own(Facet.Controls.TabView(core, {
		id = "Nav",
		-- the proof's own section Signal, unchanged: everything that must survive a
		-- tab switch is owned OUTSIDE the construct, and this is the first one
		selection = state.section,
		-- the conditions this screen already built, passed in rather than rebuilt:
		-- `adaptive.conditions` creates its own set of memos and two copies would be two
		-- answers to one question
		conditions = conditions,
		env = env,
		--[[ NATURAL-WIDTH SEGMENTS IN EVERY HOME, which is the shape this proof's
			bars have always taken: a centred cluster that hugs its four words, never
			a full-width row of equal targets. It is a LOCALIZATION decision rather
			than a taste one — four localized names divided equally across a 320px
			phone truncate three of the four at the +4 text preference (measured),
			and this proof's whole nav vocabulary exists to answer exactly that
			report. A hugging band centres, and scrolls when it cannot fit. ]]
		sizing = "hug",
		textSize = navTextSize,
		-- the enter fade the four hand-built section hosts each declared
		transition = { enter = "fade", class = "container" },
		tabs = navTabs,
		accessories = {
			--[[ THE WORDMARK, and the reason this proof could not adopt the construct
				before §6. It belongs to the RAIL FORM ALONE — a brand mark beside a
				centred cluster is the one thing that pushes the cluster off centre at
				the expansion locale — and `head` is hosted by exactly that home, so
				the placement decides it instead of a fifth memo in this file. ]]
			head = function()
				return UI.Text({ id = "Wordmark", text = L("app.title"), textSize = "title", lineLimit = 1 })
			end,
		},
	}))

	local screen = UI.Screen({
		id = "Glade",
		surface = "base",
		children = { navBar.blueprint },
	})

	-- ---- the frame tick -----------------------------------------------------
	-- The proof's ONE frame source, and it is the presenter's own: no second
	-- RunService connection, no wall clock. In Studio this advances the world at
	-- real speed; headlessly the suite hands `presenter.tick(dt)` a scripted dt
	-- and gets the identical arithmetic.
	scope:own(presenter.onTick(function(dt: number)
		advance(dt)
	end))

	-- ---- report + dump ------------------------------------------------------
	local function favouriteList(): { string }
		local out: { string } = {}
		for id, signal in state.favourites do
			if signal:get() then
				table.insert(out, id)
			end
		end
		table.sort(out)
		return out
	end

	local function surfaceList(): { string }
		local out: { string } = {}
		for _, entry in stack do
			table.insert(out, entry.kind)
		end
		return out
	end

	local function reportTable(): any
		return {
			proof = "p1_glade",
			seed = seedData.WORLD,
			now = now:get(),
			locale = locale:get(),
			section = state.section:get(),
			selectedGlade = state.selectedGlade:get(),
			search = state.search:get(),
			offerDismissed = state.offerDismissed:get(),
			favourites = favouriteList(),
			keeper = { name = state.keeperName:get(), contact = state.keeperContact:get() },
			supply = supply.dump(),
			commerce = commerce.dump(),
			visits = visits.dump(),
			surfaces = surfaceList(),
			toasts = table.clone(toastLog),
			flyIns = table.clone(flyInLog),
			feedback = table.clone(feedbackLog),
			-- the substitutions this package made against the spec, published so
			-- the audit reads them from the artifact rather than from a comment
			substitutions = {
				supplyGlow = "extra.nectarGlow -> tint role accent; extra.dewGlow -> tint role contentStrong",
				surfaceVocabulary = 'spec palette role surfaceStrong -> surface "raised"',
				compactIcons = "check -> checkmark; cart -> compact text; hourglass -> reactive label only",
				sceneArt = "tinted shape layers (no uploaded assets ship this stage)",
			},
		}
	end

	local handleRef: any = nil

	local built
	built = {
		screen = screen,
		present = {
			keyboardNavigation = true,
			rootPolicy = "coreSafeContent",
			cancelPolicy = "none",
			-- spec §3: the base surface opens on the first glade card, not on the
			-- search field — a gamepad landing in a text field is a keyboard
			-- nobody asked for.
			initialFocus = "GladeCard_" .. seedData.GLADES[1].id,
		},
		report = reportTable,
		dump = function(): string
			return serialize(reportTable())
		end,
		steps = {
			-- TIME. Every other step is a verb a player has on screen; this one is
			-- the injected clock, which is the only thing a headless run cannot
			-- get by pressing something.
			advanceClock = function(_built: any, payload: any): any
				local seconds = tonumber(payload) or 60
				advance(seconds)
				presenter.tick(0)
				return { now = now:get() }
			end,
			settleCommerce = function(): any
				advance(seedData.COMMAND_SECONDS + 0.01)
				presenter.tick(0)
				return commerce.dump()
			end,
			selectSection = function(_built: any, payload: any): any
				nav.selectSection(tostring(payload))
				return { section = state.section:get() }
			end,
			selectGlade = function(_built: any, payload: any): any
				nav.openGlade(tostring(payload or seedData.GLADES[1].id))
				return { selected = state.selectedGlade:get(), surfaces = surfaceList() }
			end,
			closeDetail = function(): any
				nav.closeDetail()
				return { selected = state.selectedGlade:get(), surfaces = surfaceList() }
			end,
			refillDew = function(_built: any, payload: any): any
				local gladeId = tostring(payload or state.selectedGlade:get() or seedData.GLADES[1].id)
				nav.refillDew(gladeId)
				return { glade = gladeId, state = supply.state(gladeId, "dew"):get() }
			end,
			openPicker = function(_built: any, payload: any): any
				nav.openPicker(tostring(payload or state.selectedGlade:get() or seedData.GLADES[1].id))
				return { surfaces = surfaceList() }
			end,
			chooseNectar = function(_built: any, payload: any): any
				local gladeId = state.selectedGlade:get() or seedData.GLADES[1].id
				nav.chooseNectar(gladeId, tostring(payload or "clover"))
				return { glade = gladeId, nectar = supply.nectarOf(gladeId):get() }
			end,
			openShop = function(): any
				nav.openShop()
				return { surfaces = surfaceList() }
			end,
			buyPack = function(_built: any, payload: any): any
				nav.buyPack(tostring(payload or "starlightBundle"))
				return commerce.dump()
			end,
			openCharm = function(): any
				nav.openCharm()
				return { surfaces = surfaceList() }
			end,
			buyCharm = function(_built: any, payload: any): any
				nav.buyCharm(tostring(payload or "ember"))
				return commerce.dump()
			end,
			openWisp = function(_built: any, payload: any): any
				nav.openWisp(tostring(payload or "tidewisp"))
				return { surfaces = surfaceList() }
			end,
			restore = function(): any
				nav.restore()
				return commerce.dump()
			end,
			openEdit = function(): any
				nav.openEdit()
				return { surfaces = surfaceList() }
			end,
			saveKeeper = function(_built: any, payload: any): any
				if payload ~= nil and payload ~= "" then
					state.draftName:set(tostring(payload))
				end
				nav.saveKeeper()
				return { keeper = { name = state.keeperName:get(), contact = state.keeperContact:get() } }
			end,
			freshStart = function(): any
				nav.openFreshStart()
				return { surfaces = surfaceList() }
			end,
			confirmFreshStart = function(): any
				nav.confirmFreshStart()
				return reportTable()
			end,
			dismissTop = function(): any
				local dismissed = nav.dismissTop()
				return { dismissed = dismissed, surfaces = surfaceList() }
			end,
			search = function(_built: any, payload: any): any
				nav.search(if payload == nil then "" else tostring(payload))
				return { search = state.search:get(), matches = #state.filtered:get() }
			end,
			toggleFavourite = function(_built: any, payload: any): any
				nav.toggleFavourite(tostring(payload or seedData.GLADES[1].id))
				return { favourites = favouriteList() }
			end,
			setLocale = function(_built: any, payload: any): any
				local next_ = tostring(payload or "en")
				if strings.TABLES[next_] ~= nil then
					locale:set(next_)
				end
				return { locale = locale:get() }
			end,
			dismissOffer = function(): any
				state.offerDismissed:set(true)
				return { offerDismissed = true }
			end,
			reset = function(): any
				resetWorld()
				return reportTable()
			end,
			dump = function(): any
				return serialize(reportTable())
			end,
		},
		-- the proof's own verbs, for a test that would rather call than drive
		api = {
			nav = nav,
			state = state,
			supply = supply,
			commerce = commerce,
			visits = visits,
			advance = advance,
			reset = resetWorld,
			now = now,
			locale = locale,
			conditions = conditions,
			fmt = fmt,
			serialize = serialize,
			sections = SECTIONS,
			surfaces = surfaceList,
			topKind = topKind,
		},
		dispose = function()
			dismissAll()
			reapRetired()
			interruptFlyIns()
			if handleRef ~= nil then
				pcall(function()
					presenter.dismiss(handleRef)
				end)
				handleRef = nil
			end
			scope:dispose()
		end,
	}

	built.api.bindHandle = function(handle: any)
		handleRef = handle
	end

	local _ = parts
	return built
end

return Glade
