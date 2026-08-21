--!strict
-- THE MAINTAINER-MAP GATE (release-candidate review row RC-11).
-- `lune run tools/lune/check_maintainer_map_cli` is the canonical command; this
-- spec runs the same checker, so a map that has drifted away from the tree fails
-- the SUITE and not only a command someone remembered to type.
--
-- Same shape as tests/theme_docs.spec.luau: assert the live repository is green,
-- then prove every rule actually bites by planting synthetic drift. The plant is
-- IN MEMORY here (`mapSource`) rather than on disk, because a suite run must
-- write nothing; the command-line selftest plants the same faults into a real
-- copy of the file in a scratch directory.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local checker = require("../tools/lune/check_maintainer_map")

local MAP = "docs/MAINTAINERS.md"
local live = fs.readFile(MAP)

local function problemsMentioning(result: any, needle: string): number
	local n = 0
	for _, problem in result.problems :: { string } do
		if string.find(problem, needle, 1, true) ~= nil then
			n += 1
		end
	end
	return n
end

-- plant one fault into a copy of the live map and check the checker names it
local function plant(mutate: (string) -> string, needle: string): number
	local mutated = mutate(live)
	if mutated == live then
		error(`the mutation changed nothing, so it proves nothing (looking for: {needle})`)
	end
	return problemsMentioning(checker.check({ mapSource = mutated }), needle)
end

describe("maintainer map: every row still points at the tree it describes", function()
	it("the live repository passes every obligation", function()
		local result = checker.check()
		if not result.ok then
			error("check_maintainer_map problems:\n  " .. table.concat(result.problems, "\n  "))
		end
		expect(result.ok).toBe(true)
		expect(#result.problems).toBe(0)
	end)

	it("checks a real amount, so a gutted map cannot pass by describing nothing", function()
		local counts = checker.check().counts
		-- every top-level src entry is claimed, and the tree has at least this many
		expect(counts.srcEntries).toBeGreaterThanOrEqual(28)
		expect(counts.areas).toBeGreaterThanOrEqual(19)
		expect(counts.tests).toBeGreaterThanOrEqual(60)
		expect(counts.scenarios).toBeGreaterThanOrEqual(17)
		expect(counts.gateRows).toBeGreaterThanOrEqual(40)
		expect(counts.boundaryRules).toBeGreaterThanOrEqual(6)
		expect(counts.links).toBeGreaterThanOrEqual(30)
		expect(counts.playbooks).toBeGreaterThanOrEqual(7)
	end)

	it("names every obligation it enforces (the command's --list output)", function()
		expect(#checker.OBLIGATIONS).toBeGreaterThanOrEqual(11)
		local joined = table.concat(checker.OBLIGATIONS, "\n")
		for _, needle in { "src/", "require graph", "gate_manifest", "check_boundary", "docs/extending" } do
			if string.find(joined, needle, 1, true) == nil then
				error(`the obligation list never mentions '{needle}'`)
			end
		end
	end)

	it("reports a src area no row claims", function()
		local dropped = plant(function(text)
			local out: { string } = {}
			for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
				if string.sub(line, 1, 1) == "|" and string.find(line, "`src/env/`", 1, true) ~= nil then
					continue
				end
				table.insert(out, line)
			end
			return table.concat(out, "\n")
		end, "src/env is not claimed by any area row")
		expect(dropped).toBeGreaterThanOrEqual(1)
	end)

	it("reports a claimed path that does not exist", function()
		expect(plant(function(text)
			return (string.gsub(text, "`src/async/`", "`src/asynchronous/`", 1))
		end, "which does not exist")).toBeGreaterThanOrEqual(1)
	end)

	it("reports two src paths claimed by the same two areas", function()
		expect(plant(function(text)
			return (string.gsub(text, "`src/focus/`", "`src/focus/`, `src/motion/`", 1))
		end, "is claimed by both")).toBeGreaterThanOrEqual(1)
	end)

	it("reports the two tables falling out of step", function()
		expect(plant(function(text)
			return (string.gsub(text, "| %*%*focus%*%* | core only%.", "| **focuss** | core only.", 1))
		end, "in the proof table")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a spec filed under an area it does not require", function()
		expect(plant(function(text)
			return (string.gsub(text, "`tests/replication%.spec%.luau`", "`tests/motion_spring.spec.luau`", 1))
		end, "requires no module of that area")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a spec file that has been renamed away", function()
		expect(plant(function(text)
			return (string.gsub(text, "`tests/focus%.spec%.luau`", "`tests/no_such.spec.luau`", 1))
		end, "which does not exist")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a Studio scenario that is not a registered scenario", function()
		expect(plant(function(text)
			return (string.gsub(text, "| `safe_area` |", "| `no_such_scenario` |", 1))
		end, "is not a module in examples/gallery/scenarios")).toBeGreaterThanOrEqual(1)
	end)

	it("reports an empty scenario cell that gives no reason", function()
		expect(plant(function(text)
			return (string.gsub(text, "| `branch_scope` |", "|  |", 1))
		end, "names no Studio scenario and gives no reason")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a gate row the manifest does not have", function()
		expect(plant(function(text)
			return (string.gsub(text, "replication%-boundary%-spike", "no-such-row", 1))
		end, "has no row of that name")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a gate stage the manifest does not have", function()
		expect(plant(function(text)
			return (string.gsub(text, "`phase%-0%-foundation/conformance%-custom%-core`", "`no-such-stage/x`", 1))
		end, "which tools/lune/gate_manifest.luau does not define")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a boundary rule check_boundary does not enforce", function()
		expect(plant(function(text)
			return (string.gsub(text, "`non%-client%-requires%-client`", "`no-such-rule-name`", 1))
		end, "which check_boundary does not enforce")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a link that resolves nowhere", function()
		expect(plant(function(text)
			return (string.gsub(text, "%(reference/constitution%.md%)", "(reference/no-such-page.md)", 1))
		end, "does not exist")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a link whose anchor is not a heading in the target", function()
		expect(plant(function(text)
			return (string.gsub(text, "#24%-why%-the%-boundaries%-exist", "#24-why-the-boundaries-moved", 1))
		end, "has no heading with that anchor")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a shipped extension playbook the map stops linking", function()
		expect(plant(function(text)
			return (string.gsub(text, "%(extending/skinned%-control%.md%)", "(extending/new-theme.md)"))
		end, "is a shipped extension playbook the map never links")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a missing marker rather than silently checking nothing", function()
		expect(plant(function(text)
			return (string.gsub(text, "<!%-%- maintainer%-map:proof %-%->", "", 1))
		end, "marker comments is missing")).toBeGreaterThanOrEqual(1)
	end)

	it("derives a per-area covering count from the require graph", function()
		local rows = checker.coverage()
		expect(#rows).toBeGreaterThanOrEqual(19)
		local total = 0
		local byArea: { [string]: number } = {}
		for _, row in rows do
			total += row.specs
			byArea[row.area] = row.specs
		end
		-- the shared reactive runtime is reached by far more specs than the
		-- single-module areas, which is what makes the derivation informative
		expect(byArea["core"]).toBeGreaterThanOrEqual(80)
		expect(byArea["replication"]).toBeGreaterThanOrEqual(2)
		expect(total).toBeGreaterThanOrEqual(500)
	end)
end)
