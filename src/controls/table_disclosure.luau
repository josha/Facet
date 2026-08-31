--!strict
--[[ THE HIDDEN-COLUMN DISCLOSURE for `controls/table.luau`.

	A column that collapsed took its values off the screen with it, and the
	standing no-dead-ends rule says the framework then owes the reader a route
	back to them. This file is that route: the facts the plate opens against, the
	list it shows, and the sheet it becomes where a plate cannot fit.

	THE PLATE ITSELF IS THE REVEAL WAVE'S, WHOLE. `src/region_expand.luau` already
	owns what a disclosure IS — an anchored panel with a full-width sheet
	fallback, a modal transparent scrim so an outside tap dismisses, gamepad B
	through the default cancel policy, a focus scope that is pushed and POPPED so
	the ring returns to the affordance, a second press on the affordance that
	closes, an epoch check that closes when the thing it points at moved or went,
	and a teardown count a leak test can read. Every one of those is something
	this control would otherwise have built a second, slightly different copy of,
	which is the standing rule against a second overlay system. What is new here
	is the FACTS and the CONTENT, and nothing else.

	WHY IT IS ITS OWN FILE. The same reason `table_rows.luau` is
	(`tools/lune/verify/data/source-cap-ledger.md`): `table.luau` is the densest control in
	the framework and the collapse paradigm is the second feature in a row to want
	room in it. This block is one-way by the checker's own test — it reads no
	mutable upvalue of `newTable`, every fact arrives as an argument, and it
	requires `table.luau` nowhere.
]]

local regionExpand = require("../region_expand")

local table_disclosure = {}

--[[ EVERY INPUT THE DISCLOSURE HAS, BY NAME — the same discipline
	`table_rows.Deps` records: the list IS the seam, and a fact this module would
	rather reach for is a require back with nowhere to put it. ]]
export type Deps = {
	UI: any,
	tableId: string,
	-- declaration order, and the id lookup the plate walks it by
	columns: { any },
	columnById: { [string]: any },
	-- Readable<{ string }>: the collapsed ids, in declaration order
	hiddenColumns: any,
	-- Readable<{ any }>: the rows the table currently has mounted (all of them
	-- for a flowing table, the window for a virtualized one)
	windowedItems: any,
	-- Readable<number?>: the post-reserve content width the rows divide, which is
	-- the width the plate wants and the number that decides plate-vs-sheet
	availableContentWidth: any,
	-- the surface's own height, or 0 with no environment
	viewportHeight: () -> number,
	keyOf: (any) -> string,
	isSortable: (any) -> boolean,
	cycleSort: (string) -> (),
	-- the row builder's OWN cell-content rule, so a disclosed value is the value
	-- the row would have shown rather than a second reading of the same spec
	cellContent: (any, any, any) -> any,
}

--[[ Returns the `region_expand` engine, or NIL for a table that can never
	collapse a column — in which case the control mounts no band, holds no engine
	and pays nothing at all for the feature existing. ]]
