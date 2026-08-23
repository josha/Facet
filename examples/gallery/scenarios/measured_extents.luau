--!strict
--[[ Scenario 'measured_extents' — A LIST WITH NO HEIGHT ARITHMETIC IN IT AT ALL.

	`newVirtualList.itemExtent = "measured"` (Stage 2 of
	`docs/plans/variable-item-extents.md`, 2026-08-15). Every new public API appears
	in a gallery scenario the headless suite executes, and this is that scenario —
	but it is here for a second reason, and the second one is the argument.

	READ THIS BESIDE `variable_extents.luau`. That fixture demonstrates Stage 1: a
	per-item extent FUNCTION. It is correct today, and being correct cost it a
	thirty-line block reproducing the solver's text arithmetic by hand —
	`max(typographyScale, typographyPaintScale)`, the additive `preferredTextOffset`,
	the live theme's per-role line height, and a `lineLimit` on the body so the
	reserved and drawn line counts cannot drift. It got that wrong on its first cut
	(a literal 1.25 line ratio; 372 solver findings on its own rows) and three other
	`itemExtent` consumers in this repo still carry a waiver for the identical
	mistake.

	THIS FIXTURE CONTAINS NO SUCH BLOCK. Search it for a multiplication: there is
	not one. The cell paints; the list measures what it painted and windows at that.
	The body here deliberately has NO `lineLimit`, so how many lines a post occupies
	is decided by the live width, the live type scale and the live text preference —
	a number no consumer could predict — and that is the case Stage 1 could express
	and could not make easy.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR:

	  · THE FOUR MEASURED TEXT OFFSETS, walked with nothing recomputed. `{0,4,10,14}`
	    is the set the sweep that bought this feature measured (a `row_actions` row
	    declaring 84 and measuring 88 at the DEFAULT preference, 249 at +14 on a
	    320x640 phone). Here the rows simply grow and the list follows them.
	  · CONVERGENCE IS A NUMBER IN THE STATUS LINE. `measured N of 400` is how much
	    of the canvas is truth and how much is still `estimatedItemExtent`, which is
	    the honest statement of this design's one residual cost: the content under
	    the eye is exact, the SCROLL THUMB's proportion is an estimate until every
	    post has been on screen once. Watch it climb as you fling.
	  · IT IS STILL VIRTUALIZED. The mounted count does not move when you fling, and
	    it never approaches 400. The refused candidate design — measure every row at
	    mount — would look identical in a screenshot and would have deleted the
	    property the control exists for.
	  · THE SCROLL DOES NOT JUMP. Change the size while parked in the middle and the
	    post under the top edge stays under the top edge, even though every offset
	    above it just grew. The status line reports the anchored post.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT. The list's window is the
	solved pane fed back through `present.onGeometry`, exactly as `variable_extents`
	learned to do the hard way: a literal reserve for chrome the SOLVER sizes is the
	same defect as a literal row height, one level up.

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

-- the path `onGeometry` reads the list's window off. One spelling, so the
-- blueprint id and the lookup cannot drift.
local LIST_PANE = "/MeasuredExtents/ListPane"

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
		local UI = ctx.Facet.UI
		local core = ctx.core
		local scope = core:scope("measured-extents")

		local posts = {}
		for i = 1, POST_COUNT do
			table.insert(posts, {
				id = "m" .. i,
				title = `Post {i}`,
				body = string.rep(`A sentence about post {i}. `, sentencesFor(i)),
			})
		end
		local rows = core:signal(posts)
		local textOffset = scope:own(core:signal(0))

		--[[ THE LIST'S WINDOW IS THE PANE THE SOLVER GAVE IT (the discipline
			`variable_extents.luau` records at length after the sweep found its literal
			`viewportHeight - 210` reserve painting 77px past its own box). `ListPane`
			takes `fill`, so its height is decided by the screen above it and never by
			the list inside it — it cannot chase its own tail. The seed is only the value
			for the frame before any geometry exists, and it is deliberately SMALL: a
			list that starts too short can only grow. ]]
		local viewportExtent = scope:own(core:signal(72))

		local list = ctx.Facet.Controls.VirtualList(core, {
			id = "Feed",
			rows = rows,
			key = function(item: any): string
				return item.id
			end,
			--[[ THE WHOLE DECLARATION. There is no function here, no `use`, no theme
				metric and no arithmetic — the two lines below are everything this fixture
				says about how tall a post is. ]]
			itemExtent = "measured",
			estimatedItemExtent = ESTIMATED_POST,
			viewportExtent = viewportExtent,
			overscan = 2,
			cell = function(item: any): any
				local titleSize = scope:own(core:memo(function(use)
					return 15 + use(textOffset)
				end))
				local bodySize = scope:own(core:memo(function(use)
					return 13 + use(textOffset)
				end))
				return UI.VStack({
					id = "Post",
					padding = 10,
					gap = "xs",
					width = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = item.title, textSize = titleSize }),
						--[[ NO `lineLimit`, ON PURPOSE. `variable_extents` caps its body at
							exactly the number of lines its extent function reserved, because a
							declared extent and an uncapped wrap cannot both be right. Here the
							body wraps to whatever the live width and the live type scale make
							it, which is the case a declared extent cannot express at all. ]]
						UI.Text({ id = "Body", text = item.body, textSize = bodySize }),
					},
				})
			end,
		})

		--[[ THE STATUS LINE IS THE INSTRUMENT, and it reports the two facts a
			screenshot cannot: how much of this list is virtualized (mounted vs 400) and
			how much of the canvas is truth rather than estimate (measured vs 400). A
			fixture that only showed the settled state would be a picture. ]]
		local status = scope:own(core:memo(function(use)
			--[[ THE TWO DEPENDENCIES ARE THE TWO THINGS THAT MOVE THE NUMBERS, and
				`scrollTop` is the load-bearing one: a measurement lands when a row enters
				the window, and a row enters the window when the player scrolls. Reading
				the dump alone would print the convergence once and then lie about it. ]]
			local offset = use(textOffset)
			local _ = use(list.scrollTop)
			local d = list.dump()
			local mounted = 0
			for _key in list.debugWindow() do
				mounted += 1
			end
			return `mounted {mounted} of {POST_COUNT} · measured {d.measuredRows} of {POST_COUNT} `
				.. `· canvas {d.contentExtent}px · text +{offset}`
		end))

		local sizeChips = {}
		for _, offset in TEXT_OFFSETS do
			table.insert(
				sizeChips,
				UI.Button({
					id = `Size{offset}`,
					label = `+{offset}`,
					selected = scope:own(core:memo(function(use)
						return use(textOffset) == offset
					end)),
					onActivate = function()
						textOffset:set(offset)
					end,
				})
			)
		end

		local screen = UI.Screen({
			id = "MeasuredExtents",
			padding = "s",
			gap = "tight",
			children = {
				--[[ THE CONTROLS WRAP rather than the page scrolling, for the reason
					`variable_extents` records: the list IS a scroll host, and nesting one
					inside another is a gesture with two owners. `wrap = true` is the
					framework's own flow-wrap doing the job a page scroller does elsewhere. ]]
				UI.HStack({
					id = "Controls",
					wrap = true,
					gap = "tight",
					width = UI.fill(),
					children = sizeChips,
				}),
				-- capped at two lines so a longer status string can never be the thing
				-- that pushes the list out of its own page
				UI.Text({ id = "Status", text = status, textSize = "caption", role = "secondary", lineLimit = 2 }),
				-- the pane whose solved height IS the list's window. `fill` is what makes
				-- it the screen's decision rather than the list's
				UI.VStack({
					id = "ListPane",
					width = UI.fill(),
					height = UI.fill(),
					children = { list.blueprint },
				}),
			},
		})

		local unbind: any = nil
		return {
			screen = screen,
			present = {
				onGeometry = function(rectOf: (string) -> any)
					local pane = rectOf(LIST_PANE)
					if pane == nil or type(pane.h) ~= "number" then
						return
					end
					local window = math.max(0, math.floor(pane.h))
					if window ~= viewportExtent:get() then
						viewportExtent:set(window)
					end
				end,
			},
			-- published for the headless suite: the signals a test drives, rather than
			-- a re-implementation of them
			textOffset = textOffset,
			list = list,

			steps = {
				bind = function(built: any)
					unbind = list.bindNativeScroll(built.handle.controller)
					return list.scrollPath and list.scrollPath() or "bound"
				end,
				setTextSize = function(_built: any, payload: string?)
					textOffset:set(tonumber(payload or "0") or 0)
					local d = list.dump()
					return { offset = textOffset:get(), canvas = d.contentExtent, measured = d.measuredRows }
				end,
				focusPost200 = function()
					return list.focusKey("m200")
				end,
				-- the anchoring proof, as one drive: park mid-feed, grow the text,
				-- report where the list ended up and which post was under the top edge
				growWhileScrolled = function(_built: any, payload: string?)
					local before = list.dump()
					textOffset:set(tonumber(payload or "14") or 14)
					local after = list.dump()
					return {
						scrollBefore = before.scrollTop,
						scrollAfter = after.scrollTop,
						firstBefore = before.window[1],
						firstAfter = after.window[1],
					}
				end,
			},

			report = function()
				local mounted, keys = 0, {}
				for key in list.debugWindow() do
					mounted += 1
					table.insert(keys, key)
				end
				table.sort(keys)
				local d = list.dump()
				return {
					textOffset = textOffset:get(),
					mounted = mounted,
					firstKeys = { keys[1], keys[2], keys[3] },
					itemExtentMode = d.itemExtentMode,
					estimatedItemExtent = d.estimatedItemExtent,
					measuredRows = d.measuredRows,
					contentExtent = d.contentExtent,
					scrollTop = d.scrollTop,
				}
			end,

			dispose = function()
				if unbind then
					unbind()
				end
				list.dispose()
				scope:dispose()
			end,
		}
	end,
}
