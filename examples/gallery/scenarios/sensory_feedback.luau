--!strict
--[[ Scenario 'sensory_feedback' — WHAT DOES PRESSING THIS FEEL LIKE?

	The per-control sensory hook shipped in SwiftUI-parity round 3 from a direct
	director request: *"should we have sensory feedback per control so that when
	you press a button, for example, you get haptic feedback?"* Every gap closure
	ships its showcase fixture, and this is that fixture.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this surface is FOR:

	  · FIVE BUTTONS THAT LOOK IDENTICAL AND FEEL DIFFERENT. `Buy` is a `commit`,
	    `Delete` is a `reject`, `Pick` is a `select`, `Mute` is `none` — declared
	    with `UI.sensoryFeedback(bp, { activation = … })` — and `Plain` declares
	    nothing. Nothing about their PAINT differs; the whole capability is the
	    difference in what each one says happened, which is why the log below is
	    not decoration but the demo itself.
	  · THE CASCADE. The second panel declares ONE verb, on the panel, and all
	    three buttons inside it inherit — including the two nested a level deeper.
	    That is the point of the mechanism: a Chip, a Stepper, a Table row and a
	    PopupButton each build their own inner Button, so a per-control PROP would
	    reach none of them without ten pieces of plumbing. Press any of the three
	    and watch the same verb appear under three different paths.
	  · `none` IS NOT `activate`. Pressing `Mute` writes NOTHING to the log — the
	    control still activates, it simply reports no sensation. An absence is
	    invisible until something says it was deliberate, so the log's counter
	    keeps climbing for every OTHER press while Mute's line never appears.

	AND WHAT THIS SURFACE DELIBERATELY DOES NOT DO: it does not play anything.
	`src/present/feedback.luau:4-5` — LuauUI says what happened and plays nothing.
	Playback is one opt-in, DEFAULT-OFF client adapter (`src/client/haptics.luau`)
	that the GAME constructs, and it is not wired here because a gallery fixture
	must stay engine-free. The sensation column below is that adapter's published
	map, shown so a reader can see what each verb would be felt as; the headless
	suite pins the column against `haptics.MAP` so it cannot drift into fiction.

	THE LOG IS BOUNDED TO `LOG_LINES` for the reason `lifecycle_hidden` bounds
	its own: an unbounded event log is a Text that grows on every press, which is
	the fixed-px-height defect wearing a different hat.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT: no panel declares a height,
	the button rows WRAP rather than running off the edge, and the page scrolls.

	TWO HOSTS MOUNT THIS FILE and only one of them runs steps (the pair
	`lifecycle_hidden.luau` documents): the scenario runner drives `steps` by name,
	and the showcase demo picker mounts it with a minimal ctx and no step ever
	runs. Every button here is an ordinary control pressed by an ordinary press.
]]

-- how many press lines the log keeps. See the header.
local LOG_LINES = 5

--[[ EVERY PLAYER-VISIBLE STRING, in one table, EXPORTED as `copy` — the contract
	`flow_wrap.luau` and `lifecycle_hidden.luau` carry, so the localization case in
	tests/examples_gallery.spec.luau can re-run the whole fixture through a ~1.4x
	pseudo-localizing expansion. Flat keys only: the pseudo-localizer walks values
	and would throw on a nested table. ]]
local COPY = {
	title = "Sensory feedback, per control",
	intro = "Five identical-looking buttons. Press them and watch what each one says happened.",
	declaredTitle = "Declared one by one",
	buy = "Buy",
	delete = "Delete",
	pick = "Pick",
	mute = "Mute",
	plain = "Plain",
	cascadeTitle = "Declared once, on the panel",
	cascadeNote = "One declaration on this panel. All three buttons inherit it — including the nested pair.",
	first = "First",
	second = "Second",
	third = "Third",
	logTitle = "What reached the feedback bus",
	logEmpty = "Nothing yet — press a button.",
	pressesPrefix = "Presses that reported something",
	muteNote = "Mute declares `none`: it activates, and reports nothing. Its line never appears.",
	sensationTitle = "What an opt-in haptics adapter would play",
	playsNothing = "LuauUI itself plays nothing. Playback is one opt-in, default-OFF client adapter.",
	silent = "(silent, on purpose)",
}

-- the five leaf declarations, in press order. `nil` is "declares nothing", which
-- is the default every control has always had.
local DECLARED: { { id: string, copyKey: string, activation: string? } } = {
	{ id = "Buy", copyKey = "buy", activation = "commit" },
	{ id = "Delete", copyKey = "delete", activation = "reject" },
	{ id = "Pick", copyKey = "pick", activation = "select" },
	{ id = "Mute", copyKey = "mute", activation = "none" },
	{ id = "Plain", copyKey = "plain", activation = nil },
}

-- the verbs this surface can produce, and what the shipped adapter maps each to.
-- WRITTEN OUT rather than derived, because a gallery fixture may not require a
-- client module — and pinned against `haptics.MAP` by the headless suite, which
-- is what keeps a written-out table honest.
local SENSATION: { { verb: string, effect: string? } } = {
	{ verb = "commit", effect = "UIClick" },
	{ verb = "reject", effect = "UINotification" },
	{ verb = "select", effect = "UIClick" },
	{ verb = "activate", effect = "UIClick" },
}

