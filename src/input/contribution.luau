--!strict
-- Input contribution seam (ui_todo §0; ADR-0013). A COMPOSITE control advertises
-- its four-input story to the presenter by attaching an input-contribution
-- bundle to its blueprint ROOT node. The presenter walks the mounted tree,
-- discovers the bundles, and auto-composes navigation groups, Activate dispatch,
-- grab-mode intercept, focus-move reporting, geometry feed, keep-visible offset,
-- and action-system binding — so MOUNTING a control yields its whole input
-- story with NO consumer wiring (the audit's fix, artifacts/input-adaptation-
-- audit/). Every consumer-passed present() opt still overrides its auto
-- counterpart per-opt (back-compat).
--
-- The bundle rides the blueprint's INTERNAL metadata channel (`bp.meta`), not
-- the public prop bag (Milestone 0, investment 1). Public props are validated
-- against src/blueprint_schema.luau and an unknown key is a hard error, so
-- framework metadata must not travel there: a reserved magic prop name would
-- either have to be whitelisted into every class's public schema (teaching
-- authors a key they must never set) or be exempted by a special case that
-- re-opens the exact hole strict validation closes. mount.luau copies `meta`
-- verbatim onto the mounted node, and nothing in the layout, render, or dump
-- paths reads it.
--
-- Bundle shape (every field optional):
--   { focusGroups: (rootNode) -> NavigationGroup[],
--     handleActivate: (path, meta) -> boolean,
--     navigateIntercept: (direction) -> boolean,
--     focusMoved: (path) -> (),
--     syncGeometry: (rectOf, rootNode) -> (),
--     keepVisibleOffset: Readable<number>?,
--     bindActionSystem: (actionSystem) -> (),
--     bindController: (controller) -> (),
--     bindFocusGraph: (focusGraph) -> (),
--     bindMotion: (motionClock, now?) -> (),
--     adjustTargets: (rootNode) -> { [path]: true },
--     handleAdjust: (path, direction) -> boolean }
--
-- adjustTargets/handleAdjust (matrix §B-Table; UI-PARADIGM-001): a control
-- advertises the focusable paths that respond to the Adjust verb (grip resize,
-- value steppers). The presenter binds the Adjust keys DYNAMICALLY — only while
-- the focused path is one of these targets — so a bare screen never shadows
-- gameplay arrow/bumper keys while focus sits off-target (the ADR-0013 hazard).
-- direction is -1 (decrement) or +1 (increment). handleAdjust returns true when
-- it consumed the adjust; longest-path-prefix wins, like handleActivate.
-- opts.onAdjust still overrides both per-opt (back-compat).
--
-- ===== transient-popup parity (matrix §B PopupButton; input-paradigms) =======
-- A non-modal control that opens a transient surface (an open PopupButton, a
-- menu) is a `UI.When` inside a PLAIN present() screen — it never engages the
-- modal machinery, so it inherited three parity GAPs (matrix §B PopupButton).
-- Three OPTIONAL fields close them WITHOUT making the control a modal:
--
--   handleCancel: (focusedPath) -> boolean
--     Cancel (gamepad ButtonB) is offered to the focused/longest-prefix
--     contribution BEFORE the presenter's modal-dismiss / passive-resign / no-op
--     branches (first true consumes). An open popup returns true (closes); when
--     it has nothing to cancel it returns false and Cancel falls through to the
--     surface's own behavior — so a modal that CONTAINS such a control still
--     dismisses on a second ButtonB (ordering documented in presenter.luau).
--
--   outsideDismiss: { active: Readable<boolean>, dismiss: () -> (), consume: boolean? }
--     While `active`, a tap on a rendered node OUTSIDE the contribution's subtree
--     dismisses it (non-destructive), and the presenter synthesizes a transparent
--     full-viewport catcher beneath the screen so a tap on EMPTY space also
--     dismisses (Zone-A geometry over the contribution's solved rects, mirroring
--     the modal two-zone model, ADR-0014). A real modal above the screen
--     suppresses the catcher.
--
--     `consume` (default true / omitted) SWALLOWS the outside tap after
--     dismissing — PopupButton's own "outside means dismiss, never clickthrough"
--     semantic, appropriate for a control that behaves like a lightweight modal.
--     `consume = false` (row-actions Task 7) dismisses WITHOUT swallowing: the
--     tap still falls through to whatever it actually landed on afterward — the
--     round-7 Zone-A lesson (docs/plans/row-actions.md) that a dismissal must
--     never eat a click meant for another control (tapping row B's button while
--     row A's tray is open must close A AND still activate B).
--
--   transientScope: { active: Readable<boolean>, rootPath: string? }
--     While `active`, focus is TRAPPED within `rootPath`'s subtree (Navigate can
--     not escape) via the focus graph's own trap/restore machinery; on
--     deactivation focus RESTORES to the pre-activation focused path (the
--     trigger). `rootPath` defaults to the contribution's mounted path (the
--     control root), which keeps the trigger as the scope's entry so focus does
--     not jump into the open rows on open.

