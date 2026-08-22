--!strict
--[[ Scenario 'lifecycle_hidden' — THE SLOT THAT STAYS, and the events nobody can see.

	`hidden`, `onAppear` and `onDisappear` shipped in parity round 3 item
	D (the completeness audit's #16 and #12). The standing obligation is that
	every new public API appears in a gallery scenario the headless suite
	executes, and this is that scenario.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR:

	  · TWO PANELS, ONE SWITCH. The same badge is declared twice — once with
	    `hidden`, once behind a `UI.When` — and one toggle drives both. Flip it
	    and the SECOND panel's caption jumps up while the FIRST panel's does not
	    move a pixel. That difference IS the capability; a screenshot of either
	    panel alone shows an ordinary card with a chip on it. The kept slot is
	    the TOP panel on purpose — see the comment at its declaration.
	  · THE EVENT LOG IS THE ONLY EVIDENCE A LIFETIME HOOK EXISTS. `onAppear`
	    and `onDisappear` produce no pixels of their own, so the fixture gives
	    them some: the badge in the `UI.When` panel writes a line every time it
	    arrives and every time it leaves, and the counters beside it never reset.
	    Watching the count climb while the kept slot silently ghosts in and out is
	    also the clearest statement of what `hidden` is NOT — it is a paint and
	    interaction state, not a mount, and it fires nothing.
	  · A HOOK THAT WRITES STATE PAINTS ON THE NEXT FRAME. The log signal is set
	    from inside the hooks, which run at the end of the render pass that
	    mounted the node — so the new dirt lands in the following frame's queue.
	    That is the honest, documented behaviour, and it is why the headless
	    drive below refreshes twice rather than once.

	THE LOG IS BOUNDED TO `LOG_LINES` ON PURPOSE. An unbounded event log is a
	`Text` that grows without limit, which is the fixed-px-height defect wearing
	a different hat: it would push the page taller on every toggle until it
	overflowed whatever box it was in. Four lines is a fixture, not a console.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT: no panel declares a height,
	both are exactly as tall as their content at every viewport and in every
	shipped package, and the page scrolls.

	TWO HOSTS MOUNT THIS FILE, AND ONLY ONE OF THEM RUNS STEPS (the same pair
	`card_rail.luau` and `flow_wrap.luau` document): the scenario runner drives
	`steps` by name, and the showcase demo picker mounts it with a minimal ctx and
	no step ever runs. The toggle is an ordinary control with its own value
	signal, never a scripted drive.
]]

-- how many event lines the log keeps. See the header: an unbounded log is a Text
-- that grows on every toggle, which is a layout defect with extra steps.
local LOG_LINES = 4

--[[ EVERY PLAYER-VISIBLE STRING ON THIS SURFACE, in one table, EXPORTED as the
	module's `copy` field — the same contract `flow_wrap.luau` carries, and for
	the same reason: the localization case in `tests/examples_gallery.spec.luau`
	re-runs the whole fixture with all of them put through a ~1.4x pseudo-
	localizing expansion, and a check that cannot reach the strings cannot make
	that claim. Flat keys only: the pseudo-localizer walks values and would throw
	on a nested table. ]]
local COPY = {
	title = "hidden, onAppear, onDisappear",
	intro = "One switch drives both badges. Watch the caption under each one: the top never moves.",
	toggleLabel = "Show the badge",
	removedTitle = "UI.When — the node is removed",
	removedNote = "This line moves up when the badge goes.",
	reservedTitle = "hidden — the slot is kept",
	reservedNote = "This line never moves.",
	badge = "New",
	logTitle = "Lifetime events, from the UI.When panel",
	logEmpty = "Nothing yet — flip the switch.",
	appeared = "appeared",
	disappeared = "disappeared",
	countsPrefix = "Appearances",
	countsMiddle = "Disappearances",
	hiddenFiresNothing = "The kept slot fires nothing: hiding is a paint state, not a mount.",
}

return {
	title = "Lifecycle hooks and hidden",
	ledgerRows = {},
	copy = COPY,
	logLines = LOG_LINES,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("lifecycle-hidden")

		local showing = scope:own(core:signal(true))
		-- `hidden` is the INVERSE of the switch, and it is a memo rather than a
		-- second signal so the two panels can never disagree about what the player
		-- asked for
		local isHidden = scope:own(core:memo(function(use)
			return not use(showing)
		end))

		local logText = scope:own(core:signal(COPY.logEmpty))
		local appearCount = scope:own(core:signal(0))
		local disappearCount = scope:own(core:signal(0))
		local lines: { string } = {}

		local function note(event: string)
			table.insert(lines, event)
			while #lines > LOG_LINES do
				table.remove(lines, 1)
			end
			logText:set(table.concat(lines, "\n"))
		end

		local counts = scope:own(core:memo(function(use)
			return `{COPY.countsPrefix}: {use(appearCount)}   {COPY.countsMiddle}: {use(disappearCount)}`
		end))

		local function badge(id: string, extra: { [string]: any }): any
			local props: any = { id = id, label = COPY.badge, surface = "chip" }
			for key, value in extra do
				props[key] = value
			end
			return UI.Button(props)
		end

		local screen = UI.Screen({
			id = "LifecycleHidden",
			padding = 12,
			gap = "s",
			children = {
				-- THE PAGE SCROLLS, for the reason every other fixture here does: a
				-- title, a switch, two panels and a log do not fit the ~200px a
				-- 640x320 landscape phone has left once the showcase reserves its chip
				-- strip, and content that overflows with nothing to scroll it is this
				-- repo's named recurring defect.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						UI.Text({ id = "Intro", text = COPY.intro, textSize = "caption", role = "secondary" }),
						UI.Toggle({ id = "ShowToggle", label = COPY.toggleLabel, value = showing }),
						-- PANEL ONE, AND THE ORDER IS THE DEMO. The kept slot goes FIRST so
						-- that "this line never moves" is literally true on screen: a panel
						-- whose height changes must sit BELOW everything claiming to be
						-- still, or the still one is pushed around by its neighbour and the
						-- comparison reads as noise. (Measured, not reasoned: with the
						-- panels the other way round the kept caption moved 52 px.)
						UI.VStack({
							id = "Reserved",
							surface = "control",
							padding = "s",
							gap = 6,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "ReservedTitle", text = COPY.reservedTitle, textSize = "caption" }),
								badge("Ghost", { hidden = isHidden }),
								UI.Text({
									id = "ReservedNote",
									text = COPY.reservedNote,
									textSize = "caption",
									role = "secondary",
								}),
							},
						}),
						-- PANEL TWO, AND IT IS SECOND ON PURPOSE (see above): the node
						-- really leaves here, so this panel's own height changes — and
						-- because it sits BELOW the kept slot, nothing above it moves.
						UI.VStack({
							id = "Removed",
							surface = "control",
							padding = "s",
							gap = 6,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "RemovedTitle", text = COPY.removedTitle, textSize = "caption" }),
								UI.When({
									id = "Gate",
									condition = showing,
									thenView = function()
										return badge("Badge", {
											onAppear = function()
												appearCount:set(appearCount:get() + 1)
												note(COPY.appeared)
											end,
											onDisappear = function()
												disappearCount:set(disappearCount:get() + 1)
												note(COPY.disappeared)
											end,
										})
									end,
								}),
								UI.Text({
									id = "RemovedNote",
									text = COPY.removedNote,
									textSize = "caption",
									role = "secondary",
								}),
							},
						}),
						UI.Text({ id = "LogTitle", text = COPY.logTitle, textSize = "caption" }),
						UI.Text({ id = "Log", text = logText, textSize = "caption", role = "secondary" }),
						UI.Text({ id = "Counts", text = counts, textSize = "caption", role = "secondary" }),
						UI.Text({
							id = "NoFire",
							text = COPY.hiddenFiresNothing,
							textSize = "caption",
							role = "secondary",
						}),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the signals a test drives and reads,
			-- rather than a re-implementation of them
			showing = showing,
			appearCount = appearCount,
			disappearCount = disappearCount,
			logText = logText,

			steps = {
				-- the switch, as the player's own press fires it
				setShowing = function(_built: any, payload: string?)
					showing:set(payload ~= "off")
					return { showing = showing:get() }
				end,
			},

			report = function()
				return {
					showing = showing:get(),
					appeared = appearCount:get(),
					disappeared = disappearCount:get(),
					log = logText:get(),
				}
			end,

			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
