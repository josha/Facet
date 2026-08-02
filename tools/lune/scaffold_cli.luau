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
