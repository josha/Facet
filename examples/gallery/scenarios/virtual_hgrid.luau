--!strict
--[[ THE LAZY GRID, SIDEWAYS — `newVirtualGrid { axis = "x" }`.

	WHAT IS ON SCREEN. A rail of five thousand cells in a small number of ROWS,
	scrolling sideways, with a live count of the ones the `cell` factory was ever
	asked for. A lazy rail and an eager one paint the same first screen, so — as in
	`virtual_grid` — the demonstration is a NUMBER, and the lane chips reflow every
	item onto a different LINE without moving the cell under the player's eye.

	WHY IT IS A SEPARATE FIXTURE RATHER THAN A STEP ON THE VERTICAL ONE. The two
	axes do not differ in a value; they differ in which axis the LANES divide and
	which way the RING walks, and both of those are things you look at rather than
	read. Here the lanes run DOWN and the lines advance RIGHTWARD, so the keyboard
	ring steps a cell with Down and a whole line with Right — the exact transpose of
	the vertical grid's, and the opposite transposition from `newVirtualList`'s.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and what the steps drive instead: the build
	counter barely moving while the rail travels four thousand cells; the anchored
	item surviving a lane change; and the ring crossing a line boundary.

	THE TWO SWEEP LESSONS THIS FIXTURE INHERITS, both learned by `virtual_grid` and
	both sharper on this axis:

	  1. THE CELL FACE IS A `tint`ED BOX, NEVER A THEMED `surface`. A themed surface
	     carries its package's chrome `contentInsets`, which under fantasy-ornate is
	     40px a side — on a windowed cell that collapses the content box to 0px and
	     filed 790 findings on the vertical fixture. `tint` is the continuous-colour
	     channel and carries no chrome at all.

	  2. THE CONSTRAINED AXIS IS THE LANE AXIS, AND HERE THAT IS THE HEIGHT — which
	     is why THIS FIXTURE HAS NO PER-CELL TEXT, and that is a finding rather than
	     a shrug. On the vertical grid a squeezed lane squeezes a cell's WIDTH, and
	     text answers a narrow box by truncating; the label there is free. A squeezed
	     lane here squeezes its HEIGHT, and text has NO vertical truncation to answer
	     with. Three drafts, each swept:

	       a literal 2-or-3 lanes                                436 findings
	       lanes derived from the label size + the text offset     371  (it missed the
	                                                                  theme's TYPE
	                                                                  SCALE)
	       lanes derived from the framework's full text formula  542  (worse: the
	                                                                  derived count
	                                                                  fed back into
	                                                                  the geometry
	                                                                  it was derived
	                                                                  from)

	     Every one of those was a consumer PREDICTING a text height, which is the
	     mistake `measured_extents.luau` exists to end and `variable_extents.luau`
	     records making (a literal 1.25 line ratio; 372 findings on its own rows).
	     The prediction is not improved here, it is DELETED: a cell is a tinted
	     plate whose blend steps every hundred items, so the rail has visible
	     landmarks with nothing in it that can outgrow its lane at any type scale.
	     The numbers the vertical fixture prints on its cells are in the status line
	     instead, where one box holds them and the solver sizes that box.

	     WHAT THIS IS NOT: a claim that a sideways grid cannot hold text. It is a
	     claim that a cell whose LANE is a division of an unknown height must either
	     hold something that cannot overflow, or MEASURE — and the measuring route
	     already exists one control over (`newVirtualList { itemExtent = "measured" }`).
	     A grid cannot use it yet, because a grid's line extent is a fact about
	     `columns` cells rather than one. That is a real remaining gap and it is
	     recorded as one, not papered over with a waiver.
]]

