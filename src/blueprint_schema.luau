--!strict
-- Public property schema (swiftui-parity-next.md Milestone 0, investment 1):
-- the SINGLE source of truth for what a public `UI.*` constructor accepts.
--
-- Before this module the blueprint layer accepted ANY key into a node's prop
-- bag: a misspelled or unsupported property froze into the node and was then
-- silently dropped by the renderer. That is the exact failure this milestone
-- exists to remove, and it is worst for agent-written screens, where a
-- plausible-looking tree can quietly omit behavior.
--
-- Everything downstream is DERIVED from this table, so the six views of a
-- property can no longer disagree:
--   * `blueprint.make` validates construction against it (unknown key, wrong
--     type, missing required prop, deprecated prop -> immediate error);
--   * `blueprint.PROP_DIRTY` is generated from the `dirty` fields (mount.luau
--     subscribes reactive props to those classes);
--   * `tools/lune/check_prop_parity.luau` proves the schema agrees with
--     `render/authority.luau`, the renderer's write sites, the adapter's
--     `setProp` switch, and `docs/reference/api.md`.
--
-- Field meanings
--   types       accepted logical types (see TYPE_CHECKS below). A prop whose
--               static value fails every entry is a construction error.
--   reactive    the prop may be a Signal/Memo. `false` means a Readable is
--               rejected at construction rather than frozen and ignored.
--   dirty       dirty classes pushed when a reactive value changes. Required
--               whenever `reactive` is true; a reactive prop with no dirty
--               class would schedule nothing.
--   required    construction fails when the key is absent.
--   channel     which subsystem consumes it: "layout" (solver), "style"
--               (paint/style authority), "binding" (adapter data prop),
--               "handler" (a function the renderer wires to an adapter seam),
--               "structural" (mount-layer region control), "semantic"
--               (presenter focus/contract input).
--   deprecated  ADR-0011 ledger entry. A deprecated prop still CONSTRUCTS for
--               its compatibility window but raises a diagnostic instead of
--               silently doing nothing (see `blueprint.make`).
--
-- Adding a property: add it here first, then satisfy `check_prop_parity`.

local themeSnapshot = require("./themes/snapshot")
-- the theme vocabulary itself (PURE, and already in this graph via snapshot):
-- the typography-role list a refusal names comes from the one table that
-- defines it, so the schema can never advertise a stale set.
local themePackage = require("./themes/package")
-- the pure style-modifier layer. ONE ruling on what a `tint` value may be
-- (styling.checkTint), read here for construction and by the adapter for a
-- REACTIVE value at the write site, so the two can never diverge.
local styling = require("./tokens/styling")

local schema = {}

export type Deprecation = {
	since: string,
	removeNoEarlierThan: string,
	replacement: string,
	note: string?,
}

export type PropSpec = {
	types: { string },
	reactive: boolean,
	dirty: { string }?,
	required: boolean?,
	channel: string,
	doc: string,
	deprecated: Deprecation?,
	-- closed value set for a string-valued property. An enum prop used to
	-- accept ANY string and silently do nothing for an unrecognised one — found
	-- live in Studio, where `surface = "panel"` (not a real role) tagged the
	-- node with a selector no style rule matched, so the surface painted
	-- nothing, and `role = "title"` did the same.
	enum: { string }?,
	-- true for the box/container groups every class shares. They are documented
	-- ONCE under `### UI` in the API reference instead of being repeated in
	-- nineteen class entries, and the parity checker enforces that split.
	shared: boolean?,
}

-- ===== logical type checks =================================================
-- "dim"      a layout dimension table: { type = "fixed"|"content"|"fill"|
--            "hug"|"percent"|"minMax"|"aspect", ... }. Rejecting a bare number here is
--            deliberate: `width = 100` used to fall through to content sizing.
-- "sides"    padding/margin: a number or { top?, right?, bottom?, left? }.
-- "metric"   a THEME METRIC NAME (ADR-0019 §2): a space step ("xs".."xl") or a
--            dotted path into the snapshot ("controls.slider.thumbSize",
--            "targetSizes.minimum"). It resolves to pixels on every solve, so a
--            theme swap moves the geometry without rebuilding the blueprint.
-- "typeRole" a typography role name: the size ladder ("caption".."title", plus
--            "control") and the two WEIGHT roles ("strong" emphasis at reading
--            size, "numeral" a rank/score figure). A role supplies the font
--            descriptor and line height as well as the size, so measurement and
--            paint can never disagree about the face.
--
-- A literal number remains legal everywhere a metric name is accepted, and is
-- thereby EXPLICITLY theme-independent — that is the documented escape hatch,
-- and the drift lint is what stops reusable controls from taking it by accident.
-- `dim` and `sides` accept a metric name in each of their numeric fields, so
-- `height = { type = "fixed", px = "controls.popup.triggerHeight" }` and
-- `padding = { left = "m" }` are both ordinary authored values.
local DIM_TYPES: { [string]: boolean } = {
	fixed = true,
	content = true,
	-- `hug` is `content` WITH THE PARENT'S OFFER AS A CEILING. `content` alone
	-- overflows the screen when the content is tall; `fill` alone paints an
	-- empty plate when it is short. See solver.luau's `resolveAxis`.
	hug = true,
	fill = true,
	percent = true,
	minMax = true,
	aspect = true,
}

local SIDE_KEYS: { [string]: boolean } = { top = true, right = true, bottom = true, left = true }

-- THE COMPACT-REPRESENTATION GRAMMAR (compact-label stage, 2026-07-27). A closed
-- set of ONE key, so the shape is checkable and so a later form joins it without
-- a breaking change: `glyph` is DEFERRED, not rejected, and lands here.
--
-- One prop rather than four, and a closed set rather than an open one, because
-- `enum-props-accept-any-string` is this repo's own lesson: a value nothing
-- validates becomes a tag no rule matches, and the UI silently draws nothing.
-- The SEMANTIC half of the grammar -- no whitespace in a compact string, an icon
-- that names a real icon, and no compact form on a content button -- lives in
-- `blueprint.luau` beside `assertShape`, the same split `icon` already uses.
local COMPACT_FORMS: { [string]: boolean } = { text = true, icon = true, image = true }
local COMPACT_FORM_LIST = "text | icon | image"

-- THE STRUCTURAL-TRANSITION VOCABULARY (ADR-0022 Decision 3; ui-designer spec
-- §2.1). Closed, like every other authored vocabulary here, and for the same
-- reason: a form nothing validates is a transition that silently does nothing.
--
-- A form names the direction of TRAVEL — an enter travels toward rest, an exit
-- travels away from it — which is what makes the mirror table below geometrically
-- honest: `slide-up` entering and `slide-down` leaving displace the node to the
-- SAME absent place, so a re-entry mid-exit reverses through one continuous
-- motion instead of jumping across the box. That reversal is the whole point of
-- the retire model, so the vocabulary is built to make it fall out.
--
-- `exit` defaults to the mirror of `enter`: "if it disappears one way, it emerges
-- from where it came" (I-1). An ASYMMETRIC exit is legal but must be declared
-- (`exit = "instant"` is the common one) — undeclared asymmetry does not exist.
local TRANSITION_FORMS: { string } = table.freeze({
	"fade",
	"slide-up",
	"slide-down",
	"slide-left",
	"slide-right",
	"materialize",
	"instant",
})
local TRANSITION_FORM_SET: { [string]: boolean } = {}
for _, form in TRANSITION_FORMS do
	TRANSITION_FORM_SET[form] = true
end
local TRANSITION_FORM_LIST = table.concat(TRANSITION_FORMS, " | ")
local TRANSITION_MIRROR: { [string]: string } = {
	fade = "fade",
	materialize = "materialize",
	instant = "instant",
	["slide-up"] = "slide-down",
	["slide-down"] = "slide-up",
	["slide-left"] = "slide-right",
	["slide-right"] = "slide-left",
}
local TRANSITION_KEYS: { [string]: boolean } = { enter = true, exit = true, class = true, fade = true }
schema.TRANSITION_MIRROR = table.freeze(TRANSITION_MIRROR)
-- forms that drive TRANSPARENCY, and therefore need a declared fade group
-- (`canvasGroup = true`). The coordinator asserts it and names the fix.
schema.TRANSITION_FADES = table.freeze({ fade = true, materialize = true })

