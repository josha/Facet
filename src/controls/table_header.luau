--!strict
--[[ THE HEADER BAND for `controls/table.luau` — the column headings, their sort
	marks, and the resize divider that lives between them.

	WHY IT IS ITS OWN FILE. `docs/handoff/SOURCE_CAP_LEDGER.md`'s row for
	`table.luau` named this seam on 2026-08-18 and set its own trigger: "the
	HEADER BAND — the header cells, `gripFor`, `isSortable`,
	`forwardUnclaimedGripTap` and `bandPadding` — behind the same parameter
	object". The column-collapse paradigm put that file back inside the 190,000
	warning band the same day, so the trigger fired on the next feature, which is
	exactly what a trigger is for.

	IT IS THE `table_rows` TECHNIQUE, ONE MORE TIME. Every fact arrives as an
	argument; the module requires `table.luau` nowhere and names no type from it.
	The row's analysis predicted the one thing this seam would cost — `resizeDrag`
	is a reassigned SCALAR, and a reassigned local cannot be shared by reference —
	so it is one record (`deps.resizeGesture`), the same shape `rowGesture` took.
	`renderController` is reassigned too, and takes an ACCESSOR
	(`deps.controllerOf`) rather than a record, because only this file READS it
	and the write stays where the contribution binds it — which is the split
	`screen_paint` already uses for the three host locals it shares.

	WHAT STAYED BEHIND: `isSortable` (three lines, and the disclosure plate and
	the activate router both ask it), `bandPadding` (the toolbar and the
	disclosure band pay the same gutters), and the whole resize MODEL —
	`setColumnWidth`, `stepColumnWidth`, the committed overrides. This file builds
	the band and starts the gesture; the table decides what a width means.
]]

local interactionTokens = require("../input/interaction_tokens")

local table_header = {}

