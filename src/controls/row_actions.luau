--!strict
-- RowActions: a swipeable action tray around an arbitrary row (spec:
-- docs/plans/row-actions.md, docs/plans/row-actions-implementation.md Task 3).
-- This module ships the SKELETON: the spec/blueprint contract, the lazy tray
-- structure, and an INSTANT (unsprung) reveal. Drag/gesture input (mouse,
-- touch, keyboard, gamepad — Tasks 5-8), the coordinator (Task 7), and the
-- spring motion (Task 4) all build on the seams declared here without
-- touching this file's structure.
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
-- tree. Every write — today's instant snap, Task 4's spring, Task 5's live
-- drag sample — goes through the ONE seam `applyOffset(px)` below.
--
-- TRAY WIDTH. Rather than hand-measure a label at build time (the exact
-- "cached before truth exists" bug class docs/research/roblox-text-bounds-
-- boot-window warns about — a width guessed before the engine has laid
-- anything out is wrong forever), each tray's width is READ from its own
-- SOLVED geometry via the input contribution's `syncGeometry` hook — the
-- same mechanism `slider.luau`'s track-fraction math and `table.luau`'s
-- resize preview use. `_open` seeds an instant estimate from the last known
-- width (0 the very first time) and `syncGeometry` corrects it the moment
-- real geometry lands, so a long, pseudo-localized label — which grows a
-- tray button past `buttonMinWidth` — reveals correctly with no hand-rolled
-- text metrics anywhere in this file.
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
	-- last KNOWN solved width of each tray (0 = never measured — a row not yet
	-- opened has nothing to know); fed by syncGeometry below.
	local leadingWidth = scope:own(core:signal(0))
	local trailingWidth = scope:own(core:signal(0))

	-- THE ONE SEAM (Tasks 4-6 write through this exclusively): however the
	-- pixel number is produced — today's instant snap, a spring chase, a live
	-- drag sample — it reaches the Content anchor's offsetX through here alone.
	local function applyOffset(px: number)
		offset:set(px)
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
		openEdge:set(edge)
		applyOffset(targetFor(edge))
	end

	local function close()
		openEdge:set(nil)
		applyOffset(0)
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
		local function buildTray(edge: Edge, actions: { ActionSpec })
			local buttons = {}
			for _, action in actions do
				table.insert(
					buttons,
					UI.Button({
						id = "Action:" .. action.id,
						label = action.label,
						icon = action.icon,
						role = if action.role == "destructive" then "destructive" else "default",
						width = { type = "minMax", min = BUTTON_MIN_WIDTH },
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
			local revealed = scope:own(core:memo(function(use)
				return use(openEdge) == "leading"
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
				return use(openEdge) == "trailing"
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

		-- SOLVED tray geometry, fed by the contribution's syncGeometry so a long
		-- (pseudo-localized) label — which grows a button past buttonMinWidth —
		-- corrects the reveal offset the moment the real width is known, exactly
		-- like slider.luau's track-fraction math and table.luau's resize preview.
		local rootPath: string? = nil
		local function syncGeometry(rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil then
				rootPath = rootNode.path
			end
			if rootPath == nil then
				return
			end
			if leadingActions ~= nil then
				local r = rectOf(rootPath .. "/TrayLeadingWhen/then/TrayLeading")
				if r ~= nil then
					leadingWidth:set(r.w)
					if openEdge:get() == "leading" then
						applyOffset(r.w)
					end
				end
			end
			if trailingActions ~= nil then
				local r = rectOf(rootPath .. "/TrayTrailingWhen/then/TrayTrailing")
				if r ~= nil then
					trailingWidth:set(r.w)
					if openEdge:get() == "trailing" then
						applyOffset(-r.w)
					end
				end
			end
		end

		blueprint = contribution.attach(root, {
			handleActivate = handleActivate,
			syncGeometry = syncGeometry,
		})
	end

	return {
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			scope:dispose()
		end,
		-- internal seam for Table + coordinator (NOT public API; underscore
		-- prefix) — Tasks 4-8 build the motion, gesture, and keyboard paths
		-- through these three:
		_open = open,
		_close = close,
		_isOpen = isOpen,
	}
end

return row_actions
