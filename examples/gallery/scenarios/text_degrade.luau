--!strict
--[[ Scenario 'text_degrade' — WHAT A LABEL GIVES UP FIRST, AND IN WHAT ORDER.

	Director rulings 1 and 5, 2026-08-13 (docs/handoff/2026-08-13-rulings-needed.md
	§1 and §5). The standing obligation is that every gap ships its showcase demo,
	and this is that demo for both — because they are one mechanism seen twice.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR:

	  · THE ORDER IS THE WHOLE ARGUMENT. Any single frame of this surface looks
	    like an ordinary row of labels. The feature is the SEQUENCE the row walks
	    as its box narrows — reflow, then the compact form, then an ellipsis, then
	    a crop — and the only way to show a sequence is to let a player drive it.
	    The width picker is that driver, and each stop is one rung.
	  · ITS SIBLINGS NEVER LOSE A CHARACTER UNTIL THE LAST STOP, and that is the
	    point of the compact rung. "Sorting" declares a compact form and its
	    two neighbours do not, so at Snug it alone gives way — measured here as
	    `Srt` with both neighbours uncut, and pinned in general by "the compact rung
	    SPARES A SIBLING" (tests/text_degrade_cascade.spec.luau). It is one word, so
	    it has no reflow to offer first; its neighbour "Best fit" does, and takes
	    that rung at Tight.
	  · THE LOWER PANEL IS RULING 5 ON ITS OWN. One phrase in a narrowing column:
	    while its LONGEST WORD fits, it wraps and the box grows; past that it takes
	    one line and an ellipsis, because wrapping into a column narrower than one
	    of its own words does not add lines of that word — the engine BREAKS the
	    word, and the solver's own wrap model (whitespace only) would have reserved
	    a box for a shape the engine will not draw.
	  · CLIP IS THE LAST RUNG, and the row is built to reach it: "Newest" declares
	    an authored `minMax` minimum of exactly the 60px it needs, which is a
	    CONTRACT the cascade may not descend below. So at Impossible there is a
	    genuine residual deficit no rung can absorb — the two other labels are
	    already at an ellipsis — and the crop is the floor guarantee doing its job
	    rather than a nicety. That is a state that files a solver finding,
	    deliberately, exactly as `flow_wrap`'s "wrapping off" state does: the
	    diagnostic is part of the demonstration.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT: the four width stops are
	fixed against the PLATE, not against a screen, and the widest is `fill`.

	BUT THE PLATE IS NOT THE SCREEN, and the 2026-08-14 theme sweep is what made
	that concrete — an earlier version of this comment claimed "every stop fits
	every device", which was reasoned from the stop widths alone and is false. On a
	320px phone at the largest text preference under Fantasy Ornate, two nested
	padded panels and the scroll reserve take 166px and the plate is 154px wide,
	while the row's own floor is 181px: the Button is at its COMPACT form and still
	83px of themed chrome, "Best fit" is at its 30px floor, "Newest" holds its
	authored 60px minimum. So the last rung fires at the FIRST stop there, and the
	surface reaches its own punchline before the player touches the picker. It is
	recorded with that measurement in `tests/lib/theme_sweep_ledger.luau` (kind
	`cascade-floor`) rather than tuned away, because every repair available — a
	wrap on the row, a smaller authored floor, thinner panel padding chosen against
	that one cell — deletes the thing this fixture exists to show.

	TWO HOSTS MOUNT THIS FILE, AND ONLY ONE OF THEM RUNS STEPS (the pair
	`flow_wrap.luau` and `card_rail.luau` document): the scenario runner drives
	`steps` by name, and the showcase demo picker mounts it with a minimal ctx and
	NO step ever runs. Everything a player can do here is an ordinary control with
	a `selected` of its own, never a scripted drive.
]]

