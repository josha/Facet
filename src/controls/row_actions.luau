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
-- remaining ingredient — `buttonPad`/`buttonMinWidth` in pixels — is a
-- theme fact with no font/size component, resolved the same way
-- `table.luau` resolves its own theme metrics (`spec.env`, optional,
-- degrades to `themeSnapshot.neutral()`).
--
-- DESTRUCTIVE COLOUR. `UI.Button` already carries a semantic `role` prop
-- (`enum = { "default", "cancel", "destructive" }`, src/blueprint_schema.luau)
-- that "drives a style tag and its sheet rule" — the exact shipped `danger`/
-- `onDanger` pair (src/tokens/sheet_model.luau: `buttonRole == "destructive"`
-- -> tag `luau-role-destructive`). An ActionSpec's `role = "destructive"`
-- maps straight to it; `role = "normal"` (or absent) leaves the Button at its
-- own default role, which already paints the control/content pair. No new
-- color token, no bespoke fill — reusing exactly what Task 2's docs promised.

local contribution = require("../input/contribution")
local row_actions_state = require("../input/row_actions_state")
local drag_velocity = require("../input/drag_velocity")
local themeSnapshot = require("../themes/snapshot")
local text_metrics = require("../layout/text_metrics")
local specGuard = require("../spec_guard")

local row_actions = {}

export type Edge = "leading" | "trailing"

export type ActionSpec = {
	id: string?, -- defaults to label
	role: ("normal" | "destructive")?, -- destructive paints danger/onDanger
	label: string,
	icon: string?, -- standard_icons name; nil = text only
	onAction: () -> (),
}

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
}

export type HostedSpec = {
	id: string?,
	leading: { ActionSpec }?,
	trailing: { ActionSpec }?,
	fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?,
	coordinator: any?,
	env: any?,
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
	"editing",
	"externalGesture",
	"width",
})
-- The hosted spec is NOT the standalone spec plus three keys: `content`,
-- `width`, `editing` and `externalGesture` are all statements about a
-- blueprint this mode never builds (`externalGesture` is implied — there is
-- no internal Hit Grip to suppress), so each is refused by name rather than
-- silently ignored.
local HOSTED_KEYS = specGuard.keySet({
	"id",
	"leading",
	"trailing",
	"fullSwipe",
	"coordinator",
	"env",
	"paths",
	"onSlide",
	"onCommitHeight",
})
local HOSTED_PATH_KEYS = specGuard.keySet({ "content", "trayLeading", "trayTrailing" })
local ACTION_KEYS = specGuard.keySet({ "id", "role", "label", "icon", "onAction" })
local FULL_SWIPE_KEYS = specGuard.keySet({ "leading", "trailing" })

-- THEME METRICS (Task 2; ADR-0019 §2). A tray button never sits narrower than
-- `buttonMinWidth` — the localization floor — and `buttonPad` is its inner
-- horizontal padding. Theme strings only; resolved by the solver exactly like
-- `slider.luau`'s `THUMB_SIZE`/`RAIL_HEIGHT`.
local BUTTON_MIN_WIDTH = "controls.rowActions.buttonMinWidth"
local BUTTON_PAD = "controls.rowActions.buttonPad"
-- Task 9: the edit-mode leading minus' diameter (both axes — `shape = "circle"`
-- below takes only ONE authored axis and derives the other).
local EDIT_AFFORDANCE = "controls.rowActions.editAffordance"

-- a node id is interpolated into a Lua PATTERN below (handleActivate's path
-- match), so its magic characters have to be escaped first — same helper,
-- same reason, as popup_button.luau/table.luau/text_input.luau/virtual_list.luau.
local function patternEscape(s: string): string
	return (s:gsub("%W", "%%%0"))
end

-- Task 8: "is `path` inside `prefix`'s own subtree" — the same 2-line
-- definition src/present/focus_map.luau and src/layout/text_audit.luau each
-- keep a private copy of (a leaf utility duplicated rather than reached for
-- across the present/ layer a control must not depend on). Used to answer
-- "does focus currently sit somewhere inside this row's OWN mounted
-- subtree" (content, a revealed tray button, or an open menu row — not
-- `content` alone; see `pathInsideRow`'s own comment below for why) from
-- the live path `bindFocusGraph` hands over.
local function isPathPrefix(prefix: string, path: string): boolean
	return path == prefix or string.sub(path, 1, #prefix + 1) == prefix .. "/"
end

local function trayId(edge: Edge): string
	return if edge == "leading" then "TrayLeading" else "TrayTrailing"
end

-- validate ONE ActionSpec entry, naming the edge and index in every error so
-- a bad row in a five-action tray is not a guessing game. `label` is the
-- CALLING entry point's own public name (`newRowActions` or
-- `newRowActionsHosted` — fix round 1, finding 5): this validation is shared,
-- unconditional code (`buildEngine` calls it for both modes), and a hosted
-- caller's bad ActionSpec used to get an error naming the WRONG entry point
-- (always the literal `"newRowActions"`) — greppable but misleading.
local function buildActionSpec(label: string, rowId: string, edge: Edge, index: number, raw: any): ActionSpec
	if type(raw) ~= "table" then
		error(`LuauUI {label}('{rowId}'): \`{edge}[{index}]\` must be a table (ActionSpec)`, 0)
	end
	specGuard.assertKnownKeys(label, raw, ACTION_KEYS, `spec.{edge}[{index}]`)
	if type(raw.label) ~= "string" or raw.label == "" then
		error(`LuauUI {label}('{rowId}'): \`{edge}[{index}].label\` must be a non-empty string`, 0)
	end
	local role = raw.role
	if role ~= nil and role ~= "normal" and role ~= "destructive" then
		error(
			`LuauUI {label}('{rowId}'): \`{edge}[{index}].role\` '{tostring(role)}' is not a role. `
				.. "Valid: normal, destructive.",
			0
		)
	end
	if type(raw.onAction) ~= "function" then
		error(`LuauUI {label}('{rowId}'): \`{edge}[{index}].onAction\` must be a function`, 0)
	end
	local actionId = if raw.id ~= nil then raw.id else raw.label
	if type(actionId) ~= "string" or actionId == "" then
		error(`LuauUI {label}('{rowId}'): \`{edge}[{index}].id\` must be a non-empty string`, 0)
	end
	if string.find(actionId, "/", 1, true) ~= nil then
		error(`LuauUI {label}('{rowId}'): {edge} action id '{actionId}' must be path-safe (no "/")`, 0)
	end
	return {
		id = actionId,
		role = role,
		label = raw.label,
		icon = raw.icon,
		onAction = raw.onAction,
	}
end

