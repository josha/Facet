--!strict
--[[ THE ANCESTOR CLOSURE OVER A REFRESH'S DIRTY LIST, lifted out of
	`render/renderer.luau` (Plan C, T3 step 0b) for the Source-write headroom the
	coordinate-space work needs. Over the cap a module silently stops live-syncing
	into an open Studio session, so a live check tests the built place rather than
	the edits on disk — which is why this file's ledger row exists at all.

	IT IS A PURE FUNCTION OF ITS ARGUMENT, which is the strongest one-way claim a
	seam out of that file can make: no `deps` record, no adapter, no upvalue of the
	host, nothing but the list it is handed and two fresh tables.
	`tests/dirty_closure_seam.spec.luau` is the proof. ]]

local dirty_closure = {}

--[[ A node may be skipped only if NOTHING inside it is dirty, so the set handed to
	the solver is every dirty node plus every ancestor of one — the solver skips
	exactly the nodes absent from it. Paths are `/a/b/c`, so the ancestors are the
	prefixes.

	TWO CLOSURES, NOT ONE (wicked-fast O2). The measure half carries `measure` dirt
	and its prefixes alone — an offset-only change cannot prove a slate stale. The
	walk terminates PER SET: an arrange entry that filled a chain must not cut a
	measure one's.

	Returns `(contains, measures)`: the arrange-and-measure closure, and the measure
	half alone. ]]
function dirty_closure.of(dirty: { any }): ({ [string]: boolean }, { [string]: boolean })
	local contains: { [string]: boolean } = {}
	local measures: { [string]: boolean } = {}
	for _, entry in dirty do
		local path = entry.path
		local isMeasure = entry.class == "measure"
		if (isMeasure or entry.class == "arrange") and path ~= nil then
			-- the set THIS entry terminates on. An arrange entry's two writes land on
			-- `contains` twice, which is a no-op.
			local target = if isMeasure then measures else contains
			contains[path] = true
			target[path] = true
			local at = path
			while true do
				local cut = string.match(at, "^(.*)/[^/]*$")
				if cut == nil or cut == "" then
					break
				end
				local seen = target[cut]
				contains[cut] = true
				target[cut] = true
				if seen then
					break
				end
				at = cut
			end
		end
	end
	return contains, measures
end

return dirty_closure
