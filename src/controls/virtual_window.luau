--!strict
--[[ VirtualList's WINDOWING ARITHMETIC — the running-offset index, the
	measurement cache, and every memo derived from them — lifted out of
	`virtual_list.luau` verbatim (2026-08-15, the 200,000-char Source-write cap;
	`tools/check_source_size.py`).

	WHAT IS HERE, and it is the whole answer to "where is slot i, and which slots
	does this viewport touch": `extentsFor` (the per-row extents, measured or
	declared), the cached `layoutIndex` over `../virtual_extents`, the row->index
	map, one row's declared extent, the canvas Dim, the clamped scroll offset, the
	keyed window, and the row-path spelling every caller keys on. `scrollTop` — the
	engine CanvasPosition mirror the clamp reads — is created here for the same
	reason: it is the index's one live input.

	WHY IT COULD LEAVE (the test `tools/check_source_size.py`'s header records):
	it writes exactly TWO mutable upvalues of `virtual_list.build`, `cachedInputs`
	and `cachedIndex`, and both are its own — declared inside the block, read
	nowhere else — so the state left with the code. Everything else it reads is a
	construction-time constant (`spec`, `id`, `axis`, `overscan`, the four
	`itemExtent*` verdicts) or a `local function` that is never reassigned
	(`itemExtentIn`, `estimateIn`, `rowGapIn`, `viewportIn`). None of them
	entangles, so they are threaded as an explicit `Deps` argument rather than
	captured.

	WHAT DELIBERATELY STAYED BEHIND: `measuredCount` and the prune/selection
	observer, and `measureWindow` — the `syncGeometry` seam that fills the cache.
	The cache tables themselves (`measured`, `lastRowExtent`) and the epoch signal
	are exported BY REFERENCE and mutated in place by that seam, which is why the
	seam did not have to move with them. `measuredCount` is a plain NUMBER, and a
	number cannot be shared by reference — moving it would have cost an accessor
	at two call sites to buy nothing.

	DEPENDS ON: `../virtual_extents` (shared with `virtual_grid.luau` — pure, and
	untouched by this split). Consumed only by `./virtual_list.luau`, which rebinds
	every export to a local of its original name so no call site in that file
	changed. ]]

local virtual_extents = require("../virtual_extents")
-- `rect.sameFlatValue`: the framework's one field-for-field equality for a FLAT
-- record. Used here as the canvas Dim's memo eq (see `canvasDim`); the renderer
-- and the selection indicator already share it for the same reason.
local rect = require("../rect")

local virtual_window = {}

export type Deps = {
	core: any,
	listScope: any,
	spec: any,
	id: string,
	axis: string,
	overscan: number,
	-- the four `itemExtent` verdicts, decided once at construction
	itemExtentSpec: any,
	itemExtentIsVariable: boolean,
	itemExtentIsMeasured: boolean,
	itemExtentIsPerItem: boolean,
	-- the live readers of the four numbers this arithmetic is made of. Every one
	-- is a `local function` in the caller and is never reassigned, so it goes by
	-- value.
	itemExtentIn: (any) -> number,
	estimateIn: (any) -> number,
	rowGapIn: (any) -> number,
	viewportIn: (any) -> number,
}

