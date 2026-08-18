--!strict
-- RowActions: a swipeable action tray around an arbitrary row (spec:
-- docs/plans/row-actions.md, docs/plans/row-actions-implementation.md Tasks
-- 3-4). The spec/blueprint contract and the lazy tray structure shipped in
-- Task 3; Task 4 adds spring-driven reveal motion (offset AND proportional
-- tray-button growth) on top of the same seams, falling back to Task 3's
-- INSTANT write whenever no presenter motion clock is available (a bare
-- mount in a unit test). Drag/gesture input (mouse, touch, keyboard, gamepad
-- — Tasks 5-8) and the coordinator (Task 7) build on the seams declared here
-- without touching this file's structure.
--
--[[ WHERE THE REST OF IT LIVES (split 2026-08-14). This file is the ONE ENGINE
	and nothing else. Five siblings hold the periphery, and every one of them
	passed the same test before it left: does it read or write a MUTABLE upvalue
	of `buildEngine`? None does — each takes build-time facts and reactive nodes
	this closure creates once and never reassigns.

	  row_actions_spec.luau        the ActionSpec authoring contract (validation),
	                               `Edge`/`ActionSpec`, patternEscape/isPathPrefix/
	                               trayId. Re-exported here under its own names.
	  row_actions_coordinator.luau `newRowActionsCoordinator`: one row open per
	                               list surface. Re-exported as `newCoordinator`.
	  row_actions_reorder.luau     `composeWithReorder`: which of swipe/reorder
	                               owns one raw capture. Re-exported by that name.
	  row_actions_metrics.luau     every live pixel amount the band is made of —
	                               theme metrics, the per-action naturals, and
	                               `bandWidth`, the distance the row TRAVELS.
	  row_actions_trays.luau       the tray blueprints both modes share, every
	                               drawn quantity spent at the reveal fraction so
	                               the drawn band is exactly `|offset|`.
	  row_actions_root.luau        the standalone/Table row node: root Anchor,
	                               trays, the sliding Content, the Hit Grip and
	                               the edit minus, in paint order. Hosted mode
	                               builds none of it.

	WHY: this file crossed 200,000 characters, which is the cap on ASSIGNING
	`Script.Source` — the path Rojo live-sync, `execute_luau` and every plugin
	take. Over it, the module silently stops syncing into an open Studio session
	and a live check tests the built place instead of your edit. It was measured
	happening: the running showcase held this file at 219,701 chars with none of
	that day's markers. `docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`,
	`tools/check_source_size.py`.

	WHAT WAS NOT SPLIT, and must not be: `buildEngine`. Its ~65 nested functions
	share ~60 mutable upvalues (`spring`, `controller`, `drag`, `committed`,
	`commitLatched`, `commitEpoch`, `menuHandle`, `rootPath`, `restorePending`,
	…) deliberately — see THE ONE ENGINE below. Threading a state record through
	them is a rewrite of code four device rounds hardened, not an extraction. ]]
