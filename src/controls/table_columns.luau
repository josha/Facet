--!strict
--[[ COLUMN-WIDTH RESOLUTION for `controls/table.luau` — the pure half.

	One rule lives here, and it is here rather than inside `newTable` for the
	reason the source-cap ledger states about that file: every large block in it
	closes over mutable instance state, so nothing can be reasoned about at a
	viewport nobody is holding. This takes the columns, the committed overrides
	and the available width as ARGUMENTS, so a rotation is three numbers in a
	spec rather than a device in someone's hand.
]]

local table_columns = {}

export type Column = {
	id: string,
	width: any,
	minWidth: number?,
	resizable: boolean?,
	[string]: any,
}

--[[ ── AN OVERRIDE IS A COMMITMENT, NOT A GUARANTEE OF SPACE (DIR-4) ─────────
	(director device round: resize Name and Artist wide in landscape, rotate to
	portrait — Rating is pushed off screen and the header still reads
	"Name 297px · Artist 168px" on a 393px viewport.)

	THE DEFECT. `setColumnWidth` turns a column into an ABSOLUTE
	`{ type = "fixed", px }`, and a fixed dim has no relation to the width it
	is being laid out in. Every other dim kind this control accepts answers to
	the available extent — `fill` divides it, `percent` is a fraction of it,
	`minMax` bands within it — so a resized table was the ONE shape whose
	columns could not respond to the viewport at all. A rotation, a window
	drag, a split-view resize or a device-profile change all reach it, and the
	failure is the worst kind: the last columns do not shrink, they LEAVE.

	THE MODEL DOES NOT MOVE. The committed px stay exactly as committed —
	`api.columnWidthOverrides` still reads back what the player dragged, a
	round trip through a narrow viewport and back is lossless, and widening
	restores the committed widths to the pixel. What clamps is RESOLUTION: the
	widths the solver is handed on THIS solve, for THIS content width.

	ONLY THE OVERRIDDEN COLUMNS PAY. A column the player never touched is
	expressing the author's own intent about how it responds to space, and
	taking room from it to honour a drag would be answering the wrong
	question — the drag is what made the table too wide. Each overridden
	column gives up the same PROPORTION of what it has above its own floor
	(`minWidth`, or the declared width for a column that is not `resizable`),
	so a 300px column yields more than a 120px one and neither can be squeezed
	out of existence. When even the floors do not fit, the clamp stops there
	and the table overflows honestly rather than pretending.

	`available` is the POST-RESERVE content width the caller measured — the
	body's solved width minus the scrollbar gutter it published, which is what
	the rows actually divide. `nil` means "no measurement yet, do not clamp":
	the first frame resolves the committed widths and the measurement corrects
	it, the same one-re-solve shape the scrollbar gutter already rides. ]]
-- the width below which a column may not be clamped: its own floor, and for a
-- column the player cannot resize, never less than what the author declared
local function overrideFloor(column: Column): number
	local floor = column.minWidth or 24
	if column.resizable ~= true then
		local declared = column.width
		if type(declared) == "table" and declared.type == "fixed" and type(declared.px) == "number" then
			floor = math.max(floor, declared.px)
		end
	end
	return floor
end

-- the space a non-overridden column needs before anything else can have any
local function reservedFor(column: Column): number
	local dim = column.width
	if type(dim) == "table" and dim.type == "fixed" and type(dim.px) == "number" then
		return dim.px
	end
	return column.minWidth or 0
end

--[[ WHAT THE COLUMNS DO NOT GET: the row's own gap and card padding.

	`sides` is the row card's padding AFTER a snapshot has resolved it — it is
	theme metric NAMES until then, which is why the caller resolves it and this
	takes the answer. Only the two horizontal sides matter: a column divides
	width. ]]
function table_columns.reserved(gap: any, columnCount: number, sides: any): number
	local total = (if type(gap) == "number" then gap else 0) * math.max(0, columnCount - 1)
	if type(sides) == "table" then
		for _, side in { "left", "right" } do
			local n = (sides :: any)[side]
			if type(n) == "number" then
				total += n
			end
		end
	end
	return total
end