local SPACE_STEP_LIST = "xs | s | m | l | xl"
-- DERIVED from the theme package's own vocabulary, never restated: a refusal
-- that names a stale six-role set while the resolver accepts eight is exactly
-- the "documentation states what ships" defect (constitution §14).
local TYPE_ROLE_LIST = table.concat(themePackage.TYPE_ROLES, " | ")
local METRIC_HINT = `a spacing step ({SPACE_STEP_LIST}) or a theme metric path such as `
	.. `"controls.slider.thumbSize" / "targetSizes.minimum"`

-- one ruling on what a metric NAME may be, reused by "metric", "sides" and "dim"
local function metricName(v: any): (boolean, string?)
	if type(v) ~= "string" then
		return false, METRIC_HINT
	end
	-- a leading "-" negates the metric ("-s" = minus one small step): offsets
	-- pull inward from an anchored edge, so the SIGN is the call site's decision
	-- while the magnitude stays theme-owned
	local name = if string.sub(v, 1, 1) == "-" then string.sub(v, 2) else v
	if themeSnapshot.isSpaceStep(name) or themeSnapshot.isMetricPath(name) then
		return true
	end
	return false, `'{v}' names no theme metric — use {METRIC_HINT}`
end

-- numeric dimension fields that may carry a metric name instead of a number
local DIM_METRIC_FIELDS = { "px", "min", "max", "preferred" }

local TYPE_CHECKS: { [string]: (any) -> (boolean, string?) } = {
	string = function(v)
		return type(v) == "string"
	end,
	number = function(v)
		return type(v) == "number"
	end,
	boolean = function(v)
		return type(v) == "boolean"
	end,
	["function"] = function(v)
		return type(v) == "function"
	end,
	table = function(v)
		return type(v) == "table"
	end,
	array = function(v)
		return type(v) == "table"
	end,
	any = function()
		return true
	end,
	readable = function(v)
		if type(v) == "table" and ((v :: any).kind == "signal" or (v :: any).kind == "memo") then
			return true
		end
		return false, "a Signal or Memo (create one with core:signal(...) / core:memo(...))"
	end,
	dim = function(v)
		if type(v) ~= "table" then
			return false, 'a dimension table such as { type = "fixed", px = 120 } or { type = "fill", weight = 1 }'
		end
		if not DIM_TYPES[(v :: any).type] then
			return false,
				`dimension type must be one of fixed|content|hug|fill|percent|minMax|aspect (got {tostring(
					(v :: any).type
				)})`
		end
		for _, field in DIM_METRIC_FIELDS do
			local raw = (v :: any)[field]
			if type(raw) == "string" then
				local ok, why = metricName(raw)
				if not ok then
					return false, `{field}: {why}`
				end
			elseif type(raw) == "table" then
				-- a dimension may ADD several metrics together, exactly as a
				-- padding side already can and for the same reason: "as wide as
				-- this theme's own border, plus room for content" is not one
				-- metric name, and a control cannot pre-compute it because metrics
				-- resolve per solve. Written as a literal px instead, the same
				-- declaration means a different THING under every package — the
				-- showcase's 52px compact button was narrower than the 56px of
				-- pure chrome a Pixel Quest Button costs (director report
				-- 2026-07-28).
				if next(raw) == nil then
					return false, `{field}: an empty list names no metric`
				end
				for _, entry in raw do
					if type(entry) == "string" then
						local ok, why = metricName(entry)
						if not ok then
							return false, `{field}: {why}`
						end
					elseif type(entry) ~= "number" then
						return false, `{field}: a list takes numbers or {METRIC_HINT}, got {typeof(entry)}`
					end
				end
			end
		end
		return true
	end,
	sides = function(v)
		if type(v) == "number" then
			return true
		end
		if type(v) == "string" then
			return metricName(v)
		end
		if type(v) ~= "table" then
			return false, `a number, {METRIC_HINT}, or a ` .. "{ top?, right?, bottom?, left? } table"
		end
		for k, raw in v :: any do
			if not SIDE_KEYS[k] then
				return false, `unknown side '{tostring(k)}' (use top/right/bottom/left)`
			end
			if type(raw) == "string" then
				local ok, why = metricName(raw)
				if not ok then
					return false, `{k}: {why}`
				end
			elseif type(raw) == "table" then
				-- a side may ADD several metrics together — two gutters at two
				-- nesting levels (a clipper's glow allowance plus a card's carved
				-- border), which no single metric name can express and which a
				-- control cannot pre-compute because metrics resolve per solve.
				-- Every entry is still a number or a real metric name, so a typo
				-- inside the list is rejected exactly as it is outside one.
				if next(raw) == nil then
					return false, `{k}: an empty list names no metric`
				end
				for _, entry in raw do
					if type(entry) == "string" then
						local ok, why = metricName(entry)
						if not ok then
							return false, `{k}: {why}`
						end
					elseif type(entry) ~= "number" then
						return false, `{k}: a list side takes numbers or {METRIC_HINT}, got {typeof(entry)}`
					end
				end
			end
		end
		return true
	end,
	compact = function(v)
		-- the sugar: a bare string IS the shorter-text form
		if type(v) == "string" then
			if v == "" then
				return false, "a compact label cannot be the empty string"
			end
			return true
		end
		if type(v) ~= "table" then
			return false, `a shorter string such as "Ed", or a one-key table ({COMPACT_FORM_LIST})`
		end
		local found: string? = nil
		for k, raw in v :: any do
			if type(k) ~= "string" or not COMPACT_FORMS[k] then
				return false, `unknown compact form '{tostring(k)}' (one of {COMPACT_FORM_LIST})`
			end
			if found ~= nil then
				-- two forms is two answers to "what does this button say when it
				-- is small", and nothing downstream could pick between them
				return false,
					`declares both '{found}' and '{k}' — a compact label is exactly ONE of {COMPACT_FORM_LIST}`
			end
			if type(raw) ~= "string" or raw == "" then
				return false, `{k} must be a non-empty string (got {typeof(raw)})`
			end
			found = k
		end
		if found == nil then
			return false, `an empty table names no compact form (one of {COMPACT_FORM_LIST})`
		end
		return true
	end,
	-- A FRACTION OF THE PARENT (ADR-0022 Decision 6, row SF-P5): an anchor offset
	-- may be a share of the anchor's inner extent plus a pixel adjustment, which is
	-- what a marker overlay needs — a minimap dot's u,v is a fraction, and it must
	-- update in the ARRANGE pass without a re-measure or a remount.
	scaleOffset = function(v)
		if type(v) ~= "table" then
			-- NO DETAIL for a non-table: `checkValue` keeps the FIRST explanation any
			-- accepted type offers, and a mistyped metric NAME deserves the metric
			-- vocabulary rather than this table's shape. A table gets this one because
			-- it is the only accepted type shaped like one.
			return false
		end
		for k in v :: any do
			if k ~= "scale" and k ~= "offset" then
				return false, `unknown fractional-offset field '{tostring(k)}' (scale | offset)`
			end
		end
		local scale = (v :: any).scale
		if type(scale) ~= "number" or scale ~= scale then
			return false, "scale must be a number (a fraction of the parent's inner extent; 0.5 = halfway)"
		end
		local offset = (v :: any).offset
		if offset ~= nil and type(offset) ~= "number" then
			if type(offset) == "string" then
				return metricName(offset)
			end
			return false, `offset must be a number of px or {METRIC_HINT}`
		end
		return true
	end,
	-- THE STRUCTURAL-TRANSITION DECLARATION (see TRANSITION_FORMS above). One
	-- ruling, three readers: construction, the coordinator that drives the motion,
	-- and the reference — so a form the coordinator cannot play cannot be authored.
	transition = function(v)
		if type(v) ~= "table" then
			return false, `a transition table such as \{ enter = "fade" } ({TRANSITION_FORM_LIST})`
		end
		for k in v :: any do
			if type(k) ~= "string" or not TRANSITION_KEYS[k] then
				return false, `unknown transition field '{tostring(k)}' (enter | exit | class | fade)`
			end
		end
		local enter = (v :: any).enter
		if enter == nil then
			return false, `a transition declares its \`enter\` form (one of {TRANSITION_FORM_LIST})`
		end
		if not TRANSITION_FORM_SET[enter] then
			return false, `unknown enter form '{tostring(enter)}' (one of {TRANSITION_FORM_LIST})`
		end
		local exit = (v :: any).exit
		if exit ~= nil and not TRANSITION_FORM_SET[exit] then
			return false, `unknown exit form '{tostring(exit)}' (one of {TRANSITION_FORM_LIST})`
		end
		local class = (v :: any).class
		if class ~= nil and (type(class) ~= "string" or class == "") then
			return false, 'class names a MOTION CLASS (a string such as "container"), never inline spring params'
		end
		local fade = (v :: any).fade
		if fade ~= nil and type(fade) ~= "boolean" then
			return false, "fade is a boolean: pair a slide with a transparency fade (needs a canvasGroup node)"
		end
		return true
	end,
	-- THE CONTINUOUS-COLOUR CHANNEL. One ruling, in tokens/styling, so the schema,
	-- the adapter's write site and the reference all quote the same vocabulary.
	tint = styling.checkTint,
	metric = metricName,
	typeRole = function(v)
		if themeSnapshot.isTypeRole(v) then
			return true
		end
		return false, `a typography role ({TYPE_ROLE_LIST}) or an explicit px number`
	end,
}

