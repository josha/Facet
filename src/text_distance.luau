--!strict
--[[ "DID YOU MEAN …?", ONCE (architecture review ARCH-17; reuse audit REUSE-5).

	Five modules carried a bounded Levenshtein matrix — `src/spec_guard.luau`,
	`src/themes/package.luau`, `src/blueprint_schema.luau`, `src/motion/classes.luau`
	and `src/motion/curves.luau` — the last three byte-identical 24-line bodies. The
	duplication was not the interesting part. The THRESHOLDS were:

	  · `spec_guard` and `themes/package` accept distance <= 2, case-SENSITIVELY.
	  · `blueprint_schema`, `motion/classes` and `motion/curves` lowercase both
	    sides and accept `d <= max(2, floor(#name / 3))`.

	So a misspelled prop and a misspelled curve name got different suggestion
	policies from one framework, and nobody had ever decided that. This module
	owns the ARITHMETIC and the list renderer; the POLICY stays at each call site,
	written out, because that is the decision worth being able to read. When
	someone eventually settles the case-folding question, there is now one place to
	settle it and five call sites to point at.

	`src/spec_guard.luau:42` used to explain its copy as "kept local because this
	module must stay dependency-free". That reasoning was backwards: `spec_guard`
	has zero requires, so the direction that follows is that anything may require
	*it* — and a leaf may require another leaf without giving anything up. This
	module requires nothing, so `spec_guard` is still reachable from every layer.

	BOUNDED, AND WHY IT MATTERS: the matrix is O(#a × #b) over a candidate set that
	is a spec's key list (tens), run only on the error path, so cost is irrelevant
	here — but `table.create` + two rolling rows is what every copy already did and
	is preserved exactly, so an error message that was produced before is produced
	now.
]]

local text_distance = {}

--[[ Damerau-free Levenshtein: insertions, deletions and substitutions, no
	transposition. Two rolling rows rather than a full matrix. Byte-wise, so it
	measures BYTES and not Unicode scalars — correct for identifiers, which is all
	this is ever handed. ]]
function text_distance.distance(a: string, b: string): number
	local la, lb = #a, #b
	if la == 0 then
		return lb
	end
	if lb == 0 then
		return la
	end
	local prev = table.create(lb + 1, 0)
	local cur = table.create(lb + 1, 0)
	for j = 0, lb do
		prev[j + 1] = j
	end
	for i = 1, la do
		cur[1] = i
		local ca = string.byte(a, i)
		for j = 1, lb do
			local cost = if ca == string.byte(b, j) then 0 else 1
			cur[j + 1] = math.min(cur[j] + 1, prev[j + 1] + 1, prev[j] + cost)
		end
		prev, cur = cur, prev
	end
	return prev[lb + 1]
end

--[[ The closest candidate within `maxDistance`, or nil. `candidates` is a SET
	(`{ [name]: true }`) — the shape both closed-key-set callers already hold.

	`maxDistance` is REQUIRED, with no default, on purpose: a suggester whose
	threshold is invisible is how two of them ended up disagreeing. Pass 2 for the
	closed-key-set behaviour the two set callers have always had.

	Ties: FIRST-WINS in iteration order, which for a set is hash order — exactly
	what both callers did before, and preserved rather than repaired because
	"repairing" it changes error text that specs pin. A caller that needs
	determinism should score explicitly with `distance`, the way `schema.suggest`
	does. ]]
function text_distance.nearest(bad: string, candidates: { [string]: any }, maxDistance: number): string?
	local best: string? = nil
	local bestD = maxDistance + 1
	for name in candidates do
		local d = text_distance.distance(bad, name)
		if d < bestD then
			best, bestD = name, d
		end
	end
	return best
end

--[[ The legal set as one sorted sentence. `separator` defaults to `", "`; the
	theme compiler passes `" | "`. It was the same function twice with different
	punctuation in the error an author reads — which is a real difference worth
	keeping and not a reason for a second implementation. ]]
function text_distance.listOf(candidates: { [string]: any }, separator: string?): string
	local out: { string } = {}
	for name in candidates do
		table.insert(out, name)
	end
	table.sort(out)
	return table.concat(out, separator or ", ")
end

return text_distance
