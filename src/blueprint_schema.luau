--!strict
-- Public property schema (parity-next.md Milestone 0, investment 1):
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
--               (presenter focus/contract input), "presentation" (ADR-0026: the
--               renderer folds it into the PRESENTATION authority's own write —
--               it never reaches an `adapter.setProp` of its own, which is what
--               makes it a second TERM rather than a second WRITER).
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
-- the one reading of the `textSize = "fit"` grammar, shared with both seams
local textFitLib = require("./layout/text_fit")
-- the pure style-modifier layer. ONE ruling on what a `tint` value may be
-- (styling.checkTint), read here for construction and by the adapter for a
-- REACTIVE value at the write site, so the two can never diverge.
local styling = require("./tokens/styling")
local textDistance = require("./text_distance")

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
--            "hug"|"percent"|"minMax"|"aspect"|"containerRelative", ... }. Rejecting a
--            bare number here is deliberate: `width = 100` used to fall through to
--            content sizing.
--            `type = "content"` alone measures the node's own children (the
--            historic meaning). Adding `lines = n` or `rows = n, of = metric`
--            (framework-gaps-phase2 gap 3) turns it into a FORMULA instead — "N
--            lines of a typography role" / "N rows of a named theme metric" —
--            for the box that must show LESS than all of its content (a
--            scroller's viewport) and so cannot be answered by measuring it.
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
	-- `containerRelative` is `percent` measured against a DIFFERENT ruler (parity
	-- round 2 §2.5): the nearest ancestor that owns a viewport — a ScrollView's
	-- content viewport, else the surface root — rather than the immediate parent's
	-- offer. Written only by `UI.containerRelativeFrame(bp, spec)`; authored by hand
	-- it is legal but the modifier is what carries the closed-key refusals.
	containerRelative = true,
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
-- ...plus ONE modifier, which is not a form (it names no content) and so does not
-- collide with the exactly-one-form rule below. `prefer = true` means "wear this
-- representation whenever there IS one", inverting the ladder from a DEGRADE into
-- a DEFAULT. It exists because the row-action tray needs it (director ruling,
-- 2026-08-12: a tray button leads with its icon and keeps `label` as the semantic
-- name): the ladder's own "does the full label fit" test cannot express it — a
-- narrow enough box makes "Delete" compact while "Flag" still fits, so half a tray
-- would wear icons and half would wear words.
local COMPACT_MODIFIERS: { [string]: string } = { prefer = "boolean" }

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

-- DERIVED from the theme package's own vocabulary, never restated — for the same
-- reason the role list below is, and it was a literal until the DIR wave added
-- the derived `gutter` step and this message went stale in the same commit that
-- made the step legal.
local SPACE_STEP_LIST = table.concat(themePackage.SPACE_STEPS, " | ")
-- DERIVED from the theme package's own vocabulary, never restated: a refusal
-- that names a stale six-role set while the resolver accepts eight is exactly
-- the "documentation states what ships" defect (constitution §14).
local TYPE_ROLE_LIST = table.concat(themePackage.TYPE_ROLES, " | ")
-- the SET twin of the list above, for the closed-role check a content-terms
-- `lines` dim needs (framework-gaps-phase2 gap 3) — same source, same reason
-- the list itself is derived rather than restated
local TYPE_ROLE_SET: { [string]: boolean } = {}
for _, role in themePackage.TYPE_ROLES do
	TYPE_ROLE_SET[role] = true
end
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

-- numeric dimension fields that may carry a metric name instead of a number.
-- `of` joined this list 2026-08-23 (framework-gaps-phase2 gap 3): a content-
-- terms `rows` dim's per-row unit is "a metric name, a literal px number, or
-- an additive list of either" — the SAME escape hatch `px`/`min`/`max`/
-- `preferred` already grant, so it rides their existing validation loop below
-- rather than a second copy of it. `themes/snapshot.luau` carries the same
-- addition to its OWN copy of this list (`resolveDim`'s), which is what turns
-- a metric name into a number at prop-normalization time.
local DIM_METRIC_FIELDS = { "px", "min", "max", "preferred", "of" }

-- ===== the authored presentation domain (ADR-0026) =========================
-- ONE ruling per property, read HERE for a static value and by the RENDERER for
-- a reactive one at the moment it reads it — the same split `styling.checkTint`
-- already uses, and for the same reason: a reactive value that skipped the check
-- would paint garbage the constructor would have refused.
--
-- NaN is refused explicitly on all three. It compares false against every bound,
-- so a range test alone lets it through, and an NaN reaching `GroupTransparency`
-- or `UIScale.Scale` is an invisible or absent node with no error anywhere.

function schema.checkOpacity(v: any): (boolean, string?)
	if type(v) ~= "number" or v ~= v then
		return false, "a number from 0 (invisible) to 1 (opaque)"
	end
	if v < 0 or v > 1 then
		return false, `a number from 0 (invisible) to 1 (opaque), got {v}`
	end
	return true
end

function schema.checkScaleFactor(v: any): (boolean, string?)
	if type(v) ~= "number" or v ~= v then
		return false, "a POSITIVE number (1 = unscaled)"
	end
	if v <= 0 then
		return false,
			`a POSITIVE number (1 = unscaled), got {v}. A zero or negative scale is not a smaller view — `
				.. "it is an absent or mirrored one, and the engine draws neither. Use `hidden = true` to "
				.. "remove a view while keeping its box"
	end
	return true
end

function schema.checkDegrees(v: any): (boolean, string?)
	if type(v) ~= "number" or v ~= v then
		return false, "a number of DEGREES (0 = upright, positive = clockwise)"
	end
	return true
end

--[[ THE FOURTH AUTHORED PRESENTATION TERM (gap 16, framework-gaps-phase2;
	ADR-0026 amendment). `scale`/`rotation` already prove the boundary: a
	paint-only perturbation the solver never sees, composed with whatever the
	framework is doing to the same node. `offset` is that same class of thing
	for TRANSLATION — it is NOT how a node's box gets positioned (that stays
	the solver's, per `width`/`height`/`margin`/`Anchor`); it is a decorative
	nudge FROM wherever the solver already put it, same as a scale nudge is a
	decorative resize from wherever the solver already sized it. ]]
function schema.checkPresentationOffset(v: any): (boolean, string?)
	if type(v) ~= "table" then
		return false, "a table { x = <number>, y = <number> } — a paint-only nudge, not a layout position"
	end
	local t = v :: any
	if type(t.x) ~= "number" or t.x ~= t.x or type(t.y) ~= "number" or t.y ~= t.y then
		return false, "{ x = <number>, y = <number> }, both finite"
	end
	return true
end

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
	-- ONE SLOT OF A FIXED-PITCH WINDOWING LIST (`virtualSlot`). Validated
	-- field-by-field rather than accepted as any table, because the whole point of
	-- the guard it feeds is to be trusted: a garbled `extent` here would either
	-- shout at every honest row or silence a real one.
	virtualSlot = function(v)
		if type(v) ~= "table" then
			return false, 'a slot table such as { list = "Racers", extent = 56 }'
		end
		local s = v :: any
		if type(s.list) ~= "string" or s.list == "" then
			return false, "`list` must be the naming the finding will quote (a non-empty string)"
		end
		if type(s.extent) ~= "number" or s.extent ~= s.extent or s.extent <= 0 then
			return false, "`extent` must be the DECLARED item extent in px (a positive number)"
		end
		if s.axis ~= nil and s.axis ~= "y" and s.axis ~= "x" then
			return false, '`axis` must be "y" (default) or "x"'
		end
		if s.contentFrom ~= nil and (type(s.contentFrom) ~= "number" or s.contentFrom < 1) then
			return false, "`contentFrom` must be the 1-based index of the first content child"
		end
		return true
	end,
	--[[ A REGION'S EXPAND (wave REVEAL). The AUTHOR writes one of three things —
		"auto", "none", or a handler function — and `UI.Region` resolves that, once,
		into the record below before this validator ever sees it: the mode, the
		DECLARED form count (which is not `#children` once the affordances are in the
		tree) and one interactivity boolean per form. Both spellings are accepted
		because the resolution is idempotent and a test may drive either. ]]
	--[[ THE AFFORDANCE THE FRAMEWORK SYNTHESIZED (wave REVEAL), declared on the one
		Button `UI.Region` appends to a collapsing region. It is public for the reason
		`virtualSlot` is: the framework declares it, an author never does, and a prop
		nothing can see is a prop nothing can audit. `role` is decided at CONSTRUCTION
		from the forms' own contents — "cover" when no form below the richest carries
		a control (the whole compact form is the target), "chevron" when any of them
		does (the form keeps its meanings and the mark sits beside it). ]]
	expandTarget = function(v)
		if type(v) ~= "table" then
			return false, 'a target such as { role = "cover" }'
		end
		local r = v :: any
		if r.role ~= "cover" and r.role ~= "chevron" and r.role ~= "close" then
			return false, '`role` must be "cover", "chevron" or "close"'
		end
		return true
	end,
	expandSpec = function(v)
		if type(v) == "function" then
			return true
		end
		if type(v) == "string" then
			if v == "auto" or v == "none" then
				return true
			end
			return false, 'a mode: "auto" (the framework discloses the richest form) or "none"'
		end
		if type(v) ~= "table" then
			return false, '"auto", "none", a handler function, or the resolved record'
		end
		local r = v :: any
		if r.mode ~= "auto" and r.mode ~= "none" and r.mode ~= "custom" then
			return false, '`mode` must be "auto", "none" or "custom"'
		end
		if type(r.forms) ~= "number" or r.forms < 1 then
			return false, "`forms` must be the DECLARED form count"
		end
		if type(r.interactive) ~= "table" then
			return false, "`interactive` must be one boolean per form"
		end
		if r.role ~= nil and r.role ~= "cover" and r.role ~= "chevron" then
			return false, '`role` must be "cover" or "chevron"'
		end
		return true
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
				`dimension type must be one of fixed|content|hug|fill|percent|minMax|aspect|containerRelative (got {tostring(
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
		--[[ CONTENT-TERMS SIZING (framework-gaps-phase2 gap 3): `{ type = "content",
			lines = n, role? }` or `{ type = "content", rows = n, of = metric }` — a
			box declaring its extent as N lines of a typography role or N rows of a
			named theme metric, rather than a literal px or a measured child.
			Refused LOUD at construction, the same "an enum prop that accepts any
			string and silently does nothing" lesson every other closed vocabulary in
			this file follows (see the file header): `lines` and `rows` name two
			DIFFERENT units (a text line height vs. an arbitrary metric), so declaring
			both is not "extra generosity", it is an unanswerable question — which
			unit wins? — and every other field here only makes sense attached to the
			shape that uses it. ]]
		local dv = v :: any
		local hasLines = dv.lines ~= nil
		local hasRows = dv.rows ~= nil
		if dv.type ~= "content" then
			if hasLines or hasRows or dv.of ~= nil or dv.role ~= nil then
				return false, '`lines`/`rows`/`of`/`role` only apply to a content-terms dimension (`type = "content"`)'
			end
		elseif hasLines and hasRows then
			return false,
				'a content dimension takes `lines` OR `rows`, never both — "N lines of a text role" and '
					.. '"N rows of a named metric" are two different units'
		elseif hasLines then
			if type(dv.lines) ~= "number" or dv.lines ~= dv.lines or dv.lines < 1 or dv.lines == math.huge then
				return false, `lines must be a finite count >= 1 (got {tostring(dv.lines)})`
			end
			if dv.of ~= nil then
				return false, "`of` only applies to `rows`, not `lines`"
			end
			if dv.role ~= nil then
				if type(dv.role) ~= "string" or not TYPE_ROLE_SET[dv.role] then
					return false, `role must be one of {TYPE_ROLE_LIST} (got {tostring(dv.role)})`
				end
			end
		elseif hasRows then
			if type(dv.rows) ~= "number" or dv.rows ~= dv.rows or dv.rows < 1 or dv.rows == math.huge then
				return false, `rows must be a finite count >= 1 (got {tostring(dv.rows)})`
			end
			if dv.of == nil then
				return false,
					"`rows` requires `of` — the metric name, literal px, or additive list naming one row's height"
			end
			if dv.role ~= nil then
				return false, "`role` only applies to `lines`, not `rows`"
			end
		else
			if dv.of ~= nil then
				return false, "`of` requires `rows`"
			end
			if dv.role ~= nil then
				return false, "`role` requires `lines`"
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
			local modifier = if type(k) == "string" then COMPACT_MODIFIERS[k] else nil
			if modifier ~= nil then
				if typeof(raw) ~= modifier then
					return false, `{k} must be a {modifier} (got {typeof(raw)})`
				end
				continue
			end
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
	-- A FRACTION OF THE PARENT (ADR-0022 Decision 6): an anchor offset
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
	opacity = schema.checkOpacity,
	scaleFactor = schema.checkScaleFactor,
	degrees = schema.checkDegrees,
	presentationOffset = schema.checkPresentationOffset,
	metric = metricName,
	typeRole = function(v)
		if themeSnapshot.isTypeRole(v) then
			return true
		end
		return false, `a typography role ({TYPE_ROLE_LIST}) or an explicit px number`
	end,
	--[[ `textSize = "fit"` and its option form (audit §10). The grammar itself is
		`layout/text_fit.checkFitProp` — the SAME reading the measure seam and the
		paint seam use — so a spelling this check accepts is a spelling those two
		can resolve, which is the whole reason it is not re-stated here. ]]
	textFit = function(v)
		local ok, why = textFitLib.checkFitProp(v)
		if ok then
			return true
		end
		--[[ IT ONLY CLAIMS THE ERROR SENTENCE FOR A VALUE SHAPED LIKE A FIT SPEC.
			`checkValue` keeps the FIRST failing type's detail, so a check that always
			spoke would drown the better sentence for a mistyped role name or a bad
			number — while a TABLE can only ever have been meant as this, and its own
			reason ("fit takes only cap and floor") is the one worth printing. ]]
		if type(v) == "table" then
			return false, why
		end
		return false
	end,
}

-- check a STATIC value against a prop spec. Returns (ok, detail?).
function schema.checkValue(spec: PropSpec, value: any): (boolean, string?)
	local detail: string? = nil
	for _, t in spec.types do
		local check = TYPE_CHECKS[t]
		if check == nil then
			error(`Facet schema: unknown logical type '{t}'`, 0)
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
	-- PER-CHILD CROSS-AXIS ALIGNMENT INSIDE A STACK'S LINE (parity round 2 §2.1) —
	-- Roblox's `ItemLineAlignment`, and the fix for a word that meant two things.
	--
	-- The solver read `child.align` for this, but `align` is a CONTAINER-only prop:
	-- it is refused on `UI.Text`/`Box`/`Spacer`/`Image`, so the only child that
	-- could align itself in its parent's line was one that was itself a stack — and
	-- there the one word did two jobs at once (a nested `VStack{ align = "center" }`
	-- centres its own children AND centres itself in the row). `lineAlign` is the
	-- second job under its own name, legal on every box, and it OUTRANKS both
	-- `child.align` and the container's `align`.
	--
	-- Same four values as `align`, `stretch` included: a child that wants to fill
	-- the line's cross extent should not have to reach for a `fill` dim, which would
	-- also claim the main axis.
	--
	-- ONLY A STACK READS IT, and that is CAUGHT rather than left to the reader: a
	-- `lineAlign` under a ZStack, an Anchor, a Grid, a ScrollView or any of the
	-- three rank/region containers is inert, so it is one of the nine props in the
	-- solver's placement read table (`solver.auditPlacement`, §2.1) and is reported
	-- on `controller.diagnostics()` naming the working spelling for that parent.
	lineAlign = p({
		types = { "string" },
		reactive = true,
		dirty = { "arrange" },
		shared = true,
		enum = { "start", "center", "end", "stretch" },
		channel = "layout",
		doc = "this child's own cross-axis alignment inside its stack parent's line "
			.. "(start|center|end|stretch); outranks the container's `align`",
	}),
	-- THE SHRINK PASS'S TWO INPUTS (parity round 2 §2.4). BOX props rather than
	-- modifiers, and deliberately: they are placement facts a stack parent reads off
	-- its children, exactly as `anchor`, `alignH`, `alignV`, `offsetX` and `offsetY`
	-- already are — and the constitution's positional-scalar modifier family
	-- (`UI.offset`, `UI.aspectRatio`, `UI.alignment`) is declared CLOSED (§16 E-18).
	--
	-- Reactive with `dirty = { "measure" }`: either value can change the arrangement,
	-- and the pass re-measures the children it squeezes.
	--
	-- AND ONLY A STACK READS EITHER ONE, which is now CAUGHT and not merely stated
	-- (Milestone-1 review C2). Both shipped in this same paragraph as the five
	-- audited props above and neither was added to the solver's placement read
	-- table, so a `shrinkWeight` under a ZStack, a Grid, an Anchor or a ScrollView
	-- was accepted and did nothing — the §4 violation the audit exists to remove,
	-- committed by the change that built the audit. They are both in the table now
	-- (`solver.auditPlacement`), reported on `controller.diagnostics()` with the
	-- reason and the way out, exactly like `lineAlign` and `gridSpan`.
	layoutPriority = p({
		types = { "number" },
		reactive = true,
		dirty = { "measure" },
		shared = true,
		channel = "layout",
		doc = "shrink-order tier when a stack's main axis is short (default 0): the deficit is consumed "
			.. "tier by tier, LOWEST priority first, so a higher number is protected for longer",
	}),
	shrinkWeight = p({
		types = { "number" },
		reactive = true,
		dirty = { "measure" },
		shared = true,
		channel = "layout",
		doc = "how readily this child gives up main-axis pixels within its `layoutPriority` tier "
			.. "(default 0 = never, matching Roblox's `UIFlexMode.None`). Inside a tier the deficit "
			.. "is split proportionally to weight x this child's natural size, down to its floor "
			.. "(`minMax.min`, else a text node's longest word, else 0)",
	}),
	-- THE ROW-GRID SPAN (parity round 2 §2.2). A BOX prop for the same reason
	-- `layoutPriority` is one: it is a placement fact a container parent — here a
	-- `UI.GridRow` — reads off its children, not a size this node has of its own.
	--
	-- A spanning cell contributes to NO single column's maximum (a
	-- span cannot widen one column on its own) and is fitted to the sum of the
	-- columns it covers plus the gaps between them.
	--
	-- OUTSIDE A `UI.GridRow` IT IS READ BY NOTHING — and that sentence used to end
	-- this paragraph as though it were part of the feature. It is not: constitution
	-- §4 says a property that is *accepted* must *do something*, so "accepted here
	-- and silently ignored" is a defect written down, not a contract. It is now
	-- CAUGHT rather than merely documented: `gridSpan` is one of the nine props in
	-- the solver's placement read table (`solver.auditPlacement`, parity round 2
	-- §2.1), so a `gridSpan` under any parent but a row is reported on
	-- `controller.diagnostics()` naming the node, the reason and the way out. The
	-- schema closes the converse cell outright — a `UI.GridRow`'s own prop set is
	-- paint-only, so no placement prop can even be authored ON a row.
	gridSpan = p({
		types = { "number" },
		reactive = true,
		dirty = { "measure" },
		shared = true,
		channel = "layout",
		doc = "how many of its row's columns this cell covers inside a `UI.GridRow` (default 1). A "
			.. "spanning cell never widens a single column on its own; it is fitted to the columns it "
			.. "covers plus the gaps between them",
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
	-- the AUTHORED STROKE (ADR-0022 Decision 6). Same shape, same
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
	-- NOT reactive, exactly like `shape` and `compactLabel`: a lift is what
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
	-- THE SPACE-RESERVING HIDE. The
	-- node keeps its solved box and stops being painted, focusable and tappable.
	-- Neither of the two things Facet already had is this: `UI.When` REMOVES the
	-- node so its siblings close up, and the engine's own `Visible = false` is
	-- documented to free the layout slot — but only inside a `UIListLayout` /
	-- `UIGridLayout` / `UITableLayout`, and this framework arranges absolutely and
	-- materializes none of those, which is exactly why one prop is enough here.
	--
	-- `arrange`, not `paint`: the solver already publishes a per-rect `hidden`
	-- verdict for a losing `ViewThatFits` candidate, and the renderer merges this
	-- prop into that SAME set. One hidden verdict, one visibility walk, one hit-rect
	-- walk, one `hiddenRoots` the focus map already filters on — a second, paint-only
	-- channel would have been a parallel mechanism that focus and hit geometry did
	-- not follow, which is precisely the defect the rich-skinning v2 decision set records.
	--
	-- Reactive, where the usual spelling is unconditional ("hides this view
	-- unconditionally"; its answer for the conditional case is an `if`, which
	-- removes the node from layout). Facet's `if` is `UI.When` and it removes the
	-- node too — so without a bindable form the space-reserving case would have no
	-- spelling at all.
	hidden = p({
		types = { "boolean" },
		reactive = true,
		dirty = { "arrange" },
		shared = true,
		channel = "layout",
		doc = "true keeps this node's layout box and stops painting it — and it leaves focus order and stops "
			.. "taking taps, with its whole subtree. Use UI.When instead when the space should close up",
	}),
	--[[ THE AUTHORED PRESENTATION PAIR (ADR-0026; the `scaleEffect` /
		`rotationEffect`). These are the FIRST authored props in the presentation
		channel, and the channel name is the whole design: the renderer folds the
		value into the presentation authority's own write. There is no
		`adapter.setProp(handle, "scale", …)` and there never will be — a second
		writer for `UIScale.Scale` or `GuiObject.Rotation` is exactly what the
		authority manifest exists to prevent.

		COMPOSITION (ADR-0026 Decision 2): a scale MULTIPLIES with whatever the
		framework is scaling this node by (a press dip, a motion pop), a rotation
		ADDS to whatever it is rotating it by. Each composes in its own group, which
		is what makes nesting mean what it says.

		NEITHER MOVES LAYOUT, hit geometry or focus — the solver never sees them and
		Facet hit-tests solved rects, which is the common rule for both:
		`rotationEffect` "has no effect on the view's frame", and `scaleEffect`'s
		dimensions "are considered to be unchanged by scaling the contents". To
		change a box, change its `width`/`height`.

		Reactive, and animatable through `presenter.withAnimation` — which is the
		point (director ruling, 2026-08-14). `paint` dirty: no measure, no arrange. ]]
	scale = p({
		types = { "scaleFactor" },
		reactive = true,
		dirty = { "paint" },
		shared = true,
		channel = "presentation",
		doc = "paint-only uniform scale about the node's centre (1 = unscaled). It changes nothing the "
			.. "solver sees — the box, the hit target and the focus order are all the unscaled ones — and "
			.. "it MULTIPLIES with any scale the framework is applying (a press dip, a motion pop)",
	}),
	rotation = p({
		types = { "degrees" },
		reactive = true,
		dirty = { "paint" },
		shared = true,
		channel = "presentation",
		doc = "paint-only rotation in DEGREES about the node's centre (0 = upright, positive = clockwise). "
			.. "It changes nothing the solver sees — the hit target stays the unrotated box — and it ADDS "
			.. "to any rotation the framework is applying",
	}),
	--[[ THE THIRD MEMBER OF THE AUTHORED PRESENTATION FAMILY (ADR-0026
		amendment, gap 16 framework-gaps-phase2): a paint-only TRANSLATION,
		exactly parallel to `scale`/`rotation` above — same boundary (the solver
		never sees it), same reason it exists (an author-declared perturbation
		composed with whatever the framework is doing to the same node), same
		gate. `x`/`y` in the CHANNEL (the framework's own `setPresentationTransform`/
		`withAnimation` writes) stay the solver's business per that channel's own
		rule; this is the AUTHORED counterpart `scale`/`rotation` already have and
		`offset` did not — before it, a decorative nudge (a bounce, a shake) had
		no declarative spelling and had to go through the imperative channel
		every frame, including every resting frame it wrote nothing over (DELETE#5,
		`p2_cartwheel/screens/celebration.luau`).

		Composes ADDITIVELY, the same rule `rotation` uses (never MULTIPLY — an
		offset has no "unscaled" identity beyond zero). ]]
	offset = p({
		types = { "presentationOffset" },
		reactive = true,
		dirty = { "paint" },
		shared = true,
		channel = "presentation",
		doc = "paint-only translation in px from the node's SOLVED position ({x=,y=}; 0,0 = unmoved). It "
			.. "changes nothing the solver sees — the box, the hit target and the focus order stay at the "
			.. "solved position; to change WHERE a node is, change its layout (margin, Anchor offsets, "
			.. "position in the tree) — and it ADDS to any offset the framework is applying (a slide "
			.. "transition, a keyboard shift)",
	}),
	-- VIEW LIFETIME (the `onAppear`/`onDisappear` pair).
	-- Mount scopes have owned this lifetime since the framework's first phase; what
	-- was missing was the author-facing hook, so "fire analytics when the screen
	-- opens" and "stop the engine sound when the panel closes" had no spelling.
	--
	-- The lifetime measured is the RENDER handle's, not the mounted node's, because
	-- that is the one a player can see: a virtualized row that scrolls out of the
	-- window disappears, and a retiring subtree playing its exit transition has not
	-- disappeared yet.
	--
	-- Not reactive, and there is nothing to make reactive: a lifetime is not a value
	-- that changes. A reactive hook would also be unrunnable — the OLD closure is the
	-- one that has to fire when the node leaves.
	onAppear = p({
		types = { "function" },
		reactive = false,
		shared = true,
		channel = "handler",
		doc = "onAppear(path) — once, the first time this node is rendered, AFTER that frame's layout solve "
			.. "(so the callback can read its own rect) and before anything reaches the screen",
	}),
	onDisappear = p({
		types = { "function" },
		reactive = false,
		shared = true,
		channel = "handler",
		doc = "onDisappear(path) — once, AFTER this node's render handle is released, so the path is already "
			.. "unmounted. Also fires for everything still mounted when the surface is torn down",
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

-- CROSS-AXIS ALIGNMENT OF THIS CONTAINER'S OWN CHILDREN. That is the whole job:
-- the second one this word used to do — "align ME inside my parent's line", which
-- a nested stack's `align` also meant — now belongs to the shared `lineAlign` box
-- prop above, where a leaf can reach it too. `child.align` is still honoured for
-- compatibility and still loses to `child.lineAlign` (solver, stack arrange).
local ALIGN: PropSpec = p({
	types = { "string" },
	reactive = true,
	dirty = { "measure" },
	shared = true,
	enum = { "start", "center", "end", "stretch" },
	channel = "layout",
	doc = "cross-axis alignment of THIS container's children (start|center|end|stretch); "
		.. "for one child's own alignment in its parent's line, see `lineAlign`",
})

-- MAIN-AXIS DISTRIBUTION OF THE LEFTOVER (parity round 2 §2.6) — Roblox's
-- `UIFlexAlignment` plus whole-group centring, on the CONTAINER.
--
-- Facet could already reproduce SpaceBetween/Around/Evenly pixel-exactly with
-- hand-placed `Spacer`s between children, but only for a STATIC child list:
-- `children` is a static array, a variable-count list goes through `UI.ForEach`,
-- and `ForEach`'s `row` returns exactly ONE blueprint — so separators cannot be
-- interleaved on the parent's main axis at all. A tab bar whose tab count varies —
-- the native documentation's own motivating example — was inexpressible.
--
-- `dirty = { "arrange" }` and not `measure`: it moves the cursor and changes no
-- child's size, which is the same reason `offsetX`/`offsetY` are arrange-only.
local DISTRIBUTE: PropSpec = p({
	types = { "string" },
	reactive = true,
	dirty = { "arrange" },
	enum = { "start", "center", "end", "spaceBetween", "spaceAround", "spaceEvenly" },
	channel = "layout",
	doc = "how the leftover main-axis space is spread (default `start`): "
		.. "start | center | end | spaceBetween | spaceAround | spaceEvenly. It acts on what `fill` "
		.. "children did not take, so a `fill` child leaves it nothing — and says so in the diagnostics",
})

-- FLOW-WRAP (docs/plans/parity-round3.md item A) — Roblox's
-- `UIListLayout.Wraps`, which Facet had no spelling for at all.
--
-- A PROP, NOT A CLASS, and the ladder decides it. Constitution §1 asks whether a
-- thing "needs its own layout/paint/input semantics an existing class cannot
-- compose"; a wrapping stack has the same children, the same paint (none), the
-- same input (none), the same `gap`, the same `align`, the same `lineAlign` and
-- the same `distribute` as the stack it is a mode of. What changes is ONE fact:
-- whether the main axis is allowed a second line. `AdaptiveStack` is the precedent
-- — one class with a reactive axis — and it exists precisely because swapping
-- CLASSES through a `When` remounts every child and loses their state. A separate
-- `UI.FlowStack` would have re-declared BOX + CONTAINER_LAYOUT + gap + align +
-- distribute to say one boolean, and made "wrap this row on a phone" a remount.
--
-- REACTIVE, therefore, and `dirty = { "measure" }`: it changes where the lines
-- break, which is a measure fact, and a bound flip is a re-solve in place.
--
-- IT IS NOT ON `Screen`, `AdaptiveStack` or any other container, deliberately. A
-- prop only two arrange branches read is a prop every other class must refuse
-- (§4), and the schema is what refuses it.
local WRAP: PropSpec = p({
	types = { "boolean" },
	reactive = true,
	dirty = { "measure" },
	channel = "layout",
	doc = "wrap the children onto more than one line when they do not fit the main axis "
		.. "(Roblox `UIListLayout.Wraps`). The block of lines is placed by `align`, an item inside "
		.. "its line by `lineAlign`, and each line's leftover by `distribute` — no new words. "
		.. '`align = "stretch"` is refused here: it would mean two things at once',
})

-- Horizontal alignment of a node's OWN text inside its own box. Until now the
-- adapter hard-coded TextXAlignment.Left, so there was no way to centre text
-- anywhere in Facet at all — which is why a Stepper's value readout could not
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
	types = { "textFit", "number", "typeRole", "metric" },
	reactive = true,
	dirty = { "paint", "measure" },
	shared = true,
	channel = "layout",
	doc = "text size: an explicit px number, a typography role name "
		.. `({TYPE_ROLE_LIST}) resolved from the active `
		.. 'theme, or `"fit"` — the largest size that fits the box this node lands in, chosen by the '
		.. "solver (option form: `{ fit = { cap = <role or px>, floor = <role or px> } }`; an absent cap is the "
		.. "class's own role and an absent floor is the theme's `caption`). A role also supplies the FONT DESCRIPTOR and "
		.. "line height, so `strong` and "
		.. "`numeral` are how a node asks for weight — both seams read the one role. "
		.. "A px or role size is scaled at BOTH the measure and paint seams; a `fit` size is already "
		.. "the painted one",
})

-- LINE LIMIT. "This label gets at most N
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

-- FULL-VALUE DISCLOSURE (large-text accessibility, 2026-08-03). The plan's
-- overflow ladder permits truncation only for bounded SECONDARY or IDENTITY text,
-- and only when the full string stays reachable. `disclose` is the declaration of
-- that permission-plus-debt: this label may ellipsize, and when it does the
-- framework owes the reader the whole value.
--
-- ONE boolean rather than a mode enum, because the author's knowledge is binary
-- (is the full string worth reading?) and every other term — which input class
-- engages it, where the plate lands, what it is themed as — is the presenter's,
-- not the screen's (constitution: screens declare, never implement). It is legal
-- on any Text and does NOTHING while the text is not truncated, so declaring it
-- is free and forgetting it is what the audit reports.
--
-- CONSTRUCTION-ONLY, exactly like `traversalPriority`: "may this be revealed" is
-- what the node IS, not a question about state, and the presenter reads it off
-- the mounted node. Binding a Readable here is an immediate refusal naming the
-- rebuild idiom (§4), never a silently ignored value. No `dirty` classes for the
-- same reason the parity checker enforces in both directions: a dirty class is
-- what a REACTIVE prop needs, and this one cannot change without a rebuild.
local DISCLOSE: PropSpec = p({
	types = { "boolean" },
	reactive = false,
	-- Text-only, like `lineLimit` beside it: documented in Text's own entry
	channel = "semantic",
	doc = "declare this bounded secondary/identity label as revealable: when it truncates, engaging it "
		.. "(hover dwell, focus, long-press) presents the full string. Inert while the text fits",
})

-- THE AUTO REVEAL (director ruling 2026-08-04, superseding large-text accessibility's "no marquee"
-- for surfaces that DECLARE it; the plan's overflow rung 4, its full constraint
-- list binding). `reveal = "auto"` says: this bounded one-line text, when it
-- truncates, auto-scrolls its whole value — the presenter slides the full string
-- through the box after a quiet delay, pausing at the ends, and rests in the
-- engine's own ellipsis between cycles. It is ALSO a disclosure source (the
-- large-text accessibility plate is its static full-value alternative), reduced motion disables the
-- travel entirely, and at most one strip runs per presentation
-- (`text_audit.movingText`).
--
-- AN ENUM WITH ONE VALUE, not a boolean: "auto" names the UNENGAGED variant the
-- ruling ordered (the surface presenting IS the engagement — the recap line is a
-- non-interactive span nothing can focus or hover deliberately). An ENGAGED
-- variant remains a possible future value; a boolean would have to be re-typed
-- to admit it.
--
-- CONSTRUCTION-ONLY, exactly as `disclose` beside it: "may this travel" is what
-- the node IS, and the presenter reads it off the mounted node.
local REVEAL: PropSpec = p({
	types = { "string" },
	enum = { "auto" },
	reactive = false,
	channel = "semantic",
	doc = "declare this bounded one-line label as an auto-scrolling reveal: when it truncates, the "
		.. "presenter slides the whole value through the box (quiet delay, pause at ends, rests as the "
		.. "ellipsis; reduced motion disables travel; the static disclosure plate stays its alternative)",
})

--[[ HELP: one sentence about what a view DOES, pulled by the player.
	One sentence about what this view does, PULLED BY THE PLAYER: the pointer
	hovers it for a moment, or the keyboard/gamepad ring lands on it. The scope
	is deliberately narrow: help sets a view's accessibility hint and its help
	tag (also called a tooltip), and a tooltip appears WHEN A POINTER HOVERS.

	ON TOUCH IT SHOWS NOTHING, AND THAT IS THE SPECIFICATION rather than a gap.
	No input class binds a gesture to help, and Facet must not either: D2
	measured the long-press collision and left that gesture with the full-value
	disclosure plate, which is the only touch route to a truncated label's value.
	Two constructs fighting for one gesture on the one class where neither has an
	alternative is the defect this restraint avoids. The consequence is a rule,
	not a footnote: `help` is NEVER the only route to information a player needs,
	and `text_audit.helpRoutes` is the check that says so out loud.

	THE APP-PUSHED PLATE IS A DIFFERENT CONSTRUCT. A coach mark that pops ITSELF,
	from eligibility rules, appears on every input class and retires permanently is
	`Facet.newCallout` (the coach-mark construct), not this. Both plates point with
	D1's arrow tail — the stem says which control the words are about, and was
	never what told the two apart.

	CONSTRUCTION-ONLY, exactly as `disclose` and `reveal` are: what a control is
	FOR does not change without a rebuild, and the presenter reads it off the
	mounted node. Binding a Readable here is an immediate refusal naming the
	rebuild idiom (§4), never a silently ignored value. ]]
local HELP: PropSpec = p({
	types = { "string" },
	reactive = false,
	-- deliberately NOT `shared`, exactly as `disclose` is not: it lives on the
	-- four classes a player engages, so it is documented in each of their own
	-- api.md entries rather than in the shared box block every class inherits
	channel = "semantic",
	doc = "one sentence about what this view does, shown when a POINTER hovers it (after a dwell) or the "
		.. "keyboard/gamepad ring lands on it. Nothing appears on touch — no input class binds a gesture "
		.. "to help, so it must never be the only route to something a player needs "
		.. "(`text_audit.helpRoutes`). The plate points at this view with an arrow tail. For an "
		.. "app-PUSHED coach mark that appears on every input class, see `newCallout`",
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

--[[ AUTHORED OPACITY (ADR-0026), and it lives on exactly
	the two classes `canvasGroup` does — because DECLARING IT IS DECLARING ONE.

	A fade in this framework is a `CanvasGroup.GroupTransparency` fact and always
	was (ADR-0022 Decision 2): it is the one alpha property no style rule owns.
	The alternative — writing `BackgroundTransparency` / `TextTransparency` on a
	leaf — is in `NATIVE_SHEET_OWNED`, and an explicit write there does not win a
	frame, it PERMANENTLY defeats the rule with no signal (spike 2026-07-19). The
	concrete price is not hypothetical: `TextTransparency`'s rule is the disabled
	state's, so a `UI.Text` that took an opacity would stop dimming when disabled,
	forever. So a leaf is refused and the spelling is one wrap:
	`UI.ZStack { opacity = 0.4, children = { … } }` — which is also the common
	answer, and the reason `compositingGroup()` exists there.

	It IMPLIES the group, so an author never writes `canvasGroup = true` beside
	it; the renderer passes the implied flag at creation exactly as the explicit
	prop does. Unlike `canvasGroup` it IS reactive — a constant fade would be a
	theme decision, and the whole point is that it moves and animates.

	COMPOSITION (ADR-0026 Decision 2): applying opacity
	to something already faded "multiplies the effect of the underlying opacity
	transformation". So an authored 0.5 under a framework fade at 0.5 paints 0.25,
	and a framework fade to nothing still reaches nothing. ]]
local OPACITY: PropSpec = p({
	types = { "opacity" },
	reactive = true,
	dirty = { "paint" },
	channel = "presentation",
	doc = "fade this node and its whole subtree: 1 = opaque (the default), 0 = invisible but still "
		.. "laid out, focusable and tappable (use `hidden` to take it out of all three). Declaring it "
		.. "makes the node a fade group, so it costs a render buffer; it MULTIPLIES with any fade the "
		.. "framework is running on the same node, and animates through presenter.withAnimation",
})

-- THE STRUCTURAL-TRANSITION DECLARATION (ADR-0022 Decision 3). A
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

-- THE CONTINUOUS-COLOUR CHANNEL (ADR-0022 Decision 6). Offered
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

-- LINEAR TRAVERSAL POSITION (Tab / Shift+Tab), as a sort TIER rather than an
-- absolute index: the key is `(traversalPriority, document position)` and the
-- default is 0, so within a tier document order always wins and an author who
-- sets nothing gets the order the screen reads in. Negative pulls a control
-- toward the front, positive pushes it toward the back — the `tabindex` model,
-- because that is the one every author already carries.
--
-- It does NOT touch the arrows: `navigateDirection` never reads the rank. The
-- two verbs walk the same SET (constitution §9) and only the reading order
-- differs.
--
-- CONSTRUCTION-ONLY, deliberately, while `focusable` beside it is reactive
-- A traversal position answers what the node IS, not a question about
-- state, and no shipped control needs to move one at runtime. Binding a Readable
-- here is an immediate refusal naming the rebuild idiom (§4), never a silently
-- ignored value. Widening to reactive later is compatible; narrowing would not be.
-- No `dirty` classes, unlike `focusable` beside it: a dirty class is what a
-- REACTIVE prop needs so a live change re-runs the affected work, and this one
-- cannot change without a rebuild. The repository's prop-parity check enforces
-- that pairing in both directions.
local TRAVERSAL_PRIORITY: PropSpec = p({
	types = { "number" },
	reactive = false,
	shared = true,
	channel = "semantic",
	doc = "linear-traversal sort tier (default 0); sorts by (priority, document position) — "
		.. "negative traverses earlier, positive later. Tab/Shift+Tab only; the arrows are unaffected",
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
	props = merge(BOX, CONTAINER_LAYOUT, { gap = GAP, align = ALIGN, distribute = DISTRIBUTE }),
})

class("VStack", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, { gap = GAP, align = ALIGN, distribute = DISTRIBUTE, wrap = WRAP }),
})

class("HStack", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, { gap = GAP, align = ALIGN, distribute = DISTRIBUTE, wrap = WRAP }),
})

class("ZStack", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, {
		canvasGroup = CANVAS_GROUP,
		opacity = OPACITY,
		--[[ "THIS CONTAINER IS ONE SLOT OF A FIXED-PITCH WINDOWED LIST" (2026-08-13).
			Declared by `newVirtualList` on every row it builds, and available to any
			hand-rolled surface that windows by `index x extent` — which is the only
			shape the promise holds for. It changes NO geometry: the solver reads it to
			check the slot's content against the extent that was declared for it, and
			says so naming both numbers when the content is taller (the defect class in
			`docs/lessons/facet-fixed-px-heights.md`). Content SHORTER than its slot is
			legitimate over-reservation and stays silent, and a cell that scrolls or
			clips its own overflow is skipped. ]]
		virtualSlot = p({
			types = { "virtualSlot" },
			reactive = true,
			dirty = { "measure" },
			-- ZStack's alone (like `canvasGroup`), so it is documented in the class's
			-- own api.md entry rather than the shared box/container table
			channel = "layout",
			doc = "declare this container one slot of a fixed-pitch windowed list: "
				.. "{ list, extent, axis?, contentFrom? }. The solver checks the slot's content "
				.. "against `extent` and names both numbers when the content is taller",
		}),
	}),
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
		indicators = p({
			-- CAROUSEL INDICATOR OPT-OUT (director ruling 2026-08-09): a peeking
			-- carousel's affordance IS the half-visible next tile, and the
			-- reference apps draw no bar on theirs — so a scroller may declare
			-- its indicators off. "auto" (default) follows the session's
			-- scrollIndicatorPolicy; "none" suppresses this host's indicator
			-- entirely. LAYOUT is untouched either way: the reserve is a
			-- session-policy fact, not a per-host one, so a "none" host in an
			-- "always" session simply leaves its reserved lane empty.
			types = { "string" },
			reactive = false,
			enum = { "auto", "none" },
			channel = "layout",
			doc = 'scroll indicators: "auto" (default, session policy) or "none" (carousels whose affordance is the peeking tile)',
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
			-- opts out; a table tunes the band/dwell/ramp (see `Facet.newAutoscroll`).
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
		flow = p({
			-- COLUMN-MAJOR WRAPPING (2026-08-15), and it is a MODE of the one flow
			-- arithmetic rather than a second one: the solver's flow grid is written
			-- in LANE/FLOW terms and binds those words to width/height in exactly two
			-- places, so a column-flow grid is the exact transpose of the row-flow
			-- grid it mirrors (`tests/grid_column_flow.spec.luau`). CSS spells the
			-- same choice `grid-auto-flow: row | column`.
			--
			-- `columns` and `minColumnWidth` keep their names in both modes because
			-- the grid has ONE lane count and ONE lane minimum, not two — under
			-- `flow = "column"` they are read against the HEIGHT. Two symmetric
			-- spellings would double this prop set to describe the same number, and
			-- `minColumnWidth`'s twin has no honest name.
			types = { "string" },
			enum = { "row", "column" },
			reactive = true,
			dirty = { "measure" },
			channel = "layout",
			doc = "row (default: cells wrap across the width, lines advance down) | column (cells wrap down the "
				.. "height, lines advance rightward — the mode a horizontal lazy grid's band is built from)",
		}),
		columns = p({
			types = { "number" },
			reactive = true,
			dirty = { "measure" },
			channel = "layout",
			doc = 'fixed LANE count — columns across under `flow = "row"`, rows down under `flow = "column"` '
				.. "(mutually exclusive with minColumnWidth)",
		}),
		minColumnWidth = p({
			-- "intrinsic" (director round 9): the widest CHILD's own measured
			-- width under the active theme's font, recomputed every solve, so a
			-- grid of labels re-columns itself on a theme swap instead of being
			-- sized by a device-pixel guess that only suits one font.
			--
			-- ...AND IT IS THE DEFAULT (2026-08-21). Declaring neither
			-- this nor `columns` used to mean ONE LANE at every width from a 390px
			-- phone to a 1920px television. It now means this, which is the only
			-- honest default available: a px minimum would be a guess about a font
			-- and a lane count would be a guess about the box. See
			-- `src/layout/grid.luau`'s `gridLaneMin`.
			types = { "number", "string" },
			enum = { "intrinsic" },
			reactive = true,
			dirty = { "measure" },
			channel = "layout",
			doc = 'derive the column count from this minimum cell width (px, or "intrinsic" for the widest child '
				.. "— the DEFAULT when neither this nor `columns` is declared)",
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

-- A ROW OF A ROW GRID (parity round 2 §2.2). A primitive, not a control: the
-- solver understands `gridrow` natively, exactly as it understands `grid`.
--
-- ITS PROP SET IS DELIBERATELY TINY, and the omissions are the design. A `width`
-- or `height` on a row would be a second authority against the grid that owns the
-- column widths and the row pitch, and `padding` would inset one row's cells out of
-- the columns every other row is aligned to — the whole point of a row grid is that
-- column n is the same column in every row. Rather than accept those and ignore
-- them (the failure mode this schema exists to remove), they are not accepted: a
-- `width` on a `UI.GridRow` is a construction error naming the fix.
--
-- What IS here is the set that is meaningful on a full-width band: its identity,
-- its children, and the paint a striped or carded row wants.
class("GridRow", {
	container = true,
	structural = false,
	props = merge({
		shadow = BOX.shadow,
		gradient = BOX.gradient,
		corners = BOX.corners,
		stroke = BOX.stroke,
		zIndex = BOX.zIndex,
		surface = CONTAINER_LAYOUT.surface,
	}),
})

class("AdaptiveStack", {
	container = true,
	structural = false,
	props = merge(BOX, CONTAINER_LAYOUT, {
		gap = GAP,
		align = ALIGN,
		distribute = DISTRIBUTE,
		-- The whole point of this class: ONE class with a REACTIVE axis. Swapping
		-- UI.VStack for UI.HStack through a `When` would remount every child and
		-- lose their state on a viewport flip; a bound axis re-solves in place
		-- (acceptance row A-AL2). Bind it to `adaptive.conditions(...).axis`.
		--
		-- ...AND IT IS REQUIRED (audit Part 2 cell A-2, 2026-08-21). It
		-- used to default to `"y"`, which made `UI.AdaptiveStack{}` a PERMANENT
		-- VSTACK at every combo — measured a column at all six, 1920px television
		-- included — and three shipped fixtures declared it exactly that way under
		-- a comment saying "side by side where there is room, a column where there
		-- is not". A class named for adapting must not be able to silently not
		-- adapt, and a default of `"y"` on THIS class buys nothing an author could
		-- not already buy with `UI.VStack`. So it takes `tab_view`'s treatment
		-- (`controls/tab_view.luau`, the in-repo precedent this framework has now
		-- adopted six times over): the absent fact is a construction refusal that
		-- names the fact, the host that publishes it, and the way out.
		axis = p({
			types = { "string" },
			reactive = true,
			required = true,
			dirty = { "measure" },
			enum = { "y", "x" },
			channel = "layout",
			doc = 'stack axis: "y" or "x" — REQUIRED, and reactive so a flip never remounts a child. Bind it '
				.. "to `Facet.adaptive.conditions(core, env).axis`, which a surface stood up with "
				.. "`Facet.client.host.new` supplies with no wiring; an unconditional column is `UI.VStack` "
				.. "and an unconditional row is `UI.HStack`",
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
-- The DECLARATION is not reactive, on purpose. `AdaptiveStack` binds an axis
-- because the author decides the axis; a Composition decides FOR the author from
-- the box it was given, on both axes, so a reactive prop would be a second source
-- of truth about a fact the solver already measures. That is the whole point of
-- the mechanism: no screen re-derives a viewport threshold, so no screen can get
-- one wrong.
--
-- `exclusions` IS REACTIVE, and it is the one prop here that answers a question
-- the solver cannot measure for itself — the same split `UI.Region.reserved`
-- makes. Every other field says what this composition IS; `exclusions` says where
-- the HOST'S OWN chrome currently sits, which is a fact about the screen outside
-- this tree that only the caller holds and that moves on a rotation, a pose
-- change or a chrome row appearing.
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
				.. "place = start|center|end|0..1, minWidth? (px or metric name), maxWidth? (px or "
				.. "metric name — the MEASURE's ceiling on a fill lane; defaults at ten-foot to "
				.. "`adaptive.LANE_MEASURE x metricScale`), gap? }",
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
		exclusions = p({
			types = { "array" },
			reactive = true,
			dirty = { "measure" },
			channel = "layout",
			doc = "rects the HOST'S own chrome occupies, in WINDOW space — the space `platformChrome.rects` "
				.. "and this solver's own output rects are stated in, so a caller never converts. A solved "
				.. "lane starts BELOW any of them that its own regions share an x range with, and a lane "
				.. "whose content clears them stays level with the chrome. The lane band stops being one "
				.. "rectangle, which is what lets a chrome row covering some columns be reserved around",
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
		--[[ D7.1. A CLOSED SPEC, REQUIRED WHERE IT MEANS SOMETHING. The rank ladder
			steps a region down and then drops it exactly as told; what it never had was
			any notion of where the content the reduced form stopped showing WENT, so
			"step down" and "delete" were one operation from the player's side. This is
			the answer, and `composition.normalize` requires it on every region with
			more than one form and refuses it on every region with one. ]]
		recover = p({
			types = { "string" },
			reactive = false,
			enum = { "none", "self", "overflow" },
			channel = "layout",
			doc = "where the content a reduced form stops showing went. REQUIRED with more than one form, "
				.. 'refused with one. "none" = every form still shows everything (state it: silence is not '
				.. 'consent) | "self" = the reduced form IS the route, so its last form must contain '
				.. 'something focusable | "overflow" = the screen\'s overflow surface is the route, and it '
				.. "reads `resolution.unshown`",
		}),
		--[[ WAVE REVEAL. `recover` says WHERE the content a reduced form stopped
			showing went; this says how the player gets it back WITHOUT leaving. Default
			"auto": the framework presents this region's RICHEST form in a transient
			plate at the region's own anchor, reached by the whole compact form when
			that form carries no controls of its own and by a chevron beside it when it
			does. "none" is the authored escape (nothing to disclose, or the author is
			disclosing it themselves) and a FUNCTION replaces the presentation entirely.

			NOT reactive, and refused on a one-form region: a region with one form never
			simplifies, so an expand on one could never fire. `rank` and `forms` stay
			the whole collapse-customization surface — if a region must not collapse,
			give it one form. ]]
		expand = p({
			types = { "expandSpec" },
			reactive = false,
			channel = "layout",
			doc = 'how a stepped-down region discloses its richest form: "auto" (default — the framework '
				.. 'presents it in a transient plate at the region\'s anchor), "none" (the authored escape), '
				.. "or a handler function that replaces the presentation. Refused on a one-form region",
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
		-- THEME-OWNED LIKE EVERY OTHER NUMBER OF ITS KIND. The default
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
		opacity = OPACITY,
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
		disclose = DISCLOSE,
		reveal = REVEAL,
		help = HELP,
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
		-- `slice` is deliberately absent: nine-slice geometry is theme-owned
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
		help = HELP,
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
		-- THE CIRCLE BUTTON (feature round 2026-07-26; the floating round
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
		-- BESIDE a title is `Facet.newLabel`, which already owns that layout.
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
				.. "With one declared, the framework never ellipsizes. Add prefer = true to wear "
				.. "the compact form ALWAYS (a default, not a degrade) — `label` stays the "
				.. "semantic name",
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
		traversalPriority = TRAVERSAL_PRIORITY,
		surface = CONTAINER_LAYOUT.surface,
		padding = CONTAINER_LAYOUT.padding,
		textSize = TEXT_SIZE,
		--[[ WAVE REVEAL. Declared by `UI.Region` on the ONE button it synthesizes for
			a collapsing region, and by nobody else — the same standing `virtualSlot`
			has. It is what lets the solver tell that button apart from the region's
			FORMS, which matters because a form behind a `UI.When` splices itself out of
			the child list and a count alone would then name the wrong node. ]]
		expandTarget = p({
			types = { "expandTarget" },
			reactive = false,
			channel = "layout",
			doc = 'framework-declared: this button is a region\'s expand chrome. { role = "cover" } '
				.. 'covers the compact form (which carries no controls of its own); { role = "chevron" } '
				.. 'sits beside it; { role = "close" } is the plate\'s own way out. Authors declare '
				.. "`UI.Region{ expand = … }`, never this. The three share one consequence — a floor "
				.. "the framework asks for on its OWN chrome grows only until it meets something "
				.. "pressable (`render/commit_walks.growWithin`)",
		}),
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
		traversalPriority = TRAVERSAL_PRIORITY,
		padding = CONTAINER_LAYOUT.padding,
		textSize = TEXT_SIZE,
		-- the Toggle's label is drawn ONE LINE with an end ellipsis by measured
		-- design (director finding 13: wrap + press-scale = mid-word breaks), so
		-- where a compact width truncates it the full value must stay reachable —
		-- the same disclosure contract a Text carries (Step 8.5 large-text accessibility)
		disclose = DISCLOSE,
		help = HELP,
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
		help = HELP,
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
		traversalPriority = TRAVERSAL_PRIORITY,
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
		traversalPriority = TRAVERSAL_PRIORITY,
		-- WHO DRAWS THE FOCUSED STATE (director playtest 2026-08-03). A focused
		-- Grip fills with accent, because a thin sliver with a hairline ring read as
		-- "focus went nowhere" in the 2026-07-20 hand test. That is right for a
		-- resize handle and wrong for a Slider, whose track is the full width of the
		-- control: filling it paints a solid bar over the value the player is trying
		-- to read. `focusVisual = "none"` lets a control that paints its OWN focused
		-- treatment say so, instead of the adapter and the control both drawing.
		-- Construction-only: which thing draws the state is what the node IS, not a
		-- question about state.
		focusVisual = p({
			types = { "string" },
			reactive = false,
			channel = "semantic",
			enum = { "default", "none" },
			doc = '"default" (adapter paints the focused state) | "none" (this control paints its own)',
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

-- THE ENGINE-CONTENT BOX (ViewportFrame adoption; research
-- docs/research/2026-08-08-viewportframe-engine-facts.md). A leaf that reserves a
-- rectangle for content the ENGINE draws — a 3D preview, a hero rig — instead of
-- content Facet lays out. It is deliberately spare: the box, its surface, and its
-- one continuous paint channel are authored props like any other leaf's, and
-- everything engine-shaped (the camera, the lighting, the content root) rides the
-- adapter's `stageHost` seam, where the engine types can be converted at the one
-- boundary that is allowed to know about them.
--
-- NO INTRINSIC CONTENT, and therefore no intrinsic size: a Stage measures 0x0
-- exactly as a Box does, because the framework cannot ask a 3D scene how big it
-- would like to be. Authors give it `width`/`height` (api.md says so).
class("Stage", {
	container = false,
	structural = false,
	props = merge(BOX, {
		-- the eight-surface vocabulary, shared with Box: the plate BEHIND the
		-- rendered scene (a Stage is transparent until something paints it)
		surface = CONTAINER_LAYOUT.surface,
		-- ...and the one continuous channel, which on this class claims the frame's
		-- own ImageColor3 — a ViewportFrame's "picture" is the scene it renders, so
		-- the tint multiplies it exactly as an Image's tint multiplies its asset
		tint = TINT,
	}),
})

--[[ THE FOREIGN BOX (ADR-0034; docs/reference/react-lua-comparison.md §5 rank 1).

	A box reserved for a `GuiObject` Facet does not wrap — a `VideoFrame`, an
	`EditableImage` surface, a vendored widget, a class Roblox ships next month.
	It is `Stage`'s sibling: the same "the framework owns the box, somebody else
	owns the content" shape, opening onto a 2-D GuiObject instead of onto a 3-D
	scene.

	IT IS DELIBERATELY THE SPAREST CLASS IN THE SCHEMA, and the emptiness is the
	design. It takes the shared box vocabulary and ONE paint prop — `surface`, the
	plate BEHIND the content, which is a property of the container Facet owns —
	and nothing else. No engine props at all: the closed key set stays closed,
	because the schema cannot validate props it has never heard of, and the
	authority manifest cannot own a property on a class it does not know. What
	goes IN the box rides `controller.foreignHost(path).adopt(instance)`.

	NO INTRINSIC CONTENT, and therefore no intrinsic size: a Foreign measures 0x0
	exactly as a Box does. This is not a shortcut — an engine instance with
	`AutomaticSize` measures ITSELF, which the solver cannot see, so a box the
	framework inferred from foreign content would be a box nobody measured. It is
	DECLARED (api.md says so) and the container clips to it.

	No `tint`: a tint multiplies the node's own picture, and this node's picture is
	the caller's instance. See REFUSED_FOREIGN below — the refusal says so where it
	is reached for. ]]
class("Foreign", {
	container = false,
	structural = false,
	props = merge(BOX, {
		-- the plate BEHIND the content: a fallback while the caller's instance
		-- loads, or a frame around it. It paints the CONTAINER, which Facet owns.
		surface = CONTAINER_LAYOUT.surface,
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
			doc = "normalized Path2D control points from Facet.pathShapes",
		}),
		thickness = p({
			-- same ruling as Divider.thickness: a theme-owned number
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
			doc = "(branchScope) -> Blueprint, run when the condition is true",
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
-- (api-architecture-consistency F-6.) `schema.all()` and
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

-- Damerau-free Levenshtein, bounded: good enough to name the intended prop. The
-- matrix lives in `src/text_distance.luau`. THE THRESHOLD STAYS HERE,
-- at the call site below, because it is the half that was never agreed: this
-- caller lowercases both sides and accepts `d <= max(2, floor(#name / 3))`,
-- where `spec_guard` and `themes/package` accept 2 case-sensitively.
local distance = textDistance.distance

--[[ A REFUSED CAPABILITY SAYS SO AT THE POINT OF USE (ADR-0029, director round
	2026-08-15).

	`opacity` and `canvasGroup` live on `Box` and `ZStack` and nowhere else, and
	until this round every other class answered `UI.Text{ opacity = 0.4 }` through
	the generic unknown-property path: *"unknown property 'opacity'. Valid
	properties: …"*. That reads as a gap in the schema rather than a decision, it
	sends the author to a list that does not contain the answer, and it never
	mentions the one line that works. The director's ruling: a capability that is
	refused should say so where it is reached for.

	WHY IT IS REFUSED, measured rather than reasoned (live probes L1/L4,
	2026-08-15, artifacts/leaf-opacity/live-probes.md). A per-node fade would have
	to write `TextTransparency`/`BackgroundTransparency`, which the native sheet
	owns. The cost is not that the rule loses this frame — it is that
	`GetStyled(prop)` returns THE EXPLICIT WRITE from then on, so the sheet's own
	value stops being readable at all. A composition needs a base term, and the act
	of composing destroys the only way to read it: measured, a leaf at
	`opacity = 0.5` recomposing on `GetStyledPropertyChangedSignal` multiplied its
	own output back in on every state transition and reached T = 0.998 — invisible
	— after four disable/enable cycles.

	ONE MESSAGE FOR BOTH SPELLINGS, and it is deliberately not class-shaped: the
	reason is the same for a leaf and for a `VStack`, because the fact is about
	which engine INSTANCE can carry the one alpha property no rule owns, not about
	having children. ]]
local REFUSED_FADE = "A fade in Facet is one engine property no style rule owns — "
	.. "CanvasGroup.GroupTransparency — and only a node materialized as a CanvasGroup has one. "
	.. "UI.Box and UI.ZStack are the two classes that can BE one. Anywhere else the fade would have to "
	.. "write TextTransparency/BackgroundTransparency, which the native stylesheet owns, and one explicit "
	.. "write does not lose a frame: it makes the sheet's value unreadable for good (GetStyled returns the "
	.. "write from then on), so a control under it would stop dimming when disabled, forever. "
	.. "The spelling is one wrap: UI.ZStack{ opacity = 0.4, children = { … } }. "
	.. "`scale` and `rotation` need no wrap and are offered on every rendered class, because each of them "
	.. "IS one engine property no rule owns (UIScale.Scale, GuiObject.Rotation) -- and on a CONTAINER they "
	.. "now reach its contents too, because such a container becomes a real instance parent and the engine "
	.. "composes both terms for the subtree (ADR-0032 Decision 4). See ADR-0029."

local REFUSED: { [string]: string } = {
	opacity = REFUSED_FADE,
	canvasGroup = REFUSED_FADE,
}

--[[ THE UNBOUNDED ESCAPE HATCH, REFUSED WHERE IT IS REACHED FOR (ADR-0034).

	`UI.Foreign{ class = "VideoFrame", props = { Video = "rbxassetid://…" } }` is
	the shape every author arriving from React-Lua will type first, and it is the
	one form this class exists NOT to be. Answering it with "unknown property
	'class'" would send them to a property list that does not contain the answer
	and never mention the line that works.

	WHY IT IS REFUSED, in one sentence each: the schema cannot validate props it
	has never heard of (the closed key set, constitution §4); the authority
	manifest has no entry for a class it does not know, and on this engine a second
	writer for a property is SILENT (an explicit write defeats a StyleSheet rule and
	fires no signal, measured 2026-08-15); and an `AutomaticSize` child measures
	itself, which the solver cannot see. The bounded form gives up all three
	problems at once by never accepting an engine prop: the caller owns the
	instance, so Facet claims nothing to have to arbitrate.

	CLASS-SCOPED, unlike `REFUSED` above, because these words are only true here:
	`class` and `props` mean nothing on a `UI.Text`, so there the generic unknown-
	property message is the right one. ]]
local REFUSED_FOREIGN = "UI.Foreign takes NO engine properties — that is what makes it safe. "
	.. "The framework owns exactly one thing about this node (the box its solver reserved) and disclaims "
	.. "the rest by construction: it never creates your instance and never writes a property on it, so "
	.. "there is no second writer to arbitrate (on this engine a second writer is SILENT — an explicit "
	.. "write defeats a style rule and fires no signal). Declare the BOX here, then fill it: "
	.. "`local host = controller.foreignHost(path); if host then host.adopt(myVideoFrame) end`. "
	.. "The instance, its properties and its lifetime stay yours. See ADR-0034."

local REFUSED_BY_CLASS: { [string]: { [string]: string } } = {
	Foreign = {
		class = REFUSED_FOREIGN,
		className = REFUSED_FOREIGN,
		props = REFUSED_FOREIGN,
		instance = REFUSED_FOREIGN,
		native = REFUSED_FOREIGN,
		-- ...and the one paint channel a box-shaped leaf usually carries. A tint
		-- multiplies the node's own picture; this node's picture is the caller's
		-- instance, and multiplying it would be the framework painting content it
		-- has just finished disclaiming.
		tint = "UI.Foreign has no `tint`: a tint multiplies the node's own picture, and this node's picture "
			.. "is the instance YOU adopted — painting it would be Facet writing the content it exists to "
			.. "disclaim. `surface` paints the plate BEHIND the content, which the framework does own; "
			.. "anything on the content itself is yours to set on your own instance. See ADR-0034.",
	},
}

--[[ refusal(class, prop) -> why this class does not offer `prop`, when the answer
	is "the framework refused it" rather than "nobody thought of it". nil otherwise,
	which is every other property on every class.

	SCOPED TO THE CLASSES THAT PAINT AN ENGINE INSTANCE, and `scale` is the marker
	for that set — a rendered class carries the shared box props, a structural one
	(`When`, `ForEach`, `Region`, `GridRow`, `ErrorBoundary`) carries none of them
	and has no instance to fade. On those five `opacity` is genuinely unknown rather
	than refused, and the message above would be a wrong answer. ]]
function schema.refusal(className: string, prop: string): string?
	-- a CLASS-SCOPED refusal wins outright and needs no scope heuristic: it was
	-- declared for this class and this prop, so there is nothing to infer
	local scoped = REFUSED_BY_CLASS[className]
	if scoped ~= nil and scoped[prop] ~= nil then
		return scoped[prop]
	end
	local why = REFUSED[prop]
	if why == nil then
		return nil
	end
	local spec = CLASSES[className]
	-- the class HAS it (Box, ZStack), or does not paint at all: nothing was refused
	if spec == nil or spec.props[prop] ~= nil or spec.props.scale == nil then
		return nil
	end
	return why
end

-- suggest(class, badProp) -> "did you mean 'x' or 'y'?" style list (may be empty)
--
-- THE TWO RESERVED KEYS ARE CANDIDATES TOO. `id` and `children` live
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