-- check a STATIC value against a prop spec. Returns (ok, detail?).
function schema.checkValue(spec: PropSpec, value: any): (boolean, string?)
	local detail: string? = nil
	for _, t in spec.types do
		local check = TYPE_CHECKS[t]
		if check == nil then
			error(`LuauUI schema: unknown logical type '{t}'`, 0)
		end
		local ok, why = check(value)
		if ok then
			if spec.enum ~= nil and type(value) == "string" then
				for _, allowed in spec.enum do
					if value == allowed then
						return true
					end
				end
				return false, `one of {table.concat(spec.enum, " | ")}`
			end
			return true
		end
		detail = detail or why
	end
	return false, detail
end

-- ===== shared prop groups ==================================================
-- Every rendered class carries the box props: the solver reads them off any
-- node, and a parent container reads the placement ones off its children.

local function p(spec: PropSpec): PropSpec
	return spec
end

local BOX: { [string]: PropSpec } = {
	width = p({
		types = { "dim" },
		reactive = true,
		dirty = { "measure" },
		shared = true,
		channel = "layout",
		doc = "width dimension; content-sized when absent",
	}),
	height = p({
		types = { "dim" },
		reactive = true,
		dirty = { "measure" },
		shared = true,
		channel = "layout",
		doc = "height dimension; content-sized when absent",
	}),
	margin = p({
		types = { "sides" },
		reactive = true,
		dirty = { "measure" },
		shared = true,
		channel = "layout",
		doc = "outer spacing reserved around this node by its parent",
	}),
	-- placement props a container parent reads off its children
	anchor = p({
		types = { "string" },
		reactive = true,
		dirty = { "arrange" },
		shared = true,
		enum = { "topLeft", "top", "topRight", "left", "center", "right", "bottomLeft", "bottom", "bottomRight" },
		channel = "layout",
		doc = "placement corner inside an Anchor parent (topLeft … bottomRight)",
	}),
	offsetX = p({
		types = { "number", "scaleOffset", "metric" },
		reactive = true,
		dirty = { "arrange" },
		shared = true,
		channel = "layout",
		doc = "horizontal offset from the anchor point (arrange-only update); a number, a theme metric name, "
			.. "or a fraction of the parent's inner width ({ scale = 0.5, offset? })",
	}),
	offsetY = p({
		types = { "number", "scaleOffset", "metric" },
		reactive = true,
		dirty = { "arrange" },
		shared = true,
		channel = "layout",
		doc = "vertical offset from the anchor point (arrange-only update); a number, a theme metric name, "
			.. "or a fraction of the parent's inner height ({ scale = 0.5, offset? })",
	}),
	alignH = p({
		types = { "string" },
		reactive = true,
		dirty = { "arrange" },
		shared = true,
		enum = { "start", "center", "end" },
		channel = "layout",
		doc = "horizontal alignment inside a ZStack parent (start|center|end)",
	}),
	alignV = p({
		types = { "string" },
		reactive = true,
		dirty = { "arrange" },
		shared = true,
		enum = { "start", "center", "end" },
		channel = "layout",
		doc = "vertical alignment inside a ZStack parent (start|center|end)",
	}),
	-- style modifiers (UI.shadow / UI.corners write these; authored directly
	-- they must already be normalized style data)
	shadow = p({
		types = { "table" },
		reactive = true,
		dirty = { "paint" },
		shared = true,
		channel = "style",
		doc = "normalized UIShadow declaration — produced by UI.shadow(bp, …)",
	}),
	-- the per-view GRADIENT modifier (charter cap 11; UI.gradient writes this).
	-- Same authority and same shape of data as `shadow`: bounded, normalized,
	-- materialized by the adapter as ONE bespoke child instance.
	gradient = p({
		types = { "table" },
		reactive = true,
		dirty = { "paint" },
		shared = true,
		channel = "style",
		doc = "normalized UIGradient declaration — produced by UI.gradient(bp, …)",
	}),
	corners = p({
		types = { "table" },
		reactive = true,
		dirty = { "paint" },
		shared = true,
		channel = "style",
		doc = "normalized per-corner rounding — produced by UI.corners(bp, …)",
	}),
	-- the AUTHORED STROKE (ADR-0022 Decision 6, row SF-P3). Same shape, same
	-- authority and same reactive story as the three modifiers above: bind the whole
	-- prop to a memo of `UI.strokeData(…)` to pulse a thickness or an alpha.
	stroke = p({
		types = { "table" },
		reactive = true,
		dirty = { "paint" },
		shared = true,
		channel = "style",
		doc = "normalized UIStroke declaration — produced by UI.stroke(bp, …) / UI.strokeData(…)",
	}),
	-- PAINT ORDER WITHIN THE PARENT'S STACKING SCOPE (ADR-0022 Decision 6, row
	-- SF-P4). NOT reactive, exactly like `shape` and `compactLabel`: a lift is what
	-- a node IS (a drag ghost, a toast), not a state it passes through — and a
	-- reactive value would have to re-run the z walk, which only a structural sync
	-- does, so it would be accepted and ignored.
	zIndex = p({
		types = { "number" },
		reactive = false,
		shared = true,
		channel = "layout",
		doc = "paint-order override within the parent's stacking scope: siblings sort by (zIndex or 0, tree order), "
			.. "and a node's whole subtree travels with it. Cross-surface lifting stays structural (overlay layers)",
	}),
}

-- container-only layout inputs
local CONTAINER_LAYOUT: { [string]: PropSpec } = {
	padding = p({
		types = { "sides" },
		reactive = true,
		dirty = { "measure" },
		shared = true,
		channel = "layout",
		doc = "inner spacing between this container's edge and its children; a number, "
			.. 'a spacing-step name ("xs"…"xl"), or per-side values of either',
	}),
	overflow = p({
		types = { "string" },
		reactive = true,
		dirty = { "measure" },
		shared = true,
		enum = { "clip", "scroll", "visible", "intentionalOverlap" },
		channel = "layout",
		doc = "declared overflow handling (clip|scroll|visible|intentionalOverlap)",
	}),
	clipChildren = p({
		types = { "boolean" },
		reactive = false,
		shared = true,
		channel = "layout",
		doc = "make this container an engine clip host (descendants crop at its edge)",
	}),
	active = p({
		types = { "boolean" },
		reactive = true,
		dirty = { "semantics" },
		shared = true,
		channel = "binding",
		doc = "engine Active flag — an input-sinking panel (modal backdrops)",
	}),
	surface = p({
		types = { "string" },
		reactive = true,
		dirty = { "paint" },
		shared = true,
		enum = { "base", "raised", "control", "chip", "badge", "accent", "scrim", "plain" },
		channel = "style",
		doc = "surface style role painted behind this container",
	}),
}

local GAP: PropSpec = p({
	types = { "number", "metric" },
	reactive = true,
	dirty = { "measure" },
	shared = true,
	channel = "layout",
	doc = 'spacing between children along the stack axis; a number or a spacing-step name ("xs"…"xl")',
})

