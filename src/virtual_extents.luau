--!strict
--[[ THE RUNNING-OFFSET INDEX — the arithmetic a virtualized list windows by.

	PUBLIC INTERFACE
	  virtual_extents.uniform(count, extent, gap) -> Index
	  virtual_extents.variable(extents: {number}, gap) -> Index
	  Index = { count, content,
	            offsetOf(i) -> px, extentOf(i) -> px,
	            window(top, viewport, overscan) -> (first, last),
	            slotAt(offset) -> 0-based insertion slot,
	            boundaryOffset(slot) -> px }

	DEPENDS ON NOTHING. Pure arithmetic over numbers: no core, no blueprint, no
	engine, no theme. That is deliberate — this is the load-bearing half of
	variable item extents and it is the half that is provable in a terminal.

	WHY IT EXISTS. `newVirtualList` windowed by `index x pitch` for its whole life
	(`src/controls/virtual_list.luau`). That is O(1) and exact ONLY because the
	pitch is one number, and the price was that the CONSUMER had to predict its own
	row's extent for every live fact the row reads — viewport, typography scale,
	theme metrics, accessibility text preference. The widened overflow sweep
	measured what that costs: a `row_actions` row declares 84px and measures 88 at
	the default text preference, and 249 at `preferredTextOffset = 14` on a 320x640
	phone (`docs/handoff/2026-08-13-rulings-needed.md` ruling 7, ruled 2026-08-13).
	Variable extents need the other arithmetic — a PREFIX SUM, searched rather than
	divided — and this module is it.

	TWO INDEXES, ONE SHAPE, AND THE UNIFORM ONE IS UNCHANGED. `uniform` is today's
	formulas verbatim, expressed through the same interface so the control has ONE
	vocabulary instead of two code paths that could drift. It allocates no table
	and answers every query in O(1); a list that does not use variable extents pays
	this module nothing beyond one constructor call per data change.

	`variable` builds a prefix sum — O(N) ARITHMETIC, once per data change, no item
	built and nothing measured — and every query after it is O(log N) by binary
	search. That distinction is the whole design: virtualization's promise is not
	to BUILD or MEASURE what you cannot see, and adding up N numbers breaks
	neither. `tests/virtual_extents.spec.luau` counts the extent reads to hold the
	queries to it.

	THE VARIABLE INDEX CONTAINS THE UNIFORM ONE. With every extent equal, both
	answer identically for `content`, `offsetOf`, `extentOf`, `slotAt`,
	`boundaryOffset`, and for `window` at every slot-aligned offset. The single
	deliberate divergence is `window` at a FRACTIONAL offset — see `window` below.

	VOCABULARY. Everything here is on the list's own scroll AXIS and in CANVAS
	space (offset 0 = the start of the content, never the viewport). "Extent" is
	the item's own size on that axis; "pitch" is extent + gap, i.e. the slot; the
	gap is dead space between slots and the content carries no TRAILING gap, so N
	slots span `sum(extent) + (N-1)*gap`. All of that is `virtual_list.luau`'s
	existing contract, moved here rather than re-invented.
]]

local virtual_extents = {}

export type Index = {
	-- how many items the index spans
	count: number,
	-- the full canvas extent: sum of every item, plus one gap BETWEEN each pair
	content: number,
	-- the canvas offset of slot `index`'s leading edge (1-based; out of range
	-- clamps to the nearest real slot, so a row unmounting mid-flight cannot
	-- produce a nil offset)
	offsetOf: (index: number) -> number,
	-- one item's own size along the axis (the row box, never its slot)
	extentOf: (index: number) -> number,
	-- the mounted band for a viewport at `top`: 1-based inclusive `first, last`,
	-- clamped to the data. `last < first` means "nothing to mount" (empty list).
	window: (top: number, viewport: number, overscan: number) -> (number, number),
	-- the 0-based INSERTION slot nearest a canvas offset: how many whole items
	-- the offset has passed the midpoint of. 0 = before everything, count = after.
	slotAt: (offset: number) -> number,
	-- where the insertion hairline is drawn for a 0-based slot: the middle of the
	-- gutter above it, clamped into the canvas so the first and last boundaries
	-- stay inside the host that clips them
	boundaryOffset: (slot: number) -> number,
}

--[[ ── THE UNIFORM INDEX — today's arithmetic, unchanged ──────────────────────
	Every line here is the formula it replaces in `virtual_list.luau`, kept in the
	same shape so a reader can check them off against each other. Nothing is
	allocated per item; `count` is the only thing it needs to know about the data. ]]
