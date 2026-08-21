--!strict
-- THE CLOSED-KEY GUARD (constitution §4).
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

local textDistance = require("./text_distance")

local spec_guard = {}

export type KeySet = { [string]: boolean }

--[[ "Did you mean" for an unknown key, cheap and bounded. THE THRESHOLD IS
	WRITTEN HERE (ARCH-17): distance <= 2, case-SENSITIVE. It used to be implicit
	in a `bestD = 3` initialiser inside a private copy of the matrix, which is how
	this module and `src/themes/package.luau` came to agree while
	`src/blueprint_schema.luau` and the two motion registries used a
	length-scaled, case-folded threshold — five suggesters, two policies, one
	framework, and no decision anywhere.

	The old comment said the copy was "kept local because this module must stay
	dependency-free". `src/text_distance.luau` requires nothing either, so nothing
	is given up: a leaf may require a leaf. ]]
local NEAREST_MAX_DISTANCE = 2

local function nearest(bad: string, known: KeySet): string?
	return textDistance.nearest(bad, known, NEAREST_MAX_DISTANCE)
end

local function sortedNames(known: KeySet): string
	return textDistance.listOf(known)
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