-- The four stops, widest first. These are the rungs made into a control, and they
-- are MEASURED rather than guessed — "Sorting" is one word at the
-- body size (so it has no reflow to give), "Best fit" wraps and "Newest" is 60, so:
--
--   fill  everything at its natural width                nothing given up
--   200   the row starts giving way                      rungs 1 and 2
--   165   ...and gives way further, still uncut
--   110   both reflowable labels reach an ellipsis, and the authored 60px
--         minimum leaves a deficit no rung can absorb  rung 3, then the CLIP
--
-- The ORDER is what the tests assert, never these numbers: the showcase chrome
-- and the active theme both change how much room this row really has, and a
-- literal re-tuned until it passes is a check that has stopped meaning anything.
--
-- They are deliberately coarse: a slider would let a player land between rungs
-- and see nothing change, which is the opposite of what this surface is for.
-- `width = nil` on the first stop means FILL: "roomy" is whatever room this screen
-- actually has, never a literal wider than the narrowest supported viewport (that
-- literal is `docs/lessons/luauui-fixed-px-heights` in its width spelling — a fixed
-- box against an unfixed screen, which overflows the moment the chrome is real).
local STOPS: { { value: string, width: number? } } = {
	{ value = "roomy", width = nil },
	{ value = "snug", width = 200 },
	{ value = "tight", width = 165 },
	{ value = "impossible", width = 110 },
}

-- The lower panel's column. It narrows with the same picker, because the wrap
-- rule and the cascade are driven by the same fact — how much room there is.
local WRAP_COLUMN: { [string]: number } = {
	roomy = 240,
	snug = 170,
	tight = 110,
	impossible = 70,
}

--[[ EVERY PLAYER-VISIBLE STRING, in one table, EXPORTED as the module's `copy`
	field — the same contract `flow_wrap.luau` and `card_rail.luau` carry, and for
	the same reason: the localization case in `tests/examples_gallery.spec.luau`
	re-runs the whole fixture with all of them put through a ~1.4x pseudo-localizing
	expansion, and a check that cannot reach the strings cannot make that claim.

	THE THREE ROW LABELS ARE IN HERE TOO, and that is the point rather than an
	oversight: a pseudo-localized label is a WIDER label, which is exactly the case
	the cascade exists for. Expanded, the row reaches its lower rungs sooner — and
	still nothing leaves the plate, which is what makes the studio's standing 1.4x
	rule safe on a surface that cannot grow.
]]
-- NOT IN `COPY`, and that is a rule rather than an oversight: a compact form is
-- ONE WORD by construction (`assertCompactLabel` refuses whitespace, because a
-- phrase has a legal break and the button would wrap into exactly the second line
-- the compact form exists to avoid). The pseudo-localizer appends a padding run to
-- every value it is handed, so a compact form inside `copy` would be refused at
-- construction the moment the localization case ran.
local SORT_COMPACT = "Srt"

local COPY = {
	title = "What a label gives up first",
	lead = "Narrow the row. It says it shorter and reflows before anything is cut, and cropping is the last thing it does.",
	widthLabel = "Room",
	roomy = "Roomy",
	snug = "Snug",
	tight = "Tight",
	impossible = "Impossible",
	rowHeading = "Three labels, one row",
	-- declares a compact form; it is the one that gives way at the Tight stop
	sortLabel = "Sorting",
	-- no compact form: it keeps every character until the last stop
	rankLabel = "Best fit",
	-- 60px is exactly what this word needs, declared as a `minMax` minimum: the
	-- contract the cascade may not descend below, which is what leaves the last
	-- stop a residual deficit for the clip rung to answer
	dateLabel = "Newest",
	wrapHeading = "One phrase, one narrowing column",
	wrapBody = "Wrapping is right only while the longest word fits",
	footnote = "Clip is the floor, never the first move.",
}

