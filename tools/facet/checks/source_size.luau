--!strict

local Case = require("../lib/case")
local Files = require("../lib/files")
local Rule = require("../lib/rule")

local ROOTS = { "src", "examples" }
local SUFFIXES: { [string]: boolean } = { [".luau"] = true, [".lua"] = true }
local MAX_CHARACTERS = 200000

local function check(context: Rule.Context): { string }
	local findings: { string } = {}
	for _, root in ROOTS do
		for _, relative in Files.walk(context.path(root)) do
			if not SUFFIXES[Files.extension(relative)] then
				continue
			end
			local path = root .. "/" .. relative
			local text = Files.text(context.path(path))
			local characters = utf8.len(text)
			if characters == nil then
				table.insert(
					findings,
					("%s: the file is not valid UTF-8; Studio Source must be UTF-8 text"):format(path)
				)
			elseif characters >= MAX_CHARACTERS then
				table.insert(
					findings,
					("%s: %d characters; Studio Source assignments require fewer than %d"):format(
						path,
						characters,
						MAX_CHARACTERS
					)
				)
			end
		end
	end
	return findings
end

local function source(characters: number, filler: string): string
	return string.rep(filler, characters)
end

local function cases(): { Rule.Case }
	return {
		{
			name = "a source one character under the limit passes and one at the limit fails",
			run = function()
				return Rule.within({
					["src/under.luau"] = source(MAX_CHARACTERS - 1, "a"),
					["examples/at.lua"] = source(MAX_CHARACTERS, "a"),
					["examples/notes.md"] = source(MAX_CHARACTERS, "a"),
				}, function(context)
					return Case.same(check(context), {
						"examples/at.lua: 200000 characters; Studio Source assignments require fewer than 200000",
					})
				end)
			end,
		},
		{
			name = "characters are code points and CRLF counts as one line break",
			run = function()
				return Rule.within({
					["src/wide.luau"] = source(MAX_CHARACTERS - 1, "é"),
					["src/crlf.luau"] = source((MAX_CHARACTERS - 1) // 2, "a\r\n"),
				}, function(context)
					return Case.same(check(context), {})
				end)
			end,
		},
		{
			name = "invalid UTF-8 is a finding",
			run = function()
				return Rule.within({ ["examples/nested/broken.luau"] = "return '\255'\n" }, function(context)
					return Case.same(check(context), {
						"examples/nested/broken.luau: the file is not valid UTF-8; Studio Source must be UTF-8 text",
					})
				end)
			end,
		},
	}
end

local rule: Rule.Rule = {
	name = "source-size",
	summary = "Each Luau source under src and examples has fewer than 200000 characters for Studio Source.",
	check = check,
	cases = cases,
}

return rule
