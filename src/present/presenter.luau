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
--   used to be (docs/plans/swiftui-parity-round2.md §Phase 1). The verb lives
--   here because the clock, the controller scopes and `refresh` all do.

local mountLib = require("../mount")
local blueprintLib = require("../blueprint")
local chrome_slots = require("../tokens/chrome_slots")
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
local profile = require("../core/profile")
-- the metric authority (ADR-0019 §2). The modal-dismissal spec pins the
-- forgiveness ring to space.l and the target ring to the effective hit floor;
-- both are now THEME values read from the live `themeMetrics` fact, so a theme
-- with roomier spacing gets a proportionally roomier dismiss ring for free.
local themeSnapshot = require("../themes/snapshot")
local specGuard = require("../spec_guard")

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
	-- engine-selection bridge (native-substrate NS-A12): presentModal-only
	-- opt-in that mirrors LuauUI's logical focus to GuiService.SelectedObject
	-- while the modal owns UI input. Ignored on present() (passive/gameplay
	-- surfaces keep SelectedObject nil — NS-A11). Experiment until the
	-- physical-gamepad row (NS-P1) closes; reversible by omitting the opt.
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
	-- groups), else the flat ring (ADR-0013 WP-1). `false` = force the flat ring,
	-- ignoring both (a legacy flat-list consumer opting out of auto-grouping).
	navigationGroups: ({ focus_graph.NavigationGroup } | (rootNode: any) -> { focus_graph.NavigationGroup } | boolean)?,
	-- presentModal only (ADR-0013 WP-2): while this modal is on top, a pointer/
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