--[[ THE COLUMNS DO NOT GET THE WHOLE WIDTH (review NEW-3, 2026-08-17).

	The cells live in an `HStack` with the table's own `gap` between them and the
	row card's `padding` around them, and the first version of this clamp fitted
	`sum(widths) <= available` against the BODY's width — so it under-reserved by
	`gap * (n - 1)` plus both padding sides, and the director's symptom
	reproduced for any table with a gap:

	    no gap  -> name 329  laps x=329 w=64  right edge 393  fits
	    12px gap -> name 329  laps x=341 w=64  right edge 405  OVERFLOWS

	`reserved` is that space, resolved by the caller (the padding is theme metric
	NAMES until a snapshot resolves them, which a pure function cannot do), so
	what the columns divide is `available - reserved`. Zero is the old behaviour,
	which is what every direct caller of the pure function gets by omission. ]]
function table_columns.fitOverrides(
	columns: { Column },
	overrides: { [string]: number },
	available: number?,
	reserved: number?
): { [string]: number }
	-- `nil` is "no measurement yet, do not clamp"; a MEASURED width that the
	-- reservation eats entirely is a real answer — zero space — and clamps every
	-- overridden column to its floor rather than declining to clamp at all
	if available == nil or next(overrides) == nil then
		return overrides
	end
	available = math.max(0, available - math.max(0, reserved or 0))
	local demand = 0
	local slack = 0
	local overridden: { Column } = {}
	for _, column in columns do
		local committed = overrides[column.id]
		if committed ~= nil then
			local floor = overrideFloor(column)
			local px = math.max(committed, floor)
			demand += px
			slack += math.max(0, px - floor)
			table.insert(overridden, column)
		else
			demand += reservedFor(column)
		end
	end
	local excess = demand - available
	if excess <= 0 or slack <= 0 then
		return overrides
	end
	-- proportional to what each column has ABOVE its own floor, capped at the
	-- total slack so the last column cannot be asked for more than it has
	local take = math.min(excess, slack)
	local fitted = table.clone(overrides)
	for _, column in overridden do
		local floor = overrideFloor(column)
		local px = math.max(overrides[column.id], floor)
		local room = math.max(0, px - floor)
		fitted[column.id] = px - take * (room / slack)
	end
	return fitted
end

