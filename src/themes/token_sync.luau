--!strict
-- Theme token SYNC codec (ADR-0019 §3, stage theme-packages-and-skinning).
-- PURE and engine-free: no Instance, no Color3, no Font — only typed RECORDS,
-- which is what makes the export deterministic and the freshness gate runnable
-- from Lune with no Studio attached.
--
-- The workflow this serves (ADR-0019 §3, the plan's PREFERRED option):
--   committed package  --seed-once-->  DataModel theme sheet (the ONE editable
--   surface)  --dump-->  typed records  --theme_sync-->  committed package.
-- There is never a second hand-edited metric source: the sheet is authored, the
-- Luau is generated, and `tools/lune/theme_sync_cli --check` fails when they
-- disagree.
--
-- Public interface
--   token_sync.SCHEMA                      the dump schema string
--   token_sync.records(package)            -> { Record } (sorted by path)
--   token_sync.recordsFromMetrics(metrics) -> { Record } (sorted by path)
--   token_sync.metricsFromRecords(records) -> a package `metrics` section
--   token_sync.overridesFromRecords(records, base?) -> snapshot override map
--   token_sync.attributeName(path)         -> the engine attribute name
--   token_sync.attributeForPath(records, path) -> the engine attribute name,
--                                          or the path when nothing claims it
--   token_sync.canonical(record)           -> a stable comparison string
--   token_sync.diff(a, b)                  -> { { path, left, right } }
--   token_sync.renderMetrics(records)      -> the `metrics = { … },` source
--   token_sync.renderModule(dump)          -> a whole generated module
--   token_sync.applyToSource(source, dump) -> (source, "patched" | "generated")
--   token_sync.BEGIN_MARKER / END_MARKER
--
-- TWO NAMESPACES, ONE RENAME. A record's `path` is the SNAPSHOT path (what
-- `themes.resolve` overrides address: "space.m", "type.body.size"), because the
-- live authoring loop feeds records straight into the resolver. The package's
-- authored section calls typography `typography`, so `type.*` <-> `typography.*`
-- is the single rename this module owns; every other segment is identical in
-- both namespaces.
--
-- ATTRIBUTE NAMES. Roblox attribute names admit only alphanumerics and
-- underscore, so a dotted path cannot be one: "type.body.size" is written
-- `Type_body_size` (first segment capitalized, dots -> underscores). The reverse
-- map is built from the known token set rather than parsed, so an attribute name
-- can never be mis-split.
--
-- TYPED RECORD KINDS (feasibility m6, proven value-exact and deterministic):
--   number, bool, string, color (hex), udim (scale+offset),
--   font (family + weight name/value + style name).
-- The v1 TOKEN SET is numbers and fonts; color tokens stay Step 2's sheet
-- tokens (several are derived — AccentHover and kin are computed from the
-- palette, so they have no authored source to write back to). The codec speaks
-- all six kinds so a future token of any of them round-trips unchanged.

local token_sync = {}

token_sync.SCHEMA = "facet-theme-sync/1"
-- The pre-rename spelling of the SAME schema. Studio dumps taken before the
-- 2026-08-17 Facet rename are immutable evidence and carry it; a reader must
-- still accept them, and nothing ever WRITES this one. Anything that is
-- neither spelling is still refused, so this is the same check, not a weaker
-- one. It is removable once no stored dump names it.
token_sync.LEGACY_SCHEMA = "luauui-theme-sync/1"

-- true when a stored dump declares a schema this build can read
function token_sync.readableSchema(schema: any): boolean
	return schema == nil or schema == token_sync.SCHEMA or schema == token_sync.LEGACY_SCHEMA
end

export type Record = {
	path: string, -- snapshot path ("space.m", "type.body.font")
	attribute: string, -- engine attribute name ("Space_m", "Type_body_font")
	kind: string, -- number | bool | string | color | udim | font
	value: any?, -- number | boolean | string
	hex: string?, -- color
	scale: number?, -- udim
	offset: number?, -- udim
	family: string?, -- font
	weight: string?, -- font, the enum NAME ("Regular")
	weightValue: number?, -- font, the enum VALUE (400) — m6's stable form
	style: string?, -- font, the enum NAME ("Normal")
}

local DEFAULT_WEIGHT = "Regular"
local DEFAULT_STYLE = "Normal"

-- Enum.FontWeight name -> numeric value. Kept as data (this module never
-- touches the engine), and it is the SAME table both directions so a dump made
-- on a client and a check run in Lune agree exactly.
local FONT_WEIGHT_VALUES: { [string]: number } = {
	Thin = 100,
	ExtraLight = 200,
	Light = 300,
	Regular = 400,
	Medium = 500,
	SemiBold = 600,
	Bold = 700,
	ExtraBold = 800,
	Heavy = 900,
}
token_sync.FONT_WEIGHT_VALUES = FONT_WEIGHT_VALUES