-- CLOSED OPTS (constitution §4; ARCH-1). This is the widest opts table in the
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
local zoneAContains = modalZones.zoneAContains
local modalInZoneA = modalZones.modalInZoneA
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
	-- (4) no-op
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
-- surface mirrors LuauUI focus onto `GuiService.SelectedObject`: the engine then
-- fires the selected `GuiButton`'s own `Activated` for the same key press that
-- IAS delivered as Activate. That must still be ONE activation (roadmap Step 8,
-- DK-9), so a cross-source pair inside ACTIVATE_ECHO_WINDOW collapses.
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
			-- ARCH-4). Recording the collapsing signal instead would roll the
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
	-- ONE ACTIVATE PER PRESS ACROSS THE TWO PATHS (roadmap Step 8, DK-9). A
	-- keyboard press on a control the engine also considers SELECTED can arrive
	-- twice: once as the IAS `Activate` action, and once as the native
	-- `GuiButton.Activated` the engine-selection bridge makes reachable. Keyed by
	-- path across the whole presenter (paths are surface-prefixed), and collapsing
	-- only a CROSS-SOURCE pair inside the window: two presses of the same key, or
	-- two real taps, are two presses and must both count — the renderer's own
	-- detector-echo guard draws the same line for the same reason.
	local activateEcho: { [string]: { at: number, source: string } } = {}

	-- ===== the semantic feedback seam (ADR-0022 Decision 7; row SF-F1) =======
	-- ONE bus per presenter. `presenter.onFeedback` is the primary seam (every
	-- surface, one subscription — a game maps events to sound/haptics in one
	-- place); `handle.onFeedback` is the same bus filtered to that surface.
	-- LuauUI plays nothing.
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
	-- `LuauUI.newPresenter`)
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

	-- FULL-VALUE DISCLOSURE (LTN-4), forward-declared: the plate's machinery needs
	-- the mount/render collaborators built further down, while the three places
	-- that ENGAGE or DISENGAGE it — the focus observer just below, the surface tap
	-- handler, and `dismiss` — all sit above it. Reassigned once, never rebound.
	local syncDisclosureFocus: (path: string?) -> () = function() end
	local dismissDisclosure: (reason: string) -> () = function() end

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
		-- THE RING IS A NAVIGATION ANSWER, NOT A FOCUS ANSWER (DB-3(b)): a
		-- pointer/touch-driven focus move tracks focus without drawing it.
		local ringVisible = graph.focusVisible:get() ~= false
		for _, handle in stack do
			local rootPath = "/" .. (handle.blueprint.id or "")
			local owns = path ~= nil and string.sub(path, 1, #rootPath) == rootPath
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
		-- FOCUS ENTER IS ONE OF THE THREE ENGAGEMENTS (LTN-4). It rides this
		-- function rather than its own observer for the reason round 7 recorded: a
		-- second copy of the "does this surface own input" decision is a copy that
		-- will not get the next rule added to the original. A surface that is not
		-- painting a focus ring is not presenting a focus-driven plate either.
		syncDisclosureFocus(path)
		-- recorded LAST, so the armed-aim seed above reads the PREVIOUS call's focus
		prevFocusPath = path
	end
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

	-- cross-surface z: a monotonic layer per presented surface (base first, each
	-- later surface above). Deterministic and creation-ordered; the synthesized
	-- scrim sits just BELOW its owner (spec §2.2).
	local displayLayer = 0

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
				self.dismiss(candidate)
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
			controller.setDisplayOrder(owner.displayOrder - 50)
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

	function self.syncPopupCatcher()
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
	function self.topPopupCatcherPath(): string?
		return if popupCatcher ~= nil then popupCatcher.path else nil
	end

	local function syncScrim()
		local topEx = currentExclusive()
		if topEx == nil then
			disposeScrim()
			self.syncPopupCatcher() -- no exclusive surface: a base popup may want a catcher
			return
		end
		local mode = topEx.scrimMode
		if scrim ~= nil and scrim.owner == topEx and scrim.mode == mode then
			self.syncPopupCatcher() -- an exclusive surface suppresses the popup catcher
			return
		end
		disposeScrim()
		scrim = mountScrim(topEx, mode)
		self.syncPopupCatcher()
	end
	function self.topScrimPath(): string?
		return if scrim ~= nil then scrim.path else nil
	end

	--[[ ===== FULL-VALUE DISCLOSURE (LTN-4) ====================================

		A `UI.Text{ disclose = true }` that TRUNCATED owes the reader the whole
		string. The screen declares the debt; the presenter pays it, here, with one
		STATIC plate — no marquee, no travel, no per-frame work (LTN-2 chose the
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
	local DISCLOSURE_SCHEMA = "luauui-disclosure-dump/1"

	local disclosurePlate: any = nil -- { scope, controller, root, owner, sourcePath, source, text }
	local disclosureDwell: any = nil -- { owner, sourcePath, text, remaining }

	-- the safe box a plate may occupy, in WINDOW space: the viewport less the
	-- per-edge MAXIMUM of the two inset facts (the `deviceSafeContent` rule). A
	-- tooltip under a notch or behind the home indicator is unreadable, and this
	-- surface is decoration rather than content only in its z-order.
	local function safeBox(): { x: number, y: number, w: number, h: number }
		local vp = env:get("viewportRect"):get()
		local core_ = env:get("coreSafeInsets"):get()
		local device = env:get("deviceSafeInsets"):get()
		local function edge(name: string): number
			local a = if type(core_) == "table" then tonumber(core_[name]) or 0 else 0
			local b = if type(device) == "table" then tonumber(device[name]) or 0 else 0
			return math.max(a, b)
		end
		local x = (if type(vp) == "table" then tonumber(vp.x) or 0 else 0) + edge("left")
		local y = (if type(vp) == "table" then tonumber(vp.y) or 0 else 0) + edge("top")
		local w = (if type(vp) == "table" then tonumber(vp.w) or 0 else 0) - edge("left") - edge("right")
		local h = (if type(vp) == "table" then tonumber(vp.h) or 0 else 0) - edge("top") - edge("bottom")
		return { x = x, y = y, w = math.max(0, w), h = math.max(0, h) }
	end

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
		local node = nodeAt(handle.root.node, path)
		if node == nil then
			return nil, nil
		end
		-- A HIDDEN CANDIDATE DISCLOSES NOTHING (architecture review F-1). A
		-- losing ViewThatFits candidate keeps its mount, its rects and its
		-- textFacts — only visibility knows it does not paint. Without this
		-- gate, focusing a row whose RICH candidate lost raised a plate for a
		-- string that is nowhere on screen.
		local hidden: { string } = {}
		if ctrl.hiddenRoots ~= nil then
			for root in ctrl.hiddenRoots() do
				table.insert(hidden, root)
			end
		end
		local function isHiddenPath(p: string): boolean
			for _, root in hidden do
				if isPathPrefix(root, p) then
					return true
				end
			end
			return false
		end
		local foundPath: string? = nil
		local foundText: string? = nil
		local function walk(n: any)
			if foundPath ~= nil or isHiddenPath(n.path) then
				return
			end
			-- class-AGNOSTIC on purpose (LT-G1): any node whose measured text
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

	dismissDisclosure = function(_reason: string)
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
		local box = safeBox()
		local gap = themeSnapshot.resolveNumber(metricsNow(), "xs") or 4
		local x = math.clamp(srcRect.x, box.x, math.max(box.x, box.x + box.w - plateRect.w))
		-- below the label by preference; above it when there is no room below,
		-- which is where a label near the bottom edge always sits
		local below = srcRect.y + srcRect.h + gap
		local y = if below + plateRect.h > box.y + box.h then srcRect.y - gap - plateRect.h else below
		y = math.clamp(y, box.y, math.max(box.y, box.y + box.h - plateRect.h))
		if plate.ox:get() ~= x or plate.oy:get() ~= y then
			plate.ox:set(x)
			plate.oy:set(y)
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

	syncDisclosureFocus = function(path: string?)
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
		-- ...AND A POINTER-DRIVEN FOCUS MOVE IS NOT A FOCUS ENGAGEMENT (DB-3(b),
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

	--[[ ENGAGEMENT SEAMS (adapter-driven; constitution §2 "a leading underscore
		means engine-adapter seam"). Pointer hover and touch long-press are engine
		facts — MouseEnter/MouseLeave and the gesture arbiter's `longPress` — and
		the presenter is engine-free, so the client hands them over here rather than
		this module reaching for either. Focus needs no seam: the presenter owns the
		focus graph and reads it directly (above).

		`nil` means DISENGAGED (the pointer left everything / the press released).
		Both are idempotent: a hover that re-reports the same node neither restarts
		the dwell nor re-mounts the plate. ]]
	function self._discloseHover(path: string?)
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

	function self._discloseLongPress(path: string?)
		local owner = handleOwning(path)
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

	--[[ ════════════════════ THE AUTO REVEAL (marquee) ════════════════════

		Director ruling 2026-08-04, superseding LTN-2's "no marquee shipped" for
		surfaces that DECLARE it: a `UI.Text{ reveal = "auto" }` that TRUNCATED
		auto-scrolls its whole value. The plan's rung-4 constraint list binds:

		· QUIET DELAY — the string rests in the engine's own ellipsis for
		  REVEAL_PAUSE before anything moves (and between cycles).
		· READING DIRECTION — the strip slides LEFT, revealing the tail (the
		  framework has no RTL fact today; when one lands, the travel sign reads
		  it here and nowhere else).
		· GRAPHEME BOUNDARIES — the whole string travels as ONE strip at its
		  natural one-line width; it is never re-segmented, and the resting paint
		  is the engine's own ellipsis. (The strip's edges crop glyphs in motion
		  exactly as any scrolling region does — the constraint forbids BREAKING
		  the string, not clipping a moving edge.)
		· PAUSE AT ENDS — the tail holds for REVEAL_PAUSE before the return leg,
		  and the return ends back in the ellipsis rest.
		· STATIC ALTERNATIVE — a reveal node is ALSO a disclosure source (the
		  renderer wires the same engagement zones), so hover dwell / long-press
		  raise the LTN-4 plate; a live plate for this label OUTRANKS the travel.
		· REDUCED MOTION — travel never starts, and a mid-flight flip retires the
		  strip on the next tick. The plate remains the full-value path.
		· AT MOST ONE — one strip across every surface; `self.movingText()` feeds
		  `text_audit.movingText`, whose allowance stays 1.
		· NO PER-LABEL FRAME LOOPS — the presenter's ONE tick drives the cycle;
		  an idle presenter pays a timer-gated rescan (REVEAL_RESCAN), never a
		  per-frame tree walk, and surfaces without the declaration are skipped
		  by the `hasReveal` stamp entirely.

		HOW THE STRIP PAINTS. Presenter-private, exactly like the disclosure
		plate: a `clipChildren` Window fixed at the source label's own rect, an
		anchored Full label inside it at the string's natural one-line width (the
		SOLVE's own `naturalWidth` fact — never a second opinion), and the travel
		is one anchor-offset signal. While the strip covers the source, the
		source's own paint is HELD through `controller.setPaintHeld` — the solve,
		the rects and the truncation facts are untouched, so the target stays
		"truncated" and the audit stays honest. The strip exists only while
		travelling; at rest the source paints its ellipsis and the moving-text
		count is zero. ]]
	local REVEAL_ROOT = "__reveal__"
	local REVEAL_WINDOW = `/{REVEAL_ROOT}/Layer/Window`
	local REVEAL_LABEL = `{REVEAL_WINDOW}/Inner/Full`
	local REVEAL_SCHEMA = "luauui-reveal-dump/1"
	-- the quiet delay before travel, and both end pauses. Longer than the plate's
	-- 0.45 dwell on purpose: nothing here was asked for, so the reader gets a
	-- moment with the stable ellipsis before the line starts moving.
	local REVEAL_PAUSE = 1.2
	-- idle rescan cadence — well under REVEAL_PAUSE, so found-to-moving latency
	-- is invisible, and far from per-frame work
	local REVEAL_RESCAN = 0.5
	-- travel speed as a GLYPH rate, so raising the text preference slows the
	-- px/s with the bigger glyphs instead of racing them: glyphs/s times the
	-- average glyph width (text_metrics' 0.62 em) times the PAINTED size
	-- (facts.size already carries the preference offset)
	local REVEAL_GLYPHS_PER_S = 3.0
	local REVEAL_GLYPH_EM = 0.62
	-- the strip is measured by the same headless metrics the solve used; the
	-- engine can paint a hair wider (measured live at ~1px on the heavy face),
	-- so the strip carries this much slack past the natural width
	local REVEAL_SLACK = 2

	local revealState: any = nil -- { owner, sourcePath, text, phase, wait, travel, overlay? }
	local revealScan = 0

	-- the first DECLARED, TRUNCATED reveal text under this surface, in document
	-- order — the same walk shape as disclosureTargetIn, against the same facts
	local function revealTargetIn(handle: any): (string?, string?)
		local ctrl = handle.controller
		if ctrl == nil or ctrl.textAt == nil then
			return nil, nil
		end
		local hidden: { string } = {}
		if ctrl.hiddenRoots ~= nil then
			for root in ctrl.hiddenRoots() do
				table.insert(hidden, root)
			end
		end
		local function isHiddenPath(p: string): boolean
			for _, root in hidden do
				if isPathPrefix(root, p) then
					return true
				end
			end
			return false
		end
		local foundPath: string? = nil
		local foundText: string? = nil
		local function walk(n: any)
			if foundPath ~= nil or isHiddenPath(n.path) then
				return
			end
			if n.props ~= nil and n.props.reveal ~= nil then
				local facts = ctrl.textAt(n.path)
				if facts ~= nil and facts.truncated == true and facts.reveal == true then
					foundPath = n.path
					foundText = tostring(n.props.text)
					return
				end
			end
			for _, child in n.children or {} do
				walk(child)
			end
		end
		walk(handle.root.node)
		return foundPath, foundText
	end

	-- unmount the strip and give the source its paint back (cycle state kept)
	local function retireRevealStrip()
		local st = revealState
		if st == nil or st.overlay == nil then
			return
		end
		local overlay = st.overlay
		st.overlay = nil
		if st.owner.controller.setPaintHeld ~= nil then
			st.owner.controller.setPaintHeld(st.sourcePath, false)
		end
		overlay.controller.dispose()
		overlay.scope:dispose()
	end

	local function retireReveal()
		retireRevealStrip()
		revealState = nil
		revealScan = 0
	end

	-- mount the strip over the source rect; returns false when the geometry or
	-- facts are not real yet (the cycle rests and asks again)
	local function mountRevealStrip(): boolean
		local st = revealState
		local ctrl = st.owner.controller
		local srcRect = if ctrl.screenRectOf ~= nil
			then ctrl.screenRectOf(st.sourcePath)
			else ctrl.rectOf(st.sourcePath)
		local facts = ctrl.textAt(st.sourcePath)
		if type(srcRect) ~= "table" or facts == nil or tonumber(facts.naturalWidth) == nil then
			return false
		end
		local labelW = (tonumber(facts.naturalWidth) :: number) + REVEAL_SLACK
		if labelW <= srcRect.w then
			return false -- nothing hidden to reveal (a stale verdict; the verify path retires it)
		end
		-- facts.size is the MEASURED size, which already carries the preference
		-- offset (LTN-1: the offset applies once, at the measure seam) — the strip
		-- declares the pre-offset size so the engine lands on the same paint
		local offsetFact = env:get("preferredTextOffset"):get()
		local offset = if type(offsetFact) == "number" then math.clamp(offsetFact, 0, 32) else 0
		local paintSize = math.max(1, (tonumber(facts.size) or 16) - offset)
		local sc = core:scope("present-reveal")
		local wx = sc:own(core:signal(srcRect.x))
		local wy = sc:own(core:signal(srcRect.y))
		local offx = sc:own(core:signal(-st.travel))
		local bp = blueprintLib.Screen({
			id = REVEAL_ROOT,
			children = {
				blueprintLib.Anchor({
					id = "Layer",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						blueprintLib.VStack({
							id = "Window",
							anchor = "topLeft",
							offsetX = wx,
							offsetY = wy,
							width = { type = "fixed", px = srcRect.w },
							height = { type = "fixed", px = srcRect.h },
							clipChildren = true,
							children = {
								blueprintLib.Anchor({
									id = "Inner",
									width = { type = "fill", weight = 1 },
									height = { type = "fill", weight = 1 },
									children = {
										blueprintLib.Text({
											id = "Full",
											text = st.text,
											textSize = paintSize,
											lineLimit = 1,
											anchor = "topLeft",
											offsetX = offx,
											width = { type = "fixed", px = labelW },
										}),
									},
								}),
							},
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp, { scope = sc:child("mount") })
		local controller = renderer.attach(core, root, env, adapter, {
			-- window space, exactly like the plate: the anchor offsets are the
			-- coordinates `screenRectOf` answers in
			rootPolicy = "edgeToEdge",
		})
		controller.initialRender()
		if controller.setDisplayOrder ~= nil then
			-- above its owner's content, below a disclosure plate (+25): the
			-- static answer always reads over the moving one
			controller.setDisplayOrder(st.owner.displayOrder + 24)
		end
		if ctrl.setPaintHeld ~= nil then
			ctrl.setPaintHeld(st.sourcePath, true)
		end
		st.overlay = {
			scope = sc,
			controller = controller,
			wx = wx,
			wy = wy,
			offx = offx,
			windowW = srcRect.w,
			windowH = srcRect.h,
			srcX = srcRect.x,
			srcY = srcRect.y,
			labelW = labelW,
		}
		return true
	end

	-- the strip FOLLOWS the live rects and facts (the clampDisclosure lesson):
	-- a moved source re-places the window; a resized source or a late engine
	-- measure re-mounts the strip at the new numbers
	local function followRevealGeometry(facts: any)
		local st = revealState
		local overlay = st.overlay
		local ctrl = st.owner.controller
		local srcRect = if ctrl.screenRectOf ~= nil
			then ctrl.screenRectOf(st.sourcePath)
			else ctrl.rectOf(st.sourcePath)
		if type(srcRect) ~= "table" then
			retireReveal()
			return
		end
		local wantLabelW = (tonumber(facts.naturalWidth) or 0) + REVEAL_SLACK
		if
			math.abs(srcRect.w - overlay.windowW) > 0.5
			or math.abs(srcRect.h - overlay.windowH) > 0.5
			or math.abs(wantLabelW - overlay.labelW) > 1
		then
			retireRevealStrip()
			if not mountRevealStrip() then
				st.phase, st.wait, st.travel = "rest", REVEAL_PAUSE, 0
			end
			return
		end
		if srcRect.x ~= overlay.srcX or srcRect.y ~= overlay.srcY then
			overlay.srcX, overlay.srcY = srcRect.x, srcRect.y
			overlay.wx:set(srcRect.x)
			overlay.wy:set(srcRect.y)
			overlay.controller.refresh()
		end
	end

	local function stepReveal(dt: number)
		-- reduced motion: the whole engine is inert (the plate is the path)
		if env:get("reducedMotion"):get() == true then
			if revealState ~= nil then
				retireReveal()
			end
			return
		end
		if revealState == nil then
			revealScan -= dt
			if revealScan > 0 then
				return
			end
			revealScan = REVEAL_RESCAN
			-- topmost surface first, same order the outside-tap policy resolves;
			-- surfaces without the declaration cost one boolean read
			for i = #stack, 1, -1 do
				local h = stack[i]
				if h.hasReveal == true then
					local path, text = revealTargetIn(h)
					if path ~= nil then
						revealState = {
							owner = h,
							sourcePath = path,
							text = text,
							phase = "rest",
							wait = REVEAL_PAUSE,
							travel = 0,
						}
						break
					end
				end
			end
			return
		end
		local st = revealState
		-- verify the debt is still real: same owner presented, same string, still
		-- truncated. A re-solve that made room, a swapped text, a dismissed
		-- surface — all retire on the next tick, releasing the held paint.
		local facts = if table.find(stack, st.owner) ~= nil then st.owner.controller.textAt(st.sourcePath) else nil
		if facts == nil or facts.truncated ~= true or facts.reveal ~= true or tostring(facts.text) ~= st.text then
			retireReveal()
			return
		end
		-- ...and still PAINTED (found live 2026-08-04, the F-1 class): a losing
		-- arrangement/ViewThatFits candidate keeps its mount, its rects AND its
		-- truncation facts — only visibility knows it does not draw. A preference
		-- drop flipped the recap's composition to the rich form and the strip
		-- kept travelling over the hidden reduced line. Hiddenness is re-read
		-- every tick exactly as the facts are.
		local ctrl = st.owner.controller
		if ctrl.hiddenRoots ~= nil then
			for root in ctrl.hiddenRoots() do
				if isPathPrefix(root, st.sourcePath) then
					retireReveal()
					return
				end
			end
		end
		-- the reader's own static ask outranks the ambient travel
		if plateShows(st.sourcePath) then
			retireRevealStrip()
			st.phase, st.wait, st.travel = "rest", REVEAL_PAUSE, 0
			return
		end
		if st.phase == "rest" then
			st.wait -= dt
			if st.wait <= 0 then
				if mountRevealStrip() then
					st.phase = "out"
				else
					st.wait = REVEAL_PAUSE
				end
			end
			return
		end
		if st.overlay == nil then
			-- a strip phase with no strip (adapter refused a mount): rest again
			st.phase, st.wait, st.travel = "rest", REVEAL_PAUSE, 0
			return
		end
		followRevealGeometry(facts)
		if revealState ~= st or st.overlay == nil then
			return
		end
		local speed = REVEAL_GLYPHS_PER_S * REVEAL_GLYPH_EM * (tonumber(facts.size) or 16)
		local distance = math.max(0, st.overlay.labelW - st.overlay.windowW)
		if st.phase == "out" then
			st.travel = math.min(distance, st.travel + speed * dt)
			st.overlay.offx:set(-st.travel)
			st.overlay.controller.refresh()
			if st.travel >= distance then
				st.phase, st.wait = "end", REVEAL_PAUSE
			end
		elseif st.phase == "end" then
			st.wait -= dt
			if st.wait <= 0 then
				st.phase = "back"
			end
		elseif st.phase == "back" then
			st.travel = math.max(0, st.travel - speed * dt)
			st.overlay.offx:set(-st.travel)
			st.overlay.controller.refresh()
			if st.travel <= 0 then
				retireRevealStrip()
				st.phase, st.wait = "rest", REVEAL_PAUSE
			end
		end
	end

	--[[ reveal() -> the live strip, in the shipped dump shape (constitution §6):
		frozen, deterministic, safe when nothing is up. `present` means the strip
		is mounted (the source's paint is held); a resting cycle reports its
		target with `present = false`, because at rest the screen shows exactly
		what an undeclared label would. ]]
	function self.reveal(): any
		local st = revealState
		if st == nil or st.overlay == nil then
			return table.freeze({
				schema = REVEAL_SCHEMA,
				present = false,
				sourcePath = if st ~= nil then st.sourcePath else nil,
				phase = if st ~= nil then st.phase else nil,
				travel = 0,
				distance = 0,
			})
		end
		return table.freeze({
			schema = REVEAL_SCHEMA,
			present = true,
			path = REVEAL_WINDOW,
			labelPath = REVEAL_LABEL,
			sourcePath = st.sourcePath,
			phase = st.phase,
			travel = st.travel,
			distance = math.max(0, st.overlay.labelW - st.overlay.windowW),
			text = st.text,
		})
	end

	-- the moving-text count `text_audit.movingText` audits (allowance 1): the
	-- strip counts the whole time it is mounted — conservative on purpose
	function self.movingText(): number
		return if revealState ~= nil and revealState.overlay ~= nil then 1 else 0
	end

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
			error(`LuauUI presenter: unknown cancelPolicy '{tostring(cancelPolicy)}'. Valid: dismiss, none.`, 0)
		end
		-- ...and so do the other two string enums (F-15). They used to be compared
		-- by equality and passed through raw, which is the exact failure the rule
		-- above refuses: `responder = "Passive"` silently presented an ENGAGED
		-- surface that sank nothing it was supposed to sink, and `scrim = "None"`
		-- silently DIMMED the screen. Absent stays legal — each has a default.
		local responderOpt = if opts ~= nil then opts.responder else nil
		if responderOpt ~= nil and responderOpt ~= "passive" then
			error(
				`LuauUI presenter: unknown responder '{tostring(responderOpt)}'. Valid: passive (omit for engaged).`,
				0
			)
		end
		local scrimOpt = if opts ~= nil then opts.scrim else nil
		if scrimOpt ~= nil and scrimOpt ~= "scrim" and scrimOpt ~= "none" then
			error(`LuauUI presenter: unknown scrim '{tostring(scrimOpt)}'. Valid: scrim, none.`, 0)
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
				`LuauUI presenter: keyboardNavigation must be a boolean (got {typeof(keyboardNavOpt)}); `
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
				`LuauUI presenter: traversalWrap must be a boolean (got {typeof(traversalWrap)}); `
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
		local initialFocus = if opts ~= nil then opts.initialFocus else nil
		if initialFocus == nil and kind == "screen" and (opts and opts.responder) == "passive" then
			initialFocus = "none"
		end
		if initialFocus ~= nil and type(initialFocus) ~= "string" and type(initialFocus) ~= "table" then
			error(
				`LuauUI presenter: initialFocus must be "first", "none", a node id, or \{ id = "…" } `
					.. `(got {typeof(initialFocus)}).`,
				0
			)
		end
		if type(initialFocus) == "table" then
			local id = (initialFocus :: any).id
			if type(id) ~= "string" then
				error(`LuauUI presenter: initialFocus \{ id = … } needs a string id (got {typeof(id)}).`, 0)
			end
			-- the table form is the ESCAPE HATCH from the reserved words below, so
			-- it is remembered as "definitely an id" rather than collapsed to a
			-- bare string that would be read as a keyword again
			initialFocus = { id = id }
		end

		-- engine-selection bridge: opt-in AND modal/exclusive-only. It is the only
		-- way `GuiService.SelectedObject` is ever set, and therefore the only way a
		-- native `Activated` can echo a key press (NS-A11) — but the echo guard in
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
			-- engine-selection bridge (native-substrate NS-A12, corrections §11):
			-- OPT-IN and modal/exclusive-only. Passive/gameplay surfaces never
			-- set it, so GuiService.SelectedObject stays nil for them (NS-A11).
			-- LuauUI's logical focus graph remains the sole authority; the
			-- bridge is a render output that clears on teardown. Physical-pad
			-- non-interference proof is ledger row NS-P1; until it closes this
			-- stays an experiment, not a contract.
			engineSelectionBridge = selectionBridged,
			-- FULL-VALUE DISCLOSURE engagement (LTN-4): the live adapter's
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
				-- A TAP RETIRES THE DISCLOSURE PLATE (LTN-4 "tap elsewhere"). Every
				-- tap, including one on the disclosed label itself: the plate answers
				-- "what does this say", and a player who has moved on to pressing
				-- something has stopped asking.
				dismissDisclosure("tap")
				-- outside-tap policy is owned by the topmost EXCLUSIVE surface: a
				-- modal (ADR-0013 WP-2) OR an engaged-from-passive surface (ADR-0014).
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
				-- finger never asked for (DB-3(b)); the next Navigate restores it.
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
		-- EVERY REFRESH (device round 1, DB-4 — the crown bug). It used to be a
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
				c.bundle.bindPresent(self.presentModal, self.dismiss)
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
		feedGeometry(controller.rectOf) -- feed the first solved geometry

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
		if controller.onSolved ~= nil then
			scope:own(controller.onSolved(function()
				feedGeometry(controller.rectOf)
			end))
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
				-- grid: derive 2D navigation from tree structure (ADR-0013 WP-1)
				navigationGroupsFn = layoutGroups
				navigationGroups = layoutGroups(root.node)
			end
		end
		-- RE-DISCOVER THE CONTRIBUTIONS FROM THE LIVE TREE (device round 1, DB-4).
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
		-- it exactly as written (ledger row TD-7). `navigationGroups = false` is
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
		local navigateH = if navigationGroups ~= nil then context.createAction("NavigateH", "Direction1D") else nil
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
		-- A SUSPENSION MUST RESTORE WHAT IT TOOK (architecture review ARCH-10). The
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
		do
			local function scan(n: any)
				if hasDisclose and hasReveal then
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
				end
				-- a structural region can mount ANYTHING later (the
				-- late-contributions class), so its presence keeps the walk —
				-- the optimization must never become a false negative
				if n.class == "When" or n.class == "ForEach" then
					hasDisclose = true
					hasReveal = true
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
			-- ONE ACTIVATE PER PRESS, ACROSS THE TWO PATHS (DK-9). The shared echo
			-- table + injected clock live on the presenter; the handle carries them
			-- so the module-level dispatchActivate can reach them.
			activateEcho = activateEcho,
			now = nowFn,
			contributions = contributions,
			-- modal outside-tap dismiss (ADR-0013 WP-2): default true; a modal
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
			-- the live re-discovery of this surface's input contributions (DB-4);
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
				displayLayer += 100
				return (if kind == "modal" then SURFACE_LAYER.modal else SURFACE_LAYER.base) + displayLayer
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

			SAFE AFTER DISPOSE (ledger row TD-10). A debug overlay outliving the
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
					table.freeze({ name = group.name, axis = group.axis, order = table.freeze(order) })
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
			-- A DISMISSED SURFACE BINDS NOTHING (architecture review ARCH-6). Input
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
		-- one that declares none keeps the pre-Step-8 key set (roadmap Step 8,
		-- DK-10/DK-11).
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
						-- document order inside its trap (ledger row TD-12). Ranked
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
			-- comes back even if a tap had put it away (DB-3(b))
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
			-- back even if a tap had put it away (DB-3(b))
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
			dispatchActivate(handle, graph.focused:get(), meta, "action")
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

		-- STEP-5 DRAG INTEGRATION (ADR-0022 Decision 5): every surface's registry
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
			if string.sub(path, 1, #rootPath) == rootPath then
				return handle
			end
		end
		return nil
	end

	function self.present(blueprint: any, opts: PresentOpts?)
		specGuard.assertKnownKeys("presenter.present", opts, PRESENT_OPTS_KEYS, "opts")
		return makeHandle(blueprint, opts, "screen")
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

	function self.dismiss(handle: any)
		local index = table.find(stack, handle)
		if index == nil then
			return
		end
		table.remove(stack, index)
		-- REDTEAM FIX (item 3, MAJOR; final-review-findings.md). `displayLayer`
		-- (the "cross-surface z" band-offset counter above, `makeHandle`'s
		-- `displayLayer += 100`) never went back down — a long-lived session
		-- that opens and closes 100 present/dismiss cycles pushes every FUTURE
		-- base screen's own `displayOrder` past the toast band (`SURFACE_LAYER
		-- .toast`, +10000 above base), and 300 cycles pushes it past the modal
		-- band too, silently reordering surfaces that were never touched.
		-- Reset to its base the moment the stack goes empty — the one point a
		-- fresh session and a long-lived one are indistinguishable (nothing is
		-- presented, so no live `handle.displayOrder` depends on the counter's
		-- current value), per the reviewer's own suggestion.
		-- REDTEAM FIX (item 3, MAJOR; final-review-findings.md). `displayLayer`
		-- (the "cross-surface z" band-offset counter above, `makeHandle`'s
		-- `displayLayer += 100`) never went back down — a long-lived session
		-- that opens and closes 100 present/dismiss cycles pushes every FUTURE
		-- base screen's own `displayOrder` past the toast band (`SURFACE_LAYER
		-- .toast`, +10000 above base), and 300 cycles pushes it past the modal
		-- band too, silently reordering surfaces that were never touched.
		-- Reset to its base the moment the stack goes empty — the one point a
		-- fresh session and a long-lived one are indistinguishable (nothing is
		-- presented, so no live `handle.displayOrder` depends on the counter's
		-- current value), per the reviewer's own suggestion.
		if #stack == 0 then
			displayLayer = 0
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
		-- of `stack` above, so the revalidation resolves it (LTN-4)
		revalidateDisclosure()
		-- ...and the reveal strip goes with its owner SYNCHRONOUSLY, exactly as
		-- the plate does — a dismissed presenter may never tick again, and a
		-- strip that waited for one would leak its overlay and the held paint
		if revealState ~= nil and revealState.owner == handle then
			retireReveal()
		end
		-- the dismissal is a fact the moment it is decided, not when the pixels
		-- finish moving (SF-F1's causal frame)
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

	function self.back()
		for i = #stack, 1, -1 do
			if stack[i].kind == "modal" then
				self.dismiss(stack[i])
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
	function self.refresh()
		profile.span("present", refreshBody)
	end

	function refreshBody()
		for _, handle in stack do
			handle.controller.refresh()
			-- FIRST: re-discover the input contributions from the tree this refresh
			-- just re-rendered (device round 1, DB-4). Before the focus map below,
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
			-- every contribution's syncGeometry — see makeHandle.feedGeometry)
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
		-- `setFocusPath(current)` in makeHandle). There is now one.
		self.syncFocusVisuals()
		-- ...and a disclosure plate is checked against the tree that just
		-- re-rendered: its source node may be gone, or the re-solve may have made
		-- room for the label (LTN-4)
		revalidateDisclosure()
	end

	-- ===== withAnimation (docs/plans/swiftui-parity-round2.md §Phase 1) =======
	--
	-- `presenter.withAnimation("container", function() open:set(true) end)` — the
	-- layout lands exactly and instantly as it always did, and every node whose box
	-- MOVED is painted travelling from where it used to be, over one spring.
	--
	-- It is a PRESENTER method rather than a `UI.` modifier or a free function on
	-- `motion`, because it needs all three of the things only the presenter has:
	-- the motion clock it builds, the controller scopes that own the records, and
	-- `refresh` itself. The motion is DECORATIVE — the instant layout already
	-- carries every fact and the travel is pure continuity — which is what makes
	-- "no flight under reduced motion" the right policy rather than information
	-- deletion.
	--
	-- THE NESTING PROBE, built ONCE per presenter and reused. `Core` exposes no
	-- `inTransaction()` and its `txDepth` is private, so the nesting refusal cannot
	-- ask: it writes a scratch signal as the first act inside its own transaction
	-- and reads whether the observer has fired by the time that transaction
	-- returns. Observers fire post-flush, so "fired" means depth was zero.
	local animationProbe = core:signal(0)
	local animationProbeFired = false
	-- session-lifetime, like the presenter itself (it has no dispose); kept on self
	-- so the ownership is visible rather than implicit
	self._animationProbeWatcher = core:observe(animationProbe, function()
		animationProbeFired = true
	end)

	--[[ RE-ENTRANCY, AND WHY IT IS ITS OWN REFUSAL RAISED FIRST (red-team R1,
		2026-08-13). Arming is presenter-wide and the disarm is a plain "off", not a
		counter: a nested call arms the very controllers the OUTER call armed and then
		disarms them on its way out, so by the time the outer call reaches its own
		armed `self.refresh()` the session is already gone. Measured before this
		flag: the outer's rect landed exactly (`rect.y` 200) while its paint never
		travelled (`presentedPosition.y` 200 where the flight should have started it
		at 100) and `animationRecordCount()` was 0 — the outer animation silently
		deleted by the inner one. Under a `pcall` around the inner call — which is
		exactly the shape `src/controls/row_actions.luau` uses for `action.onAction`
		— not even the inner refusal is visible, so the whole thing reads as "the
		animation just doesn't work".

		So the check runs BEFORE anything is armed, refreshed or mutated, and carries
		its own message: the old nesting refusal below is about an outer core
		TRANSACTION, which is a different situation with a different fix, and naming
		the wrong cause sent a reader looking for a transaction that does not exist. ]]
	local inWithAnimation = false

	function self.withAnimation(class: any, fn: () -> ())
		if inWithAnimation then
			error(
				"LuauUI presenter.withAnimation: called from inside another withAnimation call. "
					.. "Arming is presenter-wide and disarming is not counted, so the inner call would "
					.. "disarm the controllers the outer call armed and the OUTER animation would "
					.. "silently not happen (its layout still lands exactly; only the flight is lost). "
					.. "Nesting buys nothing anyway: one call already animates every consequence of "
					.. "everything its `fn` changes, over one spring. Make the change inside the outer "
					.. "`fn` directly. Nothing has been mutated by this call.",
				0
			)
		end
		-- ONE DIAL: an unknown name AND an inline params table are both refused by
		-- the class registry, with its did-you-mean and its registered list. A motion
		-- class is a NAME here exactly as it is everywhere else in the framework.
		motionClasses.resolve(class)
		if type(fn) ~= "function" then
			error(`LuauUI presenter.withAnimation(class, fn): fn must be a function, got {typeof(fn)}`, 0)
		end
		-- THE UNARMED PRE-DRAIN, and it is load-bearing. `controller.refresh` opens
		-- by draining the WHOLE dirty queue, so without this the armed commit would
		-- also commit everything dirtied since the last frame — and a DISCRETE change
		-- that landed two milliseconds earlier (a network event, a timer, an async
		-- image resizing a label) would animate at its FULL delta. Usually a no-op
		-- solve, because nothing is dirty.
		self.refresh()
		-- REDUCED MOTION INSTALLS NO RECORDS AT ALL — an explicit branch, not
		-- "install and clear". Settle fires synchronously inside `setTarget` under
		-- reduced motion, so a clear that arrives after it would leave the node
		-- painted at the full stale offset forever. `fn` still runs, the transaction
		-- still commits, the layout is still exact; there is simply no flight.
		local armed: { any } = {}
		if not motionClock:isReduced() then
			-- one session per CALL. The spring is built lazily by whichever commit
			-- finds a root, so a call that moves nothing costs no motion value.
			local session = {
				newSpring = function()
					return motionClock:spring(1, class)
				end,
			}
			-- presenter-wide, because `refresh` carries no surface — safe precisely
			-- BECAUSE of the pre-drain: with the queue already empty, another surface
			-- has no pending changes to animate by accident
			for _, handle in stack do
				handle.controller.armAnimation(session)
				table.insert(armed, handle.controller)
			end
		end
		animationProbeFired = false
		inWithAnimation = true
		local ok, err = pcall(function()
			core:transaction(function()
				animationProbe:set(animationProbe:get() + 1)
				fn()
			end)
			-- THE ARMED COMMIT: exactly `fn`'s consequences, and the only commit in
			-- the framework that ever installs records. Skipped on a throw — a
			-- half-applied `fn` is committed by the next ordinary refresh, unarmed.
			self.refresh()
		end)
		-- the finally, on every path including a throw: a throwing `fn` must not
		-- latch an animation class on for the rest of the session, and the
		-- re-entrancy flag must not latch either or the presenter refuses forever
		inWithAnimation = false
		for _, ctrl in armed do
			ctrl.disarmAnimation()
		end
		if not ok then
			error(err, 0)
		end
		--[[ THE PROBE DID NOT FIRE, AND IT CANNOT TELL YOU WHY (red-team R2,
			2026-08-13). It fires from an observer, and observers fire post-flush, so
			"did not fire" means only "nothing flushed". TWO different situations
			produce that:

			  · an outer core TRANSACTION is open — `commit` is deferred to its close;
			  · a core COMMIT is in flight — `src/core/imperative.luau`'s `commit`
			    opens `if committing then return end`, so a transaction opened from an
			    observer, effect, memo settle or any handler dispatched DURING a commit
			    never flushes either. Reproduced from a plain `core:observe` handler.

			The probe cannot separate them, so the message names both rather than
			asserting the one that used to be assumed — it named a transaction that,
			in the commit case, is not open at all.

			AND THE HAZARD, because this refusal arrives LATE: `fn` already ran, inside
			the transaction above, so its mutation has landed. A caller that catches
			this (`pcall(action.onAction)` in src/controls/row_actions.luau is exactly
			that shape) sees "no animation" and must NOT retry the mutation — retrying
			applies it twice. ]]
		if not animationProbeFired then
			error(
				"LuauUI presenter.withAnimation: nothing flushed, so it could not force its own "
					.. "commit and no records were installed — the change landed instantly with no "
					.. "flight. Either an outer core transaction is still open, or this ran during a "
					.. "core commit (from an observer, an effect, or a settle/handler dispatched by "
					.. "one), where a nested transaction cannot flush either. WARNING: `fn` HAS "
					.. "already been applied — do not retry it, or the mutation lands twice. Call "
					.. "presenter.withAnimation(class, fn) from outside the transaction/commit "
					.. "instead, e.g. deferred to the next frame.",
				0
			)
		end
	end

	-- DIAGNOSTICS (design §Proof), not features. `animationRecordCount` is how many
	-- paths currently carry a `withAnimation` record — the proof that recording is
	-- roots-only and that settle cleans the channel; `commitCount` is how many
	-- commits the presented surfaces have made — the proof that each call forces
	-- its own, which a count of animation SETS would not have caught.
	function self.animationRecordCount(): number
		local n = 0
		for _, handle in stack do
			if handle.controller.animationRecordCount ~= nil then
				n += handle.controller.animationRecordCount()
			end
		end
		return n
	end

	function self.commitCount(): number
		local n = 0
		for _, handle in stack do
			if handle.controller.stats ~= nil then
				n += handle.controller.stats().solves
			end
		end
		return n
	end

	-- ===== TOASTS (ADR-0022 Decision 4; rows SF-T1..T3) =======================
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
	-- been shown is still shown, for the same time (SF-T3).
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
		-- padding lifts the strip off the surface edges (director SFH-3: rows
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
		-- POINTER DWELL (LTN-4). Guarded, so a presentation with nothing engaged
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
		-- a LIVE plate keeps its clamp (found live 2026-08-04: an async text
		-- measure grew the plate past the screen edge after the one-shot clamp)
		if disclosurePlate ~= nil then
			clampDisclosure()
		end
		-- the auto reveal's whole cycle rides this one tick (2026-08-04): an
		-- idle presenter pays a timer-gated rescan, a live strip one signal write
		stepReveal(math.max(step :: number, 0))
		if toastSchedule ~= nil then
			toastTime += math.max(step, 0)
			toastSchedule.update()
			syncToastLayer()
		end
		-- registered frame work (Step 5): per-frame consumers that are not motion
		-- values — an autoscrolling list's `stepAutoscroll`, a fixture's per-frame
		-- probe — ride the SAME tick so "one clock, one driver" stays true. Hooks
		-- run after the motion step: they read this frame's settled values.
		for _, hook in table.clone(tickHooks) do
			-- quarantined (verifier RR-12): a throwing hook must not starve its
			-- siblings or escape into the render thread's PreRender handler
			pcall(hook, step :: number)
		end
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
