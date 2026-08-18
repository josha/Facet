--!strict
--[[ Scenario 'variable_extents' — ROWS THAT ARE NOT ALL THE SAME HEIGHT, and
	what a list does when it has to pretend they are.

	`newVirtualList.itemExtent` gained a per-item FUNCTION form (game-director
	ruling 7, 2026-08-13; built 2026-08-14). The standing obligation is that every
	new public API appears in a gallery scenario the headless suite executes, and
	this is that scenario.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR:

	  · THE TOGGLE IS THE WHOLE ARGUMENT, exactly as it is in `flow_wrap`. One
	    switch makes the same list declare ONE number for every row — the
	    pre-feature contract — and the taller posts immediately paint over their
	    neighbours, with `controller.diagnostics()` naming both numbers in the
	    status line, live. The wrong state is the one worth looking at; a
	    screenshot of the right one looks like an ordinary feed.
	  · THE FOUR MEASURED TEXT OFFSETS ARE THE POINT, not decoration. The sweep
	    that bought this feature measured a `row_actions` row at 88px against an
	    84px slot at +0, and at 249px against the same slot at +14 on a 320x640
	    phone. The size picker here walks the same { 0, 4, 10, 14 } and every row
	    re-derives, because the extent function reads the offset through its `use`.
	  · THE SCROLL DOES NOT JUMP. Change the size while scrolled into the middle
	    of the feed and the post under the top edge stays under the top edge. That
	    is a behaviour, not a picture: the status line reports the anchored key and
	    the offset before and after.
	  · IT IS STILL VIRTUALIZED. 400 posts, a mounted count in the status line that
	    does not move when you fling. A feature that made the list measure every
	    row to lay itself out would look identical in a screenshot and be worthless.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT, and the 2026-08-14 overflow
	sweep is why that sentence can now be believed — it was here before, and both
	halves of it were false. The list's window came from `viewportHeight - 210`, a
	reserve for chrome the SOLVER sizes; every row extent came from the fixture's own
	size chips times a literal line ratio, so it ignored the player's real text
	preference, the theme's line height and the ten-foot type scale. 418 findings on
	one surface, 372 of them rows painting over their neighbours. Both are now read
	from the live facts through `use`: the window is the solved pane fed back through
	`present.onGeometry`, and `rowExtent` derives from the same four facts the solver
	measures with. That discipline is what the feature buys; the toggle shows what
	its absence costs, and this fixture's own history shows how easily it is lost.

	TWO HOSTS MOUNT THIS FILE, AND ONLY ONE OF THEM RUNS STEPS (the pair
	`card_rail.luau` documents): the scenario runner drives `steps` by name, and
	the showcase demo picker mounts it with a minimal ctx and NO step ever runs.
	Everything a player can do here is an ordinary control with its own
	`onActivate`, never a scripted drive.
]]

local POST_COUNT = 400

--[[ THE ROW'S GEOMETRY, IN ONE TABLE, READ BY BOTH SIDES. `rowExtent` below
	computes a post's height from these numbers and `cell` paints with the same
	ones, so the declared extent and the painted row cannot disagree — which is
	the whole authoring discipline the per-item form exists to make possible.
	`docs/lessons/facet-fixed-px-heights.md` is the class this avoids: a px
	height fixed against unfixed content. ]]
local METRICS = {
	padding = 10,
	gap = 4,
	titleSize = 15,
	bodySize = 13,
}

-- the four measured accessibility offsets — the same set
-- `tests/large_text_matrix.spec.luau` and the overflow sweep walk
local TEXT_OFFSETS = { 0, 4, 10, 14 }

-- THE LIE THE TOGGLE TELLS: one declared number for every row, which is what
-- every list in this framework had to do before the per-item form. Chosen to be
-- right for a one-line post at +0 and wrong for everything else — the shape the
-- sweep found on `row_actions`.
local UNIFORM_EXTENT = 84

-- the path `onGeometry` reads the list's window off (below). One spelling, so the
-- blueprint id and the lookup cannot drift.
local LIST_PANE = "/VariableExtents/ListPane"

-- how many body lines post `i` has: deterministic, 1..4, so the fixture is the
-- same list on every run and on every device
local function linesFor(index: number): number
	return (index - 1) % 4 + 1
end