function table_disclosure.new(deps: Deps): any
	local UI = deps.UI
	local tableId = deps.tableId
	local columns = deps.columns
	local columnById = deps.columnById
	local hiddenColumns = deps.hiddenColumns
	local windowedItems = deps.windowedItems
	local availableContentWidth = deps.availableContentWidth
	local viewportHeight = deps.viewportHeight
	local keyOf = deps.keyOf
	local isSortable = deps.isSortable
	local cycleSort = deps.cycleSort
	local cellContent = deps.cellContent

	--[[ ── WHAT A COLLAPSED COLUMN'S VALUES ARE REACHED THROUGH  ───────
		THE PLATE IS THE REVEAL WAVE'S, WHOLE. `src/region_expand.luau` already owns
		what a disclosure is: an anchored panel with a full-width sheet fallback, a
		modal transparent scrim so an outside tap dismisses, gamepad B through the
		default cancel policy, a focus scope that is pushed and POPPED so the ring
		comes back to the affordance, a second press on the affordance that closes,
		an epoch check that closes when the thing it points at has moved or gone,
		and a teardown count a leak test can read. Every one of those is a thing this
		control would otherwise have had to build a second, slightly different copy
		of — which is the standing rule against a second overlay system, and the
		reason the only new code here is the FACTS and the CONTENT.

		THE FACTS ARE OURS BECAUSE THEY ARE NOT A COMPOSITION'S. `region_expand`
		normally reads "am I stepped down, and how wide may the plate be" out of the
		last `UI.Composition` resolution dump; a table's collapse is neither a
		composition nor a region, so `factsOf` hands it the two answers directly (its
		own note there records the six lines that made this possible).

		THE CONTENT LISTS EVERY COLLAPSED COLUMN, and under each one the value for
		each row the table currently has mounted — identified by the FIRST column,
		which is exactly why the first column never collapses. So the disclosure is
		bounded by what is on screen rather than by the size of the data: a flowing
		table lists all its rows because it has already mounted all of them, and a
		virtualized one lists its window, which is what the player is looking at.

		A COLLAPSED COLUMN'S SORT SURVIVES ITS COLLAPSE. Each section heading is the
		column's own sort verb when the column is sortable — the same `cycleSort` the
		header cell would have called — so losing the heading does not lose the
		ability to order by it. A non-sortable column's heading is a plain Text and
		takes no focus stop, because a focus stop that does nothing is the dead end
		this whole band exists to remove. ]]
	local function identityTextOf(item: any): string
		local first = columns[1]
		if first ~= nil and first.value ~= nil then
			return tostring((first.value :: any)(item))
		end
		return keyOf(item)
	end
	local function hiddenColumnRows(): { any }
		local out: { any } = {}
		for _, columnId in hiddenColumns:get() :: { string } do
			local column = columnById[columnId]
			if column == nil then
				continue
			end
			local title = column.title or column.id
			if isSortable(column) then
				table.insert(
					out,
					UI.Button({
						id = `Sort-{columnId}`,
						label = title,
						surface = "control",
						width = { type = "fill", weight = 1 },
						height = { type = "minMax", min = "targetSizes.minimum" },
						onActivate = function()
							cycleSort(columnId)
						end,
					})
				)
			else
				table.insert(out, UI.Text({ id = `Head-{columnId}`, text = title, textSize = "label" }))
			end
			for _, entry in windowedItems:get() :: { any } do
				local item = entry.item
				table.insert(
					out,
					UI.HStack({
						id = `Row-{columnId}-{keyOf(item)}`,
						width = { type = "fill", weight = 1 },
						gap = "s",
						children = {
							UI.Text({
								id = "Name",
								text = identityTextOf(item),
								textSize = "caption",
								role = "secondary",
								width = { type = "percent", fraction = 0.45 },
								-- the identity may be long; the plate is the place a
								-- truncation would be an insult, so it wraps
								lineLimit = 2,
							}),
							UI.ZStack({
								id = "Value",
								width = { type = "fill", weight = 1 },
								alignH = "start",
								-- NO LINE CAP: a row caps its cells to the row's own
								-- height, and this is the disclosure of what that cap
								-- took away
								children = { cellContent(column, item, nil) },
							}),
						},
					})
				)
			end
		end
		return out
	end
	local columnExpand: any = nil
	--[[ HOW TALL THE PLATE'S LIST MAY GET, and it is a fact about the SURFACE
		rather than a style constant — which is why it is not a theme metric and
		not a literal in a `height`. A floating plate may not be taller than the
		thing it floats over; half the viewport is what leaves the table it was
		opened from still visible behind it, which is what makes the disclosure
		read as a disclosure rather than as a screen change. Without an `env` (a
		headless mount) there is no surface to ask and the list simply hugs its
		content, which is the honest answer when nothing can be clipped anyway. ]]
	local function plateListHeight(): any
		local viewport = viewportHeight()
		if viewport <= 0 then
			return { type = "content" }
		end
		return { type = "minMax", max = math.max(viewport * 0.5, 120) }
	end
	local function columnPlateBody(): any
		return UI.VStack({
			id = "HiddenColumns",
			width = { type = "fill", weight = 1 },
			gap = "xs",
			children = {
				UI.ScrollView({
					id = "List",
					axis = "y",
					width = { type = "fill", weight = 1 },
					-- a FLOOR-less cap: the plate hugs a short list and scrolls a long
					-- one, which is the same `minMax` idiom the body's own height uses
					height = plateListHeight(),
					clipChildren = true,
					gap = "xs",
					children = hiddenColumnRows(),
				}),
				-- ESCAPE CANNOT BE BOUND ON THIS PLATFORM, so a modal's own
				-- close affordance IS the keyboard route out — the identical
				-- affordance and the identical reasoning as `UI.Region`'s plate
				UI.Button({
					id = "PlateClose",
					label = "Close",
					surface = "chip",
					textSize = "caption",
					onActivate = function()
						if columnExpand ~= nil then
							columnExpand.close()
						end
					end,
				}),
			},
		})
	end
	columnExpand = regionExpand.new({
		id = `{tableId}-columns`,
		factsOf = function(): any
			local ids = hiddenColumns:get() :: { string }
			if #ids == 0 then
				return { expandable = false, activeForm = 1, plate = nil }
			end
			local measured = availableContentWidth:get()
			--[[ THE PLATE IS AS WIDE AS THE TABLE, CAPPED. It is a list of
				identity/value pairs, so it wants the table's own reading width and
				no more; and below a width where two columns of text can sit side by
				side it becomes the SHEET instead, which is `region_expand`'s own
				fallback rather than a device test. ]]
			local width = if type(measured) == "number" and measured > 0 then math.min(measured, 360) else 280
			return { expandable = true, activeForm = 1, plate = { w = width, h = 0, sheet = width < 240 } }
		end,
		--[[ THE PLATE RECORD, not a bare width (wave REVEAL fix round 2). The engine
			now hands over the whole record — `{ w, h, sheet, max }` — because the
			region case has a correction to make that the pure pass cannot: a form
			declaring `width = fill` measures its CONTENT and has actually asked for
			the offer, so it takes `max` instead. This panel's body is a hugging list
			of column rows, so `w` is what it wants and its geometry is unchanged. ]]
		panelOf = function(plate: any): any
			return UI.VStack({
				id = "ColumnsPanel",
				surface = "raised",
				padding = "s",
				gap = "xs",
				width = { type = "fixed", px = plate.w },
				children = { columnPlateBody() },
			})
		end,
		sheetOf = function(): any
			return UI.Screen({
				id = `Columns:{tableId}`,
				children = {
					UI.Anchor({
						id = "Layer",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.VStack({
								id = "ColumnsSheet",
								anchor = "bottom",
								surface = "raised",
								padding = "m",
								gap = "xs",
								width = { type = "fill", weight = 1 },
								children = { columnPlateBody() },
							}),
						},
					}),
				},
			})
		end,
	})
	return columnExpand
end

return table_disclosure
