--!strict
-- Public-surface dump (Step 5.5 cleanup evidence). Prints the exported Facet
-- surface — every key, its Luau type, and one level into the exported
-- sub-tables (`UI`, `themes`, `motion`, `tokens`, …) — plus the version and the
-- full DEPRECATIONS ledger, in a stable sorted order.
--
-- ADR-0011 freezes exports and deprecation timing for this stage, so the check
-- is byte equality of this dump before and after the cleanup. It is a snapshot
-- instrument, not a test: tests/api_surface.spec.luau owns the semver/ledger
-- SHAPE rules, and tools/lune/check_docs owns api.md drift.
-- Usage: lune run tools/lune/_probe_public_surface

local Facet = require("../../src") :: any

local lines: { string } = {}

local function sortedKeys(t: { [string]: any }): { string }
	local keys: { string } = {}
	for k in t do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	return keys
end

local function describe(value: any): string
	local kind = type(value)
	if kind == "table" then
		return if table.isfrozen(value) then "table(frozen)" else "table"
	end
	return kind
end

table.insert(lines, `VERSION {Facet.VERSION}`)

for _, key in sortedKeys(Facet) do
	local value = Facet[key]
	if key == "DEPRECATIONS" then
		continue -- dumped in full below
	end
	table.insert(lines, `{key} : {describe(value)}`)
	if type(value) == "table" then
		for _, sub in sortedKeys(value) do
			table.insert(lines, `  {key}.{sub} : {describe(value[sub])}`)
		end
	end
end

table.insert(lines, "DEPRECATIONS:")
local entries: { any } = {}
for _, entry in Facet.DEPRECATIONS :: { any } do
	table.insert(entries, entry)
end
table.sort(entries, function(a, b)
	return tostring(a.surface) < tostring(b.surface)
end)
for _, entry in entries do
	table.insert(
		lines,
		`  {entry.surface} | since={entry.since} | removeNoEarlierThan={entry.removeNoEarlierThan} `
			.. `| replacement={entry.replacement} | note={tostring(entry.note)}`
	)
end

print(table.concat(lines, "\n"))
