--!strict
-- CLI for the extension scaffold (design §17 Phase 4; UI-AGENT-001).
-- Usage: lune run tools/lune/scaffold_cli <control|adapter> <lower_snake_name>
-- Writes the planned files (refusing to overwrite) and applies the
-- registration edits idempotently, then prints the follow-up loop.

local fs = require("@lune/fs")
local process = require("@lune/process")
local scaffold = require("./scaffold")

local kind = process.args[1]
local name = process.args[2]
if kind == nil or name == nil then
	print("usage: lune run tools/lune/scaffold_cli <control|adapter> <lower_snake_name>")
	process.exit(2)
end

local plan = scaffold.plan(kind, name)
for _, file in plan.files do
	if fs.isFile(file.path) then
		print(`scaffold: REFUSING to overwrite existing {file.path}`)
		process.exit(1)
	end
end
for _, file in plan.files do
	fs.writeFile(file.path, file.content)
	print(`scaffold: wrote {file.path}`)
end
-- BUMPS FIRST, EDITS SECOND, and the order is load-bearing: a bump is skipped
-- when its guard is already in the file, and its guard is a row one of the edits
-- below inserts into that same file. Run the other way round, a first scaffold
-- would find its own guard and count nothing.
for _, bump in plan.bumps do
	local source = fs.readFile(bump.path)
	local applied = scaffold.applyBump(source, bump)
	if applied == source then
		print(`scaffold: {bump.path} count pin already moved (skipped)`)
	else
		fs.writeFile(bump.path, applied)
		print(`scaffold: moved the '{bump.prefix}' count pin in {bump.path}`)
	end
end
for _, edit in plan.edits do
	local source = fs.readFile(edit.path)
	local applied = scaffold.applyEdit(source, edit)
	if applied == source then
		print(`scaffold: {edit.path} already registered (skipped)`)
	else
		fs.writeFile(edit.path, applied)
		print(`scaffold: registered in {edit.path}`)
	end
end
print("scaffold: done. Loop: implement until ./run-tests.sh is green (the stamped spec fails on purpose),")
print("then: lune run tools/lune/check_registration_cli && lune run tools/lune/gate phase-4-hardening")
print("Fast loop while you work: lune run tests/run_one " .. name .. "  (one spec file, seconds not minutes)")
print("Everything above is REGISTERED but STUBBED: the api.md entry, the guide catalog row, the")
print("gallery scenario and the demo blurb all carry a TODO that a reviewer will hold you to.")
