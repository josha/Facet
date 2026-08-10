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
-- TRAY WIDTH. Rather than hand-measure a label at build time (the exact
-- "cached before truth exists" bug class docs/research/roblox-text-bounds-
-- boot-window warns about — a width guessed before the engine has laid
-- anything out is wrong forever), each tray's width is the SUM of its own
-- buttons' SOLVED natural widths, read via the input contribution's
-- `syncGeometry` hook — the same mechanism `slider.luau`'s track-fraction
-- math and `table.luau`'s resize preview use. `_open` seeds an estimate from
-- the last known width (0 the very first time) and `syncGeometry` freezes
-- the real one the moment it lands (see the Task 4 comment by `leadingWidth`
-- for why FROZEN, not re-fed forever), so a long, pseudo-localized label —
-- which grows a tray button past `buttonMinWidth` — reveals correctly with
-- no hand-rolled text metrics anywhere in this file.
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
}

-- CLOSED SPEC (constitution §4; ARCH-1).
local ROW_ACTIONS_KEYS = specGuard.keySet({
	"id",
	"content",
	"leading",
	"trailing",
	"fullSwipe",
	"coordinator",
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
	-- normalized and stored now (row_actions_state.new's fullSwipeLeading/
	-- fullSwipeTrailing opts); Task 5 is the first consumer of the gesture
	-- decision itself.
	local _fullSwipe = normalizeFullSwipe(id, spec.fullSwipe)

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

	-- per-action NATURAL (unconstrained) width, frozen the first time it is
	-- measured (below) and never again — created eagerly, one signal per
	-- declared action, at BUILD time rather than inside the tray's lazy
	-- `UI.When` factory. A reactive value created INSIDE that factory would be
	-- a FRESH `core:memo` every remount (Trays mount lazily; a row can open
	-- and close many times), which `scope:own` would dutifully own and never
	-- release until this whole composite disposes — a slow leak shaped
	-- exactly like the "table with no dispose()" mistake scope_impl.luau's
	-- own `own()` guards against, just one level up (a table WITH a
	-- dispose(), that nothing ever calls). Building it once, here, and having
	-- the tray factory below only ever LOOK UP an existing entry, means every
	-- open/close cycle reuses the same handful of reactive nodes.
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
	-- the tray's total width IS the sum of its buttons' frozen naturals — never
	-- the tray CONTAINER's own solved rect. Reading the container back would
	-- be reading a number this same reveal can shrink (below), which would
	-- feed a shrunk width back in as the "true" one and chase a collapsing
	-- target forever; the naturals are only ever written once, before any
	-- shrink has happened (see `syncGeometry`), so this sum is stable for the
	-- composite's whole life.
	local leadingWidth = scope:own(core:memo(function(use)
		return sumNaturals(leadingNaturals, use)
	end))
	local trailingWidth = scope:own(core:memo(function(use)
		return sumNaturals(trailingNaturals, use)
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
	local motionClock: any = nil
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

	-- Task 5 wires the drag-release verdict (row_actions_state.settle) through
	-- here: retargets the spring at whatever edge/target the verdict names.
	-- `commit` (a full-swipe release) behaves like a plain open-to-target for
	-- now — firing the edge's first action and then closing is Task 5's.
	local function settleTo(verdict: row_actions_state.Verdict)
		openEdge:set(verdict.edge)
		retarget(verdict.target)
		-- Task 5: verdict.commit fires the edge's first action, then close().
	end

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
		-- content-sized, static); once its natural width is frozen it reads
		-- its share of the SAME observed `offset` the slide itself uses — no
		-- second spring, no per-button spring — so a button "stretches in"
		-- from 0 toward its natural width as `|offset|` approaches `trayWidth`
		-- (docs/plans/row-actions-implementation.md Task 4: "SwiftUI feel").
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
				children = { content },
			})
		)

		local root = UI.Anchor({ id = id, children = children })

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

		-- SOLVED per-button geometry, fed by the contribution's syncGeometry so a
		-- long (pseudo-localized) label — which grows a button past
		-- buttonMinWidth — corrects the reveal target the moment the real width
		-- is known, exactly like slider.luau's track-fraction math and
		-- table.luau's resize preview. Each button's natural is read ONLY while
		-- still unmeasured (`sig:get() == nil`): the FIRST solve after a tray
		-- mounts always renders through the width props' `minMax` fallback
		-- (nothing has frozen yet), so that first read is the true,
		-- unconstrained content width — reading it again on a later solve,
		-- once the width props have started shrinking the button for the
		-- reveal, would feed the shrunk number back in as "the natural width"
		-- and the tray would chase a collapsing target forever.
		local rootPath: string? = nil
		local function freezeNaturals(
			rectOf: (string) -> any,
			edge: Edge,
			actions: { ActionSpec },
			naturals: { [string]: any }
		)
			local tid = trayId(edge)
			for _, action in actions do
				local sig = naturals[action.id]
				if sig ~= nil and sig:get() == nil then
					local r = rectOf(`{rootPath}/{tid}When/then/{tid}/Action:{action.id}`)
					if r ~= nil then
						sig:set(r.w)
					end
				end
			end
		end
		local function syncGeometry(rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil then
				rootPath = rootNode.path
			end
			if rootPath == nil then
				return
			end
			if leadingActions ~= nil then
				freezeNaturals(rectOf, "leading", leadingActions, leadingNaturals)
				if openEdge:get() == "leading" then
					retarget(leadingWidth:get())
				end
			end
			if trailingActions ~= nil then
				freezeNaturals(rectOf, "trailing", trailingActions, trailingNaturals)
				if openEdge:get() == "trailing" then
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
			bindMotion = function(clock: any)
				motionClock = clock
			end,
		})
	end

	return {
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			scope:dispose()
		end,
		-- internal seam for Table + coordinator (NOT public API; underscore
		-- prefix) — Tasks 5-8 build the gesture and keyboard paths through
		-- these four:
		_open = open,
		_close = close,
		_isOpen = isOpen,
		_settleTo = settleTo,
	}
end

return row_actions
