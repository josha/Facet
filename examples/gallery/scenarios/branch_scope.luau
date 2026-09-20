--!strict
--[[ Scenario 'branch_scope' — A PANEL THAT OWNS ITS OWN THINGS, and the one
	that does not.

	A `Compose.show` branch runs under its own owner, as a `Compose.keyed` row
	does. The owner opens with the panel and is released when the panel closes, so
	a panel's timer, motion value or async handle registered with
	`Compose.cleanup` lives on the panel's own lifetime.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR.
	A LEAK PAINTS NOTHING. The two panels below are the same panel written the two
	ways, side by side, and while they are open they are indistinguishable — same
	rows, same words, same pixels. The difference only exists in the counters,
	which is why the counters are the surface:

	  · OWNED BY THE BRANCH. The branch registers its three handles with
	    `Compose.cleanup`. Close the panel and the release count catches the open
	    count, every time.
	  · HOISTED. The same three handles registered on the SCREEN's owner. They are
	    released too — when the whole screen goes. Open and close it ten times and
	    ten panels' worth of handles are alive behind one panel's worth of pixels.

	THE COUNTERS ARE READ AFTER THE WRITE, NOT DURING IT. A cell write settles
	synchronously, so by the time `toggle()` returns from `showing:set(...)` the
	branch has already mounted or released and the counters have already moved.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT: no panel declares a height,
	the page scrolls, and the two panels are exactly as tall as their own rows at
	every width.

	TWO HOSTS MOUNT THIS FILE and only one of them runs steps (the pair
	`lifecycle_hidden.luau` documents): the scenario runner drives `steps` by name,
	and the showcase demo picker mounts it with a minimal ctx and no step ever
	runs. Both buttons are ordinary controls with their own `onActivate`, so a
	player drives the whole fixture with nothing scripted.
]]

-- How many handles a panel opens with. Three rather than one so the counters
-- move by a number nobody could mistake for an off-by-one, and it is what a real
-- panel looks like: a motion value, a subscription and an async handle.
local HANDLES_PER_OPEN = 3

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED as `copy` — the same
	contract `lifecycle_hidden.luau` and `flow_wrap.luau` carry, because the
	localization case in `tests/examples_gallery.spec.luau` re-runs the whole
	fixture through a ~1.4x pseudo-localizing expansion and a check that cannot
	reach the strings cannot make that claim. Flat keys only. ]]
local COPY = {
	title = "A panel that owns its own things",
	intro = "Both panels look identical while they are open. Open and close each one a few times and read the counters.",
	ownedTitle = "Owned by the branch — Compose.cleanup",
	ownedNote = "Released the moment the panel closes.",
	hoistedTitle = "Hoisted to the screen owner",
	hoistedNote = "Released when the whole screen goes. Not before.",
	ownedButton = "Toggle the owned panel",
	hoistedButton = "Toggle the hoisted panel",
	panelBody = "A motion value, a subscription and an async handle.",
	statsTitle = "What the framework counts",
	openedLabel = "Opened",
	releasedLabel = "Released",
	liveLabel = "Still held",
	balanced = "Balanced: nothing a closed panel opened is still held.",
	leaking = "Leaking: the hoisted panel is closed and still holding handles.",
}

