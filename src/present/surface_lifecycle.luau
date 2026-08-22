--!strict
--[[ Surface lifecycle — the three helpers that run a presented surface's life
	once it exists: the shared FOCUS-VISUAL sync (who draws the ring, whose
	Adjust bindings are live, where an armed drag session is aimed), the
	per-frame REFRESH body (re-render every handle, re-derive its focus map,
	re-feed its geometry, then re-place every anchored/disclosure/help plate),
	and DISMISSAL (`dismiss`, and `back` which is its modal half). Extracted
	verbatim from src/present/presenter.luau for Studio's 200,000-character
	`Source` WRITE cap — over it a module silently stops live-syncing into an
	open session, so a live check against it tests the built place rather than
	the edits on disk (docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md).

	WHY THESE THREE TOGETHER. They are the same subject read three times: the
	live `stack` and what each handle owes it. `refresh` calls the focus-visual
	sync at the end of its loop and `dismiss` un-paints the surface leaving the
	stack — the two halves of "the ring belongs to whoever owns input", which
	this file's history says must never be two copies (round 7's rule, quoted in
	the bodies below). Splitting them across two modules would re-create exactly
	the duplication the presenter spent seven director rounds removing.

	WHY THIS IS A SAFE SEAM. The test is not line count, it is: does the block
	read or WRITE a mutable upvalue of the `presenter.new` closure? Twenty names
	cross and nineteen are by-reference tables, functions declared once, or the
	presenter instance itself. The twentieth is `displayLayer`, the cross-surface
	z counter, and it is the one place this seam costs anything: `makeHandle`
	INCREMENTS it and `dismiss` RESETS it, so the scalar became a RECORD
	(`{ value = 0 }`) declared in the presenter and shared by reference — the
	`table.luau` technique the source-cap ledger names. Two writers in two files
	need one object, never two copies of a number.
	`tests/surface_lifecycle_seam.spec.luau` mechanises all of it against the
	live sources.

	`new(ctx)` returns the four names `presenter.new` bound before the move,
	under those exact names, so not one call site changed:
	  syncFocusVisuals(path)   the one shared observer body: ring ownership,
	                           focus-gated Adjust bindings, armed-follows-focus,
	                           and the two focus-driven plates
	  refresh()                the profiled per-frame body (`self.refresh`)
	  dismiss(handle)          pop a surface (or a chrome layer) and retire
	                           everything it owned
	  back()                   dismiss the topmost modal, if there is one

	ctx — every field is a FINAL value at construction time, which is what makes
	this one-way (the presenter builds this module after all of them exist):
	  graph, stack             the focus graph and the presented handles, base
	                           first — read live, never replaced
	  presenter                the presenter instance, so `back` and the refresh
	                           body reach `dismiss`/`syncFocusVisuals` through
	                           the same table every other caller uses
	  displayLayer             the cross-surface z record described above
	  anchoredSurfaces, helpPlate, calloutQueue
	                           the three surface registries a refresh re-syncs
	                           and a dismissal prunes
	  revalidateDisclosure, syncDisclosureFocus, syncHelpFocus
	                           the two focus-driven plates' engage/revalidate
	                           verbs (the full-value disclosure plate and its
	                           help-plate sibling)
	  syncTextReveal, retireRevealFor
	                           the no-pop text gate and the marquee strip's
	                           owner-scoped retirement
	  emitFeedback             the semantic feedback seam (ADR-0022 Decision 7)
	  refreshExclusive, syncScrim
	                           the exclusivity flag and the synthesized scrim,
	                           both of which a dismissal moves

	Strictly one-way: this never requires the presenter back. ]]

local transitionsLib = require("../render/transitions")
local profile = require("../core/profile")
local focusMap = require("./focus_map")

local isPathPrefix = focusMap.isPathPrefix
local filterHidden = focusMap.filterHidden
local filterGroupsHidden = focusMap.filterGroupsHidden
local focusOrder = focusMap.focusOrder
local traversalRank = focusMap.traversalRank

local surfaceLifecycle = {}