local ALIGN: PropSpec = p({
	types = { "string" },
	reactive = true,
	dirty = { "measure" },
	shared = true,
	enum = { "start", "center", "end", "stretch" },
	channel = "layout",
	doc = "cross-axis alignment of children (start|center|end|stretch)",
})

-- Horizontal alignment of a node's OWN text inside its own box. Until now the
-- adapter hard-coded TextXAlignment.Left, so there was no way to centre text
-- anywhere in LuauUI at all — which is why a Stepper's value readout could not
-- sit centred between its buttons (director review 2026-07-24). Vertical
-- alignment stays adapter-owned: it is Center everywhere on purpose, because the
-- headless measurer over-reserves and centring splits that error evenly.
local TEXT_ALIGN: PropSpec = p({
	types = { "string" },
	reactive = true,
	dirty = { "paint" },
	shared = true,
	enum = { "start", "center", "end" },
	channel = "style",
	doc = "horizontal alignment of this node's text in its own box (start|center|end)",
})

local TEXT_SIZE: PropSpec = p({
	-- a role name is the intended form; a dotted metric path is the escape for a
	-- control-specific size the role ladder does not name (Table's cell and
	-- sort-mark sizes), which still keeps the value theme-owned
	types = { "number", "typeRole", "metric" },
	reactive = true,
	dirty = { "paint", "measure" },
	shared = true,
	channel = "layout",
	doc = "text size: an explicit px number, or a typography role name "
		.. `({TYPE_ROLE_LIST}) resolved from the active `
		.. "theme. A role also supplies the FONT DESCRIPTOR and line height, so `strong` and "
		.. "`numeral` are how a node asks for weight — both seams read the one role. "
		.. "Either form is scaled at BOTH the measure and paint seams",
})

-- LINE LIMIT (SwiftUI `.lineLimit`, 2026-07-27). "This label gets at most N
-- lines"; the engine ellipsizes the rest (TextTruncate.AtEnd is already on for
-- every text node) instead of the label growing its box.
--
-- It exists because the OWNER is the only one who knows. `singleLine` is derived
-- from the string — one word has no legal break — and answers a different
-- question: how the adapter draws it. Neither the string nor the adapter knows
-- that this label sits in a table row of a fixed height, so nothing capped the
-- measured box and a three-line track name painted straight through two rows on
-- a phone (device report 2026-07-27).
--
-- `measure` and NOT `paint`: the cap changes the reserved box, which is the
-- entire mechanism. A metric name is legal so a theme package can own the
-- number.
local LINE_LIMIT: PropSpec = p({
	types = { "number", "metric" },
	reactive = true,
	dirty = { "measure" },
	-- deliberately NOT `shared`: it lives on Text alone, so it is documented in
	-- Text's own entry rather than in the shared box/container block
	channel = "layout",
	doc = "maximum lines this text may occupy (>= 1). Beyond it the engine "
		.. "truncates with an ellipsis rather than the box growing. Absent = uncapped",
})

-- THE FADE GROUP (ADR-0022 Decision 2). Presentation transparency is offered ONLY
-- through a node that declared this, and the declaration is explicit because it
-- has a real cost: the adapter materializes the node as a CanvasGroup, which
-- renders its subtree into its own buffer and becomes that subtree's real instance
-- parent. In exchange the fade is ONE engine property (GroupTransparency) that no
-- style rule owns — so a subtree fade never contests native-sheet paint, which
-- per-node transparency writes would.
--
-- It lives on `Box` (fade one plate) AND on `ZStack` (fade a SUBTREE): the group's
-- whole value is that it is its descendants' real parent, and a leaf has no
-- descendants — a transition that fades a caption, a toast or a modal needs the
-- container form. ZStack is the overlay container, so wrapping content in one adds
-- a buffer and nothing else.
--
-- NOT reactive: it decides which engine class the node IS, at creation.
local CANVAS_GROUP: PropSpec = p({
	types = { "boolean" },
	reactive = false,
	channel = "layout",
	doc = "materialize this node as a CanvasGroup so its whole subtree can be faded as one "
		.. "(controller.setPresentationTransparency). Costs a render buffer and makes the node its "
		.. "subtree's real parent — declare it only where a group fade is wanted",
})

-- THE STRUCTURAL-TRANSITION DECLARATION (ADR-0022 Decision 3, row SF-M6). A
-- structural region declares how its branch/rows come and go; the mount layer
-- RETIRES a departing subtree (it stays mounted, turns non-interactive, and
-- disposes when the exit completes) instead of disposing it on the spot.
--
-- Not reactive: it is a declaration about the region, read when a child arrives or
-- leaves, never a value that animates. `class` names a MOTION CLASS, never inline
-- spring params (motion/classes.luau owns that vocabulary).
local TRANSITION: PropSpec = p({
	types = { "transition" },
	reactive = false,
	channel = "structural",
	doc = 'enter/exit transition for this region\'s children: { enter = "fade" | "slide-up" | "slide-down" | '
		.. '"slide-left" | "slide-right" | "materialize" | "instant", exit? (default: the mirror of enter), '
		.. 'class? (a motion class name, default "container"), fade? (pair a slide with a transparency fade) }. '
		.. "Fading forms need the child to be a declared canvasGroup node",
})

-- THE CONTINUOUS-COLOUR CHANNEL (ADR-0022 Decision 6, rows SF-P1/SF-P2). Offered
-- on the four classes that HAVE one paint channel of their own — Box's fill,
-- Text's glyphs, Image's multiply, Path's stroke — and nowhere else: a control
-- paints from its role and its states, and a continuous colour on one would be a
-- second, competing authority over the affordance the state machine owns.
--
-- Deliberately NOT `shared`: it lives on four classes, so it is documented in each
-- of their entries next to the engine property it claims.
local TINT: PropSpec = p({
	types = { "tint" },
	reactive = true,
	dirty = { "paint" },
	channel = "binding",
	doc = 'continuous colour: { role = "accent", blend = 0..1, from? } blends between two theme roles '
		.. '(preferred, themable), or { direct = { r, g, b } | "#rrggbb" } declares a theming-exempt '
		.. "identity hue. A value from a CLOSED SET is a state — use surface/role/selected instead",
})

local FOCUSABLE_OPT_OUT: PropSpec = p({
	types = { "boolean" },
	reactive = true,
	dirty = { "navigation" },
	shared = true,
	channel = "semantic",
	doc = "set false to remove this control from focus order (default: focusable)",
})

local function merge(...: { [string]: PropSpec }): { [string]: PropSpec }
	local out: { [string]: PropSpec } = {}
	for _, group in { ... } do
		for k, v in group do
			out[k] = v
		end
	end
	return out
end

-- ===== per-class schema ====================================================

export type ClassSpec = {
	container: boolean,
	structural: boolean,
	props: { [string]: PropSpec },
}

local CLASSES: { [string]: ClassSpec } = {}

local function class(name: string, spec: ClassSpec)
	CLASSES[name] = spec
end

class("Screen", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, { gap = GAP, align = ALIGN }),
})

class("VStack", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, { gap = GAP, align = ALIGN }),
})

class("HStack", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, { gap = GAP, align = ALIGN }),
})

class("ZStack", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, { canvasGroup = CANVAS_GROUP }),
})

class("ScrollView", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, {
		gap = GAP,
		axis = p({
			types = { "string" },
			reactive = false,
			enum = { "y", "x" },
			channel = "layout",
			doc = 'scroll axis: "y" (default) or "x"',
		}),
		onScrollWheel = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onScrollWheel(path, delta, rectOf) — hover-wheel routing from the adapter",
		}),
		autoscroll = p({
			-- DRAG-TO-EDGE AUTOSCROLL BELONGS TO THE SCROLLER, NOT TO ITS CONTENTS
			-- (director, 2026-07-29). The first cut of this put the policy in Table,
			-- which is wrong twice over: a Table is usually NOT the thing that has to
			-- move (a block table inside a scrolling page is the shipped shape), and
			-- every other draggable arrangement — an HStack of cards, a mix — would
			-- have needed its own copy. The scroller knows its own rect, axis, offset
			-- and extent; the drag only has to say where the pointer is.
			--
			-- ON BY DEFAULT, AND INERT. Nothing happens unless a pointer drag is in
			-- flight inside this host's edge band, so a screen with no draggable
			-- content pays a nil check per frame and behaves identically. `false`
			-- opts out; a table tunes the band/dwell/ramp (see `LuauUI.newAutoscroll`).
			types = { "boolean", "table" },
			reactive = false,
			channel = "handler",
			doc = "drag-to-edge autoscroll: `false` to disable (default on, inert unless a drag is in flight), or an options table",
		}),
	}),
})

