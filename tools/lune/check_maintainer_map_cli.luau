--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local checker = require("./check_maintainer_map")

local MAP = "docs/MAINTAINERS.md"
local USAGE = "usage: lune run tools/lune/check_maintainer_map_cli [--list | --counts | --selftest]"

local mode = "check"
for _, arg in process.args do
	if arg == "--list" or arg == "--counts" or arg == "--selftest" then
		mode = string.sub(arg, 3)
	elseif arg ~= "--" then
		print(USAGE)
		process.exit(2)
	end
end

if mode == "list" then
	print("check_maintainer_map enforces:")
	for index, obligation in checker.OBLIGATIONS do
		print(`  {index}. {obligation}`)
	end
	process.exit(0)
end

if mode == "counts" then
	print("covering specs per area (one require hop out of each spec file):")
	for _, row in checker.coverage() do
		print(`  {row.area}: {row.specs} spec files`)
	end
	process.exit(0)
end

local function replaceOnce(text: string, find: string, replacement: string): string
	local start, finish = string.find(text, find, 1, true)
	if start == nil then
		print(`check_maintainer_map: SELFTEST FAIL — the map no longer contains '{find}'`)
		process.exit(1)
	end
	return string.sub(text, 1, (start :: number) - 1) .. replacement .. string.sub(text, (finish :: number) + 1)
end

local function dropLine(text: string, needle: string): string
	local out: { string } = {}
	local dropped = false
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if not dropped and string.find(line, needle, 1, true) ~= nil then
			dropped = true
			continue
		end
		table.insert(out, line)
	end
	if not dropped then
		print(`check_maintainer_map: SELFTEST FAIL — no line contains '{needle}'`)
		process.exit(1)
	end
	return table.concat(out, "\n")
end

if mode == "selftest" then
	local tmp = process.env.TMPDIR or "/tmp"
	if string.sub(tmp, -1) == "/" then
		tmp = string.sub(tmp, 1, -2)
	end
	math.randomseed(os.time() + math.floor(os.clock() * 1e6))
	local dir = `{tmp}/facet-maintainer-map-{os.time()}-{math.random(1, 1000000)}`
	fs.writeDir(dir)
	local original = fs.readFile(MAP)
	local failed = false

	local function run(label: string, mutated: string, expect: string?)
		if failed then
			return
		end
		local path = `{dir}/{string.gsub(label, "[^%w]", "-")}.md`
		fs.writeFile(path, mutated)
		local result = checker.check({ mapPath = path })
		if expect == nil then
			if not result.ok then
				print("check_maintainer_map: SELFTEST FAIL — the unchanged copy is not clean:")
				for _, problem in result.problems do
					print("  - " .. problem)
				end
				failed = true
				return
			end
			print("  control: the unchanged copy passes")
			return
		end
		for _, problem in result.problems do
			if string.find(problem, expect :: string, 1, true) ~= nil then
				print(`  {label}: reported`)
				return
			end
		end
		print(`check_maintainer_map: SELFTEST FAIL — '{label}' was not reported (expected '{expect}')`)
		for _, problem in result.problems do
			print("  - " .. problem)
		end
		failed = true
	end

	print("check_maintainer_map: selftest (a copy of the map, one planted fault each)")
	run("control", original, nil)
	run(
		"an unowned module",
		replaceOnce(original, "`src/ui/collection_snap.luau`, ", ""),
		"src/ui/collection_snap.luau is not owned by any area row"
	)
	run(
		"an owned module that does not exist",
		replaceOnce(original, "`src/ui/icons.luau`", "`src/ui/no_such_module.luau`"),
		"which does not exist"
	)
	run(
		"a module with two owners",
		replaceOnce(original, "`src/ui/media.luau`, ", "`src/ui/media.luau`, `src/ui/icons.luau`, "),
		"is owned by both"
	)
	run(
		"an unmapped top-level directory",
		dropLine(original, "| `bench/` |"),
		"bench/ is a top-level directory that the tree table does not claim"
	)
	run(
		"a missing repository path",
		replaceOnce(original, "`python3 tools/strip_comments.py --check`", "`python3 tools/no_such_check.py --check`"),
		"names the path 'tools/no_such_check.py'"
	)
	run(
		"a spec named under an area it does not cover",
		replaceOnce(original, "`tests/radial_geometry.spec.luau`", "`tests/example_word_data.spec.luau`"),
		"requires no module of that area"
	)
	run(
		"a scenario that does not exist",
		replaceOnce(original, "`radial_menu`", "`no_such_scenario`"),
		"is not a module in examples/gallery/scenarios"
	)
	run(
		"a public seam the library does not export",
		replaceOnce(original, "`Facet.themes`", "`Facet.themez`"),
		"which the library does not export"
	)
	run(
		"a broken link",
		replaceOnce(original, "(extending/new-theme.md)", "(extending/no-such-page.md)"),
		"does not exist"
	)
	run(
		"an unlinked playbook",
		replaceOnce(original, "[Native primitives](extending/new-primitive.md)", "Native primitives"),
		"new-primitive.md is an extension playbook that the map does not link"
	)
	run("tables out of order", dropLine(original, "| **media** | `tests/"), "the proof table has")

	for _, name in fs.readDir(dir) do
		fs.removeFile(`{dir}/{name}`)
	end
	fs.removeDir(dir)
	if failed then
		process.exit(1)
	end
	print("check_maintainer_map: SELFTEST PASS — every planted fault was reported")
	process.exit(0)
end

local result = checker.check()
local counts = result.counts
if result.ok then
	print(
		`check_maintainer_map: PASS ({counts.areas} areas owning {counts.srcModules} src modules, `
			.. `{counts.treeEntries} top-level directories, {counts.tests} named specs, `
			.. `{counts.scenarios} scenarios, {counts.seams} public seams, {counts.paths} paths, `
			.. `{counts.links} local links, {counts.playbooks} playbooks linked)`
	)
	process.exit(0)
end

print(`check_maintainer_map: FAIL — {#result.problems} problem(s):`)
for _, problem in result.problems do
	print("  - " .. problem)
end
print(`hint: {MAP} is the map; --list prints each rule.`)
process.exit(1)
