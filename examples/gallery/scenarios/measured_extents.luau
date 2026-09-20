--!strict
--[[ Scenario 'measured_extents' — A LIST WITH NO HEIGHT ARITHMETIC IN IT AT ALL.

	`UI.VirtualList` with `itemExtent = "measured"`. READ THIS BESIDE
	`variable_extents.luau`, which declares each post's height and reproduces the
	solver's text arithmetic to do it. This file contains no such block: the row
	paints, the list measures what it painted and windows at that. The body has NO
	`lineLimit`, so how many lines a post occupies is decided by the live width,
	the live type scale and the live text preference — a number no consumer could
	predict.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR:

	  · THE FOUR MEASURED TEXT OFFSETS, walked with nothing recomputed. The rows
	    simply grow and the list follows them.
	  · IT IS STILL VIRTUALIZED. The status line counts the rows that are mounted
	    right now and the rows the `row` component was ever asked for. The first
	    stays a handful when you fling and never approaches 400.
	  · THE SCROLL DOES NOT JUMP. Change the size while parked in the middle and the
	    post under the top edge stays under the top edge, even though every offset
	    above it just grew.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT. The list fills `ListPane`,
	and the pane's height is the screen's decision.

	TWO HOSTS MOUNT THIS FILE, AND ONLY ONE OF THEM RUNS STEPS (the pair
	`card_rail.luau` documents): the scenario runner drives `steps` by name, and the
	showcase demo picker mounts it with a minimal ctx and NO step ever runs.
]]

local POST_COUNT = 400

-- the four measured accessibility offsets — the same set
-- `tests/large_text_matrix.spec.luau` and the overflow sweep walk
local TEXT_OFFSETS = { 0, 4, 10, 14 }

--[[ THE SEED FOR A POST NOBODY HAS SCROLLED TO YET, and the one number in this
	file that is a guess. It is allowed to be a guess: `estimatedItemExtent` decides
	only how long the canvas CLAIMS to be before a row has been seen, never how tall
	a row is painted — a wrong estimate moves the scroll thumb's proportion and
	nothing else, and it is corrected the moment the row is on screen.

	IT DELIBERATELY OVER-RESERVES a little (a two-line post at the default
	preference is nearer 60). Over-reserving is the safe direction here for the same
	reason it is for a declared extent: the first solve of a newly windowed row is
	the one frame where the row's box is still the estimate while its content is
	already the truth, so an estimate that is too SMALL is the one that lets a post
	paint over its neighbour for that frame. ]]
local ESTIMATED_POST = 76

-- how many sentences post `i` carries: deterministic, 1..7, so the fixture is the
-- same list on every run and on every device. NOTE what is NOT here: how many
-- LINES that becomes. That is the solver's answer, not the fixture's, and this
-- whole scenario exists because it is the answer nobody can predict.
local function sentencesFor(index: number): number
	return (index * 3) % 7 + 1
end