function token_sync.weightValueOf(name: string?): number
	return FONT_WEIGHT_VALUES[name or DEFAULT_WEIGHT] or FONT_WEIGHT_VALUES[DEFAULT_WEIGHT]
end

-- ===== paths <-> attribute names ===========================================

function token_sync.attributeName(path: string): string
	local out = string.gsub(path, "%.", "_")
	-- namespaced contribution roles carry ':' ("controlSizes.demo:gauge.height")
	-- and the ENGINE rejects ':' in an attribute name (found live: glossy-mobile,
	-- which covers demo:gauge, threw at seed time). '__' is unambiguous because
	-- '.' maps to a single '_' and role names may not contain '__'; the reverse
	-- direction is an index built from the record list, never parsed from the
	-- name, so the encoding only has to be legal and collision-free.
	out = string.gsub(out, ":", "__")
	return string.upper(string.sub(out, 1, 1)) .. string.sub(out, 2)
end

-- ===== the v1 token set ====================================================
-- Walked from the ACTUAL metric tree (sorted keys), never a hardcoded list, so
-- a package that declares a control family this build has not heard of still
-- round-trips instead of silently losing the value.

local FLAT_SECTIONS = { "motion", "radii", "space", "strokes", "targetSizes" }
local NESTED_SECTIONS = { "controlSizes", "controls", "insets" }

local function sortedKeys(t: any): { string }
	local keys: { string } = {}
	if type(t) ~= "table" then
		return keys
	end
	for k in t do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	return keys
end

local function numberRecord(path: string, value: number): Record
	return { path = path, attribute = token_sync.attributeName(path), kind = "number", value = value }
end

local function fontRecord(path: string, font: any): Record
	local weight = if type(font) == "table" and type(font.weight) == "string" then font.weight else DEFAULT_WEIGHT
	local style = if type(font) == "table" and type(font.style) == "string" then font.style else DEFAULT_STYLE
	return {
		path = path,
		attribute = token_sync.attributeName(path),
		kind = "font",
		family = if type(font) == "table" then tostring(font.family) else "BuilderSans",
		weight = weight,
		weightValue = token_sync.weightValueOf(weight),
		style = style,
	}
end

-- recordsFromMetrics(metrics): `metrics` is a package's AUTHORED metrics section
-- (the one `themes.define` validated), so typography is named `typography` here
-- and becomes `type` in the emitted paths.
function token_sync.recordsFromMetrics(metrics: any): { Record }
	local out: { Record } = {}
	if type(metrics) ~= "table" then
		return out
	end
	local typography = if type(metrics.typography) == "table" then metrics.typography else metrics.type
	for _, role in sortedKeys(typography) do
		local entry = (typography :: any)[role]
		if type(entry) ~= "table" then
			continue
		end
		if type(entry.size) == "number" then
			table.insert(out, numberRecord(`type.{role}.size`, entry.size))
		end
		if type(entry.lineHeight) == "number" then
			table.insert(out, numberRecord(`type.{role}.lineHeight`, entry.lineHeight))
		end
		table.insert(out, fontRecord(`type.{role}.font`, entry.font))
	end
	for _, section in FLAT_SECTIONS do
		local node = (metrics :: any)[section]
		for _, name in sortedKeys(node) do
			local v = (node :: any)[name]
			if type(v) == "number" then
				table.insert(out, numberRecord(`{section}.{name}`, v))
			end
		end
	end
	for _, section in NESTED_SECTIONS do
		local node = (metrics :: any)[section]
		for _, group in sortedKeys(node) do
			local entry = (node :: any)[group]
			for _, field in sortedKeys(entry) do
				local v = (entry :: any)[field]
				if type(v) == "number" then
					table.insert(out, numberRecord(`{section}.{group}.{field}`, v))
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.path < b.path
	end)
	return out
end

function token_sync.records(package: any): { Record }
	assert(type(package) == "table" and type(package.metrics) == "table", "token_sync.records: expected a package")
	return token_sync.recordsFromMetrics(package.metrics)
end

-- the reverse index, built from a record list (never parsed out of the name)
function token_sync.indexByAttribute(records: { Record }): { [string]: Record }
	local out: { [string]: Record } = {}
	for _, record in records do
		out[record.attribute] = record
	end
	return out
end

-- ...and the direction a live sheet edit actually needs: name a snapshot path
-- the way the designer sees it in the Style Editor. The controller used to
-- hand-roll this scan while the reverse lookup above it sat unused (Step 5.5
-- cleanup ledger C-10); the rename has one owner, which is why this module
-- exists. Falls back to the path itself when no record claims it.
function token_sync.attributeForPath(records: { Record }, path: string): string
	for _, record in records do
		if record.path == path then
			return record.attribute
		end
	end
	return path
