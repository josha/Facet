--!strict
-- Theme DRIFT lint (ADR-0019 §2: "a drift lint fails any reusable framework
-- control that hardcodes a theme-owned metric literal instead of a role").
--
-- Why it exists: the theme system only works if the framework's own controls
-- speak semantic roles. One `height = { type = "fixed", px = 44 }` slipped back
-- into a control is invisible in review, passes every test (44 is still 44 under
-- Studio Neutral), and silently makes that control immune to every theme — the
-- exact failure mode the stage exists to remove. So it is checked mechanically.
--
-- TWO SCOPES, because there are two different claims to make.
--
-- FRAMEWORK scope: the REUSABLE surface — src/controls/*, the renderer's
-- layout-node builder, and the presenter's geometry decisions. Every metric
-- family, no literal, allowlist-only. Nobody reads these files to learn how to
-- write an app, so the reason for an exception belongs in one reviewable place
-- here rather than scattered through the controls.
--
-- EXAMPLE scope: examples/** — added 2026-08-21 by the declarative-purity
-- audit, which is the reason the paragraph that used to sit here is gone. It
-- said game code AND examples were out of scope because "an app author's
-- literal is a legitimate opt-out, and saying so is the point of the escape
-- hatch". That is still exactly right for a game — Rascal Rally and every other
-- consumer stay out of scope, permanently, and this lint will never be pointed
-- at one. It was wrong for the gallery, because the gallery is not an app: it
-- is the reference a reader copies from. The audit measured what the exemption
-- bought — 539 raw literals on the three props the theme system owns, 40% of
-- every such prop in the teaching corpus, against 22% in the shipping game the
-- corpus is supposed to teach — and its verdict was that with no visible house
-- style a reader learns the escape hatch as the idiom.
--
-- The example scope is deliberately NARROWER than the framework one, in two
-- ways, and both are what makes it mechanical rather than a judgement call:
--
--   * it asks about the three prop families the audit measured (`textSize`,
--     `gap`/`rowGap`, `padding`) and no others. A demo canvas that is 300x200,
--     or a probe that offsets by 12, is structure — the audit convicted the
--     spacing-and-type class specifically, and the hit-target floor and the
--     `minColumnWidth` classes are swept by name rather than by grep;
--   * it only fires when a theme NAME RESOLVES TO EXACTLY THAT NUMBER on the
--     neutral snapshot. `gap = 8` is a violation because `"s"` is 8 and the
--     rewrite cannot move one pixel; `gap = 6` is not, because no space step is
--     6 and there is nothing to rewrite it to (the framework concedes this in
--     `snapshot.luau`'s own `label = { gap = 6 }`). That is not a loophole, it
--     is a pending finding: the day the spacing scale grows a rung for 6, this
--     lint starts failing all sixty of those sites for free.
--
-- The vocabulary is READ FROM THE FRAMEWORK (`themes/snapshot` + `themes/package`),
-- never restated, so a package that re-ladders its type scale re-ladders this
-- lint with it.
--
-- THE TWO MARKERS, for the example scope only:
--   `-- THEME-OPT-OUT: <reason>` on the offending line — a literal kept ON
--       PURPOSE, because the fixture's subject IS the escape hatch. The reason
--       lives at the site here rather than in the ALLOWLIST because in this
--       corpus the reader IS reading the file, and "no reader can tell which is
--       the house style" is the whole finding.
--   `-- PROBE-EXEMPT: <reason>` on the line, or as a
--       `-- PROBE-EXEMPT BEGIN: <reason>` / `-- PROBE-EXEMPT END` region — this
--       is instrument, not example. Whole files that are nothing but instrument
--       are listed in PROBE_EXEMPT_FILES below, and that listing is GUARDED: a
--       listed file that does not say so in its own header fails the lint, so an
--       exemption can never go silent on the reader it exists to warn.
--
-- check(opts?) -> { ok, violations, counts }. CLI: run this file directly.

local fs = require("@lune/fs")

local pkg = require("../../src/themes/package")
local snapshot = require("../../src/themes/snapshot")

local checker = {}

-- `layout_node.luau` is the renderer's MEASURE SEAM, split out of `renderer.luau`
-- when it hit the 200k `Source` write cap — it is where nearly every metric a
-- theme owns is resolved, so leaving it unscanned would have opened the exact
-- hole this checker exists to close.
local SCANNED_FILES = {
	"src/render/renderer.luau",
	"src/render/layout_node.luau",
	"src/render/presentation_channel.luau",
	"src/present/presenter.luau",
	-- the anchored-surface seam (navigation-and-menus D1) is a PRESENTER GEOMETRY
	-- DECISION in a file of its own — the gap it stands a surface off its source,
	-- the tail's size and the corner it keeps clear of are all theme-owned, and
	-- leaving a new home for them unscanned would open exactly the hole this
	-- checker exists to close. (`src/layout/anchor_placement.luau` is deliberately
	-- NOT here: it is pure arithmetic that takes every distance as an argument, so
	-- it owns no metric to drift.)
	"src/present/anchored.luau",
	-- ...and its two D3 consumers, for the same reason: the help plate resolves
	-- the spacing step it wraps inside, and the callout queue is the only other
	-- file outside `src/controls` that builds a presented plate.
	"src/present/help_plate.luau",
	"src/present/callout_queue.luau",
}
local SCANNED_DIRS = { "src/controls" }

-- the TEACHING corpus, scanned recursively. `examples/themes` is in here too:
-- a theme package authoring `space = { xs = 4 }` is the declarative act for a
-- theme and names no prop this scope asks about, so it needs no carve-out.
local EXAMPLE_DIRS = { "examples" }

-- WHOLE FILES that are instrument rather than example. Each is listed with the
-- reason, and each must SAY SO IN ITS OWN HEADER (see PROBE_HEADER_WINDOW) —
-- the list decides the lint, the header decides what the reader is told, and a
-- listing without a header is itself a violation.
local PROBE_EXEMPT_FILES: { { file: string, why: string } } = {
	{
		file = "examples/gallery/scenarios/probe.luau",
		why = "the verification surface's self-test: its geometry IS the frozen baseline ledger row "
			.. "NS-A2 captures, so every number in it must be immune to a theme swap by construction",
	},
}
-- THE BAR FOR THIS LIST IS DELIBERATELY HIGH, and "it is instrument, not
-- example" is NOT enough to clear it on its own — the perf lab's overlay and
-- levers say that about themselves in their own headers and are swept anyway,
-- because naming a spacing step there costs the instrument nothing. A file
-- earns a listing only when the LITERAL IS LOAD-BEARING FOR THE INSTRUMENT:
-- naming it would let a theme swap move the very thing being measured or
-- frozen. Everything else that is merely mistakable for example code gets the
-- reader-facing `-- PROBE-EXEMPT:` marker at the site — see the thirteen sites
-- the 2026-08-21 audit flagged — which tells the reader without pretending the
-- number could not have been a token.
local PROBE_HEADER_WINDOW = 40

-- the example scope's marker vocabulary. A marker carries a REASON or it is not
-- a marker: `-- PROBE-EXEMPT` alone would be a suppression comment, which is the
-- thing the framework scope's allowlist exists to avoid.
local MARKER_MIN_REASON = 12
local OPT_OUT_MARKER = "THEME%-OPT%-OUT:%s*(.+)$"
local PROBE_LINE_MARKER = "PROBE%-EXEMPT:%s*(.+)$"
local PROBE_BEGIN_MARKER = "PROBE%-EXEMPT BEGIN:%s*(.+)$"
local PROBE_END_MARKER = "PROBE%-EXEMPT END"

-- THE THREE PROP FAMILIES THE AUDIT MEASURED, and the vocabulary each one
-- names. `textSize` takes a typography ROLE; the spacing family takes a space
-- STEP. Zero stays legal for the spacing family for the same reason it does in
-- the framework scope: `gap = 0` is a structural statement, not a style value.
local EXAMPLE_ASSIGNMENTS: { { pattern: string, what: string, vocabulary: string } } = {
	{ pattern = "textSize%s*=%s*(%-?[1-9]%d*)", what = "textSize", vocabulary = "type" },
	{ pattern = "[^%w_]gap%s*=%s*(%-?[1-9]%d*)", what = "gap", vocabulary = "space" },
	{ pattern = "rowGap%s*=%s*(%-?[1-9]%d*)", what = "rowGap", vocabulary = "space" },
	{ pattern = "padding%s*=%s*(%-?[1-9]%d*)", what = "padding", vocabulary = "space" },
}

-- value -> the names that resolve to it, READ FROM THE FRAMEWORK. Ladder order
-- is the framework's own, so the primary role wins the number it shares with a
-- derived one (`control` 18 over `numeral` 18, `s` 8 over the derived `gutter`).
local NAMES_FOR: { [string]: { [number]: { string } } } = { type = {}, space = {} }
do
	local neutral = snapshot.neutral()
	local function add(vocabulary: string, value: any, name: string)
		if type(value) ~= "number" then
			return
		end
		local bucket = NAMES_FOR[vocabulary]
		if bucket[value] == nil then
			bucket[value] = {}
		end
		table.insert(bucket[value], name)
	end
	for _, role in pkg.TYPE_ROLES do
		local entry = snapshot.roleOf(neutral, role)
		add("type", if entry ~= nil then entry.size else nil, role)
	end
	for _, step in pkg.SPACE_STEPS do
		add("space", snapshot.resolveNumber(neutral, step), step)
	end
end

-- assignment contexts where a bare number IS a theme-owned metric. Each pattern
-- must anchor on the field name so ordinary arithmetic is not swept up.
-- ZERO is never a theme metric. `padding = 0` / `gap = 0` mean "this container
-- adds no spacing of its own", which is a structural statement about the layout,
-- not a style value a theme should be able to inflate.
local METRIC_ASSIGNMENTS: { { pattern: string, what: string } } = {
	{ pattern = "textSize%s*=%s*%-?[1-9]%d*", what = "textSize" },
	{ pattern = "[^%w_]gap%s*=%s*%-?[1-9]%d*", what = "gap" },
	{ pattern = "[^%w_]px%s*=%s*%-?[1-9]%d*", what = "dimension px" },
	{ pattern = "[^%w_]min%s*=%s*%-?[1-9]%d*", what = "dimension min" },
	{ pattern = "[^%w_]max%s*=%s*%-?[1-9]%d*", what = "dimension max" },
	{ pattern = "preferred%s*=%s*%-?[1-9]%d*", what = "dimension preferred" },
	{ pattern = "padding%s*=%s*%-?[1-9]%d*", what = "padding" },
	{ pattern = "offsetX%s*=%s*%-?[1-9]%d*", what = "offsetX" },
	{ pattern = "offsetY%s*=%s*%-?[1-9]%d*", what = "offsetY" },
	{ pattern = "iconSize%s*=%s*%-?[1-9]%d*", what = "iconSize" },
	{ pattern = "thickness%s*=%s*%-?[1-9]%d*", what = "thickness" },
	{ pattern = "[^%w_]height%s*=%s*%-?[1-9]%d*", what = "height" },
	{ pattern = "[^%w_]width%s*=%s*%-?[1-9]%d*", what = "width" },
	{ pattern = "[^%w_]top%s*=%s*%-?[1-9]%d*", what = "inset top" },
	{ pattern = "[^%w_]bottom%s*=%s*%-?[1-9]%d*", what = "inset bottom" },
	{ pattern = "[^%w_]left%s*=%s*%-?[1-9]%d*", what = "inset left" },
	{ pattern = "[^%w_]right%s*=%s*%-?[1-9]%d*", what = "inset right" },
}

-- the pattern above cannot express alternation in Lua patterns; the constant
-- check runs separately over these suffix words
local CONSTANT_WORDS =
	{ "HEIGHT", "WIDTH", "SIZE", "GAP", "INSET", "MARGIN", "PADDING", "RADIUS", "FLOOR", "THUMB", "TRACK" }

-- INTENTIONALLY theme-independent literals. `match` is a plain substring of the
-- offending source line; `why` is the standing justification.
local ALLOWLIST: { { file: string, match: string, why: string } } = {
	{
		file = "src/controls/text_input.luau",
		match = "local KEEP_VISIBLE_MARGIN = 8",
		why = "the safety gap between a field and the ENGINE's on-screen keyboard — a platform "
			.. "distance, not a style choice; a theme must not be able to push a field under the keyboard",
	},
	{
		file = "src/controls/table.luau",
		match = 'width = { type = "fixed", px = 1 }',
		why = "a 1px structural spacer column, not a hairline: it exists so the grid has a "
			.. "measurable zero-width slot, and a theme retuning strokes must not widen it",
	},
	{
		file = "src/render/renderer.luau",
		match = "math.max(r.w, floor)",
		why = "hit-rect arithmetic over the ALREADY theme-resolved floor",
	},
}

-- lines that are pure comments or inside a block comment carry no code
local function isComment(line: string): boolean
	local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
	return string.sub(trimmed, 1, 2) == "--"
end

-- the example corpus is ~70,000 lines and `check()` is called once per mutation
-- case, so the file LIST and the file BYTES are read once per process. Nothing
-- here is mutated between calls; injection is applied to a copy.
local exampleFileCache: { string }? = nil
local sourceCache: { [string]: string } = {}

local function readSource(file: string): string
	local cached = sourceCache[file]
	if cached == nil then
		cached = fs.readFile(file)
		sourceCache[file] = cached
	end
	return cached
end

local function exampleFiles(): { string }
	if exampleFileCache ~= nil then
		return exampleFileCache
	end
	local found: { string } = {}
	local function walk(dir: string)
		local names = fs.readDir(dir)
		table.sort(names)
		for _, entry in names do
			local full = `{dir}/{entry}`
			if fs.isDir(full) then
				walk(full)
			elseif string.match(entry, "%.luau$") ~= nil then
				table.insert(found, full)
			end
		end
	end
	for _, dir in EXAMPLE_DIRS do
		if fs.isDir(dir) then
			walk(dir)
		end
	end
	exampleFileCache = found
	return found
end

local function probeExemptEntry(list: { { file: string, why: string } }, file: string)
	for _, entry in list do
		if entry.file == file then
			return entry
		end
	end
	return nil
end

-- a marker only counts when it carries a reason of its own
local function markerReason(line: string, pattern: string): string?
	local reason = string.match(line, pattern)
	if reason == nil then
		return nil
	end
	local trimmed = string.match(reason, "^%s*(.-)%s*$") :: string
	return if #trimmed >= MARKER_MIN_REASON then trimmed else nil
end

export type Options = {
	-- inject a synthetic violation for the lint's own negative proof. The string
	-- may contain newlines, so a marker COMMENT plus the line it excuses can be
	-- planted as one unit.
	injectFile: string?,
	injectLine: string?,
	-- drive PROBE_EXEMPT_FILES from a case, so both directions of the listing AND
	-- of its header guard can be proved against real files in the corpus
	probeExemptFiles: { { file: string, why: string } }?,
}

export type Violation = { file: string, line: number, scope: string, what: string, text: string }

function checker.check(opts: Options?)
	local options = opts or {}
	local violations: { Violation } = {}
	local frameworkFiles: { string } = {}
	for _, file in SCANNED_FILES do
		table.insert(frameworkFiles, file)
	end
	for _, dir in SCANNED_DIRS do
		local entries = fs.readDir(dir)
		table.sort(entries)
		for _, entry in entries do
			if string.match(entry, "%.luau$") ~= nil then
				table.insert(frameworkFiles, `{dir}/{entry}`)
			end
		end
	end

	local allowed = 0
	local scannedLines = 0
	local exampleLines = 0
	local optedOut = 0
	local probeSuppressed = 0
	local probeFiles = 0

	local probeList = options.probeExemptFiles or PROBE_EXEMPT_FILES

	local function sourceOf(file: string): string
		local source = readSource(file)
		if options.injectFile == file and options.injectLine ~= nil then
			source ..= "\n" .. options.injectLine .. "\n"
		end
		return source
	end

	-- ===== the FRAMEWORK scope ==============================================
	for _, file in frameworkFiles do
		local lineNumber = 0
		for line in string.gmatch(sourceOf(file) .. "\n", "([^\n]*)\n") do
			lineNumber += 1
			scannedLines += 1
			if isComment(line) then
				continue
			end
			local what: string? = nil
			for _, rule in METRIC_ASSIGNMENTS do
				if string.find(line, rule.pattern) ~= nil then
					what = rule.what
					break
				end
			end
			if what == nil then
				local name = string.match(line, "^%s*local%s+([%u][%u_]*)%s*=%s*%-?[1-9]%d*")
				if name ~= nil then
					for _, word in CONSTANT_WORDS do
						if string.find(name, word, 1, true) ~= nil then
							what = "named metric constant"
							break
						end
					end
				end
			end
			if what == nil then
				continue
			end
			local suppressed = false
			for _, entry in ALLOWLIST do
				if entry.file == file and string.find(line, entry.match, 1, true) ~= nil then
					suppressed = true
					allowed += 1
					break
				end
			end
			if not suppressed then
				table.insert(violations, {
					file = file,
					line = lineNumber,
					scope = "framework",
					what = what,
					text = string.match(line, "^%s*(.-)%s*$") :: string,
				})
			end
		end
	end

	-- ===== the EXAMPLE scope ================================================
	for _, file in exampleFiles() do
		local source = sourceOf(file)
		local exempt = probeExemptEntry(probeList, file)
		local lineNumber = 0
		local inProbeRegion = false
		local openedAt: number? = nil
		-- A MARKER ALSO READS FORWARD FROM A COMMENT, because the reason a literal
		-- is deliberate rarely fits after it on the same line — and a reason that
		-- had to be truncated to fit is the suppression comment this mechanism is
		-- trying not to be. ONE MARKER COVERS ONE LITERAL: the pending reason is
		-- CONSUMED by the first line it excuses (and dropped at the first blank
		-- line), so a marker written for one number in a long table constructor
		-- cannot silently go on excusing every number under it.
		local pendingOptOut: string? = nil
		local pendingProbe: string? = nil
		for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
			lineNumber += 1
			exampleLines += 1
			if markerReason(line, PROBE_BEGIN_MARKER) ~= nil then
				inProbeRegion = true
				openedAt = lineNumber
				continue
			end
			if string.find(line, PROBE_END_MARKER) ~= nil then
				inProbeRegion = false
				openedAt = nil
				continue
			end
			if isComment(line) then
				local optOut = markerReason(line, OPT_OUT_MARKER)
				if optOut ~= nil then
					pendingOptOut = optOut
				end
				local probe = markerReason(line, PROBE_LINE_MARKER)
				if probe ~= nil then
					pendingProbe = probe
				end
				continue
			end
			if string.match(line, "^%s*$") ~= nil then
				pendingOptOut, pendingProbe = nil, nil
				continue
			end
			-- EVERY rule, never the first that matches: `UI.HStack{ gap = 6,
			-- padding = 16 }` has one nameable literal and one that is not, and a
			-- loop that stopped at the first hit would report neither.
			local found: { { what: string, value: number, name: string } } = {}
			for _, rule in EXAMPLE_ASSIGNMENTS do
				local captured = string.match(line, rule.pattern)
				local n = if captured ~= nil then tonumber(captured) else nil
				local resolves = if n ~= nil then NAMES_FOR[rule.vocabulary][n] else nil
				if resolves ~= nil then
					table.insert(found, { what = rule.what, value = n :: number, name = resolves[1] })
				end
			end
			if #found == 0 then
				continue
			end
			-- exemptions, most specific first
			if exempt ~= nil then
				probeSuppressed += #found
				continue
			end
			if inProbeRegion or pendingProbe ~= nil or markerReason(line, PROBE_LINE_MARKER) ~= nil then
				probeSuppressed += #found
				pendingProbe = nil
				continue
			end
			if pendingOptOut ~= nil or markerReason(line, OPT_OUT_MARKER) ~= nil then
				optedOut += #found
				pendingOptOut = nil
				continue
			end
			for _, hit in found do
				table.insert(violations, {
					file = file,
					line = lineNumber,
					scope = "example",
					what = `{hit.what} = {tostring(hit.value)}, which "{hit.name}" already names`,
					text = string.match(line, "^%s*(.-)%s*$") :: string,
				})
			end
		end
		if inProbeRegion then
			table.insert(violations, {
				file = file,
				line = openedAt or 0,
				scope = "example",
				what = "an unclosed PROBE-EXEMPT BEGIN region (no `-- PROBE-EXEMPT END` follows it)",
				text = "PROBE-EXEMPT BEGIN",
			})
		end
		if exempt ~= nil then
			probeFiles += 1
			-- THE GUARD: a listed file must warn its own reader in its own header
			local header = ""
			local seen = 0
			for headerLine in string.gmatch(source .. "\n", "([^\n]*)\n") do
				seen += 1
				header ..= headerLine .. "\n"
				if seen >= PROBE_HEADER_WINDOW then
					break
				end
			end
			if string.find(header, "PROBE-EXEMPT", 1, true) == nil then
				table.insert(violations, {
					file = file,
					line = 1,
					scope = "example",
					what = "a PROBE_EXEMPT_FILES listing with no `-- PROBE-EXEMPT` line in its own header — "
						.. "the exemption is invisible to the reader it exists to warn",
					text = "(file header)",
				})
			end
		end
	end

	local problems: { string } = {}
	for _, v in violations do
		if v.scope == "example" then
			table.insert(
				problems,
				`{v.file}:{v.line}: [example] {v.what} — "{v.text}". The teaching corpus spells a `
					.. `theme-owned value with the name the theme system already has, because a reader `
					.. `copies what the gallery writes. Name it, or — if this literal is the point — `
					.. `mark it "-- THEME-OPT-OUT: <reason>", or "-- PROBE-EXEMPT: <reason>" if the line `
					.. `is instrument rather than example.`
			)
		else
			table.insert(
				problems,
				`{v.file}:{v.line}: hardcoded {v.what} in a reusable framework surface — `
					.. `"{v.text}". Use a theme metric name (a spacing step, a typography role, or a `
					.. `dotted snapshot path such as "targetSizes.minimum"), or add an entry to the `
					.. `ALLOWLIST in tools/lune/check_theme_drift.luau with the reason it is `
					.. `deliberately theme-independent.`
			)
		end
	end

	return {
		ok = #violations == 0,
		problems = problems,
		violations = violations,
		counts = {
			files = #frameworkFiles,
			lines = scannedLines,
			allowlisted = allowed,
			exampleFiles = #exampleFiles(),
			exampleLines = exampleLines,
			optedOut = optedOut,
			probeSuppressed = probeSuppressed,
			probeExemptFiles = probeFiles,
		},
	}
end

checker.ALLOWLIST = ALLOWLIST
checker.PROBE_EXEMPT_FILES = PROBE_EXEMPT_FILES
checker.NAMES_FOR = NAMES_FOR

return checker
