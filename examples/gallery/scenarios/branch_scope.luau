--!strict
--[[ Scenario 'branch_scope' — A PANEL THAT OWNS ITS OWN THINGS, and the one
	that does not (react-lua-comparison.md §5 rank 2).

	`UI.When`'s `thenView` is handed the BRANCH's ownership scope, the twin of
	`UI.ForEach`'s `row(item, itemScope)`. The scope opens with the panel and is
	disposed when the panel closes, so a panel's timer, motion value or async
	handle can live on the panel's own lifetime.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR.
	A LEAK PAINTS NOTHING. The two panels below are the same panel written the two
	ways, side by side, and while they are open they are indistinguishable — same
	rows, same words, same pixels. The difference only exists in the counters,
	which is why the counters are the surface:

	  · OWNED BY THE BRANCH. `thenView(branchScope)` owns its three handles on the
	    scope it was handed. Close the panel and the release count catches the open
	    count, on the same frame, every time.
	  · HOISTED (the shape the framework forced before this shipped). The same
	    three handles owned on the ENCLOSING scope, because there was nowhere else
	    to put them. They are released too — when the whole screen goes. Open and
	    close it ten times and ten panels' worth of handles are alive behind one
	    panel's worth of pixels.

	AND THE LIVE SCOPE COUNT IS THE FRAMEWORK'S OWN, read straight off
	`core:counters().scopes` with no interpretation in between — the same
	instrument `tests/mount.spec.luau` asserts against, so the number on screen and
	the number in the suite cannot drift apart.

	THE COUNTERS ARE READ AFTER THE WRITE, NOT DURING IT. A write outside a
	transaction flushes synchronously, so by the time `toggle()` returns from
	`showing:set(...)` the branch has already mounted or disposed and the counters
	have already moved. Reading them in the same callback is therefore reading the
	settled state, not a frame of it.

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
	ownedTitle = "Owned by the branch — thenView(branchScope)",
	ownedNote = "Released the moment the panel closes.",
	hoistedTitle = "Hoisted to the screen — the old shape",
	hoistedNote = "Released when the whole screen goes. Not before.",
	ownedButton = "Toggle the owned panel",
	hoistedButton = "Toggle the hoisted panel",
	panelBody = "A motion value, a subscription and an async handle.",
	statsTitle = "What the framework counts",
	openedLabel = "Opened",
	releasedLabel = "Released",
	liveLabel = "Still held",
	scopesLabel = "Live scopes",
	balanced = "Balanced: nothing a closed panel opened is still held.",
	leaking = "Leaking: the hoisted panel is closed and still holding handles.",
}

return {
	title = "When branch scope",
	ledgerRows = {},
	copy = COPY,
	handlesPerOpen = HANDLES_PER_OPEN,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("branch-scope")

		local ownedShowing = scope:own(core:signal(false))
		local hoistedShowing = scope:own(core:signal(false))

		-- plain counters, because they are read after each write completes rather
		-- than subscribed to; the one signal below is what makes the readout live
		local stats = {
			ownedOpened = 0,
			ownedReleased = 0,
			hoistedOpened = 0,
			hoistedReleased = 0,
		}
		local readout = scope:own(core:signal(""))

		-- ONE handle factory for both panels, so the ONLY difference between them
		-- is which scope it is handed. A fixture whose two halves allocate
		-- different things would be comparing two changes at once.
		local function openHandles(owner: any, onRelease: () -> ())
			for _ = 1, HANDLES_PER_OPEN do
				owner:own(onRelease)
			end
		end

		local function refresh()
			local ownedLive = stats.ownedOpened * HANDLES_PER_OPEN - stats.ownedReleased
			local hoistedLive = stats.hoistedOpened * HANDLES_PER_OPEN - stats.hoistedReleased
			local verdict = if hoistedLive > 0 and not hoistedShowing:get() then COPY.leaking else COPY.balanced
			readout:set(
				`{COPY.ownedTitle}\n`
					.. `  {COPY.openedLabel}: {stats.ownedOpened}   {COPY.releasedLabel}: {stats.ownedReleased}   {COPY.liveLabel}: {ownedLive}\n`
					.. `{COPY.hoistedTitle}\n`
					.. `  {COPY.openedLabel}: {stats.hoistedOpened}   {COPY.releasedLabel}: {stats.hoistedReleased}   {COPY.liveLabel}: {hoistedLive}\n`
					.. `{COPY.scopesLabel}: {core:counters().scopes}\n`
					.. verdict
			)
		end

		local function panelBody(id: string): any
			return UI.VStack({
				id = id,
				gap = "tight",
				width = UI.fill(),
				children = {
					UI.Text({ id = "Body", text = COPY.panelBody, textSize = "caption", role = "secondary" }),
				},
			})
		end

		local screen = UI.Screen({
			id = "BranchScope",
			padding = 12,
			gap = "s",
			children = {
				-- THE PAGE SCROLLS, for the reason every other fixture here does: a
				-- title, two panels, two buttons and a five-line readout do not fit the
				-- ~200px a 640x320 landscape phone has left once the showcase reserves
				-- its chip strip.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						UI.Text({ id = "Intro", text = COPY.intro, textSize = "caption", role = "secondary" }),

						UI.VStack({
							id = "Owned",
							surface = "control",
							padding = "s",
							gap = "tight",
							width = UI.fill(),
							children = {
								UI.Text({ id = "OwnedTitle", text = COPY.ownedTitle, textSize = "caption" }),
								UI.Button({
									id = "OwnedButton",
									label = COPY.ownedButton,
									onActivate = function()
										ownedShowing:set(not ownedShowing:get())
										refresh()
									end,
								}),
								UI.When({
									id = "OwnedGate",
									condition = ownedShowing,
									-- THE WHOLE FIXTURE IS THIS ARGUMENT. The scope arrives
									-- with the branch and dies with it, so the handles below
									-- need no cleanup path of their own and no reset.
									thenView = function(branchScope)
										stats.ownedOpened += 1
										openHandles(branchScope, function()
											stats.ownedReleased += 1
										end)
										return panelBody("OwnedPanel")
									end,
								}),
								UI.Text({
									id = "OwnedNote",
									text = COPY.ownedNote,
									textSize = "caption",
									role = "secondary",
								}),
							},
						}),

						UI.VStack({
							id = "Hoisted",
							surface = "control",
							padding = "s",
							gap = "tight",
							width = UI.fill(),
							children = {
								UI.Text({ id = "HoistedTitle", text = COPY.hoistedTitle, textSize = "caption" }),
								UI.Button({
									id = "HoistedButton",
									label = COPY.hoistedButton,
									onActivate = function()
										hoistedShowing:set(not hoistedShowing:get())
										refresh()
									end,
								}),
								UI.When({
									id = "HoistedGate",
									condition = hoistedShowing,
									-- ...and this one IGNORES the argument, which is still
									-- valid and is exactly what every `thenView` written
									-- before this shipped does. It owns on `scope`, the
									-- enclosing one, because that is where the old shape had
									-- to put it.
									thenView = function()
										stats.hoistedOpened += 1
										openHandles(scope, function()
											stats.hoistedReleased += 1
										end)
										return panelBody("HoistedPanel")
									end,
								}),
								UI.Text({
									id = "HoistedNote",
									text = COPY.hoistedNote,
									textSize = "caption",
									role = "secondary",
								}),
							},
						}),

						UI.Text({ id = "StatsTitle", text = COPY.statsTitle, textSize = "caption" }),
						UI.Text({ id = "Stats", text = readout, textSize = "caption", role = "secondary" }),
					},
				}),
			},
		})

		refresh()

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the signals and the live counts a
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
					return { showing = ownedShowing:get(), opened = stats.ownedOpened, released = stats.ownedReleased }
				end,
				setHoisted = function(_built: any, payload: string?)
					hoistedShowing:set(payload ~= "off")
					refresh()
					return {
						showing = hoistedShowing:get(),
						opened = stats.hoistedOpened,
						released = stats.hoistedReleased,
					}
				end,
			},

			report = function()
				return {
					ownedShowing = ownedShowing:get(),
					hoistedShowing = hoistedShowing:get(),
					ownedOpened = stats.ownedOpened,
					ownedReleased = stats.ownedReleased,
					hoistedOpened = stats.hoistedOpened,
					hoistedReleased = stats.hoistedReleased,
					scopes = core:counters().scopes,
				}
			end,

			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
