--!strict
-- "Today's order" — the played task Sipworks is about, in the two shapes a task
-- needs: a bounded STRIP that is on screen in every section, and the CARD that
-- carries the goal, the next action and the completion state.
--
-- WHY TWO SHAPES AND NOT ONE BAND. The first build of this was a single band
-- pinned above the nav, and it was measured rather than argued: at 320x640, the
-- largest text preference and the 1.4x expansion locale, the band asked for 780px
-- of a 640px screen and the nav's own content box collapsed to 4px — the solver
-- said so on every solve. A task that buries the app it is a task ON is not a
-- task, so the two jobs were separated by what they cost:
--
--   * THE STRIP is one line by construction (`lineLimit = 1` + `disclose` on both
--     of its two texts), so its height is one line box at every preference and it
--     can never take the catalogue's room. It carries the two facts a player must
--     never have to go looking for: what the task is, and how far along it is. On a
--     landscape phone (`isShort`) even one line is more than the nav can spare under
--     the thicker theme packages, so it yields there and the card carries the task.
--   * THE CARD rides INSIDE the section's own scroller, exactly as the Blend
--     Book's unlock card does, so it is as tall as its copy needs at any text size
--     or locale and overflows nothing. It is the first thing on the opening
--     screen, with the catalogue directly underneath it.
--
-- WHY "What this shows" IS A BUTTON AND NOT `Facet.Controls.DisclosureGroup`.
-- The construct's `label` is validated as a plain `string` (see
-- `src/controls/disclosure_group.luau`), so a disclosure header cannot follow this
-- app's live locale flip — the same shape `views/parts.luau` records for
-- `newLabel.title` and Glade's supply row records for its affordance. Recorded as
-- a framework finding; the header here is a bound Button, so the `xa` sweep
-- measures the expansion locale's own words rather than an English literal.

local dims = require("../content/dims")
local rewardsService = require("../services/rewards")

local taskView = {}

-- the phase → next-action copy, as data: one key per phase, so a new phase cannot
-- be added without a line for the player to read
local NEXT_KEY: { [string]: string } = {
	order = "task.next.order",
	placing = "task.next.placing",
	rejected = "task.next.rejected",
	redeem = "task.next.redeem",
}

-- one memo set per mount, built from the services the band binds. `app.own` ties
-- every one of them to the view scope, so a shell rebuild retires them.
local function model(app: any): any
	local core = app.core
	local i18n = app.services.i18n
	local rewards = app.services.rewards
	local catalog = app.services.catalog
	local task = app.services.task

	local m: any = {}
	m.isDone = app.own(core:memo(function(use)
		return use(task.phase) == "done"
	end))
	m.isActive = app.own(core:memo(function(use)
		return use(task.phase) ~= "done"
	end))
	-- the CTA is dead while the counter is answering: a verb that fires into a
	-- pending command is a verb that lies about what it did
	m.ctaEnabled = app.own(core:memo(function(use)
		return use(task.phase) ~= "placing"
	end))
	m.nextLine = app.own(core:memo(function(use)
		local locale = use(i18n.locale)
		return i18n.at(locale, NEXT_KEY[use(task.phase)] or NEXT_KEY.order)
	end))
	-- the CTA NAMES its blend, because "choose a blend" with nothing named is a
	-- first action a player has to hunt for
	m.ctaLabel = app.own(core:memo(function(use)
		local locale = use(i18n.locale)
		local blendId = use(task.ctaBlendId)
		local blend = catalog.blend(blendId)
		local key = if use(task.phase) == "redeem" then "task.cta.redeem" else "task.cta.order"
		return i18n.at(locale, key, { title = i18n.nameAt(locale, "blend", blendId, blend.title) })
	end))
	-- the strip's own headline: the task's name while it runs, and what was
	-- accomplished once it is finished
	m.stripTitle = app.own(core:memo(function(use)
		local locale = use(i18n.locale)
		return i18n.at(locale, if use(task.phase) == "done" then "task.done.title" else "task.title")
	end))
	-- the stamp card's own progress, and the number IS the lesson (a stamp card
	-- is a counter) — so it is on the player surface rather than behind a tab
	m.progress = app.text("rewards.progress", function(use)
		return { n = math.clamp(use(rewards.earned) - use(rewards.spent), 0, rewardsService.THRESHOLD) }
	end)
	return m
end

-- ---------------------------------------------------------------------------
-- the strip: one line, every section, every phase
-- ---------------------------------------------------------------------------

--[[ ...AND IT YIELDS ON THE ONE SHAPE THAT CANNOT AFFORD IT. A landscape phone is
	320-338px tall; under the thicker theme packages (Fantasy Ornate, Pixel Quest,
	Glossy Touch) the nav's own dock, strip and content already overrun that box by
	up to 81px at the largest text preference with the strip in front of them — the
	solver files it on every solve, at every one of those packages. `isShort` is the
	framework's own name for that shape, and on it the task lives entirely in the
	CARD at the top of the page, which is one scroll away rather than one press.
	Every other shape keeps the strip. ]]