return {
	title = "Text degrade cascade (rulings 1 and 5)",
	ledgerRows = { "R-1", "R-5" },
	copy = COPY,
	stops = STOPS,
	sortCompact = SORT_COMPACT,
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core
		local scope = core:scope("text-degrade")

		local stop = scope:own(core:signal("roomy"))
		local rowWidth = scope:own(core:memo(function(use)
			local chosen = use(stop)
			for _, entry in STOPS do
				if entry.value == chosen then
					return if entry.width == nil then { type = "fill" } else { type = "fixed", px = entry.width }
				end
			end
			return { type = "fill" }
		end))
		local columnWidth = scope:own(core:memo(function(use)
			return { type = "fixed", px = WRAP_COLUMN[use(stop)] or WRAP_COLUMN.roomy }
		end))

		local widthPicker = LuauUI.newPicker(LuauUI, core, {
			id = "Room",
			label = COPY.widthLabel,
			-- SEGMENTED, declared: four peers named for how much room there is,
			-- never for the rung — a player is choosing a box, and the row's answer
			-- to it is the thing being shown
			presentation = "segmented",
			options = {
				{ value = "roomy", label = COPY.roomy },
				{ value = "snug", label = COPY.snug },
				{ value = "tight", label = COPY.tight },
				{ value = "impossible", label = COPY.impossible },
			},
			selected = stop,
		})

		-- THE PAGE SCROLLS, because this surface is a stack of panels and a 320x640
		-- phone under the showcase's own chrome does not have room for all of them —
		-- measured, at 4px over, which is exactly the kind of margin a fixed page
		-- loses on the next theme. "Wrap it in a ScrollView, or give it room" is the
		-- solver's own advice when a column runs long, and it is what a real screen
		-- does; example 03 is built the same way.
		local screen = UI.Screen({
			id = "TextDegrade",
			padding = "m",
			children = {
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "m",
					width = { type = "fill" },
					height = { type = "fill" },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "title", disclose = true }),
						UI.Text({ id = "Lead", text = COPY.lead, textSize = "caption", role = "secondary" }),
						widthPicker.blueprint,

						UI.VStack({
							id = "RowPanel",
							surface = "raised",
							padding = "m",
							gap = "s",
							children = {
								UI.Text({
									id = "RowHeading",
									text = COPY.rowHeading,
									textSize = "caption",
									role = "secondary",
								}),
								-- THE ROW ITSELF. `clipChildren` is NOT declared: the crop at the
								-- last stop is the solver's, on the rects, which is what every
								-- headless sweep in this repo can actually read. Declaring an
								-- engine clip host here would hide the same geometry from them.
								UI.HStack({
									id = "Row",
									width = rowWidth,
									gap = "xs",
									children = {
										-- A BUTTON, because `compactLabel` is a Button prop: a compact
										-- representation is what a CONTROL has. The cascade's compact
										-- rung reads exactly that declaration, so the public surface
										-- for rung 2 is a control with something shorter to say.
										UI.Button({
											id = "Sort",
											label = COPY.sortLabel,
											compactLabel = SORT_COMPACT,
											shrinkWeight = 1,
										}),
										UI.Text({ id = "Rank", text = COPY.rankLabel, shrinkWeight = 1 }),
										-- the authored floor: a contract the cascade may not
										-- descend below, which is what leaves a residual deficit
										-- for the clip rung to answer at the last stop
										UI.Text({
											id = "Date",
											text = COPY.dateLabel,
											width = { type = "minMax", min = 60, preferred = 60 },
											shrinkWeight = 1,
										}),
									},
								}),
							},
						}),

						UI.VStack({
							id = "WrapPanel",
							surface = "raised",
							padding = "m",
							gap = "s",
							children = {
								UI.Text({
									id = "WrapHeading",
									text = COPY.wrapHeading,
									textSize = "caption",
									role = "secondary",
								}),
								UI.Text({ id = "WrapBody", text = COPY.wrapBody, width = columnWidth, disclose = true }),
							},
						}),

						UI.Text({ id = "Footnote", text = COPY.footnote, textSize = "caption", role = "secondary" }),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the signal a test drives, rather
			-- than a re-implementation of it
			stop = stop,

			steps = {
				-- the picker, as the player's own press fires it
				setStop = function(_built: any, payload: string?)
					local value = payload
					local known = false
					for _, entry in STOPS do
						if entry.value == value then
							known = true
						end
					end
					stop:set(if known then value else "roomy")
					return { stop = stop:get() }
				end,
			},

			report = function()
				return { stop = stop:get(), stops = #STOPS }
			end,

			dispose = function()
				widthPicker.dispose()
				scope:dispose()
			end,
		}
	end,
}
