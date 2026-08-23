--!strict
--[[ src_tree — EVERY `.luau` FILE UNDER `src/`, ONE ENUMERATION.

	`src_tree.paths()` walks `src/` recursively and returns every `.luau` file
	path, sorted. `src_tree.readAll()` returns `{ path -> contents }` over the same
	set.

	WHY IT EXISTS, and it is a defect rather than a tidy-up (rulings P5 + PRES-X
	minor, executed 2026-08-22). Two seam specs — `measure_facts_seam.spec.luau`
	and `surface_lifecycle_seam.spec.luau` — each proved "there is exactly ONE
	consumer of this module in `src/`" by iterating a HAND-WRITTEN LIST of nine
	directories:

	    src/layout · src/render · src/present · src/controls · src/client
	    src/tokens · src/themes · src/input · src/core

	`src/` has FIFTEEN, and thirteen `.luau` files at its top level. So `src/async`,
	`src/env`, `src/focus`, `src/motion`, `src/preview`, `src/replication` and every
	one of `src/blueprint.luau`, `src/blueprint_schema.luau`, `src/init.luau`,
	`src/mount.luau`, `src/region_expand.luau` and the rest were invisible to both
	checks. A second consumer appearing in any of them would have been reported as
	"exactly one", which is the class of check this repository has had to delete
	before: one that cannot fail for the case it exists to catch.

	IT IS ALSO NOT RECURSIVE PER DIRECTORY, which is the same hole one level down —
	`src/render/…` and `src/controls/…` have no subdirectories today and a check
	that assumes they never will is a check with a shelf life.

	ONE ENUMERATION, TWO READERS, and the day a third seam spec needs it the list
	is already right. `tests/src_tree.spec.luau` proves the walk actually reaches
	the directories the old list missed, so this file cannot silently regress into
	the shape it replaces.
]]

local fs = require("@lune/fs")

local src_tree = {}

local ROOT = "src"

local function walk(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			walk(path, out)
		elseif fs.isFile(path) and string.sub(path, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

-- every `.luau` under `src/`, sorted so a failure names the same file every run
function src_tree.paths(): { string }
	local out: { string } = {}
	walk(ROOT, out)
	table.sort(out)
	return out
end

-- ...and their contents, for the source-scanning checks that read every one
function src_tree.readAll(): { [string]: string }
	local out: { [string]: string } = {}
	for _, path in src_tree.paths() do
		out[path] = fs.readFile(path)
	end
	return out
end

--[[ every file under `src/` whose text contains `needle`, sorted. The one
	question both seam specs actually ask ("who requires this module?"), asked over
	the whole tree instead of over nine of its fifteen directories. ]]
function src_tree.pathsContaining(needle: string): { string }
	local out: { string } = {}
	for path, body in src_tree.readAll() do
		if string.find(body, needle, 1, true) ~= nil then
			table.insert(out, path)
		end
	end
	table.sort(out)
	return out
end

--[[ ...and the same question asked with a Luau PATTERN, for the consumer scans
	that must match a require by its TAIL rather than by one spelling of it: a scan
	pinned to `require("./x")` cannot see `require("../present/x")` from another
	directory, which is exactly the second consumer such a rule exists to notice. ]]
function src_tree.pathsMatching(pattern: string): { string }
	local out: { string } = {}
	for path, body in src_tree.readAll() do
		if string.find(body, pattern) ~= nil then
			table.insert(out, path)
		end
	end
	table.sort(out)
	return out
end

return src_tree