function taskView.strip(app: any): any
	local UI = app.UI
	local m = model(app)
	local roomy = app.own(app.core:memo(function(use)
		return not use(app.cond.isShort)
	end))
	return UI.When({
		id = "TaskStripWhen",
		condition = roomy,
		thenView = function()
			return taskView.stripBody(app, m)
		end,
	})
end

function taskView.stripBody(app: any, m: any): any
	local UI = app.UI
	return UI.HStack({
		id = "TaskStrip",
		surface = "raised",
		padding = "xs",
		gap = "s",
		align = "center",
		width = dims.fill,
		children = {
			UI.Text({
				id = "TaskLabel",
				text = m.stripTitle,
				textSize = "strong",
				width = dims.fill,
				lineLimit = 1,
				disclose = true,
			}),
			UI.Text({
				id = "TaskProgress",
				text = m.progress,
				textSize = "caption",
				role = "secondary",
				textAlign = "end",
				-- BANDED, because `lineLimit` caps LINES and never the width a text
				-- asks for: at 320px, the largest preference and the 1.4x locale the
				-- readout's natural ask pushed the strip 3px past its box
				width = dims.atLeast("app.sip.taskProgressMin", "app.sip.taskProgressMax"),
				lineLimit = 1,
				disclose = true,
			}),
		},
	})
end

-- ---------------------------------------------------------------------------
-- the card: the goal, the next action, the verb, and the completion state
-- ---------------------------------------------------------------------------

function taskView.card(app: any): any
	local UI = app.UI
	local core = app.core
	local m = model(app)
	local showsOpen = app.own(core:signal(false))

	local active = UI.When({
		id = "TaskActive",
		condition = m.isActive,
		thenView = function()
			return UI.VStack({
				id = "TaskBody",
				gap = "s",
				width = dims.fill,
				children = {
					UI.Text({
						id = "TaskTitle",
						text = app.text("task.title"),
						textSize = "heading",
						width = dims.fill,
					}),
					-- THE GOAL, in one sentence, on the opening screen
					UI.Text({
						id = "TaskGoal",
						text = app.text("task.intro"),
						textSize = "body",
						role = "secondary",
						width = dims.fill,
					}),
					-- ...and the next action, which is the line that changes
					UI.Text({
						id = "TaskNext",
						text = m.nextLine,
						textSize = "body",
						width = dims.fill,
					}),
					UI.Button({
						id = "TaskAct",
						label = m.ctaLabel,
						enabled = m.ctaEnabled,
						surface = "accent",
						corners = UI.cornersData("pill"),
						width = dims.fill,
						onActivate = function()
							app.commands.taskAction()
						end,
					}),
				},
			})
		end,
	})

	-- THE COMPLETION STATE, and it replaces the task rather than sitting beside
	-- it: a finished task still showing its next action is a task a player cannot
	-- tell they finished.
	local done = UI.When({
		id = "TaskDone",
		condition = m.isDone,
		transition = { enter = "fade" },
		thenView = function()
			return UI.ZStack({
				id = "TaskDoneGroup",
				canvasGroup = true,
				width = dims.fill,
				children = {
					UI.VStack({
						id = "TaskDoneBody",
						gap = "s",
						width = dims.fill,
						children = {
							UI.Text({
								id = "TaskDoneTitle",
								text = app.text("task.done.title"),
								textSize = "heading",
								width = dims.fill,
							}),
							UI.Text({
								id = "TaskDoneCopy",
								text = app.text("task.done.body"),
								textSize = "body",
								role = "secondary",
								width = dims.fill,
							}),
							UI.Button({
								id = "TaskReset",
								label = app.text("task.done.reset"),
								surface = "accent",
								corners = UI.cornersData("pill"),
								width = dims.fill,
								onActivate = function()
									app.commands.serveAnother()
								end,
							}),
						},
					}),
				},
			})
		end,
	})

	return UI.VStack({
		id = "TaskCard",
		surface = "raised",
		corners = UI.cornersData("panel"),
		stroke = UI.strokeData({}),
		padding = "m",
		gap = "s",
		width = dims.fill,
		children = {
			active,
			done,
			-- ...and the Facet lesson LAST, collapsed, optional: it explains the
			-- app after the play task rather than instead of it.
			UI.Button({
				id = "TaskShows",
				label = app.text("task.shows.open"),
				selected = showsOpen,
				align = "start",
				onActivate = function()
					showsOpen:set(not showsOpen:get())
				end,
			}),
			UI.When({
				id = "TaskShowsWhen",
				condition = showsOpen,
				transition = { enter = "fade" },
				thenView = function()
					return UI.ZStack({
						id = "TaskShowsGroup",
						canvasGroup = true,
						width = dims.fill,
						children = {
							UI.Text({
								id = "TaskShowsBody",
								text = app.text("task.shows.body"),
								textSize = "caption",
								role = "secondary",
								width = dims.fill,
							}),
						},
					})
				end,
			}),
		},
	})
end

return taskView
