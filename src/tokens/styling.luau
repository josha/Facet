--!strict
-- Style-modifier normalization (design §17 Phase 4 engine styling;
-- UI-STYLE-001): validates and normalizes UI.shadow / UI.corners specs into
-- the engine-true style data the renderer writes under the STYLE authority.
-- Encodes the verified platform facts (docs/research/2026-07-20-uishadow-
-- percorner-engine-facts.md):
--   * BlurRadius is a UDim — { scale (fraction of the parent's shortest
--     dimension), offset (px) }, both non-negative;
--   * Offset and Spread are UDim2 shapes — { x = {scale, offset},
--     y = {scale, offset} };
--   * shadow ZIndex is negative-only (shadows render below the parent);
--   * per-corner UICorner: a node emits EXACTLY ONE form — uniform alias
--     ("uniform") or four explicit radii ("perCorner") — mixing the alias
--     with individual corners misbehaves in the engine and is a build error.
-- Token names resolve against the ACTIVE style (default: Studio Neutral).
-- Purely data: headless dumps carry these tables; the client adapter
-- materializes UIShadow/UICorner instances behind capability detection.

local default_style = require("./default_style")

local styling = {}

local CORNER_KEYS = { "topLeft", "topRight", "bottomLeft", "bottomRight" }

-- CLOSED KEY SETS (api-architecture-consistency F-5 / ledger BP-F2).
-- `normalizeStroke` and `checkTint` refuse an unknown field; `normalizeShadow`
-- and `normalizeGradient` did not, so `UI.gradient(bp, { colors = {…},
-- roation = 45 })` constructed happily with the default 90° rotation. That is
-- exactly the accepted-and-ignored class the whole strict boundary exists to
-- remove, surviving inside the two grammars that skipped it — and a typo in a
-- style modifier reads as a theme problem, not an authoring one.
local function assertKnownKeys(spec: any, what: string, legal: { string })
	local allowed: { [string]: boolean } = {}
	for _, key in legal do
		allowed[key] = true
	end
	for key in spec do
		assert(
			type(key) == "string" and allowed[key],
			`unknown {what} field '{tostring(key)}' ({table.concat(legal, " | ")})`
		)
	end
end

local SHADOW_KEYS = { "blurRadius", "color", "enabled", "offset", "spread", "transparency", "zIndex" }
local GRADIENT_KEYS = { "colors", "enabled", "rotation", "transparency" }

local function udim(value: any, what: string): { scale: number, offset: number }
	assert(type(value) == "table", what .. " must be a {scale, offset} table")
	local scale = value.scale or 0
	local offset = value.offset or 0
	assert(type(scale) == "number" and type(offset) == "number", what .. " scale/offset must be numbers")
	return { scale = scale, offset = offset }
end

local function udim2(
	value: any,
	what: string
): { x: { scale: number, offset: number }, y: { scale: number, offset: number } }
	if value == nil then
		return { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } }
	end
	assert(type(value) == "table", what .. " must be {x = {scale, offset}, y = {scale, offset}}")
	return { x = udim(value.x or {}, `{what}.x`), y = udim(value.y or {}, `{what}.y`) }
end

