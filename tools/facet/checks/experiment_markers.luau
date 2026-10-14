--!strict

local Case = require("../lib/case")
local Files = require("../lib/files")
local Rule = require("../lib/rule")

local ROOT = "src"

export type Marker = { file: string, line: number, token: string, text: string }

local function modules(context: Rule.Context): { string }
	local found: { string } = {}
	for _, relative in Files.walk(context.path(ROOT)) do
		if string.sub(relative, -5) == ".luau" then
			table.insert(found, ROOT .. "/" .. relative)
		end
	end
	return found
end

local function markers(file: string, source: string): { Marker }
	local found: { Marker } = {}
	for number, line in string.split(source, "\n") do
		for token in string.gmatch(line, "%f[%w_]ZZ[%w_]*") do
			table.insert(found, {
				file = file,
				line = number,
				token = token,
				text = string.match(line, "^%s*(.*)$") or line,
			})
		end
	end
	return found
end

local function describe(marker: Marker): string
	return ("%s:%d: '%s' is a scratch experiment marker. Remove it from src/. Put scratch work in tests/, bench/ or tools/. A shipped flag needs a real name and a documented default."):format(
		marker.file,
		marker.line,
		marker.token
	)
end

local function scan(context: Rule.Context): { Marker }
	local found: { Marker } = {}
	for _, file in modules(context) do
		for _, marker in markers(file, Files.text(context.path(file))) do
			table.insert(found, marker)
		end
	end
	return found
end

local function check(context: Rule.Context): { string }
	local findings: { string } = {}
	for _, marker in scan(context) do
		table.insert(findings, describe(marker))
	end
	return findings
end

local PROBE = "src/ui/probe.luau"

local function planted(line: string): { Marker }
	local found: { Marker } = {}
	local failure = Rule.within({
		["src/init.luau"] = "return {}\n",
		[PROBE] = "local value = 1\n" .. line .. "\nreturn value\n",
		["tests/scratch.spec.luau"] = "local ZZ_SCRATCH = true\n",
		["src/notes.txt"] = "ZZ_NOT_A_MODULE\n",
	}, function(context)
		found = scan(context)
		return nil
	end)
	if failure ~= nil then
		error(failure)
	end
	return found
end

local function cases(): { Rule.Case }
	local cases: { Rule.Case } = {}
	for _, line in
		{ "local ZZ_NO_PATH2D = true", "if class == 'Path' and not ZZExperiment then end", "local flag = ZZ" }
	do
		table.insert(cases, {
			name = "the planted marker line '" .. line .. "' is reported",
			run = function()
				local found = planted(line)
				return Case.expect(
					#found == 1 and found[1].file == PROBE and found[1].line == 2 and found[1].text == line,
					("expected one marker on %s:2, got %d"):format(PROBE, #found)
				)
			end,
		})
	end
	for _, line in { "local BUZZER = 1", "local fizz, buzz = 1, 2", "local aZZ = 1" } do
		table.insert(cases, {
			name = "the ordinary name line '" .. line .. "' passes",
			run = function()
				local found = planted(line)
				return Case.expect(#found == 0, ("expected no marker, got %d"):format(#found))
			end,
		})
	end
	table.insert(cases, {
		name = "a marker is reported with its line under CRLF endings",
		run = function()
			return Rule.within({ ["src/deep/module.luau"] = "local a = 1\r\n\tlocal ZZB = 2\r\n" }, function(context)
				return Case.same(check(context), {
					"src/deep/module.luau:2: 'ZZB' is a scratch experiment marker. Remove it from src/. Put scratch work in tests/, bench/ or tools/. A shipped flag needs a real name and a documented default.",
				})
			end)
		end,
	})
	return cases
end

local rule: Rule.Rule = {
	name = "experiment-markers",
	summary = "No module under src/ carries a ZZ scratch experiment marker.",
	check = check,
	cases = cases,
}

return rule
