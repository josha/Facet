--!strict
-- THE SHELL — adaptive split navigation (spec §4).
--
-- ONE TREE. A `Composition` with a nav lane and a detail lane resolves to two
-- lanes where both clear their minimums and to a column where they do not, and
-- the column form is what "the sidebar IS the root, picking a section swaps the
-- lane" means: in a column the two regions are the two levels, and each is
-- EMPTY (and therefore absent, and its lane collapsed) while the other is the
-- one being shown. There is no compact layout and no per-device branch.
--
-- The arrangement is `leadFirst` (framework-gaps-phase2 item 12), the built-in
-- mirror of `twoLane`: `twoLane`'s lane order is `{ main } { lead, trail }`,
-- so a sidebar declared `lead` would resolve to the RIGHT of the detail it
-- navigates. `leadFirst` puts `lead` in the solo lane instead — this file used
-- to hand-author that shape under a CUSTOM arrangement that reused the
-- `"twoLane"` name for a different set of lanes, which is exactly the
-- shadowing the gap names.
local data = require("../content/data")

local shell = {}

function shell.new(app: any): any
	local UI = app.UI
	local core = app.core
	local S = app.S
	local state = app.state

	local self: any = {}
	local memos: { any } = {}

	local function own(memo: any): any
		table.insert(memos, memo)
		return memo
	end

	-- ---- what is showing -----------------------------------------------------

	local sectionMemos: { [string]: any } = {}
	local function isSection(id: string): any
		local existing = sectionMemos[id]
		if existing == nil then
			existing = core:memo(function(use)
				return use(state.section) == id
			end)
			sectionMemos[id] = existing
		end
		return existing
	end

	local isPlaza = own(core:memo(function(use)
		return string.match(use(state.section), "^plaza:") ~= nil
	end))
	local brewOpen = own(core:memo(function(use)
		return use(state.openBrew) ~= 0
	end))
	local brewClosed = own(core:memo(function(use)
		return use(state.openBrew) == 0
	end))
	local navVisible = own(core:memo(function(use)
		return not use(state.isCompact) or not use(state.compactOpen)
	end))
	local detailVisible = own(core:memo(function(use)
		return not use(state.isCompact) or use(state.compactOpen)
	end))
	local headerVisible = own(core:memo(function(use)
		return use(state.isCompact) and use(state.compactOpen)
	end))
	local headerTitle = own(core:memo(function(use)
		local section = use(state.section)
		if use(state.openBrew) ~= 0 then
			return S.t("detail.title", { id = use(state.openBrew) })
		end
		local plazaId = string.match(section, "^plaza:(.+)$")
		if plazaId ~= nil then
			local plaza = data.plazaById(plazaId)
			return if plaza == nil then S.t("nav.groupPlazas") else plaza.name
		end
		return S.t("nav." .. section)
	end))

	-- ---- the sidebar ---------------------------------------------------------

	local ROWS = {
		{ id = "cart", key = "nav.cart", short = "Cart" },
		{ id = "brews", key = "nav.brews", short = "Brews" },
		{ id = "chatter", key = "nav.chatter", short = "Chatter" },
		{ id = "ledger", key = "nav.ledger", short = "Ledger" },
	}
	local POTION_ROWS = {
		{ id = "potions", key = "nav.potions", short = "Potions" },
		{ id = "workbench", key = "nav.workbench", short = "Bench" },
		{ id = "topfive", key = "nav.topfive", short = "Top" },
	}

	local function navButton(entry: any, rail: boolean): any
		local spec: any = {
			id = "Row_" .. entry.id,
			label = S.t(entry.key),
			compactLabel = { text = entry.short },
			selected = isSection(entry.id),
			onActivate = function()
				app.actions.selectSection(entry.id)
			end,
		}
		if rail then
			-- pinned on BOTH axes: the compact form is what a rail row can show,
			-- and the solver still runs the ladder for a node that declared one
			spec.width = { type = "fixed", px = "targetSizes.minimum" }
			spec.height = { type = "fixed", px = "targetSizes.minimum" }
		else
			spec.width = UI.fill()
			spec.align = "start"
		end
		return UI.Button(spec)
	end

	local function plazaButton(plaza: any, rail: boolean): any
		local id = "plaza:" .. plaza.id
		local spec: any = {
			id = "Plaza_" .. plaza.id,
			label = plaza.name,
			compactLabel = { text = string.sub(plaza.name, 1, 4) },
			selected = isSection(id),
			onActivate = function()
				app.actions.selectSection(id)
			end,
		}
		if rail then
			spec.width = { type = "fixed", px = "targetSizes.minimum" }
			spec.height = { type = "fixed", px = "targetSizes.minimum" }
		else
			spec.width = UI.fill()
			spec.align = "start"
		end
		return UI.Button(spec)
	end

	local guildLabel = own(core:memo(function(use)
		local identity = app.services.identity
		if use(identity.signedIn) then
			return S.t("guild.signedIn", { name = use(identity.guildName) })
		end
		return S.t("guild.title")
	end))

	local function sidebarChildren(rail: boolean): { any }
		local children: { any } = {}
		for _, entry in ROWS do
			table.insert(children, navButton(entry, rail))
		end
		table.insert(children, UI.Divider({ id = "Rule1" }))
		if not rail then
			table.insert(
				children,
				UI.Text({
					id = "PotionsCaption",
					text = S.t("nav.groupPotions"),
					textSize = "caption",
					role = "secondary",
				})
			)
		end
		for _, entry in POTION_ROWS do
			table.insert(children, navButton(entry, rail))
		end
		table.insert(children, UI.Divider({ id = "Rule2" }))
		if not rail then
			table.insert(
				children,
				UI.Text({
					id = "PlazasCaption",
					text = S.t("nav.groupPlazas"),
					textSize = "caption",
					role = "secondary",
				})
			)
		end
		for _, plaza in data.plazas :: any do
			table.insert(children, plazaButton(plaza, rail))
		end
		table.insert(children, UI.Spacer({ id = "Gap", height = UI.fill() }))
		table.insert(
			children,
			UI.Button({
				id = "GuildCard",
				label = guildLabel,
				compactLabel = { text = "Guild" },
				width = if rail then { type = "fixed", px = "targetSizes.minimum" } else UI.fill(),
				height = if rail then { type = "fixed", px = "targetSizes.minimum" } else nil,
				onActivate = function()
					app.actions.openGuildCard()
				end,
			})
		)
		return children
	end

	local sidebarFull = UI.ScrollView({
		id = "List",
		axis = "y",
		gap = "xs",
		padding = "s",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			UI.VStack({
				id = "Rows",
				gap = "xs",
				width = UI.fill(),
				children = sidebarChildren(false),
			}),
		},
	})

	local sidebarRail = UI.ScrollView({
		id = "Icons",
		axis = "y",
		gap = "xs",
		padding = "xs",
		height = UI.fill(),
		children = {
			UI.VStack({
				id = "Rows",
				gap = "xs",
				align = "center",
				children = sidebarChildren(true),
			}),
		},
	})

	-- ---- the detail host -----------------------------------------------------

	local function section(id: string, condition: any, body: () -> any): any
		return UI.When({
			id = id .. "When",
			condition = condition,
			thenView = function()
				return UI.ZStack({
					id = id .. "Section",
					canvasGroup = true,
					-- A SECTION PLATE CLIPS, and says so. A `canvasGroup` clips its
					-- subtree by engine rule anyway, and declaring it here is what
					-- lets the solver stop reporting a page scroller's canvas as a
					-- child painting outside its box.
					overflow = "clip",
					width = UI.fill(),
					height = UI.fill(),
					children = { body() },
				})
			end,
			-- the section swap: a fade over a canvasGroup plate, instant under
			-- reduced motion with the same events
			transition = { enter = "fade", class = "container" },
		})
	end

	local sections = UI.ZStack({
		id = "Sections",
		overflow = "clip",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			section("Cart", isSection("cart"), function()
				return app.screens.dashboard.view()
			end),
			section("Brews", isSection("brews"), function()
				return UI.ZStack({
					id = "BrewsStack",
					overflow = "clip",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.When({
							id = "ListWhen",
							condition = brewClosed,
							thenView = function()
								return app.screens.brews.view()
							end,
						}),
						UI.When({
							id = "DetailWhen",
							condition = brewOpen,
							thenView = function()
								return app.screens.brewDetail.view()
							end,
						}),
					},
				})
			end),
			section("Chatter", isSection("chatter"), function()
				return app.screens.chatter.view()
			end),
			section("Ledger", isSection("ledger"), function()
				return app.screens.ledger.view()
			end),
			section("Potions", isSection("potions"), function()
				return app.screens.gallery.view()
			end),
			section("Workbench", isSection("workbench"), function()
				return app.screens.workbench.view()
			end),
			section("TopFive", isSection("topfive"), function()
				return app.screens.topfive.view()
			end),
			section("Plaza", isPlaza, function()
				return app.screens.plaza.view()
			end),
		},
	})

	local detailHost = UI.VStack({
		id = "Host",
		gap = "xs",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			UI.When({
				id = "HeaderWhen",
				condition = headerVisible,
				thenView = function()
					-- registry item 13 (W3-D): was a hand-built HStack; the
					-- shared bar takes the same Back verb and title
					return app.Facet.navBar({
						id = "Header",
						padding = "s",
						onBack = function()
							app.actions.back()
						end,
						backLabel = S.t("nav.back"),
						title = headerTitle,
					})
				end,
			}),
			sections,
		},
	})

	-- ---- the screen ----------------------------------------------------------

	local screen = UI.Screen({
		id = "Cartwheel",
		surface = "base",
		children = {
			UI.Composition({
				id = "Shell",
				arrangements = { "leadFirst", "column" },
				laneGap = "s",
				groupGap = "s",
				width = UI.fill(),
				height = UI.fill(),
				groups = {
					{ id = "nav", lane = "lead", sizing = "hug", minWidth = "app.cartwheel.sidebarMin" },
					{ id = "detail", lane = "main", sizing = "fill", minWidth = "app.cartwheel.detailMin" },
				},
				children = {
					UI.Region({
						id = "Sidebar",
						group = "nav",
						rank = 2,
						-- the icon rail carries every destination the full list does — a poorer
						-- LAYOUT of the same content, which is exactly what "none" states
						recover = "none",
						floor = { targets = 3 },
						children = {
							-- RICHEST FIRST: the full list, then the icon rail. Each
							-- form is a bare container holding a `When`, so when the
							-- compact stack has pushed a section the region measures
							-- NOTHING — and an empty region is absent, its lane
							-- collapses (composition rule 9), and the detail takes the
							-- whole width. That is the compact stack, with no second
							-- layout anywhere.
							UI.VStack({
								id = "Full",
								height = UI.fill(),
								children = {
									UI.When({
										id = "Body",
										condition = navVisible,
										thenView = function()
											return sidebarFull
										end,
									}),
								},
							}),
							UI.VStack({
								id = "Rail",
								height = UI.fill(),
								children = {
									UI.When({
										id = "Body",
										condition = navVisible,
										thenView = function()
											return sidebarRail
										end,
									}),
								},
							}),
						},
					}),
					UI.Region({
						id = "Detail",
						group = "detail",
						rank = 1,
						sizing = "fill",
						mayScroll = true,
						floor = { lines = 4 },
						children = {
							UI.VStack({
								id = "Lane",
								height = UI.fill(),
								children = {
									UI.When({
										id = "Body",
										condition = detailVisible,
										thenView = function()
											return detailHost
										end,
									}),
								},
							}),
						},
					}),
				},
			}),
		},
	})

	-- CANCEL, one verb, one owner (spec §4/§17): the screen's contribution pops
	-- exactly one level, and the Back button in the compact header calls the
	-- same function — pointer and Cancel can never disagree.
	self.screen = app.Facet.contribution.attach(screen, {
		handleCancel = function(): boolean
			return app.actions.back()
		end,
	})

	function self.dump(): any
		return {
			section = state.section:get(),
			openBrew = state.openBrew:get(),
			openPotion = state.openPotion:get(),
			compact = state.isCompact:get(),
			compactOpen = state.compactOpen:get(),
			navVisible = navVisible:get(),
			detailVisible = detailVisible:get(),
			header = headerVisible:get(),
		}
	end

	function self.dispose()
		for _, memo in memos do
			memo:dispose()
		end
		for _, memo in sectionMemos do
			memo:dispose()
		end
	end

	return self
end

return shell