--[[ ONE POST'S EXTENT — the function handed to `itemExtent`.

	IT READS EVERY LIVE FACT THROUGH `use`, which is the contract: reading a fact
	with `:get()` would produce the right number once and register no dependency,
	and the extents would then go stale the moment the player changed the text size,
	the theme or the display class. That silent-staleness is the failure mode the
	whole feature exists to end, so the fixture models the correct spelling —
	`textFacts` below is where the live facts are read, once per re-derive rather
	than once per row.

	THIS FIXTURE USED TO CARRY THE ARITHMETIC ITSELF, and it is worth recording why
	it does not any more.

	The overflow sweep filed 372 lying-extent findings on this one node (2026-08-14)
	because the first cut multiplied `(size + <the fixture's own chip offset>)` by a
	literal 1.25 and stopped: right on Studio Neutral at the default preference and
	wrong everywhere else — 8px short at `preferredTextOffset` 4, 54px at 14, and 15px
	short at the DEFAULT preference on a ten-foot display, whose Large class multiplies
	the whole type ladder by 1.5. Every one of those rows painted over its neighbour.

	The second cut reproduced the solver's arithmetic correctly, in this file, and was
	then the ONLY correct copy of it in the repo — while `row_actions`, `perf_capture`
	and `virtual_list_native` each carried a lying-extent waiver for getting the same
	sum wrong the same way. That is an API defect, not three careless consumers, and
	`Facet.text.facts` / `Facet.text.lineBox` are the fix (ruled 2026-08-15,
	docs/plans/variable-item-extents.md). Deleting this fixture's private copy is the
	proof the public shape is the right one: the demo is unchanged, the numbers are
	unchanged, and the arithmetic now comes from the same two seams the solver spends. ]]
local function rowExtent(
	item: any,
	index: number,
	use: any,
	Facet: any,
	textFacts: any,
	chipSignal: any,
	modeSignal: any
): number
	if use(modeSignal) == "uniform" then
		return UNIFORM_EXTENT
	end
	local facts = use(textFacts)
	-- the fixture's OWN size picker, on top of the authored sizes: it is an
	-- authored size like any other, so `text.lineBox` scales it with them
	local chip = use(chipSignal)
	local _ = item
	return METRICS.padding * 2
		+ Facet.text.lineBox({ facts = facts, size = METRICS.titleSize + chip, lines = 1 })
		+ METRICS.gap
		+ Facet.text.lineBox({ facts = facts, size = METRICS.bodySize + chip, lines = linesFor(index) })
end

