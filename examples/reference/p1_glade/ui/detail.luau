--!strict
-- Glade (RA-P1) — S2, the glade detail (spec §8).
--
-- ONE body, TWO hosts. On regular and wide the shell's detail lane shows it
-- beside the overview; on compact it is a full modal. Both call `detail.body`
-- with the same arguments, so there is exactly one detail screen in this proof
-- and a fix to it cannot land on one form and miss the other.
--
-- The dew row is the loop's instant mutation: Activate stamps the refill, the
-- ring animates back to full and resumes draining, the feedback bus hears
-- `activate` then `commit`, and a toast says which glade brightened. No
-- confirmation — the state itself is visible in place and the act is free.

local seedData = require("../content/seed")
local sceneLib = require("./scene")
local parts = require("./parts")

local detail = {}

local METRICS = seedData.METRICS

local function heroHeight(ctx: any, scope: any): any
	return scope:own(ctx.core:memo(function(use)
		local class = use(ctx.conditions.sizeClass)
		local px = METRICS.sceneMedium
		if class == "compact" then
			px = METRICS.sceneShort
		elseif class == "wide" then
			px = METRICS.sceneTall
		end
		return { type = "fixed", px = px }
	end))
end

-- ---- a supply row ------------------------------------------------------------
-- Full-width Button (children content), never disabled. The state a player has
-- to read — how much is left — is the ring's own emptiness plus a caption; the
-- "Low"/"Empty" chip is the second, formal signal (§6). No hue changes.
local function supplyRow(ctx: any, gladeId: string, kind: string, scope: any): any
	local UI = ctx.UI
	local core = ctx.core
	local state = ctx.supply.state(gladeId, kind)
	local remaining = ctx.supply.remaining(gladeId, kind)

	local title = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		if kind == "dew" then
			return ctx.Lnow("supply.dew")
		end
		return ctx.Lnow("nectar." .. use(ctx.supply.nectarOf(gladeId)))
	end))
	local caption = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		local left = use(remaining)
		if left <= 0 then
			return ctx.Lnow("supply.captionEmpty")
		end
		return ctx.Lnow("supply.caption", { remaining = ctx.fmt.duration(left) })
	end))
	-- empty strengthens the caption's role; it never recolours the ring
	local captionRole = scope:own(core:memo(function(use)
		return if use(state) == "empty" then "content" else "secondary"
	end))
	local chipped = scope:own(core:memo(function(use)
		return use(state) ~= "full"
	end))
	local chipText = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow(if use(state) == "empty" then "supply.empty" else "supply.low")
	end))
	local actionTitle = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow(if kind == "dew" then "detail.refillDew" else "detail.chooseNectar")
	end))

	-- THE TRAILING AFFORDANCE. The spec asks for `newLabel` in its icon-only
	-- presentation with the semantic title preserved; `newLabel.title` accepts
	-- only a literal string (it is validated with `type(spec.title) ~= "string"`),
	-- so a locale-reactive title cannot use the control without rebuilding the row
	-- on every locale change. Recorded as a framework finding; the affordance is a
	-- bound `UI.Text` here, which keeps the title reactive and localized.
	-- minMax-CAPPED, because lineLimit does not cap the width a text asks for
	-- (the same class as the name and caption in this row): under the 1.4x
	-- locale the verb's natural ask set the row minimum 21px past the lane.
	-- The floor keeps the verb legible; past the cap it truncates through its
	-- declared disclose.
	local affordance = UI.Text({
		id = "Affordance",
		text = actionTitle,
		textSize = "label",
		role = "secondary",
		width = { type = "minMax", min = METRICS.affordanceMin, max = METRICS.affordanceMax },
		lineLimit = 1,
		disclose = true,
	})

	return UI.Button({
		id = "SupplyRow_" .. kind,
		label = actionTitle,
		width = UI.fill(),
		onActivate = function()
			if kind == "dew" then
				ctx.nav.refillDew(gladeId)
			else
				ctx.nav.openPicker(gladeId)
			end
		end,
		children = {
			UI.HStack({
				id = "Row",
				gap = "m",
				align = "center",
				width = UI.fill(),
				children = {
					sceneLib.ring(ctx, {
						id = "Ring",
						glade = gladeId,
						kind = kind,
						size = METRICS.ringLarge,
						scope = scope,
					}),
					UI.VStack({
						id = "Copy",
						gap = "xs",
						width = UI.fill(),
						children = {
							UI.HStack({
								id = "TitleRow",
								gap = "s",
								align = "center",
								width = UI.fill(),
								children = {
									UI.Text({
										id = "Name",
										text = title,
										textSize = "label",
										-- FILL, because lineLimit caps LINES, never the width a
										-- text asks for (the recorded p2-caption class): under
										-- the 1.4x locale this name's natural width pushed the
										-- row past its box; a fill share truncates through the
										-- declared disclose instead
										width = UI.fill(),
										lineLimit = 1,
										disclose = true,
									}),
									UI.When({
										id = "StateChip",
										condition = chipped,
										transition = { enter = "fade", class = "container" },
										thenView = function(): any
											return UI.ZStack({
												id = "ChipGroup",
												canvasGroup = true,
												children = { parts.chip(ctx, "Chip", chipText) },
											})
										end,
									}),
								},
							}),
							-- the caption wraps to two lines before the row grows:
							-- rows are content-sized, never fixed px (spec §13) — and
							-- FILL-width, or its natural single-line ask under the
							-- 1.4x locale sets the column's minimum instead of
							-- wrapping (the same lineLimit-is-not-a-width-cap class
							-- as the name above)
							UI.Text({
								id = "Caption",
								text = caption,
								textSize = "caption",
								role = captionRole,
								width = UI.fill(),
								lineLimit = 2,
							}),
						},
					}),
					--[[ NO `Spacer` HERE, and its removal is a defect fix rather than a
						tidy-up. `Copy` beside it is already `fill`, so a flexible spacer
						SPLIT the row's free space with the copy column instead of pushing
						anything: in the 248px detail lane the copy was starved to 29px
						while the spacer took 40, and the "Low"/"Empty" chip (23px + an
						8px gap) then painted 2px outside its own TitleRow — 8px under the
						1.4x locale. A fill sibling IS the push. Found the moment a glade
						whose dew needs refilling became the one the sweep selects; the
						same row on Fernhollow, Stillpond and Bramble Rest had carried it
						since the row was written. ]]
					affordance,
				},
			}),
		},
	})