-- normalizeShadow(spec, style?) -> engine-true shadow table
-- spec: a preset name (style.shadows[name]) or an explicit parameter table.
function styling.normalizeShadow(spec: any, style: any?): any
	local activeStyle: any = style or default_style
	if type(spec) == "string" then
		local preset = activeStyle.shadows and activeStyle.shadows[spec]
		assert(preset ~= nil, `unknown shadow preset '{spec}' (style.shadows)`)
		spec = preset
	end
	assert(type(spec) == "table", "shadow spec must be a preset name or a parameter table")
	-- the preset-NAME form resolves ABOVE this line, so a style's own presets are
	-- held to the same closed set an author is
	assertKnownKeys(spec, "shadow", SHADOW_KEYS)
	local blur = udim(spec.blurRadius, "shadow.blurRadius")
	assert(blur.scale >= 0 and blur.offset >= 0, "shadow.blurRadius is clamped non-negative by the engine")
	local zIndex = spec.zIndex or -1
	assert(type(zIndex) == "number" and zIndex < 0, "shadow.zIndex must be NEGATIVE (shadows render below the parent)")
	local transparency = spec.transparency or 0.5
	assert(transparency >= 0 and transparency <= 1, "shadow.transparency must be within 0..1")
	local color = spec.color or { r = 0, g = 0, b = 0 }
	return table.freeze({
		blurRadius = blur,
		color = table.freeze({ r = color.r or 0, g = color.g or 0, b = color.b or 0 }),
		transparency = transparency,
		offset = udim2(spec.offset, "shadow.offset"),
		spread = udim2(spec.spread, "shadow.spread"),
		zIndex = zIndex,
		enabled = if spec.enabled == nil then true else spec.enabled == true,
	})
end

local function resolveRadius(value: any, style: any): number
	if type(value) == "number" then
		assert(value >= 0, "corner radius must be non-negative")
		return value
	end
	if type(value) == "string" then
		local resolved = style.radii and style.radii[value]
		assert(type(resolved) == "number", `unknown radius token '{value}' (style.radii)`)
		return resolved
	end
	error("corner radius must be a number or a radius token name", 0)
end

-- normalizeCorners(spec, style?) -> { form = "uniform", radius } |
--   { form = "perCorner", topLeft, topRight, bottomLeft, bottomRight }
function styling.normalizeCorners(spec: any, style: any?): any
	local activeStyle: any = style or default_style
	if type(spec) == "number" or type(spec) == "string" then
		return table.freeze({ form = "uniform", radius = resolveRadius(spec, activeStyle) })
	end
	assert(type(spec) == "table", "corners spec must be a radius, a token name, or a per-corner table")
	local hasAlias = spec.radius ~= nil
	local hasCorner = false
	for _, key in CORNER_KEYS do
		if spec[key] ~= nil then
			hasCorner = true
		end
	end
	assert(
		not (hasAlias and hasCorner),
		"corner styling emits exactly one form per node: use radius OR per-corner keys, never both (engine alias-mixing hazard)"
	)
	if hasAlias then
		return table.freeze({ form = "uniform", radius = resolveRadius(spec.radius, activeStyle) })
	end
	assert(hasCorner, "corners table must set radius or at least one corner")
	local out: any = { form = "perCorner" }
	for _, key in CORNER_KEYS do
		out[key] = if spec[key] ~= nil then resolveRadius(spec[key], activeStyle) else 0
	end
	return table.freeze(out)
end

-- ===== the per-view GRADIENT modifier (charter cap 11; ADR-0020 R8 rung 2) ==
--
-- A gradient at the THEME rung is palette data (`style.themes[].extra
-- .chromeGradient.<slot>`) and compiles to a phantom `::UIGradient` rule with
-- zero child instances. A gradient at the VIEW rung cannot be: a rule matches a
-- class of nodes, and this one has to win on exactly one. So it follows
-- `UI.shadow`'s architecture instead — bounded normalized DATA under the STYLE
-- authority, materialized by the adapter as ONE bespoke child instance. There
-- is no rule for it to defeat and no dual authority.
--
-- The engine truths this encodes:
--   * `UIGradient.Color` is a ColorSequence: stops are ordered, the first is at
--     0 and the last at 1, and 2-3 of them is the whole authoring vocabulary
--     (a ramp nobody can see is not a feature);
--   * `UIGradient.Transparency` fades the parent's ENTIRE rendering, its own
--     engine-drawn text included — which is why the alpha ceiling below is the
--     SAME number `themes.define` enforces on the theme path, and why the
--     blueprint modifier refuses a text-bearing node outright;
--   * `Rotation` is degrees, 0 = left-to-right.

