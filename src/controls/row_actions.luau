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
-- live drag sample — goes through the ONE seam `applyOffset(px)` below.
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
-- Task 3's instant `applyOffset`, unchanged. `retarget(px)` is that one
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
})
local ACTION_KEYS = specGuard.keySet({ "id", "role", "label", "icon", "onAction" })
local FULL_SWIPE_KEYS = specGuard.keySet({ "leading", "trailing" })

-- THEME METRICS (Task 2; ADR-0019 §2). A tray button never sits narrower than
-- `buttonMinWidth` — the localization floor — and `buttonPad` is its inner
-- horizontal padding. Theme strings only; resolved by the solver exactly like
-- `slider.luau`'s `THUMB_SIZE`/`RAIL_HEIGHT`.
local BUTTON_MIN_WIDTH = "controls.rowActions.buttonMinWidth"
local BUTTON_PAD = "controls.rowActions.buttonPad"

-- a node id is interpolated into a Lua PATTERN below (handleActivate's path
-- match), so its magic characters have to be escaped first — same helper,
-- same reason, as popup_button.luau/table.luau/text_input.luau/virtual_list.luau.
local function patternEscape(s: string): string
	return (s:gsub("%W", "%%%0"))
end

local function trayId(edge: Edge): string
	return if edge == "leading" then "TrayLeading" else "TrayTrailing"
end

-- validate ONE ActionSpec entry, naming the edge and index in every error so
-- a bad row in a five-action tray is not a guessing game.
local function buildActionSpec(rowId: string, edge: Edge, index: number, raw: any): ActionSpec
	if type(raw) ~= "table" then
		error(`LuauUI newRowActions('{rowId}'): \`{edge}[{index}]\` must be a table (ActionSpec)`, 0)
	end
	specGuard.assertKnownKeys("newRowActions", raw, ACTION_KEYS, `spec.{edge}[{index}]`)
	if type(raw.label) ~= "string" or raw.label == "" then
		error(`LuauUI newRowActions('{rowId}'): \`{edge}[{index}].label\` must be a non-empty string`, 0)
	end
	local role = raw.role
	if role ~= nil and role ~= "normal" and role ~= "destructive" then
		error(
			`LuauUI newRowActions('{rowId}'): \`{edge}[{index}].role\` '{tostring(role)}' is not a role. `
				.. "Valid: normal, destructive.",
			0
		)
	end
	if type(raw.onAction) ~= "function" then
		error(`LuauUI newRowActions('{rowId}'): \`{edge}[{index}].onAction\` must be a function`, 0)
	end
	local actionId = if raw.id ~= nil then raw.id else raw.label
	if type(actionId) ~= "string" or actionId == "" then
		error(`LuauUI newRowActions('{rowId}'): \`{edge}[{index}].id\` must be a non-empty string`, 0)
	end
	if string.find(actionId, "/", 1, true) ~= nil then
		error(`LuauUI newRowActions('{rowId}'): {edge} action id '{actionId}' must be path-safe (no "/")`, 0)
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
local function actionsFor(rowId: string, edge: Edge, raw: any): { ActionSpec }?
	if raw == nil then
		return nil
	end
	if type(raw) ~= "table" then
		error(`LuauUI newRowActions('{rowId}'): \`{edge}\` must be an array of ActionSpec, or nil for none`, 0)
	end
	if #raw == 0 then
		error(
			`LuauUI newRowActions('{rowId}'): \`{edge}\` is an empty table — use nil for "no actions on this `
				.. `edge", not \{\}`,
			0
		)
	end
	local out: { ActionSpec } = {}
	for i, entry in raw do
		table.insert(out, buildActionSpec(rowId, edge, i, entry))
	end
	return out
end