-- `nil` = "no actions on this edge" (legal, common); `{}` is very likely an
-- authoring mistake (a caller that meant to omit the edge, or forgot to fill
-- it in) — refused loudly rather than silently rendering an empty tray.
-- `label` — see `buildActionSpec`'s own comment above.
local function actionsFor(label: string, rowId: string, edge: Edge, raw: any): { ActionSpec }?
	if raw == nil then
		return nil
	end
	if type(raw) ~= "table" then
		error(`LuauUI {label}('{rowId}'): \`{edge}\` must be an array of ActionSpec, or nil for none`, 0)
	end
	if #raw == 0 then
		error(
			`LuauUI {label}('{rowId}'): \`{edge}\` is an empty table — use nil for "no actions on this `
				.. `edge", not \{\}`,
			0
		)
	end
	local out: { ActionSpec } = {}
	for i, entry in raw do
		table.insert(out, buildActionSpec(label, rowId, edge, i, entry))
	end
	return out
end

-- `label` — see `buildActionSpec`'s own comment above.
local function normalizeFullSwipe(label: string, rowId: string, raw: any): { leading: boolean, trailing: boolean }
	if raw == nil then
		return { leading = true, trailing = true }
	end
	if type(raw) == "boolean" then
		return { leading = raw, trailing = raw }
	end
	if type(raw) == "table" then
		specGuard.assertKnownKeys(label, raw, FULL_SWIPE_KEYS, "spec.fullSwipe")
		local leading = if raw.leading == nil then true else raw.leading
		local trailing = if raw.trailing == nil then true else raw.trailing
		if type(leading) ~= "boolean" or type(trailing) ~= "boolean" then
			error(`LuauUI {label}('{rowId}'): \`fullSwipe.leading\`/\`trailing\` must be booleans`, 0)
		end
		return { leading = leading, trailing = trailing }
	end
	error(`LuauUI {label}('{rowId}'): \`fullSwipe\` must be a boolean or \{ leading?, trailing? \}`, 0)
end

-- ===== Task 7: the open-state coordinator =====================================
-- PUBLIC API (`LuauUI.newRowActionsCoordinator`, director decision
-- 2026-08-09): at most one row open per shared list surface. A VStack/
-- ScrollView list builds its own and passes it to every wrapped row's
-- `coordinator` spec key; Table (Task 10) does the identical wiring for its
-- own `rowActions` rows automatically. Standalone `newRowActions` use with no
-- coordinator stays valid — every claim/release call in `row_actions.build`
-- below is already guarded on `coordinator ~= nil`, so an instance with none
-- only ever manages itself, byte-identical to Tasks 3-6.
--
-- IDENTITY. The row instance IS its own handle here — the exact table
-- `row_actions.build` returns (`api` in that function, the same object a
-- caller already holds) — never a second wrapper/id scheme `claim`/`release`
-- would have to keep in sync with the real one.
--
-- `core` is accepted (not `_core`) for the same construction signature every
-- other `new*` factory in this module family uses, though nothing here reads
-- it today: the registry is three closures over one plain local, not
-- reactive state — there is nothing here a caller could usefully `core:observe`.
function row_actions.newCoordinator(core: any): any
	local claimed: any = nil -- the currently-open row instance's own API table, or nil

	-- called from a row (see `open`/`onPointerMove`'s axis-lock crossing in
	-- `row_actions.build`): closes whatever OTHER row is currently claimed via
	-- ITS OWN `_close` — spring-animated, or an instant snap under reduced
	-- motion / no bound motion clock, `close`'s existing behavior, entirely
	-- unchanged by going through the coordinator — then claims `instance`.
	-- Re-claiming the row that is already claimed is a harmless no-op past the
	-- identity check.
	--
	-- REDTEAM FIX (item 7, MAJOR, cross-row half): `_close()` alone only
	-- ever closed the claimed-away row's TRAY. Its MENU (independent state
	-- — `row_actions.build`'s own comment above `local menuOpen`) is a
	-- SEPARATE popup that a row can have open with no tray revealed at all,
	-- so a sibling row beginning a horizontal gesture (claiming here) used
	-- to leave the previously-open row's menu — and its `transientScope`
	-- focus trap — stranded, armed on a row the player was no longer
	-- looking at. `_closeMenu()` runs unconditionally alongside `_close()`
	-- for the identical reason: idempotent (a no-op via `menuOpen:set(false)`
	-- on a row whose menu was never open), so this never has to ask first.
	local function claim(instance: any)
		if claimed ~= nil and claimed ~= instance then
			-- captured BEFORE calling `_close()`: `close()` itself calls
			-- `coordinator.release(api)` (row_actions.build), which mutates
			-- THIS SAME `claimed` upvalue back to `nil` as a side effect —
			-- reading `claimed` again afterward would already be nil.
			local previous = claimed
			previous._close()
			previous._closeMenu()
		end
		claimed = instance
	end

	-- called from a row's own `close()`/`dispose()`. Idempotent BY DESIGN: a
	-- row that was never claimed (it settled back to closed without ever
	-- crossing the axis lock, say) releases unconditionally on every close and
	-- on dispose without first checking whether it actually holds the claim.
	local function release(instance: any)
		if claimed == instance then
			claimed = nil
		end
	end

	-- ANY scroll movement closes the open row — no distance/velocity
	-- threshold, matching iOS. A thin pass-through onto
	-- `controller.observeScroll` (table.luau:2178's own native-scroll-mirror
	-- call, the shipped precedent for a control binding this after present());
	-- returns the same unsubscribe `observeScroll` itself returns, so the
	-- consumer that called `bindScroll` owns tearing it down (present-time
	-- wiring, same shape as `Table.bindNativeScroll`).
	local function bindScroll(controller: any, path: string): () -> ()
		return controller.observeScroll(path, function()
			if claimed ~= nil then
				claimed._close()
			end
		end)
	end

	return {
		claim = claim,
		release = release,
		bindScroll = bindScroll,
	}
end