return {
	title = "Sensory feedback per control",
	ledgerRows = {},
	copy = COPY,
	logLines = LOG_LINES,
	declared = DECLARED,
	sensation = SENSATION,
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core
		local scope = core:scope("sensory-feedback")

		local logText = scope:own(core:signal(COPY.logEmpty))
		local reported = scope:own(core:signal(0))
		local lines: { string } = {}

		-- THE BUS IS THE DEMO. Subscribing here — at build, on the presenter the
		-- host handed us — is the same one line a game writes, and it is the only
		-- place this fixture learns anything: no control calls back into it.
		local presenter = ctx.presenter
		if presenter ~= nil and type(presenter.onFeedback) == "function" then
			scope:own(presenter.onFeedback(function(event: any)
				-- only this surface's own presses. `reason` is what the presenter
				-- stamps on a control activation, so a toast retiring somewhere else
				-- in the showcase cannot write a line here.
				if event.reason ~= "activation" then
					return
				end
				local path = tostring(event.path)
				if string.find(path, "/SensoryFeedback", 1, true) ~= 1 then
					return
				end
				-- the LAST path segment: the whole path is the truth but a phone's
				-- log column is 40 characters wide
				local leaf = string.match(path, "([^/]+)$") or path
				table.insert(lines, `{event.type}  ←  {leaf}`)
				while #lines > LOG_LINES do
					table.remove(lines, 1)
				end
				logText:set(table.concat(lines, "\n"))
				reported:set(reported:get() + 1)
			end))
		end

		local counts = scope:own(core:memo(function(use)
			return `{COPY.pressesPrefix}: {use(reported)}`
		end))

		-- one button, declared or not. The ONLY difference between these five is
		-- the modifier — same class, same surface, same label treatment.
		local function declaredButton(entry: { id: string, copyKey: string, activation: string? }): any
			local button = UI.Button({ id = entry.id, label = COPY[entry.copyKey], surface = "chip" })
			if entry.activation == nil then
				return button
			end
			return UI.sensoryFeedback(button, { activation = entry.activation })
		end

		local leafButtons: { any } = {}
		for _, entry in DECLARED do
			table.insert(leafButtons, declaredButton(entry))
		end

		local sensationRows: { any } = {}
		for i, row in SENSATION do
			table.insert(
				sensationRows,
				UI.Text({
					id = `Sensation{i}`,
					text = `{row.verb} → {row.effect or COPY.silent}`,
					textSize = 12,
					role = "secondary",
				})
			)
		end

		local screen = UI.Screen({
			id = "SensoryFeedback",
			padding = 12,
			gap = 8,
			children = {
				-- THE PAGE SCROLLS, for the reason every fixture here does: two
				-- panels, a log and a table do not fit the ~200px a 640x320 landscape
				-- phone has left once the showcase reserves its chip strip, and content
				-- that overflows with nothing to scroll it is this repo's named
				-- recurring defect.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = 18 }),
						UI.Text({ id = "Intro", text = COPY.intro, textSize = 12, role = "secondary" }),
						UI.VStack({
							id = "Leaves",
							surface = "control",
							padding = 8,
							gap = 6,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "LeavesTitle", text = COPY.declaredTitle, textSize = 12 }),
								-- WRAPS. Five chips at the Largest text preference, pseudo-
								-- localized, do not fit one line on a 320px phone, and a row
								-- that cannot wrap walks off the right edge of its own box.
								UI.HStack({ id = "LeafRow", wrap = true, gap = 6, children = leafButtons }),
								UI.Text({ id = "MuteNote", text = COPY.muteNote, textSize = 12, role = "secondary" }),
							},
						}),
						-- ONE DECLARATION, THREE CONTROLS, and the nesting is the point:
						-- `Third` sits a level deeper than the other two, so a mechanism
						-- that only reached direct children would be visibly wrong here.
						UI.sensoryFeedback(
							UI.VStack({
								id = "Cascade",
								surface = "control",
								padding = 8,
								gap = 6,
								width = { type = "fill", weight = 1 },
								children = {
									UI.Text({ id = "CascadeTitle", text = COPY.cascadeTitle, textSize = 12 }),
									UI.HStack({
										id = "CascadeRow",
										wrap = true,
										gap = 6,
										children = {
											UI.Button({ id = "First", label = COPY.first, surface = "chip" }),
											UI.VStack({
												id = "Nested",
												gap = 6,
												children = {
													UI.Button({ id = "Second", label = COPY.second, surface = "chip" }),
													UI.Button({ id = "Third", label = COPY.third, surface = "chip" }),
												},
											}),
										},
									}),
									UI.Text({
										id = "CascadeNote",
										text = COPY.cascadeNote,
										textSize = 12,
										role = "secondary",
									}),
								},
							}),
							{ activation = "pickup" }
						),
						UI.Text({ id = "LogTitle", text = COPY.logTitle, textSize = 12 }),
						UI.Text({ id = "Log", text = logText, textSize = 12, role = "secondary" }),
						UI.Text({ id = "Counts", text = counts, textSize = 12, role = "secondary" }),
						UI.VStack({
							id = "Sensations",
							surface = "control",
							padding = 8,
							gap = 6,
							width = { type = "fill", weight = 1 },
							children = (function(): { any }
								local kids: { any } = {
									UI.Text({ id = "SensationTitle", text = COPY.sensationTitle, textSize = 12 }),
								}
								for _, row in sensationRows do
									table.insert(kids, row)
								end
								table.insert(
									kids,
									UI.Text({
										id = "PlaysNothing",
										text = COPY.playsNothing,
										textSize = 12,
										role = "secondary",
									})
								)
								return kids
							end)(),
						}),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the signals a test reads, rather
			-- than a re-implementation of them
			logText = logText,
			reported = reported,

			steps = {
				-- the log, as the runner reads it after driving real presses through
				-- the adapter's activate path
				readLog = function()
					return { log = logText:get(), reported = reported:get() }
				end,
			},

			report = function()
				return { log = logText:get(), reported = reported:get() }
			end,

			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
