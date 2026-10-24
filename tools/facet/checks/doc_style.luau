--!strict
local Verify = require("../../vendor/verify/src/core")

local stringext = require("@std/stringext")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Rule = require("../lib/rule")

local SCANNED_DIRECTORIES = { "docs/guide", "docs/extending" }
local SCANNED_FILES = { "README.md", "docs/MAINTAINERS.md" }
local GUIDE = "docs/guide/"

local ARCHAEOLOGY_EXEMPT: { [string]: boolean } = {
	["docs/guide/choosing-facet.md"] = true,
	["docs/guide/device-verification.md"] = true,
}

type Archaeology = { pattern: string, folded: boolean, reason: string }

local ARCHAEOLOGY: { Archaeology } = {
	{
		pattern = "%f[%w_]20%d%d%-%d%d%-%d%d%f[^%w_]",
		folded = false,
		reason = "a date literal dates the page; say what is true instead of when it became true",
	},
	{
		pattern = "%f[%w_]directors?%f[^%w_]",
		folded = true,
		reason = "names an internal reviewer; state the rule, not who asked for it",
	},
	{
		pattern = "%f[%w_]rulings?%f[^%w_]",
		folded = true,
		reason = "internal process vocabulary; call it a rule, or just state it",
	},
	{
		pattern = "%f[%w_]missions?%f[^%w_]",
		folded = true,
		reason = "internal process vocabulary; say what the work produced",
	},
}

local MAX_INSTRUCTION_WORDS = 20
local MAX_SENTENCE_WORDS = 25

local COMMON: { [string]: boolean } = {}
for _, word in
	string.split(
		"UI API ID IDS URL URI JSON XML HTML CSS CPU GPU RAM KB MB GB MS FPS DPI PPI RGB HTTP HTTPS IP USB TV VR AR "
			.. "OS PNG JPG SVG ASCII UTF LZ CSV CLI SDK IDE HUD TODO FAQ WASD DPAD LED AI NPC",
		" "
	)
do
	COMMON[word] = true
end

local NEEDS_EXPANSION: { [string]: string } = {
	IAS = "Input Action System",
	CAS = "ContextActionService",
	UIS = "UserInputService",
	MCP = "Model Context Protocol",
	VM = "virtual machine",
	REPL = "read-eval-print loop",
	CDN = "content delivery network",
	GA = "general availability",
	SF = "the framework icon set",
}

local SHORTHAND_ALLOW: { [string]: boolean } = {
	L1 = true,
	L2 = true,
	R1 = true,
	R2 = true,
	F6 = true,
	F10 = true,
	P1 = true,
	UTF8 = true,
	["UTF-8"] = true,
	["UTF-16"] = true,
}

local AUXILIARIES: { [string]: boolean } = {
	is = true,
	are = true,
	was = true,
	were = true,
	be = true,
	been = true,
	being = true,
}

local PASSIVE_SKIP: { [string]: boolean } = {
	used = true,
	based = true,
	named = true,
	called = true,
	fixed = true,
	closed = true,
	open = true,
	needed = true,
	allowed = true,
	supposed = true,
	intended = true,
	limited = true,
}

local EM_DASH = "\u{2014}"

export type Report = { failures: { string }, warnings: { string } }

