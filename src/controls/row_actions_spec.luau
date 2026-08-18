--!strict
--[[ row_actions_spec — the ActionSpec authoring contract, and three leaf helpers.

	WHAT THIS IS. Everything `row_actions.luau` does BEFORE it has an engine: the
	pure validation that turns a caller's raw `leading`/`trailing`/`fullSwipe`
	tables into the normalized `ActionSpec` lists `buildEngine` closes over, plus
	the three one-line string/id helpers that file's own nodes and paths are built
	from. Nothing here reads or writes a single engine upvalue — every function is
	a total function of its arguments, which is why it can live outside the one
	closure.

	PUBLIC INTERFACE (all consumed by `row_actions.luau`, which re-exports the two
	types under its own names so no caller's `newRowActions.ActionSpec` moved):
	  * types `Edge`, `ActionSpec`
	  * `patternEscape(s)` — escape a node id for interpolation into a Lua pattern
	  * `isPathPrefix(prefix, path)` — "is `path` inside `prefix`'s own subtree"
	  * `trayId(edge)` — the tray container's node id for an edge
	  * `actionsFor(label, rowId, edge, raw)` — validate one edge's action array
	  * `normalizeFullSwipe(label, rowId, raw)` — the boolean-or-table fullSwipe form

	DEPENDS ON: `../spec_guard` alone. It deliberately imports nothing reactive,
	nothing from `present/`, and no engine type.

	WHY IT IS ITS OWN FILE (2026-08-14). `row_actions.luau` crossed the 200,000-char
	`Script.Source` WRITE cap, which is what Rojo live-sync, `execute_luau` and every
	plugin path assign through — so the module silently stopped syncing into an open
	Studio session and live checks against it were testing the built place instead of
	the edit (`docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`,
	`tools/check_source_size.py`). This is the first of the periphery extractions
	that brings it back under. The ONE ENGINE (`buildEngine`) is deliberately NOT
	split: its ~65 nested functions share ~60 mutable upvalues on purpose. ]]

local specGuard = require("../spec_guard")

local row_actions_spec = {}

export type Edge = "leading" | "trailing"

export type ActionSpec = {
	id: string?, -- defaults to label
	role: ("normal" | "destructive")?, -- destructive paints danger/onDanger
	label: string,
	icon: string?, -- standard_icons name; nil = text only
	onAction: () -> (),
}

local ACTION_KEYS = specGuard.keySet({ "id", "role", "label", "icon", "onAction" })
local FULL_SWIPE_KEYS = specGuard.keySet({ "leading", "trailing" })

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
-- `content` alone; see `pathInsideRow`'s own comment in row_actions.luau for
-- why) from the live path `bindFocusGraph` hands over.
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
		error(`Facet {label}('{rowId}'): \`{edge}[{index}]\` must be a table (ActionSpec)`, 0)
	end
	specGuard.assertKnownKeys(label, raw, ACTION_KEYS, `spec.{edge}[{index}]`)
	if type(raw.label) ~= "string" or raw.label == "" then
		error(`Facet {label}('{rowId}'): \`{edge}[{index}].label\` must be a non-empty string`, 0)
	end
	local role = raw.role
	if role ~= nil and role ~= "normal" and role ~= "destructive" then
		error(
			`Facet {label}('{rowId}'): \`{edge}[{index}].role\` '{tostring(role)}' is not a role. `
				.. "Valid: normal, destructive.",
			0
		)
	end
	if type(raw.onAction) ~= "function" then
		error(`Facet {label}('{rowId}'): \`{edge}[{index}].onAction\` must be a function`, 0)
	end
	local actionId = if raw.id ~= nil then raw.id else raw.label
	if type(actionId) ~= "string" or actionId == "" then
		error(`Facet {label}('{rowId}'): \`{edge}[{index}].id\` must be a non-empty string`, 0)
	end
	if string.find(actionId, "/", 1, true) ~= nil then
		error(`Facet {label}('{rowId}'): {edge} action id '{actionId}' must be path-safe (no "/")`, 0)
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
		error(`Facet {label}('{rowId}'): \`{edge}\` must be an array of ActionSpec, or nil for none`, 0)
	end
	if #raw == 0 then
		error(
			`Facet {label}('{rowId}'): \`{edge}\` is an empty table — use nil for "no actions on this `
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
			error(`Facet {label}('{rowId}'): \`fullSwipe.leading\`/\`trailing\` must be booleans`, 0)
		end
		return { leading = leading, trailing = trailing }
	end
	error(`Facet {label}('{rowId}'): \`fullSwipe\` must be a boolean or \{ leading?, trailing? \}`, 0)
end

row_actions_spec.patternEscape = patternEscape
row_actions_spec.isPathPrefix = isPathPrefix
row_actions_spec.trayId = trayId
row_actions_spec.buildActionSpec = buildActionSpec
row_actions_spec.actionsFor = actionsFor
row_actions_spec.normalizeFullSwipe = normalizeFullSwipe

return row_actions_spec
