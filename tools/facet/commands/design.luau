--!strict
local Verify = require("../../vendor/verify/src/core")

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Facet = require("../../../src")

local USAGE = [[usage: lute run tools/facet design check <module>...

Checks that a Compose Design module made with the Facet library still parses as a
design and reads back unchanged. A module that does not parse is custom code: the
design editor stops syncing it. A module that reads back differently is rewritten
in the editor's format on its next edit.]]

type Report = { ok: boolean, message: string }

local kit = Facet.design()
local library = kit.library({
	UI = {},
	rgb = function(r: number, g: number, b: number): unknown
		return { r, g, b }
	end,
	udim2 = function(xScale: number, xOffset: number, yScale: number, yOffset: number): unknown
		return { xScale, xOffset, yScale, yOffset }
	end,
	offset = function(x: number, y: number): unknown
		return { 0, x, 0, y }
	end,
})

local function check(source: string): Report
	local parsed, value = pcall(kit.Design.parse, source, library)
	if not parsed then
		return { ok = false, message = `custom code; the editor stops syncing: {value}` }
	end
	local emitted = kit.Design.emit(value, library, { name = value.name })
	if emitted == source then
		return { ok = true, message = "design; the editor stays in sync" }
	end
	local line = 1
	for index = 1, math.min(#source, #emitted) do
		if string.byte(source, index) ~= string.byte(emitted, index) then
			break
		elseif string.byte(source, index) == 10 then
			line += 1
		end
	end
	return { ok = false, message = `design, but the editor rewrites it from line {line} on its next edit` }
end

local function run(invocation: Cli.Invocation): number
	local paths = table.clone(invocation.positional)
	if table.remove(paths, 1) ~= "check" or #paths == 0 then
		print(USAGE)
		return 2
	end
	local failed = 0
	for _, path in paths do
		local report = check(Files.text(path))
		print(`{path}: {report.message}`)
		if not report.ok then
			failed += 1
		end
	end
	return if failed == 0 then 0 else 1
end

local function register(harness: Verify.Harness, prefix: string)
	harness:case(prefix .. "a module the editor wrote stays in sync", {
		id = prefix .. "a module the editor wrote stays in sync",
		run = function()
			local value = kit.Design.document.new("Panel", library, "Screen")
			local source = kit.Design.emit(value, library, { name = "Panel" })
			Verify.expect(check(source).ok):toBe(true)
		end,
	})
	harness:case(prefix .. "custom code and rewrites are reported", {
		id = prefix .. "custom code and rewrites are reported",
		run = function()
			local source =
				kit.Design.emit(kit.Design.document.new("Panel", library, "Screen"), library, { name = "Panel" })
			local custom = check((string.gsub(source, "UI%.Screen", "makeScreen()", 1)))
			Verify.expect(custom.ok):toBe(false)
			Verify.expect(string.find(custom.message, "custom code", 1, true) ~= nil):toBe(true)
			local rewritten = check((string.gsub(source, "\n\t", "\n    ")))
			Verify.expect(rewritten.ok):toBe(false)
			Verify.expect(string.find(rewritten.message, "rewrites", 1, true) ~= nil):toBe(true)
		end,
	})
end

local command: Cli.Command = {
	name = "design",
	summary = "Check that Compose Design modules made with the Facet library still sync with the editor.",
	usage = USAGE,
	register = register,
	run = run,
}

return command