end

-- ===== comparison ==========================================================

-- a stable, human-readable rendering of a record's VALUE — the unit both the
-- freshness gate and the drift report compare, so "drifted" always means the
-- same thing in both places
function token_sync.canonical(record: Record): string
	local kind = record.kind
	if kind == "number" then
		return string.format("%.6f", record.value :: number)
	elseif kind == "bool" then
		return tostring(record.value == true)
	elseif kind == "string" then
		return `"{tostring(record.value)}"`
	elseif kind == "color" then
		return `#{tostring(record.hex)}`
	elseif kind == "udim" then
		return string.format("(%.6f, %.6f)", record.scale or 0, record.offset or 0)
	elseif kind == "font" then
		return `{tostring(record.family)}#{tostring(record.weight)}({tostring(record.weightValue)})#{tostring(
			record.style
		)}`
	end
	return `<{tostring(kind)}>`
end

export type Drift = { path: string, left: string?, right: string? }

-- diff(left, right): every token whose value differs, plus tokens present on
-- only one side. Deterministically ordered by path.
function token_sync.diff(left: { Record }, right: { Record }): { Drift }
	local byPathLeft: { [string]: Record } = {}
	local byPathRight: { [string]: Record } = {}
	local paths: { [string]: boolean } = {}
	for _, r in left do
		byPathLeft[r.path] = r
		paths[r.path] = true
	end
	for _, r in right do
		byPathRight[r.path] = r
		paths[r.path] = true
	end
	local ordered: { string } = {}
	for path in paths do
		table.insert(ordered, path)
	end
	table.sort(ordered)
	local out: { Drift } = {}
	for _, path in ordered do
		local a, b = byPathLeft[path], byPathRight[path]
		local av = if a ~= nil then token_sync.canonical(a) else nil
		local bv = if b ~= nil then token_sync.canonical(b) else nil
		if av ~= bv then
			table.insert(out, { path = path, left = av, right = bv })
		end
	end
	return out
end

-- ===== records -> a package metrics section ================================