--[[ THE ONE MUTABLE CELL THIS FILE SHARES with `table.luau`: the live divider
	drag, nil between gestures. It is written here (the grip's own down/move/up)
	and cleared there (the interaction-class observer, when the pointer capability
	goes away mid-capture), so neither side can own it alone. ]]
export type ResizeGesture = { drag: any }

export type Deps = {
	UI: any,
	spec: any,
	columns: { any },
	resizeGesture: ResizeGesture,
	resizing: any,
	previewX: any,
	bandPadding: any,
	cellPadding: any,
	ALIGN_H: { [string]: string },
	-- the SHARED per-column dim and collapse verdict, so the band and the rows
	-- can never divide the width differently or disagree about what is on screen
	headerDim: (any) -> any,
	columnHidden: (any) -> any,
	isSortable: (any) -> boolean,
	-- the sort mark's reactive text needs a scope and a core of the table's own
	scope: any,
	core: any,
	-- the control's api table, held by reference: `setColumnWidth` is assigned
	-- after this band is built and is only ever called at gesture time
	api: any,
	-- the render controller is REASSIGNED by the contribution, so it is read
	-- through an accessor rather than captured
	controllerOf: () -> any,
}

--[[ Returns the header `HStack`, or NIL for a `header = false` table — which is
	the borderless-list shape this library ships more of than the headered one. ]]
function table_header.band(deps: Deps): any
	local UI = deps.UI
	local spec = deps.spec
	local columns = deps.columns
	local resizeGesture = deps.resizeGesture
	local resizing = deps.resizing
	local previewX = deps.previewX
	local bandPadding = deps.bandPadding
	local cellPadding = deps.cellPadding
	local ALIGN_H = deps.ALIGN_H
	local headerDim = deps.headerDim
	local columnHidden = deps.columnHidden
	local isSortable = deps.isSortable
	local scope = deps.scope
	local core = deps.core
	local api = deps.api
	local controllerOf = deps.controllerOf

	--[[ A PRESS THE DIVIDER DID NOT TURN INTO A DRAG GOES TO THE HEADER UNDERNEATH
		(director ruling 2026-08-14, option 1 of the four in
		`docs/lessons/a-forty-four-pixel-floor-under-an-eight-pixel-divider.md`).

		THE MEASUREMENT: `contract.luau` gives `Grip` `minHitSize = 44`, so the
		renderer asks the adapter for a 44x44 hit rect centred on this 8x28 divider
		and the engine adapter realises it as a real `FacetHitExpander` TextButton.
		That button sits ABOVE the header cell's own `Column` button, and a GuiButton
		sinks `InputBegan` — so live, in the showcase, a click at (264,134) inside the
		name header did NOTHING while the same click at (100,134) cycled the sort. A
		26px dead band ran down the trailing edge of every resizable header cell.

		THE REPAIR IS ONE MECHANISM FOR BOTH HALVES. The adapter now runs the grip's
		own gesture from the expander too (`screen_target.beginPointerCapture`), so
		the 44px band really is the drag target the floor always claimed to be; and a
		press that never travels — which is what a TAP is — is handed on to whatever
		the expander was covering, through the exact forwarding `row_actions` already
		uses (`controller.tapAt`, ruling 6). Underneath is the cell's own `Column`
		button, so the band sorts again.

		WHICH `tapAt` FAMILY. Ruling 6 grew two: a tappable gets the activate dispatch,
		a pointer zone gets its down/up pair replayed. The forward from here lands on
		the header's `Column` Button, so it is the TAPPABLE family that runs — the
		pointer-zone family is what stops the Grip forwarding to ITSELF, which is why
		`skip` names it.

		WHY THE PROMOTION GATE AND NOT "did the width change". A zero-travel press
		used to commit `setColumnWidth(id, currentWidth)` — a phantom override on a
		column nobody moved, which is how `auto` silently became a pinned number. The
		gate is `interaction_tokens`', not a private one: a finger's resting jitter is
		14px and a mouse's is 6, and this control already reads that table for its row
		drag.

		ponytail (inherited from ruling 6, and it applies here too): the forwarded
		press has no PRESSED VISUAL — the header button under the finger does not
		light up while held, because the engine never told it it was pressed. The
		activation itself is exact. Upgrade path is the same one: forward the down/up
		pair rather than the resolved tap. ]]
	local function forwardUnclaimedGripTap(drag: any, pos: any)
		local ctrl = controllerOf()
		if ctrl == nil or type(ctrl.tapAt) ~= "function" or drag.cellPath == nil then
			return -- no presenter/controller (a bare mount in a spec): nothing to hand to
		end
		-- scoped to THIS header cell, and never back to the Grip that is forwarding
		ctrl.tapAt(pos.x, pos.y, { within = drag.cellPath, skip = drag.gripPath })
	end

	-- resize grip (Phase B): a non-button, cursor-hinted pointer zone on the
	-- right edge of a resizable header cell; drag previews a guide line and
	-- commits through the Phase A model (setColumnWidth) on release
	local function gripFor(column: Column): any
		return UI.Grip({
			id = "Grip",
			cursorHint = "colResize",
			-- POINTER ONLY NOW. The grip used to be focusable so a gamepad could
			-- Adjust-resize from it, which meant two focus stops per column (sort
			-- hit, then a 4px divider) and nothing that could ever mean "this
			-- column". The column's focus stop is its HEADER; see `selectedColumn`.
			focusable = false,
			alignH = "end",
			width = { type = "fixed", px = "s" },
			height = { type = "fill", weight = 1 },
			onPointerDown = function(path: string, pos: any, rectOf: (string) -> any)
				local cellPath = string.match(path, "^(.*)/Grip$")
				local rootPath = string.match(path, "^(.*)/Main/Header/")
				local cellRect = cellPath and rectOf(cellPath)
				local rootRect = rootPath and rectOf(rootPath)
				if cellRect == nil or rootRect == nil then
					return
				end
				resizeGesture.drag = {
					columnId = column.id,
					startX = pos.x,
					startY = pos.y,
					-- the two paths a forwarded tap needs, captured while the press
					-- that produced them is still in hand
					gripPath = path,
					cellPath = cellPath,
					pointerType = pos.pointerType,
					startWidth = cellRect.w,
					relX = cellRect.x - rootRect.x,
					minWidth = column.minWidth or 24,
					width = cellRect.w,
					-- NOTHING IS A RESIZE UNTIL IT TRAVELS (see the ruling above). The
					-- guide line waits too: a band 44px wide that flashed a resize guide
					-- under every press near a column edge is the dead zone's cosmetic
					-- twin.
					promoted = false,
				}
			end,
			onPointerMove = function(_path: string, pos: any)
				if resizeGesture.drag == nil then
					return
				end
				if not resizeGesture.drag.promoted then
					if
						not interactionTokens.promoted(
							pos.x - resizeGesture.drag.startX,
							pos.y - resizeGesture.drag.startY,
							resizeGesture.drag.pointerType
						)
					then
						return
					end
					resizeGesture.drag.promoted = true
					resizing:set(true)
				end
				resizeGesture.drag.width = math.max(
					resizeGesture.drag.minWidth,
					resizeGesture.drag.startWidth + pos.x - resizeGesture.drag.startX
				)
				previewX:set(resizeGesture.drag.relX + resizeGesture.drag.width)
			end,
			onPointerUp = function(_path: string, pos: any)
				if resizeGesture.drag == nil then
					return
				end
				local drag = resizeGesture.drag
				resizeGesture.drag = nil
				if not drag.promoted then
					-- a TAP: it was never this zone's gesture, so it goes to whatever the
					-- 44px hit expander was covering
					forwardUnclaimedGripTap(drag, pos)
					return
				end
				resizing:set(false)
				api.setColumnWidth(drag.columnId, drag.width)
			end,
			onPointerCancel = function()
				resizeGesture.drag = nil
				resizing:set(false)
			end,
		})
	end

	if spec.header == false then
		return nil
	end
	local headerPadding = bandPadding
	local headerCells = {}
	for _, column in columns do
		-- full-contrast title (the secondary tint was unreadable over
		-- world backgrounds — director hand-test 2026-07-20), inset via
		-- its own margin (the header cell stays unpadded so the resize
		-- grip sits at the TRUE column boundary), centered like the cells
		-- ...AND IT HONOURS THE COLUMN'S OWN ALIGNMENT (F-27), through the SAME
		-- ALIGN_H mapping the cells use: a `alignment = { h = "trailing" }`
		-- numeric column used to show a left-aligned heading over
		-- right-aligned numbers — a partially-honoured property, which reads
		-- as a layout bug rather than an unsupported option.
		--
		-- The alignment is spent as a TEXT alignment inside a title box that
		-- fills the header cell minus the cell inset on both sides, rather
		-- than as the cells' container `alignH`, for two reasons: the header
		-- cell itself must stay unpadded (the resize grip sits at the TRUE
		-- column boundary), and a ZStack child's FAR margin is not spent by
		-- end-alignment — so a margin-inset hug title would have sat flush
		-- against the column edge while its cells sat 8px in.
		--
		-- ...and a TRAILING title has to clear the sort mark, which lives at
		-- the same edge of the same ZStack. `sortMarkMargin` is the theme's own
		-- reserve for that glyph ("keeps the ▲/▼ clear"), so a sortable trailing
		-- column spends it as the title's trailing inset instead of the cell
		-- inset — measured, not by luck: at 8px the two were 1px apart under
		-- Studio Neutral's 11px mark, which is a collision in any package whose
		-- mark is wider.
		--[[ ...AND THE RESERVE IS SPENT FOR EVERY SORTABLE TITLE, NOT ONLY A
			TRAILING ONE, AND IT IS TWO TERMS RATHER THAN ONE (2026-08-15). The
			solver fix that finally put the mark where it was always declared to go
			(`alignH = "end"` + `margin.right`, arranged in the box it was GIVEN —
			see the zstack branch of `arrange`) is what made both halves visible:

			· ONE TERM RESERVES THE GAP, NOT THE GLYPH. `sortMarkMargin` is the
			  mark's clearance from the column boundary, which it shares with the
			  resize grip — so a title inset by it alone ends exactly where the mark
			  ENDS, and overlaps the mark's whole width. The reserve is the sum:
			  clearance + the glyph's own column. `sortMarkTextSize` is the measured
			  upper bound on a one-character ▲/▼ (7 px drawn at 11 under Studio
			  Neutral, 12 at 12 under Pixel Quest).
			· THE ALIGNMENT DOES NOT DECIDE WHERE THE MARK IS. It always sits at the
			  cell's trailing edge, so a LEADING title collides with it too — as soon
			  as its text is long enough to reach that edge, which is the 1.4x
			  localization case on every sortable column in the corpus. The old
			  `alignment.h == "trailing"` gate only ever described which title was
			  long enough to have been noticed.

			It is spent whether or not THIS column is the sorted one, exactly as the
			trailing case always was: a reserve that came and went with the mark
			would re-flow every heading in the band on every sort. ]]
		local headAlignment = column.alignment or {}
		local titleTrailingInset = if isSortable(column)
			then { "controls.table.sortMarkMargin", "controls.table.sortMarkTextSize" }
			else cellPadding
		local title = UI.Text({
			id = "Title",
			text = column.title or column.id,
			textSize = "label",
			width = { type = "fill", weight = 1 },
			margin = { left = cellPadding, right = titleTrailingInset },
			textAlign = ALIGN_H[headAlignment.h or "leading"],
			-- ONE LINE, ALWAYS. A two-word title ("Track Name") that wrapped
			-- would push the header band down by a whole line the moment a
			-- column got narrow, and a heading that reflows out of alignment
			-- with its own column is worse than an ellipsis. The band FLOORS at
			-- `headerHeight` and grows to fit that one line (see the Head-<id>
			-- box below), so a raised text preference makes the header taller
			-- rather than making the title overflow it.
			lineLimit = 1,
			-- the column's disclosure declaration covers the title it caps
			-- (Step 8.5 LT-G2)
			disclose = if column.disclose == true then true else nil,
		})
		local headerChildren = {}
		-- ONE FOCUS STOP PER COLUMN, AND IT IS THE HEADER (director 2026-07-29).
		-- It mounts for a sortable column OR a resizable one, because both verbs
		-- now come through the same selectable handle: a pointer TAP still sorts
		-- (the universal convention, unchanged), while a device Activate selects
		-- the column and hands Left/Right and Up/Down to it.
		local columnHandle = isSortable(column) or column.resizable == true
		if columnHandle then
			-- the sort hit fills the header cell (under title/grip). Under
			-- THE COLUMN HANDLE. It fills the header cell under the title and
			-- the mark, and it is the column's single focus stop: it joins the
			-- contributed "headers" NavigationGroup (buildFocusGroups) as a
			-- leading horizontal group. A pointer tap on it sorts; a device
			-- Activate selects the column (see handleActivate).
			local columnId = column.id
			table.insert(
				headerChildren,
				UI.Button({
					id = "Column",
					label = "",
					focusable = true,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
				})
			)
			table.insert(headerChildren, title)
			if isSortable(column) then
				table.insert(
					headerChildren,
					UI.Text({
						id = "SortMark",
						text = scope:own(core:memo(function(use)
							local order = use(spec.sortOrder)
							if order == nil or order.column ~= columnId then
								return ""
							end
							return if order.ascending then "▲" else "▼"
						end)),
						textSize = "controls.table.sortMarkTextSize",
						alignH = "end",
						margin = { right = "controls.table.sortMarkMargin" },
					})
				)
			end
		else
			table.insert(headerChildren, title)
		end
		if column.resizable == true then
			table.insert(headerChildren, gripFor(column))
		end
		table.insert(
			headerCells,
			UI.ZStack({
				id = `Head-{column.id}`,
				width = headerDim(column),
				-- ADAPT-18: a collapsed column's heading leaves paint, focus and
				-- hit-testing together, subtree and all (see `columnHidden`)
				hidden = columnHidden(column),
				-- A FLOOR, NOT A CAP (director 2026-08-06: "the edit button
				-- overlaps the heading at largest text"; and the standing ask,
				-- "if height is the issue why can't we make the whole table have
				-- more height as text size increases"). This was `fixed`, so at
				-- the Largest text preference a ONE-LINE title measured 34px
				-- inside a 28px box and painted straight out of it — over the
				-- toolbar above and the first row below. The solver had been
				-- saying so all along: `Head-<id>/Title` reported "overflows its
				-- zstack by 0x6px ... give the box room — a `minMax` FLOOR rather
				-- than a fixed CAP". This is that floor. The token is what a
				-- header band should never be SHORTER than; the live text facts
				-- decide how much taller it has to be, so the header grows with
				-- the preference and the band below it moves down with it.
				-- Same defect class as the row box (§3 of paradigm_table.spec):
				-- a fixed px height against unfixed content.
				height = { type = "minMax", min = "controls.table.headerHeight" },
				alignV = "center",
				children = headerChildren,
			})
		)
	end
	return UI.HStack({
		id = "Header",
		width = { type = "fill", weight = 1 },
		gap = spec.gap or 0,
		-- THE HEADER IS NOT A ROW, but its columns have to line up with the
		-- rows' columns, so it pays the same horizontal reservation the row
		-- art costs (see ROW_ART). It carries no card of its own and so no
		-- vertical inset. Zero under every flat package.
		--
		-- ...AND THE SAME GLOW GUTTER THE ROWS' VIEWPORT PAYS (2026-07-27).
		-- The rows live in a ScrollView, and a clipper insets its content by
		-- at least `chromeBleed` or the package's shadow is cut at its edge.
		-- The header is OUTSIDE that viewport, so without this it stayed put
		-- while the rows moved in and the columns came apart by exactly the
		-- bleed. A multi-metric side ADDS its entries on every solve, which
		-- is what lets one declaration mean "clear the viewport's glow
		-- gutter AND then the row card's carved border" — two gutters at two
		-- nesting levels, so they genuinely stack.
		--
		-- ...AND THE SCROLLBAR GUTTER, the third term and the same argument a
		-- third time (see THE BODY'S SCROLLBAR GUTTER). It is reactive
		-- because it is a measurement of the body, not a theme metric: the
		-- body reserves the bar only while its rows overflow.
		padding = headerPadding,
		children = headerCells,
	})
end

return table_header
