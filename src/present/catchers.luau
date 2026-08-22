--!strict
--[[ Catchers — the two full-viewport tap swallowers the presenter synthesizes:
	the modal/engaged SCRIM (modal-dismissal spec §2.2/§3.1) and the transient
	POPUP CATCHER (matrix section B PopupButton; `outsideDismiss`). Extracted
	verbatim from src/present/presenter.luau for Studio's 200,000-character
	`Source` WRITE cap — over it a module silently stops live-syncing into an
	open session, so a live check against it tests the built place rather than
	the edits on disk (docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md,
	and O-29, where exactly that cost this file a live verification).

	WHY THIS IS THE SEAM. The test that picks a safe extraction is not line
	count, it is: does the block read or WRITE a mutable upvalue of the
	`presenter.new` closure? This block writes only upvalues it also DECLARES
	(`scrim`, `popupCatcher`) — they are referenced nowhere else in the file —
	and everything it reads from the closure is either a by-reference table
	(`stack`, the presenter instance) or a pure function (`metricsNow`). Zero
	entanglement, so the move is behaviour-preserving by construction.

	`new(ctx)` returns the five names presenter.new bound before the move, under
	those exact names, so not one call site changed:
	  applyOutsideOutcome(candidate, engagedPassive)  the one non-destructive
	                       outside-tap/Cancel/Close outcome (used by the surface
	                       tap handler in `makeHandle` too)
	  syncScrim()          keep exactly ONE scrim beneath the top exclusive
	                       surface, and re-sync the popup catcher
	  syncPopupCatcher() / topPopupCatcherPath() / topScrimPath()
	                       rebound onto the presenter instance as
	                       `self.syncPopupCatcher` etc. — the shapes tests and
	                       consumers already call

	`currentExclusive()` is returned too: it is the "who owns outside-tap" query
	both catchers resolve against, and it belongs beside them.

	ctx (the first four are passed BY REFERENCE, which is what makes them safe):
	  core, env, adapter   the injected engine seam, exactly as presenter has it
	  stack                the presented handles, base first — read live, never
	                       replaced
	  presenter            the presenter instance, so `applyOutsideOutcome` can
	                       reach `presenter.dismiss` (defined far below this
	                       block in the original file — it was `self.dismiss`
	                       there for the same late-binding reason)
	  metricsNow()         the LIVE metric authority (ADR-0019 §2), read per use
	                       so a theme commit moves the dismiss geometry in the
	                       same frame it moves the rects

	Strictly one-way: this never requires the presenter back. ]]

local mountLib = require("../mount")
local blueprintLib = require("../blueprint")
local chrome_slots = require("../tokens/chrome_slots")
local renderer = require("../render/renderer")
local modalZones = require("./modal_zones")
local focusMap = require("./focus_map")

local modalInZoneA = modalZones.modalInZoneA
local zoneAContains = modalZones.zoneAContains
local nodeAt = focusMap.nodeAt

local catchers = {}

