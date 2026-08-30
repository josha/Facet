--!strict
-- Dump tools/lune/gate_manifest.luau as JSON so the conversion to the
-- verification graph is a scripted, repeatable transform rather than a hand
-- edit. Usage: lune run tools/lune/verify/dump_manifest <output-path>

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local manifest = require("../gate_manifest")

local out = process.args[1] or "/tmp/facet-gate-manifest.json"
local dump: { [string]: any } = {}
for phase, checks in manifest do
	local rows: { any } = {}
	for index, check in checks do
		table.insert(rows, {
			index = index,
			name = check.name,
			requirements = check.requirements,
			run = check.run,
			state = check.state,
			evidence = check.evidence,
			releaseBlocking = check.releaseBlocking,
			note = check.note,
		})
	end
	dump[phase] = rows
end
fs.writeFile(out, serde.encode("json", dump, true))
print(`dump_manifest: {out}`)