local function isWordByte(byte: number?): boolean
	if byte == nil then
		return false
	end
	return (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95
end

local function isUpperByte(byte: number?): boolean
	return byte ~= nil and byte >= 65 and byte <= 90
end

local function isDigitByte(byte: number?): boolean
	return byte ~= nil and byte >= 48 and byte <= 57
end

local function isSpaceByte(byte: number?): boolean
	return byte ~= nil and (byte == 32 or (byte >= 9 and byte <= 13))
end

local function wordEnd(text: string, start: number): number
	local finish = start
	while isWordByte(string.byte(text, finish)) do
		finish += 1
	end
	return finish
end

local function skipSpaces(text: string, position: number): number
	local cursor = position
	while isSpaceByte(string.byte(text, cursor)) do
		cursor += 1
	end
	return cursor
end

local function replacePlain(text: string, needle: string): string
	local escaped = string.gsub(needle, "%p", "%%%0")
	local replaced = string.gsub(text, escaped, "")
	return replaced
end

local function readableLines(text: string): { string }
	local readable: { string } = {}
	local fenced = false
	for index, raw in string.split(text, "\n") do
		local stripped = string.match(raw, "^%s*(.*)$") or raw
		if string.sub(stripped, 1, 3) == "```" then
			fenced = not fenced
			readable[index] = ""
		elseif fenced then
			readable[index] = ""
		else
			local prose = string.gsub(raw, "`[^`]*`", "CODE")
			prose = string.gsub(prose, "<kbd>[^<]*</kbd>", "KEY")
			prose = string.gsub(prose, "%[([^%]]*)%]%([^)]*%)", "%1")
			prose = string.gsub(prose, "<https?://[^>]*>", "LINK")
			prose = string.gsub(prose, "https?://%S+", "LINK")
			prose = string.gsub(prose, "<!%-%-.-%-%->", "")
			prose = replacePlain(prose, "**")
			prose = replacePlain(prose, "__")
			readable[index] = prose
		end
	end
	return readable
end

local function countWords(text: string): number
	local count = 0
	for _ in string.gmatch(text, "[%w][%w'/._%-]*") do
		count += 1
	end
	return count
end

local function boundedAt(text: string, start: number, finish: number): boolean
	return not isWordByte(string.byte(text, start - 1)) and not isWordByte(string.byte(text, finish + 1))
end

local function expansionBefore(flat: string, acronym: string, expansion: string): number?
	local searched = string.lower(flat)
	local loweredAcronym = string.lower(acronym)
	local loweredExpansion = string.lower(expansion)
	local earliest: number? = nil
	local cursor = 1
	while true do
		local start, finish = string.find(searched, loweredExpansion, cursor, true)
		if start == nil or finish == nil then
			break
		end
		local position = skipSpaces(searched, finish + 1)
		if string.sub(searched, position, position) == "(" then
			position = skipSpaces(searched, position + 1)
			if string.sub(searched, position, position + #loweredAcronym - 1) == loweredAcronym then
				position = skipSpaces(searched, position + #loweredAcronym)
				if string.sub(searched, position, position) == ")" then
					earliest = start
					break
				end
			end
		end
		cursor = start + 1
	end
	cursor = 1
	while true do
		local start, finish = string.find(searched, loweredAcronym, cursor, true)
		if start == nil or finish == nil then
			break
		end
		if earliest ~= nil and start >= earliest then
			break
		end
		if boundedAt(searched, start, finish) then
			local position = skipSpaces(searched, finish + 1)
			if string.sub(searched, position, position + #EM_DASH - 1) == EM_DASH then
				position += #EM_DASH
			elseif string.sub(searched, position, position) == "-" then
				position += 1
			end
			position = skipSpaces(searched, position)
			if string.sub(searched, position, position) == "(" then
				position = skipSpaces(searched, position + 1)
				if string.sub(searched, position, position + #loweredExpansion - 1) == loweredExpansion then
					earliest = start
					break
				end
			end
		end
		cursor = start + 1
	end
	return earliest
end

local function expansionLines(readable: { string }): { [string]: number }
	local offsets: { number } = {}
	local position = 1
	for index, prose in readable do
		offsets[index] = position
		position += #prose + 1
	end
	local flat = table.concat(readable, " ")
	local found: { [string]: number } = {}
	for acronym, expansion in NEEDS_EXPANSION do
		local start = expansionBefore(flat, acronym, expansion)
		if start ~= nil then
			local line = 1
			for index, offset in offsets do
				if offset <= start then
					line = index
				else
					break
				end
			end
			found[acronym] = line
		end
	end
	return found
end

local function acronyms(prose: string): { string }
	local found: { string } = {}
	for token in string.gmatch(prose, "%f[%w_](%u+)%f[^%w_]") do
		if #token >= 2 and #token <= 6 then
			table.insert(found, token)
		end
	end
	return found
end

type Shorthand = { token: string, stem: string }

local function shorthandAt(prose: string, start: number): (Shorthand?, number)
	local letters = 0
	while letters < 5 and isUpperByte(string.byte(prose, start + letters)) do
		letters += 1
	end
	for stemLength = letters, 1, -1 do
		local afterStem = start + stemLength
		local hyphenOptions: { number } = if string.sub(prose, afterStem, afterStem) == "-" then { 1, 0 } else { 0 }
		for _, hyphen in hyphenOptions do
			local afterHyphen = afterStem + hyphen
			local letterOptions: { number } = if isUpperByte(string.byte(prose, afterHyphen)) then { 1, 0 } else { 0 }
			for _, letter in letterOptions do
				local digitsStart = afterHyphen + letter
				local digits = 0
				while digits < 3 and isDigitByte(string.byte(prose, digitsStart + digits)) do
					digits += 1
				end
				for digitCount = digits, 1, -1 do
					local finish = digitsStart + digitCount - 1
					if not isWordByte(string.byte(prose, finish + 1)) then
						return {
							token = string.sub(prose, start, finish),
							stem = string.sub(prose, start, start + stemLength - 1),
						},
							finish + 1
					end
				end
			end
		end
	end
	return nil, start + 1
end

local function shorthands(prose: string): { Shorthand }
	local found: { Shorthand } = {}
	local cursor = 1
	while cursor <= #prose do
		local byte = string.byte(prose, cursor)
		if isUpperByte(byte) and not isWordByte(string.byte(prose, cursor - 1)) then
			local match, nextCursor = shorthandAt(prose, cursor)
			if match ~= nil then
				table.insert(found, match)
			end
			cursor = nextCursor
		else
			cursor += 1
		end
	end
	return found
end

local function sentences(prose: string): { string }
	local text = stringext.trim(prose)
	local found: { string } = {}
	local start = 1
	local cursor = 1
	while cursor <= #text do
		local byte = string.byte(text, cursor)
		if isSpaceByte(byte) then
			local previous = string.sub(text, cursor - 1, cursor - 1)
			local finish = skipSpaces(text, cursor)
			if previous == "." or previous == "!" or previous == "?" then
				table.insert(found, string.sub(text, start, cursor - 1))
				start = finish
			end
			cursor = finish
		else
			cursor += 1
		end
	end
	table.insert(found, string.sub(text, start))
	return found
end

local function endsWith(word: string, suffix: string): boolean
	return string.sub(string.lower(word), -#suffix) == suffix
end

local function participle(word: string): boolean
	return #word >= 3 and (endsWith(word, "ed") or endsWith(word, "en"))
end

type Passive = { phrase: string, verb: string }

local function passiveAt(prose: string, start: number): (Passive?, number)
	local auxiliaryEnd = wordEnd(prose, start)
	local auxiliary = string.lower(string.sub(prose, start, auxiliaryEnd - 1))
	if not AUXILIARIES[auxiliary] or not isSpaceByte(string.byte(prose, auxiliaryEnd)) then
		return nil, auxiliaryEnd
	end
	local secondStart = skipSpaces(prose, auxiliaryEnd)
	local secondEnd = wordEnd(prose, secondStart)
	local second = string.sub(prose, secondStart, secondEnd - 1)
	if second == "" then
		return nil, auxiliaryEnd
	end
	if #second >= 3 and endsWith(second, "ly") and isSpaceByte(string.byte(prose, secondEnd)) then
		local thirdStart = skipSpaces(prose, secondEnd)
		local thirdEnd = wordEnd(prose, thirdStart)
		local third = string.sub(prose, thirdStart, thirdEnd - 1)
		if participle(third) then
			return { phrase = string.sub(prose, start, thirdEnd - 1), verb = third }, thirdEnd
		end
	end
	if participle(second) then
		return { phrase = string.sub(prose, start, secondEnd - 1), verb = second }, secondEnd
	end
	return nil, auxiliaryEnd
end

local function passives(prose: string): { Passive }
	local found: { Passive } = {}
	local cursor = 1
	while cursor <= #prose do
		if isWordByte(string.byte(prose, cursor)) and not isWordByte(string.byte(prose, cursor - 1)) then
			local match, nextCursor = passiveAt(prose, cursor)
			if match ~= nil then
				table.insert(found, match)
				cursor = nextCursor
			else
				cursor += 1
			end
		else
			cursor += 1
		end
	end
	return found
end

local function archaeology(prose: string): { { text: string, reason: string } }
	local found: { { text: string, reason: string } } = {}
	local lowered = string.lower(prose)
	for _, entry in ARCHAEOLOGY do
		local subject = if entry.folded then lowered else prose
		local start, finish = string.find(subject, entry.pattern)
		if start ~= nil and finish ~= nil then
			table.insert(found, { text = string.sub(prose, start, finish), reason = entry.reason })
		end
	end
	return found
end

local function checkDocument(path: string, text: string, report: Report)
	local readable = readableLines(text)
	local expandedAt = expansionLines(readable)
	local reported: { [string]: boolean } = {}
	local guide = string.sub(path, 1, #GUIDE) == GUIDE and not ARCHAEOLOGY_EXEMPT[path]
	for line, prose in readable do
		if stringext.trim(prose) == "" then
			continue
		end
		for _, token in acronyms(prose) do
			local expansion = NEEDS_EXPANSION[token]
			local expanded = expandedAt[token]
			if expansion ~= nil and not reported[token] and (expanded == nil or expanded > line) then
				table.insert(
					report.failures,
					("%s:%d: acronym '%s' is used before it is expanded (write \"%s (%s)\" at first use)"):format(
						path,
						line,
						token,
						expansion,
						token
					)
				)
				reported[token] = true
			end
		end
		for _, match in shorthands(prose) do
			if SHORTHAND_ALLOW[match.token] or SHORTHAND_ALLOW[match.stem] or COMMON[string.upper(match.token)] then
				continue
			end
			table.insert(
				report.failures,
				("%s:%d: '%s' is internal shorthand (an artifact row, phase or finding code). Say what it means, or put an exact identifier in inline code"):format(
					path,
					line,
					match.token
				)
			)
		end
		local step = string.match(prose, "^%s*%d+%.%s+(%S.*)$")
		if step ~= nil then
			local count = countWords(step)
			if count > MAX_INSTRUCTION_WORDS then
				table.insert(
					report.failures,
					("%s:%d: numbered step is %d words (limit %d). Split it so each step carries one instruction"):format(
						path,
						line,
						count,
						MAX_INSTRUCTION_WORDS
					)
				)
			end
		end
		if guide then
			for _, found in archaeology(prose) do
				table.insert(
					report.failures,
					("%s:%d: '%s' %s %s"):format(path, line, found.text, EM_DASH, found.reason)
				)
			end
		end
		for _, sentence in sentences(prose) do
			local count = countWords(sentence)
			if count > MAX_SENTENCE_WORDS then
				table.insert(
					report.warnings,
					("%s:%d: sentence is %d words (target %d)"):format(path, line, count, MAX_SENTENCE_WORDS)
				)
			end
		end
		for _, match in passives(prose) do
			if not PASSIVE_SKIP[string.lower(match.verb)] then
				table.insert(report.warnings, ("%s:%d: likely passive voice: '%s'"):format(path, line, match.phrase))
			end
		end
	end
end

local function documents(context: Rule.Context): { string }
	local found: { string } = {}
	for _, directory in SCANNED_DIRECTORIES do
		for _, entry in Files.list(context.path(directory)) do
			if string.sub(entry.name, -3) == ".md" and Files.isFile(context.path(directory .. "/" .. entry.name)) then
				table.insert(found, directory .. "/" .. entry.name)
			end
		end
	end
	for _, file in SCANNED_FILES do
		if Files.isFile(context.path(file)) then
			table.insert(found, file)
		end
	end
	return found
end

local function inspect(context: Rule.Context): Report
	local report: Report = { failures = {}, warnings = {} }
	for _, document in documents(context) do
		checkDocument(document, Files.text(context.path(document)), report)
	end
	return report
end

local function check(context: Rule.Context): { string }
	return inspect(context).failures
end

local function probe(test: Verify.Context, body: string, path: string?): Report
	local relative = path or "docs/guide/style_probe_tmp.md"
	local report: Report = { failures = {}, warnings = {} }
	Rule.within(test, { [relative] = "# Probe\n\n" .. body }, function(context)
		report = inspect(context)
		return
	end)
	return report
end

local function reports(test: Verify.Context, body: string, fragment: string, path: string?)
	Verify.expect(table.concat(probe(test, body, path).failures, "\n")):toContain(fragment)
end

local function passes(test: Verify.Context, body: string, path: string?)
	Verify.expect(probe(test, body, path).failures):toEqual({})
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "an over-long numbered step is reported", {
		id = prefix .. "an over-long numbered step is reported",
		run = function(test: Verify.Context)
			reports(
				test,
				"1. Open the place file, then find the client script, then read the mount call, then change the theme name, then save it and publish.\n",
				"numbered step is"
			)
		end,
	})
	harness:case(prefix .. "an unexpanded acronym is reported", {
		id = prefix .. "an unexpanded acronym is reported",
		run = function(test: Verify.Context)
			reports(test, "Turn on IAS before you mount anything.\n", "acronym 'IAS'")
		end,
	})
	harness:case(prefix .. "an acronym expanded at its first use passes", {
		id = prefix .. "an acronym expanded at its first use passes",
		run = function(test: Verify.Context)
			passes(test, "Turn on the Input Action System (IAS) first. Then IAS reads each binding.\n")
		end,
	})
	harness:case(prefix .. "an acronym expanded only after its first use is reported", {
		id = prefix .. "an acronym expanded only after its first use is reported",
		run = function(test: Verify.Context)
			reports(
				test,
				"Turn on IAS first.\n\nThe Input Action System (IAS) reads each binding.\n",
				"probe_tmp.md:3: acronym 'IAS'"
			)
		end,
	})
	harness:case(prefix .. "a bare artifact row ID is reported", {
		id = prefix .. "a bare artifact row ID is reported",
		run = function(test: Verify.Context)
			reports(test, "This behaviour is pinned by row TP-A12 in the ledger.\n", "'TP-A12' is internal shorthand")
		end,
	})
	harness:case(prefix .. "a bare contract ID is reported", {
		id = prefix .. "a bare contract ID is reported",
		run = function(test: Verify.Context)
			reports(test, "The contract themes-P5-41 still fails.\n", "'P5' is internal shorthand")
		end,
	})
	harness:case(prefix .. "a date literal in a guide chapter is reported", {
		id = prefix .. "a date literal in a guide chapter is reported",
		run = function(test: Verify.Context)
			reports(
				test,
				"The default flipped on 2026-08-21 and has stayed that way.\n",
				"'2026-08-21' " .. EM_DASH .. " a date literal dates the page"
			)
		end,
	})
	harness:case(prefix .. "an internal reviewer named in a guide chapter is reported", {
		id = prefix .. "an internal reviewer named in a guide chapter is reported",
		run = function(test: Verify.Context)
			reports(
				test,
				"The Director asked for the taller row, so the theme grew one.\n",
				"'Director' " .. EM_DASH .. " names an internal reviewer"
			)
		end,
	})
	harness:case(prefix .. "archaeology outside the guide and in an exempt chapter passes", {
		id = prefix .. "archaeology outside the guide and in an exempt chapter passes",
		run = function(test: Verify.Context)
			passes(test, "The default flipped on 2026-08-21.\n", "docs/extending/probe.md")
			passes(test, "The default flipped on 2026-08-21.\n", "docs/guide/device-verification.md")
		end,
	})
	harness:case(prefix .. "an identifier in inline code passes", {
		id = prefix .. "an identifier in inline code passes",
		run = function(test: Verify.Context)
			passes(test, "The contract `themes-P5-41` and the blocker `B1` still fail.\n")
		end,
	})
	harness:case(prefix .. "a standard text encoding and an allowed key name pass", {
		id = prefix .. "a standard text encoding and an allowed key name pass",
		run = function(test: Verify.Context)
			passes(test, "The tool reads each file as UTF-8 text. Press L1 or F10.\n")
		end,
	})
	harness:case(prefix .. "text in a code fence, a link target and a comment passes", {
		id = prefix .. "text in a code fence, a link target and a comment passes",
		run = function(test: Verify.Context)
			passes(
				test,
				"```\nTurn on IAS at 2026-01-01 with TP-A12.\n```\n\nRead [the page](docs/TP-A12.md). <!-- IAS -->\n"
			)
		end,
	})
	harness:case(prefix .. "an over-long sentence and passive voice are warnings, not findings", {
		id = prefix .. "an over-long sentence and passive voice are warnings, not findings",
		run = function(test: Verify.Context)
			local long = string.rep("word ", 30) .. "end."
			local report = probe(test, long .. " The value is quickly computed. It was used.\n")
			Verify.expect(#report.failures == 0)
				:toBeTrueWith("expected no findings, got " .. Rule.describe(report.failures))
			Verify.expect(Rule.contains(report.warnings, "probe_tmp.md:3: sentence is 31 words"))
				:toBeTrueWith("the long sentence was not a warning: " .. Rule.describe(report.warnings))
			Verify.expect(Rule.contains(report.warnings, "likely passive voice: 'is quickly computed'"))
				:toBeTrueWith("the passive phrase was not a warning: " .. Rule.describe(report.warnings))
			Verify.expect(not Rule.contains(report.warnings, "'was used'"))
				:toBeTrueWith("a skipped participle was a warning: " .. Rule.describe(report.warnings))
		end,
	})
	harness:case(prefix .. "CRLF line endings report the same lines as LF", {
		id = prefix .. "CRLF line endings report the same lines as LF",
		run = function(test: Verify.Context)
			local body = "Line one.\r\n\r\nTurn on IAS before you mount anything.\r\n"
			reports(test, body, "probe_tmp.md:5: acronym 'IAS'")
		end,
	})
end

local actions: { [string]: Rule.Action } = {}

local rule: Rule.Rule = {
	name = "doc-style",
	summary = "The guide, playbooks, README and maintainer map follow the documentation style rules.",
	check = check,
	register = register,
	actions = actions,
}

actions.warnings = {
	summary = "Also print the style warnings: over-long sentences and likely passive voice.",
	run = function(context: Rule.Context, _invocation: Cli.Invocation): number
		local report = inspect(context)
		print(("doc-style: %d warnings (they never fail)"):format(#report.warnings))
		for _, warning in report.warnings do
			print("  warn: " .. warning)
		end
		return Rule.report(rule, report.failures)
	end,
}

return rule
