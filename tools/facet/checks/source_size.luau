--!strict
local Verify = require("../../vendor/verify/src/core")

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

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "a source one character under the limit passes and one at the limit fails", {
		id = prefix .. "a source one character under the limit passes and one at the limit fails",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["src/under.luau"] = source(MAX_CHARACTERS - 1, "a"),
				["examples/at.lua"] = source(MAX_CHARACTERS, "a"),
				["examples/notes.md"] = source(MAX_CHARACTERS, "a"),
			}, function(context)
				Verify.expect(check(context)):toEqual({
					"examples/at.lua: 200000 characters; Studio Source assignments require fewer than 200000",
				})
			end)
		end,
	})
	harness:case(prefix .. "characters are code points and CRLF counts as one line break", {
		id = prefix .. "characters are code points and CRLF counts as one line break",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["src/wide.luau"] = source(MAX_CHARACTERS - 1, "é"),
				["src/crlf.luau"] = source((MAX_CHARACTERS - 1) // 2, "a\r\n"),
			}, function(context)
				Verify.expect(check(context)):toEqual({})
			end)
		end,
	})
	harness:case(prefix .. "invalid UTF-8 is a finding", {
		id = prefix .. "invalid UTF-8 is a finding",
		run = function(test: Verify.Context)
			Rule.within(test, { ["examples/nested/broken.luau"] = "return '\255'\n" }, function(context)
				Verify.expect(check(context)):toEqual({
					"examples/nested/broken.luau: the file is not valid UTF-8; Studio Source must be UTF-8 text",
				})
			end)
		end,
	})
end

local rule: Rule.Rule = {
	name = "source-size",
	summary = "Each Luau source under src and examples has fewer than 200000 characters for Studio Source.",
	check = check,
	register = register,
}

return rule