-- the readability ceiling on an alpha ramp. MUST equal
-- `themes.package.GRADIENT_ALPHA_MAX`: one number, two authoring paths, and a
-- spec asserts they are equal (they cannot share a require — `themes/package`
-- is above `tokens` in the graph and a cycle here hangs Lune rather than
-- erroring, docs/lessons/lune-circular-require-hangs.md).
styling.GRADIENT_ALPHA_MAX = 0.9

local GRADIENT_MIN_STOPS = 2
local GRADIENT_MAX_STOPS = 3

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- "#rrggbb" -> rgb 0..1, or nil when the string is not a hex literal. A hex
-- colour is the DECLARED theming-exempt escape (ADR-0022 Decision 6): it says
-- "this number is the value", which is exactly what an identity hue is and
-- exactly what a role name must be used for instead when the value has meaning.
local function hexRgb(value: any): { r: number, g: number, b: number }?
	if type(value) ~= "string" or #value ~= 7 or string.sub(value, 1, 1) ~= "#" then
		return nil
	end
	local r, g, b = string.match(value, "^#(%x%x)(%x%x)(%x%x)$")
	if r == nil then
		return nil
	end
	return { r = tonumber(r, 16) / 255, g = tonumber(g, 16) / 255, b = tonumber(b, 16) / 255 }
end
styling.hexRgb = hexRgb

-- a colour token resolves against the ACTIVE style's contract colours and then
-- its extra roles — the same two-step, in the same order, that a theme's
-- `"$Name"` recipe token uses, so one mental model covers both rungs. A
-- `"#rrggbb"` literal is taken as itself (the escape above).
local function resolveColor(value: any, style: any, what: string): { r: number, g: number, b: number }
	if type(value) == "string" then
		local hex = hexRgb(value)
		if hex ~= nil then
			return hex
		end
		local resolved = (style.colors and style.colors[value]) or (style.extra and style.extra[value])
		assert(
			type(resolved) == "table" and type(resolved.r) == "number",
			`{what}: unknown colour token '{value}' (style.colors then style.extra)`
		)
		return { r = resolved.r, g = resolved.g, b = resolved.b }
	end
	assert(
		type(value) == "table" and isFinite(value.r) and isFinite(value.g) and isFinite(value.b),
		`{what} must be a colour token name or an \{ r, g, b } table`
	)
	return { r = value.r, g = value.g, b = value.b }
end

