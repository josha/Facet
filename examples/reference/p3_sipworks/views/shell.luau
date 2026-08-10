--!strict
-- The Sipworks shell (spec §5): compact tab row ⇄ regular sidebar, decided by
-- `UI.Composition` from the box the shell actually receives.
--
-- TWO DEVIATIONS FROM THE SPEC'S LETTER, both forced by what a Region IS, and
-- both preserving what §5 is about:
--
--  1. The spec gives the Nav region TWO ranked forms (sidebar, then tab row).
--     A Region's forms are chosen by FAILURE — a region steps down when its
--     arrangement cannot fit — not by width, so in the `column` arrangement the
--     richer sidebar form fits a full-width bottom band perfectly well and
--     would have been chosen there: a phone would have got a vertical sidebar
--     across the bottom of the screen. The nav is therefore ONE form built on
--     `UI.AdaptiveStack`, whose `axis` is a bound prop — the class that exists
--     precisely so a row/column flip is a re-solve and not a remount.
--
--  2. Declaration order is the same in both forms (Menu, Favorites, Blend Book,
--     Steam Stamps) rather than moving the Stamps pocket to the foot in one and
--     the third slot in the other. The framework states the reason: "Focus
--     order is the declaration's own order, and is therefore identical in every
--     arrangement" — so two orders would have been one order and a lie. The
--     pocket still sits at the FOOT of the sidebar, pushed there by a spacer
--     that only exists in the regular arrangement.

local metrics = require("../content/metrics")
local listView = require("./list")
local detailView = require("./detail")
local bookView = require("./book")
local rewardsView = require("./rewards")

local shell = {}

local SECTIONS = { "menu", "favorites", "recipes", "stamps" }
local SECTION_LABEL: { [string]: string } = {
	menu = "nav.menu",
	favorites = "nav.favorites",
	recipes = "nav.book",
	stamps = "nav.stamps",
}

shell.SECTIONS = SECTIONS

-- ---------------------------------------------------------------------------
-- navigation
-- ---------------------------------------------------------------------------

local function navButton(app: any, section: string, opts: { short: boolean, hug: boolean? }): any
	local UI = app.UI
	local core = app.core
	local selected = app.own(core:memo(function(use)
		return use(app.state.section) == section
	end))
	return UI.Button({
		-- NO `compactLabel`, and that is a finding rather than an omission: a
		-- compact form is construction-only (a compact representation is what a
		-- control HAS), so it cannot follow the live locale flip this proof's
		-- loop drives. The short form is a second LOCALIZED string instead.
		id = "Nav-" .. section,
		label = app.text(SECTION_LABEL[section] .. (if opts.short then ".short" else "")),
		selected = selected,
		width = if opts.hug == true then nil else metrics.fill,
		onActivate = function()
			app.commands.selectSection(section)
		end,
	})
end

-- THE FOUR NAV HOMES (adaptive.navPlacement, director ruling 2026-08-09,
-- aligned to the platform tab-bar guidance the reference follows):
--   sidebar          desktop shape — the vertical rail, stamps pocket at the foot
--   topBar           tablet/ten-foot shape — CENTER-ALIGNED, HUGS its tabs
--                    (never full width), search rides the band's trailing edge
--   bottomBar        phone portrait — full-width tabs in the thumb zone
--   bottomBarCompact phone landscape — the SAME bar in its reduced inline form
--                    (short labels, tighter padding)
-- The placement is a CONDITION, not a fit: which home the nav takes is a
-- policy over shape + input facts, so it is decided by `navPlacement` and
-- mounted through `When`, while the CONTENT of a bar still degrades by fit
-- (the bottom bar is a ViewThatFits: full labels, then the short form — the
-- same localization-honest step-down the old region forms carried).

local function sideRail(app: any): any
	local UI = app.UI
	local children: { any } = {}
	for _, section in SECTIONS do
		if section == "stamps" then
			-- the pocket is pushed to the FOOT of the sidebar
			table.insert(children, UI.Spacer({ id = "PocketGap", height = metrics.fill }))
		end
		table.insert(children, navButton(app, section, { short = false }))
	end
	return UI.VStack({
		id = "NavRail",
		gap = "s",
		padding = "s",
		align = "stretch",
		width = metrics.minMax(metrics.navRailMin, metrics.navRailMin, metrics.navRailMax),
		height = metrics.fill,
		children = children,
	})
end

