--!strict
-- Scenario 'foreign_content' (UI.Foreign, ADR-0034; react-lua-comparison §5 rank 1):
-- the BOUNDED ESCAPE HATCH, shown with instances Facet genuinely cannot draw.
--
-- WHY THESE THREE PANES AND NOT A COLOURED FRAME. A demo of an escape hatch that
-- shows something the framework could have drawn itself demonstrates nothing. Each
-- pane is a capability Facet declines by design:
--
--   RICH TEXT   markup spans inside ONE string. `UI.Text` resolves ONE typography
--               role and ONE colour per label — deliberately, because the solver
--               measures with one font descriptor — so bold + italic + two colours
--               on one line is not expressible in Facet at all.
--   ENGINE LIST a ScrollingFrame with a UIListLayout and AutomaticCanvasSize, whose
--               rows carry AutomaticSize. Facet pins `AutomaticCanvasSize = None`
--               on every ScrollingFrame it creates (the solver owns content
--               geometry), so this is exactly the measure model the framework
--               refuses — running inside a box the framework declared.
--   THE CLIP    a Frame at 2x the box on both axes, offset negatively. It proves
--               the containment promise: "Facet owns the box" is a contract only
--               while nothing adopted can paint outside it.
--
-- ...and a fourth button that is not a pane: adopting a `Part` — the 3-D case
-- arriving at the 2-D seam. The REFUSAL is put on screen verbatim, because a
-- refusal that names its alternative is a shipped feature here (ADR-0029's
-- pattern), not an error nobody reads.
--
-- ENGINE-FREE, like every scenario: the instances arrive as DATA
-- (`built.foreignContent`) and the engine-side sibling `foreign_instances.luau` is
-- the one place that turns a `kind` into an Instance — shared by the scenario
-- runner AND by the shipped showcase host, so the surface a player opens is never
-- less capable than the rig. `ctx.foreign.adopt` is that same seam, live, so the
-- buttons can re-adopt and be refused while the surface is up.

local PANES = "/ForeignContent/Page/Panes"

return {
	title = "UI.Foreign — a box for an instance Facet does not own (ADR-0034)",
	build = function(ctx: any)
		local UI = ctx.Facet.UI
		local core = ctx.core

		local status = core:signal("adopting on present…")
		local refusal = core:signal("(press “Adopt a Part” to see the refusal)")

		local RICH = '<b>Rich</b> <i>text</i> <font color="rgb(120,200,255)">spans</font> '
			.. '<font color="rgb(255,180,120)">in one string</font> — <b>UI.Text cannot.</b>'

		local LIST_ITEMS = {
			"AutomaticSize rows: each one sizes itself from its own text,",
			"and the UIListLayout re-flows around it.",
			"The canvas grows with them (AutomaticCanvasSize = Y).",
			"Facet pins that to None on every ScrollingFrame it makes,",
			"because its solver owns content geometry — which is why the",
			"BOX around this list is declared in px and never inferred.",
			"Scroll me: the engine measured all of this, not the framework.",
		}

		-- forward declarations: the buttons close over these, and the bodies need
		-- `ctx.foreign`, which only exists once the surface is presented
		local readoptAll: () -> string
		local adoptPart: () -> string

		local function pane(id: string, caption: string, child: any)
			return UI.VStack({
				id = id,
				gap = 6,
				width = { type = "fixed", px = 220 },
				children = { child, UI.Text({ id = "Caption", text = caption, textSize = 13 }) },
			})
		end

		local screen = UI.Screen({
			id = "ForeignContent",
			padding = 16,
			children = {
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 12,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = "UI.Foreign", textSize = 24 }),
						UI.Text({
							id = "Blurb",
							text = "Facet reserves and clips the box. You create the instance, you own every "
								.. "property on it, and the framework writes exactly one thing: its Parent.",
							textSize = 14,
						}),
						UI.HStack({
							id = "Panes",
							gap = 12,
							wrap = true,
							children = {
								pane(
									"Rich",
									"RichText: markup spans in one label",
									UI.Foreign({
										id = "Pane",
										width = { type = "fixed", px = 220 },
										height = { type = "fixed", px = 96 },
										surface = "raised",
									})
								),
								pane(
									"Engine",
									"The ENGINE lays this out and measures it",
									UI.Foreign({
										id = "Pane",
										width = { type = "fixed", px = 220 },
										height = { type = "fixed", px = 96 },
										surface = "raised",
									})
								),
								pane(
									"Clip",
									"2x oversize — cropped at the box edge",
									UI.Foreign({
										id = "Pane",
										width = { type = "fixed", px = 220 },
										height = { type = "fixed", px = 96 },
										surface = "raised",
									})
								),
							},
						}),
						UI.Text({ id = "Status", text = status, textSize = 13 }),
						UI.HStack({
							id = "Actions",
							gap = 8,
							wrap = true,
							children = {
								UI.Button({
									id = "Readopt",
									label = "Re-adopt all three",
									onActivate = function()
										readoptAll()
									end,
								}),
								UI.Button({
									id = "AdoptPart",
									label = "Adopt a Part (refused)",
									onActivate = function()
										adoptPart()
									end,
								}),
							},
						}),
						UI.Text({ id = "Refusal", text = refusal, textSize = 12, disclose = true }),
					},
				}),
			},
		})

		local CONTENT: { [string]: any } = {
			[`{PANES}/Rich/Pane`] = { kind = "richText", text = RICH, textSize = 18 },
			[`{PANES}/Engine/Pane`] = { kind = "engineList", items = LIST_ITEMS },
			[`{PANES}/Clip/Pane`] = { kind = "oversize" },
		}

		function readoptAll(): string
			if ctx.foreign == nil then
				status:set("this host offers no live foreign seam")
				return status:get()
			end
			local parts: { string } = {}
			for path, content in CONTENT do
				table.insert(parts, `{string.match(path, "([^/]+)/Pane$") or path}: {ctx.foreign.adopt(path, content)}`)
			end
			table.sort(parts)
			status:set(table.concat(parts, "  |  "))
			return status:get()
		end

		function adoptPart(): string
			if ctx.foreign == nil then
				refusal:set("this host offers no live foreign seam")
				return refusal:get()
			end
			-- the 3-D case at the 2-D seam. The materializer returns the framework's
			-- own sentence, which is the thing worth showing.
			refusal:set(ctx.foreign.adopt(`{PANES}/Rich/Pane`, { kind = "part" }))
			return refusal:get()
		end

		return {
			screen = screen,
			present = {},
			-- the initial adoption, materialized by the runner right after present
			foreignContent = CONTENT,
			steps = {
				readopt = readoptAll,
				adoptPart = adoptPart,
			},
			report = function()
				return { status = status:get(), refusal = refusal:get() }
			end,
		}
	end,
}