local ITEM_COUNT = 5000
-- ONE LINE OF CELLS' size along the scroll axis: on `axis = "x"` that is its WIDTH
local LINE_EXTENT = 72
--[[ THE TWO GUTTERS ARE THEME METRIC NAMES, not numbers (purity audit §5,
	2026-08-22). `newVirtualGrid.gap` and `.rowGap` refused a string until this
	round — `gap` refused even a `Readable` — so a fixture that wanted a
	theme-tracking gutter had to hold pixels, and a held pixel is wrong the moment
	the theme moves: at ten-foot every space step scales by the type floor's factor
	and a literal 6 does not. The lane readout below reads the RESOLVED number
	back off the grid's own dump rather than keeping a copy, so this file
	predicts nothing.

	RESTORED TO "tight" (task G-SPACE). No space step named 6 at the
	time this round shipped, so both gutters were force-moved to `"xs"` (4) at
	neutral — a deliberate VALUE CHANGE, recorded in the G4/G5 report as "no
	metric in any shipped package resolves to 6". `space.tight` does now, and
	`"tight"` is 6 at arm's length and scales with the rest of the surface on a
	television exactly as `"xs"` did — which is the whole point of naming it. ]]
local CELL_GAP = "tight" -- between cells ACROSS a line (vertical here)
local LINE_GAP = "tight" -- between LINES (horizontal here)
--[[ TWO LANE CHOICES AND THREE BUTTONS, AND THE SWEEP CHOSE BOTH NUMBERS. On a
	640x320 landscape phone at the Largest text preference this surface has 200px
	once the CoreGui topbar and the showcase chip strip are out, and the page cannot
	delegate its scrolling (the rail IS the scroll host; nesting one inside another
	is a gesture with two owners). A third lane chip wrapped the control row onto a
	second line and a two-line status added another, which pushed the page 64-87px
	past its own box under two packages and left the rail a 15px box inside a scroll
	whose own chrome insets are 17px a side — "nothing inside this scroll can draw".
	Two chips, three buttons, one status line: the page fits, and the reflow the
	chips exist for still has two states to move between. ]]
local LANE_CHOICES = { 2, 3 }
local DEFAULT_LANES = 2

local DEEP_INDEX = 4000

-- ONE SPELLING of the pane path, so the blueprint id and the `onGeometry` lookup
-- cannot drift apart
local RAIL_PANE = "/VirtualHGrid/RailPane"

-- the window before any geometry exists, deliberately SMALL: a rail that starts
-- too narrow can only grow on the next solve; one that starts too wide paints over
-- the frame a player sees first
local SEED_WINDOW = 120

