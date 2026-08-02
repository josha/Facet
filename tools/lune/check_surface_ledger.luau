--!strict
-- Surface-ledger coverage check (stage api-architecture-consistency, ENF-5).
--
-- The stage's headline claim is "every public item is classified: a named
-- pattern or a justified exception". A ledger that silently omits an export is
-- exactly the unverifiable-coverage shape the gate-integrity sweep removed
-- elsewhere, so this check makes the claim mechanical:
--
--   1. every top-level export and every nested namespace member of the LIVE
--      public surface (required fresh from src/, never a stored dump) appears
--      backticked in artifacts/api-architecture-consistency/surface-ledger.md;
--   2. the constitution exists and is linked from the guide index and from
--      every extension playbook (an unlinked rulebook is a rulebook nobody
--      finds — the same rule check_docs applies to the theme chapter);
--   3. the ledger names the constitution and the dispositions file, so the
--      classification chain (item -> pattern/exception -> ruling) is walkable.
--
-- Usage: lune run tools/lune/check_surface_ledger   (exit 0 = PASS)

local fs = require("@lune/fs")
local process = require("@lune/process")

local LEDGER = "artifacts/api-architecture-consistency/surface-ledger.md"
local CONSTITUTION = "docs/reference/constitution.md"
local GUIDE_INDEX = "docs/guide/README.md"
local PLAYBOOK_DIR = "docs/extending"

local problems: { string } = {}

local LuauUI = require("../../src") :: any

local ledger = if fs.isFile(LEDGER) then fs.readFile(LEDGER) else nil
if ledger == nil then
	print(`check_surface_ledger: FAIL — {LEDGER} does not exist`)
	process.exit(1)
end

-- 1. coverage: every export name, and every nested member as `ns.member`.
-- The ledger may cover a set of members with one row, but each NAME must be
-- present somewhere in backticks — coverage is textual and checkable, and a
-- rename or a new export fails here the day it lands.
local function covered(name: string): boolean
	return string.find(ledger :: string, "`" .. name .. "`", 1, true) ~= nil
end

local function sortedKeys(t: { [string]: any }): { string }
	local keys: { string } = {}
	for k in t do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	return keys
end

for _, key in sortedKeys(LuauUI) do
	if key == "DEPRECATIONS" or key == "VERSION" then
		if not covered(key) then
			table.insert(problems, `metadata '{key}' has no ledger row`)
		end
		continue
	end
	local value = LuauUI[key]
	if not covered(key) then
		table.insert(problems, `top-level export '{key}' is not classified in the surface ledger`)
	end
	if type(value) == "table" then
		for _, sub in sortedKeys(value) do
			-- UI.* constructors are classified by their grouped rows; every
			-- other namespace member must appear qualified.
			local qualified = `{key}.{sub}`
			if key == "UI" then
				if not covered(qualified) and not covered(`UI.{sub}`) and not covered(sub) then
					table.insert(problems, `blueprint export 'UI.{sub}' is not classified in the surface ledger`)
				end
			elseif not covered(qualified) then
				table.insert(problems, `nested member '{qualified}' is not classified in the surface ledger`)
			end
		end
	end
end

-- 2. the constitution exists, and the ledger + docs point at it
if not fs.isFile(CONSTITUTION) then
	table.insert(problems, `{CONSTITUTION} does not exist`)
else
	if string.find(ledger :: string, "constitution.md", 1, true) == nil then
		table.insert(problems, "the surface ledger never names the constitution")
	end
	local guide = fs.readFile(GUIDE_INDEX)
	if string.find(guide, "constitution.md", 1, true) == nil then
		table.insert(problems, `{GUIDE_INDEX} does not link the constitution`)
	end
	for _, file in fs.readDir(PLAYBOOK_DIR) do
		if string.sub(file, -3) == ".md" then
			local text = fs.readFile(`{PLAYBOOK_DIR}/{file}`)
			if string.find(text, "constitution.md", 1, true) == nil then
				table.insert(problems, `{PLAYBOOK_DIR}/{file} does not link the constitution`)
			end
		end
	end
end

-- 3. the classification chain is walkable
if string.find(ledger :: string, "dispositions.md", 1, true) == nil then
	table.insert(problems, "the surface ledger never names dispositions.md")
end

if #problems > 0 then
	print(`check_surface_ledger: FAIL — {#problems} problem(s):`)
	for _, p in problems do
		print(`  - {p}`)
	end
	process.exit(1)
end

print("check_surface_ledger: PASS (every public export and nested member is classified; constitution linked)")
