--!strict
--[[ THE PUBLIC SURFACE, PRINTED IN A STABLE ORDER.

	Every export of `src/init.luau`, its Luau type, one level into each exported
	sub-table (`UI`, `themes`, `motion`, `tokens`, …), the version, and the full
	deprecation ledger — sorted, so two runs over the same tree are byte-identical
	and a diff is a change to the public API rather than to table iteration order.

	WHAT USES IT. Two gate rows redirect this into a file and compare: one asserts
	the surface did not move across a cleanup, the other that the constructor
	namespace, the version and the deprecation rows are what the naming decision
	says they are. Both had been silently disabled — the instrument was a
	`_probe_`-prefixed script that went into the archive with the stage record,
	so the producer reported "not present in this tree", both rows degraded to a
	non-blocking environment failure, and the public-API guard stopped guarding
	anything. Restored under a name that says it is a tool.

	WHAT IT IS NOT. A snapshot instrument, not a test.
	`tests/api_surface.spec.luau` owns the versioning and ledger SHAPE rules, and
	`tools/lune/check_docs` owns drift between this surface and the API
	catalogue. This prints; the caller decides.

	Usage: lune run tools/lune/check_public_surface ]]

local fs = require("@lune/fs")

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

--[[ ...AND IT IS WRITTEN DOWN, not only printed.
	Two rows read `artifacts/verify/public-surface.txt` -- one pins it as
	evidence, one greps the version out of it -- and NOTHING regenerated it. The
	file on the machine that wrote it was months old and no clone ever had one,
	so both rows were reading an operand that a fresh checkout could not
	produce: an evidence trail with no source. The dump is the tool's output,
	so the tool writes it. ]]
local dump = table.concat(lines, "\n")
print(dump)
if not fs.isDir("artifacts") then
	fs.writeDir("artifacts")
end
if not fs.isDir("artifacts/verify") then
	fs.writeDir("artifacts/verify")
end
fs.writeFile("artifacts/verify/public-surface.txt", dump .. "\n")
