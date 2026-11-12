--!strict
local Verify = require("../../vendor/verify/src/core")

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Run = require("../lib/run")

local USAGE = [[usage: lute run tools/facet design check <module>...

Checks that a Compose Design module made with the Facet library still parses as a
design and reads back unchanged. A module that does not parse is custom code: the
design editor stops syncing it. A module that reads back differently is rewritten
in the editor's format on its next edit.]]

local PROGRAM = "tools/engine/design_check.luau"
local SAMPLE = "examples/facet_home/designs/Home.luau"

local function check(paths: { string }): Run.Result
	local argv = { Run.lute(), "run", PROGRAM }
	for _, path in paths do
		table.insert(argv, path)
	end
	return Run.capture(argv)
end

local function run(invocation: Cli.Invocation): number
	local paths = table.clone(invocation.positional)
	if table.remove(paths, 1) ~= "check" or #paths == 0 then
		print(USAGE)
		return 2
	end
	local result = check(paths)
	local output = string.gsub(result.stdout .. result.stderr, "%s+$", "")
	print(output)
	return if result.ok then 0 else 1
end

local function register(harness: Verify.Harness, prefix: string)
	harness:case(prefix .. "an authored design module stays in sync", {
		id = prefix .. "an authored design module stays in sync",
		run = function()
			local result = check({ SAMPLE })
			Verify.expect(result.ok):toBe(true)
			Verify.expect(string.find(result.stdout, "stays in sync", 1, true) ~= nil):toBe(true)
		end,
	})
	harness:case(prefix .. "a rounded Group mask and ZStack stay in sync", {
		id = prefix .. "a rounded Group mask and ZStack stay in sync",
		run = function(test: Verify.Context)
			local directory = Files.temporaryDirectory("facet-design-corners-")
			test:defer(function()
				Files.remove(directory)
			end)
			local module = Files.join(directory, "Masks.luau")
			Files.write(
				module,
				table.concat({
					"--!strict",
					"",
					'local Facet = require(game:GetService("ReplicatedStorage").Facet)',
					"",
					"export type Props = {}",
					"",
					'local _design = { contract = { inputs = {}, outputs = {} }, name = "Masks" }',
					"",
					"local function Masks(UI: Facet.Controls, props: Props): GuiObject",
					'\treturn UI.Screen "Screen" {',
					'\t\tgap = "m",',
					'\t\tUI.Group "Minimap" {',
					'\t\t\tcorners = "pill",',
					"\t\t\theight = 120,",
					"\t\t\twidth = 120,",
					"\t\t},",
					'\t\tUI.ZStack "Portrait" {',
					'\t\t\tcorners = "panel",',
					"\t\t\theight = 96,",
					"\t\t\twidth = 96,",
					"\t\t},",
					"\t}",
					"end",
					"",
					"return Masks",
					"",
				}, "\n")
			)
			local result = check({ module })
			Verify.expect(result.ok):toBe(true)
			Verify.expect(string.find(result.stdout, "stays in sync", 1, true) ~= nil):toBe(true)
		end,
	})
	harness:case(prefix .. "a growing container stays in sync", {
		id = prefix .. "a growing container stays in sync",
		run = function(test: Verify.Context)
			local directory = Files.temporaryDirectory("facet-design-grow-")
			test:defer(function()
				Files.remove(directory)
			end)
			local module = Files.join(directory, "Vitals.luau")
			Files.write(
				module,
				table.concat({
					"--!strict",
					"",
					'local Facet = require(game:GetService("ReplicatedStorage").Facet)',
					"",
					"export type Props = {}",
					"",
					'local _design = { contract = { inputs = {}, outputs = {} }, name = "Vitals" }',
					"",
					"local function Vitals(UI: Facet.Controls, props: Props): GuiObject",
					'\treturn UI.HStack "Row" {',
					'\t\tgap = "s",',
					'\t\twidth = "fill",',
					'\t\tUI.ZStack "Meter" {',
					"\t\t\tgrow = 1,",
					"\t\t},",
					'\t\tUI.VStack "Shared" {',
					"\t\t\tgrow = 2,",
					"\t\t},",
					"\t}",
					"end",
					"",
					"return Vitals",
					"",
				}, "\n")
			)
			local result = check({ module })
			Verify.expect(result.ok):toBe(true)
			Verify.expect(string.find(result.stdout, "stays in sync", 1, true) ~= nil):toBe(true)
		end,
	})
	harness:case(prefix .. "custom code and rewrites are reported", {
		id = prefix .. "custom code and rewrites are reported",
		run = function(test: Verify.Context)
			local directory = Files.temporaryDirectory("facet-design-check-")
			test:defer(function()
				Files.remove(directory)
			end)
			local source = Files.text(SAMPLE)
			local custom = Files.join(directory, "Custom.luau")
			Files.write(custom, (string.gsub(source, "UI%.Screen", "makeScreen()", 1)))
			local rewritten = Files.join(directory, "Rewritten.luau")
			Files.write(rewritten, (string.gsub(source, "\n\t", "\n    ")))
			local result = check({ custom, rewritten })
			Verify.expect(result.ok):toBe(false)
			Verify.expect(string.find(result.stdout, "custom code", 1, true) ~= nil):toBe(true)
			Verify.expect(string.find(result.stdout, "rewrites it from line", 1, true) ~= nil):toBe(true)
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
