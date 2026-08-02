--!strict
-- Shared runner for the render/interact/soak commands (design §16.1): each is
-- a registry of named deterministic fixtures that write machine-readable
-- artifacts. A fixture: { name: string, requirement: string,
--   run: () -> any  -- returns a JSON-serializable artifact body; errors fail }
-- The runner writes artifacts/<command>/<name>.json plus a summary, exits
-- nonzero on empty registry or any error, and (determinism guard) runs each
-- fixture twice, failing on any difference between the two encodings.

local serde = require("@lune/serde")
local process = require("@lune/process")
local artifact = require("./artifact")

export type Fixture = {
	name: string,
	requirement: string,
	run: () -> any,
}

local function runAll(command: string, fixtures: { Fixture }, emptyHint: string): never
	if #fixtures == 0 then
		print(`{command}: FAIL - no fixtures registered ({emptyHint})`)
		process.exit(1)
	end
	local failed = false
	local summary = {}
	for _, fixture in fixtures do
		local ok, err = pcall(function()
			local first = fixture.run()
			local second = fixture.run()
			local enc1 = serde.encode("json", first, true)
			local enc2 = serde.encode("json", second, true)
			if enc1 ~= enc2 then
				error("nondeterministic fixture output between identical runs")
			end
			artifact.writeJson(`artifacts/{command}/{fixture.name}.json`, first)
			table.insert(summary, { name = fixture.name, requirement = fixture.requirement, status = "PASS" })
			print(`  PASS {fixture.name}`)
		end)
		if not ok then
			failed = true
			table.insert(
				summary,
				{ name = fixture.name, requirement = fixture.requirement, status = "FAIL", error = tostring(err) }
			)
			print(`  FAIL {fixture.name}: {err}`)
		end
	end
	artifact.writeJson(`artifacts/{command}/summary.json`, {
		schema = `luauui-{command}/1`,
		status = if failed then "FAIL" else "PASS",
		fixtures = summary,
	})
	print(`{command}: {failed and "FAIL" or "PASS"} (artifacts/{command}/summary.json)`)
	process.exit(if failed then 1 else 0)
end

return runAll
