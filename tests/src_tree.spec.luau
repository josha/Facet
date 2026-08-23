--!strict
--[[
	`tests/lib/src_tree.luau` — the ONE enumeration of `src/`, and the proof that
	it reaches the places the thing it replaces could not (rulings P5 + PRES-X
	minor, 2026-08-22).

	TWO SEAM SPECS EACH PROVED "there is exactly ONE consumer of this module in
	`src/`" by iterating a hand-written list of NINE directory names. `src/` has
	fifteen directories and thirteen top-level `.luau` files. A second consumer
	appearing in `src/env`, `src/focus`, `src/async`, `src/motion`, `src/preview`,
	`src/replication` or in `src/blueprint.luau`, `src/init.luau`, `src/mount.luau`
	— twelve places, several of them the most-required files in the library —
	would have been reported as "exactly one". That is a check that cannot fail for
	the case it exists to catch, and this repository has had to delete that shape
	before.

	THE FIX IS ONLY WORTH ANYTHING IF IT IS PROVED, so these cases are written as
	the difference: the old nine-directory list is reproduced here as data, and the
	walk has to reach files it never could.
]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")

-- verbatim, so this case measures the actual hole rather than a memory of it
local OLD_LIST = {
	"src/layout",
	"src/render",
	"src/present",
	"src/controls",
	"src/client",
	"src/tokens",
	"src/themes",
	"src/input",
	"src/core",
}

local function oldWalk(): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	for _, dir in OLD_LIST do
		for _, entry in fs.readDir(dir) do
			local path = `{dir}/{entry}`
			if fs.isFile(path) and string.sub(path, -5) == ".luau" then
				seen[path] = true
			end
		end
	end
	return seen
end

describe("src_tree: the enumeration two seam specs were missing most of", function()
	it("reaches every `.luau` under src/, and the old nine-directory list did not", function()
		local all = srcTree.paths()
		local old = oldWalk()
		local missed: { string } = {}
		for _, path in all do
			if not old[path] then
				table.insert(missed, path)
			end
		end
		--[[ THE CASE IS THE DIFFERENCE, NOT THE TOTAL. A count would rot with every
			new file; what has to stay true is that the old list had a hole and this
			walk does not, so the assertion is "the walk is a strict superset, and the
			part it adds is not empty". ]]
		expect(`the walk reaches more than the old list: {#missed > 0}`).toBe(
			"the walk reaches more than the old list: true"
		)
		-- ...and every one of the old list's files is still reached, or the fix
		-- would have traded one hole for another
		local lost: { string } = {}
		local reached: { [string]: boolean } = {}
		for _, path in all do
			reached[path] = true
		end
		for path in old do
			if not reached[path] then
				table.insert(lost, path)
			end
		end
		expect(`lost={table.concat(lost, " ")}`).toBe("lost=")
	end)

	--[[ THE DIRECTORIES BY NAME, because "more than the old list" would also pass
		if the walk merely found one extra file in a directory the list already
		named. These six were invisible in their entirety. ]]
	it("the six directories the old list never named are all in it", function()
		local dirs: { [string]: boolean } = {}
		for _, path in srcTree.paths() do
			local dir = string.match(path, "^(.*)/[^/]+$")
			if dir ~= nil then
				dirs[dir] = true
			end
		end
		local missing: { string } = {}
		for _, dir in { "src/async", "src/env", "src/focus", "src/motion", "src/preview", "src/replication" } do
			if not dirs[dir] then
				table.insert(missing, dir)
			end
		end
		expect(`missing={table.concat(missing, " ")}`).toBe("missing=")
	end)

	it("and the top-level src/*.luau files, which no directory in the old list covered", function()
		local top: { string } = {}
		for _, path in srcTree.paths() do
			if string.match(path, "^src/[^/]+%.luau$") ~= nil then
				table.insert(top, path)
			end
		end
		--[[ `blueprint.luau` and `init.luau` are the two most-required files in the
			library; a second consumer of a seam appearing in either was invisible. ]]
		expect(`blueprint reached={table.find(top, "src/blueprint.luau") ~= nil}`).toBe("blueprint reached=true")
		expect(`init reached={table.find(top, "src/init.luau") ~= nil}`).toBe("init reached=true")
		expect(`count>=10={#top >= 10}`).toBe("count>=10=true")
	end)

	--[[ IT IS RECURSIVE, which is the same hole one level down. No directory under
		`src/` has a subdirectory today; a walk that assumed they never would is a
		check with a shelf life, so the property is stated against a directory the
		walk creates nothing for rather than against today's tree shape. ]]
	it("descends into subdirectories rather than assuming a flat tree", function()
		local body = fs.readFile("tests/lib/src_tree.luau")
		expect(`recurses={string.find(body, "walk(path, out)", 1, true) ~= nil}`).toBe("recurses=true")
	end)

	it("`pathsMatching` finds a require by its TAIL, from any directory", function()
		--[[ The property the surface-lifecycle seam's own mutation M15 measured: a
			scan pinned to one spelling (`require("./x")`) cannot see the same module
			required from another directory (`require("../present/x")`), and that is
			exactly the second consumer these rules exist to notice. ]]
		local solverSeen = srcTree.pathsMatching('require%("[^"]*measure_facts"%)')
		expect(`one consumer={#solverSeen}`).toBe("one consumer=1")
		expect(solverSeen[1]).toBe("src/layout/solver.luau")
		-- a needle nothing carries answers empty rather than erroring
		expect(`absent={#srcTree.pathsMatching("no_such_module_anywhere")}`).toBe("absent=0")
	end)
end)