return {
	title = "Lazy grid, sideways (newVirtualGrid axis = x)",
	ledgerRows = { "R3-HGRID" },
	build = function(ctx: any)
		local UI = ctx.Facet.UI
		local core = ctx.core
		local scope = core:scope("virtual-hgrid")

		local cells = table.create(ITEM_COUNT)
		for i = 1, ITEM_COUNT do
			-- the blend steps every hundred items: five visible bands across the rail,
			-- so a reflow has something to be watched against
			cells[i] = { id = `h{i}`, blend = 0.18 + ((i - 1) // 100 % 5) * 0.11 }
		end
		local items = scope:own(core:signal(cells))
		local laneChoice = scope:own(core:signal(DEFAULT_LANES))
		-- the rail's cross extent (its height), published by `onGeometry` off the
		-- same solved box the window comes from. It is REPORTED, not used to size
		-- anything: the lane height is the grid's own division of it, and the point
		-- of the fixture is that nothing here predicts that number.
		local railCross = scope:own(core:signal(0))
		local lanes = laneChoice

		-- the fixture's whole subject: a COUNT OF `cell` CALLS, not a timer and not
		-- a mounted-node count. Those answer "how big is the tree"; a lazy grid is
		-- answering "how many were ever made".
		local built = 0
		local builtCount = scope:own(core:signal(0))

		local viewportExtent = scope:own(core:signal(SEED_WINDOW))

		local grid = ctx.Facet.Controls.VirtualGrid(core, {
			id = "Rail",
			-- the one word that makes this fixture different from `virtual_grid`
			axis = "x",
			items = items,
			key = function(item: any): string
				return item.id
			end,
			-- the LANE count: rows down the height, because the lanes always divide
			-- the axis the grid does NOT scroll
			columns = lanes,
			itemExtent = LINE_EXTENT,
			gap = CELL_GAP,
			rowGap = LINE_GAP,
			viewportExtent = viewportExtent,
			overscan = 2,
			cell = function(item: any): any
				built += 1
				builtCount:set(built)
				--[[ A PLATE AND NOTHING ELSE. Both dims are `fill`, so the cell's box
					IS the plate's box and the overlap guard has nothing to complain
					about at any lane height; the blend steps every hundred items, which
					is what gives the rail landmarks to watch during a reflow without
					putting a glyph in a box whose height nobody can predict (header
					lesson 2). The face is a `tint`, never a themed `surface`. ]]
				return UI.Box({
					id = "Plate",
					width = UI.fill(),
					height = UI.fill(),
					tint = { role = "accent", blend = item.blend },
				})
			end,
		})

		local status = scope:own(core:memo(function(use)
			local n = use(builtCount)
			use(grid.scrollTop)
			use(lanes)
			local cross = use(railCross)
			local d = grid.dump()
			-- the LANE HEIGHT is printed because it is the number this axis makes
			-- interesting and the one no cell may assume: the grid's own division of
			-- a height the screen chose
			-- ...and the gutter it divides around is the grid's OWN resolved number
			-- (`d.gap`, the ACROSS-a-line gutter, which on this axis is the one
			-- between lanes), never a copy held here: a name resolves per solve and a
			-- copy would answer for whatever the theme used to say.
			local lane = if d.lanes > 0 then (cross - d.gap * (d.lanes - 1)) // d.lanes else 0
			return `cells built: {n} of {ITEM_COUNT} — window {#d.window} in {d.lanes} lanes of {lane}px, `
				.. `lines {d.lines[1]}-{d.lines[2]} of {d.lineCount}, canvas {d.content}px wide, `
				.. `anchor {tostring(d.anchorKey)}`
		end))

		local laneChips = {}
		for _, count in LANE_CHOICES do
			table.insert(
				laneChips,
				UI.Button({
					id = `Lanes{count}`,
					label = tostring(count),
					selected = scope:own(core:memo(function(use)
						return use(laneChoice) == count
					end)),
					onActivate = function()
						laneChoice:set(count)
					end,
				})
			)
		end

		local function jumpTo(index: number): string?
			return grid.revealItem(`h{index}`)
		end

		--[[ NO PAGE TITLE, AND THE CONTROLS WRAP RATHER THAN THE PAGE SCROLLING —
			both for the reasons `virtual_grid` records. The rail IS a scroll host, and
			nesting one inside another is a gesture with two owners; and on a 640x320
			landscape phone at the Largest text preference there is no room for a title
			the picker chip already carries. ]]
		local screen = UI.Screen({
			id = "VirtualHGrid",
			padding = "s",
			gap = "tight",
			children = {
				UI.HStack({
					id = "Controls",
					wrap = true,
					gap = "tight",
					width = UI.fill(),
					children = (function()
						local kids: { any } = {}
						for _, chip in laneChips do
							table.insert(kids, chip)
						end
						table.insert(
							kids,
							UI.Button({
								id = "Deep",
								label = "Jump",
								onActivate = function()
									jumpTo(DEEP_INDEX)
								end,
							})
						)
						table.insert(
							kids,
							UI.Button({
								id = "Start",
								label = "Start",
								onActivate = function()
									jumpTo(1)
								end,
							})
						)
						return kids
					end)(),
				}),
				UI.Text({ id = "Status", text = status, textSize = "caption", role = "secondary", lineLimit = 1 }),
				--[[ THE PANE WHOSE SOLVED WIDTH IS THE RAIL'S WINDOW, and whose solved
					HEIGHT is the rail's cross extent. On `axis = "x"` the grid refuses a
					`width` — there the width IS the scroll axis — and its height fills its
					container, so this pane is the single place the screen decides both. ]]
				UI.VStack({
					id = "RailPane",
					width = UI.fill(),
					height = UI.fill(),
					children = { grid.blueprint },
				}),
			},
		})

		local unbind: any = nil
		return {
			screen = screen,
			present = {
				onGeometry = function(rectOf: (string) -> any)
					local pane = rectOf(RAIL_PANE)
					if pane == nil or type(pane.w) ~= "number" or type(pane.h) ~= "number" then
						return
					end
					-- the WIDTH is the window, because the width is this grid's scroll
					-- axis; the HEIGHT is the cross extent the lane count is derived from.
					-- Both come from the same solved box, so they cannot disagree about
					-- which pane they describe.
					local window = math.max(0, math.floor(pane.w))
					if window ~= viewportExtent:get() then
						viewportExtent:set(window)
					end
					local cross = math.max(0, math.floor(pane.h))
					if cross ~= railCross:get() then
						railCross:set(cross)
					end
				end,
			},
			grid = grid,
			lanes = lanes,
			laneChoice = laneChoice,
			railCross = railCross,
			builtCount = builtCount,

			steps = {
				bind = function(b: any)
					unbind = grid.bindNativeScroll(b.handle.controller)
					return grid.scrollPath() or "bound"
				end,
				-- the laziness, as one drive: travel four thousand cells and report the
				-- built count either side. The window moves by its own size; the counter
				-- moves by a band, not by four thousand.
				scrollDeep = function(_b: any, payload: string?)
					local index = tonumber(payload or DEEP_INDEX) or DEEP_INDEX
					local before = built
					local path = jumpTo(index)
					local d = grid.dump()
					return {
						builtBefore = before,
						builtAfter = built,
						builtByThisJump = built - before,
						itemCount = ITEM_COUNT,
						path = path,
						lines = d.lines,
						scrollTop = d.scrollTop,
						window = #d.window,
					}
				end,
				-- the reflow, as one drive. The lane count is the destabilizer only a
				-- grid has; both directions report the anchored key and the offset either
				-- side, so the drive SHOWS which of the two outcomes happened rather than
				-- asserting one (the vertical fixture records the honest edge: a scroll
				-- write clamps against the canvas of the LAST solve, so an item in the
				-- final screenful cannot be restored on the frame the lanes multiply it).
				narrow = function()
					local before = grid.dump()
					laneChoice:set(LANE_CHOICES[1])
					local after = grid.dump()
					return {
						lanesBefore = before.lanes,
						lanesAfter = after.lanes,
						anchorBefore = before.anchorKey,
						anchorAfter = after.anchorKey,
						scrollBefore = before.scrollTop,
						scrollAfter = after.scrollTop,
						firstBefore = before.window[1],
						firstAfter = after.window[1],
						contentAfter = after.content,
						built = built,
					}
				end,
				widen = function()
					local before = grid.dump()
					laneChoice:set(LANE_CHOICES[#LANE_CHOICES])
					local after = grid.dump()
					return {
						lanesBefore = before.lanes,
						lanesAfter = after.lanes,
						anchorBefore = before.anchorKey,
						anchorAfter = after.anchorKey,
						scrollBefore = before.scrollTop,
						scrollAfter = after.scrollTop,
						firstBefore = before.window[1],
						firstAfter = after.window[1],
						contentAfter = after.content,
						built = built,
					}
				end,
				setLanes = function(_b: any, payload: string?)
					laneChoice:set(tonumber(payload or DEFAULT_LANES) or DEFAULT_LANES)
					return { lanes = grid.dump().lanes, content = grid.dump().content }
				end,
				focusCell = function(_b: any, payload: string?)
					return grid.focusKey(payload or `h{DEEP_INDEX}`)
				end,
				-- back to the seed state. The build counter is NOT reset: it is the
				-- fixture's cumulative evidence.
				reset = function()
					laneChoice:set(DEFAULT_LANES)
					jumpTo(1)
					local d = grid.dump()
					return { lanes = d.lanes, scrollTop = d.scrollTop, built = built }
				end,
			},

			report = function()
				local d = grid.dump()
				return {
					axis = d.axis,
					built = built,
					itemCount = d.itemCount,
					lanes = d.lanes,
					laneChoice = laneChoice:get(),
					railCross = railCross:get(),
					window = d.window,
					mounted = #d.window,
					lines = d.lines,
					lineCount = d.lineCount,
					scrollTop = d.scrollTop,
					content = d.content,
					itemExtentMode = d.itemExtentMode,
					anchorKey = d.anchorKey,
					viewportExtent = viewportExtent:get(),
				}
			end,

			dispose = function()
				if unbind then
					unbind()
				end
				grid.dispose()
				scope:dispose()
			end,
		}
	end,
}
