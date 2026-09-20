--!strict
--[[ Scenario 'sorted_entries' — THE SAME TWELVE SCORES, BUILT THREE WAYS
	(docs/reference/api.md §sortedEntries).

	`UI.ForEach` takes an array, so a dictionary has to be flattened first — and
	the obvious flatten is wrong. Luau's `pairs` order is a function of the table's
	hash layout, and the hash layout is a function of its CONSTRUCTION HISTORY. The
	twelve players below always have the same twelve scores; the only thing the
	picker changes is the ORDER THEY WERE PUT INTO THE MAP, which is a thing no
	player of a real game would ever know had happened.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR.
	One frame of a leaderboard is just a leaderboard. The defect is a DIFFERENCE
	BETWEEN TWO FRAMES that nothing in the game caused:

	  · the LEFT column is `for k, v in scores` — the three-line flatten every
	    consumer writes. Move the picker and it deals itself a new order.
	  · the RIGHT column is `UI.sortedEntries(scores)`. Same twelve rows, same
	    order, every time.

	Both columns are built from the SAME table object on the same frame, so
	nothing but the flatten differs between them.

	THE THIRD CONSTRUCTION IS CHURN, not a third insertion order, and it is here
	because it is the one that survives being small. Measured 2026-08-15: at twelve
	keys all three constructions disagree, but at SIX keys the two insertion orders
	produce byte-identical `pairs` orders and only churn moves — which is why
	`tests/sorted_entries.spec.luau` is built at twelve and says so, and why this
	fixture carries twelve rows rather than a comfortable six.

	THE STATUS LINE IS A MEASUREMENT, NOT A CLAIM. It compares the raw column's
	current order with the one before it and reports whether it moved. On the first
	selection there is nothing to compare against and it says so, rather than
	asserting stability it has not observed.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT: neither column declares a
	height, the page scrolls, and the two columns share the width by weight so the
	pair still reads at 320px.

	TWO HOSTS MOUNT THIS FILE and only one of them runs steps (the pair
	`lifecycle_hidden.luau` documents): the scenario runner drives `steps` by name,
	and the showcase demo picker mounts it with a minimal ctx and no step ever
	runs. The picker is an ordinary control with its own `selected` signal.
]]

-- TWELVE, and the number is load-bearing rather than tidy — see the header. At
-- six the insertion orders agree and the fixture would demonstrate nothing.
local PLAYER_COUNT = 12

-- the id and score for player i. Ids are the shape a real key has (a stable
-- string), and the scores are a fixed function of i so no run differs from
-- another for a reason that is not the construction order.
local function playerId(i: number): string
	return string.format("player_%d", 1000 + i * 7)
end
local function playerScore(i: number): number
	return (13 - i) * 25
end

local ASCENDING: { number } = {}
local DESCENDING: { number } = {}
for i = 1, PLAYER_COUNT do
	table.insert(ASCENDING, i)
	table.insert(DESCENDING, PLAYER_COUNT + 1 - i)
end

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED as `copy` — the same
	contract `lifecycle_hidden.luau` and `flow_wrap.luau` carry, because the
	localization case in `tests/examples_gallery.spec.luau` re-runs the whole
	fixture through a ~1.4x pseudo-localizing expansion and a check that cannot
	reach the strings cannot make that claim. Flat keys only.

	The player ids are NOT in here: they are keys, not copy. A pseudo-localized
	key would change the sort input and make the fixture demonstrate the wrong
	thing. ]]
local COPY = {
	title = "The same twelve scores, built three ways",
	intro = "Every option below builds the identical twelve pairs. Only the order they were inserted changes.",
	pick = "How the map was built",
	ascending = "In order",
	descending = "Reversed",
	churn = "With churn",
	rawTitle = "for k, v in scores",
	sortedTitle = "UI.sortedEntries(scores)",
	rawNote = "Deals itself a new order.",
	sortedNote = "Same order, every time.",
	statusTitle = "What changed between the last two builds",
	firstBuild = "First build — nothing to compare it with yet.",
	rawMoved = "The raw column re-ordered itself. The sorted column did not move.",
	rawHeld = "The raw column happened to hold this time. It is not promised to.",
	note = "Nothing about the players changed. Only the order they were put into the table did.",
}