return {
	title = "Variable item extents (ruling 7)",
	ledgerRows = { "R3-VIE" },
	build = function(ctx: any)
		local UI = ctx.Facet.UI
		local core = ctx.core
		local scope = core:scope("variable-extents")

		local posts = {}
		for i = 1, POST_COUNT do
			table.insert(posts, {
				id = "p" .. i,
				title = `Post {i}`,
				body = string.rep(`Body line for post {i}. `, linesFor(i)),
				lines = linesFor(i),
			})
		end
		local rows = core:signal(posts)
		--[[ THE TOGGLE'S OWN BOOLEAN, and `mode` derived from it. `UI.Toggle` writes
			its bound Signal itself (there is no `onChange` on it — the value IS the
			seam), so the switch is an ordinary control the player drives and the
			scenario's steps write the same signal. ]]
		local uniformOn = scope:own(core:signal(false))
		-- "variable" (each post declares its own height) | "uniform" (one number
		-- for all of them — the pre-feature contract, and the defect)
		local mode = scope:own(core:memo(function(use)
			return if use(uniformOn) then "uniform" else "variable"
		end))
		local textOffset = scope:own(core:signal(0))

		--[[ THE LIVE TEXT FACTS, IN ONE MEMO. Read here rather than inside `itemExtent`
			so 400 extents cost four `use` calls and not sixteen hundred — the per-item
			function is evaluated O(N) per data change and is meant to stay arithmetic
			(docs/plans/variable-item-extents.md, "what was traded"). The memo is also what
			makes the dependency edges exist at all: the whole offset index re-derives when
			the player raises their text size, swaps the theme, or the screen lands on a
			ten-foot display.

			`text.facts` takes the memo's own `use` for exactly that reason — it is the
			caller's derivation the edges have to land in. ]]
		local textFacts = scope:own(core:memo(function(use)
			return ctx.Facet.text.facts({ env = ctx.env, use = use })
		end))

		--[[ THE LIST'S WINDOW IS THE PANE THE SOLVER GAVE IT, fed back through
			`present.onGeometry` — the same shape `row_actions.luau`'s hosted list uses,
			and for the same reason its comment records: *reproduce a framework's
			inputs, never its result*.

			WHAT WAS HERE BEFORE, AND WHY IT WAS THE SAME DEFECT TWICE. This was
			`viewportHeight - 210`, a literal reserve for the title, the wrapping control
			row and the two-line status. The number was measured (150 was the first guess
			and overflowed by 80px), and it was still wrong, because the chrome above the
			list is not a constant — it is the SOLVER's decision. At the largest text
			preference the control row and the status both grow, and the sweep measured
			this page painting 77px past its own box at `preferredTextOffset` 14 and 49px
			at 10, plus a further 19 findings under packages whose own metrics widen the
			same chrome at the DEFAULT preference. `docs/lessons/facet-fixed-px-heights.md`
			is the class, in its height spelling; a fixed reserve against unfixed chrome
			is the same bug as a fixed row height against unfixed text.

			IT CANNOT CHASE ITS OWN TAIL: `ListPane` takes `fill`, so its height is
			decided by the screen above it and never by the list inside it. One solve
			after any change the window is exact; the seed below is only the value for
			the frame before any geometry exists, and it is deliberately SMALL — a list
			that starts too short can only grow, and a list that starts too tall paints
			over the frame a player sees first.

			AND THE WINDOW HAS NO FLOOR OF ITS OWN, which is the second half of the same
			rule. A `math.max(oneRow, pane.h)` here reads like kindness and is the
			original defect back again: on a 640x320 landscape phone at the largest text
			preference this page's own chrome needs 268px of a 200px box, so the pane is
			genuinely 0 — and a list that insists on 72px there paints those 72px over
			whatever is beside it. The page not fitting is a real finding about the page
			(recorded against `/VariableExtents` in the overflow sweep's lists, with the
			measurement); a list that overflows its pane to hide it is a second defect
			laid on top. ]]
		local SEED_WINDOW = 72
		local viewportExtent = scope:own(core:signal(SEED_WINDOW))

		local list = ctx.Facet.newVirtualList(ctx.Facet, core, {
			id = "Feed",
			rows = rows,
			key = function(item: any): string
				return item.id
			end,
			itemExtent = function(item: any, index: number, use: any): number
				return rowExtent(item, index, use, ctx.Facet, textFacts, textOffset, mode)
			end,
			viewportExtent = viewportExtent,
			overscan = 2,
			cell = function(item: any): any
				local titleSize = scope:own(core:memo(function(use)
					return METRICS.titleSize + use(textOffset)
				end))
				local bodySize = scope:own(core:memo(function(use)
					return METRICS.bodySize + use(textOffset)
				end))
				return UI.VStack({
					id = "Post",
					padding = METRICS.padding,
					gap = METRICS.gap,
					width = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = item.title, textSize = titleSize }),
						UI.Text({
							id = "Body",
							text = item.body,
							textSize = bodySize,
							-- `lineLimit` is the wrap contract on UI.Text (there is no
							-- `wrap` prop): the body wraps and is capped at exactly the
							-- number of lines `rowExtent` reserved for it, so the two
							-- sides of the declaration cannot drift
							lineLimit = item.lines,
						}),
					},
				})
			end,
		})

		-- THE STATUS LINE IS THE INSTRUMENT. It reports the mounted count (the
		-- virtualization claim), the canvas total, and — when the toggle is lying —
		-- how many rows the solver's own guard is complaining about. A fixture that
		-- only showed the good state would be a screenshot.
		local status = scope:own(core:memo(function(use)
			local m = use(mode)
			local d = list.dump()
			local mounted = 0
			for _ in list.debugWindow() do
				mounted += 1
			end
			if m == "uniform" then
				return `DECLARING {UNIFORM_EXTENT}px FOR EVERY ROW — taller posts paint over their neighbours. `
					.. `mounted {mounted} of {POST_COUNT}, canvas {d.contentExtent}px`
			end
			return `each post declares its own height — mounted {mounted} of {POST_COUNT}, `
				.. `canvas {d.contentExtent}px, text +{use(textOffset)}`
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

		--[[ THE CHROME'S OWN HEIGHT: HUG WHERE THERE IS ROOM, A BOUNDED SCROLLER
			WHERE THERE IS NOT (O-21, measured 2026-08-15).

			`wrap = true` on the control row was the right first answer and stays, but
			it is not sufficient: at +14 on a 640x320 landscape the title (39), the
			control row's TWO wrapped lines (132) and the two-line status (63) come to
			252px of a 184px canvas, so the page ran 68px over with the list already
			at ZERO — the status line ended 36px below the fold, cut, with nothing to
			scroll it back.

			WHAT DID NOT CHANGE: the block below is still right that a PAGE scroller
			cannot wrap this surface, because the list is a y-scroll host and nesting
			one inside another gives the gesture two owners. A SIBLING scroller is a
			different shape: `Chrome` and `ListPane` sit side by side in the screen's
			stack, each owning its own window, which is exactly the arrangement
			`scroll_host` exists to prove is legal.

			WHY IT IS CONDITIONAL. On any viewport with the room, the chrome hugs and
			the screen looks exactly as it always has — a `fill` here would reserve a
			share of a tall screen for a band that needs ~150px of it and leave the
			rest blank. `heightClass` (ADR-0023) is the framework's own Readable for
			"the vertical room is scarce" and it re-resolves on rotation. ]]
		local conditions = ctx.Facet.adaptive.conditions(core, ctx.env, { scope = scope })
		local chromeHeight = scope:own(core:memo(function(use)
			return if use(conditions.isShort) then { type = "fill", weight = 1 } else nil
		end))

		local screen = UI.Screen({
			id = "VariableExtents",
			padding = 8,
			gap = 6,
			children = {
				UI.ScrollView({
					id = "Chrome",
					axis = "y",
					gap = 6,
					width = { type = "fill", weight = 1 },
					height = chromeHeight,
					children = {
						UI.Text({ id = "Title", text = "400 posts, four heights", textSize = 18 }),
						--[[ THE CONTROLS WRAP rather than the page scrolling. Every other
					fixture here puts its chrome in a page `UI.ScrollView`, and this one
					cannot: the list IS a scroll host, and nesting one inside another is a
					gesture with two owners. `wrap = true` is the alternative that keeps
					the whole page inside its box on a 320px phone — the framework's own
					flow-wrap, doing the job the page scroller does elsewhere. ]]
						UI.HStack({
							id = "Controls",
							wrap = true,
							gap = 6,
							width = { type = "fill", weight = 1 },
							children = (function()
								local kids: { any } = {
									UI.Toggle({ id = "UniformToggle", label = "One height for all", value = uniformOn }),
								}
								for _, chip in sizeChips do
									table.insert(kids, chip)
								end
								return kids
							end)(),
						}),
						-- capped at two lines so a longer status string can never be the thing
						-- that pushes the list out of its own page — and `disclose`d, because a
						-- cap with no way past it is a cut string rather than a declared
						-- degrade (O-21: this line IS cut at +10 and +14 on every phone here)
						UI.Text({
							id = "Status",
							text = status,
							textSize = 12,
							role = "secondary",
							lineLimit = 2,
							disclose = true,
						}),
					},
				}),
				-- the pane whose solved height IS the list's window (see the
				-- `viewportExtent` block above). `fill` is what makes it the screen's
				-- decision rather than the list's
				UI.VStack({
					id = "ListPane",
					width = { type = "fill", weight = 1 },
					-- weight 2 against the chrome's 1: on a short canvas the list still
					-- gets the larger share of what there is, and where the chrome hugs
					-- this is the only fill and takes everything left, as before
					height = { type = "fill", weight = 2 },
					children = { list.blueprint },
				}),
			},
		})

		local unbind: any = nil
		return {
			screen = screen,
			present = {
				-- `onGeometry` is a broadcast the presenter makes after every solve
				-- (presenter.luau: "solved rects are a notification"), so reading one
				-- rect here costs the rest of the screen nothing
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
			-- published for the headless suite: the signals a test drives, rather
			-- than a re-implementation of them
			mode = mode,
			uniformOn = uniformOn,
			textOffset = textOffset,
			list = list,

			steps = {
				bind = function(built: any)
					unbind = list.bindNativeScroll(built.handle.controller)
					return list.scrollPath and list.scrollPath() or "bound"
				end,
				setMode = function(_built: any, payload: string?)
					uniformOn:set(payload == "uniform")
					return { mode = mode:get(), canvas = list.dump().contentExtent }
				end,
				setTextSize = function(_built: any, payload: string?)
					textOffset:set(tonumber(payload or "0") or 0)
					return { offset = textOffset:get(), canvas = list.dump().contentExtent }
				end,
				focusPost200 = function()
					return list.focusKey("p200")
				end,
				-- the anchoring proof, as one drive: park mid-feed, grow the text,
				-- report where the list ended up
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
					mode = mode:get(),
					textOffset = textOffset:get(),
					mounted = mounted,
					firstKeys = { keys[1], keys[2], keys[3] },
					itemExtentMode = d.itemExtentMode,
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