function catchers.new(ctx: any)
	local core = ctx.core
	local env = ctx.env
	local adapter = ctx.adapter
	local stack = ctx.stack
	local presenter = ctx.presenter
	local metricsNow = ctx.metricsNow

	-- ===== synthesized scrim / catcher (modal-dismissal spec §2.2/§3.1) ========
	-- The presenter mounts ONE full-viewport catcher beneath the top EXCLUSIVE
	-- surface (a modal, or an engaged-from-passive surface). It closes the
	-- Drive-F1 empty-space gap (every tap now hits something), is the modal
	-- barrier (blocks lower surfaces), and doubles as the "region B exists"
	-- affordance. It is presenter-private: NOT in `stack`, NOT focusable, NOT in
	-- any focus scope, on a path outside every blueprint root ("/__scrim__/...").
	local scrim: any = nil -- { scope, controller, path, owner, mode }

	-- one non-destructive outcome for outside-tap, Cancel (B), and Close (spec
	-- §2.3): a modal dismisses (or SWALLOWS if it declined outside-dismiss — a
	-- true barrier, never a clickthrough); an engaged-passive surface resigns.
	local function applyOutsideOutcome(candidate: any, engagedPassive: boolean)
		if candidate.kind == "modal" then
			if candidate.outsideTapCancel then
				presenter.dismiss(candidate)
			end
			-- outsideTapCancel=false: swallow (barrier), no dismiss, no clickthrough
		elseif engagedPassive then
			candidate.resign() -- back to passive (ADR-0014), not disposal
		end
	end

	local function currentExclusive(): any?
		for i = #stack, 1, -1 do
			local h = stack[i]
			if h.kind == "modal" or (h.isPassive and h.responder:get() == "engaged") then
				return h
			end
		end
		return nil
	end

	local function disposeScrim()
		if scrim ~= nil then
			scrim.controller.dispose()
			scrim.scope:dispose()
			scrim = nil
		end
	end

	-- a scrim tap: Zone A (panel + ring + button hit rects) does nothing (benign
	-- near-miss); Zone B resolves the one non-destructive outcome.
	local function onScrimInteraction(meta: any)
		local owner = if scrim ~= nil then scrim.owner else nil
		if owner == nil then
			return
		end
		local x = if type(meta) == "table" then meta.x else nil
		local y = if type(meta) == "table" then meta.y else nil
		local resigning = owner.isPassive and owner.responder:get() == "engaged"
		--[[ ZONE A IS DISMISSAL FORGIVENESS, AND A RESIGN IS NOT A DISMISSAL
			(director playtest 2026-08-03 round 7: "i have the slider selected. i
			click on the world. the slider still shows focus. left/right go to the
			slider.")

			Zone A is the union BOUNDING BOX of every painted node on the surface,
			inflated by a spacing step, plus every focusable's 44px hit rect. That is
			right for a modal: a fat-finger just outside a card must not destroy it,
			and a card's bbox is a card.

			It is wrong for an engaged HUD. Its bbox is the whole UI extent, so
			"outside" barely exists — measured on the keyboard fixture, the slider
			track alone is 803px wide at y=163..207 and the union bbox reaches
			y≈447 across the full viewport. A click at (600,225) is empty world to
			a player and Zone A to this check, so nothing resigned: the ring stayed,
			and the Adjust keys stayed bound to the slider. A click far below it at
			(600,780) resigned correctly, which is why this survived my own live
			check — I had happened to click below the box.

			So the forgiveness applies to the DESTRUCTIVE outcome only. A resign is
			cheap and reversible, and a click that reached this catcher has already
			missed every real UI node above it (the catcher sits at
			displayOrder - 50), so there is nothing left to forgive. ]]
		if not resigning and x ~= nil and y ~= nil and modalInZoneA(owner, x, y, metricsNow()) then
			return -- Zone A: forgiveness / a tap on the painted panel itself
		end
		applyOutsideOutcome(owner, resigning)
	end

	--[[ ONE DEFINITION OF "AN INVISIBLE FULL-VIEWPORT TAP SWALLOWER", shared by
		BOTH catchers this presenter synthesizes — the modal/engaged scrim below
		and the transient popup catcher further down.

		IT IS ONE FUNCTION BECAUSE IT SHIPPED AS TWO AND THE SECOND ONE PAINTED
		(director device report 2026-08-13: "when i swipe from left to right in
		swipe row actions/table, some random thing appears over the top of the
		screen blocking the demo picker and settings button"). `mountScrim`
		learned both halves of "invisible" live, under the P5 packages;
		`mountPopupCatcher` — written later, for the identical job — inherited
		NEITHER, so an open row-actions tray (row_actions.luau publishes
		`outsideDismiss.active` for exactly as long as a tray is open) synthesized
		a catcher that wore the installed package's button plate. A second `if`
		for a sibling case means the first one was the bug; a second COPY of a
		declaration means the same thing.

		SURFACE — the caller's one axis of freedom, and the only one. "scrim" DIMS
		at scrimOpacity; "plain" is the suppressed surface — no fill, no
		interactive tag, no corner, no stroke. NO surface at all is the defect:
		a Button with none still classifies as `control` (chrome_slots.classify
		falls every `Button` through to the control slot), so the invisible
		catcher wears the installed package's SOLID control colour across the
		whole viewport and hides what it is guarding. Both suppressed values are
		what `sheet_model.classifyTags` already treats as paint-free.

		NOT A DECORATION SURFACE either (ADR-0020 R9 / chrome_slots.NO_SLOT).
		Nothing generic can tell a catcher apart from a real button, so every
		image-driven package materialized its button plate over the whole screen —
		the same defect class the Slider's accent fill needed the hint for. This
		is load-bearing in the DIMMING case specifically, where `surface` is
		"scrim" rather than "plain" and so does not itself suppress the slot.

		FOCUSABLE = false: never in the focus walk, never in navigation, in either
		mode.

		=== WHAT SUPPLIES "INVISIBLE", AND WHY THAT IS WORTH SAYING OUT LOUD ===
		(DIR5 fix round, 2026-08-21, after the third report of "the popup background
		is opaque" and a review that refuted the mechanism the second fix claimed.)

		A `plain` catcher's transparency is NOT owned by its declaration. `plain`
		earns no `facet-surface-*` tag at all (`sheet_model.classifyTags` — that is
		what "suppressed" means), so in NATIVE mode the only rule that reaches it is
		the CLASS DEFAULT, `Button default` (`TextButton` -> `BackgroundTransparency
		= 1`). Measured, on the built neutral sheet and on a live engine: it resolves
		to exactly 1, i.e. correctly invisible. So the class default was never the
		source of an opaque catcher — and `tests/popup_catcher_paint.spec.luau`
		now resolves that number for EVERY catcher this file can mount, rather than
		asserting the declaration and hoping. If `Button default` is ever renamed,
		reordered under a rule that paints, or a state rule starts carrying a fill,
		all three paths redden together instead of one of them shipping opaque.

		THE ONE THING NO DECLARATION HERE CAN OWN, measured live in Studio and
		recorded in artifacts/expand-plate/catcher-paint-window.md: in native mode the
		adapter writes NO `BackgroundTransparency` at create — an explicit write would
		permanently defeat every surface rule (spike m10) — and the styling pass does
		not apply on the frame an instance is created. Measured ~3 frames, during
		which `GetStyled` reports the CLASS DEFAULT (0, opaque) for a `plain` catcher
		AND for a `scrim` one. A full-viewport catcher is the worst possible member of
		that class, and it is why a `GetStyled` reading taken near a catcher's birth is
		not evidence about its settled paint. Nothing in this file can close that
		window; what it can do is not add a second, permanent way to be opaque.

		WHY THESE STAY `plain` AND THE EXPAND PLATE DOES NOT. A menu at a button, an
		engaged HUD and an open row-actions tray must not dim the screen — the catcher
		is a tap swallower, not a backdrop, and a dim there would be a product
		regression. A region's EXPAND plate is the opposite: it is a modal that covers
		content, and the dim is how a player is told the screen behind it is not live.
		That one wears `scrim`, whose number the THEME owns and the player's
		`PreferredTransparency` composes against (ADR-0035). Both answers are
		deliberate; neither is a default nobody chose.

		Full write-up, with the live same-adapter A/B that measured it:
		docs/lessons/an-invisible-surface-declares-its-invisibility.md ]]
	local function catcherScreen(rootId: string, surface: string): any
		local catcher: { [string]: any } = {
			id = "catcher",
			label = "",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			focusable = false,
			surface = surface,
		}
		local catcherBlueprint = chrome_slots.attachHint(blueprintLib.Button(catcher), { slot = chrome_slots.NO_SLOT })
		return blueprintLib.Screen({ id = rootId, children = { catcherBlueprint } })
	end

	-- mount the catcher beneath `owner`. mode "scrim" = dim at scrimOpacity
	-- (modals); "none" = transparent but still catching (engaged HUDs, §3.6).
	local function mountScrim(owner: any, mode: string): any
		local bp = catcherScreen("__scrim__", if mode ~= "none" then "scrim" else "plain")
		local sc = core:scope("present-scrim")
		local root = mountLib.mount(core, bp, { scope = sc:child("mount") })
		local controller = renderer.attach(core, root, env, adapter, {
			-- edge-to-edge: the dim/barrier covers the whole viewport (incl. insets)
			rootPolicy = "edgeToEdge",
			onNodeTap = function(_path: string, meta: any?)
				onScrimInteraction(meta)
			end,
		})
		controller.initialRender()
		if controller.setDisplayOrder ~= nil then
			controller.setDisplayOrder(owner.displayOrder - 50)
		end
		return {
			scope = sc,
			controller = controller,
			root = root,
			path = "/__scrim__/catcher",
			owner = owner,
			mode = mode,
		}
	end

	-- keep exactly ONE scrim, beneath the current top exclusive surface. Only the
	-- top modal's scrim is live (spec §3.5): as the top changes, the scrim moves.
	-- ===== transient-popup catcher (matrix section B PopupButton; outsideDismiss)
	-- A PLAIN base screen with an OPEN PopupButton (a contribution whose
	-- outsideDismiss is active) is NOT exclusive, so the modal scrim above never
	-- covers it. The presenter synthesizes a SEPARATE transparent full-viewport
	-- catcher beneath that screen so a tap on EMPTY space dismisses the popup
	-- (Zone-A geometry over the contribution's own subtree). A tap on a rendered
	-- sibling above the catcher is handled in onNodeTap (path-outside test). A
	-- real modal/engaged surface SUPPRESSES this catcher (currentExclusive gate),
	-- so the two mechanisms never stack.
	local popupCatcher: any = nil -- { scope, controller, root, path, owner, contribPath, dismiss, consume }

	-- KNOWN LIMITATION (item 6, MINOR; final-review-findings.md): ONE global
	-- catcher slot for potentially MANY simultaneously-active `outsideDismiss`
	-- contributions on the same screen — e.g. a PopupButton AND a Table with
	-- an open row's tray, both open at once. `currentPopupOwner` below
	-- returns the FIRST such contribution in per-handle document order; if a
	-- Table's `rowActions` contribution sits earlier in the tree than a
	-- PopupButton also open on the same screen, the PopupButton's own
	-- empty-space (Zone B) dismiss is silently starved — the catcher tracks
	-- only one owner at a time. The RENDERED-sibling path (`onNodeTap`
	-- below) is NOT affected: it walks every active contribution on every
	-- tap, independent of this slot. Investigated for this fix wave: a real
	-- fix is either (a) one catcher per active contribution — a stack of
	-- full-viewport transparent surfaces whose relative Zone-A/Zone-B
	-- geometry and z-order interaction is genuinely new design surface, not
	-- a mechanical change, or (b) resolving `currentPopupOwner` by
	-- z-order/recency instead of document order, which only narrows WHICH
	-- one contribution wins, never fixes the two-simultaneous-consumers case
	-- itself. Neither is a small, mechanical fix, so this wave documents the
	-- limitation here rather than shipping a partial one; ledgered as a
	-- follow-up (multi-owner popup catcher) rather than fixed.
	local function currentPopupOwner(): (any?, any?)
		if currentExclusive() ~= nil then
			return nil, nil -- a modal / engaged-passive surface owns outside-tap
		end
		for i = #stack, 1, -1 do
			local h = stack[i]
			for _, c in h.contributions or {} do
				local od = c.bundle.outsideDismiss
				if od ~= nil and od.active ~= nil and od.active:get() == true then
					return h, c
				end
			end
		end
		return nil, nil
	end

	local function disposePopupCatcher()
		if popupCatcher ~= nil then
			popupCatcher.controller.dispose()
			popupCatcher.scope:dispose()
			popupCatcher = nil
		end
	end

	-- a catcher tap: Zone A (the popup's painted panel + ring + hit rects) does
	-- nothing (a benign near-miss / a tap on the popup itself); Zone B dismisses.
	--
	-- REDTEAM FIX (item 7, MINOR; final-review-findings.md). Task 7's own
	-- investigation into this exact function (row-actions-implementation/
	-- task-7-report.md, "The catcher-semantics investigation") found only ONE
	-- `outsideDismiss` consumer and concluded a Zone-B tap here is always
	-- correct to swallow: "there is nothing else at that point that could
	-- have received the tap." That was true for a plain popup world. It is
	-- NOT true once the `owner` surface can itself be PASSIVE (row-actions'
	-- own Table integration, mounted over live, un-engaged gameplay — a
	-- RascalRally-shaped HUD): empty catcher space there is not "nothing,"
	-- it is the game underneath. `consume == false` (row_actions.luau's own
	-- `outsideDismiss`, added by that same task for the RENDERED-sibling
	-- path below in `onNodeTap` — "closing must not swallow unrelated
	-- clicks") has to mean the identical thing here. The one thing it must
	-- NOT mean: engaging `owner` as a side effect of a dismiss that pressed
	-- nothing at all — a tray-close tap over open gameplay must never be
	-- what sinks that gameplay's own input (the rendered-sibling path's own
	-- "tap on a focusable inside a passive surface engages it" step,
	-- `onNodeTap` below, is deliberately NEVER reached from here, consume or
	-- not — there is no real focusable at an empty-space tap to engage
	-- toward). `popupCatcher.consume` is read explicitly (not just relied
	-- on by omission) so this stays a locked, tested invariant rather than
	-- something a future "let it fall through like the other path does"
	-- edit could accidentally wire straight into `owner.engage()`.
	local function onPopupCatcherTap(meta: any)
		if popupCatcher == nil then
			return
		end
		local owner = popupCatcher.owner
		local x = if type(meta) == "table" then meta.x else nil
		local y = if type(meta) == "table" then meta.y else nil
		local sub = nodeAt(owner.root.node, popupCatcher.contribPath)
		if x ~= nil and y ~= nil and zoneAContains(owner.controller.rectOf, sub, x, y, metricsNow()) then
			return -- Zone A
		end
		-- captured BEFORE `dismiss()`: the popup's own `active` readable
		-- flipping false can synchronously fan out through `syncPopupCatcher`
		-- (`core:observe`'s own subscriber, wired below) and dispose THIS
		-- `popupCatcher` — reading `.consume` off it AFTER the call risks
		-- indexing an already-nil'd local (caught live: exactly this crashed
		-- PopupButton's own "dismisses on a tap in EMPTY space" test, whose
		-- `consume` is nil/default-true but the read happened post-dismiss
		-- regardless).
		-- captured BEFORE `dismiss()`: the popup's own `active` readable
		-- flipping false can synchronously fan out through `syncPopupCatcher`
		-- (`core:observe`'s own subscriber, wired below) and dispose THIS
		-- `popupCatcher` — reading `.consume` off it AFTER the call risks
		-- indexing an already-nil'd local (caught live: exactly this crashed
		-- PopupButton's own "dismisses on a tap in EMPTY space" test, whose
		-- `consume` is nil/default-true but the read happened post-dismiss
		-- regardless).
		local consume = popupCatcher.consume
		popupCatcher.dismiss()
		if consume == false then
			-- not swallowed: still no rendered node was actually pressed, so
			-- there is nothing to activate and — see the comment above —
			-- `owner` is never engaged as a consequence of this tap either.
			return
		end
	end

	local function mountPopupCatcher(owner: any, contribPath: string, dismiss: () -> (), consume: boolean?): any
		--[[ ALWAYS "plain" — this catcher never dims; it exists only to swallow one
			outside tap. Until 2026-08-13 it declared no surface at all and built its
			own Button inline rather than going through `catcherScreen`, and both
			halves of "invisible" were therefore missing: an open row-actions tray
			painted the installed package's button plate over the viewport. It read
			as "over the top of the screen" rather than "over everything" because the
			catcher mounts at `owner.displayOrder - 50` — the base screen covers it
			wherever the base screen paints, and the showcase's inset chrome band
			(the demo picker and Settings) is exactly where it does not.
			tests/popup_catcher_paint.spec.luau pins it from both live
			`outsideDismiss` owners. ]]
		local bp = catcherScreen("__popupcatcher__", "plain")
		local sc = core:scope("present-popup-catcher")
		local root = mountLib.mount(core, bp, { scope = sc:child("mount") })
		local controller = renderer.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			onNodeTap = function(_path: string, meta: any?)
				onPopupCatcherTap(meta)
			end,
		})
		controller.initialRender()
		if controller.setDisplayOrder ~= nil then
			--[[ BELOW EVERY LIVE SURFACE, NOT BELOW `owner` (device review
				2026-08-16, F2). The rule this catcher has always meant is the one both
				comments above state — *"a click that reached this catcher has already
				missed every real UI node above it"*, and *"the base screen covers it
				wherever the base screen paints"*. It was WRITTEN as `owner.displayOrder
				- 50`, which says that only while `owner` IS the base screen — and for
				both consumers it was written for it is: `row_actions`' tray and
				`popup_button`'s panel each publish `outsideDismiss` from a contribution
				on the base handle, so the two expressions agree exactly and this change
				moves neither.

				`newCallout` is the first `outsideDismiss` owner that is itself a
				PRESENTED SURFACE ABOVE the base screen. Its anchored surface sits at
				base + 100 (`presenter.luau`'s `displayLayer += 100`), so `- 50` put this
				full-viewport, input-SINKING `Button` at base + 50 — over every control
				the coach mark is documented never to block. Measured on the gallery
				fixture: base screen 10100, catcher 10150. On device that makes the whole
				screen one dismiss target: the next press lands on the catcher instead of
				the button it was aimed at, retires the plate permanently (`retired` is a
				one-way latch), and the coach marks "stopped appearing".

				The MINIMUM over the live stack is that same invariant said in a way that
				stays true when the owner is not the bottom: a catcher is the fallback
				for a tap that hit NOTHING, so it belongs under everything that could
				have been hit. ]]
			local lowest = owner.displayOrder
			for _, h in stack do
				local order = h.displayOrder
				if type(order) == "number" and order < lowest then
					lowest = order
				end
			end
			controller.setDisplayOrder(lowest - 50)
		end
		return {
			scope = sc,
			controller = controller,
			root = root,
			path = "/__popupcatcher__/catcher",
			owner = owner,
			contribPath = contribPath,
			dismiss = dismiss,
			-- REDTEAM FIX (item 7, MINOR): threaded straight from the owning
			-- contribution's own `outsideDismiss.consume` (see `syncPopupCatcher`
			-- below) so `onPopupCatcherTap` can honor it — the same flag the
			-- rendered-sibling path in `onNodeTap` already reads.
			consume = consume,
		}
	end

	local function syncPopupCatcher()
		local owner, c = currentPopupOwner()
		if owner == nil or c == nil then
			disposePopupCatcher()
			return
		end
		if popupCatcher ~= nil and popupCatcher.owner == owner and popupCatcher.contribPath == c.path then
			return
		end
		disposePopupCatcher()
		popupCatcher =
			mountPopupCatcher(owner, c.path, c.bundle.outsideDismiss.dismiss, c.bundle.outsideDismiss.consume)
	end
	local function topPopupCatcherPath(): string?
		return if popupCatcher ~= nil then popupCatcher.path else nil
	end

	local function syncScrim()
		local topEx = currentExclusive()
		if topEx == nil then
			disposeScrim()
			syncPopupCatcher() -- no exclusive surface: a base popup may want a catcher
			return
		end
		local mode = topEx.scrimMode
		if scrim ~= nil and scrim.owner == topEx and scrim.mode == mode then
			syncPopupCatcher() -- an exclusive surface suppresses the popup catcher
			return
		end
		disposeScrim()
		scrim = mountScrim(topEx, mode)
		syncPopupCatcher()
	end
	local function topScrimPath(): string?
		return if scrim ~= nil then scrim.path else nil
	end
	return {
		applyOutsideOutcome = applyOutsideOutcome,
		currentExclusive = currentExclusive,
		syncScrim = syncScrim,
		syncPopupCatcher = syncPopupCatcher,
		topPopupCatcherPath = topPopupCatcherPath,
		topScrimPath = topScrimPath,
	}
end

return catchers