function virtual_extents.uniform(count: number, extent: number, gap: number): Index
	local pitch = extent + gap
	local content = if count <= 0 then 0 else count * extent + (count - 1) * gap
	local ix: Index
	ix = {
		count = count,
		content = content,
		offsetOf = function(index: number): number
			return (math.clamp(index, 1, math.max(1, count)) - 1) * pitch
		end,
		extentOf = function(_index: number): number
			return extent
		end,
		window = function(top: number, viewport: number, overscan: number): (number, number)
			--[[ THE PRE-FEATURE FORMULA, BYTE FOR BYTE. The visible COUNT comes from
				the viewport alone and is therefore independent of where between two
				slots the scroll sits, which at a fractional offset names one row fewer
				than the viewport actually touches; `overscan` (default 2) has always
				covered it. Kept exactly rather than tightened: it is the baseline every
				shipped list, every window assertion in the suite and the perf lab's
				instance counts were measured against, and tightening it is its own
				change with its own before/after (`docs/plans/variable-item-extents.md`). ]]
			if pitch <= 0 then
				return 1, count
			end
			local firstVisible = math.floor(top / pitch) + 1
			local visibleCount = math.ceil(viewport / pitch)
			return math.max(1, firstVisible - overscan), math.min(count, firstVisible + visibleCount - 1 + overscan)
		end,
		slotAt = function(offset: number): number
			if pitch <= 0 then
				return 0
			end
			return math.clamp(math.floor((offset + pitch / 2) / pitch), 0, count)
		end,
		boundaryOffset = function(slot: number): number
			return math.clamp(slot * pitch - gap / 2, 0, content)
		end,
	}
	return ix
end

--[[ ── THE VARIABLE INDEX — a prefix sum, searched ────────────────────────────
	`starts[i]` is the canvas offset of slot i's LEADING edge, so `starts[1]` is
	always 0 and `starts[i+1] = starts[i] + extents[i] + gap`. One pass to build,
	binary search to query.

	NUMERIC `for`, NOT `ipairs`/generic-for, ON PURPOSE: the spec hands this a
	table whose extents are served through `__index` so it can COUNT the reads,
	and a generic-for would iterate its (empty) array part and see nothing. A
	measurement instrument that silently reads zero is exactly the trap
	`docs/lessons/the-solver-already-told-you.md` is about. ]]
function virtual_extents.variable(extents: { number }, gap: number): Index
	local count = #extents
	local starts = table.create(math.max(count, 1))
	local run = 0
	for i = 1, count do
		starts[i] = run
		run += extents[i] + gap
	end
	-- the content drops the TRAILING gutter the running sum just added
	local content = if count <= 0 then 0 else run - gap

	-- the 1-based slot whose band contains `offset`: the largest i with
	-- starts[i] <= offset, clamped into the data. An offset past the end clamps to
	-- the last slot, which is what a garbage or overshooting scroll mirror needs.
	local function slotContaining(offset: number): number
		if count <= 0 then
			return 1
		end
		if offset <= 0 then
			return 1
		end
		local lo, hi = 1, count
		while lo < hi do
			-- the upper midpoint, so `lo = mid` always makes progress
			local mid = lo + math.floor((hi - lo + 1) / 2)
			if starts[mid] <= offset then
				lo = mid
			else
				hi = mid - 1
			end
		end
		return lo
	end

	local ix: Index
	ix = {
		count = count,
		content = content,
		offsetOf = function(index: number): number
			if count <= 0 then
				return 0
			end
			return starts[math.clamp(index, 1, count)]
		end,
		extentOf = function(index: number): number
			if count <= 0 then
				return 0
			end
			return extents[math.clamp(index, 1, count)]
		end,
		window = function(top: number, viewport: number, overscan: number): (number, number)
			--[[ THE EXACT RULE, because there is no count to take. With ragged
				extents "how many items fit in 498px" has no answer — one tall row can
				fill the viewport on its own — so the question asked is the exact one:
				which slot holds the viewport's LEADING edge, and which holds its
				TRAILING edge. That makes this window a strict SUPERSET of the uniform
				one at every offset, never a subset: no row the viewport touches is
				left unmounted. ]]
			if count <= 0 then
				return 1, 0
			end
			local firstVisible = slotContaining(top)
			local lastVisible = slotContaining(top + math.max(0, viewport))
			return math.max(1, firstVisible - overscan), math.min(count, lastVisible + overscan)
		end,
		slotAt = function(offset: number): number
			--[[ HOW MANY ITEMS' MIDPOINTS THIS OFFSET HAS PASSED. Uniform reads
				`floor((y + pitch/2) / pitch)`; with ragged extents the midpoints are not
				evenly spaced, so it is a search — but on the SAME predicate, which is
				what makes the two agree when the extents are equal. The midpoint band is
				monotone in i (starts is increasing and every extent is positive), so a
				binary search is exact. ]]
			if count <= 0 then
				return 0
			end
			local function passed(i: number): boolean
				return starts[i] + (extents[i] + gap) / 2 <= offset
			end
			if not passed(1) then
				return 0
			end
			local lo, hi = 1, count
			while lo < hi do
				local mid = lo + math.floor((hi - lo + 1) / 2)
				if passed(mid) then
					lo = mid
				else
					hi = mid - 1
				end
			end
			return lo
		end,
		boundaryOffset = function(slot: number): number
			-- the middle of the gutter above slot `slot` (0-based), i.e. just before
			-- the item that would follow it. Past the end it is the canvas end; the
			-- clamp reproduces the uniform form's own clamp at both edges.
			local raw = if slot < count and count > 0 then starts[slot + 1] - gap / 2 else content + gap / 2
			return math.clamp(raw, 0, content)
		end,
	}
	return ix
end

return virtual_extents