class("Anchor", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT),
})

class("Grid", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, {
		gap = GAP,
		rowGap = p({
			-- THE ROW GAP IS ITS OWN AXIS (director finding 14, 2026-07-26). A
			-- grid's column pitch is `innerWidth / columns`, so `gap` moves the
			-- cells inside their columns and — through `minColumnWidth` — can
			-- re-column the grid; the ROW pitch IS the gap. Measured live: the
			-- gallery picker ran with rows 4 px apart and columns 78 px apart.
			-- Defaults to `gap`, so every existing grid is byte-unchanged.
			types = { "number", "metric" },
			reactive = true,
			dirty = { "measure" },
			channel = "layout",
			doc = 'vertical spacing between grid ROWS; a number or a spacing-step name ("xs"…"xl"). Defaults to `gap`',
		}),
		columns = p({
			types = { "number" },
			reactive = true,
			dirty = { "measure" },
			channel = "layout",
			doc = "fixed column count (mutually exclusive with minColumnWidth)",
		}),
		minColumnWidth = p({
			-- "intrinsic" (director round 9): the widest CHILD's own measured
			-- width under the active theme's font, recomputed every solve, so a
			-- grid of labels re-columns itself on a theme swap instead of being
			-- sized by a device-pixel guess that only suits one font.
			types = { "number", "string" },
			enum = { "intrinsic" },
			reactive = true,
			dirty = { "measure" },
			channel = "layout",
			doc = 'derive the column count from this minimum cell width (px, or "intrinsic" for the widest child)',
		}),
		itemSizing = p({
			-- OPT-IN uniform cells (director ruling 2026-07-26). `natural` is the
			-- default framework-wide: content sizing is what every existing grid
			-- was authored against. `uniform` measures every child, takes the MAX
			-- across items and gives every cell that size, so a set of ragged
			-- variable-width plates becomes a clean grid — and a wider theme font
			-- grows all of them together on the next solve.
			types = { "string" },
			enum = { "natural", "uniform" },
			reactive = true,
			dirty = { "measure" },
			channel = "layout",
			doc = "natural (default, content-sized cells) | uniform (every cell takes the max measured cell size)",
		}),
	}),
})

class("AdaptiveStack", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, {
		gap = GAP,
		align = ALIGN,
		-- The whole point of this class: ONE class with a REACTIVE axis. Swapping
		-- UI.VStack for UI.HStack through a `When` would remount every child and
		-- lose their state on a viewport flip; a bound axis re-solves in place
		-- (acceptance row A-AL2). Bind it to `adaptive.conditions(...).axis`.
		axis = p({
			types = { "string" },
			reactive = true,
			dirty = { "measure" },
			enum = { "y", "x" },
			channel = "layout",
			doc = 'stack axis: "y" (default) or "x" — reactive, and a flip never remounts a child',
		}),
	}),
})

class("ViewThatFits", {
	container = true,
	structural = false,
	props = merge(BOX, {
		-- children ARE the candidates, in declared preference order. There is no
		-- prop to configure: the choice comes from the real measurement contract
		-- (acceptance row A-AL1), never from a declared minimum width the author
		-- has to keep in sync with the content.
	}),
})

-- DECLARED-CONTENT ADAPTIVE COMPOSITION (ADR-0023).
--
-- Nothing here is reactive, on purpose. `AdaptiveStack` binds an axis because
-- the author decides the axis; a Composition decides FOR the author from the
-- box it was given, on both axes, so a reactive prop would be a second source
-- of truth about a fact the solver already measures. That is the whole point of
-- the mechanism: no screen re-derives a viewport threshold, so no screen can get
-- one wrong.
class("Composition", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, {
		arrangements = p({
			types = { "array" },
			reactive = false,
			channel = "layout",
			required = true,
			doc = 'ordered candidate arrangements, richest first — preset names ("threeLane" | "twoLane" | '
				.. '"column") or tables { name, lanes = { { "lead" }, { "main" } }, eligible? }. `eligible` '
				.. "gates a candidate on a fact geometry cannot show (a size class): false = skip it and try "
				.. "the next, which is different from losing on fit. The LAST one is the declared fallback "
				.. "when none is legal, and is never gated out",
		}),
		groups = p({
			types = { "array" },
			reactive = false,
			channel = "layout",
			required = true,
			doc = "the groups a lane holds: { id, lane (affinity), sizing = hug|fill, weight?, "
				.. "place = start|center|end|0..1, minWidth? (px or metric name), gap? }",
		}),
		laneGap = p({
			types = { "number", "metric" },
			reactive = false,
			channel = "layout",
			doc = "spacing between lanes",
		}),
		groupGap = p({
			types = { "number", "metric" },
			reactive = false,
			channel = "layout",
			doc = "spacing between the groups stacked inside one lane",
		}),
		maxMeasure = p({
			types = { "number", "metric" },
			reactive = false,
			channel = "layout",
			doc = "cap both axes of the box the composition resolves in, and centre the result — the "
				.. '"full width, but no wider than this" shape for very large offers',
		}),
	}),
})

class("Region", {
	container = true,
	structural = false,
	props = merge({
		group = p({
			types = { "string" },
			reactive = false,
			channel = "layout",
			required = true,
			doc = "the group this region travels with (a group is the unit a lane holds)",
		}),
		rank = p({
			types = { "number" },
			reactive = false,
			channel = "layout",
			required = true,
			doc = "adaptation priority, 1 = most important. Step-down and drop both go DESCENDING rank, "
				.. "ties broken by declaration order — so every device is predictable from the table alone",
		}),
		floor = p({
			-- A FLOOR IS CONTENT, NEVER A PIXEL COUNT. "One line" survives a theme
			-- swap, a preferred-text change and a locale; `28` survives none of
			-- them, and a floor that is wrong is a region rendered as a sliver —
			-- which is the one thing this mechanism promises can never happen.
			types = { "table" },
			reactive = false,
			channel = "layout",
			doc = "the minimum content this region must be able to show: { lines = n, role? } and/or "
				.. "{ targets = n }. Absent, the floor is the minimum-viable form's own measure",
		}),
		sizing = p({
			types = { "string" },
			reactive = false,
			enum = { "hug", "fill" },
			channel = "layout",
			doc = "hug (default, takes its content) | fill (takes the slack above its floor)",
		}),
		weight = p({
			types = { "number" },
			reactive = false,
			channel = "layout",
			doc = "share of the slack when several regions in a group fill (default 1)",
		}),
		mayScroll = p({
			types = { "boolean" },
			reactive = false,
			channel = "layout",
			doc = "this is THE scroll region. At most one per composition; a second is refused at "
				.. "construction, because two scrolling regions on one surface is a declaration mistake",
		}),
		mayDrop = p({
			types = { "boolean" },
			reactive = false,
			channel = "layout",
			doc = "this region may be removed entirely when stepping down is not enough (default false)",
		}),
		-- THE ONE REACTIVE PROP ON A REGION, and it is reactive for a reason the
		-- rest of the declaration is not. Every other field answers "what is this
		-- region" — a fact about the screen, which is why re-deriving it from state
		-- would be a second source of truth. `reserved` answers "is this region's
		-- SCHEDULE still running", which is a fact about TIME that only the caller
		-- holds. Pinned `true` it is what it always was; bound to a live read it
		-- holds the box mid-sequence and releases it — with the whole lane, rule 9
		-- — once the schedule is provably done or never started.
		reserved = p({
			types = { "boolean" },
			reactive = true,
			dirty = { "measure" },
			channel = "layout",
			doc = "hold this region's box while its content rests BETWEEN pieces, so a finishing "
				.. "transient never moves its neighbours. `true` reserves for the surface's whole life; "
				.. "a Readable<boolean> reserves only while it reads true (the schedule is still able to "
				.. "produce a piece) and leaves the region as empty as any other when it reads false. "
				.. "Mutually exclusive with mayDrop",
		}),
	}),
})

