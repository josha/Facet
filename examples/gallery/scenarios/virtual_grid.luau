--!strict
--[[ Scenario 'virtual_grid' — FIVE THOUSAND CELLS, AND THE COUNT OF THE ONES
	THAT WERE EVER BUILT.

	`Facet.newVirtualGrid` is the lazy grid: a grid that mounts
	only the LINES OF CELLS the viewport touches. The standing obligation is that
	every new public API appears in a gallery scenario the headless suite executes,
	and this is that scenario.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR:

	  · A LAZY GRID AND AN EAGER ONE ARE THE SAME PICTURE. `UI.Grid` over five
	    thousand cells would paint an identical first screen and then never finish
	    a solve again — so the demonstration cannot be the grid, it has to be a
	    NUMBER. The `cell` factory increments a counter and the status line reports
	    "cells built: N of 5000" beside the mounted-window size, which is the only
	    place the feature exists. Fling the grid to the bottom and N moves by tens
	    while the collection is five thousand; that difference IS a vertical grid.
	  · THE REFLOW KEEPS THE PLAYER'S PLACE. The lane chips rewrite `columns`
	    live, and a lane-count change moves EVERY item to a different line — a
	    grid's own destabilizer, which `newVirtualList` never has because there an
	    item IS its line. The control anchors on the ITEM under the viewport's
	    leading edge, so the cell you were looking at is still the cell you are
	    looking at; the status line reports the anchored key across the change.
	  · IT IS THE INDEX, NOT A SECOND ARITHMETIC. `content` in the report is
	    `virtual_extents` over `ceil(5000 / lanes)` LINES, which is the whole
	    reuse: the canvas total changes when the lanes change, and the built count
	    does not.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT, and the sibling fixture's
	history is why that sentence is written down rather than assumed:
	`variable_extents` filed 418 findings on itself the first time the overflow
	sweep reached it (docs/plans/variable-item-extents.md, "What the showcase
	proved about Stage 1, the hard way"), 372 of them rows painting over their
	neighbours, because it reproduced the solver's text arithmetic by hand and got
	it wrong. This fixture does not reproduce that arithmetic AT ALL, and the two
	choices that make that safe are deliberate rather than lazy:

	  · THE LINE EXTENT IS ONE COMFORTABLY LARGE UNIFORM NUMBER (`LINE_EXTENT`,
	    96px). A per-line function would have been the expressive choice and the
	    expressive choice is the one that has to predict `typographyScale`,
	    `typographyPaintScale`, `preferredTextOffset` and the theme's line height
	    correctly on every device. Here there is nothing to predict: the cell holds
	    ONE short line of 12px text, whose largest box anywhere in the swept cross
	    product — the ten-foot type scale times the Largest accessibility
	    preference times the tallest package line height — is comfortably under
	    the slot even after the plate's own padding. Over-reserving is the safe
	    direction and the solver says so ("a slot a few px too TALL is the safe
	    direction"); this fixture's subject is LAZINESS, and buying that
	    demonstration with a second demonstration's defect would be a bad trade.
	  · THE GRID'S WINDOW IS THE PANE THE SOLVER GAVE IT, fed back through
	    `present.onGeometry` — never `viewportHeight - <a reserve for chrome>`,
	    which is the same class in its other spelling. `GridPane` takes `fill`, so
	    its height is the screen's decision and never the grid's, and the grid has
	    no floor of its own: a pane that is genuinely 0px on a short landscape
	    phone gets a 0px grid, because a grid that insists on one line in a 0px
	    pane paints that line over whatever sits beside it.

	TWO HOSTS MOUNT THIS FILE, AND ONLY ONE OF THEM RUNS STEPS (the pair
	`card_rail.luau` documents): the scenario runner drives `steps` by name, and
	the showcase demo picker mounts it with a minimal ctx and NO step ever runs.
	Everything a player can do here is an ordinary control with its own
	`onActivate`, never a scripted drive.
]]

local ITEM_COUNT = 5000

--[[ ONE LINE OF CELLS, IN PX — the number `itemExtent` declares, and the number
	the solver's lying-extent guard measures every mounted cell against.

	IT IS UNIFORM AND IT IS GENEROUS, ON PURPOSE (see the header). The plate below
	paints ONE line of `LABEL_SIZE` text inside `CELL_PADDING` on each side. The
	solver's own arithmetic for an authored numeric size is

	    px = ceil(lines * (size * max(typographyScale, typographyPaintScale)
	                       + preferredTextOffset) * theRole'sLineHeight)

	and its worst case anywhere in the swept cross product — the ten-foot display
	class, the Largest accessibility preference, the tallest shipped package line
	height — is around 55px. Plus 20px of padding that leaves better than 20px of
	headroom, and headroom is exactly what a declared extent is allowed to have. ]]
local LINE_EXTENT = 96
local CELL_PADDING = 10
local LABEL_SIZE = 12

-- THE TWO GUTTERS (across a line, and between lines) ARE THEME METRIC NAMES (purity audit §5, 2026-08-22), for the
-- reason `virtual_hgrid` states at length: a held pixel does not scale at
-- ten-foot and a name does. `newVirtualGrid` refused a string until this round.
--
-- RESTORED TO "tight" (task G-SPACE): the G4/G5 round wanted 6 here
-- and no space step named it, so both gutters were force-moved to "xs" (4) at
-- neutral — a deliberate VALUE CHANGE recorded in that round's report because
-- "no metric in any shipped package resolves to 6" at the time. `space.tight`
-- now does, and restoring it is the matching deliberate value change back.
local CELL_GAP = "tight"
local LINE_GAP = "tight"

-- the lane counts the chips offer. The middle one is the seed, so the swept
-- (step-free) mount is the ordinary case rather than either extreme.
local LANE_CHOICES = { 2, 4, 8 }
local DEFAULT_LANES = 4

-- the cell a deep jump aims at: far enough down that no window has ever held it,
-- which is the point of the step
local DEEP_INDEX = 4000

-- the path `onGeometry` reads the grid's window off. One spelling, so the
-- blueprint id and the lookup cannot drift.
local GRID_PANE = "/VirtualGrid/GridPane"

--[[ THE WINDOW BEFORE ANY GEOMETRY EXISTS, and it is deliberately SMALL. A grid
	that starts too short can only grow on the next solve; a grid that starts too
	tall paints over the frame a player sees first. ]]
local SEED_WINDOW = 96

return {
	title = "Lazy grid (newVirtualGrid)",
	ledgerRows = { "R3-VGRID" },
	build = function(ctx: any)
		local UI = ctx.Facet.UI
		local core = ctx.core
		local scope = core:scope("virtual-grid")

		local cells = table.create(ITEM_COUNT)
		for i = 1, ITEM_COUNT do
			cells[i] = { id = `c{i}`, label = tostring(i) }
		end
		local items = scope:own(core:signal(cells))
		local lanes = scope:own(core:signal(DEFAULT_LANES))

		--[[ THE BUILD COUNTER — the fixture's whole subject, and the same
			instrument `tests/virtual_grid.spec.luau` proves the feature with. It is a
			COUNT OF `cell` CALLS, not a timer and not a mounted-node count: those two
			answer "how big is the tree", and the question a lazy grid is answering is
			"how many were ever made". The plain number is what `report()` publishes;
			the Signal beside it is what puts the number on screen, and it is written
			from the factory rather than derived, because nothing else in the tree
			knows a cell was built. ]]
		local built = 0
		local builtCount = scope:own(core:signal(0))

		local viewportExtent = scope:own(core:signal(SEED_WINDOW))

		local grid = ctx.Facet.Controls.VirtualGrid(core, {
			id = "Cells",
			items = items,
			key = function(item: any): string
				return item.id
			end,
			columns = lanes,
			itemExtent = LINE_EXTENT,
			gap = CELL_GAP,
			rowGap = LINE_GAP,
			viewportExtent = viewportExtent,
			overscan = 2,
			cell = function(item: any): any
				built += 1
				builtCount:set(built)
				--[[ THE PLATE IS `fill` ON BOTH AXES AND HOLDS ONE SHORT LINE. Both
					halves matter to the solver: a `fill` axis is granted exactly the
					cell's box at arrange, so the overlap guard excuses it, and
					`lineLimit = 1` is what makes "one line" a contract rather than a
					hope — a label that wrapped would be free to outgrow the slot at a
					lane count nobody swept.

					THE FACE IS A `tint`ED BOX AND NOT A `surface`, AND THAT IS THE FIRST
					THING THE SWEEP TAUGHT THIS FIXTURE. `surface = "raised"` was here,
					and a themed surface brings its package's chrome `contentInsets` with
					it: under fantasy-ornate the panel slot is 40px a side, which on a
					70px cell collapsed the content box to 0px on BOTH axes and made the
					cell measure 97px against its own 96px slot — 790 findings, all of
					them that one word. `tint` is the continuous-colour channel and
					carries no chrome at all, so the plate is paint and the geometry stays
					this fixture's own. ]]
				return UI.ZStack({
					id = "Plate",
					width = UI.fill(),
					height = UI.fill(),
					padding = CELL_PADDING,
					alignH = "center",
					alignV = "center",
					children = {
						UI.Box({
							id = "Face",
							width = UI.fill(),
							height = UI.fill(),
							tint = { role = "accent", blend = 0.35 },
						}),
						UI.Text({
							id = "N",
							text = item.label,
							textSize = LABEL_SIZE,
							textAlign = "center",
							lineLimit = 1,
							width = UI.fill(),
						}),
					},
				})
			end,
		})

		--[[ THE STATUS LINE IS THE INSTRUMENT, and it reads three live signals so
			that it re-derives on every one of the three things a player can do here:
			scroll (the engine's offset, mirrored into `grid.scrollTop`), change the
			lane count, and cause a cell to be built. `dump()` is then read for its
			current answer — it is a snapshot, not a Readable, so the `use` calls above
			it are what make the snapshot arrive at the right moment. ]]
		local status = scope:own(core:memo(function(use)
			local n = use(builtCount)
			use(grid.scrollTop)
			use(lanes)
			local d = grid.dump()
			return `cells built: {n} of {ITEM_COUNT} — window {#d.window} in {d.lanes} lanes, `
				.. `lines {d.lines[1]}-{d.lines[2]} of {d.lineCount}, canvas {d.content}px`
		end))

		local laneChips = {}
		for _, count in LANE_CHOICES do
			table.insert(
				laneChips,
				UI.Button({
					id = `Lanes{count}`,
					label = tostring(count),
					selected = scope:own(core:memo(function(use)
						return use(lanes) == count
					end)),
					onActivate = function()
						lanes:set(count)
					end,
				})
			)
		end

		-- reach a cell no window has ever held, through the control's own public
		-- route: `revealItem` computes the canvas offset from the index and issues
		-- the framework's one programmatic scroll write
		local function jumpTo(index: number): string?
			return grid.revealItem(`c{index}`)
		end

		local screen = UI.Screen({
			id = "VirtualGrid",
			padding = "s",
			gap = "tight",
			children = {
				--[[ THERE IS NO PAGE TITLE, AND ITS ABSENCE IS THE SECOND THING THE
					SWEEP TAUGHT THIS FIXTURE. A 640x320 landscape phone leaves this
					surface a 640x200 box once the CoreGui topbar and the showcase's chip
					strip are taken out, and at the Largest text preference a title, a
					button row and two status lines need 7-32px more than that under six
					of the eight shipped packages — with the grid already windowed down
					to zero. The page CANNOT delegate its scrolling (the grid is the
					scroll host; nesting one inside another is a gesture with two owners),
					so something had to go, and the title was the one line here that says
					nothing the status line does not. The fixture's name is already on the
					picker chip and in `title` above. ]]
				--[[ THE CONTROLS WRAP rather than the page scrolling, for the reason
					`variable_extents` records: the grid IS a scroll host, and nesting one
					inside another is a gesture with two owners. ]]
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
								id = "Top",
								label = "Top",
								onActivate = function()
									jumpTo(1)
								end,
							})
						)
						return kids
					end)(),
				}),
				-- capped at two lines so a longer status string can never be the thing
				-- that pushes the grid out of its own page
				UI.Text({ id = "Status", text = status, textSize = "caption", role = "secondary", lineLimit = 2 }),
				-- the pane whose solved height IS the grid's window (see `onGeometry`
				-- below). `fill` is what makes it the screen's decision, never the
				-- grid's
				UI.VStack({
					id = "GridPane",
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
				-- `onGeometry` is a broadcast the presenter makes after every solve, so
				-- reading one rect here costs the rest of the screen nothing
				onGeometry = function(rectOf: (string) -> any)
					local pane = rectOf(GRID_PANE)
					if pane == nil or type(pane.h) ~= "number" then
						return
					end
					local window = math.max(0, math.floor(pane.h))
					if window ~= viewportExtent:get() then
						viewportExtent:set(window)
					end
				end,
			},
			-- published for the headless suite and for the showcase host's
			-- native-scroll auto-bind, which probes a returned table's values for a
			-- flat `bindNativeScroll`
			grid = grid,
			lanes = lanes,
			builtCount = builtCount,

			steps = {
				bind = function(b: any)
					unbind = grid.bindNativeScroll(b.handle.controller)
					return grid.scrollPath() or "bound"
				end,
				--[[ THE LAZINESS, AS ONE DRIVE. Jump four thousand cells down the
					collection and report the built count either side: the window moves
					by its own size and the counter moves by a band, not by four
					thousand. ]]
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
				--[[ THE REFLOW, AS ONE DRIVE. The lane count is the destabilizer only
					a grid has, so both `narrow` and `widen` report the anchored key and
					the offset either side: the item under the viewport's leading edge is
					the same item afterwards, at whatever offset its NEW line sits at.

					ONE HONEST EDGE, MEASURED HERE ON A REAL PRESENTER (2026-08-15) AND
					REPORTED RATHER THAN HIDDEN. Narrowing MULTIPLIES the canvas — 4 lanes
					to 2 doubles it — and the anchor's scroll write goes through the render
					controller, which clamps against the canvas of the LAST solve. So an
					item in the last screenful of the old canvas cannot be restored on the
					frame the lanes change: from 80% down a 4-lane grid, `narrow` lands at
					the old canvas end instead of the item's new offset. Anywhere else, and
					in the widening direction (where the canvas shrinks) at any offset, the
					item is held exactly — `c77` at 2 033px comes back at 3 971px, its new
					line plus the same 95px into it. The steps report both keys, so the
					drive shows which of the two happened rather than asserting one. ]]
				narrow = function()
					local before = grid.dump()
					lanes:set(LANE_CHOICES[1])
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
					lanes:set(LANE_CHOICES[#LANE_CHOICES])
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
					lanes:set(tonumber(payload or DEFAULT_LANES) or DEFAULT_LANES)
					return { lanes = grid.dump().lanes, content = grid.dump().content }
				end,
				focusCell = function(_b: any, payload: string?)
					return grid.focusKey(payload or `c{DEEP_INDEX}`)
				end,
				-- back to the seed state. The build counter is NOT reset: it is the
				-- fixture's cumulative evidence, and zeroing it would erase the very
				-- thing the other steps are producing
				reset = function()
					lanes:set(DEFAULT_LANES)
					jumpTo(1)
					local d = grid.dump()
					return { lanes = d.lanes, scrollTop = d.scrollTop, built = built }
				end,
			},

			report = function()
				local d = grid.dump()
				return {
					built = built,
					itemCount = d.itemCount,
					lanes = d.lanes,
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