return {
	title = "Deterministic dictionary iteration",
	ledgerRows = {},
	copy = COPY,
	playerCount = PLAYER_COUNT,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI, Compose = ctx.UI, ctx.Compose

		-- THE THREE CONSTRUCTIONS. Same twelve pairs out of all three; only the
		-- history that produced the table differs.
		local function build(kind: string): { [string]: number }
			local map: { [string]: number } = {}
			if kind == "churn" then
				-- inserted alongside twelve keys that are then removed: the deletions
				-- leave the hash layout somewhere neither insertion order reaches
				for i = 1, PLAYER_COUNT do
					map[playerId(i)] = playerScore(i)
					map[`ghost_{i}`] = -1
				end
				for i = 1, PLAYER_COUNT do
					map[`ghost_{i}`] = nil
				end
			else
				for _, i in (if kind == "descending" then DESCENDING else ASCENDING) do
					map[playerId(i)] = playerScore(i)
				end
			end
			return map
		end

		local kind = Compose.cell("ascending")
		local scores = Compose.cell(build("ascending"))
		local status = Compose.cell(COPY.firstBuild)
		local lastRawOrder: string? = nil

		-- THE RAW FLATTEN, verbatim: the three lines the gap note says every
		-- consumer writes, kept exactly as a consumer would write them so the
		-- fixture is showing the real thing rather than a caricature of it.
		local rawEntries = Compose.formula(function(use)
			local out: { { key: string, value: number } } = {}
			for key, value in use(scores) do
				table.insert(out, { key = key, value = value })
			end
			return out
		end)

		local sortedEntries = Compose.formula(function(use)
			return UI.sortedEntries(use(scores))
		end)

		local function orderOf(entries: { { key: string, value: number } }): string
			local names: { string } = {}
			for _, e in entries do
				table.insert(names, e.key)
			end
			return table.concat(names, ",")
		end

		-- MEASURED, not asserted: compare this build's raw order with the previous
		-- one and report what actually happened.
		local function select(next: string)
			kind:set(next)
			scores:set(build(next))
			local order = orderOf(rawEntries:peek())
			if lastRawOrder == nil then
				status:set(COPY.firstBuild)
			elseif order ~= lastRawOrder then
				status:set(COPY.rawMoved)
			else
				status:set(COPY.rawHeld)
			end
			lastRawOrder = order
		end
		lastRawOrder = orderOf(rawEntries:peek())

		--[[ THE DISABLE IS GONE (ADAPT-1 call-site review, 2026-08-18). This
			declared `presentation = "segmented"` with no reason beside it, which is
			the shape the audit found ten times: a site that opted out of a ladder
			that could not work anyway, because no fact ever reached it. Three short
			labels still resolve segmented wherever there is room; on a compact
			screen they now become the row list, which is what the ladder is for. ]]
		local function picker()
			return UI.Picker("Construction")({
				label = COPY.pick,
				options = {
					{ value = "ascending", label = COPY.ascending },
					{ value = "descending", label = COPY.descending },
					{ value = "churn", label = COPY.churn },
				},
				selected = kind,
				onChange = select,
			})
		end

		-- ONE column builder for both, so the ONLY difference on screen is which
		-- entry list it is handed
		local function column(id: string, title: string, note: string, items: any): any
			return UI.VStack(id)({
				surface = "control",
				padding = "s",
				gap = "xs",
				width = UI.fill(),

				UI.Text("Title")({ text = title, textSize = "caption" }),
				UI.Text("Note")({ text = note, textSize = "caption", role = "secondary" }),
				UI.VStack("Rows")({
					gap = 2,
					width = UI.fill(),

					UI.ForEach("List")({
						Compose.keyed({
							from = items,
							key = function(entry: any): string
								return entry.key
							end,
							render = function(entry: any): any
								return UI.Text("Row-" .. entry:peek().key)({
									text = function(use)
										local current = use(entry)
										return `{current.key}  {current.value}`
									end,
									textSize = "caption",
								})
							end,
						}),
					}),
				}),
			})
		end

		local function screen()
			-- stacked without room, side by side with it
			local conditions = Facet.adaptive.conditions(ctx.env)
			return UI.Screen("SortedEntries")({
				padding = 12,
				gap = "s",

				-- THE PAGE SCROLLS, for the reason every other fixture here does:
				-- twelve rows in each of two columns plus a picker and a status line do
				-- not fit the ~200px a 640x320 landscape phone has left once the
				-- showcase reserves its chip strip.
				UI.ScrollView("Page")({
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),

					UI.Text("Title")({ text = COPY.title, textSize = "control" }),
					UI.Text("Intro")({ text = COPY.intro, textSize = "caption", role = "secondary" }),
					picker(),
					-- SIDE BY SIDE WITH ROOM, STACKED WITHOUT, and the axis is bound
					-- rather than branched: an `AdaptiveStack` re-solves in place, so
					-- flipping a 320px phone does not remount twenty-four rows and
					-- lose the comparison the fixture exists for. (`wrap` was the
					-- first draft and the solver refused it, correctly: a wrapping
					-- stack has no single leftover to share, so a `fill` child on the
					-- main axis takes a whole line and the columns were never beside
					-- each other at any width.)
					UI.AdaptiveStack("Columns")({
						axis = conditions.axis,
						gap = "s",
						width = UI.fill(),

						column("Raw", COPY.rawTitle, COPY.rawNote, rawEntries),
						column("Sorted", COPY.sortedTitle, COPY.sortedNote, sortedEntries),
					}),
					UI.Text("StatusTitle")({ text = COPY.statusTitle, textSize = "caption" }),
					UI.Text("Status")({ text = status, textSize = "caption", role = "secondary" }),
					UI.Text("Note")({ text = COPY.note, textSize = "caption", role = "secondary" }),
				}),
			})
		end

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the signals and the two live entry
			-- lists a test reads, rather than a re-implementation of them
			kind = kind,
			scores = scores,
			status = status,
			rawEntries = rawEntries,
			sortedEntries = sortedEntries,
			rawOrder = function()
				return orderOf(rawEntries:peek())
			end,
			sortedOrder = function()
				return orderOf(sortedEntries:peek())
			end,

			steps = {
				-- the picker, as the player's own press fires it
				setConstruction = function(_built: any, payload: string?)
					local next = if payload == "descending" or payload == "churn" then payload else "ascending"
					select(next)
					return { kind = next, raw = orderOf(rawEntries:peek()), sorted = orderOf(sortedEntries:peek()) }
				end,
			},

			report = function()
				return {
					kind = kind:peek(),
					raw = orderOf(rawEntries:peek()),
					sorted = orderOf(sortedEntries:peek()),
					status = status:peek(),
				}
			end,

			-- nothing outlives the screen
			dispose = function() end,
		}
	end,
}
