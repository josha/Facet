--!strict
-- THE canonical command for the maintainer map (docs/MAINTAINERS.md;
-- release-candidate review row RC-11):
--
--   lune run tools/lune/check_maintainer_map_cli              check the live map
--   lune run tools/lune/check_maintainer_map_cli -- --list    print the obligations
--   lune run tools/lune/check_maintainer_map_cli -- --counts  per-area covering-spec counts
--   lune run tools/lune/check_maintainer_map_cli -- --selftest prove each rule bites
--
-- READ-ONLY over the repository. The selftest plants its drift into a COPY of
-- the map in a scratch directory and points the checker at that copy, so it is
-- the same scan over the same tree while a concurrent reader never sees a
-- planted file. The scratch directory is named with a per-run stamp, because an
-- unkeyed one is raced by a second sweep.

local fs = require("@lune/fs")
local process = require("@lune/process")
local checker = require("./check_maintainer_map")

local MAP = "docs/MAINTAINERS.md"

local wantList, wantCounts, wantSelftest = false, false, false
for _, arg in process.args do
	if arg == "--list" then
		wantList = true
	elseif arg == "--counts" then
		wantCounts = true
	elseif arg == "--selftest" then
		wantSelftest = true
	end
end

if wantList then
	print("check_maintainer_map enforces:")
	for index, obligation in checker.OBLIGATIONS do
		print(`  {index}. {obligation}`)
	end
	process.exit(0)
end

if wantCounts then
	print("covering specs per area (the require graph, one hop out of each spec file):")
	for _, row in checker.coverage() do
		print(`  {row.area}: {row.specs} spec files`)
	end
	process.exit(0)
end

if wantSelftest then
	local tmp = process.env.TMPDIR or "/tmp"
	if string.sub(tmp, -1) == "/" then
		tmp = string.sub(tmp, 1, -2)
	end
	math.randomseed(os.time() + math.floor(os.clock() * 1e6))
	local dir = `{tmp}/facet-maintainer-map-{os.time()}-{math.random(1, 1000000)}`
	fs.writeDir(dir)
	local original = fs.readFile(MAP)

	local function run(label: string, mutate: (string) -> string, expect: string?)
		local path = `{dir}/{string.gsub(label, "[^%w]", "-")}.md`
		fs.writeFile(path, mutate(original))
		local result = checker.check({ mapPath = path })
		if expect == nil then
			if not result.ok then
				print(`check_maintainer_map: SELFTEST FAIL — the unmutated copy is not clean:`)
				for _, problem in result.problems do
					print("  - " .. problem)
				end
				process.exit(1)
			end
			print(`  control: an unmutated copy passes`)
			return
		end
		local found = false
		for _, problem in result.problems do
			if string.find(problem, expect :: string, 1, true) ~= nil then
				found = true
				break
			end
		end
		if not found then
			print(`check_maintainer_map: SELFTEST FAIL — '{label}' was not reported`)
			print(`  expected a problem naming: {expect}`)
			for _, problem in result.problems do
				print("  - " .. problem)
			end
			process.exit(1)
		end
		print(`  {label}: reported`)
	end

	-- the dropped area is `env`, whose row is the one line that claims src/env/
	local function dropArea(text: string): string
		local out: { string } = {}
		for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
			if string.sub(line, 1, 1) == "|" and string.find(line, "`src/env/`", 1, true) ~= nil then
				continue
			end
			table.insert(out, line)
		end
		return table.concat(out, "\n")
	end

	print("check_maintainer_map: selftest (a copy of the map, one planted fault each)")
	run("control", function(text)
		return text
	end, nil)
	run("a dropped area row", dropArea, "src/env is not claimed by any area row")
	run("a broken link", function(text)
		return (string.gsub(text, "%(reference/constitution%.md%)", "(reference/no-such-page.md)", 1))
	end, "does not exist")
	run("a spec named under an area it does not cover", function(text)
		return (string.gsub(text, "`tests/replication%.spec%.luau`", "`tests/motion_spring.spec.luau`", 1))
	end, "requires no module of that area")
	run("a gate row that does not exist", function(text)
		return (
			string.gsub(text, "phase%-0%-foundation/replication%-boundary%-spike", "phase-0-foundation/no-such-row", 1)
		)
	end, "has no row of that name")
	run("a boundary rule nothing enforces", function(text)
		return (string.gsub(text, "`non%-client%-requires%-client`", "`no-such-rule-name`", 1))
	end, "which check_boundary does not enforce")
	run("a scenario that is not registered", function(text)
		return (string.gsub(text, "| `safe_area` |", "| `no_such_scenario` |", 1))
	end, "is not a module in examples/gallery/scenarios")

	for _, name in fs.readDir(dir) do
		fs.removeFile(`{dir}/{name}`)
	end
	fs.removeDir(dir)
	print("check_maintainer_map: SELFTEST PASS — every planted fault was reported")
	process.exit(0)
end

local result = checker.check()
if result.ok then
	print(
		`check_maintainer_map: PASS ({result.counts.areas} areas covering {result.counts.srcEntries} src entries, `
			.. `{result.counts.tests} named specs, {result.counts.scenarios} scenarios, `
			.. `{result.counts.gateRows} gate rows, {result.counts.boundaryRules} boundary rules, `
			.. `{result.counts.links} local links, {result.counts.playbooks} playbooks linked)`
	)
	process.exit(0)
end

print(`check_maintainer_map: FAIL [UI-AGENT-001] — {#result.problems} problem(s):`)
for _, problem in result.problems do
	print("  - " .. problem)
end
print(`hint: {MAP} is the map; '--list' prints every obligation this command enforces.`)
process.exit(1)