-- THE ONE ENGINE (Task 2). `row_actions.build` and `row_actions.buildHosted`
-- (both at the bottom of this file) are the two entry points into this single
-- function — the state signals, axis lock, velocity tracker, coordinator
-- claim, commit ladder, menu and keyboard bindings are all shared code, never
-- a fork. `hosted == nil` is the standalone/Table composite (blueprint and
-- all); `hosted ~= nil` skips every node this file would otherwise build and
-- routes the two things a node used to answer — paths and paint — through
-- `pathsOf`/`applySlide` below. Each entry point validates its OWN spec
-- against its own closed key set before calling in here.
local function buildEngine(LuauUI: any, core: any, spec: any, hosted: HostedOpts?)
	local UI = LuauUI.UI
	local id = spec.id or "RowActions"
	local scope = core:scope("row-actions-" .. tostring(id))
	-- read once: `hosted` is a build-time fact, never live
	local isHosted = hosted ~= nil
	-- fix round 1, finding 5: every error this shared function (and the
	-- validation helpers it calls — `actionsFor`/`buildActionSpec`/
	-- `normalizeFullSwipe`) raises names the CALLING entry point, not always
	-- the standalone one. Both `row_actions.build` and `row_actions.buildHosted`
	-- already assert their OWN closed key set under their own name before
	-- ever reaching here (`"newRowActions"`/`"newRowActionsHosted"` at the
	-- `assertKnownKeys` call sites) — this is that same label, reused for
	-- every OTHER error this shared body can still raise.
	local label = if isHosted then "newRowActionsHosted" else "newRowActions"

	if not isHosted and (type(spec.content) ~= "table" or (spec.content :: any).class == nil) then
		error(`LuauUI {label}('{id}'): \`content\` is required and must be a Blueprint`, 0)
	end
	-- nil in hosted mode: the HOST mounts the row, this engine wraps nothing
	local content = spec.content

	if spec.coordinator ~= nil and type(spec.coordinator) ~= "table" then
		error(
			`LuauUI {label}('{id}'): \`coordinator\` must be a table (the value newRowActionsCoordinator `
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
			`LuauUI {label}: rows sharing a coordinator must carry unique ids `
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
	-- published check (`blueprint.isReadable`, exposed as `LuauUI.UI.isReadable`
	-- — `async_image.luau`'s own precedent for reaching it from a control).
	if spec.editing ~= nil and not UI.isReadable(spec.editing) then
		error(
			`LuauUI {label}('{id}'): \`editing\` must be a Readable<boolean> (a signal or memo), or nil `
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
	-- REDTEAM FIX (item 1, BLOCKER): incremented once per commit that
	-- actually starts (`doCommitAction`'s destructive branch); the two
	-- `onSettle` chains it launches capture the value at start and refuse to
	-- run past a generation that has moved on. See `doCommitAction`'s own
	-- comment for why this exists on top of `committed`/`disposed` alone.
	local commitEpoch = 0

	-- per-action NATURAL (unconstrained) width — a live-derived signal, one per
	-- declared action, created eagerly at BUILD time rather than inside the
	-- tray's lazy `UI.When` factory. A reactive value created INSIDE that
	-- factory would be a FRESH `core:memo` every remount (Trays mount lazily;
	-- a row can open and close many times), which `scope:own` would dutifully
	-- own and never release until this whole composite disposes — a slow leak
	-- shaped exactly like the "table with no dispose()" mistake
	-- scope_impl.luau's own `own()` guards against, just one level up (a table
	-- WITH a dispose(), that nothing ever calls). Building it once, here, and
	-- having the tray factory below only ever LOOK UP an existing entry, means
	-- every open/close cycle reuses the same handful of reactive nodes.
	--
	-- The signal itself is written by `syncGeometry`/`deriveNaturals` below,
	-- on EVERY sync (not frozen — see the TRAY WIDTH header comment): a plain
	-- `core:signal`, not a memo, because the write happens from an external
	-- hook (the presenter's geometry broadcast), not from a `use()`-tracked
	-- computation.
	local leadingNaturals: { [string]: any } = {}
	for _, action in leadingActions or {} do
		leadingNaturals[action.id] = scope:own(core:signal(nil :: number?))
	end
	local trailingNaturals: { [string]: any } = {}
	for _, action in trailingActions or {} do
		trailingNaturals[action.id] = scope:own(core:signal(nil :: number?))
	end
	local function sumNaturals(naturals: { [string]: any }, use: (any) -> any): number
		local total = 0
		for _, sig in naturals do
			local v = use(sig)
			if v ~= nil then
				total += v
			end
		end
		return total
	end
	-- the tray's total width IS the sum of its buttons' naturals — never the
	-- tray CONTAINER's own solved rect (that WAS the feedback-loop bug: a
	-- number this same reveal can shrink, chasing a collapsing target). The
	-- naturals themselves are geometry-free (see above), so this sum moves
	-- live with a label/text-size/theme change and can never chase itself.
	local leadingWidth = scope:own(core:memo(function(use)
		return sumNaturals(leadingNaturals, use)
	end))
	local trailingWidth = scope:own(core:memo(function(use)
		return sumNaturals(trailingNaturals, use)
	end))

	-- ===== theme-resolved chrome (Task 4 fix) ================================
	-- `buttonPad`/`buttonMinWidth` are theme facts with no font/size
	-- component (unlike the label's own font/size, which arrive already
	-- resolved through `controller.textAt` — see `deriveNaturals` below), so
	-- they need the environment's theme snapshot directly. `spec.env` is
	-- optional, exactly `table.luau`'s own `metricsOr`/`rowGapPx` pattern:
	-- absent degrades to `themeSnapshot.neutral()`, present and live re-solves
	-- on a runtime theme swap (`env:get("themeMetrics")` is itself reactive).
	local function metricsOr(raw: any): any
		return if type(raw) == "table" and type(raw.controls) == "table" then raw else themeSnapshot.neutral()
	end
	local metricsSig = scope:own(core:memo(function(use)
		local env = spec.env
		if env == nil then
			return themeSnapshot.neutral()
		end
		return metricsOr(use(env:get("themeMetrics")))
	end))
	local buttonPadPx = scope:own(core:memo(function(use)
		return themeSnapshot.resolveNumber(use(metricsSig), BUTTON_PAD) or 0
	end))
	local buttonMinWidthPx = scope:own(core:memo(function(use)
		return themeSnapshot.resolveNumber(use(metricsSig), BUTTON_MIN_WIDTH) or 0
	end))

	-- ===== Task 9: the edit-mode gutter (leading minus + content/leading-tray
	-- shift) — built ONLY when it can ever matter (`hasEditAffordance`), so a
	-- caller who never wires `editing` adds none of these reactive nodes.
	--
	-- `editGutterPx` is the ONE live pixel amount both Content's rendered
	-- offsetX (below) and the leading tray's own offsetX (`buildTray`) read: 0
	-- when not currently editing, `editAffordancePx` (the resolved
	-- `controls.rowActions.editAffordance` metric, live to a theme swap
	-- exactly like `buttonPadPx`/`buttonMinWidthPx` above) while editing. A
	-- SEPARATE signal from `offset` (Task 5's gesture/spring seam) by design —
	-- see the big comment above `local editingReadable` and the one above
	-- `contentOffsetX` below for why the two must never merge into one write.
	local editAffordanceShown: any = nil
	local editGutterPx: any = nil
	if hasEditAffordance then
		editAffordanceShown = scope:own(core:memo(function(use)
			return use(editingReadable) == true
		end))
		local editAffordancePx = scope:own(core:memo(function(use)
			return themeSnapshot.resolveNumber(use(metricsSig), EDIT_AFFORDANCE) or 0
		end))
		editGutterPx = scope:own(core:memo(function(use)
			if use(editAffordanceShown) then
				return use(editAffordancePx)
			end
			return 0
		end))
	end

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
		if coordinator ~= nil then
			coordinator.release(api)
		end
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
	local menuOy = scope:own(core:signal(0))
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

	-- like `retarget`, but calls `onArrive` exactly once when the value
	-- reaches its target: a spring settle (subscribed BEFORE retargeting, so
	-- a reduced-motion synchronous placement — motion.luau `setTarget`'s
	-- `placeNow(v, true)` — still reaches it), or immediately under the
	-- no-clock fallback. The seam the commit sequence below chains
	-- slide-off -> collapse -> fire through. `unsub`s itself the moment it
	-- fires, so a LATER, unrelated retarget of the same persistent spring
	-- (an `_open`/`_close` after a commit that did not destroy this row)
	-- can never re-trigger it.
	local function retargetThen(px: number, onArrive: () -> ())
		if motionClock ~= nil then
			ensureSpring()
			local unsub: (() -> ())? = nil
			unsub = spring:onSettle(function()
				if unsub ~= nil then
					unsub()
				end
				onArrive()
			end)
			spring:setTarget(px)
		else
			applySlide(px)
			onArrive()
		end
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
	-- guarantee `retargetThen`/`collapseThen`'s own self-unsubscribing
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
		retargetThen(offscreenTarget, function()
			if disposed or commitEpoch ~= myEpoch then
				return
			end
			local startHeight = currentRowHeight()
			collapseThen(startHeight, function()
				if disposed or commitEpoch ~= myEpoch then
					return
				end
				-- QUARANTINED (constitution): the ONE user callback this
				-- composite ever fires on a caller's behalf. A throw must
				-- not skip `resetToClosed()` below, nor fire a second time —
				-- `committed` already forbids a second commit, and this
				-- whole chain only ever runs once per row.
				pcall(action.onAction)
				-- the ONE place allowed to clear `committed` mid-flight (see
				-- `resetToClosed`'s own comment above `close()`): this IS the
				-- commit's own natural completion, not an external cancel —
				-- `close()` itself would no-op here since `committed` is
				-- still true.
				resetToClosed()
			end)
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
			-- unreachable in practice (row_actions_state only ever proposes a
			-- commit against a real, positive tray width, which always has an
			-- action behind it) — stay honest and settle normally rather than
			-- silently doing nothing if that invariant is ever wrong.
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
	local MENU_ROW_HEIGHT = "controlSizes.compact.height" -- same theme
	-- token popup_button.luau's own compact-menu row uses (ADR-0019 §2);
	-- no new theme surface needed.
	local function buildMenuRows(): { any }
		local rows = {}
		for _, entry in menuItemsOrdered do
			table.insert(
				rows,
				UI.Button({
					id = "Action:" .. entry.action.id,
					label = entry.action.label,
					-- same reasoning as the tray build above: `icon` alone
					-- needs `shape = "circle"`, and a menu row keeps its
					-- label, so the action icon rides `compactLabel`. A
					-- fill-width menu row rarely runs out of room, so this
					-- mostly keeps the label — that is the correct default
					-- for a menu, not a defect.
					compactLabel = if entry.action.icon ~= nil then { icon = entry.action.icon } else nil,
					role = if entry.action.role == "destructive" then "destructive" else "default",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = MENU_ROW_HEIGHT },
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

	-- live anchor position: `srcRect` is THIS row's own solved window-space
	-- rect (`controller`/`rootPath` — the SAME facts `currentRect` above
	-- reads); the menu opens just below the row's own left edge, matching
	-- `popup_button.luau`'s own "menu" placement (`offsetY = TRIGGER_HEIGHT`,
	-- just below the trigger) translated into absolute window-space
	-- coordinates rather than a relative offset (this Anchor's own parent
	-- is a full-viewport `edgeToEdge` screen root, not the trigger itself).
	-- Absent `controller`/`rootPath` (no presenter, or the very first frame
	-- before any solve — `openMenu` never runs at all without `controller`,
	-- see its own guard below) degrades to `0, 0` rather than erroring.
	local function computeMenuAnchor(): (number, number)
		local path = pathsOf()
		if controller == nil or path == nil then
			return 0, 0
		end
		local rect = controller.screenRectOf(path)
		if rect == nil then
			return 0, 0
		end
		return rect.x, rect.y + rect.h
	end

	local function buildMenuBlueprint(): any
		return UI.Screen({
			id = MENU_SURFACE_ID,
			children = {
				contribution.attach(
					UI.Anchor({
						id = MENU_ROOT_ID,
						anchor = "topLeft",
						offsetX = menuOx,
						offsetY = menuOy,
						children = {
							UI.VStack({
								id = "MenuRows",
								surface = "raised",
								gap = "strokes.hairline",
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
		local ox, oy = computeMenuAnchor()
		menuOx:set(ox)
		menuOy:set(oy)
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
	local ROW_ACTIONS_KEY_PRIORITY = 10000
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
			deleteAction.bind({ keyCode = "Delete" })
			deleteAction.bind({ keyCode = "Backspace" })
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
		menuAction.bind({ keyCode = "ButtonX" })
		menuAction.bind({ keyCode = "Return", modifiers = { shift = true } })
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
			`LuauUI {label}('{id}'): a pointer gesture reached _pointerHandlers with no bound \`now\` `
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
				spring:setVelocity(vx)
			end
			settleTo(verdict)
		else
			-- "pending" (a tap, never past the lock radius) or "vertical"
			-- (declined): nothing this gesture touched needs undoing
			drag = nil
		end
	end

	local function onPointerCancel(_path: string, _reason: string?): boolean?
		if drag == nil then
			return nil
		end
		local wasHorizontal = drag.axis == "horizontal"
		drag = nil
		if wasHorizontal then
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
			schema = "luauui-rowactions-dump/1",
			id = id,
			offset = offset:get(),
			openEdge = edge,
			phase = phase,
			-- Task 8: the action menu's own open state, independent of the
			-- tray's `openEdge`/`phase` above.
			menuOpen = menuOpen:get(),
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
		if not isHosted then
			-- per-action WIDTH prop: one `core:memo` per declared action, built HERE
			-- (not inside `buildTray`'s lazy factory) for the identical reuse-not-
			-- leak reason as the naturals above. Unmeasured, or no spring at all
			-- (the fallback) — keeps Task 3's shape exactly (`minMax`, floored,
			-- content-sized, static, and it stays live even once measured — the
			-- fallback and the derived branch both track the SAME live `natural`
			-- signal, so neither ever goes stale); once its natural width IS known
			-- it reads its share of the SAME observed `offset` the slide itself
			-- uses — no second spring, no per-button spring — so a button
			-- "stretches in" from 0 toward its (live) natural width as `|offset|`
			-- approaches `trayWidth` (docs/plans/row-actions-implementation.md
			-- Task 4: "SwiftUI feel").
			local function buildWidthProps(naturals: { [string]: any }, traySig: any, actions: { ActionSpec })
				local props: { [string]: any } = {}
				for _, action in actions do
					local natural = naturals[action.id]
					props[action.id] = scope:own(core:memo(function(use)
						local n = use(natural)
						if spring == nil or n == nil then
							return { type = "minMax", min = BUTTON_MIN_WIDTH }
						end
						local trayW = use(traySig)
						local frac = if trayW > 0 then math.clamp(math.abs(use(offset)) / trayW, 0, 1) else 0
						return { type = "fixed", px = math.floor(n * frac + 0.5) }
					end))
				end
				return props
			end
			local leadingWidthProps = buildWidthProps(leadingNaturals, leadingWidth, leadingActions or {})
			local trailingWidthProps = buildWidthProps(trailingNaturals, trailingWidth, trailingActions or {})

			local function buildTray(edge: Edge, actions: { ActionSpec })
				local widthProps = if edge == "leading" then leadingWidthProps else trailingWidthProps
				local buttons = {}
				for _, action in actions do
					table.insert(
						buttons,
						UI.Button({
							id = "Action:" .. action.id,
							label = action.label,
							-- `Button.icon` (the top-level prop) is circle-only —
							-- a tray button is rectangular and keeps its label, so
							-- an action icon rides `compactLabel` instead: full
							-- label when the button has room (the common case, at
							-- its natural/settled width), the framework icon when
							-- it does not (mid-swipe, `widthProps` shrinks this
							-- toward BUTTON_MIN_WIDTH as the tray reveals) — the
							-- same "says less when there is less room" ladder
							-- every other compactLabel caller gets, not a new one.
							compactLabel = if action.icon ~= nil then { icon = action.icon } else nil,
							role = if action.role == "destructive" then "destructive" else "default",
							width = widthProps[action.id],
							height = { type = "fill" },
							padding = { left = BUTTON_PAD, right = BUTTON_PAD },
						})
					)
				end
				return UI.HStack({
					id = trayId(edge),
					anchor = if edge == "leading" then "left" else "right",
					-- Task 9: the LEADING tray shifts right by the same live gutter
					-- Content does below, so the two compose instead of colliding —
					-- "the minus sits outside the leading tray's reveal" (brief). The
					-- trailing tray needs no such term: it is anchored to the row's
					-- OWN right edge, untouched by a LEADING-side gutter.
					offsetX = if edge == "leading" then editGutterPx else nil,
					height = { type = "fill" },
					children = buttons,
				})
			end

			local children = {}
			if leadingActions ~= nil then
				-- MOUNTED WHILE OPEN, **OR** WHILE THE CLOSE FLIGHT IS STILL LIVE
				-- (Task 4). `openEdge` flips the instant `close()`/a new `open()` on
				-- the other edge is called, but the spring keeps animating `offset`
				-- back toward 0 over several frames — unmounting on `openEdge`
				-- alone would make the tray vanish INSTANTLY while Content is still
				-- visibly sliding back over empty space. Reusing `offset` (the same
				-- signal `Content.offsetX` and the width props above already read)
				-- keeps the outgoing tray mounted for exactly as long as it is
				-- still on screen, with no new coupling.
				local revealed = scope:own(core:memo(function(use)
					if use(openEdge) == "leading" then
						return true
					end
					return use(offset) > 0
				end))
				table.insert(
					children,
					UI.When({
						id = "TrayLeadingWhen",
						condition = revealed,
						thenView = function()
							return buildTray("leading", leadingActions :: { ActionSpec })
						end,
					})
				)
			end
			if trailingActions ~= nil then
				local revealed = scope:own(core:memo(function(use)
					if use(openEdge) == "trailing" then
						return true
					end
					return use(offset) < 0
				end))
				table.insert(
					children,
					UI.When({
						id = "TrayTrailingWhen",
						condition = revealed,
						thenView = function()
							return buildTray("trailing", trailingActions :: { ActionSpec })
						end,
					})
				)
			end

			-- ===== Task 9: the edit-mode leading minus =============================
			-- iOS pattern: while editing AND a destructive action exists somewhere,
			-- a small circular button sits in a LEADING gutter; tapping it opens the
			-- trailing tray (the destructive action is a second tap away, never
			-- direct). `UI.When` keyed on `editAffordanceShown` — the identical
			-- lazy-mount idiom the trays already use (Task 3's own header comment;
			-- `table.luau:1079-1122`'s `EditWhen` is the cited precedent): zero
			-- Instances while not editing, beyond the one permanent `Frame` a
			-- mounted-but-closed `UI.When` always costs — paid only when
			-- `hasEditAffordance`, i.e. only when a caller actually wires `editing`
			-- on a row that has a destructive action. (The menu no longer shares
			-- this cost — redteam item 2's fix moved it to its own presentModal
			-- surface, which mounts and unmounts atomically with zero permanent
			-- node on the row at all; see the big comment above `local function
			-- openMenu`.)
			--
			-- PAINT ORDER: inserted BEFORE `Content` (array order = paint order,
			-- later wins — the same relationship the leading/trailing trays already
			-- have with `Content` below), so `Content` sitting on top during a live
			-- trailing drag (see `contentOffsetX`'s own comment for why a trailing
			-- reveal is deliberately NOT gutter-shifted) covers the minus exactly
			-- when a trailing swipe is genuinely in progress — acceptable, since a
			-- mid-swipe row is not a moment the minus needs to keep receiving taps.
			--
			-- DIAMETER: `shape = "circle"` + ONE authored axis (`width` only —
			-- `blueprint.luau`'s own `assertShape` rejects both) makes a true 1:1
			-- disc at the theme's `editAffordance` metric; the framework's OWN
			-- Button contract (`src/controls/contract.luau`: `Button.minHitSize =
			-- 44`) already floors the ENGINE HIT RECT at `targetSizes.minimum`
			-- regardless of the painted size (`renderer.luau`'s `effectiveHitFloor`
			-- — B-BTN3, "the VISUAL rect is deliberately untouched... declaring a
			-- floor here is all a new control has to do") — the documented small-
			-- target pattern this codebase already has (the reorder Grip's own
			-- `minHitSize = 44` is the sibling precedent), so NOTHING extra is
			-- authored here for the hit-target rule: a 28px disc already gets a
			-- 44px+ tappable area for free, on every input class.
			--
			-- COLOUR (`danger` glyph, per the brief). `role = "destructive"` is the
			-- one existing theme-token mechanism this control family has for
			-- "danger" (the SAME mapping the header comment above already
			-- establishes for a destructive tray button: "role = 'destructive'
			-- maps straight to it... paints control/content pair"). It could NOT be
			-- composed with `surface = "raised"` (surfaceStrong) to get a literal
			-- "danger glyph ON a surfaceStrong plate" split: `src/tokens/
			-- sheet_model.luau`'s own comment on the role rules is explicit — "role
			-- owns the resting fill... sit after the base/surface/selected fills"
			-- — so a `role = "destructive"` Button's BackgroundColor3 always wins
			-- over a `surface = "raised"` on the SAME node, regardless of prop
			-- order; the token vocabulary has no independent "content-only danger"
			-- tint (Text's own `role` enum is `{ "secondary", "content" }`, no
			-- `"danger"`; the chrome `ImageColor3` role tints — `$ChromeTintDanger`
			-- — only reach IMAGE-driven skinned art layers, not the plain-glyph
			-- fallback path this composite otherwise relies on). Adding that split
			-- would mean a new sheet rule in a file this task does not touch.
			-- `role = "destructive"` reuses the ALREADY-shipped, already-tested
			-- mapping instead: a solid danger-filled disc with an onDanger minus,
			-- visually consistent with the trailing tray's own destructive button
			-- one tap away — the closer real-iOS match besides.
			if hasEditAffordance then
				local destructiveEntry = firstDestructiveEntry()
				table.insert(
					children,
					UI.When({
						id = "EditAffordanceWhen",
						condition = editAffordanceShown,
						thenView = function()
							return UI.Button({
								id = "EditAffordance",
								anchor = "left",
								shape = "circle",
								role = "destructive",
								icon = "decrement", -- the framework's own minus glyph (standard_icons)
								-- ACCESSIBLE LABEL (the reorder Grip carries none — it is
								-- unfocusable, non-activating; this IS a Button, so it
								-- needs one). `Button.label` is the framework's own
								-- "required even when the button renders custom content...
								-- stays the semantic name and is not drawn" seam
								-- (blueprint_schema.luau) — the SAME icon-only-control
								-- precedent `shape = "circle"` exists for. Reuses the
								-- destructive action's own label (typically "Delete") so
								-- the announced name matches exactly what a second tap
								-- reaches.
								label = if destructiveEntry ~= nil then destructiveEntry.action.label else "Delete",
								width = { type = "fixed", px = EDIT_AFFORDANCE },
							})
						end,
					})
				)
			end

			-- Content's rendered offsetX. Deliberately NOT the same signal `offset`
			-- itself while `hasEditAffordance` — the header comment's own THE SLIDE
			-- MECHANISM section is explicit that every seam (spring, drag, the
			-- instant fallback) writes `offset` as the ONE bare reveal amount, and
			-- every piece of gesture/decision math (`targetFor`, `currentDecision`,
			-- `retarget`'s spring target, `settleTo`'s verdict) reads it back
			-- expecting exactly that — folding a constant gutter bias straight into
			-- `offset` would corrupt all of it. `contentOffsetX` is instead a
			-- SEPARATE, paint-only derived value: `offset` for the gesture, plus
			-- the live gutter, ADDED ONLY ON THE NON-NEGATIVE (resting/leading)
			-- side. The trailing side is deliberately left untouched: `offset`'s
			-- own topLeft-anchor shrink math (`solver.luau`'s `offsetFill`, "pushing
			-- a child out past the very edge it is anchored to... is deliberate")
			-- never gives back room for a NEGATIVE offset, so adding a positive
			-- gutter bias there would permanently under-expose the trailing tray by
			-- the gutter width for as long as it stayed open — a real geometry bug,
			-- not a cosmetic one. Leaving the trailing side alone means a trailing
			-- swipe/commit behaves BYTE IDENTICAL whether or not `editing` is true;
			-- the one accepted cost is a single-frame `editGutterPx` pop exactly at
			-- the instant a live drag crosses `offset == 0` from the leading side
			-- into the trailing side while editing — a genuinely rare simultaneous
			-- gesture (real iOS does not offer swipe-to-reveal and edit-mode at
			-- once either), documented rather than engineered around.
			local contentOffsetX = offset
			if hasEditAffordance then
				contentOffsetX = scope:own(core:memo(function(use)
					local raw = use(offset)
					if raw < 0 then
						return raw
					end
					return raw + use(editGutterPx)
				end))
			end
			-- REDTEAM FIX (item 15, LOW). This block used to ALWAYS mount the
			-- hit-surface Grip below, even under `externalGesture = true`, with
			-- every handler set to `nil` — a real Instance that does nothing:
			-- `screen_target.luau` sets `instance.Active = true` for EVERY
			-- `Grip` unconditionally at create time, regardless of whether it
			-- carries any pointer handlers at all, so an "inert" Grip still
			-- costs a genuine extra Active (hit-testable) node — the comment
			-- above (Task 10's own) claimed the caller "must not ALSO wire its
			-- own competing Content Grip," which undersold what was actually
			-- happening: the node itself still mounted, unwired, not "not
			-- wired = doesn't exist." `externalGesture` means Table's own row
			-- Hit (composed with reorder) is ALREADY the row's one pointer
			-- surface — this Grip would never receive a single event even if it
			-- did carry handlers — so it is now OMITTED entirely rather than
			-- merely left unwired: one real Instance saved per wrapped,
			-- reorderable Table row (proven by table.spec.luau's own "mounts NO
			-- internal Content/Hit Grip" case).
			local contentChildren: { any } = {}
			if not externalGesture then
				table.insert(
					contentChildren,
					-- Task 5: the drag hit surface. A `UI.Grip` — unfocusable by
					-- default (never steals a Tab stop from whatever focusable
					-- controls live inside `content`), exactly the "non-button
					-- Active node" pointer.spec.luau exercises — sized to fill,
					-- painted BEHIND `content` in the same array-order-is-
					-- paint-order relationship table.luau's own row "Hit"
					-- Button uses ahead of its "Cells" (table.luau
					-- `rowBlueprint`): Roblox delivers InputBegan/Changed/Ended
					-- to every Active GuiObject under the point independently
					-- of paint order, so this background Grip still captures a
					-- drag while a button INSIDE `content` still receives its
					-- own tap, unaffected, when the row is not being dragged.
					UI.Grip({
						id = "Hit",
						width = { type = "fill" },
						height = { type = "fill" },
						onPointerDown = pointerHandlers.onPointerDown,
						onPointerMove = pointerHandlers.onPointerMove,
						onPointerUp = pointerHandlers.onPointerUp,
						onPointerCancel = pointerHandlers.onPointerCancel,
					})
				)
			end
			table.insert(contentChildren, content)
			table.insert(
				children,
				UI.ZStack({
					id = "Content",
					anchor = "topLeft",
					offsetX = contentOffsetX,
					width = { type = "fill" },
					height = { type = "fill" },
					children = contentChildren,
				})
			)

			-- REDTEAM FIX (item 2, BLOCKER): the action menu no longer builds a
			-- node here at all — it moved to its own `presentModal` surface (see
			-- the big comment above `local function openMenu`, further up this
			-- function). No `menuAnchor`, nothing inserted into `children`: a row
			-- with a menu now costs exactly the SAME instance count, open or
			-- closed, as a row with none — an improvement over the old design's
			-- "one permanent Instance while closed" cost (its own comment used
			-- to price that in here), not merely a wash.

			-- Task 5: `height` is the ONE new root prop this task adds — bound to
			-- `rowHeightOverride`, which stays `nil` (BOX.height "content-sized
			-- when absent") for every row that never commits, byte-identical to
			-- Tasks 3-4 (no `height` prop existed on the root before this task).
			local heightPx = scope:own(core:memo(function(use)
				local px = use(rowHeightOverride)
				if px == nil then
					return nil
				end
				return { type = "fixed", px = px }
			end))
			root = UI.Anchor({ id = id, width = spec.width, height = heightPx, children = children })
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
		local editAffordancePattern = `/{idPattern}/EditAffordanceWhen/then/EditAffordance$`

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
			-- Task 9: the minus never deletes directly — it opens the tray
			-- holding the destructive action, same as the header comment/
			-- brief promise. THE REQUIRED NO-OP (Task 7's review, now
			-- required by this task's own brief): while that edge's tray is
			-- already open, activating the minus again does nothing — no
			-- re-claim, no re-retarget of a spring already at (or flying
			-- toward) the same target.
			--
			-- REDTEAM FIX (item 6, MAJOR): this used to hard-code
			-- `open("trailing")` — dead for a row whose ONLY destructive
			-- action sits on the LEADING edge (`hasDestructive` (build-time,
			-- above) scans BOTH edges, so `hasEditAffordance`/the minus
			-- itself can be true with no trailing destructive action at
			-- all). Opens whichever edge `firstDestructiveEntry` (Task 8's
			-- own Delete-key lookup, "search trailing list first, then
			-- leading") actually finds the minus's own destructive action
			-- on — the SAME edge the minus's own accessible `label` already
			-- borrows from (`destructiveEntry` below, at the button's own
			-- build site). `hasEditAffordance` already guarantees
			-- `hasDestructive`, so a `nil` entry here is unreachable in
			-- practice; `"trailing"` is kept as the honest fallback rather
			-- than asserting, matching this file's own house style
			-- elsewhere (e.g. `settleTo`'s "unreachable in practice... stay
			-- honest").
			if hasEditAffordance and string.match(path, editAffordancePattern) ~= nil then
				local destructiveEntry = firstDestructiveEntry()
				local edge: Edge = if destructiveEntry ~= nil then destructiveEntry.edge else "trailing"
				if openEdge:get() ~= edge then
					open(edge)
				end
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
			for _, action in actions do
				local sig = naturals[action.id]
				if sig == nil then
					continue
				end
				local facts = controller.textAt(`{trayPath}/Action:{action.id}`)
				if facts == nil or type(facts.font) ~= "string" or type(facts.size) ~= "number" then
					continue -- not yet measured this pass (e.g. the button just mounted)
				end
				local measured = text_metrics.measure(action.label, facts.font, facts.size, math.huge)
				sig:set(math.max(minWidth, measured.width + 2 * pad))
			end
		end
		-- Task 2: both arguments are optional now. The presenter always passes
		-- both (a contribution's `syncGeometry(rectOf, rootNode)`); a HOST calls
		-- `engine.syncGeometry()` bare from its own sync pass — it has no root
		-- node of this control's to hand over, and `rootPath` was seeded from
		-- `spec.paths.content` at build time rather than learned here.
		local function syncGeometry(_rectOf: ((string) -> any)?, rootNode: any?)
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
				local ox, oy = computeMenuAnchor()
				menuOx:set(ox)
				menuOy:set(oy)
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
		api.syncGeometry = contributionFields.syncGeometry
		api.bindMotion = contributionFields.bindMotion
		api.bindController = contributionFields.bindController
		api.bindPresent = contributionFields.bindPresent
		api.bindActionSystem = contributionFields.bindActionSystem
		api.bindFocusGraph = contributionFields.bindFocusGraph
		api.handleCancel = contributionFields.handleCancel
		api.outsideDismiss = contributionFields.outsideDismiss
	end
	return api
end

-- THE STANDALONE/TABLE ENTRY POINT — `LuauUI.newRowActions`. Unchanged
-- behavior: the whole composite, blueprint and all.
function row_actions.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newRowActions", spec, ROW_ACTIONS_KEYS, "spec")
	return buildEngine(LuauUI, core, spec, nil)
end

-- THE HOSTED ENTRY POINT (Task 2) — engine only, NO blueprint. Internal, not
-- public API: `newVirtualList`'s own `rowActions` spec key (Task 3) is what a
-- caller reaches, exactly as Table already owns its own row-actions wiring.
-- See the HOSTED MODE comment at the top of this file for the contract, and
-- docs/plans/row-actions-hosted-mode-design.md for why the host owns the
-- nodes.
function row_actions.buildHosted(LuauUI: any, core: any, spec: HostedSpec): HostedEngine
	specGuard.assertKnownKeys("newRowActionsHosted", spec, HOSTED_KEYS, "spec")
	local id = spec.id or "RowActions"
	local paths: any = spec.paths
	if type(paths) ~= "table" then
		error(
			`LuauUI newRowActionsHosted('{id}'): \`paths\` is required — a hosted engine mounts nothing of its `
				.. "own, so the host must name the nodes it reads live rects and text facts from",
			0
		)
	end
	specGuard.assertKnownKeys("newRowActionsHosted", paths, HOSTED_PATH_KEYS, "spec.paths")
	if type(paths.content) ~= "string" or paths.content == "" then
		error(`LuauUI newRowActionsHosted('{id}'): \`paths.content\` must be the host's own row path (a string)`, 0)
	end
	if type(spec.onSlide) ~= "function" then
		error(
			`LuauUI newRowActionsHosted('{id}'): \`onSlide\` must be a function — the host paints the slide `
				.. "(this engine owns no node to paint)",
			0
		)
	end
	if spec.onCommitHeight ~= nil and type(spec.onCommitHeight) ~= "function" then
		error(`LuauUI newRowActionsHosted('{id}'): \`onCommitHeight\` must be a function, or nil`, 0)
	end
	-- REFUSED, not silently degraded: a hosted engine with nothing to reveal on
	-- either edge is a host that built a row engine it never needed. The
	-- standalone "inert passthrough" answer (return `content` unwrapped) has no
	-- meaning here — there is no content to hand back.
	if spec.leading == nil and spec.trailing == nil then
		error(
			`LuauUI newRowActionsHosted('{id}'): a hosted engine needs actions on at least one edge — build no `
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
			`LuauUI newRowActionsHosted('{id}'): \`leading\` actions require \`paths.trayLeading\` (the host's `
				.. "own leading tray container path) — without it the tray can never be measured or found to "
				.. "paint, and the row would silently claim to be open with nothing revealed",
			0
		)
	end
	if spec.trailing ~= nil and (type(paths.trayTrailing) ~= "string" or paths.trayTrailing == "") then
		error(
			`LuauUI newRowActionsHosted('{id}'): \`trailing\` actions require \`paths.trayTrailing\` (the host's `
				.. "own trailing tray container path) — without it the tray can never be measured or found to "
				.. "paint, and the row would silently claim to be open with nothing revealed",
			0
		)
	end
	return buildEngine(LuauUI, core, spec, {
		paths = paths,
		onSlide = spec.onSlide,
		onCommitHeight = spec.onCommitHeight,
	}) :: HostedEngine
end

-- ===== Task 10: reorder composition (Table integration) ====================
-- Table's own row Hit surface, when BOTH `reorderable` and `rowActions` are
-- true for a row, has two candidate owners for the SAME raw pointer capture:
-- this composite's swipe gesture (horizontal) and Table's own drag-to-reorder
-- (vertical). Both ride the identical low-level onPointerDown/Move/Up/Cancel
-- capture (ADR-0008) — the engine hands a SINGLE gesture to whichever side
-- claims it, and neither gesture alone knows the other exists. Composed here,
-- not in table.luau (the brief's own design), because the axis-lock rule —
-- "ties go vertical" (`row_actions_state.AXIS_LOCK_PX`), the SAME constant
-- this composite's own internal `onPointerMove` already applies to itself —
-- belongs with the one other place it is authored, not duplicated.
--
-- THE DEFERRED-DOWN SHAPE. The axis is unknown at down (dx = dy = 0, the same
-- "tentative accept" problem `onPointerDown`'s own header comment describes
-- for this composite alone), so down here commits to neither engine yet: it
-- tracks the raw origin and accepts the capture (mouse can never partially
-- decline once accepted — same "no third option" the header comment already
-- establishes), deferring both `rowActionsHandlers.onPointerDown` and
-- `reorderHandlers.onPointerDown` until the FIRST move that crosses the axis
-- lock, at which point exactly ONE is replayed from the ORIGINAL down
-- position (never the current one — a gesture that resolves 20px into the
-- move must still look, to whichever engine wins, like a press that just
-- happened) and owns every subsequent move/up/cancel for the rest of this
-- gesture. The OTHER engine never sees this gesture at all — never a down,
-- never a move — so neither `reorderHandlers`' own `rowDrag` nor this
-- composite's own `drag` local is ever touched by the loser, and neither can
-- misfire later from stray state.
--
-- TOUCH skips the deferral entirely: table.luau's `reorderHandlers` already
-- declines touch on the row body unconditionally (native scroll owns the
-- pan — table.luau's own native-scroll header), so a touch gesture is
-- unambiguously this composite's from the first frame.
--
-- `reorderHandlers == nil` (a Table that is not `reorderable`, or a
-- standalone caller with nothing to compose against) returns
-- `rowActionsHandlers` unchanged — a plain pass-through, zero overhead.
function row_actions.composeWithReorder(rowActionsHandlers: any, reorderHandlers: any?): any
	if reorderHandlers == nil then
		return rowActionsHandlers
	end

	type Pending = {
		originX: number,
		originY: number,
		originPos: any,
		path: string,
		rectOf: (string) -> any,
		mode: "pending" | "rowActions" | "reorder",
	}
	local pending: Pending? = nil

	-- axis verdict is a pure function of dx/dy and the fixed AXIS_LOCK_PX
	-- constant alone (identical rule to this composite's own internal
	-- `onPointerMove`); called only while `mode == "pending"`.
	local function resolveAxis(pos: any)
		local p = pending :: Pending
		local dx, dy = pos.x - p.originX, pos.y - p.originY
		if dx * dx + dy * dy < row_actions_state.AXIS_LOCK_PX ^ 2 then
			return -- still accumulating toward the lock radius
		end
		-- ties go vertical (row_actions_state.axisVerdict's own rule):
		-- scrolling/reordering must never lose an ambiguous gesture.
		if math.abs(dx) > math.abs(dy) then
			p.mode = "rowActions"
			-- REDTEAM FIX (item 13, LOW): `replayed = true` (a shallow copy —
			-- `p.originPos` itself is left untouched, still the exact table a
			-- caller may be holding elsewhere) tells `onPointerDown`'s own
			-- velocity-tracker seed to skip itself here (see its own big
			-- comment): this replay's POSITION is correct (the true origin,
			-- still needed for `drag.originX/Y`'s own clamp math) but its
			-- TIME is not (this dispatcher has no clock of its own, by
			-- design), so seeding the tracker from it would corrupt a
			-- release-velocity computed shortly after the axis resolves.
			rowActionsHandlers.onPointerDown(
				p.path,
				{ x = p.originPos.x, y = p.originPos.y, pointerType = p.originPos.pointerType, replayed = true },
				p.rectOf
			)
		else
			p.mode = "reorder"
			-- REPLAYED at the origin (see header comment). reorder's own down
			-- handler re-runs its handle-zone/touch decline checks here too —
			-- both moot in practice (touch never reaches this branch; the
			-- handle zone is checked by Table BEFORE this dispatcher ever
			-- runs), so this is a harmless re-check on the way to seeding
			-- `rowDrag`.
			reorderHandlers.onPointerDown(p.path, p.originPos, p.rectOf)
		end
	end

	local function onPointerDown(path: string, pos: any, rectOf: (string) -> any): boolean?
		if pending ~= nil then
			return false -- a capture is already live; never steal
		end
		if pos.pointerType == "touch" then
			pending = {
				originX = pos.x,
				originY = pos.y,
				originPos = pos,
				path = path,
				rectOf = rectOf,
				mode = "rowActions",
			}
			local accepted = rowActionsHandlers.onPointerDown(path, pos, rectOf)
			if accepted == false then
				pending = nil
			end
			return accepted
		end
		pending = {
			originX = pos.x,
			originY = pos.y,
			originPos = pos,
			path = path,
			rectOf = rectOf,
			mode = "pending",
		}
		return true
	end

	local function onPointerMove(path: string, pos: any, rectOf: (string) -> any)
		if pending == nil then
			return
		end
		if pending.mode == "pending" then
			resolveAxis(pos)
		end
		if pending.mode == "rowActions" then
			rowActionsHandlers.onPointerMove(path, pos, rectOf)
		elseif pending.mode == "reorder" then
			reorderHandlers.onPointerMove(path, pos, rectOf)
		end
	end

	local function onPointerUp(path: string, pos: any, rectOf: (string) -> any)
		if pending == nil then
			return
		end
		local mode = pending.mode
		pending = nil
		if mode == "rowActions" then
			rowActionsHandlers.onPointerUp(path, pos, rectOf)
		elseif mode == "reorder" then
			reorderHandlers.onPointerUp(path, pos, rectOf)
		end
		-- "pending" (never crossed the lock radius — a tap): neither engine
		-- was ever told a down, so neither is told an up.
	end

	local function onPointerCancel(path: string, reason: string?): boolean?
		if pending == nil then
			return nil
		end
		local mode = pending.mode
		pending = nil
		if mode == "rowActions" then
			return rowActionsHandlers.onPointerCancel(path, reason)
		elseif mode == "reorder" then
			return reorderHandlers.onPointerCancel(path, reason)
		end
		return nil
	end

	return {
		onPointerDown = onPointerDown,
		onPointerMove = onPointerMove,
		onPointerUp = onPointerUp,
		onPointerCancel = onPointerCancel,
	}
end

return row_actions