--
-- STRUCTURE. The root is a `UI.Anchor` — the same "overlay without joining
-- stack flow" shape `newTable` uses for its own drag guides
-- (table.luau: "root: an Anchor so drag guides overlay the content without
-- joining any stack flow") — holding up to three anchor children: a lazily
-- mounted leading tray, a lazily mounted trailing tray, and the wrapped
-- `content`, which slides horizontally over both by `offsetX`. A row with NO
-- actions on EITHER edge returns `content` completely UNWRAPPED (no Anchor,
-- no extra node at all) — the true "inert passthrough" the perf directive
-- asks for.
--
-- THE SLIDE MECHANISM. `offsetX` is a reactive, arrange-only prop
-- (src/blueprint_schema.luau BOX.offsetX: `dirty = { "arrange" }`) honoured
-- ONLY by an `anchor`-kind parent (src/layout/solver.luau's `anchor` arrange
-- branch reads `child.offsetX`; the sibling `zstack` branch does not — a
-- ZStack child's offsetX is silently inert). `virtual_list.luau`'s row
-- (`anchor = "topLeft", offsetY = offsetY`) and `table.luau`'s resize/drop
-- guides are the shipped precedent for binding a live signal straight to it:
-- an `offsetX`/`offsetY` write re-arranges ONE node, never re-measures the
-- tree. Every write — the fallback instant snap, Task 4's spring, Task 5's
-- live drag sample — goes through the ONE seam `applySlide(px)` below.
--
-- THE MOTION SEAM (Task 4). A composite has no direct line to the
-- presenter's motion clock — `bindActionSystem`/`bindController`/
-- `bindFocusGraph` are the shipped precedent for a presenter handing a
-- control something it cannot construct for itself, all delivered the same
-- way: an optional field on the `contribution.attach` bundle, called once per
-- discovered bundle from the presenter's `bindContribution` (src/present/
-- presenter.luau). `bindMotion` follows that exact shape. With a clock bound,
-- `_open`/`_close`/`_settleTo` aim ONE persistent spring (`motionClock:
-- spring(0, "object")` — the same class name a drag flight uses,
-- drag_registry.luau:376) at the target and let it fly, interrupting mid-
-- flight rather than snapping (the spring's own guarantee); with none — a
-- bare `mountLib.mount` + `renderer.attach` in a unit test, which never runs
-- a presenter's `bindContribution` walk at all — every retarget falls back to
-- Task 3's instant `applySlide`, unchanged. `retarget(px)` is that one
-- fork; `open`/`close`/`settleTo` never write `offset` directly.
--
-- TRAY WIDTH (revised: code review, 2026-08-10 — see the Task 4 fix-report
-- addendum). Rather than hand-measure a label at BUILD time (the exact
-- "cached before truth exists" bug class docs/research/roblox-text-bounds-
-- boot-window warns about — a width guessed before the engine has laid
-- anything out is wrong forever) OR read it back from the tray's own SOLVED
-- geometry (the first shipped version of this file: a feedback loop once that
-- geometry is itself something this reveal shrinks, AND — the review finding
-- — permanently stale against a live `preferredTextSize`/theme change, since
-- a solved rect is only ever produced by a solve THIS composite triggered),
-- each tray button's natural width is an INDEPENDENT measurement: the same
-- `text_metrics.measure(label, font, size, math.huge)` oracle
-- `tests/row_actions.spec.luau`'s own localization test already uses,
-- fed by `controller.textAt(path)` — the framework's own published,
-- LIVE-subscribed font/size facts for that exact node (`bindController`,
-- the same delivery shape as `bindMotion`; `renderer.luau`'s `toLayoutNode`
-- already re-measures on `themeMetrics`/`typographyScale`/
-- `preferredTextOffset` changing, so these facts are ALREADY reactive to
-- every one of those — this control duplicates none of that arithmetic).
-- Because the measurement asks for the label at UNLIMITED width, it can
-- never read back anything this reveal itself painted — there is no
-- geometry in the loop at all, so re-deriving it on EVERY `syncGeometry`
-- (no freeze, no staleness) is safe by construction, not by care. The
-- remaining ingredients — `buttonPad`/`buttonMinWidth`/`trayGap`/`rowGutter`
-- in pixels, and the installed package's own `chromeInsets.control` — are
-- theme facts with no font/size component, resolved the same way
-- `table.luau` resolves its own theme metrics (`spec.env`, optional,
-- degrades to `themeSnapshot.neutral()`).
--
-- THE FRAME IS PART OF THE REQUIREMENT (device bug round 2026-08-12, finding
-- A3). A plate's width is decided here and written as `fixed px`, so nothing
-- downstream can grow it — which means this sum has to include everything the
-- box will be asked to hold, the package's carved border included. It shipped
-- as text + 2 * `buttonPad`, the flat-theme half of the sum, and every package
-- that paints a frame reserved `chromeInsets.control` out of that same box at
-- paint time; the label lost exactly the frame ("Mark Read" cut off under
-- Fantasy Parchment). See docs/lessons/measure-the-requirement-not-the-render.md
-- and a-fixed-box-cannot-hold-a-themes-frame.md — this is that lesson's width
-- form.
--
-- AND THE BAND HAS TO FIT THE ROW (same round, finding A1b). Nothing used to
-- constrain the sum at all: four actions on a 160px row put the first plate at
-- x = -108, outside the row, unreachable, with `controller.diagnostics()`
-- empty. On a row whose width is decided FOR it the naturals now share out what
-- there is; on a hug row — whose solved width is itself derived from this band
-- — they do not, because clamping to it would be clamping the band to itself.
--
-- DESTRUCTIVE COLOUR. `UI.Button` already carries a semantic `role` prop
-- (`enum = { "default", "cancel", "destructive" }`, src/blueprint_schema.luau)
-- that "drives a style tag and its sheet rule" — the exact shipped `danger`/
-- `onDanger` pair (src/tokens/sheet_model.luau: `buttonRole == "destructive"`
-- -> tag `facet-role-destructive`). An ActionSpec's `role = "destructive"`
-- maps straight to it; `role = "normal"` (or absent) leaves the Button at its
-- own default role, which already paints the control/content pair. No new
-- color token, no bespoke fill — reusing exactly what Task 2's docs promised.

local contribution = require("../input/contribution")
local row_actions_state = require("../input/row_actions_state")
local drag_velocity = require("../input/drag_velocity")
local themeSnapshot = require("../themes/snapshot")
-- for `iconGlyph` alone: an icon-first tray button DRAWS the framework glyph, so
-- the natural width below has to measure the glyph rather than the label the
-- button no longer paints (director device round 2026-08-12).
local themePackage = require("../themes/package")
local text_metrics = require("../layout/text_metrics")
-- the SHARED anchored-placement decision (navigation-and-menus D1). `computeMenuAnchor`
-- below was one of the two hand-rolled copies of it; the flip rule this file's own
-- ruling 4 wrote down now lives in one place and three callers ask it.
local anchorPlacement = require("../layout/anchor_placement")
local specGuard = require("../spec_guard")
-- the ONE menu row and the ONE presentation rule, shared with popup_button and
-- the freestanding newMenu (navigation-and-menus D2)
local menuRecipe = require("./menu_recipe")
-- the ActionSpec authoring contract and three leaf helpers, lifted out whole
-- (2026-08-14): pure functions of their arguments, sharing not one upvalue with
-- `buildEngine`. See that file's header for why the split happened at all.
local rowActionsSpec = require("./row_actions_spec")
-- ...and the open-state coordinator, which was always a PUBLIC export
-- (`Facet.newRowActionsCoordinator`) living inside this module's private body.
-- Re-exported below as `row_actions.newCoordinator`, unchanged.
local rowActionsCoordinator = require("./row_actions_coordinator")
-- ...and the reorder-vs-swipe arbiter Table composes over one row Hit surface.
-- Re-exported below as `row_actions.composeWithReorder`, unchanged.
local rowActionsReorder = require("./row_actions_reorder")
-- ...and every live pixel amount the band is made of: the four
-- `controls.rowActions.*` theme metrics, the per-action naturals, the band
-- arithmetic and the edit-mode gutter. Built once per engine, below.
local rowActionsMetrics = require("./row_actions_metrics")
-- ...and the tray blueprints themselves, which both modes share: standalone
-- parents them under its own row root, a host under its one shared overlay.
local rowActionsTrays = require("./row_actions_trays")
-- ...and the standalone/Table row node those trays are parented under. Hosted
-- mode builds none of it, which is the whole point of hosted mode.
local rowActionsRoot = require("./row_actions_root")

-- ALIASED AT MODULE SCOPE, above every caller, deliberately — a local declared
-- LATER is not an upvalue, it silently captures a nil global
-- (docs/lessons/later-locals-are-not-upvalues.md, bitten five times here).
-- Aliasing rather than rewriting ~15 call sites keeps this extraction a move.
local patternEscape = rowActionsSpec.patternEscape
local isPathPrefix = rowActionsSpec.isPathPrefix
local trayId = rowActionsSpec.trayId
local actionsFor = rowActionsSpec.actionsFor
local normalizeFullSwipe = rowActionsSpec.normalizeFullSwipe

local row_actions = {}

--[[ THE ROW'S KEY SURFACE, DECLARED ONCE (parity round 3, owed row 9,
	2026-08-13). Two readers: this file's own `ensureKeysContext`, which binds
	them on the engine's focus-scoped context; and a HOST that has to stand in
	for an engine it has not built yet (`newVirtualList` — a hosted engine is
	born at a pointer gesture's axis lock, so a row a keyboard-only or pad-only
	player has merely focused had no engine and therefore no binding at all,
	neither Delete nor the menu that is a pad's route to a non-destructive
	action). A host binding its own spelling of these keys is how the two drift;
	one table is why they cannot.

	`ROW_KEY_PRIORITY` is the ENGINE's, and it is the higher: with `sink = true`
	a live engine consumes the key before any stand-in at a lower priority sees
	it (`src/input/actions.luau`'s arbitration cuts strictly-lower contexts), so
	a row whose engine exists commits exactly once however many bindings name
	the key. A host binds strictly BELOW this number. ]]
row_actions.ROW_KEY_PRIORITY = 10000
row_actions.ROW_KEYS = {
	-- Delete/Backspace: commit the first destructive action (`commitDestructive`)
	delete = { { keyCode = "Delete" }, { keyCode = "Backspace" } },
	-- gamepad ButtonX / keyboard Shift+Return: the action menu (`toggleMenu`)
	menu = { { keyCode = "ButtonX" }, { keyCode = "Return", modifiers = { shift = true } } },
}

-- RE-EXPORTED, not moved out of the public surface: both types are authored in
-- `row_actions_spec.luau` (which is what validates against them) and republished
-- here under their shipped names, so `newRowActions.ActionSpec` and every
-- `{ ActionSpec }` annotation in this file read exactly as before.
export type Edge = rowActionsSpec.Edge
export type ActionSpec = rowActionsSpec.ActionSpec

export type Spec = {
	id: string?,
	content: any, -- Blueprint, required
	leading: { ActionSpec }?, -- nil = none; {} is a spec error
	trailing: { ActionSpec }?,
	fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?, -- default true
	coordinator: any?, -- newRowActionsCoordinator() result; Task 7 wires it
	-- OPTIONAL, table.luau's own precedent (`table.luau` Spec.env): live text/
	-- theme reactivity for each tray button's reserved width (buttonPad,
	-- buttonMinWidth) needs the environment's theme snapshot, and a composite
	-- has no other line to it (unlike font/size, which arrive fully resolved
	-- through `controller.textAt` — see the natural-width comment below).
	-- Absent degrades to `themeSnapshot.neutral()`, exactly like `table.luau`'s
	-- own `metricsOr` fallback — "the neutral package at authored size... which
	-- is what the suite has always solved" (table.luau).
	env: any?,
	--[[ MAY THIS ROW BE DELETED AT ALL? (`rowDeletable`, wired 2026-08-14.)
		A thunk, evaluated at COMMIT time inside `doCommitAction` — the one funnel
		the swipe commit, the revealed tray's Delete button, the edit-mode ⊖, the
		Delete/Backspace key and the action menu's destructive row all reach.
		Returning `false` refuses the delete; every non-destructive action is
		untouched.

		A THUNK AND NOT A BOOLEAN, because this composite has NO NOTION OF AN ITEM
		— it receives already-resolved `ActionSpec` lists. `newTable` /
		`newVirtualList` own the item and own `spec.rowDeletable`, so each closes
		over both and hands the verdict down; evaluating it late means a predicate
		reading a mutated item still decides correctly, and it keeps the fail-closed
		reading in ONE place (`row_capability.allows`) rather than two.

		`nil` (the default) means "every destructive action commits", which is what
		makes this cost nothing for every caller that never wires it. ]]
	deletable: (() -> boolean)?,
	-- Task 9 (iOS edit-mode leading minus). PUBLIC, not `_editing`: `table.luau`'s
	-- own `editing` spec key (Spec.editing there, "owner-held edit-mode signal")
	-- is the shipped precedent for a Readable-valued spec key living in the
	-- open, undecorated namespace — Table (Task 10) passes its OWN `editing`
	-- straight through to this exact field, and a standalone caller wiring an
	-- edit-mode toggle by hand (no Table involved) wants the identical seam, not
	-- an internal one it cannot reach. `nil` (the default) means "this row is
	-- never in edit mode" — the minus can then never appear, structurally,
	-- regardless of `hasDestructive`, at zero cost (see `hasEditAffordance`
	-- below): a caller that never wires edit mode pays nothing for this task.
	editing: any?, -- Readable<boolean>?
	-- Task 10 (Table integration). `nil` (default) leaves the root
	-- content-sized — Tasks 3-9's own shipped shape, unchanged, and correct
	-- for every existing caller whose `content` already carries its own
	-- intrinsic width (a Text/Button-shaped row). A caller whose `content`
	-- is ITSELF `width = fill` (Table's own row — see table.luau's own
	-- rowBlueprint) has nothing intrinsic for the composite's own
	-- content-sized root to measure: `Content` (fill) degrading to ITS
	-- children's natural size finds only more "fill" all the way down, so
	-- the whole composite collapses to a near-zero measured width. Table
	-- passes `{ type = "fill", weight = 1 }` here — the exact prop the
	-- unwrapped "Row" node carries on its own — to restore the row's normal
	-- list-flow width; a standalone caller never sets this and is
	-- byte-identical to before this field existed.
	width: any?,
	-- Task 10 (Table integration). Default false: every standalone
	-- `newRowActions` caller (and every Table row that is NOT `reorderable`)
	-- keeps this composite's own internal Content "Hit" Grip wired to
	-- `_pointerHandlers` exactly as Tasks 3-9 shipped it — the composite is
	-- fully self-sufficient. `true` skips wiring that Grip's pointer handlers
	-- (the node itself still mounts, just inert): the caller is going to
	-- drive `_pointerHandlers` from ITS OWN hit surface instead (Table's own
	-- row "Hit" Button, composed with reorder via `composeWithReorder`
	-- below). Structural reason, not a style choice: `content` (a Table row)
	-- already carries its OWN full-fill Active pointer surface at the
	-- identical rect this composite's Grip occupies — two independent Active
	-- zones racing for the engine's one-at-a-time InputBegan capture
	-- (ADR-0008) is exactly the "row hit won the race" class table.luau's own
	-- `rowPointerHandlers` header comment already names as unsafe to leave to
	-- firing order. Table wins deterministically by construction instead:
	-- this composite simply never enters the race.
	externalGesture: boolean?,
}

-- HOSTED MODE (row-actions perf mission, Task 2; design:
-- docs/plans/row-actions-hosted-mode-design.md §"Hosted mode: a closed row
-- mounts NOTHING"). `row_actions.buildHosted` runs the SAME engine `build`
-- runs — one shared `buildEngine` below, not a fork — and builds NO BLUEPRINT
-- AT ALL: the host (VirtualList) already mounts a per-row hit surface and can
-- paint the slide through its own presentation channel, so a closed hosted row
-- costs zero extra Instances. What the host must supply is exactly what the
-- missing blueprint used to answer:
--   * `paths` — the rects/text facts this engine reads live (the row's own
--     node, and the shared tray overlay's own tray containers). `build` fills
--     the identical lookups from its OWN mounted node ids; every one of them
--     now goes through `pathsOf` below, so neither mode hardcodes the other's.
--   * `onSlide` — the paint. `applySlide` still writes the internal `offset`
--     signal (every gesture/commit decision in this file reads it back), and
--     additionally hands the host the pixel number to paint with.
--   * `onCommitHeight` — the commit's height collapse, same shape.
-- The host reaches the presenter-only seams (`bindMotion`/`bindController`/…)
-- by FORWARDING them from its own contribution — a hosted engine has no node
-- to attach one to.
export type HostedPaths = {
	content: string, -- the host's own row node: the row's live rect/screen rect
	trayLeading: string?, -- the shared overlay's leading tray container
	trayTrailing: string?,
	-- where the host mounts `api.editAffordanceView` (stage 1, 2026-08-15).
	-- Required exactly when that view exists — an unreachable minus that
	-- ANNOUNCES itself as "Delete" is refused at build time, not shipped.
	editAffordance: string?,
}

export type HostedSpec = {
	id: string?,
	leading: { ActionSpec }?,
	trailing: { ActionSpec }?,
	fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?,
	coordinator: any?,
	env: any?,
	-- `Readable<boolean>?`, same contract as `Spec.editing` — see `HOSTED_KEYS`
	editing: any?,
	paths: HostedPaths,
	onSlide: (px: number) -> (),
	onCommitHeight: ((px: number?) -> ())?,
}

type HostedOpts = {
	paths: HostedPaths,
	onSlide: (px: number) -> (),
	onCommitHeight: ((px: number?) -> ())?,
}

-- fix round 1, finding 6: `row_actions.buildHosted`'s own return type, named
-- rather than the `any` it shipped with. `pointerHandlers`'s four members
-- carry the SAME `(path, pos, rectOf)` signature as `_pointerHandlers`
-- (mirrored below rather than reused — the header's own struct literal, not a
-- named type, is what `onPointerDown`/etc. are declared against). Every
-- `bind*`/`dump`/`trayState` member stays `any` on purpose, matching this
-- file's own existing convention for a Readable-valued or presenter-supplied
-- field (see `HostedSpec.coordinator`/`Spec.editing` above): the real shapes
-- (`Readable<T>`, a presenter's action-system/focus-graph/motion-clock
-- handles) live in modules this control deliberately does not import a type
-- from (`core/contract.luau`, `input/actions.luau`, `present/focus_map.luau`,
-- `motion/clock.luau`) — a documented `any` here, same as everywhere else in
-- this file a presenter hands over something it cannot construct for itself.
export type HostedEngine = {
	blueprint: nil, -- always nil: a hosted engine mounts no node of its own
	dump: () -> any,
	dispose: () -> (),
	_open: (edge: Edge) -> (),
	_close: () -> (),
	_isOpen: () -> boolean,
	_settleTo: any,
	_closeMenu: () -> (),
	_menuHandle: () -> any,
	_pointerHandlers: {
		onPointerDown: (path: string, pos: any, rectOf: (string) -> any) -> boolean?,
		onPointerMove: (path: string, pos: any, rectOf: (string) -> any) -> (),
		onPointerUp: (path: string, pos: any, rectOf: (string) -> any) -> (),
		onPointerCancel: (path: string, reason: string?) -> boolean?,
	},
	_commitFirst: (edge: Edge) -> boolean,
	_handleActivate: (path: string, meta: any?) -> boolean,
	-- hosted-only (never present on `row_actions.build`'s own return):
	pointerHandlers: {
		onPointerDown: (path: string, pos: any, rectOf: (string) -> any) -> boolean?,
		onPointerMove: (path: string, pos: any, rectOf: (string) -> any) -> (),
		onPointerUp: (path: string, pos: any, rectOf: (string) -> any) -> (),
		onPointerCancel: (path: string, reason: string?) -> boolean?,
	},
	open: (edge: Edge) -> (),
	close: () -> (),
	-- `Readable<nil | { edge: Edge, actions: { ActionSpec }, revealPx: Readable<number> }>`
	trayState: any,
	-- the tray `UI.When` blueprints — the SAME ones standalone mode parents under
	-- its row root, for the host to parent under its shared overlay (Task 4)
	trayViews: { any },
	-- ...and the edit-mode minus, same deal (stage 1). BOTH are nil unless this
	-- row can ever show it: `spec.editing` wired AND a destructive action
	-- somewhere. `editGutterPx` is a `Readable<number>` the host declares as its
	-- own row content's left PADDING — not a callback, because the gutter stopped
	-- being an offset at the director's 2026-08-12 device round (finding 2) and a
	-- padding is a declaration, not an event.
	editAffordanceView: any,
	editGutterPx: any,
	syncGeometry: ((rectOf: ((string) -> any)?, rootNode: any?) -> ())?,
	bindMotion: (clock: any, now: (() -> number)?) -> (),
	bindController: (controller: any) -> (),
	bindPresent: (presentModal: any, dismiss: any) -> (),
	bindActionSystem: (system: any) -> (),
	bindFocusGraph: (graph: any) -> (),
	handleCancel: (focusedPath: string?) -> boolean,
	-- `{ active: Readable<boolean>, dismiss: () -> (), consume: boolean }` —
	-- fix round 1, finding 3.
	outsideDismiss: any,
}

-- CLOSED SPEC (constitution §4; ARCH-1).
local ROW_ACTIONS_KEYS = specGuard.keySet({
	"id",
	"content",
	"leading",
	"trailing",
	"fullSwipe",
	"coordinator",
	"env",
	"deletable",
	"editing",
	"externalGesture",
	"width",
})
-- The hosted spec is NOT the standalone spec plus three keys: `content`,
-- `width` and `externalGesture` are all statements about a blueprint this mode
-- never builds (`externalGesture` is implied — there is no internal Hit Grip to
-- suppress), so each is refused by name rather than silently ignored.
--
-- `editing` USED TO BE ON THAT LIST AND NO LONGER IS (2026-08-15, stage 1 of the
-- order in `docs/plans/table-hosted-row-actions-stage2.md`). The refusal was
-- filed under the same sentence as the other three and was not true of it: the
-- minus is ONE `UI.When` view — exactly the shape `trayViews` already hands a
-- host to parent — and the gutter is ONE Readable the host declares as its own
-- row content's left padding. Nothing about either is a statement about a
-- blueprint. It was a prerequisite, not a property: Table is the only surface
-- with an edit mode, it ships, and it is gamepad-reachable through the
-- `padMinusTable` showcase case *because* VirtualList cannot do it — so a Table
-- that hosted without this would have had to delete that case.
local HOSTED_KEYS = specGuard.keySet({
	"id",
	"leading",
	"trailing",
	"fullSwipe",
	"coordinator",
	"env",
	"deletable",
	"editing",
	"paths",
	"onSlide",
	"onCommitHeight",
})
-- `editAffordance` is the path the host mounts `api.editAffordanceView` at —
-- `{itsOwnParent}/EditAffordanceWhen/then/EditAffordance`, the node ids the view
-- itself declares — because that is the path an Activate on the minus arrives
-- on. Required exactly when the minus can ever appear (see `buildEngine`).
local HOSTED_PATH_KEYS = specGuard.keySet({ "content", "trayLeading", "trayTrailing", "editAffordance" })
-- ACTION_KEYS / FULL_SWIPE_KEYS live in `row_actions_spec.luau` beside the only
-- two functions that read them (`buildActionSpec`, `normalizeFullSwipe`).

-- THE TRAY BUTTON'S OWN THEME METRICS (Task 2; ADR-0019 §2) live in
-- `row_actions_metrics.luau`, with the memos that resolve them.
--[[ THE LEGIBILITY FLOOR — below this a revealing plate stops being drawable.

	DEVICE REPORT, game director, 2026-08-13 (`pop.mov`, Glossy Touch): on close
	the tray buttons "go past the end of the rows, overlap, and then pop out."

	MEASURED, per frame, before anything was changed. The plates do not slide out
	from under the row — each plate's WIDTH is scaled by the reveal fraction, so
	they squeeze in place: on a settled-open close the trailing pair goes
	75/58 -> 33/26 -> 9/7 -> 3/2 -> 1/1 -> gone. That is by design (round 2's C9a
	made plate width track the finger, to stop the whole band painting before the
	row had moved) and the director's ruling of 2026-08-13 KEEPS it.

	WHAT IT IS NOT is drawable at the bottom of that ramp, and the theme is what
	exposes it. A package like `glossy_touch` paints every plate with a corner
	radius, a stroke and a gradient. At 3px wide the radius and the stroke have
	nowhere to go: the engine renders a smeared lens rather than a button, which
	reads as a coloured sliver overlapping the row's edge — and then it hits 0 and
	vanishes, which reads as the pop. On a flat package the same 3px is an
	unremarkable thin rectangle, which is exactly why this was invisible until
	somebody filmed the glossy theme.

	So a plate narrower than this is drawn at ZERO instead. The row is still
	travelling when it happens (8px of 159 remaining, ~5% of the flight, ~2
	frames at the settle end of the spring), so the band simply finishes early
	rather than crushing — and finishing early is SAFE against the invariant the
	open direction asserts, which is one-directional: never MORE band than the
	row has travelled. Less is allowed; more is the defect.

	SO IT IS ONE THRESHOLD, NOT TWO. The first attempt floored each PLATE's width
	and left the band's own box alone, which broke the band-tracks-travel invariant
	the open direction asserts: the plates went to zero while the container kept
	its inter-plate gaps and its row-facing gutter, so the box stopped agreeing
	with `|offset|` by several px. The coherent version is the one below — this is
	`REVEAL_EPS`, the single place that decides whether a tray is revealed AT ALL.
	Below this much travel there is nothing legible to draw, so the tray is
	closed, container and plates together, and the invariant holds by
	construction.

	It replaces a 0.5px epsilon whose only job was "not exactly zero" (C9b, device
	round 2026-08-12 — the unmount used to wait for an exact 0 that a
	position-domain spring reaches several frames after it visually arrives).
	Raising 0.5 -> 8 keeps that fix and adds this one: the last 8px of travel is
	~5% of a full reveal and about two frames at the settle end of the spring.

	A literal rather than a theme metric, deliberately: this is a floor on what
	the ENGINE can render legibly, not a design value a package should be able to
	tune. A package that wants a wider plate raises `buttonMinWidth`, which is a
	different question with its own metric. ]]
local PLATE_LEGIBLE_MIN_PX = 8
-- BUTTON_PAD / TRAY_GAP / ROW_GUTTER / EDIT_AFFORDANCE live in
-- `row_actions_metrics.luau` with the memos that resolve them; each keeps its
-- own device-round history there, and the two theme KEYS a Button declares raw
-- are read by `row_actions_trays`/`row_actions_root` directly.

--[[ PERCEPTUAL ARRIVAL, not the solver's epsilon (device bug round 2026-08-12,
	finding C9b: "after the row slides back, you see it stop and then pop position
	one or two frames later"). The reveal `When`s below used to unmount on `offset
	== 0` EXACTLY, and a position-domain spring only reaches its target at
	`spring.luau`'s `DEFAULT_EPS` of 1e-3 — which that module's own header warns is
	"a few frames after they visually arrive". Measured on the showcase list: the
	row was within half a pixel of home at frame 23 and the tray unmounted at frame
	58, so a visible sliver of band (the row gutter the band spends as its own
	padding) stood on screen for 35 frames after the motion was over and then
	vanished in one. Half a pixel is the distance below which no engine can paint
	the row anywhere else, so it is the honest place to call the reveal finished —
	the same "arrival is a RADIUS, not an epsilon" rule `chase.luau` already
	states. ]]
local REVEAL_EPS = PLATE_LEGIBLE_MIN_PX
-- PUBLISHED, because a HOST has to end its engagement on the same test. The
-- VirtualList clears the engaged row (and with it the presentation transform and
-- the shared overlay entry) from its own `onSlide`, and if that used a different
-- threshold than the reveal above, the tray's focused button would unmount a
-- frame before the host got the chance to put the ring back on its row — measured
-- as the R1 focus restore stranding at the top of the list. One number, two
-- readers (`virtual_list.luau`'s `hostedApplySlide`).
row_actions.REVEAL_EPS = REVEAL_EPS

-- ===== Task 7: the open-state coordinator =====================================
-- PUBLIC API, and it lives in `row_actions_coordinator.luau` (2026-08-14): a
-- public export inside another module's private body was the clearest seam this
-- file had, and it had to shed periphery to get back under the 200,000-char
-- `Script.Source` WRITE cap Rojo live-sync assigns through. RE-EXPORTED HERE
-- UNDER ITS SHIPPED NAME — `src/init.luau` publishes this exact field as
-- `newRowActionsCoordinator`, and `table.luau`/`virtual_list.luau` both call it
-- as `row_actions.newCoordinator`, so the export shape does not move.
row_actions.newCoordinator = rowActionsCoordinator.new

-- THE ONE ENGINE (Task 2). `row_actions.build` and `row_actions.buildHosted`
-- (both at the bottom of this file) are the two entry points into this single
-- function — the state signals, axis lock, velocity tracker, coordinator
-- claim, commit ladder, menu and keyboard bindings are all shared code, never
-- a fork. `hosted == nil` is the standalone/Table composite (blueprint and
-- all); `hosted ~= nil` skips every node this file would otherwise build and
-- routes the two things a node used to answer — paths and paint — through
-- `pathsOf`/`applySlide` below. Each entry point validates its OWN spec
-- against its own closed key set before calling in here.
local function buildEngine(Facet: any, core: any, spec: any, hosted: HostedOpts?)
	local UI = Facet.UI
	local id = spec.id or "RowActions"
	local scope = core:scope("row-actions-" .. tostring(id))
	-- read once: `hosted` is a build-time fact, never live
	local isHosted = hosted ~= nil
	-- ...and so is "is this row's width decided FOR it" (device bug round
	-- 2026-08-12, finding A1b — see `deriveNaturals`, the one reader). A hosted
	-- row's box is the host's own (this file mounts nothing at all, and the tray
	-- lives in a separate overlay); a `fill`/`fixed` root is sized by its parent.
	-- Anything else — the default, content-sized root above all — HUGS, and an
	-- Anchor's hug includes the tray it is being asked to measure against, so
	-- its width is not an independent fact and must never be used as a cap.
	local widthKind = if type(spec.width) == "table" then (spec.width :: any).type else nil
	local clampable = isHosted or widthKind == "fill" or widthKind == "fixed"
	-- fix round 1, finding 5: every error this shared function (and the
	-- validation helpers it calls — `actionsFor`/`buildActionSpec`/
	-- `normalizeFullSwipe`, now in `row_actions_spec.luau`, which is why they
	-- take `label` as their first argument) raises names the CALLING entry point,
	-- not always
	-- the standalone one. Both `row_actions.build` and `row_actions.buildHosted`
	-- already assert their OWN closed key set under their own name before
	-- ever reaching here (`"newRowActions"`/`"newRowActionsHosted"` at the
	-- `assertKnownKeys` call sites) — this is that same label, reused for
	-- every OTHER error this shared body can still raise.
	local label = if isHosted then "newRowActionsHosted" else "newRowActions"

	if not isHosted and (type(spec.content) ~= "table" or (spec.content :: any).class == nil) then
		error(`Facet {label}('{id}'): \`content\` is required and must be a Blueprint`, 0)
	end
	-- nil in hosted mode: the HOST mounts the row, this engine wraps nothing
	local content = spec.content

	if spec.coordinator ~= nil and type(spec.coordinator) ~= "table" then
		error(
			`Facet {label}('{id}'): \`coordinator\` must be a table (the value newRowActionsCoordinator `
				.. "returns) — Task 7 wires it",
			0
		)
	end
	-- REDTEAM FIX (item 16, LOW; director ruling — constitution strictness).
	-- `id` defaults to the literal string `"RowActions"` when absent (below)
	-- — harmless for a single standalone row, but every row in a VStack/
	-- ScrollView built with a SHARED `coordinator` and no explicit `id`
	-- would default to that SAME literal, colliding: the composite's own
	-- root node id (and every path under it — trays, menu, the edit
	-- affordance) is not unique per row, which corrupts the presenter's
	-- own path-keyed bookkeeping (instances, focus, contributions) the
	-- instant a second such row mounts alongside the first. Table's own
	-- integration always supplies a unique `id = "RowActions-" .. rowKey`
	-- (table.luau), so this can only ever be reached by a standalone
	-- caller composing its own list — refused loudly, at build time,
	-- rather than left to silently corrupt the second row's own state.
	if spec.coordinator ~= nil and spec.id == nil then
		error(
			`Facet {label}: rows sharing a coordinator must carry unique ids `
				.. '(pass `id` explicitly — every row defaults to the same "RowActions" id otherwise, '
				.. "colliding paths under one shared list)",
			0
		)
	end
	-- Task 7: the shared open-state coordinator (`row_actions.newCoordinator`),
	-- optional. Read live below rather than snapshotted, though a build-time
	-- read is already the whole story here — the spec table itself is never
	-- mutated after `build` returns.
	local coordinator = spec.coordinator

	-- Task 10: see the Spec field's own comment. Hosted mode is the same
	-- statement taken to its fixed point (the host's own row surface drives
	-- these handlers), except there is no internal Grip to suppress at all —
	-- this whole file builds no node in that mode.
	local externalGesture = isHosted or spec.externalGesture == true

	-- Task 7: this composite's own identity as far as the coordinator is
	-- concerned IS the object `row_actions.build` returns below (the exact
	-- table a caller already holds) — no second identity scheme, no wrapper.
	-- Forward-declared because `claim`/`release` are called from closures
	-- defined BELOW this point (the gesture handlers, `open`, `close`,
	-- `dispose`) that only ever run at event time, long after `api` has been
	-- assigned at the bottom of this function — never at build time, when it
	-- would still be nil.
	local api: any = nil

	-- Task 9: `editing` must be a Readable<boolean> (a signal or memo) when
	-- present — `nil` is the other legal value ("this row is never in edit
	-- mode"), a plain `true`/`false` literal is not (unlike `table.luau`'s own
	-- `spec.editing`, which accepts one but silently treats it as absent via
	-- `spec.editing or scope:own(core:signal(false))` — a real, if minor,
	-- existing footgun this control does not repeat: a caller who passes a
	-- literal boolean here gets a loud build-time error naming the mistake,
	-- not a silently-ignored one). `UI.isReadable` is the framework's own
	-- published check (`blueprint.isReadable`, exposed as `Facet.UI.isReadable`
	-- — `async_image.luau`'s own precedent for reaching it from a control).
	if spec.editing ~= nil and not UI.isReadable(spec.editing) then
		error(
			`Facet {label}('{id}'): \`editing\` must be a Readable<boolean> (a signal or memo), or nil `
				.. "for a row that is never in edit mode",
			0
		)
	end

	local leadingActions = actionsFor(label, id, "leading", spec.leading)
	local trailingActions = actionsFor(label, id, "trailing", spec.trailing)
	-- normalized at build time (row_actions_state.new's fullSwipeLeading/
	-- fullSwipeTrailing opts); Task 5's gesture/commit paths below are the
	-- first consumers of the decision itself.
	local fullSwipe = normalizeFullSwipe(label, id, spec.fullSwipe)

	local actionsById: { leading: { [string]: ActionSpec }, trailing: { [string]: ActionSpec } } =
		{ leading = {}, trailing = {} }
	for _, action in leadingActions or {} do
		actionsById.leading[action.id] = action
	end
	for _, action in trailingActions or {} do
		actionsById.trailing[action.id] = action
	end

	-- Task 8: does ANY edge declare a destructive action? Static (an
	-- ActionSpec list never changes post-build — see `actionsById` above),
	-- computed once so the keyboard Delete binding below can be skipped
	-- ENTIRELY when the answer is false: "No destructive action anywhere = do
	-- not register the binding at all — the key must fall through to
	-- whatever else wants it" (brief). A REGISTERED-but-inert binding would
	-- still shadow whatever else on the screen wants Delete/Backspace while
	-- this row holds focus; not registering is the only way to truly not be
	-- there.
	local hasDestructive = false
	for _, action in trailingActions or {} do
		if action.role == "destructive" then
			hasDestructive = true
			break
		end
	end
	if not hasDestructive then
		for _, action in leadingActions or {} do
			if action.role == "destructive" then
				hasDestructive = true
				break
			end
		end
	end

	-- Task 9: the minus can EVER appear only when both halves are true — a
	-- destructive action exists somewhere, AND the caller actually wired an
	-- edit-mode signal. Static (both inputs are build-time facts: `hasDestructive`
	-- never changes post-build, and whether `spec.editing` was PASSED AT ALL is
	-- likewise fixed at build time — only its VALUE is live), so every reactive
	-- node this feature costs (`editAffordanceShown`/`editGutterPx`/the extra
	-- `contentOffsetX` memo/the tray's own gutter `offsetX`/the `EditAffordanceWhen`
	-- node itself) is built ONLY inside `if hasEditAffordance then` below —
	-- a caller who never wires `editing` pays NOTHING for this task, byte-
	-- identical to Tasks 3-8 (measured: Task 9 report §Instance Count).
	local editingReadable = spec.editing
	local hasEditAffordance = hasDestructive and editingReadable ~= nil

	--[[ THE HOSTED MINUS NEEDS A PATH, for the same reason a hosted tray does
		(fix round 1, finding 1 — see `buildHosted`'s own tray-path refusals). This
		engine mounts nothing, so an Activate on the minus can only get home by
		matching the path the HOST mounted it at. Without one, `handleActivate`
		below has no pattern, returns `false` for every press, and the host forwards
		it nowhere — a button that borrows the destructive action's own accessible
		label and therefore ANNOUNCES itself as "Delete" would do nothing at all.
		The same class of silent degradation the tray-path refusal exists for.

		CHECKED HERE, NOT IN `buildHosted`: `hasEditAffordance` is the honest
		condition ("can this row EVER show the minus"), and it needs the validated
		action lists, which is work `buildHosted` would have to duplicate. ]]
	local hostedEditPath: string? = if hosted ~= nil then (hosted.paths :: any).editAffordance else nil
	if isHosted and hasEditAffordance and (type(hostedEditPath) ~= "string" or hostedEditPath == "") then
		error(
			`Facet {label}('{id}'): \`editing\` on a row with a destructive action requires `
				.. "`paths.editAffordance` (where the host mounts `editAffordanceView`) — without it the "
				.. "minus is mounted but unreachable: every Activate on it falls through, and a button "
				.. 'that announces itself as "Delete" does nothing',
			0
		)
	end

	-- Task 8: every action, leading-then-trailing, DOCUMENT ORDER — the
	-- action menu's own row order (brief: "listing EVERY action (leading
	-- then trailing, document order)"). Static for the same reason as
	-- `actionsById` above.
	local menuItemsOrdered: { { edge: Edge, action: ActionSpec } } = {}
	for _, action in leadingActions or {} do
		table.insert(menuItemsOrdered, { edge = "leading" :: Edge, action = action })
	end
	for _, action in trailingActions or {} do
		table.insert(menuItemsOrdered, { edge = "trailing" :: Edge, action = action })
	end

	-- ===== reveal state ======================================================
	local openEdge = scope:own(core:signal(nil :: Edge?))
	local offset = scope:own(core:signal(0))
	-- Task 5: the commit sequence's own height-collapse target — `nil` means
	-- "no override" (BOX.height "content-sized when absent",
	-- src/layout/solver.luau: `node.height or CONTENT`), which is what every
	-- row that never commits reads forever, byte-identical to Tasks 3-4 (no
	-- `height` prop was ever set on the root before this task). Only a commit
	-- (`doCommit` below) ever writes a real pixel number here.
	local rowHeightOverride = scope:own(core:signal(nil :: number?))
	-- true once `dispose()` has run — the commit sequence's own belt-and-
	-- suspenders guard (spec: "never fire onAction for a row whose key no
	-- longer matches"), on top of the emergent one disposing `scope` already
	-- gives it for free: a disposed MotionValue clears its `onSettle`
	-- subscribers (motion.luau `value.dispose`: "table.clear(subs)"), so a
	-- slide/collapse already in flight when disposal lands never reaches its
	-- next `onArrive` at all. See `doCommit`'s own comment below.
	local disposed = false
	-- a row commits at most once WHILE IN FLIGHT (a destructive commit's own
	-- async slide-off+collapse chain, guarded against a second commit racing
	-- in mid-sequence) — declared here (rather than immediately above
	-- `doCommitAction`, where it is READ) so `close()` below, defined before
	-- `doCommitAction`, can also WRITE it (redteam item 5, MAJOR: see the
	-- big comment on `close()` for why resetting it there is the fix). Luau
	-- locals are only visible to code that follows their own declaration
	-- textually, so this has to sit ahead of every closure that touches it.
	local committed = false
	--[[ REVIEW FIX (hosted-mode round 2, D1 — SHARED, both modes). `committed`
		covers the commit's OWN flight, and `onPointerDown` already refuses a new
		gesture while it is set. What neither covered is the window AFTER the
		commit completes: the chain's last step fires the action and calls
		`resetToClosed()`, which clears `committed` and starts a spring home from
		the parked slide-off position — a whole row width away. Measured on the
		hosted list: the row sits at exactly -800 while the height collapse plays,
		fires at ~frame 115, and then flies -800 -> 0 over ~65 more frames with
		`committed` already false.

		A press landing in THAT window was accepted, and `drag.startOffset` read
		the live `offset` — so a gesture that never travelled anywhere began at
		-800, and the very next release handed `settle()` a magnitude past the 60%
		commit threshold. Swipe-to-delete fired twice, on one swipe.

		`commitLatched` closes the whole window: set the moment either role branch
		of `doCommitAction` decides to fire, cleared only when the row is actually
		back at rest (`applySlide` sees exactly 0 — the terminal write every path
		makes, spring or instant). While it is set, `onPointerDown` refuses, so
		the commit ladder cannot be re-entered from a position the player never
		dragged to. Standalone and Table have the identical hole and are fixed by
		the same lines: this is shared code, and the shared window is the reason
		it must be fixed here rather than in the host. ]]
	local commitLatched = false
	--[[ THE REACTIVE HALF OF `committed` (device bug round 2026-08-12, finding
		C8a, first half: "the row goes fully away but the delete/flag buttons show
		up and then animate away vertically? That's odd — the row should just go
		away").

		`doCommitAction` sets `openEdge` to the committing edge and leaves it there
		for the whole slide-off AND the whole height collapse, so the tray's reveal
		memos below held the band fully painted on a row that had already left.
		Measured on a 400px row: the band stood at its full 159px from frame 1 to
		frame 115 of the commit — 95 of those frames (1.58 s) with the row entirely
		off-screen — and was then squashed vertically as the row's height collapsed
		to 0. That squash is the "animate away vertically" in the report.

		The director's sentence IS the rule: a destructive commit carries the row
		off and leaves NOTHING standing where it was. So the reveal memos read this
		signal and go false for the commit's duration. It is a signal rather than
		the plain `committed` bool beside it because a memo has to be able to
		`use()` it; the two are written together, always, in the same call — set on
		`doCommitAction`'s destructive branch, cleared wherever `committed` is.

		NOTE FOR THE DIRECTOR GATE: `iOS.mov` does something different and richer
		here — the destructive plate EXPANDS to fill the row and the row leaves over
		it, so nothing has to vanish. That is a real feature (a per-plate stretch
		past the band width) rather than a bug fix, it is a feel decision, and it is
		not taken here. What ships is the sentence that was written down. ]]
	local committingSig = scope:own(core:signal(false))
	-- REDTEAM FIX (item 1, BLOCKER): incremented once per commit that
	-- actually starts (`doCommitAction`'s destructive branch); the two
	-- `onSettle` chains it launches capture the value at start and refuse to
	-- run past a generation that has moved on. See `doCommitAction`'s own
	-- comment for why this exists on top of `committed`/`disposed` alone.
	local commitEpoch = 0

	--[[ EVERY LIVE PIXEL AMOUNT THIS BAND IS MADE OF, built in one call
		(`row_actions_metrics.luau`, 2026-08-14). The four `controls.rowActions.*`
		theme metrics, the per-action NATURAL width signals, the band arithmetic
		those sum into, and the edit-mode gutter — all pure functions of `core`,
		`scope`, `spec.env` and the two validated ActionSpec lists, none of them
		reading a single upvalue of this closure, which is why they could leave
		when this file had to get back under the 200,000-char `Script.Source`
		WRITE cap (docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md).

		DESTRUCTURED INTO THE SAME LOCAL NAMES the ~20 readers below already use,
		at the same point in the file they were declared, so every call site is
		unchanged and nothing moved above or below anything it depends on
		(docs/lessons/later-locals-are-not-upvalues.md).

		The naturals are OWNED here and WRITTEN by `deriveNaturals` below, which
		stays: the measurement needs `controller.textAt`'s live font/size facts and
		the icon glyph, and those arrive through a presenter handoff this control
		receives, not through a theme snapshot. ]]
	local bandMetrics = rowActionsMetrics.build(
		core,
		scope,
		spec.env,
		leadingActions,
		trailingActions,
		hasEditAffordance,
		editingReadable
	)
	local metricsSig = bandMetrics.metricsSig
	local buttonPadPx = bandMetrics.buttonPadPx
	local buttonMinWidthPx = bandMetrics.buttonMinWidthPx
	local trayGapPx = bandMetrics.trayGapPx
	local rowGutterPx = bandMetrics.rowGutterPx
	local buttonChromePx = bandMetrics.buttonChromePx
	local leadingNaturals = bandMetrics.leadingNaturals
	local trailingNaturals = bandMetrics.trailingNaturals
	local leadingWidth = bandMetrics.leadingWidth
	local trailingWidth = bandMetrics.trailingWidth
	local editAffordanceShown = bandMetrics.editAffordanceShown
	local editGutterPx = bandMetrics.editGutterPx

	-- THE ONE SEAM (Tasks 4-6 write through this exclusively): however the
	-- pixel number is produced — the fallback instant snap, a spring chase, a
	-- live drag sample — it reaches the Content anchor's offsetX through here
	-- alone.
	--
	-- Task 2 (hosted): the `offset` signal write is NOT conditional. It is this
	-- engine's own state — `onPointerDown`'s `startOffset`, `settle`'s release
	-- verdict, `targetFor`, the tray-reveal memos and `dump()` all read it back
	-- — so both modes keep it. What hosted mode ADDS is the paint: the host
	-- owns the row's node (this file mounts none), so it is handed the same
	-- pixel number to translate its own row content by. One seam, so a host
	-- cannot miss a write: the spring's every step, the drag's every sample and
	-- the commit's slide-off all already come through here.
	-- fix round 1, finding 4: change-gated, mirroring `offset`'s own signal
	-- (`eq = defaultEq`, `src/core/imperative.luau`'s `node.set` — a write
	-- that does not change the value never marks the node dirty or fires its
	-- observers). `offset:set(px)` below already no-ops internally on a
	-- repeat value; `onSlide` used to fire anyway, EVERY call, because it sat
	-- outside that suppression — `resetToClosed`'s `retarget(0)` on every
	-- ORDINARY close (offset already 0 the whole time: the row never left
	-- closed) sent the host a spurious `onSlide(0)`. Reading `offset:get()`
	-- BEFORE the write is what `defaultEq` itself compares against, so this
	-- is the identical decision the signal already makes, made visible to the
	-- one caller sitting outside its notification path.
	local onSlide = if hosted ~= nil then hosted.onSlide else nil
	local function applySlide(px: number)
		local changed = px ~= offset:get()
		offset:set(px)
		-- D1: the row is home. This is the ONE seam every offset write goes
		-- through, so it is the one place that can say "back at rest" without
		-- caring which path got here — a spring's terminal write, the no-clock
		-- instant snap, or a reduced-motion placement all land on exactly 0.
		if px == 0 then
			commitLatched = false
		end
		if onSlide ~= nil and changed then
			onSlide(px)
		end
	end

	-- the same shape for the commit's height collapse: `rowHeightOverride` is
	-- the root's own `height` prop in standalone mode, and in hosted mode the
	-- host's own row-height override seam (design doc §5) — `nil` meaning "no
	-- override, back to content height" in both. Optional: a host that does not
	-- collapse rows simply never passes one.
	--
	-- fix round 1, finding 4: the identical change-gate as `applySlide` above
	-- — `resetToClosed`'s unconditional `applyCommitHeight(nil)` used to fire
	-- `onCommitHeight(nil)` on EVERY ordinary close, including one that never
	-- collapsed anything at all (`rowHeightOverride` already `nil` the whole
	-- time), which the report's own case (c) already distinguishes from the
	-- real, load-bearing `nil` a completed commit sends ("no override, back
	-- to content height" — a real transition, still forwarded because `px ~=
	-- rowHeightOverride:get()` is true exactly when the value actually moves).
	local onCommitHeight = if hosted ~= nil then hosted.onCommitHeight else nil
	local function applyCommitHeight(px: number?)
		local changed = px ~= rowHeightOverride:get()
		rowHeightOverride:set(px)
		if onCommitHeight ~= nil and changed then
			onCommitHeight(px)
		end
	end

	-- ===== the motion seam (Task 4) ==========================================
	-- `motionClock` arrives (if ever) via `bindMotion` on the contribution
	-- bundle below, once, at present time — well before any caller-driven
	-- `_open`/`_close`. `spring` is built lazily, on the first retarget that
	-- has a clock to build it from, and lives for the composite's whole life
	-- (one persistent spring drives every open/close/settle, never one per
	-- gesture): `motionClock:spring(0, "object")`, the same class name a drag
	-- flight uses (drag_registry.luau:376).
	-- `controller` arrives (if ever) via `bindController` — an EXISTING
	-- contribution field (B-VAL2; every other consumer reaches a native
	-- adapter capability through it), not a new seam. `controller.textAt(path)`
	-- is the framework's own published, live-subscribed font/size facts for a
	-- text node — the same oracle `tests/row_actions.spec.luau`'s localization
	-- test independently re-derives against. Absent (a bare mount, no
	-- presenter) means `deriveNaturals` below simply has nothing to read, so
	-- naturals stay `nil` and the width props' existing fallback stands.
	local controller: any = nil
	local motionClock: any = nil
	-- the reactive twin of `motionClock ~= nil` — see `bindMotion`'s own comment
	local motionBound = scope:own(core:signal(false))
	-- REDTEAM FIX (item 2, BLOCKER): the presenter's own `presentModal`/
	-- `dismiss`, arriving (if ever) via the new `bindPresent` contribution
	-- seam (contribution.luau; presenter.luau's `bindContribution`) — what
	-- the action menu now uses to become its OWN floating surface rather
	-- than a measured child of this row's root. `nil` (a bare mount, no
	-- presenter) means `openMenu` below simply has nowhere to present the
	-- menu onto and is a no-op, the same degrade-gracefully contract
	-- `controller`/`motionClock` already have.
	local presentModalFn: ((blueprint: any, opts: any?) -> any)? = nil
	local dismissFn: ((handle: any) -> ())? = nil
	-- Task 5: the SAME function `motionClock` itself was built from
	-- (`bindMotion`'s ADDITIVE second argument — src/input/contribution.luau,
	-- src/present/presenter.luau `c.bundle.bindMotion(motionClock, nowFn)`),
	-- the one legal time source the gesture's `drag_velocity` tracker below
	-- may read. Absent has the identical shape as `controller`/`motionClock`
	-- absent: a bare mount, no presenter.
	local nowFn: (() -> number)? = nil
	-- Task 8: `bindActionSystem`/`bindFocusGraph` — the SAME "presenter hands
	-- a composite something it cannot construct for itself" shape as
	-- `bindMotion`/`bindController` above (constitution §13: a control is
	-- handed the action system/focus graph BY THE PRESENTER, never by its
	-- consumer — see slider.luau's own `bindFocusGraph` for the canonical
	-- precedent). Absent (a bare mount, no presenter) means the Delete/Menu
	-- keyboard-and-gamepad bindings below are simply never created — the
	-- identical absent-degrades shape every other bind* seam in this file
	-- already has.
	local actionSystemRef: any = nil
	local focusGraph: any = nil
	local keysContext: any = nil
	-- Task 5: hoisted out of `deriveNaturals`'s original home below (still
	-- written there, on every `syncGeometry`) so the commit path's own
	-- `currentRect`/`currentRowWidth`/`currentRowHeight` — shared, unconditional
	-- code, reused by both the gesture and `_commitFirst` — can read it too.
	-- Task 2 (hosted): LEARNED from the first `syncGeometry` in standalone mode
	-- (this composite's own mounted root), SEEDED at build time from the host's
	-- own row path in hosted mode — where nothing this file owns ever mounts,
	-- so there is no root node to learn one from.
	local hostedPaths: HostedPaths? = if hosted ~= nil then hosted.paths else nil
	local rootPath: string? = if hostedPaths ~= nil then hostedPaths.content else nil

	-- THE PATH INDIRECTION (Task 2). Every live lookup this file makes — the
	-- row's own rect/screen rect, the focus-prefix test, a tray button's text
	-- facts, the Activate path match — asks HERE for the path instead of
	-- interpolating node ids inline. Standalone answers with exactly the
	-- strings it always did (this composite's own mounted ids under the
	-- learned `rootPath`); hosted answers with the host's own
	-- (`spec.paths`) — one seam, two fills, no second copy of any lookup.
	-- Multiple returns rather than a table: `deriveNaturals` calls this once
	-- per action per sync, and a per-call allocation there is the kind of
	-- thing the perf mission this task belongs to exists to remove.
	--
	-- `edge == nil` asks for the ROW's own path; an edge asks for that tray's
	-- own CONTAINER path (its buttons are `{trayPath}/Action:{id}` in both
	-- modes). `nil` back means "not knowable yet" (standalone, before the
	-- first sync learns `rootPath`) or "the host declared no tray on that
	-- edge" — every caller already handles a missing path.
	local function pathsOf(edge: Edge?): string?
		if edge == nil then
			return rootPath
		end
		if hostedPaths ~= nil then
			return if edge == "leading" then hostedPaths.trayLeading else hostedPaths.trayTrailing
		end
		if rootPath == nil then
			return nil
		end
		local tid = trayId(edge)
		return `{rootPath}/{tid}When/then/{tid}`
	end

	local spring: any = nil
	local function ensureSpring()
		if spring ~= nil or motionClock == nil then
			return
		end
		spring = scope:own(motionClock:spring(offset:get(), "object"))
		-- dispose pattern mirrors drag_registry.luau:388-396 (unsubscribe, then
		-- dispose the value) — one axis here instead of drag's two.
		scope:own(core:observe(spring, function()
			applySlide(spring:get())
		end))
	end

	-- THE ONE RETARGET FORK. With a clock, aim the persistent spring — the
	-- spring's own interruptibility guarantee means a retarget mid-flight
	-- continues rather than snapping. With none, write `offset` instantly
	-- (Task 3's behavior, unchanged) — the fallback a bare mount (no
	-- presenter, so `bindMotion` never ran) needs.
	local function retarget(px: number)
		if motionClock ~= nil then
			ensureSpring()
			spring:setTarget(px)
		else
			applySlide(px)
		end
	end

	local function targetFor(edge: Edge?): number
		if edge == "leading" then
			return leadingWidth:get()
		elseif edge == "trailing" then
			return -trailingWidth:get()
		end
		return 0
	end

	local function hasActions(edge: Edge): boolean
		return if edge == "leading" then leadingActions ~= nil else trailingActions ~= nil
	end

	-- Task 7: one of the two coordinator claim sites (brief: "on `_open`/
	-- gesture-reveal past the axis lock: `coordinator.claim(self)`"). Claiming
	-- BEFORE retargeting means a previously-open sibling's animated close is
	-- already under way by the time this row starts revealing, rather than
	-- racing it.
	local function open(edge: Edge)
		-- REDTEAM FIX (item 1, BLOCKER): irrevocable-commit ruling — a commit
		-- in flight owns `offset`/`openEdge`; a programmatic re-open (e.g. a
		-- caller-driven `_open` racing the tail of a commit) must not re-aim
		-- the same persistent spring out from under it any more than a fresh
		-- gesture may (`onPointerDown`'s own identical guard, below).
		if committed then
			return
		end
		if not hasActions(edge) then
			return
		end
		if coordinator ~= nil then
			coordinator.claim(api)
		end
		retarget(targetFor(edge))
		openEdge:set(edge)
	end

	-- Task 7: releases this row's own coordinator claim unconditionally
	-- (idempotent — a no-op when this row was never the claimed one, e.g. a
	-- row that settled back to closed without ever crossing the axis lock).
	-- Every path that ends a row's open state — a gesture settling closed, a
	-- programmatic `_close`, `handleCancel`, an `outsideDismiss`/scroll close
	-- routed through the coordinator itself — runs through this one function,
	-- so the coordinator's bookkeeping never drifts from what is actually
	-- painted.
	--
	-- REDTEAM FIX (item 5, MAJOR): a completed DESTRUCTIVE commit's own
	-- collapse sequence (`doCommitAction` below) writes `rowHeightOverride`
	-- and sets `committed = true`, but nothing ever reset either — a repro
	-- found the row permanently pinned at 0 height and permanently
	-- uncommittable forever afterward whenever the OWNER did not actually
	-- remove the row instance following the commit (a throwing `onAction`
	-- that never mutated the data, or a caller that treats a destructive
	-- action as reversible/undo-able rather than instance-destroying) — a
	-- "phantom row": visually collapsed to nothing, its trays and menu still
	-- fully mounted underneath, unable to ever open or commit again.
	--
	-- REDTEAM FIX (item 1, BLOCKER; final-review-findings.md; director
	-- ruling — a STARTED destructive commit is IRREVOCABLE, iOS-style: it
	-- completes — slide-off, collapse, fire exactly once — regardless of
	-- close()/claim/scroll/outside-tap/Cancel arriving mid-flight). Split
	-- into two functions rather than one more `if committed then` patch at
	-- each of close()'s own call sites (a coordinator claiming a sibling
	-- away, a scroll, an outside tap, `handleCancel`, `dispose` — every one
	-- of which already funnels through `close()`, the paragraph above):
	-- `resetToClosed()` is the actual reset body, unconditional — the ONE
	-- place allowed to clear `committed` back to false, called ONLY from
	-- `close()` itself (the ordinary, non-commit path, where `committed` is
	-- already false so the guard below is a no-op) and from the commit
	-- chain's OWN natural completion (`doCommitAction`'s final
	-- `collapseThen` callback, which bypasses `close()` entirely to reach
	-- this directly). `close()` is what every OTHER caller in this file
	-- still calls, and it is now a no-op for the WHOLE reset — animation,
	-- `openEdge`, `rowHeightOverride`, coordinator release — while a commit
	-- owns the row: bookkeeping that does not touch `committed` (e.g. a
	-- sibling's `_closeMenu()`, called separately by the coordinator, never
	-- through here) is unaffected, exactly the ruling's "bookkeeping...may
	-- still run" carve-out.
	local function resetToClosed()
		openEdge:set(nil)
		retarget(0)
		applyCommitHeight(nil)
		committed = false
		committingSig:set(false)
		if coordinator ~= nil then
			coordinator.release(api)
		end
	end

	--[[ THE POST-COMMIT RESTORE, DEFERRED BY ONE SYNC (device bug round
		2026-08-12, finding C8a, second half: "Then the row reappears quickly before
		the delete happens").

		The commit chain's last step fired `onAction` and then called
		`resetToClosed()` — which puts the height override back to `nil` (the row is
		instantly full height again) and `retarget(0)` (the row springs home from a
		whole row width away, over ~65 frames). Measured on a 400px row: at the fire
		frame the row went 0px -> 48px tall and travelled -400 -> -252 in four
		frames. A whole row, repainted and flying back across the screen, BEFORE the
		owner's `rows:set(...)` had reached the diff that removes it.

		Splitting the reset in two is what fixes it, and it costs nothing:

		  * `finishCommit()` runs the BOOKKEEPING immediately — `openEdge`,
		    `committed`/`committingSig`, the coordinator release. All of it is state
		    nobody paints.
		  * the PAINT (`applySlide(0)` + `applyCommitHeight(nil)`) is deferred to the
		    next `syncGeometry`, and it is a SNAP, never a flight: `spring:snap(0)`
		    is a placement, not an arrival (motion.luau), so it fires no stray
		    settle.

		A row whose owner really did remove it is disposed before that sync ever
		runs, so it never repaints at all — which is the whole point. A row whose
		owner did NOT remove it (the "phantom row" `resetToClosed`'s own comment
		describes, redteam item 5) is back to a normal, openable, full-height row one
		sync later instead of never — the same guarantee that fix bought, delivered
		without the visible return flight. ]]
	local restorePending = false
	local function finishCommit()
		openEdge:set(nil)
		committed = false
		committingSig:set(false)
		if coordinator ~= nil then
			coordinator.release(api)
		end
		restorePending = true
	end

	-- ...and the deferred half, drained by `syncGeometry` below (the one per-frame
	-- hook this composite has in BOTH modes: the presenter calls it on the
	-- contribution, a host calls `engine.syncGeometry()` bare).
	local function drainPostCommitRestore()
		if not restorePending then
			return
		end
		restorePending = false
		if spring ~= nil then
			spring:snap(0)
		end
		applySlide(0)
		applyCommitHeight(nil)
	end

	local function close()
		if committed then
			-- irrevocable: a commit in flight owns `offset`/`rowHeightOverride`
			-- until its own onSettle chain reaches the end on its own —
			-- see `resetToClosed`'s comment above for who may still clear this.
			return
		end
		resetToClosed()
	end

	-- Task 8's own menu state (own state; independent of `openEdge`/`offset`
	-- above — the menu never reveals a tray). Declared HERE, ahead of
	-- `doCommitAction` below (rather than down by `openMenu`/`toggleMenu`,
	-- Task 8's original home for all four), so that function can read/call
	-- `menuOpen`/`closeMenu` too (redteam item 7, MAJOR — see the big
	-- comment on `doCommitAction`'s own use of it) — the same "Luau locals
	-- are only visible to code following their own declaration" constraint
	-- `committed` already ran into (item 5's own comment above `local
	-- committed`).
	--
	-- REDTEAM FIX (item 2, BLOCKER — director ruling: floating presenter
	-- surface). `menuHandle` is the presentModal handle for the menu's OWN
	-- surface (nil while closed); `menuOx`/`menuOy` are its live anchor
	-- position, written by `syncGeometry` below from this row's own solved
	-- rect (the full design rationale sits with the surface's construction,
	-- further down at "Task 8: the action menu"). `closeMenu` has to live
	-- here too, same as `menuOpen` always has, so `doCommitAction` below can
	-- call it — its body now tears down a REAL presented surface rather
	-- than merely flipping a signal a permanently-mounted `UI.When` reads.
	local menuOpen = scope:own(core:signal(false))
	local menuHandle: any = nil
	local menuOx = scope:own(core:signal(0))
	--[[ `menuOy` IS NOT ALWAYS A PIXEL COUNT (ruling 4, director 2026-08-13).
		Paired with `menuAnchorKind` below, it spells BOTH placements:

		  * `topLeft` + a plain number — the menu's TOP at that y (the default,
		    "just below the trigger", unchanged);
		  * `bottomLeft` + `{ scale = -1, offset = <trigger top> }` — the menu's
		    BOTTOM at the trigger's top, i.e. FLIPPED above it.

		The flipped form is a FRACTION of the anchor's inner height (`solver.luau`
		`offsetPx`, ADR-0022 row SF-P5) precisely so this file never has to know
		that height: a `bottomLeft` child lands at `(innerH - h) + oy`, so
		`oy = trigger.y - innerH` puts its bottom edge exactly on the trigger's top
		WITHOUT this file measuring the menu at all. Spelling it as a scale lets the
		solver supply `innerH`, which is the number that is actually true. ]]
	local menuOy = scope:own(core:signal(0 :: any))
	local menuAnchorKind = scope:own(core:signal("topLeft"))
	-- `menuOpen:set(false)` runs FIRST, BEFORE `dismissFn(handle)` — found
	-- live (a real bug, not a style choice): `dismissFn` synchronously
	-- restores focus (`focus_graph.luau`'s own `restoreStack`), which fires
	-- this row's OWN focus-change observer (`bindFocusGraph` below,
	-- `core:observe(graph.focused, syncKeysEnabled)`) DURING the dismiss
	-- call, before `closeMenu` would otherwise get a chance to update
	-- `menuOpen`. `pathInsideRow`'s own `menuOpen:get()` branch has to see
	-- the truth at that exact moment — restoring focus back onto this row's
	-- own content is harmless either way (still a path-prefix match), but
	-- `openMenu`'s mirror-image ordering below is NOT harmless (see its own
	-- comment), so both are ordered the same way on principle: never let a
	-- side effect that reads `menuOpen` run before the write it needs to see.
	local function closeMenu()
		menuOpen:set(false)
		if menuHandle ~= nil then
			local handle = menuHandle
			menuHandle = nil
			if dismissFn ~= nil then
				dismissFn(handle)
			end
		end
	end

	-- ===== Task 5: the commit path (shared by the gesture and `_commitFirst`) ===
	-- Live geometry read through `controller` (bound the same absent-degrades
	-- way `deriveNaturals` already reads `controller.textAt` — Task 4), never
	-- cached: a row's width/height are facts about what actually solved, not
	-- something this control could compute for itself.
	local function currentRect(): any
		local path = pathsOf()
		if controller == nil or path == nil then
			return nil
		end
		return controller.rectOf(path)
	end
	local function currentRowWidth(): number
		local r = currentRect()
		return if r ~= nil then r.w else 0
	end
	local function currentRowHeight(): number
		local r = currentRect()
		return if r ~= nil then r.h else 0
	end

	local function firstActionFor(edge: Edge): ActionSpec?
		local list = if edge == "leading" then leadingActions else trailingActions
		if list == nil or #list == 0 then
			return nil
		end
		return list[1]
	end

	-- the collapse spring: a SECOND, independent `"object"`-class value from
	-- the same family the offset spring already rides (see the big comment
	-- above `ensureSpring`) — a different signal (row height, not offsetX),
	-- built lazily on the FIRST commit a row ever makes and reused (never
	-- rebuilt) by every commit after — see item 4's fix below for why reuse
	-- needs its own re-seed step.
	local collapseSpring: any = nil
	-- REDTEAM FIX (item 4, MINOR; final-review-findings.md). A row that
	-- survives its first destructive commit (the owner kept it alive — see
	-- `resetToClosed`'s own "phantom row" comment) can be committed again,
	-- and the SECOND collapse silently never moved: `collapseSpring` already
	-- existed from the first commit, so the `collapseSpring ~= nil` guard
	-- returned early WITHOUT re-seeding either the spring's own resting
	-- value (still 0, exactly where the first collapse left it settled) or
	-- `rowHeightOverride` (already `nil`, i.e. painting the row at its full
	-- content-sized height again, since `resetToClosed` reset it after the
	-- first commit finished) back to `initial`. `collapseThen` then aimed
	-- this already-at-0 spring at 0 again — no motion, no visible collapse,
	-- yet the chain still completed normally (probe: min height stayed 48,
	-- never dipped toward 0). `spring:snap(v)` (motion.luau: "come to rest
	-- on `v` right now... a PLACEMENT, not an arrival" — no `onSettle` fan-
	-- out, so this never fires a stray callback) puts a REUSED spring back
	-- at the new starting height before this collapse aims it at 0, exactly
	-- what building a fresh spring already did for the first commit for
	-- free. `rowHeightOverride:set(initial)` now runs unconditionally
	-- (moved out of the "build" branch) for the identical reason: the paint
	-- has to be seeded before the first step on EVERY commit, not only the
	-- first ever.
	local function ensureCollapseSpring(initial: number)
		if motionClock == nil then
			return
		end
		if collapseSpring == nil then
			collapseSpring = scope:own(motionClock:spring(initial, "object"))
			scope:own(core:observe(collapseSpring, function()
				applyCommitHeight(collapseSpring:get())
			end))
		else
			collapseSpring:snap(initial)
		end
		applyCommitHeight(initial) -- seed the paint before the first step
	end

	local function collapseThen(fromHeight: number, onArrive: () -> ())
		if motionClock ~= nil then
			ensureCollapseSpring(fromHeight)
			local unsub: (() -> ())? = nil
			unsub = collapseSpring:onSettle(function()
				if unsub ~= nil then
					unsub()
				end
				onArrive()
			end)
			collapseSpring:setTarget(0)
		else
			applyCommitHeight(0)
			onArrive()
		end
	end

	-- `committed` itself is declared earlier (see the comment there) so
	-- `close()`/`resetToClosed()`, defined above this point, can read/reset
	-- it too; this flag makes "at most one commit in flight" true even if
	-- something calls the commit path twice, on top of the exactly-once
	-- guarantee `collapseThen`'s own self-unsubscribing
	-- already gives each individual spring chain, and — since the director's
	-- irrevocable-commit ruling — is now also the ONE thing that makes a
	-- commit uncancellable: see `close()`'s own guard and `resetToClosed`'s
	-- comment above it.

	-- THE ONE COMMIT PATH (brief: `_commitFirst`; generalized below for Task
	-- 8, whose keyboard Delete and menu-Activate entries fire a SPECIFIC
	-- action, not necessarily the edge's first). Slides `content` fully
	-- off-screen, collapses the row's own height to 0 over the same spring
	-- family, fires `action` exactly once (quarantined — a throw still
	-- closes, never refires), then runs the same bookkeeping `_close()`
	-- already does.
	--
	-- THE GUARD (spec docs/plans/row-actions.md: "Commit racing a data
	-- refresh (row rebuilt under the gesture) -> gesture cancels; never fire
	-- onAction for a row whose key no longer matches"). From THIS composite's
	-- own point of view, "the row was rebuilt" always manifests as its own
	-- `dispose()`: a keyed diff destroys the old row_actions instance and
	-- builds a fresh one for the new key, it never mutates one in place. The
	-- `disposed` check below, plus the emergent guarantee disposing `scope`
	-- already gives (a disposed MotionValue clears its `onSettle`
	-- subscribers — motion.luau `value.dispose`: "table.clear(subs)" — so a
	-- slide/collapse in flight when disposal lands never reaches its next
	-- `onArrive` at all), together mean `action.onAction` cannot fire for a
	-- row this composite no longer owns.
	local function doCommitAction(edge: Edge, action: ActionSpec, offscreenTarget: number): boolean
		-- REDTEAM FIX (item 7, MAJOR): the ORIGINAL "menu-open carve-out"
		-- (see the big comment above `ROW_ACTIONS_KEY_PRIORITY` further down)
		-- only ever guarded the KEYBOARD Delete entry point — a full-swipe
		-- POINTER gesture committing on this SAME row (same-row: this row's
		-- own menu is open when its own tray gesture commits) was never
		-- gated at all, stranding the menu (and its `transientScope` focus
		-- trap) on top of a row that had just slid off and collapsed out
		-- from under it. Closing the menu FIRST, unconditionally, at the one
		-- root every commit path (gesture, tray tap, keyboard Delete, menu
		-- Activate itself) already funnels through, is what keeps it from
		-- ever outliving the row state it was popped over. (The cross-row
		-- half of this same finding — another row's coordinator CLAIM
		-- leaving THIS row's menu armed while ITS tray closes — is fixed at
		-- `row_actions.newCoordinator`'s own `claim`, below.)
		if menuOpen:get() then
			closeMenu()
		end
		-- RULING (director-delegated, final-review-findings.md): "The
		-- non-destructive branch...must sit below the committed guard." A
		-- commit already in flight (destructive, irrevocable) owns this row
		-- until its own chain completes — nothing else, destructive or not,
		-- may commit on top of it (item 1's own "does not allow a new
		-- gesture/commit on the row" requirement; `onPointerDown` below
		-- separately refuses a brand-new GESTURE for the identical reason).
		-- Checked FIRST, ahead of the role branch below, so a non-destructive
		-- action reached some other way while committed (menu Activate,
		-- keyboard) can never race the collapse either.
		if committed then
			return false
		end
		--[[ THE DELETE GATE — `rowDeletable`, the ONE place it is evaluated
			(architecture gate, 2026-08-14; director ruling, parity round 3: "both
			routes gate the same funnel... with one predicate evaluated in one
			place").

			WHY HERE AND NOWHERE ELSE. Five affordances reach a destructive commit —
			the full-swipe gesture (`settleTo` -> `doCommit`), a tap on the revealed
			tray's own Delete (`fireTrayAction`), the edit-mode ⊖ (`handleActivate`
			-> `commitDestructive`), the Delete/Backspace key (the IAS action, same
			`commitDestructive`) and the action menu's destructive row
			(`menuHandleActivate`) — and every one of them funnels through THIS
			function. `table.luau:1015-1030` records what a per-affordance guard
			costs: "a third, wholly separate way to start the identical reorder"
			that missed one. One gate at the funnel cannot be missed by a sixth.

			DESTRUCTIVE ONLY. The predicate answers "may this row be DELETED"; a
			protected row still flags, archives and pins exactly as before, so the
			non-destructive branch below must not see this at all.

			ponytail: the AFFORDANCE is not hidden — a protected row still paints its
			tray Delete and its ⊖, and they do nothing. Hiding them needs the verdict
			as a REACTIVE fact (this is a thunk, so no memo can track it), and the
			already-shipped spelling for removing the affordance is the one the
			parity doc names: return no destructive action from `spec.rowActions` for
			that row, which takes the tray button, the ⊖, the menu row and the key
			arming with it. Upgrade path: accept a `Readable<boolean>` here and let
			`hasEditAffordance`/`hasDestructive` read it. ]]
		if action.role == "destructive" and spec.deletable ~= nil and spec.deletable() == false then
			return false
		end
		-- REDTEAM FIX (item 4, MAJOR — director ruling, SwiftUI behavior): a
		-- full swipe commits differently by role. A DESTRUCTIVE first action
		-- keeps the full slide-off + collapse sequence below unchanged. A
		-- NON-destructive first action fires immediately (quarantined, the
		-- SAME guarantee `fireTrayAction` above gives a direct tray-button
		-- tap) and the row springs back to CLOSED — never sliding off-screen,
		-- never collapsing height at all; a full swipe on a "Flag"/"Archive"-
		-- shaped action must look and feel exactly like tapping that same
		-- button in the revealed tray, not like a deletion. `committed` is
		-- deliberately left untouched on this branch: this is not "the row
		-- is being removed" the way a destructive commit is, so a later full
		-- swipe (or tray tap) on the same still-alive row must be able to
		-- fire again, exactly like a direct tray-button tap already can.
		if action.role ~= "destructive" then
			-- D1: this branch fires and springs home from wherever the full
			-- swipe reached — a distance well past the commit threshold. Latched
			-- for the same reason the destructive branch is: until the row is
			-- actually back at 0, a new gesture would inherit that position as
			-- its own starting point and re-commit on release.
			commitLatched = true
			pcall(action.onAction)
			close()
			return true
		end
		committed = true
		-- C8a (device round 2026-08-12): the reactive twin, read by the tray reveal
		-- memos — the row leaves and nothing stays standing behind it. See
		-- `committingSig`'s own comment where it is declared.
		committingSig:set(true)
		commitLatched = true
		-- REDTEAM FIX (item 1, BLOCKER): a commit "generation" counter,
		-- captured by both `onSettle` chains below (belt, on top of the
		-- `committed`/`disposed` guards this whole function and `close()`
		-- already carry): a chain from a PREVIOUS commit generation — which
		-- should be structurally unreachable now that `committed` blocks a
		-- second commit and `close()` can no longer clear it mid-flight —
		-- must still never fire a stale callback if that invariant is ever
		-- wrong elsewhere. Cheap (one integer compare) and makes the
		-- invariant local to the two places that actually need it, rather
		-- than trusted from a distance.
		commitEpoch += 1
		local myEpoch = commitEpoch
		openEdge:set(edge)
		--[[ THE TWO FLIGHTS RUN TOGETHER, NOT ONE AFTER THE OTHER ───────────────
			Director device round 2026-08-13: "there's an odd pause once the row
			goes away before the others animate up after i swipe and click delete."

			MEASURED, frame by frame on the playlist example at 60fps. The slide
			carried the row off-screen over frames 1-38 — it was completely out of
			view by about frame 20 — and then NOTHING in the tree moved for 27
			frames (~0.45s). Only at frame 65 did the height collapse begin and the
			rows below start closing the gap. Counted from the moment the row
			actually disappeared, the list sat still with a hole in it for the
			better part of a second.

			THE CAUSE WAS SERIALISATION ON A SETTLE. The chain was slide-off ->
			collapse -> fire, handed off on `spring:onSettle` — the NUMERIC settle,
			`|x - target| <= 1e-3 AND |v| <= 1e-3` (spring.luau `DEFAULT_EPS`).
			`spring.luau`'s own header warns about exactly this: "position-domain
			springs (hundreds of px) settle a few frames after they visually arrive
			— which is exactly why perceptual arrival is a RADIUS, not this epsilon
			(chase.luau)". This was the largest position-domain spring in the
			library, a whole row width, so the visible half of the animation waited
			on an invisible object converging through its last thousandth of a pixel.

			WHY CONCURRENT RATHER THAN A RADIUS. A perceptual-arrival radius was
			built first and it did fix the timing — rows started moving at frame 23
			instead of 65 — but it had to observe the spring's VALUE to see the
			radius, which meant `onArrive` (and through it the consumer's
			`onAction`) fired from inside a core commit. That is a real hazard, not
			a theoretical one: `presenter.withAnimation` refuses outright from
			inside a commit, so a consumer animating its own deletion started
			raising "nothing flushed, so it could not force its own commit". Two
			concurrent flights need no observer at all — the collapse keeps its own
			plain `onSettle`, which motion.luau fires from its `post()` phase,
			after the write and outside the commit, exactly as this code always did.

			It is also the better animation. iOS collapses the row WHILE it slides;
			the gap closing is what tells you the deletion took. Nothing about the
			C8a ruling changes: the tray still unmounts the instant the commit
			starts (`committingSig`), and the row's paint is still not put back
			before the owner's removal lands (`finishCommit`).

			`onAction` now chains off the COLLAPSE, which is the correct one of the
			two to wait for — the row must genuinely be at zero height before the
			owner removes it, or the rows below jump the last few pixels. The slide
			is aimed and left to fly; nothing waits on it.
		]]
		retarget(offscreenTarget)
		collapseThen(currentRowHeight(), function()
			if disposed or commitEpoch ~= myEpoch then
				return
			end
			-- QUARANTINED (constitution): the ONE user callback this
			-- composite ever fires on a caller's behalf. A throw must
			-- not skip `finishCommit()` below, nor fire a second time —
			-- `committed` already forbids a second commit, and this
			-- whole chain only ever runs once per row.
			pcall(action.onAction)
			-- the ONE place allowed to clear `committed` mid-flight (see
			-- `resetToClosed`'s own comment above `close()`): this IS the
			-- commit's own natural completion, not an external cancel —
			-- `close()` itself would no-op here since `committed` is
			-- still true. C8a (device round 2026-08-12): `finishCommit`
			-- rather than `resetToClosed`, so the row's PAINT is not put
			-- back — full height, flying home from a row width away —
			-- before the owner's own removal has landed. See its comment
			-- above `close()`.
			finishCommit()
		end)
		return true
	end

	-- the gesture/`_commitFirst` shape: the edge's FIRST declared action,
	-- whichever one that is — unchanged behavior from Tasks 5-7, now
	-- expressed as a thin wrapper over the generalized seam above.
	local function doCommit(edge: Edge, offscreenTarget: number): boolean
		local action = firstActionFor(edge)
		if action == nil then
			return false
		end
		return doCommitAction(edge, action, offscreenTarget)
	end

	-- Task 5: the drag-release verdict's commit branch (row_actions_state.
	-- settle) routes through here.
	local function settleTo(verdict: row_actions_state.Verdict)
		if verdict.commit and verdict.edge ~= nil then
			if doCommit(verdict.edge, verdict.target) then
				return
			end
			--[[ REACHABLE NOW, AND ALREADY HANDLED (`rowDeletable`, 2026-08-14).
				This used to say "unreachable in practice"; the delete gate in
				`doCommitAction` makes a refused commit real, so the fall-through
				below is what a refused full swipe actually takes — and it aims at
				`verdict.target`, which for a full swipe is ±the whole ROW WIDTH.

				That would be wrong, and it is not what happens: `openEdge` is set to
				the swiped edge here, and `syncGeometry`'s open-edge re-assert (search
				`openEdge:get() == "trailing"`) re-aims the spring at the TRAY width on
				the very next sync. The row therefore settles revealed, on screen,
				exactly where an ordinary open swipe leaves it.

				An explicit `retarget(targetFor(verdict.edge))` was written here first
				and then DELETED: it could not be mutation-proved, because that
				re-assert already produces the identical settle (measured — the row
				travels 91px either way, the tray's own width). A guard nothing can
				redden is a guard that will rot. ]]
		end
		openEdge:set(verdict.edge)
		retarget(verdict.target)
	end

	local function commitFirst(edge: Edge): boolean
		local rowW = currentRowWidth()
		local target = if edge == "leading" then rowW else -rowW
		return doCommit(edge, target)
	end

	-- ===== Task 8: destructive-action lookup (Delete key + menu Activate) ===
	-- "the first `destructive` action (search trailing list first, then
	-- leading)" (brief) — deliberately NOT `firstActionFor` above: a
	-- destructive action is not guaranteed to sit at index 1 of its own
	-- edge's list (a row could legally declare `{ "flag", "delete" }`), so
	-- Delete has to find the SPECIFIC destructive entry rather than assume
	-- position. Static lookup (actions never change post-build), searched
	-- fresh on every press — cheap, and there is no natural place to cache
	-- it that would not also have to invalidate on nothing (it never
	-- changes).
	local function firstDestructiveEntry(): { edge: Edge, action: ActionSpec }?
		for _, action in trailingActions or {} do
			if action.role == "destructive" then
				return { edge = "trailing" :: Edge, action = action }
			end
		end
		for _, action in leadingActions or {} do
			if action.role == "destructive" then
				return { edge = "leading" :: Edge, action = action }
			end
		end
		return nil
	end

	-- keyboard Delete's entry point, and the menu's own commit path for a
	-- destructive item (brief: "a destructive action from the menu runs the
	-- same _commitFirst path — slide-off+collapse, not a bare callback"):
	-- the SAME slide-off/collapse/quarantine/close sequence a full-swipe
	-- commit uses, generalized via `doCommitAction` above rather than
	-- `commitFirst`, because the destructive entry is not necessarily the
	-- edge's first action (see `firstDestructiveEntry`'s own comment).
	local function commitDestructive(): boolean
		local entry = firstDestructiveEntry()
		if entry == nil then
			return false
		end
		local rowW = currentRowWidth()
		local target = if entry.edge == "leading" then rowW else -rowW
		return doCommitAction(entry.edge, entry.action, target)
	end

	-- ===== Task 8: the action menu (Shift+Return desktop / ButtonX gamepad) =
	-- Own state; independent of `openEdge`/`offset` above — the menu never
	-- reveals a tray, it is a floating popup listing every action (brief:
	-- "PopupButton-pattern panel"). `menuOpen`/`menuHandle`/`closeMenu`
	-- themselves are declared earlier (see the comment there) so
	-- `doCommitAction` above, defined before this point, can also read/call
	-- them.
	--
	-- REDTEAM FIX (item 2, BLOCKER; director ruling — re-architect onto the
	-- presenter's own surface machinery). The menu USED TO be a permanently
	-- mounted `UI.Anchor` inside this row's OWN root (a measured child of
	-- the row's content-sized Anchor): opening it made the row's own solved
	-- height grow (48px -> 73px in the redteam's own repro) and pushed
	-- every following row down — defeating Table's authored, arithmetic
	-- `rowHeight` (redteam-findings.md item 2). The fix-wave's own
	-- investigation into item 2 (redteam-fixwave-report.md) found NO
	-- solver-level "escapes measure" primitive anywhere in `solver.luau` —
	-- the union-bbox measure an Anchor/ZStack runs every child through has
	-- no exemption, and `popup_button.luau`'s own escape (a `height = fill`
	-- root, excluded from a STACK's own Pass-1 `mainSum`) cannot transfer:
	-- Table drives row height ARITHMETICALLY (`{ type = "fixed", px = ... }`,
	-- never `fill`), so that one lever never engages.
	--
	-- FIXED HERE by never giving the menu a node in this row's tree AT ALL.
	-- `openMenu` presents it as its own SIBLING top-level surface via
	-- `presentModal` (arriving through the new `bindPresent` contribution
	-- seam — contribution.luau, presenter.luau's `bindContribution`, the
	-- same "hand a control what it cannot construct for itself" shape
	-- `bindMotion`/`bindController`/`bindFocusGraph` already establish). A
	-- presented handle's blueprint is never a descendant of ANY row's own
	-- mounted tree, so it cannot contribute one pixel to any row's measured
	-- box — not "a smaller number," simply never in the walk. THE
	-- ZERO-INFLATION REGRESSION TEST (`tests/row_actions_input.spec.luau`,
	-- "menu open contributes nothing to row/list measure") is the redteam's
	-- own repro numbers turned into an assertion: sibling row y is
	-- byte-identical open vs closed, VStack and Table both.
	--
	-- WHY `presentModal`, NOT plain `present()` (this is the framework's
	-- OWN documented constraint, not a guess — presenter.luau's own
	-- `contextPriority` comment: "two focus-driven base screens would
	-- double-deliver on the shared focus graph... present the second one
	-- as a modal instead"). Two `kind == "screen"` surfaces share
	-- `BASE_SCREEN_PRIORITY`; a base screen presented with `sinkNavigation`
	-- (this row's own OWN presenting screen, in every existing test) already
	-- sinks at that priority, and a SECOND sinking screen at the identical
	-- priority would double-fire Navigate/Activate/Cancel on every key —
	-- exactly what stacking the menu as a second base screen would risk.
	-- `presentModal` instead stacks at `topModalPriority() + 500`, strictly
	-- above any base screen, so IAS delivers to it first with no double
	-- delivery — the collision-free primitive, and the one the framework's
	-- own comment names as the fix for this exact shape of problem.
	--
	-- TWO THINGS COME FREE FROM `presentModal` THAT THE OLD DESIGN HAD TO
	-- HAND-WIRE, for LESS code than before, not more:
	--   (1) a focus TRAP — `focus_graph.luau`'s own `pushScope` traps
	--       navigation whenever `kind == "modal"` — replacing the deleted
	--       `transientScope` contribution field (and the fragile "permanent
	--       anchor split from the lazily-mounted rows" workaround its own
	--       comment used to require, so `syncTransientScopes` would still
	--       find a live contribution on the SAME refresh `menuOpen` went
	--       false — moot now: the whole surface unmounts atomically with
	--       `dismiss`, there is no separate "gate a child" step to race).
	--   (2) a focus RESTORE on ANY dismiss (ours or the presenter's own) —
	--       `pushScope`'s own `restoreStack`, recorded automatically at
	--       present time and popped automatically by `removeScope` inside
	--       `presenter.dismiss` — matching "Cancel... restores focus"
	--       (Task 8's own tests) with zero bespoke bookkeeping.
	--
	-- `outsideTapCancel = true` and `cancelPolicy = "none"` — corrected
	-- (this comment used to claim BOTH were refused; only `cancelPolicy`
	-- is). `cancelPolicy = "none"` refuses the modal's own native
	-- Cancel-dismiss branch, so gamepad/keyboard Cancel is decided
	-- EXCLUSIVELY by `menuHandleCancel` below (offered to the focused
	-- contribution before any surface-level default either way, so this is
	-- belt-and-suspenders, not load-bearing — but it keeps Cancel on the
	-- SAME explicit `closeMenu()` path as Activate). Outside-tap dismissal,
	-- by contrast, is NOT hand-wired: `outsideTapCancel = true` is the
	-- modal's own NATIVE mechanism (`presenter.luau`'s `applyOutsideOutcome`)
	-- doing the dismiss itself — a real correction from an earlier attempt
	-- that tried to reuse the row's own contribution-level `outsideDismiss`
	-- field for the menu too (the ORIGINAL, pre-item-2 menu's own shape):
	-- that field's catcher (`presenter.luau`'s `syncPopupCatcher`) is built
	-- for a popup living inside a plain, non-exclusive screen, and its own
	-- comment says so — "an exclusive surface suppresses the popup catcher"
	-- — so it silently never fired once the menu became a `presentModal`
	-- (caught live: a tap outside the open menu had no effect at all).
	-- `menuHandle`'s own `onFeedback` subscription (`openMenu` below) is
	-- what keeps `menuOpen`/`menuHandle` in sync with THIS dismiss path,
	-- since it runs entirely inside the presenter, never through
	-- `closeMenu`.
	--
	-- `scrim = "none"`: STILL CATCHING (the presenter's own doc: "'none' is
	-- fully transparent but STILL catching") — an outside tap closes the
	-- menu and is consumed, never clicking through to a sibling row — but
	-- never dims the row list behind it, which a real scrim would: a
	-- row-action menu is a lightweight popover, not a modal sheet.
	--
	-- `rootPolicy = "edgeToEdge"`: the SAME choice `presenter.luau`'s own
	-- `presentDisclosure` (the disclose-plate mechanism — the existing,
	-- shipped precedent for "a presenter-owned surface anchored to
	-- another surface's live rect") makes, for the identical reason its
	-- own comment gives: "window space... the SAME coordinates
	-- `screenRectOf` answers in" — an inset root (the default
	-- `"coreSafeContent"`) would offset the menu's own Anchor from this
	-- row's true window-space rect by whatever safe-area/inset padding
	-- happens to apply on this platform.
	local MENU_SURFACE_ID = "RowActionsMenu-" .. id
	local MENU_ROOT_ID = "Menu"
	--[[ THE ROW RECIPE IS SHARED NOW (navigation-and-menus D2, director call §5).
		Both metric names and the per-row body moved to `src/controls/menu_recipe
		.luau`, which `popup_button` and the freestanding `newMenu` render from too
		— *"three copies of a menu row is how the icon-first ruling gets silently
		lost"*. The ruling itself (a menu row KEEPS its label; icon-first is the
		TRAY's inversion; deliberately no `prefer`) travelled with it and is
		restated in that file's header rather than re-derived.

		THE PROPS ARE IDENTICAL, deliberately: two shipped cases pin this tree.
		`row_actions_input.spec`'s flip prediction is exact only while `MenuRows`
		stays "a padding-free VStack of fixed-height rows", and its large-text case
		reads `controller.textAt(<row path>)` for the row's OWN label — both of
		which a reshaped row would break silently. ]]
	local MENU_ROW_HEIGHT = menuRecipe.ROW_HEIGHT
	local MENU_ROW_GAP = menuRecipe.ROW_GAP
	local function buildMenuRows(): { any }
		local rows = {}
		for _, entry in menuItemsOrdered do
			table.insert(
				rows,
				menuRecipe.row(UI, {
					id = "Action:" .. entry.action.id,
					label = entry.action.label,
					icon = entry.action.icon,
					role = entry.action.role,
					height = MENU_ROW_HEIGHT,
				})
			)
		end
		return rows
	end

	-- computed once here (NOT the tray's own `idPattern` below — this
	-- block runs before that declaration; a fresh `patternEscape` call
	-- per Activate would be harmless but there is no reason to pay it
	-- twice when a closure can just capture the escaped id once). Rides
	-- `MENU_SURFACE_ID` (this control's OWN presented screen's id), not the
	-- row's `id`, now that the menu is a sibling surface with its own root.
	local menuIdPattern = patternEscape(MENU_SURFACE_ID)
	local function findMenuAction(aid: string): (Edge?, ActionSpec?)
		if actionsById.leading[aid] ~= nil then
			return "leading", actionsById.leading[aid]
		end
		if actionsById.trailing[aid] ~= nil then
			return "trailing", actionsById.trailing[aid]
		end
		return nil, nil
	end

	-- routes a presenter/tap/keyboard/gamepad Activate landing inside the
	-- MENU's own surface; returns true when the path was ours. A
	-- destructive item runs through `doCommitAction` (the FULL slide-off
	-- + collapse sequence, brief: "not a bare callback"); anything else
	-- is a quarantined, exactly-once callback — either way the menu
	-- closes (and its surface dismisses) first, so the collapse (if any)
	-- plays out on a row whose own menu is already gone.
	local function menuHandleActivate(path: string, _meta: any?): boolean
		local aid = string.match(path, `/{menuIdPattern}/{MENU_ROOT_ID}/MenuRows/Action:(.+)$`)
		if aid == nil then
			return false
		end
		local edge, action = findMenuAction(aid)
		if edge == nil or action == nil then
			return false
		end
		closeMenu()
		if action.role == "destructive" then
			local rowW = currentRowWidth()
			local target = if edge == "leading" then rowW else -rowW
			doCommitAction(edge, action, target)
		else
			pcall(action.onAction)
		end
		return true
	end

	-- gamepad ButtonB / the shared handleCancel offer (matrix §B
	-- PopupButton parity): closes the menu without firing anything.
	-- `cancelPolicy = "none"` on the modal's own present opts (below) means
	-- this is the ONLY thing that ever answers Cancel while the menu is up
	-- — offered to the focused contribution before any surface-level
	-- default (presenter.luau's own documented ordering), so it always
	-- wins over the modal's own (refused) native Cancel routing.
	local function menuHandleCancel(_focusedPath: string?): boolean
		if menuOpen:get() then
			closeMenu()
			return true
		end
		return false
	end

	--[[ THE MENU'S OWN SOLVED HEIGHT, PREDICTED (ruling 4). It is a prediction
		only in name: `MenuRows` is a plain VStack with no padding whose every child
		declares `height = { type = "fixed", px = MENU_ROW_HEIGHT }`, so its solved
		height is exactly `n * rowHeight + (n - 1) * gap` — and both metric names are
		resolved HERE against `metricsSig`, the same live theme snapshot the solver
		resolves them against when it lays the menu out. The two cannot disagree
		about a themed or text-scaled row height, which is the failure this would
		otherwise have (`table.luau`'s `rowGapPx` makes the identical argument for
		the identical reason).

		`row_actions_menu_placement.spec` pins the prediction against the SOLVED
		rect, so a future padding/surface change to `buildMenuBlueprint` reddens a
		named case instead of silently un-flipping the menu. ]]
	local function predictedMenuHeight(): number
		local n = #menuItemsOrdered
		if n == 0 then
			return 0
		end
		local metrics = metricsSig:get()
		local rowH = themeSnapshot.resolveNumber(metrics, MENU_ROW_HEIGHT) or 0
		local gap = themeSnapshot.resolveNumber(metrics, MENU_ROW_GAP) or 0
		return n * rowH + (n - 1) * gap
	end

	-- the height of the window the menu has to stay inside. `spec.env` is
	-- OPTIONAL everywhere in this file (see `metricsSig`), and BOTH shipped hosts
	-- pass it (`table.luau` and `virtual_list.luau` both thread `spec.env`
	-- through); a bare standalone mount without one simply never flips, which is
	-- exactly the placement it had before this ruling.
	local function viewportRectPx(): any
		local env = spec.env
		if env == nil then
			return nil
		end
		local vp = env:get("viewportRect"):get()
		if type(vp) ~= "table" or type(vp.h) ~= "number" then
			return nil
		end
		return { x = tonumber(vp.x) or 0, y = tonumber(vp.y) or 0, w = tonumber(vp.w) or 0, h = vp.h }
	end

	--[[ WHERE THE MENU LANDS, AND WHICH WAY UP (ruling 4, director 2026-08-13:
		"flip the menu above the trigger when it would overflow" — option A, over
		clamping, because a clamp lets the menu cover its own trigger).

		`rect` is THIS row's own solved window-space rect (`controller`/`rootPath` —
		the SAME facts `currentRect` above reads). By default the menu opens just
		below the row's own left edge, matching `popup_button.luau`'s own "menu"
		placement (`offsetY = TRIGGER_HEIGHT`) translated into absolute window-space
		coordinates rather than a relative offset (the node these are spent on is
		`MenuRows`, whose `anchor`-kind parent `Menu` fills the surface's own
		edge-to-edge root, so the anchor's inner origin IS the window origin — see
		`buildMenuBlueprint`'s own comment for why the placement props ride the CHILD
		and not the Anchor itself).

		THE FLIP. Measured before this: a trigger at y=508 on a 600px viewport put
		the menu at y=556..629 — 29px past the bottom edge, silently, because an
		anchor parent emits no overflow diagnostic for a child it places. When the
		below-placement would run past the bottom AND there is room above, the menu
		is anchored `bottomLeft` with its bottom edge on the trigger's top instead.

		IT NEVER FLIPS INTO A WORSE PLACE. Both conditions have to hold: a menu too
		tall for the space above stays below (partly clipped is better than partly
		clipped AND upside down), which is the standard platform behaviour and the
		reason this is a flip rather than a clamp.

		Absent `controller`/`rootPath` (no presenter, or the very first frame before
		any solve — `openMenu` never runs at all without `controller`, see its own
		guard below) degrades to `0, 0, "topLeft"` rather than erroring. ]]
	--[[ WRITE THE THREE PLACEMENT SIGNALS, AND ONLY WHEN SOMETHING MOVED.
		`core:signal`'s baseline no-op-on-same-value covers the plain-number case for
		free, but the flipped form is a FRESH `{ scale, offset }` table every call —
		so a straight `set` would dirty the menu's arrange on every single
		`syncGeometry` frame the menu is open, which is exactly the per-frame churn
		the re-aim below is careful to avoid. Compared field-wise instead. ]]
	local function setMenuAnchor(ox: number, oy: any, kind: string)
		menuOx:set(ox)
		menuAnchorKind:set(kind)
		local current = menuOy:get()
		if type(oy) == "table" and type(current) == "table" then
			if current.scale == oy.scale and current.offset == oy.offset then
				return
			end
		end
		menuOy:set(oy)
	end

	local function computeMenuAnchor(): (number, any, string)
		local path = pathsOf()
		if controller == nil or path == nil then
			return 0, 0, "topLeft"
		end
		local rect = controller.screenRectOf(path)
		if rect == nil then
			return 0, 0, "topLeft"
		end
		local below = rect.y + rect.h
		local viewport = viewportRectPx()
		local menuH = predictedMenuHeight()
		if viewport == nil or menuH <= 0 then
			-- no window fact (a bare standalone mount) or nothing measured yet: the
			-- placement this control had before ruling 4, unchanged
			return rect.x, below, "topLeft"
		end
		--[[ THE FLIP IS THE SHARED DECISION NOW (navigation-and-menus D1), not a
			second copy of it. Same two conditions, same ruling, same numbers — the
			rules above are the ones `anchor_placement.solve` encodes, and this file
			was one of the two places they were written by hand.

			TWO INPUTS ARE DELIBERATELY NOT WHAT THE SOLVER WOULD PREFER, because
			changing either would change this control's shipped behaviour:
			  * `size.w = 0` — the menu's WIDTH is never learned here (`MenuRows`
			    goes unconstrained-width by design), so there is no along-edge extent
			    to shift and `placement.x` is not used. This control flips; it does
			    not shift. When a width becomes available the zero comes out and the
			    horizontal answer arrives for free.
			  * the safe box is the raw VIEWPORT, not `deviceSafeContent`. Ruling 4
			    was written against the viewport, and tightening it here would make
			    the menu flip earlier than the ruling that shipped it says. ]]
		local placement = anchorPlacement.solve({
			source = rect,
			size = { w = 0, h = menuH },
			safe = viewport,
			edge = "bottom",
			align = "start",
			gap = 0,
			-- ruling 4 again: "a clamp lets the menu cover its own trigger", so a
			-- menu that fits on neither side stays below and clipped
			overflow = "keep",
		})
		if placement.flipped then
			-- see `menuOy`'s own comment: a fraction of the anchor's inner height,
			-- so the solver supplies the height this file must not guess at
			return rect.x, { scale = -1, offset = rect.y }, "bottomLeft"
		end
		return rect.x, placement.y, "topLeft"
	end

	--[[ THE PLACEMENT PROPS BELONG TO THE CHILD, NOT TO THE ANCHOR ITSELF (live
		defect, found 2026-08-13 by the placement-prop audit; fixed with the Group C
		flight round because it is the same trap in the same file).

		`anchor`/`offsetX`/`offsetY` are read by a node's PARENT, and only by an
		`anchor`-kind one — this file's own header says so for the row slide
		("honoured ONLY by an `anchor`-kind parent... the sibling `zstack` branch
		does not — a ZStack child's `offsetX` is silently inert"). `MENU_ROOT_ID` IS
		the `UI.Anchor`, but it declared those three props on ITSELF, where its
		parent is the `UI.Screen` this surface is presented as — a VSTACK, which
		reads none of them. Measured before the fix: the row's own screen rect
		(20, 148, 760x48) put `menuOx/menuOy` at (20, 196), and the menu solved to
		x = 0, y = 0. Silently, with `controller.diagnostics()` empty.

		So the Anchor now FILLS the edge-to-edge surface (which makes its inner
		origin the window origin, which is the space `computeMenuAnchor` measures
		in) and the placement rides `MenuRows`, its child, where an anchor-kind
		parent actually reads it. Every path is unchanged — `MenuRows` is still
		`/{MENU_SURFACE_ID}/{MENU_ROOT_ID}/MenuRows` — so the Activate pattern, the
		focus assertions and the contribution's own subtree all stay put.

		AND IT IS KEPT INSIDE THE VIEWPORT NOW (ruling 4, 2026-08-13). This block
		used to end "STILL NOT CLAMPED TO THE VIEWPORT... flipping the menu above its
		trigger is a placement decision rather than this fix". The director made that
		decision: `computeMenuAnchor` above flips the menu to `bottomLeft` above its
		trigger when the below-placement would run past the bottom edge. An anchor
		parent still emits no overflow diagnostic, which is why the flip is pinned by
		a test that measures the solved rect rather than trusting one. ]]
	local function buildMenuBlueprint(): any
		return UI.Screen({
			id = MENU_SURFACE_ID,
			children = {
				contribution.attach(
					UI.Anchor({
						id = MENU_ROOT_ID,
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.VStack({
								id = "MenuRows",
								-- ruling 4: `topLeft` (below the trigger) or `bottomLeft`
								-- (flipped above it) — see `computeMenuAnchor`
								anchor = menuAnchorKind,
								offsetX = menuOx,
								offsetY = menuOy,
								surface = "raised",
								gap = MENU_ROW_GAP,
								children = buildMenuRows(),
							}),
						},
					}),
					{
						handleActivate = menuHandleActivate,
						handleCancel = menuHandleCancel,
						-- NO `outsideDismiss` here (found live — a real correction,
						-- not the original design). `outsideDismiss`'s own catcher
						-- (presenter.luau's `syncPopupCatcher`) is BUILT for a
						-- popup living inside a plain, non-exclusive screen — its
						-- own comment: "an exclusive surface suppresses the popup
						-- catcher" — and a `presentModal` handle IS exclusive, so
						-- the field would simply never fire (proven: the "tap
						-- OUTSIDE the open menu... closes AND swallows" test hung
						-- open until this was found and fixed). `outsideTapCancel`
						-- on the presentModal opts below (the NATIVE mechanism
						-- built for exactly this — a modal-dismissal "swallow,
						-- never clickthrough" — presenter.luau `applyOutsideOutcome`)
						-- replaces it exactly: same "swallowing" contract, the
						-- exclusivity-aware primitive instead of the one built for
						-- a different (non-exclusive) shape of surface.
					}
				),
			},
		})
	end

	local function openMenu()
		if #menuItemsOrdered == 0 then
			return -- unreachable given the `else` branch below only builds
			-- this seam when at least one action exists; stay honest anyway
			-- rather than open an empty popup if that invariant is ever wrong.
		end
		if presentModalFn == nil or menuHandle ~= nil then
			return -- no presenter to present onto, or already open (toggleMenu's
			-- own guard already prevents the latter in practice — stay honest).
		end
		setMenuAnchor(computeMenuAnchor())
		-- REAL BUG, caught live (not a style choice — see `closeMenu`'s own
		-- mirror-image comment). `presentModal` synchronously paints the
		-- surface's INITIAL focus (`makeHandle`'s own "paint the INITIAL
		-- focus ring" step) as part of THIS call, moving `graph.focused`
		-- onto the menu's own first row — which fires this row's OWN
		-- focus-change observer (`bindFocusGraph` below) SYNCHRONOUSLY,
		-- inside `presentModalFn(...)`, before `menuOpen:set(true)` would
		-- otherwise run. `syncKeysEnabled` -> `pathInsideRow` reads
		-- `menuOpen:get()` at exactly that moment: with the old ordering it
		-- was STILL `false` (the new focus path is under the menu's own
		-- surface, never a prefix of `rootPath`), so `syncKeysEnabled`
		-- DISABLED this row's own `RowActionsKeys-<id>` context right then
		-- — and nothing ever re-enabled it, because focus never changes
		-- again while the menu stays open. ButtonX/Shift+Return (bound in
		-- that now-disabled context) went permanently dead the instant the
		-- menu opened once — caught by "toggling the menu 10 times leaks
		-- nothing" (the SECOND press, meant to close it, silently did
		-- nothing at all). Setting `menuOpen` true FIRST means the observer
		-- sees the truth already in place.
		menuOpen:set(true)
		-- `outsideTapCancel = true` (the presenter's own default for a modal,
		-- spelled out explicitly here anyway — see the big comment on the
		-- deleted `outsideDismiss` field above for why THIS is now the real
		-- mechanism): a tap outside the menu's own subtree dismisses it and
		-- is swallowed, never clicking through to whatever it actually
		-- landed on (`presenter.luau`'s own `applyOutsideOutcome`).
		local handle = presentModalFn(buildMenuBlueprint(), {
			rootPolicy = "edgeToEdge",
			scrim = "none",
			outsideTapCancel = true,
			cancelPolicy = "none",
		})
		menuHandle = handle
		-- KEEP `menuOpen`/`menuHandle` IN SYNC WITH EVERY DISMISS PATH, not
		-- only the ones this file itself drives through `closeMenu` — the
		-- outside-tap dismiss above runs entirely inside the presenter
		-- (`applyOutsideOutcome` -> `self.dismiss`, never through
		-- `closeMenu`), so without this, tapping outside would tear the
		-- surface down while `menuOpen`/`dump().menuOpen` stayed stuck
		-- `true` forever. `handle.onFeedback` is the presenter's own
		-- per-surface event bus (`presenter.luau`, "the same bus filtered to
		-- that surface"); a `dismiss` event fires for EVERY teardown path —
		-- ours (`closeMenu` -> `dismissFn`) included, making this the ONE
		-- place this bookkeeping happens rather than duplicated at every
		-- call site. The `menuHandle == handle` guard is defensive: this
		-- closure captures the exact handle it was registered for, so a
		-- LATER open/close cycle's own (different) handle can never have
		-- this stale subscription mistakenly clear ITS state.
		if handle.onFeedback ~= nil then
			handle.onFeedback(function(event: any)
				if type(event) == "table" and event.type == "dismiss" and menuHandle == handle then
					menuHandle = nil
					menuOpen:set(false)
				end
			end)
		end
	end
	local function toggleMenu()
		if menuOpen:get() then
			closeMenu()
		else
			openMenu()
		end
	end

	-- ===== Task 8: focus-scoped keyboard/gamepad bindings ===================
	-- THE REAL SCOPE (corrected, review round 1 — the brief's own "active
	-- ONLY while the wrapper's content subtree holds focus" undersold what
	-- is actually built and true, and the mismatch hid a real bug; see the
	-- MENU-OPEN CARVE-OUT below for what it hid). `pathInsideRow` checks
	-- `rootPath` — this COMPOSITE's own whole mounted subtree: `content`,
	-- a revealed tray button, or an open menu row are ALL "inside the row"
	-- by this check, not `content` alone. That is deliberate, not a
	-- shortcut: a player who has tabbed onto a revealed tray button, or
	-- into the open menu itself, is still unambiguously interacting with
	-- THIS row, and Delete/ButtonX ought to keep meaning "this row" there
	-- too — narrowing the check to literally `content`'s own path would
	-- make ButtonX unable to re-close the menu it just opened (focus moves
	-- to the menu's own first row the instant it opens — see `buildMenuRows`
	-- below — which is immediately outside a `content`-only scope) without
	-- gaining anything Delete/ButtonX need to refuse.
	--
	-- THE MENU-OPEN CARVE-OUT. That broad scope has exactly one hazard: with
	-- the menu open, `pathInsideRow` is STILL true (a menu row is inside
	-- `rootPath`), so nothing here stopped Delete from firing straight
	-- through `commitDestructive()` — an entirely separate IAS path from the
	-- menu's own `handleActivate`/`transientScope` — while a NON-destructive
	-- menu row (e.g. "Flag") sat focused. Reproduced: the row committed and
	-- collapsed (`phase == "closed"`) while `menuOpen` stayed `true` and the
	-- menu's own rows stayed mounted on top of a fully collapsed row. Fixed
	-- at the Delete handler itself (below): the open menu is the ONLY
	-- legal path to ANY action once it is up, destructive or not, so Delete
	-- is inert for the whole time `menuOpen` is true — the menu's own
	-- Activate/Cancel is the one way in. ButtonX is NOT carved out the same
	-- way: toggling it closed while a menu row holds focus is the intended
	-- close affordance, and it never touches an action directly (only
	-- `toggleMenu`, which the menu's own state already guards idempotently).
	--
	-- `bindFocusGraph` hands over the screen's live focused-path signal
	-- (`graph.focused`, slider.luau's own precedent); `rootPath` is learned
	-- by `syncGeometry` below (same "learned here, re-ask once known"
	-- two-step slider.luau's own `syncTrackFocus` uses). The two
	-- keys/actions this scope owns:
	--   RowActionsDelete (Delete, Backspace) — only ever created when
	--     `hasDestructive`, so an unregistered binding truly falls through
	--     (brief) rather than existing-but-inert; additionally inert
	--     whenever `menuOpen` (the carve-out above).
	--   RowActionsMenu (gamepad ButtonX, keyboard Shift+Return — Task 8b).
	--     Task 8 shipped ButtonX only; Shift+Return was NOT expressible then
	--     (`Return` already claimed unconditionally by the base screen's own
	--     Activate context, `presenter.luau:2528`, and this framework's own
	--     `action.bind` wrapper accepted no modifier slot at all — Task 8
	--     report §Shift+Return). Task 8b added an additive `modifiers` slot
	--     to `action.bind` (this repo's `src/input/actions.luau` + its
	--     real-engine adapter `src/client/roblox_input.luau`): a binding may
	--     now declare `modifiers = { shift = true }`, matched only while
	--     shift is held. Bound in THIS SAME sink=true, priority-10000
	--     context as Delete/ButtonX above.
	--
	--     Headlessly, the preemption of the base Activate context's
	--     unmodified `Return` binding falls out of the EXISTING priority/
	--     sink arbitration (spike T1: a higher-priority Sink context blocks
	--     a lower one on the same key) the moment the modifier match makes
	--     this binding an eligible candidate; with shift NOT held it is
	--     never a candidate at all, so plain Return reaches the base
	--     Activate context exactly as before Task 8b (see actions.luau's
	--     `modifierMatch`/`deviceKey`). On the real client, real
	--     `InputBinding` turns out to carry a genuine modifier concept —
	--     `PrimaryModifier`/`SecondaryModifier` (fix round 2, platform
	--     review BLOCKER-1: the first round's premise that it did not was
	--     never checked against the engine's own class reference and was
	--     wrong) — so `roblox_input.luau` realizes this as two ordinary
	--     `InputBinding`s (one per physical Shift key, since
	--     `PrimaryModifier` is a single `Enum.KeyCode` and Left/RightShift
	--     have no combined enum) under the SAME action/context, no second
	--     mechanism, inheriting that context's live Enabled/Sink/Priority
	--     through the identical engine arbitration every other binding here
	--     already goes through.
	--
	-- `sink = true` (TEXT_ENTRY_PRIORITY's own precedent, text_input.luau):
	-- while this scope owns Delete/Backspace/ButtonX, nothing lower-priority
	-- also sees them — none of the three is claimed by any base-screen
	-- context today, so this is a no-op in practice, and future-proof if one
	-- ever is.
	-- the keys themselves are `row_actions.ROW_KEYS`, module scope, because a host
	-- binds the identical set while standing in for an engine that does not exist
	-- yet — see that table's own comment.
	local ROW_ACTIONS_KEY_PRIORITY = row_actions.ROW_KEY_PRIORITY
	local function ensureKeysContext()
		if actionSystemRef == nil or keysContext ~= nil then
			return
		end
		local ctx = actionSystemRef.createContext({
			name = `RowActionsKeys-{id}`,
			priority = ROW_ACTIONS_KEY_PRIORITY,
			sink = true,
		})
		if hasDestructive then
			local deleteAction = ctx.createAction("RowActionsDelete", "Bool")
			for _, binding in row_actions.ROW_KEYS.delete do
				deleteAction.bind(binding)
			end
			deleteAction.onPressed(function()
				-- MENU-OPEN CARVE-OUT (review round 1 MAJOR, see the big
				-- comment above): the open menu owns ALL action dispatch
				-- while it is up — Delete must not reach a destructive
				-- action out from under it. `menuOpen` is checked live
				-- (not snapshotted), so this guard tracks the menu's real
				-- state on every single press.
				if menuOpen:get() then
					return
				end
				commitDestructive()
			end)
		end
		local menuAction = ctx.createAction("RowActionsMenu", "Bool")
		for _, binding in row_actions.ROW_KEYS.menu do
			menuAction.bind(binding)
		end
		menuAction.onPressed(function()
			toggleMenu()
		end)
		ctx.setEnabled(false) -- enabled only while `pathInsideRow` — see syncKeysEnabled
		keysContext = ctx
		scope:own(function()
			if keysContext ~= nil then
				keysContext.destroy()
				keysContext = nil
			end
		end)
	end
	-- REDTEAM FIX (item 2, BLOCKER, follow-on): the menu now lives under its
	-- OWN presented surface's root (`MENU_SURFACE_ID`, not `rootPath`), so a
	-- plain prefix check against `rootPath` alone would go false the instant
	-- focus lands inside the open menu — disabling THIS row's own keys
	-- context (`syncKeysEnabled` below) right as focus enters it, which
	-- would leave ButtonX/Shift+Return unable to re-close the menu they
	-- just opened (the exact hazard the big comment above
	-- `ROW_ACTIONS_KEY_PRIORITY` already documents as the reason this scope
	-- has to be broad). `menuOpen:get()` alone is a sufficient, simpler
	-- test than a second path-prefix comparison: this row's own menu can
	-- only ever be open while ITS OWN presentModal handle is the trapped
	-- top of the focus stack (`focus_graph.luau`'s own `pushScope(trap =
	-- true)`), so focus cannot be anywhere else at all while `menuOpen` is
	-- true.
	-- fix round 1, finding 2: in hosted mode a revealed tray's buttons live in
	-- the HOST'S SHARED OVERLAY (`hostedPaths.trayLeading`/`trayTrailing`),
	-- never under `pathsOf()` (the row's own content path, `hostedPaths.
	-- content`) — the two are siblings, not parent/child, unlike standalone
	-- mode where a tray IS a descendant of this composite's own root (see
	-- `pathsOf`'s own standalone branch: `{rootPath}/{tid}When/then/{tid}`).
	-- Without this, a player who has tabbed onto a revealed tray button in a
	-- hosted list reads as OUTSIDE the row to the plain prefix check below,
	-- so `syncKeysEnabled` would disable this row's own Delete/ButtonX keys
	-- context at the exact moment a tray button holds focus — the header
	-- comment above's whole "a player who has tabbed onto a revealed tray
	-- button... is still unambiguously interacting with THIS row" contract,
	-- broken specifically for hosted rows. Standalone is untouched: `pathsOf`
	-- for a tray edge already returns a path INSIDE `rootPath` there, so the
	-- extra checks below are always false when `hostedPaths == nil`.
	local function pathInsideRow(path: string?): boolean
		if menuOpen:get() then
			return true
		end
		if path == nil then
			return false
		end
		local row = pathsOf()
		if row ~= nil and isPathPrefix(row, path) then
			return true
		end
		if hostedPaths ~= nil then
			local leadingTray = pathsOf("leading")
			if leadingTray ~= nil and isPathPrefix(leadingTray, path) then
				return true
			end
			local trailingTray = pathsOf("trailing")
			if trailingTray ~= nil and isPathPrefix(trailingTray, path) then
				return true
			end
		end
		return false
	end
	-- Task 11b (perf): `ensureKeysContext` used to run unconditionally, every
	-- time — meaning EVERY mounted row paid a real `actionSystemRef.
	-- createContext` + two `createAction`/`.bind()` calls at mount (via
	-- `bindActionSystem`'s own unconditional `syncKeysEnabled()` call below),
	-- even though the binding is `setEnabled(false)` immediately after and
	-- stays that way for the entire life of a row nobody ever tabs/clicks
	-- into — exactly the "Delete-key/menu bindings only matter when the
	-- row's subtree has focus" cost the perf directive calls out by name.
	-- Confirmed safe to defer: a disabled context is fully excluded from
	-- arbitration (`src/input/actions.luau`'s own dispatch checks
	-- `context.enabled` before ever consulting a context at all — lines
	-- ~369/420), so "context exists but disabled" and "context was never
	-- built" are OBSERVATIONALLY IDENTICAL to every caller; the only
	-- difference is which rows pay to allocate one. Building it here, gated
	-- on `insideRow` being true, means the FIRST call this ever makes to
	-- `ensureKeysContext` is the one where focus has actually just arrived —
	-- still built exactly once per row (idempotent inside `ensureKeysContext`
	-- itself), still torn down by the identical `scope:own` in there, just
	-- never at all for a row nobody ever focuses.
	local function syncKeysEnabled()
		local insideRow = pathInsideRow(if focusGraph ~= nil then focusGraph.focused:get() else nil)
		if not insideRow and keysContext == nil then
			return -- never built; nothing to disable, and no reason to build one now
		end
		ensureKeysContext()
		if keysContext == nil then
			return
		end
		keysContext.setEnabled(insideRow)
	end

	-- ===== Tasks 5-6: the pointer gesture (mouse + touch; axis lock, live
	-- drag, flick velocity) ===
	-- One in-flight gesture at a time — the adapter's own capture model
	-- already guarantees `onPointerDown` is never re-entered while a capture
	-- is live (fake_target.luau `pointerDown`: "a live capture OWNS the
	-- pointer... ignored, never a steal"; the real engine's ADR-0008 capture
	-- is the same shape — and this holds regardless of which class is asking:
	-- a touch press arriving mid-mouse-drag, or a mouse press arriving
	-- mid-touch-drag, is silently ignored by the adapter BEFORE this
	-- composite's own `onPointerDown` is even called, exactly like a same-
	-- class second press would be), so `drag` here is just this composite's
	-- own record of that one gesture — CARRIED through any other class's
	-- failed attempt to touch it, never handed off.
	type DragState = {
		originX: number,
		originY: number,
		startOffset: number,
		axis: row_actions_state.AxisVerdict,
	}
	local drag: DragState? = nil
	local tracker = drag_velocity.new()

	-- the only legal time source for `tracker.push` (drag_velocity's own
	-- contract: "this module never reads os.clock"). REVIEW FIX: the
	-- previous `os.clock()` fallback was dead code that still violated that
	-- contract by construction — a real gesture can only reach these
	-- handlers through a live adapter capture, which only exists once a
	-- presenter mounted this control, and every presenter supplies SOME
	-- `nowFn` (`presenterOpts.now or os.clock`) that `bindMotion` always
	-- threads through before any pointer event can fire. `nowFn == nil` here
	-- means `_pointerHandlers` was invoked directly, with no presenter ever
	-- having bound this composite at all — a genuine misuse of an internal
	-- seam (`_pointerHandlers`'s own doc: "Table composes them"), not a
	-- supported degradation the way an absent `motionClock`/`controller` is
	-- elsewhere in this file. Fail loudly (the `assert(...)` convention this
	-- codebase already uses for internal invariants — e.g. `virtual_list.
	-- luau`, `text_input.luau`) rather than silently inventing a time axis.
	local function currentNow(): number
		assert(
			nowFn ~= nil,
			`Facet {label}('{id}'): a pointer gesture reached _pointerHandlers with no bound \`now\` `
				.. "(bindMotion never ran) — these handlers must only be driven through a live presenter capture"
		)
		return nowFn()
	end

	-- a FRESH row_actions_state instance, read LIVE every time it is needed
	-- (every move, and again at release) rather than snapshotted once at
	-- `pointerDown`. This is not optional polish: `leadingWidth`/
	-- `trailingWidth` are the SUM of per-button naturals a tray only
	-- publishes once it has actually mounted and measured at least one real
	-- frame (the header comment's own "TRAY WIDTH" section — trays mount
	-- LAZILY, `UI.When`, only once `revealed`), so a row that has never been
	-- opened before has BOTH still reading 0 at the exact instant of
	-- `pointerDown` — a real chicken-and-egg a live-found repro caught this
	-- task (a fresh row's very first-ever swipe settled CLOSED no matter how
	-- far it was dragged, because the down-time snapshot had frozen a tray
	-- width of 0 before the tray had ever had a chance to mount and measure
	-- itself). Reading live means the moment the drag's own first negative
	-- `applySlide` reveals the tray (see the `revealed` memos below) and the
	-- next `syncGeometry` measures it, this decision sees the REAL number —
	-- self-correcting within a frame or two, rather than wrong for the rest
	-- of the gesture. `row_actions_state.new` is a cheap, pure constructor
	-- (closures over already-known scalars, no engine, no allocation beyond
	-- itself), so rebuilding it per move costs nothing next to a solve pass.
	-- REDTEAM FIX (item 9, MEDIUM): the "self-correcting within a frame or
	-- two" story above assumes at least one `syncGeometry` (a `pres.refresh()`)
	-- lands somewhere between `pointerDown` and `pointerUp` — true of a real
	-- host frame loop, but not of a synthetic gesture driven with ZERO ticks
	-- in between (down/move/up back-to-back, no refresh at all): with no
	-- `syncGeometry` ever having run, `leadingWidth`/`trailingWidth` are
	-- STILL exactly 0 at release, so `settle` sees `tray <= 0` on both edges
	-- and closes no matter how far the drag actually traveled — a real
	-- "flick that never opens" a player could hit on an unlucky single-frame
	-- flick. `provisionalWidth` substitutes an ESTIMATE — `#actions *
	-- buttonMinWidthPx` (the theme's own per-button floor, already resolved
	-- live above) — only when the true measured sum is still 0, for THIS
	-- decision's inputs alone: it never writes back to `leadingWidth`/
	-- `trailingWidth` themselves (the reactive signals every width PROP
	-- still reads), so the real measurement from the next `syncGeometry`
	-- (if one ever runs) replaces it exactly as before, unchanged.
	local function provisionalWidth(actions: { ActionSpec }?, measured: number): number
		if measured > 0 or actions == nil then
			return measured
		end
		return #actions * buttonMinWidthPx:get()
	end

	local function currentDecision(): any
		return row_actions_state.new({
			rowWidth = currentRowWidth(),
			leadingWidth = provisionalWidth(leadingActions, leadingWidth:get()),
			trailingWidth = provisionalWidth(trailingActions, trailingWidth:get()),
			fullSwipeLeading = fullSwipe.leading,
			fullSwipeTrailing = fullSwipe.trailing,
		})
	end

	local function onPointerDown(_path: string, pos: any, _rectOf: (string) -> any): boolean?
		if pos.pointerType ~= nil and pos.pointerType ~= "mouse" and pos.pointerType ~= "touch" then
			-- pen/stylus/anything else: DECLINE — mouse and touch are the
			-- only two classes this gesture understands. Touch spike (Task 6,
			-- artifacts/row-actions/touch-spike.md): accepted through the
			-- IDENTICAL tentative-accept + axis-lock-then-inert dance mouse
			-- already uses below, on the evidence that (1) the real adapter
			-- already delivers touch through this exact seam today
			-- (screen_target.luau's setPointerHandlers checks
			-- `UserInputType.Touch` alongside `MouseButton1` at every step —
			-- row_actions.luau's own decline was the only thing blocking it),
			-- and (2) `row_actions_state.axisVerdict`'s own tie-break
			-- ("ties go vertical: scrolling must never lose an ambiguous
			-- gesture") is what makes accepting safe next to a native Y-scroll
			-- Body — unlike table.luau's own rowPointerHandlers, which
			-- declines touch UNCONDITIONALLY because ITS gesture (vertical
			-- reorder) is itself ambiguous with scroll; RowActions' swipe is
			-- horizontal, so the two are axis-disambiguable, not competing.
			return false
		end
		if drag ~= nil then
			return false -- a capture is already live; never steal (engine parity)
		end
		-- REDTEAM FIX (item 1, BLOCKER; director ruling): a commit already in
		-- flight is irrevocable — a NEW gesture must never be able to grab
		-- this row's own `offset`/spring out from under it (that IS the
		-- BLOCKER'S own repro: a second swipe starting mid-commit). Declined
		-- the same way a live capture already is, one line above: no partial
		-- accept-then-decline, this row simply does not participate in a new
		-- gesture until the commit's own chain reaches `resetToClosed()`.
		if committed then
			return false
		end
		-- D1 (see `commitLatched`'s own comment): a commit has fired and the row
		-- has not finished travelling home. Refused for the SAME reason
		-- `committed` is one line above — the difference is only that this one
		-- outlives the commit chain itself, covering the spring back from the
		-- parked slide-off position that `startOffset` would otherwise inherit.
		if commitLatched then
			return false
		end
		drag = {
			originX = pos.x,
			originY = pos.y,
			startOffset = offset:get(),
			axis = "pending",
		}
		tracker:reset()
		-- REDTEAM FIX (item 13, LOW): `composeWithReorder` (below) REPLAYS
		-- this down at the true origin POSITION but at the LOCK-CROSSING
		-- moment — a real gesture's true down time is unknowable to it (it
		-- is deliberately clockless, mirroring `row_actions_state.luau`'s
		-- own purity — see its own header comment); `pos.replayed` (set
		-- only by that one replay call site, never by a real adapter event)
		-- marks it. Seeding the tracker's FIRST sample at the true origin
		-- but the WRONG time, immediately followed by a second sample at
		-- the CURRENT position at essentially the SAME instant, produced a
		-- large spatial delta over a near-zero time delta — an inflated
		-- (real clock) or degenerate (scripted clock) velocity neither a
		-- direct, uncomposed gesture nor touch (which never defers) can
		-- ever produce. Skipping the seed here means the window starts
		-- cleanly AT the lock, from whatever position/time the very next
		-- real `onPointerMove` supplies — `tracker:reset()` above still
		-- runs unconditionally, so a stale window from an earlier gesture
		-- on this same row is still cleared either way.
		if pos.replayed ~= true then
			tracker:push(pos.x, pos.y, currentNow())
		end
		-- TENTATIVE ACCEPT (capture-semantics investigation — task-5-report.md
		-- carries the full writeup): the axis is genuinely unknown at down
		-- (dx = dy = 0 here, always), and this adapter's capture model —
		-- mirroring the real engine's ADR-0008 capture — offers no way to
		-- hand the capture back once accepted: renderer.luau wires `move`/
		-- `up` without ever reading a return value from either, only `down`
		-- may decline. A "vertical" verdict is therefore honored by going
		-- INERT for the rest of THIS gesture (see `onPointerMove` below), not
		-- by un-capturing — there is no third option. Mouse and touch share
		-- this identically (Task 6): no branch below distinguishes them past
		-- this point.
		return true
	end

	local function onPointerMove(_path: string, pos: any, _rectOf: (string) -> any)
		if drag == nil or drag.axis == "vertical" then
			return
		end
		local dx = pos.x - drag.originX
		local dy = pos.y - drag.originY
		if drag.axis == "pending" then
			-- axisVerdict is a pure function of dx/dy and the fixed
			-- AXIS_LOCK_PX constant alone (never reads width/fullSwipe), so
			-- which decision instance answers it is immaterial.
			local verdict = currentDecision().axisVerdict(dx, dy)
			if verdict == "pending" then
				return -- still accumulating toward the lock radius
			end
			drag.axis = verdict
			if verdict == "vertical" then
				return -- declined: `offset` is never touched for this gesture
			end
			-- Task 7: the SECOND coordinator claim site (brief: "when a gesture
			-- crosses the axis lock into horizontal... coordinator.claim(self)").
			-- Claimed the instant the axis resolves — before the release verdict
			-- is even known — so a sibling row already open starts its animated
			-- close the moment this row starts visibly dragging, not only once
			-- this row itself settles open.
			if coordinator ~= nil then
				coordinator.claim(api)
			end
			-- transitioning to "horizontal": the persistent reveal spring must
			-- stop pushing its OWN writes into `offset` right now, or its next
			-- step fights the manual drag this function is about to start
			-- driving directly — the spring's interruptibility guarantee
			-- (comment above `ensureSpring`) is for a RETARGET, not for a
			-- live human hand on the same value.
			if spring ~= nil then
				spring:stop()
			end
		end
		local target = currentDecision().clampDrag(drag.startOffset + dx)
		applySlide(target)
		tracker:push(pos.x, pos.y, currentNow())
	end

	--[[ A PRESS THE ROW DID NOT CLAIM GOES TO WHATEVER IS UNDERNEATH (ruling 6,
		director 2026-08-13 — option A, "the Grip goes ON TOP and forwards presses it
		does not claim").

		THE ENGINE FACT (measured live, `docs/lessons/a-button-eats-the-swipe-
		underneath-it.md`): Roblox delivers `InputBegan` to the TOPMOST interactive
		object only. This file used to paint its hit Grip BEHIND `content` on a
		comment claiming the engine delivered to every Active object under the point
		"independently of paint order". It does not — a `GuiButton` in the content
		sinks the press and the Grip receives nothing, so a row whose content holds a
		button could not be swiped where that button covered it. Every swipe demo
		built to date used inert content, which is why nothing caught it.

		So the Grip is on top now (see the `Content` children below), and the cost of
		that is exactly this function: the gesture always reaches the row, and a press
		the row decides is NOT a swipe has to be handed on. The decision is already
		made — `row_actions_state.axisVerdict`, whose "ties go vertical" rule is what
		makes it safe — and this is only the handing on.

		ONLY A TAP IS FORWARDED. `axis == "pending"` means the gesture never left the
		lock radius, which is what a tap is. A `"vertical"` verdict is a scroll the
		row declined, and a scroll is not an activation of anything. A `"horizontal"`
		one never reaches here at all.

		ponytail: the forwarded press has no PRESSED VISUAL — the button under the
		finger does not light up while held, because the engine never told it it was
		pressed. Upgrade path: forward the down/up pair, not just the resolved tap.
		The activation itself is exact (`controller.tapAt` runs the same dispatch the
		engine's own `Activated` would have reached). ]]
	local function forwardUnclaimedTap(pos: any)
		if externalGesture then
			return -- no Grip of ours is mounted; the host owns the press outright
		end
		local ctrl = controller
		local root = pathsOf()
		if ctrl == nil or root == nil or type(ctrl.tapAt) ~= "function" then
			return
		end
		-- scoped to THIS row's own content: a forwarded tap must never reach a
		-- sibling row, and `Content` is the subtree the Grip is painted over.
		-- `skip` is this Grip itself — it is a pointer zone inside `within`, so
		-- without it the forward would land straight back here.
		ctrl.tapAt(pos.x, pos.y, { within = `{root}/Content`, skip = `{root}/Content/Hit` })
	end

	local function onPointerUp(_path: string, pos: any, _rectOf: (string) -> any)
		if drag == nil then
			return
		end
		local wasHorizontal = drag.axis == "horizontal"
		if wasHorizontal then
			tracker:push(pos.x, pos.y, currentNow())
			local vx = tracker:velocity() -- (vx, vy); only the horizontal axis matters here
			local verdict = currentDecision().settle(offset:get(), vx)
			drag = nil
			-- REVIEW FIX (director-visible fidelity gap): `vx` already drove
			-- the DECISION above (settle's velocity projection); it must also
			-- drive the ANIMATION, or a flick and a slow release settle
			-- identically — the same gesture->animation handoff
			-- `drag_registry.luau:376-379` does at flight start. `setTarget`
			-- itself "never touches value or velocity, so an interrupt
			-- continues from where it is at the speed it has" (comment above
			-- `ensureSpring`), so seeding velocity HERE, before `settleTo`
			-- below calls `retarget`/`retargetThen` (both of which only ever
			-- `setTarget` the SAME persistent `spring`), carries the flick's
			-- speed into whichever flight follows — snap-open, snap-closed,
			-- or a full-swipe commit's slide-off alike. Guarded to a real
			-- spring only: no clock means `retarget` falls back to the
			-- instant `applySlide` snap, which has no velocity concept at
			-- all; reduced motion is separately a no-op inside `setVelocity`
			-- itself (motion.luau: "nothing is animating under reduced
			-- motion: no seam to smooth").
			if motionClock ~= nil then
				ensureSpring()
				--[[ RE-SEED THE PERSISTENT SPRING AT THE DRAG'S OWN OFFSET before
					aiming it (found by Task 5's hosted parity sweep; the identical
					bug the COLLAPSE spring's own `snap` comment describes, in the
					one other place a reused spring is re-aimed).

					A live drag drives `offset` DIRECTLY (`applySlide` in
					`onPointerMove`) after stopping the spring, so from that moment
					the spring's internal value is wherever the last flight left it —
					not where the finger is. `ensureSpring` seeds a spring only when
					it CREATES one, so the first gesture on a row was always correct
					and every later one was not: on the second short swipe of the
					same row the spring still sat at 0, `settleTo` aimed it at 0, and
					a target it was already at produced NO steps and NO writes. The
					row stayed parked at the drag's last offset — visibly slid, with
					`_isOpen()` false, so nothing would ever put it back — and each
					further swipe ratcheted it further out (measured: 0, -20, -40).

					`snap(v)` is placement, not arrival: value and target both go to
					`v`, velocity is zeroed and no settle event fires — so it can
					never announce an arrival the caller did not ask for. It runs
					BEFORE `setVelocity`/`setTarget` for exactly that reason. On a
					spring that IS already at `offset` (the first gesture, or a
					second one after an ordinary settled flight) it is a no-op. ]]
				spring:snap(offset:get())
				spring:setVelocity(vx)
			end
			settleTo(verdict)
		else
			-- "pending" (a tap, never past the lock radius) or "vertical"
			-- (declined): nothing this gesture touched needs undoing
			local wasTap = drag.axis == "pending"
			drag = nil
			if wasTap then
				forwardUnclaimedTap(pos)
			end
		end
	end

	local function onPointerCancel(_path: string, _reason: string?): boolean?
		if drag == nil then
			return nil
		end
		local wasHorizontal = drag.axis == "horizontal"
		drag = nil
		if wasHorizontal then
			-- ...and the SAME re-seed the release does (see `onPointerUp`): a
			-- cancel ends a manual drag too, so `close()`'s retarget would
			-- otherwise aim a spring that is still standing where the previous
			-- flight left it — and a cancel's target is 0, the very value a row
			-- that has already been closed once is parked at.
			if spring ~= nil then
				spring:snap(offset:get())
			end
			-- spec: "pointer cancel mid-drag springs back to closed"
			close()
		end
		return nil
	end

	local pointerHandlers = {
		onPointerDown = onPointerDown,
		onPointerMove = onPointerMove,
		onPointerUp = onPointerUp,
		onPointerCancel = onPointerCancel,
	}

	-- REDTEAM FIX (item 5, MINOR; final-review-findings.md): `_isOpen()`
	-- reporting `true` for the WHOLE duration of an in-flight commit (the row
	-- is sliding off-screen and about to be destroyed, not "open" in any
	-- sense a caller should act on) is what let finding 1's own BLOCKER hide
	-- everywhere it did — Table's row-tap close guard and the reorder-vs-tray
	-- guards (table.luau) all gate on this one function, and every one of
	-- them would have tried to `_close()`/re-grab an irrevocably-committing
	-- row had this kept saying "open". `committed` wins outright.
	local function isOpen(): boolean
		return not committed and openEdge:get() ~= nil
	end

	-- Task 7: the reactive twin of `isOpen()` — `outsideDismiss.active` (below)
	-- needs a Readable<boolean> to `core:observe`/`:get()`, not a plain
	-- function; a one-line memo over the same `openEdge` signal `isOpen`
	-- already reads. `committed` is a plain (non-signal) local, but every
	-- write to it in this file is always paired, same-call, with an
	-- `openEdge` write (`doCommitAction`'s `committed = true` before
	-- `openEdge:set(edge)`; `resetToClosed`'s `openEdge:set(nil)` before
	-- `committed = false`) — so reading it here still recomputes at exactly
	-- the right moments, never one commit-generation stale.
	local isOpenReadable = scope:own(core:memo(function(use)
		return not committed and use(openEdge) ~= nil
	end))

	-- Task 7 (matrix §B PopupButton parity, popup_button.luau:331-337's exact
	-- shape): gamepad ButtonB closes an open tray, offered to the presenter's
	-- Cancel dispatch before its modal-dismiss/passive-resign/no-op branches.
	-- Returns false with nothing open, so Cancel falls through to whatever a
	-- surrounding surface (a modal, a passive list) does with it.
	local function handleCancel(_focusedPath: string?): boolean
		if isOpen() then
			close()
			return true
		end
		return false
	end

	-- REDTEAM FIX (item 5, MINOR): a fourth phase word — "committing" — names
	-- what `dump().phase` used to call "open" for the entire duration of an
	-- in-flight commit, indistinguishable from an ordinary revealed tray to
	-- anything reading the dump. `committed` wins outright, ahead of the
	-- `edge == nil` check, for the identical reason `isOpen()` above checks
	-- it first.
	local function dump()
		local edge = openEdge:get()
		local phase
		if committed then
			phase = "committing"
		elseif edge == nil then
			phase = "closed"
		else
			phase = "open"
		end
		return {
			schema = "facet-rowactions-dump/1",
			id = id,
			offset = offset:get(),
			openEdge = edge,
			phase = phase,
			-- Task 8: the action menu's own open state, independent of the
			-- tray's `openEdge`/`phase` above.
			menuOpen = menuOpen:get(),
			-- ruling 4: the height the FLIP decision is made against, published so a
			-- test can compare the number this file actually uses with the one the
			-- solver paints. Without it the only available check compares the solver
			-- against a second copy of the same arithmetic written in the test — a
			-- check that cannot see this file being wrong, which is the class
			-- docs/lessons and the simplicity gate both name.
			menuHeightPx = predictedMenuHeight(),
		}
	end

	-- REDTEAM FIX (item 11, MEDIUM): `handleActivate` (below, in the `else`
	-- branch only — a true inert-passthrough row contributes nothing at
	-- all, so it has none) is normally reached ONLY through the presenter's
	-- own longest-prefix contribution walk (`contribution.attach` below).
	-- `opts.onActivate` (presenter.luau's own documented consumer-override
	-- seam: "wins outright") bypasses that walk entirely — a caller who
	-- hands the presenter their OWN top-level Activate function (Table's
	-- own `api.handleActivate` is the natural thing to reach for, see its
	-- big comment there) needs an explicit way to forward a path back INTO
	-- this composite's own dispatch, since it can no longer be found by
	-- walking contributions. Exposed unconditionally (a safe no-op — `false`
	-- — on a true inert-passthrough row) so a caller never has to nil-check
	-- before calling it, the same "always callable" shape `_commitFirst`
	-- already has.
	local exposedHandleActivate: (string, any?) -> boolean = function(_path: string, _meta: any?)
		return false
	end

	--[[ ===== THE TRAY VIEWS — BUILT ONCE, USED BY BOTH MODES (Task 4) =========
		They live in `row_actions_trays.luau` (2026-08-14). A tray is the same thing
		in both modes — same buttons, same compactLabel degrade ladder, same
		destructive role, same per-action width props, revealed by the same memo
		over `openEdge`/`offset` — and the only difference is WHO PARENTS IT: this
		composite's own row root in standalone/Table, the host's ONE shared overlay
		in hosted mode. A parent is not a reason to have two tray builders that can
		drift apart, so the whole construction is one function and the two modes
		differ only in where the result is handed (`children` below, or
		`api.trayViews`).

		IT MOVED OUT WHOLE, not split: every input below is a build-time constant —
		the validated action lists, and reactive nodes this closure creates once and
		never reassigns — so the tray builder reads engine state without touching a
		single one of the mutable upvalues that make `buildEngine` one closure. That
		is what let this file get back under the 200,000-char `Script.Source` WRITE
		cap (docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md).

		THE COUPLING THAT REMAINS IS THE REAL ONE, and it is stated at both ends:
		`row_actions_metrics.bandWidth` decides how far the row TRAVELS, and every
		quantity the tray draws is spent at the reveal fraction so the drawn band is
		exactly `|offset|`. Four device rounds are written into that file's comments. ]]
	local trayViews = rowActionsTrays.build({
		UI = UI,
		core = core,
		scope = scope,
		leadingActions = leadingActions,
		trailingActions = trailingActions,
		leadingWidth = leadingWidth,
		trailingWidth = trailingWidth,
		leadingNaturals = leadingNaturals,
		trailingNaturals = trailingNaturals,
		offset = offset,
		openEdge = openEdge,
		committingSig = committingSig,
		motionBound = motionBound,
		editGutterPx = editGutterPx,
		buttonPadPx = buttonPadPx,
		trayGapPx = trayGapPx,
		rowGutterPx = rowGutterPx,
		REVEAL_EPS = REVEAL_EPS,
	})

	--[[ ...AND THE EDIT-MODE MINUS, ON THE SAME TERMS (stage 1, 2026-08-15).
		One `UI.When`, built here for BOTH modes exactly as `trayViews` above is,
		because the only difference between the modes is who PARENTS it: this
		composite's own row root in standalone/Table (`row_actions_root.build`
		receives it), the host's shared overlay in hosted mode (`api.editAffordanceView`
		hands it over). `nil` unless this row can ever show it, so an uninvolved
		caller pays nothing — the guarantee `hasEditAffordance`'s own comment makes. ]]
	local editAffordanceView: any = if hasEditAffordance
		then rowActionsRoot.buildEditAffordance({
			UI = UI,
			editAffordanceShown = editAffordanceShown,
			destructiveEntry = firstDestructiveEntry(),
		})
		else nil

	local blueprint: any
	-- the contribution field bundle (see its own comment where it is built)
	local contributionFields: any = nil
	if not isHosted and leadingActions == nil and trailingActions == nil then
		-- TRUE INERT PASSTHROUGH (perf directive): nothing to reveal on either
		-- edge, so this control adds NOTHING — not an Anchor, not a wrapper, not
		-- an extra GuiObject. `content` mounts exactly as the caller wrote it.
		blueprint = content
	else
		-- ===== THE BLUEPRINT (standalone/Table mode only) ================
		-- HOSTED MODE BUILDS NONE OF THIS (Task 2). Not "builds it and hides
		-- it": every node, every per-action width memo and every reveal memo
		-- below is skipped outright, which is the whole point — a closed
		-- hosted row must cost the host nothing at all. The engine seams the
		-- nodes used to answer for (paths, paint, the presenter handoffs) are
		-- `pathsOf`/`applySlide`/`contributionFields` instead.
		local root: any = nil
		--[[ THE ROW'S OWN NODE TREE lives in `row_actions_root.luau`
			(2026-08-14): the root Anchor, the trays under it, the sliding Content
			ZStack, the drag Hit Grip on top of `content`, and the edit-mode minus
			painted over the lot — in that paint order, which is three device rounds
			deep and is stated at both ends.

			It moved out for the same reason and on the same test as the other five
			siblings: every input is a build-time fact or a reactive node this closure
			creates once and never reassigns, so it composes the row's nodes without
			touching a single mutable upvalue of `buildEngine`. ]]
		if not isHosted then
			root = rowActionsRoot.build({
				UI = UI,
				core = core,
				scope = scope,
				id = id,
				width = spec.width,
				content = content,
				trayViews = trayViews,
				offset = offset,
				rowHeightOverride = rowHeightOverride,
				pointerHandlers = pointerHandlers,
				externalGesture = externalGesture,
				hasEditAffordance = hasEditAffordance,
				editAffordanceShown = editAffordanceShown,
				editGutterPx = editGutterPx,
				editAffordanceView = editAffordanceView,
			})
		end

		local idPattern = patternEscape(id)
		-- Task 2 (hosted): the standalone form matches a SUFFIX keyed on this
		-- composite's own node ids, deliberately not on the full path — it has
		-- to answer before the first `syncGeometry` has taught this file its own
		-- `rootPath` (an Activate can reach `_handleActivate` from a caller that
		-- took over `opts.onActivate`, at any time). A hosted engine has no ids
		-- of its own to key on, so it matches under the host's own tray path
		-- from `pathsOf` — which, unlike `rootPath`, is known at build time.
		local function actionIdFromPath(edge: Edge, path: string): string?
			if hostedPaths ~= nil then
				local trayPath = pathsOf(edge)
				if trayPath == nil then
					return nil
				end
				return string.match(path, `{patternEscape(trayPath)}/Action:(.+)$`)
			end
			local tid = trayId(edge)
			return string.match(path, `/{idPattern}/{tid}When/then/{tid}/Action:(.+)$`)
		end
		-- Task 9: a single fixed node (no per-action index needed, unlike the
		-- tray's own `Action:<id>` list).
		--
		-- Stage 1 (hosted): the SAME split `actionIdFromPath` just above makes, for
		-- the same reason — standalone keys on this composite's own node ids under
		-- its learned root, hosted on the ONE path the host declared. Hosted is an
		-- EXACT match (`^…$`), not a suffix: every row in a hosted list mounts its
		-- minus with the identical two node ids under a per-list overlay, so a
		-- suffix match would let row 2's minus delete row 1. Standalone keeps its
		-- suffix form — `idPattern` is this row's own unique id, which is what makes
		-- the suffix unambiguous there.
		local editAffordancePattern = if hostedPaths ~= nil
			then (if hostedEditPath ~= nil then `^{patternEscape(hostedEditPath)}$` else nil)
			else `/{idPattern}/EditAffordanceWhen/then/EditAffordance$`

		-- REDTEAM FIX (item 3, MAJOR): a direct tap/Activate on a REVEALED tray
		-- button (this composite's own `handleActivate` below — distinct from
		-- the full-swipe gesture's `doCommit` and the menu's own
		-- `menuHandleActivate`, both of which already ran their callback
		-- through a quarantine) used to call `action.onAction()` bare — an
		-- uncaught throw would escape straight through the presenter's own
		-- Activate dispatch — AND never closed the tray afterward, leaving it
		-- open (and, for a destructive action, the row never collapsing)
		-- after a successful fire. Fixed at the one call site both edges
		-- share: mirrors `menuHandleActivate`'s own edge/role split exactly
		-- (menuAnchor's own comment: "a destructive item runs through
		-- `doCommitAction`... anything else is a quarantined, exactly-once
		-- callback") rather than inventing a third behavior — a destructive
		-- tray button gets the SAME full slide-off+collapse commit sequence a
		-- full swipe or a destructive menu row already gets; a normal one
		-- gets a quarantined fire followed by an ordinary `close()`. `close()`
		-- runs unconditionally after the `pcall` (not gated on success) —
		-- same "a throw must not skip close()" guarantee `doCommitAction`'s
		-- own comment already documents for its own quarantined callback.
		local function fireTrayAction(edge: Edge, action: ActionSpec)
			if action.role == "destructive" then
				local rowW = currentRowWidth()
				local target = if edge == "leading" then rowW else -rowW
				doCommitAction(edge, action, target)
			else
				pcall(action.onAction)
				close()
			end
		end

		-- routes a presenter/tap Activate; returns true when the path was ours
		-- (mirrors popup_button.luau's api.handleActivate).
		local function handleActivate(path: string, _meta: any?): boolean
			-- THE MINUS DELETES. Game-director ruling, 2026-08-13 (parity
			-- round 3, item C), from a device report: a player in edit mode
			-- taps the minus and expects the row to go.
			--
			-- It used to REVEAL the tray instead, and the comment here
			-- justified that as "the iOS pattern". That justification did not
			-- survive being checked: Apple documents the control's APPEARANCE
			-- (`UITableViewCell.EditingStyle.delete` — "a red circle
			-- enclosing a minus sign") and documents that edit mode "provides
			-- controls to delete or move list items", but documents NO
			-- behaviour for tapping it. It was an uncited recollection.
			--
			-- What made the report legitimate rather than a misunderstanding
			-- is one line further down this file: the minus borrows the
			-- destructive action's own accessible `label`, so it ANNOUNCED
			-- itself as "Delete" and then did not delete. The ruling makes
			-- the name true.
			--
			-- ONE FUNNEL, NOT A NEW PATH. `commitDestructive()` is what
			-- keyboard Delete/Backspace and the action menu's destructive
			-- item already call, and it is what carries the full slide-off +
			-- height-collapse sequence — including the C8a fix, where nothing
			-- stands painted once the row is carried clear. Calling
			-- `entry.action.onAction` directly here would have been a bare
			-- callback and a fourth way to delete a row; this file's own
			-- history (`table.luau:1015-1030`, "a third, wholly separate way
			-- to start the identical reorder") is why it is not.
			--
			-- It also subsumes REDTEAM item 6 for free: `commitDestructive`
			-- resolves its edge through `firstDestructiveEntry` ("search
			-- trailing first, then leading"), so a row whose ONLY destructive
			-- action sits on the LEADING edge still deletes. A hard-coded
			-- trailing commit would have been dead there in exactly the way
			-- the old hard-coded `open("trailing")` was.
			--
			-- THE NO-OP GUARD IS GONE ON PURPOSE. It existed because opening
			-- an already-open tray is a meaningless re-retarget. A commit is
			-- not idempotent-by-nature, so the protection that matters is the
			-- one `doCommitAction` already owns — its `committed` latch,
			-- which is what makes a second press during a commit's flight do
			-- nothing (`tests/row_actions_input.spec.luau`, "a re-swipe the
			-- instant a commit clears...").
			if
				hasEditAffordance
				and editAffordancePattern ~= nil
				and string.match(path, editAffordancePattern) ~= nil
			then
				commitDestructive()
				return true
			end
			if leadingActions ~= nil then
				local aid = actionIdFromPath("leading", path)
				local action = if aid ~= nil then actionsById.leading[aid] else nil
				if action ~= nil then
					fireTrayAction("leading", action)
					return true
				end
			end
			if trailingActions ~= nil then
				local aid = actionIdFromPath("trailing", path)
				local action = if aid ~= nil then actionsById.trailing[aid] else nil
				if action ~= nil then
					fireTrayAction("trailing", action)
					return true
				end
			end
			return false
		end
		-- item 11's forwarding seam (see the big comment above
		-- `exposedHandleActivate`): now that the real function exists.
		exposedHandleActivate = handleActivate

		-- LIVE per-button natural width, fed by the contribution's syncGeometry
		-- every sync (Task 4 fix, code review 2026-08-10): `controller.textAt`
		-- publishes the label's font/size at the button's CURRENT path — facts
		-- the renderer already re-derives on a `themeMetrics`/`typographyScale`/
		-- `preferredTextOffset` change — and `text_metrics.measure(..., math.huge)`
		-- re-measures the label at THAT font/size, unconstrained. This never
		-- reads the button's own solved rect (the geometry-feedback bug the
		-- header comment describes), so it is safe to recompute unconditionally
		-- rather than freeze: a `preferredTextSize` bump, a theme swap, or a
		-- reactive label change all reach the reveal on the very next sync.
		-- (`rootPath` itself is declared in the shared scope above — Task 5.)
		local function deriveNaturals(edge: Edge, actions: { ActionSpec }, naturals: { [string]: any })
			if controller == nil then
				return -- no presenter (bare mount): the width props' own fallback stands
			end
			-- Task 2: the tray's own container path — this composite's lazily
			-- mounted `UI.When` subtree in standalone mode, the host's shared
			-- overlay in hosted mode. `nil` = the host declared no tray on this
			-- edge, so there is nothing to measure.
			local trayPath = pathsOf(edge)
			if trayPath == nil then
				return
			end
			local pad = buttonPadPx:get()
			local minWidth = buttonMinWidthPx:get()
			-- A3 (device bug round 2026-08-12, "Mark Read" cut off under Fantasy
			-- Parchment). MEASURE THE REQUIREMENT, NOT THE RENDER
			-- (docs/lessons/measure-the-requirement-not-the-render.md): the room a
			-- tray plate needs is the drawn text PLUS the button's own inner
			-- padding PLUS whatever the installed package's control frame reserves
			-- out of that box. `buttonPad` alone was the flat-theme half of the
			-- sum, so under every framed package the band was reserved (and the
			-- row travelled) exactly one frame too narrow and the label lost the
			-- difference — `docs/lessons/a-fixed-box-cannot-hold-a-themes-frame.md`
			-- in its width form: the plate's `fixed` px is decided HERE, so this
			-- is the one place that can afford the frame for it. Zero on flat
			-- packages, so nothing that already fit moves.
			local chrome = buttonChromePx:get()
			-- A1b (same round): a band wider than the row it belongs to hangs off
			-- the row's far edge — measured at 108px outside a 160px row, with no
			-- diagnostic — and those plates are unreachable. Under a row whose
			-- width is decided FOR it, the naturals share out what there is
			-- instead. `clampable` is what keeps that safe: on a HUG row the
			-- solved width is itself derived from this band (an Anchor hugs its
			-- anchored children), so clamping to it would ratchet the band down to
			-- the content's width and never recover — a row with no cage is
			-- allowed to grow one instead.
			local desired: { [number]: number } = {}
			local desiredTotal = 0
			local measuredCount = 0
			for index, action in actions do
				local facts = controller.textAt(`{trayPath}/Action:{action.id}`)
				if facts == nil or type(facts.font) ~= "string" or type(facts.size) ~= "number" then
					continue -- not yet measured this pass (e.g. the button just mounted)
				end
				-- MEASURE WHAT THE BUTTON DRAWS, not what it is NAMED (director
				-- device round 2026-08-12). An icon-first tray button paints the
				-- framework's glyph for its semantic icon and keeps `label` as the
				-- announced name only, so measuring the label reserved a box for a
				-- word that never lands in it — the "painted at a size nobody
				-- measured for it" family, one step ahead of it this time. Mirrors
				-- `renderer.drawnButtonText`'s own icon branch exactly, including
				-- its fallback: a name with no glyph still draws the label.
				local drawn = action.label
				if action.icon ~= nil then
					drawn = themePackage.iconGlyph(action.icon) or action.label
				end
				local measured = text_metrics.measure(drawn, facts.font, facts.size, math.huge)
				local want = math.max(minWidth, measured.width + 2 * pad + chrome)
				desired[index] = want
				desiredTotal += want
				measuredCount += 1
			end
			-- the band's fixed extras, exactly as `bandExtras` sums them, so the
			-- share-out below is measured against the same total the row travels
			local extras = (#actions - 1) * trayGapPx:get() + rowGutterPx:get()
			local room = if clampable then currentRowWidth() - extras else 0
			local scale = 1
			if clampable and room > 0 and desiredTotal > room and measuredCount == #actions then
				scale = room / desiredTotal
			end
			for index, action in actions do
				local sig = naturals[action.id]
				local want = desired[index]
				if sig == nil or want == nil then
					continue
				end
				sig:set(want * scale)
			end
		end
		-- Task 2: both arguments are optional now. The presenter always passes
		-- both (a contribution's `syncGeometry(rectOf, rootNode)`); a HOST calls
		-- `engine.syncGeometry()` bare from its own sync pass — it has no root
		-- node of this control's to hand over, and `rootPath` was seeded from
		-- `spec.paths.content` at build time rather than learned here.
		local function syncGeometry(_rectOf: ((string) -> any)?, rootNode: any?)
			-- C8a (device round 2026-08-12): the completed commit's deferred paint
			-- restore. FIRST, and ahead of the `rootPath == nil` return below, because
			-- it is the one piece of work here that does not need a path — see
			-- `drainPostCommitRestore`'s own comment above `close()`.
			drainPostCommitRestore()
			if rootNode ~= nil then
				local isFirstRootPath = rootPath == nil
				rootPath = rootNode.path
				if isFirstRootPath then
					-- Task 8 (slider.luau's own two-step precedent: "the path
					-- is LEARNED here... re-ask now that we know what to
					-- compare against"): `bindFocusGraph`/`bindActionSystem`
					-- may both have already run by the time this first sync
					-- lands (both are bound at present time, before the
					-- first `syncGeometry`), so `pathInsideRow` would have
					-- compared against a still-nil `rootPath` and answered
					-- false forever if nothing re-asked once it became known.
					syncKeysEnabled()
				end
			end
			if rootPath == nil then
				return
			end
			if leadingActions ~= nil then
				deriveNaturals("leading", leadingActions, leadingNaturals)
			end
			if trailingActions ~= nil then
				deriveNaturals("trailing", trailingActions, trailingNaturals)
			end
			-- REVIEW FIX (device-video repro, 2026-08-10): re-aiming the spring
			-- here whenever `openEdge` names an edge — regardless of a LIVE
			-- drag — is what a re-grab mid-snap-open-flight actually hits.
			-- `openEdge` is set at RELEASE (`settleTo`), which is exactly when
			-- a re-grab can land: the persistent spring is still flying toward
			-- `leadingWidth`/`trailingWidth`, the player grabs it, axis
			-- resolves horizontal, `onPointerMove` calls `spring:stop()` — and
			-- the VERY NEXT `syncGeometry` (the next `pres.refresh()`, which a
			-- real host frame loop runs every frame right alongside the
			-- pointer move) called `retarget` again unconditionally, undoing
			-- the stop and re-launching the spring at the stale target. Drag
			-- state is this composite's single source of truth for "who owns
			-- `offset` right now" (comment above `DragState`): while ANY
			-- gesture is in flight (`drag ~= nil` — pending, resolving, or
			-- actively horizontal), the drag path through `applySlide` is the
			-- ONLY writer, full stop; a natural-width change reactively re-fed
			-- from `deriveNaturals` above still updates `leadingWidth`/
			-- `trailingWidth` for whenever the NEXT ungated sync runs (right
			-- after release), it just doesn't retarget THIS frame.
			--
			-- REDTEAM FIX (item 1, BLOCKER): the SAME re-aim also has to yield
			-- to a commit already under way, for the identical reason it
			-- yields to a live drag. `doCommitAction` sets `openEdge` to the
			-- committing edge BEFORE its own `retargetThen(offscreenTarget,
			-- ...)` aims the persistent spring off-screen (`committed` is set
			-- true in the very same call, ahead of both) — so with `drag ==
			-- nil` (the gesture already released) this block used to run on
			-- the VERY NEXT refresh and call the plain `retarget(-trailingWidth
			-- :get())` on that SAME spring, overwriting the commit's own
			-- off-screen target back to the merely-open one before the spring
			-- ever got there. The commit's `retargetThen` had already
			-- subscribed its `onSettle`, so the spring still eventually
			-- "arrived" — just at the wrong (open, not off-screen) target —
			-- and the whole collapse+onAction+close chain ran from there:
			-- `onAction` fired at `-trayWidth`, not `-rowWidth`, with no
			-- visible symptom in `#fired`/`_isOpen()` alone. `committed` is
			-- this composite's own single source of truth for "a commit
			-- sequence already owns `offset`/the spring" (see `doCommitAction`
			-- above), so gating on it here is the same shape as gating on
			-- `drag` — never re-aim a value something else already owns.
			if drag == nil and not committed then
				if leadingActions ~= nil and openEdge:get() == "leading" then
					retarget(leadingWidth:get())
				end
				if trailingActions ~= nil and openEdge:get() == "trailing" then
					retarget(-trailingWidth:get())
				end
			end
			-- REDTEAM FIX (item 2, BLOCKER, follow-on): re-read this row's own
			-- live rect and re-aim the menu's presented Anchor at it on EVERY
			-- sync while open — this is what "the list scrolled while the
			-- menu was open" needs (director's ruling offered "re-read the
			-- rect... or close on scroll" as alternatives; this runs on the
			-- exact cadence a real scroll already drives `syncGeometry` at,
			-- asking nothing new of any caller, so re-reading is what is
			-- implemented — the menu tracks the row frame for frame, the same
			-- continuity a plain measured child gave for free before this
			-- fix). A no-op the instant nothing moved (two signal reads, a
			-- write only on an actual change — `core:signal`'s own baseline
			-- no-op-on-same-value behavior).
			if menuOpen:get() then
				-- ...and the FLIP is re-decided here too (ruling 4): a row scrolling
				-- toward the bottom edge with its menu open has to flip as it goes,
				-- for the same reason the position is re-read at all.
				setMenuAnchor(computeMenuAnchor())
			end
		end

		-- THE PRESENTER HANDOFF BUNDLE (Task 2). Built once, used twice: in
		-- standalone/Table mode it is handed to `contribution.attach` below and
		-- the presenter discovers it by walking this control's own mounted node;
		-- in hosted mode there IS no node to walk, so the host forwards the same
		-- members from ITS OWN contribution through the engine api. One table,
		-- so a seam can never be wired in one mode and forgotten in the other.
		contributionFields = {
			handleActivate = handleActivate,
			syncGeometry = syncGeometry,
			-- Task 4: the presenter hands over its motion clock the same way it
			-- hands over the action system/controller/focus graph (see the big
			-- comment above `local motionClock`). No presenter (a bare mount in
			-- a unit test) means this is simply never called, which is exactly
			-- the fallback `retarget` already handles.
			-- Task 5: second, ADDITIVE argument — the same `now` function the
			-- clock itself was built from (contribution.luau bindMotion doc);
			-- `nowFn` is what `currentNow()` (the gesture's velocity-tracker
			-- time source) reads.
			bindMotion = function(clock: any, now: (() -> number)?)
				motionClock = clock
				nowFn = now
				-- ...and its REACTIVE twin. The tray's reveal geometry (`revealFrac`
				-- below) branches on "is there a motion authority at all", and a memo
				-- may not read that off a plain upvalue: `bindMotion` lands at present
				-- time, AFTER the memos are built, and a memo that had already
				-- computed a "no clock" answer would keep serving it until some other
				-- dependency happened to change. The signal is what makes the switch
				-- reach every memo the moment the clock arrives (device round
				-- 2026-08-12 — the same staleness class as the `spring == nil`
				-- fallback this replaced).
				motionBound:set(clock ~= nil)
			end,
			-- Task 4 fix: hands over the render controller — an EXISTING
			-- contribution field, not a new seam — so `deriveNaturals` above can
			-- reach `controller.textAt`. Same absent-means-degrade shape as
			-- `bindMotion`.
			bindController = function(c: any)
				controller = c
			end,
			-- REDTEAM FIX (item 2, BLOCKER): hands over `presentModal`/
			-- `dismiss` — see the big comment above `local function openMenu`
			-- for the full rationale. Same absent-means-degrade shape as
			-- `bindMotion`/`bindController`: a bare mount (no presenter) means
			-- `openMenu` simply has nothing to present onto.
			bindPresent = function(presentModal: any, dismiss: any)
				presentModalFn = presentModal
				dismissFn = dismiss
			end,
			-- Task 8: the action-system + focus-graph handoff that lets
			-- `ensureKeysContext`/`syncKeysEnabled` above bind Delete/
			-- Backspace/ButtonX SCOPED to this row's own mounted subtree
			-- holding focus (see the big comment above
			-- `ROW_ACTIONS_KEY_PRIORITY` for the real scope and the
			-- menu-open carve-out). Either arriving triggers a
			-- re-check; order between the two (and against `syncGeometry`'s
			-- own first-rootPath re-check) is not guaranteed, so all three
			-- call the same idempotent `syncKeysEnabled`.
			bindActionSystem = function(sys: any)
				actionSystemRef = sys
				syncKeysEnabled()
			end,
			bindFocusGraph = function(graph: any)
				focusGraph = graph
				scope:own(core:observe(graph.focused, syncKeysEnabled))
				syncKeysEnabled()
			end,
			-- Task 7 (matrix §B PopupButton parity, popup_button.luau:338-346's
			-- exact shape — see the big comment above `local coordinator`):
			handleCancel = handleCancel,
			outsideDismiss = {
				active = isOpenReadable,
				dismiss = close,
				-- NOT swallowed (round-7 Zone-A lesson): an open tray is a
				-- peripheral affordance on ONE row, not a modal — closing it on
				-- an outside tap must never eat the press that tap was actually
				-- for (another row's own button, e.g.). See presenter.luau's
				-- onNodeTap for the consume/fall-through mechanics this flag
				-- drives.
				consume = false,
			},
			-- DELIBERATELY NO `transientScope` (unlike PopupButton). A
			-- transient POPUP is the only interactive surface worth reaching
			-- while it is up, so trapping focus inside it and restoring the
			-- trigger on close is correct. An open row's tray is the opposite:
			-- it is peripheral to a list a player is still navigating — Tab/
			-- Navigate must keep moving through SIBLING rows while this row's
			-- tray sits open (Task 8's keyboard journey depends on this), and
			-- `transientScope`'s own default `rootPath` (the control root)
			-- would trap focus inside THIS ONE ROW, unable to reach the very
			-- next row in the list. A tray is not a modal; it must never
			-- behave like one.
		}

		if not isHosted then
			blueprint = contribution.attach(root, contributionFields)
		end
	end

	-- ===== Task 2 (hosted): what a shared tray overlay needs =================
	-- ONE Readable answering "which tray, if any, does the host have to be
	-- showing right now, and how far is it revealed" — the whole interface
	-- between this engine and the host's single per-list overlay (design doc
	-- §4: one overlay for the list, never a tray per row, because the
	-- coordinator's one-open policy means at most one row is ever engaged).
	--
	-- The edge answer is the SAME rule the standalone trays' own `revealed`
	-- memos use (built above, inside the blueprint branch): `openEdge` names
	-- it while open, and while a CLOSE flight is still live `openEdge` has
	-- already gone nil but `offset` has not reached 0 yet — an overlay that
	-- unmounted on `openEdge` alone would blink the tray away while the row
	-- is still visibly sliding back over it. Not a duplicate rule so much as
	-- the same one asked once for the pair rather than once per edge.
	--
	-- Built ONLY in hosted mode: a standalone/Table row would pay two live
	-- reactive nodes for something nothing reads (its trays are declarative).
	-- The returned table is one of two STATIC tables, so `trayState` changes
	-- identity only when the edge itself changes — a host `UI.When`/memo over
	-- it does not churn on every pixel of the drag; the pixels ride
	-- `revealPx`, its own signal.
	local trayState: any = nil
	if isHosted then
		local revealPx = scope:own(core:memo(function(use)
			return math.abs(use(offset))
		end))
		local leadingState = if leadingActions ~= nil
			then { edge = "leading" :: Edge, actions = leadingActions, revealPx = revealPx }
			else nil
		local trailingState = if trailingActions ~= nil
			then { edge = "trailing" :: Edge, actions = trailingActions, revealPx = revealPx }
			else nil
		trayState = scope:own(core:memo(function(use)
			local edge = use(openEdge)
			if edge == nil then
				local px = use(offset)
				if px > 0 then
					edge = "leading"
				elseif px < 0 then
					edge = "trailing"
				end
			end
			if edge == "leading" then
				return leadingState
			elseif edge == "trailing" then
				return trailingState
			end
			return nil
		end))
	end

	api = {
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			-- Task 5: set BEFORE tearing the scope down — the commit path's
			-- own guard (see `doCommit`'s comment) reads this synchronously
			-- inside the same `scope:dispose()` call if a spring is settling
			-- mid-teardown.
			disposed = true
			-- REDTEAM FIX (item 2, BLOCKER, follow-on requirement: "dispose
			-- cleanly with the wrapper"). The menu is now a SIBLING presented
			-- surface, never a descendant of this row's own `scope` — disposing
			-- `scope` below tears down THIS row's own mounted tree only, and
			-- would leave an open menu's own handle stranded in the presenter's
			-- `stack` forever (its `transientScope`-equivalent focus trap along
			-- with it) with nothing left alive to ever close it. `closeMenu()`
			-- is idempotent (a no-op via the `menuHandle == nil` guard when no
			-- menu is open), so this is safe unconditionally, same as the
			-- coordinator release below.
			closeMenu()
			-- Task 7: clear this row's coordinator entry BEFORE the scope
			-- (and every spring/signal it owns) tears down — a coordinator
			-- holding a stale reference to a disposed row would call `_close()`
			-- on it the next time something else claims/scrolls, reaching into
			-- a torn-down scope. Unconditional and idempotent (see `release`'s
			-- own comment): correct whether this row was open, mid-gesture, or
			-- never claimed at all.
			if coordinator ~= nil then
				coordinator.release(api)
			end
			scope:dispose()
		end,
		-- internal seam for Table + coordinator (NOT public API; underscore
		-- prefix) — Tasks 6-8 build the touch/keyboard/gamepad paths through
		-- these six:
		_open = open,
		_close = close,
		_isOpen = isOpen,
		_settleTo = settleTo,
		-- REDTEAM FIX (item 7, MAJOR): the coordinator's own `claim` (below,
		-- `row_actions.newCoordinator`) calls this on the row it is claiming
		-- AWAY from — closing that row's TRAY (`_close`) already ran; the
		-- menu (independent state, see the big comment above `local
		-- menuOpen`) needs its own explicit close or a cross-row claim left
		-- it (and its `transientScope` focus trap) armed on a row another
		-- row had just taken over the gesture from.
		_closeMenu = closeMenu,
		-- REDTEAM FIX (item 2, BLOCKER): the menu's own presentModal handle
		-- (nil while closed) — a test-only seam (fake_target's own adapter is
		-- SHARED across every controller a presenter mounts, so
		-- `w.adapter.node(menuPath)` keeps working unchanged, but
		-- `controller.textAt`/`.rectOf` are PER-controller, so a test reading
		-- a live fact about a node inside the menu's own separate surface
		-- needs THIS controller, not the base screen's).
		_menuHandle = function(): any
			return menuHandle
		end,
		-- Task 5: down/move/up/cancel, attached to the Content hit surface
		-- above AND exposed here so Table (Task 10) can compose them with its
		-- own row-level pointer handling instead of only reaching them
		-- through the mounted node.
		_pointerHandlers = pointerHandlers,
		-- Task 5: the commit path minus the gesture — Task 8's keyboard
		-- Delete entry point. `false` when `edge` has no actions (`firstActionFor`
		-- above), which is always true for the true inert-passthrough row (no
		-- leading or trailing actions at all).
		_commitFirst = commitFirst,
		-- REDTEAM FIX (item 11, MEDIUM): forwards a presenter/tap Activate
		-- into this composite's own dispatch — the seam a caller who has
		-- taken over `opts.onActivate` at the presenter (bypassing the
		-- normal contribution walk that would otherwise reach
		-- `handleActivate` directly) needs to keep tray/menu/minus
		-- activations working. Always callable (a safe `false` no-op on a
		-- true inert-passthrough row), see `exposedHandleActivate`'s own
		-- comment above.
		_handleActivate = exposedHandleActivate,
	}

	-- ===== Task 2 (hosted): the host-facing surface =========================
	-- Added only in hosted mode, so the standalone/Table api is byte-identical
	-- to what every existing caller already holds. Three groups:
	--   * `pointerHandlers`/`open`/`close`/`trayState` — the engine proper.
	--     `pointerHandlers` is the SAME table `_pointerHandlers` exposes (the
	--     `(path, pos, rectOf)` contract Table already composes through
	--     `composeWithReorder`), under the undecorated name a host wires
	--     straight onto its own row hit surface.
	--   * the presenter handoffs (`bindMotion`/`bindController`/`bindPresent`/
	--     `bindActionSystem`/`bindFocusGraph`) and `syncGeometry` — the exact
	--     members `contributionFields` carries, which a mounted control gets
	--     from the presenter's own contribution walk and a hosted engine gets
	--     by the host forwarding them from ITS contribution. `bindMotion` is
	--     not optional in practice: the gesture's velocity tracker asserts a
	--     bound `now` (`currentNow`).
	--   * `handleCancel`/`_handleActivate` — the host offers Cancel and routes
	--     an Activate landing inside its own tray overlay back in here.
	--   * `outsideDismiss` — fix round 1, finding 3. `contributionFields`
	--     already carries this (built ONCE, shared by both modes — the header
	--     comment above `contributionFields` itself), and standalone/Table
	--     wires it through `contribution.attach` automatically; a hosted
	--     engine has no node of its own for a presenter's contribution walk to
	--     find it on, so without this forward the seam existed but was simply
	--     unreachable — a host would have had to reinvent "close this row's
	--     tray on an outside tap, without swallowing the tap" (the `consume =
	--     false` rule — see the field's own comment) from scratch, and could
	--     just as easily forget the `consume` rule as get it right. Forwarded
	--     verbatim, same `{ active, dismiss, consume }` shape a presenter's
	--     contribution walk already expects, so a host can hand it straight to
	--     its OWN outside-tap plumbing (the shared overlay's whole reason to
	--     exist) exactly the way `bindMotion`/`bindController`/etc. are handed
	--     back from the host's own contribution.
	-- `_close`/`_closeMenu` come from the shared api above and are what the
	-- COORDINATOR calls on a row it claims away, so a hosted engine is a
	-- first-class coordinator citizen with no adapter of any kind.
	if isHosted then
		api.pointerHandlers = pointerHandlers
		api.open = open
		api.close = close
		api.trayState = trayState
		--[[ THE TRAY BLUEPRINTS, for the host to parent under its own overlay
			(Task 4). The SAME array standalone mode puts in its row root: same
			buttons, same compactLabel ladder, same roles/icons, same width props,
			same reveal `When`s — see `trayViews`' own comment for why there is one
			construction rather than two. The host must mount them under a node
			whose path is what it named in `spec.paths.trayLeading`/`trayTrailing`
			(each `{trayRoot}/{Tray*}When/then/{Tray*}`, this file's own convention
			in both modes), because that is where `deriveNaturals` measures. ]]
		api.trayViews = trayViews
		--[[ THE EDIT-MODE MINUS AND ITS GUTTER (stage 1, 2026-08-15). Both nil
			unless this row can ever show the minus, so a host wires nothing extra for
			a list with no edit mode — and a hosted row that never wires `editing`
			stays byte-identical to what shipped.

			The host parents `editAffordanceView` at the path it named in
			`spec.paths.editAffordance` (refused at build time if it named none), and
			declares `editGutterPx` as the LEFT PADDING of its own row content. A
			padding, not an offset: the director's 2026-08-12 device round (finding 2)
			established that a gutter spent as an offset steps by the whole gutter at
			`offset == 0` and lets a trailing swipe slide the row over its own minus,
			where a padding is spent before `offsetFill` runs and is therefore
			continuous on both signs. `row_actions_root.build`'s own big comment
			carries the arithmetic; the host applies the identical number. ]]
		--[[ ponytail: THE VIEW HANGS OFF AN ENGINE, AND THE MINUS IS PER-ROW.
			Ceiling: a host that shows the minus on every row while editing must hold
			one ENGINE per such row, because that is where the view (and the
			`commitDestructive` its Activate routes into) comes from. The tray overlay
			does not have this problem — the coordinator's one-open policy means at
			most one row is ever engaged — but edit mode is on ALL of them at once, so
			"a closed row mounts NOTHING" degrades to "a closed row mounts nothing
			unless the list is editing" for the windowed case.

			This is bounded and it is the shape the order asked for
			(`docs/plans/table-hosted-row-actions-stage2.md`, item 1: "an
			edit-affordance view the host parents (the `trayViews` shape)"): bounded by
			the window, paid only in an explicit modal state, and exactly what Table's
			WRAP mode already pays unconditionally today. Upgrade path if a hosted
			VirtualList ever wants a per-row minus at zero closed-row cost: the view
			needs only `editingShown` and the destructive action's LABEL, neither of
			which is engine state — so `row_actions_root.buildEditAffordance` can be
			called by a host directly from `spec.rowActions(item)`, with the Activate
			routed through the same build-an-engine-at-press-time path
			`hostedEnsureKeysContext` already uses for keyboard Delete. Not built here:
			no consumer, and stage 4's consumer (Table) holds an engine per actionable
			row already. ]]
		api.editAffordanceView = editAffordanceView
		api.editGutterPx = editGutterPx
		api.syncGeometry = contributionFields.syncGeometry
		api.bindMotion = contributionFields.bindMotion
		api.bindController = contributionFields.bindController
		api.bindPresent = contributionFields.bindPresent
		api.bindActionSystem = contributionFields.bindActionSystem
		api.bindFocusGraph = contributionFields.bindFocusGraph
		api.handleCancel = contributionFields.handleCancel
		api.outsideDismiss = contributionFields.outsideDismiss
		--[[ THE TWO KEY VERBS, for a host standing in for an engine that did not
			exist when the key was pressed (owed row 9; `row_actions.ROW_KEYS`).
			They are the SAME functions this engine's own context calls — the whole
			point is that a press routed by the host and a press routed by the
			engine take one path, so the slide-off/collapse/quarantine sequence and
			the menu's own state guards cannot diverge by host. A host calls these
			only after building the engine, which is what makes "one engine per
			press that needs one" the whole cost of reaching a row by key. ]]
		api.commitDestructive = commitDestructive
		api.toggleMenu = toggleMenu
	end
	return api
end

-- THE STANDALONE/TABLE ENTRY POINT — `Facet.newRowActions`. Unchanged
-- behavior: the whole composite, blueprint and all.
function row_actions.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newRowActions", spec, ROW_ACTIONS_KEYS, "spec")
	return buildEngine(Facet, core, spec, nil)
end

-- THE HOSTED ENTRY POINT (Task 2) — engine only, NO blueprint. Internal, not
-- public API: `newVirtualList`'s own `rowActions` spec key (Task 3) is what a
-- caller reaches, exactly as Table already owns its own row-actions wiring.
-- See the HOSTED MODE comment at the top of this file for the contract, and
-- docs/plans/row-actions-hosted-mode-design.md for why the host owns the
-- nodes.
function row_actions.buildHosted(Facet: any, core: any, spec: HostedSpec): HostedEngine
	specGuard.assertKnownKeys("newRowActionsHosted", spec, HOSTED_KEYS, "spec")
	local id = spec.id or "RowActions"
	local paths: any = spec.paths
	if type(paths) ~= "table" then
		error(
			`Facet newRowActionsHosted('{id}'): \`paths\` is required — a hosted engine mounts nothing of its `
				.. "own, so the host must name the nodes it reads live rects and text facts from",
			0
		)
	end
	specGuard.assertKnownKeys("newRowActionsHosted", paths, HOSTED_PATH_KEYS, "spec.paths")
	if type(paths.content) ~= "string" or paths.content == "" then
		error(`Facet newRowActionsHosted('{id}'): \`paths.content\` must be the host's own row path (a string)`, 0)
	end
	if type(spec.onSlide) ~= "function" then
		error(
			`Facet newRowActionsHosted('{id}'): \`onSlide\` must be a function — the host paints the slide `
				.. "(this engine owns no node to paint)",
			0
		)
	end
	if spec.onCommitHeight ~= nil and type(spec.onCommitHeight) ~= "function" then
		error(`Facet newRowActionsHosted('{id}'): \`onCommitHeight\` must be a function, or nil`, 0)
	end
	-- REFUSED, not silently degraded: a hosted engine with nothing to reveal on
	-- either edge is a host that built a row engine it never needed. The
	-- standalone "inert passthrough" answer (return `content` unwrapped) has no
	-- meaning here — there is no content to hand back.
	if spec.leading == nil and spec.trailing == nil then
		error(
			`Facet newRowActionsHosted('{id}'): a hosted engine needs actions on at least one edge — build no `
				.. "engine at all for a row with none",
			0
		)
	end
	-- fix round 1, finding 1: a declared edge with no tray path for that edge
	-- used to degrade SILENTLY rather than refuse. Without `paths.trayLeading`/
	-- `paths.trayTrailing`, `pathsOf(edge)` (above) answers `nil` for that
	-- edge, `deriveNaturals` returns early forever (never measures a natural
	-- width), `targetFor(edge)` stays 0 (leadingWidth/trailingWidth never grow
	-- past their zero start), and `_open`/a gesture past the axis lock still
	-- sets `openEdge` and claims the coordinator — so the row LOOKS open to
	-- every piece of state that matters (`_isOpen()` is true, the coordinator
	-- thinks it owns the claim) while `offset` never leaves 0 and no tray ever
	-- paints. Every symptom the review named: refused by name, at build time,
	-- instead.
	if spec.leading ~= nil and (type(paths.trayLeading) ~= "string" or paths.trayLeading == "") then
		error(
			`Facet newRowActionsHosted('{id}'): \`leading\` actions require \`paths.trayLeading\` (the host's `
				.. "own leading tray container path) — without it the tray can never be measured or found to "
				.. "paint, and the row would silently claim to be open with nothing revealed",
			0
		)
	end
	if spec.trailing ~= nil and (type(paths.trayTrailing) ~= "string" or paths.trayTrailing == "") then
		error(
			`Facet newRowActionsHosted('{id}'): \`trailing\` actions require \`paths.trayTrailing\` (the host's `
				.. "own trailing tray container path) — without it the tray can never be measured or found to "
				.. "paint, and the row would silently claim to be open with nothing revealed",
			0
		)
	end
	return buildEngine(Facet, core, spec, {
		paths = paths,
		onSlide = spec.onSlide,
		onCommitHeight = spec.onCommitHeight,
	}) :: HostedEngine
end

-- ===== Task 10: reorder composition (Table integration) ====================
-- LIVES IN `row_actions_reorder.luau` (2026-08-14). It is a top-level arbiter
-- over two handler TABLES — one `pending` record per live gesture, nothing
-- shared with `buildEngine` — so it moved out whole when this file had to shed
-- periphery to get back under the 200,000-char `Script.Source` WRITE cap.
-- RE-EXPORTED HERE UNDER ITS SHIPPED NAME: `table.luau` calls this exact field
-- as `row_actions.composeWithReorder`. The axis-lock rule it applies is still
-- authored in exactly one place, `row_actions_state.AXIS_LOCK_PX`, which the
-- engine's own `onPointerMove` in this file reads too.
row_actions.composeWithReorder = rowActionsReorder.compose

return row_actions