local contribution = {}

export type Bundle = {
	focusGroups: ((rootNode: any) -> { any })?,
	handleActivate: ((path: string, meta: any?) -> boolean)?,
	navigateIntercept: ((direction: string) -> boolean)?,
	focusMoved: ((path: string) -> ())?,
	syncGeometry: ((rectOf: (string) -> any, rootNode: any?) -> ())?,
	keepVisibleOffset: any?, -- Readable<number>
	bindActionSystem: ((actionSystem: any) -> ())?,
	-- bindController (B-VAL2): hands the control the render controller so it can
	-- reach NATIVE adapter capabilities the renderer owns — specifically
	-- `attachDragDetector`, the UIDragDetector host required by
	-- roblox-native-audit-corrections §1. Called at present time, and again on a
	-- structural sync, so a control that re-attaches stays wired. A control MUST
	-- still work when the capability is absent (the corrections require a
	-- fallback), so this is an enhancement seam, not a dependency.
	bindController: ((controller: any) -> ())?,
	-- bindFocusGraph: hands the control the screen's FOCUS GRAPH, for the one
	-- case a control has to MOVE focus rather than merely follow it — the data
	-- under a focused row changed and the control's own policy says the ring
	-- belongs somewhere else now (`newVirtualList.focusPolicy = "index"`), or
	-- content about to unmount still holds focus. Bound alongside the action
	-- system and the controller, once per discovered bundle, so a control that a
	-- keyed region mounts late is wired the same way. It is the CANONICAL route
	-- (constitution §13): a control must never be handed the graph by its
	-- consumer, because then the consumer owns half the focus story. Absent, the
	-- control degrades to logical focus only — an enhancement seam, never a
	-- dependency.
	bindFocusGraph: ((focusGraph: any) -> ())?,
	--[[ OPEN THIS SUBTREE'S EXPAND (wave REVEAL). Declared by `UI.Region` on a
		region that collapses, and read by `presenter.expand(path)` — the seam a
		screen's overflow census uses to open the SAME plate the region's own
		affordance opens, rather than building a second one beside it. Returns the
		presentation that opened, or nil when the region is at its richest form and
		has nothing more to show. ]]
	expandOpen: (() -> string?)?,
	--[[ WHERE THE DISCLOSURE WALK SHOULD START, when the focused node is not where
		the truncated text lives (2026-08-18).

		The plate's rule is "the first truncated, disclosed Text at or under the
		FOCUSED path", and it is right for every control whose label is inside its
		own focusable. It is structurally dead for a TABLE: the focus stop is the
		row's `Hit` — a full-bleed Button with no children, because a Button's
		content may hold no focusable and a rating cell is five of them — while the
		disclosed value is `Row/Cells/Cell-<id>/Value`, a SIBLING. The audit
		measured a positive control passing (a `disclose` Text inside a focused
		Button raises the plate) and the identical declaration in a table row
		raising nothing, on the one combination — ten-foot — where there is no hover
		and no long press to fall back to.

		WHY A SEAM AND NOT A WIDER WALK. "Walk the focused node's PARENT subtree"
		would raise a plate for any disclosed sibling of any focusable in the
		framework — a truncated caption beside a button, another row's cell inside a
		shared wrapper — and the thing that knows which siblings belong to the
		focused thing is the control. So the control answers, once, for a path it
		recognises, and returns nil for every path it does not: a Table maps a row's
		`Hit` to that row, and a heading's `Column` to that heading, and says nothing
		about anything else.

		THE ANSWER IS A SCOPE, NOT A TARGET. The presenter still runs its own walk
		inside it, so the hidden-candidate gate, the truncation test, the disclose
		declaration and the document order are all unchanged — a control cannot
		nominate an untruncated label, and cannot skip the visibility rules. ]]
	discloseScope: ((path: string) -> string?)?,
	-- bindMotion (row-actions Task 4): hands the control the presenter's own
	-- motion clock (`self.motionClock`, ADR-0022 Decision 1) — the one every
	-- surface transition, toast schedule, and drag flight already rides —
	-- the same way bindActionSystem/bindController/bindFocusGraph hand over
	-- what a composite cannot construct for itself. Called once per
	-- discovered bundle, at present time, before any caller-driven input
	-- reaches the control. Absent (a bare `mountLib.mount` in a unit test,
	-- which never runs a presenter's bindContribution walk at all) is a real,
	-- supported degradation: a control that wants motion MUST also work with
	-- none, falling back to an instant write — exactly what a headless test
	-- with no presenter needs.
	--
	-- second argument (row-actions Task 5, ADDITIVE like bindFocusGraph's own
	-- second argument above — every control written before it ignores the
	-- extra parameter and is unchanged): the SAME `now` function the clock
	-- itself was built from (`presenterOpts.now or os.clock`, presenter.luau
	-- `nowFn`) — the one legal time source `src/input/drag_velocity.luau` may
	-- read (its own contract: "this module never reads os.clock... a
	-- scripted clock replays a flick exactly"). A control threading gesture
	-- samples through `drag_velocity` needs a timestamp for every pointer
	-- move, and no existing seam handed one over; reusing the clock's own
	-- `now` rather than inventing a second, potentially-divergent time axis
	-- is what "the same source" means here.
	bindMotion: ((motionClock: any, now: (() -> number)?) -> ())?,
	-- bindPresent (row-actions redteam item 2, BLOCKER: "the action menu
	-- inflates the row" fix). Hands the control the presenter's OWN
	-- `presentModal`/`dismiss` functions — the identical two an app-level
	-- caller already reaches via `presenter.presentModal(...)` / `presenter.
	-- dismiss(handle)` — for the one case a control needs a surface that is
	-- NEVER a descendant of its own mounted tree: a floating menu/popover
	-- anchored to a live rect, which must contribute ZERO to any ancestor's
	-- measured box (an ordinary child, however positioned, always can).
	-- Same shape and same degradation contract as bindMotion/bindController/
	-- bindFocusGraph above: called once per discovered bundle, at present
	-- time; absent (a bare mount in a unit test, no presenter) is a real,
	-- supported degradation — a control offering this MUST also work with
	-- neither function ever arriving (its "open a floating surface" seam
	-- simply has nothing to call).
	--
	-- Deliberately `presentModal`, never the plain `present` a base screen
	-- uses: `presenter.luau`'s own `contextPriority` comment documents that
	-- two `kind == "screen"` surfaces share one priority band and would
	-- double-deliver Navigate/Activate/Cancel if both sank — exactly the
	-- failure a composite-owned floating surface would hit, so only the
	-- collision-free primitive (`presentModal`, which stacks strictly above
	-- any base screen and gets a focus TRAP + RESTORE for free from
	-- `focus_graph.luau`'s own `pushScope`) is ever handed over.
	-- REDTEAM FIX (item 8, MINOR; final-review-findings.md — documentation).
	-- A surface opened through `presentModal` is FULLY EXCLUSIVE (`kind =
	-- "modal"`), not a lightweight overlay: it participates in
	-- `presenter.exclusiveSurfaceActive`'s own fan-out the identical way any
	-- other modal does. A game observing that signal to gate its own input
	-- (RascalRally's `FacetSponsor/init.luau`: `core:observe(presenter.
	-- exclusiveSurfaceActive, ...)` -> `inputBridge:setModalBlocked(...)`)
	-- sees gameplay input BLOCKED for as long as ANY control using this seam
	-- (e.g. row_actions' own action menu) holds a presented handle open —
	-- consumers of `bindPresent` must expect and accept full modal semantics,
	-- not a popover-weight exemption.
	-- THIRD ARGUMENT (navigation-and-menus D2), ADDITIVE exactly as
	-- bindFocusGraph's and bindMotion's second arguments are — every control
	-- written before it ignores the extra parameter and is unchanged.
	-- `presentAnchored(panel, opts)` is the D1 seam: a surface placed against a
	-- SOURCE VIEW'S screen rect rather than a parent corner. A floating menu
	-- anchored to its trigger, and a submenu anchored to its parent ROW, are
	-- exactly what it is for, and a control cannot construct one for itself for
	-- the same reason it cannot construct `presentModal` — it has no line to the
	-- presenter. Same degradation contract as the two beside it: absent (a bare
	-- mount in a unit test, no presenter) is real and supported.
	-- `presentCallout(spec)` / `releaseCallout(id, reason?)` are the D3b queue:
	-- "at most one coach mark on screen, a queue not a pile" is a rule about the
	-- WHOLE application, so it cannot live inside one control instance. Same
	-- degradation contract again: absent is real and supported.
	bindPresent: ((
		presentModal: (blueprint: any, opts: any?) -> any,
		dismiss: (handle: any) -> (),
		presentAnchored: ((panel: any, opts: any?) -> any)?,
		presentCallout: ((spec: any) -> number)?,
		releaseCallout: ((id: number, reason: string?) -> boolean)?
	) -> ())?,
	--[[ WHICH MOUNTED SUBTREES OWN A CONTEXT GESTURE (navigation-and-menus D2).
		Returns the paths whose subtree has claimed the pointer's secondary button
		and touch long-press as a MENU trigger.

		It exists to settle one ownership question in code rather than in prose.
		Touch long-press is claimed today by the full-value disclosure plate
		(`presenter._discloseLongPress`, the only touch route to a truncated
		label's full value — `UI.Text{ reveal = "auto" }` is opt-in, `UI.Text`-only,
		one-at-a-time and absent entirely under reduced motion, and a `Toggle`
		label or a disclosing `Table` cell has no marquee even in principle). So
		the plate KEEPS the gesture, and this is the carve-out: inside a subtree
		that has declared a menu trigger, the long press means the MENU, and the
		plate yields rather than both firing off one unsunk press. Everywhere
		else — which is everywhere today — the accessibility route is untouched. ]]
	contextTriggers: (() -> { string })?,
	adjustTargets: ((rootNode: any) -> { [string]: boolean })?,
	handleAdjust: ((path: string, direction: number) -> boolean)?,
	-- WHICH ARROWS THIS CONTROL CONSUMES (roadmap Step 8). "horizontal" (what every
	-- shipped adjust target declares — Slider, Stepper, Rating) means Left/Right +
	-- DPadLeft/DPadRight become Adjust while one of this bundle's `adjustTargets`
	-- holds focus; "vertical" means Up/Down + DPadUp/DPadDown do. Comma/Period and
	-- L1/R1 are axis-independent and are bound for a declared target either way.
	-- Declared rather than inferred, because only the control knows which
	-- direction its value runs in.
	--
	-- CHOOSE THE AXIS THE SCREEN DOES NOT NAVIGATE ON. The other axis keeps
	-- navigating, but which axes navigate depends on the screen: a GROUPED screen
	-- navigates both, so either choice leaves the ring a way out on the arrows; a
	-- FLAT screen navigates only vertically, so "vertical" there takes the only
	-- arrows that could move focus and Tab becomes the only way off the control.
	-- That is the author's call to make knowingly, which is why this is an option
	-- and not an inference.
	--
	-- Omitting it is a real choice too: an undeclared target keeps the pre-0.9 key
	-- set (Comma/Period/L1/R1 always, plus the horizontal arrows only on a flat
	-- screen where nothing else wants them). `newTable` omits it deliberately — its
	-- resizable headers are navigation stops and adjust targets at once, and it
	-- resolves the contention with a mode instead.
	adjustAxis: string?, -- "horizontal" (default) | "vertical"
	-- CONSUME Tab / Shift+Tab BEFORE the ring moves (roadmap Step 8). `direction`
	-- is +1 (Tab) or -1 (Shift+Tab). Return true to keep focus where it is; false
	-- or nil to let the presenter traverse. It exists for the one control that
	-- must finish something first: a TextInput being edited commits through its
	-- own validation path and then returns false so focus advances — it must
	-- never type a tab character, and never advance out of an unfinished edit.
	-- Longest-path-prefix wins, like handleActivate.
	handleTraverse: ((path: string, direction: number) -> boolean)?,
	handleCancel: ((focusedPath: string?) -> boolean)?,
	outsideDismiss: { active: any, dismiss: () -> (), consume: boolean? }?, -- active: Readable<boolean>
	transientScope: { active: any, rootPath: string? }?, -- active: Readable<boolean>
}

-- the reserved metadata key the bundle rides under bp.meta
local PROP = "inputContribution"
contribution.PROP = PROP

-- attach a bundle to a control's root blueprint, returning a NEW frozen
-- blueprint (blueprints are immutable). Controls call this once, on their
-- returned root, so the attachment is uniform and the magic prop name lives in
-- exactly one place.
function contribution.attach(rootBlueprint: any, bundle: Bundle): any
	-- an illegal axis is refused at construction, naming the legal set
	-- (constitution §4): silently defaulting to horizontal would leave a vertical
	-- control's arrows navigating with nothing to say about it
	local axis = (bundle :: any).adjustAxis
	if axis ~= nil and axis ~= "horizontal" and axis ~= "vertical" then
		error(
			`Facet contribution.attach: adjustAxis '{tostring(axis)}' is not an axis. Valid: horizontal, vertical.`,
			0
		)
	end
	local meta = if rootBlueprint.meta ~= nil then table.clone(rootBlueprint.meta) else {}
	meta[PROP] = bundle
	return table.freeze({
		class = rootBlueprint.class,
		id = rootBlueprint.id,
		props = rootBlueprint.props,
		children = rootBlueprint.children,
		meta = table.freeze(meta),
	}) :: any
end

-- read the bundle off a MOUNTED node (nil when the node carries none)
function contribution.read(node: any): Bundle?
	local meta = node.meta
	if type(meta) ~= "table" then
		return nil
	end
	-- type-guard: the reserved key is a convention, not enforced at build —
	-- a consumer smuggling a non-table under it must read as "no
	-- contribution", not fault the presenter (architecture verifier F1)
	local value = meta[PROP]
	if type(value) ~= "table" then
		return nil
	end
	return value
end

return contribution