-- 2-3 entries -> stops with t pinned to 0 … 1. Each entry is a bare value (the
-- position is derived, evenly spaced) or `{ t = …, color = … }` / `{ t, v }`
-- when the author wants the middle stop somewhere else.
local function ramp(list: any, what: string, read: (any, number) -> any): { any }
	assert(type(list) == "table", `{what} must be an array of {GRADIENT_MIN_STOPS}-{GRADIENT_MAX_STOPS} stops`)
	local count = #list
	assert(
		count >= GRADIENT_MIN_STOPS and count <= GRADIENT_MAX_STOPS,
		`{what} takes {GRADIENT_MIN_STOPS}-{GRADIENT_MAX_STOPS} stops (got {count}) — the engine wants an ordered `
			.. "sequence, and a ramp with more stops than that is a texture, not a wash"
	)
	local out: { any } = {}
	local previous = -1
	for index, entry in ipairs(list) do
		local derived = if count == 1 then 0 else (index - 1) / (count - 1)
		local t = if type(entry) == "table" and isFinite(entry.t) then entry.t else derived
		assert(isFinite(t) and t >= 0 and t <= 1, `{what}[{index}].t must be a number within 0..1 (got {tostring(t)})`)
		assert(t > previous, `{what}[{index}].t = {t} is not after the previous stop — gradient stops must ascend`)
		previous = t
		table.insert(out, read(entry, t))
	end
	assert(out[1].t == 0, `{what}[1].t must be 0 — the engine pins a sequence to both ends`)
	assert(out[#out].t == 1, `{what}[{#out}].t must be 1 — the engine pins a sequence to both ends`)
	return out
end

-- normalizeGradient(spec, style?) -> engine-true gradient table
--
-- spec = {
--   colors = { <token | {r,g,b}> , … }         -- 2-3, required
--   rotation = <degrees>                        -- optional, default 90 (top -> bottom)
--   transparency = { <0..GRADIENT_ALPHA_MAX>, … } -- optional, 2-3
--   enabled = <boolean>                         -- optional, default true
-- }
function styling.normalizeGradient(spec: any, style: any?): any
	local activeStyle: any = style or default_style
	assert(type(spec) == "table", "gradient spec must be a table with a `colors` ramp")
	assertKnownKeys(spec, "gradient", GRADIENT_KEYS)
	local colors = ramp(spec.colors, "gradient.colors", function(entry, t)
		local value = if type(entry) == "table" and (entry.color ~= nil or entry.t ~= nil) then entry.color else entry
		local rgbValue = resolveColor(value, activeStyle, "gradient.colors")
		return table.freeze({ t = t, r = rgbValue.r, g = rgbValue.g, b = rgbValue.b })
	end)

	local rotation = if spec.rotation == nil then 90 else spec.rotation
	assert(isFinite(rotation), `gradient.rotation must be a finite number of degrees (got {tostring(rotation)})`)
	rotation = rotation % 360

	local transparency: { any }? = nil
	if spec.transparency ~= nil then
		transparency = ramp(spec.transparency, "gradient.transparency", function(entry, t)
			local v = if type(entry) == "table" then entry.v else entry
			assert(
				isFinite(v) and v >= 0,
				`gradient.transparency stop must be a number at or above 0 (got {tostring(v)})`
			)
			assert(
				v <= styling.GRADIENT_ALPHA_MAX,
				`gradient.transparency stop {v} is above the {styling.GRADIENT_ALPHA_MAX} ceiling — `
					.. "UIGradient.Transparency fades the parent's ENTIRE rendering, so a near-1 stop ghosts the "
					.. `whole node rather than softening the wash; a subtle ramp is 0.1-0.35`
			)
			return table.freeze({ t = t, v = v })
		end)
	end

	return table.freeze({
		colors = table.freeze(colors),
		rotation = rotation,
		transparency = if transparency ~= nil then table.freeze(transparency) else nil,
		enabled = if spec.enabled == nil then true else spec.enabled == true,
	})
end

-- ===== the CONTINUOUS-COLOUR channel: `tint` (ADR-0022 Decision 6) =========
--
-- Everything finite stays tokens + tags + native-sheet states (ADR-0018): a
-- value drawn from a CLOSED SET (hover, selected, disabled, verdict, phase) is a
-- STATE, and reaching for a continuous channel to express one is a defect the
-- docs and this vocabulary both say so. `tint` exists for the two values a
-- finite selector cannot express — a blend along a scalar, and an identity hue
-- that IS game data.
--
-- TWO VALUE FORMS, and the loud word lives in the value (ui-designer F11, lead
-- disposition 2026-07-27):
--   { role = "accent", blend = 0.6, from = "control"? }  themable, PREFERRED
--   { direct = { r, g, b } | "#rrggbb" }                 declared theming-EXEMPT
--
-- `from` defaults to the class's identity base (sheet_model.TINT_IDENTITY), so
-- the two-role blend the Sponsor motion spec ratified ("control -> accent driven
-- by an energy value") is written with the base named rather than guessed. The
-- framework deliberately does NOT infer the base from the node's own `surface`:
-- that mapping already exists twice (the sheet's surface rules and the adapter's
-- fallback fills) and a third copy would drift, painting a blend = 0 tint a
-- different colour than the untinted node.
--
-- The ROLE vocabulary is closed and shared with the chrome recipes' resting tint
-- (sheet_model asserts the two sets are equal at load), because a role name
-- nothing validates is a tint that silently paints nothing —
-- docs/lessons/enum-props-accept-any-string.md.
local TINT_ROLES: { string } = {
	"surface",
	"surfaceStrong",
	"content",
	"contentStrong",
	"contentSecondary",
	"accent",
	"control",
	"controlSelected",
	"danger",
	"hairline",
}
styling.TINT_ROLES = table.freeze(TINT_ROLES)

local TINT_ROLE_SET: { [string]: boolean } = {}
for _, role in TINT_ROLES do
	TINT_ROLE_SET[role] = true
end
styling.TINT_ROLE_LIST = table.concat(TINT_ROLES, " | ")

local TINT_KEYS: { [string]: boolean } = { role = true, blend = true, from = true, direct = true, transparency = true }

--[[ THE TINT'S OWN ALPHA (`transparency`, added 2026-07-31 — RascalRally row
	OWN-D39, recorded 2026-07-30 as "if a SECOND consumer meets it, a tint alpha
	returns to the LuauUI roadmap rather than being re-composited per game").

	The recorded workaround was to compute the COMPOSITE a legacy transparency
	paints — the fill lerped toward the backdrop it sits on — which is exact, and
	which requires knowing that backdrop. The second consumer's two cases have
	NO knowable backdrop: a results scrim sits over the live 3D world, and a map
	name tag sits over whatever the map canvas is drawing under it. There is no
	arithmetic available, so the channel has to be real.

	Engine-true, and deliberately the same word and the same polarity as
	`UI.stroke`'s `transparency`: 0 is opaque (the default, so every tint written
	before this is byte-identical) and 1 is invisible. It rides the SAME claim the
	tint already takes — a tinted Box has always claimed `BackgroundTransparency`,
	so on a Box this adds no new authority at all, only a value other than 0.
]]
styling.TINT_TRANSPARENCY_DEFAULT = 0

-- checkTint(value) -> (ok, detail?). ONE ruling, three readers: the public
-- schema validates a static value at construction, the adapter validates a
-- REACTIVE one at the write site (a bound tint is read long after
-- construction), and the docs quote the same vocabulary.
function styling.checkTint(value: any): (boolean, string?)
	if type(value) ~= "table" then
		return false,
			`a tint table — \{ role = "accent", blend = 0.6 } (themable) or \{ direct = "#rrggbb" } `
				.. "(declared theming-exempt)"
	end
	for key in value :: any do
		if type(key) ~= "string" or not TINT_KEYS[key] then
			return false, `unknown tint field '{tostring(key)}' (role | blend | from | direct | transparency)`
		end
	end
	local alpha = (value :: any).transparency
	if alpha ~= nil and not (isFinite(alpha) and alpha >= 0 and alpha <= 1) then
		return false,
			`tint transparency must be a number within 0..1 (got {tostring(alpha)}) — `
				.. "0 is opaque (the default), 1 is invisible"
	end
	local hasRole = (value :: any).role ~= nil
	local hasDirect = (value :: any).direct ~= nil
	if hasRole and hasDirect then
		return false,
			"declares both `role` and `direct` — a tint is exactly ONE form, so nothing could pick between them"
	end
	if hasDirect then
		if (value :: any).blend ~= nil or (value :: any).from ~= nil then
			return false,
				"the `direct` form takes no `blend`/`from` (it IS the colour; blending belongs to the role form)"
		end
		local direct = (value :: any).direct
		if hexRgb(direct) ~= nil then
			return true
		end
		if type(direct) == "string" then
			return false, `direct must be an "#rrggbb" literal or an \{ r, g, b } table (got '{direct}')`
		end
		if not (type(direct) == "table" and isFinite(direct.r) and isFinite(direct.g) and isFinite(direct.b)) then
			return false, 'direct must be an { r, g, b } table (0..1) or an "#rrggbb" literal'
		end
		return true
	end
	if not hasRole then
		return false, `a tint names a \`role\` ({styling.TINT_ROLE_LIST}) or a \`direct\` colour`
	end
	if not TINT_ROLE_SET[(value :: any).role] then
		return false, `unknown tint role '{tostring((value :: any).role)}' (one of {styling.TINT_ROLE_LIST})`
	end
	local from = (value :: any).from
	if from ~= nil and not TINT_ROLE_SET[from] then
		return false, `unknown tint \`from\` role '{tostring(from)}' (one of {styling.TINT_ROLE_LIST})`
	end
	local blend = (value :: any).blend
	if not isFinite(blend) or blend < 0 or blend > 1 then
		return false, `blend must be a number within 0..1 (got {tostring(blend)}) — 0 is the base, 1 is the role`
	end
	return true
end

-- ===== the authored STROKE modifier: UI.stroke (ADR-0022 Decision 6) =======
--
-- Same architecture as `UI.shadow`/`UI.gradient`/`UI.corners`: bounded
-- normalized DATA under the STYLE authority, materialized by the adapter as ONE
-- bespoke child instance. A theme's own chrome stroke is a phantom `::UIStroke`
-- RULE, and the engine renders a real UIStroke child ALONGSIDE it (ADR-0020 R8,
-- measured) — so an authored stroke is ADDITIVE, never a replacement, and the
-- reference says so.
--
-- Defaults are the theme's hairline, so `UI.stroke(bp, {})` is exactly the
-- hairline the adapter already draws on a raised panel.
function styling.normalizeStroke(spec: any, style: any?): any
	local activeStyle: any = style or default_style
	if spec == nil then
		spec = {}
	end
	assert(type(spec) == "table", "stroke spec must be a { thickness?, color?, transparency? } table")
	for key in spec :: any do
		assert(
			key == "thickness" or key == "color" or key == "transparency",
			`unknown stroke field '{tostring(key)}' (thickness | color | transparency)`
		)
	end
	-- A READABLE FIELD IS REFUSED, and the message names the working idiom. A
	-- Signal frozen INSIDE normalized data would never be read again: the mount
	-- layer subscribes PROPS, not fields, so a pulsing thickness has to be a
	-- pulsing `stroke` prop — `stroke = core:memo(function() return
	-- UI.strokeData({ thickness = t:get() }) end)`.
	for _, key in { "thickness", "color", "transparency" } do
		local v = (spec :: any)[key]
		if type(v) == "table" and (v.kind == "signal" or v.kind == "memo") then
			error(
				`LuauUI UI.stroke: '{key}' cannot be a Signal/Memo — normalized style data is read once. `
					.. "Bind the whole prop instead: stroke = core:memo(function() return "
					.. `UI.strokeData(\{ {key} = … }) end)`,
				0
			)
		end
	end
	local thickness: any = (spec :: any).thickness
	if thickness == nil then
		thickness = activeStyle.strokes.hairline
	elseif type(thickness) == "string" then
		local resolved = activeStyle.strokes and activeStyle.strokes[thickness]
		assert(type(resolved) == "number", `unknown stroke thickness token '{thickness}' (style.strokes)`)
		thickness = resolved
	end
	assert(isFinite(thickness) and thickness >= 0, "stroke.thickness must be a non-negative number or a stroke token")
	local color = resolveColor(
		if (spec :: any).color == nil
			then (activeStyle.extra and activeStyle.extra.hairline) or { r = 1, g = 1, b = 1 }
			else (spec :: any).color,
		activeStyle,
		"stroke.color"
	)
	local transparency: any = (spec :: any).transparency
	if transparency == nil then
		transparency = (activeStyle.extra and activeStyle.extra.hairlineOpacity) or 0
	end
	assert(
		isFinite(transparency) and transparency >= 0 and transparency <= 1,
		"stroke.transparency must be a number within 0..1"
	)
	return table.freeze({
		thickness = thickness,
		color = table.freeze({ r = color.r, g = color.g, b = color.b }),
		transparency = transparency,
	})
end

return styling
