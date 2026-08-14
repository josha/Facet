--!strict
-- Scenario 'hud' (ADR-0025): THE SCREEN-ANCHORED HUD, and the thing it refuses
-- to do.
--
-- The commissioning case is two screenshots of a shipped FPS. Fullscreen the HUD
-- is right. Open a browser URL bar — SAME WIDTH, ~200px LESS HEIGHT — and it
-- collapses into itself: the task panel climbs into the round buttons above it,
-- the weapon rail runs into the fps/ping readout, and the action buttons land on
-- each other.
--
-- This fixture is that HUD, built on `composition.HUD` — corner clusters, a task
-- panel down the middle-left, a weapon rail top-right — plus the ONE control that
-- makes the point: **URL BAR**, which takes 200px of height off the HUD's box
-- exactly the way a browser chrome bar does. Turn it on and nothing overlaps;
-- what happens instead is that the least important zone in the column that ran
-- out gives up its richest form, and then drops.
--
-- WHY THE TOGGLE AND NOT "JUST RESIZE THE WINDOW". Resizing works too — the HUD
-- measures the box it received, so the emulator, a window drag and this toggle
-- are the same event to it. The toggle exists because the DEFECT is a comparison
-- between two states of one screen, and a still screenshot flattens a comparison
-- into one picture (`flow_wrap`'s wrapping switch is here for the same reason).
--
-- AND THE PLATFORM'S OWN ROW (ADR-0027, director 2026-08-14: *"we should be able
-- to have things at top that are aligned with the controls but don't overlap"*).
-- Roblox's chrome does NOT own the whole top band — measured live at 735x413 it
-- occupies x 0..164 of a 58px band and the rest of that band is the developer's
-- (`GuiService.TopbarInset`). `deviceSafeContent` spends the whole band because a
-- rect inset is a bounding box, so nothing could ever sit level with the platform's
-- buttons. This surface therefore presents `edgeToEdge` and insets itself from the
-- ONE fact that knows the difference — `platformChrome` — which is still a single
-- authority, just one that can state an L:
--
--   riding the band   margin.top = platformChrome.bandInsets.top (0 here), and the
--                     `topbar` zone is the row LEVEL WITH the platform's controls
--   not riding        margin.top = platformChrome.insets.top — byte-identical to
--                     what `deviceSafeContent` applied, which is what a platform
--                     reporting NO strip (desktop, or an engine without
--                     `GetInsetArea`) gets automatically
--
-- THE ZONES, and the director's own list of where things live:
--   topbar      the objective chip, in the free strip beside Roblox's own buttons
--   topLeft     the round-button strip (the platform's chrome sits above it)
--   left        the "Beginner Tasks" panel — three forms: full / one task / chip
--   top         the round timer and the score pill
--   topRight    the weapon rail (two forms) and the fps/ping readout (droppable)
--   bottomRight the action buttons (two forms)
--   bottomLeft  the kill feed (droppable)

-- EVERY PLAYER-VISIBLE STRING, in one table and exported, so the localization
-- case can expand all of them ~1.4x. All of it must fit and wrap, never clip.
local COPY = {
	tasksTitle = "Beginner tasks",
	task1 = "Win a round",
	task2 = "Land 25 hits",
	task3 = "Open a crate",
	tasksChip = "Tasks 1/3",
	timer = "2:14",
	score = "12 - 9",
	weapon1 = "Rifle",
	weapon2 = "Pistol",
	weapon3 = "Knife",
	readout = "60 FPS · 42 ms",
	action1 = "Shop",
	action2 = "Team",
	action3 = "Menu",
	feed = "Ravi eliminated Mo",
	urlBarOn = "URL bar",
	rideOn = "Topbar strip",
	objective = "Round 3 · Capture",
	objectiveShort = "R3",
	round1 = "A",
	round2 = "B",
	round3 = "C",
}

-- the browser chrome the commissioning screenshot opened, in pixels. A landscape
-- phone losing this much height is the exact case; it is a constant here because
-- it is a fact about the SCREENSHOT, not a layout number the theme owns.
local URL_BAR_PX = 200

-- ...and the same kind of constant for the OTHER commissioning fact: the width of
-- Roblox's own control cluster, measured live at 735x413 on 2026-08-14. It is used
-- for ONE thing — modelling a platform in the headless suite and the always-on
-- sweep, which have no engine to ask — and never by the layout, which reads
-- `platformChrome`. A fixture that could not model the platform would leave the
-- mechanism unexercised by every sweep, which is how a feature becomes decoration.
local MODELLED_CLUSTER_PX = 164
local MODELLED_STRIP_PX = 58

return {
	title = "Screen-anchored HUD (ADR-0025)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core
		local scope = core:scope("hud")

		local urlBar = scope:own(core:signal(false))
		-- the author's own decision, and the demo's second comparison: a HUD that
		-- RIDES the platform's free strip against the same HUD that does not
		local ride = scope:own(core:signal(true))

		local env = ctx.env
		local chromeFact = env:get("platformChrome")
		local viewportFact = env:get("viewportRect")

		--[[ MODELLING A PLATFORM THAT IS NOT THERE (headless only). The engine
			publishes `topbarInset` through `roblox_env`; a Lune suite and the
			always-on overflow sweep have no engine, so `platformChrome.band` is nil
			and every rung below would be the no-strip one — the mechanism would ship
			unexercised by the sweep that is supposed to be watching it. So when, and
			only when, the platform reports NO strip, this fixture states one the way
			the live engine states it. On any real client the fact is already there
			and this branch never runs.

			`flags.noTopbarStrip` opts out, which is how a test drives the OTHER
			platform — the one with no strip at all — through this same fixture. ]]
		local modelStrip = (ctx.flags == nil or ctx.flags.noTopbarStrip ~= true)
			and (chromeFact:get() :: any).band == nil
		if modelStrip then
			local vp = viewportFact:get()
			local coreTop = (env:get("coreSafeInsets"):get() or {}).top or 0
			if coreTop > 0 and vp.w > MODELLED_CLUSTER_PX * 2 then
				env:set("topbarInset", {
					x = MODELLED_CLUSTER_PX,
					y = 0,
					w = vp.w - MODELLED_CLUSTER_PX,
					h = math.min(MODELLED_STRIP_PX, coreTop),
				})
			end
		end

		-- ONE fact, read four ways. Nothing below knows 164, or 58, or a device.
		local riding = scope:own(core:memo(function(use)
			return use(ride) == true and (use(chromeFact) :: any).band ~= nil
		end))
		-- the surface is edgeToEdge, so the HUD spends the insets itself — from the
		-- fact, and the fact alone. Riding the band spends the top down to where the
		-- band starts; not riding spends the whole band, which is exactly what
		-- `deviceSafeContent` used to apply here.
		local margin = scope:own(core:memo(function(use)
			local chrome = use(chromeFact) :: any
			local insets = if use(riding) then chrome.bandInsets else chrome.insets
			return {
				top = insets.top,
				right = 0,
				bottom = if use(urlBar) then URL_BAR_PX else 0,
				left = 0,
			}
		end))
		-- everything the HUD is NOT allowed to reach, on the other three edges. The
		-- top is the HUD's own margin above, because the top is the edge with a hole
		-- in it.
		local screenPadding = scope:own(core:memo(function(use)
			local insets = (use(chromeFact) :: any).insets
			return { top = 0, right = insets.right, bottom = insets.bottom, left = insets.left }
		end))
		-- the topbar row: as tall as the band the platform left free, and inset to
		-- START where that band starts — so the chip is level with Roblox's own
		-- buttons and cannot be over them.
		local stripHeight = scope:own(core:memo(function(use)
			local chrome = use(chromeFact) :: any
			if not use(riding) then
				return { type = "fixed", px = 0 }
			end
			return { type = "fixed", px = math.max(0, chrome.insets.top - chrome.bandInsets.top) }
		end))
		-- ...and the platform's own cluster is held open as SPACE inside that row —
		-- a leading spacer as wide as the distance from the HUD's own left edge to
		-- where the free band begins, and a trailing one for the platforms that put
		-- something on the right too. Space, not an offset, so the row's content is
		-- laid out INSIDE what is left rather than positioned over what is not.
		local function edgeSpacer(pick: (any, any) -> number): any
			return scope:own(core:memo(function(use)
				local chrome = use(chromeFact) :: any
				local band = chrome.band
				if not use(riding) or band == nil then
					return { type = "fixed", px = 0 }
				end
				return { type = "fixed", px = math.max(0, pick(chrome, use(viewportFact))) }
			end))
		end
		local stripLead = edgeSpacer(function(chrome, _vp)
			return chrome.band.x - chrome.insets.left
		end)
		local stripTrail = edgeSpacer(function(chrome, vp)
			return (vp.w - chrome.insets.right) - (chrome.band.x + chrome.band.w)
		end)

		-- ---- the pieces --------------------------------------------------
		local function roundButton(id: string, label: string): any
			return UI.corners(UI.Button({ id = id, label = label, surface = "chip" }), "pill")
		end

		local function pill(id: string, text: string, size: string): any
			return UI.corners(
				UI.HStack({
					id = id,
					surface = "raised",
					padding = 8,
					children = { UI.Text({ id = id .. "T", text = text, textSize = size }) },
				}),
				"pill"
			)
		end

		local taskBars = {}
		for i, key in { "task1", "task2", "task3" } do
			local view = LuauUI.newProgressView(LuauUI, core, {
				id = `Task{i}`,
				label = (COPY :: any)[key],
				value = scope:own(core:signal(0.2 * i)),
			})
			table.insert(taskBars, view)
		end

		-- ---- the HUD -----------------------------------------------------
		local hud = UI.Composition({
			id = "Hud",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			margin = margin,
			groups = LuauUI.composition.HUD_GROUPS,
			arrangements = { LuauUI.composition.HUD },
			children = {
				-- THE PLATFORM'S OWN ROW (ADR-0027). A `span = "above"` group, so it
				-- is one full-width row above every lane in every arrangement — which
				-- is what makes the nine anchored zones start BELOW the platform's
				-- band instead of being told to avoid it. Its content is inset to the
				-- free band's own left edge, so it sits level with Roblox's buttons
				-- and cannot be on them; when nothing is riding, `UI.When` closes the
				-- row entirely and the composition is byte-identical to the HUD that
				-- never had the zone.
				UI.Region({
					id = "Strip",
					group = "topbar",
					rank = 6,
					--[[ RESERVED, AND THIS IS THE ONE THAT WAS FOUND BY THE CHECK.
						With `mayDrop` the row was droppable, so on a 213px-tall window
						the ladder dropped it (rank 6, 58px bought) — and every lane then
						climbed into the space it left, which is THE PLATFORM'S BAND. The
						band is not the HUD's to reclaim: it belongs to Roblox whether or
						not this HUD has anything to put in it. `reserved` is rule 7's own
						word for exactly that, and it is live, so the row reserves nothing
						at all on the rung that is not riding. ]]
					reserved = riding,
					-- the floor a reserved region owes: content-expressed, like every
					-- floor. The row's real height is the band's (a platform fact the
					-- form carries); this is only what it may never fall below.
					floor = { targets = 1 },
					children = {
						UI.HStack({
							id = "StripRow",
							width = { type = "fill", weight = 1 },
							height = stripHeight,
							align = "center",
							children = {
								UI.Spacer({ id = "StripLead", width = stripLead }),
								UI.HStack({
									id = "StripFree",
									width = { type = "fill", weight = 1 },
									align = "center",
									distribute = "center",
									children = {
										UI.When({
											id = "StripChip",
											condition = riding,
											thenView = function()
												-- the band can be narrow (a 320px phone has ~156px
												-- of it), so the fit is the framework's decision
												-- and not an authored width guess
												return UI.ViewThatFits({
													id = "StripFit",
													children = {
														pill("Objective", COPY.objective, "caption"),
														pill("ObjectiveShort", COPY.objectiveShort, "caption"),
													},
												})
											end,
										}),
									},
								}),
								UI.Spacer({ id = "StripTrail", width = stripTrail }),
							},
						}),
					},
				}),
				-- UPPER LEFT — the round-button strip. One form: this is the thing
				-- the player reaches for, and a HUD that hides its own buttons on a
				-- short screen has solved the wrong problem.
				UI.Region({
					id = "Rounds",
					group = "topLeft",
					rank = 1,
					children = {
						UI.HStack({
							id = "RoundStrip",
							gap = 6,
							children = { roundButton("R1", COPY.round1), roundButton("R2", COPY.round2) },
						}),
						-- ...and the same three buttons stacked, for the column a 320px
						-- phone actually has. Rank 1: it is the last thing to give way,
						-- but it still has somewhere to go
						UI.VStack({
							id = "RoundColumn",
							gap = 6,
							children = {
								roundButton("R1c", COPY.round1),
								roundButton("R2c", COPY.round2),
								roundButton("R3c", COPY.round3),
							},
						}),
					},
				}),
				-- MIDDLE LEFT — the task panel, three forms richest first. This is
				-- the panel that landed on the round buttons in the screenshot.
				UI.Region({
					id = "Tasks",
					group = "left",
					rank = 8,
					mayDrop = true,
					floor = { lines = 1 },
					children = {
						UI.VStack({
							id = "TasksFull",
							surface = "raised",
							padding = 10,
							gap = 6,
							children = {
								UI.Text({ id = "TasksTitle", text = COPY.tasksTitle, textSize = "label" }),
								taskBars[1].blueprint,
								taskBars[2].blueprint,
								taskBars[3].blueprint,
							},
						}),
						UI.VStack({
							id = "TasksOne",
							surface = "raised",
							padding = 10,
							gap = 6,
							children = {
								UI.Text({ id = "TasksTitle2", text = COPY.tasksTitle, textSize = "label" }),
								taskBars[1].blueprint,
							},
						}),
						pill("TasksChip", COPY.tasksChip, "caption"),
					},
				}),
				-- LOWER LEFT — the kill feed, droppable: the first thing a real HUD
				-- gives up, and the least missed.
				UI.Region({
					id = "Feed",
					group = "bottomLeft",
					rank = 9,
					mayDrop = true,
					children = { UI.Text({ id = "FeedLine", text = COPY.feed, textSize = "caption" }) },
				}),
				-- UPPER CENTRE — the round clock and the score.
				UI.Region({
					id = "Clock",
					group = "top",
					rank = 2,
					children = {
						UI.VStack({
							id = "ClockStack",
							gap = 4,
							align = "center",
							children = { pill("Timer", COPY.timer, "heading"), pill("Score", COPY.score, "label") },
						}),
						-- the clock ALONE, and the Studio canary is why this exists: with
						-- the URL bar open on a 735x413 window the centre column has 61px
						-- and the pair needs 77. One form meant the centre could not give,
						-- so a legal HUD still painted 16px below its own box. What a real
						-- HUD gives up on a squeezed screen is the score, not the clock.
						pill("TimerOnly", COPY.timer, "heading"),
					},
				}),
				-- UPPER RIGHT — the weapon rail, two forms, and the readout beside
				-- it. In the screenshot these two are what ran into each other.
				UI.Region({
					id = "Rail",
					group = "topRight",
					rank = 4,
					-- DROPPABLE, and the Studio canary is why. On a 735x413 window with
					-- the URL bar open the right column has 61px and holds a 31px rail
					-- over a 46px button: neither could give any more, so the whole
					-- arrangement went illegal and rule 8 showed the DECLARED FALLBACK —
					-- correct by contract, and 16px of HUD painted below its own box. A
					-- weapon rail is more expendable than the action buttons (rank 4 vs
					-- 3), so saying so is what lets the ladder finish instead of falling
					-- back.
					mayDrop = true,
					children = {
						UI.VStack({
							id = "RailTall",
							gap = 4,
							align = "end",
							children = {
								pill("W1", COPY.weapon1, "label"),
								pill("W2", COPY.weapon2, "label"),
								pill("W3", COPY.weapon3, "label"),
							},
						}),
						-- the compact form is NARROWER, not merely shorter: a HUD column
						-- is a third of the screen, so a horizontal compact form is the
						-- wrong ladder in a column (the sweep found this at 320px)
						pill("W1c", COPY.weapon1, "caption"),
					},
				}),
				UI.Region({
					id = "Readout",
					group = "topRight",
					rank = 7,
					mayDrop = true,
					children = { UI.Text({ id = "ReadoutText", text = COPY.readout, textSize = "caption" }) },
				}),
				-- LOWER RIGHT — the action buttons, two forms (column, then row).
				UI.Region({
					id = "Actions",
					group = "bottomRight",
					rank = 3,
					children = {
						UI.VStack({
							id = "ActionsCol",
							gap = 6,
							align = "end",
							children = {
								roundButton("A1", COPY.action1),
								roundButton("A2", COPY.action2),
								roundButton("A3", COPY.action3),
							},
						}),
						roundButton("A1r", COPY.action1),
					},
				}),
			},
		})

		-- The switches are the FIXTURE'S DRIVERS, not HUD content, so they sit under
		-- the HUD rather than in a zone: a Toggle does not fit a third of a 320px
		-- phone, and putting the instrument inside the thing it measures would have
		-- made the narrowest swept viewport a test of the instrument.
		--
		-- The screen is `edgeToEdge` (the HUD needs the top band), so the three edges
		-- with no hole in them are spent HERE, once, from the same fact — which is
		-- also what keeps these two drivers off a home indicator.
		local screen = UI.Screen({
			id = "HudScreen",
			padding = screenPadding,
			gap = 4,
			children = {
				hud,
				-- two switches WRAP rather than run off a 320px phone at the largest
				-- text preference — found by the always-on sweep the moment the second
				-- one was added, which is the sweep doing its job on the instrument
				UI.HStack({
					id = "Drivers",
					gap = 12,
					wrap = true,
					children = {
						UI.Toggle({ id = "UrlBar", label = COPY.urlBarOn, value = urlBar }),
						UI.Toggle({ id = "RideStrip", label = COPY.rideOn, value = ride }),
					},
				}),
			},
		})

		-- the last solve's resolution, through the runner's own accessor (the same
		-- one `composition` uses) — nil before anything has solved
		local function state(): any
			return if ctx.composition ~= nil then ctx.composition("/HudScreen/Hud") else nil
		end

		return {
			screen = screen,
			-- EDGE TO EDGE, and the insets come from `platformChrome` above — still
			-- ONE authority, and the only one that can say "the top band is an L".
			-- `deviceSafeContent` would spend the whole band and put the topbar row
			-- out of reach; every other edge is spent identically (pinned in
			-- tests/adaptive.spec.luau).
			present = { rootPolicy = "edgeToEdge" },
			steps = {
				openUrlBar = function()
					urlBar:set(true)
					return { urlBar = true, lostPx = URL_BAR_PX }
				end,
				closeUrlBar = function()
					urlBar:set(false)
					return { urlBar = false, lostPx = 0 }
				end,
				rideStrip = function()
					ride:set(true)
					return { riding = riding:get(), band = (chromeFact:get() :: any).band }
				end,
				leaveStrip = function()
					ride:set(false)
					return { riding = false }
				end,
			},
			report = function()
				local dump = state()
				local forms: { [string]: number } = {}
				local dropped: { string } = {}
				if dump ~= nil then
					for _, r in dump.regions do
						forms[r.id] = r.form
						if r.dropped then
							table.insert(dropped, r.id)
						end
					end
				end
				local chrome = chromeFact:get() :: any
				return {
					urlBar = urlBar:get(),
					arrangement = if dump ~= nil then dump.arrangement else nil,
					fallback = if dump ~= nil then dump.fallback else nil,
					-- the whole point, in one number: a HUD that adapted has ZERO
					-- collisions at every size, and the ones that gave way are named
					collisions = if dump ~= nil then #dump.collisions else nil,
					forms = forms,
					dropped = dropped,
					-- ...and the OTHER whole point, in three: what the platform kept,
					-- what it left free, and whether this HUD is using it. The rects
					-- nothing may touch are `chromeRects`; the regression check that
					-- nothing does is tests/hud_composition.spec.luau.
					riding = riding:get(),
					band = chrome.band,
					chromeRects = chrome.rects,
				}
			end,
			dispose = function()
				for _, view in taskBars do
					view.dispose()
				end
				scope:dispose()
			end,
		}
	end,
}