end

-- ---- the recent-visitors list ------------------------------------------------
local function visitors(ctx: any, gladeId: string, scope: any): any
	local UI = ctx.UI
	local core = ctx.core
	local rows = ctx.visits.recent(gladeId)
	local empty = scope:own(core:memo(function(use)
		return #use(rows) == 0
	end))
	return UI.VStack({
		id = "Visitors",
		gap = "s",
		width = UI.fill(),
		children = {
			parts.heading(ctx, "VisitorsTitle", ctx.L("detail.visitors")),
			UI.When({
				id = "NoVisitors",
				condition = empty,
				thenView = function(): any
					return parts.body(ctx, "None", ctx.L("detail.noVisitors"))
				end,
			}),
			UI.ForEach({
				id = "VisitorRows",
				items = rows,
				key = function(visit: any): string
					return visit.id
				end,
				row = function(visit: any, rowScope: any): any
					local name = rowScope:own(core:memo(function(use)
						local _ = use(ctx.state.locale)
						return ctx.Lnow("wisp." .. visit.wisp)
					end))
					local when = rowScope:own(core:memo(function(use)
						local _ = use(ctx.state.locale)
						return ctx.fmt.relative(use(ctx.now) - visit.finish)
					end))
					local activate = rowScope:own(core:memo(function(use)
						local _ = use(ctx.state.locale)
						return ctx.Lnow("wisp.activate", { wisp = ctx.Lnow("wisp." .. visit.wisp) })
					end))
					return UI.Button({
						id = "Visitor_" .. visit.id,
						label = activate,
						width = UI.fill(),
						align = "start",
						onActivate = function()
							ctx.nav.openWisp(visit.wisp)
						end,
						children = {
							UI.HStack({
								id = "Row",
								gap = "m",
								align = "center",
								width = UI.fill(),
								children = {
									sceneLib.portrait(ctx, "Portrait", visit.wisp, METRICS.portrait),
									UI.Text({
										id = "Name",
										text = name,
										textSize = "label",
										-- fill for the same reason as the supply row's name:
										-- lineLimit does not cap the width a text asks for
										width = UI.fill(),
										lineLimit = 1,
										disclose = true,
									}),
									parts.caption(ctx, "When", when),
								},
							}),
						},
					})
				end,
			}),
		},
	})
end

-- ---- the body ----------------------------------------------------------------

