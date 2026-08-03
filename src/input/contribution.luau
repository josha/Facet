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
--   outsideDismiss: { active: Readable<boolean>, dismiss: () -> () }
--     While `active`, a tap on a rendered node OUTSIDE the contribution's subtree
--     dismisses it (non-destructive) and is swallowed, and the presenter
--     synthesizes a transparent full-viewport catcher beneath the screen so a tap
--     on EMPTY space also dismisses (Zone-A geometry over the contribution's
--     solved rects, mirroring the modal two-zone model, ADR-0014). A real modal
--     above the screen suppresses the catcher.
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
	adjustTargets: ((rootNode: any) -> { [string]: boolean })?,
	handleAdjust: ((path: string, direction: number) -> boolean)?,
	handleCancel: ((focusedPath: string?) -> boolean)?,
	outsideDismiss: { active: any, dismiss: () -> () }?, -- active: Readable<boolean>
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
