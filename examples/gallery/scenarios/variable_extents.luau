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

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT. The list's viewport extent
	is a live memo over the real screen (the same shape `virtual_list_native`
	documents), and every row extent is DERIVED from the same constants the cell
	paints with — `rowExtent` and `cell` read one table, so the declaration and the
	paint cannot drift. That discipline is what the feature buys; the toggle shows
	what its absence costs.

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
	`docs/lessons/luauui-fixed-px-heights.md` is the class this avoids: a px
	height fixed against unfixed content. ]]
local METRICS = {
	padding = 10,
	gap = 4,
	titleSize = 15,
	bodySize = 13,
	-- Roblox lays a text line out at its font size plus leading; 1.25 is the
	-- ratio this framework's own text calibration uses for a single line, and it
	-- is applied to the OFFSET size, not the base one
	lineRatio = 1.25,
}

-- the four measured accessibility offsets — the same set
-- `tests/large_text_matrix.spec.luau` and the overflow sweep walk
local TEXT_OFFSETS = { 0, 4, 10, 14 }

-- THE LIE THE TOGGLE TELLS: one declared number for every row, which is what
-- every list in this framework had to do before the per-item form. Chosen to be
-- right for a one-line post at +0 and wrong for everything else — the shape the
-- sweep found on `row_actions`.
local UNIFORM_EXTENT = 84

local function lineHeight(offset: number, size: number): number
	return math.ceil((size + offset) * METRICS.lineRatio)
end

-- how many body lines post `i` has: deterministic, 1..4, so the fixture is the
-- same list on every run and on every device
local function linesFor(index: number): number
	return (index - 1) % 4 + 1
end

--[[ ONE POST'S EXTENT — the function handed to `itemExtent`.

	IT READS EVERY LIVE FACT THROUGH `use`, which is the contract: reading the
	offset signal with `:get()` would produce the right number once and register no
	dependency, and the extents would then go stale the moment the player changed
	the text size. That silent-staleness is the failure mode the whole feature
	exists to end, so the fixture models the correct spelling. ]]
local function rowExtent(item: any, index: number, use: any, offsetSignal: any, modeSignal: any): number
	if use(modeSignal) == "uniform" then
		return UNIFORM_EXTENT
	end
	local offset = use(offsetSignal)
	local lines = linesFor(index)
	local _ = item
	return METRICS.padding * 2
		+ lineHeight(offset, METRICS.titleSize)
		+ METRICS.gap
		+ lines * lineHeight(offset, METRICS.bodySize)
end

return {
	title = "Variable item extents (ruling 7)",
	ledgerRows = { "R3-VIE" },
	build = function(ctx: any)
		local UI = ctx.LuauUI.UI
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

		-- the same live-viewport memo `virtual_list_native` documents: a fixed
		-- number here would paint past a 320px landscape phone with nothing to
		-- scroll it
		local viewportExtent = scope:own(core:memo(function(use)
			local vp: any = use(ctx.env:get("viewportRect"))
			local insets: any = use(ctx.env:get("coreSafeInsets"))
			local h = if type(vp) == "table" and type(vp.h) == "number" then vp.h else 640
			local top = if type(insets) == "table" and type(insets.top) == "number" then insets.top else 0
			local bottom = if type(insets) == "table" and type(insets.bottom) == "number" then insets.bottom else 0
			--[[ THE RESERVE IS MEASURED, NOT GUESSED, and the first guess was wrong in
				exactly the documented way (`docs/lessons/luauui-fixed-px-heights.md`):
				150 was reasoned from the title alone and the fixture then overflowed its
				own page by 80px at 320x640, because the toggle, the size chips and a
				two-line status sit above the list too.

				210 clears the worst measured case — 320 wide, where the control row
				WRAPS to two lines and the status takes two — and the gallery spec's
				zero-diagnostic case at three viewports is what keeps it honest.
				Over-reserving only shortens the list, which can never overflow;
				under-reserving squeezes the chrome, which is the defect above. ]]
			return math.clamp(math.floor(h - top - bottom - 210), 72, 600)
		end))

		local list = ctx.LuauUI.newVirtualList(ctx.LuauUI, core, {
			id = "Feed",
			rows = rows,
			key = function(item: any): string
				return item.id
			end,
			itemExtent = function(item: any, index: number, use: any): number
				return rowExtent(item, index, use, textOffset, mode)
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

		local screen = UI.Screen({
			id = "VariableExtents",
			padding = 8,
			gap = 6,
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
				-- that pushes the list out of its own page
				UI.Text({ id = "Status", text = status, textSize = 12, role = "secondary", lineLimit = 2 }),
				list.blueprint,
			},
		})

		local unbind: any = nil
		return {
			screen = screen,
			present = {},
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
