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
-- SAFE AREAS ARE THE ROOT POLICY'S JOB, not this fixture's: `deviceSafeContent`
-- clears the CoreGui topbar AND the device notch/home insets from one authority,
-- which is what keeps the top-left cluster off Roblox's own chrome in the
-- screenshot. This surface therefore declares the policy and no insets of its own.
--
-- THE ZONES, and the director's own list of where things live:
--   topLeft     the round-button strip (the chrome sits above it)
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
	round1 = "A",
	round2 = "B",
	round3 = "C",
}

-- the browser chrome the commissioning screenshot opened, in pixels. A landscape
-- phone losing this much height is the exact case; it is a constant here because
-- it is a fact about the SCREENSHOT, not a layout number the theme owns.
local URL_BAR_PX = 200

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
		local margin = scope:own(core:memo(function(use)
			return { top = 0, right = 0, bottom = if use(urlBar) then URL_BAR_PX else 0, left = 0 }
		end))

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

		-- The switch is the FIXTURE'S DRIVER, not HUD content, so it sits under the
		-- HUD rather than in a zone: a Toggle does not fit a third of a 320px phone,
		-- and putting the instrument inside the thing it measures would have made
		-- the narrowest swept viewport a test of the instrument.
		local screen = UI.Screen({
			id = "HudScreen",
			padding = 0,
			gap = 4,
			children = {
				hud,
				UI.Toggle({ id = "UrlBar", label = COPY.urlBarOn, value = urlBar }),
			},
		})

		-- the last solve's resolution, through the runner's own accessor (the same
		-- one `composition` uses) — nil before anything has solved
		local function state(): any
			return if ctx.composition ~= nil then ctx.composition("/HudScreen/Hud") else nil
		end

		return {
			screen = screen,
			-- the topbar and the notch come from ONE authority; a HUD that inset
			-- itself would be the second source of truth this policy exists to remove
			present = { rootPolicy = "deviceSafeContent" },
			steps = {
				openUrlBar = function()
					urlBar:set(true)
					return { urlBar = true, lostPx = URL_BAR_PX }
				end,
				closeUrlBar = function()
					urlBar:set(false)
					return { urlBar = false, lostPx = 0 }
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
				return {
					urlBar = urlBar:get(),
					arrangement = if dump ~= nil then dump.arrangement else nil,
					fallback = if dump ~= nil then dump.fallback else nil,
					-- the whole point, in one number: a HUD that adapted has ZERO
					-- collisions at every size, and the ones that gave way are named
					collisions = if dump ~= nil then #dump.collisions else nil,
					forms = forms,
					dropped = dropped,
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
