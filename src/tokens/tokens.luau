--!strict
-- Token compiler (design §11): one validated semantic token schema per game →
-- strict frozen Luau tables + a contrast/completeness report. Engine-free.
-- Native StyleSheet generation (formerly deferred while transitions were the
-- open question) now SHIPS via src/tokens/sheet_model.luau + the client
-- materializer (ADR-0018, native-stylesheets stage): transitions stay opt-in
-- progressive enhancement with an instant-change path, so the "always a
-- non-beta path" guarantee holds. Compiled Luau tokens remain the solver's
-- source of truth; the sheet owns paint at opted-in targets.

local tokens = {}

export type Rgb = { r: number, g: number, b: number } -- 0..1

local REQUIRED_COLOR_PAIRS: { { surface: string, content: string } } = {
	{ surface = "surface", content = "content" },
	{ surface = "surfaceStrong", content = "contentStrong" },
	{ surface = "accent", content = "onAccent" },
}
local REQUIRED_SPACE = { "xs", "s", "m", "l", "xl" }
local REQUIRED_TYPE = { "body", "label", "heading", "title" }

-- THE WEIGHT ROLES (F2, 2026-08-02): `strong` (emphasis at reading size) and
-- `numeral` (a rank/score figure) are first-class typography roles, and OPTIONAL
-- in a game's schema. A schema that omits one gets the size derived here from the
-- ramp it DID author, so every compiled style answers all eight role names and a
-- game never has to restate a number it already declared.
--
-- Sizes only — a compiled token style has never carried font descriptors (that is
-- the theme PACKAGE's `metrics.typography`, where the same two roles derive their
-- FACES from `themes.package.deriveTypeRole`). The two derivations agree by
-- construction: both take `strong` from `body` and `numeral` from
-- `control`-or-`heading`.
local DERIVED_TYPE: { { role: string, from: { string } } } = {
	{ role = "strong", from = { "body" } },
	{ role = "numeral", from = { "control", "heading" } },
}

local function luminance(c: Rgb): number
	local function chan(v: number): number
		return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b)
end

function tokens.contrastRatio(a: Rgb, b: Rgb): number
	local la, lb = luminance(a), luminance(b)
	local hi, lo = math.max(la, lb), math.min(la, lb)
	return (hi + 0.05) / (lo + 0.05)
end

-- The destructive role's library-fallback palette (B-BTN2): a style/theme that
-- predates the pair keeps working, and every gate then runs on the EFFECTIVE
-- pair. Lives HERE (dep-free) because both sheet_model and the theme-package
-- compiler gate it — requiring one from the other is a cycle (found live
-- 2026-07-25: Lune hangs on circular require, it does not error).
local DANGER_FALLBACK: Rgb = { r = 176 / 255, g = 42 / 255, b = 42 / 255 }
local ON_DANGER_FALLBACK: Rgb = { r = 1, g = 1, b = 1 }

function tokens.dangerPair(colors: any): (Rgb, Rgb)
	return colors.danger or DANGER_FALLBACK, colors.onDanger or ON_DANGER_FALLBACK
end

-- compile(schema) -> (compiled | nil, report)
-- report = { ok, missing = {..}, contrast = { {pair, ratio, ok} } }
function tokens.compile(schema: any): (any, any)
	local missing: { string } = {}
	local function need(section: string, key: string): any
		local sec = schema[section]
		local v = sec and sec[key]
		if v == nil then
			table.insert(missing, `{section}.{key}`)
		end
		return v
	end

	for _, k in REQUIRED_SPACE do
		need("space", k)
	end
	for _, k in REQUIRED_TYPE do
		need("type", k)
	end
	for _, pair in REQUIRED_COLOR_PAIRS do
		need("colors", pair.surface)
		need("colors", pair.content)
	end
	need("targetSizes", "minimum")
	need("motion", "fast")
	need("motion", "normal")

	local contrast = {}
	local contrastOk = true
	if schema.colors then
		for _, pair in REQUIRED_COLOR_PAIRS do
			local s, c = schema.colors[pair.surface], schema.colors[pair.content]
			if s and c then
				local ratio = tokens.contrastRatio(s, c)
				local ok = ratio >= 4.5
				if not ok then
					contrastOk = false
				end
				table.insert(contrast, {
					pair = `{pair.content} on {pair.surface}`,
					ratio = math.floor(ratio * 100) / 100,
					ok = ok,
				})
			end
		end
	end

	local report = {
		ok = #missing == 0 and contrastOk,
		missing = missing,
		contrast = contrast,
	}
	if not report.ok then
		return nil, report
	end

	-- the weight roles' sizes, filled in for a schema that did not author them
	-- (see DERIVED_TYPE above). An authored value always wins.
	local typeRamp = table.clone(schema.type)
	for _, entry in DERIVED_TYPE do
		if typeRamp[entry.role] == nil then
			for _, source in entry.from do
				if typeRamp[source] ~= nil then
					typeRamp[entry.role] = typeRamp[source]
					break
				end
			end
		end
	end

	local function deepFreeze(t: any): any
		for _, v in t do
			if type(v) == "table" then
				deepFreeze(v)
			end
		end
		return table.freeze(t)
	end
	local compiled = deepFreeze({
		colors = table.clone(schema.colors),
		type = typeRamp,
		space = table.clone(schema.space),
		radii = table.clone(schema.radii or {}),
		strokes = table.clone(schema.strokes or {}),
		targetSizes = table.clone(schema.targetSizes),
		motion = table.clone(schema.motion),
		-- shadow presets (§17 Phase 4 engine styling): engine-true UIShadow
		-- parameter sets referenced by name from UI.shadow(bp, "<preset>")
		shadows = table.clone(schema.shadows or {}),
	})
	return compiled, report
end

return tokens