function virtual_window.new(deps: Deps)
	local core = deps.core
	local listScope = deps.listScope
	local spec = deps.spec
	local id = deps.id
	local axis = deps.axis
	local overscan = deps.overscan
	local itemExtentSpec = deps.itemExtentSpec
	local itemExtentIsVariable = deps.itemExtentIsVariable
	local itemExtentIsMeasured = deps.itemExtentIsMeasured
	local itemExtentIsPerItem = deps.itemExtentIsPerItem
	local itemExtentIn = deps.itemExtentIn
	local estimateIn = deps.estimateIn
	local rowGapIn = deps.rowGapIn
	local viewportIn = deps.viewportIn

	--[[ ── THE RUNNING-OFFSET INDEX (variable item extents, 2026-08-14) ───────────
		ONE PLACE ANSWERS "where is slot i, and which slots does this viewport
		touch". Everything that used to multiply by the pitch — the canvas extent,
		the scroll clamp, window membership, each row's canvas offset and box, the
		keep-visible target, the insertion slot and its hairline — reads it, so the
		two arithmetics can never disagree about the same list.

		WHICH ARITHMETIC IS CHOSEN ONCE, AT BUILD, on `itemExtentIsVariable`:

		  · UNIFORM (`virtual_extents.uniform`) is the pre-feature formulas verbatim.
		    It allocates nothing, answers in O(1), and every shipped list keeps the
		    numbers and the window it always had. Where a memo body would have gained
		    a dependency it did not have — a row's own extent, a row's own offset —
		    the branch below keeps the OLD body instead of routing through here, so a
		    uniform list's per-row reactivity is unchanged too.

		  · VARIABLE (`virtual_extents.variable`) builds a prefix sum: O(N)
		    ARITHMETIC once per data change — no item built, nothing measured — and
		    O(log N) per query. That distinction IS the design. Virtualization's
		    promise is not to build or measure what you cannot see, and adding up N
		    numbers breaks neither; the rejected alternative ("measure every item at
		    mount") breaks both, which is why `virtual_list_variable_extents.spec`
		    counts cell builds rather than timing anything.

		The extents are resolved INSIDE the memo, so a function that reads live facts
		through its `use` argument makes the whole table re-derive when they move. ]]
	--[[ ── THE MEASUREMENT CACHE (measured extents, Stage 2) ──────────────────────
		key -> the px this row's cell last MEASURED on the scroll axis. Written by
		`measureWindow` (the `syncGeometry` seam, far below), read by `extentsFor`,
		pruned with the data by the `indexByKey` observer.

		KEYED, NOT INDEXED, and that is load-bearing: a re-sort moves every index and
		moves no row's height, so an index-keyed cache would discard every
		measurement on a sort and re-converge from the estimate — a visible re-flow
		for a change that moved no geometry.

		THE EPOCH IS THE REACTIVE HANDLE, since a plain table is not a Readable.
		Bumped once per BATCH of changed measurements, never per row and never when
		nothing changed; `sameLayoutInputs` then compares the extents element-wise, so
		an epoch bump producing the same numbers rebuilds no index either. ]]
	local measured: { [string]: number } = {}
	local measuredCount = 0
	local measuredEpoch = listScope:own(core:signal(0))
	local function extentsFor(use: any): { number }
		local items = use(spec.rows) :: { any }
		local out = table.create(math.max(#items, 1))
		if itemExtentIsMeasured then
			-- the dependency on the measurements, declared once for the whole table
			use(measuredEpoch)
			local estimate = estimateIn(use)
			for i = 1, #items do
				out[i] = measured[spec.key(items[i])] or estimate
			end
			return out
		end
		for i = 1, #items do
			local px = (itemExtentSpec :: any)(items[i], i, use)
			if type(px) ~= "number" or px ~= px or px <= 0 then
				-- NAME THE ROW. On a 10,000-item list "itemExtent returned nil" without
				-- the key is a scavenger hunt, and the key is what the consumer's own
				-- data is addressed by.
				error(
					`newVirtualList '{id}': spec.itemExtent(item, {i}) returned {tostring(px)} for row `
						.. `'{tostring(spec.key(items[i]))}' — a per-item extent must be a positive number of px `
						.. "(the item's size along the list's own axis).",
					0
				)
			end
			out[i] = px
		end
		return out
	end
	--[[ THE INDEX IS CACHED ON ITS INPUTS, and the reason is worth writing down
		because the obvious spelling does not work.

		An index is six closures and a table. Building one is cheap; building one on
		every DATA EDIT is a tax every shipped list pays, and a list is edited far
		more often than its geometry moves (a rename, a live value ticking, a re-sort
		of equal-height rows). The obvious fix — hand `core:memo` an equality — does
		NOT do this: a memo's `eq` is OBSERVER-facing only (`src/core/custom.luau`,
		`notify`); `markMemosStale` invalidates the whole downstream subtree
		unconditionally and `pull` overwrites `node.value` without comparing. So the
		cache is inside the body, keyed on the numbers that actually decide the
		geometry, and it returns the SAME index object when none of them moved.

		THE JUSTIFICATION IS THE MECHANISM, NOT A NUMBER. The headless perf runner
		cannot resolve one allocation per edit: an A/A control on the list scenes
		measured a ±5%..±28% noise band, so no honest before/after exists at tier 1
		(device is authoritative — §14.3). What IS observable is the construction
		count, and `virtual_list_variable_extents.spec` counts it directly. ]]
	local function sameLayoutInputs(a: any, b: any): boolean
		if a == nil or b == nil or a.gap ~= b.gap then
			return false
		end
		if not itemExtentIsVariable then
			return a.count == b.count and a.extent == b.extent
		end
		local x, y = a.extents, b.extents
		if #x ~= #y then
			return false
		end
		for i = 1, #x do
			if x[i] ~= y[i] then
				return false
			end
		end
		return true
	end
	local cachedInputs: any = nil
	local cachedIndex: any = nil
	local layoutIndex = listScope:own(core:memo(function(use)
		local inputs: any = if itemExtentIsVariable
			then { extents = extentsFor(use), gap = rowGapIn(use) }
			else { count = #(use(spec.rows) :: { any }), extent = itemExtentIn(use), gap = rowGapIn(use) }
		if cachedIndex ~= nil and sameLayoutInputs(cachedInputs, inputs) then
			return cachedIndex
		end
		cachedInputs = inputs
		cachedIndex = if itemExtentIsVariable
			then virtual_extents.variable(inputs.extents, inputs.gap)
			else virtual_extents.uniform(inputs.count, inputs.extent, inputs.gap)
		return cachedIndex
	end))
	local function layoutNow(): any
		return layoutIndex:get() :: any
	end
	--[[ VALIDATE THE CURRENT DATA AT THE CALL SITE. A throwing memo body is
		QUARANTINED by the core (`src/core/custom.luau`'s `fail`) — it records the
		message and the memo reads `nil`, which downstream turns into "attempt to
		iterate over a nil value" three frames away from the mistake. That is the
		wrong channel for an authoring error, so the extents are resolved once here,
		outside any memo, where the error unwinds out of `build()` naming the row.

		THE COST IS ONE EXTRA PASS OVER THE DATA AT CONSTRUCTION and nothing after:
		the memo's own first pull would have made that pass regardless. Data that
		arrives LATER and is invalid still lands on the quarantine channel — the
		construction check is what makes the common case (a function that was always
		wrong) fail where it was written. ]]
	if itemExtentIsPerItem then
		extentsFor(function(readable: any): any
			return readable:get()
		end)
	end
	--[[ ── THE DECLARED SLOT, HANDED TO THE SOLVER (2026-08-13) ────────────────────
		This control makes the CONSUMER responsible for predicting its own row's
		extent — `index × itemExtent` is O(1) and exact only because that extent is
		one declared number — and for the whole life of the control nothing checked
		the prediction. The perf lab's own `rows.heightFor` is the case study: it
		learned the viewport width, then the type scale, then the theme insets, each
		one AFTER a device pass caught rows painting over each other, and never
		learned the accessibility text preference at all (at `preferredTextOffset`
		4/10/14 every row overflowed its 56px slot by 11/39/59px).

		SO THE ROW CARRIES ITS OWN DECLARATION DOWN TO THE ONE PLACE THAT KNOWS THE
		TRUTH. The extent is not knowable here — it is a function of the viewport,
		the typography scale, the theme metrics and the text preference, and the
		first two are not decided until a solve — so this is not a construction
		refusal but a fact the solver checks per solve and reports through
		`controller.diagnostics()` (the channel `tests/overflow_sweep.spec.luau`
		already fails the suite on).

		ONE TABLE FOR THE WHOLE LIST ON THE UNIFORM PATH, not one per row: every
		field is a property of the LIST, and the row's own identity is already its
		node path (`…/W/[key]/Row/…`), which is what the finding is filed under. A
		row's marginal cost is one prop assignment. It is a memo only because
		`itemExtent` may be a Readable; a plain number resolves it once and never
		again.

		UNDER VARIABLE EXTENTS THE DECLARATION IS PER ROW, because that is what it
		now is — see `rowSlotDeclaration`. The guard does not go away with this
		feature and must not: a declared per-item extent is still a PREDICTION, so a
		row can still exceed it, and now the finding names that row's own number
		instead of one list-wide one.

		IT PUBLISHES THE DECLARED EXTENT, NEVER THE ROW'S CURRENT BOX — a hosted
		row-actions commit collapse drives one row's box down its own height ladder
		on purpose, and comparing against the box would make that animation shout. ]]
	-- child 1 is the control's own full-row hit Button; the consumer's cell is
	-- everything from 2 on (a cell that is a `UI.When`/`UI.ForEach` splices
	-- several children in, and they all sit after the hit)
	local SLOT_CONTENT_FROM = 2
	local slotDeclaration = if itemExtentIsVariable
		then nil
		else listScope:own(core:memo(function(use)
			return {
				list = id,
				axis = axis,
				extent = itemExtentIn(use),
				contentFrom = SLOT_CONTENT_FROM,
			}
		end))
	--[[ scrollTop: the engine CanvasPosition MIRROR (the native substrate). Fed
		by bindNativeScroll (engine observer) or a test; NEVER a hand-rolled offset.

		IT IS THE OFFSET ON THE LIST'S OWN AXIS — `CanvasPosition.Y` on
		`axis = "y"`, `CanvasPosition.X` on `axis = "x"`. The NAME is vertical and
		is kept anyway, deliberately: it is public API that consumers and tests
		read by name, and renaming it would be a breaking change this field does
		not need. Read it as "the offset from the start of the canvas". ]]
	local scrollTop = listScope:own(core:signal(0))
	-- key -> 1-based index in the CURRENT data
	local indexByKey = listScope:own(core:memo(function(use)
		local map: { [string]: number } = {}
		for i, item in use(spec.rows) :: { any } do
			map[spec.key(item)] = i
		end
		return map
	end))

	--[[ ONE ROW'S DECLARED EXTENT, BY KEY — what the row's box is sized to and
		what its slot declaration promises the solver.

		UNIFORM: the list's one number, read WITHOUT touching `layoutIndex`, so a
		constant extent still resolves once and never recomputes.

		VARIABLE: that row's own entry in the running-offset index.

		THE LAST-KNOWN CACHE EXISTS FOR ONE FRAME OF ONE CASE: a row whose key has
		already left the data but whose node has not yet unmounted. Its index is nil,
		and answering 0 there would collapse the row's box on its way out and make
		the slot guard shout at a corpse. It keeps the extent it last had instead.
		Entries are written only by MOUNTED rows and pruned with the data below, so
		the cache is window-sized, not list-sized. ]]
	local lastRowExtent: { [string]: number } = {}
	local function rowExtentIn(use: any, key: string): number
		if not itemExtentIsVariable then
			return itemExtentIn(use)
		end
		local index = (use(indexByKey) :: { [string]: number })[key]
		if index == nil then
			return lastRowExtent[key] or 0
		end
		local px = (use(layoutIndex) :: any).extentOf(index)
		lastRowExtent[key] = px
		return px
	end

	--[[ the full virtual extent as a live fixed Dim: the ScrollView's single Canvas
		child is this big ALONG THE SCROLL AXIS, so the solver's scroll-axis sum ==
		the full virtual extent and the renderer pushes it as CanvasSize (native §6).
		Rows mount only in the window, but the canvas always spans the whole list.

		BY VALUE, NOT BY IDENTITY (the reactive review's fresh-table finding,
		measured wave T15). A table literal
		is never identity-equal to the one before it, so with the default eq this
		memo notified on EVERY layout-index recompute — including the ordinary case
		where the index was rebuilt and the total extent did not move: an edit to a
		row nobody is looking at in a list whose length did not change. Downstream
		that is a measure dirty on the canvas and a whole re-solve of the surface.

		Measured, forty iterations of the perf lab's own collection churn: 41 solves
		against 1, the forty extra ones producing zero rect writes and zero prop
		writes. Three lab workloads moved with it (`variable-extents` 294 -> 246,
		`edit-locality` 131 -> 83, `collection-churn` 30 -> 25).

		`rect.sameFlatValue` is the framework's one flat-record equality — the
		renderer's `sameGeometryValue` and `selection_indicator`'s `sameGeometry` are
		already the same function — and it REFUSES a nested field rather than
		half-comparing it, which is exactly right for a Dim: `fixed` carries a
		number, and any richer Dim shape reports "changed" and propagates. ]]
	local canvasDim = listScope:own(core:memo(function(use)
		return { type = "fixed", px = use(layoutIndex).content }
	end, rect.sameFlatValue))

	-- scroll clamped into the content band, so garbage/overshoot mirror values
	-- cannot mount phantom windows
	local clampedTop = listScope:own(core:memo(function(use)
		local maxTopPx = math.max(0, use(layoutIndex).content - viewportIn(use))
		local raw = use(scrollTop)
		if type(raw) ~= "number" or raw ~= raw then
			return 0
		end
		return math.clamp(raw, 0, maxTopPx)
	end))

	-- the window: visible rows + overscan, keyed. Equality compares the KEY
	-- SEQUENCE, so a same-window scroll delta never fires the ForEach.
	local function sameWindow(a: { any }, b: { any }): boolean
		if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
			return false
		end
		for i, entry in a do
			if entry.key ~= b[i].key then
				return false
			end
		end
		return true
	end
	local windowItems = listScope:own(core:memo(function(use)
		local items = use(spec.rows) :: { any }
		local top = use(clampedTop)
		-- SLOTS, not rows, and the index owns which arithmetic that is: division
		-- on a uniform list, a binary search over the prefix sums on a variable one
		local first, last = use(layoutIndex).window(top, viewportIn(use), overscan)
		local window = {}
		for i = first, last do
			table.insert(window, { key = spec.key(items[i]), item = items[i] })
		end
		return window
	end, sameWindow))

	-- ONE definition of a row's path shape under a given root (`{root}` is the
	-- standalone `/{id}` for the public form and the mounted ScrollView path for
	-- the screen-rooted one). Every caller that needs a row or hit path goes
	-- through here, so the ForEach's `W/[{key}]` convention (src/mount.luau) is
	-- written down exactly once.
	local function rowPathUnder(root: string, key: string): string
		return `{root}/Canvas/W/[{key}]/Row`
	end
	local function pathOf(key: string): string?
		for _, entry in windowItems:get() :: { any } do
			if entry.key == key then
				return rowPathUnder(`/{id}`, key)
			end
		end
		return nil
	end
	return {
		SLOT_CONTENT_FROM = SLOT_CONTENT_FROM,
		canvasDim = canvasDim,
		clampedTop = clampedTop,
		extentsFor = extentsFor,
		indexByKey = indexByKey,
		-- the two caches, BY REFERENCE: `measureWindow` and the prune observer
		-- stayed in virtual_list.luau and mutate these in place (see the header)
		lastRowExtent = lastRowExtent,
		layoutIndex = layoutIndex,
		layoutNow = layoutNow,
		measured = measured,
		measuredEpoch = measuredEpoch,
		pathOf = pathOf,
		rowExtentIn = rowExtentIn,
		rowPathUnder = rowPathUnder,
		scrollTop = scrollTop,
		slotDeclaration = slotDeclaration,
		windowItems = windowItems,
	}
end

return virtual_window