class("Divider", {
	container = false,
	structural = false,
	props = merge(BOX, {
		-- axis-aware by default: a Divider infers its orientation from the
		-- enclosing stack, so the same declaration is a horizontal hairline in a
		-- VStack and a vertical one in an HStack (acceptance row A-LV3). An
		-- explicit axis overrides the inference.
		axis = p({
			types = { "string" },
			reactive = true,
			dirty = { "measure" },
			enum = { "y", "x" },
			channel = "layout",
			doc = 'explicit orientation — "y" spans horizontally, "x" spans vertically; inferred from the parent stack when absent',
		}),
		-- THEME-OWNED LIKE EVERY OTHER NUMBER OF ITS KIND (BP-F12). The default
		-- IS a metric (`metrics.strokes.hairline`, resolved by the renderer), so
		-- refusing the metric NAME made this the one theme-owned number an author
		-- could not track — and the doc claimed a literal default it never had.
		thickness = p({
			types = { "number", "metric" },
			reactive = true,
			dirty = { "measure" },
			channel = "layout",
			doc = 'hairline thickness: a px number or a theme metric name. Absent = the theme\'s "strokes.hairline"',
		}),
	}),
})

class("Box", {
	container = false,
	structural = false,
	props = merge(BOX, {
		surface = CONTAINER_LAYOUT.surface,
		active = CONTAINER_LAYOUT.active,
		tint = TINT,
		-- THE FADE-ABLE SUBTREE (ADR-0022 Decision 2). Presentation transparency is
		-- offered ONLY through a node that declared this, and the declaration is
		-- explicit because it has a real cost: the adapter materializes the node as a
		-- CanvasGroup, which renders its subtree into its own buffer and becomes that
		-- subtree's real instance parent. In exchange the fade is ONE engine property
		-- (GroupTransparency) that no style rule owns — so a subtree fade never
		-- contests native-sheet paint, which per-node transparency writes would.
		--
		-- NOT reactive: it decides which engine class the node IS, at creation.
		canvasGroup = CANVAS_GROUP,
	}),
})

class("Spacer", {
	container = false,
	structural = false,
	props = merge(BOX),
})

class("Text", {
	container = false,
	structural = false,
	props = merge(BOX, {
		text = p({
			types = { "string", "number" },
			reactive = true,
			dirty = { "paint", "measure" },
			required = true,
			channel = "binding",
			doc = "the displayed string",
		}),
		textSize = TEXT_SIZE,
		textAlign = TEXT_ALIGN,
		lineLimit = LINE_LIMIT,
		tint = TINT,
		-- the solver's text measure adds padding to the reserved box, so this is a
		-- real layout input on a label (it lets UI.padding apply without wrapping)
		padding = CONTAINER_LAYOUT.padding,
		-- A DELIBERATELY NARROWER VOCABULARY than Box's (director fix round
		-- 2026-07-25). Box and Image take all eight surfaces; a Text takes the two
		-- that are READ-ONLY BY NATURE, and the restriction is the point:
		--
		--   badge  the counter seal — the case this prop exists for. Without it
		--          the `badge` decoration slot had no public authoring path at
		--          all: the slot shipped, the guide promised "a badge is a
		--          TextLabel", and no constructor could put the surface on one.
		--   chip   a read-only tag/pill/status label — the same plate a drag chip
		--          wears, on something that only labels itself.
		--
		-- The other six are rejected because a Text is NOT INTERACTIVE and each of
		-- them says otherwise or says nothing:
		--   control / accent  are affordances. `accent` is documented as the
		--                     PRIMARY-ACTION treatment and `control` as the
		--                     pressable fill; wearing either makes a label look
		--                     pressable, which is the exact class of lie the
		--                     affordance matrix exists to prevent (a11y §8.4,
		--                     "every affordance states itself").
		--   raised            is the panel treatment. A label on a card is a Box
		--                     WITH a Text inside it, so that the panel's content
		--                     insets have something to inset; a single node
		--                     playing both parts has nowhere to put them.
		--   base / scrim      are backdrops — the app background and the modal
		--                     dimmer. A label is neither, and `scrim` additionally
		--                     suppresses interaction state on a node that has none.
		--   plain             is "no chrome", which is already what a Text with no
		--                     surface is. It would be a second spelling of the
		--                     default.
		-- A game that genuinely wants a label on a control-coloured plate wraps it
		-- in a Box, which is one node more and honest about what it is.
		surface = p({
			types = { "string" },
			reactive = true,
			dirty = { "paint" },
			enum = { "badge", "chip" },
			channel = "style",
			doc = 'read-only surface role painted behind this label — "badge" (the counter seal) or '
				.. '"chip" (a tag/pill). A Text is not interactive, so the pressable surfaces '
				.. "(control/accent), the panel surface (raised) and the backdrops (base/scrim) are "
				.. "deliberately NOT offered: wrap the label in a UI.Box for those",
		}),
		role = p({
			types = { "string" },
			reactive = true,
			dirty = { "paint" },
			-- A REACTIVE ROLE HAS TO BE ABLE TO NAME BOTH ENDS. `role` is declared
			-- reactive, so a label that recedes and comes back (a list row leaving a
			-- disabled state) binds it — and with `"secondary"` the only legal value
			-- the return trip had no word: a binding can only resolve to a value, and
			-- `nil` drops the prop instead of writing the default. `"content"` is that
			-- word — the resting role, explicit, so the closed set is round-trippable.
			enum = { "secondary", "content" },
			channel = "style",
			doc = 'text style role — "secondary" (receded) or "content" (the resting '
				.. "default, worth naming so a REACTIVE role can return to it; the "
				.. "ten-foot strong treatment is applied by the distance profile, not authored)",
		}),
		color = p({
			types = { "any" },
			reactive = true,
			dirty = { "paint" },
			channel = "style",
			doc = "DEPRECATED — never reached the adapter; use `role`",
			deprecated = {
				since = "0.5.0",
				removeNoEarlierThan = "0.6.0",
				replacement = "UI.Text{ role = … }",
				note = "Text.color was declared and documented but no render target ever consumed it: "
					.. "a reactive color scheduled paint work the adapter dropped. Text color is style "
					.. "authority (native StyleSheet / style role), never an authored literal.",
			},
		}),
		font = p({
			types = { "string" },
			reactive = false,
			channel = "layout",
			doc = "DEPRECATED — measurement-only; the adapter never painted it",
			deprecated = {
				since = "0.5.0",
				removeNoEarlierThan = "0.6.0",
				replacement = "UI.Text{ role = … } (fonts are style authority)",
				note = "Text.font reached the text-metrics measure seam but no paint seam, so an "
					.. "authored font silently made measured and painted bounds disagree. FontFace is "
					.. "owned by the style sheet (authority.nativeSheetOwned).",
			},
		}),
	}),
})

