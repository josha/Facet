--!strict
-- Presenter (design §12.1): owns screen/modal lifetimes, ScreenGui-level
-- policy (via the render adapter), focus scopes, and InputContext lifetime +
-- priority. Never owns game state. Engine-free: the adapter and action system
-- are injected (FakeTarget + headless actions in tests; ScreenTarget + IAS on
-- the client).
-- present(blueprint, opts)      -> handle   (base screen)
-- presentModal(blueprint, opts) -> handle   (focus trap + higher-priority sink context)
-- dismiss(handle) / back()      -> pops the top modal (Cancel routing)
-- withAnimation(class, fn)      -> runs fn in its own transaction and forces its
--   own commit, so the nodes fn MOVED are painted travelling from where they
--   used to be (docs/plans/parity-round2.md §Phase 1). The verb lives
--   here because the clock, the controller scopes and `refresh` all do.

local mountLib = require("../mount")
local blueprintLib = require("../blueprint")
local renderer = require("../render/renderer")
local focus_graph = require("../focus/focus_graph")
-- structural transitions, the toast model and the semantic feedback seam
-- (ADR-0022 Decisions 3, 4, 7). Each is engine-free and driven from here.
local transitionsLib = require("../render/transitions")
local toast_schedule = require("./toast_schedule")
local feedbackLib = require("./feedback")
local motionClockLib = require("../motion/clock")
-- the motion-class registry, read by `withAnimation` so an unknown name and an
-- inline params table are refused by the one dial the whole framework uses
local motionClasses = require("../motion/classes")
local motionCurves = require("../motion/curves")
local profile = require("../core/profile")
-- the metric authority (ADR-0019 §2). The modal-dismissal spec pins the
-- forgiveness ring to space.l and the target ring to the effective hit floor;
-- both are now THEME values read from the live `themeMetrics` fact, so a theme
-- with roomier spacing gets a proportionally roomier dismiss ring for free.
local themeSnapshot = require("../themes/snapshot")
local specGuard = require("../spec_guard")
-- D1, the anchored-surface seam: the PURE placement decision (preferred edge,
-- safe-area flip, along-edge shift, arrow tail) and the presented surface built
-- on it. The disclosure plate below is one of the two hand-rolled precedents the
-- pure solver replaced — it asks `anchorPlacement.solve` now instead of carrying
-- its own copy of the same four rules.
local anchorPlacement = require("../layout/anchor_placement")
local anchoredLib = require("./anchored")

local presenter = {}