--[[ ── WHAT EACH COLUMN ACTUALLY GETS ─────────────────────────────────────────
	One rule, one pass, for the whole band — because the header and the cells
	divide the SAME width and the only spelling in which they cannot disagree is
	the one where the division happens once (`table.luau`'s own DIR-4 note).

	`layout` is the successor to `resolveDim`, which lived in `table.luau` and
	answered per column with no idea what the others were doing. That was enough
	while the only question was "does this override still fit"; it is not enough
	for a FLOOR, because a floor is a claim on a shared pool.

	ADAPT-19 — A DECLARED FLOOR IS A FLOOR, INCLUDING ON `fill`. `minWidth` used
	to be spent in exactly two places: an override's clamp, and a `percent` dim's
	`min`. A `fill` dim — the kind a responsive table uses for nearly every
	column — was returned untouched, and the solver divides fill slack strictly by
	weight with no notion of a minimum (`arrangeStack`'s fill block reads only
	`weight`). So `minWidth = 120` on a fill column was a property the framework
	ACCEPTED and never spent: measured at 390px, 120 resolved to 73 and 100 to 37,
	with the cell text reporting `truncated = true`.

	WHY THE RULE IS THE TABLE'S AND NOT THE SOLVER'S. The table already measures
	the post-reserve content width its rows divide and already resolves one dim per
	column against it, so the floor is applied exactly where the division happens —
	as the ordinary flex-with-minimum negotiation: pin any fill whose share would
	fall under its floor, take it out of the pool, and divide again. Teaching
	`fill` a `min` in the solver would be a layout-language change reaching every
	control in the framework to fix a table.

	WHAT IT DELIBERATELY DOES NOT DO: MEASURE. A `content`/`hug` column's appetite
	is a measurement, and this is a pure function of numbers — so those columns
	consume nothing here and the fills go on dividing what is left, exactly as
	they do today. The floors that ARE enforced are the ones the author declared
	and the widths this rule can know: fixed, percent, overridden, and fill.
]]
--[[ ── ADAPT-18 · COLUMN PRIORITY-COLLAPSE ───────────────────────────────────
	(director-approved paradigm; audit J-1, severity highest: "at 390px all five
	columns stay mounted and divide the width".)

	THE RULE. When the visible column set cannot meet every column's own floor,
	the LOWEST-PRIORITY column collapses whole — not a squeeze, not a clip — and
	the rest are re-divided. One at a time, until the remainder fits or nothing is
	left that may go.

	PRIORITY IS DECLARATION ORDER UNTIL SOMEBODY SAYS OTHERWISE. `priority = n`
	(1 = most important) sorts a column explicitly; a column with none sorts at
	its own 1-based index, which means an author who never heard of this feature
	gets exactly the ordering they wrote down. Ties break on the later index,
	because the later of two equals is the one further from the row's identity.

	TWO COLUMNS NEVER GO. The FIRST declared column is the row's identity — a
	table whose rows have no name is not a narrower table, it is a different
	thing — and `priority = "always"` is the author's own opt-out for a column
	that must stand whatever the width (a status light, a running total). Both
	are refusals rather than very-high priorities, because a number can always be
	beaten by another number.

	THE TRIGGER IS A DECLARED FLOOR, AND THAT IS WHY THIS IS NOT A BEHAVIOUR
	CHANGE FOR EVERY SHIPPED TABLE. A column with no `minWidth`, no `fixed` px
	and no `percent` has a floor of zero and can be squeezed forever, so a table
	whose columns declare nothing never collapses anything: the demand is zero and
	zero always fits. Collapse begins exactly where the author said "this column
	needs at least this much", which is the same declaration ADAPT-19 above
	started honouring.

	WHAT COLLAPSE IS, STRUCTURALLY, is `table.luau`'s: the column keeps its node
	and takes the framework's own space-reserving hide (`hidden`, which leaves
	paint, focus order and hit-testing together with its whole subtree) at zero
	width. Nothing remounts, so a collapse and its reversal cost no selection, no
	focus and no live in-cell control — which is what makes "re-evaluates in both
	directions" a property rather than a hope.
]]
export type Layout = {
	-- the dim each column resolves to this solve, keyed by id. A COLLAPSED column
	-- resolves to a zero-width fixed dim: it keeps its box, and `table.luau` hides
	-- the subtree that would have painted in it.
	dims: { [string]: any },
	-- the collapsed ids, in DECLARATION order (the order the disclosure lists
	-- them), and the same set keyed for a per-column reactive read
	hidden: { string },
	hiddenSet: { [string]: boolean },
}

local ZERO_WIDTH = table.freeze({ type = "fixed", px = 0 })

-- may this column ever collapse? The row's identity may not, and neither may a
-- column whose author pinned it.
local function collapsible(column: Column, index: number): boolean
	return index > 1 and column.priority ~= "always"
end

-- the order collapse eats them in: the least important first. A declared
-- `priority` is the rank; absent, the column's own 1-based index is.
local function rankOf(column: Column, index: number): number
	return if type(column.priority) == "number" then column.priority :: number else index
end

-- the width a column occupies that the fills cannot have. Only what is KNOWABLE
-- without measuring: everything else answers 0 and leaves the pool alone.
local function consumedBy(column: Column, dim: any, room: number): number
	local t = if type(dim) == "table" then dim.type else nil
	if t == "fixed" and type(dim.px) == "number" then
		return dim.px
	end
	if t == "percent" and type(dim.fraction) == "number" then
		return math.max(dim.fraction * room, dim.min or column.minWidth or 0)
	end
	if t == "minMax" then
		-- the FLOOR, not the appetite: a `minMax` column takes preferred-or-content
		-- clamped, and this rule does not measure. Under-counting hands the fills
		-- more room than they will finally get, which is the behaviour that ships
		-- today; over-counting would pin a fill against a number nobody spent.
		return dim.min or column.minWidth or 0
	end
	return 0
end

--[[ ONE COLUMN'S DIM, given the committed widths already fitted to the viewport.
	Was `resolveDim` in `table.luau`; moved here whole, because the floor rule
	above has to run against the same answers. ]]
local function dimOf(column: Column, overrides: { [string]: number }): any
	local override = overrides[column.id]
	if override ~= nil then
		return { type = "fixed", px = math.max(override, column.minWidth or 24) }
	end
	local dim = column.width
	if dim.type == "percent" and column.minWidth then
		local clone = table.clone(dim)
		clone.min = column.minWidth
		return clone
	end
	return dim
end

-- the width this column will not go under: what the author declared, read
-- through whichever dim kind declared it
local function floorOf(column: Column, dim: any, room: number): number
	local t = if type(dim) == "table" then dim.type else nil
	if t == "fixed" and type(dim.px) == "number" then
		return dim.px
	end
	if t == "percent" and type(dim.fraction) == "number" then
		return math.max(dim.fraction * room, dim.min or column.minWidth or 0)
	end
	if t == "minMax" then
		return dim.min or column.minWidth or 0
	end
	-- `fill`, `content`, `hug`, `aspect`: whatever the author declared, or nothing
	return column.minWidth or 0
end

function table_columns.layout(
	columns: { Column },
	overrides: { [string]: number },
	available: number?,
	gap: any,
	sides: any
): Layout
	--[[ THE RESERVATION IS THE WHOLE BAND'S, COLLAPSED OR NOT, and it is one of the
		two reasons `hidden` was the right structural answer: a collapsed column
		keeps its box, so the `HStack` still spends a gap beside it and the number
		below stays true through every collapse. The alternative — unmounting the
		cell — would have made the reservation a function of the collapse and the
		collapse a function of the reservation, i.e. a fixed point to iterate rather
		than a sum to take. ]]
	local reserved = table_columns.reserved(gap, #columns, sides)
	local fitted = table_columns.fitOverrides(columns, overrides, available, reserved)
	local dims: { [string]: any } = {}
	for _, column in columns do
		dims[column.id] = dimOf(column, fitted)
	end
	--[[ NO MEASUREMENT YET IS NOT A NARROW VIEWPORT. The first frame resolves what
		the author declared and the measurement corrects it on the next — the same
		one-re-solve shape the scrollbar gutter and the DIR-4 clamp already ride.
		Pinning against a width nobody measured would make every table's first frame
		its narrowest, and collapsing against one would make it its emptiest. ]]
	if available == nil then
		return { dims = dims, hidden = {}, hiddenSet = {} }
	end
	local room = math.max(0, available - math.max(0, reserved))
	--[[ THE COLLAPSE, one column per pass. Each pass asks the same question the
		fill negotiation below asks — does the declared demand fit — and answers it
		by REMOVING the least important column rather than by squeezing every
		column past its own floor. Bounded by the number of columns. ]]
	local hiddenSet: { [string]: boolean } = {}
	local hidden: { string } = {}
	while true do
		local demand = 0
		local victim: Column? = nil
		local victimRank, victimIndex = -math.huge, 0
		for index, column in columns do
			if not hiddenSet[column.id] then
				demand += floorOf(column, dims[column.id], room)
				if collapsible(column, index) then
					local rank = rankOf(column, index)
					-- least important first; the later of two equals goes first
					if rank > victimRank or (rank == victimRank and index > victimIndex) then
						victim, victimRank, victimIndex = column, rank, index
					end
				end
			end
		end
		if demand <= room or victim == nil then
			break
		end
		local gone = (victim :: Column).id
		hiddenSet[gone] = true
		dims[gone] = ZERO_WIDTH
	end
	if next(hiddenSet) ~= nil then
		-- DECLARATION order, which is the order the disclosure lists them in: the
		-- player is reading the table's own left-to-right, not this rule's
		for _, column in columns do
			if hiddenSet[column.id] then
				table.insert(hidden, column.id)
			end
		end
	end
	-- what the fills are dividing, and who is dividing it
	local consumed = 0
	local pool: { Column } = {}
	for _, column in columns do
		local dim = dims[column.id]
		if hiddenSet[column.id] then
			-- a collapsed column takes nothing: its box is zero wide
		elseif type(dim) == "table" and dim.type == "fill" then
			table.insert(pool, column)
		else
			consumed += consumedBy(column, dim, room)
		end
	end
	--[[ THE NEGOTIATION. Each pass divides the remaining slack by weight and pins
		every fill whose share does not clear its own floor; a pinned column leaves
		the pool with its floor, so the survivors divide MORE on the next pass.
		Bounded by the number of columns, because each pass pins at least one. ]]
	local pinned = 0
	while #pool > 0 do
		local slack = math.max(0, room - consumed - pinned)
		local weightSum = 0
		for _, column in pool do
			weightSum += (dims[column.id].weight or 1)
		end
		local under: { Column } = {}
		local rest: { Column } = {}
		for _, column in pool do
			local floor = column.minWidth or 0
			local share = if weightSum > 0 then slack * (dims[column.id].weight or 1) / weightSum else 0
			if floor > 0 and share < floor then
				table.insert(under, column)
			else
				table.insert(rest, column)
			end
		end
		if #under == 0 then
			break
		end
		for _, column in under do
			local floor = column.minWidth or 0
			dims[column.id] = { type = "fixed", px = floor }
			pinned += floor
		end
		pool = rest
	end
	return { dims = dims, hidden = hidden, hiddenSet = hiddenSet }
end

return table_columns