return {
	title = "When branch scope",
	ledgerRows = {},
	copy = COPY,
	handlesPerOpen = HANDLES_PER_OPEN,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose

		local ownedShowing = Compose.cell(false)
		local hoistedShowing = Compose.cell(false)

		-- plain counters, because they are read after each write completes rather
		-- than subscribed to; the one cell below is what makes the readout live
		local stats = {
			ownedOpened = 0,
			ownedReleased = 0,
			hoistedOpened = 0,
			hoistedReleased = 0,
		}
		local readout = Compose.cell("")

		local function refresh()
			local ownedLive = stats.ownedOpened * HANDLES_PER_OPEN - stats.ownedReleased
			local hoistedLive = stats.hoistedOpened * HANDLES_PER_OPEN - stats.hoistedReleased
			local verdict = if hoistedLive > 0 and not hoistedShowing:peek() then COPY.leaking else COPY.balanced
			readout:set(
				`{COPY.ownedTitle}\n`
					.. `  {COPY.openedLabel}: {stats.ownedOpened}   {COPY.releasedLabel}: {stats.ownedReleased}   {COPY.liveLabel}: {ownedLive}\n`
					.. `{COPY.hoistedTitle}\n`
					.. `  {COPY.openedLabel}: {stats.hoistedOpened}   {COPY.releasedLabel}: {stats.hoistedReleased}   {COPY.liveLabel}: {hoistedLive}\n`
					.. verdict
			)
		end

		local function panelBody(id: string): any
			return UI.VStack(id)({
				gap = "tight",
				width = UI.fill(),

				UI.Text("Body")({ text = COPY.panelBody, textSize = "caption", role = "secondary" }),
			})
		end

		local function Example()
			-- the owner the hoisted panel registers on: it lives as long as the screen
			local screenOwner = Compose.currentOwner()
			return UI.Screen("BranchScope")({
				padding = 12,
				gap = "s",

				-- The page scrolls: a title, two panels, two buttons and a readout do
				-- not fit the ~200px a 640x320 landscape phone has left once the
				-- showcase reserves its chip strip.
				UI.ScrollView("Page")({
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),

					UI.Text("Title")({ text = COPY.title, textSize = "control" }),
					UI.Text("Intro")({ text = COPY.intro, textSize = "caption", role = "secondary" }),

					UI.VStack("Owned")({
						surface = "control",
						padding = "s",
						gap = "tight",
						width = UI.fill(),

						UI.Text("OwnedTitle")({ text = COPY.ownedTitle, textSize = "caption" }),
						UI.Button("OwnedButton")({
							label = COPY.ownedButton,
							onActivate = function()
								ownedShowing:set(not ownedShowing:peek())
								refresh()
							end,
						}),
						UI.When("OwnedGate")({
							-- THE WHOLE FIXTURE IS THIS BRANCH. Its owner arrives with
							-- the panel and is released with it, so the handles below
							-- need no cleanup path of their own and no reset.
							Compose.show(ownedShowing, function()
								stats.ownedOpened += 1
								for _ = 1, HANDLES_PER_OPEN do
									Compose.cleanup(function()
										stats.ownedReleased += 1
									end)
								end
								return panelBody("OwnedPanel")
							end),
						}),
						UI.Text("OwnedNote")({ text = COPY.ownedNote, textSize = "caption", role = "secondary" }),
					}),

					UI.VStack("Hoisted")({
						surface = "control",
						padding = "s",
						gap = "tight",
						width = UI.fill(),

						UI.Text("HoistedTitle")({ text = COPY.hoistedTitle, textSize = "caption" }),
						UI.Button("HoistedButton")({
							label = COPY.hoistedButton,
							onActivate = function()
								hoistedShowing:set(not hoistedShowing:peek())
								refresh()
							end,
						}),
						UI.When("HoistedGate")({
							-- ...and this one registers on the SCREEN's owner, which is
							-- still valid and is what state hoisted out of a branch does.
							Compose.show(hoistedShowing, function()
								stats.hoistedOpened += 1
								for _ = 1, HANDLES_PER_OPEN do
									screenOwner.own(function()
										stats.hoistedReleased += 1
									end)
								end
								return panelBody("HoistedPanel")
							end),
						}),
						UI.Text("HoistedNote")({ text = COPY.hoistedNote, textSize = "caption", role = "secondary" }),
					}),

					UI.Text("StatsTitle")({ text = COPY.statsTitle, textSize = "caption" }),
					UI.Text("Stats")({ text = readout, textSize = "caption", role = "secondary" }),
				}),
			})
		end

		refresh()

		return {
			screen = Example,
			present = {},
			-- published for the headless suite: the cells and the live counts a
			-- test drives and reads, rather than a re-implementation of them
			ownedShowing = ownedShowing,
			hoistedShowing = hoistedShowing,
			readout = readout,
			stats = function()
				return table.clone(stats)
			end,

			steps = {
				setOwned = function(_built: any, payload: string?)
					ownedShowing:set(payload ~= "off")
					refresh()
					return { showing = ownedShowing:peek(), opened = stats.ownedOpened, released = stats.ownedReleased }
				end,
				setHoisted = function(_built: any, payload: string?)
					hoistedShowing:set(payload ~= "off")
					refresh()
					return {
						showing = hoistedShowing:peek(),
						opened = stats.hoistedOpened,
						released = stats.hoistedReleased,
					}
				end,
			},

			report = function()
				return {
					ownedShowing = ownedShowing:peek(),
					hoistedShowing = hoistedShowing:peek(),
					ownedOpened = stats.ownedOpened,
					ownedReleased = stats.ownedReleased,
					hoistedOpened = stats.hoistedOpened,
					hoistedReleased = stats.hoistedReleased,
				}
			end,

			dispose = function() end,
		}
	end,
}
