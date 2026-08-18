--!strict
-- THE CLOSED-KEY GUARD (constitution §4; architecture finding ARCH-1).
--
-- §4 states as shipped fact that "an unknown key ... is an immediate error —
-- never a value that silently does nothing", and that the rule "applies to
-- modifier specs and control specs exactly as to UI.* props". It did not: the
-- blueprint layer refused junk, but every composite control spec and every
-- service/model opts table accepted it silently, so
-- `newSlider(…, { tapToPositon = false })` built a slider that ignored the
-- option, and `newResourceProvider(core, { maxConcurent = 8 })` capped nothing.
-- That is the accepted-and-ignored class the strict boundary exists to remove,
-- and it is worse on an opts table than on a prop: a misspelled option is
-- indistinguishable from a working one until something misbehaves in
-- production.
--
-- ONE helper, engine-free, no dependencies, so it is legal from any layer:
--
--   guard.assertKnownKeys("newSlider", spec, SLIDER_KEYS, "spec")
--
-- Contract:
--   * nil and empty tables are legal — every guarded boundary already decides
--     for itself whether the table is required, and this helper never invents a
--     requirement (it is a CLOSED-SET check, not a schema);
--   * a non-table is left alone for the same reason: the boundary's own
--     type assertion owns that message, and two errors for one mistake is
--     noise;
--   * a non-string key is refused too — `{ [1] = … }` on a keyed spec is the
--     same authoring mistake wearing a different hat;
--   * the message NAMES the boundary, the offending key, and the full sorted
--     legal set, with a bounded "did you mean" when the key is close to a real
--     one (the same Levenshtein <= 2 rule the theme package uses). A closed set
--     is only useful if the error tells you what the set is.
--
-- `known` is a SET (`{ [string]: true }`) rather than an array so a caller can
-- build it once at module scope and freeze it; the sorted list is derived here.

local spec_guard = {}

export type KeySet = { [string]: boolean }

-- "did you mean" for an unknown key, cheap and bounded (Levenshtein <= 2).
-- Mirrors src/themes/package.luau's `nearest`; kept local because this module
-- must stay dependency-free (it is required from src/, controls, input,
-- present, render and async alike).
local function nearest(bad: string, known: KeySet): string?
	local best: string? = nil
	local bestD = 3
	for name in known do
		local la, lb = #bad, #name
		local prev = table.create(lb + 1, 0)
		local cur = table.create(lb + 1, 0)
		for j = 0, lb do
			prev[j + 1] = j
		end
		for i = 1, la do
			cur[1] = i
			for j = 1, lb do
				local cost = if string.byte(bad, i) == string.byte(name, j) then 0 else 1
				cur[j + 1] = math.min(cur[j] + 1, prev[j + 1] + 1, prev[j] + cost)
			end
			prev, cur = cur, prev
		end
		local d = prev[lb + 1]
		if d < bestD then
			best, bestD = name, d
		end
	end
	return best
end

local function sortedNames(known: KeySet): string
	local out: { string } = {}
	for name in known do
		table.insert(out, name)
	end
	table.sort(out)
	return table.concat(out, ", ")
end

-- assertKnownKeys(where, tbl, known, kind)
--   where — the PUBLIC name of the boundary as the author typed it
--           ("newSlider", "presenter.present", "UI.mount"), never the internal
--           module path: the error has to be greppable from the call site.
--   kind  — "spec" | "opts", so the sentence reads the way the API does.
function spec_guard.assertKnownKeys(where: string, tbl: any, known: KeySet, kind: string)
	if type(tbl) ~= "table" then
		return
	end
	for key in tbl do
		if type(key) ~= "string" or known[key] ~= true then
			local shown = tostring(key)
			local suggestion = if type(key) == "string" then nearest(key, known) else nil
			local didYouMean = if suggestion ~= nil then ` Did you mean '{suggestion}'?` else ""
			error(`Facet {where}: unknown {kind} key '{shown}'.{didYouMean} Known: {sortedNames(known)}.`, 0)
		end
	end
end

-- Build a frozen key set from an array of names — the shape most call sites
-- want to write, and the one that keeps the legal set readable in the source.
function spec_guard.keySet(names: { string }): KeySet
	local set: KeySet = {}
	for _, name in names do
		set[name] = true
	end
	return table.freeze(set)
end

return table.freeze(spec_guard)