class("Image", {
	container = false,
	structural = false,
	props = merge(BOX, {
		-- NOT required: an Image may mount empty and receive content later (the
		-- async-image control binds a Readable that starts as ""), and a
		-- surface-only Image is a legitimate placeholder shape.
		image = p({
			types = { "string" },
			reactive = true,
			dirty = { "paint" },
			channel = "binding",
			doc = "engine content/asset string",
		}),
		surface = CONTAINER_LAYOUT.surface,
		tint = TINT,
		-- HOW THE PICTURE FILLS THE BOX THE SOLVER GAVE IT (ADR-0022 Decision 6, row
		-- SF-P2). `slice` is deliberately absent: nine-slice geometry is theme-owned
		-- chrome (a recipe's sliceCenter/sliceScale), and an authored slice would be a
		-- second authority over the same three engine properties.
		scaleMode = p({
			types = { "string" },
			reactive = true,
			dirty = { "paint" },
			enum = { "fit", "fill", "crop", "stretch" },
			channel = "style",
			doc = "how the picture fills its box: fit (contain, whole picture visible) | fill | crop (cover, "
				.. "overflow cropped — two names for the engine's Crop) | stretch (ignore the aspect ratio, "
				.. "the engine default)",
		}),
	}),
})

-- Button is a CONTAINER (B-BTN1): custom visual content lives inside the ONE
-- activation surface. `blueprint.Button` additionally rejects a focusable in that
-- content, so a content button can never create a second focus or activation site.
class("Button", {
	container = true,
	structural = false,
	props = merge(BOX, {
		role = p({
			types = { "string" },
			reactive = true,
			dirty = { "paint" },
			enum = { "default", "cancel", "destructive" },
			channel = "style",
			doc = "semantic role — drives a style tag and its sheet rule (never a bespoke fill)",
		}),
		gap = GAP,
		align = ALIGN,
		-- THE CIRCLE BUTTON (feature round 2026-07-26; the iOS floating round
		-- "..." action). `shape` is a closed set of two and defaults to the
		-- rectangle every existing Button already is, so nothing that predates it
		-- moves by a pixel. NOT reactive: a shape is what the control IS, not a
		-- state it passes through, and a reactive shape would re-solve one axis
		-- against the other mid-flight for no expressive gain.
		shape = p({
			types = { "string" },
			reactive = false,
			enum = { "rect", "circle" },
			channel = "style",
			doc = '"circle" makes a TRUE 1:1 disc whose diameter is the control metric '
				.. "(controls.button.height) — the solver enforces the square, so an authored width "
				.. "or height drives the other axis and neither means the metric",
		}),
		-- SEMANTIC ICON CONTENT (ADR-0020 R4) for the one shape whose content is a
		-- single mark. A NAME, never an asset id: the framework draws its own
		-- ASCII-safe glyph and a package that ships art for that name has the
		-- adapter paint the picture over it. Circle-only on purpose — an icon
		-- BESIDE a title is `LuauUI.newLabel`, which already owns that layout.
		icon = p({
			types = { "string" },
			reactive = false,
			channel = "style",
			doc = 'semantic icon NAME for shape = "circle" ("more", "close", "menu", "chevron.trailing", '
				.. 'a namespaced "ns:name", …) — never an asset id; `label` stays the semantic name and is '
				.. "not drawn",
		}),
		label = p({
			types = { "string", "number" },
			reactive = true,
			dirty = { "paint", "measure" },
			required = true,
			channel = "binding",
			doc = "semantic label — required even when the button renders custom content",
		}),
		-- WHAT THIS BUTTON SAYS WHEN IT HAS LESS ROOM (director, 2026-07-27). The
		-- solver picks it when the full label does not fit the box the button will
		-- occupy, and the ladder is: full label fits -> full label; does not fit ->
		-- this; absent -> the word/phrase rule (an ellipsis or a wrap).
		--
		-- NOT reactive, exactly like `shape` and `icon`: a compact representation
		-- is what the control HAS, not a state it passes through. The `label` it
		-- stands in for is still free to be a binding — the table's own toggle
		-- flips Edit <-> Done under one unchanging pencil.
		compactLabel = p({
			types = { "compact" },
			reactive = false,
			channel = "style",
			doc = 'the shorter thing to draw when the full label does not fit — "Ed", '
				.. '{ text = "Ed" }, { icon = "edit" } (semantic, themable, degrades to the '
				.. 'framework glyph) or { image = "rbxassetid://…" } (raw, does not degrade). '
				.. "With one declared, the framework never ellipsizes",
		}),
		enabled = p({
			types = { "boolean" },
			reactive = true,
			dirty = { "paint", "semantics" },
			channel = "binding",
			doc = "false removes the control from focus and activation and paints the disabled state",
		}),
		selected = p({
			types = { "boolean" },
			reactive = true,
			dirty = { "paint", "semantics" },
			channel = "binding",
			doc = "app-state selection — rides a style tag, never a bespoke fill",
		}),
		focusable = FOCUSABLE_OPT_OUT,
		surface = CONTAINER_LAYOUT.surface,
		padding = CONTAINER_LAYOUT.padding,
		textSize = TEXT_SIZE,
		onActivate = p({
			types = { "function" },
			reactive = false,
			shared = true,
			channel = "semantic",
			doc = "onActivate(path, meta) — the PRESENTER auto-dispatches tap / Return / ButtonA here (ADR-0013)",
		}),
		onPointerDown = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onPointerDown(path, pos, rectOf) — capture-based pointer zone (ADR-0008)",
		}),
		onPointerMove = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onPointerMove(path, pos, rectOf)",
		}),
		onPointerUp = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onPointerUp(path, pos, rectOf)",
		}),
		onPointerCancel = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onPointerCancel(path, reason) — return true to keep a capture alive",
		}),
	}),
})

class("Toggle", {
	container = false,
	structural = false,
	props = merge(BOX, {
		label = p({
			types = { "string", "number" },
			reactive = true,
			dirty = { "paint", "measure" },
			required = true,
			channel = "binding",
			doc = "semantic label",
		}),
		value = p({
			types = { "boolean" },
			reactive = true,
			dirty = { "paint", "semantics" },
			channel = "binding",
			doc = "boolean state; a settable Signal is AUTO-FLIPPED on Activate",
		}),
		enabled = p({
			types = { "boolean" },
			reactive = true,
			dirty = { "paint", "semantics" },
			channel = "binding",
			doc = "false removes the control from focus and activation",
		}),
		focusable = FOCUSABLE_OPT_OUT,
		padding = CONTAINER_LAYOUT.padding,
		textSize = TEXT_SIZE,
		onActivate = p({
			types = { "function" },
			reactive = false,
			shared = true,
			channel = "semantic",
			doc = "onActivate(path, meta) — takes over from the presenter's auto value flip",
		}),
	}),
})

class("TextField", {
	container = false,
	structural = false,
	props = merge(BOX, {
		text = p({
			types = { "string" },
			reactive = true,
			dirty = { "paint", "measure" },
			channel = "binding",
			doc = "current value (the owner holds the Signal; the field never creates one)",
		}),
		placeholder = p({
			types = { "string" },
			reactive = true,
			dirty = { "paint", "measure" },
			channel = "binding",
			doc = "shown while the value is empty; also the intrinsic measure source",
		}),
		editing = p({
			types = { "boolean" },
			reactive = true,
			dirty = { "semantics" },
			channel = "binding",
			doc = "drives the adapter's CaptureFocus/ReleaseFocus handshake",
		}),
		enabled = p({
			types = { "boolean" },
			reactive = true,
			dirty = { "paint", "semantics" },
			channel = "binding",
			doc = "false removes the field from focus and editing",
		}),
		focusable = FOCUSABLE_OPT_OUT,
		padding = CONTAINER_LAYOUT.padding,
		textSize = TEXT_SIZE,
		maxLength = p({
			types = { "number" },
			reactive = true,
			dirty = { "semantics" },
			channel = "binding",
			doc = "best-effort engine length hint (validation still enforces it)",
		}),
		keyboardType = p({
			types = { "string" },
			reactive = true,
			dirty = { "semantics" },
			channel = "binding",
			doc = "declared intent only — Roblox exposes no keyboard-type API",
		}),
		onTextChanged = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onTextChanged(text) — engine edit reported through the adapter seam",
		}),
		onFocusGained = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onFocusGained(path) — engine-initiated focus delivers the node path",
		}),
		onFocusLost = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onFocusLost(reason) — reason ∈ enter | focusLost | cancel",
		}),
	}),
})

class("Grip", {
	container = false,
	structural = false,
	props = merge(BOX, {
		cursorHint = p({
			types = { "string" },
			reactive = true,
			dirty = { "paint" },
			channel = "binding",
			doc = "engine MouseIcon hint for this pointer zone",
		}),
		focusable = p({
			types = { "boolean" },
			reactive = true,
			dirty = { "navigation" },
			channel = "semantic",
			doc = "opt IN to focus order (Grips are unfocusable by default)",
		}),
		onPointerDown = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onPointerDown(path, pos, rectOf) — return false to decline the capture",
		}),
		onPointerMove = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onPointerMove(path, pos, rectOf)",
		}),
		onPointerUp = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onPointerUp(path, pos, rectOf)",
		}),
		onPointerCancel = p({
			types = { "function" },
			reactive = false,
			channel = "handler",
			doc = "onPointerCancel(path, reason)",
		}),
	}),
})

