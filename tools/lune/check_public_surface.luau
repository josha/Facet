--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")

local Facet = require("../../src") :: any
local engines = require("../../tests/lib/native_engine")

local SNAPSHOT = "tools/public_surface.txt"
local INIT = "src/init.luau"

local function sortedKeys(t: { [any]: any }): { string }
	local keys: { string } = {}
	for key in t do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	return keys
end

local function kind(value: any): string
	if type(value) == "table" then
		return if table.isfrozen(value) then "table(frozen)" else "table"
	end
	return type(value)
end

local function surface(): { string }
	local lines: { string } = { `VERSION {Facet.VERSION}` }
	for _, key in sortedKeys(Facet) do
		local value = Facet[key]
		table.insert(lines, `{key} : {kind(value)}`)
		if type(value) == "table" then
			for _, sub in sortedKeys(value) do
				table.insert(lines, `  {key}.{sub} : {kind(value[sub])}`)
			end
		end
	end
	local engine = engines.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local controls = Facet.controls(runtime, { types = engine.types })
	for _, key in sortedKeys(controls) do
		table.insert(lines, `controls(runtime).{key} : {kind(controls[key])}`)
	end
	runtime:dispose()
	local types: { string } = {}
	for name in string.gmatch(fs.readFile(INIT), "\nexport type ([%w_]+)") do
		table.insert(types, name)
	end
	table.sort(types)
	for _, name in types do
		table.insert(lines, `type {name}`)
	end
	return lines
end

local function compare(expected: string, actual: { string }): { string }
	local wanted: { string } = {}
	for line in string.gmatch(expected, "[^\n]+") do
		table.insert(wanted, line)
	end
	local have: { [string]: boolean } = {}
	for _, line in actual do
		have[line] = true
	end
	local recorded: { [string]: boolean } = {}
	for _, line in wanted do
		recorded[line] = true
	end
	local differences: { string } = {}
	for _, line in wanted do
		if not have[line] then
			table.insert(differences, `- {line}`)
		end
	end
	for _, line in actual do
		if not recorded[line] then
			table.insert(differences, `+ {line}`)
		end
	end
	return differences
end

local mode = process.args[1]
local lines = surface()
local text = table.concat(lines, "\n") .. "\n"

if mode == "--write" then
	fs.writeFile(SNAPSHOT, text)
	print(`check_public_surface: wrote {#lines} lines to {SNAPSHOT}`)
	process.exit(0)
end

if mode == "--selftest" then
	local removed = table.clone(lines)
	table.remove(removed, #removed)
	local added = table.clone(lines)
	table.insert(added, "controls(runtime).Removed : function")
	local changed = table.clone(lines)
	changed[1] = "VERSION 0.0.0"
	local ok = #compare(text, lines) == 0
		and #compare(text, removed) == 1
		and #compare(text, added) == 1
		and #compare(text, changed) == 2
	print(if ok then "check_public_surface: SELFTEST PASS" else "check_public_surface: SELFTEST FAIL")
	process.exit(if ok then 0 else 1)
end

if mode ~= nil then
	print("usage: lune run tools/lune/check_public_surface [--write | --selftest]")
	process.exit(2)
end

if not fs.isFile(SNAPSHOT) then
	print(`check_public_surface: FAIL - {SNAPSHOT} is missing; run with --write and review the file`)
	process.exit(1)
end
local differences = compare(fs.readFile(SNAPSHOT), lines)
if #differences > 0 then
	print(`check_public_surface: FAIL - the public surface differs from {SNAPSHOT}:`)
	for _, line in differences do
		print(`  {line}`)
	end
	print("Update the snapshot with --write, api.md and the changelog in the same change.")
	process.exit(1)
end
print(`check_public_surface: PASS - {#lines} public surface lines match {SNAPSHOT}`)
