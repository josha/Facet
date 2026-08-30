--!strict
-- Glade (RA-P1) — "Prepare this glade", the played task, in the two shapes a task
-- needs.
--
--   * THE STRIP rides above the nav and is one line by construction (both of its
--     texts declare `lineLimit = 1` with `disclose`), so it costs exactly one line
--     box at every text preference and in both locales. It carries the two facts a
--     player must never go looking for: what the task is, and how much of it is
--     done.
--   * THE CARD leads the Glades page, inside that page's own scroller, so it is as
--     tall as its copy needs at any text size or locale and overflows nothing. It
--     carries the goal sentence, the named subject, the two progress rows, the
--     next action, the verb, the completion state and the reset.
--
-- WHY NOT ONE PINNED BAND. Measured on the sibling app first: a single band above
-- the nav asked for 780px of a 640px phone at the largest text preference and the
-- 1.4x expansion locale, and the tab construct's content box collapsed to 4px. A
-- task that buries the app it is a task ON is not a task.
--
-- THE ROWS CARRY STATE AS FORM AND WORDS, never as a second hue — the same rule
-- the supply chips follow (spec §6). A row is its label plus a "Done" / "To do"
-- chip, so a player who cannot separate the two tints still reads the checklist.
--
-- WHY "What this shows" IS A BUTTON AND NOT `Facet.Controls.DisclosureGroup`: the
-- construct's `label` is validated as a plain `string`, so a disclosure header
-- cannot follow this app's live locale flip — the same shape this proof already
-- records for `newLabel.title` in `ui/parts.luau`. Recorded as a framework
-- finding; the header here is a bound Button, so the `xa` sweep measures the
-- expansion locale's own words.

local seedData = require("../content/seed")
local parts = require("./parts")

local task = {}

local METRICS = seedData.METRICS

-- the phase → next-action key, as data: a new phase cannot be added without a
-- line for the player to read
local NEXT_KEY: { [string]: string } = {
	start = "task.next.start",
	nectar = "task.next.nectar",
	dew = "task.next.dew",
	resume = "task.next.resume",
}

local function subs(ctx: any): { [string]: string }
	local model = ctx.task
	return {
		glade = ctx.Lnow("glade." .. model.glade),
		wisp = ctx.Lnow("wisp." .. model.wisp),
		nectar = ctx.Lnow("nectar." .. model.nectar),
	}
end

-- one memo set per mount, owned by the caller's scope
local function copy(ctx: any, scope: any): any
	local core = ctx.core
	local model = ctx.task
	local function line(key: string, extra: ((any) -> { [string]: string })?): any
		return scope:own(core:memo(function(use)
			local _ = use(ctx.state.locale)
			local params = subs(ctx)
			if extra ~= nil then
				for name, value in extra(use) do
					params[name] = value
				end
			end
			return ctx.Lnow(key, params)
		end))
	end

	local m: any = {}
	m.subject = line("task.subject")
	m.rowDew = line("task.row.dew")
	m.rowNectar = line("task.row.nectar")
	m.open = line("task.open")
	m.doneTitle = line("task.done.title")
	m.doneBody = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("task.done.body")
	end))
	m.next = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow(NEXT_KEY[use(model.phase)] or NEXT_KEY.start, subs(ctx))
	end))
	m.progress = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		local ready = (if use(model.dewReady) then 1 else 0) + (if use(model.nectarReady) then 1 else 0)
		return ctx.Lnow("task.progress", { n = tostring(ready) })
	end))
	m.stripTitle = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		if use(model.complete) then
			return ctx.Lnow("task.done.title", subs(ctx))
		end
		return ctx.Lnow("task.title")
	end))
	m.isDone = scope:own(core:memo(function(use)
		return use(model.complete)
	end))
	m.isActive = scope:own(core:memo(function(use)
		return not use(model.complete)
	end))
	return m
end

-- ---------------------------------------------------------------------------
-- the strip: one line, above the nav, in every section
-- ---------------------------------------------------------------------------

--[[ ...AND IT YIELDS ON THE ONE SHAPE THAT CANNOT AFFORD IT. A landscape phone is
	320-338px tall; under the thicker theme packages the nav's own dock, strip and
	content already overrun that box with the strip in front of them (measured on
	both apps, at Fantasy Ornate/Parchment, Glossy Mobile/Touch, Pixel Quest and
	Sci-fi HUD). `isShort` is the framework's own name for that shape, and on it the
	task lives entirely in the CARD at the top of the page. ]]
function task.strip(ctx: any): any
	local UI = ctx.UI
	local m = copy(ctx, ctx.scope)
	local roomy = ctx.scope:own(ctx.core:memo(function(use)
		return not use(ctx.conditions.isShort)
	end))
	return UI.When({
		id = "TaskStripWhen",
		condition = roomy,
		thenView = function(): any
			return task.stripBody(ctx, m)
		end,
	})