export type BodySpec = {
	id: string,
	glade: string,
	scope: any,
	compact: boolean,
}

function detail.body(ctx: any, spec: BodySpec): any
	local UI = ctx.UI
	local core = ctx.core
	local gladeId = spec.glade
	local name = spec.scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("glade." .. gladeId)
	end))

	-- the shared back+title+trailing bar (registry item 13; W3-D):
	-- `onBack` is nil outside compact, which is this site's OWN "nothing to go
	-- back to" decision (the detail pane is beside the overview there, not a
	-- pushed surface) — `Facet.navBar` never invents a verb it was not given
	local titleBar = ctx.Facet.navBar({
		onBack = if spec.compact
			then function()
				ctx.nav.closeDetail()
			end
			else nil,
		backLabel = ctx.L("detail.back"),
		title = name,
		trailing = {
			UI.Button({
				id = "Fav",
				label = ctx.L("overview.favorite"),
				compactLabel = "★",
				selected = ctx.state.favourites[gladeId],
				width = { type = "fixed", px = "targetSizes.minimum" },
				height = { type = "fixed", px = "targetSizes.minimum" },
				onActivate = function()
					ctx.nav.toggleFavourite(gladeId)
				end,
			}),
		},
	})

	return UI.ScrollView({
		id = spec.id,
		axis = "y",
		gap = "l",
		padding = "l",
		width = UI.fill(),
		height = UI.fill(),
		-- COMPACT ONLY: this body is pushed as its OWN full-viewport root
		-- (`nav.openGlade`'s `scrim = "none"` push) over the still-mounted
		-- overview root, and NOTHING dims the overview behind it — the same
		-- convention `p3_sipworks`'s compact detail push already uses
		-- (`UI.Screen{surface="base",...}` around its own body). Without an
		-- opaque backdrop here, every gap this ScrollView does not itself paint
		-- (padding, the space around the nav bar) is fully transparent, so the
		-- overview root paints straight through it — director device round
		-- 2026-08-23: "Mossholm" (this body's own NavBar title) interleaved with
		-- "Keeper's Charm" (the overview's promo banner, still fully bright
		-- underneath, never dimmed). The regular/wide lane (`compact = false`)
		-- stays transparent on purpose: it sits beside the overview in normal
		-- flow, not stacked over it, so there is nothing behind it to bleed
		-- through, and painting it would be an unreviewed style change to a
		-- five-view-matrix-clean surface no symptom named.
		surface = if spec.compact then "base" else nil,
		children = {
			titleBar,
			sceneLib.glade(ctx, {
				id = "Hero",
				glade = gladeId,
				form = "hero",
				scope = spec.scope,
				height = heroHeight(ctx, spec.scope),
			}),
			UI.VStack({
				id = "Supplies",
				gap = "s",
				width = UI.fill(),
				children = {
					supplyRow(ctx, gladeId, "nectar", spec.scope),
					supplyRow(ctx, gladeId, "dew", spec.scope),
				},
			}),
			visitors(ctx, gladeId, spec.scope),
		},
	})
end

-- The shell's detail lane: a keyed region over the selection, so switching
-- glades replaces the body cleanly and an empty selection leaves the lane with
-- nothing paintable — which is what makes the composition collapse it (rule 9)
-- rather than reserving a dead band.
function detail.lane(ctx: any): any
	local UI = ctx.UI
	local core = ctx.core
	local items = ctx.scope:own(core:memo(function(use)
		local selected = use(ctx.state.selectedGlade)
		if selected == nil or use(ctx.conditions.isCompact) then
			return {}
		end
		return { { id = selected } }
	end))
	-- the region's FORM has to be something that measures, so the keyed region
	-- lives inside a stack: empty selection ⇒ the stack measures nothing ⇒ the
	-- region is not mounted ⇒ the composition collapses the whole lane (rule 9).
	local rows = UI.ForEach({
		id = "DetailLane",
		items = items,
		key = function(item: any): string
			return item.id
		end,
		transition = { enter = "fade", class = "container" },
		row = function(item: any, rowScope: any): any
			return UI.ZStack({
				id = "Pane",
				canvasGroup = true,
				width = { type = "fixed", px = METRICS.detailPaneMin },
				height = UI.fill(),
				children = {
					detail.body(ctx, { id = "Detail", glade = item.id, scope = rowScope, compact = false }),
				},
			})
		end,
	})
	return UI.VStack({ id = "DetailForm", height = UI.fill(), children = { rows } })
end

return detail