-- present()/presentModal()/presentCritical() options (verifier F4: the
-- presenter surface is typed, not `any`)
export type PresentOpts = {
	rootPolicy: string?,
	onActivate: ((path: string?, meta: any?) -> ())?,
	onAdjust: ((path: string, direction: number, rectOf: (string) -> any) -> ())?,
	onFocusNav: ((path: string) -> ())?,
	onReorderNav: ((path: string, direction: number) -> ())?,
	sinkNavigation: boolean?,
	-- responder mode (ADR-0014, present() only). Absent/nil = today's
	-- engaged-open semantics (context enabled, non-sinking — correct for a
	-- UI-only place). "passive" = a HUD that binds nothing gameplay-contended:
	-- its nav context is created DISABLED, so deviceKey navigation reaches lower
	-- (gameplay) contexts and never moves the HUD's focus. A passive surface
	-- becomes first responder via a tap on one of its focusables or handle.engage(),
	-- and drops back on Cancel / outside-tap / handle.resign(). presentModal is
	-- always engaged-exclusive regardless of this opt.
	responder: string?, -- "passive"
	-- LINEAR TRAVERSAL wrap policy for this surface's focus scope (roadmap
	-- Step 8). Default true: Tab past the last control returns to the first, and
	-- Shift+Tab off the first goes to the last. Set false for a surface where
	-- running off the end should mean "stop" — a step-by-step form whose author
	-- wants the end of the chain to feel like an end. It is declared HERE, per
	-- surface, and never by a control: the plan's rule is one consistent policy
	-- per active scope. It governs Tab only; a NavigationGroup's own `wrap`
	-- still governs the directional arrows along that group's axis.
	traversalWrap: boolean?,
	-- where focus lands when this surface appears: "first" (default), "none", a
	-- node id, or { id = "…" } when the id collides with one of those two words
	initialFocus: (string | { id: string })?,
	-- Per-surface override of the presenter's `keyboardNavigation` default: `true`
	-- turns the desktop keyboard conventions on for this surface, `false` off,
	-- `nil` inherits. Turning it ON also makes this surface's input context SINK
	-- while it is engaged — the whole point is that the keys it claims (Space, the
	-- arrows) stop reaching the avatar underneath, which is what "the UI has focus"
	-- has to mean to a player. See api.md § Desktop keyboard conventions.
	keyboardNavigation: boolean?,
	-- engine-selection bridge (the native-substrate round): presentModal-only
	-- opt-in that mirrors Facet's logical focus to GuiService.SelectedObject
	-- while the modal owns UI input. Ignored on present() (passive/gameplay
	-- surfaces keep SelectedObject nil, the same round's finding). Experiment until the
	-- physical-gamepad non-interference proof closes; reversible by omitting the opt.
	engineSelectionBridge: boolean?,
	-- NO-POP TEXT (text-measurement milestone): mount and measure with the
	-- surface's ROOT hidden, and reveal it once the text is exact. Exact text
	-- arrives one re-solve after the first solve, so an ungated screen appears
	-- with conservatively-wide boxes and then visibly shrinks. The shrink is
	-- always safe (the estimate can only over-reserve; nothing ever clips) but
	-- "usually doesn't jump" is not a property a designer can build on.
	--
	-- Bounded by `revealTimeout` seconds, because a UI that never appears is a
	-- worse failure than one that jumps: on timeout the surface is revealed with
	-- the safe boxes. Needs an adapter with setRootVisible; without one the
	-- surface simply reveals immediately rather than hiding forever.
	revealWhenTextExact: boolean?,
	revealTimeout: number?, -- default 2s
	-- gameplay guard (ADR-0014): an engaged-exclusive context (modal, or a
	-- passive surface once engaged) binds Space to a no-op GameplayGuard so the
	-- keyboard jump is sunk while it is first responder (ButtonA is already sunk
	-- via Activate, arrows/D-pad via Navigate). Default true; set false for a
	-- surface that wants Space (a word-game modal). WASD is not sunk in v1.
	gameplayGuard: boolean?,
	-- grouped, direction-aware focus (§9.3; verifier F2): NavigationGroups
	-- for this screen's scope. When present, Up/Down/Left/Right (and dpad)
	-- route through graph.navigateDirection; Left/Right adjust bindings are
	-- unavailable on such screens (grouped navigation owns the horizontal).
	-- static array, or a function of the mounted root re-evaluated on every
	-- refresh (dynamic surfaces: tables whose rows churn/reorder). ABSENT =
	-- auto-derive: from mounted input contributions when any provides focusGroups,
	-- else from the mounted LAYOUT structure when it has a horizontal container or
	-- Grid with >=2 focusables (HStack row -> horizontal group; Grid -> per-row 2D
	-- groups), else the flat ring (ADR-0013's automatic navigation groups). `false` = force the flat ring,
	-- ignoring both (a legacy flat-list consumer opting out of auto-grouping).
	navigationGroups: ({ focus_graph.NavigationGroup } | (rootNode: any) -> { focus_graph.NavigationGroup } | boolean)?,
	-- presentModal only (ADR-0013's modal outside-tap rule): while this modal is on top, a pointer/
	-- touch tap whose path is NOT owned by the modal's blueprint dismisses the
	-- modal (platform sheet outside-tap) and never routes to a lower screen.
	-- Default true; set false to restore legacy clickthrough routing. A scrim or
	-- close button living INSIDE the modal blueprint is owned by it and routes
	-- normally, so consumers with an in-blueprint scrim are unaffected.
	outsideTapCancel: boolean?,
	-- what the CANCEL verb (gamepad ButtonB) does to this surface.
	--   "dismiss" (default) — today's contract, unchanged: a modal dismisses, an
	--                         engaged-from-passive surface resigns (ADR-0014).
	--   "none"              — Cancel does nothing to THIS surface. For a
	--                         MANDATORY surface: a modal whose choice has no
	--                         legal "not now" (a role pick that parks the player
	--                         until they choose), where dismiss-on-B would strand
	--                         them behind a decision they never made.
	-- Orthogonal to `outsideTapCancel` (the pointer path) by design: a mandatory
	-- modal sets BOTH. Cancel is still OFFERED to the focused contribution's
	-- `handleCancel` first either way — a control inside the surface keeps its own
	-- cancel (an open popup still closes) — this opt only governs what the
	-- SURFACE does when nothing consumed it. `presenter.dismiss(handle)` and
	-- `presenter.back()` are explicit programmatic calls and are NOT gated by it.
	cancelPolicy: string?, -- "dismiss" | "none"
	-- scrim/catcher appearance (modal-dismissal spec §2.2/§3.1). The presenter
	-- synthesizes a full-viewport catcher beneath the top exclusive surface so
	-- outside taps land on SOMETHING (closes the empty-space gap) and lower
	-- surfaces are blocked. "scrim" (default for modals) dims at the scrimOpacity
	-- token (0.45); "none" is fully transparent but STILL catching (a transient
	-- popover, or an engaged HUD that must keep the world visible — the default
	-- for a passive surface once engaged, §3.6).
	scrim: string?, -- "scrim" | "none"
	-- consume a navigation direction before focus moves (gamepad grab mode:
	-- a grabbed row eats up/down to reorder itself). Return true = consumed.
	onNavigateIntercept: ((direction: string) -> boolean)?,
	-- post-layout geometry hook (§17 Phase 5 keyboard occlusion): called with
	-- the controller's rectOf after the initial render and after every refresh,
	-- so a control can read its own solved rects (a text field feeds its rect
	-- into its keep-visible policy). Generic: never text-specific.
	--
	-- ADDITIVE, not an override (see feedGeometry): passing this does NOT suppress
	-- the contributions' own `syncGeometry`, so a screen may ask where its nodes
	-- landed without silently disabling a composed Table's scroll-into-view.
	onGeometry: ((rectOf: (string) -> any) -> ())?,
	-- keep-visible presentation offset (§17 Phase 5): a Readable<number> the
	-- presenter observes and applies as an upward transform on the screen root
	-- (0 = none). A text field publishes its keyboard-occlusion offset here.
	keepVisibleOffset: any?,
	-- structural transition for the SURFACE itself (ADR-0022 Decision 3):
	-- { enter, exit?, class?, fade? }. The enter runs on the first painted frame;
	-- `dismiss` then defers the teardown until the exit completes or the
	-- coordinator's flat 500 ms cap fires — whichever comes first. The surface
	-- leaves the stack (and its focus scope and input context) IMMEDIATELY either
	-- way: a screen on its way out must never still take input.
	--
	-- A fading form needs a fade GROUP, and a `Screen` is not one — so the
	-- transition targets the root's single `canvasGroup` child when it has one
	-- (`UI.ZStack{ canvasGroup = true }` around the screen's content is the
	-- documented shape), and the root otherwise.
	transition: any?,
	-- presentCritical only
	fallbackScreen: ((err: any) -> any)?,
}

-- presentToast options (ADR-0022 Decision 4; ui-designer spec §3.1)
export type ToastOpts = {
	key: string?, -- same-key supersede ("subject" in the spec)
	priority: number?, -- default 0; higher runs first in the queue
	duration: number?, -- seconds visible, default 4
	readFloor: number?, -- minimum dwell before anything may replace it, default 1.5
	position: string?, -- "top" (default) | "bottom" — the edge it docks to
	transition: any?, -- default: slide in from its own edge, with a fade
	context: any?, -- carried on the toast's dismiss event, untouched
}

-- CLOSED OPTS (constitution §4, and the architecture review's first finding).
-- This is the widest opts table in the
-- library — twenty declared fields, most of them booleans and policy strings
-- with silent defaults — so it is the one where an accepted-and-ignored key
-- costs the most: `outsideTapCancle = false` left the modal dismissing on an
-- outside tap with nothing to say about it. Every declared field is legal, and
-- exactly those.
local PRESENT_OPTS_KEYS = specGuard.keySet({
	"cancelPolicy",
	"engineSelectionBridge",
	"fallbackScreen",
	"gameplayGuard",
	"keepVisibleOffset",
	"navigationGroups",
	"onActivate",
	"onAdjust",
	"onFocusNav",
	"onGeometry",
	"initialFocus",
	-- ADOPTED CHROME (F1): "top" | "bottom" | "leading" | "trailing". See
	-- FocusScope.chrome, which owns this feature's whole argument.
	"focusChrome",
	"onNavigateIntercept",
	"onReorderNav",
	"outsideTapCancel",
	"responder",
	"revealTimeout",
	"revealWhenTextExact",
	"rootPolicy",
	"scrim",
	"sinkNavigation",
	"transition",
	"traversalWrap",
	-- INSTANCE RECYCLING (opt-in, default off). A windowed list rebuilds an
	-- identical row every time its window slides; with this on, retiring nodes are
	-- parked and reused instead of destroyed and re-created. Feature-detected on
	-- the adapter as well, and the adapter refuses any node carrying path-keyed
	-- state — so it can only ever save work, never change what is on screen.
	"recycleInstances",
	-- INCREMENTAL LAYOUT (opt-in, default off — Stage 2)
	"incrementalLayout",
	"keyboardNavigation",
})
local TOAST_OPTS_KEYS = specGuard.keySet({
	"context",
	"duration",
	"key",
	"position",
	"priority",
	"readFloor",
	"transition",
})
local PRESENTER_OPTS_KEYS = specGuard.keySet({ "clock", "keyboardNavigation", "now" })

local modalZones = require("./modal_zones")
local focusMap = require("./focus_map")
-- the two synthesized full-viewport tap swallowers (the modal/engaged scrim and
-- the transient popup catcher) — see that module's header for why they left
local catchersLib = require("./catchers")
-- the auto-reveal marquee strip — see that module's header for the seam
local textRevealLib = require("./text_reveal")
local withAnimationLib = require("./with_animation")
-- D3a: the player-PULLED help plate (hover dwell + focus, nothing on touch), and
-- D3b: the at-most-one queue the app-PUSHED coach mark presents through. Both are
-- consumers of the D1 anchored seam and neither mounts a surface of its own.
local helpPlateLib = require("./help_plate")
local calloutQueueLib = require("./callout_queue")
-- the surface lifecycle helpers — the shared focus-visual sync, the per-frame
-- refresh body and the dismissal pair. See that module's header for the seam
-- (docs/handoff/SOURCE_CAP_LEDGER.md's row for this file named it) and
-- tests/surface_lifecycle_seam.spec.luau for what mechanises it.
local surfaceLifecycleLib = require("./surface_lifecycle")

-- ALIASED TO THE SAME LOCAL NAMES the 3 500-line `presenter.new` closure below already
-- calls (2026-08-06). The focus-order/traversal-rank/navigation-group derivations and
-- the modal two-zone geometry moved into their own modules — see the headers there for
-- why — and binding them back to their original names here means NOT ONE LINE of the
-- closure changed. A rename sweep through that closure is exactly the kind of churn
-- this codebase's defect history says not to take on for a file move.
local FOCUS_ORDER_SCHEMA = focusMap.FOCUS_ORDER_SCHEMA
local FOCUSABLE = focusMap.FOCUSABLE
local isDisabled = focusMap.isDisabled
local isRetiring = focusMap.isRetiring
local isPathPrefix = focusMap.isPathPrefix
local entryPath = focusMap.entryPath
local isHiddenPath = focusMap.isHiddenPath
local filterHidden = focusMap.filterHidden
local filterGroupsHidden = focusMap.filterGroupsHidden
local focusOrder = focusMap.focusOrder
local resolveInitialFocus = focusMap.resolveInitialFocus
local nodePriority = focusMap.nodePriority
local documentIndex = focusMap.documentIndex
local orderPaths = focusMap.orderPaths
local traversalRank = focusMap.traversalRank
local collectContributions = focusMap.collectContributions
local nodeAt = focusMap.nodeAt
local pathIsRetiring = focusMap.pathIsRetiring
local contributionsForPath = focusMap.contributionsForPath
local collectFocusables = focusMap.collectFocusables
local focusableCount = focusMap.focusableCount
local subtreeHasFocusGroups = focusMap.subtreeHasFocusGroups
local autoGroups = focusMap.autoGroups
local hasHorizontalStructure = focusMap.hasHorizontalStructure
local layoutGroups = focusMap.layoutGroups
local pointInRect = modalZones.pointInRect
local inflate = modalZones.inflate
local inflateToFloor = modalZones.inflateToFloor
-- `zoneAContains` / `modalInZoneA` left with the catchers (src/present/catchers.luau):
-- the two Zone-A tests had no other reader here.
type Contribution = focusMap.Contribution

-- Activate dispatch when the consumer passed NO opts.onActivate: (1) a
-- props.onActivate on the node; (2) a Toggle whose value is a settable signal
-- flips; (3) the longest-prefix contribution whose handleActivate consumes it;
-- (4) no-op. When opts.onActivate IS present it wins outright (override).
local function activateEffect(handle: any, node: any, path: string?, meta: any?)
	if handle.onActivate ~= nil then
		handle.onActivate(path, meta) -- consumer override
		return
	end
	if path == nil then
		return
	end
	-- (1) a leaf that declares its own effect
	if node ~= nil and node.props ~= nil and type(node.props.onActivate) == "function" then
		node.props.onActivate(path, meta)
		return
	end
	-- (2) Toggle auto-flip (contract.luau §Toggle: "Activate flips value")
	if node ~= nil and node.class == "Toggle" and node.dynamicProps ~= nil then
		local value = node.dynamicProps.value
		if type(value) == "table" and (value :: any).kind == "signal" then
			value:set(not value:get())
			return
		end
	end
	-- (3) longest-prefix contribution dispatch
	for _, c in contributionsForPath(handle.contributions, path) do
		if c.bundle.handleActivate ~= nil and c.bundle.handleActivate(path, meta) then
			return
		end
	end
	--[[ (4) THE PUBLIC DRAG VERB'S PICKUP (the adaptation wave's generic-verb
		row). An action-source Activate
		that nobody above wanted, on a mounted `UI.draggable`, ARMS it — and the
		next one commits it at the aim the focus ring has been feeding. The rule is
		`newVirtualList`'s own ("a source with no consumer Activate arms on
		Activate"), hoisted to the public verb, and it is asked LAST so that
		"nobody wanted it" is structural rather than predicted: a node's own
		`onActivate`, a Toggle's flip and every control contribution have already
		declined. Before this, the whole arm->navigate->commit path existed, was
		tested, and was bound to nothing on a pad or a keyboard. ]]
	if handle.controller ~= nil and handle.controller.activateArms ~= nil then
		if handle.controller.activateArms(path, meta) then
			return
		end
	end
	-- (5) no-op
end

-- Activate dispatch + the semantic `activate` event, which fires on the CAUSAL
-- FRAME (this one) and exactly once per press, AFTER the effect — so a subscriber
-- that reads the resulting state sees the state the press produced.
--
-- DISABLED FIRST (B-BTN4; verifier finding V12). This gate used to sit AFTER the
-- consumer override, so a screen presented with `opts.onActivate` — the gallery
-- client's own integration and the common game pattern — still activated a
-- disabled control. `enabled = false` has to mean disabled on every path,
-- including the one that overrides everything else, and a disabled control emits
-- no event either: nothing happened.
--
-- `source` names which of the two paths saw the press: "action" (the IAS
-- Activate action — Return, Space, ButtonA) or "tap" (a native tap/Activated
-- routed through the renderer). One press can be seen by BOTH exactly when this
-- surface mirrors Facet focus onto `GuiService.SelectedObject`: the engine then
-- fires the selected `GuiButton`'s own `Activated` for the same key press that
-- IAS delivered as Activate. That must still be ONE activation (roadmap Step 8,
-- the one-Activate-per-press rule), so a cross-source pair inside
-- ACTIVATE_ECHO_WINDOW collapses.
--
-- IDENTIFIED BY INPUT CLASS, NOT BY TIME ALONE. A time-only window would eat a
-- real mouse click that happened to land beside a key press — which is a thing
-- players do, and it broke the "one event per press" feedback pin the moment it
-- was tried. The engine's selection activation is distinguishable: its
-- `InputObject.UserInputType` is Keyboard or a Gamepad, never Mouse or Touch. So
-- only an {IAS Activate, non-pointer native Activated} pair collapses. Two
-- pointer taps, two key presses, or a tap next to a key press are all two
-- presses. The renderer's own detector echo guard draws the same line for the
-- same reason: deduplicate only what genuinely has two signals per press.
local ACTIVATE_ECHO_WINDOW = 0.05 -- s; far below any human double-press
local function isEngineSelectionTap(source: string?, meta: any?): boolean
	if source ~= "tap" or type(meta) ~= "table" then
		return false
	end
	return meta.pointer == "keyboard" or meta.pointer == "gamepad"
end
local function dispatchActivate(handle: any, path: string?, meta: any?, source: string?)
	local node = if path ~= nil then nodeAt(handle.root.node, path) else nil
	if isDisabled(node) then
		return true -- consumes the verb and does nothing
	end
	if path ~= nil and source ~= nil and handle.activateEcho ~= nil then
		local at = handle.now()
		local selectionTap = isEngineSelectionTap(source, meta)
		local previous = handle.activateEcho[path]
		local echoes = previous ~= nil
			and previous.source ~= source
			and (selectionTap or previous.selectionTap == true)
			and (at - previous.at) < ACTIVATE_ECHO_WINDOW
		if echoes then
			-- A PRESS IS A PAIR, AND THE PAIR IS NOW SPENT (architecture review
			-- finding on the echo window). Recording the collapsing signal instead would roll the
			-- window forward on every echo, so a genuinely fast third press —
			-- key, echo, key — would land inside a window opened by the echo and
			-- be eaten as well. Clearing means the next signal starts a new press.
			handle.activateEcho[path] = nil
			return true -- the same press echoing through the other path
		end
		handle.activateEcho[path] = { at = at, source = source, selectionTap = selectionTap }
	end
	activateEffect(handle, node, path, meta)
	if path ~= nil and handle.emitFeedback ~= nil then
		-- THE PER-CONTROL VERB (director request 2026-08-13). `activate` is the
		-- default, not the only answer: a control (or any ancestor of it) may have
		-- declared what its own press means through
		-- `UI.sensoryFeedback(bp, { activation = … })`, which `mount.luau` already
		-- resolved down the tree onto this node. `"none"` is a control the author
		-- deliberately silenced, and it emits nothing at all rather than a verb a
		-- subscriber then has to know to ignore.
		--
		-- `reason` is stamped on EVERY control activation, including the default
		-- one, because a subscriber otherwise cannot tell "a player pressed a
		-- control" from "the game emitted `commit` for its own reason" — and the
		-- client haptics adapter has to: on a platform where the engine itself
		-- plays a button's press through the button's own press-effect property,
		-- a second play from the bus would be two pulses for one press. (The
		-- engine symbol is deliberately not named here — the boundary rule in
		-- tests/haptics.spec.luau keeps every haptics name out of src/present.)
		local verb = if node ~= nil then node.activationFeedback else nil
		if verb ~= feedbackLib.ACTIVATION_SILENT then
			handle.emitFeedback({
				type = verb or "activate",
				path = path,
				surface = handle,
				reason = "activation",
				context = meta,
			})
		end
	end
	return nil
end

-- THE FIVE-LAYER SURFACE ORDER (ui-designer spec §6.3), encoded here because this
-- is where surface z is decided. BANDS, not one running counter: a toast has to
-- sit above every base screen and below every modal regardless of the order they
-- were presented in, which a single monotonic counter cannot express. Within a
-- band, creation order still decides (each surface takes the next +100 step), so
-- ~100 live surfaces per band before two would tie — far past anything real.
--
-- `dragProxy` has no consumer in this package: the drag proxy is P4's, and the
-- constant lives here so its layer is a decision on the record rather than a
-- number chosen at the proxy's call site.
local SURFACE_LAYER = table.freeze({
	base = 10000,
	toast = 20000,
	dragProxy = 30000,
	modal = 40000,
})
presenter.SURFACE_LAYER = SURFACE_LAYER

export type PresenterOpts = {
	-- DESKTOP KEYBOARD NAVIGATION, OFF UNTIL ASKED FOR (director playtest
	-- 2026-08-03). Tab/Shift+Tab traversal and Space-as-Activate are opt-in at the
	-- presenter, and every surface inherits this unless it overrides it with its
	-- own `keyboardNavigation`. It defaults FALSE because the keys it claims are
	-- the ones an avatar is already using: a game that has not asked for keyboard
	-- navigation keeps exactly the input behavior it had.
	keyboardNavigation: boolean?,
	-- the motion clock every transition and the toast schedule ride. Supply one to
	-- share it with the rest of the application (the client binds it to
	-- RunService.PreRender); absent, the presenter builds its own and `tick`
	-- steps it.
	clock: any?,
	now: (() -> number)?,
}

function presenter.new(core: any, env: any, adapter: any, actionSystem: any, opts: PresenterOpts?)
	specGuard.assertKnownKeys("newPresenter", opts, PRESENTER_OPTS_KEYS, "opts")
	local self = {}
	local graph = focus_graph.new(core)
	local stack: { any } = {} -- presented handles, base first
	self.focus = graph
	local presenterOpts: PresenterOpts = opts or {}
	local nowFn = presenterOpts.now or os.clock
	-- ONE ACTIVATE PER PRESS ACROSS THE TWO PATHS (roadmap Step 8, the desktop
	-- keyboard round). A
	-- keyboard press on a control the engine also considers SELECTED can arrive
	-- twice: once as the IAS `Activate` action, and once as the native
	-- `GuiButton.Activated` the engine-selection bridge makes reachable. Keyed by
	-- path across the whole presenter (paths are surface-prefixed), and collapsing
	-- only a CROSS-SOURCE pair inside the window: two presses of the same key, or
	-- two real taps, are two presses and must both count — the renderer's own
	-- detector-echo guard draws the same line for the same reason.
	local activateEcho: { [string]: { at: number, source: string } } = {}

	-- ===== the semantic feedback seam (ADR-0022 Decision 7) ===================
	-- ONE bus per presenter. `presenter.onFeedback` is the primary seam (every
	-- surface, one subscription — a game maps events to sound/haptics in one
	-- place); `handle.onFeedback` is the same bus filtered to that surface.
	-- Facet plays nothing.
	local bus = feedbackLib.new()

	local function emitFeedback(event: any)
		bus.emit(event)
	end

	-- THE REGISTRATION POINT FOR SESSION EVENTS (ADR-0022 Decision 7). P4's drag
	-- session emits `commit` / `land` / `reject` / `cancel` / `pickup` through
	-- exactly this call, so every semantic event a game hears — control, motion,
	-- toast, session — arrives on one bus with one taxonomy.
	self.emitFeedback = emitFeedback
	self.onFeedback = bus.subscribe
	self.feedbackTypes = feedbackLib.TYPES
	-- the documented five-band paint order, reachable from the INSTANCE the
	-- public API hands out (P5-F3: the module-table copy was unreachable through
	-- `Facet.newPresenter`)
	self.SURFACE_LAYER = SURFACE_LAYER

	-- subscribers to "a modal took the screen" (disposition F7; see presentModal)
	local modalWatchers: { (handle: any) -> () } = {}

	-- ===== the motion clock (ADR-0022 Decision 1) ============================
	-- One clock for every surface transition and the toast schedule. A clock at
	-- rest costs nothing, so building it eagerly costs a table; `self.tick(dt)`
	-- steps it (the client binds that to RunService.PreRender).
	local motionPolicy: any = nil
	do
		local ok, readable = pcall(function()
			return env:get("motionPolicy")
		end)
		if ok then
			motionPolicy = readable
		end
	end
	local motionClock = presenterOpts.clock or motionClockLib.new(core, { motionPolicy = motionPolicy, now = nowFn })
	self.motionClock = motionClock

	-- ===== scroll indicator policy (director ruling 2026-08-09) ==============
	-- The environment derives it ("always" on pointer sessions, "auto" on
	-- touch/gamepad); the ADAPTER applies it, because indicators are engine
	-- paint. A DECLARED optional target method: an adapter without it keeps its
	-- constant bar and nothing else changes.
	--
	-- IT NO LONGER MOVES THE RESERVE (director ruling 2026-08-12, reversing
	-- 2026-08-09). The policy used to zero the adapter's published bar thickness
	-- under "auto", which is why a change re-solves every surface; the engine
	-- charges the window for the bar instance whatever the policy paints, so the
	-- reserve is now constant and the re-solve exists for the indicator lifecycle
	-- alone. See src/client/screen_target.luau SCROLL_BAR_THICKNESS.
	if type((adapter :: any).setScrollIndicatorPolicy) == "function" then
		local okP, policyReadable = pcall(function()
			return env:get("scrollIndicatorPolicy")
		end)
		if okP and policyReadable ~= nil then
			local function applyIndicatorPolicy()
				local reduced = if motionPolicy ~= nil then motionPolicy:get() == "reduced" else false
				local policy = policyReadable:get();
				(adapter :: any).setScrollIndicatorPolicy(policy, reduced)
			end
			-- session-lifetime, like the presenter itself (it has no dispose):
			-- kept on self so the ownership is visible, not implicit. An effect
			-- runs once at creation — that first run is the boot application and
			-- must NOT refresh (self.refresh is not constructed yet, and there
			-- is nothing mounted to re-solve); only CHANGES re-solve.
			local booted = false
			self._scrollIndicatorWatcher = core:effect(function(use)
				use(policyReadable)
				if motionPolicy ~= nil then
					use(motionPolicy)
				end
				applyIndicatorPolicy()
				if booted and type(self.refresh) == "function" then
					self.refresh()
				end
				booted = true
			end)
		end
	end
	local lastTick = nowFn()
	-- per-frame work registered through self.onTick (autoscroll steppers, fixture
	-- probes) — run inside self.tick, after the motion step
	local tickHooks: { (dt: number) -> () } = {}

	-- the live metric authority (ADR-0019 §2). Read per use, never captured: a
	-- theme commit must move the dismiss geometry in the same frame it moves the
	-- solved rects those decisions are taken against.
	local function metricsNow(): any
		local m = env:get("themeMetrics"):get()
		return if type(m) == "table" and type(m.targetSizes) == "table" then m else themeSnapshot.neutral()
	end

	-- ===== responder priority bands (ADR-0014; research conclusion 3) ========
	-- Base screens stay at 1500 (above the ~1000 avatar default, below the
	-- doc-sanctioned gameplay sink at 2000, so a passive/plain screen never
	-- suppresses movement). The ENGAGED-EXCLUSIVE band starts at 3000 —
	-- mirroring ContextActionPriority.High and sitting STRICTLY above the
	-- gameplay sink at 2000 (moved up from the previous 2000 base, which would
	-- have TIED a game's own PlayContext with undocumented tie-break). An
	-- engaged-from-passive surface takes the band base (3000); modals stack
	-- +500 per depth above it.
	local BASE_SCREEN_PRIORITY = 1500
	local ENGAGED_BASE_PRIORITY = 3000

	local function topModalPriority(): number
		local top = ENGAGED_BASE_PRIORITY
		for _, handle in stack do
			if handle.kind == "modal" then
				top += 500
			end
		end
		return top
	end

	-- presenter-level readable: true while ANY presented surface is exclusive
	-- (a modal, or an engaged-from-passive surface — both sink, becoming first
	-- responder over gameplay). A client adapter observes this to hide the touch
	-- controls while an exclusive surface is up (src/client/responder_effects).
	local exclusive = core:signal(false)
	self.exclusiveSurfaceActive = exclusive
	local function refreshExclusive()
		local anyExclusive = false
		for _, handle in stack do
			if handle.kind == "modal" or (handle.isPassive and handle.responder:get() == "engaged") then
				anyExclusive = true
				break
			end
		end
		exclusive:set(anyExclusive)
	end

	local handleByPath: ((string) -> any)? = nil

	-- cross-surface z: a monotonic layer per presented surface (base first, each
	-- later surface above). Deterministic and creation-ordered; the synthesized
	-- scrim sits just BELOW its owner (spec §2.2).
	-- A RECORD RATHER THAN A SCALAR, and it is the only thing the surface-
	-- lifecycle split cost: `makeHandle` below INCREMENTS this counter while
	-- `dismiss` (src/present/surface_lifecycle.luau) RESETS it, so the two
	-- writers now live in two files and need one object between them rather than
	-- two copies of a number.
	local displayLayer = { value = 0 }

	-- ===== synthesized scrim / popup catcher ==================================
	-- The two full-viewport tap swallowers this presenter synthesizes moved into
	-- src/present/catchers.luau for the 200,000-char Source WRITE cap (see that
	-- header, and docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md).
	-- They took the ONLY two mutable upvalues they touched with them (`scrim`,
	-- `popupCatcher`) and read the rest of this closure by reference, so the move
	-- was behaviour-preserving by construction. Bound back to the SAME local names
	-- the call sites below already use — `applyOutsideOutcome` (the surface tap
	-- handler in `makeHandle`) and `syncScrim` (present/dismiss/engage/resign) —
	-- so not one of them changed.
	local catchers = catchersLib.new({
		core = core,
		env = env,
		adapter = adapter,
		stack = stack,
		presenter = self,
		metricsNow = metricsNow,
	})
	local applyOutsideOutcome = catchers.applyOutsideOutcome
	local syncScrim = catchers.syncScrim
	self.syncPopupCatcher = catchers.syncPopupCatcher
	self.topPopupCatcherPath = catchers.topPopupCatcherPath
	self.topScrimPath = catchers.topScrimPath

	--[[ ===== FULL-VALUE DISCLOSURE (the large-text round) =====================

		A `UI.Text{ disclose = true }` that TRUNCATED owes the reader the whole
		string. The screen declares the debt; the presenter pays it, here, with one
		STATIC plate — no marquee, no travel, no per-frame work (the same round chose the
		static form precisely so reduced-motion parity is structural rather than a
		branch, and so the moving-label count stays zero).

		PRESENTER-PRIVATE, exactly like the scrim, the popup catcher and the toast
		layer: not in `stack`, no focus scope, no input context, no tap handler. It
		cannot be focused or traversed because there is nothing there to focus it
		WITH — that is what "presentation chrome" means, rather than a property the
		layer politely observes.

		AT MOST ONE, ACROSS EVERY SURFACE AND EVERY INPUT CLASS. Three engagements
		feed it — hover dwell (pointer), focus enter (keyboard/gamepad), long-press
		(touch) — and presenting disposes whatever was up. Two plates would be two
		answers to "what is this label", and the second would be covering the first.
		A plate already showing THIS label is left alone whichever engagement raised
		it, and only that engagement takes it down; a direct pointer/touch ask
		outranks focus, which is merely wherever focus happens to be.

		THE FACTS COME FROM THE SOLVE, NEVER FROM A RE-MEASURE. `controller.textAt`
		is the same verdict the reserved box was built from, so the plate appears
		exactly when the engine is ellipsizing and vanishes the moment a re-solve
		makes room — a second measurement here would be a second opinion.
	]]
	local DISCLOSE_ROOT = "__disclose__"
	local DISCLOSE_PLATE = `/{DISCLOSE_ROOT}/Layer/Plate`
	local DISCLOSE_LABEL = `{DISCLOSE_PLATE}/Full`
	-- POINTER DWELL. A plate that appeared the instant a pointer crossed a label
	-- would fire on every pass THROUGH a list; 0.45s is the quiet delay the plan
	-- asks for, long enough to be a decision and short enough not to feel broken.
	-- Focus and long-press carry their own deliberation and present immediately.
	local DISCLOSE_DWELL = 0.45
	local DISCLOSURE_SCHEMA = "facet-disclosure-dump/1"

	local disclosurePlate: any = nil -- { scope, controller, root, owner, sourcePath, source, text }
	local disclosureDwell: any = nil -- { owner, sourcePath, text, remaining }

	--[[ the safe box a plate may occupy, in WINDOW space: the viewport less the
		per-edge MAXIMUM of the two inset facts (the `deviceSafeContent` rule). A
		tooltip under a notch or behind the home indicator is unreadable, and this
		surface is decoration rather than content only in its z-order.

		...AND LESS THE THEME'S OWN STEP ON THE THREE EDGES A PLATE MAY TOUCH
		(device review 2026-08-16, F3). Director, on compact desktop: *"the left
		pixel seems cutoff."* Measured on the callout fixture at every width from
		320 to 1232: the coach mark's plate landed at x = 0.0, and the f1 plate's
		right edge came out EXACTLY equal to the viewport width. Flush is the
		defect, and it is the defect that no overflow check in this repository can
		see — every one of them asks `x + w <= viewport`, which a flush rect
		satisfies. `docs/lessons/device-emulator-truths.md` is why it survived: the
		engine reports only the 58px CoreGui topbar and NOTHING lateral, so both
		inset facts are structurally zero on the sides on every device, and a policy
		that is nothing but `max(core, device)` therefore yields a zero gutter
		forever.

		THE THIRD TERM IS THE ONE `hud.luau` ALREADY SHIPS FIXTURE-SIDE. Its
		`screenPadding` memo has computed `max(platform inset, theme space.s)` per
		edge since the chrome-rotation round, and its own header says the quiet part:
		`screenPadding` is a fixture-local memo and not a framework API. This is that
		rule promoted to the one place every plate already reads — anchored surfaces
		(`anchored.luau`), the disclosure plate and its clamp all take this box — so
		they are fixed together rather than three times.

		TOP IS DELIBERATELY EXEMPT, matching `hud.luau`'s own `top = 0`. The top
		edge is the chrome band's, already reserved in full by `coreSafeInsets.top`;
		adding a decorative step on top of a reserved band pushes every plate down by
		a gutter nobody asked for and buys nothing — there is no "flush against the
		top" case, because the topbar inset is never zero. ]]
	local function safeBox(): { x: number, y: number, w: number, h: number }
		local vp = env:get("viewportRect"):get()
		local core_ = env:get("coreSafeInsets"):get()
		local device = env:get("deviceSafeInsets"):get()
		-- the theme's own smallest gutter step, never a literal: a package that
		-- retunes its spacing ladder retunes the screen's margin with it
		local gutter = themeSnapshot.resolveNumber(metricsNow(), "s") or 0
		local function edge(name: string): number
			local a = if type(core_) == "table" then tonumber(core_[name]) or 0 else 0
			local b = if type(device) == "table" then tonumber(device[name]) or 0 else 0
			local floor = if name == "top" then 0 else gutter
			return math.max(a, b, floor)
		end
		local x = (if type(vp) == "table" then tonumber(vp.x) or 0 else 0) + edge("left")
		local y = (if type(vp) == "table" then tonumber(vp.y) or 0 else 0) + edge("top")
		local w = (if type(vp) == "table" then tonumber(vp.w) or 0 else 0) - edge("left") - edge("right")
		local h = (if type(vp) == "table" then tonumber(vp.h) or 0 else 0) - edge("top") - edge("bottom")
		return { x = x, y = y, w = math.max(0, w), h = math.max(0, h) }
	end

	--[[ ===== ANCHORED SURFACES (D1) ========================================
		`presentAnchored(panel, opts)` — a surface placed against a SOURCE VIEW'S
		screen rect instead of a parent corner. It owns none of the presenter's
		machinery: it synthesizes the Screen/Anchor wrapper and the arrow tail, and
		delegates straight back to `present`/`presentModal` for the stack, the focus
		scope, the input context, the layering band and the tap-away catcher.
		Constructed HERE, below `safeBox`, because that is the fact it reuses —
		re-deriving the safe area in a second place is exactly the fork this
		deliverable exists to remove. `handleByPath` is forward-declared above and
		assigned far below, so it is reached through a thunk. ]]
	local anchoredSurfaces = anchoredLib.new({
		core = core,
		env = env,
		-- the render target, for the CHROME mode only: a chrome layer hand-mounts
		-- its own controller the way the disclosure plate and the toast strip do
		adapter = adapter,
		baseDisplayOrder = SURFACE_LAYER.base,
		stack = stack,
		presenter = self,
		metricsNow = metricsNow,
		safeBox = safeBox,
		handleByPath = function(path: string): any
			return if handleByPath ~= nil then handleByPath(path) else nil
		end,
		presentOptsKeys = PRESENT_OPTS_KEYS,
	})

	-- the first TRUNCATED, DISCLOSED Text at or under `path`, in document order.
	-- Engagement names a focusable (or the label itself); the debt belongs to the
	-- Text, and a control is free to hold exactly one — a row's name cell.
	local function disclosureTargetIn(handle: any, path: string?): (string?, string?)
		if handle == nil or path == nil then
			return nil, nil
		end
		local ctrl = handle.controller
		if ctrl == nil or ctrl.textAt == nil then
			return nil, nil
		end
		--[[ A CONTROL MAY WIDEN THE SCOPE TO ITS OWN ROW (the adaptation wave). The default is
			"at or under the focused path", which is dead for any control whose focus
			stop is a SIBLING of its disclosed label rather than its ancestor — a
			Table's row `Hit` beside `Row/Cells/…`. The control answers for the paths
			it recognises and nil for the rest; the walk below is unchanged, so the
			hidden gate, the truncation test and the document order still decide. ]]
		local scoped = path
		for _, c in contributionsForPath(handle.contributions or {}, path) do
			if c.bundle.discloseScope ~= nil then
				local widened = c.bundle.discloseScope(path)
				if type(widened) == "string" then
					scoped = widened
					break
				end
			end
		end
		local node = nodeAt(handle.root.node, scoped)
		if node == nil then
			return nil, nil
		end
		-- A HIDDEN CANDIDATE DISCLOSES NOTHING (architecture review F-1). A
		-- losing ViewThatFits candidate keeps its mount, its rects and its
		-- textFacts — only visibility knows it does not paint. Without this
		-- gate, focusing a row whose RICH candidate lost raised a plate for a
		-- string that is nowhere on screen.
		--[[ ONE OWNER FOR "IS THIS PATH INSIDE A SUBTREE THAT DOES NOT PAINT"
			(the reuse audit's fourth-copy finding). `focusMap.isHiddenPath` is the published answer and
			takes the SET `hiddenRoots()` already returns, so the array this used to
			build was a conversion nobody needed. Hoisted once rather than re-read per
			node: the walk visits every node in the subtree. ]]
		local hiddenRoots: { [string]: boolean } = if ctrl.hiddenRoots ~= nil then ctrl.hiddenRoots() else {}
		local foundPath: string? = nil
		local foundText: string? = nil
		local function walk(n: any)
			if foundPath ~= nil or isHiddenPath(n.path, hiddenRoots) then
				return
			end
			-- class-AGNOSTIC on purpose (the large-text gate): any node whose measured text
			-- carries the disclose declaration owes its full value — a Text's
			-- `text`, a Toggle's one-line `label` — the facts channel is the same.
			-- A `reveal` node is a disclosure source too (2026-08-04): the static
			-- plate is the auto reveal's declared full-value alternative
			if n.props ~= nil and (n.props.disclose == true or n.props.reveal ~= nil) then
				local facts = ctrl.textAt(n.path)
				if facts ~= nil and facts.truncated == true then
					foundPath = n.path
					-- the mounted node carries the RESOLVED value, so a bound label
					-- discloses what it is currently saying rather than a Readable
					foundText = tostring(n.props.text ~= nil and n.props.text or n.props.label)
					return
				end
			end
			for _, child in n.children or {} do
				walk(child)
			end
		end
		walk(node)
		return foundPath, foundText
	end

	-- the presented surface that owns `path`, or nil. Topmost wins, exactly as the
	-- outside-tap policy resolves it.
	local function handleOwning(path: string?): any
		if path == nil then
			return nil
		end
		for i = #stack, 1, -1 do
			local h = stack[i]
			if isPathPrefix("/" .. (h.blueprint.id or ""), path) then
				return h
			end
		end
		return nil
	end

	local function disposeDisclosure()
		if disclosurePlate == nil then
			return
		end
		local plate = disclosurePlate
		disclosurePlate = nil
		plate.controller.dispose()
		plate.scope:dispose()
	end

	local function dismissDisclosure(_reason: string)
		disclosureDwell = nil
		disposeDisclosure()
	end

	--[[ THE CLAMP, RE-RUNNABLE (found live 2026-08-04, RascalRally: a card
		caption's full-value plate hung off the BOTTOM of the screen). The plate's
		size is a solve output whose text measure can land ASYNCHRONOUSLY on the
		live adapter: a clamp computed once at mount used the placeholder height,
		chose "below fits", and the plate then grew past the screen edge — while
		every headless witness measured synchronously and stayed green. The clamp
		therefore FOLLOWS the live rects: `presentDisclosure` runs it at mount and
		the presenter tick re-runs it while a plate is live, so a late text
		measure, a source that moved, or a viewport change all re-place the plate
		on the next frame. The signals no-op when nothing changed, so a settled
		plate costs two reads per frame and zero writes. ]]
	local function clampDisclosure()
		local plate = disclosurePlate
		if plate == nil then
			return
		end
		local ctrl = plate.owner.controller
		local srcRect = if ctrl.screenRectOf ~= nil
			then ctrl.screenRectOf(plate.sourcePath)
			else ctrl.rectOf(plate.sourcePath)
		local plateRect = plate.controller.rectOf(DISCLOSE_PLATE)
		if type(srcRect) ~= "table" or type(plateRect) ~= "table" then
			return
		end
		--[[ THROUGH THE SHARED SOLVER (D1). This block WAS the first hand-rolled
			copy of the anchored-placement rules: prefer below, flip above, clamp
			into the safe box. Being a copy, it had the flip subtly wrong — it
			flipped whenever below did not fit, including when above did not fit
			either, which is the "worse place" `row_actions`' own ruling forbids (a
			plate both clipped AND on the wrong side of its label). It now asks
			`anchor_placement.solve`, which encodes both halves of that rule once. ]]
		local placement = anchorPlacement.solve({
			source = srcRect,
			size = { w = plateRect.w, h = plateRect.h },
			safe = safeBox(),
			edge = "bottom",
			-- leading-aligned on the label, which is where a reader's eye already is
			align = "start",
			gap = themeSnapshot.resolveNumber(metricsNow(), "xs") or 4,
		})
		if plate.ox:get() ~= placement.x or plate.oy:get() ~= placement.y then
			plate.ox:set(placement.x)
			plate.oy:set(placement.y)
			plate.controller.refresh()
		end
	end

	-- mount the plate near `sourcePath`, clamped into the safe box. Two passes by
	-- necessity: the plate's size is a solve output, and the clamp needs it — so
	-- it is mounted at the source's own corner, measured, then moved through the
	-- anchor offsets (reactive, `dirty = arrange`), which is a re-solve and never
	-- a remount — and the clamp KEEPS following the live rects after mount
	-- (`clampDisclosure` above).
	local function presentDisclosure(owner: any, sourcePath: string, fullText: string, source: string)
		disposeDisclosure()
		local ctrl = owner.controller
		local srcRect = if ctrl.screenRectOf ~= nil then ctrl.screenRectOf(sourcePath) else ctrl.rectOf(sourcePath)
		if type(srcRect) ~= "table" then
			return
		end
		local box = safeBox()
		local metrics = metricsNow()
		local gap = themeSnapshot.resolveNumber(metrics, "xs") or 4
		local sc = core:scope("present-disclose")
		local ox = sc:own(core:signal(srcRect.x))
		local oy = sc:own(core:signal(srcRect.y + srcRect.h + gap))
		local bp = blueprintLib.Screen({
			id = DISCLOSE_ROOT,
			children = {
				blueprintLib.Anchor({
					id = "Layer",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						-- a VStack and not a Box: a Box is a LEAF, and the plate has to
						-- hold the label it exists to show
						blueprintLib.VStack({
							id = "Plate",
							anchor = "topLeft",
							offsetX = ox,
							offsetY = oy,
							-- the panel treatment, so the plate is themed by the ACTIVE
							-- ThemeSnapshot (fill, corner, stroke, contentInsets) rather
							-- than by numbers written here
							surface = "raised",
							padding = "s",
							-- HUG WITH A CEILING, not a fixed width: a short value gets a
							-- short plate, and a long one wraps inside the safe box instead
							-- of running off the screen edge — which is the same overflow
							-- ladder the label it is disclosing just failed
							width = { type = "hug", max = math.max(0, box.w - 2 * gap) },
							children = {
								blueprintLib.Text({ id = "Full", text = fullText, textSize = "body" }),
							},
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp, { scope = sc:child("mount") })
		local controller = renderer.attach(core, root, env, adapter, {
			-- window space: the anchor offsets below are the SAME coordinates
			-- `screenRectOf` answers in, so the clamp arithmetic has one frame
			rootPolicy = "edgeToEdge",
		})
		controller.initialRender()
		if controller.setDisplayOrder ~= nil then
			-- above its owner's content, inside its owner's band — so a plate over a
			-- base screen never covers a modal, and a modal's own plate is above it
			controller.setDisplayOrder(owner.displayOrder + 25)
		end
		disclosurePlate = {
			scope = sc,
			controller = controller,
			root = root,
			owner = owner,
			sourcePath = sourcePath,
			source = source,
			text = fullText,
			ox = ox,
			oy = oy,
		}
		clampDisclosure()
	end

	--[[ FIRST ENGAGEMENT OWNS THE PLATE, AND IT IS KEYED ON THE LABEL, NOT ON THE
		INPUT CLASS. A focused row that is also long-pressed, or hovered, is ONE
		question with one answer, and re-presenting it as a different `source` would
		dispose and remount an identical plate — visibly, on every refresh, because
		the focus sync runs on all of them. So a live plate for this label is left
		exactly as it is, and the engagement that raised it is the one entitled to
		take it down. ]]
	local function plateShows(sourcePath: string): boolean
		return disclosurePlate ~= nil and disclosurePlate.sourcePath == sourcePath
	end

	--[[ THE HELP PLATE (D3a), built here because this is the first point at which
		every collaborator it reads exists: `handleOwning`, `disclosureTargetIn` (it
		asks the disclosure walker FIRST, so a truncated value outranks the
		convenience) and `safeBox`. It owns no surface — it presents through
		`self.presentAnchored`, which is the D1 seam — and it binds NO gesture: the
		pointer's hover zone and the focus graph are the only two things that reach
		it, which is why nothing appears on touch. See that module's header. ]]
	local helpPlate = helpPlateLib.new({
		env = env,
		stack = stack,
		presenter = self,
		handleOwning = handleOwning,
		discloseTargetIn = disclosureTargetIn,
		metricsNow = metricsNow,
		safeBox = safeBox,
	})

	--[[ ...and the CALLOUT QUEUE (D3b), on the same seam and for the same reason.
		"At most one on screen, a queue not a pile" is `toast_schedule`'s existing
		job, so this is a driver over it rather than a second scheduler. ]]
	local calloutQueue = calloutQueueLib.new({
		presenter = self,
		stack = stack,
		-- so a coach mark dies with the surface it points at rather than outliving
		-- it as an arrow aimed at nothing
		handleByPath = handleOwning,
	})

	local function syncDisclosureFocus(path: string?)
		-- A DIRECT ENGAGEMENT OUTRANKS FOCUS. A pointer dwell or a long press is a
		-- deliberate ask about ONE label; focus merely happens to be somewhere, and
		-- it is re-synced on every refresh. Without this, a refresh under a live
		-- hover plate would replace it with the focused row's plate — the reader's
		-- answer swapped out from under them by a frame of housekeeping.
		if disclosurePlate ~= nil and disclosurePlate.source ~= "focus" then
			return
		end
		local owner = handleOwning(path)
		-- containment (architecture review F-11): a surface that declared no
		-- disclosure anywhere skips the tree walk entirely — the stamp is
		-- conservative (structural regions keep it true), so this can never
		-- silently disable the feature
		if owner ~= nil and owner.hasDisclose ~= true then
			owner = nil
		end
		-- ...AND A POINTER-DRIVEN FOCUS MOVE IS NOT A FOCUS ENGAGEMENT (device round 3,
		-- the same term the ring reads). Tapping a row moves focus there; the
		-- finger asked to press the row, not to read its name, and a plate popping
		-- up under every tap is the tooltip-on-click behaviour nobody wants. The
		-- pointer's own engagement is the hover dwell, which has its own seam.
		if graph.focusVisible:get() == false then
			owner = nil
		end
		-- ...AND THE SURFACE MUST OWN INPUT (rounds 4/6). A passive HUD has focus
		-- IDENTITY from the moment it mounts; it has the keyboard only once it
		-- engages, and a plate presented off a focus the player never moved is the
		-- same lie as a focus ring on a surface the keyboard is not reaching.
		if owner ~= nil and owner.isPassive and owner.responder:get() ~= "engaged" then
			owner = nil
		end
		local targetPath, fullText = disclosureTargetIn(owner, path)
		if targetPath == nil then
			-- focus left every disclosed label, so the plate it raised goes with it
			-- (the guard above already returned for a pointer/touch one)
			if disclosurePlate ~= nil then
				dismissDisclosure("focusLeave")
			end
			return
		end
		if plateShows(targetPath :: string) then
			return -- already answered for this label; a refresh must not restart it
		end
		presentDisclosure(owner, targetPath :: string, fullText :: string, "focus")
	end

	--[[ THE FOCUS ROUTE INTO `help` (D3a), gated exactly as the plate's is above
		and for the same three reasons — which is also, without a single device
		branch, why a touch player sees nothing:

		  * A POINTER-DRIVEN FOCUS MOVE IS NOT A FOCUS ENGAGEMENT (device round 3). A tap
		    sets `focusOrigin = "pointer"`, which clears `focusVisible` — so a
		    finger moves the ring and raises no plate. That is the whole of the
		    touch story: the hover zone is never wired without a pointer class, and
		    the focus route declines a focus the player never navigated to.
		  * A PASSIVE SURFACE HAS FOCUS IDENTITY LONG BEFORE IT HAS THE KEYBOARD,
		    so a HUD that has not engaged does not describe itself unprompted.
		  * `hasHelp` is stamped once at present, so a surface that declared no
		    help anywhere pays nothing for the feature (the F-11 containment rule). ]]
	local function syncHelpFocus(path: string?)
		if graph.focusVisible:get() == false then
			helpPlate.focus(nil)
			return
		end
		local owner = handleOwning(path)
		if owner ~= nil and owner.isPassive and owner.responder:get() ~= "engaged" then
			helpPlate.focus(nil)
			return
		end
		helpPlate.focus(path)
	end

	--[[ ENGAGEMENT SEAMS (adapter-driven; constitution §2 "a leading underscore
		means engine-adapter seam"). Pointer hover and touch long-press are engine
		facts — MouseEnter/MouseLeave and the gesture arbiter's `longPress` — and
		the presenter is engine-free, so the client hands them over here rather than
		this module reaching for either. Focus needs no seam: the presenter owns the
		focus graph and reads it directly (above).

		`nil` means DISENGAGED (the pointer left everything / the press released).
		Both are idempotent: a hover that re-reports the same node neither restarts
		the dwell nor re-mounts the plate. ]]
	local function discloseHoverEngage(path: string?)
		local owner = handleOwning(path)
		local targetPath, fullText = disclosureTargetIn(owner, path)
		if targetPath == nil then
			disclosureDwell = nil
			if disclosurePlate ~= nil and disclosurePlate.source == "pointer" then
				dismissDisclosure("pointerLeave")
			end
			return
		end
		if plateShows(targetPath :: string) then
			return -- already answered for this label, by this or another engagement
		end
		if disclosureDwell ~= nil and disclosureDwell.sourcePath == targetPath then
			return -- the dwell is already counting on this label
		end
		-- moving to a DIFFERENT label retires the old answer immediately; the new
		-- one has to earn its dwell
		if disclosurePlate ~= nil and disclosurePlate.source == "pointer" then
			dismissDisclosure("pointerMove")
		end
		disclosureDwell = {
			owner = owner,
			sourcePath = targetPath,
			text = fullText,
			remaining = DISCLOSE_DWELL,
		}
	end

	--[[ ONE POINTER-ENGAGEMENT SEAM, TWO CONSUMERS (D3a). The renderer wires a
		hover zone on any node declaring `disclose`, `reveal` or `help`, and hands
		every one of them here. The full-value plate answers first, because a value
		the reader cannot see outranks a sentence about what a control does; the
		help plate answers for everything it left, and stands down on the nodes it
		did not. Two plates over one control is never the right answer.

		The help plate takes NOTHING from `_discloseLongPress` below: `help` binds
		no gesture on any input class, exactly as Apple's does not. ]]
	function self._discloseHover(path: string?)
		discloseHoverEngage(path)
		helpPlate.hover(path)
	end

	function self._discloseLongPress(path: string?)
		local owner = handleOwning(path)
		--[[ THE MENU OWNS THE LONG PRESS INSIDE ITS OWN TRIGGER, and only there
			(navigation-and-menus D2). The plate keeps the gesture everywhere else,
			because it is the ONLY touch route to a truncated label's full value:
			`UI.Text{ reveal = "auto" }` is opt-in, `UI.Text`-only, at most one per
			presentation and disabled entirely under reduced motion, and a disclosing
			`Toggle` label or `Table` cell has no marquee even in principle. Deleting
			the binding would therefore have been an accessibility regression that
			`text_audit` structurally cannot see — it checks the DECLARATION, never
			the reachability. So this is a carve-out, not a removal. ]]
		if owner ~= nil and owner.contextTriggerOwns ~= nil and owner.contextTriggerOwns(path) then
			return
		end
		local targetPath, fullText = disclosureTargetIn(owner, path)
		if targetPath == nil then
			if disclosurePlate ~= nil and disclosurePlate.source == "touch" then
				dismissDisclosure("release")
			end
			return
		end
		if plateShows(targetPath :: string) then
			return -- already answered for this label, by this or another engagement
		end
		-- the long press IS the deliberation: no dwell on top of it
		disclosureDwell = nil
		presentDisclosure(owner, targetPath :: string, fullText :: string, "touch")
	end

	--[[ the plate outlives neither its source node nor its surface. Called from
		`refresh` and from `dismiss`.

		TWO conditions, not three. "The source node unmounted" needs no walk of its
		own: `refresh` re-solves before this runs, so a node a `UI.When` closed over
		has no entry in the solve's text facts at all — the same read that answers
		"a re-solve made room for it" answers "it is gone", and it is a map lookup
		rather than a tree walk on every refresh. What the STACK check adds is
		different in kind: it keeps a dismissed surface's DISPOSED controller from
		being read at all. ]]
	local function revalidateDisclosure()
		if disclosureDwell ~= nil and table.find(stack, disclosureDwell.owner) == nil then
			disclosureDwell = nil
		end
		if disclosurePlate == nil then
			return
		end
		local plate = disclosurePlate
		if table.find(stack, plate.owner) == nil then
			dismissDisclosure("surfaceDismissed")
			return
		end
		local facts = plate.owner.controller.textAt ~= nil and plate.owner.controller.textAt(plate.sourcePath)
		if facts == nil or facts.truncated ~= true then
			dismissDisclosure("goneOrNoLongerTruncated")
		end
	end

	--[[ disclosure() -> the live plate, in the shipped `dump()` shape
		(constitution §6): frozen, deterministic, and safe when nothing is up. It is
		the inspection surface for "is the full value reachable right now", which is
		otherwise only observable as pixels. ]]
	function self.disclosure(): any
		if disclosurePlate == nil then
			return table.freeze({ schema = DISCLOSURE_SCHEMA, present = false })
		end
		return table.freeze({
			schema = DISCLOSURE_SCHEMA,
			present = true,
			path = DISCLOSE_PLATE,
			labelPath = DISCLOSE_LABEL,
			sourcePath = disclosurePlate.sourcePath,
			source = disclosurePlate.source,
			text = disclosurePlate.text,
		})
	end

	--[[ THE HELP PLATE'S OWN STATE (D3a, schema `facet-help-dump/1`): what is
		showing, which control asked, which engagement raised it, and how many help
		declarations are live across the whole stack. ]]
	function self.help(): any
		return helpPlate.dump()
	end

	--[[ ...and every live `help` declaration with the routes that actually reach
		it — `{ [path] = { text, hover, focus } }`. This is the input
		`text_audit.helpRoutes` is written against, and it is read off the MOUNTED
		tree and the LIVE interaction classes rather than from a declaration: a
		pure-touch session reports `hover = false` here, which is exactly the fact
		that makes "help is never the only route" checkable instead of asserted. ]]
	function self.helpDeclarations(): any
		return helpPlate.declarations()
	end

	-- ═════════════════ THE AUTO REVEAL (marquee) ═════════════════════════════
	-- The travelling strip a truncated `UI.Text{ reveal = "auto" }` gets moved
	-- into src/present/text_reveal.luau for the 200,000-char Source WRITE cap
	-- (see that header, and the constraint list it carries — the director's
	-- rung-4 rules for what a marquee may and may not do live there now).
	-- It took its only two mutable upvalues with it (`revealState`, `revealScan`)
	-- and reads the rest of this closure by reference, so the move preserved
	-- behaviour by construction. `plateShows` is passed in because of the one
	-- cross-feature rule: a live disclosure plate outranks the ambient travel.
	local textReveal = textRevealLib.new({
		core = core,
		env = env,
		adapter = adapter,
		stack = stack,
		plateShows = plateShows,
	})
	local stepReveal = textReveal.stepReveal
	self.reveal = textReveal.reveal
	self.movingText = textReveal.movingText

	-- no-pop text gate (text-measurement milestone). A gated surface stays
	-- hidden until its renderer reports no outstanding premeasurement round,
	-- OR until its deadline passes — whichever comes first. The deadline is not
	-- optional: an adapter that never answers must not be able to hide a game's
	-- UI permanently.
	local function syncTextReveal(handle: any)
		if not handle.textRevealPending then
			return
		end
		local pending = handle.controller.textPending ~= nil and handle.controller.textPending()
		if pending and os.clock() < handle.textRevealDeadline then
			return
		end
		handle.textRevealPending = false
		handle.textRevealedExact = not pending
		handle.controller.setRootVisible(true)
	end

	-- ===== surface lifecycle ==================================================
	-- The shared focus-visual sync, the per-frame refresh body and the dismissal
	-- pair moved into src/present/surface_lifecycle.luau for the 200,000-char
	-- Source WRITE cap (see that header, and
	-- docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md).
	--
	-- BUILT HERE rather than where any of the three used to stand, because this
	-- is the first line at which every collaborator they read is a FINAL value:
	-- the two focus-driven plates, the anchored/callout registries, and the
	-- reveal gate directly above. That is what makes the seam one-way — the
	-- alternative was a record of forward declarations, which is the shape this
	-- file has been paying for. REBOUND TO THEIR ORIGINAL NAMES, so not one call
	-- site moved.
	local surfaceLifecycle = surfaceLifecycleLib.new({
		graph = graph,
		stack = stack,
		presenter = self,
		displayLayer = displayLayer,
		anchoredSurfaces = anchoredSurfaces,
		helpPlate = helpPlate,
		calloutQueue = calloutQueue,
		revalidateDisclosure = revalidateDisclosure,
		syncDisclosureFocus = syncDisclosureFocus,
		syncHelpFocus = syncHelpFocus,
		syncTextReveal = syncTextReveal,
		retireRevealFor = textReveal.retireRevealFor,
		emitFeedback = emitFeedback,
		refreshExclusive = refreshExclusive,
		syncScrim = syncScrim,
	})
	local syncFocusVisuals = surfaceLifecycle.syncFocusVisuals
	-- THE TWO OBSERVERS REGISTER HERE rather than up beside the focus scalars,
	-- where the function they call used to be declared, and that is order-neutral
	-- for one measured reason: `presenter.new` mounts nothing, so these are still the
	-- FIRST two observers on both signals — every other observer of
	-- `graph.focused` in this library belongs to a CONTROL and is registered at
	-- mount, which cannot happen until this constructor has returned. `observe`
	-- also seeds `lastSeen` from the value at registration, so moving a
	-- registration later inside one constructor cannot make it fire late.
	core:observe(graph.focused, syncFocusVisuals)
	-- ...and on the ORIGIN flipping under a standing focus: the first arrow press
	-- after a tap must bring the ring back onto the node the finger left it on,
	-- without waiting for focus to move somewhere else.
	core:observe(graph.focusVisible, function()
		syncFocusVisuals(graph.focused:get())
	end)
	-- ...and on a RESPONDER flipping, for the same reason: engaging must bring the
	-- ring up on the node focus is already standing on (nothing moved, so neither
	-- observer above fires), and resigning must take it away again. `engage()` and
	-- `resign()` call this; it is exposed on the presenter rather than inlined
	-- there because a handle cannot reach this closure.
	function self.syncFocusVisuals()
		syncFocusVisuals(graph.focused:get())
	end

	-- ===== DRAG-PROXY HOST (ADR-0022 Decision 5; ui-designer §5.3/§6.3) ======
	--
	-- The ghost layer. PRESENTER-PRIVATE exactly like the toast layer: not in
	-- `stack`, no focus scope, no input context, no tap handler — a surface with
	-- nothing to intercept input with. The drag registry drives it through the
	-- three-verb contract (`show`/`transform`/`hide`); the registry owns 1:1
	-- tracking, pickup scale and flights, this host owns pixels and the layer
	-- slot (above toasts, below modals — SURFACE_LAYER.dragProxy). Proxy
	-- blueprints are display composites by contract: nothing here wires a tap,
	-- and an interactive proxy is the caller doing it wrong.
	local dragProxyState: any = nil
	local function dragProxyHide(token: any)
		if dragProxyState == nil or (token ~= nil and dragProxyState.token ~= token) then
			return
		end
		local state = dragProxyState
		dragProxyState = nil
		state.controller.dispose()
		state.scope:dispose()
	end
	local dragProxyHost = {
		show = function(info: any): any
			dragProxyHide(nil) -- one live session, one ghost: a second show replaces
			local rect = (type(info) == "table" and info.rect) or { x = 0, y = 0, w = 44, h = 44 }
			local content = (type(info) == "table" and info.blueprint)
			if content == nil then
				-- the default ghost: a themed plate the size of the grab rect. Styling
				-- rides the NORMALIZING modifiers, never raw prop tables — the same
				-- rule authored screens follow.
				content = blueprintLib.Box({
					id = "Ghost",
					surface = "control",
					width = { type = "fixed", px = rect.w },
					height = { type = "fixed", px = rect.h },
				})
				content = blueprintLib.corners(content, "control")
				content = blueprintLib.shadow(content, "overlay")
			end
			-- the slot pins at the GRAB rect origin; `transform` drives deltas from
			-- there through the presentation channel, so the ghost never touches
			-- solver geometry mid-drag (Decision 2)
			local slot = blueprintLib.ZStack({
				id = "Slot",
				offsetX = rect.x,
				offsetY = rect.y,
				width = { type = "fixed", px = rect.w },
				height = { type = "fixed", px = rect.h },
				children = { content },
			})
			local bp = blueprintLib.Screen({
				id = "__dragproxy__",
				children = {
					blueprintLib.Anchor({
						id = "Layer",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = { slot },
					}),
				},
			})
			local sc = core:scope("present-dragproxy")
			local root = mountLib.mount(core, bp, { scope = sc:child("mount") })
			-- edgeToEdge, NOT coreSafeContent (director fix round, the "odd offset"):
			-- the registry hands this host WINDOW-space coordinates (screenRectOf
			-- includes the core inset), so the ghost surface's own origin must BE the
			-- window origin. Under coreSafeContent the root sat below the inset and
			-- the ghost rendered exactly GuiInset pixels below the finger — invisible
			-- headlessly, where insets are zero.
			local ctrl = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
			ctrl.initialRender()
			if ctrl.setDisplayOrder ~= nil then
				ctrl.setDisplayOrder(SURFACE_LAYER.dragProxy)
			end
			dragProxyState = {
				scope = sc,
				controller = ctrl,
				origin = { x = rect.x, y = rect.y },
				token = {},
			}
			return dragProxyState.token
		end,
		transform = function(token: any, t: any)
			if dragProxyState == nil or dragProxyState.token ~= token then
				return
			end
			dragProxyState.controller.setPresentationTransform("/__dragproxy__/Layer/Slot", {
				x = (t.x or 0) - dragProxyState.origin.x,
				y = (t.y or 0) - dragProxyState.origin.y,
				scale = t.scale,
			})
		end,
		hide = dragProxyHide,
	}

	local function makeHandle(blueprint: any, opts: any, kind: string)
		-- an unknown cancelPolicy is refused LOUDLY, the same way an unknown
		-- rootPolicy is (renderer.attach): a typo that silently kept the default
		-- would read as "the framework ignored my mandatory modal".
		local cancelPolicy = (opts and opts.cancelPolicy) or "dismiss"
		if cancelPolicy ~= "dismiss" and cancelPolicy ~= "none" then
			error(`Facet presenter: unknown cancelPolicy '{tostring(cancelPolicy)}'. Valid: dismiss, none.`, 0)
		end
		-- ...and so do the other two string enums (F-15). They used to be compared
		-- by equality and passed through raw, which is the exact failure the rule
		-- above refuses: `responder = "Passive"` silently presented an ENGAGED
		-- surface that sank nothing it was supposed to sink, and `scrim = "None"`
		-- silently DIMMED the screen. Absent stays legal — each has a default.
		local responderOpt = if opts ~= nil then opts.responder else nil
		if responderOpt ~= nil and responderOpt ~= "passive" then
			error(
				`Facet presenter: unknown responder '{tostring(responderOpt)}'. Valid: passive (omit for engaged).`,
				0
			)
		end
		local scrimOpt = if opts ~= nil then opts.scrim else nil
		if scrimOpt ~= nil and scrimOpt ~= "scrim" and scrimOpt ~= "none" then
			error(`Facet presenter: unknown scrim '{tostring(scrimOpt)}'. Valid: scrim, none.`, 0)
		end
		-- Tab/Shift+Tab wrap policy for this surface's scope (roadmap Step 8),
		-- declared once here rather than per control. Same enum discipline as the
		-- three above: only a boolean, and only this surface's own scope.
		-- keyboardNavigation: per-surface override of the presenter default, and
		-- the switch that decides whether this surface claims the contended keys
		-- at all (director playtest 2026-08-03)
		local keyboardNavOpt = if opts ~= nil then opts.keyboardNavigation else nil
		if keyboardNavOpt ~= nil and type(keyboardNavOpt) ~= "boolean" then
			error(
				`Facet presenter: keyboardNavigation must be a boolean (got {typeof(keyboardNavOpt)}); `
					.. `omit it to inherit the presenter's default.`,
				0
			)
		end
		local keyboardNavigation = if keyboardNavOpt ~= nil
			then keyboardNavOpt
			else presenterOpts.keyboardNavigation == true
		local traversalWrap = if opts ~= nil then opts.traversalWrap else nil
		if traversalWrap ~= nil and type(traversalWrap) ~= "boolean" then
			error(
				`Facet presenter: traversalWrap must be a boolean (got {typeof(traversalWrap)}); `
					.. `it declares whether Tab wraps at the ends of this surface's focus scope.`,
				0
			)
		end
		--[[ A PASSIVE SURFACE TAKES NO INITIAL FOCUS (director, 2026-08-03 round 6,
			revising round 5's "keep first everywhere").

			The default now follows the responder, because that is what the option is
			actually about: a surface that owns input from the moment it mounts should
			say where focus is, and a surface that owns nothing until the player
			touches it has no business claiming any. An explicit `initialFocus`
			always wins, so an author who wants a passive HUD pre-focused says so.

			Engaged-open screens and modals are UNCHANGED — they still default to the
			first focusable, which is every caller that is not passive. ]]
		-- ADOPTED CHROME (F1) — screens only: a modal traps by construction and a
		-- toast is not navigable, so neither has an edge to sit on. The edge name
		-- itself is checked by the graph. See FocusScope.chrome.
		local focusChrome = if opts ~= nil then opts.focusChrome else nil
		if focusChrome ~= nil and kind ~= "screen" then
			error(`Facet presenter: focusChrome is a screen option; a {kind} cannot be adopted as chrome.`, 0)
		end
		local initialFocus = if opts ~= nil then opts.initialFocus else nil
		if initialFocus == nil and kind == "screen" and (opts and opts.responder) == "passive" then
			initialFocus = "none"
		end
		if initialFocus ~= nil and type(initialFocus) ~= "string" and type(initialFocus) ~= "table" then
			error(
				`Facet presenter: initialFocus must be "first", "none", a node id, or \{ id = "…" } `
					.. `(got {typeof(initialFocus)}).`,
				0
			)
		end
		if type(initialFocus) == "table" then
			local id = (initialFocus :: any).id
			if type(id) ~= "string" then
				error(`Facet presenter: initialFocus \{ id = … } needs a string id (got {typeof(id)}).`, 0)
			end
			-- the table form is the ESCAPE HATCH from the reserved words below, so
			-- it is remembered as "definitely an id" rather than collapsed to a
			-- bare string that would be read as a keyword again
			initialFocus = { id = id }
		end

		-- engine-selection bridge: opt-in AND modal/exclusive-only. It is the only
		-- way `GuiService.SelectedObject` is ever set, and therefore the only way a
		-- native `Activated` can echo a key press (the native-substrate round) — but the echo guard in
		-- `dispatchActivate` does NOT read this flag, because the input CLASS of
		-- the native half is a stricter test and needs no per-surface state. Named
		-- here only for the renderer wiring below.
		local selectionBridged = (opts and opts.engineSelectionBridge) == true and kind ~= "screen"
		local scope = core:scope(`present-{kind}-{blueprint.id or "screen"}`)
		--[[ RESPONDER STATE IS HOISTED HERE, above `bindContribution`, because a
			control has to be handed the paint permission below at BIND time and
			`handle` does not exist until far later in this function — writing
			through it there would resolve a nil global (the upvalue trap that bit
			newSlider's trackPath and newTextInput's idPattern in Step 8). The handle
			literal reuses these locals rather than making its own. ]]
		local isPassive = kind == "screen" and (opts and opts.responder) == "passive"
		local responderState = scope:own(core:signal(if isPassive then "passive" else "engaged"))

		--[[ MAY A CONTROL PAINT ITS OWN FOCUSED STATE RIGHT NOW? (director playtest
			2026-08-03 round 6: "slider has focus, and i clicked on the world. it's
			not giving up focus.")

			A control that declares `focusVisual = "none"` paints its own focused
			treatment — a Slider's thumb ring — and it did so from `graph.focused`
			alone. Focus IDENTITY deliberately survives a resign, so the responder
			handed the keyboard back and the slider went on wearing its ring: the
			adapter's ring obeys the ownership gate added in round 4, and a
			control-painted one had no way to see that gate at all.

			So the rule is published as a fact instead of re-derived. Same two terms
			the adapter's ring uses: the ring is a NAVIGATION answer (hidden after a
			pointer move) AND a claim about owning input (a passive surface owns
			none until it engages). ]]
		local focusPaintAllowed = scope:own(core:memo(function(use)
			if use(graph.focusVisible) == false then
				return false
			end
			return not isPassive or use(responderState) == "engaged"
		end))
		-- STRUCTURAL TRANSITIONS (ADR-0022 Decision 3). Every surface gets a
		-- coordinator: it costs a table, builds a spring only when a region actually
		-- declares a transition, and it is the only thing that makes `UI.When
		-- { transition = … }` mean anything on this screen. `surfaceRef` is filled in
		-- once the handle exists, so an `arrive` fired at mount already names its
		-- surface.
		local surfaceRef: any = nil
		local coordinator = transitionsLib.new({
			core = core,
			clock = motionClock,
			metrics = metricsNow,
			feedback = function(event: any)
				event.surface = surfaceRef
				emitFeedback(event)
			end,
		})
		local root = mountLib.mount(core, blueprint, {
			scope = scope:child("mount"),
			transitions = coordinator,
			-- `UI.sensoryFeedback` (round 2 §3.3) emits through here, stamped with
			-- the surface it happened on exactly as the transition coordinator's
			-- events are, so `handle.onFeedback`'s per-surface filter sees it
			feedback = function(event: any)
				event.surface = surfaceRef
				emitFeedback(event)
			end,
		})
		local controller = renderer.attach(core, root, env, adapter, {
			rootPolicy = (opts and opts.rootPolicy) or "coreSafeContent",
			-- default ON; an explicit `false` opts out (see renderer for the measurement)
			recycleInstances = opts == nil or opts.recycleInstances ~= false,
			incrementalLayout = opts == nil or opts.incrementalLayout ~= false,
			-- engine-selection bridge (the native-substrate round, corrections §11):
			-- OPT-IN and modal/exclusive-only. Passive/gameplay surfaces never
			-- set it, so GuiService.SelectedObject stays nil for them.
			-- Facet's logical focus graph remains the sole authority; the
			-- bridge is a render output that clears on teardown. Physical-pad
			-- non-interference proof is the physical-gamepad row; until it closes this
			-- stays an experiment, not a contract.
			engineSelectionBridge = selectionBridged,
			-- FULL-VALUE DISCLOSURE engagement (the large-text round): the live adapter's
			-- pointer enter/leave and touch long-press zones on `disclose`
			-- Texts route into the presenter's engagement seams. The seams
			-- re-check live truncation facts, so a zone firing proves nothing
			-- by itself — which is what lets the wiring be mount-time-static.
			onDiscloseHover = function(path: string?)
				self._discloseHover(path)
			end,
			onDiscloseLongPress = function(path: string?)
				self._discloseLongPress(path)
			end,
			-- pointer taps activate directly (no focus round-trip): same
			-- semantic command path as the Activate action
			onNodeTap = function(path: string, meta: any?)
				-- a control inside a subtree that is playing its EXIT is not there any
				-- more as far as interaction is concerned: it still paints, so it can
				-- still be pressed, and a press on something on its way out is never
				-- what the player meant (ADR-0022 Decision 3)
				if pathIsRetiring(root.node, path) then
					return
				end
				-- A TAP RETIRES THE DISCLOSURE PLATE (the large-text round's "tap
				-- elsewhere"). Every
				-- tap, including one on the disclosed label itself: the plate answers
				-- "what does this say", and a player who has moved on to pressing
				-- something has stopped asking.
				dismissDisclosure("tap")
				-- ...and the help plate with it (D3a): a player who has moved on to
				-- pressing something has stopped asking what it does
				helpPlate.dismiss("tap")
				-- outside-tap policy is owned by the topmost EXCLUSIVE surface: a
				-- modal (ADR-0013's outside-tap rule) OR an engaged-from-passive surface (ADR-0014).
				-- A tap whose path is NOT owned by that surface dismisses/resigns it
				-- (platform sheet dismiss) and never clicks through to a lower handle.
				for i = #stack, 1, -1 do
					local candidate = stack[i]
					local engagedPassive = candidate.isPassive and candidate.responder:get() == "engaged"
					if candidate.kind == "modal" or engagedPassive then
						local surfaceRoot = "/" .. (candidate.blueprint.id or "")
						if not isPathPrefix(surfaceRoot, path) then
							-- outside taps are ALWAYS consumed now (the modal is a barrier):
							-- dismiss/resign, or SWALLOW when the modal declined outside-
							-- dismiss — never a clickthrough to a lower surface (modal-
							-- dismissal spec §3.4, changed from the pre-spec fall-through).
							-- The scrim catcher makes this correct by construction; this
							-- fast-path handles a tap on a rendered lower node.
							applyOutsideOutcome(candidate, engagedPassive)
							return
						end
						break -- only the topmost exclusive surface owns the policy
					end
				end
				local h = handleByPath and handleByPath(path)
				-- transient-popup outside-tap (matrix §B PopupButton; outsideDismiss):
				-- when a base-screen contribution is dismissable-on-outside-tap and the
				-- tapped node is OUTSIDE its subtree, dismiss it (non-destructive). By
				-- default this SWALLOWS the tap (PopupButton's own modal-ish "outside
				-- taps mean dismiss, never clickthrough" semantic — matches the
				-- synthesized catcher, which has nothing else to hand the tap to
				-- anyway). Handles a tap on a rendered sibling ABOVE the synthesized
				-- catcher; taps on empty space route through the catcher. An exclusive
				-- surface above already returned (it owns the policy), so a real modal
				-- never lets a lower popup steal its outside-tap.
				--
				-- `od.consume == false` (row-actions Task 7, the round-7 Zone-A lesson:
				-- "closing must not swallow unrelated clicks") opts OUT of the swallow:
				-- the dismiss still fires, but the tap is NOT returned-and-consumed here
				-- — it falls through to the normal dispatch below, so a tap that closes
				-- an open row's tray on ANOTHER row's button still activates that
				-- button. PopupButton (and anything else that never sets `consume`)
				-- keeps the original swallowing behavior byte-for-byte.
				if h ~= nil then
					for _, c in h.contributions or {} do
						local od = c.bundle.outsideDismiss
						if
							od ~= nil
							and od.active ~= nil
							and od.active:get() == true
							and not isPathPrefix(c.path, path)
						then
							od.dismiss()
							if od.consume ~= false then
								return
							end
						end
					end
				end
				-- a tap on a focusable INSIDE a passive (not-yet-engaged) surface
				-- engages it BEFORE the activate routes (director 2026-07-21): the
				-- surface becomes first responder for that gesture, then dispatches
				if h ~= nil and h.isPassive and h.responder:get() == "passive" then
					h.engage()
				end
				-- Apple model: clicking a focusable moves keyboard focus there
				-- BEFORE the activate routes (director round 2) — navigation
				-- then continues from the clicked control. The ORIGIN is set
				-- first, so the move tracks focus without painting a ring the
				-- finger never asked for (device round 3); the next Navigate restores it.
				graph.setFocusOrigin("pointer")
				graph.focusOn(path)
				if h ~= nil then
					dispatchActivate(h, path, meta, "tap")
				end
			end,
		})
		controller.initialRender()
		-- the coordinator's writes need handles, which only exist once the tree has
		-- rendered; binding flushes whatever a mount-time enter already seeded, so
		-- the first painted frame is the seeded one rather than a frame at rest
		-- followed by a jump
		coordinator.bindController(controller)

		-- discover the mounted input contributions (ADR-0013) in document order;
		-- the presenter auto-composes each screen's four-input story from them,
		-- with every consumer opt overriding its auto counterpart per-opt (below)
		--
		-- THIS ARRAY IS LIVE, AND IS UPDATED IN PLACE BY `syncContributions` ON
		-- EVERY REFRESH (device round 1 — the crown bug). It used to be a
		-- ONE-SHOT walk, which silently assumed every contributing control is
		-- mounted at present() time. `UI.When` exists precisely so that is not
		-- true: RascalRally's whole Sponsor HUD lives under one region gated on
		-- "am I a sponsor", the presenter is constructed at client startup while
		-- the player is still a racer, and so on a real device NOTHING the racer
		-- list contributes was ever wired — no `handleActivate` (a tap on a row
		-- with a card held did nothing at all), no `handleCancel`, no declared
		-- focus groups, no `bindController`. Every headless row passed because
		-- the test rig seats the sponsor BEFORE constructing the presenter.
		-- The focus MAP was already re-derived per refresh for exactly this
		-- reason (see `refresh`, "phase-1 verifier finding F1"); this is the same
		-- rule applied to the wiring the map is useless without.
		local contributions = collectContributions(root.node)
		-- DRAG-TO-EDGE AUTOSCROLL RIDES THE PRESENTER CLOCK (device report
		-- 2026-07-29). A finger parked in a scroller's edge band emits no further
		-- pointer events, so nothing driven by input alone can ever start the
		-- scroll — it needs frames. The policy is the ScrollView's (see the
		-- `autoscroll` prop) and the controller owns the host chain; this is only
		-- the clock, on the one sanctioned frame source, quarantined like every
		-- other tick hook. Inert while no drag is announced.
		if type(controller.stepAutoscroll) == "function" then
			scope:own(self.onTick(function(dt: number)
				controller.stepAutoscroll(dt)
			end))
		end
		-- ONE-TIME wiring per DISCOVERED bundle, run at present time for what is
		-- mounted now and again from `syncContributions` for anything a keyed
		-- region mounts later. Keyed on the bundle table's identity, so a
		-- surviving contribution is never bound twice and a control that
		-- unmounts and remounts (same bundle, same closures) is not re-bound.
		local boundBundles: { [any]: boolean } = {}
		local function bindContribution(c: Contribution)
			if boundBundles[c.bundle] then
				return
			end
			boundBundles[c.bundle] = true
			-- always bind the action system into every contribution
			-- (idempotent — e.g. TextInput's edit-mode sink context uses it)
			if c.bundle.bindActionSystem ~= nil then
				c.bundle.bindActionSystem(actionSystem)
			end
			-- hand over the render controller too (B-VAL2): a control that adopts a
			-- native adapter capability (UIDragDetector) reaches it through the
			-- controller, never by fabricating an adapter handle of its own
			if c.bundle.bindController ~= nil then
				c.bundle.bindController(controller)
			end
			-- and the FOCUS GRAPH, for the controls that must MOVE focus rather
			-- than merely follow it (VirtualList's index focus policy: the data
			-- re-sorted under the ring and the control's policy says the ring stays
			-- on the SLOT). Bound here rather than handed over by the consumer, so
			-- there is exactly one focus authority and no consumer-side split brain.
			if c.bundle.bindFocusGraph ~= nil then
				-- second argument is ADDITIVE: every control written before it
				-- ignores the extra parameter and is unchanged
				c.bundle.bindFocusGraph(graph, focusPaintAllowed)
			end
			-- and the MOTION CLOCK (row-actions Task 4): the same clock every
			-- surface transition, toast schedule, and drag flight already rides
			-- (`self.motionClock` above), so a composite that wants a spring
			-- never builds or threads its own — one clock, one driver, same as
			-- the other three binds this function makes.
			--
			-- second argument is ADDITIVE (row-actions Task 5, same pattern as
			-- bindFocusGraph's own second argument above): `nowFn` is the exact
			-- function `motionClock` itself was built from a few lines up
			-- (`motionClockLib.new(core, { ..., now = nowFn })`) — "the same
			-- source the motion clock uses" a control's own gesture-velocity
			-- tracker needs (contribution.luau bindMotion doc).
			if c.bundle.bindMotion ~= nil then
				c.bundle.bindMotion(motionClock, nowFn)
			end
			-- and PRESENT/DISMISS (row-actions redteam item 2, BLOCKER fix): the
			-- same two functions any app-level caller already reaches through
			-- `presenter.presentModal`/`presenter.dismiss` — the ONLY way a
			-- composite can own a SIBLING top-level surface in `stack` (never a
			-- descendant of its own mounted tree, so it can never inflate its
			-- own — or anyone else's — measured box the way a plain child node
			-- always can). `self.dismiss` is handed over unbound-but-closed-over
			-- `self` (a plain function value, exactly like `self.presentModal`
			-- itself), so a control holding both never needs a reference back to
			-- the presenter object as a whole — the same "hand over exactly what
			-- cannot be constructed, nothing more" shape `bindMotion`/
			-- `bindController`/`bindFocusGraph` already establish. Deliberately
			-- `presentModal`, never plain `present`: two `kind == "screen"`
			-- surfaces share `BASE_SCREEN_PRIORITY` and would double-deliver
			-- Navigate/Activate/Cancel if both sank (see `contextPriority`'s own
			-- comment below, "present the second one as a modal instead") — a
			-- composite-owned floating surface is exactly the case that comment
			-- warns about, so only the collision-free primitive is exposed here.
			if c.bundle.bindPresent ~= nil then
				-- third argument, additive (navigation-and-menus D2): the D1
				-- anchored seam, for the control whose floating surface belongs
				-- against a live source RECT rather than a parent corner
				c.bundle.bindPresent(
					self.presentModal,
					self.dismiss,
					self.presentAnchored,
					self.presentCallout,
					self.releaseCallout
				)
			end
			-- transient-popup outsideDismiss (matrix §B PopupButton): observe each
			-- active readable so the synthesized catcher is mounted/retired as the
			-- popup opens/closes (see the popup-catcher block above)
			if c.bundle.outsideDismiss ~= nil and c.bundle.outsideDismiss.active ~= nil then
				scope:own(core:observe(c.bundle.outsideDismiss.active, function()
					self.syncPopupCatcher()
				end))
			end
		end
		for _, c in contributions do
			bindContribution(c)
		end

		-- GEOMETRY IS A BROADCAST, NOT A ROUTING DECISION (2026-07-27).
		--
		-- `opts.onGeometry` used to WIN OUTRIGHT — feed the consumer, return, and
		-- skip every contribution's `syncGeometry`. That is the right shape for
		-- `onActivate`, where two handlers for one press is a genuine conflict the
		-- surface owner has to settle. It is the wrong shape here: solved rects are
		-- a notification, nothing arbitrates, and there is no reading under which
		-- one listener's interest cancels another's.
		--
		-- What it actually did was arm a silent trap, and the parity reference had
		-- already written it down as one: passing `onGeometry` on a screen holding a
		-- Table disabled that Table's scroll-into-view, and any TextInput's
		-- keep-visible, with nothing to see. A consumer asking "where did my chip
		-- row land" has no way to know it just switched off a control it composed.
		--
		-- Both are fed now. Every syncGeometry in the framework is idempotent and
		-- equality-guarded (text_input's stores and compares; table's assigns), so a
		-- consumer that already forwards by hand — the shape the audit found in the
		-- tutorial examples — simply feeds the same rects twice and nothing moves.
		local function feedGeometry(rectOf: (string) -> any)
			if opts and opts.onGeometry ~= nil then
				opts.onGeometry(rectOf)
			end
			for _, c in contributions do
				if c.bundle.syncGeometry ~= nil then
					-- the contribution's own MOUNTED NODE rides along: a control that
					-- needs the solved rect of one of its own descendants (a Slider's
					-- track) would otherwise have to guess the path, or wait for an
					-- unrelated callback to hand it one. Second argument, so every
					-- existing one-argument syncGeometry is unaffected.
					c.bundle.syncGeometry(rectOf, c.node)
				end
			end
		end
		--[[ ...AND FEED IT AGAIN THE INSTANT THIS SURFACE RE-SOLVES (L-31,
			2026-08-14), not on the next frame.

			`refreshBody` below still calls `feedGeometry` once per frame, and that
			call is what a contribution needs after `syncContributions` mounts a new
			control without any solve happening. What it could never do is serve a
			consumer that PUBLISHES something derived from the rects it is handed —
			a dock reserving its measured height as a safe-area inset, a keyboard
			avoidance inset, a sticky header. That write arrived a whole frame after
			the solve that produced it, so it always opened a SECOND reactive flush
			and re-solved every mounted surface a second time: measured headless on
			the general two-surface shape, 2 flushes and 4 solves per geometry
			change against 1 and 2 with no round trip, plus one painted frame
			carrying the un-settled number.

			Fed from the solve itself — which now runs in the core's settle phase —
			the consumer's write joins the flush that caused it and the cycle
			converges before anything is committed. Both calls are kept because
			`feedGeometry` is idempotent by construction (every syncGeometry in the
			framework is equality-guarded, and that is stated above); feeding the
			same rects twice moves nothing. ]]
		--[[ REGISTERED BEFORE THE FIRST FEED BELOW, deliberately: `settleFeedback`'s
			re-solve announces itself through this listener, so a publication that
			needs a second step (one measurement moving another) converges here
			instead of waiting for a frame. Registration is free until a solve
			happens, and the first solve — `initialRender` above — is already
			over. ]]
		if controller.onSolved ~= nil then
			scope:own(controller.onSolved(function()
				feedGeometry(controller.rectOf)
			end))
		end

		feedGeometry(controller.rectOf) -- feed the first solved geometry
		--[[ ...AND CLOSE THE LOOP THAT FEED MAY HAVE OPENED. This one call is
			outside a solve — `initialRender` runs above, before any contribution is
			discovered, so it cannot be an `onSolved` notification — and the
			renderer's own solve-feedback drain therefore never sees what a
			`syncGeometry` publishes here. A Table's header gutter is the shipped
			case: published from this very call, and laid out un-guttered until the
			first refresh. Every LATER feed rides the listener above and needs
			nothing. ]]
		if controller.settleFeedback ~= nil then
			controller.settleFeedback()
		end

		-- navigation groups: an explicit array/function wins; `false` forces the
		-- flat ring; ABSENT auto-derives grouped nav when any contribution
		-- provides focusGroups, else the flat ring stays (today's behavior)
		local ngOpt = opts and opts.navigationGroups
		local navigationGroups: any = nil
		local navigationGroupsFn: any = nil
		if type(ngOpt) == "function" then
			navigationGroupsFn = ngOpt
			navigationGroups = navigationGroupsFn(root.node)
		elseif type(ngOpt) == "table" then
			navigationGroups = ngOpt -- static array
		elseif ngOpt ~= false then
			local hasFocusGroups = false
			for _, c in contributions do
				if c.bundle.focusGroups ~= nil then
					hasFocusGroups = true
					break
				end
			end
			if hasFocusGroups then
				navigationGroupsFn = autoGroups
				navigationGroups = autoGroups(root.node)
			elseif hasHorizontalStructure(root.node) then
				-- no contributions, but the LAYOUT has a horizontal container /
				-- grid: derive 2D navigation from tree structure (ADR-0013's automatic groups)
				navigationGroupsFn = layoutGroups
				navigationGroups = layoutGroups(root.node)
			end
		end
		-- RE-DISCOVER THE CONTRIBUTIONS FROM THE LIVE TREE (device round 1).
		-- Called at the top of every `refresh`, i.e. after every structural change.
		-- Cheap by construction: one pre-order walk of the same tree `refresh`
		-- already walks for the focus map, and a pass that finds nothing new does
		-- nothing at all. Two things can change:
		--   · a bundle appears (a `UI.When` opened) — it is bound once and starts
		--     receiving Activate/Cancel/geometry from this frame;
		--   · a bundle disappears (the region closed) — it leaves the array, so a
		--     dispatch can never reach a control that is no longer on screen.
		-- A surviving bundle keeps its identity, so nothing is re-bound and no
		-- consumer sees a second `bindController`.
		local autoNavigationGroups = ngOpt == nil
		-- ...AND THE SECOND PER-FRAME TREE WALK, gated on the same epoch as the focus
		-- map (L-27). This runs at the top of every refresh and its own doc calls it
		-- "cheap by construction: one pre-order walk" — which is true per call and
		-- false per second. On an idle mounted surface the walk IS the frame: after the
		-- focus-map cache, `present` was 57% of a 0.180 ms idle frame and this is the
		-- bulk of it.
		--
		-- A contribution is a MOUNTED NODE's input bundle, so the set can only change
		-- when the tree does. The epoch is strictly more conservative than that — it
		-- also bumps on `navigation`/`semantics` dirt — so nothing that could reach the
		-- comparison below is missed.
		local contribEpoch: number? = nil
		local function syncContributions()
			local epoch = if controller.structureEpoch ~= nil then controller.structureEpoch() else nil
			if epoch ~= nil and contribEpoch == epoch then
				return false
			end
			contribEpoch = epoch
			local fresh = collectContributions(root.node)
			local changed = #fresh ~= #contributions
			if not changed then
				for i, c in fresh do
					if contributions[i].bundle ~= c.bundle or contributions[i].path ~= c.path then
						changed = true
						break
					end
				end
			end
			if not changed then
				return false
			end
			-- IN PLACE: `feedGeometry`, the Activate dispatch and the popup sweep
			-- all hold this array (directly or through `handle.contributions`), so
			-- replacing the table would leave stale readers behind.
			table.clear(contributions)
			for _, c in fresh do
				table.insert(contributions, c)
				bindContribution(c)
			end
			-- A LATE focusGroups contribution UPGRADES the scope's navigation model
			-- (a screen whose only grouped control mounts later would otherwise keep
			-- the flat/layout-derived ring forever). Only when the consumer left the
			-- choice to us; an explicit `navigationGroups` opt still wins outright.
			if autoNavigationGroups and navigationGroupsFn ~= autoGroups then
				for _, c in contributions do
					if c.bundle.focusGroups ~= nil then
						navigationGroupsFn = autoGroups
						if surfaceRef ~= nil then
							surfaceRef.navigationGroupsFn = autoGroups
						end
						break
					end
				end
			end
			return true
		end

		-- WHOSE ORDER IS IT? A traversal rank is the framework's opinion about the
		-- order IT derived. When the consumer handed us a focus map — an explicit
		-- `navigationGroups` array or function — that map IS the declared order and
		-- the framework adds no opinion to it: no rank, so `graph.traverse` walks
		-- it exactly as written (the traversal-order ledger). `navigationGroups = false` is
		-- not such a map: it says "no groups", which puts us back on the
		-- framework's own flat derivation, and that does get ranked.
		-- a plain local, carried onto the handle in its table literal below: at this
		-- point in makeHandle `handle` is not yet declared, so writing through it
		-- here would resolve a nil GLOBAL and throw (the upvalue trap that bit
		-- newTextInput.idPattern and newSlider.trackPath in Step 8)
		local consumerFocusMap = ngOpt ~= nil and ngOpt ~= false

		if navigationGroups ~= nil then
			-- grouped, direction-aware scope (§9.3; verifier F2). Hidden candidates
			-- leave the ring here exactly as they do on the flat path below.
			navigationGroups = filterGroupsHidden(
				navigationGroups,
				if controller.hiddenRoots ~= nil then controller.hiddenRoots() else nil
			)
			graph.pushScope({
				name = blueprint.id or kind,
				trap = kind == "modal",
				chrome = focusChrome,
				groups = navigationGroups,
				traversalWrap = traversalWrap,
				initialFocus = resolveInitialFocus(
					initialFocus,
					orderPaths(nil, navigationGroups),
					blueprint.id or kind
				),
				-- derived AFTER the hidden filter, from the filtered map, so the
				-- rank covers exactly the members the scope will have
				traversalRank = if consumerFocusMap then nil else traversalRank(root.node, nil, navigationGroups),
			})
		else
			local order: { string } = {}
			focusOrder(root.node, order)
			order = filterHidden(order, if controller.hiddenRoots ~= nil then controller.hiddenRoots() else nil)
			graph.pushScope({
				name = blueprint.id or kind,
				trap = kind == "modal",
				chrome = focusChrome,
				order = order,
				traversalWrap = traversalWrap,
				traversalRank = traversalRank(root.node, order, nil),
				initialFocus = resolveInitialFocus(initialFocus, order, blueprint.id or kind),
			})
		end

		-- navigation InputContext: modal contexts sit above and SINK so lower
		-- screens never receive navigation while covered (§9.1, spike-true).
		-- Base screens never sink by default (HUD overlays must not eat
		-- gameplay input) but a focus-DRIVEN screen opts in via
		-- opts.sinkNavigation (director hand-test 2026-07-20). NOTE: sinking
		-- is per-CONTEXT, so the opt-in sinks EVERYTHING this context binds —
		-- arrows AND Return/ButtonA/ButtonB (and Adjust keys when wired) —
		-- correct for a full-screen focus-driven list, too broad for a HUD.
		-- Also: base screens share priority 1500, and sink only beats
		-- STRICTLY lower priorities — two focus-driven base screens would
		-- double-deliver on the shared focus graph (modals avoid this via
		-- +500 stacking); present the second one as a modal instead.
		-- Responder mode (ADR-0014). present() default = today's engaged-open
		-- semantics (context enabled, non-sinking — correct for a UI-only place).
		-- opts.responder = "passive" (present() only): the nav context is created
		-- DISABLED so a passive HUD binds nothing gameplay-contended and deviceKey
		-- navigation reaches lower (gameplay) contexts. presentModal is always
		-- engaged-exclusive (sinking). A passive surface becomes first responder
		-- via engage() (tap-in / explicit), raising itself into the engaged band
		-- (3000, strictly above the gameplay sink at 2000) with sink=true, and
		-- drops back on resign() / Cancel / outside-tap.
		local contextPriority: number
		if kind == "modal" then
			contextPriority = topModalPriority() + 500
		elseif isPassive then
			contextPriority = ENGAGED_BASE_PRIORITY
		else
			contextPriority = BASE_SCREEN_PRIORITY
		end
		local context = actionSystem.createContext({
			name = `Nav-{blueprint.id or kind}`,
			priority = contextPriority,
			-- passive starts non-sinking + DISABLED (below); engage() flips both
			-- KEYBOARD NAVIGATION IMPLIES SINKING (director playtest 2026-08-03).
			-- A surface that claims Space and the arrows must also consume them:
			-- priority alone only ORDERS delivery, and with both contexts
			-- non-sinking the avatar jumped and the camera turned while the UI had
			-- focus — measured, 3/3, against the real PlayerModule CharacterContext.
			-- A passive surface still sinks nothing until it engages.
			sink = kind == "modal"
				or (not isPassive and ((opts and opts.sinkNavigation) == true or keyboardNavigation)),
		})
		local navigate = context.createAction("Navigate", "Direction1D")
		local activate = context.createAction("Activate", "Bool")
		local cancel = context.createAction("Cancel", "Bool")
		-- Adjust: the horizontal "change the focused thing" semantic (grip
		-- resize now; sliders later) — keyboard arrows, dpad, and bumpers
		local adjust = context.createAction("Adjust", "Direction1D")
		-- ...and the SAME semantic reached through a DIRECTIONAL key that navigation
		-- would otherwise own (ruling 9, 2026-08-14). Two actions rather than one
		-- because only these bindings can be YIELDED: a control that took Right away
		-- from the ring gives it back when it cannot use it, and Comma/Period/L1/R1
		-- took nothing away and therefore give nothing back. The observer cannot ask
		-- which key produced a Direction1D, so the two answers have to arrive on two
		-- actions — see `AdjustAxis` in bindAdjustKeys and its observer below.
		local adjustAxis = context.createAction("AdjustAxis", "Direction1D")
		-- TRAVERSE: the desktop focus-chain verb (roadmap Step 8). A Bool action,
		-- not a Direction1D, because both directions arrive on the SAME KeyCode —
		-- Shift+Tab is Tab with a modifier, and IAS bindings carry no modifier
		-- slot. The direction is read from the same live modifier state Activate
		-- already uses for range/toggle selection, so keyboard and pointer agree
		-- about what "shift held" means. Its Tab binding is added and removed
		-- dynamically (see setKeyboardBound) — the action existing costs nothing.
		local traverse = context.createAction("Traverse", "Bool")
		navigate.bind({ keyCode = "Down", direction = 1 })
		navigate.bind({ keyCode = "Up", direction = -1 })
		-- gamepad d-pad (PS Cross maps to ButtonA for Activate; the d-pad
		-- names are shared across vendors)
		navigate.bind({ keyCode = "DPadDown", direction = 1 })
		navigate.bind({ keyCode = "DPadUp", direction = -1 })
		-- input-axis tolerance (matrix §D.5; UI-PARADIGM-003): some console
		-- stacks deliver the D-pad (or the left stick) as an analog Thumbstick1
		-- axis, not DPad* keys. Bind it with the deadzone/re-center LATCH so such
		-- a pad still Navigates one step per push (the y component drives the
		-- vertical axis; screen-space convention = +y is down). The IAS
		-- realization is a Studio-drive/physical rider (roblox_input.bindAxis).
		navigate.bindAxis({ axis = "Thumbstick1", component = "y" })
		-- grouped screens own the horizontal axis too (verifier F2): Left/
		-- Right + dpad become real directions instead of Adjust
		-- ...and so does a screen that ADOPTS a chrome strip (F1): the composed scope
		-- is grouped even when this surface's own derivation is one flat ring, so
		-- without this the pad could reach the strip and not walk it. Read at present
		-- time, which is why chrome is presented before the screens that adopt it
		-- (FocusScope.chrome).
		local navigateH = if navigationGroups ~= nil or graph.hasChromeScope()
			then context.createAction("NavigateH", "Direction1D")
			else nil
		if navigateH ~= nil then
			navigateH.bind({ keyCode = "Left", direction = -1 })
			navigateH.bind({ keyCode = "Right", direction = 1 })
			navigateH.bind({ keyCode = "DPadLeft", direction = -1 })
			navigateH.bind({ keyCode = "DPadRight", direction = 1 })
			-- Thumbstick1 horizontal (matrix §D.5): the x component drives the
			-- horizontal axis on a grouped screen, same latch as the vertical.
			navigateH.bindAxis({ axis = "Thumbstick1", component = "x" })
		end
		activate.bind({ keyCode = "Return" })
		activate.bind({ keyCode = "ButtonA" })
		-- horizontal keys bind ONLY when the screen opts in (onAdjust): a
		-- non-modal screen must not shadow gameplay arrow/bumper bindings
		if opts and opts.onAdjust then
			adjust.bind({ keyCode = "Left", direction = -1 })
			adjust.bind({ keyCode = "Right", direction = 1 })
			-- dedicated keys the platform never contends for: Left/Right
			-- arrows are eaten upstream by camera scripts on some control
			-- stacks (hand-test + injection probes 2026-07-20), so comma
			-- and period always reach IAS
			adjust.bind({ keyCode = "Comma", direction = -1 })
			adjust.bind({ keyCode = "Period", direction = 1 })
			adjust.bind({ keyCode = "DPadLeft", direction = -1 })
			adjust.bind({ keyCode = "DPadRight", direction = 1 })
			adjust.bind({ keyCode = "ButtonL1", direction = -1 })
			adjust.bind({ keyCode = "ButtonR1", direction = 1 })
		end

		-- Dynamic Adjust auto-wiring (matrix §B-Table; UI-PARADIGM-001). ADR-0013
		-- kept Adjust consumer-opt-in so a non-modal screen never shadows gameplay
		-- arrow/bumper keys. To close the GAP without reopening that hazard, a
		-- control's contribution can declare `adjustTargets` + `handleAdjust`, and
		-- the presenter binds the Adjust keys ONLY while the FOCUSED path is one of
		-- those targets — so the keys are unbound (never shadowing) whenever focus
		-- sits elsewhere. opts.onAdjust (above) still wins per-opt and binds
		-- unconditionally (back-compat), so this engages only when it is absent.
		-- Comma/Period/L1/R1 never collide with a grouped screen's horizontal
		-- Navigate (NavigateH owns Left/Right + DPad L/R).
		--
		-- THE ARROWS ARE THE CONTROL'S, ON THE AXIS IT DECLARES (roadmap Step 8).
		-- Binding the arrows only on a FLAT screen left the desktop convention
		-- half-built: on any GROUPED screen — which is most real screens, since an
		-- HStack row or a Grid derives groups automatically — Left/Right belonged
		-- permanently to NavigateH, so a focused Slider could only be moved with
		-- comma and period. A control that declares `adjustAxis` now takes that
		-- one axis: the presenter SUSPENDS the directional bindings for it while
		-- the target holds focus and restores them the moment focus leaves. One
		-- key, one action, always — the alternative (both bound, disambiguated in
		-- a handler) delivers the same press to two actions inside one context.
		--
		-- A target that declares NO axis keeps exactly the pre-Step-8 deal:
		-- Comma/Period/L1/R1 always, plus the horizontal arrows only on a flat
		-- screen where nothing else wants them. Table is the reason that stays a
		-- real option rather than an omission — its resizable headers are
		-- navigation stops AND adjust targets at once, and it resolves the
		-- contention with a MODE (Activate selects the column, then the arrows
		-- resize it through `navigateIntercept`, Cancel releases). Taking the
		-- arrows away from Navigate for every focused header would break the walk
		-- through the header row. Declaring an axis is therefore a statement that
		-- the control's value IS the arrows, which is true of a Slider and not of
		-- a column header.
		local ADJUST_AXIS_KEYS: { [string]: { { any } } } = {
			horizontal = { { "Left", -1 }, { "Right", 1 }, { "DPadLeft", -1 }, { "DPadRight", 1 } },
			vertical = { { "Up", -1 }, { "Down", 1 }, { "DPadUp", -1 }, { "DPadDown", 1 } },
		}
		-- which action owns an axis's arrows when nothing is adjusting
		local function axisOwner(axis: string): any
			return if axis == "horizontal" then navigateH else navigate
		end
		-- A SUSPENSION MUST RESTORE WHAT IT TOOK (architecture review). The
		-- whole binding spec is captured, not just the key and direction: a binding
		-- also carries `displayName` (what `inputHint` reads to label the
		-- affordance) and `uiButton`. Restoring a partial spec would silently
		-- relabel a hint the first time focus passed through a value control.
		--
		-- NO TEST PINS THIS, DELIBERATELY. No binding the presenter puts on a
		-- SUSPENDABLE axis carries a displayName today, so a regression written now
		-- would pass against the lossy version too — a check that proves nothing,
		-- which this repository treats as its own defect class. The loss was latent
		-- rather than live; the capture is written to be total so it stays latent
		-- when the first labelled directional binding lands.
		local suspendedNav: { { action: any, spec: any } } = {}
		local function suspendAxisKeys(axis: string)
			local owner = axisOwner(axis)
			if owner == nil then
				return -- a flat screen has no NavigateH: nothing to take the keys from
			end
			for _, pair in ADJUST_AXIS_KEYS[axis] do
				local keyCode = pair[1] :: string
				for i = #owner.bindings, 1, -1 do
					local b = owner.bindings[i]
					if b.keyCode == keyCode then
						table.insert(suspendedNav, {
							action = owner,
							spec = {
								keyCode = b.keyCode,
								direction = b.direction,
								displayName = b.displayName,
								uiButton = b.uiButton,
							},
						})
						b.remove()
					end
				end
			end
		end
		local function restoreSuspendedNav()
			for _, entry in suspendedNav do
				entry.action.bind(entry.spec)
			end
			table.clear(suspendedNav)
		end
		-- `state` is "horizontal" | "vertical" (a declared axis) or "legacy" (a
		-- target that declared none)
		--
		-- WHICH ACTION EACH KEY LANDS ON (ruling 9). The dedicated adjust keys are
		-- always `Adjust`. The DIRECTIONAL keys of a DECLARED axis go to
		-- `AdjustAxis`, because those are the ones that were taken from navigation
		-- and are therefore the ones that can be given back at the control's limit.
		-- The `legacy` flat-screen case keeps them on `Adjust`: nothing was
		-- suspended there (a flat screen has no horizontal navigation at all), so
		-- there is nothing to yield to and its behaviour is byte-identical to before.
		local function bindAdjustKeys(state: string): { any }
			local bound: { any } = {
				adjust.bind({ keyCode = "Comma", direction = -1 }),
				adjust.bind({ keyCode = "Period", direction = 1 }),
				adjust.bind({ keyCode = "ButtonL1", direction = -1 }),
				adjust.bind({ keyCode = "ButtonR1", direction = 1 }),
			}
			local axis = state
			local action = adjustAxis
			if state == "legacy" then
				if navigateH ~= nil then
					return bound -- grouped screen: the arrows stay with Navigate
				end
				axis = "horizontal" -- flat screen: nothing else wants them
				action = adjust
			else
				suspendAxisKeys(axis)
			end
			for _, pair in ADJUST_AXIS_KEYS[axis] do
				table.insert(bound, action.bind({ keyCode = pair[1] :: string, direction = pair[2] :: number }))
			end
			return bound
		end
		local dynamicAdjust = not (opts and opts.onAdjust)
			and (function(): boolean
				for _, c in contributions do
					if c.bundle.adjustTargets ~= nil or c.bundle.handleAdjust ~= nil then
						return true
					end
				end
				return false
			end)()
		local adjustBindings: { any } = {}
		local adjustStateBound: string? = nil
		-- `state` is nil (unbind), "legacy", "horizontal" or "vertical"
		local function setAdjustBound(state: string?)
			if state == adjustStateBound then
				return -- already in the requested state
			end
			for _, b in adjustBindings do
				b.remove()
			end
			adjustBindings = {}
			restoreSuspendedNav()
			adjustStateBound = state
			if state ~= nil then
				adjustBindings = bindAdjustKeys(state)
			end
		end
		-- Escape is permanently bound to the Roblox CoreGui menu (engine
		-- VirtualInput refuses it outright; verified live 2026-07-19, D1) —
		-- keyboard/mouse close affordances are screen-provided (scrim tap,
		-- gear toggle); gamepad B is the bindable Cancel.
		cancel.bind({ keyCode = "ButtonB" })

		-- Gameplay guard (ADR-0014): an engaged-exclusive context (modal, or a
		-- passive surface once engaged) additionally sinks the avatar-contended
		-- keys our other bindings do not already cover. ButtonA is sunk via
		-- Activate and arrows/D-pad via Navigate; Space (keyboard jump) is not,
		-- so bind it to a no-op GameplayGuard Bool action inside this sinking
		-- context. Overridable: opts.gameplayGuard = false opts out (a word-game
		-- modal that wants Space). WASD is deliberately NOT sunk in v1 (ADR-0014
		-- open decision, pending the live IAS move/jump binding-set probe). For a
		-- passive surface the guard lives in a DISABLED context until engage(),
		-- so Space reaches gameplay while passive.
		--
		-- SPACE IS ALSO THE ACTIVATE KEY (roadmap Step 8), which changes what this
		-- guard is for without changing what it protects. While a keyboard is live
		-- and this surface owns UI input, Space rides `activate` — inside the same
		-- sinking context, so the avatar still never sees it — and the no-op guard
		-- is not bound at all: one key belongs to one action. When the keyboard is
		-- absent (a pure-touch or pad-only client) Space is not an activation key
		-- and the no-op guard is what stands between a covered avatar and a jump,
		-- so it goes back on. `gameplayGuard = false` opts out of BOTH: a word game
		-- that wants Space gets Space, and does not get a stray Activate either.
		local spaceIsOurs = not (opts and opts.gameplayGuard == false)
		local gameplayGuard: any = nil
		local gameplayGuardBinding: any = nil
		if (kind == "modal" or isPassive) and spaceIsOurs then
			gameplayGuard = context.createAction("GameplayGuard", "Bool")
		end

		-- ===== desktop keyboard bindings (roadmap Step 8) =====================
		-- Tab and Space are bound ONLY while all three are true:
		--   * this surface has keyboard navigation ENABLED — opt-in at the
		--     presenter, overridable per surface. Off by default, because the keys
		--     it claims are the ones an avatar is already using (director playtest
		--     2026-08-03: with it implicitly on, Space jumped the character while
		--     the UI had focus);
		--   * keyboard capability is LIVE (env interactionClasses.keyboard) — a
		--     phone with no keyboard binds neither, and a tablet that gains one
		--     starts behaving like a desktop with no device branch anywhere; and
		--   * this surface's responder is ENGAGED — a passive HUD binds nothing
		--     gameplay-contended, which is stronger than relying on its context
		--     being disabled, and makes "no leaked sink" a testable claim rather
		--     than an inference about arbitration.
		-- All three are re-evaluated reactively, so a hot-plug adds and removes real
		-- bindings (the Roblox adapter creates/destroys the InputBinding instances)
		-- rather than leaving a dead sink behind.
		local keyboardBindings: { any } = {}
		local function setKeyboardBound(on: boolean)
			if on == (#keyboardBindings > 0) then
				return
			end
			if on then
				keyboardBindings = { traverse.bind({ keyCode = "Tab", displayName = "Tab" }) }
				if spaceIsOurs then
					table.insert(keyboardBindings, activate.bind({ keyCode = "Space" }))
					if gameplayGuardBinding ~= nil then
						gameplayGuardBinding.remove()
						gameplayGuardBinding = nil
					end
				end
			else
				for _, b in keyboardBindings do
					b.remove()
				end
				keyboardBindings = {}
				if gameplayGuard ~= nil and gameplayGuardBinding == nil then
					gameplayGuardBinding = gameplayGuard.bind({ keyCode = "Space" })
				end
			end
		end
		-- the no-keyboard starting state, so a client that never gains one behaves
		-- exactly as it did before this stage
		if gameplayGuard ~= nil then
			gameplayGuardBinding = gameplayGuard.bind({ keyCode = "Space" })
		end

		-- passive surfaces present with their nav context DISABLED: they bind
		-- nothing gameplay-contended until engaged (ADR-0014). engage() enables +
		-- sinks; resign() disables + un-sinks.
		if isPassive then
			context.setEnabled(false)
		end

		-- stamped ONCE at present (architecture review F-11): a surface with no
		-- disclosed label anywhere must pay nothing for the feature — without
		-- this, syncDisclosureFocus walked the whole mounted tree on every focus
		-- change and every refresh of every surface, disclosed or not
		local hasDisclose = false
		-- ...and the reveal's own stamp (2026-08-04), from the same one scan: the
		-- tick's idle rescan skips a surface that declared no reveal anywhere
		local hasReveal = false
		-- ...and `help`'s (D3a), for exactly the same containment reason: a surface
		-- that declared no help anywhere must not pay a tree walk per focus change
		local hasHelp = false
		do
			local function scan(n: any)
				if hasDisclose and hasReveal and hasHelp then
					return
				end
				if n.props ~= nil then
					-- a reveal node is a disclosure source too (its static
					-- full-value alternative), so it stamps BOTH
					if n.props.disclose == true or n.props.reveal ~= nil then
						hasDisclose = true
					end
					if n.props.reveal ~= nil then
						hasReveal = true
					end
					if n.props.help ~= nil then
						hasHelp = true
					end
				end
				-- a structural region can mount ANYTHING later (the
				-- late-contributions class), so its presence keeps the walk —
				-- the optimization must never become a false negative
				if n.class == "When" or n.class == "ForEach" then
					hasDisclose = true
					hasReveal = true
					hasHelp = true
					return
				end
				for _, child in n.children or {} do
					scan(child)
				end
			end
			scan(root.node)
		end

		local handle: any = {
			kind = kind,
			blueprint = blueprint,
			hasDisclose = hasDisclose,
			hasReveal = hasReveal,
			hasHelp = hasHelp,
			scope = scope,
			root = root,
			controller = controller,
			context = context,
			actions = {
				navigate = navigate,
				activate = activate,
				cancel = cancel,
				adjust = adjust,
				-- the YIELDABLE half of Adjust (ruling 9): the directional keys a
				-- declared axis takes away from navigation land on this action and
				-- never on `adjust`, which is what lets one of them be given back
				adjustAxis = adjustAxis,
				traverse = traverse,
			},
			-- ONE ACTIVATE PER PRESS, ACROSS THE TWO PATHS (roadmap Step 8). The shared echo
			-- table + injected clock live on the presenter; the handle carries them
			-- so the module-level dispatchActivate can reach them.
			activateEcho = activateEcho,
			now = nowFn,
			contributions = contributions,
			-- modal outside-tap dismiss (ADR-0013's outside-tap rule): default true; a modal
			-- opts out with outsideTapCancel=false to keep legacy clickthrough
			outsideTapCancel = not (opts and opts.outsideTapCancel == false),
			-- what Cancel (ButtonB) does to this SURFACE once no contribution
			-- consumed it: "dismiss" (default — modal dismisses / engaged-passive
			-- resigns) or "none" (a mandatory surface: Cancel is a no-op)
			cancelPolicy = cancelPolicy,
			onActivate = (opts and opts.onActivate) or nil,
			-- the surface's structural-transition machinery (ADR-0022 Decision 3)
			coordinator = coordinator,
			transition = (opts and opts.transition) or nil,
			emitFeedback = emitFeedback,
			navigationGroupsFn = navigationGroupsFn,
			-- did the FRAMEWORK derive this surface's focus map (rank it) or did the
			-- consumer hand one over (leave it exactly as declared)? Read by refresh,
			-- which re-derives the map on every structural change.
			autoFocusMap = not consumerFocusMap,
			onAdjust = (opts and opts.onAdjust) or nil,
			onReorderNav = (opts and opts.onReorderNav) or nil,
			feedGeometry = feedGeometry,
			-- the live re-discovery of this surface's input contributions (device round 1);
			-- `refresh` calls it before it re-derives the focus map, so a region
			-- that opened this frame is wired BEFORE its nodes join the ring
			syncContributions = syncContributions,
			-- responder mode (ADR-0014): passive surfaces engage/resign; every
			-- other surface reports "engaged" (a plain screen is engaged-open,
			-- non-sinking; a modal is engaged-exclusive). Readable for consumers.
			isPassive = isPassive,
			responder = responderState,
			-- scrim appearance (spec §3.1): modals dim by default; engaged HUDs are
			-- transparent-but-catching; either overridable via opts.scrim.
			scrimMode = (opts and opts.scrim) or (if kind == "modal" then "scrim" else "none"),
			-- cross-surface z (spec §2.2 + ui-designer §6.3): each later surface
			-- renders above the ones before it WITHIN ITS BAND, and the bands keep a
			-- modal above every toast above every base screen whatever order they
			-- arrived in. The synthesized scrim sits at displayOrder-50, beneath its
			-- owner.
			displayOrder = (function()
				displayLayer.value += 100
				return (if kind == "modal" then SURFACE_LAYER.modal else SURFACE_LAYER.base) + displayLayer.value
			end)(),
		}
		if controller.setDisplayOrder ~= nil then
			controller.setDisplayOrder(handle.displayOrder)
		end
		surfaceRef = handle

		-- ONE SURFACE, ONE TRANSITION TARGET. A fading form needs a fade GROUP and a
		-- `Screen` is not one, so the transition targets the root's single declared
		-- `canvasGroup` child when it has one — `UI.ZStack{ canvasGroup = true }`
		-- around the screen's content is the documented shape — and the root itself
		-- otherwise (a slide needs no group).
		handle.transitionNode = (function()
			local rootNode = root.node
			if rootNode.props ~= nil and rootNode.props.canvasGroup == true then
				return rootNode
			end
			local only: any = nil
			for _, child in rootNode.children or {} do
				if child.props ~= nil and child.props.canvasGroup == true then
					if only ~= nil then
						return rootNode -- two groups: the surface itself is the target
					end
					only = child
				end
			end
			return only or rootNode
		end)()
		if handle.transition ~= nil then
			coordinator.beginEnter(handle.transitionNode.path, handle.transitionNode, handle.transition)
		end

		-- the same bus, filtered to this surface (the presenter-level
		-- `presenter.onFeedback` is the primary seam; this is the per-screen one)
		function handle.onFeedback(fn: (event: any) -> ()): () -> ()
			return bus.subscribe(function(event: any)
				if event.surface == handle then
					fn(event)
				end
			end)
		end

		-- no-pop text gate: hide the ROOT now (the tree is already mounted and
		-- solved, it just must not be SEEN yet) and let refresh() reveal it.
		-- Gating is only possible where the adapter can hide a whole root and
		-- the surface actually asked for it.
		handle.textRevealPending = false
		if (opts and opts.revealWhenTextExact) == true then
			local timeout = if type(opts.revealTimeout) == "number" then opts.revealTimeout else 2
			handle.textRevealDeadline = os.clock() + timeout
			-- an adapter that cannot hide a root does not get a hidden surface:
			-- it gets today's behaviour, which is visible and correct
			handle.textRevealPending = controller.setRootVisible(false)
			syncTextReveal(handle)
		end

		-- keyboard-binding gate (roadmap Step 8): live keyboard AND an engaged
		-- responder. Called on present, on engage/resign, and reactively whenever
		-- the live interaction-class set changes, so a keyboard arriving or leaving
		-- mid-session adds and removes the real bindings.
		--[[ ── handle.focusOrder(): what order will Tab take? ────────────────────
			The inspection dump for this surface's focus map, in the shipped `dump()`
			shape (constitution §6): frozen, deterministic — two calls with nothing
			changed in between return equal data — and carrying a `schema` string.

			It reports BOTH readings of the one map. `traversal` is the linear
			Tab/Shift+Tab order with each entry's declared `traversalPriority` and its
			LIVE eligibility; `navigation` is the group map the arrows walk. They are
			meant to differ (a focusable Grip traverses in document position and
			arrows to the end) and they must cover the same set, and a reader can now
			see both facts instead of pressing Tab sixteen times and writing down
			where focus landed — which is how the defect this ships beside was found.

			A node excluded upstream — hidden, disabled, non-focusable, retiring, a
			losing `ViewThatFits` candidate — never reaches the graph and is absent
			here entirely. Its absence IS the answer to "why is it not in my Tab
			order"; `eligible = false` means something narrower, that a live
			focus-skip predicate is refusing it right now.

			SAFE AFTER DISPOSE (the traversal-order ledger). A debug overlay outliving the
			surface it inspects gets an empty map carrying the schema, never a throw:
			an inspection tool that crashes the client it was added to diagnose is
			worse than no tool. ]]
		function handle.focusOrder(): any
			local map = graph.focusMap(handle.blueprint.id or handle.kind)
			if map == nil then
				return table.freeze({
					schema = FOCUS_ORDER_SCHEMA,
					scope = handle.blueprint.id or handle.kind,
					present = false,
					traversal = table.freeze({}),
					navigation = table.freeze({}),
				})
			end
			local traversal = table.create(#map.traversal)
			for _, entry in map.traversal do
				table.insert(
					traversal,
					table.freeze({
						path = entry.path,
						-- the AUTHORED tier, not the resolved rank: the resolved rank is
						-- just this list's index, which the reader can already see
						priority = nodePriority(handle.root.node, entry.path),
						eligible = entry.eligible,
					})
				)
			end
			local navigation = table.create(#map.navigation)
			for _, group in map.navigation do
				local order = table.create(#group.order)
				for _, entry in group.order do
					local path = entryPath(entry)
					if path ~= nil then
						table.insert(order, path)
					end
				end
				table.insert(
					navigation,
					table.freeze({
						name = group.name,
						axis = group.axis,
						-- present only on a TWO-DIMENSIONAL group (ADR-0030), where it is
						-- the lane count: `axis` names the direction ±1 walks and `columns`
						-- says where the lines break, so the perpendicular key moves a whole
						-- line. Nothing in the order shows this — a 4-lane grid and a
						-- 16-button row are the same sixteen paths — which is exactly the
						-- kind of question this dump exists to answer without pressing Tab
						-- sixteen times.
						columns = group.columns,
						order = table.freeze(order),
					})
				)
			end
			return table.freeze({
				schema = FOCUS_ORDER_SCHEMA,
				scope = map.scope,
				present = true,
				trap = map.trap,
				traversalWrap = map.traversalWrap,
				ranked = map.ranked,
				traversal = table.freeze(traversal),
				navigation = table.freeze(navigation),
			})
		end

		function handle.syncKeyboardBindings()
			-- A DISMISSED SURFACE BINDS NOTHING (architecture review). Input
			-- stops the frame `dismiss` runs — `context.destroy()` is immediate —
			-- but a surface with an exit transition keeps `handle.scope` alive until
			-- the transition finishes (or the coordinator's 500 ms cap fires), so
			-- this observer outlives its own context. A keyboard arriving inside
			-- that window would otherwise call `bind` on a destroyed context.
			if context.destroyed then
				return
			end
			local classes = env:get("interactionClasses"):get()
			local keyboardLive = type(classes) == "table" and classes.keyboard == true
			setKeyboardBound(keyboardNavigation and keyboardLive and handle.responder:get() == "engaged")
		end
		scope:own(core:observe(env:get("interactionClasses"), function()
			handle.syncKeyboardBindings()
		end))

		-- engage(): a passive surface becomes first responder — its nav context
		-- rises into the engaged band with sink=true, so it handles events BEFORE
		-- the avatar (IAS priority 3000 > gameplay 2000). No-op for non-passive
		-- surfaces (a modal is always exclusive; a plain screen is engaged-open).
		-- Idempotent, so tap-then-explicit or churn never double-registers.
		function handle.engage()
			if not isPassive or handle.responder:get() == "engaged" then
				return
			end
			context.setEnabled(true)
			-- through the seam, never a field write: the Roblox adapter must
			-- mirror this onto the real InputContext.Sink (P1, 2026-07-21)
			context.setSink(true)
			handle.responder:set("engaged")
			handle.syncKeyboardBindings() -- Tab/Space arrive with first responder
			self.syncFocusVisuals() -- ...and so does the ring (round 4)
			refreshExclusive()
			syncScrim() -- an engaged HUD gets its transparent catcher (spec §3.6)
		end

		-- resign(): drop back to passive — un-sink and disable the nav context so
		-- avatar/gameplay input is restored EXACTLY (Cancel / outside-tap route
		-- here). No-op for non-passive surfaces.
		function handle.resign()
			if not isPassive or handle.responder:get() == "passive" then
				return
			end
			context.setSink(false)
			context.setEnabled(false)
			handle.responder:set("passive")
			handle.syncKeyboardBindings() -- ...and leave with it, binding and all
			self.syncFocusVisuals() -- ...ring included: it claimed input we gave back
			refreshExclusive()
			syncScrim() -- resigned: no longer exclusive, its catcher is retired
		end

		-- navigate intercept (gamepad grab mode etc.): opts.onNavigateIntercept
		-- wins; else chain the contributions' navigateIntercept, first true
		-- consumes the direction
		--[[ HAS A CONTROL ON THIS SURFACE CLAIMED THE CONTEXT GESTURE FOR THIS PATH?
			(navigation-and-menus D2 — the long-press ownership question, settled in
			code.) `contribution.contextTriggers` explains the whole argument; the
			short version is that the disclosure plate KEEPS long-press, because it
			is the only touch route to a truncated label's full value, and a Menu
			trigger subtree is the one carve-out where the press means the menu. ]]
		function handle.contextTriggerOwns(path: string?): boolean
			if path == nil then
				return false
			end
			for _, c in contributions do
				if c.bundle.contextTriggers ~= nil then
					for _, root in c.bundle.contextTriggers() do
						if isPathPrefix(root, path) then
							return true
						end
					end
				end
			end
			return false
		end

		function handle.navigateIntercept(direction: string): boolean
			if opts and opts.onNavigateIntercept ~= nil then
				return opts.onNavigateIntercept(direction) == true
			end
			for _, c in contributions do
				if c.bundle.navigateIntercept ~= nil and c.bundle.navigateIntercept(direction) then
					return true
				end
			end
			return false
		end

		-- focus-move report (Apple selection-follows-focus): opts.onFocusNav
		-- wins; else route to the longest-prefix contribution's focusMoved.
		--
		-- Keep-visible (A-SV1) runs FIRST and unconditionally: any focusable
		-- inside a native scroll host is brought into view by the ONE shared
		-- substrate (controller.scrollToVisible), so a keyboard/gamepad focus
		-- move off the visible band works without every control re-implementing
		-- scroll arithmetic. It is a no-op when the node has no scroll ancestor,
		-- is already visible, or the adapter has no scroll seam — and a control
		-- with its OWN windowing (VirtualList) still gets its focusMoved call.
		function handle.focusMoved(path: string)
			if handle.controller ~= nil and handle.controller.scrollToVisible ~= nil then
				handle.controller.scrollToVisible(path)
			end
			if opts and opts.onFocusNav ~= nil then
				opts.onFocusNav(path)
				return
			end
			for _, c in contributionsForPath(contributions, path) do
				if c.bundle.focusMoved ~= nil and c.bundle.focusMoved(path) then
					return
				end
			end
		end

		-- dynamic Adjust binding gate (matrix §B-Table): bind the Adjust keys iff
		-- the currently-focused (owned) path is a declared adjust target, so
		-- gameplay keys are never shadowed while focus sits off-target. Called by
		-- the shared focus observer on every focus move and by refresh (targets may
		-- churn). No-op unless a contribution opted into the dynamic path.
		-- The axis comes from the OWNING contribution (`adjustAxis`): a control that
		-- declares one consumes those arrows and leaves the other axis to Navigate;
		-- one that declares none keeps the pre-Step-8 key set (roadmap Step 8's
		-- adjust-axis rows).
		function handle.syncAdjustBindings(ownedPath: string?)
			if not dynamicAdjust then
				return
			end
			local state: string? = nil
			if ownedPath ~= nil then
				for _, c in contributions do
					if c.bundle.adjustTargets ~= nil then
						-- ITS OWN NODE, NOT THE SCREEN ROOT (Studio 2026-08-02).
						-- This used to hand every contribution the whole screen,
						-- while `focusGroups` — the seam right beside it — has
						-- always been handed the contribution's own node. Controls
						-- that identify their targets STRUCTURALLY rather than by a
						-- unique id therefore claimed the whole screen: `newStepper`
						-- returns "every Button below here", `newRating` "every
						-- Grip", and on a screen carrying either one plus any other
						-- button the Adjust keys stayed bound with focus anywhere at
						-- all. That is precisely the gameplay-key shadowing this
						-- dynamic binding exists to prevent (matrix §B-Table), and
						-- no headless test saw it because every fixture put the
						-- value control on a screen by itself. Live: focus on an
						-- unrelated Save button, one Right press, an Adjust action
						-- fired and nothing consumed it.
						local targets = c.bundle.adjustTargets(c.node)
						if type(targets) == "table" and targets[ownedPath] == true then
							state = c.bundle.adjustAxis or "legacy"
							break
						end
					end
				end
			end
			setAdjustBound(state)
		end

		-- transient-popup focus trap/restore (matrix §B PopupButton; transientScope).
		-- While a contribution's transientScope is active, focus is TRAPPED within
		-- rootPath's subtree (defaulting to the contribution's own mounted path so the
		-- trigger stays the scope entry — focus does not jump into the open rows on
		-- open) via the focus graph's own trap/restore machinery; on deactivation
		-- focus RESTORES to the pre-activation focused path (the trigger). Driven from
		-- refresh (the rows are mounted/unmounted by the same UI.When at refresh), so
		-- the pushed trap scope always reflects the CURRENT mounted popup.
		local transientPushed: { [string]: boolean } = {}
		local function transientName(c: any): string
			return `__transient__{c.path}`
		end
		function handle.syncTransientScopes()
			for _, c in contributions do
				local ts = c.bundle.transientScope
				if ts ~= nil and ts.active ~= nil then
					local name = transientName(c)
					local wantActive = ts.active:get() == true
					local pushed = transientPushed[c.path] == true
					if wantActive then
						local rootPath = ts.rootPath or c.path
						local sub = nodeAt(root.node, rootPath)
						local order: { string } = {}
						if sub ~= nil then
							focusOrder(sub, order)
						end
						-- a popup's trap scope is a framework-derived flat order like any
						-- other, so it ranks too — a popup holding a Slider traverses in
						-- document order inside its trap (the traversal-order ledger). Ranked
						-- against the POPUP's own subtree, which is the tree its order
						-- was walked from.
						local rank = if sub ~= nil then traversalRank(sub, order, nil) else nil
						if not pushed then
							-- pushScope records the current focus (the trigger) for
							-- restore and enters at order[1] (the trigger) — no jump
							graph.pushScope({ name = name, trap = true, order = order, traversalRank = rank })
							transientPushed[c.path] = true
						else
							-- rows may churn while open: keep the trap order current
							graph.setOrder(name, order, rank)
						end
					elseif pushed then
						graph.removeScope(name) -- top trap: restores focus to the trigger
						transientPushed[c.path] = nil
					end
				end
			end
		end
		-- pop any live transient trap scopes (dismissing a screen with an OPEN
		-- popup must not orphan its trap scope in the focus graph)
		function handle.clearTransientScopes()
			for _, c in contributions do
				if transientPushed[c.path] then
					graph.removeScope(transientName(c))
					transientPushed[c.path] = nil
				end
			end
		end

		-- keep-visible: opts.keepVisibleOffset wins; else observe EVERY
		-- contribution's keepVisibleOffset readable and apply the MAX (the largest
		-- upward shift keeps every field clear of the on-screen keyboard; with a
		-- single control the max is just its own offset — unchanged §17 Phase 5)
		local offsets: { any } = {}
		if opts and opts.keepVisibleOffset ~= nil then
			table.insert(offsets, opts.keepVisibleOffset)
		else
			for _, c in contributions do
				if c.bundle.keepVisibleOffset ~= nil then
					table.insert(offsets, c.bundle.keepVisibleOffset)
				end
			end
		end
		if #offsets > 0 then
			local function maxOffset(): number
				local m = 0
				for _, r in offsets do
					local v = r:get()
					if type(v) == "number" and v > m then
						m = v
					end
				end
				return m
			end
			for _, r in offsets do
				scope:own(core:observe(r, function()
					controller.setPresentationOffset(maxOffset())
				end))
			end
			controller.setPresentationOffset(maxOffset())
		end

		-- ARMED AIM = FOCUS, ONE TRUTH (director virtual-controller round): a
		-- consumed intercept that stepped a live armed session's aim must move
		-- the RING with it — two parallel "where am I" states (a frozen ring and
		-- an invisible aim) is exactly the disorientation the live pass found.
		-- focusOn feeds the shared focused-observer, which re-aims idempotently.
		local function syncFocusToAim()
			local reg = if controller.peekDragRegistry ~= nil then controller.peekDragRegistry() else nil
			if reg ~= nil and reg.mode ~= nil and reg.mode() == "armed" then
				local target = reg.interactionTarget()
				if target ~= nil and target ~= graph.focused:get() then
					graph.focusOn(target)
				end
			end
		end

		-- ONE IMPLEMENTATION OF "AN ARROW MOVED THE RING", per axis (ruling 9). It is
		-- a named function rather than an observer body because there are now TWO
		-- ways to reach it: the arrow key itself, and a value control YIELDING that
		-- arrow at its limit. A yield that reimplemented any part of this — the
		-- focus-origin reset, the screen's intercept, the armed-aim sync, the
		-- focus-moved report — would be a second, quietly different kind of arrow
		-- press, which is exactly the drift this framework keeps paying for.
		local function navigateHorizontal(dir: number)
			-- a NAVIGATION verb asks "where does the ring go next", so the ring
			-- comes back even if a tap had put it away (device round 3)
			graph.setFocusOrigin("navigation")
			local direction = if dir == 1 then "right" else "left"
			if handle.navigateIntercept(direction) then
				syncFocusToAim()
				return
			end
			graph.navigateDirection(direction)
			local focused = graph.focused:get()
			if focused ~= nil then
				handle.focusMoved(focused)
			end
		end
		if navigateH ~= nil then
			scope:own(core:observe(navigateH.state, function(dir)
				if dir == 1 or dir == -1 then
					navigateHorizontal(dir)
				end
			end))
		end
		local function navigateVertical(dir: number)
			graph.setFocusOrigin("navigation") -- see the horizontal case above
			local vertical = if dir == 1 then "down" else "up"
			-- gamepad grab mode etc.: the screen may CONSUME the move
			if handle.navigateIntercept(vertical) then
				syncFocusToAim()
				return
			end
			if navigationGroups ~= nil then
				-- direction-aware vertical movement for grouped scopes
				graph.navigateDirection(vertical)
				local focused = graph.focused:get()
				if focused ~= nil then
					handle.focusMoved(focused)
				end
				return
			end
			-- shift+Navigate: move the focused thing instead of focus
			-- (list reorder — the keyboard-reachable drag equivalent).
			-- Shift held CONSUMES the key even when the reorder is
			-- impossible (top row + up): falling through would wrap focus
			-- to the far end (verifier 2026-07-20 F1)
			if handle.onReorderNav ~= nil and actionSystem.modifiers ~= nil and actionSystem.modifiers().shift then
				local focused = graph.focused:get()
				if focused ~= nil then
					handle.onReorderNav(focused, dir)
				end
				return
			end
			graph.navigate(dir)
			-- Apple model: navigation-driven focus moves report to the
			-- screen (selection follows focus in lists); pointer focusOn
			-- does NOT route here — tap selection rides the activate meta
			local focused = graph.focused:get()
			if focused ~= nil then
				handle.focusMoved(focused)
			end
		end
		scope:own(core:observe(navigate.state, function(dir)
			if dir == 1 or dir == -1 then
				navigateVertical(dir)
			end
		end))
		-- ADJUST DISPATCH, shared by both adjust actions. Returns whether anything
		-- claimed the press — which is what the axis action turns into a yield.
		local function dispatchAdjust(dir: number): boolean
			local focused = graph.focused:get()
			if focused == nil then
				return false
			end
			if handle.onAdjust then
				-- rectOf rides along so consumers can seed a first adjust
				-- from the actually-rendered size (fill columns)
				handle.onAdjust(focused, dir, controller.rectOf)
				-- the legacy opt-in returns nothing and its keys are bound
				-- unconditionally, so it is treated as always claiming the press
				return true
			end
			-- contribution dynamic path (matrix §B-Table): route to the
			-- longest-prefix contribution's handleAdjust
			for _, c in contributionsForPath(contributions, focused) do
				if c.bundle.handleAdjust ~= nil and c.bundle.handleAdjust(focused, dir) then
					return true
				end
			end
			return false
		end
		scope:own(core:observe(adjust.state, function(dir)
			if dir == 1 or dir == -1 then
				dispatchAdjust(dir)
			end
		end))
		--[[ THE ARROW GOES BACK TO NAVIGATION AT THE CONTROL'S LIMIT (ruling 9,
			2026-08-14, director: "do a").

			MEASURED LIVE on the shipped playlist before this existed: `DPadRight` on
			a rating strip at 5 of 5 moved neither the value nor the ring, so nothing
			after the rating in that row could be reached with a gamepad at all — and
			a gamepad has no Tab. The control had SUSPENDED Right from `NavigateH`
			(see `suspendAxisKeys`) and then declined to use it.

			The rule is the narrow one: a control gives back exactly the key it took.
			`handleAdjust` already returns false when the value did not move — every
			value control's `apply` reports that — so this is one condition on an
			answer the contract was already giving. Comma/Period/L1/R1 arrive on the
			OTHER action and are unaffected: they suspended nothing, so a bumper at
			the limit still does nothing, which is how a platform stepper behaves.

			`adjustStateBound` is the axis the keys were bound FOR, so the yield goes
			to that axis's navigation and cannot map a vertical control's press onto
			a horizontal move. On a flat screen `bindAdjustKeys` never puts the
			arrows on this action, so there is no case where the ring is asked to
			move along an axis that has no navigation. ]]
		scope:own(core:observe(adjustAxis.state, function(dir)
			if not (dir == 1 or dir == -1) then
				return
			end
			if dispatchAdjust(dir) then
				return -- the control used it
			end
			if adjustStateBound == "vertical" then
				navigateVertical(dir)
			elseif navigateH ~= nil then
				navigateHorizontal(dir)
			end
			-- A YIELD ENDS THIS PRESS, AND HAS TO SAY SO. The key-up that would put
			-- this Direction1D back to neutral is no longer reliably ours: the ring
			-- has moved, and either the bindings were torn down (they cannot deliver
			-- a release) or the ring landed on ANOTHER adjust target, where
			-- `setAdjustBound` sees no state change and rebinds nothing. `_deliver`
			-- deduplicates, so a value left latched at 1 SWALLOWS the next press of
			-- the same arrow outright — the second rating in a row would be dead on
			-- arrival. Neutralising here covers both exits with one line (pinned:
			-- "the yield RE-ARMS ... the NEXT value control in the row").
			adjustAxis.state:set(0)
		end))
		-- TRAVERSE (Tab / Shift+Tab, roadmap Step 8). Shift chooses the direction
		-- from the same live modifier state Activate reads.
		--
		-- A contribution may CONSUME the verb before the ring moves — the one case
		-- that exists today is a TextInput being edited, which has to run its own
		-- commit/validation path first and only then let focus advance. It returns
		-- true to keep focus where it is (validation refused), false to say "I have
		-- finished, go ahead", and the traversal happens here either way rather
		-- than inside the control, so there is exactly one place that moves focus.
		traverse.onPressed(function()
			local backward = actionSystem.modifiers ~= nil and actionSystem.modifiers().shift
			local direction = if backward then -1 else 1
			-- a traversal verb asks "where does the ring go next", so the ring comes
			-- back even if a tap had put it away (device round 3)
			graph.setFocusOrigin("navigation")
			local from = graph.focused:get()
			if from ~= nil then
				for _, c in contributionsForPath(contributions, from) do
					if c.bundle.handleTraverse ~= nil and c.bundle.handleTraverse(from, direction) then
						return -- consumed: focus stays where it is
					end
				end
			end
			if graph.traverse(direction) then
				local focused = graph.focused:get()
				if focused ~= nil then
					-- the same focus-move report every other navigation verb makes:
					-- keep-visible first, then the owning contribution
					handle.focusMoved(focused)
				end
			end
		end)
		activate.onPressed(function()
			-- held modifiers ride along so list semantics (range/toggle select)
			-- work identically for keyboard and pointer
			local meta: any = { source = "action" }
			if actionSystem.modifiers ~= nil then
				local mods = actionSystem.modifiers()
				meta.shift = mods.shift
				meta.toggle = mods.toggle
			end
			--[[ THE PRESS GOES TO WHOEVER OWNS THE NODE (F1). Adopted chrome is the one
				case where focus can stand on another surface: the strip is passive, so the
				ACTIVE screen's context is what hears ButtonA, and dispatching that against
				THIS handle resolves `nodeAt` to nil and the press evaporates — exactly how
				the chrome broke last time (`showcase_chrome.luau` §1). Gated on
				`isAdoptedChrome`, not on "the path is not mine": two un-sunk base surfaces
				both bind Activate, and re-routing on absence would make one press one
				activation PER surface that heard the key. ]]
			local focused = graph.focused:get()
			local target = handle
			if graph.isAdoptedChrome(focused) then
				target = (handleByPath ~= nil and handleByPath(focused :: string)) or handle
			end
			dispatchActivate(target, focused, meta, "action")
		end)
		cancel.onPressed(function()
			-- transient-popup Cancel (matrix §B PopupButton; handleCancel): offer
			-- Cancel to the focused/longest-prefix contribution BEFORE the modal-
			-- dismiss / passive-resign / no-op branches (first true consumes). An
			-- open popup consumes it (closes); with nothing to cancel it returns
			-- false and Cancel falls through. ORDERING: a base screen and a modal
			-- are SEPARATE contexts — a modal above sinks ButtonB, so a base
			-- popup's handleCancel never fires while a modal is up (the modal's own
			-- dismiss wins, as required). Inside a MODAL, its OWN contribution is
			-- offered first, then the modal dismiss falls through — so a modal that
			-- contains an open popup closes the popup on the first ButtonB and
			-- dismisses on the second. Every existing modal/responder test stays
			-- green (no prior contribution declares handleCancel).
			local focused = graph.focused:get()
			local candidates = if focused ~= nil then contributionsForPath(contributions, focused) else contributions
			for _, c in candidates do
				if c.bundle.handleCancel ~= nil and c.bundle.handleCancel(focused) then
					return
				end
			end
			--[[ A CARD THE GENERIC VERB PICKED UP IS PUT BACK DOWN (the adaptation
				wave's generic-verb row). After
				the contributions, because a control that owns its own grab owns its own
				Cancel; before the surface branches, because a player holding something
				means "put it down", not "close the screen". `cancelArmed` answers false
				unless THIS seam armed the live session, so a VirtualList grab and every
				existing modal/responder route are untouched. ]]
			if controller.cancelArmed ~= nil and controller.cancelArmed("cancelVerb") then
				return
			end
			-- cancelPolicy = "none": the SURFACE ignores Cancel (a mandatory modal
			-- whose choice has no legal "not now"). Declared per surface, checked
			-- AFTER the contribution offer above, so a control inside a mandatory
			-- modal still cancels itself.
			if handle.cancelPolicy == "none" then
				return
			end
			if handle.kind == "modal" then
				self.dismiss(handle)
			elseif handle.isPassive and handle.responder:get() == "engaged" then
				-- Cancel on an engaged-from-passive surface resigns it (back to
				-- passive, context disabled) instead of doing nothing (ADR-0014)
				handle.resign()
			end
		end)

		-- ROADMAP STEP 5 DRAG INTEGRATION (ADR-0022 Decision 5): every surface's registry
		-- receives the presentation collaborators the moment the surface exists,
		-- so no fixture or game ever wires them — the feedback bus (drag events
		-- carry this surface), the shared motion clock (pickup scale, flights),
		-- an injected `now`, and the ghost layer above. `emit` adapts the
		-- registry's `(event, info)` shape onto the bus's Event table.
		if controller.setDragCollaborators ~= nil then
			controller.setDragCollaborators({
				feedback = {
					emit = function(event: string, info: any)
						emitFeedback({
							type = event,
							path = if type(info) == "table" then (info.source or info.targetId) else nil,
							reason = if type(info) == "table" then info.reason else nil,
							surface = surfaceRef,
							context = info,
						})
					end,
				},
				motionClock = motionClock,
				now = nowFn,
				proxy = dragProxyHost,
			})
		end
		-- FINDING F7: a trapping surface presenting cancels any live drag on the
		-- surfaces beneath it. Broadcast to registries that already EXIST (peek —
		-- never build a registry just to tell it about a modal); the registry
		-- itself decides which kinds trap.
		for _, liveHandle in stack do
			local reg = if liveHandle.controller ~= nil and liveHandle.controller.peekDragRegistry ~= nil
				then liveHandle.controller.peekDragRegistry()
				else nil
			if reg ~= nil then
				reg.surfacePresented(kind)
			end
		end
		table.insert(stack, handle)
		-- ...and the surface's keyboard bindings, now that its responder is known
		handle.syncKeyboardBindings()
		refreshExclusive() -- a modal joining the stack raises the exclusive flag
		syncScrim() -- synthesize/move the catcher beneath the new top exclusive surface
		-- paint the INITIAL focus ring: the shared focused-observer fired
		-- during pushScope, BEFORE this handle joined the stack, so the first
		-- focus of a fresh screen never rendered its ring (latent since
		-- phase 1; surfaced by the gamepad flow, 2026-07-20)
		--
		-- THROUGH THE SHARED FUNCTION, not by hand (round 4). This used to call
		-- `controller.setFocusPath(current)` with no second argument, so the ring
		-- defaulted to VISIBLE and skipped every rule the shared path applies —
		-- which is how a passive surface came up painting a ring over a keyboard it
		-- had not bound. One decision site, so a rule added there cannot be missed
		-- here; it also drops a hand-rolled copy of the same ownership/adjust work.
		if graph.focused:get() ~= nil then
			self.syncFocusVisuals()
		end
		return handle
	end

	handleByPath = function(path: string): any
		-- taps route to the handle whose blueprint owns the path prefix;
		-- modals sit later in the stack, so search from the top
		for i = #stack, 1, -1 do
			local handle = stack[i]
			local rootPath = "/" .. (handle.blueprint.id or "")
			--[[ SEGMENT-ALIGNED (the reuse audit). The raw `string.sub` form that stood here
				made `/Menu` own every tap on `/MenuBar/…`: the search runs from the top
				of the stack, so whichever of the two was presented LAST swallowed the
				other's taps, dispatched them against a handle with no such node, and
				the button did nothing at all. ]]
			if isPathPrefix(rootPath, path) then
				return handle
			end
		end
		return nil
	end

	function self.present(blueprint: any, opts: PresentOpts?)
		specGuard.assertKnownKeys("presenter.present", opts, PRESENT_OPTS_KEYS, "opts")
		return makeHandle(blueprint, opts, "screen")
	end

	--[[ AN ANCHORED SURFACE (D1). `panel` is a PANEL blueprint — any node, not a
		`UI.Screen`: the Screen root, the full-viewport anchor layer, the
		window-space placement and the optional arrow tail are synthesized by
		`src/present/anchored.luau`, which then delegates to `present`/`presentModal`
		(`opts.modal = true`) so every `PresentOpts` key, the focus scope, the
		layering band and the tap-away catcher are the ones every other surface uses.
		`opts.anchor` names the source (a mounted `path` or a fixed `rect`), the
		preferred `edge`, the `align`ment along it, the `gap`, the `tail` and the
		`overflow` policy. See docs/reference/api.md § Anchored surfaces. ]]
	function self.presentAnchored(panel: any, opts: any)
		return anchoredSurfaces.present(panel, opts)
	end

	-- every live anchored surface, its resolved edge, whether it flipped, how far
	-- it shifted and what became of its tail (schema `facet-anchored-dump/1`)
	function self.anchoredSurfaces(): any
		return anchoredSurfaces.dump()
	end

	--[[ OPEN A REGION'S EXPAND FROM SOMEWHERE ELSE (wave REVEAL).

		A stepped-down region carries its own affordance and needs nothing from any
		caller. This is for the SECOND route to the same disclosure: a screen's
		overflow census lists what the screen has stopped showing, and a row for a
		SIMPLIFIED region has to open the same plate the region's own affordance
		opens — not a copy of it, and not the census's own idea of what that region
		holds. Two plates for one region is how the two drift.

		It takes the region's PATH, which is what the composition resolution already
		names every region by (`resolution.regions[i].id`), so a census built from
		the framework's own list has the argument in its hand. Returns the
		presentation that opened ("anchored" | "sheet" | "custom") or nil when there
		was nothing to open — a region at its richest form has nothing more to show,
		and that is an answer rather than a failure.

		The lookup is the shipped one: longest-prefix contribution dispatch, top of
		the stack down, exactly as an Activate is routed. ]]
	function self.expand(path: string): string?
		for i = #stack, 1, -1 do
			local handle = stack[i]
			for _, c in contributionsForPath(handle.contributions or {}, path) do
				if c.bundle.expandOpen ~= nil then
					return c.bundle.expandOpen()
				end
			end
		end
		return nil
	end

	--[[ A CALLOUT'S TURN ON SCREEN (D3b). `spec` is
		`{ id, build, priority?, key?, onShow?, onHide? }`, and `build()` returns the
		panel blueprint and its anchor table when this request's turn comes — the
		queue mounts, the caller builds. Returns the entry id for
		`releaseCallout(id, reason)`.

		AT MOST ONE IS EVER ON SCREEN, and a second request WAITS rather than
		stacking beside it. That rule, the priority ordering, the queue cap and the
		read floor priority may never truncate are all `toast_schedule`'s, which is
		why this is a driver and not a second scheduler
		(`src/present/callout_queue.luau`). ]]
	function self.presentCallout(spec: any): number
		return calloutQueue.request(spec)
	end

	function self.releaseCallout(id: number, reason: string?): boolean
		return calloutQueue.release(id, reason)
	end

	-- what is on screen and what is waiting (schema `facet-callout-queue-dump/1`)
	function self.callouts(): any
		return calloutQueue.dump()
	end

	function self.presentModal(blueprint: any, opts: PresentOpts?)
		specGuard.assertKnownKeys("presenter.presentModal", opts, PRESENT_OPTS_KEYS, "opts")
		-- the base screen's context stays enabled for non-sunk actions, but
		-- navigation keys are sunk by the modal context's priority+sink
		local handle = makeHandle(blueprint, opts, "modal")
		-- A MODAL CANCELS A LIVE DRAG (ui-designer spec §5.4/§6.3; disposition F7).
		-- A focus trap and a drag proxy cannot coexist: the proxy tracks a pointer
		-- the trap has just taken away, and the drop it would resolve against is
		-- behind a barrier. The presenter states the fact; P4's drag session
		-- subscribes here and cancels itself (emitting its own `cancel` event with a
		-- reason) — the presenter never reaches into a session it does not own.
		local watchers = table.clone(modalWatchers)
		for _, fn in watchers do
			fn(handle)
		end
		return handle
	end

	-- P4's registration point for the rule above; returns an unsubscribe.
	function self.onModalPresented(fn: (handle: any) -> ()): () -> ()
		assert(type(fn) == "function", "presenter.onModalPresented takes a function(handle)")
		table.insert(modalWatchers, fn)
		return function()
			local index = table.find(modalWatchers, fn)
			if index ~= nil then
				table.remove(modalWatchers, index)
			end
		end
	end

	-- critical-screen fallback (§17 Phase 4): a screen whose construction or
	-- presentation throws presents opts.fallbackScreen(err) instead of taking
	-- the client down. The factory runs under pcall; so does makeHandle, so a
	-- blueprint that explodes during mount/render also falls back. The
	-- fallback screen itself presents normally (its errors stay hard).
	function self.presentCritical(blueprintFactory: () -> any, opts: PresentOpts)
		specGuard.assertKnownKeys("presenter.presentCritical", opts, PRESENT_OPTS_KEYS, "opts")
		assert(
			type(opts) == "table" and type(opts.fallbackScreen) == "function",
			"presentCritical requires opts.fallbackScreen(err) -> Blueprint"
		)
		local ok, blueprintOrError = pcall(blueprintFactory)
		if ok then
			local presented, handleOrError = pcall(makeHandle, blueprintOrError, opts, "screen")
			if presented then
				return handleOrError
			end
			blueprintOrError = handleOrError
		end
		-- THE FALLBACK IS PRESENTED WITH THE CALLER'S OPTS (F-16). It used to get
		-- `{ onActivate = … }` and nothing else, so a critical screen declared
		-- `rootPolicy = "edgeToEdge"` (or navigationGroups, transition,
		-- keepVisibleOffset, sinkNavigation…) lost every one of them exactly when
		-- things had already gone wrong — the stand-in rendered under the wrong
		-- root policy and the wrong navigation model, a second failure stacked on
		-- the first. Everything the caller declared about this screen is still
		-- true of the screen standing in for it. `fallbackScreen` is the one opt
		-- that does not ride along: the fallback presents as an ordinary screen
		-- and its own errors stay hard.
		local fallbackOpts: any = table.clone(opts :: any)
		fallbackOpts.fallbackScreen = nil
		return makeHandle(opts.fallbackScreen(blueprintOrError), fallbackOpts, "screen")
	end

	-- `dismiss` and `back` live in src/present/surface_lifecycle.luau now, with
	-- the shared focus-visual sync and the refresh body — see that module's
	-- header for why the three are one seam and what the `displayLayer` record
	-- costs. Bound HERE, where they have always been declared, so every caller
	-- reads the same `self.dismiss` it always did.
	self.dismiss = surfaceLifecycle.dismiss
	self.back = surfaceLifecycle.back
	-- ...and so does `refresh`, whose loop ends by calling the focus-visual sync
	-- back through `self` — round 7's rule, that there is exactly ONE copy of the
	-- "does this surface own input" decision, is what keeps them in one file.
	self.refresh = surfaceLifecycle.refresh

	-- ===== withAnimation (docs/plans/parity-round2.md §Phase 1) ===============
	--
	-- `presenter.withAnimation("container", function() open:set(true) end)` — the
	-- layout lands exactly and instantly as it always did, and every node whose box
	-- MOVED is painted travelling from where it used to be, over one spring. It is a
	-- PRESENTER method rather than a `UI.` modifier because it needs all three of the
	-- things only the presenter has: the motion clock it builds, the controller
	-- scopes that own the records, and `refresh` itself.
	--
	-- The verb, its two refusals (re-entrancy and the nesting probe) and its two
	-- diagnostics live in src/present/with_animation.luau — moved for the
	-- 200,000-char Source WRITE cap, which this file was 519 characters from. That
	-- module's header carries the seam test it passed and the four read-only names
	-- it takes. REBOUND TO THEIR ORIGINAL NAMES, so not one call site moved.
	local withAnimation = withAnimationLib.new({
		core = core,
		presenter = self,
		stack = stack,
		motionClock = motionClock,
	})
	-- session-lifetime, like the presenter itself (it has no dispose); kept on self
	-- so the ownership is visible rather than implicit
	self._animationProbeWatcher = withAnimation.probeWatcher
	self.withAnimation = withAnimation.withAnimation
	self.animationRecordCount = withAnimation.animationRecordCount
	self.commitCount = withAnimation.commitCount

	-- ===== TOASTS (ADR-0022 Decision 4) =======================================
	--
	-- A toast surface is PRESENTER-PRIVATE, exactly like the scrim and the popup
	-- catcher: it is not in `stack`, pushes no focus scope, creates no input
	-- context and wires no tap handler. That is what "input-transparent" is —
	-- not a property the layer politely observes, but a surface that has nothing
	-- to observe it with. Nothing here can reach `SelectedObject`, the responder
	-- chain, or the outside-tap policy, because none of that is built.
	--
	-- ONE layer holds every visible toast, as a keyed `UI.ForEach` carrying the
	-- transition — so a toast's enter/exit is the SAME retire model a `UI.When`
	-- gets, proven by the same tests, rather than a second animation path.
	--
	-- The scheduler (`toast_schedule`) owns priority, the queue cap, read floors
	-- and supersede; this driver owns pixels. Under reduced motion the transition
	-- places instantly and the schedule is untouched: every toast that would have
	-- been shown is still shown, for the same time (ADR-0022 Decision 4).
	local toastTime = 0
	local toastPosition = "top"
	local toastTransition: any = nil
	local toastLayer: any = nil
	local toastSchedule: any = nil
	local syncToastLayer: () -> ()

	local function toastRowBlueprint(entry: any): any
		-- the fade GROUP the transition needs, wrapped by the presenter so a caller
		-- never has to know that a fade is a CanvasGroup fact
		return blueprintLib.ZStack({
			id = "Toast",
			width = { type = "fill", weight = 1 },
			height = { type = "content" },
			canvasGroup = true,
			children = { entry.data.blueprint },
		})
	end

	local function disposeToastLayer()
		if toastLayer == nil then
			return
		end
		local layer = toastLayer
		toastLayer = nil
		layer.coordinator.dispose()
		layer.controller.dispose()
		layer.scope:dispose()
	end

	local function ensureToastSchedule()
		if toastSchedule ~= nil then
			return
		end
		toastSchedule = toast_schedule.new({
			now = function()
				return toastTime
			end,
			onDismiss = function(entry: any, reason: string)
				-- every retirement is traceable, including the queued one dropped at
				-- the cap (disposition F3) — nothing vanishes without a reason code.
				-- REPLACEMENT IS ITS OWN VERB (ui-designer review R2-F1 ruling): a
				-- superseded toast emits exactly one `supersede`; `dismiss` means the
				-- surface actually retired on its own terms (timeout/capacity/manual/
				-- preempt). One causal moment, one event.
				emitFeedback({
					type = if reason == "supersede" then "supersede" else "dismiss",
					path = `/__toast__/Items/[{entry.id}]`,
					reason = if reason == "supersede" then nil else reason,
					context = { key = entry.key, priority = entry.priority, context = entry.data.context },
				})
			end,
		})
	end

	local function ensureToastLayer(options: any)
		if toastLayer ~= nil then
			return
		end
		-- the first toast fixes the layer's edge and transition for its lifetime:
		-- one layer, one stacking direction, so a burst cannot make the strip hop
		-- from one edge to the other mid-read
		toastPosition = if options.position == "bottom" then "bottom" else "top"
		toastTransition = options.transition
			or {
				-- a toast comes from the edge it docks to, and fades with it
				enter = if toastPosition == "bottom" then "slide-up" else "slide-down",
				fade = true,
			}
		local sc = core:scope("present-toast")
		-- scope-owned, so a layer that comes and goes twenty times leaves the core's
		-- counters exactly where it found them
		local items = sc:own(core:signal({}))
		local rows = blueprintLib.ForEach({
			id = "Items",
			items = items,
			key = function(entry: any): string
				return tostring(entry.id)
			end,
			row = toastRowBlueprint,
			transition = toastTransition,
		})
		local children: { any } = {}
		if toastPosition == "bottom" then
			-- the strip is pushed to the far edge; nothing else in the layer paints,
			-- so the spacer costs one transparent frame
			table.insert(children, blueprintLib.Spacer({ id = "Push", height = { type = "fill", weight = 1 } }))
		end
		table.insert(children, rows)
		-- padding lifts the strip off the surface edges (director, sensory-feedback
		-- round: rows
		-- hugging the exact top edge collided with content pinned there, and
		-- edge-to-edge rows read as a debug bar rather than a toast)
		local bp = blueprintLib.Screen({
			id = "__toast__",
			align = "center",
			gap = "s",
			padding = "m",
			children = children,
		})
		local surfaceRef: any = nil
		local coordinator = transitionsLib.new({
			core = core,
			clock = motionClock,
			metrics = metricsNow,
			feedback = function(event: any)
				event.surface = surfaceRef
				emitFeedback(event)
			end,
		})
		local root = mountLib.mount(core, bp, {
			scope = sc:child("mount"),
			transitions = coordinator,
			-- the toast strip carries CONSUMER-authored rows, so a
			-- `UI.sensoryFeedback` declared on one has the same seam a screen's does
			feedback = function(event: any)
				event.surface = surfaceRef
				emitFeedback(event)
			end,
		})
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
		controller.initialRender()
		coordinator.bindController(controller)
		if controller.setDisplayOrder ~= nil then
			-- above every base screen, below every modal (ui-designer §6.3)
			controller.setDisplayOrder(SURFACE_LAYER.toast)
		end
		toastLayer = {
			scope = sc,
			controller = controller,
			root = root,
			items = items,
			coordinator = coordinator,
			itemsNode = nodeAt(root.node, "/__toast__/Items"),
		}
		surfaceRef = toastLayer
	end

	syncToastLayer = function()
		if toastLayer == nil then
			return
		end
		toastLayer.items:set(toastSchedule.visible())
		toastLayer.controller.refresh()
		-- the refresh is what CREATED the new row's handles; re-assert the enter's
		-- seeded values onto them so a toast never paints one frame at rest
		toastLayer.coordinator.flush()
		-- the layer retires when nothing is showing, nothing is waiting, and no row
		-- is still playing its exit — a retiring row is still mounted, so the
		-- mounted child count is the honest test
		local itemsNode = toastLayer.itemsNode
		local pending = if itemsNode ~= nil then #itemsNode.children else 0
		if toastSchedule.isEmpty() and pending == 0 then
			disposeToastLayer()
		end
	end

	function self.presentToast(blueprint: any, opts: ToastOpts?)
		assert(
			type(blueprint) == "table" and type(blueprint.class) == "string",
			"presenter.presentToast takes a blueprint (UI.*) and an options table"
		)
		specGuard.assertKnownKeys("presenter.presentToast", opts, TOAST_OPTS_KEYS, "opts")
		local options: any = opts or {}
		ensureToastSchedule()
		ensureToastLayer(options)
		local id = toastSchedule.push({
			key = options.key,
			priority = options.priority,
			duration = options.duration,
			readFloor = options.readFloor,
			data = { blueprint = blueprint, context = options.context },
		})
		syncToastLayer()
		return {
			id = id,
			dismiss = function()
				if toastSchedule == nil then
					return false
				end
				local removed = toastSchedule.dismiss(id, "manual")
				syncToastLayer()
				return removed
			end,
		}
	end

	function self.toastCounts()
		if toastSchedule == nil then
			return { visible = 0, queued = 0, sequence = 0 }
		end
		return toastSchedule.counts()
	end

	-- ONE FRAME OF PRESENTER TIME. Steps the motion clock (every surface and toast
	-- transition rides it) and advances the toast schedule. The client binds this
	-- to RunService.PreRender; the headless suite passes a scripted `dt`, which is
	-- what makes every rule above deterministic. Nothing animates and no deferred
	-- teardown completes without it — including the exit cap, which is measured in
	-- CLOCK time, not wall time.
	local tickBody: (dt: number?) -> ()
	function self.tick(dt: number?)
		profile.span("tick", function()
			tickBody(dt)
		end)
	end

	function tickBody(dt: number?)
		local step = dt
		local t = nowFn()
		if step == nil then
			step = t - lastTick
		end
		lastTick = t
		motionClock:step(step)
		-- POINTER DWELL (the large-text round). Guarded, so a presentation with nothing engaged
		-- does no per-frame work at all — the plan's own bound on this feature, and
		-- the reason the disclosure is static rather than a per-label reveal.
		if disclosureDwell ~= nil then
			local d = disclosureDwell
			d.remaining -= math.max(step :: number, 0)
			if d.remaining <= 0 then
				disclosureDwell = nil
				-- RE-ASK AT EXPIRY, never present the hover-time snapshot
				-- (architecture review F-2): the label may have stopped
				-- truncating (a re-solve made room) or changed its bound value
				-- while the dwell counted — the plate must answer for the label
				-- as it IS, or not at all. The facts come from the live solve,
				-- which is the same rule the seams and refresh already follow.
				local targetPath, fullText = disclosureTargetIn(d.owner, d.sourcePath)
				if targetPath ~= nil and fullText ~= nil then
					presentDisclosure(d.owner, targetPath, fullText, "pointer")
				end
			end
		end
		-- ...and the HELP dwell rides the same tick (D3a), guarded the same way: a
		-- presentation with nothing hovered does no per-frame work at all
		helpPlate.tick(math.max(step :: number, 0))
		-- a LIVE plate keeps its clamp (found live 2026-08-04: an async text
		-- measure grew the plate past the screen edge after the one-shot clamp)
		if disclosurePlate ~= nil then
			clampDisclosure()
		end
		-- ...and an ANCHORED surface keeps its placement for the same reason (D1):
		-- its own size is a solve output whose text measure can land after mount, so
		-- a surface placed once at mount would be placed from the placeholder
		-- height. Same tick, same rule, no second clock.
		anchoredSurfaces.sync()
		-- the auto reveal's whole cycle rides this one tick (2026-08-04): an
		-- idle presenter pays a timer-gated rescan, a live strip one signal write
		stepReveal(math.max(step :: number, 0))
		if toastSchedule ~= nil then
			toastTime += math.max(step, 0)
			toastSchedule.update()
			syncToastLayer()
		end
		-- ...and the callout queue's own clock, so a read floor can elapse and a
		-- more urgent coach mark take its turn (D3b). Costs nothing while empty.
		calloutQueue.update(math.max(step, 0))
		-- registered frame work (Step 5): per-frame consumers that are not motion
		-- values — an autoscrolling list's `stepAutoscroll`, a fixture's per-frame
		-- probe — ride the SAME tick so "one clock, one driver" stays true. Hooks
		-- run after the motion step: they read this frame's settled values.
		for _, hook in table.clone(tickHooks) do
			-- quarantined (the reactive-runtime verifier): a throwing hook must not starve its
			-- siblings or escape into the render thread's PreRender handler
			pcall(hook, step :: number)
		end
	end

	--[[ ONE CLOCK, ONE DRIVER — CLAIMED HERE, WHERE BOTH DRIVERS CAN SEE IT
		(R5 review §3b-3).

		`motion_driver.bind` has asserted "this presenter is already bound" since
		it shipped, but the assert reads a table private to that module, so it can
		only ever see ITS OWN binds. `client.host` connects its own PreRender and
		registered nowhere, which made `host.new()` followed by
		`motion_driver.bind(h.presenter)` legal and silent — and it is not a
		cosmetic collision: measured, two drivers advance this clock twice per
		frame, so a one-second timer is fully elapsed after half a second.

		The claim lives on the PRESENTER because the presenter is the thing being
		driven and the only object both drivers already hold. It is engine-free,
		so the rule has a headless test for the first time; `motion_driver` keeps
		its own connection table for its own unbind and takes the claim on top.

		`name` is what the error prints, so it must be the thing an author would
		grep for (`"client.host"`, `"motion_driver.bind"`). The returned function
		releases the claim; a driver that releases and re-claims is fine, which is
		what a surface torn down and stood back up does. ]]
	local frameDriver: string? = nil
	function self.claimFrameDriver(name: string): () -> ()
		if frameDriver ~= nil then
			error(
				`Facet presenter: this presenter is already driven by '{frameDriver}', and '{name}' `
					.. `tried to drive it too. ONE CLOCK, ONE DRIVER: two frame sources advance the motion `
					.. `clock twice per frame, so every duration on it elapses at double speed and nothing `
					.. `reports it. Drive it once — 'client.host' already connects a PreRender that ticks `
					.. `and refreshes, and per-frame work of your own belongs on presenter.onTick.`,
				0
			)
		end
		frameDriver = name
		return function()
			if frameDriver == name then
				frameDriver = nil
			end
		end
	end

	-- who is driving this presenter's frame, or nil. The honest read behind the
	-- claim above, for a diagnostic or a spec.
	function self.frameDriver(): string?
		return frameDriver
	end

	-- register per-frame work on the presenter's clock; returns an unsubscribe.
	-- The one sanctioned frame source outside the motion clock itself — a second
	-- RunService connection in a consumer is the bug class this prevents.
	function self.onTick(fn: (dt: number) -> ()): () -> ()
		table.insert(tickHooks, fn)
		return function()
			local index = table.find(tickHooks, fn)
			if index ~= nil then
				table.remove(tickHooks, index)
			end
		end
	end

	function self.depth(): number
		return #stack
	end

	return self
end

return presenter
