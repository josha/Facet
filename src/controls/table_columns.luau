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

-- committed overrides -> the px this solve can actually afford
function table_columns.fitOverrides(
	columns: { Column },
	overrides: { [string]: number },
	available: number?
): { [string]: number }
	if available == nil or available <= 0 or next(overrides) == nil then
		return overrides
	end
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

return table_columns