class("Path", {
	container = false,
	structural = false,
	props = merge(BOX, {
		points = p({
			types = { "array" },
			reactive = true,
			dirty = { "paint" },
			required = true,
			channel = "binding",
			doc = "normalized Path2D control points from LuauUI.pathShapes",
		}),
		thickness = p({
			-- same ruling as Divider.thickness (BP-F12): a theme-owned number
			-- accepts the theme's own vocabulary
			types = { "number", "metric" },
			reactive = true,
			dirty = { "paint" },
			channel = "binding",
			doc = "stroke thickness: a px number or a theme metric name",
		}),
		closed = p({
			types = { "boolean" },
			reactive = true,
			dirty = { "paint" },
			channel = "binding",
			doc = "close the stroke back to its first point",
		}),
		role = p({
			types = { "string" },
			reactive = true,
			dirty = { "paint" },
			enum = { "accent", "secondary", "content" },
			channel = "style",
			doc = "stroke style role — never a raw color",
		}),
		tint = TINT,
	}),
})

-- structural regions: mount-layer control flow, no rendered box of their own
class("When", {
	container = false,
	structural = true,
	props = {
		condition = p({
			types = { "readable" },
			reactive = true,
			dirty = { "structure" },
			required = true,
			channel = "structural",
			doc = "Signal/Memo of a boolean — mounts/unmounts the branch",
		}),
		thenView = p({
			types = { "function" },
			reactive = false,
			required = true,
			channel = "structural",
			doc = "() -> Blueprint, run when the condition is true",
		}),
		transition = TRANSITION,
	},
})

class("ForEach", {
	container = false,
	structural = true,
	props = {
		items = p({
			types = { "readable" },
			reactive = true,
			dirty = { "structure" },
			required = true,
			channel = "structural",
			doc = "Signal/Memo of an array",
		}),
		key = p({
			types = { "function" },
			reactive = false,
			required = true,
			channel = "structural",
			doc = "(item) -> string; duplicate keys are hard errors",
		}),
		row = p({
			types = { "function" },
			reactive = false,
			required = true,
			channel = "structural",
			doc = "(item, itemScope) -> Blueprint",
		}),
		transition = TRANSITION,
	},
})

class("ErrorBoundary", {
	container = false,
	structural = true,
	props = {
		view = p({
			types = { "function" },
			reactive = false,
			required = true,
			channel = "structural",
			doc = "() -> Blueprint — the guarded subtree",
		}),
		fallback = p({
			types = { "function" },
			reactive = false,
			required = true,
			channel = "structural",
			doc = "(err) -> Blueprint — replaces the subtree when a factory throws",
		}),
	},
})

-- ===== the authority tables are FROZEN =====================================
-- (api-architecture-consistency F-6 / ledger BP-F5.) `schema.all()` and
-- `schema.forClass()` are a documented tooling seam and they used to hand out
-- the LIVE tables: `UI.schema.all().Text.props.text.required = false` disabled
-- framework validation process-wide, and a well-meaning tool that annotated a
-- ClassSpec mutated the shipped contract. `deprecations()` / `propDirty()` /
-- `propNames()` already build fresh tables per call, so the seam's only mutable
-- half was this one.
--
-- Nothing internal writes a ClassSpec after build — every reader (blueprint's
-- `make`/`withProps`/`padding`, `check_prop_parity`, the specs) only looks — so
-- the freeze is a pure tightening. It is DEEP because one level would leave
-- every PropSpec, its `types` array and its `enum` set writable, which is the
-- half that matters.
--
-- IDEMPOTENT BY CONSTRUCTION: PropSpec tables are deliberately SHARED between
-- classes (BOX, CONTAINER_LAYOUT, GAP, TINT …) and `table.freeze` throws on an
-- already-frozen table, so the walk checks `table.isfrozen` first.
local function deepFreeze(value: any)
	if type(value) ~= "table" or table.isfrozen(value) then
		return
	end
	table.freeze(value)
	for _, entry in value :: any do
		deepFreeze(entry)
	end
end

for _, classSpec in CLASSES do
	deepFreeze(classSpec)
end
table.freeze(CLASSES)

-- ===== accessors ===========================================================

function schema.forClass(name: string): ClassSpec?
	return CLASSES[name]
end

function schema.all(): { [string]: ClassSpec }
	return CLASSES
end

function schema.classNames(): { string }
	local out = {}
	for name in CLASSES do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

-- PROP_DIRTY, derived: class -> prop -> dirty classes. mount.luau subscribes a
-- reactive prop to exactly these classes.
function schema.propDirty(): { [string]: { [string]: { string } } }
	local out: { [string]: { [string]: { string } } } = {}
	for name, spec in CLASSES do
		local m: { [string]: { string } } = {}
		for prop, ps in spec.props do
			if ps.dirty ~= nil then
				m[prop] = ps.dirty
			end
		end
		out[name] = m
	end
	return out
end

-- every deprecated prop, as ADR-0011 ledger rows
function schema.deprecations(): {
	{
		surface: string,
		since: string,
		removeNoEarlierThan: string,
		replacement: string,
		note: string?,
	}
}
	local out = {}
	for _, name in schema.classNames() do
		local spec = CLASSES[name]
		local props = {}
		for prop in spec.props do
			table.insert(props, prop)
		end
		table.sort(props)
		for _, prop in props do
			local d = spec.props[prop].deprecated
			if d ~= nil then
				table.insert(out, {
					surface = `UI.{name}.{prop}`,
					since = d.since,
					removeNoEarlierThan = d.removeNoEarlierThan,
					replacement = d.replacement,
					note = d.note,
				})
			end
		end
	end
	return out
end

-- ===== diagnostics =========================================================

-- Damerau-free Levenshtein, bounded: good enough to name the intended prop.
local function distance(a: string, b: string): number
	local la, lb = #a, #b
	if la == 0 then
		return lb
	end
	if lb == 0 then
		return la
	end
	local prev = table.create(lb + 1, 0)
	local cur = table.create(lb + 1, 0)
	for j = 0, lb do
		prev[j + 1] = j
	end
	for i = 1, la do
		cur[1] = i
		local ca = string.byte(a, i)
		for j = 1, lb do
			local cost = if ca == string.byte(b, j) then 0 else 1
			cur[j + 1] = math.min(cur[j] + 1, prev[j + 1] + 1, prev[j] + cost)
		end
		prev, cur = cur, prev
	end
	return prev[lb + 1]
end

-- suggest(class, badProp) -> "did you mean 'x' or 'y'?" style list (may be empty)
--
-- THE TWO RESERVED KEYS ARE CANDIDATES TOO (BP-F14). `id` and `children` live
-- OUTSIDE `spec.props` — `make` handles both before the schema lookup — so the
-- two most-typed keys in the layer were the two the suggester could not help
-- with: `UI.Text{ idd = … }` and `UI.VStack{ childern = … }` listed every valid
-- property and never the one word that was meant. `children` is offered only by
-- a container, because on a leaf it is not a legal key either.
function schema.suggest(className: string, bad: string): { string }
	local spec = CLASSES[className]
	if spec == nil then
		return {}
	end
	local candidates: { string } = { "id" }
	if spec.container then
		table.insert(candidates, "children")
	end
	for prop in spec.props do
		table.insert(candidates, prop)
	end
	local lowerBad = string.lower(bad)
	local scored: { { name: string, d: number } } = {}
	for _, prop in candidates do
		local d = distance(lowerBad, string.lower(prop))
		-- accept close spellings and case/prefix confusions
		if d <= math.max(2, math.floor(#prop / 3)) then
			table.insert(scored, { name = prop, d = d })
		end
	end
	table.sort(scored, function(x, y)
		if x.d ~= y.d then
			return x.d < y.d
		end
		return x.name < y.name
	end)
	local out = {}
	for i, entry in scored do
		if i > 3 then
			break
		end
		table.insert(out, entry.name)
	end
	return out
end

-- the full sorted valid-prop list for a class (used in error text)
-- the shared box/container props, documented once under `### UI`
function schema.sharedPropNames(): { string }
	local seen: { [string]: boolean } = {}
	for _, spec in CLASSES do
		for prop, ps in spec.props do
			if ps.shared and ps.deprecated == nil then
				seen[prop] = true
			end
		end
	end
	local out = {}
	for prop in seen do
		table.insert(out, prop)
	end
	table.sort(out)
	return out
end

function schema.propNames(className: string): { string }
	local spec = CLASSES[className]
	if spec == nil then
		return {}
	end
	local out = {}
	for prop, ps in spec.props do
		if ps.deprecated == nil then
			table.insert(out, prop)
		end
	end
	table.sort(out)
	return out
end

return schema
