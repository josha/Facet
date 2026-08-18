--!strict
-- ============================================================================
-- Reference proof "Glade" (RA-P1, swiftui-reference-app-validation).
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
	-- ONE tree, and the nav has FOUR HOMES chosen by `adaptive.navPlacement`
	-- (director ruling 2026-08-09, the same policy the Sipworks proof adopts):
	--
	--   sidebar          desktop shape — the vertical rail, wordmark at its head,
	--                    full section names
	--   topBar           tablet / ten-foot shape — CENTER-ALIGNED and hugging its
	--                    four tabs, never stretched edge to edge; full names,
	--                    stepping down to the terse ones by fit
	--   bottomBar        phone portrait — the thumb-zone band, TERSE names, a
	--                    centered natural-width cluster first
	--   bottomBarCompact phone landscape — the same terse band, tighter
	--
	-- Both bottom bars declare the same honest step-down: the centered cluster,
	-- then a full-width shared row once extreme text can no longer fit the
	-- cluster in the band.
	--
	-- The placement is a CONDITION, not a fit. The rail used to be a Composition
	-- Region whose arrangement decided where it went, and a Region steps down by
	-- FAILURE rather than by policy — so the shape a phone got was whatever
	-- happened to fit, and a ten-foot screen got the densest thing that fitted,
	-- which is the opposite of what a TV wants. `navPlacement` answers from shape,
	-- input class and display facts (never a device name), and `When` mounts the
	-- one home it names; the CONTENT of a bar still degrades by fit.
	local placement = conditions.navPlacement
	local navSidebar = scope:own(core:memo(function(use)
		return use(placement) == "sidebar"
	end))
	local navTop = scope:own(core:memo(function(use)
		return use(placement) == "topBar"
	end))
	local navBottomFull = scope:own(core:memo(function(use)
		return use(placement) == "bottomBar"
	end))
	local navBottomCompact = scope:own(core:memo(function(use)
		return use(placement) == "bottomBarCompact"
	end))

	local FILL = { type = "fill", weight = 1 }
	local HUG = { type = "content" }

	-- one selection memo per section, shared by every home (the homes are
	-- mutually exclusive, so a section's four buttons are never on screen at
	-- once, but they must all read the SAME signal)
	local sectionSelected: { [string]: any } = {}
	for _, id in SECTIONS do
		sectionSelected[id] = scope:own(core:memo(function(use)
			return use(state.section) == id
		end))
	end

	-- `width = nil` lets a button hug its own label (the sidebar and the
	-- centered clusters); `FILL` shares the band equally (the full-width rows,
	-- where four natural label widths overflow a 360px phone by 22px — the
	-- solver said so on every solve before equal-weight tabs landed).
	local function railButtons(short: boolean, width: any?): { any }
		local out: { any } = {}
		for _, id in SECTIONS do
			table.insert(
				out,
				UI.Button({
					-- the terse form comes with the terse TREATMENT: a thumb-zone tab
					-- is caption-sized in tighter chrome, which is what a tab bar is
					-- everywhere, and what keeps four tabs off the ellipsis on a
					-- 320px phone. The sidebar and the top bar keep the body size.
					textSize = if short then "caption" else nil,
					padding = if short then "xs" else nil,
					-- NO `compactLabel`, and that is a finding rather than an
					-- omission: a compact form is construction-only (it is what a
					-- control HAS), so it cannot follow the live locale flip this
					-- proof's loop drives. The terse form is a second LOCALIZED
					-- string instead.
					id = "Nav_" .. id,
					label = L("section." .. id .. (if short then ".short" else "")),
					selected = sectionSelected[id],
					width = width,
					onActivate = function()
						nav.selectSection(id)
					end,
				})
			)
		end
		return out
	end

	local function tabRow(id: string, opts: { natural: boolean, short: boolean, gap: string, pad: any }): any
		return UI.HStack({
			id = id,
			gap = opts.gap,
			padding = opts.pad,
			-- NO `align` on the natural-width rows: a container's own `align` is
			-- ALSO read by its PARENT as cross-axis alignment (framework finding
			-- 15), so "stretch" here would defeat the centering wrapper and
			-- stretch the cluster back to full width.
			align = if opts.natural then nil else "stretch",
			-- CONTENT, not hug, on the MEASURED candidates: `hug` CAPS at the
			-- offer, so a hug row can never tell a ViewThatFits that it does not
			-- fit — the ladder silently pins its first candidate and the tabs
			-- truncate ("a lot of cutoff text", director live report 2026-08-09).
			-- `content` is the uncapped natural width, which is what a fit CHOICE
			-- needs; the chosen row is then centered by its wrapper, never
			-- stretched.
			width = if opts.natural then HUG else FILL,
			children = railButtons(opts.short, if opts.natural then HUG else FILL),
		})
	end

	local function sideRail(): any
		return UI.VStack({
			id = "NavRail",
			gap = "s",
			padding = "s",
			align = "stretch",
			width = HUG,
			height = FILL,
			children = {
				UI.Text({ id = "Wordmark", text = L("app.title"), textSize = "title", lineLimit = 1 }),
				UI.VStack({
					id = "Links",
					gap = "s",
					align = "stretch",
					width = HUG,
					children = railButtons(false, nil),
				}),
			},
		})
	end

	-- CENTERED AND HUGGING: the tablet/ten-foot band is the full width of the
	-- screen and the tab cluster sits in the middle of it. The wordmark stays in
	-- the rail form alone — a brand mark beside a centered cluster is the one
	-- thing that pushes the cluster off centre at the expansion locale. This home
	-- has room for the full names, so it carries the honest full → terse ladder.
	local function topBar(): any
		return UI.VStack({
			id = "TopBar",
			align = "center",
			width = FILL,
			children = {
				UI.ViewThatFits({
					id = "TopTabsFit",
					children = {
						tabRow("TopTabsFull", { natural = true, short = false, gap = "s", pad = "s" }),
						tabRow("TopTabsShort", { natural = true, short = true, gap = "s", pad = "s" }),
					},
				}),
			},
		})
	end

	-- BOTH BOTTOM BARS SPEAK THE TERSE VOCABULARY (director refinement
	-- 2026-08-09: "consider when to use the compact representation — I see a lot
	-- of cutoff text"). Full names belong to the homes with room; a thumb-zone
	-- tab bar takes the terse localized strings by construction, so nothing
	-- ellipsizes in the normal range at all. What remains is the honest
	-- extreme-text step-down: a CENTERED natural-width cluster first, then the
	-- full-width shared band once 1.4x copy at the largest text preference can no
	-- longer fit the cluster in the band.
	local function bottomBar(compactForm: boolean): any
		-- THE TWO BOTTOM SHAPES SPEND THEIR SCARCE AXIS DIFFERENTLY. A portrait
		-- phone is width-poor and height-rich, so the band keeps a comfortable
		-- vertical rhythm and gives every horizontal pixel to the labels; a
		-- landscape phone is the mirror (313 safe px of height), so the band goes
		-- tight on BOTH axes. Horizontal `xs` on either is what keeps four terse
		-- names off the ellipsis on a 320px phone.
		local pad: any = if compactForm then "xs" else { left = "xs", right = "xs", top = "s", bottom = "s" }
		local ids = if compactForm
			then { fit = "TabsCompactFit", center = "TabsCompactCenter", row = "TabsCompact", wide = "TabsCompactWide" }
			else { fit = "TabsFit", center = "TabsShortCenter", row = "TabsShort", wide = "TabsShortWide" }
		return UI.ViewThatFits({
			id = ids.fit,
			width = FILL,
			children = {
				UI.VStack({
					id = ids.center,
					align = "center",
					width = FILL,
					children = { tabRow(ids.row, { natural = true, short = true, gap = "xs", pad = pad }) },
				}),
				tabRow(ids.wide, { natural = false, short = true, gap = "xs", pad = pad }),
			},
		})
	end

	local function sectionBody(id: string, build: (any) -> any): any
		local visible = scope:own(core:memo(function(use)
			return use(state.section) == id
		end))
		return UI.When({
			id = "Section_" .. id,
			condition = visible,
			transition = { enter = "fade", class = "container" },
			thenView = function(): any
				return UI.ZStack({
					id = "Body_" .. id,
					canvasGroup = true,
					-- A SECTION PLATE CLIPS, AND SAYS SO: a `canvasGroup` clips its
					-- subtree by engine rule, and the declaration keeps the solver's
					-- model agreeing with what the engine already does.
					overflow = "clip",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = { build(ctx) },
				})
			end,
		})
	end

	-- The two CONTENT panes still adapt by measurement, which is what a
	-- Composition is for: the detail lane sits beside the section when both
	-- clear their floors, folds under it when they do not, and drops entirely
	-- when even that will not fit.
	local panes = UI.Composition({
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
		-- no longer one of these regions, so it reads in the ring where it is
		-- PAINTED — the leading rail before the content, the bottom bar after it.
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
						id = "Sections",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							sectionBody("glades", overviewUI.glades),
							sectionBody("wisps", overviewUI.wisps),
							sectionBody("flora", overviewUI.flora),
							sectionBody("keeper", keeperUI.section),
						},
					}),
				},
			}),
			UI.Region({
				id = "Detail",
				group = "detail",
				rank = 2,
				children = { detailUI.lane(ctx) },
			}),
		},
	})

	-- The scaffold: one band above, one band below, the rail inside the middle
	-- row. Exactly one of the four Whens is live at a time (the placements are
	-- mutually exclusive) and none of them declares a transition, so a section
	-- button is never mounted in two homes at once.
	local screen = UI.Screen({
		id = "Glade",
		surface = "base",
		children = {
			UI.VStack({
				id = "Shell",
				gap = "s",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.When({ id = "TopBarWhen", condition = navTop, thenView = topBar }),
					UI.HStack({
						id = "Middle",
						gap = "m",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.When({ id = "SideRailWhen", condition = navSidebar, thenView = sideRail }),
							panes,
						},
					}),
					UI.When({
						id = "BottomFullWhen",
						condition = navBottomFull,
						thenView = function()
							return bottomBar(false)
						end,
					}),
					UI.When({
						id = "BottomCompactWhen",
						condition = navBottomCompact,
						thenView = function()
							return bottomBar(true)
						end,
					}),
				},
			}),
		},
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