end

function task.stripBody(ctx: any, m: any): any
	local UI = ctx.UI
	return UI.HStack({
		id = "TaskStrip",
		surface = "raised",
		padding = "xs",
		gap = "s",
		align = "center",
		width = UI.fill(),
		children = {
			UI.Text({
				id = "TaskLabel",
				text = m.stripTitle,
				textSize = "label",
				width = UI.fill(),
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
				-- asks for — the class this proof already records on the supply row's
				-- name, caption and affordance
				width = { type = "minMax", min = METRICS.affordanceMin, max = METRICS.affordanceMax },
				lineLimit = 1,
				disclose = true,
			}),
		},
	})
end

-- ---------------------------------------------------------------------------
-- the card: goal, subject, the two rows, the next action, the verb
-- ---------------------------------------------------------------------------

local function progressRow(ctx: any, id: string, label: any, done: any, scope: any): any
	local UI = ctx.UI
	local core = ctx.core
	local chipText = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow(if use(done) then "task.row.done" else "task.row.todo")
	end))
	return UI.HStack({
		id = id,
		gap = "s",
		align = "center",
		width = UI.fill(),
		children = {
			UI.Text({ id = "RowLabel", text = label, textSize = "body", width = UI.fill() }),
			parts.chip(ctx, "RowState", chipText),
		},
	})
end

function task.card(ctx: any): any
	local UI = ctx.UI
	local core = ctx.core
	local scope = ctx.scope
	local model = ctx.task
	local m = copy(ctx, scope)
	local showsOpen = scope:own(core:signal(false))

	local active = UI.When({
		id = "TaskActive",
		condition = m.isActive,
		thenView = function(): any
			return UI.VStack({
				id = "TaskBody",
				gap = "s",
				width = UI.fill(),
				children = {
					parts.heading(ctx, "TaskTitle", ctx.L("task.title")),
					-- THE GOAL, in one sentence, on the opening screen
					parts.body(ctx, "TaskGoal", ctx.L("task.intro")),
					-- ...and the named subject: a glade, a wisp, and what it likes
					UI.Text({ id = "TaskSubject", text = m.subject, textSize = "label", width = UI.fill() }),
					UI.VStack({
						id = "TaskRows",
						gap = "xs",
						width = UI.fill(),
						children = {
							progressRow(ctx, "TaskRowDew", m.rowDew, model.dewReady, scope),
							progressRow(ctx, "TaskRowNectar", m.rowNectar, model.nectarReady, scope),
						},
					}),
					UI.Text({ id = "TaskNext", text = m.next, textSize = "body", width = UI.fill() }),
					UI.Button({
						id = "TaskOpen",
						label = m.open,
						width = UI.fill(),
						onActivate = function()
							ctx.nav.openGlade(model.glade)
						end,
					}),
				},
			})
		end,
	})

	-- THE COMPLETION STATE, and it replaces the task rather than standing beside
	-- it: a finished task still showing its next action is a task a player cannot
	-- tell they finished.
	local done = UI.When({
		id = "TaskSettled",
		condition = m.isDone,
		transition = { enter = "fade", class = "container" },
		thenView = function(): any
			return UI.ZStack({
				id = "TaskSettledGroup",
				canvasGroup = true,
				width = UI.fill(),
				children = {
					UI.VStack({
						id = "TaskSettledBody",
						gap = "s",
						width = UI.fill(),
						children = {
							UI.Text({
								id = "TaskSettledTitle",
								text = m.doneTitle,
								textSize = "heading",
								width = UI.fill(),
							}),
							parts.body(ctx, "TaskSettledCopy", m.doneBody),
							UI.Button({
								id = "TaskAgain",
								label = ctx.L("task.done.reset"),
								width = UI.fill(),
								onActivate = function()
									ctx.nav.prepareAgain()
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
		padding = "m",
		gap = "s",
		width = UI.fill(),
		children = {
			active,
			done,
			-- ...and the Facet lesson LAST, collapsed, optional: it explains the app
			-- after the play task rather than instead of it.
			UI.Button({
				id = "TaskShows",
				label = ctx.L("task.shows.open"),
				selected = showsOpen,
				align = "start",
				onActivate = function()
					showsOpen:set(not showsOpen:get())
				end,
			}),
			UI.When({
				id = "TaskShowsWhen",
				condition = showsOpen,
				transition = { enter = "fade", class = "container" },
				thenView = function(): any
					return UI.ZStack({
						id = "TaskShowsGroup",
						canvasGroup = true,
						width = UI.fill(),
						children = { parts.caption(ctx, "TaskShowsBody", ctx.L("task.shows.body")) },
					})
				end,
			}),
		},
	})
end

return task