return {
	title = "Measured item extents (ruling 7, stage 2)",
	ledgerRows = { "R3-VIE" },
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose

		local posts = {}
		for i = 1, POST_COUNT do
			table.insert(posts, {
				id = "m" .. i,
				title = `Post {i}`,
				body = string.rep(`A sentence about post {i}. `, sentencesFor(i)),
			})
		end
		local items = Compose.cell(posts)
		local textOffset = Compose.cell(0)
		local titleSize = Compose.formula(function(use)
			return 15 + use(textOffset)
		end)
		local bodySize = Compose.formula(function(use)
			return 13 + use(textOffset)
		end)

		-- The row component counts itself in and out, so the status line reports
		-- the window from the application's side of the list.
		local mounted = Compose.cell(0)
		local built = Compose.cell(0)

		--[[ THE STATUS LINE IS THE INSTRUMENT, and it reports the fact a screenshot
			cannot: how much of this list is virtualized (mounted vs 400, and how many
			rows were ever built to get here). ]]
		local status = Compose.formula(function(use)
			return `mounted {use(mounted)} of {POST_COUNT} · built {use(built)} · text +{use(textOffset)}`
		end)

		--[[ A STABLE PROXY, not a plain upvalue: `screen()` below is called once,
			lazily, by whatever presents it (`runtime.mount` opens the owner
			`UI.VirtualList` needs, which does not exist yet while `build()` itself
			is running), so `ref` cannot fire until well after this scenario's
			`return` table is built. A plain `local list; ref = function(record)
			list = record.api end` would freeze `list = list` at nil in that return
			table forever. This table's IDENTITY is what `return { list = list }`
			captures, and its `__index` resolves through to the real record once
			`ref` sets `listApi` — so a reader that waits until after mount (the
			showcase host's native-scroll auto-bind, `tests/gallery_demo_picker.spec`)
			sees the real thing. ]]
		local listApi: any
		local list = setmetatable({}, {
			__index = function(_, key)
				return if listApi ~= nil then listApi[key] else nil
			end,
		})

		local function screen()
			local sizes = {}
			for _, offset in TEXT_OFFSETS do
				table.insert(sizes, { value = offset, label = `+{offset}` })
			end
			return UI.Screen("MeasuredExtents")({
				padding = "s",
				gap = "tight",

				-- The page does not scroll: the list IS a scroll host, and nesting one
				-- inside another is a gesture with two owners.
				UI.Picker("TextSize")({
					style = "segmented",
					selected = textOffset,
					options = sizes,
				}),
				-- capped at two lines so a longer status string can never be the thing
				-- that pushes the list out of its own page
				UI.Text("Status")({ text = status, textSize = "caption", role = "secondary", lineLimit = 2 }),
				-- the pane whose solved height IS the list's window. `fill` is what makes
				-- it the screen's decision rather than the list's
				UI.VStack("ListPane")({
					width = UI.fill(),
					height = UI.fill(),
					UI.VirtualList("Feed")({
						-- `UI.VirtualList(...)` (the app's `api`-flavoured control library)
						-- answers only the blueprint node; the control's own verbs and its
						-- native-scroll mirror arrive through `ref`, per the round-2
						-- addendum's contract.
						ref = function(record: any)
							listApi = record.api
						end,
						rows = items,
						key = "id",
						--[[ THE WHOLE DECLARATION. There is no function here, no theme metric
							and no arithmetic — the two lines below are everything this
							fixture says about how tall a post is. ]]
						itemExtent = "measured",
						estimatedItemExtent = ESTIMATED_POST,
						viewportExtent = "auto",
						overscan = 2,
						cell = function(_, ctx: any): any
							-- The cell receives the item; `ctx.current` follows its edits.
							local item = Compose.formula(ctx.current)
							mounted:set(mounted:peek() + 1)
							built:set(built:peek() + 1)
							Compose.cleanup(function()
								mounted:set(mounted:peek() - 1)
							end)
							return UI.VStack("Post")({
								padding = 10,
								gap = "xs",
								width = UI.fill(),

								UI.Text("Title")({
									text = function(use)
										return use(item).title
									end,
									textSize = titleSize,
								}),
								--[[ NO `lineLimit`, ON PURPOSE. The body wraps to whatever the
									live width and the live type scale make it, which is the
									case a declared extent cannot express at all. ]]
								UI.Text("Body")({
									text = function(use)
										return use(item).body
									end,
									textSize = bodySize,
								}),
							})
						end,
					}),
				}),
			})
		end

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the cell a test drives, rather than a
			-- re-implementation of it
			textOffset = textOffset,
			-- published for the showcase host's native-scroll auto-bind, which probes
			-- a returned table's values for a flat `bindNativeScroll` (see
			-- `variable_extents.luau`, the sibling fixture this pattern is carried
			-- from)
			list = list,

			steps = {
				setTextSize = function(_built: any, payload: string?)
					textOffset:set(tonumber(payload or "0") or 0)
					return { offset = textOffset:peek() }
				end,
			},

			report = function()
				return {
					textOffset = textOffset:peek(),
					mounted = mounted:peek(),
					built = built:peek(),
					itemExtentMode = "measured",
					estimatedItemExtent = ESTIMATED_POST,
				}
			end,
		}
	end,
}