local function tabRow(app: any, id: string, opts: { short: boolean, hug: boolean?, pad: string }): any
	local UI = app.UI
	local children: { any } = {}
	for _, section in SECTIONS do
		table.insert(children, navButton(app, section, { short = opts.short, hug = opts.hug }))
	end
	return UI.HStack({
		id = id,
		gap = if opts.short then "xs" else "s",
		padding = opts.pad,
		-- NO `align` on the natural-width rows: a container's own `align` is
		-- also read by its PARENT as cross-axis alignment (framework finding
		-- 15), so "stretch" here would defeat the centering wrapper and
		-- stretch the cluster back to full width.
		align = if opts.hug == true then nil else "stretch",
		-- CONTENT, not hug, on the measured candidates: `hug` CAPS at the
		-- offer, so a hug row can never tell a ViewThatFits it does not fit —
		-- the ladder silently pinned its first candidate and the tabs
		-- truncated ("a lot of cutoff text", director live report). `content`
		-- is the uncapped natural width, which is what a fit CHOICE needs;
		-- the chosen row is then centered by its wrapper and never stretched.
		width = if opts.hug == true then { type = "content" } else metrics.fill,
		children = children,
	})
end

local function bottomBar(app: any, compactForm: boolean): any
	local UI = app.UI
	if compactForm then
		-- the INLINE form: short labels, tighter band — and CENTERED, HUGGING
		-- its tabs like the top bar (director refinement 2026-08-09: a
		-- landscape phone's reduced bar is a centered cluster, never a
		-- full-width stretch). A ViewThatFits carries the honest step-down:
		-- at the 1.4x locale + the largest text preference the cluster cannot
		-- hug 720px, and the full-width shared band is the fallback (the same
		-- degradation rule every other bar form declares).
		return UI.ViewThatFits({
			id = "TabsCompactFit",
			width = metrics.fill,
			children = {
				UI.VStack({
					id = "TabsCompactCenter",
					align = "center",
					width = metrics.fill,
					children = {
						tabRow(app, "TabsCompact", { short = true, hug = true, pad = "xs" }),
					},
				}),
				tabRow(app, "TabsCompactWide", { short = true, pad = "xs" }),
			},
		})
	end
	-- BOTTOM BARS SPEAK THE SHORT VOCABULARY (director refinement 2026-08-09:
	-- "consider when to use the compact representation — I see a lot of cutoff
	-- text"). Full labels belong to the homes with room (sidebar, top bar); a
	-- thumb-zone tab bar uses the terse localized strings by construction, so
	-- nothing ellipsizes in the normal range at all. The ladder that remains
	-- is the honest extreme-text step-down: a CENTERED natural-width cluster,
	-- then the full-width shared band at the 1.4x locale + largest preference.
	return UI.ViewThatFits({
		id = "TabsFit",
		width = metrics.fill,
		children = {
			UI.VStack({
				id = "TabsShortCenter",
				align = "center",
				width = metrics.fill,
				children = { tabRow(app, "TabsShort", { short = true, hug = true, pad = "s" }) },
			}),
			tabRow(app, "TabsShortWide", { short = true, pad = "s" }),
		},
	})
end

local function topBar(app: any): any
	local UI = app.UI
	-- CENTERED AND HUGGING: the tab cluster is a hug row centered in a
	-- full-width band (never stretched edge to edge), with the search field on
	-- the band's trailing edge — the tablet tab-bar shape the guidance draws
	return UI.ZStack({
		id = "TopBar",
		width = metrics.fill,
		children = {
			UI.VStack({
				id = "TopTabsCenter",
				align = "center",
				width = metrics.fill,
				children = {
					UI.ViewThatFits({
						id = "TopTabsFit",
						children = {
							tabRow(app, "TopTabsFull", { short = false, hug = true, pad = "s" }),
							tabRow(app, "TopTabsShort", { short = true, hug = true, pad = "s" }),
						},
					}),
				},
			}),
			UI.When({
				id = "TopSearchWhen",
				condition = app.searchable,
				thenView = function()
					return UI.VStack({
						id = "TopSearchSlot",
						align = "end",
						width = metrics.fill,
						children = {
							UI.VStack({
								id = "TopSearchBox",
								width = metrics.minMax(160, 200, 260),
								children = { listView.searchBar(app) },
							}),
						},
					})
				end,
			}),
		},
	})
end

-- ---------------------------------------------------------------------------
-- section bodies — one two-pane shape, one bound pane width
-- ---------------------------------------------------------------------------

local function paneWidth(app: any): any
	return app.own(app.core:memo(function(use)
		if not use(app.paneSplit) then
			return metrics.fill
		end
		return metrics.minMax(metrics.listPaneMin, metrics.listPaneMin, metrics.listPaneMax)
	end))
end

-- the regular detail pane; compact never mounts it (the detail is a pushed
-- surface there), and WIDENING with a compact detail up dismisses that surface
-- and lets this pane render the same selection
local function detailPane(app: any, kind: string): any
	local UI = app.UI
	local core = app.core
	local hasSelection = app.own(core:memo(function(use)
		return use(app.state.selectedBlendId) ~= nil
	end))
	local noSelection = app.own(core:memo(function(use)
		return use(app.state.selectedBlendId) == nil
	end))
	return UI.HStack({
		id = "DetailPane",
		gap = "m",
		width = metrics.fill,
		height = metrics.fill,
		children = {
			UI.Divider({ id = "Rule" }),
			UI.ZStack({
				id = "PaneBody",
				width = metrics.fill,
				height = metrics.fill,
				alignH = "center",
				alignV = "center",
				children = {
					UI.When({
						id = "Body",
						condition = hasSelection,
						thenView = function()
							if kind == "recipes" then
								return bookView.recipeView(app, { id = "Recipe", showBack = false })
							end
							return detailView.body(app, { id = "Detail", showBack = false })
						end,
					}),
					UI.When({
						id = "Empty",
						condition = noSelection,
						thenView = function()
							return UI.Text({
								id = "Hint",
								text = app.text("detail.empty"),
								role = "secondary",
								textSize = "body",
								textAlign = "center",
							})
						end,
					}),
				},
			}),
		},
	})
end

local function listSection(app: any, kind: string): any
	local UI = app.UI
	local core = app.core

	local items = app.own(core:memo(function(use)
		return app.visibleBlends(use, kind)
	end))

	-- the search field has ONE home per placement: inline atop the list pane on
	-- the sidebar shape, the top band's trailing slot on the topBar shape, and
	-- the tab-bar ACCESSORY (directly above the dock) on the bottom shapes —
	-- the conditions are mutually exclusive and none of these Whens declares a
	-- transition, so the shared field identity is never mounted twice at once
	local body: { any } = {
		UI.When({
			id = "InlineSearchWhen",
			condition = app.navSidebar,
			thenView = function()
				return listView.searchBar(app)
			end,
		}),
	}

	local listBlueprint = listView.blendList(app, {
		id = "List",
		items = items,
		-- the unlock card scrolls WITH the recipes it is offering
		leading = if kind == "recipes" then bookView.unlockCard(app) else nil,
		onActivate = function(blendId: string)
			app.commands.openBlend(blendId, kind)
		end,
	})

	if kind == "favorites" then
		local empty = app.own(core:memo(function(use)
			local set = use(app.services.favorites.set)
			return next(set) == nil
		end))
		table.insert(
			body,
			UI.ZStack({
				id = "ListArea",
				width = metrics.fill,
				height = metrics.fill,
				alignH = "center",
				alignV = "center",
				children = {
					listBlueprint,
					UI.When({
						id = "EmptyState",
						condition = empty,
						transition = { enter = "fade" },
						thenView = function()
							return UI.ZStack({
								id = "EmptyBox",
								canvasGroup = true,
								width = metrics.fill,
								height = metrics.fill,
								alignH = "center",
								alignV = "center",
								children = {
									UI.VStack({
										id = "Empty",
										gap = "s",
										align = "center",
										padding = "m",
										children = {
											UI.Text({
												id = "Message",
												text = app.text("favorites.empty"),
												role = "secondary",
												textSize = "body",
												textAlign = "center",
											}),
											UI.Button({
												id = "Browse",
												label = app.text("favorites.browse"),
												corners = UI.cornersData("pill"),
												onActivate = function()
													app.commands.selectSection("menu")
												end,
											}),
										},
									}),
								},
							})
						end,
					}),
				},
			})
		)
	else
		table.insert(body, listBlueprint)
	end

	return UI.HStack({
		id = "Panes",
		gap = "m",
		width = metrics.fill,
		height = metrics.fill,
		children = {
			UI.VStack({
				id = "ListPane",
				gap = "s",
				width = paneWidth(app),
				height = metrics.fill,
				children = body,
			}),
			UI.When({
				id = "Side",
				condition = app.paneSplit,
				thenView = function()
					return detailPane(app, kind)
				end,
			}),
		},
	})
end

local function stampsSection(app: any): any
	local UI = app.UI
	return UI.ScrollView({
		id = "StampsPage",
		axis = "y",
		gap = "m",
		padding = "m",
		width = metrics.fill,
		height = metrics.percent(1),
		children = {
			UI.ZStack({
				-- HUGS, never fills: a `fill` height inside a y-scroller measures
				-- against a canvas that is itself derived from the content
				id = "Backdrop",
				width = metrics.fill,
				alignH = "center",
				alignV = "start",
				children = {
					rewardsView.card(app, { id = "RewardsCard", compact = true }),
				},
			}),
		},
	})
end

local function content(app: any): any
	local UI = app.UI
	local core = app.core
	local children: { any } = {}
	for _, section in SECTIONS do
		local this = section
		local visible = app.own(core:memo(function(use)
			return use(app.state.section) == this
		end))
		table.insert(
			children,
			UI.When({
				id = "Section-" .. this,
				condition = visible,
				transition = { enter = "fade" },
				thenView = function()
					return UI.ZStack({
						id = "Body",
						canvasGroup = true,
						width = metrics.fill,
						height = metrics.fill,
						children = {
							if this == "stamps" then stampsSection(app) else listSection(app, this),
						},
					})
				end,
			})
		)
	end
	return UI.VStack({
		id = "Content",
		gap = "s",
		padding = "s",
		width = metrics.fill,
		height = metrics.fill,
		children = children,
	})
end

-- ---------------------------------------------------------------------------
-- the shell itself
-- ---------------------------------------------------------------------------

function shell.build(app: any): any
	local UI = app.UI
	local core = app.core

	-- the placement policy, spelled once (adaptive.navPlacement via conditions)
	local placement = app.cond.navPlacement
	app.navSidebar = app.own(core:memo(function(use)
		return use(placement) == "sidebar"
	end))
	local navTop = app.own(core:memo(function(use)
		return use(placement) == "topBar"
	end))
	local navBottomFull = app.own(core:memo(function(use)
		return use(placement) == "bottomBar"
	end))
	local navBottomCompact = app.own(core:memo(function(use)
		return use(placement) == "bottomBarCompact"
	end))
	local navBottomish = app.own(core:memo(function(use)
		local m = use(placement)
		return m == "bottomBar" or m == "bottomBarCompact"
	end))
	-- the accessory (and the top band's search slot) only makes sense on the
	-- sections that HAVE a searchable list — never over the stamps pocket
	app.searchable = app.own(core:memo(function(use)
		return use(app.state.section) ~= "stamps"
	end))

	return UI.Screen({
		id = "Sipworks",
		padding = 0,
		surface = "base",
		children = {
			UI.VStack({
				id = "Shell",
				gap = "s",
				width = metrics.fill,
				height = metrics.fill,
				children = {
					UI.When({
						id = "TopBarWhen",
						condition = navTop,
						thenView = function()
							return topBar(app)
						end,
					}),
					UI.HStack({
						id = "Middle",
						gap = "m",
						width = metrics.fill,
						height = metrics.fill,
						children = {
							UI.When({
								id = "SideRailWhen",
								condition = app.navSidebar,
								thenView = function()
									return sideRail(app)
								end,
							}),
							content(app),
						},
					}),
					UI.When({
						id = "DockWhen",
						condition = navBottomish,
						thenView = function()
							return UI.VStack({
								id = "Dock",
								gap = "xs",
								width = metrics.fill,
								children = {
									-- THE TAB-BAR ACCESSORY: the search field rides
									-- directly above the bottom tab bar (the guidance's
									-- accessory slot), for the sections that search
									UI.When({
										id = "AccessoryWhen",
										condition = app.searchable,
										thenView = function()
											return UI.VStack({
												id = "Accessory",
												width = metrics.fill,
												padding = "xs",
												children = { listView.searchBar(app) },
											})
										end,
									}),
									UI.When({
										id = "BottomFullWhen",
										condition = navBottomFull,
										thenView = function()
											return bottomBar(app, false)
										end,
									}),
									UI.When({
										id = "BottomCompactWhen",
										condition = navBottomCompact,
										thenView = function()
											return bottomBar(app, true)
										end,
									}),
								},
							})
						end,
					}),
				},
			}),
		},
	})
end

return shell
