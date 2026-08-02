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
-- Scope: the REUSABLE framework surface — src/controls/*, the renderer's
-- layout-node builder, and the presenter's geometry decisions. Examples, tests,
-- and game code are deliberately out of scope: an app author's literal is a
-- legitimate opt-out, and saying so is the point of the escape hatch.
--
-- The mechanism is an ALLOWLIST, not a suppression comment: every intentionally
-- theme-independent literal is listed here with a justification, so the reason
-- lives in one reviewable place instead of scattered through the controls.
--
-- check(opts?) -> { ok, violations, counts }. CLI: run this file directly.

local fs = require("@lune/fs")

local checker = {}

local SCANNED_FILES = { "src/render/renderer.luau", "src/present/presenter.luau" }
local SCANNED_DIRS = { "src/controls" }

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

export type Options = {
	-- inject a synthetic violation for the lint's own negative proof
	injectFile: string?,
	injectLine: string?,
}

function checker.check(opts: Options?)
	local options = opts or {}
	local violations: { { file: string, line: number, what: string, text: string } } = {}
	local files: { string } = {}
	for _, file in SCANNED_FILES do
		table.insert(files, file)
	end
	for _, dir in SCANNED_DIRS do
		local entries = fs.readDir(dir)
		table.sort(entries)
		for _, entry in entries do
			if string.match(entry, "%.luau$") ~= nil then
				table.insert(files, `{dir}/{entry}`)
			end
		end
	end

	local allowed = 0
	local scannedLines = 0
	for _, file in files do
		local source = fs.readFile(file)
		if options.injectFile == file and options.injectLine ~= nil then
			source ..= "\n" .. options.injectLine .. "\n"
		end
		local lineNumber = 0
		for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
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
					what = what,
					text = string.match(line, "^%s*(.-)%s*$") :: string,
				})
			end
		end
	end

	local problems: { string } = {}
	for _, v in violations do
		table.insert(
			problems,
			`{v.file}:{v.line}: hardcoded {v.what} in a reusable framework surface — `
				.. `"{v.text}". Use a theme metric name (a spacing step, a typography role, or a `
				.. `dotted snapshot path such as "targetSizes.minimum"), or add an entry to the `
				.. `ALLOWLIST in tools/lune/check_theme_drift.luau with the reason it is `
				.. `deliberately theme-independent.`
		)
	end

	return {
		ok = #violations == 0,
		problems = problems,
		violations = violations,
		counts = { files = #files, lines = scannedLines, allowlisted = allowed },
	}
end

checker.ALLOWLIST = ALLOWLIST

return checker