local function writePath(tree: any, path: string, value: any)
	local parts: { string } = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end
	if #parts == 0 then
		return
	end
	-- the ONE namespace rename: the snapshot calls it `type`, the authored
	-- package section calls it `typography`
	if parts[1] == "type" then
		parts[1] = "typography"
	end
	local node = tree
	for i = 1, #parts - 1 do
		if type(node[parts[i]]) ~= "table" then
			node[parts[i]] = {}
		end
		node = node[parts[i]]
	end
	node[parts[#parts]] = value
end

function token_sync.metricsFromRecords(records: { Record }): any
	local out: any = {}
	for _, record in records do
		if record.kind == "font" then
			writePath(out, record.path, { family = record.family, weight = record.weight, style = record.style })
		elseif record.kind == "number" or record.kind == "bool" or record.kind == "string" then
			writePath(out, record.path, record.value)
		elseif record.kind == "udim" then
			writePath(out, record.path, { scale = record.scale, offset = record.offset })
		elseif record.kind == "color" then
			writePath(out, record.path, { hex = record.hex })
		end
	end
	return out
end

-- overridesFromRecords(records, base?): the map `themes.resolve` takes as its
-- `overrides` argument. When `base` is supplied only records that DIFFER from it
-- are emitted, so an untouched sheet produces zero overrides and the resolver's
-- composition (display policy, floors, chrome content insets) is left intact —
-- an override is reserved for a value a human actually changed.
--
-- A font override writes BOTH `type.<role>.font` and `type.<role>.fontKey`: the
-- descriptor is the measurement cache key, and leaving it stale would measure
-- the old font while painting the new one.
function token_sync.overridesFromRecords(records: { Record }, base: { Record }?): { [string]: any }
	local baseline: { [string]: string } = {}
	if base ~= nil then
		for _, record in base do
			baseline[record.path] = token_sync.canonical(record)
		end
	end
	local out: { [string]: any } = {}
	for _, record in records do
		if base ~= nil and baseline[record.path] == token_sync.canonical(record) then
			continue
		end
		if record.kind == "number" or record.kind == "bool" or record.kind == "string" then
			out[record.path] = record.value
		elseif record.kind == "font" then
			local weight = record.weight or DEFAULT_WEIGHT
			local style = record.style or DEFAULT_STYLE
			out[record.path] = { family = record.family, weight = weight, style = style }
			local role = string.match(record.path, "^type%.(.+)%.font$")
			if role ~= nil then
				out[`type.{role}.fontKey`] = `{record.family}#{weight}#{style}`
			end
		elseif record.kind == "udim" then
			out[record.path] = { scale = record.scale, offset = record.offset }
		elseif record.kind == "color" then
			out[record.path] = { hex = record.hex }
		end
	end
	return out
end

-- ===== deterministic Luau emission =========================================

token_sync.BEGIN_MARKER = "-- theme_sync:begin metrics"
token_sync.END_MARKER = "-- theme_sync:end metrics"

local function numberSource(v: number): string
	if v % 1 == 0 and math.abs(v) < 1e15 then
		return string.format("%d", v)
	end
	return string.format("%.6g", v)
end

local function quoted(s: string): string
	return '"' .. string.gsub(s, '"', '\\"') .. '"'
end

-- the metric tree is all string keys, so one sorted-key writer covers it
local function renderValue(value: any, indent: string, out: { string })
	if type(value) == "number" then
		table.insert(out, numberSource(value))
		return
	end
	if type(value) == "boolean" then
		table.insert(out, tostring(value))
		return
	end
	if type(value) == "string" then
		table.insert(out, quoted(value))
		return
	end
	if type(value) ~= "table" then
		table.insert(out, tostring(value))
		return
	end
	local keys = sortedKeys(value)
	if #keys == 0 then
		table.insert(out, "{}")
		return
	end
	local inner = indent .. "\t"
	table.insert(out, "{\n")
	for _, key in keys do
		table.insert(out, inner .. key .. " = ")
		renderValue((value :: any)[key], inner, out)
		table.insert(out, ",\n")
	end
	table.insert(out, indent .. "}")
end

-- the `metrics = { … },` fragment, tab-indented one level in (module-table
-- depth), byte-identical for identical records
function token_sync.renderMetrics(records: { Record }): string
	local metrics = token_sync.metricsFromRecords(records)
	local out: { string } = { "\tmetrics = " }
	renderValue(metrics, "\t", out)
	table.insert(out, ",\n")
	return table.concat(out)
end

export type Dump = {
	schema: string?,
	package: any?, -- { id, displayName, version, schemaVersion }
	theme: string?,
	stamp: string?,
	tokens: { Record },
}

local GENERATED_HEADER = "-- GENERATED by `lune run tools/lune/theme_sync_cli` — do not hand-edit.\n"
	.. "-- The authoring source is the DataModel theme sheet (ADR-0019 §3); edit the\n"
	.. "-- tokens there, dump them, and re-run theme_sync. `--check` fails on drift.\n"

function token_sync.renderModule(dump: Dump): string
	local identity = dump.package or {}
	local out: { string } = { GENERATED_HEADER }
	if dump.theme ~= nil then
		table.insert(out, `-- theme: {dump.theme}\n`)
	end
	if dump.stamp ~= nil then
		table.insert(out, `-- package stamp at export: {dump.stamp}\n`)
	end
	table.insert(out, "\nreturn {\n")
	table.insert(out, "\tidentity = ")
	renderValue({
		id = identity.id,
		displayName = identity.displayName,
		schemaVersion = identity.schemaVersion,
		version = identity.version,
	}, "\t", out)
	table.insert(out, ",\n")
	table.insert(out, token_sync.BEGIN_MARKER .. "\n")
	table.insert(out, token_sync.renderMetrics(dump.tokens))
	table.insert(out, token_sync.END_MARKER .. "\n")
	table.insert(out, "}\n")
	return table.concat(out)
end

-- applyToSource(source, dump): a file carrying the markers keeps everything
-- around them (its style, chrome and asset sections stay hand-authored and
-- untouched) and has only the metrics region regenerated. A file without them
-- is generator-owned end to end.
function token_sync.applyToSource(source: string?, dump: Dump): (string, string)
	if source == nil then
		return token_sync.renderModule(dump), "generated"
	end
	local beginAt = string.find(source, token_sync.BEGIN_MARKER, 1, true)
	local endAt = string.find(source, token_sync.END_MARKER, 1, true)
	if beginAt == nil or endAt == nil or endAt < beginAt then
		return token_sync.renderModule(dump), "generated"
	end
	local head = string.sub(source, 1, beginAt - 1)
	local tail = string.sub(source, endAt)
	return head .. token_sync.BEGIN_MARKER .. "\n" .. token_sync.renderMetrics(dump.tokens) .. tail, "patched"
end

-- the metrics region as a standalone loadable chunk, so `--check` can read a
-- marker-patched file that also `require`s things a sandbox cannot resolve
function token_sync.extractMetricsChunk(source: string): string?
	local beginAt = string.find(source, token_sync.BEGIN_MARKER, 1, true)
	local endAt = string.find(source, token_sync.END_MARKER, 1, true)
	if beginAt == nil or endAt == nil or endAt < beginAt then
		return nil
	end
	local body = string.sub(source, beginAt + #token_sync.BEGIN_MARKER, endAt - 1)
	return "return {\n" .. body .. "}\n"
end

return token_sync