function surfaceLifecycle.new(ctx: any)
	local graph = ctx.graph
	local stack = ctx.stack
	local presenter = ctx.presenter
	local displayLayer = ctx.displayLayer
	local anchoredSurfaces = ctx.anchoredSurfaces
	local helpPlate = ctx.helpPlate
	local calloutQueue = ctx.calloutQueue
	local revalidateDisclosure = ctx.revalidateDisclosure
	local syncDisclosureFocus = ctx.syncDisclosureFocus
	local syncHelpFocus = ctx.syncHelpFocus
	local syncTextReveal = ctx.syncTextReveal
	local retireRevealFor = ctx.retireRevealFor
	local emitFeedback = ctx.emitFeedback
	local refreshExclusive = ctx.refreshExclusive
	local syncScrim = ctx.syncScrim

	-- the path an ARMED drag session was last aimed at, so "armed follows focus"
	-- re-aims on a focus MOVE rather than on every sync (see the block below)
	local lastArmedAim: string? = nil
	-- ...and whether the CURRENT armed session has been seen at all yet, so the
	-- arming frame seeds the aim instead of counting as a move
	local armedSeen = false
	-- the focus this function last ran on, so the arming frame can tell "focus is
	-- where it already was" from "arming moved focus here"
	local prevFocusPath: string? = nil

	-- one shared observer drives focus visuals across all presented handles
	local function syncFocusVisuals(path: string?)
		-- THE RING IS A NAVIGATION ANSWER, NOT A FOCUS ANSWER (the device round's
		-- pointer-vs-navigation rule): a pointer/touch-driven focus move tracks
		-- focus without drawing it.
		local ringVisible = graph.focusVisible:get() ~= false
		for _, handle in stack do
			local rootPath = "/" .. (handle.blueprint.id or "")
			--[[ SEGMENT-ALIGNED, because `/Menu` is a raw string prefix of
				`/MenuBar/Save` and this decides which surface draws the ring (the
				reuse audit's rule). `isPathPrefix` is the focus map's own
				segment-aware test and was already the right answer everywhere else
				in the presenter; this site wrote the unsafe form by hand. ]]
			local owns = path ~= nil and isPathPrefix(rootPath, path :: string)
			-- ...AND IT IS A CLAIM ABOUT WHO OWNS INPUT, SO A SURFACE THAT DOES NOT
			-- OWN IT DRAWS NO RING (director playtest 2026-08-03 round 4: "when i hit
			-- play and clicked on the world, the text field kept showing a focus ring
			-- even though input goes to the avatar").
			--
			-- A passive surface has focus IDENTITY from the moment it mounts —
			-- entry focus lands on its first focusable, which is correct and is what
			-- every consumer that follows focus depends on. What it does not have is
			-- the keyboard: it binds nothing until it engages. The ring was painted
			-- from `focusVisible` alone, which only answers "was the last focus move
			-- a pointer move or a navigation move", so a freshly mounted passive HUD
			-- drew a full ring while every key it looked ready to receive went to the
			-- avatar. The ring was not stale — it had never been true.
			--
			-- Clicking the world could not clear it either: a passive surface is not
			-- `currentExclusive`, so there is no catcher and the click is never seen.
			-- Gating on ownership fixes both halves at once — nothing to clear,
			-- because nothing was ever drawn.
			local ownsInput = not handle.isPassive or handle.responder:get() == "engaged"
			handle.controller.setFocusPath(if owns then path else nil, ringVisible and ownsInput)
			-- focus-gated Adjust bindings (matrix §B-Table): bind/unbind as focus
			-- enters/leaves a declared adjust target so gameplay keys are never
			-- shadowed while focus is elsewhere
			-- ...AND SO DO THE ADJUST BINDINGS (round 7). These were gated on focus
			-- alone, so a resigned surface kept Left/Right/Comma/Period bound to
			-- whatever its focus was standing on. It is inert today only because a
			-- passive surface's context is DISABLED — the keys are bound to a
			-- context that delivers nothing — which is luck, not design: the whole
			-- point of the dynamic binding is that a surface shadows no gameplay key
			-- it is not using, and "bound but currently undeliverable" is exactly the
			-- stuck-sink shape ADR-0014 forbids.
			if handle.syncAdjustBindings ~= nil then
				handle.syncAdjustBindings(if owns and ownsInput then path else nil)
			end
			-- ARMED FOLLOWS FOCUS (director virtual-controller round): while a
			-- session is armed, every focus move IS the aim — the verdict paints
			-- on the row you are standing on and the ghost rides along (RR
			-- SponsorGesture §3: ghost-follows-focus). Without this, navigation
			-- moved the ring but the session kept aiming at the hand, so a commit
			-- landed where the pickup began.
			--[[ …ON A FOCUS **MOVE**, NOT ON EVERY SYNC (director, 2026-08-04: "when
				I tap to pick up a card, racers are randomly highlighted red or
				green").

				This block was written when `syncFocusVisuals` ran from ONE place: the
				`graph.focused` observer, i.e. only when focus actually moved. Step 8
				(desktop keyboard navigation) promoted it to a method and started
				calling it unconditionally from `refresh()`, `engage()`, `resign()`
				and `present()` — so "re-aim on a focus move" silently became "re-aim
				on every frame".

				That is what put a verdict wash on a row nobody aimed at. A tap that
				ARMS deliberately skips the presenter's tap handler, so it never moves
				focus onto the card slot; focus stays wherever it was left — most
				often a racer row, because a successful play parks it there. The next
				refresh then aimed the armed session at that row and painted it green
				or red. It read as random because a pointer-origin focus move paints
				no ring, so the player could not see where focus was standing.

				Guarding on the path CHANGING restores the original meaning without
				re-splitting the ownership decision into a second observer (round 7's
				rule). `nil` is tracked too, so leaving and re-entering the same row
				re-aims. ]]
			if owns then
				local reg = if handle.controller.peekDragRegistry ~= nil
					then handle.controller.peekDragRegistry()
					else nil
				if reg ~= nil and reg.mode ~= nil and reg.mode() == "armed" then
					if not armedSeen then
						--[[ THE ARM ITSELF IS NOT A MOVE — but an arm that MOVES focus is.

							Seed from the focus as it stood BEFORE this session armed, not
							from the focus right now. That one distinction separates the two
							real flows:

							  · a touch tap-arm does not move focus at all (the tap path
							    that arms deliberately skips the presenter's tap handler),
							    so focus is still parked on whatever row the last play left
							    it on. Seed == current => no aim, which is the director's
							    report fixed: a pickup must not paint a row nobody chose.
							  · a gamepad arm that lands focus on the first eligible row HAS
							    moved it. Seed != current => aim, and the ghost hops to the
							    row the ring just went to, exactly as before.

							`prevFocusPath` is last call's focus, and this branch runs
							before it is updated below — so it is the pre-arm value. ]]
						armedSeen = true
						lastArmedAim = prevFocusPath
						if path ~= lastArmedAim then
							lastArmedAim = path
							reg.armTo(path)
						end
					elseif path ~= lastArmedAim then
						lastArmedAim = path
						reg.armTo(path)
					end
				else
					-- no session: the next arm seeds itself again from scratch
					armedSeen = false
					lastArmedAim = nil
				end
			end
		end
		-- FOCUS ENTER IS ONE OF THE THREE ENGAGEMENTS of the full-value
		-- disclosure plate. It rides this
		-- function rather than its own observer for the reason round 7 recorded: a
		-- second copy of the "does this surface own input" decision is a copy that
		-- will not get the next rule added to the original. A surface that is not
		-- painting a focus ring is not presenting a focus-driven plate either.
		syncDisclosureFocus(path)
		-- ...and so is a helped view's own sentence (D3a), from the same call and
		-- under the same ownership decision
		syncHelpFocus(path)
		-- recorded LAST, so the armed-aim seed above reads the PREVIOUS call's focus
		prevFocusPath = path
	end

	local function dismiss(handle: any)
		--[[ A CHROME LAYER IS NOT ON THE STACK (D3a). `presentAnchored{ chrome =
			true }` hand-mounts its own controller precisely so it can never take a
			focus scope or an input context, so there is nothing here to remove — its
			teardown is the anchored module's. One dismissal verb, two shapes. ]]
		if type(handle) == "table" and handle.chrome == true then
			anchoredSurfaces.dismissChrome(handle)
			return
		end
		local index = table.find(stack, handle)
		if index == nil then
			return
		end
		table.remove(stack, index)
		-- an ANCHORED surface stops being anchored the moment it leaves the stack
		-- (D1): the record and the placement signals it owns die here, not a frame
		-- later on the next sync
		anchoredSurfaces.prune()
		-- REDTEAM FIX (item 3, MAJOR; final-review-findings.md). `displayLayer`
		-- (the "cross-surface z" band-offset record presenter.luau declares, which
		-- `makeHandle` increments by 100 a surface) never went back down — a long-lived session
		-- that opens and closes 100 present/dismiss cycles pushes every FUTURE
		-- base screen's own `displayOrder` past the toast band (`SURFACE_LAYER
		-- .toast`, +10000 above base), and 300 cycles pushes it past the modal
		-- band too, silently reordering surfaces that were never touched.
		-- Reset to its base the moment the stack goes empty — the one point a
		-- fresh session and a long-lived one are indistinguishable (nothing is
		-- presented, so no live `handle.displayOrder` depends on the counter's
		-- current value), per the reviewer's own suggestion.
		if #stack == 0 then
			displayLayer.value = 0
		end
		handle.context.destroy()
		-- pop any live transient popup trap scopes first, so removing the base
		-- scope never leaves an orphaned trap on top (matrix §B PopupButton)
		if handle.clearTransientScopes ~= nil then
			handle.clearTransientScopes()
		end
		-- remove THIS handle's focus scope wherever it sits — dismissing a
		-- covered screen must not pop the live top scope (verifier F3)
		graph.removeScope(handle.blueprint.id or handle.kind)
		--[[ AND STOP PAINTING FOCUS ON THE WAY OUT (director playtest 2026-08-03
			round 5: "if the user does something that would dismiss the view, when
			the view goes away we give up focus").

			Removing the scope releases focus IDENTITY correctly — the graph moves
			to the next scope's entry, or to nil. What it cannot do is un-paint the
			departing surface: `syncFocusVisuals` iterates the live `stack`, and
			this handle was removed from it three lines above, so the focus change
			it just caused reaches every surface EXCEPT the one that was wearing the
			ring. With an exit transition the tree stays mounted for the whole
			animation, so the ring sat there, on a surface that had already stopped
			taking input, until the instances were destroyed. Measured: `graph focus
			= nil`, node still mounted, ring still `true`.

			The input half was already right. This makes the paint tell the same
			story. ]]
		handle.controller.setFocusPath(nil)
		-- ...and it stops being a SURFACE at the same moment, for the same reason
		-- (ADR-0028). With an exit transition the tree stays mounted and fully
		-- painted for the whole animation, and a departing screen covering its
		-- replacement is the transition rather than a defect — so the
		-- cross-surface overlap alarm's set of live surfaces is exactly this
		-- stack, and this is the one call that keeps the two equal.
		if handle.controller.retireSurface ~= nil then
			handle.controller.retireSurface()
		end
		-- ...and so does any disclosure plate this surface owns: the handle is out
		-- of `stack` above, so the revalidation resolves it (the full-value plate)
		revalidateDisclosure()
		-- ...and any help plate it raised, on the same call and for the same
		-- reason — a dismissed presenter may never refresh again (D3a)
		helpPlate.revalidate()
		-- ...and a callout whose surface this WAS is released from the queue, so
		-- the next one in line is promoted instead of the queue stalling (D3b)
		calloutQueue.prune()
		-- ...and the reveal strip goes with its owner SYNCHRONOUSLY, exactly as
		-- the plate does — a dismissed presenter may never tick again, and a
		-- strip that waited for one would leak its overlay and the held paint
		retireRevealFor(handle)
		-- the dismissal is a fact the moment it is decided, not when the pixels
		-- finish moving (the semantic feedback seam's causal frame, ADR-0022
		-- Decision 7)
		emitFeedback({ type = "dismiss", path = "/" .. (handle.blueprint.id or handle.kind), surface = handle })
		local function teardown()
			handle.controller.dispose()
			-- handle.scope owns the mount child scope; disposing it disposes the
			-- mounted tree exactly once (a separate root.dispose() here double-
			-- disposed the 'mount' child — phase-4 fault injection, input-switch)
			handle.scope:dispose()
			if handle.coordinator ~= nil then
				handle.coordinator.dispose()
			end
		end
		-- A DISMISSED SURFACE LEAVES THE STACK NOW AND THE SCREEN LATER. Its input
		-- context is destroyed, its focus scope popped and its exclusivity dropped
		-- above — a surface on its way out must never still take input — while the
		-- mounted tree and the instances live on until the exit completes, or until
		-- the coordinator's flat 500 ms cap fires. `dismiss` is idempotent through
		-- the stack check, so a second call during the exit does nothing.
		if handle.transition ~= nil and handle.coordinator ~= nil and handle.transitionNode ~= nil then
			local spec = transitionsLib.resolve(handle.transition)
			if spec.exit ~= "instant" then
				handle.coordinator.beginExit(handle.transitionNode.path, handle.transitionNode, spec, teardown)
				refreshExclusive()
				syncScrim()
				return
			end
		end
		teardown()
		refreshExclusive() -- dismissing a modal may lower the exclusive flag
		syncScrim() -- retire or re-home the scrim to the new top exclusive surface
	end

	local function back()
		for i = #stack, 1, -1 do
			if stack[i].kind == "modal" then
				presenter.dismiss(stack[i])
				return true
			end
		end
		return false
	end

	-- THE FRAME'S OWN SCOPE (2026-08-05). Everything below runs on the host's frame
	-- connection whether or not anything changed, and until this scope existed none of
	-- the nine layout phases could see it: they only open when there is layout work,
	-- so a frame that solved nothing profiled as free while costing 2 ms.
	-- RE-DERIVE THE FOCUS MAP from the CURRENT mounted tree, so focusables mounted or
	-- unmounted by `When`/`ForEach` stay reachable and dead paths never receive
	-- Activate (phase-1 verifier finding F1). The rank is re-derived here with the
	-- order, from the same tree walk, so a list that grew or shrank between presses
	-- ranks its current members and never sorts by a map describing rows that no
	-- longer exist.
	-- ONLY THE DERIVATION IS CACHED, NEVER THE GRAPH CALL (2026-08-05). `replaceGroups`
	-- and `setOrder` are not pure: on the topmost scope they re-seed focus when the
	-- current path is no longer in the order, and that re-seed is load-bearing for the
	-- passive/resign behaviour this project spent seven director rounds getting right.
	-- So the walk is skipped and the call is still made, with the same arguments it
	-- would have been given. Nothing downstream of this function can tell the
	-- difference; the two tree walks and the rank sort simply stop repeating.
	local function focusDerivation(handle: any): any
		local ctrl = handle.controller
		local epoch = if ctrl ~= nil and ctrl.structureEpoch ~= nil then ctrl.structureEpoch() else nil
		local cached = handle.focusDerived
		-- the FUNCTION is part of the key: `syncContributions` can swap a surface from
		-- the flat ring to `autoGroups` mid-refresh when a contribution with
		-- focusGroups mounts, and that changes the derivation without touching the tree
		if
			epoch ~= nil
			and cached ~= nil
			and cached.epoch == epoch
			and cached.fn == handle.navigationGroupsFn
			and cached.autoFocusMap == handle.autoFocusMap
		then
			return cached
		end
		local hidden = if ctrl ~= nil and ctrl.hiddenRoots ~= nil then ctrl.hiddenRoots() else nil
		local derived: any
		if handle.navigationGroupsFn ~= nil then
			local groups = filterGroupsHidden(handle.navigationGroupsFn(handle.root.node), hidden)
			derived = {
				grouped = true,
				groups = groups,
				rank = if handle.autoFocusMap == false then nil else traversalRank(handle.root.node, nil, groups),
			}
		else
			local order: { string } = {}
			focusOrder(handle.root.node, order)
			order = filterHidden(order, hidden)
			derived = { grouped = false, order = order, rank = traversalRank(handle.root.node, order, nil) }
		end
		derived.epoch = epoch
		derived.fn = handle.navigationGroupsFn
		derived.autoFocusMap = handle.autoFocusMap
		-- a controller with no epoch (a test double, an older adapter) simply never
		-- caches: `epoch == nil` fails the hit test above every time
		handle.focusDerived = if epoch ~= nil then derived else nil
		return derived
	end

	local function syncFocusMap(handle: any)
		local derived = focusDerivation(handle)
		local scopeName = handle.blueprint.id or handle.kind
		if derived.grouped then
			graph.replaceGroups(scopeName, derived.groups, derived.rank)
		else
			graph.setOrder(scopeName, derived.order, derived.rank)
		end
	end

	local refreshBody: () -> ()
	local function refresh()
		profile.span("present", refreshBody)
	end

	function refreshBody()
		for _, handle in stack do
			handle.controller.refresh()
			-- FIRST: re-discover the input contributions from the tree this refresh
			-- just re-rendered (device round 1, the crown bug). Before the focus map
			-- below,
			-- because a contribution that just mounted owns the groups that map is
			-- built from — wiring it a frame later would give the surface one frame
			-- of the wrong navigation model and, worse, one frame in which a tap on
			-- a freshly-mounted control dispatches to nothing.
			if handle.syncContributions ~= nil then
				handle.syncContributions()
			end
			-- a region that mounted since the last refresh has handles only now, so
			-- its enter transition's seeded values land here rather than a frame late
			if handle.coordinator ~= nil then
				handle.coordinator.flush()
			end
			-- re-feed solved geometry to keep-visible-aware controls (opt or
			-- every contribution's syncGeometry — see presenter.luau's
			-- makeHandle.feedGeometry)
			handle.feedGeometry(handle.controller.rectOf)
			-- a gated surface reveals itself the moment its text round closes
			syncTextReveal(handle)
			-- re-derive the focus map from the CURRENT mounted tree so
			-- focusables mounted/unmounted by When/ForEach stay reachable and
			-- dead paths never receive Activate (phase-1 verifier finding F1)
			-- the rank is RE-DERIVED here with the order, from the same tree walk, so
			-- a list that grew or shrank between presses ranks its current members
			-- and never sorts by a map describing rows that no longer exist
			profile.span("focusmap", function()
				syncFocusMap(handle)
			end)
			-- push/pop transient popup trap scopes now that the popup rows are
			-- mounted/unmounted (matrix §B PopupButton; transientScope) — AFTER the
			-- base order update so a close restores focus to the trigger cleanly
			if handle.syncTransientScopes ~= nil then
				handle.syncTransientScopes()
			end
		end
		-- re-gate the dynamic Adjust bindings and the focus ring: adjust targets may
		-- have churned (rows added/removed) even when the focused path is unchanged.
		--
		-- THROUGH THE SHARED FUNCTION, once, after the loop (round 7). This was a
		-- hand-rolled copy of the ownership decision that syncFocusVisuals makes —
		-- and being a copy, it did not get the ownership gate, so every refresh
		-- re-bound the Adjust keys onto a surface that had already resigned. That is
		-- the second time in this stage a duplicate of this exact decision has
		-- silently opted out of a rule added to the original (the first was
		-- `setFocusPath(current)` in presenter.luau's makeHandle). There is now one.
		presenter.syncFocusVisuals()
		-- ...and every ANCHORED surface re-reads its source (D1). AFTER the loop,
		-- because a surface is anchored to a rect that belongs to a DIFFERENT
		-- handle, which has only just re-rendered and re-fed its geometry. This is
		-- the cadence a real scroll already drives — the same one row_actions'
		-- floating menu re-aims on — so following a moving source asks nothing new
		-- of any caller and adds no watcher.
		anchoredSurfaces.sync()
		-- ...and a disclosure plate is checked against the tree that just
		-- re-rendered: its source node may be gone, or the re-solve may have made
		-- room for the label (the full-value plate again)
		revalidateDisclosure()
		-- ...and a help plate against the same tree, for the same reason (D3a)
		helpPlate.revalidate()
	end

	return {
		syncFocusVisuals = syncFocusVisuals,
		refresh = refresh,
		dismiss = dismiss,
		back = back,
	}
end

return surfaceLifecycle
