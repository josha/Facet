--!strict

local Case = require("../lib/case")
local Files = require("../lib/files")
local Rule = require("../lib/rule")

local SUFFIXES: { [string]: boolean } = {
	[".md"] = true,
	[".luau"] = true,
	[".lua"] = true,
	[".json"] = true,
	[".txt"] = true,
	[".toml"] = true,
	[".yml"] = true,
	[".yaml"] = true,
	[".csv"] = true,
}
local SKIP: { [string]: boolean } = {
	[".git"] = true,
	artifacts = true,
	build = true,
	vendor = true,
	node_modules = true,
}
local WINDOWS_1252: { [number]: number } = {
	[0x20AC] = 0x80,
	[0x201A] = 0x82,
	[0x0192] = 0x83,
	[0x201E] = 0x84,
	[0x2026] = 0x85,
	[0x2020] = 0x86,
	[0x2021] = 0x87,
	[0x02C6] = 0x88,
	[0x2030] = 0x89,
	[0x0160] = 0x8A,
	[0x2039] = 0x8B,
	[0x0152] = 0x8C,
	[0x017D] = 0x8E,
	[0x2018] = 0x91,
	[0x2019] = 0x92,
	[0x201C] = 0x93,
	[0x201D] = 0x94,
	[0x2022] = 0x95,
	[0x2013] = 0x96,
	[0x2014] = 0x97,
	[0x02DC] = 0x98,
	[0x2122] = 0x99,
	[0x0161] = 0x9A,
	[0x203A] = 0x9B,
	[0x0153] = 0x9C,
	[0x017E] = 0x9E,
	[0x0178] = 0x9F,
}

local function encodedTwice(line: string): boolean
	if not string.find(line, "[\128-\255]") then
		return false
	end
	local bytes: { string } = {}
	for _, point in utf8.codes(line) do
		local byte = if point < 0x100 then point else WINDOWS_1252[point]
		if byte == nil then
			return false
		end
		table.insert(bytes, string.char(byte))
	end
	local original = table.concat(bytes)
	return original ~= line and utf8.len(original) ~= nil
end

local function check(context: Rule.Context): { string }
	local findings: { string } = {}
	for _, relative in Files.walk(context.root, { skip = SKIP }) do
		if not SUFFIXES[Files.extension(relative)] then
			continue
		end
		local text = Files.text(context.path(relative))
		if utf8.len(text) == nil then
			table.insert(findings, ("%s: the file is not valid UTF-8"):format(relative))
			continue
		end
		local number = 0
		for line in string.gmatch(text, "([^\n]*)\n?") do
			number += 1
			if encodedTwice(line) then
				table.insert(
					findings,
					("%s:%d: the text is UTF-8 encoded twice; restore the original characters"):format(relative, number)
				)
			end
		end
	end
	table.sort(findings)
	return findings
end

local function cases(): { Rule.Case }
	return {
		{
			name = "a line encoded twice is found and correct non-ASCII text passes",
			run = function()
				return Rule.within({
					["CHANGELOG.md"] = "# Changes\n\n- Facet\u{E2}\u{20AC}\u{2122}s default\n- Facet\u{2019}s default \u{2212} 0 \u{2192} 90, \u{3B6}1.0, caf\u{E9}\n",
					["docs/notes.md"] = "A \u{2013} B\n",
					["src/vendor/upstream.md"] = "Facet\u{E2}\u{20AC}\u{2122}s\n",
					["artifacts/run.json"] = '"\u{C3}\u{A9}"\n',
				}, function(context)
					return Case.same(check(context), {
						"CHANGELOG.md:3: the text is UTF-8 encoded twice; restore the original characters",
					})
				end)
			end,
		},
		{
			name = "an arrow, a minus sign and a Greek letter encoded twice are found",
			run = function()
				return Rule.within({
					["notes.md"] = "0 \u{E2}\u{2020}\u{2019} 90\nx \u{E2}\u{2C6}\u{2019} y\n\u{CE}\u{B6}1.0\n",
				}, function(context)
					return Case.same(check(context), {
						"notes.md:1: the text is UTF-8 encoded twice; restore the original characters",
						"notes.md:2: the text is UTF-8 encoded twice; restore the original characters",
						"notes.md:3: the text is UTF-8 encoded twice; restore the original characters",
					})
				end)
			end,
		},
	}
end

local rule: Rule.Rule = {
	name = "text-encoding",
	summary = "Find tracked text whose UTF-8 bytes were decoded as Windows-1252 and encoded again.",
	check = check,
	cases = cases,
}

return rule