local function normalizeFullSwipe(rowId: string, raw: any): { leading: boolean, trailing: boolean }
	if raw == nil then
		return { leading = true, trailing = true }
	end
	if type(raw) == "boolean" then
		return { leading = raw, trailing = raw }
	end
	if type(raw) == "table" then
		specGuard.assertKnownKeys("newRowActions", raw, FULL_SWIPE_KEYS, "spec.fullSwipe")
		local leading = if raw.leading == nil then true else raw.leading
		local trailing = if raw.trailing == nil then true else raw.trailing
		if type(leading) ~= "boolean" or type(trailing) ~= "boolean" then
			error(`LuauUI newRowActions('{rowId}'): \`fullSwipe.leading\`/\`trailing\` must be booleans`, 0)
		end
		return { leading = leading, trailing = trailing }
	end
	error(`LuauUI newRowActions('{rowId}'): \`fullSwipe\` must be a boolean or \{ leading?, trailing? \}`, 0)
end

function row_actions.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newRowActions", spec, ROW_ACTIONS_KEYS, "spec")
	local UI = LuauUI.UI
	local id = spec.id or "RowActions"
	local scope = core:scope("row-actions-" .. tostring(id))

	if type(spec.content) ~= "table" or (spec.content :: any).class == nil then
		error(`LuauUI newRowActions('{id}'): \`content\` is required and must be a Blueprint`, 0)
	end
	local content = spec.content

	if spec.coordinator ~= nil and type(spec.coordinator) ~= "table" then
		error(
			`LuauUI newRowActions('{id}'): \`coordinator\` must be a table (the value newRowActionsCoordinator `
				.. "returns) — Task 7 wires it",
			0
		)
	end
	-- accepted and stored now; Task 7 is the first consumer.
	local _coordinator = spec.coordinator

	local leadingActions = actionsFor(id, "leading", spec.leading)
	local trailingActions = actionsFor(id, "trailing", spec.trailing)
	-- normalized at build time (row_actions_state.new's fullSwipeLeading/
	-- fullSwipeTrailing opts); Task 5's gesture/commit paths below are the
	-- first consumers of the decision itself.
	local fullSwipe = normalizeFullSwipe(id, spec.fullSwipe)

	local actionsById: { leading: { [string]: ActionSpec }, trailing: { [string]: ActionSpec } } =
		{ leading = {}, trailing = {} }
	for _, action in leadingActions or {} do
		actionsById.leading[action.id] = action
	end
	for _, action in trailingActions or {} do
		actionsById.trailing[action.id] = action
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

	-- THE ONE SEAM (Tasks 4-6 write through this exclusively): however the
	-- pixel number is produced — the fallback instant snap, a spring chase, a
	-- live drag sample — it reaches the Content anchor's offsetX through here
	-- alone.
	local function applyOffset(px: number)
		offset:set(px)
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
	-- Task 5: the SAME function `motionClock` itself was built from
	-- (`bindMotion`'s ADDITIVE second argument — src/input/contribution.luau,
	-- src/present/presenter.luau `c.bundle.bindMotion(motionClock, nowFn)`),
	-- the one legal time source the gesture's `drag_velocity` tracker below
	-- may read. Absent has the identical shape as `controller`/`motionClock`
	-- absent: a bare mount, no presenter.
	local nowFn: (() -> number)? = nil
	-- Task 5: hoisted out of `deriveNaturals`'s original home below (still
	-- written there, on every `syncGeometry`) so the commit path's own
	-- `currentRect`/`currentRowWidth`/`currentRowHeight` — shared, unconditional
	-- code, reused by both the gesture and `_commitFirst` — can read it too.
	local rootPath: string? = nil
	local spring: any = nil
	local function ensureSpring()
		if spring ~= nil or motionClock == nil then
			return
		end
		spring = scope:own(motionClock:spring(offset:get(), "object"))
		-- dispose pattern mirrors drag_registry.luau:388-396 (unsubscribe, then
		-- dispose the value) — one axis here instead of drag's two.
		scope:own(core:observe(spring, function()
			applyOffset(spring:get())
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
			applyOffset(px)
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

	local function open(edge: Edge)
		if not hasActions(edge) then
			return
		end
		retarget(targetFor(edge))
		openEdge:set(edge)
	end

	local function close()
		openEdge:set(nil)
		retarget(0)
	end

	-- ===== Task 5: the commit path (shared by the gesture and `_commitFirst`) ===
	-- Live geometry read through `controller` (bound the same absent-degrades
	-- way `deriveNaturals` already reads `controller.textAt` — Task 4), never
	-- cached: a row's width/height are facts about what actually solved, not
	-- something this control could compute for itself.
	local function currentRect(): any
		if controller == nil or rootPath == nil then
			return nil
		end
		return controller.rectOf(rootPath)
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
	-- built lazily on the one commit a row ever makes.
	local collapseSpring: any = nil
	local function ensureCollapseSpring(initial: number)
		if collapseSpring ~= nil or motionClock == nil then
			return
		end
		collapseSpring = scope:own(motionClock:spring(initial, "object"))
		rowHeightOverride:set(initial) -- seed the paint before the first step
		scope:own(core:observe(collapseSpring, function()
			rowHeightOverride:set(collapseSpring:get())
		end))
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
			applyOffset(px)
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
			rowHeightOverride:set(0)
			onArrive()
		end
	end

	-- a row commits at most once in its life (the caller's next move is to
	-- mutate the data and let a keyed diff remove this instance) — this flag
	-- makes that true even if something calls the commit path twice, on top
	-- of the exactly-once guarantee `retargetThen`/`collapseThen`'s own
	-- self-unsubscribing already gives each individual spring chain.
	local committed = false

	-- THE ONE COMMIT PATH (brief: `_commitFirst`, keyboard Delete's Task 8
	-- entry point, reuses this exact function minus the gesture that got it
	-- here). Slides `content` fully off-screen, collapses the row's own
	-- height to 0 over the same spring family, fires the edge's FIRST action
	-- exactly once (quarantined — a throw still closes, never refires), then
	-- runs the same bookkeeping `_close()` already does.
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
	local function doCommit(edge: Edge, offscreenTarget: number): boolean
		if committed then
			return false
		end
		local action = firstActionFor(edge)
		if action == nil then
			return false
		end
		committed = true
		openEdge:set(edge)
		retargetThen(offscreenTarget, function()
			if disposed then
				return
			end
			local startHeight = currentRowHeight()
			collapseThen(startHeight, function()
				if not disposed then
					-- QUARANTINED (constitution): the ONE user callback this
					-- composite ever fires on a caller's behalf. A throw must
					-- not skip `close()` below, nor fire a second time —
					-- `committed` already forbids a second `doCommit`, and this
					-- whole chain only ever runs once per row.
					pcall(action.onAction)
				end
				close()
			end)
		end)
		return true
	end

	-- Task 5: the drag-release verdict's commit branch (row_actions_state.
	-- settle) routes through here; Task 8's keyboard Delete calls `doCommit`
	-- directly via the public `_commitFirst` seam below instead.
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
			`LuauUI newRowActions('{id}'): a pointer gesture reached _pointerHandlers with no bound \`now\` `
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
	-- `applyOffset` reveals the tray (see the `revealed` memos below) and the
	-- next `syncGeometry` measures it, this decision sees the REAL number —
	-- self-correcting within a frame or two, rather than wrong for the rest
	-- of the gesture. `row_actions_state.new` is a cheap, pure constructor
	-- (closures over already-known scalars, no engine, no allocation beyond
	-- itself), so rebuilding it per move costs nothing next to a solve pass.
	local function currentDecision(): any
		return row_actions_state.new({
			rowWidth = currentRowWidth(),
			leadingWidth = leadingWidth:get(),
			trailingWidth = trailingWidth:get(),
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
		drag = {
			originX = pos.x,
			originY = pos.y,
			startOffset = offset:get(),
			axis = "pending",
		}
		tracker:reset()
		tracker:push(pos.x, pos.y, currentNow())
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
		applyOffset(target)
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
			-- instant `applyOffset` snap, which has no velocity concept at
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

	local function isOpen(): boolean
		return openEdge:get() ~= nil
	end

	local function dump()
		local edge = openEdge:get()
		return {
			schema = "luauui-rowactions-dump/1",
			id = id,
			offset = offset:get(),
			openEdge = edge,
			phase = if edge == nil then "closed" else "open",
		}
	end

	local blueprint: any
	if leadingActions == nil and trailingActions == nil then
		-- TRUE INERT PASSTHROUGH (perf directive): nothing to reveal on either
		-- edge, so this control adds NOTHING — not an Anchor, not a wrapper, not
		-- an extra GuiObject. `content` mounts exactly as the caller wrote it.
		blueprint = content
	else
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
						icon = action.icon,
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
		table.insert(
			children,
			UI.ZStack({
				id = "Content",
				anchor = "topLeft",
				offsetX = offset,
				width = { type = "fill" },
				height = { type = "fill" },
				children = {
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
					}),
					content,
				},
			})
		)

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
		local root = UI.Anchor({ id = id, height = heightPx, children = children })

		local idPattern = patternEscape(id)
		local function actionIdFromPath(edge: Edge, path: string): string?
			local tid = trayId(edge)
			return string.match(path, `/{idPattern}/{tid}When/then/{tid}/Action:(.+)$`)
		end

		-- routes a presenter/tap Activate; returns true when the path was ours
		-- (mirrors popup_button.luau's api.handleActivate).
		local function handleActivate(path: string, _meta: any?): boolean
			if leadingActions ~= nil then
				local aid = actionIdFromPath("leading", path)
				if aid ~= nil and actionsById.leading[aid] ~= nil then
					actionsById.leading[aid].onAction()
					return true
				end
			end
			if trailingActions ~= nil then
				local aid = actionIdFromPath("trailing", path)
				if aid ~= nil and actionsById.trailing[aid] ~= nil then
					actionsById.trailing[aid].onAction()
					return true
				end
			end
			return false
		end

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
			local tid = trayId(edge)
			local pad = buttonPadPx:get()
			local minWidth = buttonMinWidthPx:get()
			for _, action in actions do
				local sig = naturals[action.id]
				if sig == nil then
					continue
				end
				local facts = controller.textAt(`{rootPath}/{tid}When/then/{tid}/Action:{action.id}`)
				if facts == nil or type(facts.font) ~= "string" or type(facts.size) ~= "number" then
					continue -- not yet measured this pass (e.g. the button just mounted)
				end
				local measured = text_metrics.measure(action.label, facts.font, facts.size, math.huge)
				sig:set(math.max(minWidth, measured.width + 2 * pad))
			end
		end
		local function syncGeometry(_rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil then
				rootPath = rootNode.path
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
			-- actively horizontal), the drag path through `applyOffset` is the
			-- ONLY writer, full stop; a natural-width change reactively re-fed
			-- from `deriveNaturals` above still updates `leadingWidth`/
			-- `trailingWidth` for whenever the NEXT ungated sync runs (right
			-- after release), it just doesn't retarget THIS frame.
			if drag == nil then
				if leadingActions ~= nil and openEdge:get() == "leading" then
					retarget(leadingWidth:get())
				end
				if trailingActions ~= nil and openEdge:get() == "trailing" then
					retarget(-trailingWidth:get())
				end
			end
		end

		blueprint = contribution.attach(root, {
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
		})
	end

	return {
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			-- Task 5: set BEFORE tearing the scope down — the commit path's
			-- own guard (see `doCommit`'s comment) reads this synchronously
			-- inside the same `scope:dispose()` call if a spring is settling
			-- mid-teardown.
			disposed = true
			scope:dispose()
		end,
		-- internal seam for Table + coordinator (NOT public API; underscore
		-- prefix) — Tasks 6-8 build the touch/keyboard/gamepad paths through
		-- these six:
		_open = open,
		_close = close,
		_isOpen = isOpen,
		_settleTo = settleTo,
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
	}
end

return row_actions
